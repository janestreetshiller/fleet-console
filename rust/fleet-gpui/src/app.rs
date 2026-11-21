
use crate::cli::Options;
use crate::feeds::{Built, Feeds, Fingerprint, STALENESS_CHECK};
use crate::full::FullView;
use crate::quick::QuickView;
use crate::state::View;
use crate::status_item::{self, Anchor};
use crate::ui::UiFont;use fleet_ui_core::Action;
use futures::channel::mpsc::{unbounded, UnboundedReceiver};
use futures::future::Either;
use futures::StreamExt;
use gpui::{
    actions, point, px, size, App, AppContext, Application, AsyncApp, Bounds, Context, Entity,
    Global, KeyBinding, Menu, MenuItem, Task, TitlebarOptions, WeakEntity, WindowBounds,
    WindowHandle, WindowKind, WindowOptions,
};
use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

actions!(fleet_console, [Quit, OpenWindow, OpenQuickView, Refresh]);

pub const NOTICE_LIMIT: usize = 6;

pub const FULL_SIZE: (f32, f32) = (1180.0, 780.0);
pub const FULL_MIN: (f32, f32) = (720.0, 480.0);
pub const QUICK_SIZE: (f32, f32) = (600.0, 300.0);
pub const QUICK_MIN: (f32, f32) = (520.0, 240.0);

pub struct Hub {
    feeds: Feeds,
    pub built: Arc<Built>,
    fingerprint: Fingerprint,
    pub notices: VecDeque<String>,
    pub status_note: Option<String>,
    _watch: Option<Task<()>>,
}

impl Hub {
    fn new(feeds: Feeds, wake: (UnboundedReceiver<()>, Arc<AtomicBool>), cx: &mut Context<Self>) -> Self {
        let now = feeds.now();
        let built = Arc::new(feeds.build(now));
        let fingerprint = feeds.fingerprint(now);
        let watch = if feeds.is_static() {
            None
        } else {
            let (rx, pending) = wake;
            Some(cx.spawn(async move |this, cx| watch(this, rx, pending, cx).await))
        };
        Self {
            feeds,
            built,
            fingerprint,
            notices: VecDeque::new(),
            status_note: None,
            _watch: watch,
        }
    }

    fn update_if_changed(&mut self, cx: &mut Context<Self>) {
        let now = self.feeds.now();
        let fingerprint = self.feeds.fingerprint(now);
        if fingerprint == self.fingerprint {
            return;
        }
        self.fingerprint = fingerprint;
        let built = self.feeds.build(now);
        if *self.built != built {
            self.built = Arc::new(built);
            cx.notify();
        }
    }

    pub fn submit(&mut self, action: Action, cx: &mut Context<Self>) {
        match self.feeds.submit(action.clone()) {
            Ok(_) => self.update_if_changed(cx),
            Err(reason) => self.notice(format!("{} not sent: {reason}", action.label()), cx),
        }
    }

    pub fn notice(&mut self, text: String, cx: &mut Context<Self>) {
        self.notices.push_front(text);
        self.notices.truncate(NOTICE_LIMIT);
        cx.notify();
    }

    pub fn refresh(&mut self, cx: &mut Context<Self>) {
        if self.feeds.is_static() {
            self.notice("refresh unavailable: fixture mode: no controller".into(), cx);
        } else {
            self.feeds.refresh();
        }
    }

    pub fn set_status_note(&mut self, note: Option<String>, cx: &mut Context<Self>) {
        if self.status_note != note {
            self.status_note = note;
            cx.notify();
        }
    }
}

async fn watch(
    this: WeakEntity<Hub>,
    mut rx: UnboundedReceiver<()>,
    pending: Arc<AtomicBool>,
    cx: &mut AsyncApp,
) {
    let mut channel_open = true;
    loop {
        let timer = cx.background_executor().timer(STALENESS_CHECK);
        if channel_open {
            if let Either::Left((None, _)) = futures::future::select(rx.next(), timer).await {
                channel_open = false;
            }
        } else {
            timer.await;
        }
        pending.store(false, Ordering::Release);
        if this.update(cx, |hub, cx| hub.update_if_changed(cx)).is_err() {
            return;
        }
    }
}

pub struct Windows {
    pub hub: Entity<Hub>,
    pub quick: Option<WindowHandle<QuickView>>,
    pub full: Option<WindowHandle<FullView>>,
    first_size: Option<(f32, f32)>,
    initial_view: View,
    item: Option<status_item::Item>,
    popover_closed_at: Option<Instant>,
}

