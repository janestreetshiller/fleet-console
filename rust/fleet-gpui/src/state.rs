//! What the full window is showing and what a key or click does.
//!
//! A pure state machine over `Dashboard`: `handle_key` and the request
//! helpers return `Effect`s, and the window applies them (submit to the
//! controller, post a notice, quit). Keeping GPUI out of this module is what
//! lets the keyboard, selection and confirmation rules be tested against
//! fixtures.

use fleet_ui_core::controller::{Action, LogStream};
use fleet_ui_core::views::{Control, Dashboard, ServiceRow, APPROVE_REPLY, DENY_REPLY};

/// Lease renewal requested by `n` in the Services view, matching the
/// `fleetctl renew <id> --lease 30m` example in docs/AGENTS.md.
pub const RENEW_SECONDS: f64 = 1_800.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum View {
    Overview,
    Processes,
    Services,
    Agents,
    Storage,
    Attention,
    /// The relational map: controller, devices, services, agents, processes
    /// and volumes as one graph.
    Map,
}

impl View {
    pub const ALL: [View; 7] = [
        Self::Overview,
        Self::Processes,
        Self::Services,
        Self::Agents,
        Self::Storage,
        Self::Attention,
        Self::Map,
    ];

    pub fn index(self) -> usize {
        Self::ALL.iter().position(|v| *v == self).unwrap_or(0)
    }

    /// The `1` to `7` key that selects it.
    pub fn number(self) -> usize {
        self.index() + 1
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Overview => "Overview",
            Self::Processes => "Processes",
            Self::Services => "Services",
            Self::Agents => "Agents",
            Self::Storage => "Storage",
            Self::Attention => "Attention",
            Self::Map => "Map",
        }
    }

    pub fn from_number(number: usize) -> Option<Self> {
        number
            .checked_sub(1)
            .and_then(|i| Self::ALL.get(i).copied())
    }

    /// `1` to `6` or a view name, case-insensitive.
    pub fn parse(text: &str) -> Option<Self> {
        if let Ok(number) = text.parse::<usize>() {
            return Self::from_number(number);
        }
        let lower = text.to_ascii_lowercase();
        Self::ALL
            .into_iter()
            .find(|v| v.label().to_ascii_lowercase() == lower)
    }
}

/// A key as the state machine sees it. The window maps GPUI keystrokes here.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Key {
    Char(char),
    Up,
    Down,
    Enter,
    Escape,
    /// `cmd-q` or `ctrl-q`.
    Quit,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ServiceCommand {
    Restart,
    Stop,
    Pause,
    Resume,
    Renew,
    Logs,
}

impl ServiceCommand {
    pub fn verb(self) -> &'static str {
        match self {
            Self::Restart => "restart",
            Self::Stop => "stop",
            Self::Pause => "pause",
            Self::Resume => "resume",
            Self::Renew => "renew",
            Self::Logs => "read logs",
        }
    }

    pub fn control(self, row: &ServiceRow) -> &Control {
        match self {
            Self::Restart => &row.restart,
            Self::Stop => &row.stop,
            Self::Pause => &row.pause,
            Self::Resume => &row.resume,
            Self::Renew => &row.renew,
            Self::Logs => &row.logs,
        }
    }

    pub fn action(self, service_id: &str) -> Action {
        let service_id = service_id.to_string();
        match self {
            Self::Restart => Action::Restart { service_id },
            Self::Stop => Action::Stop { service_id },
            Self::Pause => Action::Pause { service_id },
            Self::Resume => Action::Resume { service_id },
            Self::Renew => Action::Renew {
                service_id,
                ttl_sec: RENEW_SECONDS,
            },
            Self::Logs => Action::Logs {
                service_id,
                stream: LogStream::Out,
            },
        }
    }
}

/// A destructive action waiting for the operator to confirm it.
#[derive(Debug, Clone, PartialEq)]
pub struct Confirmation {
    pub action: Action,
    pub prompt: String,
    pub confirm_label: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Effect {
    Submit(Action),
    Notice(String),
    Quit,
    /// Bring this row of this view into the visible part of its list.
    Reveal(View, usize),
}

#[derive(Debug, Clone, Default, PartialEq)]
struct Selection {
    index: usize,
    /// A stable identity for the selected row, so a list that reorders or
    /// grows between polls keeps the same row selected.
    key: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct UiState {
    pub view: View,
    selections: [Selection; 7],
    /// `enter` expands the selected tile, process, service or volume.
    pub inspecting: bool,
    pub confirm: Option<Confirmation>,
}

impl UiState {
    pub fn new(view: View) -> Self {
        Self {
            view,
            selections: Default::default(),
            inspecting: false,
            confirm: None,
        }
    }

