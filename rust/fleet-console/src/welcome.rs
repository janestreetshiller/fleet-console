use cocoa::base::{id, nil};
use cocoa::foundation::{NSAutoreleasePool, NSString};
use gpui::{
    canvas, div, point, px, rgb, rgba, size, App, AppContext, Bounds, Context, Div, FocusHandle,
    FontWeight, Global, InteractiveElement, IntoElement, KeyDownEvent, Modifiers, ParentElement,
    PathBuilder, Render, Rgba, Stateful, StatefulInteractiveElement, Styled, TitlebarOptions,
    Window, WindowBounds, WindowHandle, WindowOptions,
};
use objc::runtime::{BOOL, NO, YES};
use objc::{class, msg_send, sel, sel_impl};

use crate::BUNDLE_ID;

const TITLE: &str = "Welcome to FleetConsole";
const SHOWN_KEY: &str = "fleetconsole.welcomeShown";
const SKIP_KEY: &str = "fleetconsole.skipWelcome";
const GUTTER: f32 = 21.0;
const PANEL_INSET: f32 = 8.0;
const ACTION_FILL: u32 = 0xB8460A;

#[derive(Default)]
struct Preferences {
    shown: bool,
    skip: bool,
}

impl Preferences {
    fn consume_first_run(&mut self) -> Option<bool> {
        if std::mem::replace(&mut self.shown, true) {
            None
        } else {
            Some(!self.skip)
        }
    }
}

struct Welcome {
    window: Option<WindowHandle<WelcomeView>>,
    preferences: Preferences,
    persist: bool,
    open_dashboard: fn(&mut App),
}

impl Global for Welcome {}

pub(super) fn init(cx: &mut App, persist: bool, open_dashboard: fn(&mut App)) {
    let preferences = if persist {
        Preferences {
            shown: default_bool(SHOWN_KEY),
            skip: default_bool(SKIP_KEY),
        }
    } else {
        Preferences::default()
    };
    cx.set_global(Welcome {
        window: None,
        preferences,
        persist,
        open_dashboard,
    });
}

pub(super) fn show_if_due(cx: &mut App) {
    let welcome = cx.global_mut::<Welcome>();
    if !welcome.persist {
        return;
    }
    let Some(show) = welcome.preferences.consume_first_run() else {
        return;
    };
    set_default_bool(SHOWN_KEY, true);
    if show {
        show_window(cx);
    }
}

pub(super) fn replay(cx: &mut App) {
    show_window(cx);
}

fn show_window(cx: &mut App) {
    cx.activate(true);
    if let Some(handle) = cx.global::<Welcome>().window {
        if handle
            .update(cx, |_, window, _| window.activate_window())
            .is_ok()
        {
            return;
        }
        cx.global_mut::<Welcome>().window = None;
    }
    let options = WindowOptions {
        window_bounds: Some(WindowBounds::Windowed(Bounds::centered(
            None,
            size(px(560.0), px(420.0)),
            cx,
        ))),
        titlebar: Some(TitlebarOptions {
            title: Some(TITLE.into()),
            appears_transparent: true,
            traffic_light_position: None,
        }),
        is_resizable: false,
        is_minimizable: false,
        app_id: Some(BUNDLE_ID.into()),
        ..Default::default()
    };
    match cx.open_window(options, |window, cx| {
        window.on_window_should_close(cx, |_, cx| {
            cx.global_mut::<Welcome>().window = None;
            true
        });
        cx.new(|cx| WelcomeView::new(window, cx))
    }) {
        Ok(handle) => cx.global_mut::<Welcome>().window = Some(handle),
        Err(error) => eprintln!("FleetConsole: could not open Welcome: {error}"),
    }
}

struct WelcomeView {
    focus: FocusHandle,
    skip: FocusHandle,
    never_show: FocusHandle,
    open: FocusHandle,
}

impl WelcomeView {
    fn new(window: &mut Window, cx: &mut Context<Self>) -> Self {
        let focus = cx.focus_handle();
        window.focus(&focus);
        Self {
            focus,
            skip: cx.focus_handle().tab_index(0).tab_stop(true),
            never_show: cx.focus_handle().tab_index(1).tab_stop(true),
            open: cx.focus_handle().tab_index(2).tab_stop(true),
        }
    }

    fn dismiss(window: &mut Window, cx: &mut App) {
        cx.global_mut::<Welcome>().window = None;
        window.remove_window();
    }

    fn toggle_skip(cx: &mut Context<Self>) {
        let welcome = cx.global_mut::<Welcome>();
        let skip = !welcome.preferences.skip;
        welcome.preferences.skip = skip;
        if welcome.persist {
            set_default_bool(SKIP_KEY, skip);
        }
        cx.notify();
    }

