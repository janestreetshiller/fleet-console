//! The controller snapshot, typed.
//!
//! `fleet-proto` keeps the snapshot as opaque JSON so a half-modelled record
//! cannot silently drop fields on the conformance path. The clients need typed
//! access, so this module models exactly the fields they render, decoded the way
//! Swift's `Codec` writes them: dates are epoch seconds, absent optionals are
//! `None`, and keys keep Swift's spelling (`serviceID`, `memMB`, `leaseTTLSec`).
//! Unknown enum values decode to `Unknown` so a newer controller does not take
//! the whole client down; a missing required field is a decode error that the
//! client reports, never a default.

use serde::Deserialize;

pub use fleet_proto::DaemonInfo;

#[derive(Debug, Clone, Deserialize)]
pub struct Snapshot {
    #[serde(rename = "generatedAt")]
    pub generated_at: f64,
    pub daemon: DaemonInfo,
    #[serde(default)]
    pub services: Vec<ServiceRecord>,
    #[serde(default)]
    pub unmanaged: Vec<UnmanagedProcess>,
    #[serde(default)]
    pub devices: Vec<DeviceRecord>,
    #[serde(default)]
    pub attention: Vec<AttentionItem>,
    #[serde(rename = "recentEvents", default)]
    pub recent_events: Vec<ServiceEvent>,
    #[serde(default)]
    pub messages: Vec<AgentMessage>,
    #[serde(default)]
    pub external: Vec<ExternalService>,
    #[serde(default)]
    pub sessions: Vec<AgentSession>,
}

impl Snapshot {
    /// Everything not finished, including an expired lease still being reported.
    pub fn active_services(&self) -> impl Iterator<Item = &ServiceRecord> {
        self.services.iter().filter(|s| !s.state.is_terminal())
    }

    /// Actually up. This is what a count worded "running" shows, matching
    /// `Snapshot.runningServices` in Swift.
    pub fn running_service_count(&self) -> usize {
        self.services
            .iter()
            .filter(|s| s.state.is_running())
            .count()
    }