    pub fn set_view(&mut self, view: View) {
        if self.view != view {
            self.inspecting = false;
        }
        self.view = view;
    }

    /// The selected row of `view` in this dashboard, if the list has rows.
    pub fn selected(&self, view: View, dash: &Dashboard) -> Option<usize> {
        let keys = row_keys(view, dash);
        if keys.is_empty() {
            return None;
        }
        let selection = &self.selections[view.index()];
        if let Some(key) = &selection.key {
            if let Some(found) = keys.iter().position(|k| k == key) {
                return Some(found);
            }
        }
        Some(selection.index.min(keys.len() - 1))
    }

    pub fn select(&mut self, view: View, index: usize, dash: &Dashboard) {
        let keys = row_keys(view, dash);
        if keys.is_empty() {
            return;
        }
        let index = index.min(keys.len() - 1);
        self.selections[view.index()] = Selection {
            index,
            key: Some(keys[index].clone()),
        };
    }

    fn select_key(&mut self, view: View, key: &str, dash: &Dashboard) -> bool {
        match row_keys(view, dash).iter().position(|k| k == key) {
            Some(index) => {
                self.select(view, index, dash);
                true
            }
            None => false,
        }
    }

    /// The selected service row, from the Services view or from a selected
    /// Attention report that names a service.
    pub fn selected_service<'a>(&self, dash: &'a Dashboard) -> Option<&'a ServiceRow> {
        match self.view {
            View::Services => self
                .selected(View::Services, dash)
                .and_then(|i| dash.services.get(i)),
            View::Attention => {
                let row = dash
                    .attention
                    .get(self.selected(View::Attention, dash)?)?;
                let id = row.service_id.as_ref()?;
                dash.services.iter().find(|s| &s.id == id)
            }
            _ => None,
        }
    }

    pub fn handle_key(&mut self, key: Key, dash: &Dashboard) -> Vec<Effect> {
        if key == Key::Quit {
            return vec![Effect::Quit];
        }
        if self.confirm.is_some() {
            return match key {
                Key::Char('y') | Key::Enter => self.confirm(),
                Key::Char('n') | Key::Escape => {
                    self.cancel();
                    Vec::new()
                }
                _ => Vec::new(),
            };
        }
        match key {
            Key::Char(c @ '1'..='7') => {
                let number = c.to_digit(10).unwrap_or(1) as usize;
                if let Some(view) = View::from_number(number) {
                    self.set_view(view);
                }
                self.reveal(dash)
            }
            Key::Char('j') | Key::Down => self.move_selection(1, dash),
            Key::Char('k') | Key::Up => self.move_selection(-1, dash),
            Key::Escape => {
                self.inspecting = false;
                Vec::new()
            }
            Key::Enter => self.enter(dash),
            Key::Char('r') => self.service_key(ServiceCommand::Restart, dash),
            Key::Char('s') => self.service_key(ServiceCommand::Stop, dash),
            Key::Char('t') => self.service_key(ServiceCommand::Logs, dash),
            Key::Char('n') if self.view == View::Agents => self.answer_selected(false, dash),
            Key::Char('n') => self.service_key(ServiceCommand::Renew, dash),
            Key::Char('y') if self.view == View::Agents => self.answer_selected(true, dash),
            _ => Vec::new(),
        }
    }

    fn reveal(&self, dash: &Dashboard) -> Vec<Effect> {
        self.selected(self.view, dash)
            .map(|i| vec![Effect::Reveal(self.view, i)])
            .unwrap_or_default()
    }

    fn move_selection(&mut self, delta: isize, dash: &Dashboard) -> Vec<Effect> {
        let Some(current) = self.selected(self.view, dash) else {
            return Vec::new();
        };
        let len = row_keys(self.view, dash).len();
        let next = (current as isize + delta).clamp(0, len as isize - 1) as usize;
        self.select(self.view, next, dash);
        vec![Effect::Reveal(self.view, next)]
    }

