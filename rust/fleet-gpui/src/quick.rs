//! The quick view: the Mac popover's information in the phosphor system.
//!
//! Header: logo, "FleetConsole", the running-service count, a button that
//! opens the full window, an Agents button that opens it on the Agents view,
//! and a More menu (Refresh, Open window, Quit). Four columns: CPU and
//! Memory dials, Disk as a 5 by 4 block grid, Network as download and upload
//! rates with bars. Opened from the status item it is a popover that closes
//! when it loses focus; opened with `--quick` it is an ordinary window.

use crate::app::{self, Hub};
use crate::palette::Colors;
use crate::state::View;
use crate::ui::{self, SMALL_SIZE, TEXT_SIZE};
use fleet_ui_core::observe::Phase;
use fleet_ui_core::views::{Control, Gauge};
use gpui::{
    div, prelude::*, px, ClickEvent, Context, Div, Entity, FocusHandle, FontWeight, KeyDownEvent,
    Subscription, Window,
};

pub struct QuickView {
    hub: Entity<Hub>,
    colors: Colors,
    focus: FocusHandle,
    menu_open: bool,
    popover: bool,
    _subscriptions: Vec<Subscription>,
}

impl QuickView {
    pub fn new(hub: Entity<Hub>, popover: bool, window: &mut Window, cx: &mut Context<Self>) -> Self {
        let focus = cx.focus_handle();
        window.focus(&focus);
        let mut subscriptions = vec![
            cx.observe(&hub, |_, _, cx| cx.notify()),
            cx.observe_window_appearance(window, |this, window, cx| {
                this.colors = Colors::for_window(window.appearance(), cx);
                cx.notify();
            }),
        ];
        if popover {
            subscriptions.push(cx.observe_window_activation(window, |_, window, cx| {
                if !window.is_window_active() {
                    app::popover_closed(cx);
                    window.remove_window();
                }
            }));
        }
        Self {
            hub,
            colors: Colors::for_window(window.appearance(), cx),
            focus,
            menu_open: false,
            popover,
            _subscriptions: subscriptions,
        }
    }

    fn on_key(&mut self, event: &KeyDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        let key = event.keystroke.key.as_str();
        let m = &event.keystroke.modifiers;
        if m.platform || m.control || m.alt {
            return;
        }
        match key {
            "escape" if self.menu_open => self.menu_open = false,
            "escape" if self.popover => window.remove_window(),
            "r" => app::refresh(cx),
            "g" | "enter" => cx.defer(|cx| app::open_full(None, cx)),
            "a" => cx.defer(|cx| app::open_full(Some(View::Agents), cx)),
            _ => return,
        }
        cx.stop_propagation();
        cx.notify();
    }

    fn header(&self, cx: &mut Context<Self>) -> Div {
        let c = self.colors;
        let (waiting, subtitle) = {
            let header = &self.hub.read(cx).built.dashboard.header;
            (header.awaiting_reply.unwrap_or(0), header.subtitle.clone())
        };
        let agents_label = if waiting > 0 {
            format!("Agents {waiting} waiting")
        } else {
            "Agents".to_string()
        };
        div()
            .flex()
            .flex_row()
            .items_center()
            .gap(px(10.0))
            .px(px(12.0))
            .py(px(8.0))
            .border_b_1()
            .border_color(c.line)
            .child(ui::logo(c, 4.0))
            .child(
                div()
                    .flex()
                    .flex_col()
                    .flex_1()
                    .min_w(px(0.0))
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
                            .child(subtitle),
                    ),
            )
            .child(
                div()
                    .id("quick.open-window")
                    .flex()
                    .flex_row()
                    .flex_shrink_0()
                    .items_center()
                    .gap(px(6.0))
                    .px(px(8.0))
                    .py(px(2.0))
                    .border_1()
                    .border_color(c.dark)
                    .text_color(c.bright)
                    .cursor_pointer()
                    .hover(|s| s.bg(c.panel_fill()))
                    .child(ui::grid_icon(c.bright))
                    .child("Window")
                    .tooltip(ui::tooltip("Open the full window (g)", c))
                    .on_click(|_: &ClickEvent, _, cx| cx.defer(|cx| app::open_full(None, cx))),
            )
            .child(
                ui::button("quick.agents", agents_label, &Control::Allowed, c)
                    .tooltip(ui::tooltip("Open the window on the Agents view (a)", c))
                    .on_click(|_: &ClickEvent, _, cx| {
                        cx.defer(|cx| app::open_full(Some(View::Agents), cx))
                    }),
            )
            .child(
                ui::button("quick.more", "More", &Control::Allowed, c)
                    .when(self.menu_open, |b| b.bg(c.dark).text_color(c.selected_text))
                    .on_click(cx.listener(|this, _: &ClickEvent, _, cx| {
                        this.menu_open = !this.menu_open;
                        cx.notify();
                    })),
            )
    }

    fn menu(&self, cx: &mut Context<Self>) -> Div {
        let c = self.colors;
        let item = |id: &'static str, label: &'static str| {
            div()
                .id(id)
                .px(px(12.0))
                .py(px(4.0))
                .cursor_pointer()
                .text_color(c.text)
                .hover(|s| s.bg(c.dark).text_color(c.selected_text))
                .child(label)
        };
        div()
            .absolute()
            .top(px(46.0))
            .right(px(12.0))
            .w(px(180.0))
            .flex()
            .flex_col()
            .py(px(4.0))
            .bg(c.panel_fill())
            .border_1()
            .border_color(c.line)
            .occlude()
            .child(item("menu.refresh", "Refresh").on_click(cx.listener(
                |this, _: &ClickEvent, _, cx| {
                    this.menu_open = false;
                    app::refresh(cx);
                    cx.notify();
                },
            )))
            .child(item("menu.window", "Open window").on_click(cx.listener(
                |this, _: &ClickEvent, _, cx| {
                    this.menu_open = false;
                    cx.defer(|cx| app::open_full(None, cx));
                    cx.notify();
                },
            )))
            .child(
                item("menu.quit", "Quit")
                    .on_click(|_: &ClickEvent, _, cx| cx.quit()),
            )
    }
}

