#![allow(unexpected_cfgs)]

use futures::channel::mpsc::{unbounded, UnboundedReceiver};
use futures::StreamExt;
use gpui::{
    actions, div, prelude::*, px, size, App, Application, Bounds, Context, Global, Menu, MenuItem,
    TitlebarOptions, Window, WindowBounds, WindowHandle, WindowOptions,
};
#[cfg(target_os = "macos")]
use gpui::{point, WindowKind};

mod sampler;

use sampler::Meters;

actions!(fleet_console, [Quit]);

pub const BUNDLE_ID: &str = "com.fleetconsole.app";
pub const STATUS_ITEM_AUTOSAVE_NAME: &str = "com.fleetconsole.item.fleet";
pub const METER_TEXT: &str = "CPU —   RAM —   DISK —";
pub const TOOLTIP_DISCONNECTED: &str = "FleetConsole — controller not running";
pub const POPOVER_SIZE: (f32, f32) = (360.0, 210.0);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShellEvent {
    TogglePopover,
    Quit,
    Meters(Meters),
}

pub struct PopoverView {
    meters: Meters,
}

impl Render for PopoverView {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        let meter = |label: &'static str, value: Option<u32>| {
            div()
                .flex()
                .flex_col()
                .items_center()
                .gap(px(2.0))
                .child(div().text_size(px(10.0)).child(label))
                .child(div().text_size(px(16.0)).child(sampler::value_text(value)))
        };
        div()
            .flex()
            .flex_col()
            .gap(px(12.0))
            .p(px(16.0))
            .size_full()
            .bg(gpui::rgb(0x1f1f1f))
            .text_color(gpui::rgb(0xffffff))
            .child(div().text_size(px(15.0)).child("FleetConsole"))
            .child(
                div()
                    .flex()
                    .flex_row()
                    .justify_around()
                    .child(meter("CPU", self.meters.cpu))
                    .child(meter("RAM", self.meters.ram))
                    .child(meter("DISK", self.meters.disk)),
            )
            .child(
                div()
                    .text_size(px(12.0))
                    .child("Controller not connected yet"),
            )
            .child(
                div()
                    .id("quit")
                    .flex()
                    .flex_row()
                    .justify_center()
                    .py(px(6.0))
                    .border_1()
                    .border_color(gpui::rgb(0x8a8a8a))
                    .child("Quit FleetConsole")
                    .on_click(|_, _, cx| cx.quit()),
            )
    }
}

pub struct Shell {
    meters: Meters,
    popover: Option<WindowHandle<PopoverView>>,
    #[cfg(target_os = "macos")]
    _item: Option<mac_status::Item>,
    #[cfg(target_os = "linux")]
    _tray: Option<linux_tray::Handle>,
}

impl Global for Shell {}

fn toggle_popover(cx: &mut App) {
    if let Some(handle) = cx.global::<Shell>().popover {
        let toggled = handle.update(cx, |_, window, _| {
            if window.is_window_active() {
                window.remove_window();
            } else {
                window.activate_window();
            }
        });
        if toggled.is_ok() {
            return;
        }
    }
    open_popover(cx);
}