impl Global for Windows {}

impl Windows {
    pub fn has_status_item(&self) -> bool {
        self.item.is_some()
    }
}

fn take_size(cx: &mut App, default: (f32, f32)) -> (f32, f32) {
    if !cx.has_global::<Windows>() {
        return default;
    }
    cx.global_mut::<Windows>()
        .first_size
        .take()
        .unwrap_or(default)
}

pub fn open_full(view: Option<View>, cx: &mut App) {
    let (hub, existing, initial) = {
        let w = cx.global::<Windows>();
        (w.hub.clone(), w.full, w.initial_view)
    };
    if let Some(handle) = existing {
        let shown = handle.update(cx, |full, window, cx| {
            if let Some(view) = view {
                full.show_view(view, cx);
            }
            window.activate_window();
        });
        if shown.is_ok() {
            cx.activate(true);
            return;
        }
    }
    let (w, h) = take_size(cx, FULL_SIZE);
    let bounds = Bounds::centered(None, size(px(w), px(h)), cx);
    let options = WindowOptions {
        window_bounds: Some(WindowBounds::Windowed(bounds)),
        titlebar: Some(TitlebarOptions {
            title: Some("FleetConsole".into()),
            appears_transparent: false,
            traffic_light_position: None,
        }),
        window_min_size: Some(size(px(FULL_MIN.0), px(FULL_MIN.1))),
        app_id: Some("fleetconsole".into()),
        window_background: crate::palette::window_background(cx),
        ..Default::default()
    };
    let start = view.unwrap_or(initial);
    match cx.open_window(options, |window, cx| {
        cx.new(|cx| FullView::new(hub, start, window, cx))
    }) {
        Ok(handle) => {
            cx.global_mut::<Windows>().full = Some(handle);
            cx.activate(true);
        }
        Err(error) => eprintln!("fleet-gpui: could not open the window: {error}"),
    }
}

pub fn open_quick(anchor: Option<Anchor>, cx: &mut App) {
    let (hub, existing) = {
        let w = cx.global::<Windows>();
        (w.hub.clone(), w.quick)
    };
    if let Some(handle) = existing {
        if handle
            .update(cx, |_, window, _| window.activate_window())
            .is_ok()
        {
            return;
        }
    }
    let (w, h) = take_size(cx, QUICK_SIZE);
    let popover = anchor.and_then(|a| {
        cx.displays()
            .into_iter()
            .find(|d| u32::from(d.id()) == a.display)
            .map(|d| (a, d.id(), f32::from(d.bounds().size.width)))
    });
    let options = match popover {
        Some((anchor, display, display_width)) => {
            let (x, y) = status_item::popover_origin(anchor, display_width, w);
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(Bounds::new(
                    point(px(x), px(y)),
                    size(px(w), px(h)),
                ))),
                titlebar: None,
                kind: WindowKind::PopUp,
                display_id: Some(display),
                is_movable: false,
                is_resizable: false,
                is_minimizable: false,
                app_id: Some("fleetconsole".into()),
                window_background: crate::palette::window_background(cx),
                ..Default::default()
            }
        }
        None => WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(Bounds::centered(
                None,
                size(px(w), px(h)),
                cx,
            ))),
            titlebar: Some(TitlebarOptions {
                title: Some("FleetConsole quick view".into()),
                appears_transparent: false,
                traffic_light_position: None,
            }),
            window_min_size: Some(size(px(QUICK_MIN.0), px(QUICK_MIN.1))),
            app_id: Some("fleetconsole".into()),
            window_background: crate::palette::window_background(cx),
            ..Default::default()
        },
    };
    let is_popover = popover.is_some();
    match cx.open_window(options, |window, cx| {
        cx.new(|cx| QuickView::new(hub, is_popover, window, cx))
    }) {
        Ok(handle) => {
            cx.global_mut::<Windows>().quick = Some(handle);
            if !is_popover {
                cx.activate(true);
            }
        }
        Err(error) => eprintln!("fleet-gpui: could not open the quick view: {error}"),
    }
}

pub fn popover_closed(cx: &mut App) {
    if cx.has_global::<Windows>() {
        cx.global_mut::<Windows>().popover_closed_at = Some(Instant::now());
    }
}

