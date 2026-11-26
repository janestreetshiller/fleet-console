use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use gpui::{
    div, px, rgb, Context, InteractiveElement, IntoElement, ParentElement, Render, ScrollHandle,
    StatefulInteractiveElement, Styled, Window,
};

use crate::quickview::fmt_bytes;
use crate::sampler::{ProcRow, Sample};
use crate::snapshot::{FleetTopology, FleetView, Snapshot, TopologyNodeKind};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Module {
    Overview,
    Processes,
    Storage,
    Services,
    Events,
    LaunchServices,
}

impl Module {
    pub fn all() -> [Module; 6] {
        [
            Module::Overview,
            Module::Processes,
            Module::Storage,
            Module::Services,
            Module::Events,
            Module::LaunchServices,
        ]
    }

    pub fn nav_label(self) -> &'static str {
        match self {
            Module::Overview => "Overview",
            Module::Processes => "Processes",
            Module::Storage => "Storage",
            Module::Services => "Services",
            Module::Events => "Events",
            Module::LaunchServices => "Launch Services",
        }
    }

    pub fn title(self) -> &'static str {
        match self {
            Module::Overview => "Agent awareness",
            Module::Processes => "Processes",
            Module::Storage => "Storage",
            Module::Services => "Operations",
            Module::Events => "Events",
            Module::LaunchServices => "Plists",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct LaunchRow {
    pub label: String,
    pub pid: Option<i64>,
    pub status: String,
}

pub fn fetch_launch_services() -> Vec<LaunchRow> {
    #[cfg(target_os = "macos")]
    {
        let output = std::process::Command::new("launchctl")
            .arg("list")
            .output();
        let Ok(output) = output else {
            return Vec::new();
        };
        let text = String::from_utf8_lossy(&output.stdout);
        let mut rows: Vec<LaunchRow> = text
            .lines()
            .skip(1)
            .filter_map(|line| {
                let mut parts = line.splitn(3, '\t');
                let pid = parts.next()?.trim();
                let status = parts.next()?.trim();
                let label = parts.next()?.trim();
                if label.is_empty() {
                    return None;
                }
                Some(LaunchRow {
                    label: label.to_string(),
                    pid: pid.parse::<i64>().ok(),
                    status: status.to_string(),
                })
            })
            .collect();
        rows.sort_by(|a, b| a.label.cmp(&b.label));
        rows.truncate(300);
        rows
    }
    #[cfg(not(target_os = "macos"))]
    {
        let output = std::process::Command::new("systemctl")
            .args([
                "--user",
                "list-units",
                "--type=service",
                "--all",
                "--no-legend",
                "--no-pager",
            ])
            .output();
        let Ok(output) = output else {
            return Vec::new();
        };
        let text = String::from_utf8_lossy(&output.stdout);
        let mut rows: Vec<LaunchRow> = text
            .lines()
            .filter_map(|line| {
                let line = line.trim_start_matches(['●', ' ']);
                let mut parts = line.split_whitespace();
                let unit = parts.next()?;
                let _load = parts.next()?;
                let active = parts.next().unwrap_or("");
                let sub = parts.next().unwrap_or("");
                Some(LaunchRow {
                    label: unit.trim_end_matches(".service").to_string(),
                    pid: None,
                    status: format!("{active} · {sub}"),
                })
            })
            .collect();
        rows.sort_by(|a, b| a.label.cmp(&b.label));
        rows.truncate(300);
        rows
    }
}

pub struct DashboardView {
    pub module: Module,
    pub connected: bool,
    pub view: Option<FleetView>,
    pub sample: Option<Sample>,
    pub processes: Vec<ProcRow>,
    pub launch_rows: Vec<LaunchRow>,
    pub scroll: ScrollHandle,
    pub(crate) snapshot: Option<Arc<Snapshot>>,
    pub(crate) topology: Option<TopologyCache>,
}

pub(crate) struct TopologyCache {
    source: Arc<Snapshot>,
    live: bool,
    projection: FleetTopology,
}

fn now_seconds() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0.0, |age| age.as_secs_f64())
}

fn fmt_cpu(pct: Option<f64>) -> String {
    match pct {
        Some(pct) => format!("{pct:.1}%"),
        None => "—".to_string(),
    }
}

fn fmt_mem(mb: Option<f64>) -> String {
    match mb {
        Some(mb) if mb >= 1024.0 => format!("{:.1} GB", mb / 1024.0),
        Some(mb) => format!("{mb:.0} MB"),
        None => "—".to_string(),
    }
}

