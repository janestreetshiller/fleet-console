//! Everything a client draws, derived from the two feeds.
//!
//! `Dashboard::build` is a pure function of its inputs: the controller feed,
//! the telemetry feed, the pending and finished actions, and a clock. Both
//! clients call it on each change and render the result, so the terminal and
//! the window cannot disagree about a count, a band or an unavailable value.
//! It allocates a few hundred rows at most; every list has a bound.

use crate::controller::{Action, ActionOutcome, ActionPayload};
use crate::format;
use crate::model::{
    AgentMessage, AttentionSeverity, DeviceHealth, DeviceRecord, MessageKind, ServiceRecord,
    ServiceState, Snapshot,
};
use crate::observe::{epoch_seconds, Feed, Metric, Phase, Reason};
use crate::platform::{HostSample, ProcessRow, Volume};
use crate::thresholds::{Level, NodeState};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::time::{Duration, SystemTime};

pub const MAX_SERVICE_ROWS: usize = 500;
pub const MAX_PROCESS_LINES: usize = 300;
pub const MAX_TRANSCRIPT_LINES: usize = 200;
pub const MAX_ATTENTION_ROWS: usize = 100;
const TREE_DEPTH: usize = 4;
const TREE_CHILDREN: usize = 8;
const OTHER_PROCESSES: usize = 15;
pub const DISK_CELLS: usize = 20;
pub const GAUGE_SEGMENTS: usize = 20;

/// The reply text sent when the operator approves or denies an agent question.
/// The agent reads it with `fleetctl inbox`.
pub const APPROVE_REPLY: &str = "approved";
pub const DENY_REPLY: &str = "denied";