    fn enter(&mut self, dash: &Dashboard) -> Vec<Effect> {
        match self.view {
            View::Attention => {
                let Some(row) = self
                    .selected(View::Attention, dash)
                    .and_then(|i| dash.attention.get(i))
                else {
                    return Vec::new();
                };
                if let Some(id) = row.service_id.clone() {
                    if dash.services.iter().any(|s| s.id == id) {
                        self.set_view(View::Services);
                        self.select_key(View::Services, &id, dash);
                        self.inspecting = true;
                        return self.reveal(dash);
                    }
                }
                if let Some(message_id) = row.message_id {
                    self.set_view(View::Agents);
                    self.select_key(View::Agents, &question_key(message_id), dash);
                    return self.reveal(dash);
                }
                vec![Effect::Notice(format!(
                    "{}: {}",
                    row.title, row.available
                ))]
            }
            // Process lines, volumes and transcript lines show everything
            // they have inline; there is nothing more to expand.
            View::Agents | View::Processes | View::Storage => Vec::new(),
            // A map node's inspector is drawn beside the graph; `enter`
            // opens and closes it over the selected node.
            View::Overview | View::Services | View::Map => {
                if self.selected(self.view, dash).is_some() {
                    self.inspecting = !self.inspecting;
                }
                Vec::new()
            }
        }
    }

    fn service_key(&mut self, command: ServiceCommand, dash: &Dashboard) -> Vec<Effect> {
        if !matches!(self.view, View::Services | View::Attention) {
            return Vec::new();
        }
        match self.selected_service(dash) {
            Some(row) => {
                let id = row.id.clone();
                self.request(command, &id, dash)
            }
            None if self.view == View::Attention => vec![Effect::Notice(
                "the selected report names no managed service".into(),
            )],
            None => Vec::new(),
        }
    }

    /// Ask for a service action. A refused control becomes a notice with the
    /// refusal reason; a destructive action opens the confirmation step; any
    /// other action is submitted.
    pub fn request(
        &mut self,
        command: ServiceCommand,
        service_id: &str,
        dash: &Dashboard,
    ) -> Vec<Effect> {
        let Some(row) = dash.services.iter().find(|s| s.id == service_id) else {
            return vec![Effect::Notice(format!(
                "{} unavailable: the service is no longer in the controller snapshot",
                command.verb()
            ))];
        };
        if let Control::Refused(reason) = command.control(row) {
            return vec![Effect::Notice(format!(
                "{} {} unavailable: {reason}",
                command.verb(),
                row.name
            ))];
        }
        let action = command.action(&row.id);
        if action.needs_confirmation() {
            self.confirm = Some(Confirmation {
                prompt: confirmation_prompt(command, &row.name),
                confirm_label: format!("{} {}", command.verb(), row.name),
                action,
            });
            Vec::new()
        } else {
            vec![Effect::Submit(action)]
        }
    }

    fn answer_selected(&mut self, approve: bool, dash: &Dashboard) -> Vec<Effect> {
        let line = self
            .selected(View::Agents, dash)
            .and_then(|i| dash.agents.transcript.get(i));
        match line.and_then(|l| l.question.as_ref()) {
            Some(question) => self.answer(question.message_id, approve, dash),
            None => vec![Effect::Notice(
                "select a question that is waiting for an answer".into(),
            )],
        }
    }

    /// Approve or deny an agent's open question.
    pub fn answer(&mut self, message_id: i64, approve: bool, dash: &Dashboard) -> Vec<Effect> {
        let question = dash
            .agents
            .transcript
            .iter()
            .filter_map(|l| l.question.as_ref())
            .find(|q| q.message_id == message_id);
        let verb = if approve { "approve" } else { "deny" };
        match question {
            None => vec![Effect::Notice(format!(
                "{verb} unavailable: the question is no longer open"
            ))],
            Some(q) => match &q.reply {
                Control::Refused(reason) => {
                    vec![Effect::Notice(format!("{verb} unavailable: {reason}"))]
                }
                Control::Allowed => vec![Effect::Submit(Action::Reply {
                    message_id,
                    body: if approve { APPROVE_REPLY } else { DENY_REPLY }.to_string(),
                })],
            },
        }
    }

