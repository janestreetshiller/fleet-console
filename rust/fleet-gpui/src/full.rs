//! The full window: six views over the same dashboard, tabs across the top
//! as in `design/tui.html`, the connection banner whenever the controller is
//! not live, an activity strip with action outcomes, and the confirmation
//! step for destructive actions.

use crate::app::{self, Hub};
use crate::feeds::Built;
use crate::geometry;
use crate::palette::{Colors, MapAccents};
use crate::state::{self, Effect, Key, ServiceCommand, UiState, View};
use crate::ui::{self, cell, cell_flex, SMALL_SIZE, TEXT_SIZE};
use fleet_ui_core::map::{EdgeKind, MapNode, NodeKind, RelationalMap};
use fleet_ui_core::observe::Phase;
use fleet_ui_core::thresholds::{self, Level, NodeState};
use fleet_ui_core::views::{
    Control, Dashboard, Freshness, NodeTile, ProcessRole, ServiceRow, Severity, GAUGE_SEGMENTS,
};
use gpui::{
    canvas, div, prelude::*, px, AnyElement, App, ClickEvent, Context, Div, Entity, FocusHandle,
    FontWeight, Hsla, KeyDownEvent, Keystroke, ScrollHandle, SharedString, Subscription, Window,
};
use std::collections::VecDeque;
use std::sync::Arc;

const TILE_MIN: f32 = 300.0;
const TILE_GAP: f32 = 14.0;
const PAD: f32 = 12.0;
const MAP_CELL: f32 = 10.0;
const MAP_GAP: f32 = 2.0;
const MAP_ROWS: usize = 3;
const LOG_LINES: usize = 40;
/// Header, tabs, banners, the activity strip and the key hints above and
/// below the map panel. The map sizes itself to what is left of the window.
const MAP_CHROME: f32 = 190.0;
/// The legend and the notes strip at the bottom of the map panel.
const MAP_FOOT: f32 = 64.0;
/// Clear space around the graph so labels never touch the panel edge.
const MAP_MARGIN: f32 = 90.0;
/// The width of every clickable node label.
const MAP_LABEL_W: f32 = 140.0;

pub struct FullView {
    hub: Entity<Hub>,
    ui: UiState,
    colors: Colors,
    focus: FocusHandle,
    scroll: [ScrollHandle; 7],
    _subscriptions: Vec<Subscription>,
}

/// GPUI keystroke to state-machine key. Modified keys other than the quit
/// chord are left for the system.
pub fn map_key(keystroke: &Keystroke) -> Option<Key> {
    let m = &keystroke.modifiers;
    if (m.platform || m.control) && keystroke.key == "q" {
        return Some(Key::Quit);
    }
    if m.platform || m.control || m.alt || m.function {
        return None;
    }
    match keystroke.key.as_str() {
        "up" => Some(Key::Up),
        "down" => Some(Key::Down),
        "enter" => Some(Key::Enter),
        "escape" => Some(Key::Escape),
        key => {
            let mut chars = key.chars();
            match (chars.next(), chars.next()) {
                (Some(c), None) if !m.shift => Some(Key::Char(c)),
                _ => None,
            }
        }
    }
}

impl FullView {
    pub fn new(hub: Entity<Hub>, view: View, window: &mut Window, cx: &mut Context<Self>) -> Self {
        let focus = cx.focus_handle();
        window.focus(&focus);
        let subscriptions = vec![
            cx.observe(&hub, |_, _, cx| cx.notify()),
            cx.observe_window_appearance(window, |this, window, cx| {
                this.colors = Colors::for_window(window.appearance(), cx);
                cx.notify();
            }),
        ];
        Self {
            hub,
            ui: UiState::new(view),
            colors: Colors::for_window(window.appearance(), cx),
            focus,
            scroll: Default::default(),
            _subscriptions: subscriptions,
        }
    }

    pub fn show_view(&mut self, view: View, cx: &mut Context<Self>) {
        self.ui.set_view(view);
        cx.notify();
    }

    fn built(&self, cx: &App) -> Arc<Built> {
        self.hub.read(cx).built.clone()
    }

    fn apply(&mut self, effects: Vec<Effect>, cx: &mut Context<Self>) {
        for effect in effects {
            match effect {
                Effect::Submit(action) => self.hub.update(cx, |hub, cx| hub.submit(action, cx)),
                Effect::Notice(text) => self.hub.update(cx, |hub, cx| hub.notice(text, cx)),
                Effect::Quit => cx.quit(),
                Effect::Reveal(view, index) => self.scroll[view.index()].scroll_to_item(index),
            }
        }
        cx.notify();
    }

    fn on_key(&mut self, event: &KeyDownEvent, _window: &mut Window, cx: &mut Context<Self>) {
        let Some(key) = map_key(&event.keystroke) else {
            return;
        };
        let built = self.built(cx);
        let effects = self.ui.handle_key(key, &built.dashboard);
        self.apply(effects, cx);
        cx.stop_propagation();
    }

    fn select(&mut self, view: View, index: usize, inspect: bool, cx: &mut Context<Self>) {
        let built = self.built(cx);
        let already = self.ui.selected(view, &built.dashboard) == Some(index);
        self.ui.select(view, index, &built.dashboard);
        if inspect {
            self.ui.inspecting = if already { !self.ui.inspecting } else { true };
        }
        cx.notify();
    }

    fn request(&mut self, command: ServiceCommand, service_id: &str, cx: &mut Context<Self>) {
        let built = self.built(cx);
        let effects = self.ui.request(command, service_id, &built.dashboard);
        self.apply(effects, cx);
    }

    fn answer(&mut self, message_id: i64, approve: bool, cx: &mut Context<Self>) {
        let built = self.built(cx);
        let effects = self.ui.answer(message_id, approve, &built.dashboard);
        self.apply(effects, cx);
    }

    fn header(&self, built: &Built) -> Div {
        let c = self.colors;
        let dash = &built.dashboard;
        let conn = &dash.connection;
        let mut status: Vec<(String, Hsla)> = vec![(
            format!("controller {}", conn.phase.label()),
            ui::phase_color(conn.phase, c),
        )];
        if conn.phase == Phase::Live {
            if let Some(version) = &conn.controller_version {
                status.push((format!("version {version}"), c.dim));
            }
            if conn.locality == fleet_ui_core::views::Locality::Remote {
                status.push(("on another machine".into(), c.info));
            }
        }
        if conn.read_only {
            status.push(("read-only".into(), c.warn));
        }
        if let Some(name) = built.fixture {
            status.push((format!("synthetic fixture data: {name}"), c.warn));
        }
        div()
            .flex()
            .flex_row()
            .items_center()
            .gap(px(12.0))
            .px(px(PAD))
            .py(px(8.0))
            .border_b_1()
            .border_color(c.line)
            .child(ui::logo(c, 4.0))
            .child(
                div()
                    .flex()
                    .flex_col()
                    .child(
                        div()
                            .text_color(c.bright)
                            .font_weight(FontWeight::BOLD)
                            .child("FleetConsole"),
                    )
                    .child(
                        div()
                            .text_size(px(SMALL_SIZE))
                            .text_color(c.dim)
                            .child(dash.header.subtitle.clone()),
                    ),
            )
            .child(
                div()
                    .flex()
                    .flex_row()
                    .flex_wrap()
                    .flex_1()
                    .justify_end()
                    .gap(px(12.0))
                    .children(status.into_iter().map(|(text, color)| div().text_color(color).child(text))),
            )
            .child(
                ui::button("full.refresh", "Refresh", &Control::Allowed, c)
                    .on_click(|_: &ClickEvent, _, cx| app::refresh(cx)),
            )
            .child(
                ui::button("full.quick", "Quick view", &Control::Allowed, c).on_click(
                    |_: &ClickEvent, _, cx| cx.defer(|cx| app::open_quick(None, cx)),
                ),
            )
    }

