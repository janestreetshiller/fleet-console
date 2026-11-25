
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Snapshot {
    #[serde(rename = "generatedAt", default)]
    pub generated_at: f64,
    #[serde(default = "default_daemon")]
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
    pub sessions: Vec<serde_json::Value>,
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

fn default_daemon() -> fleet_proto::DaemonInfo {
    fleet_proto::DaemonInfo {
        version: String::new(),
        pid: 0,
        started_at: 0.0,
        last_tick_at: None,
        last_reconcile_at: None,
        tick_interval_sec: 5.0,
        socket_path: String::new(),
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct Service {
    #[serde(default)]
    pub id: String,
    #[serde(rename = "ownerAgent", default)]
    pub owner: String,
    #[serde(default)]
    pub state: String,
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
    #[serde(rename = "listeningPorts", default)]
    pub listening_ports: Vec<i64>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct Resources {
    #[serde(rename = "cpuPct", default)]
    pub cpu_pct: Option<f64>,
    #[serde(rename = "memMB", default)]
    pub mem_mb: Option<f64>,
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
                total_leaked: all.iter().filter(|s| s.reaped_for_expiry).count() as i64,
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