fn header(text: &str) -> impl IntoElement {
    div()
        .text_size(px(17.0))
        .text_color(rgb(0xFFFFFF))
        .child(text.to_string())
}

fn cell(text: String, width: f32, color: u32) -> impl IntoElement {
    div()
        .w(px(width))
        .flex_none()
        .overflow_hidden()
        .text_size(px(12.0))
        .text_color(rgb(color))
        .child(text)
}

impl DashboardView {
    pub(crate) fn start_topology_clock(cx: &mut Context<Self>) {
        let executor = cx.background_executor().clone();
        cx.spawn(async move |this, cx| {
            loop {
                executor.timer(Duration::from_secs(1)).await;
                if this.update(cx, |view, cx| {
                    if view.module == Module::Overview
                        && view.topology.as_ref().and_then(|cache| cache.projection.valid_until)
                            .is_some_and(|until| now_seconds() > until)
                    {
                        cx.notify();
                    }
                }).is_err() {
                    return;
                }
            }
        }).detach();
    }

    fn refresh_topology(&mut self) {
        let Some(source) = &self.snapshot else { return; };
        let live = self.connected && self.view.is_some();
        let now = now_seconds();
        if self.topology.as_ref().is_some_and(|cache| {
            Arc::ptr_eq(&cache.source, source) && cache.live == live
                && cache.projection.valid_until.is_none_or(|until| now <= until)
        }) {
            return;
        }
        self.topology = Some(TopologyCache {
            source: source.clone(),
            live,
            projection: FleetTopology::from_snapshot(source, None, now, live),
        });
    }

    fn relationships(topology: &FleetTopology) -> gpui::Div {
        let mut body = div().flex().flex_col().gap(px(8.0)).pt(px(10.0));
        if topology.is_stale {
            body = body.child("Retained controller observations; live evidence is unavailable.");
        }
        for (kind, label) in [
            (TopologyNodeKind::Owner, "Recorded owners"),
            (TopologyNodeKind::Service, "Registered services"),
            (TopologyNodeKind::Listener, "Observed group listeners"),
            (TopologyNodeKind::Session, "Detected sessions · ownership unlinked"),
        ] {
            let mut rows = topology.nodes.iter().filter(|node| node.kind == kind).peekable();
            if rows.peek().is_none() {
                continue;
            }
            body = body.child(header(label));
            for node in rows {
                let title = match (kind, &node.owner, &node.service_id) {
                    (TopologyNodeKind::Service, Some(owner), _) => format!("{} · registry owner: {owner}", node.title),
                    (TopologyNodeKind::Listener, _, Some(id)) => format!("{} · service: {id}", node.title),
                    _ => node.title.clone(),
                };
                let metrics = matches!(kind, TopologyNodeKind::Service | TopologyNodeKind::Session)
                    .then(|| format!("CPU {} · Memory {}", fmt_cpu(node.cpu_pct), fmt_mem(node.mem_mb)));
                body = body.child(
                    div().flex().flex_col().gap(px(2.0)).text_size(px(13.0))
                        .child(title)
                        .children(metrics.map(|metrics| div().text_size(px(12.0)).child(metrics)))
                        .child(div().text_size(px(12.0)).text_color(rgb(0x8E8E93)).child(node.detail.clone())),
                );
            }
        }
        body
    }

    fn overview(&self) -> impl IntoElement {
        let mut body = div().flex().flex_col().gap(px(10.0));
        match (&self.view, self.connected) {
            (Some(view), true) => {
                body = body
                    .child(
                        div()
                            .text_size(px(20.0))
                            .child(view.status_line.clone()),
                    )
                    .child(
                        div()
                            .text_size(px(12.0))
                            .text_color(rgb(0x8E8E93))
                            .child(format!(
                                "{} running · {} critical · {} warning · {} awaiting your answer",
                                view.running_count,
                                view.critical_count,
                                view.warning_count,
                                view.awaiting_reply_count
                            )),
                    );
                for profile in &view.profiles {
                    let mut line = format!("{} — {}", profile.id, profile.headline);
                    if profile.awaiting_reply > 0 {
                        line +=
                            &format!(" — {} awaiting your answer", profile.awaiting_reply);
                    }
                    body = body.child(div().text_size(px(13.0)).child(line));
                }
            }
            _ => {
                body = body.child(
                    div()
                        .text_size(px(20.0))
                        .child("Controller offline"),
                );
            }
        }
        if let Some(topology) = &self.topology {
            body = body.child(Self::relationships(&topology.projection));
        }
        if let Some(sample) = &self.sample {
            body = body.child(
                div()
                    .pt(px(8.0))
                    .text_size(px(12.0))
                    .text_color(rgb(0x8E8E93))
                    .child(format!(
                        "This machine — CPU {} · RAM {} · DISK {}",
                        crate::sampler::value_text(sample.meters.cpu),
                        crate::sampler::value_text(sample.meters.ram),
                        crate::sampler::value_text(sample.meters.disk),
                    )),
            );
        }
        body
    }

