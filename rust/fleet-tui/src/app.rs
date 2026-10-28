//! Interface state and the key-handling state machine.
//!
//! `App::handle_key` is a pure function of the current state, the key and the
//! dashboard. It never talks to the controller: it returns a `Command`, and
//! the runtime submits any action and reports the result back with
//! `App::submitted`. That keeps the confirmation rule testable without a
//! socket: a destructive action only ever leaves as `Command::Submit` after a
//! `y` on its confirmation line.

use crate::content;
use fleet_ui_core::controller::{Action, LogStream};
use fleet_ui_core::views::{Control, Dashboard, APPROVE_REPLY, DENY_REPLY};
use fleet_ui_core::model::LogChunk;
use std::time::Instant;

/// Lease length the `n` key renews to, matching `fleetctl renew --lease 30m`.
pub const RENEW_SECONDS: f64 = 30.0 * 60.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum View {
    Overview,
    Processes,
    Services,
    Agents,
    Storage,
    Attention,
}

impl View {
    pub const ALL: [View; 6] = [
        View::Overview,
        View::Processes,
        View::Services,
        View::Agents,
        View::Storage,
        View::Attention,
    ];

    pub fn index(self) -> usize {
        self as usize
    }

    pub fn title(self) -> &'static str {
        match self {
            View::Overview => "Overview",
            View::Processes => "Processes",
            View::Services => "Services",
            View::Agents => "Agents",
            View::Storage => "Storage",
            View::Attention => "Attention",
        }
    }

    /// Lowercase name for commands and capture file names.
    pub fn name(self) -> &'static str {
        match self {
            View::Overview => "overview",
            View::Processes => "processes",
            View::Services => "services",
            View::Agents => "agents",
            View::Storage => "storage",
            View::Attention => "attention",
        }
    }
}

/// Keys the interface reacts to, independent of the terminal library.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Key {
    Char(char),
    Enter,
    Esc,
    Up,
    Down,
    PageUp,
    PageDown,
    Home,
    End,
    Tab,
    Backspace,
    Interrupt,
}

