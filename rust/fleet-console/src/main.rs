#![allow(unexpected_cfgs)]

use std::io;
use std::os::unix::fs::{DirBuilderExt, MetadataExt};
use std::path::Path;
use std::sync::Arc;
use std::time::{Duration, Instant};

use futures::channel::mpsc::{unbounded, UnboundedReceiver, UnboundedSender};
use futures::StreamExt;
use gpui::{
    actions, div, prelude::*, px, size, App, Application, Bounds, Context, Global, Menu, MenuItem,
    TitlebarOptions, Window, WindowBounds, WindowHandle, WindowOptions,
};
#[cfg(target_os = "macos")]
use gpui::{point, WindowKind};

mod awareness_layout;
mod config;
mod controller;
mod dashboard;
#[cfg(target_os = "macos")]
mod mac_launch;
#[cfg(any(target_os = "macos", test))]
mod notifications;
mod quickview;
mod sampler;
mod snapshot;
#[cfg(target_os = "macos")]
mod welcome;

use config::{ConfigPath, ConfigRead, Sections, UiConfig};
use dashboard::{DashboardView, LaunchRow, Module};
use sampler::{Meters, Sample};
use snapshot::FleetView;

actions!(fleet_console, [Quit]);
#[cfg(target_os = "macos")]
actions!(fleet_console, [ShowAbout, HideFleetConsole, HideOtherApps]);
actions!(
    fleet_console_dashboard,
    [
        OpenDashboard,
        ShowOverview,
        ShowProcesses,
        ShowStorage,
        ShowServices,
        ShowEvents,
        ShowLaunchServices,
        RefreshProbes,
        EditConfiguration,
        RevealLogs,
        OpenGuide,
        ShowCliSetup
    ]
);

pub const BUNDLE_ID: &str = "com.fleetconsole.app";
pub const STATUS_ITEM_AUTOSAVE_NAME: &str = "com.fleetconsole.item.fleet";
pub const METER_TEXT: &str = "CPU —   RAM —   DISK —";
pub const TOOLTIP_DISCONNECTED: &str = "FleetConsole — controller not running";
pub const POPOVER_SIZE: (f32, f32) = (480.0, 260.0);
const CONFIG_CHECK_INTERVAL: Duration = Duration::from_secs(1);

#[derive(Debug, Clone)]
pub enum ShellEvent {
    TogglePopover,
    Quit,
    Sample(Sample),
    Connection(bool),
    Snapshot(snapshot::Snapshot),
    Processes(Vec<sampler::ProcRow>),
    LaunchServices(Vec<LaunchRow>),
    ShowModule(Module),
    #[cfg(target_os = "macos")]
    DashboardHandoff(Module),
    Reconcile,
    ConfigLoaded(ConfigRead),
    EditConfiguration,
    RevealLogs,
    #[cfg(target_os = "macos")]
    ReplayWelcome,
    OpenGuide,
    #[cfg(target_os = "macos")]
    ShowCliSetup,
}

pub struct PopoverView {
    sample: Option<Sample>,
    status: String,
}

impl Render for PopoverView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .id("quick-view")
            .overflow_y_scroll()
            .flex()
            .flex_col()
            .gap(px(10.0))
            .p(px(16.0))
            .size_full()
            .bg(gpui::rgb(0x1f1f1f))
            .text_color(gpui::rgb(0xffffff))
            .child(
                div()
                    .flex()
                    .flex_row()
                    .justify_between()
                    .items_start()
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap(px(2.0))
                            .child(div().text_size(px(15.0)).child("FleetConsole"))
                            .child(
                                div()
                                    .text_size(px(12.0))
                                    .text_color(gpui::rgb(0x8e8e93))
                                    .child(self.status.clone()),
                            ),
                    )
                    .child(
                        div()
                            .id("open-dashboard")
                            .px(px(10.0))
                            .py(px(5.0))
                            .border_1()
                            .border_color(gpui::rgb(0x8a8a8a))
                            .rounded(px(6.0))
                            .text_size(px(12.0))
                            .child("Dashboard")
                            .on_click(|_, _, cx| {
                                open_dashboard(cx, Module::Overview)
                            }),
                    ),
            )
            .children(config_warning(cx))
            .child(quickview::quick_view(self.sample.as_ref()))
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
    sample: Option<Sample>,
    connected: bool,
    view: Option<FleetView>,
    snapshot: Option<Arc<snapshot::Snapshot>>,
    popover: Option<WindowHandle<PopoverView>>,
    dashboard: Option<WindowHandle<DashboardView>>,
    processes: Vec<sampler::ProcRow>,
    launch_rows: Vec<LaunchRow>,
    config_path: Arc<ConfigPath>,
    config: ConfigRead,
    tx: Option<UnboundedSender<ShellEvent>>,
    #[cfg(target_os = "macos")]
    notifications: Option<notifications::Notifications>,
    #[cfg(target_os = "macos")]
    _item: Option<mac_status::Item>,
    #[cfg(target_os = "linux")]
    _tray: Option<linux_tray::Handle>,
}

impl Global for Shell {}

impl Shell {
    fn status_line(&self) -> String {
        match (&self.connected, &self.view) {
            (true, Some(view)) => view.status_line.clone(),
            _ => "Controller offline".to_string(),
        }
    }