    fn processes(&self) -> impl IntoElement {
        let mut body = div().flex().flex_col().gap(px(4.0));
        body = body.child(
            div()
                .flex()
                .flex_row()
                .child(cell("PID".into(), 70.0, 0x8E8E93))
                .child(cell("Name".into(), 260.0, 0x8E8E93))
                .child(cell("CPU".into(), 80.0, 0x8E8E93))
                .child(cell("Memory".into(), 110.0, 0x8E8E93)),
        );
        if self.processes.is_empty() {
            body = body.child(div().text_size(px(12.0)).child("No process sample yet"));
        }
        for process in &self.processes {
            body = body.child(
                div()
                    .flex()
                    .flex_row()
                    .child(cell(process.pid.to_string(), 70.0, 0xFFFFFF))
                    .child(cell(process.name.clone(), 260.0, 0xFFFFFF))
                    .child(cell(format!("{:.1}%", process.cpu_pct), 80.0, 0xFFFFFF))
                    .child(cell(fmt_bytes(process.mem_bytes), 110.0, 0xFFFFFF)),
            );
        }
        body
    }

    fn storage(&self) -> impl IntoElement {
        let mut body = div().flex().flex_col().gap(px(12.0));
        match &self.sample {
            None => {
                body = body.child(div().text_size(px(12.0)).child("No storage sample yet"));
            }
            Some(sample) => {
                for disk in &sample.disks {
                    let share = if disk.total > 0 {
                        (disk.total - disk.available) as f64 / disk.total as f64
                    } else {
                        0.0
                    };
                    body = body.child(
                        div()
                            .flex()
                            .flex_col()
                            .gap(px(4.0))
                            .child(
                                div()
                                    .text_size(px(13.0))
                                    .child(format!(
                                        "{} — {}",
                                        if disk.name.is_empty() {
                                            disk.mount.clone()
                                        } else {
                                            disk.name.clone()
                                        },
                                        disk.mount
                                    )),
                            )
                            .child(
                                div()
                                    .relative()
                                    .w(px(420.0))
                                    .h(px(8.0))
                                    .rounded(px(3.0))
                                    .bg(rgb(0x3A3A3C))
                                    .child(
                                        div()
                                            .absolute()
                                            .left_0()
                                            .top_0()
                                            .h_full()
                                            .w(gpui::relative(share as f32))
                                            .rounded(px(3.0))
                                            .bg(rgb(0xF17B33)),
                                    ),
                            )
                            .child(
                                div()
                                    .text_size(px(12.0))
                                    .text_color(rgb(0x8E8E93))
                                    .child(format!(
                                        "{} available of {}",
                                        fmt_bytes(disk.available),
                                        fmt_bytes(disk.total)
                                    )),
                            ),
                    );
                }
            }
        }
        body
    }

    fn services(&self) -> impl IntoElement {
        let mut body = div().flex().flex_col().gap(px(4.0));
        body = body.child(
            div()
                .flex()
                .flex_row()
                .child(cell("Service".into(), 220.0, 0x8E8E93))
                .child(cell("State".into(), 170.0, 0x8E8E93))
                .child(cell("Owner".into(), 110.0, 0x8E8E93))
                .child(cell("Ports".into(), 110.0, 0x8E8E93))
                .child(cell("CPU".into(), 70.0, 0x8E8E93))
                .child(cell("Memory".into(), 90.0, 0x8E8E93))
                .child(cell("Restarts".into(), 70.0, 0x8E8E93)),
        );
        match &self.view {
            Some(view) if !view.service_rows.is_empty() => {
                for service in &view.service_rows {
                    body = body.child(
                        div()
                            .flex()
                            .flex_row()
                            .child(cell(service.id.clone(), 220.0, 0xFFFFFF))
                            .child(cell(service.state_label.clone(), 170.0, 0xFFFFFF))
                            .child(cell(service.owner.clone(), 110.0, 0xFFFFFF))
                            .child(cell(service.ports.clone(), 110.0, 0xFFFFFF))
                            .child(cell(fmt_cpu(service.cpu_pct), 70.0, 0xFFFFFF))
                            .child(cell(fmt_mem(service.mem_mb), 90.0, 0xFFFFFF))
                            .child(cell(service.restart_count.to_string(), 70.0, 0xFFFFFF)),
                    );
                    if !service.purpose.is_empty() {
                        body = body.child(
                            div()
                                .pl(px(220.0))
                                .text_size(px(11.0))
                                .text_color(rgb(0x8E8E93))
                                .child(service.purpose.clone()),
                        );
                    }
                }
            }
            _ => {
                body = body.child(
                    div()
                        .text_size(px(12.0))
                        .child(if self.connected {
                            "No services recorded"
                        } else {
                            "Controller offline"
                        }),
                );
            }
        }
        body
    }

