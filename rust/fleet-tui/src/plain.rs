//! Line mode for screen readers and logs: no alternate screen, no box
//! drawing, no block glyphs, no color. Each view prints as sentences. The
//! view reprints when a fact a person would act on changes (a phase, a state,
//! a count, a band), at most every five seconds, or when asked; drifting
//! numbers alone do not trigger a reprint. Commands are read one per line.

use crate::app::{View, RENEW_SECONDS};
use crate::content::{self, clean, speak, spoken_gauge};
use crate::runtime::Msg;
use crate::source::{Settings, Source};
use fleet_ui_core::controller::{Action, ActionPayload, LogStream};
use fleet_ui_core::format;
use fleet_ui_core::views::{Control, Dashboard, Freshness, ServiceRow};
use fleet_ui_core::Phase;
use std::io::Write;
use std::sync::mpsc::{Receiver, RecvTimeoutError};
use std::time::{Duration, Instant};

pub const MIN_REPRINT: Duration = Duration::from_secs(5);
const LOG_LINES: usize = 20;

/// Full text, or the reprint key: the same sentences without values that
/// drift between samples (percentages, sizes, rates, ages).
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Full,
    Key,
}

struct Out {
    mode: Mode,
    lines: Vec<String>,
}

impl Out {
    fn line(&mut self, text: impl Into<String>) {
        self.lines.push(text.into());
    }
    /// A drifting value: kept in full text, dropped from the reprint key.
    fn v(&self, text: impl Into<String>) -> String {
        match self.mode {
            Mode::Full => text.into(),
            Mode::Key => String::new(),
        }
    }
    fn gauge(&self, g: &fleet_ui_core::views::Gauge) -> String {
        match (self.mode, g.metric.reason(), g.level) {
            (Mode::Key, None, Some(level)) => format!("{} {}", g.label.to_lowercase(), level.label()),
            _ => spoken_gauge(g),
        }
    }
}

pub fn header(dash: &Dashboard, mode: Mode) -> Vec<String> {
    let mut out = Out {
        mode,
        lines: Vec::new(),
    };
    let c = &dash.connection;
    let summary = if mode == Mode::Key && c.phase == Phase::Stale {
        "controller data is stale".to_string()
    } else {
        c.summary.trim_end_matches('.').to_string()
    };
    out.line(format!(
        "Fleet Console. Controller {}: {}. {}.",
        c.phase.label(),
        summary,
        dash.header.subtitle
    ));
    if let Some(n) = dash.header.awaiting_reply.filter(|n| *n > 0) {
        out.line(format!(
            "{n} agent question{} awaiting a reply.",
            if n == 1 { " is" } else { "s are" }
        ));
    }
    if c.phase != Phase::Live {
        if let Some(detail) = &c.detail {
            out.line(format!("Detail: {}.", clean(detail).trim_end_matches('.')));
        }
        if c.phase != Phase::Loading {
            out.line("Service controls are disabled until controller data is current.");
        }
    }
    if c.telemetry_phase != Phase::Live {
        out.line(format!("Local telemetry {}.", c.telemetry_phase.label()));
    }
    if c.read_only {
        out.line("This client is read-only.");
    }
    if c.locality == fleet_ui_core::views::Locality::Remote {
        out.line("The controller runs on another machine.");
    }
    if let Some(v) = &c.controller_version {
        out.line(format!("Controller version {}.", clean(v)));
    }
    out.lines
}

pub fn view_lines(view: View, dash: &Dashboard, mode: Mode) -> Vec<String> {
    let mut out = Out {
        mode,
        lines: Vec::new(),
    };
    out.line(format!(
        "View {} of 6: {}.",
        view.index() + 1,
        view.title()
    ));
    match view {
        View::Overview => overview(&mut out, dash),
        View::Processes => processes(&mut out, dash),
        View::Services => services(&mut out, dash),
        View::Agents => agents(&mut out, dash),
        View::Storage => storage(&mut out, dash),
        View::Attention => attention(&mut out, dash),
    }
    if let Some(a) = dash.activity.first() {
        out.line(format!(
            "Latest request: {}.",
            clean(&a.text).trim_end_matches('.')
        ));
    }
    out.lines
}

/// Header and one view, as printed.
pub fn render(view: View, dash: &Dashboard, mode: Mode) -> Vec<String> {
    let mut lines = header(dash, mode);
    lines.extend(view_lines(view, dash, mode));
    lines
}