    fn tabs(&self, dash: &Dashboard, map: &RelationalMap, cx: &mut Context<Self>) -> Div {
        let c = self.colors;
        let current = self.ui.view;
        div()
            .flex()
            .flex_row()
            .border_b_1()
            .border_color(c.line)
            .children(View::ALL.into_iter().map(|view| {
                let selected = view == current;
                let count = match view {
                    View::Services => Some(dash.services.len()),
                    View::Agents => Some(dash.agents.open_questions).filter(|n| *n > 0),
                    View::Attention => Some(dash.attention.len()),
                    View::Map => Some(map.badge_count()).filter(|n| *n > 0),
                    _ => None,
                };
                div()
                    .id(("tab", view.index()))
                    .flex()
                    .flex_row()
                    .gap(px(6.0))
                    .px(px(14.0))
                    .py(px(5.0))
                    .cursor_pointer()
                    .when(selected, |d| d.bg(c.bright).text_color(c.selected_text))
                    .when(!selected, |d| d.text_color(c.dim).hover(|s| s.text_color(c.text)))
                    .child(
                        div()
                            .text_color(if selected { c.selected_text } else { c.dark })
                            .child(view.number().to_string()),
                    )
                    .child(view.label())
                    .when_some(count, |d, n| d.child(div().child(n.to_string())))
                    .on_click(cx.listener(move |this, _: &ClickEvent, _, cx| {
                        this.ui.set_view(view);
                        cx.notify();
                    }))
            }))
    }

    fn activity(&self, dash: &Dashboard, notices: &VecDeque<String>) -> Div {
        let c = self.colors;
        let mut lines: Vec<(String, Hsla)> = notices
            .iter()
            .take(2)
            .map(|n| (n.clone(), c.warn))
            .collect();
        lines.extend(dash.activity.iter().map(|a| {
            (
                a.text.clone(),
                match a.ok {
                    Some(true) => c.bright,
                    Some(false) => c.crit,
                    None => c.info,
                },
            )
        }));
        lines.truncate(3);
        div()
            .flex()
            .flex_col()
            .px(px(PAD))
            .py(px(4.0))
            .border_t_1()
            .border_color(c.line)
            .min_h(px(22.0))
            .when(lines.is_empty(), |d| {
                d.child(div().text_color(c.dim).child("No actions in this session."))
            })
            .children(lines.into_iter().map(|(text, color)| {
                div()
                    .text_color(color)
                    .whitespace_nowrap()
                    .overflow_hidden()
                    .text_ellipsis()
                    .child(text)
            }))
    }

    fn key_hints(&self) -> Div {
        let c = self.colors;
        let quit = if cfg!(target_os = "macos") { "cmd-q" } else { "ctrl-q" };
        let hints: [(&str, &str); 10] = [
            ("1-6", "views"),
            ("j/k", "move"),
            ("enter", "inspect"),
            ("r", "restart"),
            ("s", "stop"),
            ("n", "renew"),
            ("t", "logs"),
            ("y/n", "answer"),
            ("esc", "close"),
            (quit, "quit"),
        ];
        div()
            .flex()
            .flex_row()
            .flex_wrap()
            .gap_x(px(14.0))
            .px(px(PAD))
            .py(px(5.0))
            .border_t_1()
            .border_color(c.line)
            .text_size(px(SMALL_SIZE))
            .text_color(c.dim)
            .children(hints.into_iter().map(|(key, what)| {
                div()
                    .flex()
                    .flex_row()
                    .gap(px(4.0))
                    .child(div().text_color(c.bright).child(key))
                    .child(what)
            }))
    }

    fn confirm_overlay(&self, confirm: &state::Confirmation, cx: &mut Context<Self>) -> Div {
        let c = self.colors;
        div()
            .absolute()
            .top_0()
            .left_0()
            .size_full()
            .flex()
            .items_center()
            .justify_center()
            .bg(c.bg.opacity(0.8))
            .occlude()
            .child(
                div()
                    .w(px(520.0))
                    .flex()
                    .flex_col()
                    .gap(px(10.0))
                    .p(px(16.0))
                    .bg(c.panel_fill())
                    .border_1()
                    .border_color(c.warn)
                    .child(div().text_color(c.warn).child("Confirm"))
                    .child(div().text_color(c.text).child(confirm.prompt.clone()))
                    .child(
                        div()
                            .flex()
                            .flex_row()
                            .gap(px(10.0))
                            .child(
                                ui::button(
                                    "confirm.yes",
                                    format!("{}  y", confirm.confirm_label),
                                    &Control::Allowed,
                                    c,
                                )
                                .on_click(cx.listener(|this, _: &ClickEvent, _, cx| {
                                    let effects = this.ui.confirm();
                                    this.apply(effects, cx);
                                })),
                            )
                            .child(
                                ui::button("confirm.no", "cancel  esc", &Control::Allowed, c)
                                    .on_click(cx.listener(|this, _: &ClickEvent, _, cx| {
                                        this.ui.cancel();
                                        cx.notify();
                                    })),
                            ),
                    ),
            )
    }

    fn empty(&self, text: impl Into<SharedString>) -> AnyElement {
        div()
            .p(px(PAD))
            .text_color(self.colors.dim)
            .child(text.into())
            .into_any_element()
    }

    // ---- Overview ---------------------------------------------------------

    fn overview(&self, dash: &Dashboard, width: f32, cx: &mut Context<Self>) -> AnyElement {
        let c = self.colors;
        let s = &dash.cluster.summary;
        let summary: Vec<(&str, String)> = vec![
            ("nodes", format!("{}/{}", s.online, s.total)),
            ("avg cpu", fleet_ui_core::format::percent(s.average_cpu)),
            ("avg mem", fleet_ui_core::format::percent(s.average_memory)),
            ("avg gpu", fleet_ui_core::format::percent(s.average_gpu)),
            (
                "agents",
                s.agents
                    .map(|a| a.to_string())
                    .unwrap_or_else(|| fleet_ui_core::format::UNAVAILABLE.into()),
            ),
            ("needs attention", s.needs_attention.to_string()),
        ];
        let selected = self.ui.selected(View::Overview, dash);
        let (_, tile_width) = geometry::tile_columns(width, TILE_MIN, TILE_GAP);
        let inspector = selected
            .filter(|_| self.ui.inspecting)
            .and_then(|i| dash.cluster.tiles.get(i))
            .map(|t| self.tile_inspector(t));
        div()
            .flex()
            .flex_col()
            .size_full()
            .gap(px(12.0))
            .child(
                div()
                    .flex()
                    .flex_row()
                    .flex_wrap()
                    .gap_x(px(16.0))
                    .px(px(14.0))
                    .py(px(8.0))
                    .border_1()
                    .border_color(c.line)
                    .bg(c.panel_fill())
                    .children(summary.into_iter().map(|(label, value)| {
                        div()
                            .flex()
                            .flex_row()
                            .gap(px(6.0))
                            .child(label)
                            .child(div().text_color(c.bright).font_weight(FontWeight::BOLD).child(value))
                    })),
            )
            .when_some(inspector, |d, panel| d.child(panel))
            .child(
                div()
                    .id("overview.tiles")
                    .flex()
                    .flex_row()
                    .flex_wrap()
                    .content_start()
                    .gap(px(TILE_GAP))
                    .flex_1()
                    .min_h(px(0.0))
                    .overflow_y_scroll()
                    .track_scroll(&self.scroll[View::Overview.index()])
                    .children(dash.cluster.tiles.iter().enumerate().map(|(i, t)| {
                        self.tile(t, i, selected == Some(i), tile_width, cx)
                    })),
            )
            .into_any_element()
    }