fn open_popover(cx: &mut App) {
    let meters = cx.global::<Shell>().meters;
    let (w, h) = POPOVER_SIZE;
    #[cfg(target_os = "macos")]
    let anchored = cx
        .global::<Shell>()
        ._item
        .as_ref()
        .and_then(|item| item.anchor())
        .and_then(|anchor| {
            cx.displays()
                .into_iter()
                .find(|d| u32::from(d.id()) == anchor.display)
                .map(|d| (anchor, d.id(), f32::from(d.bounds().size.width)))
        });
    #[cfg(target_os = "macos")]
    if let Some((anchor, display, display_width)) = anchored {
        let x = (anchor.x + anchor.width - w).clamp(8.0, (display_width - w - 8.0).max(8.0));
        let options = WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(Bounds::new(
                point(px(x), px(anchor.y + anchor.height + 4.0)),
                size(px(w), px(h)),
            ))),
            titlebar: None,
            kind: WindowKind::PopUp,
            display_id: Some(display),
            is_movable: false,
            is_resizable: false,
            is_minimizable: false,
            app_id: Some(BUNDLE_ID.into()),
            ..Default::default()
        };
        if let Ok(handle) = cx.open_window(options, |_, cx| cx.new(|_| PopoverView { meters })) {
            cx.global_mut::<Shell>().popover = Some(handle);
        }
        return;
    }
    let options = WindowOptions {
        window_bounds: Some(WindowBounds::Windowed(Bounds::centered(
            None,
            size(px(w), px(h)),
            cx,
        ))),
        titlebar: Some(TitlebarOptions {
            title: Some("FleetConsole".into()),
            appears_transparent: false,
            traffic_light_position: None,
        }),
        app_id: Some(BUNDLE_ID.into()),
        ..Default::default()
    };
    if let Ok(handle) = cx.open_window(options, |_, cx| cx.new(|_| PopoverView { meters })) {
        cx.global_mut::<Shell>().popover = Some(handle);
    }
}

async fn forward_events(mut rx: UnboundedReceiver<ShellEvent>, cx: &mut gpui::AsyncApp) {
    while let Some(event) = rx.next().await {
        match event {
            ShellEvent::TogglePopover => {
                if cx.update(toggle_popover).is_err() {
                    return;
                }
            }
            ShellEvent::Meters(meters) => {
                if cx.update(|cx| apply_meters(meters, cx)).is_err() {
                    return;
                }
            }
            ShellEvent::Quit => {
                let _ = cx.update(|cx| cx.quit());
                return;
            }
        }
    }
}