    pub fn awaiting_reply(&self) -> impl Iterator<Item = &AgentMessage> {
        self.messages.iter().filter(|m| m.is_awaiting_reply())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ServiceState {
    Starting,
    Running,
    Healthy,
    Degraded,
    Unhealthy,
    Paused,
    Expiring,
    Expired,
    Stopping,
    Stopped,
    Crashed,
    #[serde(other)]
    Unknown,
}

impl ServiceState {
    pub fn is_terminal(self) -> bool {
        matches!(self, Self::Stopped | Self::Crashed)
    }

    pub fn is_running(self) -> bool {
        matches!(
            self,
            Self::Starting
                | Self::Running
                | Self::Healthy
                | Self::Degraded
                | Self::Unhealthy
                | Self::Paused
                | Self::Expiring
        )
    }

    pub fn needs_attention(self) -> bool {
        matches!(
            self,
            Self::Unhealthy | Self::Crashed | Self::Expired | Self::Degraded
        )
    }

    /// The word a row shows. `running` without a health check is unverified,
    /// which is what the Swift app calls it too.
    pub fn label(self) -> &'static str {
        match self {
            Self::Starting => "starting",
            Self::Running => "running, unverified",
            Self::Healthy => "healthy",
            Self::Degraded => "degraded",
            Self::Unhealthy => "unhealthy",
            Self::Paused => "paused",
            Self::Expiring => "lease expiring",
            Self::Expired => "lease expired",
            Self::Stopping => "stopping",
            Self::Stopped => "stopped",
            Self::Crashed => "crashed",
            Self::Unknown => "unknown state",
        }
    }
}

/// Four separate facts. Never collapse them into one boolean.
#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
pub struct Evidence {
    #[serde(rename = "processExists", default)]
    pub process_exists: Option<bool>,
    #[serde(rename = "listeningPorts", default)]
    pub listening_ports: Vec<i64>,
    #[serde(rename = "portScanRan", default)]
    pub port_scan_ran: bool,
    #[serde(rename = "healthCheckRan", default)]
    pub health_check_ran: bool,
    #[serde(rename = "healthPassed", default)]
    pub health_passed: Option<bool>,
    #[serde(rename = "healthDetail", default)]
    pub health_detail: Option<String>,
    #[serde(rename = "healthLatencyMs", default)]
    pub health_latency_ms: Option<f64>,
    #[serde(rename = "checkedAt", default)]
    pub checked_at: Option<f64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum HealthKind {
    #[default]
    None,
    Tcp,
    Http,
    #[serde(other)]
    Unknown,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
pub struct HealthSpec {
    #[serde(default)]
    pub kind: HealthKind,
    #[serde(default)]
    pub target: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
pub struct ResourceSample {
    #[serde(rename = "cpuPct", default)]
    pub cpu_pct: Option<f64>,
    #[serde(rename = "memMB", default)]
    pub mem_mb: Option<f64>,
    #[serde(rename = "processCount", default)]
    pub process_count: i64,
    #[serde(rename = "sampledAt", default)]
    pub sampled_at: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct ServiceRecord {
    pub id: String,
    #[serde(rename = "friendlyName")]
    pub friendly_name: String,
    #[serde(rename = "ownerAgent")]
    pub owner_agent: String,
    #[serde(default)]
    pub purpose: String,
    #[serde(default)]
    pub command: Vec<String>,
    #[serde(default)]
    pub cwd: String,
    #[serde(default)]
    pub pid: Option<i32>,
    #[serde(default)]
    pub pgid: Option<i32>,
    #[serde(rename = "declaredPorts", default)]
    pub declared_ports: Vec<i64>,
    #[serde(rename = "startedAt")]
    pub started_at: f64,
    #[serde(rename = "leaseExpiresAt")]
    pub lease_expires_at: f64,
    #[serde(rename = "leaseTTLSec")]
    pub lease_ttl_sec: f64,
    pub state: ServiceState,
    #[serde(default)]
    pub health: HealthSpec,
    #[serde(default)]
    pub evidence: Evidence,
    #[serde(default)]
    pub resources: ResourceSample,
    #[serde(rename = "restartCount", default)]
    pub restart_count: i64,
    #[serde(rename = "lastExitCode", default)]
    pub last_exit_code: Option<i32>,
    #[serde(rename = "updatedAt", default)]
    pub updated_at: Option<f64>,
    #[serde(rename = "cpuHistory", default)]
    pub cpu_history: Vec<f64>,
    #[serde(rename = "memHistory", default)]
    pub mem_history: Vec<f64>,
    #[serde(rename = "budgetBreaches", default)]
    pub budget_breaches: Vec<String>,
    #[serde(default)]
    pub claimed: bool,
    #[serde(rename = "pausedAt", default)]
    pub paused_at: Option<f64>,
}

impl ServiceRecord {
    pub fn short_id(&self) -> &str {
        let end = self
            .id
            .char_indices()
            .nth(8)
            .map(|(i, _)| i)
            .unwrap_or(self.id.len());
        &self.id[..end]
    }

    /// Observed listeners when a scan found any, otherwise what was declared.
    pub fn effective_ports(&self) -> &[i64] {
        if self.evidence.listening_ports.is_empty() {
            &self.declared_ports
        } else {
            &self.evidence.listening_ports
        }
    }

    /// A claimed process is visible, not signallable. The controller refuses
    /// stop, restart, pause and kill for it; the clients disable those controls
    /// with the same reason instead of sending a request that will fail.
    pub fn signal_refusal(&self) -> Option<String> {
        self.claimed.then(|| {
            format!(
                "{} was claimed, not launched. The controller does not signal processes it did not start.",
                self.friendly_name
            )
        })
    }

    pub fn uptime_seconds(&self, now: f64) -> f64 {
        let end = if self.state.is_terminal() {
            self.updated_at.unwrap_or(now)
        } else {
            now
        };
        (end - self.started_at).max(0.0)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum AttentionSeverity {
    Critical,
    Warning,
    #[serde(other)]
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct AttentionItem {
    pub id: String,
    pub severity: AttentionSeverity,
    pub title: String,
    #[serde(default)]
    pub detail: String,
    #[serde(rename = "serviceID", default)]
    pub service_id: Option<String>,
    #[serde(rename = "unmanagedID", default)]
    pub unmanaged_id: Option<String>,
    #[serde(default)]
    pub since: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct ServiceEvent {
    pub seq: i64,
    #[serde(rename = "serviceID", default)]
    pub service_id: Option<String>,
    #[serde(rename = "serviceName", default)]
    pub service_name: Option<String>,
    pub ts: f64,
    /// Kept as the raw Swift case name; the clients show it, nothing branches on it.
    pub kind: String,
    #[serde(default)]
    pub detail: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum MessageKind {
    Status,
    Question,
    Problem,
    #[serde(other)]
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct AgentMessage {
    pub id: i64,
    pub agent: String,
    #[serde(rename = "serviceID", default)]
    pub service_id: Option<String>,
    #[serde(rename = "serviceName", default)]
    pub service_name: Option<String>,
    pub kind: MessageKind,
    pub body: String,
    #[serde(rename = "createdAt")]
    pub created_at: f64,
    #[serde(rename = "needsReply", default)]
    pub needs_reply: bool,
    #[serde(default)]
    pub reply: Option<String>,
    #[serde(rename = "repliedAt", default)]
    pub replied_at: Option<f64>,
    #[serde(rename = "seenAt", default)]
    pub seen_at: Option<f64>,
}

impl AgentMessage {
    pub fn is_awaiting_reply(&self) -> bool {
        self.needs_reply && self.reply.is_none()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum AgentTurn {
    Assistant,
    User,
    Tool,
    #[serde(other)]
    Unknown,
}

impl AgentTurn {
    pub fn label(self) -> &'static str {
        match self {
            Self::Assistant => "said",
            Self::User => "asked",
            Self::Tool => "ran",
            Self::Unknown => "wrote",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct AgentSession {
    pub id: String,
    pub tool: String,
    pub pid: i32,
    #[serde(default)]
    pub project: Option<String>,
    #[serde(rename = "startedAt", default)]
    pub started_at: Option<f64>,
    #[serde(rename = "cpuPct", default)]
    pub cpu_pct: Option<f64>,
    #[serde(rename = "memMB", default)]
    pub mem_mb: Option<f64>,
    #[serde(rename = "sessionName", default)]
    pub session_name: Option<String>,
    #[serde(default)]
    pub preview: Option<String>,
    #[serde(rename = "previewTurn", default)]
    pub preview_turn: Option<AgentTurn>,
    #[serde(rename = "previewAt", default)]
    pub preview_at: Option<f64>,
}

impl AgentSession {
    /// The project folder's last component, never the full path: the full
    /// path carries a home directory and does not belong on screen captures.
    pub fn project_name(&self) -> Option<&str> {
        self.project
            .as_deref()
            .map(|p| p.trim_end_matches('/').rsplit('/').next().unwrap_or(p))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum UnmanagedReason {
    ListenerNotInRegistry,
    DevServerShape,
    EscapedProcessGroup,
    #[serde(other)]
    Unknown,
}

impl UnmanagedReason {
    pub fn label(self) -> &'static str {
        match self {
            Self::ListenerNotInRegistry => "listening port with no registry record",
            Self::DevServerShape => "dev-server-shaped process, not launched by the controller",
            Self::EscapedProcessGroup => "port still held after its managed group exited",
            Self::Unknown => "unmanaged process",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct UnmanagedProcess {
    pub id: String,
    pub pid: i32,
    pub command: String,
    #[serde(default)]
    pub ports: Vec<i64>,
    pub reason: UnmanagedReason,
    #[serde(rename = "firstSeen", default)]
    pub first_seen: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct ExternalService {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub running: bool,
    #[serde(default)]
    pub pid: Option<i32>,
    #[serde(default)]
    pub ports: Vec<i64>,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
pub struct HostMetrics {
    #[serde(rename = "cpuPct", default)]
    pub cpu_pct: Option<f64>,
    #[serde(rename = "memUsedGB", default)]
    pub mem_used_gb: Option<f64>,
    #[serde(rename = "memTotalGB", default)]
    pub mem_total_gb: Option<f64>,
    #[serde(rename = "diskUsedGB", default)]
    pub disk_used_gb: Option<f64>,
    #[serde(rename = "diskTotalGB", default)]
    pub disk_total_gb: Option<f64>,
    #[serde(rename = "gpuPct", default)]
    pub gpu_pct: Option<f64>,
    #[serde(rename = "collectedAt", default)]
    pub collected_at: Option<f64>,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
pub struct DeviceEvidence {
    #[serde(rename = "icmpOK", default)]
    pub icmp_ok: Option<bool>,
    #[serde(rename = "tcpOK", default)]
    pub tcp_ok: Option<bool>,
    #[serde(rename = "tailscaleOnline", default)]
    pub tailscale_online: Option<bool>,
    #[serde(rename = "checkedAt", default)]
    pub checked_at: Option<f64>,
    #[serde(rename = "isSelf", default)]
    pub is_self: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeviceHealth {
    Reachable,
    Partial,
    Unreachable,
    Unknown,
}

/// A linked device. Host and address fields exist on the wire; they are not
/// modelled because neither client displays them.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct DeviceRecord {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub model: String,
    #[serde(default)]
    pub evidence: DeviceEvidence,
    #[serde(rename = "lastReachableAt", default)]
    pub last_reachable_at: Option<f64>,
    #[serde(rename = "remoteServices", default)]
    pub remote_services: Vec<ServiceRecord>,
    #[serde(rename = "remoteError", default)]
    pub remote_error: Option<String>,
    #[serde(default)]
    pub metrics: HostMetrics,
}

impl DeviceRecord {
    /// Same rule as `DeviceRecord.health` in Swift: reachability is claimed only
    /// when a probe succeeded, and no completed probe is unknown, not down.
    pub fn health(&self) -> DeviceHealth {
        if self.evidence.is_self {
            return DeviceHealth::Reachable;
        }
        let e = &self.evidence;
        let results: Vec<bool> = [e.icmp_ok, e.tcp_ok, e.tailscale_online]
            .into_iter()
            .flatten()
            .collect();
        if results.is_empty() {
            DeviceHealth::Unknown
        } else if results.iter().all(|r| *r) {
            DeviceHealth::Reachable
        } else if results.iter().any(|r| *r) {
            DeviceHealth::Partial
        } else {
            DeviceHealth::Unreachable
        }
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct LogChunk {
    #[serde(rename = "serviceID")]
    pub service_id: String,
    pub stream: String,
    #[serde(default)]
    pub bytes: i64,
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub truncated: bool,
}

/// Decode the opaque snapshot `fleet-proto` returns.
pub fn decode_snapshot(value: serde_json::Value) -> Result<Snapshot, String> {
    serde_json::from_value(value).map_err(|e| format!("snapshot did not decode: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn swift_spellings_decode() {
        let json = serde_json::json!({
            "id": "0123456789abcdef", "friendlyName": "api", "ownerAgent": "agent-a",
            "startedAt": 1_800_000_000.0, "leaseExpiresAt": 1_800_003_600.0,
            "leaseTTLSec": 3600.0, "state": "healthy",
            "resources": {"cpuPct": 4.5, "memMB": 120.0, "processCount": 2},
            "evidence": {"processExists": true, "listeningPorts": [8080], "portScanRan": true,
                          "healthCheckRan": true, "healthPassed": true}
        });
        let record: ServiceRecord = serde_json::from_value(json).unwrap();
        assert_eq!(record.short_id(), "01234567");
        assert_eq!(record.resources.mem_mb, Some(120.0));
        assert_eq!(record.lease_ttl_sec, 3600.0);
        assert_eq!(record.effective_ports(), &[8080]);
        assert!(record.state.is_running());
    }

    #[test]
    fn absent_resources_stay_unavailable() {
        let json = serde_json::json!({
            "id": "a", "friendlyName": "api", "ownerAgent": "agent-a",
            "startedAt": 1.0, "leaseExpiresAt": 2.0, "leaseTTLSec": 1.0, "state": "running"
        });
        let record: ServiceRecord = serde_json::from_value(json).unwrap();
        assert_eq!(record.resources.cpu_pct, None);
        assert_eq!(record.evidence.process_exists, None);
        assert!(!record.evidence.health_check_ran);
    }

    #[test]
    fn unknown_state_does_not_fail_the_snapshot() {
        let state: ServiceState = serde_json::from_value(serde_json::json!("hibernating")).unwrap();
        assert_eq!(state, ServiceState::Unknown);
        assert!(!state.is_running());
    }

    #[test]
    fn missing_required_field_is_an_error() {
        let json = serde_json::json!({"daemon": {"version": "1", "pid": 1, "startedAt": 1.0, "tickIntervalSec": 5.0}});
        assert!(decode_snapshot(json).is_err());
    }

    #[test]
    fn device_health_follows_probe_evidence() {
        let mut device: DeviceRecord =
            serde_json::from_value(serde_json::json!({"id": "d", "name": "node-b"})).unwrap();
        assert_eq!(device.health(), DeviceHealth::Unknown);
        device.evidence.icmp_ok = Some(false);
        device.evidence.tcp_ok = Some(true);
        assert_eq!(device.health(), DeviceHealth::Partial);
        device.evidence.icmp_ok = Some(false);
        device.evidence.tcp_ok = Some(false);
        assert_eq!(device.health(), DeviceHealth::Unreachable);
    }

    #[test]
    fn project_name_drops_the_parent_path() {
        let session: AgentSession = serde_json::from_value(serde_json::json!({
            "id": "s", "tool": "codex", "pid": 9, "project": "/home/example/work/fleet/"
        }))
        .unwrap();
        assert_eq!(session.project_name(), Some("fleet"));
    }
}