    fn tile(
        &self,
        t: &NodeTile,
        index: usize,
        selected: bool,
        width: f32,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let c = self.colors;
        let offline = t.state == NodeState::Offline;
        let border = if offline { c.line } else { c.level_border(t.worst_level()) };
        let state_color = match t.state {
            NodeState::Healthy => c.bright,
            NodeState::Pressure => c.warn,
            NodeState::Critical => c.crit,
            NodeState::Offline | NodeState::Unmeasured => c.dim,
        };
        let mut state_text = t.state.label().to_string();
        match t.freshness {
            Freshness::Current => {}
            Freshness::Stale => state_text.push_str(", stale"),
            Freshness::Disconnected => state_text.push_str(", controller disconnected"),
        }
        // Group unavailable gauges by reason: "cpu, mem, gpu: node offline".
        let mut reasons: Vec<(String, Vec<&str>)> = Vec::new();
        for g in t.gauges.iter().filter(|g| g.label != "net") {
            if let Some(reason) = g.metric.reason() {
                let label = reason.label().to_string();
                match reasons.iter_mut().find(|(r, _)| *r == label) {
                    Some((_, names)) => names.push(g.label),
                    None => reasons.push((label, vec![g.label])),
                }
            }
        }
        let mut notes: Vec<String> = reasons
            .into_iter()
            .map(|(reason, names)| format!("{}: {reason}", names.join(", ")))
            .collect();
        if let Some(disk) = t.gauges.iter().find(|g| g.label == "disk" && g.detail.starts_with("last known")) {
            notes.push(format!("disk {}", disk.detail));
        }
        if let Some(note) = &t.note {
            notes.push(note.clone());
        }
        let rows = t.gauges.iter().map(|g| {
            let middle: AnyElement = if g.label == "net" && !g.metric.is_measured() {
                let text = if t.network_text != fleet_ui_core::format::UNAVAILABLE {
                    t.network_text.clone()
                } else {
                    g.detail.clone()
                };
                div()
                    .flex_1()
                    .text_size(px(SMALL_SIZE))
                    .text_color(c.dim)
                    .whitespace_nowrap()
                    .overflow_hidden()
                    .text_ellipsis()
                    .child(text)
                    .into_any_element()
            } else {
                div()
                    .flex_1()
                    .child(ui::segments(&thresholds::segments(g.metric, GAUGE_SEGMENTS), c, 12.0))
                    .into_any_element()
            };
            div()
                .flex()
                .flex_row()
                .items_center()
                .gap(px(8.0))
                .my(px(3.0))
                .child(div().w(px(40.0)).text_color(c.dim).child(g.label))
                .child(middle)
                .child(
                    div()
                        .w(px(44.0))
                        .text_right()
                        .text_color(c.level_text(g.level))
                        .child(g.text.clone()),
                )
        });
        let footer = [
            format!(
                "services {}",
                match (t.services_up, t.services_total) {
                    (Some(up), Some(total)) => format!("{up}/{total}"),
                    _ => fleet_ui_core::format::UNAVAILABLE.into(),
                }
            ),
            format!(
                "agents {}",
                t.agents
                    .map(|a| a.to_string())
                    .unwrap_or_else(|| fleet_ui_core::format::UNAVAILABLE.into())
            ),
            format!(
                "up {}",
                t.uptime.clone().unwrap_or_else(|| fleet_ui_core::format::UNAVAILABLE.into())
            ),
        ];
        let has_history = t.cpu_history.iter().any(Option::is_some);
        div()
            .id(("tile", index))
            .w(px(width))
            .p(px(1.0))
            .border_1()
            .border_color(if selected { c.bright } else { c.bg })
            .cursor_pointer()
            .on_click(cx.listener(move |this, _: &ClickEvent, _, cx| {
                this.select(View::Overview, index, true, cx);
            }))
            .child(
                div()
                    .flex()
                    .flex_col()
                    .border_1()
                    .border_color(border)
                    .bg(c.panel_fill())
                    .px(px(14.0))
                    .py(px(12.0))
                    .when(offline, |d| d.opacity(0.5))
                    .child(
                        div()
                            .flex()
                            .flex_row()
                            .justify_between()
                            .mb(px(8.0))
                            .child(
                                div()
                                    .text_color(c.bright)
                                    .font_weight(FontWeight::BOLD)
                                    .child(t.name.clone()),
                            )
                            .child(
                                div()
                                    .text_size(px(SMALL_SIZE))
                                    .text_color(state_color)
                                    .child(state_text),
                            ),
                    )
                    .children(rows)
                    .child(
                        div()
                            .mt(px(8.0))
                            .pt(px(6.0))
                            .border_t_1()
                            .border_color(c.line)
                            .child(if has_history {
                                ui::spark(&t.cpu_history, c, fleet_ui_core::platform::HISTORY, 26.0)
                                    .into_any_element()
                            } else {
                                div()
                                    .h(px(26.0))
                                    .text_size(px(SMALL_SIZE))
                                    .text_color(c.dim)
                                    .child("no cpu history reported")
                                    .into_any_element()
                            }),
                    )
                    .child(
                        div()
                            .flex()
                            .flex_row()
                            .justify_between()
                            .mt(px(8.0))
                            .text_size(px(SMALL_SIZE))
                            .text_color(c.dim)
                            .children(footer.into_iter().map(|f| div().child(f))),
                    )
                    .children(notes.into_iter().map(|n| {
                        div()
                            .mt(px(4.0))
                            .text_size(px(SMALL_SIZE))
                            .text_color(c.dim)
                            .child(n)
                    })),
            )
            .into_any_element()
    }

    fn tile_inspector(&self, t: &NodeTile) -> Div {
        let c = self.colors;
        ui::panel(format!("{}, {}", t.name, t.state.label()), c)
            .child(
                div()
                    .flex()
                    .flex_col()
                    .px(px(10.0))
                    .py(px(6.0))
                    .gap(px(2.0))
                    .children(t.gauges.iter().map(|g| div().child(ui::spoken(g))))
                    .child(div().text_color(c.dim).child(format!("network {}", t.network_text)))
                    .when_some(t.note.clone(), |d, note| d.child(div().text_color(c.dim).child(note))),
            )
    }

    // ---- Processes --------------------------------------------------------

    fn processes(&self, dash: &Dashboard, cx: &mut Context<Self>) -> AnyElement {
        let c = self.colors;
        let p = &dash.processes;
        if p.lines.is_empty() {
            return self.empty(match p.phase {
                Phase::Loading => "Waiting for the first telemetry sample.".to_string(),
                phase => format!("No process sample: local telemetry {}.", phase.label()),
            });
        }
        let prefixes = geometry::tree_prefixes(
            &p.lines.iter().map(|l| (l.depth, l.last_child)).collect::<Vec<_>>(),
        );
        let selected = self.ui.selected(View::Processes, dash);
        let heading = match p.total_processes {
            Some(total) => format!(
                "{total} processes on this machine, {} lines shown, highest CPU first",
                p.lines.len()
            ),
            None => format!("{} lines", p.lines.len()),
        };
        div()
            .flex()
            .flex_col()
            .size_full()
            .gap(px(6.0))
            .child(
                div()
                    .flex()
                    .flex_row()
                    .gap(px(12.0))
                    .child(div().text_color(c.dim).child(heading))
                    .when(p.phase != Phase::Live, |d| {
                        d.child(
                            div()
                                .text_color(ui::phase_color(p.phase, c))
                                .child(format!("local telemetry {}", p.phase.label())),
                        )
                    }),
            )
            .when_some(p.note.clone(), |d, note| d.child(div().text_color(c.info).child(note)))
            .child(
                div()
                    .flex()
                    .flex_row()
                    .px(px(6.0))
                    .text_color(c.dim)
                    .child(cell_flex("process"))
                    .child(cell(80.0, "pid"))
                    .child(cell(70.0, "cpu"))
                    .child(cell(90.0, "memory"))
                    .child(cell(220.0, "")),
            )
            .child(
                div()
                    .id("processes.list")
                    .flex()
                    .flex_col()
                    .flex_1()
                    .min_h(px(0.0))
                    .overflow_y_scroll()
                    .track_scroll(&self.scroll[View::Processes.index()])
                    .children(p.lines.iter().enumerate().map(|(i, l)| {
                        let is_selected = selected == Some(i);
                        let name_color = if is_selected {
                            c.selected_text
                        } else {
                            match l.role {
                                ProcessRole::Controller => c.bright,
                                ProcessRole::Service => c.text,
                                ProcessRole::Agent => c.info,
                                ProcessRole::Other => c.text,
                            }
                        };
                        let tag_color = if is_selected {
                            c.selected_text
                        } else if l.role == ProcessRole::Service
                            || l.tag.as_deref().is_some_and(|t| t.starts_with("not in"))
                        {
                            c.warn
                        } else {
                            c.dim
                        };
                        let name = format!("{}{}", prefixes[i], l.name);
                        ui::row(("process", i), is_selected, c)
                            .on_click(cx.listener(move |this, _: &ClickEvent, _, cx| {
                                this.select(View::Processes, i, false, cx);
                            }))
                            .child(cell_flex(name).text_color(name_color))
                            .child(cell(80.0, l.pid.map(|p| p.to_string()).unwrap_or_default()))
                            .child(cell(70.0, fleet_ui_core::format::percent(l.cpu)))
                            .child(cell(90.0, l.memory.clone()))
                            .child(cell(220.0, l.tag.clone().unwrap_or_default()).text_color(tag_color))
                    })),
            )
            .into_any_element()
    }

    // ---- Services ---------------------------------------------------------