    /// When the Agents view has never had a selection, start on the first
    /// open question so `y` and `n` act on it without moving first.
    pub fn prefer_open_question(&mut self, dash: &Dashboard) {
        if self.selections[View::Agents.index()].key.is_none() {
            if let Some(index) = first_open_question(dash) {
                self.select(View::Agents, index, dash);
            }
        }
    }

    pub fn confirm(&mut self) -> Vec<Effect> {
        match self.confirm.take() {
            Some(c) => vec![Effect::Submit(c.action)],
            None => Vec::new(),
        }
    }

    pub fn cancel(&mut self) {
        self.confirm = None;
    }
}

fn confirmation_prompt(command: ServiceCommand, name: &str) -> String {
    match command {
        ServiceCommand::Stop => format!(
            "Stop {name}? The controller ends the process group it launched and the service stays stopped."
        ),
        ServiceCommand::Restart => format!(
            "Restart {name}? Work in progress is interrupted while the controller restarts it."
        ),
        ServiceCommand::Pause => format!(
            "Pause {name}? It keeps its memory and ports while paused, and its lease does not expire until it resumes."
        ),
        other => format!("{} {name}?", other.verb()),
    }
}

pub fn question_key(message_id: i64) -> String {
    format!("question-{message_id}")
}

/// Stable identities for the rows of a view, in display order.
pub fn row_keys(view: View, dash: &Dashboard) -> Vec<String> {
    match view {
        View::Overview => dash.cluster.tiles.iter().map(|t| t.id.clone()).collect(),
        View::Processes => dash
            .processes
            .lines
            .iter()
            .enumerate()
            .map(|(i, l)| match l.pid {
                Some(pid) => format!("pid-{pid}"),
                None => format!("line-{i}"),
            })
            .collect(),
        View::Services => dash.services.iter().map(|s| s.id.clone()).collect(),
        View::Agents => dash
            .agents
            .transcript
            .iter()
            .map(|l| match &l.question {
                Some(q) => question_key(q.message_id),
                None => format!("{}|{}|{}", l.time, l.agent, l.text),
            })
            .collect(),
        View::Storage => dash
            .storage
            .volumes
            .iter()
            .map(|v| v.mount.clone())
            .collect(),
        View::Attention => dash.attention.iter().map(|r| r.id.clone()).collect(),
        View::Map => fleet_ui_core::map::RelationalMap::build(dash).selection_keys(),
    }
}

/// The question to select when the Agents view opens: the first one still
/// waiting, so `y` and `n` act on it without moving first.
pub fn first_open_question(dash: &Dashboard) -> Option<usize> {
    dash.agents
        .transcript
        .iter()
        .position(|l| l.question.is_some())
}

#[cfg(test)]
mod tests {
    use super::*;
    use fleet_ui_core::fixtures::{self, Scenario};
    use fleet_ui_core::views::Inputs;
    use std::time::Duration;

    fn dashboard(scenario: Scenario, read_only: bool) -> Dashboard {
        let now = fixtures::now();
        let controller = fixtures::controller_feed(scenario, now);
        let telemetry = fixtures::telemetry_feed(scenario, now);
        Dashboard::build(&Inputs {
            controller: &controller,
            controller_stale_after: Duration::from_secs(11),
            telemetry: &telemetry,
            telemetry_stale_after: Duration::from_secs(6),
            pending: &[],
            outcomes: &[],
            read_only,
            socket_label: "~/fleetd.sock".into(),
            assume_remote_controller: false,
            now,
        })
    }

    fn select_service(state: &mut UiState, dash: &Dashboard, name: &str) {
        state.set_view(View::Services);
        let index = dash.services.iter().position(|s| s.name == name).unwrap();
        state.select(View::Services, index, dash);
    }

    #[test]
    fn number_keys_switch_views() {
        let dash = dashboard(Scenario::Healthy, false);
        let mut state = UiState::new(View::Overview);
        for view in View::ALL {
            let key = char::from_digit(view.number() as u32, 10).unwrap();
            state.handle_key(Key::Char(key), &dash);
            assert_eq!(state.view, view);
        }
        assert_eq!(View::parse("3"), Some(View::Services));
        assert_eq!(View::parse("agents"), Some(View::Agents));
        assert_eq!(View::parse("7"), Some(View::Map));
    }