fn not_current(dash: &Dashboard) -> Option<String> {
    let phase = dash.connection.phase;
    (phase != Phase::Live).then(|| format!("Controller {}, so controller data is not current.", phase.label()))
}

fn overview(out: &mut Out, dash: &Dashboard) {
    let s = &dash.cluster.summary;
    let avg = |m: fleet_ui_core::Metric| match m.value() {
        Some(_) => out.v(speak(&format::percent(m))),
        None => "unavailable".into(),
    };
    out.line(format!(
        "Cluster: {} of {} nodes online. Average cpu {}, memory {}, gpu {}. Agents {}. {} node{} under pressure.",
        s.online,
        s.total,
        avg(s.average_cpu),
        avg(s.average_memory),
        avg(s.average_gpu),
        s.agents.map(|a| a.to_string()).unwrap_or_else(|| "unknown".into()),
        s.needs_attention,
        if s.needs_attention == 1 { "" } else { "s" }
    ));
    for t in &dash.cluster.tiles {
        let gauges: Vec<String> = t.gauges.iter().map(|g| out.gauge(g)).collect();
        let mut text = format!(
            "Node {}, {}{}: {}.",
            clean(&t.name),
            t.state.label(),
            match t.freshness {
                Freshness::Current => "",
                Freshness::Stale => ", not current",
                Freshness::Disconnected => ", controller disconnected",
            },
            gauges.join("; ")
        );
        if let (Some(up), Some(total)) = (t.services_up, t.services_total) {
            text.push_str(&format!(" Services {up} up of {total}."));
        }
        if let Some(u) = &t.uptime {
            let u = out.v(format!(" Uptime {u}."));
            text.push_str(&u);
        }
        if let Some(note) = &t.note {
            if out.mode == Mode::Full {
                text.push_str(&format!(" {}.", clean(note).trim_end_matches('.')));
            }
        }
        out.line(text);
    }
    let n = dash.attention.len();
    out.line(format!(
        "Needs attention: {n} report{}.",
        if n == 1 { "" } else { "s" }
    ));
    for (i, r) in dash.attention.iter().take(5).enumerate() {
        out.line(format!(
            "  {}. {}: {}.",
            i + 1,
            severity_word(r.severity),
            clean(&r.title)
        ));
    }
    if n > 5 {
        out.line(format!("  {} more in view 6, Attention.", n - 5));
    }
    agent_rows(out, dash);
}

fn severity_word(s: fleet_ui_core::views::Severity) -> &'static str {
    match s {
        fleet_ui_core::views::Severity::Critical => "critical",
        fleet_ui_core::views::Severity::Warning => "warning",
        fleet_ui_core::views::Severity::Info => "information",
    }
}

fn agent_rows(out: &mut Out, dash: &Dashboard) {
    let rows = &dash.agents.rows;
    if rows.is_empty() {
        out.line(match not_current(dash) {
            Some(note) => format!("Agents: none shown. {note}"),
            None => "Agents: none reported.".into(),
        });
        return;
    }
    out.line(format!("Agents: {}.", rows.len()));
    for a in rows {
        let runtime = out.v(format!(", running {}", a.runtime));
        out.line(format!(
            "  {}, {}, {}{runtime}.",
            clean(&a.name),
            clean(&a.target),
            a.state
        ));
    }
}

fn processes(out: &mut Out, dash: &Dashboard) {
    let p = &dash.processes;
    if p.lines.is_empty() {
        out.line(if p.phase == Phase::Loading {
            "Processes: waiting for the first sample."
        } else {
            "Processes: none sampled."
        });
        return;
    }
    out.line(format!(
        "Processes: {} on this machine, {} shown.",
        out.v(p.total_processes
            .map(|n| n.to_string())
            .unwrap_or_else(|| "unknown".into())),
        p.lines.len()
    ));
    if let Some(note) = &p.note {
        out.line(note.clone());
    }
    if out.mode == Mode::Key {
        // The tree reorders by CPU every sample; only its roots are facts.
        for l in p.lines.iter().filter(|l| l.depth == 0 && l.role != fleet_ui_core::views::ProcessRole::Other) {
            out.line(format!("  {}, {}", clean(&l.name), l.tag.as_deref().unwrap_or("")));
        }
        return;
    }
    let mut parents: Vec<String> = Vec::new();
    for l in &p.lines {
        parents.truncate(l.depth);
        let under = parents
            .last()
            .map(|p| format!(", under {p}"))
            .unwrap_or_default();
        let pid = l.pid.map(|p| format!(", pid {p}")).unwrap_or_default();
        let figures = if l.pid.is_some() {
            format!(
                ", cpu {}, memory {}",
                match l.cpu.value() {
                    Some(_) => speak(&format::percent(l.cpu)),
                    None => format!(
                        "unavailable, {}",
                        l.cpu.reason().map(|r| r.label()).unwrap_or("")
                    ),
                },
                l.memory
            )
        } else {
            String::new()
        };
        let tag = l
            .tag
            .as_deref()
            .map(|t| format!(", {}", clean(t)))
            .unwrap_or_default();
        out.line(format!("  {}{pid}{under}{figures}{tag}.", clean(&l.name)));
        parents.push(clean(&l.name));
    }
}