    fn services(&self, built: &Built, cx: &mut Context<Self>) -> AnyElement {
        let c = self.colors;
        let dash = &built.dashboard;
        if dash.services.is_empty() {
            return self.empty(if dash.connection.phase == Phase::Live {
                "The controller supervises no services.".to_string()
            } else {
                format!("No service data. {}", dash.connection.summary)
            });
        }
        let selected = self.ui.selected(View::Services, dash);
        let heading = match dash.header.services_running {
            Some(n) => format!("{} services, {n} running", dash.services.len()),
            None => format!(
                "{} services from the last read; controller data is not current",
                dash.services.len()
            ),
        };
        let detail = selected
            .filter(|_| self.ui.inspecting)
            .and_then(|i| dash.services.get(i))
            .map(|row| self.service_detail(row, built, cx));
        let table = div()
            .flex()
            .flex_col()
            .flex_1()
            .min_w(px(0.0))
            .gap(px(6.0))
            .child(div().text_color(c.dim).child(heading))
            .child(
                div()
                    .flex()
                    .flex_row()
                    .px(px(6.0))
                    .text_color(c.dim)
                    .child(cell_flex("service"))
                    .child(cell(170.0, "state"))
                    .child(cell(70.0, "pid"))
                    .child(cell(80.0, "uptime"))
                    .child(cell(70.0, "restarts"))
                    .child(cell(56.0, "cpu"))
                    .child(cell(80.0, "memory")),
            )
            .child(
                div()
                    .id("services.list")
                    .flex()
                    .flex_col()
                    .flex_1()
                    .min_h(px(0.0))
                    .overflow_y_scroll()
                    .track_scroll(&self.scroll[View::Services.index()])
                    .children(dash.services.iter().enumerate().map(|(i, s)| {
                        let is_selected = selected == Some(i);
                        let state_color = if is_selected {
                            c.selected_text
                        } else {
                            match s.level {
                                Some(Level::Critical) => c.crit,
                                Some(Level::Warning) => c.warn,
                                Some(Level::Elevated) => c.bright,
                                _ => c.text,
                            }
                        };
                        let state_text = match &s.in_flight {
                            Some(work) => format!("{}, {work}", s.state_text),
                            None if s.claimed => format!("{}, claimed", s.state_text),
                            None => s.state_text.to_string(),
                        };
                        ui::row(("service", i), is_selected, c)
                            .on_click(cx.listener(move |this, _: &ClickEvent, _, cx| {
                                this.select(View::Services, i, true, cx);
                            }))
                            .child(cell_flex(s.name.clone()))
                            .child(cell(170.0, state_text).text_color(state_color))
                            .child(cell(70.0, s.pid.map(|p| p.to_string()).unwrap_or_else(|| "--".into())))
                            .child(cell(80.0, s.uptime.clone()))
                            .child(cell(70.0, s.restarts.to_string()))
                            .child(cell(56.0, fleet_ui_core::format::percent(s.cpu)))
                            .child(cell(80.0, s.memory.clone()))
                    })),
            );
        div()
            .flex()
            .flex_row()
            .size_full()
            .gap(px(12.0))
            .child(table)
            .when_some(detail, |d, panel| d.child(panel))
            .into_any_element()
    }

    fn service_detail(&self, row: &ServiceRow, built: &Built, cx: &mut Context<Self>) -> Div {
        let c = self.colors;
        let commands = [
            (ServiceCommand::Restart, "restart  r"),
            (ServiceCommand::Stop, "stop  s"),
            (ServiceCommand::Pause, "pause"),
            (ServiceCommand::Resume, "resume"),
            (ServiceCommand::Renew, "renew 30m  n"),
            (ServiceCommand::Logs, "logs  t"),
        ];
        // Refusal reasons, grouped so a shared reason prints once.
        let mut refusals: Vec<(String, Vec<&str>)> = Vec::new();
        for (command, _) in commands {
            if let Control::Refused(reason) = command.control(row) {
                match refusals.iter_mut().find(|(r, _)| r == reason) {
                    Some((_, verbs)) => verbs.push(command.verb()),
                    None => refusals.push((reason.clone(), vec![command.verb()])),
                }
            }
        }
        let launch = if row.claimed {
            "claimed, not launched: visible to the controller, never signalled by it".to_string()
        } else {
            "launched by the controller".to_string()
        };
        let facts = [
            ("process", row.process.clone()),
            ("ports", row.listening.clone()),
            ("health", row.health.clone()),
            ("launch", launch),
        ];
        let logs = built
            .logs
            .as_ref()
            .filter(|(id, _)| *id == row.id)
            .map(|(_, chunk)| chunk.clone());
        let id = row.id.clone();
        ui::panel(format!("{}  {}", row.name, row.short_id), c)
            .w(px(400.0))
            .flex_shrink_0()
            .child(
                div()
                    .id("service.detail")
                    .flex()
                    .flex_col()
                    .gap(px(4.0))
                    .px(px(10.0))
                    .py(px(8.0))
                    .overflow_y_scroll()
                    .child(div().child(format!("owner {}", row.owner)))
                    .when(!row.purpose.is_empty(), |d| {
                        d.child(div().text_color(c.dim).child(row.purpose.clone()))
                    })
                    .child(div().child(format!("state {}", row.state_text)))
                    .when_some(row.in_flight.clone(), |d, work| {
                        d.child(div().text_color(c.info).child(work))
                    })
                    .child(div().pt(px(4.0)).text_color(c.bright).child("Evidence"))
                    .children(facts.into_iter().map(|(label, value)| {
                        div()
                            .flex()
                            .flex_row()
                            .gap(px(8.0))
                            .child(div().w(px(64.0)).flex_shrink_0().text_color(c.dim).child(label))
                            .child(div().flex_1().child(value))
                    }))
                    .child(div().text_color(c.dim).child(format!("{}; declared {}", row.lease, row.ports)))
                    .child(
                        div()
                            .flex()
                            .flex_row()
                            .flex_wrap()
                            .gap(px(6.0))
                            .pt(px(6.0))
                            .children(commands.into_iter().map(|(command, label)| {
                                let control = command.control(row).clone();
                                let id = id.clone();
                                let button = ui::button(
                                    SharedString::from(format!("service.{}", command.verb())),
                                    label,
                                    &control,
                                    c,
                                );
                                if control.is_allowed() {
                                    button.on_click(cx.listener(move |this, _: &ClickEvent, _, cx| {
                                        this.request(command, &id, cx);
                                    }))
                                } else {
                                    button
                                }
                            })),
                    )
                    .children(refusals.into_iter().map(|(reason, verbs)| {
                        div()
                            .text_size(px(SMALL_SIZE))
                            .text_color(c.dim)
                            .child(format!("{} unavailable: {reason}", verbs.join(", ")))
                    }))
                    .when_some(logs, |d, chunk| {
                        let lines: Vec<&str> = chunk.text.lines().collect();
                        let skip = lines.len().saturating_sub(LOG_LINES);
                        let shown: Vec<String> = lines[skip..].iter().map(|l| l.to_string()).collect();
                        d.child(
                            div()
                                .pt(px(6.0))
                                .text_color(c.bright)
                                .child(format!(
                                    "std{} log, last {} lines of {}{}",
                                    chunk.stream,
                                    shown.len(),
                                    fleet_ui_core::format::bytes(chunk.bytes.max(0) as u64),
                                    if chunk.truncated { ", truncated" } else { "" }
                                )),
                        )
                        .child(
                            div()
                                .flex()
                                .flex_col()
                                .text_size(px(SMALL_SIZE))
                                .border_1()
                                .border_color(c.line)
                                .p(px(6.0))
                                .when(shown.is_empty(), |d| d.child(div().text_color(c.dim).child("empty")))
                                .children(shown.into_iter().map(|l| div().whitespace_nowrap().child(l))),
                        )
                    }),
            )
    }

    // ---- Agents -----------------------------------------------------------