pub struct Inputs<'a> {
    pub controller: &'a Feed<Snapshot>,
    pub controller_stale_after: Duration,
    pub telemetry: &'a Feed<HostSample>,
    pub telemetry_stale_after: Duration,
    pub pending: &'a [(u64, Action)],
    pub outcomes: &'a [ActionOutcome],
    pub read_only: bool,
    /// Socket path as it may be shown, home directory already replaced.
    pub socket_label: String,
    /// Force the remote interpretation even when a local `fleetd` with the
    /// controller's pid exists.
    pub assume_remote_controller: bool,
    pub now: SystemTime,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Dashboard {
    pub connection: Connection,
    pub header: Header,
    pub quick: QuickView,
    pub cluster: ClusterView,
    pub services: Vec<ServiceRow>,
    pub processes: ProcessView,
    pub agents: AgentsView,
    pub storage: StorageView,
    pub attention: Vec<AttentionRow>,
    pub activity: Vec<ActivityLine>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Connection {
    pub phase: Phase,
    /// One sentence a person can act on.
    pub summary: String,
    pub detail: Option<String>,
    pub controller_version: Option<String>,
    pub socket_label: String,
    pub age: Option<String>,
    /// Whether the controller supervises this machine. When it does not (an
    /// SSH-forwarded socket from another machine), its pids are not joined
    /// with local processes.
    pub locality: Locality,
    pub telemetry_phase: Phase,
    pub read_only: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Locality {
    /// A local process with the controller's pid is named `fleetd`.
    Local,
    /// No such local process; the controller runs elsewhere.
    Remote,
    /// Not decided yet: no snapshot or no local process sample.
    Unknown,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Header {
    pub title: &'static str,
    pub services_running: Option<usize>,
    pub subtitle: String,
    pub awaiting_reply: Option<usize>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Gauge {
    pub label: &'static str,
    pub metric: Metric,
    pub level: Option<Level>,
    pub text: String,
    pub detail: String,
}

impl Gauge {
    fn percent(label: &'static str, metric: Metric, detail: String) -> Self {
        Self {
            label,
            metric,
            level: Level::for_metric(metric),
            text: format::percent(metric),
            detail,
        }
    }

    /// Accessible description: label, value and the reason when unavailable.
    pub fn spoken(&self) -> String {
        match self.metric.reason() {
            Some(reason) => format!("{} unavailable, {}", self.label, reason.label()),
            None => format!("{} {}, {}", self.label, self.text, self.detail),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct DiskGrid {
    pub gauge: Gauge,
    /// 20 cells, a 5 by 4 grid in reading order; `Some` cells are used space.
    pub cells: Vec<Option<Level>>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Rate {
    pub label: &'static str,
    pub metric: Metric,
    pub text: String,
    /// Bar length relative to the highest rate in the retained history.
    pub fraction: Option<f64>,
    pub history: Vec<Option<f64>>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct QuickView {
    pub cpu: Gauge,
    pub memory: Gauge,
    pub disk: DiskGrid,
    pub download: Rate,
    pub upload: Rate,
    pub gpu: Gauge,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Freshness {
    Current,
    Stale,
    Disconnected,
}

#[derive(Debug, Clone, PartialEq)]
pub struct NodeTile {
    pub id: String,
    pub name: String,
    pub is_local: bool,
    pub state: NodeState,
    pub freshness: Freshness,
    pub gauges: Vec<Gauge>,
    /// Network rate text for the `net` row; the percent gauge needs a link
    /// capacity that is not measured.
    pub network_text: String,
    pub cpu_history: Vec<Option<f64>>,
    pub services_up: Option<usize>,
    pub services_total: Option<usize>,
    pub agents: Option<usize>,
    pub uptime: Option<String>,
    pub note: Option<String>,
}

impl NodeTile {
    pub fn worst_level(&self) -> Option<Level> {
        self.gauges.iter().filter_map(|g| g.level).max()
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct ClusterSummary {
    pub online: usize,
    pub total: usize,
    pub average_cpu: Metric,
    pub average_memory: Metric,
    pub average_gpu: Metric,
    pub agents: Option<usize>,
    pub needs_attention: usize,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ClusterView {
    pub summary: ClusterSummary,
    pub tiles: Vec<NodeTile>,
}

/// Why a control is unavailable for a row. Clients show this text instead of
/// sending a request that the controller would refuse.
#[derive(Debug, Clone, PartialEq)]
pub enum Control {
    Allowed,
    Refused(String),
}

impl Control {
    pub fn is_allowed(&self) -> bool {
        matches!(self, Self::Allowed)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct ServiceRow {
    pub id: String,
    pub short_id: String,
    pub name: String,
    pub owner: String,
    pub purpose: String,
    pub state: ServiceState,
    pub state_text: &'static str,
    pub level: Option<Level>,
    pub pid: Option<i32>,
    pub uptime: String,
    pub restarts: i64,
    pub ports: String,
    pub cpu: Metric,
    pub memory: String,
    pub lease: String,
    /// The four separate facts, in words.
    pub process: String,
    pub listening: String,
    pub health: String,
    pub claimed: bool,
    pub restart: Control,
    pub stop: Control,
    pub pause: Control,
    pub resume: Control,
    pub renew: Control,
    pub logs: Control,
    pub in_flight: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProcessRole {
    Service,
    Agent,
    Controller,
    Other,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ProcessLine {
    pub depth: usize,
    pub pid: Option<u32>,
    pub name: String,
    pub role: ProcessRole,
    pub cpu: Metric,
    pub memory: String,
    pub tag: Option<String>,
    pub last_child: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ProcessView {
    pub phase: Phase,
    pub lines: Vec<ProcessLine>,
    pub total_processes: Option<usize>,
    pub note: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AgentRow {
    pub name: String,
    pub target: String,
    pub state: String,
    pub level: Option<Level>,
    pub runtime: String,
    pub awaiting_reply: usize,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TranscriptLine {
    pub time: String,
    pub agent: String,
    pub verb: String,
    pub text: String,
    /// Set for a question still awaiting an answer.
    pub question: Option<Question>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Question {
    pub message_id: i64,
    pub reply: Control,
    pub in_flight: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AgentsView {
    pub rows: Vec<AgentRow>,
    pub transcript: Vec<TranscriptLine>,
    pub open_questions: usize,
}

#[derive(Debug, Clone, PartialEq)]
pub struct VolumeRow {
    pub mount: String,
    pub filesystem: String,
    pub used: String,
    pub total: String,
    pub free: String,
    pub gauge: Gauge,
}

#[derive(Debug, Clone, PartialEq)]
pub struct StorageView {
    pub phase: Phase,
    pub volumes: Vec<VolumeRow>,
    /// The per-path breakdown the Swift app scans is not implemented in the
    /// Rust clients; this says so instead of showing an empty list.
    pub largest_paths: Result<Vec<(String, String)>, String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Severity {
    Critical,
    Warning,
    Info,
}

impl Severity {
    pub fn label(self) -> &'static str {
        match self {
            Self::Critical => "crit",
            Self::Warning => "warn",
            Self::Info => "info",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct AttentionRow {
    pub id: String,
    pub severity: Severity,
    pub title: String,
    pub detail: String,
    /// Where the report came from: the controller, or this client's own telemetry.
    pub source: &'static str,
    pub service_id: Option<String>,
    pub message_id: Option<i64>,
    /// What can be done through the controller, in words.
    pub available: String,
    /// The read-only commands an agent would run to investigate this target.
    pub agent_commands: Vec<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ActivityLine {
    pub text: String,
    pub ok: Option<bool>,
}

impl Dashboard {
    pub fn build(inputs: &Inputs<'_>) -> Self {
        let now = epoch_seconds(inputs.now);
        let controller_phase = inputs
            .controller
            .at(inputs.now, inputs.controller_stale_after);
        let telemetry_phase = inputs
            .telemetry
            .at(inputs.now, inputs.telemetry_stale_after);
        let snapshot = inputs.controller.value.as_deref();
        let current = controller_phase.is_current();
        let sample = inputs
            .telemetry
            .value
            .as_deref()
            .filter(|_| telemetry_phase != Phase::Loading);

        let locality = match (snapshot, sample) {
            _ if inputs.assume_remote_controller => Locality::Remote,
            (Some(s), Some(h)) => {
                let pid = s.daemon.pid.max(0) as u32;
                if h.processes
                    .iter()
                    .any(|p| p.pid == pid && p.name.contains("fleetd"))
                {
                    Locality::Local
                } else {
                    Locality::Remote
                }
            }
            _ => Locality::Unknown,
        };

        let connection = connection(
            inputs,
            controller_phase,
            telemetry_phase,
            snapshot,
            locality,
        );
        let header = Header {
            title: "FleetConsole",
            services_running: snapshot
                .filter(|_| current)
                .map(Snapshot::running_service_count),
            subtitle: match (snapshot, current) {
                (Some(s), true) => {
                    let n = s.running_service_count();
                    if n == 1 {
                        "1 service running".into()
                    } else {
                        format!("{n} services running")
                    }
                }
                (_, _) => format!("services {}", controller_phase.label()),
            },
            awaiting_reply: snapshot
                .filter(|_| current)
                .map(|s| s.awaiting_reply().count()),
        };
        let quick = quick_view(sample, telemetry_phase);
        let cluster = cluster(
            inputs,
            snapshot,
            controller_phase,
            sample,
            telemetry_phase,
            &quick,
        );
        let services = snapshot
            .map(|s| service_rows(s, now, current, inputs.read_only, inputs.pending))
            .unwrap_or_default();
        let processes = process_view(snapshot, sample, telemetry_phase, locality);
        let agents = agents_view(snapshot, now, current, inputs.read_only, inputs.pending);
        let storage = storage_view(sample, telemetry_phase);
        let attention = attention_rows(snapshot, current, &quick, &storage, inputs.read_only);
        let activity = activity(inputs.pending, inputs.outcomes);
        Self {
            connection,
            header,
            quick,
            cluster,
            services,
            processes,
            agents,
            storage,
            attention,
            activity,
        }
    }
}

fn connection(
    inputs: &Inputs<'_>,
    phase: Phase,
    telemetry_phase: Phase,
    snapshot: Option<&Snapshot>,
    locality: Locality,
) -> Connection {
    let age = inputs
        .controller
        .age(inputs.now)
        .map(|d| format!("{} ago", format::duration(d.as_secs_f64())));
    let summary = match phase {
        Phase::Loading => "Connecting to the controller".to_string(),
        Phase::Live => match locality {
            Locality::Remote => "Connected to a controller on another machine".to_string(),
            _ => "Connected to the controller".to_string(),
        },
        Phase::Stale => format!(
            "Controller data is stale{}",
            age.as_ref().map(|a| format!(", last read {a}")).unwrap_or_default()
        ),
        Phase::Disconnected => {
            "Controller unavailable. Service and agent data is not current; local telemetry still updates."
                .to_string()
        }
        Phase::Error => "The controller returned an error".to_string(),
    };
    Connection {
        phase,
        summary,
        detail: inputs.controller.detail.clone(),
        controller_version: snapshot.map(|s| s.daemon.version.clone()),
        socket_label: inputs.socket_label.clone(),
        age,
        locality,
        telemetry_phase,
        read_only: inputs.read_only,
    }
}

fn telemetry_metric(sample: Option<&HostSample>, pick: impl Fn(&HostSample) -> Metric) -> Metric {
    sample
        .map(pick)
        .unwrap_or(Metric::Unavailable(Reason::AwaitingSample))
}

fn quick_view(sample: Option<&HostSample>, phase: Phase) -> QuickView {
    let stale = |m: Metric| {
        if phase == Phase::Stale {
            Metric::Unavailable(Reason::Failed)
        } else {
            m
        }
    };
    let cpu = stale(telemetry_metric(sample, |s| s.cpu_pct));
    let memory = stale(telemetry_metric(sample, |s| s.memory_pct));
    let disk = stale(telemetry_metric(sample, |s| s.disk_pct));
    let gpu = stale(telemetry_metric(sample, |s| s.gpu_pct));
    let rx = stale(telemetry_metric(sample, |s| s.net_rx_bytes_per_sec));
    let tx = stale(telemetry_metric(sample, |s| s.net_tx_bytes_per_sec));

    let memory_detail = match sample.and_then(|s| s.memory_used_bytes.zip(s.memory_total_bytes)) {
        Some((used, total)) => format!("{} of {}", format::bytes(used), format::bytes(total)),
        None => String::new(),
    };
    let disk_detail = match sample.and_then(|s| s.disk.as_ref()) {
        Some(v) => format!(
            "{} free of {}",
            format::bytes(v.available_bytes),
            format::bytes(v.total_bytes)
        ),
        None => String::new(),
    };
    let rate = |label, metric: Metric, history: Vec<Option<f64>>| {
        let peak = history.iter().flatten().copied().fold(0.0_f64, f64::max);
        let fraction = metric.value().map(|v| {
            if peak > 0.0 {
                (v / peak).clamp(0.0, 1.0)
            } else {
                0.0
            }
        });
        Rate {
            label,
            metric,
            text: format::rate(metric),
            fraction,
            history,
        }
    };
    QuickView {
        cpu: Gauge::percent("CPU", cpu, String::new()),
        memory: Gauge::percent("Memory", memory, memory_detail),
        disk: DiskGrid {
            gauge: Gauge::percent("Disk", disk, disk_detail),
            cells: crate::thresholds::segments(disk, DISK_CELLS),
        },
        download: rate(
            "Download",
            rx,
            sample.map(|s| s.rx_history.clone()).unwrap_or_default(),
        ),
        upload: rate(
            "Upload",
            tx,
            sample.map(|s| s.tx_history.clone()).unwrap_or_default(),
        ),
        gpu: Gauge::percent("GPU", gpu, String::new()),
    }
}

fn distinct_owners<'a>(services: impl Iterator<Item = &'a ServiceRecord>) -> usize {
    services
        .filter(|s| !s.state.is_terminal())
        .map(|s| s.owner_agent.as_str())
        .collect::<HashSet<_>>()
        .len()
}

fn cluster(
    inputs: &Inputs<'_>,
    snapshot: Option<&Snapshot>,
    controller_phase: Phase,
    sample: Option<&HostSample>,
    telemetry_phase: Phase,
    quick: &QuickView,
) -> ClusterView {
    let current = controller_phase.is_current();
    let mut tiles = Vec::new();

    let local_gauges = vec![
        quick.cpu.clone(),
        Gauge {
            label: "mem",
            ..quick.memory.clone()
        },
        Gauge {
            label: "gpu",
            ..quick.gpu.clone()
        },
        Gauge::percent(
            "net",
            Metric::Unavailable(Reason::NotMeasured),
            "link capacity is not measured".into(),
        ),
        Gauge {
            label: "disk",
            ..quick.disk.gauge.clone()
        },
    ];
    let local_gauges: Vec<Gauge> = local_gauges
        .into_iter()
        .map(|g| {
            if g.label == "CPU" {
                Gauge { label: "cpu", ..g }
            } else {
                g
            }
        })
        .collect();
    let judged: Vec<Metric> = local_gauges
        .iter()
        .filter(|g| g.label != "net")
        .map(|g| g.metric)
        .collect();
    let local_services = snapshot.filter(|_| current);
    tiles.push(NodeTile {
        id: "local".into(),
        name: "this machine".into(),
        is_local: true,
        state: if telemetry_phase == Phase::Loading {
            NodeState::Unmeasured
        } else {
            NodeState::from_gauges(&judged)
        },
        freshness: if telemetry_phase == Phase::Stale {
            Freshness::Stale
        } else {
            Freshness::Current
        },
        gauges: local_gauges,
        network_text: format!("rx {} tx {}", quick.download.text, quick.upload.text),
        cpu_history: sample.map(|s| s.cpu_history.clone()).unwrap_or_default(),
        services_up: local_services.map(|s| s.running_service_count()),
        services_total: local_services.map(|s| s.active_services().count()),
        agents: local_services.map(|s| distinct_owners(s.services.iter())),
        uptime: sample
            .and_then(|s| s.uptime_sec)
            .map(|u| format::duration(u as f64)),
        note: sample.map(|s| format!("{} telemetry", s.os)),
    });

    if let Some(snapshot) = snapshot {
        for device in snapshot.devices.iter().filter(|d| !d.evidence.is_self) {
            tiles.push(device_tile(device, controller_phase, inputs.now));
        }
    }

    let online: Vec<&NodeTile> = tiles
        .iter()
        .filter(|t| t.state != NodeState::Offline && t.freshness == Freshness::Current)
        .collect();
    let average = |label: &str| {
        let values: Vec<f64> = online
            .iter()
            .filter_map(|t| {
                t.gauges
                    .iter()
                    .find(|g| g.label == label)
                    .and_then(|g| g.metric.value())
            })
            .collect();
        if values.is_empty() {
            Metric::Unavailable(Reason::NotMeasured)
        } else {
            Metric::Measured(values.iter().sum::<f64>() / values.len() as f64)
        }
    };
    let agents = tiles
        .iter()
        .map(|t| t.agents)
        .try_fold(0usize, |sum, a| a.map(|a| sum + a));
    let summary = ClusterSummary {
        online: online.len(),
        total: tiles.len(),
        average_cpu: average("cpu"),
        average_memory: average("mem"),
        average_gpu: average("gpu"),
        agents,
        needs_attention: tiles
            .iter()
            .filter(|t| matches!(t.state, NodeState::Pressure | NodeState::Critical))
            .count(),
    };
    ClusterView { summary, tiles }
}

fn device_tile(device: &DeviceRecord, controller_phase: Phase, now: SystemTime) -> NodeTile {
    let m = &device.metrics;
    let health = device.health();
    let offline = health == DeviceHealth::Unreachable;
    let freshness = match controller_phase {
        Phase::Live => Freshness::Current,
        Phase::Stale | Phase::Error => Freshness::Stale,
        Phase::Loading | Phase::Disconnected => Freshness::Disconnected,
    };
    let missing = if offline {
        Reason::Offline
    } else if freshness == Freshness::Disconnected {
        Reason::Disconnected
    } else {
        Reason::NotMeasured
    };
    let ratio = |used: Option<f64>, total: Option<f64>| match (used, total) {
        (Some(u), Some(t)) if t > 0.0 => Some(u / t * 100.0),
        _ => None,
    };
    let live = |v: Option<f64>| {
        if offline || freshness == Freshness::Disconnected {
            None
        } else {
            v
        }
    };
    let cpu = Metric::from_option(live(m.cpu_pct), missing);
    let mem = Metric::from_option(live(ratio(m.mem_used_gb, m.mem_total_gb)), missing);
    let gpu = Metric::from_option(live(m.gpu_pct), missing);
    // An offline node keeps its last disk reading: disk does not change while
    // it is down, and the design labels it last-known.
    let disk = Metric::from_option(ratio(m.disk_used_gb, m.disk_total_gb), missing);
    let disk_detail = match (m.disk_used_gb, m.disk_total_gb) {
        (Some(u), Some(t)) if offline => format!("last known, {u:.0} of {t:.0} GB"),
        (Some(u), Some(t)) => format!("{u:.0} of {t:.0} GB"),
        _ => String::new(),
    };
    let gauges = vec![
        Gauge::percent("cpu", cpu, String::new()),
        Gauge::percent("mem", mem, String::new()),
        Gauge::percent("gpu", gpu, String::new()),
        Gauge::percent(
            "net",
            Metric::Unavailable(Reason::NotMeasured),
            "not reported by linked devices".into(),
        ),
        Gauge::percent("disk", disk, disk_detail),
    ];
    let judged = [cpu, mem, gpu, disk];
    let state = if offline {
        NodeState::Offline
    } else {
        NodeState::from_gauges(&judged)
    };
    let collected = m
        .collected_at
        .map(|t| format::relative(t, epoch_seconds(now)));
    let note = match (&device.remote_error, health, collected) {
        (Some(error), _, _) => Some(format!("remote read failed: {}", format::clip(error, 80))),
        (None, DeviceHealth::Unknown, _) => Some("no probe has completed".into()),
        (None, DeviceHealth::Partial, _) => Some("partially reachable".into()),
        (None, _, Some(age)) => Some(format!("metrics {age}")),
        _ => None,
    };
    let remote_known = device.remote_error.is_none() && !offline;
    NodeTile {
        id: device.id.clone(),
        name: device.name.clone(),
        is_local: false,
        state,
        freshness,
        gauges,
        network_text: format::UNAVAILABLE.into(),
        cpu_history: Vec::new(),
        services_up: remote_known.then(|| {
            device
                .remote_services
                .iter()
                .filter(|s| s.state.is_running())
                .count()
        }),
        services_total: remote_known.then(|| {
            device
                .remote_services
                .iter()
                .filter(|s| !s.state.is_terminal())
                .count()
        }),
        agents: remote_known.then(|| distinct_owners(device.remote_services.iter())),
        uptime: None,
        note,
    }
}

fn level_for_state(state: ServiceState) -> Option<Level> {
    match state {
        ServiceState::Crashed | ServiceState::Unhealthy | ServiceState::Expired => {
            Some(Level::Critical)
        }
        ServiceState::Degraded
        | ServiceState::Expiring
        | ServiceState::Starting
        | ServiceState::Stopping => Some(Level::Warning),
        ServiceState::Healthy => Some(Level::Elevated),
        _ => None,
    }
}

fn service_rows(
    snapshot: &Snapshot,
    now: f64,
    current: bool,
    read_only: bool,
    pending: &[(u64, Action)],
) -> Vec<ServiceRow> {
    let mut records: Vec<&ServiceRecord> = snapshot.services.iter().collect();
    records.sort_by_key(|s| {
        let group = if s.state.needs_attention() {
            0
        } else if s.state.is_running() {
            1
        } else {
            2
        };
        (group, s.friendly_name.to_lowercase())
    });
    records.truncate(MAX_SERVICE_ROWS);
    records
        .into_iter()
        .map(|s| service_row(s, now, current, read_only, pending))
        .collect()
}

fn service_row(
    s: &ServiceRecord,
    now: f64,
    current: bool,
    read_only: bool,
    pending: &[(u64, Action)],
) -> ServiceRow {
    let e = &s.evidence;
    let process = match e.process_exists {
        Some(true) => "process exists".to_string(),
        Some(false) => "process not found".to_string(),
        None => "process not checked".to_string(),
    };
    let listening = if !e.port_scan_ran {
        "port scan not run".to_string()
    } else if e.listening_ports.is_empty() {
        "no listening ports".to_string()
    } else {
        format!("listening {}", format::ports(&e.listening_ports))
    };
    let health = if !e.health_check_ran {
        if s.health.kind == crate::model::HealthKind::None {
            "no health check configured".to_string()
        } else {
            "health check not run yet".to_string()
        }
    } else {
        match (e.health_passed, e.health_latency_ms) {
            (Some(true), Some(ms)) => format!("health passed in {ms:.0} ms"),
            (Some(true), None) => "health passed".to_string(),
            (Some(false), _) => format!(
                "health failed{}",
                e.health_detail
                    .as_ref()
                    .map(|d| format!(": {}", format::clip(d, 60)))
                    .unwrap_or_default()
            ),
            (None, _) => "health result unavailable".to_string(),
        }
    };
    let in_flight = pending.iter().find_map(|(_, a)| match a {
        Action::Restart { service_id }
        | Action::Stop { service_id }
        | Action::Pause { service_id }
        | Action::Resume { service_id }
        | Action::Renew { service_id, .. }
            if service_id == &s.id =>
        {
            Some(format!("{} in progress", a.label()))
        }
        _ => None,
    });

    let gate = |applies: bool, not_applicable: &str| -> Control {
        if read_only {
            Control::Refused("this client is read-only".into())
        } else if !current {
            Control::Refused("controller data is not current".into())
        } else if in_flight.is_some() {
            Control::Refused("a request for this service is in progress".into())
        } else if let Some(reason) = s.signal_refusal() {
            Control::Refused(reason)
        } else if !applies {
            Control::Refused(not_applicable.into())
        } else {
            Control::Allowed
        }
    };
    let terminal = s.state.is_terminal();
    let renew = if read_only {
        Control::Refused("this client is read-only".into())
    } else if !current {
        Control::Refused("controller data is not current".into())
    } else if terminal {
        Control::Refused("service has ended".into())
    } else {
        Control::Allowed
    };
    ServiceRow {
        id: s.id.clone(),
        short_id: s.short_id().to_string(),
        name: s.friendly_name.clone(),
        owner: s.owner_agent.clone(),
        purpose: s.purpose.clone(),
        state: s.state,
        state_text: s.state.label(),
        level: level_for_state(s.state),
        pid: s.pid,
        uptime: if terminal {
            format::UNAVAILABLE.into()
        } else {
            format::duration(s.uptime_seconds(now))
        },
        restarts: s.restart_count,
        ports: format::ports(s.effective_ports()),
        cpu: Metric::from_option(s.resources.cpu_pct, Reason::AwaitingSample),
        memory: format::megabytes(s.resources.mem_mb),
        lease: if terminal {
            "ended".into()
        } else if s.lease_expires_at <= now {
            format!(
                "lease expired {}",
                format::relative(s.lease_expires_at, now)
            )
        } else {
            format!("lease ends {}", format::relative(s.lease_expires_at, now))
        },
        process,
        listening,
        health,
        claimed: s.claimed,
        restart: gate(true, ""),
        stop: gate(!terminal, "service has ended"),
        pause: gate(
            s.state.is_running() && s.state != ServiceState::Paused,
            "only a running service can pause",
        ),
        resume: gate(s.state == ServiceState::Paused, "service is not paused"),
        renew,
        logs: Control::Allowed,
        in_flight,
    }
}

fn process_view(
    snapshot: Option<&Snapshot>,
    sample: Option<&HostSample>,
    phase: Phase,
    locality: Locality,
) -> ProcessView {
    let Some(sample) = sample else {
        return ProcessView {
            phase,
            lines: Vec::new(),
            total_processes: None,
            note: None,
        };
    };
    let by_pid: HashMap<u32, &ProcessRow> = sample.processes.iter().map(|p| (p.pid, p)).collect();
    let mut children: HashMap<u32, Vec<&ProcessRow>> = HashMap::new();
    for p in &sample.processes {
        if let Some(parent) = p.ppid {
            children.entry(parent).or_default().push(p);
        }
    }
    for list in children.values_mut() {
        list.sort_by(|a, b| {
            b.cpu_pct
                .value()
                .unwrap_or(0.0)
                .total_cmp(&a.cpu_pct.value().unwrap_or(0.0))
        });
    }

    let mut lines = Vec::new();
    let mut shown: HashSet<u32> = HashSet::new();
    let mut note = None;

    // Roots come from the controller only when it supervises this machine;
    // a remote controller's pids name processes on another host.
    let mut roots: Vec<(u32, String, ProcessRole, Option<String>)> = Vec::new();
    match (snapshot, locality) {
        (Some(s), Locality::Local) => {
            roots.push((
                s.daemon.pid.max(0) as u32,
                "fleetd".into(),
                ProcessRole::Controller,
                Some("controller".into()),
            ));
            for svc in s.active_services() {
                if let Some(pid) = svc.pid.filter(|p| *p > 0) {
                    let tag = svc
                        .state
                        .needs_attention()
                        .then(|| svc.state.label().to_string());
                    roots.push((
                        pid as u32,
                        svc.friendly_name.clone(),
                        ProcessRole::Service,
                        tag,
                    ));
                }
            }
            for session in &s.sessions {
                if session.pid > 0 {
                    roots.push((
                        session.pid as u32,
                        session.tool.clone(),
                        ProcessRole::Agent,
                        Some("agent".into()),
                    ));
                }
            }
        }
        (Some(_), Locality::Remote) => {
            note = Some(
                "The controller runs on another machine, so its services are not shown in this machine's process tree."
                    .into(),
            );
        }
        _ => {}
    }

    for (pid, label, role, tag) in roots {
        if lines.len() >= MAX_PROCESS_LINES || shown.contains(&pid) {
            continue;
        }
        match by_pid.get(&pid) {
            Some(row) => {
                lines.push(ProcessLine {
                    depth: 0,
                    pid: Some(pid),
                    name: label,
                    role,
                    cpu: row.cpu_pct,
                    memory: format::bytes(row.rss_bytes),
                    tag,
                    last_child: false,
                });
                shown.insert(pid);
                descend(pid, 1, &children, &mut lines, &mut shown);
            }
            None => lines.push(ProcessLine {
                depth: 0,
                pid: Some(pid),
                name: label,
                role,
                cpu: Metric::Unavailable(Reason::Failed),
                memory: format::UNAVAILABLE.into(),
                tag: Some("not in this machine's process table".into()),
                last_child: false,
            }),
        }
    }

    let others: Vec<&ProcessRow> = sample
        .processes
        .iter()
        .filter(|p| !shown.contains(&p.pid))
        .take(OTHER_PROCESSES)
        .collect();
    for p in others {
        if lines.len() >= MAX_PROCESS_LINES {
            break;
        }
        lines.push(ProcessLine {
            depth: 0,
            pid: Some(p.pid),
            name: p.name.clone(),
            role: ProcessRole::Other,
            cpu: p.cpu_pct,
            memory: format::bytes(p.rss_bytes),
            tag: None,
            last_child: false,
        });
    }
    ProcessView {
        phase,
        lines,
        total_processes: Some(sample.process_count),
        note,
    }
}

fn descend(
    pid: u32,
    depth: usize,
    children: &HashMap<u32, Vec<&ProcessRow>>,
    lines: &mut Vec<ProcessLine>,
    shown: &mut HashSet<u32>,
) {
    if depth > TREE_DEPTH {
        return;
    }
    let Some(kids) = children.get(&pid) else {
        return;
    };
    let visible: Vec<&&ProcessRow> = kids
        .iter()
        .filter(|k| !shown.contains(&k.pid))
        .take(TREE_CHILDREN)
        .collect();
    let hidden = kids.len().saturating_sub(visible.len());
    let count = visible.len();
    for (i, kid) in visible.into_iter().enumerate() {
        if lines.len() >= MAX_PROCESS_LINES {
            return;
        }
        shown.insert(kid.pid);
        lines.push(ProcessLine {
            depth,
            pid: Some(kid.pid),
            name: kid.name.clone(),
            role: ProcessRole::Other,
            cpu: kid.cpu_pct,
            memory: format::bytes(kid.rss_bytes),
            tag: None,
            last_child: i + 1 == count && hidden == 0,
        });
        descend(kid.pid, depth + 1, children, lines, shown);
    }
    if hidden > 0 && lines.len() < MAX_PROCESS_LINES {
        lines.push(ProcessLine {
            depth,
            pid: None,
            name: format!("{hidden} more"),
            role: ProcessRole::Other,
            cpu: Metric::Unavailable(Reason::NotMeasured),
            memory: String::new(),
            tag: None,
            last_child: true,
        });
    }
}

fn clock(epoch: f64) -> String {
    let seconds_of_day = (epoch.max(0.0) as u64) % 86_400;
    // UTC wall time. A local time zone needs a database this crate does not
    // carry; the clients label the column so it is not mistaken for local.
    format!(
        "{:02}:{:02}",
        seconds_of_day / 3_600,
        (seconds_of_day % 3_600) / 60
    )
}

fn agents_view(
    snapshot: Option<&Snapshot>,
    now: f64,
    current: bool,
    read_only: bool,
    pending: &[(u64, Action)],
) -> AgentsView {
    let Some(s) = snapshot else {
        return AgentsView {
            rows: Vec::new(),
            transcript: Vec::new(),
            open_questions: 0,
        };
    };
    let mut rows = Vec::new();
    for session in &s.sessions {
        rows.push(AgentRow {
            name: session.tool.clone(),
            target: session
                .session_name
                .clone()
                .or_else(|| session.project_name().map(str::to_string))
                .unwrap_or_else(|| format::UNAVAILABLE.into()),
            state: match (&session.preview_turn, session.preview_at) {
                (Some(turn), Some(at)) => format!("{} {}", turn.label(), format::relative(at, now)),
                _ => "running, no transcript published".into(),
            },
            level: None,
            runtime: session
                .started_at
                .map(|t| format::duration(now - t))
                .unwrap_or_else(|| format::UNAVAILABLE.into()),
            awaiting_reply: 0,
        });
    }
    let mut by_owner: BTreeMap<&str, (usize, usize, f64)> = BTreeMap::new();
    for svc in s.active_services() {
        let entry = by_owner
            .entry(svc.owner_agent.as_str())
            .or_insert((0, 0, f64::MAX));
        entry.0 += 1;
        if svc.state.needs_attention() {
            entry.1 += 1;
        }
        entry.2 = entry.2.min(svc.started_at);
    }
    let mut waiting: HashMap<&str, usize> = HashMap::new();
    for m in s.awaiting_reply() {
        *waiting.entry(m.agent.as_str()).or_default() += 1;
        by_owner.entry(m.agent.as_str()).or_insert((0, 0, f64::MAX));
    }
    for (owner, (services, troubled, oldest)) in by_owner {
        let awaiting = waiting.get(owner).copied().unwrap_or(0);
        rows.push(AgentRow {
            name: owner.to_string(),
            target: if services == 1 {
                "1 service".into()
            } else {
                format!("{services} services")
            },
            state: if awaiting > 0 {
                "waiting for approval".into()
            } else if troubled > 0 {
                format!("{troubled} need attention")
            } else if services > 0 {
                "working".into()
            } else {
                "idle".into()
            },
            level: if awaiting > 0 || troubled > 0 {
                Some(Level::Warning)
            } else {
                None
            },
            runtime: if oldest < f64::MAX {
                format::duration(now - oldest)
            } else {
                format::UNAVAILABLE.into()
            },
            awaiting_reply: awaiting,
        });
    }
    rows.sort_by(|a, b| {
        b.awaiting_reply
            .cmp(&a.awaiting_reply)
            .then(a.name.cmp(&b.name))
    });

    let mut messages: Vec<&AgentMessage> = s.messages.iter().collect();
    messages.sort_by(|a, b| a.created_at.total_cmp(&b.created_at));
    let skip = messages.len().saturating_sub(MAX_TRANSCRIPT_LINES);
    let transcript = messages
        .into_iter()
        .skip(skip)
        .map(|m| {
            let in_flight = pending
                .iter()
                .any(|(_, a)| matches!(a, Action::Reply { message_id, .. } if *message_id == m.id));
            TranscriptLine {
                time: clock(m.created_at),
                agent: m.agent.clone(),
                verb: match (m.kind, m.is_awaiting_reply()) {
                    (_, true) => "ask".into(),
                    (MessageKind::Question, false) => "asked".into(),
                    (MessageKind::Problem, _) => "problem".into(),
                    _ => "status".into(),
                },
                text: match &m.reply {
                    Some(reply) => format!("{}  answered: {}", m.body, format::clip(reply, 60)),
                    None => m.body.clone(),
                },
                question: m.is_awaiting_reply().then(|| Question {
                    message_id: m.id,
                    reply: if read_only {
                        Control::Refused("this client is read-only".into())
                    } else if !current {
                        Control::Refused("controller data is not current".into())
                    } else if in_flight {
                        Control::Refused("reply in progress".into())
                    } else {
                        Control::Allowed
                    },
                    in_flight,
                }),
            }
        })
        .collect();
    AgentsView {
        rows,
        transcript,
        open_questions: s.awaiting_reply().count(),
    }
}

fn storage_view(sample: Option<&HostSample>, phase: Phase) -> StorageView {
    let volumes = sample
        .map(|s| {
            s.volumes
                .iter()
                .map(|v: &Volume| VolumeRow {
                    mount: v.mount.clone(),
                    filesystem: v.filesystem.clone(),
                    used: format::bytes(v.used_bytes()),
                    total: format::bytes(v.total_bytes),
                    free: format::bytes(v.available_bytes),
                    gauge: Gauge::percent("used", v.used_percent(), String::new()),
                })
                .collect()
        })
        .unwrap_or_default();
    StorageView {
        phase,
        volumes,
        largest_paths: Err(
            "per-path scanning runs in the macOS app only; the Rust clients show volumes".into(),
        ),
    }
}

fn attention_rows(
    snapshot: Option<&Snapshot>,
    current: bool,
    quick: &QuickView,
    storage: &StorageView,
    read_only: bool,
) -> Vec<AttentionRow> {
    let mut rows = Vec::new();
    if let Some(s) = snapshot.filter(|_| current) {
        for item in &s.attention {
            let service = item
                .service_id
                .as_ref()
                .and_then(|id| s.services.iter().find(|r| &r.id == id));
            let available = match service {
                Some(r) if r.claimed => {
                    "visibility only: claimed processes are not signalled by the controller".into()
                }
                Some(_) if read_only => "read-only client: inspect logs and events".into(),
                Some(_) => "restart, stop, renew or read logs through the controller".into(),
                None => "inspect only".into(),
            };
            let agent_commands = match &item.service_id {
                Some(id) => {
                    let short: String = id.chars().take(8).collect();
                    vec![
                        format!("fleetctl show {short}"),
                        format!("fleetctl logs {short}"),
                        format!("fleetctl events {short}"),
                    ]
                }
                None => vec!["fleetctl list".into(), "fleetctl doctor".into()],
            };
            rows.push(AttentionRow {
                id: item.id.clone(),
                severity: match item.severity {
                    AttentionSeverity::Critical => Severity::Critical,
                    _ => Severity::Warning,
                },
                title: item.title.clone(),
                detail: item.detail.clone(),
                source: "controller",
                service_id: item.service_id.clone(),
                message_id: None,
                available,
                agent_commands,
            });
        }
        for m in s.awaiting_reply() {
            rows.push(AttentionRow {
                id: format!("message-{}", m.id),
                severity: Severity::Warning,
                title: format!("{} is waiting for an answer", m.agent),
                detail: format::clip(&m.body, 120),
                source: "controller",
                service_id: m.service_id.clone(),
                message_id: Some(m.id),
                available: if read_only {
                    "read-only client: answer with fleetctl reply".into()
                } else {
                    "approve or deny from the Agents view".into()
                },
                agent_commands: vec![format!("fleetctl inbox --agent {}", m.agent)],
            });
        }
        for u in s.unmanaged.iter().take(20) {
            rows.push(AttentionRow {
                id: format!("unmanaged-{}", u.id),
                severity: Severity::Info,
                title: format!("unmanaged process {} ({})", u.command, u.pid),
                detail: u.reason.label().into(),
                source: "controller",
                service_id: None,
                message_id: None,
                available: "claim it for visibility with fleetctl claim, or ignore it".into(),
                agent_commands: vec![format!("fleetctl claim {}", u.pid)],
            });
        }
    }
    for gauge in [&quick.memory, &quick.disk.gauge] {
        if let Some(level @ (Level::Warning | Level::Critical)) = gauge.level {
            rows.push(AttentionRow {
                id: format!("local-{}", gauge.label.to_lowercase()),
                severity: if level == Level::Critical {
                    Severity::Critical
                } else {
                    Severity::Warning
                },
                title: format!(
                    "{} at {} on this machine",
                    gauge.label.to_lowercase(),
                    gauge.text
                ),
                detail: gauge.detail.clone(),
                source: "local telemetry",
                service_id: None,
                message_id: None,
                available: "inspect the Processes and Storage views".into(),
                agent_commands: Vec::new(),
            });
        }
    }
    for v in &storage.volumes {
        if v.mount == "/" || v.mount == "/System/Volumes/Data" {
            continue;
        }
        if let Some(Level::Critical) = v.gauge.level {
            rows.push(AttentionRow {
                id: format!("local-volume-{}", v.mount),
                severity: Severity::Critical,
                title: format!("volume {} at {}", v.mount, v.gauge.text),
                detail: format!("{} free of {}", v.free, v.total),
                source: "local telemetry",
                service_id: None,
                message_id: None,
                available: "inspect the Storage view".into(),
                agent_commands: Vec::new(),
            });
        }
    }
    rows.sort_by_key(|r| r.severity);
    rows.truncate(MAX_ATTENTION_ROWS);
    rows
}

fn activity(pending: &[(u64, Action)], outcomes: &[ActionOutcome]) -> Vec<ActivityLine> {
    let mut lines: Vec<ActivityLine> = outcomes
        .iter()
        .rev()
        .take(8)
        .map(|o| match &o.result {
            Ok(ActionPayload::Done) => ActivityLine {
                text: format!("{} accepted by the controller", o.action.label()),
                ok: Some(true),
            },
            Ok(ActionPayload::Logs(chunk)) => ActivityLine {
                text: format!(
                    "read {} of std{} log",
                    format::bytes(chunk.bytes.max(0) as u64),
                    chunk.stream
                ),
                ok: Some(true),
            },
            Ok(ActionPayload::Events(events)) => ActivityLine {
                text: format!("read {} events", events.len()),
                ok: Some(true),
            },
            Err(error) => ActivityLine {
                text: format!("{} failed: {}", o.action.label(), format::clip(error, 120)),
                ok: Some(false),
            },
        })
        .collect();
    for (_, action) in pending {
        lines.insert(
            0,
            ActivityLine {
                text: format!("{} in progress", action.label()),
                ok: None,
            },
        );
    }
    lines
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fixtures;

    fn build(
        controller: &Feed<Snapshot>,
        telemetry: &Feed<HostSample>,
        now: SystemTime,
    ) -> Dashboard {
        Dashboard::build(&Inputs {
            controller,
            controller_stale_after: Duration::from_secs(11),
            telemetry,
            telemetry_stale_after: Duration::from_secs(6),
            pending: &[],
            outcomes: &[],
            read_only: false,
            socket_label: "~/fleetd.sock".into(),
            assume_remote_controller: false,
            now,
        })
    }

    #[test]
    fn disconnected_controller_shows_no_current_service_count() {
        let now = fixtures::now();
        let controller = fixtures::controller_feed(fixtures::Scenario::Disconnected, now);
        let telemetry = fixtures::telemetry_feed(fixtures::Scenario::Healthy, now);
        let dash = build(&controller, &telemetry, now);
        assert_eq!(dash.connection.phase, Phase::Disconnected);
        assert_eq!(dash.header.services_running, None);
        assert_eq!(dash.header.subtitle, "services disconnected");
        assert!(dash.services.iter().all(|r| !r.restart.is_allowed()));
        assert!(
            dash.quick.cpu.metric.is_measured(),
            "local telemetry is independent of the controller"
        );
    }

    #[test]
    fn healthy_fixture_counts_running_services() {
        let now = fixtures::now();
        let controller = fixtures::controller_feed(fixtures::Scenario::Healthy, now);
        let telemetry = fixtures::telemetry_feed(fixtures::Scenario::Healthy, now);
        let dash = build(&controller, &telemetry, now);
        assert_eq!(dash.connection.phase, Phase::Live);
        assert_eq!(dash.header.services_running, Some(5));
        assert_eq!(dash.header.subtitle, "5 services running");
        let claimed = dash
            .services
            .iter()
            .find(|r| r.claimed)
            .expect("fixture has a claimed service");
        assert!(matches!(&claimed.stop, Control::Refused(reason) if reason.contains("claimed")));
        let healthy = dash
            .services
            .iter()
            .find(|r| r.state == ServiceState::Healthy)
            .unwrap();
        assert!(healthy.restart.is_allowed());
        assert!(healthy.health.starts_with("health passed"));
    }

    #[test]
    fn stale_controller_disables_controls_but_keeps_rows() {
        let now = fixtures::now();
        let controller = fixtures::controller_feed(fixtures::Scenario::Stale, now);
        let telemetry = fixtures::telemetry_feed(fixtures::Scenario::Healthy, now);
        let dash = build(&controller, &telemetry, now);
        assert_eq!(dash.connection.phase, Phase::Stale);
        assert!(!dash.services.is_empty());
        assert!(dash.services.iter().all(|r| !r.stop.is_allowed()));
    }

    #[test]
    fn offline_node_keeps_last_known_disk_only() {
        let now = fixtures::now();
        let controller = fixtures::controller_feed(fixtures::Scenario::Critical, now);
        let telemetry = fixtures::telemetry_feed(fixtures::Scenario::Critical, now);
        let dash = build(&controller, &telemetry, now);
        let offline = dash
            .cluster
            .tiles
            .iter()
            .find(|t| t.state == NodeState::Offline)
            .expect("offline node");
        let disk = offline.gauges.iter().find(|g| g.label == "disk").unwrap();
        assert!(disk.metric.is_measured());
        assert!(disk.detail.starts_with("last known"));
        for gauge in offline.gauges.iter().filter(|g| g.label != "disk") {
            assert!(
                !gauge.metric.is_measured(),
                "{} should be unavailable",
                gauge.label
            );
        }
        assert!(dash.cluster.summary.online < dash.cluster.summary.total);
        assert!(dash
            .cluster
            .tiles
            .iter()
            .any(|t| t.state == NodeState::Critical));
        assert!(dash.attention.first().map(|r| r.severity) == Some(Severity::Critical));
    }

    #[test]
    fn remote_controller_pids_are_not_joined_with_local_processes() {
        let now = fixtures::now();
        let controller = fixtures::controller_feed(fixtures::Scenario::Healthy, now);
        let mut telemetry = fixtures::telemetry_feed(fixtures::Scenario::Healthy, now);
        let mut sample = (*telemetry.value.take().unwrap()).clone();
        sample.processes.retain(|p| !p.name.contains("fleetd"));
        telemetry.value = Some(std::sync::Arc::new(sample));
        let dash = build(&controller, &telemetry, now);
        assert_eq!(dash.connection.locality, Locality::Remote);
        assert!(dash
            .processes
            .lines
            .iter()
            .all(|l| l.role != ProcessRole::Service));
        assert!(dash.processes.note.is_some());
    }

    #[test]
    fn open_question_offers_reply_until_one_is_in_flight() {
        let now = fixtures::now();
        let controller = fixtures::controller_feed(fixtures::Scenario::Healthy, now);
        let telemetry = fixtures::telemetry_feed(fixtures::Scenario::Healthy, now);
        let dash = build(&controller, &telemetry, now);
        let question = dash
            .agents
            .transcript
            .iter()
            .find_map(|l| l.question.clone())
            .expect("fixture asks");
        assert!(question.reply.is_allowed());

        let pending = [(
            1,
            Action::Reply {
                message_id: question.message_id,
                body: APPROVE_REPLY.into(),
            },
        )];
        let dash = Dashboard::build(&Inputs {
            controller: &controller,
            controller_stale_after: Duration::from_secs(11),
            telemetry: &telemetry,
            telemetry_stale_after: Duration::from_secs(6),
            pending: &pending,
            outcomes: &[],
            read_only: false,
            socket_label: String::new(),
            assume_remote_controller: false,
            now,
        });
        let question = dash
            .agents
            .transcript
            .iter()
            .find_map(|l| l.question.clone())
            .unwrap();
        assert!(question.in_flight);
        assert!(!question.reply.is_allowed());
        assert_eq!(dash.activity.first().map(|a| a.ok), Some(None));
    }

    #[test]
    fn loading_shows_no_numbers() {
        let now = fixtures::now();
        let dash = build(&Feed::default(), &Feed::default(), now);
        assert_eq!(dash.connection.phase, Phase::Loading);
        assert_eq!(dash.quick.cpu.text, "--");
        assert_eq!(dash.cluster.tiles[0].state, NodeState::Unmeasured);
        assert!(dash.services.is_empty());
    }

    #[test]
    fn lists_are_bounded() {
        let now = fixtures::now();
        let controller = fixtures::controller_feed(fixtures::Scenario::Flood, now);
        let telemetry = fixtures::telemetry_feed(fixtures::Scenario::Flood, now);
        let dash = build(&controller, &telemetry, now);
        assert!(dash.services.len() <= MAX_SERVICE_ROWS);
        assert!(dash.processes.lines.len() <= MAX_PROCESS_LINES);
        assert!(dash.agents.transcript.len() <= MAX_TRANSCRIPT_LINES);
        assert!(dash.attention.len() <= MAX_ATTENTION_ROWS);
    }
}