fn service_sentence(out: &Out, r: &ServiceRow) -> String {
    let mut text = format!(
        "  {}, id {}, {}{}, pid {}, ",
        clean(&r.name),
        r.short_id,
        r.state_text,
        r.in_flight
            .as_ref()
            .map(|f| format!(" ({f})"))
            .unwrap_or_default(),
        r.pid
            .map(|p| p.to_string())
            .unwrap_or_else(|| "none".into()),
    );
    text.push_str(&out.v(format!("up {}, ", r.uptime)));
    text.push_str(&format!(
        "{} restart{}, ports {}, ",
        r.restarts,
        if r.restarts == 1 { "" } else { "s" },
        r.ports
    ));
    text.push_str(&out.v(format!(
        "cpu {}, memory {}, {}. ",
        match r.cpu.value() {
            Some(_) => speak(&format::percent(r.cpu)),
            None => "unavailable".into(),
        },
        if r.memory == format::UNAVAILABLE {
            "unavailable".to_string()
        } else {
            r.memory.clone()
        },
        r.lease
    )));
    text.push_str(&format!(
        "Evidence: {}; {}; {}.",
        r.process,
        r.listening,
        clean(&r.health)
    ));
    if r.claimed {
        text.push_str(" Claimed, not launched: visible only, never signalled by the controller.");
    }
    text
}

fn services(out: &mut Out, dash: &Dashboard) {
    if dash.services.is_empty() {
        out.line(match not_current(dash) {
            Some(note) => format!("Services: none shown. {note}"),
            None => "Services: no managed services.".into(),
        });
        return;
    }
    out.line(format!("Services: {} managed.", dash.services.len()));
    for r in &dash.services {
        let sentence = service_sentence(out, r);
        out.line(sentence);
    }
    out.line("Act with restart ID, stop ID, renew ID or logs ID; ID is a name or the start of an id.");
}

fn agents(out: &mut Out, dash: &Dashboard) {
    agent_rows(out, dash);
    let a = &dash.agents;
    if a.transcript.is_empty() {
        out.line(match not_current(dash) {
            Some(note) => format!("Transcript: empty. {note}"),
            None => "Transcript: no agent messages.".into(),
        });
        return;
    }
    out.line(format!(
        "Transcript, times in UTC: {} message{}, {} open question{}.",
        a.transcript.len(),
        if a.transcript.len() == 1 { "" } else { "s" },
        a.open_questions,
        if a.open_questions == 1 { "" } else { "s" }
    ));
    let shown = a.transcript.len().saturating_sub(30);
    if shown > 0 {
        out.line(format!("  {shown} older messages not printed."));
    }
    for l in a.transcript.iter().skip(shown) {
        let mut text = format!(
            "  {} {} {}: {}.",
            l.time,
            clean(&l.agent),
            l.verb,
            clean(&l.text).trim_end_matches('.')
        );
        if let Some(q) = &l.question {
            match &q.reply {
                Control::Allowed => text.push_str(&format!(
                    " Open question {id}: answer with approve {id} or deny {id}.",
                    id = q.message_id
                )),
                Control::Refused(reason) => {
                    text.push_str(&format!(" Open question {}: {reason}.", q.message_id))
                }
            }
        }
        out.line(text);
    }
}