    fn agents(&self, dash: &Dashboard, cx: &mut Context<Self>) -> AnyElement {
        let c = self.colors;
        let a = &dash.agents;
        if a.rows.is_empty() && a.transcript.is_empty() {
            return self.empty(if dash.connection.phase == Phase::Live {
                "No agent sessions, agent-owned services or agent messages reported.".to_string()
            } else {
                format!("No agent data. {}", dash.connection.summary)
            });
        }
        let selected = self.ui.selected(View::Agents, dash);
        let rows = ui::panel("Agents", c).child(
            div()
                .flex()
                .flex_col()
                .px(px(4.0))
                .py(px(4.0))
                .child(
                    div()
                        .flex()
                        .flex_row()
                        .px(px(6.0))
                        .text_color(c.dim)
                        .child(cell(160.0, "agent"))
                        .child(cell_flex("target"))
                        .child(cell(260.0, "state"))
                        .child(cell(90.0, "runtime")),
                )
                .children(a.rows.iter().map(|r| {
                    let state_color = match r.level {
                        Some(Level::Warning) => c.warn,
                        Some(Level::Critical) => c.crit,
                        _ => c.text,
                    };
                    div()
                        .flex()
                        .flex_row()
                        .px(px(6.0))
                        .child(cell(160.0, r.name.clone()))
                        .child(cell_flex(r.target.clone()))
                        .child(cell(260.0, r.state.clone()).text_color(state_color))
                        .child(cell(90.0, r.runtime.clone()))
                })),
        );
        let transcript = ui::panel(
            format!(
                "Transcript, times in UTC, {} open question{}",
                a.open_questions,
                if a.open_questions == 1 { "" } else { "s" }
            ),
            c,
        )
        .flex_1()
        .min_h(px(0.0))
        .child(
            div()
                .id("agents.transcript")
                .flex()
                .flex_col()
                .flex_1()
                .min_h(px(0.0))
                .py(px(4.0))
                .overflow_y_scroll()
                .track_scroll(&self.scroll[View::Agents.index()])
                .children(a.transcript.iter().enumerate().map(|(i, l)| {
                    let is_selected = selected == Some(i);
                    let verb_color = if is_selected {
                        c.selected_text
                    } else if l.verb == "ask" {
                        c.warn
                    } else if l.verb == "problem" {
                        c.crit
                    } else {
                        c.dim
                    };
                    let mut line = ui::row(("line", i), is_selected, c)
                        .items_center()
                        .gap(px(4.0))
                        .on_click(cx.listener(move |this, _: &ClickEvent, _, cx| {
                            this.select(View::Agents, i, false, cx);
                        }))
                        .child(cell(52.0, l.time.clone()))
                        .child(cell(130.0, l.agent.clone()))
                        .child(cell(70.0, l.verb.clone()).text_color(verb_color))
                        .child(cell_flex(l.text.clone()));
                    if let Some(q) = &l.question {
                        let message_id = q.message_id;
                        let approve = ui::button(("approve", i), "approve  y", &q.reply, c);
                        let deny = ui::button(("deny", i), "deny  n", &q.reply, c);
                        line = if q.reply.is_allowed() {
                            line.child(approve.on_click(cx.listener(move |this, _: &ClickEvent, _, cx| {
                                this.answer(message_id, true, cx);
                            })))
                            .child(deny.on_click(cx.listener(move |this, _: &ClickEvent, _, cx| {
                                this.answer(message_id, false, cx);
                            })))
                        } else {
                            let reason = match &q.reply {
                                Control::Refused(r) => r.clone(),
                                Control::Allowed => String::new(),
                            };
                            line.child(approve).child(deny).child(
                                div()
                                    .text_size(px(SMALL_SIZE))
                                    .text_color(if is_selected { c.selected_text } else { c.dim })
                                    .whitespace_nowrap()
                                    .child(reason),
                            )
                        };
                    }
                    line
                })),
        );
        div()
            .flex()
            .flex_col()
            .size_full()
            .gap(px(12.0))
            .when(!a.rows.is_empty(), |d| d.child(rows))
            .child(transcript)
            .into_any_element()
    }

    // ---- Storage ----------------------------------------------------------

    fn storage(&self, built: &Built, width: f32, cx: &mut Context<Self>) -> AnyElement {
        let c = self.colors;
        let st = &built.dashboard.storage;
        let largest: AnyElement = match &st.largest_paths {
            Ok(list) if !list.is_empty() => div()
                .flex()
                .flex_col()
                .children(list.iter().map(|(size, path)| {
                    div()
                        .flex()
                        .flex_row()
                        .child(cell(90.0, size.clone()))
                        .child(cell_flex(path.clone()))
                }))
                .into_any_element(),
            Ok(_) => div().text_color(c.dim).child("No paths reported.").into_any_element(),
            Err(reason) => div().text_color(c.dim).child(reason.clone()).into_any_element(),
        };
        let largest_panel = ui::panel("Largest paths", c).child(div().px(px(10.0)).py(px(6.0)).child(largest));
        if st.volumes.is_empty() {
            return div()
                .flex()
                .flex_col()
                .gap(px(12.0))
                .child(self.empty(match st.phase {
                    Phase::Loading => "Waiting for the first telemetry sample.".to_string(),
                    phase => format!("No volumes measured; local telemetry {}.", phase.label()),
                }))
                .child(largest_panel)
                .into_any_element();
        }
        // Proportional map: blocks per volume by total bytes, used blocks
        // colored by the volume's band, one empty block between volumes.
        let bytes: Vec<(u64, u64)> = st
            .volumes
            .iter()
            .map(|v| {
                built
                    .volumes
                    .iter()
                    .find(|(mount, _, _)| *mount == v.mount)
                    .map(|(_, total, used)| (*total, *used))
                    .unwrap_or((0, 0))
            })
            .collect();
        let per_row = (((width - 24.0 + MAP_GAP) / (MAP_CELL + MAP_GAP)).floor() as usize).max(10);
        let total_cells = per_row * MAP_ROWS;
        let gaps = st.volumes.len().saturating_sub(1);
        let allocation = geometry::volume_cells(&bytes, total_cells.saturating_sub(gaps));
        let mut blocks: Vec<Option<Hsla>> = Vec::with_capacity(total_cells);
        for (i, ((used, free), v)) in allocation.iter().zip(&st.volumes).enumerate() {
            let used_color = v.gauge.level.map(|l| c.level(l)).unwrap_or(c.dark);
            blocks.extend(std::iter::repeat_n(Some(used_color), *used));
            blocks.extend(std::iter::repeat_n(Some(c.segment_off), *free));
            if i + 1 < st.volumes.len() {
                blocks.push(None);
            }
        }
        let selected = self.ui.selected(View::Storage, &built.dashboard);
        let map = div()
            .flex()
            .flex_col()
            .gap(px(MAP_GAP))
            .children(blocks.chunks(per_row).map(|row| {
                div().flex().flex_row().gap(px(MAP_GAP)).children(row.iter().map(|b| {
                    div()
                        .w(px(MAP_CELL))
                        .h(px(MAP_CELL))
                        .when_some(*b, |d, color| d.bg(color))
                }))
            }));
        let legend = div()
            .flex()
            .flex_row()
            .flex_wrap()
            .gap_x(px(16.0))
            .pt(px(6.0))
            .children(st.volumes.iter().map(|v| {
                div()
                    .flex()
                    .flex_row()
                    .items_center()
                    .gap(px(6.0))
                    .child(
                        div()
                            .w(px(MAP_CELL))
                            .h(px(MAP_CELL))
                            .bg(v.gauge.level.map(|l| c.level(l)).unwrap_or(c.dark)),
                    )
                    .child(format!("{} {} of {}", v.mount, v.used, v.total))
            }));
        let table = div()
            .flex()
            .flex_col()
            .child(
                div()
                    .flex()
                    .flex_row()
                    .px(px(6.0))
                    .text_color(c.dim)
                    .child(cell_flex("mount"))
                    .child(cell(100.0, "filesystem"))
                    .child(cell(90.0, "used"))
                    .child(cell(90.0, "free"))
                    .child(cell(90.0, "total"))
                    .child(cell(150.0, "used share")),
            )
            .child(
                div()
                    .id("storage.list")
                    .flex()
                    .flex_col()
                    .track_scroll(&self.scroll[View::Storage.index()])
                    .children(st.volumes.iter().enumerate().map(|(i, v)| {
                        let is_selected = selected == Some(i);
                        let share = match v.gauge.level {
                            Some(level @ (Level::Warning | Level::Critical)) => {
                                format!("{} {}", v.gauge.text, level.label())
                            }
                            _ => v.gauge.text.clone(),
                        };
                        ui::row(("volume", i), is_selected, c)
                            .on_click(cx.listener(move |this, _: &ClickEvent, _, cx| {
                                this.select(View::Storage, i, false, cx);
                            }))
                            .child(cell_flex(v.mount.clone()))
                            .child(cell(100.0, v.filesystem.clone()))
                            .child(cell(90.0, v.used.clone()))
                            .child(cell(90.0, v.free.clone()))
                            .child(cell(90.0, v.total.clone()))
                            .child(cell(150.0, share).text_color(if is_selected {
                                c.selected_text
                            } else {
                                c.level_text(v.gauge.level)
                            }))
                    })),
            );
        div()
            .id("storage")
            .flex()
            .flex_col()
            .size_full()
            .gap(px(12.0))
            .overflow_y_scroll()
            .when(st.phase != Phase::Live, |d| {
                d.child(
                    div()
                        .text_color(ui::phase_color(st.phase, c))
                        .child(format!("local telemetry {}", st.phase.label())),
                )
            })
            .child(
                ui::panel("Volume map, area is allocated bytes", c)
                    .child(div().px(px(10.0)).py(px(8.0)).child(map).child(legend)),
            )
            .child(table)
            .child(largest_panel)
            .into_any_element()
    }

