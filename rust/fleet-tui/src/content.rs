//! What each view lists, inspects and hands to an agent, derived from the
//! dashboard. Pure functions shared by the full-screen and plain renderers,
//! so both show the same rows, the same detail facts and the same commands.

use crate::app::View;
use crate::theme::Tone;
use fleet_ui_core::controller::Action;
use fleet_ui_core::format;
use fleet_ui_core::views::{
    AttentionRow, Control, Dashboard, Gauge, ProcessLine, ProcessRole, ServiceRow, Severity,
};
use fleet_ui_core::{Metric, Phase};

/// Remove terminal control sequences and control characters from text that
/// came from the controller, an agent or a log. Tabs become spaces.
pub fn clean(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '\u{1b}' => match chars.peek() {
                // CSI: parameters and intermediates up to a final byte.
                Some('[') => {
                    chars.next();
                    for n in chars.by_ref() {
                        if ('\u{40}'..='\u{7e}').contains(&n) {
                            break;
                        }
                    }
                }
                // OSC, DCS, SOS, PM, APC: up to BEL or ST.
                Some(']') | Some('P') | Some('X') | Some('^') | Some('_') => {
                    chars.next();
                    while let Some(n) = chars.next() {
                        if n == '\u{7}' {
                            break;
                        }
                        if n == '\u{1b}' && chars.peek() == Some(&'\\') {
                            chars.next();
                            break;
                        }
                    }
                }
                _ => {
                    chars.next();
                }
            },
            '\t' => out.push(' '),
            c if c.is_control() => {}
            c => out.push(c),
        }
    }
    out
}

/// Bytes from a size `format::bytes` produced (`512 B`, `1.5 KB`, `995 GB`).
/// The storage view needs relative volume capacities and the view model
/// carries only the formatted text; `None` when the text is not a size.
pub fn parse_size(text: &str) -> Option<f64> {
    let (number, unit) = text.trim().split_once(' ')?;
    let value: f64 = number.parse().ok()?;
    let power = ["B", "KB", "MB", "GB", "TB", "PB"]
        .iter()
        .position(|u| *u == unit)?;
    Some(value * 1024f64.powi(power as i32))
}

/// Percent wording for speech: `34 percent`, `above 50 percent`.
pub fn speak(text: &str) -> String {
    text.replace('%', " percent")
}

/// `cpu 34 percent, normal` or `gpu unavailable, not measured on this platform`.
pub fn spoken_gauge(gauge: &Gauge) -> String {
    match (gauge.metric, gauge.level) {
        (Metric::Unavailable(reason), _) => {
            format!("{} unavailable, {}", gauge.label.to_lowercase(), reason.label())
        }
        (Metric::Measured(_), Some(level)) => format!(
            "{} {}, {}",
            gauge.label.to_lowercase(),
            speak(&gauge.text),
            speak(level.label())
        ),
        (Metric::Measured(_), None) => {
            format!("{} {}", gauge.label.to_lowercase(), speak(&gauge.text))
        }
    }
}

pub fn metric_reason(metric: Metric) -> String {
    match metric.reason() {
        Some(reason) => format!("--, {}", reason.label()),
        None => format::percent(metric),
    }
}

pub fn severity_tone(severity: Severity) -> Tone {
    match severity {
        Severity::Critical => Tone::Crit,
        Severity::Warning => Tone::Warn,
        Severity::Info => Tone::Info,
    }
}

pub fn phase_tone(phase: Phase) -> Tone {
    match phase {
        Phase::Live => Tone::Bright,
        Phase::Loading => Tone::Info,
        Phase::Stale => Tone::Warn,
        Phase::Disconnected | Phase::Error => Tone::Crit,
    }
}

