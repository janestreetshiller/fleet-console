//! What differs between macOS and Linux, behind one interface.
//!
//! Telemetry is sampled with `sysinfo` on both systems, plus the few sources it
//! does not cover (Linux GPU busy time from sysfs). Every value a source cannot
//! provide is `Metric::Unavailable(Reason::NotMeasured)`, and `capabilities()`
//! states which values are measured on the running system so a client or a
//! document can say so in words. Paths, notifications and the status-area item
//! are here too, because each has a macOS and a Linux answer.

mod sampler;

#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "macos")]
mod macos;

#[cfg(target_os = "linux")]
use linux as os;
#[cfg(target_os = "macos")]
use macos as os;

use crate::controller::Wake;
use crate::observe::{Feed, Metric, Phase};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError, SyncSender};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, SystemTime};

pub use sampler::Sampler;

/// Process rows kept per sample, highest CPU first. A process tree needs
/// parents, so this is generous, but it is a bound.
pub const MAX_PROCESSES: usize = 2048;
/// Volumes kept per sample.
pub const MAX_VOLUMES: usize = 32;
/// Samples of history kept for sparklines, matching `ServiceRecord.historyLimit`.
pub const HISTORY: usize = 40;

#[derive(Debug, Clone, PartialEq)]
pub struct ProcessRow {
    pub pid: u32,
    pub ppid: Option<u32>,
    /// Executable name only. Arguments are never collected: they carry paths,
    /// tokens and hostnames that do not belong on a screen capture.
    pub name: String,
    /// Percent of one core, as `ps` reports it; can exceed 100.
    pub cpu_pct: Metric,
    pub rss_bytes: u64,
    pub start_time: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Volume {
    pub mount: String,
    pub filesystem: String,
    pub total_bytes: u64,
    pub available_bytes: u64,
    pub removable: bool,
}

impl Volume {
    pub fn used_percent(&self) -> Metric {
        if self.total_bytes == 0 {
            return Metric::Unavailable(crate::observe::Reason::Failed);
        }
        let used = self.total_bytes.saturating_sub(self.available_bytes) as f64;
        Metric::Measured(used / self.total_bytes as f64 * 100.0)
    }