fn storage(out: &mut Out, dash: &Dashboard) {
    let s = &dash.storage;
    if s.volumes.is_empty() {
        out.line(if s.phase == Phase::Loading {
            "Storage: waiting for the first telemetry sample."
        } else {
            "Storage: no volumes reported."
        });
    } else {
        out.line(format!(
            "Storage: {} volume{}.",
            s.volumes.len(),
            if s.volumes.len() == 1 { "" } else { "s" }
        ));
        for v in &s.volumes {
            let share = match (v.gauge.metric.reason(), v.gauge.level) {
                (Some(reason), _) => format!("used share unavailable, {}", reason.label()),
                (None, Some(level)) => format!(
                    "{}{}",
                    out.v(format!("{} used, ", speak(&v.gauge.text))),
                    speak(level.label())
                ),
                (None, None) => out.v(speak(&v.gauge.text)),
            };
            out.line(format!(
                "  {}, {}, {}{}.",
                clean(&v.mount),
                clean(&v.filesystem),
                out.v(format!(
                    "{} used, {} free, of {}, ",
                    v.used, v.free, v.total
                )),
                share
            ));
        }
    }
    match &s.largest_paths {
        Ok(paths) if paths.is_empty() => out.line("Largest paths: none reported."),
        Ok(paths) => {
            out.line("Largest paths:");
            for (size, path) in paths {
                out.line(format!("  {size}, {}.", clean(path)));
            }
        }
        Err(reason) => out.line(format!("Largest paths: unavailable, {reason}.")),
    }
}

fn attention(out: &mut Out, dash: &Dashboard) {
    if dash.attention.is_empty() {
        out.line(match not_current(dash) {
            Some(note) => format!("Attention: no reports from local telemetry. {note}"),
            None => "Attention: nothing needs attention.".into(),
        });
        return;
    }
    out.line(format!("Attention: {} reports.", dash.attention.len()));
    for (i, r) in dash.attention.iter().enumerate() {
        let commands = r
            .agent_commands
            .iter()
            .map(|c| {
                if content::is_read_only_command(c) {
                    c.clone()
                } else {
                    format!("{c} (changes controller state)")
                }
            })
            .collect::<Vec<_>>();
        out.line(format!(
            "  {}. {}: {}. {}. Source {}. Available: {}.{}",
            i + 1,
            severity_word(r.severity),
            clean(&r.title),
            clean(&r.detail).trim_end_matches('.'),
            r.source,
            r.available,
            if commands.is_empty() {
                String::new()
            } else {
                format!(" Agent commands: {}.", commands.join("; "))
            }
        ));
    }
}

pub fn help() -> Vec<String> {
    vec![
        "Commands: 1 to 6, or a view name, switches view and prints it. An empty line or print reprints. help lists commands. q quits.".into(),
        "Views: 1 overview, 2 processes, 3 services, 4 agents, 5 storage, 6 attention.".into(),
        "Service actions: restart ID, stop ID, renew ID for a 30 minute lease, logs ID or logs ID err, show ID, agent ID. ID is a service name or the start of its id.".into(),
        "Agent questions: approve MESSAGE-ID, deny MESSAGE-ID.".into(),
        "Restart and stop print the evidence and wait for y to confirm or n to cancel.".into(),
    ]
}

/// Resolve a service by exact name, full id or id prefix.
pub fn find_service<'a>(dash: &'a Dashboard, needle: &str) -> Result<&'a ServiceRow, String> {
    let needle = needle.trim();
    if needle.is_empty() {
        return Err("name a service: its name or the start of its id".into());
    }
    if let Some(r) = dash
        .services
        .iter()
        .find(|r| r.id == needle || r.name.eq_ignore_ascii_case(needle))
    {
        return Ok(r);
    }
    let matches: Vec<&ServiceRow> = dash
        .services
        .iter()
        .filter(|r| r.id.starts_with(needle))
        .collect();
    match matches.as_slice() {
        [one] => Ok(one),
        [] => Err(format!("no service named or with an id starting {needle}")),
        many => Err(format!(
            "{} services have ids starting {needle}; give more of the id",
            many.len()
        )),
    }
}

/// What a typed line asks for.
#[derive(Debug, Clone, PartialEq)]
pub enum Request {
    View(View),
    Print,
    Help,
    Quit,
    /// Text to print, nothing to send.
    Say(Vec<String>),
    Confirm { action: Action, prompt: String },
    Send(Action),
    Logs { service_id: String, name: String, stream: LogStream },
}