fn dial_column(gauge: &Gauge, c: Colors) -> Div {
    div()
        .flex()
        .flex_col()
        .items_center()
        .flex_1()
        .min_w(px(0.0))
        .gap(px(2.0))
        .child(div().text_color(c.dim).child(gauge.label))
        .child(ui::dial(gauge, c, 116.0, 86.0))
        .child(
            div()
                .text_size(px(20.0))
                .text_color(c.level_text(gauge.level))
                .font_weight(FontWeight::BOLD)
                .child(gauge.text.clone()),
        )
        .child(
            div()
                .text_size(px(SMALL_SIZE))
                .text_color(c.dim)
                .text_center()
                .child(ui::gauge_caption(gauge)),
        )
}

impl Render for QuickView {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let c = self.colors;
        let font = ui::ui_font(cx);
        let (built, status_note) = {
            let hub = self.hub.read(cx);
            (hub.built.clone(), hub.status_note.clone())
        };
        let dash = &built.dashboard;
        let q = &dash.quick;
        let header = self.header(cx);
        let telemetry_note = match dash.connection.telemetry_phase {
            Phase::Live => None,
            Phase::Loading => Some("local telemetry: waiting for the first sample".to_string()),
            other => Some(format!("local telemetry {}", other.label())),
        };
        let mut footer: Vec<String> = Vec::new();
        if let Some(name) = built.fixture {
            footer.push(format!("synthetic fixture data: {name}"));
        }
        if dash.connection.read_only {
            footer.push("read-only".into());
        }
        if let Some(note) = status_note {
            footer.push(note);
        }
        let _ = window;

        div()
            .id("quick")
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
            .when_some(ui::connection_banner(&dash.connection, c, true), |d, banner| {
                d.child(div().px(px(12.0)).pt(px(8.0)).child(banner))
            })
            .when_some(telemetry_note, |d, note| {
                d.child(
                    div()
                        .px(px(12.0))
                        .pt(px(6.0))
                        .text_size(px(SMALL_SIZE))
                        .text_color(c.info)
                        .child(note),
                )
            })
            .child(
                div()
                    .flex()
                    .flex_row()
                    .flex_1()
                    .gap(px(12.0))
                    .px(px(12.0))
                    .py(px(10.0))
                    .child(dial_column(&q.cpu, c))
                    .child(dial_column(&q.memory, c))
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .items_center()
                            .flex_1()
                            .min_w(px(0.0))
                            .gap(px(4.0))
                            .child(div().text_color(c.dim).child(q.disk.gauge.label))
                            .child(div().pt(px(8.0)).child(ui::disk_grid(&q.disk, c, 14.0)))
                            .child(
                                div()
                                    .pt(px(6.0))
                                    .text_size(px(20.0))
                                    .text_color(c.level_text(q.disk.gauge.level))
                                    .font_weight(FontWeight::BOLD)
                                    .child(q.disk.gauge.text.clone()),
                            )
                            .child(
                                div()
                                    .text_size(px(SMALL_SIZE))
                                    .text_color(c.dim)
                                    .text_center()
                                    .child(ui::gauge_caption(&q.disk.gauge)),
                            ),
                    )
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .flex_1()
                            .min_w(px(0.0))
                            .gap(px(10.0))
                            .child(div().text_color(c.dim).text_center().child("Network"))
                            .child(ui::rate(&q.download, c))
                            .child(ui::rate(&q.upload, c)),
                    ),
            )
            .when(!footer.is_empty(), |d| {
                d.child(
                    div()
                        .flex()
                        .flex_col()
                        .px(px(12.0))
                        .py(px(6.0))
                        .border_t_1()
                        .border_color(c.line)
                        .text_size(px(SMALL_SIZE))
                        .text_color(c.dim)
                        .children(footer.into_iter().map(|line| div().child(line))),
                )
            })
            .when(self.menu_open, |d| d.child(self.menu(cx)))
    }
}