/// Tree glyphs for each process line from its depth and last-child flag:
/// `├─ ` and `└─ ` for the line itself, `│  ` for an ancestor with siblings
/// still to come.
pub fn tree_prefixes(lines: &[ProcessLine]) -> Vec<String> {
    let mut open: Vec<bool> = Vec::new();
    lines
        .iter()
        .map(|line| {
            let depth = line.depth;
            if depth == 0 {
                open.clear();
                return String::new();
            }
            open.resize(depth + 1, false);
            let mut prefix = String::new();
            for level in open.iter().take(depth).skip(1) {
                prefix.push_str(if *level { "│  " } else { "   " });
            }
            prefix.push_str(if line.last_child { "└─ " } else { "├─ " });
            open[depth] = !line.last_child;
            open.truncate(depth + 1);
            prefix
        })
        .collect()
}

pub fn len(view: View, dash: &Dashboard) -> usize {
    match view {
        View::Overview => dash.cluster.tiles.len(),
        View::Processes => dash.processes.lines.len(),
        View::Services => dash.services.len(),
        View::Agents => dash.agents.transcript.len(),
        View::Storage => dash.storage.volumes.len(),
        View::Attention => dash.attention.len(),
    }
}

/// A stable identity for a row, so the selection follows it across refreshes.
pub fn key(view: View, dash: &Dashboard, index: usize) -> Option<String> {
    Some(match view {
        View::Overview => dash.cluster.tiles.get(index)?.id.clone(),
        View::Processes => {
            let l = dash.processes.lines.get(index)?;
            match l.pid {
                Some(pid) => format!("pid:{pid}"),
                None => format!("more:{}:{}", l.depth, l.name),
            }
        }
        View::Services => dash.services.get(index)?.id.clone(),
        View::Agents => {
            let l = dash.agents.transcript.get(index)?;
            match &l.question {
                Some(q) => format!("message:{}", q.message_id),
                None => format!("{}|{}|{}", l.time, l.agent, l.text),
            }
        }
        View::Storage => dash.storage.volumes.get(index)?.mount.clone(),
        View::Attention => dash.attention.get(index)?.id.clone(),
    })
}

/// The text a filter matches against.
pub fn search_text(view: View, dash: &Dashboard, index: usize) -> String {
    match view {
        View::Overview => dash
            .cluster
            .tiles
            .get(index)
            .map(|t| format!("{} {}", t.name, t.state.label()))
            .unwrap_or_default(),
        View::Processes => dash
            .processes
            .lines
            .get(index)
            .map(|l| {
                format!(
                    "{} {} {}",
                    l.name,
                    l.pid.map(|p| p.to_string()).unwrap_or_default(),
                    l.tag.clone().unwrap_or_default()
                )
            })
            .unwrap_or_default(),
        View::Services => dash
            .services
            .get(index)
            .map(|r| format!("{} {} {} {} {}", r.name, r.short_id, r.owner, r.state_text, r.ports))
            .unwrap_or_default(),
        View::Agents => dash
            .agents
            .transcript
            .get(index)
            .map(|l| format!("{} {} {}", l.agent, l.verb, l.text))
            .unwrap_or_default(),
        View::Storage => dash
            .storage
            .volumes
            .get(index)
            .map(|v| format!("{} {}", v.mount, v.filesystem))
            .unwrap_or_default(),
        View::Attention => dash
            .attention
            .get(index)
            .map(|r| format!("{} {} {} {}", r.severity.label(), r.title, r.detail, r.source))
            .unwrap_or_default(),
    }
    .to_lowercase()
}

/// Indices of the rows a filter keeps, in display order.
pub fn visible(view: View, dash: &Dashboard, filter: &str) -> Vec<usize> {
    let needle = filter.trim().to_lowercase();
    (0..len(view, dash))
        .filter(|&i| needle.is_empty() || search_text(view, dash, i).contains(&needle))
        .collect()
}