    fn open_console(window: &mut Window, cx: &mut App) {
        let open_dashboard = cx.global::<Welcome>().open_dashboard;
        Self::dismiss(window, cx);
        cx.defer(open_dashboard);
    }

    fn key_down(&mut self, event: &KeyDownEvent, window: &mut Window, cx: &mut Context<Self>) {
        let modifiers = event.keystroke.modifiers;
        match event.keystroke.key.as_str() {
            "escape" if !modifiers.modified() => Self::dismiss(window, cx),
            "enter" if !modifiers.modified() => Self::open_console(window, cx),
            "tab" if !modifiers.modified() => window.focus_next(),
            "tab" if modifiers == Modifiers::shift() => window.focus_prev(),
            "w" if modifiers == Modifiers::command() => Self::dismiss(window, cx),
            "space" if !modifiers.modified() && !event.is_held => {
                if self.skip.is_focused(window) {
                    Self::dismiss(window, cx);
                } else if self.never_show.is_focused(window) {
                    Self::toggle_skip(cx);
                } else if self.open.is_focused(window) {
                    Self::open_console(window, cx);
                } else {
                    return;
                }
            }
            _ => return,
        }
        window.prevent_default();
        cx.stop_propagation();
    }
}

impl Render for WelcomeView {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        use gpui::WindowAppearance::{Dark, VibrantDark};

        let (surface, ink, secondary, line, hover, link) =
            if matches!(window.appearance(), Dark | VibrantDark) {
                (0x202124, 0xF5F5F6, 0xBCBDC4, 0x48494F, 0x35363B, 0x8ABBFA)
            } else {
                (0xF8F7F3, 0x232427, 0x555860, 0xD8D5CE, 0xEDEBE4, 0x005BB5)
            };
        let skip = cx.global::<Welcome>().preferences.skip;
        div()
            .id("welcome")
            .track_focus(&self.focus)
            .on_key_down(cx.listener(Self::key_down))
            .size_full()
            .flex()
            .flex_col()
            .bg(rgb(surface))
            .text_color(rgb(ink))
            .text_size(px(13.0))
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .pl(px(76.0))
                    .pr(px(GUTTER))
                    .py(px(PANEL_INSET))
                    .border_b_1()
                    .border_color(rgb(line))
                    .child(div().font_weight(FontWeight::SEMIBOLD).child(TITLE))
                    .child(
                        div()
                            .px(px(7.0))
                            .py(px(2.0))
                            .rounded(px(4.0))
                            .border_1()
                            .border_color(rgb(line))
                            .text_color(rgb(secondary))
                            .text_size(px(10.0))
                            .font_weight(FontWeight::MEDIUM)
                            .child("MIT · OPEN SOURCE"),
                    ),
            )
            .child(
                div()
                    .flex_1()
                    .flex()
                    .flex_col()
                    .justify_center()
                    .gap(px(13.0))
                    .px(px(GUTTER))
                    .child(
                        div()
                            .text_size(px(24.0))
                            .font_weight(FontWeight::SEMIBOLD)
                            .child("See what your Mac is doing."),
                    )
                    .child(
                        div()
                            .text_color(rgb(secondary))
                            .child("Live metrics and background work, one click from the menu bar."),
                    )
                    .children(FEATURES.iter().map(|&(label, icon)| {
                        div()
                            .flex()
                            .items_center()
                            .gap(px(8.0))
                            .child(feature_icon(icon, rgb(ink)))
                            .child(label)
                    })),
            )
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap(px(8.0))
                    .px(px(GUTTER - 8.0))
                    .pr(px(GUTTER))
                    .py(px(PANEL_INSET))
                    .border_t_1()
                    .border_color(rgb(line))
                    .child(
                        control("welcome-skip", &self.skip, rgb(link))
                            .text_color(rgb(link))
                            .hover(move |style| style.bg(rgb(hover)))
                            .on_click(|_, window, cx| Self::dismiss(window, cx))
                            .child("Skip"),
                    )
                    .child(
                        control("welcome-never-show", &self.never_show, rgb(link))
                            .text_size(px(12.0))
                            .hover(move |style| style.bg(rgb(hover)))
                            .on_click(cx.listener(|_, _, _, cx| Self::toggle_skip(cx)))
                            .child(
                                div()
                                    .size(px(14.0))
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .rounded(px(3.0))
                                    .border_1()
                                    .border_color(rgb(if skip { ACTION_FILL } else { secondary }))
                                    .bg(if skip { rgb(ACTION_FILL) } else { rgba(0) })
                                    .text_color(rgb(0xFFFFFF))
                                    .font_weight(FontWeight::SEMIBOLD)
                                    .children(skip.then_some("✓")),
                            )
                            .child("Don't show again"),
                    )
                    .child(div().flex_1())
                    .child(
                        control("welcome-open", &self.open, rgb(link))
                            .px(px(12.0))
                            .bg(rgb(ACTION_FILL))
                            .text_color(rgb(0xFFFFFF))
                            .hover(|style| style.bg(rgb(0xAC4209)))
                            .active(|style| style.bg(rgb(0xA23E09)))
                            .on_click(|_, window, cx| Self::open_console(window, cx))
                            .child("Open Console"),
                    ),
            )
    }
}