    #[test]
    fn selection_moves_and_clamps() {
        let dash = dashboard(Scenario::Healthy, false);
        let mut state = UiState::new(View::Services);
        assert_eq!(state.selected(View::Services, &dash), Some(0));
        state.handle_key(Key::Char('k'), &dash);
        assert_eq!(state.selected(View::Services, &dash), Some(0));
        let effects = state.handle_key(Key::Char('j'), &dash);
        assert_eq!(effects, vec![Effect::Reveal(View::Services, 1)]);
        for _ in 0..50 {
            state.handle_key(Key::Down, &dash);
        }
        assert_eq!(
            state.selected(View::Services, &dash),
            Some(dash.services.len() - 1)
        );
    }

    #[test]
    fn selection_follows_the_row_not_the_index() {
        let dash = dashboard(Scenario::Healthy, false);
        let mut state = UiState::new(View::Services);
        select_service(&mut state, &dash, "n8n");
        let mut reordered = dash.clone();
        reordered.services.reverse();
        let index = state.selected(View::Services, &reordered).unwrap();
        assert_eq!(reordered.services[index].name, "n8n");
    }

    #[test]
    fn empty_lists_have_no_selection() {
        let dash = dashboard(Scenario::Disconnected, false);
        let mut state = UiState::new(View::Services);
        assert!(dash.services.is_empty());
        assert_eq!(state.selected(View::Services, &dash), None);
        assert!(state.handle_key(Key::Char('j'), &dash).is_empty());
        assert!(state.handle_key(Key::Char('s'), &dash).is_empty());
    }

    #[test]
    fn stop_opens_a_confirmation_before_submitting() {
        let dash = dashboard(Scenario::Healthy, false);
        let mut state = UiState::new(View::Services);
        select_service(&mut state, &dash, "render-studio");
        let id = state.selected_service(&dash).unwrap().id.clone();

        assert!(state.handle_key(Key::Char('s'), &dash).is_empty());
        let confirm = state.confirm.clone().expect("stop is confirmed first");
        assert_eq!(confirm.action, Action::Stop { service_id: id.clone() });
        assert!(confirm.prompt.starts_with("Stop render-studio?"));

        // Keys other than confirm or cancel do nothing while the step is open.
        assert!(state.handle_key(Key::Char('2'), &dash).is_empty());
        assert_eq!(state.view, View::Services);

        assert_eq!(
            state.handle_key(Key::Char('y'), &dash),
            vec![Effect::Submit(Action::Stop { service_id: id })]
        );
        assert!(state.confirm.is_none());
    }

    #[test]
    fn escape_and_n_cancel_the_confirmation() {
        let dash = dashboard(Scenario::Healthy, false);
        let mut state = UiState::new(View::Services);
        select_service(&mut state, &dash, "render-studio");
        state.handle_key(Key::Char('r'), &dash);
        assert!(state.confirm.is_some());
        assert!(state.handle_key(Key::Escape, &dash).is_empty());
        assert!(state.confirm.is_none());
        state.handle_key(Key::Char('r'), &dash);
        assert!(state.handle_key(Key::Char('n'), &dash).is_empty());
        assert!(state.confirm.is_none());
    }

    #[test]
    fn renew_submits_without_confirmation() {
        let dash = dashboard(Scenario::Healthy, false);
        let mut state = UiState::new(View::Services);
        select_service(&mut state, &dash, "render-studio");
        let effects = state.handle_key(Key::Char('n'), &dash);
        assert!(matches!(
            effects.as_slice(),
            [Effect::Submit(Action::Renew { ttl_sec, .. })] if *ttl_sec == RENEW_SECONDS
        ));
        assert!(state.confirm.is_none());
    }

    #[test]
    fn claimed_service_refusal_is_reported_not_sent() {
        let dash = dashboard(Scenario::Healthy, false);
        let mut state = UiState::new(View::Services);
        select_service(&mut state, &dash, "notebook");
        let effects = state.handle_key(Key::Char('s'), &dash);
        match effects.as_slice() {
            [Effect::Notice(text)] => assert!(text.contains("claimed"), "{text}"),
            other => panic!("expected a refusal notice, got {other:?}"),
        }
        assert!(state.confirm.is_none());
    }