fn apply_meters(meters: Meters, cx: &mut App) {
    eprintln!("FleetConsole: meters {}", meters.text());
    cx.global_mut::<Shell>().meters = meters;
    #[cfg(target_os = "macos")]
    if let Some(item) = &cx.global::<Shell>()._item {
        item.set_meters(meters);
    }
    #[cfg(target_os = "linux")]
    if let Some(tray) = &cx.global::<Shell>()._tray {
        let _ = tray.update(|tray: &mut linux_tray::FleetTray| tray.meters = meters);
    }
    if let Some(handle) = cx.global::<Shell>().popover {
        let _ = handle.update(cx, |view, _, view_cx| {
            if view.meters != meters {
                view.meters = meters;
                view_cx.notify();
            }
        });
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.iter().any(|a| a == "--version") {
        println!("FleetConsole {}", env!("CARGO_PKG_VERSION"));
        return;
    }
    if args.iter().any(|a| a == "--identity") {
        println!(
            "{{\"bundle_id\":\"{BUNDLE_ID}\",\"name\":\"FleetConsole\",\"executable\":\"FleetConsole\",\"version\":\"{}\"}}",
            env!("CARGO_PKG_VERSION")
        );
        return;
    }
    if args.iter().any(|a| a == "--help") {
        println!(
            "FleetConsole — menubar (macOS) / tray (Linux) shell\n\nUsage: FleetConsole [--popover] [--identity] [--version]\n  --popover   open the popover at launch (verification aid)\n"
        );
        return;
    }
    let open_popover_at_launch = args.iter().any(|a| a == "--popover");

    Application::new().run(move |cx: &mut App| {
        #[cfg(target_os = "macos")]
        mac_status::set_accessory_policy();

        cx.bind_keys([
            gpui::KeyBinding::new("cmd-q", Quit, None),
            gpui::KeyBinding::new("ctrl-q", Quit, None),
        ]);
        cx.on_action(|_: &Quit, cx: &mut App| cx.quit());
        cx.set_menus(vec![Menu {
            name: "FleetConsole".into(),
            items: vec![MenuItem::action("Quit FleetConsole", Quit)],
        }]);

        let (tx, rx) = unbounded::<ShellEvent>();

        #[cfg(target_os = "macos")]
        let item = match mac_status::Item::install(tx.clone()) {
            Ok(item) => {
                eprintln!("FleetConsole: macOS status item installed ({METER_TEXT})");
                Some(item)
            }
            Err(reason) => {
                eprintln!("FleetConsole: no status item: {reason}");
                None
            }
        };
        #[cfg(target_os = "linux")]
        let tray = match linux_tray::install(tx.clone()) {
            Ok(handle) => {
                eprintln!("FleetConsole: Linux StatusNotifierItem published ({METER_TEXT})");
                Some(handle)
            }
            Err(reason) => {
                eprintln!("FleetConsole: no tray item: {reason}");
                None
            }
        };

        cx.set_global(Shell {
            meters: Meters::default(),
            popover: None,
            #[cfg(target_os = "macos")]
            _item: item,
            #[cfg(target_os = "linux")]
            _tray: tray,
        });

        cx.spawn(async move |cx: &mut gpui::AsyncApp| forward_events(rx, cx).await)
            .detach();

        std::thread::spawn(move || {
            let mut sampler = sampler::Sampler::new();
            loop {
                let meters = sampler.sample();
                if tx.unbounded_send(ShellEvent::Meters(meters)).is_err() {
                    return;
                }
                std::thread::sleep(sampler::SAMPLE_INTERVAL);
            }
        });

        if open_popover_at_launch {
            toggle_popover(cx);
        }
    });
}

#[cfg(target_os = "macos")]
mod mac_status {
    use super::{Meters, ShellEvent, METER_TEXT, STATUS_ITEM_AUTOSAVE_NAME, TOOLTIP_DISCONNECTED};
    use cocoa::base::{id, nil};
    use cocoa::foundation::{NSPoint, NSRect, NSString};
    use futures::channel::mpsc::UnboundedSender;
    use objc::declare::ClassDecl;
    use objc::runtime::{Class, Object, Sel};
    use objc::{class, msg_send, sel, sel_impl};
    use std::sync::{Mutex, OnceLock};

    const TARGET_CLASS: &str = "FleetConsoleProdStatusTarget";
    const VARIABLE_LENGTH: f64 = -1.0;
    const POLICY_ACCESSORY: i64 = 1;
    const EVENT_RIGHT_MOUSE_UP: u64 = 4;

    static EVENTS: Mutex<Option<UnboundedSender<ShellEvent>>> = Mutex::new(None);

    fn send(event: ShellEvent) {
        if let Ok(guard) = EVENTS.lock() {
            if let Some(tx) = guard.as_ref() {
                let _ = tx.unbounded_send(event);
            }
        }
    }

    extern "C" fn clicked(_this: &Object, _cmd: Sel, _sender: id) {
        unsafe {
            let app: id = msg_send![class!(NSApplication), sharedApplication];
            let event: id = msg_send![app, currentEvent];
            let event_type: u64 = if event == nil {
                0
            } else {
                msg_send![event, type]
            };
            if event_type == EVENT_RIGHT_MOUSE_UP {
                show_quit_menu(_sender);
            } else {
                send(ShellEvent::TogglePopover);
            }
        }
    }

    extern "C" fn quit_clicked(_this: &Object, _cmd: Sel, _sender: id) {
        send(ShellEvent::Quit);
    }

    unsafe fn show_quit_menu(sender: id) {
        unsafe {
            let menu: id = msg_send![class!(NSMenu), alloc];
            let menu: id = msg_send![menu, init];
            let item: id = msg_send![class!(NSMenuItem), alloc];
            let item: id = msg_send![
                item,
                initWithTitle: ns_string("Quit FleetConsole")
                action: sel!(fleetQuitClicked:)
                keyEquivalent: ns_string("q")
            ];
            let target: id = msg_send![target_class(), new];
            let _: () = msg_send![item, setTarget: target];
            let _: () = msg_send![menu, addItem: item];
            let _: () = msg_send![menu, popUpMenuPositioningItem: nil atLocation: NSPoint::new(0.0, 0.0) inView: sender];
            let _: () = msg_send![menu, release];
        }
    }

    fn target_class() -> &'static Class {
        static CLASS: OnceLock<&'static Class> = OnceLock::new();
        CLASS.get_or_init(|| {
            if let Some(existing) = Class::get(TARGET_CLASS) {
                return existing;
            }
            let mut decl = ClassDecl::new(TARGET_CLASS, class!(NSObject))
                .expect("status target class name is unused");
            unsafe {
                decl.add_method(
                    sel!(fleetStatusItemClicked:),
                    clicked as extern "C" fn(&Object, Sel, id),
                );
                decl.add_method(
                    sel!(fleetQuitClicked:),
                    quit_clicked as extern "C" fn(&Object, Sel, id),
                );
            }
            decl.register()
        })
    }

    unsafe fn ns_string(text: &str) -> id {
        unsafe {
            let s: id = NSString::alloc(nil).init_str(text);
            msg_send![s, autorelease]
        }
    }

    pub fn set_accessory_policy() {
        unsafe {
            let app: id = msg_send![class!(NSApplication), sharedApplication];
            let _: bool = msg_send![app, setActivationPolicy: POLICY_ACCESSORY];
        }
    }

    pub struct Item {
        item: id,
        _target: id,
    }

    unsafe impl Send for Item {}
    unsafe impl Sync for Item {}

    impl Item {
        pub fn install(tx: UnboundedSender<ShellEvent>) -> Result<Self, String> {
            unsafe {
                let bar: id = msg_send![class!(NSStatusBar), systemStatusBar];
                if bar == nil {
                    return Err("system status bar unavailable".into());
                }
                let item: id = msg_send![bar, statusItemWithLength: VARIABLE_LENGTH];
                if item == nil {
                    return Err("status bar did not create an item".into());
                }
                let item: id = msg_send![item, retain];
                let _: () = msg_send![item, setAutosaveName: ns_string(STATUS_ITEM_AUTOSAVE_NAME)];
                let button: id = msg_send![item, button];
                if button == nil {
                    let _: () = msg_send![bar, removeStatusItem: item];
                    return Err("status item has no button".into());
                }
                let _: () = msg_send![button, setTitle: ns_string(METER_TEXT)];
                let _: () = msg_send![button, setToolTip: ns_string(TOOLTIP_DISCONNECTED)];
                let _: () = msg_send![
                    button,
                    setAccessibilityLabel: ns_string("FleetConsole fleet — CPU —, RAM —, DISK —")
                ];
                let _: () = msg_send![button, sendActionOn: 20u64];
                let target: id = msg_send![target_class(), new];
                let _: () = msg_send![button, setTarget: target];
                let _: () = msg_send![button, setAction: sel!(fleetStatusItemClicked:)];
                if let Ok(mut guard) = EVENTS.lock() {
                    *guard = Some(tx);
                }
                Ok(Self {
                    item,
                    _target: target,
                })
            }
        }

        pub fn set_meters(&self, meters: Meters) {
            unsafe {
                let button: id = msg_send![self.item, button];
                if button == nil {
                    return;
                }
                let _: () = msg_send![button, setTitle: ns_string(&meters.text())];
                let _: () = msg_send![
                    button,
                    setAccessibilityLabel: ns_string(&meters.accessibility())
                ];
            }
        }

        pub fn anchor(&self) -> Option<super::Anchor> {
            unsafe {
                let button: id = msg_send![self.item, button];
                if button == nil {
                    return None;
                }
                let window: id = msg_send![button, window];
                if window == nil {
                    return None;
                }
                let bounds: NSRect = msg_send![button, bounds];
                let in_window: NSRect = msg_send![button, convertRect: bounds toView: nil];
                let frame: NSRect = msg_send![window, convertRectToScreen: in_window];
                let screen: id = msg_send![window, screen];
                if screen == nil {
                    return None;
                }
                let screen_frame: NSRect = msg_send![screen, frame];
                let description: id = msg_send![screen, deviceDescription];
                let number: id = msg_send![description, objectForKey: ns_string("NSScreenNumber")];
                if number == nil {
                    return None;
                }
                let display: u32 = msg_send![number, unsignedIntValue];
                Some(super::Anchor {
                    display,
                    x: (frame.origin.x - screen_frame.origin.x) as f32,
                    y: (screen_frame.origin.y + screen_frame.size.height
                        - frame.origin.y
                        - frame.size.height) as f32,
                    width: frame.size.width as f32,
                    height: frame.size.height as f32,
                })
            }
        }
    }

    impl Drop for Item {
        fn drop(&mut self) {
            unsafe {
                let bar: id = msg_send![class!(NSStatusBar), systemStatusBar];
                if bar != nil && self.item != nil {
                    let _: () = msg_send![bar, removeStatusItem: self.item];
                }
            }
        }
    }
}