pub fn interpret(line: &str, dash: &Dashboard) -> Request {
    let words: Vec<&str> = line.split_whitespace().collect();
    let Some(first) = words.first().map(|w| w.to_ascii_lowercase()) else {
        return Request::Print;
    };
    let arg = words.get(1).copied().unwrap_or("");
    if let Some(crate::cli::StartView::One(view)) = crate::cli::parse_view(&first) {
        return Request::View(view);
    }
    let refused = |verb: &str, name: &str, reason: &str| {
        Request::Say(vec![format!("{verb} {name} is not available: {reason}.")])
    };
    match first.as_str() {
        "q" | "quit" | "exit" => Request::Quit,
        "help" | "?" | "h" => Request::Help,
        "print" | "p" | "r" | "refresh" => Request::Print,
        "restart" | "stop" | "renew" => {
            let row = match find_service(dash, arg) {
                Ok(row) => row,
                Err(e) => return Request::Say(vec![format!("{e}.")]),
            };
            let name = clean(&row.name);
            let (control, action) = match first.as_str() {
                "restart" => (&row.restart, Action::Restart { service_id: row.id.clone() }),
                "stop" => (&row.stop, Action::Stop { service_id: row.id.clone() }),
                _ => (
                    &row.renew,
                    Action::Renew {
                        service_id: row.id.clone(),
                        ttl_sec: RENEW_SECONDS,
                    },
                ),
            };
            if let Control::Refused(reason) = control {
                return refused(&first, &name, reason);
            }
            if action.needs_confirmation() {
                Request::Confirm {
                    prompt: format!(
                        "{} Type y to confirm or n to cancel.",
                        content::confirm_prompt(&action, row)
                    ),
                    action,
                }
            } else {
                Request::Send(action)
            }
        }
        "logs" | "tail" => match find_service(dash, arg) {
            Ok(row) => Request::Logs {
                service_id: row.id.clone(),
                name: clean(&row.name),
                stream: if words.get(2).is_some_and(|w| w.starts_with("err")) {
                    LogStream::Err
                } else {
                    LogStream::Out
                },
            },
            Err(e) => Request::Say(vec![format!("{e}.")]),
        },
        "show" => match find_service(dash, arg) {
            Ok(row) => Request::Say(
                std::iter::once(format!("Service {} {}:", clean(&row.name), row.short_id))
                    .chain(
                        content::service_facts(row)
                            .into_iter()
                            .map(|f| format!("  {}: {}.", f.label, f.text.trim_end_matches('.'))),
                    )
                    .collect(),
            ),
            Err(e) => Request::Say(vec![format!("{e}.")]),
        },
        "agent" | "a" => match find_service(dash, arg) {
            Ok(row) => {
                let i = dash.services.iter().position(|r| r.id == row.id).unwrap_or(0);
                let mut lines = Vec::new();
                if let Some(h) = content::handoff(View::Services, dash, i) {
                    lines.push(format!("Target: {}.", h.target));
                    lines.push("Read-only commands for an agent:".into());
                    lines.extend(h.read_only.iter().map(|c| format!("  {c}")));
                    if let Some(note) = h.note {
                        lines.push(note);
                    }
                }
                lines.push(content::HANDOFF_LIMIT.into());
                Request::Say(lines)
            }
            Err(e) => Request::Say(vec![format!("{e}.")]),
        },
        "approve" | "deny" => {
            let Ok(id) = arg.parse::<i64>() else {
                return Request::Say(vec![format!("{first} needs a message id, such as {first} 43.")]);
            };
            match content::question_by_id(dash, id) {
                None => Request::Say(vec![format!("No open question with message id {id}.")]),
                Some(q) => match q.reply {
                    Control::Refused(reason) => refused(&first, &format!("question {id}"), &reason),
                    Control::Allowed => Request::Send(Action::Reply {
                        message_id: id,
                        body: if first == "approve" {
                            fleet_ui_core::views::APPROVE_REPLY
                        } else {
                            fleet_ui_core::views::DENY_REPLY
                        }
                        .to_string(),
                    }),
                },
            }
        }
        other => Request::Say(vec![format!(
            "Unknown command {other}. Type help for the list."
        )]),
    }
}

fn emit(lines: &[String]) {
    let stdout = std::io::stdout();
    let mut out = stdout.lock();
    for line in lines {
        let _ = writeln!(out, "{line}");
    }
    let _ = out.flush();
}