    fn events(&self) -> impl IntoElement {
        let mut body = div().flex().flex_col().gap(px(4.0));
        match &self.view {
            Some(view) if !view.event_rows.is_empty() => {
                for event in &view.event_rows {
                    body = body.child(
                        div()
                            .flex()
                            .flex_row()
                            .gap(px(8.0))
                            .child(cell(
                                event.label.clone(),
                                170.0,
                                if event.is_bad { 0xFF6961 } else { 0xFFFFFF },
                            ))
                            .child(cell(event.service_name.clone(), 170.0, 0xFFFFFF))
                            .child(cell(event.detail.clone(), 380.0, 0xFFFFFF))
                            .child(cell(event.when.clone(), 130.0, 0x8E8E93)),
                    );
                }
            }
            _ => {
                body = body.child(
                    div()
                        .text_size(px(12.0))
                        .child(if self.connected {
                            "No events yet"
                        } else {
                            "Controller offline"
                        }),
                );
            }
        }
        body
    }

    fn launch_services(&self) -> impl IntoElement {
        let mut body = div().flex().flex_col().gap(px(4.0));
        body = body.child(
            div()
                .flex()
                .flex_row()
                .child(cell("Label".into(), 420.0, 0x8E8E93))
                .child(cell("PID".into(), 90.0, 0x8E8E93))
                .child(cell("Status".into(), 160.0, 0x8E8E93)),
        );
        if self.launch_rows.is_empty() {
            body = body.child(
                div()
                    .text_size(px(12.0))
                    .child("No launch services read yet"),
            );
        }
        for row in &self.launch_rows {
            body = body.child(
                div()
                    .flex()
                    .flex_row()
                    .child(cell(row.label.clone(), 420.0, 0xFFFFFF))
                    .child(cell(
                        row.pid.map(|pid| pid.to_string()).unwrap_or_else(|| "—".into()),
                        90.0,
                        0xFFFFFF,
                    ))
                    .child(cell(row.status.clone(), 160.0, 0xFFFFFF)),
            );
        }
        body
    }
}

impl Render for DashboardView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let mut sidebar = div()
            .flex()
            .flex_col()
            .gap(px(4.0))
            .w(px(180.0))
            .flex_none()
            .p(px(12.0));
        for module in Module::all() {
            let selected = module == self.module;
            sidebar = sidebar.child(
                div()
                    .id(gpui::SharedString::from(format!(
                        "module-{}",
                        module.nav_label()
                    )))
                    .px(px(10.0))
                    .py(px(6.0))
                    .rounded(px(6.0))
                    .bg(if selected {
                        rgb(0x3A3A3C)
                    } else {
                        rgb(0x1F1F1F)
                    })
                    .text_size(px(13.0))
                    .child(module.nav_label())
                    .on_click(cx.listener(move |view, _, _, cx| {
                        view.module = module;
                        cx.notify();
                    })),
            );
        }
        let content = match self.module {
            Module::Overview => {
                self.refresh_topology();
                self.overview().into_any_element()
            }
            Module::Processes => self.processes().into_any_element(),
            Module::Storage => self.storage().into_any_element(),
            Module::Services => self.services().into_any_element(),
            Module::Events => self.events().into_any_element(),
            Module::LaunchServices => self.launch_services().into_any_element(),
        };
        div()
            .flex()
            .flex_row()
            .size_full()
            .bg(rgb(0x1F1F1F))
            .text_color(rgb(0xFFFFFF))
            .child(sidebar)
            .child(
                div()
                    .flex()
                    .flex_col()
                    .flex_1()
                    .gap(px(12.0))
                    .p(px(16.0))
                    .child(header(self.module.title()))
                    .children(crate::config_warning(cx))
                    .child(
                        div()
                            .id("dashboard-scroll")
                            .flex_1()
                            .overflow_y_scroll()
                            .track_scroll(&self.scroll)
                            .child(content),
                    ),
            )
    }
}