    pub fn used_bytes(&self) -> u64 {
        self.total_bytes.saturating_sub(self.available_bytes)
    }
}

/// One reading of this machine.
#[derive(Debug, Clone, PartialEq)]
pub struct HostSample {
    pub taken_at: SystemTime,
    pub os: &'static str,
    pub cpu_pct: Metric,
    pub memory_pct: Metric,
    pub memory_used_bytes: Option<u64>,
    pub memory_total_bytes: Option<u64>,
    pub swap_used_bytes: Option<u64>,
    /// The volume that holds user data: `/System/Volumes/Data` on macOS when
    /// present, otherwise `/`.
    pub disk_pct: Metric,
    pub disk: Option<Volume>,
    pub net_rx_bytes_per_sec: Metric,
    pub net_tx_bytes_per_sec: Metric,
    pub gpu_pct: Metric,
    pub uptime_sec: Option<u64>,
    pub process_count: usize,
    pub processes: Vec<ProcessRow>,
    pub volumes: Vec<Volume>,
    /// The last `HISTORY` readings, oldest first, filled by `TelemetryWorker`.
    /// `None` marks an interval with no measurement, which a chart leaves blank.
    pub cpu_history: Vec<Option<f64>>,
    pub rx_history: Vec<Option<f64>>,
    pub tx_history: Vec<Option<f64>>,
}

/// Something that can read this machine. The real implementation is
/// `Sampler`; tests substitute recorded samples.
pub trait TelemetrySource: Send {
    fn sample(&mut self) -> HostSample;
}

impl TelemetrySource for Sampler {
    fn sample(&mut self) -> HostSample {
        Sampler::sample(self)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Support {
    Measured,
    NotMeasured,
    /// Measured only on some hardware; the sample says which.
    Conditional,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Capability {
    pub value: &'static str,
    pub support: Support,
    pub source: &'static str,
}

/// What this build measures on the running operating system.
pub fn capabilities() -> &'static [Capability] {
    os::CAPABILITIES
}

/// Bounded rings of recent readings.
#[derive(Default)]
struct History {
    cpu: std::collections::VecDeque<Option<f64>>,
    rx: std::collections::VecDeque<Option<f64>>,
    tx: std::collections::VecDeque<Option<f64>>,
}

impl History {
    fn record(&mut self, sample: &mut HostSample) {
        for (ring, value) in [
            (&mut self.cpu, sample.cpu_pct.value()),
            (&mut self.rx, sample.net_rx_bytes_per_sec.value()),
            (&mut self.tx, sample.net_tx_bytes_per_sec.value()),
        ] {
            if ring.len() == HISTORY {
                ring.pop_front();
            }
            ring.push_back(value);
        }
        sample.cpu_history = self.cpu.iter().copied().collect();
        sample.rx_history = self.rx.iter().copied().collect();
        sample.tx_history = self.tx.iter().copied().collect();
    }
}

/// Background sampling. The render thread reads the latest sample; it never
/// waits for a process scan.
pub struct TelemetryWorker {
    feed: Arc<Mutex<Feed<HostSample>>>,
    generation: Arc<AtomicU64>,
    stop: SyncSender<()>,
    interval: Duration,
    thread: Option<JoinHandle<()>>,
}

impl TelemetryWorker {
    pub const DEFAULT_INTERVAL: Duration = Duration::from_secs(2);

    pub fn spawn(interval: Duration, wake: Wake) -> Self {
        Self::spawn_with(Sampler::new(), interval, wake)
    }

    pub fn spawn_with<S: TelemetrySource + 'static>(
        mut source: S,
        interval: Duration,
        wake: Wake,
    ) -> Self {
        let interval = interval.clamp(Duration::from_secs(1), Duration::from_secs(60));
        let feed = Arc::new(Mutex::new(Feed::default()));
        let generation = Arc::new(AtomicU64::new(0));
        let (stop, stopped) = mpsc::sync_channel::<()>(1);
        let thread = {
            let feed = feed.clone();
            let generation = generation.clone();
            std::thread::Builder::new()
                .name("fleet-telemetry".into())
                .spawn(move || {
                    let mut history = History::default();
                    loop {
                        let mut sample = source.sample();
                        history.record(&mut sample);
                        if let Ok(mut feed) = feed.lock() {
                            feed.phase = Phase::Live;
                            feed.received_at = Some(sample.taken_at);
                            feed.value = Some(Arc::new(sample));
                            feed.reads += 1;
                        }
                        generation.fetch_add(1, Ordering::Release);
                        wake();
                        match stopped.recv_timeout(interval) {
                            Err(RecvTimeoutError::Timeout) => continue,
                            _ => return,
                        }
                    }
                })
                .expect("spawn telemetry thread")
        };
        Self {
            feed,
            generation,
            stop,
            interval,
            thread: Some(thread),
        }
    }

    pub fn feed(&self) -> Feed<HostSample> {
        self.feed.lock().map(|f| f.clone()).unwrap_or_default()
    }

    pub fn generation(&self) -> u64 {
        self.generation.load(Ordering::Acquire)
    }

    pub fn stale_after(&self) -> Duration {
        self.interval * 3
    }
}

impl Drop for TelemetryWorker {
    fn drop(&mut self) {
        let _ = self.stop.try_send(());
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

/// The controller socket this client connects to by default. See
/// `fleet_proto::default_socket_path` for the override order.
pub fn socket_path() -> PathBuf {
    fleet_proto::default_socket_path()
}

/// Whether a status-area item can be shown, and if not, why.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StatusArea {
    /// macOS menu bar status item.
    MenuBar,
    /// A StatusNotifierItem host is registered on the session bus.
    StatusNotifier,
    /// No host is available; the client runs as an ordinary window.
    Unavailable(String),
}

pub fn status_area() -> StatusArea {
    os::status_area()
}

/// Post a desktop notification through the system's own tool. Returns the
/// reason when none exists rather than failing silently.
pub fn notify(title: &str, body: &str) -> Result<(), String> {
    os::notify(&sanitize(title, 80), &sanitize(body, 240))
}

fn sanitize(text: &str, limit: usize) -> String {
    text.chars()
        .filter(|c| !c.is_control())
        .take(limit)
        .collect()
}

/// Run a short command with a hard deadline, returning stdout on success.
pub(crate) fn run_bounded(program: &str, args: &[&str], deadline: Duration) -> Option<String> {
    use std::process::{Command, Stdio};
    use std::time::Instant;
    let mut child = Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    let started = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(status)) if status.success() => {
                let mut out = String::new();
                use std::io::Read;
                child
                    .stdout
                    .take()?
                    .take(64 * 1024)
                    .read_to_string(&mut out)
                    .ok()?;
                return Some(out);
            }
            Ok(Some(_)) => return None,
            Ok(None) if started.elapsed() < deadline => {
                std::thread::sleep(Duration::from_millis(20))
            }
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return None;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Recorded(u32);

    impl TelemetrySource for Recorded {
        fn sample(&mut self) -> HostSample {
            self.0 += 1;
            crate::fixtures::host_sample(f64::from(self.0))
        }
    }

    #[test]
    fn worker_publishes_samples_and_stops() {
        let (tx, rx) = mpsc::channel();
        let worker = TelemetryWorker::spawn_with(
            Recorded(0),
            Duration::from_secs(1),
            Arc::new(move || {
                let _ = tx.send(());
            }),
        );
        rx.recv_timeout(Duration::from_secs(2))
            .expect("first sample");
        let feed = worker.feed();
        assert_eq!(feed.phase, Phase::Live);
        assert!(feed.value.is_some());
        drop(worker);
    }

    #[test]
    fn every_platform_value_has_a_capability_row() {
        let names: Vec<&str> = capabilities().iter().map(|c| c.value).collect();
        for required in ["cpu", "memory", "disk", "network", "gpu", "processes"] {
            assert!(
                names.contains(&required),
                "missing capability row for {required}"
            );
        }
    }

    #[test]
    fn notification_text_is_bounded_and_printable() {
        assert_eq!(sanitize("a\u{7}b\nc", 10), "abc");
        assert_eq!(sanitize(&"x".repeat(500), 80).len(), 80);
    }
}