pub fn print_once(source: &Source, settings: &Settings, views: &[View]) {
    let dash = source.dashboard(settings);
    let mut lines = header(&dash, Mode::Full);
    for (i, view) in views.iter().enumerate() {
        if i > 0 || !lines.is_empty() {
            lines.push(String::new());
        }
        lines.extend(view_lines(*view, &dash, Mode::Full));
    }
    emit(&lines);
}

/// The interactive line loop. Returns the process exit code.
pub fn run(source: &Source, settings: &Settings, start: View, rx: &Receiver<Msg>) -> i32 {
    let mut view = start;
    let mut dash = source.dashboard(settings);
    emit(&render(view, &dash, Mode::Full));
    emit(&["Type help for commands.".to_string()]);
    let mut printed_key = render(view, &dash, Mode::Key);
    let mut printed_at = Instant::now();
    let mut generation = source.generation();
    let mut confirm: Option<Action> = None;
    let mut logs: Option<(u64, String)> = None;
    let mut sent: Vec<u64> = Vec::new();

    loop {
        let wait = if render(view, &dash, Mode::Key) != printed_key {
            MIN_REPRINT.saturating_sub(printed_at.elapsed())
        } else {
            Duration::from_secs(30)
        };
        let message = rx.recv_timeout(wait);
        let mut print_now = false;
        match message {
            Ok(Msg::Line(line)) => {
                if let Some(action) = confirm.take() {
                    match line.trim().to_ascii_lowercase().as_str() {
                        "y" | "yes" => send(source, action, &mut sent),
                        "n" | "no" => emit(&[format!(
                            "{} cancelled; nothing was sent.",
                            action.label()
                        )]),
                        _ => {
                            emit(&["Type y to confirm or n to cancel.".to_string()]);
                            confirm = Some(action);
                        }
                    }
                    continue;
                }
                dash = source.dashboard(settings);
                match interpret(&line, &dash) {
                    Request::View(v) => {
                        view = v;
                        print_now = true;
                    }
                    Request::Print => print_now = true,
                    Request::Help => emit(&help()),
                    Request::Quit => return 0,
                    Request::Say(lines) => emit(&lines),
                    Request::Confirm { action, prompt } => {
                        emit(&[prompt]);
                        confirm = Some(action);
                    }
                    Request::Send(action) => send(source, action, &mut sent),
                    Request::Logs {
                        service_id,
                        name,
                        stream,
                    } => match source.submit(Action::Logs { service_id, stream }) {
                        Ok(id) => logs = Some((id, name)),
                        Err(e) => emit(&[format!("Logs not read: {e}.")]),
                    },
                }
            }
            // Without input the client keeps reporting changes, like a monitor.
            Ok(Msg::Eof) => {}
            Ok(Msg::Wake) | Ok(Msg::Event(_)) | Ok(Msg::InputError(_)) => {}
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => return 0,
        }
        let now_generation = source.generation();
        if now_generation != generation {
            generation = now_generation;
            dash = source.dashboard(settings);
            if let Some((id, name)) = &logs {
                if let Some(outcome) = source.outcome(*id) {
                    emit(&log_lines(name, &outcome.result));
                    logs = None;
                }
            }
            sent.retain(|id| match source.outcome(*id) {
                Some(outcome) => {
                    emit(&[match &outcome.result {
                        Ok(_) => format!("{} accepted by the controller.", outcome.action.label()),
                        Err(e) => format!("{} failed: {}.", outcome.action.label(), clean(e)),
                    }]);
                    false
                }
                None => true,
            });
        }
        let key = render(view, &dash, Mode::Key);
        if print_now || (key != printed_key && printed_at.elapsed() >= MIN_REPRINT) {
            emit(&[String::new()]);
            emit(&render(view, &dash, Mode::Full));
            printed_key = key;
            printed_at = Instant::now();
        }
    }
}

fn send(source: &Source, action: Action, sent: &mut Vec<u64>) {
    match source.submit(action.clone()) {
        Ok(id) => {
            sent.push(id);
            emit(&[format!("{} sent to the controller.", action.label())]);
        }
        Err(e) => emit(&[format!("{} not sent: {}.", action.label(), clean(&e))]),
    }
}