fn toggle_quick_from_status_item(cx: &mut App) {
    let (existing, recently_closed, anchor) = {
        let w = cx.global::<Windows>();
        (
            w.quick,
            w.popover_closed_at
                .is_some_and(|t| t.elapsed() < Duration::from_millis(400)),
            w.item.as_ref().and_then(|i| i.anchor()),
        )
    };
    if recently_closed {
        cx.global_mut::<Windows>().popover_closed_at = None;
        return;
    }
    if let Some(handle) = existing {
        let result = handle.update(cx, |_, window, _| {
            if window.is_window_active() {
                window.remove_window();
            } else {
                window.activate_window();
            }
        });
        if result.is_ok() {
            return;
        }
    }
    open_quick(anchor, cx);
}

fn show_quick(cx: &mut App) {
    let anchor = cx
        .global::<Windows>()
        .item
        .as_ref()
        .and_then(|i| i.anchor());
    open_quick(anchor, cx);
}

pub fn refresh(cx: &mut App) {
    let hub = cx.global::<Windows>().hub.clone();
    hub.update(cx, |hub, cx| hub.refresh(cx));
}

pub fn run(options: Options) {
    Application::new().run(move |cx: &mut App| {
        let font = crate::palette::choose_font(&cx.text_system().all_font_names());
        cx.set_global(UiFont(font.into()));
        cx.set_global(crate::palette::UiDarkTheme(options.theme));

        cx.bind_keys([
            KeyBinding::new("cmd-q", Quit, None),
            KeyBinding::new("ctrl-q", Quit, None),
        ]);
        cx.on_action(|_: &Quit, cx: &mut App| cx.quit());
        cx.on_action(|_: &OpenWindow, cx: &mut App| open_full(None, cx));
        cx.on_action(|_: &OpenQuickView, cx: &mut App| show_quick(cx));
        cx.on_action(|_: &Refresh, cx: &mut App| refresh(cx));
        cx.set_menus(vec![Menu {
            name: "FleetConsole".into(),
            items: vec![
                MenuItem::action("Open Quick View", OpenQuickView),
                MenuItem::action("Open Window", OpenWindow),
                MenuItem::action("Refresh", Refresh),
                MenuItem::separator(),
                MenuItem::action("Quit FleetConsole", Quit),
            ],
        }]);

        let (tx, rx) = unbounded::<()>();
        let pending = Arc::new(AtomicBool::new(false));
        let wake: fleet_ui_core::controller::Wake = {
            let pending = pending.clone();
            Arc::new(move || {
                if !pending.swap(true, Ordering::AcqRel) {
                    let _ = tx.unbounded_send(());
                }
            })
        };
        let feeds = Feeds::start(&options, wake);
        let hub = cx.new(|cx| Hub::new(feeds, (rx, pending), cx));

        let item = install_status_item(&hub, cx);
        let has_item = item.is_some();
        cx.set_global(Windows {
            hub: hub.clone(),
            quick: None,
            full: None,
            first_size: options.window_size,
            initial_view: options.view,
            item,
            popover_closed_at: None,
        });

        cx.on_window_closed(move |cx| {
            if !has_item && cx.windows().is_empty() {
                cx.quit();
            }
        })
        .detach();

        if options.quick {
            open_quick(None, cx);
        } else {
            open_full(Some(options.view), cx);
        }
    });
}

fn install_status_item(hub: &Entity<Hub>, cx: &mut App) -> Option<status_item::Item> {
    match status_item::Item::install() {
        Ok((item, mut clicks)) => {
            cx.spawn(async move |cx: &mut AsyncApp| {
                while clicks.next().await.is_some() {
                    if cx.update(toggle_quick_from_status_item).is_err() {
                        return;
                    }
                }
            })
            .detach();
            Some(item)
        }
        Err(status_item::Unavailable::Immediate(reason)) => {
            hub.update(cx, |hub, cx| hub.set_status_note(Some(reason), cx));
            None
        }
        Err(status_item::Unavailable::Probe) => {
            let hub = hub.downgrade();
            let probe = cx
                .background_executor()
                .spawn(async { status_item::describe(&fleet_ui_core::platform::status_area()) });
            cx.spawn(async move |cx: &mut AsyncApp| {
                let note = probe.await;
                let _ = hub.update(cx, |hub, cx| hub.set_status_note(note, cx));
            })
            .detach();
            None
        }
    }
}