#[cfg(target_os = "macos")]
#[derive(Debug, Clone, Copy)]
pub struct Anchor {
    pub display: u32,
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

#[cfg(target_os = "linux")]
mod linux_tray {
    use super::{Meters, ShellEvent, BUNDLE_ID, TOOLTIP_DISCONNECTED};
    use futures::channel::mpsc::UnboundedSender;
    use ksni::menu::{MenuItem, StandardItem};
    use ksni::{Icon, ToolTip, Tray};

    pub type Handle = ksni::blocking::Handle<FleetTray>;

    pub struct FleetTray {
        tx: UnboundedSender<ShellEvent>,
        pub meters: Meters,
    }

    fn orange_pixmap() -> Vec<Icon> {
        let (w, h) = (22i32, 22i32);
        let mut data = Vec::with_capacity((w * h * 4) as usize);
        for _ in 0..(w * h) {
            data.extend_from_slice(&[0xFF, 0xF1, 0x7B, 0x33]);
        }
        vec![Icon {
            width: w,
            height: h,
            data,
        }]
    }

    impl Tray for FleetTray {
        fn id(&self) -> String {
            BUNDLE_ID.into()
        }
        fn title(&self) -> String {
            "FleetConsole".into()
        }
        fn icon_pixmap(&self) -> Vec<Icon> {
            orange_pixmap()
        }
        fn tool_tip(&self) -> ToolTip {
            ToolTip {
                title: TOOLTIP_DISCONNECTED.into(),
                description: self.meters.text(),
                icon_name: String::new(),
                icon_pixmap: Vec::new(),
            }
        }
        fn activate(&mut self, _x: i32, _y: i32) {
            let _ = self.tx.unbounded_send(ShellEvent::TogglePopover);
        }
        fn menu(&self) -> Vec<MenuItem<Self>> {
            vec![
                StandardItem {
                    label: self.meters.text(),
                    enabled: false,
                    ..Default::default()
                }
                .into(),
                StandardItem {
                    label: "Open FleetConsole".into(),
                    activate: Box::new(|tray: &mut Self| {
                        let _ = tray.tx.unbounded_send(ShellEvent::TogglePopover);
                    }),
                    ..Default::default()
                }
                .into(),
                MenuItem::Separator,
                StandardItem {
                    label: "Quit FleetConsole".into(),
                    activate: Box::new(|tray: &mut Self| {
                        let _ = tray.tx.unbounded_send(ShellEvent::Quit);
                    }),
                    ..Default::default()
                }
                .into(),
            ]
        }
    }

    pub fn install(tx: UnboundedSender<ShellEvent>) -> Result<Handle, String> {
        use ksni::blocking::TrayMethods;
        FleetTray {
            tx,
            meters: Meters::default(),
        }
        .spawn()
            .map_err(|error| format!("StatusNotifierItem spawn failed: {error}"))
    }
}