fn log_lines(name: &str, result: &Result<ActionPayload, String>) -> Vec<String> {
    match result {
        Ok(ActionPayload::Logs(chunk)) => {
            let text = chunk.text.trim_end();
            if text.is_empty() {
                return vec![format!("The std{} log of {name} is empty.", chunk.stream)];
            }
            let lines: Vec<&str> = text.lines().collect();
            let skip = lines.len().saturating_sub(LOG_LINES);
            std::iter::once(format!(
                "Last {} lines of the std{} log of {name}:",
                lines.len() - skip,
                chunk.stream
            ))
            .chain(lines.into_iter().skip(skip).map(|l| format!("  {}", clean(l))))
            .collect()
        }
        Ok(_) => vec![format!("The controller sent no log text for {name}.")],
        Err(e) => vec![format!("Logs of {name} not read: {}.", clean(e))],
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::source::tests::dashboard;
    use fleet_ui_core::fixtures::Scenario;

    fn is_drawing(c: char) -> bool {
        // Box drawing, block elements and geometric shapes.
        ('\u{2500}'..='\u{25FF}').contains(&c)
    }

    #[test]
    fn plain_output_has_no_box_drawing_or_block_characters() {
        for scenario in Scenario::ALL {
            let dash = dashboard(scenario, false);
            for view in View::ALL {
                for mode in [Mode::Full, Mode::Key] {
                    for line in render(view, &dash, mode) {
                        assert!(
                            !line.chars().any(is_drawing),
                            "{} {}: {line}",
                            scenario.name(),
                            view.name()
                        );
                        assert!(!line.contains(" | ") && !line.contains('·'), "{line}");
                        assert!(!line.contains('\u{1b}'), "escape in {line}");
                    }
                }
            }
        }
    }

    #[test]
    fn plain_gauges_are_spoken() {
        let dash = dashboard(Scenario::Healthy, false);
        let text = render(View::Overview, &dash, Mode::Full).join("\n");
        assert!(text.contains("percent, normal") || text.contains("percent, above 50 percent"), "{text}");
        assert!(text.contains("gpu unavailable, not measured on this platform"), "{text}");
        assert!(!text.contains('%'), "{text}");
    }

    #[test]
    fn disconnected_plain_output_says_so() {
        let dash = dashboard(Scenario::Disconnected, false);
        let text = render(View::Services, &dash, Mode::Full).join("\n");
        assert!(text.contains("Controller disconnected"), "{text}");
        assert!(text.contains("no controller socket"), "{text}");
        assert!(text.contains("not current"), "{text}");
    }

    #[test]
    fn reprint_key_ignores_drifting_numbers() {
        let a = dashboard(Scenario::Healthy, false);
        let mut b = a.clone();
        b.quick.cpu.text = "99%".into();
        for tile in &mut b.cluster.tiles {
            for g in &mut tile.gauges {
                if g.label == "cpu" {
                    g.text = "31%".into();
                }
            }
        }
        assert_eq!(render(View::Overview, &a, Mode::Key), render(View::Overview, &b, Mode::Key));
        let mut c = a.clone();
        c.header.subtitle = "4 services running".into();
        assert_ne!(render(View::Overview, &a, Mode::Key), render(View::Overview, &c, Mode::Key));
    }

    #[test]
    fn commands_confirm_destructive_actions() {
        let dash = dashboard(Scenario::Healthy, false);
        match interpret("stop render-studio", &dash) {
            Request::Confirm { action, prompt } => {
                assert!(matches!(action, Action::Stop { .. }));
                assert!(prompt.starts_with("Stop render-studio?"), "{prompt}");
                assert!(prompt.contains("Type y to confirm"));
            }
            other => panic!("expected confirmation, got {other:?}"),
        }
        assert!(matches!(interpret("renew b2", &dash), Request::Send(Action::Renew { .. })));
        assert!(matches!(interpret("stop notebook", &dash), Request::Say(_)));
        assert!(matches!(interpret("approve 43", &dash), Request::Send(Action::Reply { message_id: 43, .. })));
        assert!(matches!(interpret("approve 41", &dash), Request::Say(_)));
        assert_eq!(interpret("3", &dash), Request::View(View::Services));
        assert_eq!(interpret("storage", &dash), Request::View(View::Storage));
        assert_eq!(interpret("q", &dash), Request::Quit);
        assert_eq!(interpret("", &dash), Request::Print);
    }

    #[test]
    fn service_lookup_reports_ambiguity() {
        let dash = dashboard(Scenario::Flood, false);
        assert!(find_service(&dash, "0000").unwrap_err().contains("services have ids starting"));
        assert_eq!(find_service(&dash, "API-GATEWAY").unwrap().name, "api-gateway");
    }
}