fn control(id: &'static str, focus: &FocusHandle, focus_color: Rgba) -> Stateful<Div> {
    div()
        .id(id)
        .track_focus(focus)
        .h(px(30.0))
        .px(px(8.0))
        .flex()
        .items_center()
        .gap(px(6.0))
        .rounded(px(5.0))
        .border_1()
        .border_color(rgba(0))
        .focus(move |style| style.border_color(focus_color))
        .cursor_pointer()
}

type Icon = &'static [&'static [(f32, f32)]];

const FEATURES: [(&str, Icon); 3] = [
    (
        "Explore CPU and memory over time",
        &[
            &[(2.0, 2.0), (2.0, 14.0), (14.0, 14.0)],
            &[(4.0, 11.0), (7.0, 7.0), (10.0, 9.0), (14.0, 4.0)],
        ],
    ),
    (
        "Inspect processes, services and leases",
        &[
            &[(2.0, 4.0), (3.0, 4.0)],
            &[(6.0, 4.0), (14.0, 4.0)],
            &[(2.0, 8.0), (3.0, 8.0)],
            &[(6.0, 8.0), (14.0, 8.0)],
            &[(2.0, 12.0), (3.0, 12.0)],
            &[(6.0, 12.0), (14.0, 12.0)],
        ],
    ),
    (
        "Link more computers through the device add-on",
        &[
            &[(1.5, 2.5), (14.5, 2.5), (14.5, 11.5), (1.5, 11.5), (1.5, 2.5)],
            &[(8.0, 11.5), (8.0, 14.0)],
            &[(5.0, 14.0), (11.0, 14.0)],
        ],
    ),
];

fn feature_icon(icon: Icon, color: Rgba) -> impl IntoElement {
    canvas(
        |_, _, _| (),
        move |bounds, (), window, _| {
            let at = |(x, y)| point(bounds.origin.x + px(x), bounds.origin.y + px(y));
            let mut path = PathBuilder::stroke(px(1.25));
            for segment in icon {
                let Some((&first, rest)) = segment.split_first() else {
                    continue;
                };
                path.move_to(at(first));
                for &point in rest {
                    path.line_to(at(point));
                }
            }
            if let Ok(path) = path.build() {
                window.paint_path(path, color);
            }
        },
    )
    .size(px(16.0))
    .flex_none()
}

fn with_default_key<T>(key: &str, action: impl FnOnce(id, id) -> T) -> T {
    unsafe {
        let pool = NSAutoreleasePool::new(nil);
        let defaults: id = msg_send![class!(NSUserDefaults), standardUserDefaults];
        let key = NSString::alloc(nil).init_str(key);
        let key: id = msg_send![key, autorelease];
        let result = action(defaults, key);
        pool.drain();
        result
    }
}

fn default_bool(key: &str) -> bool {
    with_default_key(key, |defaults, key| unsafe {
        let value: BOOL = msg_send![defaults, boolForKey: key];
        value != NO
    })
}

fn set_default_bool(key: &str, value: bool) {
    with_default_key(key, |defaults, key| unsafe {
        let value = if value { YES } else { NO };
        let _: () = msg_send![defaults, setBool: value forKey: key];
    });
}

#[cfg(test)]
mod tests {
    use super::Preferences;

    #[test]
    fn first_run_is_consumed_once() {
        let mut preferences = Preferences::default();
        assert_eq!(preferences.consume_first_run(), Some(true));
        assert_eq!(preferences.consume_first_run(), None);
    }

    #[test]
    fn first_run_is_consumed_even_when_skip_is_set() {
        let mut preferences = Preferences {
            shown: false,
            skip: true,
        };
        assert_eq!(preferences.consume_first_run(), Some(false));
        assert!(preferences.shown);
        assert!(preferences.skip);
        preferences.skip = false;
        assert_eq!(preferences.consume_first_run(), None);
    }
}
