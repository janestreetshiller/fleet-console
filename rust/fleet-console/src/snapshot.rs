
use std::collections::BTreeMap;

use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Snapshot {
    #[serde(rename = "generatedAt")]
    pub generated_at: f64,
    pub daemon: fleet_proto::DaemonInfo,
    #[serde(default)]
    pub services: Vec<Service>,
    #[serde(default)]
    pub unmanaged: Vec<serde_json::Value>,
    #[serde(default)]
    pub devices: Vec<serde_json::Value>,
    #[serde(default)]
    pub attention: Vec<Attention>,
    #[serde(rename = "recentEvents", default)]
    pub recent_events: Vec<Event>,
    #[serde(default)]
    pub messages: Vec<Message>,
    #[serde(default)]
    pub external: Vec<serde_json::Value>,
    #[serde(default)]
    pub sessions: Vec<AgentSession>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentSession {
    id: String,
    tool: String,
    pid: i32,
    project: Option<String>,
    cpu_pct: Option<f64>,
    #[serde(rename = "memMB")]
    mem_mb: Option<f64>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct Event {
    #[serde(default)]
    pub seq: i64,
    #[serde(rename = "serviceID", default)]
    pub service_id: Option<String>,
    #[serde(rename = "serviceName", default)]
    pub service_name: Option<String>,
    #[serde(default)]
    pub ts: serde_json::Value,
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub detail: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ServiceRow {
    pub id: String,
    pub state: String,
    pub state_label: String,
    pub owner: String,
    pub ports: String,
    pub cpu_pct: Option<f64>,
    pub mem_mb: Option<f64>,
    pub restart_count: i64,
    pub purpose: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct EventRow {
    pub seq: i64,
    pub label: String,
    pub is_bad: bool,
    pub service_name: String,
    pub detail: String,
    pub when: String,
}

pub fn service_state_label(state: &str) -> String {
    match state {
        "starting" => "Starting",
        "running" => "Running (unverified)",
        "healthy" => "Healthy",
        "degraded" => "Degraded",
        "unhealthy" => "Health check failing",
        "paused" => "Paused (still holding ports)",
        "expiring" => "Lease expiring",
        "expired" => "Lease expired",
        "stopping" => "Stopping",
        "stopped" => "Stopped",
        "crashed" => "Crashed",
        other => other,
    }
    .to_string()
}

pub fn event_kind_label(kind: &str) -> (String, bool) {
    let (label, is_bad) = match kind {
        "registered" => ("Registered", false),
        "claimed" => ("Claimed", false),
        "started" => ("Started", false),
        "restarted" => ("Restarted", false),
        "healthPassed" => ("Health check passed", false),
        "healthFailed" => ("Health check failed", true),
        "leaseRenewed" => ("Lease renewed", false),
        "leaseExpiring" => ("Lease expiring", false),
        "leaseExpired" => ("Lease expired", true),
        "maxRuntimeExceeded" => ("Max runtime exceeded", true),
        "budgetWarning" => ("Budget warning", true),
        "portViolation" => ("Port violation", true),
        "stopRequested" => ("Stop requested", false),
        "stopping" => ("Stopping", false),
        "stopped" => ("Stopped", false),
        "paused" => ("Paused", false),
        "resumed" => ("Resumed", false),
        "messagePosted" => ("Message posted", false),
        "messageAnswered" => ("Message answered", false),
        "crashed" => ("Crashed", true),
        "reapIncomplete" => ("Reap incomplete", true),
        "pidReuseSuspected" => ("PID reuse suspected", true),
        "reconcileMissing" => ("Process missing", true),
        "becameUnmanaged" => ("Became unmanaged", true),
        "rejectedLaunch" => ("Launch rejected", true),
        "rejectedPeer" => ("Peer rejected", true),
        "daemonStarted" => ("Controller started", false),
        "daemonStopping" => ("Controller stopping", false),
        "daemonCrashed" => ("Controller exited abnormally", true),
        other => (other, false),
    };
    (label.to_string(), is_bad)
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct Service {
    #[serde(default)]
    pub id: String,
    #[serde(rename = "friendlyName", default)]
    friendly_name: String,
    #[serde(rename = "ownerAgent", default)]
    pub owner: String,
    #[serde(default)]
    pub state: String,
    pid: Option<i32>,
    pgid: Option<i32>,
    #[serde(rename = "startSignature")]
    start_signature: Option<String>,
    #[serde(default)]
    claimed: bool,
    #[serde(rename = "claimedAt")]
    claimed_at: Option<f64>,
    #[serde(default)]
    health: HealthSpec,
    #[serde(rename = "leaseExpiresAt", default)]
    pub lease_expires_at: Option<f64>,
    #[serde(rename = "declaredPorts", default)]
    pub declared_ports: Vec<i64>,
    #[serde(default)]
    pub evidence: Evidence,
    #[serde(default)]
    pub resources: Resources,
    #[serde(rename = "startedAt", default)]
    pub started_at: f64,
    #[serde(rename = "updatedAt", default)]
    pub updated_at: f64,
    #[serde(rename = "restartCount", default)]
    pub restart_count: i64,
    #[serde(rename = "healthFailureCount", default)]
    pub health_failure_count: i64,
    #[serde(rename = "reapedForExpiry", default)]
    pub reaped_for_expiry: bool,
    #[serde(default)]
    pub purpose: String,
    #[serde(default)]
    pub cwd: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct Evidence {
    #[serde(rename = "processExists", default)]
    process_exists: bool,
    #[serde(rename = "listeningPorts", default)]
    pub listening_ports: Vec<i64>,
    #[serde(rename = "checkedAt")]
    checked_at: Option<f64>,
    #[serde(rename = "leaderVerifiedAt")]
    leader_verified_at: Option<f64>,
    #[serde(rename = "portScanRan", default)]
    port_scan_ran: bool,
    #[serde(rename = "healthCheckRan", default)]
    health_check_ran: bool,
    #[serde(rename = "healthPassed")]
    health_passed: Option<bool>,
}

#[derive(Debug, Clone, Default, Deserialize)]
struct HealthSpec {
    #[serde(default)]
    kind: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct Resources {
    #[serde(rename = "cpuPct", default)]
    pub cpu_pct: Option<f64>,
    #[serde(rename = "memMB", default)]
    pub mem_mb: Option<f64>,
    #[serde(rename = "sampledAt")]
    sampled_at: Option<f64>,
}

impl Service {
    pub fn is_terminal(&self) -> bool {
        matches!(self.state.as_str(), "stopped" | "crashed")
    }

    pub fn is_running(&self) -> bool {
        matches!(
            self.state.as_str(),
            "starting" | "running" | "healthy" | "degraded" | "unhealthy" | "paused" | "expiring"
        )
    }

    pub fn needs_attention(&self) -> bool {
        matches!(
            self.state.as_str(),
            "unhealthy" | "crashed" | "expired" | "degraded"
        )
    }

    pub fn effective_ports(&self) -> &[i64] {
        if self.evidence.listening_ports.is_empty() {
            &self.declared_ports
        } else {
            &self.evidence.listening_ports
        }
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct Message {
    #[serde(default)]
    pub id: i64,
    #[serde(default)]
    pub agent: String,
    #[serde(rename = "serviceName", default)]
    pub service_name: Option<String>,
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub body: String,
    #[serde(rename = "needsReply", default)]
    pub needs_reply: bool,
    #[serde(default)]
    pub reply: Option<serde_json::Value>,
    #[serde(rename = "createdAt", default)]
    pub created_at: f64,
    #[serde(rename = "seenAt", default)]
    pub seen_at: Option<f64>,
}

impl Message {
    pub fn is_awaiting_reply(&self) -> bool {
        self.needs_reply && self.reply.is_none()
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct Attention {
    #[serde(default)]
    pub severity: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tint {
    Bad,
    Warn,
    None,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ProfileLine {
    pub id: String,
    pub headline: String,
    pub awaiting_reply: i64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct FleetView {
    pub alert: String,
    pub status_line: String,
    pub tint: Tint,
    pub tooltip: String,
    pub awaiting_reply_count: i64,
    pub critical_count: i64,
    pub warning_count: i64,
    pub running_count: i64,
    pub profiles: Vec<ProfileLine>,
    pub next_lease_expiry: Option<f64>,
    pub service_rows: Vec<ServiceRow>,
    pub event_rows: Vec<EventRow>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum TopologyNodeKind {
    Owner,
    Service,
    Leader,
    Listener,
    Session,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct TopologyNode {
    pub(crate) id: String,
    pub(crate) kind: TopologyNodeKind,
    pub(crate) title: String,
    pub(crate) detail: String,
    pub(crate) service_id: Option<String>,
    pub(crate) owner: Option<String>,
    pub(crate) observed_at: Option<f64>,
    pub(crate) cpu_pct: Option<f64>,
    pub(crate) mem_mb: Option<f64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum TopologyEdgeKind {
    Owns,
    VerifiedLeader,
    ObservedListener,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct TopologyEdge {
    pub(crate) source: String,
    pub(crate) target: String,
    pub(crate) kind: TopologyEdgeKind,
    pub(crate) observed_at: Option<f64>,
    pub(crate) provenance: &'static str,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct FleetTopology {
    pub(crate) generated_at: f64,
    pub(crate) is_stale: bool,
    pub(crate) valid_until: Option<f64>,
    pub(crate) nodes: Vec<TopologyNode>,
    pub(crate) edges: Vec<TopologyEdge>,
    pub(crate) limitations: &'static [&'static str],
}

impl FleetTopology {
    pub(crate) fn from_snapshot(snapshot: &Snapshot, owner: Option<&str>, now: f64, connected: bool) -> Self {
        let interval = snapshot.daemon.tick_interval_sec;
        let tolerance = if interval.is_finite() && interval > 0.0 {
            (interval * 3.0).max(1.0)
        } else {
            15.0
        };
        let generated_at = snapshot.generated_at;
        let is_stale = !connected || now - generated_at > tolerance;
        let mut topology = Self {
            generated_at,
            is_stale,
            valid_until: (!is_stale).then_some(generated_at + tolerance),
            nodes: Vec::new(),
            edges: Vec::new(),
            limitations: &[
                "Ownership is a registry record; it does not identify a detected agent session.",
                "Recorded process IDs and group liveness alone do not verify a leader.",
                "Listeners show observed group ports, not connections or dependencies.",
                "Agent reasoning, token velocity, context usage and Ouros account usage are unavailable in the controller snapshot.",
            ],
        };
        let includes_owner = |name: &str| !name.trim().is_empty() && owner.is_none_or(|id| id == name);
        let mut services: Vec<_> = snapshot
            .services
            .iter()
            .filter(|s| {
                !s.is_terminal()
                    && !s.id.trim().is_empty()
                    && (owner.is_none() || includes_owner(&s.owner))
            })
            .collect();
        services.sort_unstable_by(|a, b| (&a.owner, &a.id).cmp(&(&b.owner, &b.id)));
        let mut owners = BTreeMap::new();
        for service in &services {
            if includes_owner(&service.owner) {
                owners.insert(service.owner.as_str(), 0);
            }
        }
        for message in &snapshot.messages {
            if includes_owner(&message.agent) {
                *owners.entry(message.agent.as_str()).or_default() +=
                    message.is_awaiting_reply() as usize;
            }
        }
        for (name, waiting) in owners {
            topology.nodes.push(TopologyNode {
                id: format!("owner:{name}"),
                kind: TopologyNodeKind::Owner,
                title: name.to_owned(),
                detail: format!("{waiting} awaiting replies"),
                service_id: None,
                owner: Some(name.to_owned()),
                observed_at: None,
                cpu_pct: None,
                mem_mb: None,
            });
        }

        let fresh_observation = |at: Option<f64>| {
            at.filter(|&at| !is_stale && at <= generated_at && now - at <= tolerance)
        };
        let metric = |fresh: Option<f64>, value: Option<f64>| {
            fresh.and(value).filter(|n| n.is_finite() && *n >= 0.0)
        };
        for service in services {
            let id = format!("service:{}", service.id);
            let recorded_owner = includes_owner(&service.owner).then(|| service.owner.clone());
            let evidence_at = fresh_observation(service.evidence.checked_at);
            let sample_at = fresh_observation(service.resources.sampled_at);
            topology.track_expiry(evidence_at, tolerance);
            topology.track_expiry(sample_at, tolerance);

            let health = if evidence_at.is_none() {
                "health unavailable or stale"
            } else if service.health.kind == "none" {
                "no health check configured"
            } else {
                match (service.evidence.health_check_ran, service.evidence.health_passed) {
                    (true, Some(true)) => "health check passed",
                    (true, Some(false)) => "health check failed",
                    _ => "health check unavailable",
                }
            };
            let listener_at = evidence_at.zip(sample_at).and_then(|(checked, sampled)| {
                (service.evidence.port_scan_ran
                    && service.pgid.is_some_and(|pgid| pgid > 0)
                    && sampled >= snapshot.daemon.started_at
                    && sampled <= checked
                    && (!service.claimed || service.claimed_at.is_some_and(|at| sampled >= at)))
                .then_some(sampled)
            });
            let mut ports: Vec<_> = if listener_at.is_some() {
                service
                    .evidence
                    .listening_ports
                    .iter()
                    .copied()
                    .filter(|port| (1..=65535).contains(port))
                    .collect()
            } else {
                Vec::new()
            };
            ports.sort_unstable();
            ports.dedup();
            let scan = match (listener_at, ports.is_empty()) {
                (None, _) => "listener scan unavailable or stale",
                (Some(_), true) => "no listeners observed",
                (Some(_), false) => "listeners observed",
            };
            let control = if service.claimed {
                "claimed · visibility only"
            } else {
                "controller launched"
            };
            let mut detail = format!("{} · {control} · {health} · {scan}", service.state);
            if let Some(pid) = service.pid {
                detail.push_str(&format!(" · recorded PID {pid}"));
            }
            if let Some(pgid) = service.pgid {
                detail.push_str(&format!(" · recorded group {pgid}"));
            }
            if !service.declared_ports.is_empty() {
                detail.push_str(&format!(" · declared {}", fmt_ports(&service.declared_ports)));
            }
            if let Some(name) = &recorded_owner {
                topology.edges.push(TopologyEdge {
                    source: format!("owner:{name}"),
                    target: id.clone(),
                    kind: TopologyEdgeKind::Owns,
                    observed_at: (service.updated_at != 0.0).then_some(service.updated_at),
                    provenance: "fleetd service registry",
                });
            }
            if let Some((at, pid)) = fresh_observation(service.evidence.leader_verified_at)
                .filter(|&at| at >= snapshot.daemon.started_at && at <= now)
                .zip(service.pid.filter(|&pid| {
                    pid > 0
                        && service.pgid == Some(pid)
                        && service.evidence.process_exists
                        && service.start_signature.as_ref().is_some_and(|s| !s.is_empty())
                }))
            {
                topology.track_expiry(Some(at), tolerance);
                let leader_id = format!("{id}:leader:{pid}");
                topology.nodes.push(TopologyNode {
                    id: leader_id.clone(),
                    kind: TopologyNodeKind::Leader,
                    title: format!("PID {pid}"),
                    detail: "Fleetd matched the process group and recorded start signature".to_owned(),
                    service_id: Some(service.id.clone()),
                    owner: recorded_owner.clone(),
                    observed_at: Some(at),
                    cpu_pct: None,
                    mem_mb: None,
                });
                topology.edges.push(TopologyEdge {
                    source: id.clone(),
                    target: leader_id,
                    kind: TopologyEdgeKind::VerifiedLeader,
                    observed_at: Some(at),
                    provenance: "fleetd process table identity match",
                });
            }
            for port in ports {
                let port_id = format!("{id}:port:{port}");
                topology.nodes.push(TopologyNode {
                    id: port_id.clone(),
                    kind: TopologyNodeKind::Listener,
                    title: format!(":{port}"),
                    detail: "Observed group listener".to_owned(),
                    service_id: Some(service.id.clone()),
                    owner: recorded_owner.clone(),
                    observed_at: listener_at,
                    cpu_pct: None,
                    mem_mb: None,
                });
                topology.edges.push(TopologyEdge {
                    source: id.clone(),
                    target: port_id,
                    kind: TopologyEdgeKind::ObservedListener,
                    observed_at: listener_at,
                    provenance: "fleetd group listener scan",
                });
            }
            topology.nodes.push(TopologyNode {
                id,
                kind: TopologyNodeKind::Service,
                title: if service.friendly_name.is_empty() {
                    service.id.clone()
                } else {
                    service.friendly_name.clone()
                },
                detail,
                service_id: Some(service.id.clone()),
                owner: recorded_owner,
                observed_at: service.evidence.checked_at,
                cpu_pct: metric(sample_at, service.resources.cpu_pct),
                mem_mb: metric(sample_at, service.resources.mem_mb),
            });
        }
        if owner.is_none() {
            let scanned_at = snapshot.daemon.last_reconcile_at;
            let session_at = fresh_observation(scanned_at);
            topology.track_expiry(session_at, tolerance);
            let mut sessions: Vec<_> = snapshot.sessions.iter().collect();
            sessions.sort_unstable_by(|a, b| a.id.cmp(&b.id));
            for session in sessions {
                let project = session
                    .project
                    .as_deref()
                    .and_then(|path| std::path::Path::new(path).file_name())
                    .and_then(|name| name.to_str())
                    .unwrap_or("—");
                let freshness = if session_at.is_some() {
                    ""
                } else {
                    " · session scan stale or unavailable"
                };
                topology.nodes.push(TopologyNode {
                    id: format!("session:{}", session.id),
                    kind: TopologyNodeKind::Session,
                    title: session.tool.clone(),
                    detail: format!("Detected PID {} · {project} · ownership unlinked{freshness}", session.pid),
                    service_id: None,
                    owner: None,
                    observed_at: scanned_at,
                    cpu_pct: metric(session_at, session.cpu_pct),
                    mem_mb: metric(session_at, session.mem_mb),
                });
            }
        }
        topology
    }

    fn track_expiry(&mut self, observation: Option<f64>, tolerance: f64) {
        if let Some(at) = observation {
            let expiry = at + tolerance;
            self.valid_until = Some(self.valid_until.map_or(expiry, |current| current.min(expiry)));
        }
    }
}

struct Profile {
    id: String,
    owned: i64,
    running: i64,
    paused: i64,
    needing_attention: i64,
    ports: Vec<i64>,
    next_lease_expiry: Option<f64>,
    total_launched: i64,
    total_crashed: i64,
    total_leaked: i64,
    message_count: i64,
    awaiting_reply: i64,
}

impl Profile {
    fn headline(&self) -> String {
        if self.running > 0 {
            let mut parts = vec![if self.running == 1 {
                "1 service running".to_string()
            } else {
                format!("{} services running", self.running)
            }];
            if self.paused > 0 {
                parts.push(format!("{} paused", self.paused));
            }
            if !self.ports.is_empty() {
                parts.push(fmt_ports(&self.ports));
            }
            return parts.join(" · ");
        }
        if self.total_launched == 0 {
            return if self.message_count > 0 {
                "no services — messages only".to_string()
            } else {
                "nothing recorded yet".to_string()
            };
        }
        let mut parts = vec![
            "idle".to_string(),
            format!("{} launched", self.total_launched),
        ];
        if self.total_crashed > 0 {
            parts.push(format!("{} crashed", self.total_crashed));
        }
        if self.total_leaked > 0 {
            parts.push(format!("{} left running", self.total_leaked));
        }
        parts.join(" · ")
    }
}

pub fn fmt_duration(seconds: f64) -> String {
    let s = seconds.abs().round() as i64;
    if s < 60 {
        return format!("{s}s");
    }
    let m = s / 60;
    let h = m / 60;
    let d = h / 24;
    if m < 60 {
        return format!("{m}m");
    }
    if h < 24 {
        return format!("{h}h {}m", m % 60);
    }
    format!("{d}d {}h", h % 24)
}

pub fn fmt_relative(date: Option<f64>, now: f64) -> String {
    let Some(date) = date else {
        return "never".to_string();
    };
    let delta = now - date;
    if delta < -1.0 {
        return format!("in {}", fmt_duration(-delta));
    }
    if delta < 2.0 {
        return "just now".to_string();
    }
    format!("{} ago", fmt_duration(delta))
}

pub fn fmt_ports(ports: &[i64]) -> String {
    if ports.is_empty() {
        return "—".to_string();
    }
    let mut sorted = ports.to_vec();
    sorted.sort_unstable();
    sorted
        .iter()
        .map(|p| format!(":{p}"))
        .collect::<Vec<_>>()
        .join(" ")
}

fn profiles(snapshot: &Snapshot) -> Vec<Profile> {
    use std::collections::BTreeMap;
    let mut by_agent: BTreeMap<&str, Vec<&Service>> = BTreeMap::new();
    for service in &snapshot.services {
        by_agent.entry(service.owner.as_str()).or_default().push(service);
    }
    let mut mail_by_agent: BTreeMap<&str, Vec<&Message>> = BTreeMap::new();
    for message in &snapshot.messages {
        mail_by_agent.entry(message.agent.as_str()).or_default().push(message);
    }
    let mut names: Vec<&str> = by_agent.keys().copied().collect();
    for name in mail_by_agent.keys() {
        if !names.contains(name) {
            names.push(name);
        }
    }
    let mut profiles: Vec<Profile> = names
        .into_iter()
        .map(|name| {
            let all = by_agent.get(name).cloned().unwrap_or_default();
            let live: Vec<&&Service> = all.iter().filter(|s| !s.is_terminal()).collect();
            let mail = mail_by_agent.get(name).cloned().unwrap_or_default();
            let mut ports: Vec<i64> = live
                .iter()
                .flat_map(|s| s.effective_ports().to_vec())
                .collect();
            ports.sort_unstable();
            ports.dedup();
            Profile {
                id: name.to_string(),
                owned: live.len() as i64,
                running: live.iter().filter(|s| s.is_running()).count() as i64,
                paused: live.iter().filter(|s| s.state == "paused").count() as i64,
                needing_attention: live.iter().filter(|s| s.needs_attention()).count() as i64,
                ports,
                next_lease_expiry: live
                    .iter()
                    .filter_map(|s| s.lease_expires_at)
                    .fold(None, |acc: Option<f64>, v| Some(acc.map_or(v, |a| a.min(v)))),
                total_launched: all.len() as i64,
                total_crashed: all.iter().filter(|s| s.state == "crashed").count() as i64,
                total_leaked: all.iter().filter(|s| !s.claimed && s.reaped_for_expiry).count() as i64,
                message_count: mail.len() as i64,
                awaiting_reply: mail.iter().filter(|m| m.is_awaiting_reply()).count() as i64,
            }
        })
        .collect();
    profiles.sort_by(|a, b| {
        (b.awaiting_reply, b.needing_attention, b.running, b.total_launched)
            .cmp(&(a.awaiting_reply, a.needing_attention, a.running, a.total_launched))
    });
    profiles
}

impl FleetView {
    pub fn from_snapshot(snapshot: &Snapshot, now: f64) -> FleetView {
        let awaiting = snapshot
            .messages
            .iter()
            .filter(|m| m.is_awaiting_reply())
            .count() as i64;
        let critical = snapshot
            .attention
            .iter()
            .filter(|a| a.severity == "critical")
            .count() as i64;
        let warning = snapshot
            .attention
            .iter()
            .filter(|a| a.severity == "warning")
            .count() as i64;
        let running = snapshot.services.iter().filter(|s| s.is_running()).count() as i64;

        let alert = if awaiting > 0 {
            format!("!{awaiting}")
        } else if critical + warning > 0 {
            format!("!{}", critical + warning)
        } else {
            String::new()
        };

        let status_line = if awaiting > 0 {
            format!("{awaiting} awaiting your answer")
        } else if critical > 0 {
            format!("{critical} critical · {warning} warning")
        } else if warning > 0 {
            format!("{warning} warning")
        } else {
            format!("{running} services running")
        };

        let tint = if critical > 0 {
            Tint::Bad
        } else if awaiting > 0 || warning > 0 {
            Tint::Warn
        } else {
            Tint::None
        };

        let profiles = profiles(snapshot);
        let next_lease = profiles
            .iter()
            .filter_map(|p| p.next_lease_expiry)
            .fold(None, |acc: Option<f64>, v| Some(acc.map_or(v, |a| a.min(v))));

        let mut counts = vec![format!("{running} running")];
        if !snapshot.unmanaged.is_empty() {
            counts.push(format!("{} unmanaged", snapshot.unmanaged.len()));
        }
        if critical > 0 {
            counts.push(format!("{critical} critical"));
        }
        if warning > 0 {
            counts.push(format!("{warning} warning"));
        }
        let mut lines = vec![counts.join(" · ")];
        for profile in profiles.iter().take(4) {
            let mut line = format!("{}: {}", profile.id, profile.headline());
            if profile.awaiting_reply > 0 {
                line += &format!(" — {} awaiting your answer", profile.awaiting_reply);
            }
            lines.push(line);
        }
        if let Some(lease) = next_lease {
            lines.push(format!(
                "next lease expires {}",
                fmt_relative(Some(lease), now)
            ));
        }
        let unreachable: Vec<_> = snapshot
            .devices
            .iter()
            .filter_map(|device| {
                let evidence = device.get("evidence")?;
                if evidence.get("isSelf").and_then(serde_json::Value::as_bool) == Some(true) {
                    return None;
                }
                let observed = ["icmpOK", "tcpOK", "tailscaleOnline"]
                    .map(|probe| evidence.get(probe).and_then(serde_json::Value::as_bool));
                if !observed.contains(&Some(false)) || observed.contains(&Some(true)) {
                    return None;
                }
                device.get("name").and_then(serde_json::Value::as_str)
            })
            .collect();
        if let Some((first, rest)) = unreachable.split_first() {
            use std::fmt::Write;
            let mut line = String::with_capacity(
                26 + 2 * rest.len() + unreachable.iter().map(|name| name.len()).sum::<usize>(),
            );
            write!(line, "{} device(s) unreachable: {first}", unreachable.len())
                .expect("formatting into a string is infallible");
            for name in rest {
                line.push_str(", ");
                line.push_str(name);
            }
            lines.push(line);
        }
        lines.push(format!(
            "fleetd up {}",
            fmt_duration(now - snapshot.daemon.started_at)
        ));

        let service_rows = snapshot
            .services
            .iter()
            .map(|service| ServiceRow {
                id: service.id.clone(),
                state: service.state.clone(),
                state_label: service_state_label(&service.state),
                owner: service.owner.clone(),
                ports: fmt_ports(service.effective_ports()),
                cpu_pct: service.resources.cpu_pct,
                mem_mb: service.resources.mem_mb,
                restart_count: service.restart_count,
                purpose: service.purpose.clone(),
            })
            .collect();
        let event_rows = snapshot
            .recent_events
            .iter()
            .rev()
            .map(|event| {
                let (label, is_bad) = event_kind_label(&event.kind);
                let when = match &event.ts {
                    serde_json::Value::Number(number) => number
                        .as_f64()
                        .map(|ts| fmt_relative(Some(ts), now))
                        .unwrap_or_default(),
                    serde_json::Value::String(text) => {
                        text.chars().take(19).collect::<String>().replace('T', " ")
                    }
                    _ => String::new(),
                };
                EventRow {
                    seq: event.seq,
                    label,
                    is_bad,
                    service_name: event
                        .service_name
                        .clone()
                        .or_else(|| event.service_id.clone())
                        .unwrap_or_default(),
                    detail: event.detail.clone(),
                    when,
                }
            })
            .collect();

        FleetView {
            alert,
            status_line,
            tint,
            tooltip: lines.join("\n"),
            awaiting_reply_count: awaiting,
            critical_count: critical,
            warning_count: warning,
            running_count: running,
            profiles: profiles
                .iter()
                .map(|p| ProfileLine {
                    id: p.id.clone(),
                    headline: p.headline(),
                    awaiting_reply: p.awaiting_reply,
                })
                .collect(),
            next_lease_expiry: next_lease,
            service_rows,
            event_rows,
        }
    }

    pub fn offline_alert() -> &'static str {
        "Offline"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn snapshot_from(json: &str) -> Snapshot {
        serde_json::from_str(json).expect("fixture parses")
    }

    fn topology_snapshot() -> Snapshot {
        snapshot_from(
            r#"{"generatedAt":1000, "daemon":{"version":"1.3.0","pid":7,"startedAt":990,
                "tickIntervalSec":5,"lastReconcileAt":999},
                "services":[
                    {"id":"tracked","friendlyName":"Web","ownerAgent":"registry","state":"running",
                        "pid":42,"pgid":42,"startSignature":"recorded start","updatedAt":995,
                        "declaredPorts":[8000],"health":{"kind":"none"},
                        "evidence":{"processExists":true,"checkedAt":998,"portScanRan":true,
                            "listeningPorts":[8123,8123,0,65536]},
                        "resources":{"sampledAt":997,"cpuPct":2,"memMB":-1}},
                    {"id":"no-owner","state":"running","pid":42,"pgid":42},
                    {"id":"stopped","ownerAgent":"former","state":"stopped"}],
                "sessions":[{"id":"s","tool":"codex","pid":42,"project":"/work/web","cpuPct":3,"memMB":4}]}"#,
        )
    }

    #[test]
    fn topology_uses_registry_ownership_and_observed_ports_not_pid_matches() {
        let snap = topology_snapshot();
        let topology = FleetTopology::from_snapshot(&snap, None, 1000.0, true);
        assert!(!topology.is_stale);
        assert_eq!(topology.valid_until, Some(1012.0));
        assert_eq!(
            topology.edges,
            [
                TopologyEdge {
                    source: "owner:registry".into(),
                    target: "service:tracked".into(),
                    kind: TopologyEdgeKind::Owns,
                    observed_at: Some(995.0),
                    provenance: "fleetd service registry",
                },
                TopologyEdge {
                    source: "service:tracked".into(),
                    target: "service:tracked:port:8123".into(),
                    kind: TopologyEdgeKind::ObservedListener,
                    observed_at: Some(997.0),
                    provenance: "fleetd group listener scan",
                },
            ]
        );
        assert_eq!(topology.nodes.len(), 5);
        let tracked = topology.nodes.iter().find(|n| n.id == "service:tracked").unwrap();
        assert!(tracked.detail.contains("declared :8000"));
        assert!(tracked.detail.contains("recorded group 42"));
        assert_eq!(tracked.cpu_pct, Some(2.0));
        assert_eq!(tracked.mem_mb, None);
        let session = topology.nodes.iter().find(|n| n.id == "session:s").unwrap();
        assert_eq!(session.kind, TopologyNodeKind::Session);
        assert_eq!(session.owner, None);
        assert_eq!(session.service_id, None);
        assert_eq!(session.mem_mb, Some(4.0));
        let filtered = FleetTopology::from_snapshot(&snap, Some("registry"), 1000.0, true);
        assert_eq!(filtered.edges, topology.edges);
        assert_eq!(filtered.nodes.len(), 3);
    }

    #[test]
    fn topology_expires_live_evidence_without_losing_recorded_ownership() {
        let snap = topology_snapshot();
        for (now, connected, is_stale, valid_until) in [
            (1012.5, true, false, Some(1013.0)),
            (1016.0, true, true, None),
            (1000.0, false, true, None),
        ] {
            let topology = FleetTopology::from_snapshot(&snap, None, now, connected);
            assert_eq!(topology.is_stale, is_stale);
            assert_eq!(topology.valid_until, valid_until);
            assert_eq!(topology.edges.len(), 1);
            assert_eq!(topology.edges[0].kind, TopologyEdgeKind::Owns);
            assert!(topology.nodes.iter().all(|n| n.kind != TopologyNodeKind::Listener));
            let tracked = topology.nodes.iter().find(|n| n.id == "service:tracked").unwrap();
            assert_eq!(tracked.cpu_pct, None);
            assert_eq!(tracked.owner.as_deref(), Some("registry"));
            let session = topology.nodes.iter().find(|n| n.id == "session:s").unwrap();
            assert_eq!(session.owner, None);
            assert_eq!(session.cpu_pct, (!is_stale).then_some(3.0));
        }
    }

    fn stamped_leader_snapshot() -> Snapshot {
        snapshot_from(
            r#"{"generatedAt":1000, "daemon":{"version":"1.3.0","pid":7,"startedAt":990,"tickIntervalSec":5},
                "services":[{"id":"tracked","ownerAgent":"registry","state":"running",
                    "pid":42,"pgid":42,"startSignature":"recorded start",
                    "evidence":{"processExists":true,"leaderVerifiedAt":995}}]}"#,
        )
    }

    #[test]
    fn topology_projects_stamped_leader_independently_of_health_and_resources() {
        let snap = stamped_leader_snapshot();
        let topology = FleetTopology::from_snapshot(&snap, Some("registry"), 1000.0, true);
        let leader = topology.nodes.iter().find(|n| n.kind == TopologyNodeKind::Leader).unwrap();
        assert_eq!(leader.title, "PID 42");
        assert_eq!(leader.service_id.as_deref(), Some("tracked"));
        assert_eq!(leader.observed_at, Some(995.0));
        assert_eq!(topology.edges[1], TopologyEdge {
            source: "service:tracked".into(),
            target: leader.id.clone(),
            kind: TopologyEdgeKind::VerifiedLeader,
            observed_at: Some(995.0),
            provenance: "fleetd process table identity match",
        });
        assert_eq!(topology.valid_until, Some(1010.0));
    }

    #[test]
    fn topology_requires_fresh_leader_evidence_and_exact_recorded_identity() {
        let snap = stamped_leader_snapshot();
        let assert_no_leader = |snapshot: &Snapshot, now, connected| {
            let topology = FleetTopology::from_snapshot(snapshot, None, now, connected);
            assert!(topology.nodes.iter().all(|n| n.kind != TopologyNodeKind::Leader));
            assert!(topology.edges.iter().all(|e| e.kind != TopologyEdgeKind::VerifiedLeader));
        };
        assert_no_leader(&topology_snapshot(), 1000.0, true);
        assert_no_leader(&snap, 1010.1, true);
        assert_no_leader(&snap, 1000.0, false);
        for (pid, pgid, signature, exists, verified_at) in [
            (Some(42), Some(41), Some("start"), true, 995.0),
            (Some(0), Some(0), Some("start"), true, 995.0),
            (Some(42), Some(42), None, true, 995.0),
            (Some(42), Some(42), Some(""), true, 995.0),
            (Some(42), Some(42), Some("start"), false, 995.0),
            (Some(42), Some(42), Some("start"), true, 989.0),
            (Some(42), Some(42), Some("start"), true, 1001.0),
        ] {
            let mut snap = stamped_leader_snapshot();
            let service = &mut snap.services[0];
            service.pid = pid;
            service.pgid = pgid;
            service.start_signature = signature.map(str::to_owned);
            service.evidence.process_exists = exists;
            service.evidence.leader_verified_at = Some(verified_at);
            assert_no_leader(&snap, 1000.0, true);
        }
    }

    #[test]
    fn topology_rejects_unrun_retained_and_unstamped_listener_scans() {
        for (scan_ran, checked_at, sampled_at, claimed_at) in [
            (false, Some(998.0), Some(997.0), None),
            (true, None, Some(997.0), None),
            (true, Some(998.0), None, None),
            (true, Some(998.0), Some(989.0), None),
            (true, Some(998.0), Some(997.0), Some(998.0)),
        ] {
            let mut snap = topology_snapshot();
            let service = &mut snap.services[0];
            service.evidence.port_scan_ran = scan_ran;
            service.evidence.checked_at = checked_at;
            service.resources.sampled_at = sampled_at;
            service.claimed = claimed_at.is_some();
            service.claimed_at = claimed_at;
            let topology = FleetTopology::from_snapshot(&snap, None, 1000.0, true);
            assert_eq!(topology.edges.len(), 1);
            assert_eq!(topology.edges[0].kind, TopologyEdgeKind::Owns);
            assert!(topology.nodes.iter().all(|n| n.kind != TopologyNodeKind::Listener));
        }
    }

    #[test]
    fn healthy_snapshot_has_empty_alert() {
        let snap = snapshot_from(
            r#"{"generatedAt": 1000.0, "daemon": {"version":"1.1.0","pid":7,"startedAt":400.0,"tickIntervalSec":5},
                "services": [{"id":"a","ownerAgent":"claude","state":"running","startedAt":1.0,"updatedAt":2.0}],
                "messages": [], "attention": [], "unmanaged": []}"#,
        );
        let view = FleetView::from_snapshot(&snap, 1000.0);
        assert_eq!(view.alert, "");
        assert_eq!(view.status_line, "1 services running");
        assert_eq!(view.tint, Tint::None);
        assert_eq!(view.tooltip, "1 running\nclaude: 1 service running\nfleetd up 10m");
    }

    #[test]
    fn tooltip_reports_only_devices_with_negative_reachability_evidence() {
        let snap = snapshot_from(
            r#"{"generatedAt":1000.0,"daemon":{"version":"1.1.0","pid":7,"startedAt":400.0,"tickIntervalSec":5},
                "services":[{"id":"svc","ownerAgent":"claude","state":"running","startedAt":1.0,
                             "updatedAt":2.0,"leaseExpiresAt":1120.0}],
                "devices":[
                    {"name":"This Mac","evidence":{"isSelf":true,"tcpOK":false}},
                    {"name":"Not sampled","evidence":{}},
                    {"name":"Mixed","evidence":{"icmpOK":false,"tailscaleOnline":true}},
                    {"name":"Build machine","evidence":{"icmpOK":false}},
                    {"name":"Test machine","evidence":{"tcpOK":false,"tailscaleOnline":false}}
                ]}"#,
        );
        let view = FleetView::from_snapshot(&snap, 1000.0);
        assert!(view.tooltip.ends_with(
            "\nnext lease expires in 2m\n2 device(s) unreachable: Build machine, Test machine\nfleetd up 10m"
        ));
    }

    #[test]
    fn legacy_claim_expiry_is_not_counted_as_a_reap() {
        let snapshot = snapshot_from(
            r#"{"generatedAt":1000.0,"daemon":{"version":"1.1.0","pid":7,"startedAt":400.0,"tickIntervalSec":5},
                "services":[
                    {"id":"claimed","ownerAgent":"codex","state":"expired","claimed":true,"reapedForExpiry":true},
                    {"id":"launched","ownerAgent":"codex","state":"expired","reapedForExpiry":true}
                ]}"#,
        );
        assert!(FleetView::from_snapshot(&snapshot, 1000.0).tooltip.contains("1 left running"));
    }

    #[test]
    fn awaiting_reply_wins_the_alert() {
        let snap = snapshot_from(
            r#"{"generatedAt": 1000.0, "daemon": {"version":"1.1.0","pid":7,"startedAt":400.0,"tickIntervalSec":5},
                "services": [],
                "messages": [{"id":1,"agent":"codex","kind":"question","body":"?","needsReply":true,"createdAt":9.0},
                             {"id":2,"agent":"codex","kind":"status","body":"ok","needsReply":false,"createdAt":8.0}],
                "attention": [{"severity":"warning"}], "unmanaged": [{}]}"#,
        );
        let view = FleetView::from_snapshot(&snap, 1000.0);
        assert_eq!(view.alert, "!1");
        assert_eq!(view.status_line, "1 awaiting your answer");
        assert_eq!(view.tint, Tint::Warn);
        assert!(view.tooltip.starts_with("0 running · 1 unmanaged · 1 warning"));
        assert!(view.tooltip.contains("codex: no services — messages only — 1 awaiting your answer"));
    }

    #[test]
    fn critical_attention_is_bad_tint() {
        let snap = snapshot_from(
            r#"{"generatedAt": 1000.0, "daemon": {"version":"1.1.0","pid":7,"startedAt":400.0,"tickIntervalSec":5},
                "services": [], "messages": [],
                "attention": [{"severity":"critical"},{"severity":"warning"}], "unmanaged": []}"#,
        );
        let view = FleetView::from_snapshot(&snap, 1000.0);
        assert_eq!(view.alert, "!2");
        assert_eq!(view.status_line, "1 critical · 1 warning");
        assert_eq!(view.tint, Tint::Bad);
    }

    #[test]
    fn durations_and_relatives_match_swift() {
        assert_eq!(fmt_duration(42.0), "42s");
        assert_eq!(fmt_duration(600.0), "10m");
        assert_eq!(fmt_duration(7_500.0), "2h 5m");
        assert_eq!(fmt_duration(90_000.0), "1d 1h");
        assert_eq!(fmt_relative(None, 100.0), "never");
        assert_eq!(fmt_relative(Some(160.0), 100.0), "in 1m");
        assert_eq!(fmt_relative(Some(99.0), 100.0), "just now");
        assert_eq!(fmt_relative(Some(40.0), 100.0), "1m ago");
    }
}
