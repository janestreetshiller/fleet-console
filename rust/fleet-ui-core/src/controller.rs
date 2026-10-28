//! The controller connection both clients use.
//!
//! Two background threads, each opening a fresh connection per request: a
//! poller that reads `snapshot` on a fixed interval, and an action worker that
//! runs operator requests one at a time from a bounded queue. Every request
//! carries a deadline and a response byte limit through
//! `fleet_proto::Client::send_bounded`, so a stalled or oversized controller
//! reply ends as an error instead of a frozen client or unbounded memory.
//!
//! The render thread only reads shared state behind a mutex and a generation
//! counter. Nothing here signals a process: every action is a controller
//! request with the same semantics as the matching `fleetctl` command, and the
//! controller keeps enforcing owner, lease and start-identity checks.
//!
//! Polling, not `subscribe`: a snapshot every two seconds costs one local
//! socket round trip and one JSON decode, which the idle measurements in
//! docs/CROSS-PLATFORM.md show is within budget. Subscriptions are added to
//! `fleet-proto` only if that measurement stops holding.

use crate::model::{self, LogChunk, ServiceEvent, Snapshot};
use crate::observe::{Feed, Phase};
use fleet_proto::{Client, ClientError, RpcOp, RpcRequest, RpcResponse};
use std::collections::VecDeque;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, SyncSender, TrySendError};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant, SystemTime};

pub type Wake = Arc<dyn Fn() + Send + Sync>;

const MIN_POLL: Duration = Duration::from_secs(1);
const MAX_POLL: Duration = Duration::from_secs(60);
const ACTION_QUEUE: usize = 16;
const OUTCOME_HISTORY: usize = 64;

#[derive(Debug, Clone)]
pub struct ControllerConfig {
    pub socket: PathBuf,
    /// Clamped to 1 to 60 seconds.
    pub poll_interval: Duration,
    /// Deadline for `snapshot`, `logs`, `events` and `reply`.
    pub request_timeout: Duration,
    /// Deadline for `stop` and `restart`, which wait out the controller's
    /// grace period before answering.
    pub lifecycle_timeout: Duration,
    pub max_snapshot_bytes: usize,
    pub max_log_bytes: i64,
    /// Refuse every mutating action in the client. Logs and events still work.
    pub read_only: bool,
}

impl Default for ControllerConfig {
    fn default() -> Self {
        Self {
            socket: fleet_proto::default_socket_path(),
            poll_interval: Duration::from_secs(2),
            request_timeout: Duration::from_secs(5),
            lifecycle_timeout: Duration::from_secs(30),
            max_snapshot_bytes: 16 * 1024 * 1024,
            max_log_bytes: 256 * 1024,
            read_only: false,
        }
    }
}

impl ControllerConfig {
    pub fn poll_interval(&self) -> Duration {
        self.poll_interval.clamp(MIN_POLL, MAX_POLL)
    }

    /// Three missed polls plus one request deadline. Past this, a value that
    /// was live is shown as stale even though no error was reported.
    pub fn stale_after(&self) -> Duration {
        self.poll_interval() * 3 + self.request_timeout
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LogStream {
    Out,
    Err,
}

impl LogStream {
    fn wire(self) -> &'static str {
        match self {
            Self::Out => "out",
            Self::Err => "err",
        }
    }
}

/// An operator request. Each maps to exactly one controller operation.
#[derive(Debug, Clone, PartialEq)]
pub enum Action {
    Restart {
        service_id: String,
    },
    Stop {
        service_id: String,
    },
    Pause {
        service_id: String,
    },
    Resume {
        service_id: String,
    },
    Renew {
        service_id: String,
        ttl_sec: f64,
    },
    /// Answer an agent's question. Approve and deny are replies whose text the
    /// agent reads; the controller records it once and never rewrites it.
    Reply {
        message_id: i64,
        body: String,
    },
    Logs {
        service_id: String,
        stream: LogStream,
    },
    Events {
        service_id: Option<String>,
        limit: i64,
    },
}

impl Action {
    pub fn is_mutating(&self) -> bool {
        !matches!(self, Self::Logs { .. } | Self::Events { .. })
    }

