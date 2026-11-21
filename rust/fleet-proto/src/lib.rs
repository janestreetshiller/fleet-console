
use serde::{Deserialize, Serialize};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::time::Duration;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum RpcOp {
    #[serde(rename = "ping")]
    #[default]
    Ping,
    #[serde(rename = "snapshot")]
    Snapshot,
    #[serde(rename = "subscribe")]
    Subscribe,
    #[serde(rename = "launch")]
    Launch,
    #[serde(rename = "renew")]
    Renew,
    #[serde(rename = "stop")]
    Stop,
    #[serde(rename = "restart")]
    Restart,
    #[serde(rename = "events")]
    Events,
    #[serde(rename = "logs")]
    Logs,
    #[serde(rename = "claim")]
    Claim,
    #[serde(rename = "reconcile")]
    Reconcile,
    #[serde(rename = "refreshDevices")]
    RefreshDevices,
    #[serde(rename = "reloadConfig")]
    ReloadConfig,
    #[serde(rename = "ignoreCommand")]
    IgnoreCommand,
    #[serde(rename = "prune")]
    Prune,
    #[serde(rename = "pause")]
    Pause,
    #[serde(rename = "resume")]
    Resume,
    #[serde(rename = "kill")]
    Kill,
    #[serde(rename = "postMessage")]
    PostMessage,
    #[serde(rename = "messages")]
    Messages,
    #[serde(rename = "reply")]
    Reply,
    #[serde(rename = "markSeen")]
    MarkSeen,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct RpcRequest {
    pub op: RpcOp,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub launch: Option<serde_json::Value>,
    #[serde(rename = "serviceID", skip_serializing_if = "Option::is_none")]
    pub service_id: Option<String>,
    #[serde(rename = "ttlSec", skip_serializing_if = "Option::is_none")]
    pub ttl_sec: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stream: Option<String>,
    #[serde(rename = "maxBytes", skip_serializing_if = "Option::is_none")]
    pub max_bytes: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub command: Option<String>,
    #[serde(rename = "unmanagedID", skip_serializing_if = "Option::is_none")]
    pub unmanaged_id: Option<String>,
    #[serde(rename = "friendlyName", skip_serializing_if = "Option::is_none")]
    pub friendly_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub purpose: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub agent: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub body: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    #[serde(rename = "needsReply", skip_serializing_if = "Option::is_none")]
    pub needs_reply: Option<bool>,
    #[serde(rename = "messageID", skip_serializing_if = "Option::is_none")]
    pub message_id: Option<i64>,
    #[serde(rename = "unansweredOnly", skip_serializing_if = "Option::is_none")]
    pub unanswered_only: Option<bool>,
}

impl RpcRequest {
    pub fn new(op: RpcOp) -> Self {
        Self { op, ..Default::default() }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DaemonInfo {
    pub version: String,
    pub pid: i32,
    #[serde(rename = "startedAt")]
    pub started_at: f64,
    #[serde(rename = "lastTickAt", default, skip_serializing_if = "Option::is_none")]
    pub last_tick_at: Option<f64>,
    #[serde(rename = "lastReconcileAt", default, skip_serializing_if = "Option::is_none")]
    pub last_reconcile_at: Option<f64>,
    #[serde(rename = "tickIntervalSec")]
    pub tick_interval_sec: f64,
    #[serde(rename = "socketPath", default)]
    pub socket_path: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RpcResponse {
    pub ok: bool,
    #[serde(default)]
    pub error: Option<String>,
    #[serde(default)]
    pub snapshot: Option<serde_json::Value>,
    #[serde(default)]
    pub service: Option<serde_json::Value>,
    #[serde(default)]
    pub events: Option<Vec<serde_json::Value>>,
    #[serde(default)]
    pub logs: Option<serde_json::Value>,
    #[serde(default)]
    pub daemon: Option<DaemonInfo>,
    #[serde(default)]
    pub messages: Option<Vec<serde_json::Value>>,
    #[serde(default)]
    pub message: Option<serde_json::Value>,
}

#[derive(Debug)]
pub enum ClientError {
    Io(std::io::Error),
    Decode(serde_json::Error),
    Closed,
}

impl std::fmt::Display for ClientError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ClientError::Io(e) => write!(f, "io error: {e}"),
            ClientError::Decode(e) => write!(f, "decode error: {e}"),
            ClientError::Closed => write!(f, "controller closed the connection"),
        }
    }
}

impl std::error::Error for ClientError {}

pub const SOCKET_VARIABLE: &str = "FLEETCONSOLE_SOCKET";
pub const STATE_ROOT_VARIABLE: &str = "FLEETCONSOLE_STATE_ROOT";

const SUPPORT_SUFFIX: &str = "Library/Application Support/FleetConsole";

pub fn default_socket_path() -> PathBuf {
    socket_path_from(|name| std::env::var_os(name).filter(|v| !v.is_empty()))
}

fn socket_path_from(env: impl Fn(&str) -> Option<std::ffi::OsString>) -> PathBuf {
    if let Some(socket) = env(SOCKET_VARIABLE) {
        return PathBuf::from(socket);
    }
    if let Some(root) = env(STATE_ROOT_VARIABLE) {
        return PathBuf::from(root).join(SUPPORT_SUFFIX).join("fleetd.sock");
    }
    let home = PathBuf::from(env("HOME").unwrap_or_default());
    if cfg!(target_os = "macos") {
        return home.join(SUPPORT_SUFFIX).join("fleetd.sock");
    }
    match env("XDG_RUNTIME_DIR") {
        Some(runtime) => PathBuf::from(runtime).join("fleetconsole/fleetd.sock"),
        None => home.join(".local/state/fleetconsole/fleetd.sock"),
    }
}

pub struct Client {
    reader: BufReader<UnixStream>,
    writer: UnixStream,
}

impl Client {
    pub fn connect(path: &std::path::Path) -> Result<Self, ClientError> {
        let stream = UnixStream::connect(path).map_err(ClientError::Io)?;
        Self::from_stream(stream)
    }

    pub fn from_stream(stream: UnixStream) -> Result<Self, ClientError> {
        stream
            .set_read_timeout(Some(Duration::from_secs(15)))
            .map_err(ClientError::Io)?;
        let writer = stream.try_clone().map_err(ClientError::Io)?;
        Ok(Self { reader: BufReader::new(stream), writer })
    }

    pub fn send(&mut self, request: &RpcRequest) -> Result<RpcResponse, ClientError> {
        let mut line = serde_json::to_vec(request).map_err(ClientError::Decode)?;
        line.push(b'\n');
        self.writer.write_all(&line).map_err(ClientError::Io)?;
        self.writer.flush().map_err(ClientError::Io)?;

        let mut buffer = String::new();
        let read = self.reader.read_line(&mut buffer).map_err(ClientError::Io)?;
        if read == 0 {
            return Err(ClientError::Closed);
        }
        serde_json::from_str(&buffer).map_err(ClientError::Decode)
    }

    pub fn send_bounded(
        &mut self,
        request: &RpcRequest,
        deadline: std::time::Instant,
        maximum: usize,
    ) -> Result<RpcResponse, ClientError> {
        use std::os::fd::AsRawFd;
        fn remaining(deadline: std::time::Instant) -> Result<Duration, ClientError> {
            deadline.checked_duration_since(std::time::Instant::now()).filter(|d| !d.is_zero())
                .ok_or_else(|| ClientError::Io(std::io::Error::new(std::io::ErrorKind::TimedOut, "proposal deadline exceeded")))
        }
        #[repr(C)]
        struct PollFd { fd: i32, events: i16, revents: i16 }
        #[cfg(target_os = "macos")]
        type PollCount = u32;
        #[cfg(not(target_os = "macos"))]
        type PollCount = usize;
        extern "C" { fn poll(fds: *mut PollFd, count: PollCount, milliseconds: i32) -> i32; }
        fn ready(fd: i32, events: i16, deadline: std::time::Instant) -> Result<(), ClientError> {
            loop {
                let timeout = remaining(deadline)?;
                let milliseconds = timeout.as_millis().saturating_add(1).min(i32::MAX as u128) as i32;
                let mut descriptor = PollFd { fd, events, revents: 0 };
                let result = unsafe { poll(&mut descriptor, 1, milliseconds) };
                if result > 0 { return Ok(()); }
                if result == 0 { remaining(deadline)?; continue; }
                let error = std::io::Error::last_os_error();
                if error.kind() != std::io::ErrorKind::Interrupted { return Err(ClientError::Io(error)); }
            }
        }
        self.writer.set_nonblocking(true).map_err(ClientError::Io)?;
        let result = (|| {
            let mut line = serde_json::to_vec(request).map_err(ClientError::Decode)?;
            line.push(b'\n');
            let mut left = line.as_slice();
            while !left.is_empty() {
                ready(self.writer.as_raw_fd(), 4, deadline)?;
                let written = match self.writer.write(left) {
                    Ok(written) => written,
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => continue,
                    Err(error) => return Err(ClientError::Io(error)),
                };
                if written == 0 { return Err(ClientError::Closed); }
                left = &left[written..];
            }
            let mut buffer = Vec::new();
            loop {
                remaining(deadline)?;
                if self.reader.buffer().is_empty() {
                    ready(self.reader.get_ref().as_raw_fd(), 1, deadline)?;
                }
                let available = match self.reader.fill_buf() {
                    Ok(available) => available,
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => continue,
                    Err(error) => return Err(ClientError::Io(error)),
                };
                if available.is_empty() { return Err(ClientError::Closed); }
                let end = available.iter().position(|b| *b == b'\n').map(|i| i+1);
                let count = end.unwrap_or(available.len());
                if count > maximum.saturating_sub(buffer.len()) {
                    return Err(ClientError::Io(std::io::Error::new(std::io::ErrorKind::InvalidData,
                        "controller response exceeds proposal byte limit")));
                }
                buffer.extend_from_slice(&available[..count]);
                self.reader.consume(count);
                if end.is_some() { break; }
            }
            remaining(deadline)?;
            serde_json::from_slice(&buffer).map_err(ClientError::Decode)
        })();
        let reset = self.writer.set_nonblocking(false).map_err(ClientError::Io);
        match result {
            Err(error) => Err(error),
            Ok(response) => { reset?; Ok(response) }
        }
    }

    pub fn encode(request: &RpcRequest) -> String {
        serde_json::to_string(request).unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn omits_absent_fields() {
        let encoded = Client::encode(&RpcRequest::new(RpcOp::Ping));
        assert_eq!(encoded, r#"{"op":"ping"}"#);
    }

    #[test]
    fn uses_swift_case_names() {
        let encoded = Client::encode(&RpcRequest::new(RpcOp::RefreshDevices));
        assert!(encoded.contains(r#""op":"refreshDevices""#), "got {encoded}");
    }

    #[test]
    fn socket_path_precedence() {
        use std::ffi::OsString;
        let env = |pairs: &'static [(&'static str, &'static str)]| {
            move |name: &str| pairs.iter().find(|(k, _)| *k == name).map(|(_, v)| OsString::from(v))
        };
        let all = env(&[
            ("FLEETCONSOLE_SOCKET", "/forwarded/fleetd.sock"),
            ("FLEETCONSOLE_STATE_ROOT", "/isolated"),
            ("HOME", "/home/example"),
        ]);
        assert_eq!(socket_path_from(all), PathBuf::from("/forwarded/fleetd.sock"));
        let root = env(&[("FLEETCONSOLE_STATE_ROOT", "/isolated"), ("HOME", "/home/example")]);
        assert_eq!(
            socket_path_from(root),
            PathBuf::from("/isolated/Library/Application Support/FleetConsole/fleetd.sock")
        );
        let plain = env(&[("HOME", "/home/example"), ("XDG_RUNTIME_DIR", "/run/user/1000")]);
        let expected = if cfg!(target_os = "macos") {
            "/home/example/Library/Application Support/FleetConsole/fleetd.sock"
        } else {
            "/run/user/1000/fleetconsole/fleetd.sock"
        };
        assert_eq!(socket_path_from(plain), PathBuf::from(expected));
    }

    #[test]
    fn service_id_keeps_swift_spelling() {
        let mut request = RpcRequest::new(RpcOp::Stop);
        request.service_id = Some("abc".into());
        assert!(Client::encode(&request).contains(r#""serviceID":"abc""#));
    }
}