    // ---- Attention --------------------------------------------------------

    fn attention(&self, dash: &Dashboard, cx: &mut Context<Self>) -> AnyElement {
        let c = self.colors;
        if dash.attention.is_empty() {
            return self.empty(if dash.connection.phase == Phase::Live {
                "Nothing needs attention.".to_string()
            } else {
                format!(
                    "No controller reports. {} Local telemetry reports still appear here.",
                    dash.connection.summary
                )
            });
        }
        let selected = self.ui.selected(View::Attention, dash);
        div()
            .flex()
            .flex_col()
            .size_full()
            .gap(px(6.0))
            .when(dash.connection.phase != Phase::Live, |d| {
                d.child(div().text_color(c.warn).child(
                    "Controller reports are not current; only local telemetry reports are listed.",
                ))
            })
            .child(
                div()
                    .flex()
                    .flex_row()
                    .px(px(6.0))
                    .text_color(c.dim)
                    .child(cell(56.0, "level"))
                    .child(cell_flex("report"))
                    .child(cell(130.0, "source")),
            )
            .child(
                div()
                    .id("attention.list")
                    .flex()
                    .flex_col()
                    .flex_1()
                    .min_h(px(0.0))
                    .overflow_y_scroll()
                    .track_scroll(&self.scroll[View::Attention.index()])
                    .children(dash.attention.iter().enumerate().map(|(i, r)| {
                        let is_selected = selected == Some(i);
                        let level_color = if is_selected {
                            c.selected_text
                        } else {
                            match r.severity {
                                Severity::Critical => c.crit,
                                Severity::Warning => c.warn,
                                Severity::Info => c.info,
                            }
                        };
                        let dim = if is_selected { c.selected_text } else { c.dim };
                        let next = if r.service_id.as_ref().is_some_and(|id| dash.services.iter().any(|s| &s.id == id)) {
                            Some("enter opens the service; r, s and n act on it")
                        } else if r.message_id.is_some() {
                            Some("enter opens the question in the Agents view")
                        } else {
                            None
                        };
                        div()
                            .id(("report", i))
                            .flex()
                            .flex_col()
                            .w_full()
                            .px(px(6.0))
                            .py(px(2.0))
                            .cursor_pointer()
                            .when(is_selected, |d| d.bg(c.dark).text_color(c.selected_text))
                            .when(!is_selected, |d| d.hover(|s| s.bg(c.panel_fill())))
                            .on_click(cx.listener(move |this, _: &ClickEvent, _, cx| {
                                this.select(View::Attention, i, false, cx);
                            }))
                            .child(
                                div()
                                    .flex()
                                    .flex_row()
                                    .child(cell(56.0, r.severity.label()).text_color(level_color))
                                    .child(cell_flex(r.title.clone()))
                                    .child(cell(130.0, r.source).text_color(dim)),
                            )
                            .child(
                                div()
                                    .pl(px(56.0))
                                    .text_size(px(SMALL_SIZE))
                                    .text_color(dim)
                                    .child(format!("{}  available: {}", r.detail, r.available)),
                            )
                            .when(is_selected, |d| {
                                d.child(
                                    div()
                                        .pl(px(56.0))
                                        .pb(px(2.0))
                                        .flex()
                                        .flex_col()
                                        .text_size(px(SMALL_SIZE))
                                        .when(!r.agent_commands.is_empty(), |d| {
                                            d.child("agent commands:")
                                        })
                                        .children(r.agent_commands.iter().map(|cmd| div().pl(px(12.0)).child(cmd.clone())))
                                        .when_some(next, |d, hint| d.child(hint)),
                                )
                            })
                    })),
            )
            .into_any_element()
    }


    // ---- Map --------------------------------------------------------