/// The managed service a row refers to, for restart, stop, renew and tail.
pub fn service_for<'a>(view: View, dash: &'a Dashboard, index: usize) -> Option<&'a ServiceRow> {
    match view {
        View::Services => dash.services.get(index),
        View::Attention => {
            let id = dash.attention.get(index)?.service_id.as_ref()?;
            dash.services.iter().find(|s| &s.id == id)
        }
        View::Processes => {
            let line = dash.processes.lines.get(index)?;
            if line.role != ProcessRole::Service {
                return None;
            }
            let pid = line.pid?;
            dash.services
                .iter()
                .find(|s| s.pid.map(|p| p as u32) == Some(pid))
        }
        _ => None,
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct QuestionRef {
    pub message_id: i64,
    pub agent: String,
    pub text: String,
    pub reply: Control,
}

/// The open agent question a row refers to, for approve and deny.
pub fn question_for(view: View, dash: &Dashboard, index: usize) -> Option<QuestionRef> {
    match view {
        View::Agents => {
            let line = dash.agents.transcript.get(index)?;
            let q = line.question.as_ref()?;
            Some(QuestionRef {
                message_id: q.message_id,
                agent: line.agent.clone(),
                text: line.text.clone(),
                reply: q.reply.clone(),
            })
        }
        View::Attention => {
            let row = dash.attention.get(index)?;
            let id = row.message_id?;
            Some(question_by_id(dash, id).unwrap_or(QuestionRef {
                message_id: id,
                agent: String::new(),
                text: row.detail.clone(),
                reply: Control::Refused(
                    "this question is not in the loaded transcript; answer it with fleetctl reply"
                        .into(),
                ),
            }))
        }
        _ => None,
    }
}

pub fn question_by_id(dash: &Dashboard, message_id: i64) -> Option<QuestionRef> {
    dash.agents.transcript.iter().find_map(|line| {
        line.question
            .as_ref()
            .filter(|q| q.message_id == message_id)
            .map(|q| QuestionRef {
                message_id,
                agent: line.agent.clone(),
                text: line.text.clone(),
                reply: q.reply.clone(),
            })
    })
}

/// The evidence a destructive action rests on, shown before it is sent.
pub fn confirm_prompt(action: &Action, row: &ServiceRow) -> String {
    let verb = match action {
        Action::Stop { .. } => "Stop",
        Action::Restart { .. } => "Restart",
        Action::Pause { .. } => "Pause",
        _ => "Send to",
    };
    let pid = row
        .pid
        .map(|p| format!("pid {p}"))
        .unwrap_or_else(|| "no pid".into());
    format!(
        "{verb} {}? {pid}, owner {}, {}, up {}.",
        clean(&row.name),
        clean(&row.owner),
        row.ports,
        row.uptime
    )
}

pub fn control_text(control: &Control) -> String {
    match control {
        Control::Allowed => "available".into(),
        Control::Refused(reason) => format!("unavailable: {reason}"),
    }
}

/// One fact in a detail pane.
#[derive(Debug, Clone, PartialEq)]
pub struct Fact {
    pub label: String,
    pub text: String,
    pub tone: Tone,
}

fn fact(label: &str, text: impl Into<String>, tone: Tone) -> Fact {
    Fact {
        label: label.into(),
        text: text.into(),
        tone,
    }
}

/// Title and facts for the selected row.
pub fn detail(view: View, dash: &Dashboard, index: usize) -> Option<(String, Vec<Fact>)> {
    match view {
        View::Overview => {
            let t = dash.cluster.tiles.get(index)?;
            let mut facts = vec![fact(
                "state",
                format!(
                    "{}{}",
                    t.state.label(),
                    match t.freshness {
                        fleet_ui_core::views::Freshness::Current => "",
                        fleet_ui_core::views::Freshness::Stale => ", not current",
                        fleet_ui_core::views::Freshness::Disconnected => ", controller disconnected",
                    }
                ),
                Tone::for_level(t.worst_level()),
            )];
            for g in &t.gauges {
                let text = match g.metric.reason() {
                    Some(reason) => format!("--, {}", reason.label()),
                    None if g.detail.is_empty() => g.text.clone(),
                    None => format!("{}, {}", g.text, g.detail),
                };
                let text = match g.level {
                    Some(level) => format!("{text}, {}", level.label()),
                    None => text,
                };
                facts.push(fact(g.label, text, Tone::for_level(g.level)));
            }
            facts.push(fact("network", t.network_text.clone(), Tone::Text));
            facts.push(fact(
                "services",
                match (t.services_up, t.services_total) {
                    (Some(up), Some(total)) => format!("{up} up of {total}"),
                    _ => "--, not reported".into(),
                },
                Tone::Text,
            ));
            facts.push(fact(
                "agents",
                t.agents
                    .map(|a| a.to_string())
                    .unwrap_or_else(|| "--, not reported".into()),
                Tone::Text,
            ));
            facts.push(fact(
                "uptime",
                t.uptime.clone().unwrap_or_else(|| "--, not reported".into()),
                Tone::Text,
            ));
            if let Some(note) = &t.note {
                facts.push(fact("note", clean(note), Tone::Dim));
            }
            Some((clean(&t.name), facts))
        }
        View::Processes => {
            let l = dash.processes.lines.get(index)?;
            let mut facts = vec![
                fact(
                    "pid",
                    l.pid.map(|p| p.to_string()).unwrap_or_else(|| "--".into()),
                    Tone::Text,
                ),
                fact(
                    "role",
                    match l.role {
                        ProcessRole::Service => "managed service",
                        ProcessRole::Agent => "agent session",
                        ProcessRole::Controller => "controller",
                        ProcessRole::Other => "process",
                    },
                    Tone::Text,
                ),
                fact("cpu", metric_reason(l.cpu), Tone::Text),
                fact(
                    "memory",
                    if l.memory.is_empty() {
                        "--".to_string()
                    } else {
                        l.memory.clone()
                    },
                    Tone::Text,
                ),
            ];
            if let Some(tag) = &l.tag {
                facts.push(fact("note", clean(tag), Tone::Warn));
            }
            facts.push(fact(
                "control",
                if service_for(view, dash, index).is_some() {
                    "a managed service: r, s, n and t act on it through the controller"
                } else {
                    "read-only: only services the controller launched can be restarted or stopped"
                },
                Tone::Dim,
            ));
            Some((clean(&l.name), facts))
        }
        View::Services => {
            let r = dash.services.get(index)?;
            Some((format!("{} {}", clean(&r.name), r.short_id), service_facts(r)))
        }
        View::Agents => {
            let l = dash.agents.transcript.get(index)?;
            let mut facts = vec![
                fact("time", format!("{} UTC", l.time), Tone::Dim),
                fact("agent", clean(&l.agent), Tone::Text),
                fact("kind", l.verb.clone(), Tone::Text),
                fact("message", clean(&l.text), Tone::Text),
            ];
            if let Some(q) = &l.question {
                facts.push(fact("message id", q.message_id.to_string(), Tone::Text));
                facts.push(fact(
                    "reply",
                    match &q.reply {
                        Control::Allowed => "y approves, n denies; the agent reads the reply with fleetctl inbox".into(),
                        Control::Refused(reason) => format!("unavailable: {reason}"),
                    },
                    if q.reply.is_allowed() { Tone::Bright } else { Tone::Warn },
                ));
            }
            Some((format!("{} {}", clean(&l.agent), l.verb), facts))
        }
        View::Storage => {
            let v = dash.storage.volumes.get(index)?;
            Some((
                clean(&v.mount),
                vec![
                    fact("filesystem", clean(&v.filesystem), Tone::Text),
                    fact("used", v.used.clone(), Tone::Text),
                    fact("free", v.free.clone(), Tone::Text),
                    fact("capacity", v.total.clone(), Tone::Text),
                    fact(
                        "used share",
                        match (v.gauge.metric.reason(), v.gauge.level) {
                            (Some(reason), _) => format!("--, {}", reason.label()),
                            (None, Some(level)) => format!("{}, {}", v.gauge.text, level.label()),
                            (None, None) => v.gauge.text.clone(),
                        },
                        Tone::for_level(v.gauge.level),
                    ),
                    fact("source", "this client's local telemetry", Tone::Dim),
                ],
            ))
        }
        View::Attention => {
            let r = dash.attention.get(index)?;
            Some((clean(&r.title), attention_facts(r)))
        }
    }
}

pub fn service_facts(r: &ServiceRow) -> Vec<Fact> {
    let mut facts = vec![
        fact("state", r.state_text, Tone::for_level(r.level)),
        fact("owner", clean(&r.owner), Tone::Text),
        fact("purpose", clean(&r.purpose), Tone::Text),
        fact(
            "pid",
            r.pid
                .map(|p| p.to_string())
                .unwrap_or_else(|| "--, no running process".into()),
            Tone::Text,
        ),
        fact("uptime", r.uptime.clone(), Tone::Text),
        fact("restarts", r.restarts.to_string(), Tone::Text),
        fact("ports", r.ports.clone(), Tone::Text),
        fact("cpu", metric_reason(r.cpu), Tone::Text),
        fact(
            "memory",
            if r.memory == format::UNAVAILABLE {
                "--, not reported by the controller".to_string()
            } else {
                r.memory.clone()
            },
            Tone::Text,
        ),
        fact("lease", r.lease.clone(), Tone::Text),
        fact("process", r.process.clone(), Tone::Text),
        fact("listening", r.listening.clone(), Tone::Text),
        fact("health", clean(&r.health), Tone::Text),
    ];
    if r.claimed {
        let reason = match &r.stop {
            Control::Refused(reason) if reason.contains("claimed") => reason.clone(),
            _ => "claimed, not launched: the controller does not signal processes it did not start".into(),
        };
        facts.push(fact("claimed", reason, Tone::Warn));
    }
    for (label, control) in [
        ("restart", &r.restart),
        ("stop", &r.stop),
        ("renew", &r.renew),
        ("logs", &r.logs),
    ] {
        facts.push(fact(
            label,
            control_text(control),
            if control.is_allowed() { Tone::Bright } else { Tone::Dim },
        ));
    }
    if let Some(in_flight) = &r.in_flight {
        facts.push(fact("request", in_flight.clone(), Tone::Warn));
    }
    facts
}

fn attention_facts(r: &AttentionRow) -> Vec<Fact> {
    let mut facts = vec![
        fact("severity", r.severity.label(), severity_tone(r.severity)),
        fact("detail", clean(&r.detail), Tone::Text),
        fact("source", r.source, Tone::Text),
        fact("available", r.available.clone(), Tone::Text),
    ];
    if let Some(id) = &r.service_id {
        facts.push(fact("service", id.chars().take(8).collect::<String>(), Tone::Text));
    }
    if let Some(id) = r.message_id {
        facts.push(fact("message id", id.to_string(), Tone::Text));
    }
    for command in &r.agent_commands {
        facts.push(fact("command", command.clone(), Tone::Dim));
    }
    facts
}

/// The read-only `fleetctl` commands that describe a target, for handing it
/// to an agent session. Commands that change controller state are listed
/// apart and labelled.
#[derive(Debug, Clone, PartialEq)]
pub struct Handoff {
    pub target: String,
    pub read_only: Vec<String>,
    pub changes: Vec<String>,
    pub note: Option<String>,
}

pub const HANDOFF_LIMIT: &str = "Dispatching work to an agent is not available through the controller protocol. Give these commands to an agent session; agents act through fleetctl and never signal processes directly.";

const READ_ONLY_SUBCOMMANDS: [&str; 8] = [
    "list", "show", "agents", "events", "logs", "ping", "doctor", "inbox",
];

pub fn is_read_only_command(command: &str) -> bool {
    let mut words = command.split_whitespace();
    words.next() == Some("fleetctl")
        && words
            .next()
            .is_some_and(|sub| READ_ONLY_SUBCOMMANDS.contains(&sub))
}

fn service_commands(short: &str) -> Vec<String> {
    vec![
        format!("fleetctl show {short}"),
        format!("fleetctl logs {short}"),
        format!("fleetctl logs {short} --err"),
        format!("fleetctl events {short}"),
    ]
}

pub fn handoff(view: View, dash: &Dashboard, index: usize) -> Option<Handoff> {
    let split = |target: String, commands: Vec<String>, note: Option<String>| {
        let (read_only, changes): (Vec<String>, Vec<String>) =
            commands.into_iter().partition(|c| is_read_only_command(c));
        Handoff {
            target,
            read_only,
            changes,
            note,
        }
    };
    if let Some(row) = service_for(view, dash, index) {
        if view != View::Attention {
            return Some(split(
                format!("service {} ({})", clean(&row.name), row.short_id),
                service_commands(&row.short_id),
                row.claimed.then(|| {
                    "Claimed process: visible to the controller, never signalled by it.".to_string()
                }),
            ));
        }
    }
    match view {
        View::Overview => {
            let t = dash.cluster.tiles.get(index)?;
            Some(split(
                format!("node {}", clean(&t.name)),
                vec!["fleetctl doctor".into(), "fleetctl list --all".into()],
                Some("Node metrics come from the controller's device probes and this client's telemetry.".into()),
            ))
        }
        View::Processes => {
            let l = dash.processes.lines.get(index)?;
            Some(split(
                format!(
                    "process {}{}",
                    clean(&l.name),
                    l.pid.map(|p| format!(" (pid {p})")).unwrap_or_default()
                ),
                vec!["fleetctl list --all".into(), "fleetctl doctor".into()],
                Some("This process was not launched by the controller, so no controller command targets it.".into()),
            ))
        }
        View::Services => None,
        View::Agents => {
            let l = dash.agents.transcript.get(index)?;
            let agent = clean(&l.agent);
            Some(split(
                format!("agent {agent}"),
                vec![
                    format!("fleetctl inbox --agent {agent}"),
                    "fleetctl agents".into(),
                ],
                l.question.as_ref().map(|q| {
                    format!("Open question {}: answer here with y or n, or with fleetctl reply {}.", q.message_id, q.message_id)
                }),
            ))
        }
        View::Storage => {
            let v = dash.storage.volumes.get(index)?;
            Some(Handoff {
                target: format!("volume {}", clean(&v.mount)),
                read_only: Vec::new(),
                changes: Vec::new(),
                note: Some(
                    "Storage comes from this client's local telemetry; no fleetctl command reads volumes."
                        .into(),
                ),
            })
        }
        View::Attention => {
            let r = dash.attention.get(index)?;
            Some(split(
                clean(&r.title),
                r.agent_commands.clone(),
                Some(r.available.clone()),
            ))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clean_strips_terminal_sequences() {
        assert_eq!(clean("a\u{1b}[31mred\u{1b}[0m b"), "ared b");
        assert_eq!(clean("x\u{1b}]0;title\u{7}y"), "xy");
        assert_eq!(clean("x\u{1b}]8;;http://e\u{1b}\\link"), "xlink");
        assert_eq!(clean("tab\there\r\n"), "tab here");
        assert_eq!(clean("ñ…"), "ñ…");
    }

    #[test]
    fn read_only_commands_are_recognised() {
        assert!(is_read_only_command("fleetctl show a1b2c3d4"));
        assert!(is_read_only_command("fleetctl inbox --agent codex-3"));
        assert!(!is_read_only_command("fleetctl claim 41822"));
        assert!(!is_read_only_command("fleetctl stop a1"));
        assert!(!is_read_only_command("kill 41822"));
    }

    #[test]
    fn tree_prefixes_draw_structure() {
        use fleet_ui_core::views::ProcessLine;
        let line = |depth, last_child| ProcessLine {
            depth,
            pid: Some(1),
            name: String::new(),
            role: ProcessRole::Other,
            cpu: Metric::Measured(0.0),
            memory: String::new(),
            tag: None,
            last_child,
        };
        let lines = [
            line(0, false),
            line(1, false),
            line(2, true),
            line(1, true),
            line(2, false),
            line(2, true),
            line(0, false),
        ];
        assert_eq!(
            tree_prefixes(&lines),
            vec!["", "├─ ", "│  └─ ", "└─ ", "   ├─ ", "   └─ ", ""]
        );
    }
}