    #[test]
    fn read_only_refuses_every_mutation() {
        let dash = dashboard(Scenario::Healthy, true);
        let mut state = UiState::new(View::Services);
        select_service(&mut state, &dash, "render-studio");
        for key in ['r', 's', 'n'] {
            match state.handle_key(Key::Char(key), &dash).as_slice() {
                [Effect::Notice(text)] => assert!(text.contains("read-only"), "{text}"),
                other => panic!("{key}: expected refusal, got {other:?}"),
            }
        }
        assert!(matches!(
            state.handle_key(Key::Char('t'), &dash).as_slice(),
            [Effect::Submit(Action::Logs { .. })]
        ));
    }

    #[test]
    fn stale_controller_refuses_actions_with_its_reason() {
        let dash = dashboard(Scenario::Stale, false);
        let mut state = UiState::new(View::Services);
        select_service(&mut state, &dash, "render-studio");
        match state.handle_key(Key::Char('r'), &dash).as_slice() {
            [Effect::Notice(text)] => assert!(text.contains("not current"), "{text}"),
            other => panic!("expected refusal, got {other:?}"),
        }
    }

    #[test]
    fn y_and_n_answer_the_selected_question() {
        let dash = dashboard(Scenario::Healthy, false);
        let mut state = UiState::new(View::Agents);
        let index = first_open_question(&dash).expect("fixture asks a question");
        state.select(View::Agents, index, &dash);
        let message_id = dash.agents.transcript[index]
            .question
            .as_ref()
            .unwrap()
            .message_id;
        assert_eq!(
            state.handle_key(Key::Char('y'), &dash),
            vec![Effect::Submit(Action::Reply {
                message_id,
                body: APPROVE_REPLY.into()
            })]
        );
        assert_eq!(
            state.handle_key(Key::Char('n'), &dash),
            vec![Effect::Submit(Action::Reply {
                message_id,
                body: DENY_REPLY.into()
            })]
        );
        state.select(View::Agents, 0, &dash);
        if dash.agents.transcript[0].question.is_none() {
            assert!(matches!(
                state.handle_key(Key::Char('y'), &dash).as_slice(),
                [Effect::Notice(_)]
            ));
        }
    }

    #[test]
    fn attention_enter_opens_the_named_service() {
        let dash = dashboard(Scenario::Healthy, false);
        let mut state = UiState::new(View::Attention);
        let index = dash
            .attention
            .iter()
            .position(|r| r.service_id.is_some())
            .unwrap();
        state.select(View::Attention, index, &dash);
        let service_id = dash.attention[index].service_id.clone().unwrap();
        state.handle_key(Key::Enter, &dash);
        assert_eq!(state.view, View::Services);
        assert_eq!(state.selected_service(&dash).unwrap().id, service_id);
        assert!(state.inspecting);
    }

    #[test]
    fn attention_enter_opens_the_waiting_question() {
        let dash = dashboard(Scenario::Healthy, false);
        let mut state = UiState::new(View::Attention);
        let index = dash
            .attention
            .iter()
            .position(|r| r.message_id.is_some())
            .unwrap();
        let message_id = dash.attention[index].message_id.unwrap();
        state.select(View::Attention, index, &dash);
        // The fixture question also names a service; open the question by
        // removing that link, as for an agent asking without a service.
        let mut dash = dash;
        dash.attention[index].service_id = None;
        state.handle_key(Key::Enter, &dash);
        assert_eq!(state.view, View::Agents);
        let selected = state.selected(View::Agents, &dash).unwrap();
        assert_eq!(
            dash.agents.transcript[selected]
                .question
                .as_ref()
                .map(|q| q.message_id),
            Some(message_id)
        );
    }

    #[test]
    fn enter_toggles_inspection_and_escape_closes_it() {
        let dash = dashboard(Scenario::Healthy, false);
        let mut state = UiState::new(View::Overview);
        state.handle_key(Key::Enter, &dash);
        assert!(state.inspecting);
        state.handle_key(Key::Escape, &dash);
        assert!(!state.inspecting);
        state.handle_key(Key::Enter, &dash);
        state.handle_key(Key::Char('2'), &dash);
        assert!(!state.inspecting, "switching views closes the inspector");
    }

    #[test]
    fn quit_works_even_inside_a_confirmation() {
        let dash = dashboard(Scenario::Healthy, false);
        let mut state = UiState::new(View::Services);
        select_service(&mut state, &dash, "render-studio");
        state.handle_key(Key::Char('s'), &dash);
        assert_eq!(state.handle_key(Key::Quit, &dash), vec![Effect::Quit]);
    }
}