    /// The relational map: the controller at the center, devices, services,
    /// agents, processes and volumes around it, laid out once per dashboard
    /// by `RelationalMap`. Edges and node plates are canvas strokes; labels
    /// are clickable overlays; the inspector explains the selected node.
    fn map_view(
        &mut self,
        dash: &Dashboard,
        map: &RelationalMap,
        width: f32,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let c = self.colors;
        // The map opens with its first node selected so the inspector has
        // something honest to show from the first frame, the way the Agents
        // view prefers an open question.
        if !map.nodes.is_empty() && self.ui.selected(View::Map, dash).is_none() {
            self.ui.select(View::Map, 0, dash);
        }
        let selected = self.ui.selected(View::Map, dash);
        let accents = MapAccents::for_colors(&c);
        // Only fog glass draws translucent chrome; phosphor and paper keep
        // solid fills and full-color accents.
        let edge_alpha = |accent: Hsla| c.glass().map(|g| g.edge(accent)).unwrap_or(accent);
        let glow_alpha = |accent: Hsla| c.glass().map(|g| g.glow(accent)).unwrap_or(accent);

        let panel_w = width.max(380.0);
        let panel_h = (f32::from(window.viewport_size().height) - MAP_CHROME).clamp(300.0, 680.0);
        let graph_h = panel_h - MAP_FOOT;

        // Fit the settled layout into the drawing area. The margin leaves
        // room for the labels under the nodes.
        let extent = map
            .nodes
            .iter()
            .map(|n| n.x.abs().max(n.y.abs()))
            .fold(1.0_f32, f32::max)
            * 1.18;
        let scale = ((panel_w / 2.0 - MAP_MARGIN) / extent)
            .min((graph_h / 2.0 - MAP_MARGIN) / extent)
            .max(0.15);
        let points: Vec<(f32, f32)> = map
            .nodes
            .iter()
            .map(|n| (panel_w / 2.0 + n.x * scale, graph_h / 2.0 + n.y * scale))
            .collect();

        // Paint values precomputed here so the canvas closure only paints:
        // for each node its disc radius, its plate color, the glow behind it
        // and, while the level is warning or critical, its level ring.
        let rings: Vec<Option<Hsla>> = map
            .nodes
            .iter()
            .map(|node| match node.level {
                Some(Level::Critical) => Some(c.crit),
                Some(Level::Warning) => Some(c.warn),
                _ => None,
            })
            .collect();
        let plates: Vec<(f32, Hsla, Hsla)> = map
            .nodes
            .iter()
            .map(|node| {
                let accent = accents.map_accent(node.kind);
                (node_radius(node.kind), accent, glow_alpha(accent))
            })
            .collect();
        // Edges resolved to node indexes, in map order, with the overlay
        // color for the activity stroke: the target's accent when its feed
        // measured activity, `None` where it did not.
        let edges: Vec<(usize, usize, EdgeKind, Option<f64>)> = map
            .edges
            .iter()
            .filter_map(|edge| {
                let from = map.nodes.iter().position(|n| n.id == edge.source)?;
                let to = map.nodes.iter().position(|n| n.id == edge.target)?;
                Some((from, to, edge.kind, edge.activity))
            })
            .collect();
        let edge_overlay: Vec<Option<Hsla>> = map
            .edges
            .iter()
            .map(|edge| {
                map.nodes
                    .iter()
                    .position(|n| n.id == edge.target)
                    .map(|to| edge_alpha(accents.map_accent(map.nodes[to].kind)))
            })
            .collect();
        // The selection ring, drawn for whichever node is selected now.
        let selected_ring: Option<(usize, Vec<(f32, f32)>)> = selected.map(|index| {
            let node = &map.nodes[index];
            let radius = node_radius(node.kind) + 6.0;
            (
                index,
                (0..=36)
                    .map(|i| {
                        let angle = std::f32::consts::TAU * i as f32 / 36.0;
                        (
                            points[index].0 + radius * angle.cos(),
                            points[index].1 + radius * angle.sin(),
                        )
                    })
                    .collect(),
            )
        });

        let graph = div()
            .id("map.graph")
            .relative()
            .w(px(panel_w))
            .h(px(graph_h))
            .overflow_hidden()
            .child(
                canvas(
                    |_, _, _| {},
                    {
                        let points = points.clone();
                        let plates = plates.clone();
                        let rings = rings.clone();
                        let edges = edges.clone();
                        let edge_overlay = edge_overlay.clone();
                        let selected_ring = selected_ring.clone();
                        let line = c.line;
                        let bright = c.bright;
                        move |bounds, _, window, _| {
                            let o = bounds.origin;
                            // Edges first, under the node plates. The base
                            // stroke's weight follows the edge kind; the
                            // activity overlay rides on top only where a
                            // feed measured it, so an unmeasured edge never
                            // reads as active.
                            for (index, (from, to, kind, activity)) in
                                edges.iter().enumerate()
                            {
                                let a = points[*from];
                                let b = points[*to];
                                let heat = activity.unwrap_or(0.0) as f32;
                                match kind {
                                    EdgeKind::Supervises => {
                                        ui::stroke(window, o, &[a, b], 1.0 + heat * 2.5, line);
                                    }
                                    EdgeKind::RoutesTo | EdgeKind::ReportsOn => {
                                        ui::stroke_dashed(
                                            window,
                                            o,
                                            &[a, b],
                                            1.0,
                                            line,
                                            &[3.0, 3.0],
                                        );
                                    }
                                    _ => ui::stroke(window, o, &[a, b], 0.6, line),
                                }
                                if heat > 0.02 {
                                    if let Some(accent) = edge_overlay[index] {
                                        ui::stroke(
                                            window,
                                            o,
                                            &[a, b],
                                            0.8 + heat * 2.0,
                                            accent,
                                        );
                                    }
                                }
                            }
                            // Node plates: the soft glow, the disc, the
                            // level ring and the selection ring.
                            for (i, (radius, accent, glow)) in plates.iter().enumerate() {
                                let p = points[i];
                                ui::disc(window, o, p, radius + 7.0, *glow);
                                ui::disc(window, o, p, *radius, *accent);
                                if let Some(ring) = rings[i] {
                                    let points: Vec<(f32, f32)> = (0..=36)
                                        .map(|j| {
                                            let angle =
                                                std::f32::consts::TAU * j as f32 / 36.0;
                                            (
                                                p.0 + (radius + 3.5) * angle.cos(),
                                                p.1 + (radius + 3.5) * angle.sin(),
                                            )
                                        })
                                        .collect();
                                    ui::stroke(window, o, &points, 1.5, ring);
                                }
                                if selected_ring
                                    .as_ref()
                                    .is_some_and(|(selected, _)| *selected == i)
                                {
                                    let points =
                                        selected_ring.as_ref().map(|(_, points)| points).unwrap();
                                    ui::stroke(window, o, points, 1.5, bright);
                                }
                            }
                        }
                    },
                )
                .absolute()
                .size_full(),
            )
            .children(map.nodes.iter().enumerate().map(|(i, node)| {
                let (x, y) = points[i];
                let is_selected = selected == Some(i);
                let label_x = (x - MAP_LABEL_W / 2.0).clamp(2.0, panel_w - MAP_LABEL_W - 2.0);
                let label_y = (y + node_radius(node.kind) + 4.0)
                    .min((graph_h - 34.0).max(2.0));
                // The worst pinned report's word rides on the label, so the
                // dot of severity never has to travel without its word.
                let severity = node.badges.iter().map(|b| b.severity).max_by_key(|s| match s {
                    Severity::Critical => 2,
                    Severity::Warning => 1,
                    Severity::Info => 0,
                });
                div()
                    .id(("map.node", i))
                    .absolute()
                    .left(px(label_x))
                    .top(px(label_y))
                    .w(px(MAP_LABEL_W))
                    .cursor_pointer()
                    .on_click(cx.listener(move |this, _: &ClickEvent, _, cx| {
                        this.select(View::Map, i, true, cx);
                    }))
                    .flex()
                    .flex_col()
                    .items_center()
                    .gap(px(1.0))
                    .child(
                        div()
                            .text_size(px(SMALL_SIZE))
                            .font_weight(if is_selected { FontWeight::BOLD } else { FontWeight::MEDIUM })
                            .text_color(if is_selected { c.bright } else { c.text })
                            .overflow_hidden()
                            .whitespace_nowrap()
                            .text_ellipsis()
                            .max_w(px(MAP_LABEL_W))
                            .child(node.label.clone()),
                    )
                    .child(
                        div()
                            .flex()
                            .flex_row()
                            .gap(px(4.0))
                            .max_w(px(MAP_LABEL_W))
                            .overflow_hidden()
                            .child(
                                div()
                                    .text_size(px(SMALL_SIZE - 1.0))
                                    .text_color(c.dim)
                                    .overflow_hidden()
                                    .whitespace_nowrap()
                                    .text_ellipsis()
                                    .child(node.kind.label().to_string()),
                            )
                            .when_some(severity, |d, s| {
                                let color = match s {
                                    Severity::Critical => c.crit,
                                    Severity::Warning => c.warn,
                                    Severity::Info => c.info,
                                };
                                d.child(
                                    div()
                                        .text_size(px(SMALL_SIZE - 1.0))
                                        .flex_shrink_0()
                                        .text_color(color)
                                        .child(s.label().to_string()),
                                )
                            }),
                    )
                    .when(node.badge_overflow > 0, |d| {
                        d.child(
                            div()
                                .text_size(px(SMALL_SIZE - 1.0))
                                .text_color(c.crit)
                                .child(format!("+{} more", node.badge_overflow)),
                        )
                    })
            }));

        // The legend names every line shape and hue with the word it stands
        // for; color never travels alone.
        let legend = div()
            .flex()
            .flex_wrap()
            .gap_x(px(12.0))
            .gap_y(px(2.0))
            .text_size(px(SMALL_SIZE))
            .text_color(c.dim)
            .child(format!(
                "lines: {} solid at the activity it measures, {} dashed, {} thin",
                EdgeKind::Supervises.label(),
                [
                    EdgeKind::RoutesTo.label(),
                    EdgeKind::ReportsOn.label(),
                ]
                .join(" and "),
                [
                    EdgeKind::Owns.label(),
                    EdgeKind::ParentOf.label(),
                    EdgeKind::MountedOn.label(),
                ]
                .join("/")
            ))
            .children(
                [
                    (NodeKind::Controller, "controller"),
                    (NodeKind::Device, "device"),
                    (NodeKind::Service, "service"),
                    (NodeKind::Agent, "agent"),
                    (NodeKind::Process, "process"),
                    (NodeKind::Volume, "volume"),
                ]
                .into_iter()
                .map(|(kind, word)| {
                    div()
                        .flex()
                        .flex_row()
                        .items_center()
                        .gap(px(4.0))
                        .child(div().w(px(7.0)).h(px(7.0)).bg(accents.map_accent(kind)))
                        .child(word.to_string())
                }),
            );

        // The notes say which groups are not drawn and why, in feed words.
        let notes = div()
            .flex()
            .flex_col()
            .gap(px(1.0))
            .text_size(px(SMALL_SIZE))
            .text_color(c.dim)
            .max_h(px(MAP_FOOT - 2.0))
            .overflow_hidden()
            .children(map.notes.iter().map(|note| div().child(note.clone())))
            .when(map.notes.is_empty(), |d| {
                d.child(div().child("every group is drawn"))
            });

        let graph_panel = div()
            .flex()
            .flex_col()
            .border_1()
            .border_color(c.line)
            .bg(c.panel_fill())
            .px(px(8.0))
            .py(px(6.0))
            .gap(px(6.0))
            .max_h(px(panel_h))
            .child(graph)
            .child(div().border_b_1().border_color(c.line))
            .child(legend)
            .child(notes);

        // The inspector explains the selected node: its kind, heat, level,
        // freshness and the reports pinned on it. `enter` opens and closes
        // it over the selection.
        let inspector = selected
            .and_then(|index| map.nodes.get(index))
            .filter(|_| self.ui.inspecting)
            .map(|node| self.map_inspector(node));

        div()
            .flex()
            .flex_row()
            .items_start()
            .gap(px(12.0))
            .when_some(inspector, |d, panel| d.child(panel))
            .child(graph_panel)
            .into_any_element()
    }