    /// Stop ends work and restart interrupts it; pause holds resources while
    /// doing nothing. Each is confirmed before it is sent.
    pub fn needs_confirmation(&self) -> bool {
        matches!(
            self,
            Self::Stop { .. } | Self::Restart { .. } | Self::Pause { .. }
        )
    }

    pub fn label(&self) -> String {
        match self {
            Self::Restart { .. } => "restart".into(),
            Self::Stop { .. } => "stop".into(),
            Self::Pause { .. } => "pause".into(),
            Self::Resume { .. } => "resume".into(),
            Self::Renew { ttl_sec, .. } => {
                format!("renew lease {}", crate::format::duration(*ttl_sec))
            }
            Self::Reply { .. } => "reply".into(),
            Self::Logs { stream, .. } => format!("read std{} log", stream.wire()),
            Self::Events { .. } => "read events".into(),
        }
    }

    fn request(&self, config: &ControllerConfig) -> RpcRequest {
        let reason = Some("requested from fleet client".to_string());
        match self {
            Self::Restart { service_id } => RpcRequest {
                service_id: Some(service_id.clone()),
                reason,
                ..RpcRequest::new(RpcOp::Restart)
            },
            Self::Stop { service_id } => RpcRequest {
                service_id: Some(service_id.clone()),
                reason,
                ..RpcRequest::new(RpcOp::Stop)
            },
            Self::Pause { service_id } => RpcRequest {
                service_id: Some(service_id.clone()),
                reason,
                ..RpcRequest::new(RpcOp::Pause)
            },
            Self::Resume { service_id } => RpcRequest {
                service_id: Some(service_id.clone()),
                reason,
                ..RpcRequest::new(RpcOp::Resume)
            },
            Self::Renew {
                service_id,
                ttl_sec,
            } => RpcRequest {
                service_id: Some(service_id.clone()),
                ttl_sec: Some(*ttl_sec),
                ..RpcRequest::new(RpcOp::Renew)
            },
            Self::Reply { message_id, body } => RpcRequest {
                message_id: Some(*message_id),
                body: Some(body.clone()),
                ..RpcRequest::new(RpcOp::Reply)
            },
            Self::Logs { service_id, stream } => RpcRequest {
                service_id: Some(service_id.clone()),
                stream: Some(stream.wire().to_string()),
                max_bytes: Some(config.max_log_bytes),
                ..RpcRequest::new(RpcOp::Logs)
            },
            Self::Events { service_id, limit } => RpcRequest {
                service_id: service_id.clone(),
                limit: Some((*limit).clamp(1, 500)),
                ..RpcRequest::new(RpcOp::Events)
            },
        }
    }