/// What the runtime does after a key.
#[derive(Debug, Clone, PartialEq)]
pub enum Command {
    None,
    Quit,
    Submit(Action),
    /// The log tail opened, closed or switched stream: poll now.
    TailChanged,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Pane {
    None,
    Detail,
    Handoff,
    Tail,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Confirm {
    pub action: Action,
    pub prompt: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Tone {
    Info,
    Ok,
    Refused,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Status {
    pub text: String,
    pub tone: Tone,
}

#[derive(Debug, Clone)]
pub struct Tail {
    pub service_id: String,
    pub name: String,
    pub stream: LogStream,
    /// The `Logs` request in flight, if any.
    pub request: Option<u64>,
    pub last_sent: Option<Instant>,
    pub chunk: Option<Result<LogChunk, String>>,
}

#[derive(Debug, Clone, Default)]
struct Selection {
    /// Position in the filtered list.
    position: usize,
    key: Option<String>,
}

#[derive(Debug, Clone)]
pub struct App {
    pub view: View,
    pub pane: Pane,
    pub help: bool,
    pub confirm: Option<Confirm>,
    pub status: Option<Status>,
    pub tail: Option<Tail>,
    /// The filter being typed, if any; the view's filter is updated live.
    pub editing_filter: bool,
    filters: [String; 6],
    selections: [Selection; 6],
    /// First visible row of each view's list, kept between frames.
    pub offsets: [usize; 6],
    quit_armed: bool,
    pub read_only: bool,
}

impl App {
    pub fn new(view: View, read_only: bool) -> Self {
        Self {
            view,
            pane: Pane::None,
            help: false,
            confirm: None,
            status: None,
            tail: None,
            editing_filter: false,
            filters: Default::default(),
            selections: Default::default(),
            offsets: [0; 6],
            quit_armed: false,
            read_only,
        }
    }

    pub fn filter(&self, view: View) -> &str {
        &self.filters[view.index()]
    }

    pub fn visible(&self, view: View, dash: &Dashboard) -> Vec<usize> {
        content::visible(view, dash, self.filter(view))
    }

    /// Position of the selection within the filtered list.
    pub fn position(&self, view: View, dash: &Dashboard) -> Option<usize> {
        let visible = self.visible(view, dash);
        if visible.is_empty() {
            return None;
        }
        let sel = &self.selections[view.index()];
        if let Some(key) = &sel.key {
            if let Some(p) = visible
                .iter()
                .position(|&i| content::key(view, dash, i).as_deref() == Some(key.as_str()))
            {
                return Some(p);
            }
        }
        Some(sel.position.min(visible.len() - 1))
    }

    /// Index into the view's underlying list for the selected row.
    pub fn selected(&self, view: View, dash: &Dashboard) -> Option<usize> {
        let visible = self.visible(view, dash);
        self.position(view, dash).map(|p| visible[p])
    }

    fn select_position(&mut self, view: View, dash: &Dashboard, position: usize) {
        let visible = self.visible(view, dash);
        if visible.is_empty() {
            self.selections[view.index()] = Selection::default();
            return;
        }
        let position = position.min(visible.len() - 1);
        self.selections[view.index()] = Selection {
            position,
            key: content::key(view, dash, visible[position]),
        };
    }

    /// Select a row by its position in the filtered list (mouse clicks).
    pub fn click_row(&mut self, dash: &Dashboard, position: usize) {
        self.select_position(self.view, dash, position);
    }

    /// Re-anchor selections after the dashboard changed, so a selected row
    /// stays selected when rows above it come or go. On the Agents view the
    /// first open question is selected until the person moves.
    pub fn sync(&mut self, dash: &Dashboard) {
        for view in View::ALL {
            if view == View::Agents && self.selections[view.index()].key.is_none() {
                if let Some(i) = dash
                    .agents
                    .transcript
                    .iter()
                    .position(|l| l.question.is_some())
                {
                    let visible = self.visible(view, dash);
                    if let Some(p) = visible.iter().position(|&v| v == i) {
                        self.select_position(view, dash, p);
                        continue;
                    }
                }
            }
            if let Some(p) = self.position(view, dash) {
                self.selections[view.index()].position = p;
            }
        }
    }

    fn move_by(&mut self, dash: &Dashboard, delta: isize) {
        let view = self.view;
        let count = self.visible(view, dash).len();
        if count == 0 {
            return;
        }
        let current = self.position(view, dash).unwrap_or(0) as isize;
        let next = (current + delta).clamp(0, count as isize - 1) as usize;
        self.select_position(view, dash, next);
    }

    fn info(&mut self, text: impl Into<String>) {
        self.status = Some(Status {
            text: text.into(),
            tone: Tone::Info,
        });
    }

    fn refused(&mut self, text: impl Into<String>) {
        self.status = Some(Status {
            text: text.into(),
            tone: Tone::Refused,
        });
    }

    pub fn switch(&mut self, view: View) {
        if self.view != view {
            self.view = view;
            self.pane = if self.pane == Pane::Tail {
                Pane::Tail
            } else {
                Pane::None
            };
            self.editing_filter = false;
        }
    }

    /// Record the runtime's result for a submitted action.
    pub fn submitted(&mut self, action: &Action, result: Result<u64, String>) {
        match result {
            Ok(_) => {
                self.status = Some(Status {
                    text: format!("{} sent to the controller", action.label()),
                    tone: Tone::Ok,
                })
            }
            Err(reason) => self.refused(format!("{} not sent: {reason}", action.label())),
        }
    }

    pub fn handle_key(&mut self, key: Key, dash: &Dashboard) -> Command {
        if key == Key::Interrupt {
            return Command::Quit;
        }
        let armed = std::mem::take(&mut self.quit_armed);

        if let Some(confirm) = self.confirm.take() {
            return match key {
                Key::Char('y') | Key::Char('Y') => {
                    self.status = None;
                    Command::Submit(confirm.action)
                }
                Key::Char('n') | Key::Char('N') | Key::Esc => {
                    self.info(format!("{} cancelled; nothing was sent", confirm.action.label()));
                    Command::None
                }
                _ => {
                    // Anything else leaves the question open.
                    self.confirm = Some(confirm);
                    Command::None
                }
            };
        }

        if self.editing_filter {
            let view = self.view;
            match key {
                Key::Char(c) => self.filters[view.index()].push(c),
                Key::Backspace => {
                    self.filters[view.index()].pop();
                }
                Key::Enter => self.editing_filter = false,
                Key::Esc => {
                    self.filters[view.index()].clear();
                    self.editing_filter = false;
                }
                _ => {}
            }
            self.select_position(view, dash, 0);
            return Command::None;
        }

        if self.help {
            match key {
                Key::Char('q') => return Command::Quit,
                Key::Esc | Key::Char('?') | Key::Enter => self.help = false,
                _ => {}
            }
            return Command::None;
        }

        self.status = None;

        if self.pane == Pane::Tail {
            match key {
                Key::Esc | Key::Char('t') => {
                    self.pane = Pane::None;
                    self.tail = None;
                    return Command::TailChanged;
                }
                Key::Tab => {
                    if let Some(tail) = &mut self.tail {
                        tail.stream = match tail.stream {
                            LogStream::Out => LogStream::Err,
                            LogStream::Err => LogStream::Out,
                        };
                        tail.chunk = None;
                        tail.last_sent = None;
                    }
                    return Command::TailChanged;
                }
                _ => {}
            }
        }

        match key {
            Key::Char(c @ '1'..='6') => {
                self.switch(View::ALL[c as usize - '1' as usize]);
                Command::None
            }
            Key::Char('j') | Key::Down => {
                self.move_by(dash, 1);
                Command::None
            }
            Key::Char('k') | Key::Up => {
                self.move_by(dash, -1);
                Command::None
            }
            Key::PageDown => {
                self.move_by(dash, 10);
                Command::None
            }
            Key::PageUp => {
                self.move_by(dash, -10);
                Command::None
            }
            Key::Char('g') | Key::Home => {
                self.select_position(self.view, dash, 0);
                Command::None
            }
            Key::Char('G') | Key::End => {
                self.select_position(self.view, dash, usize::MAX);
                Command::None
            }
            Key::Enter => {
                self.pane = if self.pane == Pane::Detail {
                    Pane::None
                } else {
                    Pane::Detail
                };
                Command::None
            }
            Key::Esc => {
                if self.pane != Pane::None {
                    self.pane = Pane::None;
                } else if !self.filters[self.view.index()].is_empty() {
                    self.filters[self.view.index()].clear();
                    self.select_position(self.view, dash, 0);
                }
                Command::None
            }
            Key::Char('/') => {
                self.editing_filter = true;
                Command::None
            }
            Key::Char('?') => {
                self.help = true;
                Command::None
            }
            Key::Char('q') => {
                let pending = dash.activity.iter().filter(|a| a.ok.is_none()).count();
                if pending > 0 && !armed {
                    self.quit_armed = true;
                    self.refused(format!(
                        "{pending} controller request{} still in flight. Press q again to quit without waiting.",
                        if pending == 1 { " is" } else { "s are" }
                    ));
                    Command::None
                } else {
                    Command::Quit
                }
            }
            Key::Char('r') => self.lifecycle(dash, LifecycleKey::Restart),
            Key::Char('s') => self.lifecycle(dash, LifecycleKey::Stop),
            Key::Char('t') => self.open_tail(dash),
            Key::Char('a') => {
                match self.selected(self.view, dash) {
                    Some(i) if content::handoff(self.view, dash, i).is_some() => {
                        self.pane = Pane::Handoff
                    }
                    _ => self.info("select an item to hand to an agent"),
                }
                Command::None
            }
            Key::Char('y') => self.reply(dash, true),
            Key::Char('n') => {
                let index = self.selected(self.view, dash);
                let is_question = index
                    .and_then(|i| content::question_for(self.view, dash, i))
                    .is_some();
                if is_question || self.view == View::Agents {
                    self.reply(dash, false)
                } else {
                    self.lifecycle(dash, LifecycleKey::Renew)
                }
            }
            _ => Command::None,
        }
    }

    fn lifecycle(&mut self, dash: &Dashboard, which: LifecycleKey) -> Command {
        let verb = which.verb();
        let Some(index) = self.selected(self.view, dash) else {
            self.info(format!("nothing selected to {verb}"));
            return Command::None;
        };
        let Some(row) = content::service_for(self.view, dash, index) else {
            self.info(format!(
                "{verb} applies to a managed service; select one in 3 Services"
            ));
            return Command::None;
        };
        let (control, action) = match which {
            LifecycleKey::Restart => (
                &row.restart,
                Action::Restart {
                    service_id: row.id.clone(),
                },
            ),
            LifecycleKey::Stop => (
                &row.stop,
                Action::Stop {
                    service_id: row.id.clone(),
                },
            ),
            LifecycleKey::Renew => (
                &row.renew,
                Action::Renew {
                    service_id: row.id.clone(),
                    ttl_sec: RENEW_SECONDS,
                },
            ),
        };
        if let Control::Refused(reason) = control {
            self.refused(format!("{verb} {}: {reason}", content::clean(&row.name)));
            return Command::None;
        }
        if action.needs_confirmation() {
            self.confirm = Some(Confirm {
                prompt: content::confirm_prompt(&action, row),
                action,
            });
            return Command::None;
        }
        Command::Submit(action)
    }

    fn open_tail(&mut self, dash: &Dashboard) -> Command {
        let row = self
            .selected(self.view, dash)
            .and_then(|i| content::service_for(self.view, dash, i));
        let Some(row) = row else {
            self.info("log tail applies to a managed service; select one in 3 Services");
            return Command::None;
        };
        if let Control::Refused(reason) = &row.logs {
            self.refused(format!("logs for {}: {reason}", content::clean(&row.name)));
            return Command::None;
        }
        self.tail = Some(Tail {
            service_id: row.id.clone(),
            name: content::clean(&row.name),
            stream: LogStream::Out,
            request: None,
            last_sent: None,
            chunk: None,
        });
        self.pane = Pane::Tail;
        Command::TailChanged
    }

    fn reply(&mut self, dash: &Dashboard, approve: bool) -> Command {
        let word = if approve { "approve" } else { "deny" };
        let question = self
            .selected(self.view, dash)
            .and_then(|i| content::question_for(self.view, dash, i));
        let Some(q) = question else {
            self.info(format!(
                "{word} answers an open agent question; select a line marked ask in 4 Agents"
            ));
            return Command::None;
        };
        if let Control::Refused(reason) = &q.reply {
            self.refused(format!("{word} question {}: {reason}", q.message_id));
            return Command::None;
        }
        Command::Submit(Action::Reply {
            message_id: q.message_id,
            body: if approve { APPROVE_REPLY } else { DENY_REPLY }.to_string(),
        })
    }
}

#[derive(Clone, Copy)]
enum LifecycleKey {
    Restart,
    Stop,
    Renew,
}

impl LifecycleKey {
    fn verb(self) -> &'static str {
        match self {
            Self::Restart => "restart",
            Self::Stop => "stop",
            Self::Renew => "renew",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::source::tests::dashboard;
    use fleet_ui_core::fixtures::Scenario;
    use fleet_ui_core::model::ServiceState;

    fn select_service(app: &mut App, dash: &Dashboard, name: &str) {
        app.switch(View::Services);
        let i = dash.services.iter().position(|r| r.name == name).unwrap();
        let p = app.visible(View::Services, dash).iter().position(|&v| v == i).unwrap();
        app.click_row(dash, p);
        assert_eq!(app.selected(View::Services, dash), Some(i));
    }

    #[test]
    fn stop_asks_for_confirmation_before_anything_is_sent() {
        let dash = dashboard(Scenario::Healthy, false);
        let mut app = App::new(View::Overview, false);
        select_service(&mut app, &dash, "render-studio");

        assert_eq!(app.handle_key(Key::Char('s'), &dash), Command::None);
        let confirm = app.confirm.clone().expect("confirmation line");
        assert!(confirm.prompt.starts_with("Stop render-studio?"), "{}", confirm.prompt);
        assert!(confirm.prompt.contains("pid 3302"));
        assert!(confirm.prompt.contains("owner codex-1"));

        // Keys other than y and n leave the question open and send nothing.
        assert_eq!(app.handle_key(Key::Char('j'), &dash), Command::None);
        assert!(app.confirm.is_some());

        let id = dash.services.iter().find(|r| r.name == "render-studio").unwrap().id.clone();
        assert_eq!(
            app.handle_key(Key::Char('y'), &dash),
            Command::Submit(Action::Stop { service_id: id })
        );
        assert!(app.confirm.is_none());
    }

    #[test]
    fn cancelling_a_confirmation_sends_nothing() {
        let dash = dashboard(Scenario::Healthy, false);
        let mut app = App::new(View::Overview, false);
        select_service(&mut app, &dash, "render-studio");
        app.handle_key(Key::Char('r'), &dash);
        assert!(app.confirm.as_ref().unwrap().prompt.starts_with("Restart render-studio?"));
        assert_eq!(app.handle_key(Key::Char('n'), &dash), Command::None);
        assert!(app.confirm.is_none());
        assert!(app.status.as_ref().unwrap().text.contains("nothing was sent"));
        app.handle_key(Key::Char('s'), &dash);
        assert_eq!(app.handle_key(Key::Esc, &dash), Command::None);
        assert!(app.confirm.is_none());
    }

    #[test]
    fn refused_controls_show_the_reason_instead_of_confirming() {
        let dash = dashboard(Scenario::Healthy, false);
        let mut app = App::new(View::Overview, false);
        select_service(&mut app, &dash, "notebook");
        assert_eq!(app.handle_key(Key::Char('s'), &dash), Command::None);
        assert!(app.confirm.is_none());
        let status = app.status.clone().unwrap();
        assert_eq!(status.tone, Tone::Refused);
        assert!(status.text.contains("claimed"), "{}", status.text);

        let read_only = dashboard(Scenario::Healthy, true);
        let mut app = App::new(View::Overview, true);
        select_service(&mut app, &read_only, "render-studio");
        app.handle_key(Key::Char('r'), &read_only);
        assert!(app.confirm.is_none());
        assert!(app.status.unwrap().text.contains("read-only"));
    }

    #[test]
    fn disconnected_controller_disables_every_action() {
        let dash = dashboard(Scenario::Stale, false);
        let mut app = App::new(View::Overview, false);
        select_service(&mut app, &dash, "render-studio");
        for key in ['r', 's', 'n'] {
            assert_eq!(app.handle_key(Key::Char(key), &dash), Command::None);
            assert!(app.confirm.is_none());
            assert!(app.status.as_ref().unwrap().text.contains("not current"));
        }
    }

    #[test]
    fn renew_is_sent_without_confirmation() {
        let dash = dashboard(Scenario::Healthy, false);
        let mut app = App::new(View::Overview, false);
        select_service(&mut app, &dash, "render-studio");
        match app.handle_key(Key::Char('n'), &dash) {
            Command::Submit(Action::Renew { ttl_sec, .. }) => assert_eq!(ttl_sec, RENEW_SECONDS),
            other => panic!("expected renew, got {other:?}"),
        }
    }

    #[test]
    fn agents_view_selects_the_open_question_and_replies() {
        let dash = dashboard(Scenario::Healthy, false);
        let mut app = App::new(View::Agents, false);
        app.sync(&dash);
        let i = app.selected(View::Agents, &dash).unwrap();
        let question = dash.agents.transcript[i].question.clone().expect("open question selected");
        assert_eq!(
            app.handle_key(Key::Char('y'), &dash),
            Command::Submit(Action::Reply {
                message_id: question.message_id,
                body: APPROVE_REPLY.into()
            })
        );
        assert_eq!(
            app.handle_key(Key::Char('n'), &dash),
            Command::Submit(Action::Reply {
                message_id: question.message_id,
                body: DENY_REPLY.into()
            })
        );
        // A status line is not a question.
        app.handle_key(Key::Char('g'), &dash);
        assert_eq!(app.handle_key(Key::Char('y'), &dash), Command::None);
        assert!(app.status.unwrap().text.contains("open agent question"));
    }

    #[test]
    fn filter_narrows_and_escape_clears() {
        let dash = dashboard(Scenario::Healthy, false);
        let mut app = App::new(View::Services, false);
        let all = app.visible(View::Services, &dash).len();
        app.handle_key(Key::Char('/'), &dash);
        for c in "gate".chars() {
            app.handle_key(Key::Char(c), &dash);
        }
        assert_eq!(app.visible(View::Services, &dash).len(), 1);
        app.handle_key(Key::Enter, &dash);
        assert!(!app.editing_filter);
        assert_eq!(app.filter(View::Services), "gate");
        app.handle_key(Key::Esc, &dash);
        assert_eq!(app.visible(View::Services, &dash).len(), all);
    }

    #[test]
    fn tail_opens_for_a_service_and_toggles_streams() {
        let dash = dashboard(Scenario::Healthy, false);
        let mut app = App::new(View::Overview, false);
        select_service(&mut app, &dash, "api-gateway");
        assert_eq!(app.handle_key(Key::Char('t'), &dash), Command::TailChanged);
        assert_eq!(app.pane, Pane::Tail);
        assert_eq!(app.tail.as_ref().unwrap().stream, LogStream::Out);
        assert_eq!(app.handle_key(Key::Tab, &dash), Command::TailChanged);
        assert_eq!(app.tail.as_ref().unwrap().stream, LogStream::Err);
        assert_eq!(app.handle_key(Key::Esc, &dash), Command::TailChanged);
        assert!(app.tail.is_none());
    }

    #[test]
    fn quit_waits_for_a_second_press_while_requests_are_in_flight() {
        let mut dash = dashboard(Scenario::Healthy, false);
        let mut app = App::new(View::Overview, false);
        assert_eq!(app.handle_key(Key::Char('q'), &dash), Command::Quit);
        dash.activity.insert(
            0,
            fleet_ui_core::views::ActivityLine {
                text: "stop in progress".into(),
                ok: None,
            },
        );
        assert_eq!(app.handle_key(Key::Char('q'), &dash), Command::None);
        assert_eq!(app.handle_key(Key::Char('q'), &dash), Command::Quit);
        assert_eq!(app.handle_key(Key::Interrupt, &dash), Command::Quit);
    }

    #[test]
    fn selection_follows_its_row_across_refreshes() {
        let dash = dashboard(Scenario::Healthy, false);
        let mut app = App::new(View::Overview, false);
        select_service(&mut app, &dash, "n8n");
        let mut changed = dash.clone();
        changed.services.retain(|r| r.state != ServiceState::Unhealthy);
        app.sync(&changed);
        let i = app.selected(View::Services, &changed).unwrap();
        assert_eq!(changed.services[i].name, "n8n");
    }
}