    fn map_inspector(&self, node: &MapNode) -> Div {
        let c = self.colors;
        let accent = MapAccents::for_colors(&c).map_accent(node.kind);
        let heat_words = match node.cpu.reason() {
            Some(reason) => format!("cpu unmeasured: {}", reason.label()),
            None => format!("cpu {}", fleet_ui_core::format::percent(node.cpu)),
        };
        let level_word = node
            .level
            .filter(|level| matches!(level, Level::Warning | Level::Critical))
            .map(|level| {
                (
                    level.label().to_string(),
                    match level {
                        Level::Critical => c.crit,
                        _ => c.warn,
                    },
                )
            });
        let freshness = freshness_words(node.freshness);
        ui::panel("map node  ·  enter closes", c)
            .w(px(280.0))
            .flex_shrink_0()
            .max_h(px(560.0))
            .child(
                div()
                    .id("map.inspector")
                    .flex()
                    .flex_col()
                    .gap(px(4.0))
                    .px(px(10.0))
                    .py(px(8.0))
                    .overflow_y_scroll()
                    .child(
                        div()
                            .flex()
                            .flex_row()
                            .items_center()
                            .gap(px(6.0))
                            .child(div().w(px(9.0)).h(px(9.0)).bg(accent))
                            .child(
                                div()
                                    .text_color(accent)
                                    .child(node.kind.label().to_string()),
                            ),
                    )
                    .child(
                        div()
                            .font_weight(FontWeight::MEDIUM)
                            .overflow_hidden()
                            .whitespace_nowrap()
                            .text_ellipsis()
                            .child(node.label.clone()),
                    )
                    .child(
                        div()
                            .text_size(px(SMALL_SIZE))
                            .child(heat_words),
                    )
                    .when_some(level_word, |d, (word, color)| {
                        d.child(
                            div()
                                .text_size(px(SMALL_SIZE))
                                .text_color(color)
                                .child(word),
                        )
                    })
                    .when_some(freshness, |d, words| {
                        d.child(div().text_size(px(SMALL_SIZE)).text_color(c.dim).child(words))
                    })
                    .child(
                        div()
                            .text_size(px(SMALL_SIZE))
                            .text_color(c.dim)
                            .child(node.meta.clone()),
                    )
                    .when(
                        !node.badges.is_empty() || node.badge_overflow > 0,
                        |d| {
                            d.child(
                                div()
                                    .pt(px(4.0))
                                    .text_color(c.bright)
                                    .child("Reports"),
                            )
                            .children(node.badges.iter().map(|badge| {
                                let color = match badge.severity {
                                    Severity::Critical => c.crit,
                                    Severity::Warning => c.warn,
                                    Severity::Info => c.info,
                                };
                                div()
                                    .flex()
                                    .flex_col()
                                    .gap(px(1.0))
                                    .pt(px(2.0))
                                    .child(
                                        div()
                                            .flex()
                                            .flex_row()
                                            .gap(px(6.0))
                                            .child(
                                                div()
                                                    .w(px(30.0))
                                                    .flex_shrink_0()
                                                    .text_size(px(SMALL_SIZE))
                                                    .text_color(color)
                                                    .child(
                                                        badge.severity.label().to_string(),
                                                    ),
                                            )
                                            .child(div().flex_1().text_size(px(SMALL_SIZE)).child(badge.title.clone())),
                                    )
                                    .child(
                                        div()
                                            .pl(px(36.0))
                                            .text_size(px(SMALL_SIZE))
                                            .text_color(c.dim)
                                            .child(badge.detail.clone()),
                                    )
                                    .child(
                                        div()
                                            .pl(px(36.0))
                                            .text_size(px(SMALL_SIZE))
                                            .child(format!("available: {}", badge.available)),
                                    )
                            }))
                            .when(node.badge_overflow > 0, |d| {
                                d.child(
                                    div()
                                        .pl(px(36.0))
                                        .text_size(px(SMALL_SIZE))
                                        .text_color(c.crit)
                                        .child(format!("+{} more", node.badge_overflow)),
                                )
                            })
                        },
                    ),
            )
    }
}

/// Node plate sizes. The controller is the big center disc; groups get
/// smaller toward the periphery so the map reads from the center out.
fn node_radius(kind: NodeKind) -> f32 {
    match kind {
        NodeKind::Controller => 14.0,
        NodeKind::Device => 10.0,
        NodeKind::Service => 9.0,
        NodeKind::Agent => 9.0,
        NodeKind::Process => 6.0,
        NodeKind::Volume => 8.0,
    }
}

/// Why a node's feed is not current, in the words the other views use. The
/// current feed needs no word: the values on the node speak for it.
fn freshness_words(freshness: Freshness) -> Option<&'static str> {
    match freshness {
        Freshness::Current => None,
        Freshness::Stale => Some("feed stale"),
        Freshness::Disconnected => Some("controller disconnected"),
    }
}

impl Render for FullView {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let c = self.colors;
        let font = ui::ui_font(cx);
        let (built, notices, status_note) = {
            let hub = self.hub.read(cx);
            (hub.built.clone(), hub.notices.clone(), hub.status_note.clone())
        };
        if self.ui.view == View::Agents {
            self.ui.prefer_open_question(&built.dashboard);
        }
        let width = f32::from(window.viewport_size().width) - 2.0 * PAD;
        let map = RelationalMap::build(&built.dashboard);
        let header = self.header(&built);
        let tabs = self.tabs(&built.dashboard, &map, cx);
        let content = match self.ui.view {
            View::Overview => self.overview(&built.dashboard, width, cx),
            View::Processes => self.processes(&built.dashboard, cx),
            View::Services => self.services(&built, cx),
            View::Agents => self.agents(&built.dashboard, cx),
            View::Storage => self.storage(&built, width, cx),
            View::Attention => self.attention(&built.dashboard, cx),
            View::Map => self.map_view(&built.dashboard, &map, width, window, cx),
        };
        let telemetry_phase = built.dashboard.connection.telemetry_phase;
        let confirm = self.ui.confirm.clone().map(|confirm| self.confirm_overlay(&confirm, cx));
        div()
            .id("full")
            .track_focus(&self.focus)
            .on_key_down(cx.listener(Self::on_key))
            .relative()
            .size_full()
            .flex()
            .flex_col()
            .bg(c.window_fill())
            .text_color(c.text)
            .font_family(font)
            .text_size(px(TEXT_SIZE))
            .child(header)
            .child(tabs)
            .when_some(ui::connection_banner(&built.dashboard.connection, c, false), |d, banner| {
                d.child(div().px(px(PAD)).pt(px(10.0)).child(banner))
            })
            .when(telemetry_phase != Phase::Live, |d| {
                d.child(
                    div()
                        .px(px(PAD))
                        .pt(px(6.0))
                        .text_color(ui::phase_color(telemetry_phase, c))
                        .child(match telemetry_phase {
                            Phase::Loading => "local telemetry: waiting for the first sample".to_string(),
                            other => format!("local telemetry {}", other.label()),
                        }),
                )
            })
            .when_some(status_note, |d, note| {
                d.child(
                    div()
                        .px(px(PAD))
                        .pt(px(6.0))
                        .text_size(px(SMALL_SIZE))
                        .text_color(c.dim)
                        .child(note),
                )
            })
            .child(
                div()
                    .flex()
                    .flex_col()
                    .flex_1()
                    .min_h(px(0.0))
                    .p(px(PAD))
                    .child(content),
            )
            .child(self.activity(&built.dashboard, &notices))
            .child(self.key_hints())
            .when_some(confirm, |d, overlay| d.child(overlay))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use gpui::Modifiers;

    fn key(key: &str, modifiers: Modifiers) -> Keystroke {
        Keystroke {
            modifiers,
            key: key.into(),
            key_char: None,
        }
    }

    #[test]
    fn keystrokes_map_to_state_keys() {
        let none = Modifiers::default();
        assert_eq!(map_key(&key("j", none)), Some(Key::Char('j')));
        assert_eq!(map_key(&key("4", none)), Some(Key::Char('4')));
        assert_eq!(map_key(&key("down", none)), Some(Key::Down));
        assert_eq!(map_key(&key("enter", none)), Some(Key::Enter));
        assert_eq!(map_key(&key("escape", none)), Some(Key::Escape));
        let cmd = Modifiers {
            platform: true,
            ..Modifiers::default()
        };
        let ctrl = Modifiers {
            control: true,
            ..Modifiers::default()
        };
        assert_eq!(map_key(&key("q", cmd)), Some(Key::Quit));
        assert_eq!(map_key(&key("q", ctrl)), Some(Key::Quit));
        assert_eq!(map_key(&key("q", none)), Some(Key::Char('q')));
        assert_eq!(map_key(&key("s", cmd)), None, "cmd-s is not stop");
        let shift = Modifiers {
            shift: true,
            ..Modifiers::default()
        };
        assert_eq!(map_key(&key("s", shift)), None, "shift-s is not stop");
        assert_eq!(map_key(&key("f5", none)), None);
    }
}