    fn alert_text(&self) -> String {
        match (&self.connected, &self.view) {
            (true, Some(view)) => view.alert.clone(),
            _ => FleetView::offline_alert().to_string(),
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
struct MenuSections {
    agents: bool,
    processes: bool,
    services: bool,
}

impl From<&Sections> for MenuSections {
    fn from(sections: &Sections) -> Self {
        Self {
            agents: sections.agents,
            processes: sections.processes,
            services: sections.services,
        }
    }
}

fn config_warning(cx: &App) -> Option<impl IntoElement> {
    let error = cx.global::<Shell>().config.error.as_ref()?;
    Some(
        div()
            .flex()
            .flex_col()
            .items_start()
            .flex_none()
            .gap(px(4.0))
            .text_size(px(12.0))
            .text_color(gpui::rgb(0xffcc80))
            .child("Cannot load config.json; using defaults.")
            .child(error.clone())
            .child(
                div()
                    .id("edit-unreadable-config")
                    .border_1()
                    .border_color(gpui::rgb(0xffcc80))
                    .rounded(px(4.0))
                    .px(px(6.0))
                    .py(px(2.0))
                    .child("Edit Configuration")
                    .on_click(|_, _, cx| open_config_path(cx, true)),
            ),
    )
}

fn popover_opened() {
    std::thread::spawn(|| {
        let _ = controller::send_one_shot(&fleet_proto::RpcRequest::new(
            fleet_proto::RpcOp::MarkSeen,
        ));
        let _ = controller::send_one_shot(&fleet_proto::RpcRequest::new(
            fleet_proto::RpcOp::RefreshDevices,
        ));
    });
}

fn toggle_popover(cx: &mut App) {
    if let Some(handle) = cx.global::<Shell>().popover {
        let toggled = handle.update(cx, |_, window, _| {
            if window.is_window_active() {
                window.remove_window();
            } else {
                window.activate_window();
                popover_opened();
            }
        });
        if toggled.is_ok() {
            return;
        }
    }
    open_popover(cx);
}

fn open_popover(cx: &mut App) {
    popover_opened();
    let sample = cx.global::<Shell>().sample.clone();
    let status = cx.global::<Shell>().status_line();
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
        if let Ok(handle) = cx.open_window(options, |_, cx| cx.new(|_| PopoverView { sample: sample.clone(), status: status.clone() })) {
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
    if let Ok(handle) = cx.open_window(options, |_, cx| cx.new(|_| PopoverView { sample, status: status.clone() })) {
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
            ShellEvent::Sample(sample) => {
                if cx.update(|cx| apply_sample(sample, cx)).is_err() {
                    return;
                }
            }
            ShellEvent::Connection(connected) => {
                if cx.update(|cx| apply_connection(connected, cx)).is_err() {
                    return;
                }
            }
            ShellEvent::Snapshot(snapshot) => {
                if cx.update(|cx| apply_snapshot(snapshot, cx)).is_err() {
                    return;
                }
            }
            ShellEvent::Processes(rows) => {
                if cx.update(|cx| apply_processes(rows, cx)).is_err() {
                    return;
                }
            }
            ShellEvent::LaunchServices(rows) => {
                if cx.update(|cx| apply_launch_services(rows, cx)).is_err() {
                    return;
                }
            }
            ShellEvent::ShowModule(module) => {
                if cx.update(|cx| open_dashboard(cx, module)).is_err() {
                    return;
                }
            }
            #[cfg(target_os = "macos")]
            ShellEvent::DashboardHandoff(module) => {
                if cx.update(|cx| open_launched_dashboard(cx, module)).is_err() {
                    return;
                }
            }
            ShellEvent::Reconcile => {
                let _ = controller::send_one_shot(&fleet_proto::RpcRequest::new(
                    fleet_proto::RpcOp::Reconcile,
                ));
            }
            ShellEvent::ConfigLoaded(config) => {
                if cx.update(|cx| apply_config(config, cx)).is_err() {
                    return;
                }
            }
            ShellEvent::EditConfiguration | ShellEvent::RevealLogs => {
                let edit = matches!(event, ShellEvent::EditConfiguration);
                if cx.update(|cx| open_config_path(cx, edit)).is_err() {
                    return;
                }
            }
            #[cfg(target_os = "macos")]
            ShellEvent::ReplayWelcome => {
                if cx.update(welcome::replay).is_err() {
                    return;
                }
            }
            ShellEvent::OpenGuide => {
                if cx
                    .update(|cx| {
                        cx.open_url(
                            "https://github.com/janestreetshiller/fleet-console#readme",
                        )
                    })
                    .is_err()
                {
                    return;
                }
            }
            #[cfg(target_os = "macos")]
            ShellEvent::ShowCliSetup => {
                if cx.update(mac_launch::show_cli_setup).is_err() {
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

fn apply_sample(sample: Sample, cx: &mut App) {
    eprintln!("FleetConsole: meters {}", sample.meters.text());
    let meters = sample.meters;
    let shell = cx.global_mut::<Shell>();
    shell.meters = meters;
    shell.sample = Some(sample);
    push_shell_state(cx);
    push_dashboard(cx);
    if let Some(handle) = cx.global::<Shell>().popover {
        let sample = cx.global::<Shell>().sample.clone();
        let _ = handle.update(cx, |view, _, view_cx| {
            if view.sample.as_ref().map(|s| s.meters) != Some(meters) {
                view.sample = sample;
                view_cx.notify();
            }
        });
    }
}

fn apply_connection(connected: bool, cx: &mut App) {
    eprintln!("FleetConsole: controller connected={connected}");
    let shell = cx.global_mut::<Shell>();
    shell.connected = connected;
    if !connected {
        shell.view = None;
    }
    push_shell_state(cx);
    push_popover_status(cx);
    push_dashboard(cx);
}

fn open_config_path(cx: &App, edit: bool) {
    let paths = Arc::clone(&cx.global::<Shell>().config_path);
    std::thread::spawn(move || {
        let path = if edit { paths.file() } else { paths.logs() };
        let prepared = if edit {
            paths.ensure_exists()
        } else {
            std::fs::DirBuilder::new()
                .recursive(true)
                .mode(0o700)
                .create(path)
        };
        let mut command = std::process::Command::new(if cfg!(target_os = "macos") {
            "open"
        } else {
            "xdg-open"
        });
        if cfg!(target_os = "macos") && edit {
            command.arg("-t");
        }
        match prepared.and_then(|()| command.arg(path).status()) {
            Ok(status) if status.success() => {}
            Ok(status) => eprintln!("FleetConsole: cannot open {}: {status}", path.display()),
            Err(error) => eprintln!("FleetConsole: cannot open {}: {error}", path.display()),
        }
    });
}

fn apply_config(config: ConfigRead, cx: &mut App) {
    let shell = cx.global_mut::<Shell>();
    let previous_sections = MenuSections::from(&shell.config.config.sections);
    let sections = MenuSections::from(&config.config.sections);
    let error_changed = shell.config.error != config.error;
    shell.config = config;
    if sections != previous_sections {
        if sections.processes != previous_sections.processes
            || sections.services != previous_sections.services
        {
            set_app_menus(cx, sections);
        }
        #[cfg(target_os = "macos")]
        if let Some(item) = &cx.global::<Shell>()._item {
            item.set_sections(sections);
        }
        #[cfg(target_os = "linux")]
        if let Some(tray) = &cx.global::<Shell>()._tray {
            let _ = tray.update(move |tray: &mut linux_tray::FleetTray| {
                tray.sections = sections;
            });
        }
    }
    if error_changed {
        let shell = cx.global::<Shell>();
        let (popover, dashboard) = (shell.popover, shell.dashboard);
        if let Some(handle) = popover {
            let _ = handle.update(cx, |_, _, cx| cx.notify());
        }
        if let Some(handle) = dashboard {
            let _ = handle.update(cx, |_, _, cx| cx.notify());
        }
    }
}

#[derive(PartialEq, Eq)]
struct ConfigStamp {
    device: u64,
    inode: u64,
    size: u64,
    modified: (i64, i64),
    changed: (i64, i64),
}

fn config_stamp(path: &Path) -> Result<ConfigStamp, io::ErrorKind> {
    let metadata = path.metadata().map_err(|error| error.kind())?;
    Ok(ConfigStamp {
        device: metadata.dev(),
        inode: metadata.ino(),
        size: metadata.size(),
        modified: (metadata.mtime(), metadata.mtime_nsec()),
        changed: (metadata.ctime(), metadata.ctime_nsec()),
    })
}

fn spawn_process_sampler(
    paths: Arc<ConfigPath>,
    mut stamp: Result<ConfigStamp, io::ErrorKind>,
    mut interval: Duration,
    tx: UnboundedSender<ShellEvent>,
) {
    std::thread::spawn(move || {
        let mut system = sysinfo::System::new();
        system.refresh_processes(sysinfo::ProcessesToUpdate::All);
        let mut last_sample = Instant::now();
        let mut last_check = last_sample;
        while !tx.is_closed() {
            if last_check.elapsed() >= CONFIG_CHECK_INTERVAL {
                last_check = Instant::now();
                let current = config_stamp(paths.file());
                if current != stamp {
                    stamp = current;
                    let config = UiConfig::load(paths.file());
                    interval = config.config.process_sample;
                    if tx.unbounded_send(ShellEvent::ConfigLoaded(config)).is_err() {
                        return;
                    }
                }
            }
            if last_sample.elapsed() >= interval {
                let rows = sampler::collect_processes(&mut system);
                last_sample = Instant::now();
                if tx.unbounded_send(ShellEvent::Processes(rows)).is_err() {
                    return;
                }
            }
            std::thread::sleep(
                CONFIG_CHECK_INTERVAL
                    .saturating_sub(last_check.elapsed())
                    .min(interval.saturating_sub(last_sample.elapsed())),
            );
        }
    });
}

fn apply_processes(rows: Vec<sampler::ProcRow>, cx: &mut App) {
    cx.global_mut::<Shell>().processes = rows;
    push_dashboard(cx);
}

fn apply_launch_services(rows: Vec<LaunchRow>, cx: &mut App) {
    cx.global_mut::<Shell>().launch_rows = rows;
    push_dashboard(cx);
}

fn open_dashboard(cx: &mut App, module: Module) {
    cx.defer(move |cx| show_dashboard(cx, module));
}

fn open_launched_dashboard(cx: &mut App, module: Module) {
    #[cfg(target_os = "macos")]
    cx.activate(true);
    open_dashboard(cx, module);
}

fn show_dashboard(cx: &mut App, module: Module) {
    if let Some(handle) = cx.global::<Shell>().dashboard {
        let updated = handle.update(cx, |view, window, view_cx| {
            view.module = module;
            window.activate_window();
            view_cx.notify();
        });
        if updated.is_ok() {
            request_launch_services(cx);
            return;
        }
        cx.global_mut::<Shell>().dashboard = None;
    }
    let (connected, view, sample, processes, launch_rows, snapshot) = {
        let shell = cx.global::<Shell>();
        (
            shell.connected,
            shell.view.clone(),
            shell.sample.clone(),
            shell.processes.clone(),
            shell.launch_rows.clone(),
            shell.snapshot.clone(),
        )
    };
    let options = WindowOptions {
        window_bounds: Some(WindowBounds::Windowed(Bounds::centered(
            None,
            size(px(1100.0), px(700.0)),
            cx,
        ))),
        titlebar: Some(TitlebarOptions {
            title: Some("FleetConsole Dashboard".into()),
            appears_transparent: false,
            traffic_light_position: None,
        }),
        app_id: Some(BUNDLE_ID.into()),
        ..Default::default()
    };
    if let Ok(handle) = cx.open_window(options, |_, cx| {
        cx.new(|cx| {
            DashboardView::start_topology_clock(cx);
            DashboardView {
                module,
                connected,
                view,
                sample,
                processes,
                launch_rows,
                scroll: gpui::ScrollHandle::new(),
                snapshot,
                topology: None,
            }
        })
    }) {
        cx.global_mut::<Shell>().dashboard = Some(handle);
    }
    request_launch_services(cx);
}

fn request_launch_services(cx: &mut App) {
    let Some(tx) = cx.global::<Shell>().tx.clone() else {
        return;
    };
    std::thread::spawn(move || {
        let rows = dashboard::fetch_launch_services();
        let _ = tx.unbounded_send(ShellEvent::LaunchServices(rows));
    });
}

fn push_dashboard(cx: &mut App) {
    let Some(handle) = cx.global::<Shell>().dashboard else {
        return;
    };
    let _ = handle.update(cx, |dash, _, view_cx| {
        let shell = view_cx.global::<Shell>();
        dash.connected = shell.connected;
        dash.view = shell.view.clone();
        dash.sample = shell.sample.clone();
        dash.processes = shell.processes.clone();
        dash.launch_rows = shell.launch_rows.clone();
        dash.snapshot = shell.snapshot.clone();
        view_cx.notify();
    });
}

fn apply_snapshot(snapshot: snapshot::Snapshot, cx: &mut App) {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0);
    let view = FleetView::from_snapshot(&snapshot, now);
    eprintln!(
        "FleetConsole: fleet status '{}' alert '{}'",
        view.status_line, view.alert
    );
    let shell = cx.global_mut::<Shell>();
    #[cfg(target_os = "macos")]
    if let Some(notifications) = shell.notifications.as_mut() {
        notifications.update(&snapshot);
    }
    shell.connected = true;
    shell.view = Some(view);
    shell.snapshot = Some(Arc::new(snapshot));
    push_shell_state(cx);
    push_popover_status(cx);
    push_dashboard(cx);
}

fn push_shell_state(cx: &mut App) {
    let (meters, connected, view) = {
        let shell = cx.global::<Shell>();
        (shell.meters, shell.connected, shell.view.clone())
    };
    #[cfg(target_os = "macos")]
    if let Some(item) = &cx.global::<Shell>()._item {
        item.set_status(meters, connected, view.as_ref());
    }
    #[cfg(target_os = "linux")]
    if let Some(tray) = &cx.global::<Shell>()._tray {
        let alert = match (&connected, &view) {
            (true, Some(view)) => view.alert.clone(),
            _ => FleetView::offline_alert().to_string(),
        };
        let fleet_tooltip = match (&connected, &view) {
            (true, Some(view)) => Some(view.tooltip.clone()),
            _ => None,
        };
        let awaiting = match (&connected, &view) {
            (true, Some(view)) => view.awaiting_reply_count,
            _ => 0,
        };
        let _ = tray.update(|tray: &mut linux_tray::FleetTray| {
            tray.meters = meters;
            tray.alert = alert;
            tray.fleet_tooltip = fleet_tooltip;
            tray.awaiting = awaiting;
        });
    }
}

fn push_popover_status(cx: &mut App) {
    let status = cx.global::<Shell>().status_line();
    if let Some(handle) = cx.global::<Shell>().popover {
        let _ = handle.update(cx, |view, _, view_cx| {
            if view.status != status {
                view.status = status;
                view_cx.notify();
            }
        });
    }
}

const DASHBOARD_ROUTES: [(&str, Module); 6] = [
    ("overview", Module::Overview),
    ("processes", Module::Processes),
    ("storage", Module::Storage),
    ("services", Module::Services),
    ("events", Module::Events),
    ("launch", Module::LaunchServices),
];

fn dashboard_launch_module<'a>(
    args: impl IntoIterator<Item = &'a str>,
    dashboard_env: Option<&str>,
) -> Option<Module> {
    args.into_iter()
        .find_map(|arg| {
            if arg == "--dashboard" {
                return Some(Module::Overview);
            }
            let route = arg.strip_prefix("--dashboard=")?;
            DASHBOARD_ROUTES
                .iter()
                .find_map(|(name, module)| (*name == route).then_some(*module))
        })
        .or_else(|| (dashboard_env == Some("1")).then_some(Module::Overview))
}

fn set_app_menus(cx: &mut App, sections: MenuSections) {
    let mut view_items = vec![
        MenuItem::action("Open Dashboard", OpenDashboard),
        MenuItem::separator(),
        MenuItem::action("Overview", ShowOverview),
    ];
    if sections.processes {
        view_items.push(MenuItem::action("Processes", ShowProcesses));
    }
    view_items.push(MenuItem::action("Storage", ShowStorage));
    if sections.services {
        view_items.push(MenuItem::action("Services", ShowServices));
    }
    view_items.extend([
        MenuItem::action("Events", ShowEvents),
        MenuItem::action("Launch Services", ShowLaunchServices),
        MenuItem::separator(),
        MenuItem::action("Refresh", RefreshProbes),
    ]);
    let help_items = vec![
        MenuItem::action("FleetConsole Guide", OpenGuide),
        #[cfg(target_os = "macos")]
        MenuItem::action("fleetctl Setup…", ShowCliSetup),
    ];
    cx.set_menus(vec![
        Menu {
            name: "FleetConsole".into(),
            items: vec![
                #[cfg(target_os = "macos")]
                MenuItem::action("About FleetConsole", ShowAbout),
                #[cfg(target_os = "macos")]
                MenuItem::separator(),
                MenuItem::action("Edit Configuration", EditConfiguration),
                MenuItem::action("Reveal Logs", RevealLogs),
                MenuItem::separator(),
                #[cfg(target_os = "macos")]
                MenuItem::action("Hide FleetConsole", HideFleetConsole),
                #[cfg(target_os = "macos")]
                MenuItem::action("Hide Others", HideOtherApps),
                #[cfg(target_os = "macos")]
                MenuItem::separator(),
                MenuItem::action("Quit FleetConsole", Quit),
            ],
        },
        Menu {
            name: "View".into(),
            items: view_items,
        },
        Menu {
            name: "Help".into(),
            items: help_items,
        },
    ]);
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
            "FleetConsole — menubar (macOS) / tray (Linux) shell\n\nUsage: FleetConsole [--popover] [--dashboard[=module]] [--identity] [--version]\n  --popover   open the popover at launch (verification aid)\n  --dashboard open the Dashboard at launch, optionally on a module:\n              overview, processes, storage, services, events, launch\n  FLEETCONSOLE_DASHBOARD=1 also opens the Dashboard at launch\n"
        );
        #[cfg(target_os = "macos")]
        println!("  --review    open the Dashboard in review mode (no Dock icon)\n");
        return;
    }
    let open_popover_at_launch = args.iter().any(|a| a == "--popover");
    let dashboard_at_launch = dashboard_launch_module(
        args.iter().map(String::as_str),
        std::env::var("FLEETCONSOLE_DASHBOARD").as_deref().ok(),
    );

    let (tx, rx) = unbounded::<ShellEvent>();
    #[cfg(target_os = "macos")]
    let launch = mac_launch::Launch::new(&args);
    #[cfg(target_os = "macos")]
    let _dashboard_observer = launch.observe_dashboard(&tx);
    #[cfg(target_os = "macos")]
    if launch.handoff(dashboard_at_launch) {
        return;
    }

    Application::new().run(move |cx: &mut App| {
        #[cfg(target_os = "macos")]
        let dashboard_at_launch = {
            launch.apply_activation_policy();
            if launch.handoff(dashboard_at_launch) {
                cx.quit();
                return;
            }
            launch.startup_dashboard(dashboard_at_launch)
        };
        #[cfg(target_os = "macos")]
        let onboarding = launch.enables_onboarding();

        let config_path = Arc::new(ConfigPath::detect());
        if let Err(error) = config_path.ensure_exists() {
            eprintln!(
                "FleetConsole: could not initialize {}: {error}",
                config_path.file().display()
            );
        }
        let stamp = config_stamp(config_path.file());
        let config = UiConfig::load(config_path.file());
        let interval = config.config.process_sample;
        let sections = MenuSections::from(&config.config.sections);

        cx.bind_keys([
            #[cfg(target_os = "macos")]
            gpui::KeyBinding::new("cmd-h", HideFleetConsole, None),
            #[cfg(target_os = "macos")]
            gpui::KeyBinding::new("alt-cmd-h", HideOtherApps, None),
            gpui::KeyBinding::new("cmd-q", Quit, None),
            gpui::KeyBinding::new("ctrl-q", Quit, None),
            gpui::KeyBinding::new("cmd-0", OpenDashboard, None),
            gpui::KeyBinding::new("cmd-1", ShowOverview, None),
            gpui::KeyBinding::new("cmd-2", ShowProcesses, None),
            gpui::KeyBinding::new("cmd-3", ShowStorage, None),
            gpui::KeyBinding::new("cmd-4", ShowServices, None),
            gpui::KeyBinding::new("cmd-5", ShowEvents, None),
            gpui::KeyBinding::new("cmd-6", ShowLaunchServices, None),
            gpui::KeyBinding::new("cmd-r", RefreshProbes, None),
        ]);
        cx.on_action(|_: &Quit, cx: &mut App| cx.quit());
        #[cfg(target_os = "macos")]
        {
            cx.on_action(|_: &ShowAbout, cx: &mut App| mac_launch::show_about(cx));
            cx.on_action(|_: &HideFleetConsole, cx: &mut App| cx.hide());
            cx.on_action(|_: &HideOtherApps, cx: &mut App| cx.hide_other_apps());
        }
        cx.on_action(|_: &OpenDashboard, cx: &mut App| {
            open_dashboard(cx, Module::Overview)
        });
        cx.on_action(|_: &ShowOverview, cx: &mut App| {
            open_dashboard(cx, Module::Overview)
        });
        cx.on_action(|_: &ShowProcesses, cx: &mut App| {
            open_dashboard(cx, Module::Processes)
        });
        cx.on_action(|_: &ShowStorage, cx: &mut App| {
            open_dashboard(cx, Module::Storage)
        });
        cx.on_action(|_: &ShowServices, cx: &mut App| {
            open_dashboard(cx, Module::Services)
        });
        cx.on_action(|_: &ShowEvents, cx: &mut App| {
            open_dashboard(cx, Module::Events)
        });
        cx.on_action(|_: &ShowLaunchServices, cx: &mut App| {
            open_dashboard(cx, Module::LaunchServices)
        });
        cx.on_action(|_: &RefreshProbes, cx: &mut App| {
            let _ = controller::send_one_shot(&fleet_proto::RpcRequest::new(
                fleet_proto::RpcOp::RefreshDevices,
            ));
            request_launch_services(cx);
        });
        cx.on_action(|_: &OpenGuide, cx: &mut App| {
            cx.open_url("https://github.com/janestreetshiller/fleet-console#readme");
        });
        #[cfg(target_os = "macos")]
        cx.on_action(|_: &ShowCliSetup, cx: &mut App| mac_launch::show_cli_setup(cx));
        cx.on_action(|_: &EditConfiguration, cx: &mut App| open_config_path(cx, true));
        cx.on_action(|_: &RevealLogs, cx: &mut App| open_config_path(cx, false));
        set_app_menus(cx, sections);

        #[cfg(target_os = "macos")]
        let item = match mac_status::Item::install(tx.clone(), sections) {
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
        let tray = match linux_tray::install(tx.clone(), sections) {
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
            sample: None,
            connected: false,
            view: None,
            snapshot: None,
            popover: None,
            dashboard: None,
            processes: Vec::new(),
            launch_rows: Vec::new(),
            config_path: Arc::clone(&config_path),
            config,
            tx: Some(tx.clone()),
            #[cfg(target_os = "macos")]
            notifications: onboarding.then(notifications::Notifications::new),
            #[cfg(target_os = "macos")]
            _item: item,
            #[cfg(target_os = "linux")]
            _tray: tray,
        });
        #[cfg(target_os = "macos")]
        {
            welcome::init(cx, onboarding, |cx| open_dashboard(cx, Module::Overview));
            launch.register_controller();
            welcome::show_if_due(cx);
        }

        cx.spawn(async move |cx: &mut gpui::AsyncApp| forward_events(rx, cx).await)
            .detach();

        controller::spawn(tx.clone());

        spawn_process_sampler(config_path, stamp, interval, tx.clone());

        std::thread::spawn(move || {
            let mut sampler = sampler::Sampler::new();
            loop {
                let sample = sampler.sample();
                if tx.unbounded_send(ShellEvent::Sample(sample)).is_err() {
                    return;
                }
                std::thread::sleep(sampler::SAMPLE_INTERVAL);
            }
        });

        if open_popover_at_launch {
            toggle_popover(cx);
        }
        if let Some(module) = dashboard_at_launch {
            open_launched_dashboard(cx, module);
        }
    });
}

#[cfg(target_os = "macos")]
mod mac_status {
    use super::{
        MenuSections, Meters, ShellEvent, METER_TEXT, STATUS_ITEM_AUTOSAVE_NAME, TOOLTIP_DISCONNECTED,
    };
    use cocoa::base::{id, nil};
    use cocoa::foundation::{NSPoint, NSRect, NSString};
    use futures::channel::mpsc::UnboundedSender;
    use objc::declare::ClassDecl;
    use objc::runtime::{Class, Object, Sel};
    use objc::{class, msg_send, sel, sel_impl};
    use std::sync::{Mutex, OnceLock};

    const TARGET_CLASS: &str = "FleetConsoleProdStatusTarget";
    const VARIABLE_LENGTH: f64 = -1.0;
    const EVENT_RIGHT_MOUSE_UP: u64 = 4;

    static EVENTS: Mutex<Option<UnboundedSender<ShellEvent>>> = Mutex::new(None);
    static MENU_SECTIONS: Mutex<Option<MenuSections>> = Mutex::new(None);

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
                show_context_menu(_sender);
            } else {
                send(ShellEvent::TogglePopover);
            }
        }
    }

    extern "C" fn quit_clicked(_this: &Object, _cmd: Sel, _sender: id) {
        send(ShellEvent::Quit);
    }

    static CURRENT_AWAITING: Mutex<i64> = Mutex::new(0);

    fn current_awaiting() -> i64 {
        CURRENT_AWAITING.lock().map(|guard| *guard).unwrap_or(0)
    }

    extern "C" fn menu_clicked(_this: &Object, _cmd: Sel, sender: id) {
        let tag: i64 = unsafe { msg_send![sender, tag] };
        let event = match tag {
            1 => ShellEvent::TogglePopover,
            2 | 3 | 4 | 5 => ShellEvent::ShowModule(super::Module::Overview),
            6 => ShellEvent::ShowModule(super::Module::Processes),
            7 => ShellEvent::ShowModule(super::Module::Storage),
            8 => ShellEvent::ShowModule(super::Module::Services),
            9 => ShellEvent::ShowModule(super::Module::Events),
            10 => ShellEvent::ShowModule(super::Module::LaunchServices),
            11 => ShellEvent::Reconcile,
            12 => ShellEvent::RevealLogs,
            13 => ShellEvent::OpenGuide,
            14 => ShellEvent::EditConfiguration,
            15 => ShellEvent::ReplayWelcome,
            16 => ShellEvent::ShowCliSetup,
            _ => return,
        };
        send(event);
    }

    unsafe fn add_menu_item(
        menu: id,
        target: id,
        title: &str,
        action: Sel,
        tag: i64,
        key: &str,
        enabled: bool,
    ) {
        unsafe {
            let item: id = msg_send![class!(NSMenuItem), alloc];
            let item: id = msg_send![
                item,
                initWithTitle: ns_string(title)
                action: action
                keyEquivalent: ns_string(key)
            ];
            let _: () = msg_send![item, setTarget: target];
            let _: () = msg_send![item, setTag: tag];
            let _: () = msg_send![item, setEnabled: enabled];
            let _: () = msg_send![menu, addItem: item];
        }
    }

    unsafe fn add_separator(menu: id) {
        unsafe {
            let separator: id = msg_send![class!(NSMenuItem), separatorItem];
            let _: () = msg_send![menu, addItem: separator];
        }
    }

    unsafe fn show_context_menu(sender: id) {
        unsafe {
            let Some(sections) = MENU_SECTIONS.lock().ok().and_then(|guard| *guard) else {
                return;
            };
            let menu: id = msg_send![class!(NSMenu), alloc];
            let menu: id = msg_send![menu, init];
            let target: id = msg_send![target_class(), new];
            let action = sel!(fleetMenuClicked:);
            add_menu_item(menu, target, "Quick View", action, 1, "", true);
            add_menu_item(menu, target, "Needs Attention", action, 2, "", true);
            if sections.agents {
                let awaiting = current_awaiting();
                let agents_title = if awaiting > 0 {
                    format!("Agents — {awaiting} awaiting your answer")
                } else {
                    "Agents".to_string()
                };
                add_menu_item(menu, target, &agents_title, action, 3, "", true);
            }
            add_menu_item(menu, target, "Open Dashboard", action, 4, "0", true);
            add_separator(menu);
            add_menu_item(menu, target, "Monitor This Mac", action, 0, "", false);
            add_menu_item(menu, target, "Overview", action, 5, "", true);
            if sections.processes {
                add_menu_item(menu, target, "Processes", action, 6, "", true);
            }
            add_menu_item(menu, target, "Storage", action, 7, "", true);
            add_separator(menu);
            add_menu_item(menu, target, "Background Work", action, 0, "", false);
            if sections.services {
                add_menu_item(menu, target, "Services", action, 8, "", true);
            }
            add_menu_item(menu, target, "Events", action, 9, "", true);
            add_menu_item(menu, target, "Launch Services", action, 10, "", true);
            add_separator(menu);
            add_menu_item(menu, target, "Find Background Processes", action, 11, "", true);
            add_menu_item(menu, target, "Edit Configuration", action, 14, "", true);
            add_menu_item(menu, target, "Reveal Logs in Finder", action, 12, "", true);
            add_menu_item(menu, target, "Replay Welcome", action, 15, "", true);
            add_separator(menu);
            add_menu_item(menu, target, "Help", action, 0, "", false);
            add_menu_item(menu, target, "FleetConsole Guide", action, 13, "", true);
            add_menu_item(menu, target, "fleetctl Setup…", action, 16, "", true);
            add_separator(menu);
            add_menu_item(menu, target, "Quit FleetConsole", sel!(fleetQuitClicked:), 0, "q", true);
            let _: () = msg_send![menu, popUpMenuPositioningItem: nil atLocation: NSPoint::new(0.0, 0.0) inView: sender];
            let _: () = msg_send![menu, release];
        }
    }

    unsafe fn set_attributed_title(
        button: id,
        title: &str,
        alert: &str,
        tint: super::snapshot::Tint,
    ) {
        unsafe {
            let attributed: id = msg_send![class!(NSMutableAttributedString), alloc];
            let attributed: id = msg_send![attributed, initWithString: ns_string(title)];
            if attributed == nil {
                let _: () = msg_send![button, setTitle: ns_string(title)];
                return;
            }
            if tint != super::snapshot::Tint::None && !alert.is_empty() {
                let color: id = match tint {
                    super::snapshot::Tint::Bad => {
                        msg_send![class!(NSColor), systemRedColor]
                    }
                    _ => msg_send![class!(NSColor), systemOrangeColor],
                };
                if color != nil {
                    let total = title.encode_utf16().count() as u64;
                    let alert_len = alert.encode_utf16().count() as u64;
                    let range = cocoa::foundation::NSRange::new(
                        total.saturating_sub(alert_len),
                        alert_len,
                    );
                    let _: () = msg_send![
                        attributed,
                        addAttribute: ns_string("NSForegroundColor")
                        value: color
                        range: range
                    ];
                }
            }
            let _: () = msg_send![button, setAttributedTitle: attributed];
            let _: () = msg_send![attributed, release];
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
                decl.add_method(
                    sel!(fleetMenuClicked:),
                    menu_clicked as extern "C" fn(&Object, Sel, id),
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

    pub struct Item {
        item: id,
        _target: id,
    }

    unsafe impl Send for Item {}
    unsafe impl Sync for Item {}

    impl Item {
        pub(super) fn install(
            tx: UnboundedSender<ShellEvent>,
            sections: MenuSections,
        ) -> Result<Self, String> {
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
                let installed = Self {
                    item,
                    _target: target,
                };
                installed.set_sections(sections);
                Ok(installed)
            }
        }

        pub(super) fn set_sections(&self, sections: MenuSections) {
            if let Ok(mut guard) = MENU_SECTIONS.lock() {
                *guard = Some(sections);
            }
        }

        pub fn set_status(
            &self,
            meters: Meters,
            connected: bool,
            view: Option<&super::FleetView>,
        ) {
            if let Ok(mut guard) = CURRENT_AWAITING.lock() {
                *guard = match (connected, view) {
                    (true, Some(view)) => view.awaiting_reply_count,
                    _ => 0,
                };
            }
            unsafe {
                let button: id = msg_send![self.item, button];
                if button == nil {
                    return;
                }
                let (alert, tint, tooltip) = match (connected, view) {
                    (true, Some(view)) => (
                        view.alert.clone(),
                        view.tint,
                        view.tooltip.clone(),
                    ),
                    _ => (
                        super::FleetView::offline_alert().to_string(),
                        super::snapshot::Tint::Bad,
                        TOOLTIP_DISCONNECTED.to_string(),
                    ),
                };
                let mut title = meters.text();
                if !alert.is_empty() {
                    title.push_str("  ");
                    title.push_str(&alert);
                }
                set_attributed_title(button, &title, &alert, tint);
                let _: () = msg_send![button, setToolTip: ns_string(&tooltip)];
                let mut accessibility = format!(
                    "FleetConsole fleet — {}. CPU {}, RAM {}, DISK {}",
                    tooltip.replace('\n', ", "),
                    super::sampler::value_text(meters.cpu),
                    super::sampler::value_text(meters.ram),
                    super::sampler::value_text(meters.disk),
                );
                if !alert.is_empty() {
                    accessibility.push(' ');
                    accessibility.push_str(&alert);
                }
                let _: () = msg_send![
                    button,
                    setAccessibilityLabel: ns_string(&accessibility)
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
    use super::{MenuSections, Meters, ShellEvent, BUNDLE_ID, TOOLTIP_DISCONNECTED};
    use futures::channel::mpsc::UnboundedSender;
    use ksni::menu::{MenuItem, StandardItem};
    use ksni::{Icon, ToolTip, Tray};

    pub type Handle = ksni::blocking::Handle<FleetTray>;

    pub struct FleetTray {
        tx: UnboundedSender<ShellEvent>,
        pub meters: Meters,
        pub alert: String,
        pub fleet_tooltip: Option<String>,
        pub awaiting: i64,
        pub(super) sections: MenuSections,
    }

    fn entry(label: String, event: ShellEvent) -> MenuItem<FleetTray> {
        StandardItem {
            label,
            activate: Box::new(move |tray: &mut FleetTray| {
                let _ = tray.tx.unbounded_send(event.clone());
            }),
            ..Default::default()
        }
        .into()
    }

    fn header_item(label: &str) -> MenuItem<FleetTray> {
        StandardItem {
            label: label.into(),
            enabled: false,
            ..Default::default()
        }
        .into()
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
            match &self.fleet_tooltip {
                Some(tooltip) => ToolTip {
                    title: "FleetConsole".into(),
                    description: tooltip.clone(),
                    icon_name: String::new(),
                    icon_pixmap: Vec::new(),
                },
                None => ToolTip {
                    title: TOOLTIP_DISCONNECTED.into(),
                    description: self.meters.text(),
                    icon_name: String::new(),
                    icon_pixmap: Vec::new(),
                },
            }
        }
        fn activate(&mut self, _x: i32, _y: i32) {
            let _ = self.tx.unbounded_send(ShellEvent::TogglePopover);
        }
        fn menu(&self) -> Vec<MenuItem<Self>> {
            let meters_label = if self.alert.is_empty() {
                self.meters.text()
            } else {
                format!("{}  {}", self.meters.text(), self.alert)
            };
            use super::Module;
            let mut menu = Vec::with_capacity(24);
            menu.extend([
                StandardItem {
                    label: meters_label,
                    enabled: false,
                    ..Default::default()
                }
                .into(),
                entry("Quick View".into(), ShellEvent::TogglePopover),
                entry(
                    "Needs Attention".into(),
                    ShellEvent::ShowModule(Module::Overview),
                ),
            ]);
            if self.sections.agents {
                let label = if self.awaiting > 0 {
                    format!("Agents — {} awaiting your answer", self.awaiting)
                } else {
                    "Agents".to_string()
                };
                menu.push(entry(label, ShellEvent::ShowModule(Module::Overview)));
            }
            menu.extend([
                entry(
                    "Open Dashboard".into(),
                    ShellEvent::ShowModule(Module::Overview),
                ),
                MenuItem::Separator,
                header_item("Monitor This Mac"),
                entry(
                    "Overview".into(),
                    ShellEvent::ShowModule(Module::Overview),
                ),
            ]);
            if self.sections.processes {
                menu.push(entry(
                    "Processes".into(),
                    ShellEvent::ShowModule(Module::Processes),
                ));
            }
            menu.extend([
                entry(
                    "Storage".into(),
                    ShellEvent::ShowModule(Module::Storage),
                ),
                MenuItem::Separator,
                header_item("Background Work"),
            ]);
            if self.sections.services {
                menu.push(entry(
                    "Services".into(),
                    ShellEvent::ShowModule(Module::Services),
                ));
            }
            menu.extend([
                entry("Events".into(), ShellEvent::ShowModule(Module::Events)),
                entry(
                    "Launch Services".into(),
                    ShellEvent::ShowModule(Module::LaunchServices),
                ),
                MenuItem::Separator,
                entry("Find Background Processes".into(), ShellEvent::Reconcile),
                entry("Edit Configuration".into(), ShellEvent::EditConfiguration),
                entry("Reveal Logs".into(), ShellEvent::RevealLogs),
                MenuItem::Separator,
                header_item("Help"),
                entry("FleetConsole Guide".into(), ShellEvent::OpenGuide),
                MenuItem::Separator,
                entry("Quit FleetConsole".into(), ShellEvent::Quit),
            ]);
            menu
        }
    }

    pub(super) fn install(
        tx: UnboundedSender<ShellEvent>,
        sections: MenuSections,
    ) -> Result<Handle, String> {
        use ksni::blocking::TrayMethods;
        FleetTray {
            tx,
            meters: Meters::default(),
            alert: String::new(),
            fleet_tooltip: None,
            awaiting: 0,
            sections,
        }
        .spawn()
            .map_err(|error| format!("StatusNotifierItem spawn failed: {error}"))
    }
}

#[cfg(test)]
mod tests {
    use super::{dashboard_launch_module, Module};

    #[test]
    fn dashboard_launch_accepts_each_supported_route() {
        for (arg, module) in [
            ("--dashboard", Module::Overview),
            ("--dashboard=overview", Module::Overview),
            ("--dashboard=processes", Module::Processes),
            ("--dashboard=storage", Module::Storage),
            ("--dashboard=services", Module::Services),
            ("--dashboard=events", Module::Events),
            ("--dashboard=launch", Module::LaunchServices),
        ] {
            assert_eq!(dashboard_launch_module([arg], None), Some(module));
        }
    }

    #[test]
    fn invalid_module_does_not_select_a_route() {
        assert_eq!(dashboard_launch_module(["--dashboard=unknown"], None), None);
        assert_eq!(dashboard_launch_module(["--dashboard="], None), None);
        assert_eq!(
            dashboard_launch_module(["--dashboard=unknown", "--dashboard=events"], None),
            Some(Module::Events),
        );
    }

    #[test]
    fn dashboard_environment_opens_overview_unless_a_route_is_explicit() {
        assert_eq!(dashboard_launch_module([], None), None);
        for value in ["", "0", "true", "01"] {
            assert_eq!(dashboard_launch_module([], Some(value)), None);
        }
        assert_eq!(dashboard_launch_module([], Some("1")), Some(Module::Overview));
        assert_eq!(
            dashboard_launch_module(["--dashboard=unknown"], Some("1")),
            Some(Module::Overview),
        );
        assert_eq!(
            dashboard_launch_module(["--dashboard=services"], Some("1")),
            Some(Module::Services),
        );
    }
}