    fn timeout(&self, config: &ControllerConfig) -> Duration {
        match self {
            Self::Restart { .. } | Self::Stop { .. } => config.lifecycle_timeout,
            _ => config.request_timeout,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum ActionPayload {
    Done,
    Logs(LogChunk),
    Events(Vec<ServiceEvent>),
}

#[derive(Debug, Clone)]
pub struct ActionOutcome {
    pub id: u64,
    pub action: Action,
    pub result: Result<ActionPayload, String>,
    pub finished_at: SystemTime,
}

struct Shared {
    feed: Mutex<Feed<Snapshot>>,
    outcomes: Mutex<VecDeque<ActionOutcome>>,
    pending: Mutex<Vec<(u64, Action)>>,
    generation: AtomicU64,
    wake: Wake,
}

impl Shared {
    fn changed(&self) {
        self.generation.fetch_add(1, Ordering::Release);
        (self.wake)();
    }
}

enum Command {
    Act(u64, Action),
    Shutdown,
}

enum PollCommand {
    Refresh,
    Shutdown,
}

pub struct Controller {
    config: ControllerConfig,
    shared: Arc<Shared>,
    actions: SyncSender<Command>,
    polls: SyncSender<PollCommand>,
    next_id: AtomicU64,
    threads: Vec<JoinHandle<()>>,
}

impl Controller {
    pub fn spawn(config: ControllerConfig, wake: Wake) -> Self {
        let shared = Arc::new(Shared {
            feed: Mutex::new(Feed::default()),
            outcomes: Mutex::new(VecDeque::with_capacity(OUTCOME_HISTORY)),
            pending: Mutex::new(Vec::new()),
            generation: AtomicU64::new(0),
            wake,
        });
        let (polls, poll_rx) = mpsc::sync_channel(4);
        let (actions, action_rx) = mpsc::sync_channel(ACTION_QUEUE);

        let poller = {
            let shared = shared.clone();
            let config = config.clone();
            std::thread::Builder::new()
                .name("fleet-controller-poll".into())
                .spawn(move || poll_loop(&config, &shared, poll_rx))
                .expect("spawn controller poll thread")
        };
        let worker = {
            let shared = shared.clone();
            let config = config.clone();
            let refresh = polls.clone();
            std::thread::Builder::new()
                .name("fleet-controller-action".into())
                .spawn(move || action_loop(&config, &shared, action_rx, refresh))
                .expect("spawn controller action thread")
        };
        Self {
            config,
            shared,
            actions,
            polls,
            next_id: AtomicU64::new(1),
            threads: vec![poller, worker],
        }
    }

    pub fn config(&self) -> &ControllerConfig {
        &self.config
    }

    /// A copy of the feed. The snapshot itself is shared, not cloned.
    pub fn feed(&self) -> Feed<Snapshot> {
        self.shared
            .feed
            .lock()
            .map(|f| f.clone())
            .unwrap_or_default()
    }

    pub fn phase(&self, now: SystemTime) -> Phase {
        self.feed().at(now, self.config.stale_after())
    }

    /// Increments whenever the feed, the pending list or an outcome changes.
    pub fn generation(&self) -> u64 {
        self.shared.generation.load(Ordering::Acquire)
    }

    pub fn refresh(&self) {
        let _ = self.polls.try_send(PollCommand::Refresh);
    }

    /// Queue an action. Refused in read-only mode for mutating actions, and
    /// when the bounded queue is full rather than growing without limit.
    pub fn submit(&self, action: Action) -> Result<u64, String> {
        if self.config.read_only && action.is_mutating() {
            return Err(format!(
                "{} refused: this client is read-only",
                action.label()
            ));
        }
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        if let Ok(mut pending) = self.shared.pending.lock() {
            pending.push((id, action.clone()));
        }
        match self.actions.try_send(Command::Act(id, action)) {
            Ok(()) => {
                self.shared.changed();
                Ok(id)
            }
            Err(error) => {
                if let Ok(mut pending) = self.shared.pending.lock() {
                    pending.retain(|(p, _)| *p != id);
                }
                Err(match error {
                    TrySendError::Full(_) => {
                        "too many requests in flight; wait for one to finish".into()
                    }
                    TrySendError::Disconnected(_) => "controller worker stopped".into(),
                })
            }
        }
    }

    /// Actions queued or in flight, oldest first.
    pub fn pending(&self) -> Vec<(u64, Action)> {
        self.shared
            .pending
            .lock()
            .map(|p| p.clone())
            .unwrap_or_default()
    }

    /// The most recent outcomes, newest last, at most 64.
    pub fn outcomes(&self) -> Vec<ActionOutcome> {
        self.shared
            .outcomes
            .lock()
            .map(|o| o.iter().cloned().collect())
            .unwrap_or_default()
    }

    pub fn outcome(&self, id: u64) -> Option<ActionOutcome> {
        self.shared
            .outcomes
            .lock()
            .ok()?
            .iter()
            .rev()
            .find(|o| o.id == id)
            .cloned()
    }
}

impl Drop for Controller {
    fn drop(&mut self) {
        // Blocking sends are bounded: each worker drains its queue promptly,
        // and an in-flight request ends at its own deadline.
        let _ = self.polls.send(PollCommand::Shutdown);
        let _ = self.actions.send(Command::Shutdown);
        for thread in self.threads.drain(..) {
            let _ = thread.join();
        }
    }
}

fn poll_loop(config: &ControllerConfig, shared: &Shared, commands: Receiver<PollCommand>) {
    let interval = config.poll_interval();
    let mut next = Instant::now();
    loop {
        let wait = next.saturating_duration_since(Instant::now());
        match commands.recv_timeout(wait) {
            Ok(PollCommand::Refresh) => next = Instant::now(),
            Ok(PollCommand::Shutdown) | Err(RecvTimeoutError::Disconnected) => return,
            Err(RecvTimeoutError::Timeout) => {}
        }
        if Instant::now() < next {
            continue;
        }
        let outcome = read_snapshot(config);
        if let Ok(mut feed) = shared.feed.lock() {
            record(&mut feed, outcome, SystemTime::now());
        }
        shared.changed();
        next = Instant::now() + interval;
    }
}

fn action_loop(
    config: &ControllerConfig,
    shared: &Shared,
    commands: Receiver<Command>,
    refresh: SyncSender<PollCommand>,
) {
    while let Ok(Command::Act(id, action)) = commands.recv() {
        let result = run_action(config, &action);
        if let Ok(mut pending) = shared.pending.lock() {
            pending.retain(|(p, _)| *p != id);
        }
        let mutated = action.is_mutating() && result.is_ok();
        if let Ok(mut outcomes) = shared.outcomes.lock() {
            if outcomes.len() == OUTCOME_HISTORY {
                outcomes.pop_front();
            }
            outcomes.push_back(ActionOutcome {
                id,
                action,
                result,
                finished_at: SystemTime::now(),
            });
        }
        shared.changed();
        if mutated {
            // Show the controller's new state now, not at the next tick.
            let _ = refresh.try_send(PollCommand::Refresh);
        }
    }
}

/// How one read ended, before it is folded into a feed.
#[derive(Debug)]
pub(crate) enum ReadOutcome {
    Snapshot(Box<Snapshot>),
    Disconnected(String),
    Failed(String),
}

pub(crate) fn record(feed: &mut Feed<Snapshot>, outcome: ReadOutcome, now: SystemTime) {
    match outcome {
        ReadOutcome::Snapshot(snapshot) => {
            feed.phase = Phase::Live;
            feed.value = Some(Arc::new(*snapshot));
            feed.received_at = Some(now);
            feed.detail = None;
            feed.reads += 1;
        }
        ReadOutcome::Disconnected(detail) => {
            feed.phase = Phase::Disconnected;
            feed.detail = Some(detail);
        }
        ReadOutcome::Failed(detail) => {
            feed.phase = Phase::Error;
            feed.detail = Some(detail);
        }
    }
}

fn read_snapshot(config: &ControllerConfig) -> ReadOutcome {
    let response = match exchange(
        &config.socket,
        &RpcRequest::new(RpcOp::Snapshot),
        config.request_timeout,
        config.max_snapshot_bytes,
    ) {
        Ok(response) => response,
        Err(error) => return error,
    };
    if !response.ok {
        return ReadOutcome::Failed(controller_error(&response));
    }
    match response.snapshot {
        Some(value) => match model::decode_snapshot(value) {
            Ok(snapshot) => ReadOutcome::Snapshot(Box::new(snapshot)),
            Err(detail) => ReadOutcome::Failed(detail),
        },
        None => ReadOutcome::Failed("controller answered without a snapshot".into()),
    }
}

fn run_action(config: &ControllerConfig, action: &Action) -> Result<ActionPayload, String> {
    let limit = match action {
        Action::Logs { .. } => (config.max_log_bytes.max(0) as usize).saturating_mul(2) + 64 * 1024,
        _ => config.max_snapshot_bytes,
    };
    let response = exchange(
        &config.socket,
        &action.request(config),
        action.timeout(config),
        limit,
    )
    .map_err(|outcome| match outcome {
        ReadOutcome::Disconnected(detail) | ReadOutcome::Failed(detail) => detail,
        ReadOutcome::Snapshot(_) => unreachable!("exchange never yields a snapshot"),
    })?;
    if !response.ok {
        return Err(controller_error(&response));
    }
    match action {
        Action::Logs { .. } => {
            let value = response
                .logs
                .ok_or("controller answered without log text")?;
            serde_json::from_value(value)
                .map(ActionPayload::Logs)
                .map_err(|e| format!("log chunk did not decode: {e}"))
        }
        Action::Events { .. } => {
            let events = response
                .events
                .unwrap_or_default()
                .into_iter()
                .map(serde_json::from_value)
                .collect::<Result<Vec<ServiceEvent>, _>>()
                .map_err(|e| format!("events did not decode: {e}"))?;
            Ok(ActionPayload::Events(events))
        }
        _ => Ok(ActionPayload::Done),
    }
}

fn controller_error(response: &RpcResponse) -> String {
    response
        .error
        .clone()
        .unwrap_or_else(|| "controller refused the request without a reason".into())
}

fn exchange(
    socket: &Path,
    request: &RpcRequest,
    timeout: Duration,
    limit: usize,
) -> Result<RpcResponse, ReadOutcome> {
    let mut client = Client::connect(socket).map_err(|error| classify_connect(socket, error))?;
    client
        .send_bounded(request, Instant::now() + timeout, limit)
        .map_err(|error| ReadOutcome::Failed(describe(error)))
}

fn classify_connect(socket: &Path, error: ClientError) -> ReadOutcome {
    let shown = display_path(socket);
    match error {
        ClientError::Io(e) if e.kind() == ErrorKind::NotFound => {
            ReadOutcome::Disconnected(format!("no controller socket at {shown}"))
        }
        ClientError::Io(e) if e.kind() == ErrorKind::ConnectionRefused => {
            ReadOutcome::Disconnected(format!(
                "controller socket at {shown} refused the connection"
            ))
        }
        ClientError::Io(e) if e.kind() == ErrorKind::PermissionDenied => {
            ReadOutcome::Disconnected(format!("no permission to open {shown}"))
        }
        other => ReadOutcome::Failed(describe(other)),
    }
}

fn describe(error: ClientError) -> String {
    match error {
        ClientError::Io(e) if e.kind() == ErrorKind::TimedOut => {
            "controller did not answer before the deadline".into()
        }
        ClientError::Io(e) if e.kind() == ErrorKind::InvalidData => {
            "controller response exceeded the size limit".into()
        }
        other => other.to_string(),
    }
}

/// Replace the home directory with `~` so a socket path can appear on screen
/// and in captures without naming the account.
pub fn display_path(path: &Path) -> String {
    let text = path.display().to_string();
    match std::env::var("HOME") {
        Ok(home) if !home.is_empty() && text.starts_with(&home) => {
            format!("~{}", &text[home.len()..])
        }
        _ => text,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{BufRead, BufReader, Write};
    use std::os::unix::net::UnixListener;

    fn test_config(socket: PathBuf) -> ControllerConfig {
        ControllerConfig {
            socket,
            poll_interval: Duration::from_secs(1),
            request_timeout: Duration::from_millis(500),
            lifecycle_timeout: Duration::from_millis(500),
            max_snapshot_bytes: 64 * 1024,
            ..ControllerConfig::default()
        }
    }

    fn snapshot_json() -> serde_json::Value {
        serde_json::json!({
            "generatedAt": 1_800_000_000.0,
            "daemon": {"version": "test", "pid": 7, "startedAt": 1_799_990_000.0, "tickIntervalSec": 5.0},
            "services": [], "messages": []
        })
    }

    /// A one-request controller stand-in answering with `reply`.
    fn serve_once(listener: UnixListener, reply: String) -> std::thread::JoinHandle<String> {
        std::thread::spawn(move || {
            let (stream, _) = listener.accept().unwrap();
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            let mut line = String::new();
            reader.read_line(&mut line).unwrap();
            // The client may hang up early on an oversized reply; that is the
            // behavior under test, not a server failure.
            let mut writer = stream;
            let _ = writer
                .write_all(reply.as_bytes())
                .and_then(|()| writer.write_all(b"\n"));
            line
        })
    }

    #[test]
    fn missing_socket_is_disconnected_not_error() {
        let dir = tempfile::tempdir().unwrap();
        let config = test_config(dir.path().join("absent.sock"));
        match read_snapshot(&config) {
            ReadOutcome::Disconnected(detail) => assert!(detail.contains("no controller socket")),
            other => panic!("expected disconnected, got {other:?}"),
        }
    }

    #[test]
    fn snapshot_round_trip_is_live() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("c.sock");
        let listener = UnixListener::bind(&path).unwrap();
        let reply = serde_json::json!({"ok": true, "snapshot": snapshot_json()}).to_string();
        let server = serve_once(listener, reply);
        let outcome = read_snapshot(&test_config(path));
        assert_eq!(server.join().unwrap().trim(), r#"{"op":"snapshot"}"#);
        let mut feed = Feed::default();
        record(&mut feed, outcome, SystemTime::now());
        assert_eq!(feed.phase, Phase::Live);
        assert_eq!(feed.value.unwrap().daemon.version, "test");
    }

    #[test]
    fn controller_refusal_is_error_and_keeps_last_value() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("c.sock");
        let mut feed = Feed::default();
        record(
            &mut feed,
            ReadOutcome::Snapshot(Box::new(model::decode_snapshot(snapshot_json()).unwrap())),
            SystemTime::now(),
        );

        let listener = UnixListener::bind(&path).unwrap();
        let server = serve_once(
            listener,
            r#"{"ok":false,"error":"registry locked"}"#.to_string(),
        );
        let outcome = read_snapshot(&test_config(path));
        server.join().unwrap();
        record(&mut feed, outcome, SystemTime::now());
        assert_eq!(feed.phase, Phase::Error);
        assert_eq!(feed.detail.as_deref(), Some("registry locked"));
        assert!(
            feed.value.is_some(),
            "last-known value is retained, marked by phase"
        );
    }

    #[test]
    fn oversized_snapshot_is_refused() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("c.sock");
        let listener = UnixListener::bind(&path).unwrap();
        let padding = "x".repeat(128 * 1024);
        let reply = serde_json::json!({"ok": true, "error": padding}).to_string();
        let server = serve_once(listener, reply);
        let outcome = read_snapshot(&test_config(path));
        let _ = server.join();
        match outcome {
            ReadOutcome::Failed(detail) => assert!(detail.contains("size limit"), "{detail}"),
            other => panic!("expected size failure, got {other:?}"),
        }
    }

    #[test]
    fn silent_controller_times_out() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("c.sock");
        let listener = UnixListener::bind(&path).unwrap();
        let holder = std::thread::spawn(move || {
            let (stream, _) = listener.accept().unwrap();
            std::thread::sleep(Duration::from_millis(900));
            drop(stream);
        });
        let started = Instant::now();
        let outcome = read_snapshot(&test_config(path));
        assert!(started.elapsed() < Duration::from_millis(850));
        holder.join().unwrap();
        match outcome {
            ReadOutcome::Failed(detail) => assert!(detail.contains("deadline"), "{detail}"),
            other => panic!("expected timeout, got {other:?}"),
        }
    }

    #[test]
    fn reply_request_matches_the_swift_wire_shape() {
        let config = ControllerConfig::default();
        let action = Action::Reply {
            message_id: 42,
            body: "approved".into(),
        };
        let encoded = Client::encode(&action.request(&config));
        assert_eq!(
            encoded,
            r#"{"op":"reply","body":"approved","messageID":42}"#
        );
        let stop = Action::Stop {
            service_id: "abc".into(),
        };
        assert!(Client::encode(&stop.request(&config)).contains(r#""serviceID":"abc""#));
        assert!(stop.needs_confirmation());
        assert!(!Action::Logs {
            service_id: "abc".into(),
            stream: LogStream::Out
        }
        .is_mutating());
    }

    #[test]
    fn read_only_client_refuses_mutations_before_the_socket() {
        let dir = tempfile::tempdir().unwrap();
        let config = ControllerConfig {
            read_only: true,
            ..test_config(dir.path().join("absent.sock"))
        };
        let controller = Controller::spawn(config, Arc::new(|| {}));
        let refused = controller.submit(Action::Restart {
            service_id: "abc".into(),
        });
        assert!(refused.unwrap_err().contains("read-only"));
        assert!(controller
            .submit(Action::Events {
                service_id: None,
                limit: 10
            })
            .is_ok());
    }

    #[test]
    fn display_path_hides_the_home_directory() {
        if let Ok(home) = std::env::var("HOME") {
            let shown = display_path(&Path::new(&home).join("x/fleetd.sock"));
            assert_eq!(shown, "~/x/fleetd.sock");
        }
    }
}
