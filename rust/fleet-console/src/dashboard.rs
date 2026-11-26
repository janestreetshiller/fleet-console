use std::rc::Rc;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use gpui::{
    canvas, div, point, px, rgb, uniform_list, Context, InteractiveElement, IntoElement, MouseButton,
    ParentElement, PathBuilder, Pixels, Point, Render, ScrollHandle, SharedString, StatefulInteractiveElement,
    Styled, Window,
};

use crate::awareness_layout::{Layout, CARD_HEIGHT, CARD_WIDTH, COLUMN_GAP, ROW_GAP};
use crate::quickview::fmt_bytes;
use crate::sampler::{ProcRow, Sample};
use crate::snapshot::{fmt_relative, FleetTopology, FleetView, Snapshot, TopologyEdgeKind, TopologyNode, TopologyNodeKind};

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
    map: Rc<TopologyMap>,
    camera: Option<MapCamera>,
    drag_position: Option<Point<Pixels>>,
    selected: Option<SharedString>,
}

const SIDEBAR_WIDTH: f32 = 180.0;
const CONTENT_PADDING: f32 = 16.0;
const INSPECTOR_WIDTH: f32 = 270.0;
const MAP_GAP: f32 = 10.0;
const MAP_PADDING: f32 = 20.0;
const MAX_ZOOM: f32 = 2.0;

struct MapCard {
    id: SharedString,
    title: SharedString,
    detail: SharedString,
}

struct TopologyMap {
    projection: FleetTopology,
    layout: Layout,
    cards: Vec<MapCard>,
}

impl TopologyMap {
    fn new(projection: FleetTopology) -> Self {
        let layout = Layout::new(&projection);
        let cards = layout.nodes.iter().map(|placed| {
            let node = &projection.nodes[placed.source_index];
            MapCard {
                id: node.id.clone().into(),
                title: node.title.clone().into(),
                detail: node.detail.clone().into(),
            }
        }).collect();
        Self { projection, layout, cards }
    }

    fn node(&self, index: usize) -> &TopologyNode {
        &self.projection.nodes[self.layout.nodes[index].source_index]
    }
}

#[derive(Clone, Copy)]
struct MapCamera {
    center_x: f32,
    center_y: f32,
    zoom: f32,
}

impl MapCamera {
    fn fit(layout: &Layout, width: f32, height: f32) -> Self {
        Self {
            center_x: layout.width / 2.0,
            center_y: layout.height / 2.0,
            zoom: ((width - MAP_PADDING * 2.0).max(1.0) / layout.width.max(1.0))
                .min((height - MAP_PADDING * 2.0).max(1.0) / layout.height.max(1.0))
                .min(1.0),
        }
    }

    fn offset(self, width: f32, height: f32) -> (f32, f32) {
        (
            width / 2.0 - self.center_x * self.zoom,
            height / 2.0 - self.center_y * self.zoom,
        )
    }
}

fn node_kind(kind: TopologyNodeKind) -> (&'static str, u32) {
    match kind {
        TopologyNodeKind::Owner => ("Recorded owner", 0xBCA6FF),
        TopologyNodeKind::Service => ("Registered service", 0x8FC6FF),
        TopologyNodeKind::Leader => ("Verified group leader", 0x91D9A9),
        TopologyNodeKind::Listener => ("Observed group listener", 0xF4B77C),
        TopologyNodeKind::Session => ("Detected session · unlinked", 0xDBCD97),
    }
}

const EDGE_STYLES: [(&str, u32); 3] = [
    ("Registry ownership", 0xBCA6FF),
    ("Verified leader", 0x91D9A9),
    ("Observed listener", 0xF4B77C),
];

fn edge_style(kind: TopologyEdgeKind) -> usize {
    match kind {
        TopologyEdgeKind::Owns => 0,
        TopologyEdgeKind::VerifiedLeader => 1,
        TopologyEdgeKind::ObservedListener => 2,
    }
}

fn map_button(id: &'static str, label: &'static str) -> gpui::Stateful<gpui::Div> {
    div().id(id).px(px(8.0)).py(px(4.0)).rounded(px(5.0))
        .text_size(px(12.0)).bg(rgb(0x30353F))
        .hover(|style| style.bg(rgb(0x414A5C)))
        .cursor_pointer().child(label)
}

fn map_edges(map: Rc<TopologyMap>, camera: MapCamera, selected: Option<usize>) -> impl IntoElement {
    canvas(
        |_, _, _| (),
        move |bounds, (), window, _| {
            let width = f32::from(bounds.size.width);
            let height = f32::from(bounds.size.height);
            let (ox, oy) = camera.offset(width, height);
            let z = camera.zoom;
            let mut paths: [Option<PathBuilder>; EDGE_STYLES.len() * 2] = Default::default();
            let at = |x, y| point(bounds.origin.x + px(x), bounds.origin.y + px(y));
            for edge in &map.layout.edges {
                let source = &map.layout.nodes[edge.source];
                let target = &map.layout.nodes[edge.target];
                let sx = ox + (source.x + CARD_WIDTH) * z;
                let sy = oy + (source.y + CARD_HEIGHT * 0.5) * z;
                let tx = ox + (target.x + CARD_WIDTH * 0.5) * z;
                let ty = oy + target.y * z;
                let gx = sx + COLUMN_GAP * 0.5 * z;
                let gy = ty - ROW_GAP * 0.5 * z;
                if sx.min(tx) > width || gx.max(tx) < 0.0 || sy > height || ty < 0.0 {
                    continue;
                }
                let focused = selected.is_some_and(|index| edge.source == index || edge.target == index);
                let style = edge_style(map.projection.edges[edge.source_index].kind);
                let index = style + if focused { EDGE_STYLES.len() } else { 0 };
                let path = paths[index].get_or_insert_with(|| {
                    PathBuilder::stroke(px(if focused { 2.5 } else { 1.2 }))
                });
                path.move_to(at(sx, sy));
                path.line_to(at(gx, sy));
                path.line_to(at(gx, gy));
                path.line_to(at(tx, gy));
                path.line_to(at(tx, ty));
            }
            for (index, path) in paths.into_iter().enumerate() {
                if let Some(path) = path.and_then(|path| path.build().ok()) {
                    window.paint_path(path, rgb(EDGE_STYLES[index % EDGE_STYLES.len()].1));
                }
            }
        },
    ).absolute().top_0().left_0().size_full()
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
                        && view.topology.as_ref().and_then(|cache| cache.map.projection.valid_until)
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
                && cache.map.projection.valid_until.is_none_or(|until| now <= until)
        }) {
            return;
        }
        let map = Rc::new(TopologyMap::new(FleetTopology::from_snapshot(source, None, now, live)));
        if let Some(cache) = &mut self.topology {
            cache.source = source.clone();
            cache.live = live;
            if cache.selected.as_ref().is_some_and(|id| !map.cards.iter().any(|card| &card.id == id)) {
                cache.selected = None;
            }
            cache.map = map;
        } else {
            self.topology = Some(TopologyCache {
                source: source.clone(),
                live,
                map,
                camera: None,
                drag_position: None,
                selected: None,
            });
        }
    }

    fn map_viewport(
        cache: &TopologyCache,
        camera: MapCamera,
        selected: Option<usize>,
        width: f32,
        height: f32,
        cx: &Context<Self>,
    ) -> impl IntoElement {
        let (ox, oy) = camera.offset(width, height);
        let z = camera.zoom;
        let mut viewport = div().id("awareness-viewport").relative().w(px(width)).h(px(height))
            .flex_none().overflow_hidden().rounded(px(8.0)).bg(rgb(0x141820))
            .capture_any_mouse_down(cx.listener(|view, event: &gpui::MouseDownEvent, _, _| {
                if event.button == MouseButton::Left {
                    if let Some(cache) = &mut view.topology {
                        cache.drag_position = Some(event.position);
                    }
                }
            }))
            .on_mouse_move(cx.listener(move |view, event: &gpui::MouseMoveEvent, _, cx| {
                if let Some(cache) = &mut view.topology {
                    if !event.dragging() {
                        cache.drag_position = None;
                    } else if let Some(previous) = cache.drag_position {
                        cache.drag_position = Some(event.position);
                        let delta = event.position - previous;
                        if delta.x != px(0.0) || delta.y != px(0.0) {
                            let mut camera = cache.camera.unwrap_or(camera);
                            camera.center_x -= f32::from(delta.x) / camera.zoom;
                            camera.center_y -= f32::from(delta.y) / camera.zoom;
                            cache.camera = Some(camera);
                            cx.notify();
                        }
                    }
                }
            }))
            .on_mouse_up(MouseButton::Left, cx.listener(|view, _, _, _| {
                if let Some(cache) = &mut view.topology {
                    cache.drag_position = None;
                }
            }))
            .on_mouse_up_out(MouseButton::Left, cx.listener(|view, _, _, _| {
                if let Some(cache) = &mut view.topology {
                    cache.drag_position = None;
                }
            }))
            .child(map_edges(Rc::clone(&cache.map), camera, selected));
        for (index, placed) in cache.map.layout.nodes.iter().enumerate() {
            let left = ox + placed.x * z;
            let top = oy + placed.y * z;
            if left >= width || top >= height || left + CARD_WIDTH * z <= 0.0 || top + CARD_HEIGHT * z <= 0.0 {
                continue;
            }
            let card = &cache.map.cards[index];
            let (kind, color) = node_kind(cache.map.node(index).kind);
            let active = selected == Some(index);
            let id = card.id.clone();
            let mut node = div().id(card.id.clone()).absolute().left(px(left)).top(px(top))
                .w(px(CARD_WIDTH * z)).h(px(CARD_HEIGHT * z))
                .overflow_hidden().rounded(px(7.0 * z)).border_1().border_color(rgb(color))
                .bg(rgb(if active { 0x34445C } else { 0x222A36 }))
                .hover(|style| style.bg(rgb(0x303D50))).cursor_pointer()
                .on_mouse_down(MouseButton::Left, cx.listener(|view, _, _, _| {
                    if let Some(cache) = &mut view.topology {
                        cache.drag_position = None;
                    }
                }))
                .on_click(cx.listener(move |view, _, _, cx| {
                    if let Some(cache) = &mut view.topology {
                        cache.selected = Some(id.clone());
                        cx.notify();
                    }
                }));
            if z >= 0.28 {
                node = node.flex().flex_col().gap(px(3.0 * z)).p(px(9.0 * z))
                    .line_height(px(16.0 * z))
                    .child(div().truncate().text_size(px(11.0 * z)).text_color(rgb(color)).child(kind))
                    .child(div().truncate().text_size(px(15.0 * z)).child(card.title.clone()));
                if z >= 0.56 {
                    node = node.child(div().truncate().text_size(px(11.0 * z))
                        .text_color(rgb(0xA9B3C3)).child(card.detail.clone()));
                }
            }
            viewport = viewport.child(node);
        }
        viewport
    }

    fn map_inspector(cache: &TopologyCache, selected: Option<usize>, camera: MapCamera, height: f32, cx: &Context<Self>) -> impl IntoElement {
        let panel_id = cache.selected.clone().unwrap_or_else(|| "awareness-inspector".into());
        let mut panel = div().id(panel_id).h(px(height)).overflow_y_scroll()
            .rounded(px(8.0)).bg(rgb(0x22262E)).p(px(12.0)).flex().flex_col().gap(px(7.0))
            .text_size(px(12.0)).child(header("Map evidence"));
        let Some(index) = selected else {
            return panel.child("Select a card to see what the controller recorded and which relationships it supports.");
        };
        let node = cache.map.node(index);
        let card = &cache.map.cards[index];
        let placed = &cache.map.layout.nodes[index];
        let (kind, color) = node_kind(node.kind);
        let focus = MapCamera {
            center_x: placed.x + CARD_WIDTH / 2.0,
            center_y: placed.y + CARD_HEIGHT / 2.0,
            zoom: camera.zoom.max(0.9),
        };
        panel = panel
            .child(div().text_color(rgb(color)).child(kind))
            .child(div().text_size(px(16.0)).child(card.title.clone()))
            .child(card.detail.clone());
        if let Some(owner) = &node.owner {
            panel = panel.child(format!("Recorded owner: {owner}"));
        }
        if let Some(service) = &node.service_id {
            panel = panel.child(format!("Registered service: {service}"));
        }
        let now = now_seconds();
        if let Some(at) = node.observed_at {
            panel = panel.child(format!("Last recorded observation: {}", fmt_relative(Some(at), now)));
        }
        if matches!(node.kind, TopologyNodeKind::Service | TopologyNodeKind::Session) {
            panel = panel.child(format!(
                "CPU {} · Memory {}",
                node.cpu_pct.map_or_else(|| "unavailable".to_owned(), |value| fmt_cpu(Some(value))),
                node.mem_mb.map_or_else(|| "unavailable".to_owned(), |value| fmt_mem(Some(value))),
            ));
        }
        panel = panel.child(div().flex().gap(px(6.0))
            .child(map_button("focus-selected", "Focus").on_click(cx.listener(move |view, _, _, cx| {
                if let Some(cache) = &mut view.topology {
                    cache.camera = Some(focus);
                    cx.notify();
                }
            })))
            .child(map_button("clear-selection", "Clear").on_click(cx.listener(|view, _, _, cx| {
                if let Some(cache) = &mut view.topology {
                    cache.selected = None;
                    cx.notify();
                }
            }))));
        let mut connections = cache.map.layout.edges.iter()
            .filter(|edge| edge.source == index || edge.target == index).peekable();
        if connections.peek().is_none() {
            return panel.child(if node.kind == TopologyNodeKind::Session {
                "No registry ownership link is established for this session."
            } else {
                "No relationships shown for this card."
            });
        }
        panel = panel.child(header("Relationships on the map"));
        for edge in connections {
            let evidence = &cache.map.projection.edges[edge.source_index];
            let other = if edge.source == index { edge.target } else { edge.source };
            let other_card = &cache.map.cards[other];
            let other_placed = &cache.map.layout.nodes[other];
            let (label, color) = EDGE_STYLES[edge_style(evidence.kind)];
            let id = other_card.id.clone();
            let focus = MapCamera {
                center_x: other_placed.x + CARD_WIDTH / 2.0,
                center_y: other_placed.y + CARD_HEIGHT / 2.0,
                zoom: focus.zoom,
            };
            let observed = evidence.observed_at.map_or_else(|| "time unavailable".to_owned(), |at| fmt_relative(Some(at), now));
            panel = panel.child(div().id(edge.source_index).flex().flex_col().gap(px(2.0))
                .p(px(6.0)).rounded(px(5.0)).bg(rgb(0x2C333F))
                .hover(|style| style.bg(rgb(0x414A5C))).cursor_pointer()
                .child(div().text_color(rgb(color)).child(label))
                .child(other_card.title.clone())
                .child(format!("{} · {observed}", evidence.provenance))
                .on_click(cx.listener(move |view, _, _, cx| {
                    if let Some(cache) = &mut view.topology {
                        cache.selected = Some(id.clone());
                        cache.camera = Some(focus);
                        cx.notify();
                    }
                })));
        }
        panel
    }

    fn awareness(&self, window: &Window, cx: &Context<Self>) -> gpui::Div {
        let mut body = div().flex().flex_col().gap(px(MAP_GAP)).child(header("Agent awareness map"));
        let Some(cache) = &self.topology else {
            return body.child("Map unavailable · waiting for a controller snapshot.");
        };
        let projection = &cache.map.projection;
        body = body.child(div().text_size(px(12.0)).text_color(rgb(0xA9B3C3)).child(
            if projection.is_stale {
                "Retained controller observations · live evidence unavailable"
            } else {
                "Current controller snapshot · cards show available evidence only"
            },
        ));
        let layout = &cache.map.layout;
        if layout.nodes.is_empty() {
            return body.child("No agent sessions or registry activity in this snapshot.");
        }
        let window_size = window.viewport_size();
        let content_width = (f32::from(window_size.width) - SIDEBAR_WIDTH - CONTENT_PADDING * 2.0).max(1.0);
        let wide = content_width >= 780.0;
        let width = content_width - if wide { INSPECTOR_WIDTH + MAP_GAP } else { 0.0 };
        let height = (f32::from(window_size.height) * 0.57).clamp(220.0, 720.0);
        let fit = MapCamera::fit(layout, width, height);
        let camera = cache.camera.unwrap_or(fit);
        let selected = cache.selected.as_ref()
            .and_then(|id| cache.map.cards.iter().position(|card| &card.id == id));
        let mut controls = div().flex().flex_wrap().items_center().gap(px(6.0));
        for (id, label, factor) in [("map-zoom-out", "− Zoom", 0.8), ("map-zoom-in", "+ Zoom", 1.25)] {
            controls = controls.child(map_button(id, label).on_click(cx.listener(move |view, _, _, cx| {
                if let Some(cache) = &mut view.topology {
                    let mut camera = cache.camera.unwrap_or(camera);
                    camera.zoom = (camera.zoom * factor).clamp(fit.zoom.min(0.18), MAX_ZOOM);
                    cache.camera = Some(camera);
                    cx.notify();
                }
            })));
        }
        controls = controls.child(map_button("map-fit", "Fit all").on_click(cx.listener(|view, _, _, cx| {
            if let Some(cache) = &mut view.topology {
                cache.camera = None;
                cx.notify();
            }
        }))).child(div().text_size(px(12.0)).text_color(rgb(0xA9B3C3))
            .child(format!("{:.0}% · drag empty space to pan", camera.zoom * 100.0)));
        let inspector_height = if !wide && selected.is_none() { 105.0 } else { height };
        let inspector = Self::map_inspector(cache, selected, camera, inspector_height, cx);
        let row = div().flex().gap(px(MAP_GAP));
        let row = if wide { row.flex_row() } else { row.flex_col() };
        body = body.child(controls).child(row
            .child(Self::map_viewport(cache, camera, selected, width, height, cx))
            .child(div().flex_none().w(px(if wide { INSPECTOR_WIDTH } else { width })).child(inspector)))
            .child(div().flex().flex_wrap().gap(px(10.0)).text_size(px(12.0)).children(
                EDGE_STYLES.into_iter().map(|(label, color)| div().text_color(rgb(color)).child(label)),
            ));
        if layout.omitted > 0 {
            body = body.child(div().text_size(px(12.0)).text_color(rgb(0xA9B3C3))
                .child(format!("{} more cards omitted from this map; see Services and Processes for diagnostics.", layout.omitted)));
        }
        body
    }

    fn overview(&self, window: &Window, cx: &Context<Self>) -> impl IntoElement {
        let mut body = div().flex().flex_col().gap(px(10.0));
        match (&self.view, self.connected) {
            (Some(view), true) => {
                let retained = self.topology.as_ref().is_some_and(|cache| cache.map.projection.is_stale);
                let status = if retained {
                    format!("Last reported: {}", view.status_line)
                } else {
                    view.status_line.clone()
                };
                body = body.child(div().text_size(px(20.0)).child(status))
                    .child(div().text_size(px(12.0)).text_color(rgb(0xA9B3C3)).child(format!(
                        "{} running · {} critical · {} warning · {} awaiting your answer",
                        view.running_count, view.critical_count, view.warning_count, view.awaiting_reply_count,
                    )));
            }
            _ => {
                body = body.child(div().text_size(px(20.0)).child(if self.connected {
                    "Waiting for a controller snapshot"
                } else {
                    "Controller offline"
                }));
            }
        }
        body = body.child(self.awareness(window, cx)).child(header("Diagnostics"));
        body = body.child(div().flex().flex_wrap().gap(px(6.0)).children(
            [("overview-services", "Services", Module::Services), ("overview-processes", "Processes", Module::Processes),
                ("overview-events", "Events", Module::Events)].into_iter().map(|(id, label, module)| {
                map_button(id, label).on_click(cx.listener(move |view, _, _, cx| {
                    view.module = module;
                    view.scroll.set_offset(Point::default());
                    cx.notify();
                }))
            }),
        ));
        if let Some(cache) = &self.topology {
            let projection = &cache.map.projection;
            body = body.child(div().text_size(px(12.0)).text_color(rgb(0xA9B3C3))
                .child(format!("Controller snapshot: {}", fmt_relative(Some(projection.generated_at), now_seconds())))
                .children(projection.limitations.iter().map(|&note| div().child(note))));
        }
        if let Some(view) = self.view.as_ref().filter(|_| self.connected) {
            let count = view.profiles.len();
            if count > 0 {
                let dashboard = cx.entity().downgrade();
                body = body.child(header("Controller profiles")).child(
                    uniform_list("overview-profiles", count, move |range, _, cx| {
                        let Some(entity) = dashboard.upgrade() else { return Vec::new() };
                        let Some(view) = &entity.read(cx).view else { return Vec::new() };
                        view.profiles.get(range).unwrap_or_default().iter().map(|profile| {
                            let headline = if profile.awaiting_reply > 0 {
                                format!("{} — {} — {} awaiting your answer", profile.id, profile.headline, profile.awaiting_reply)
                            } else {
                                format!("{} — {}", profile.id, profile.headline)
                            };
                            div().h(px(24.0)).text_size(px(13.0)).truncate().child(headline)
                        }).collect()
                    }).h(px(24.0 * count.min(6) as f32)).w_full(),
                );
            }
        }
        if let Some(sample) = &self.sample {
            body = body.child(div().text_size(px(12.0)).text_color(rgb(0xA9B3C3)).child(format!(
                "This machine — CPU {} · RAM {} · DISK {}",
                crate::sampler::value_text(sample.meters.cpu),
                crate::sampler::value_text(sample.meters.ram),
                crate::sampler::value_text(sample.meters.disk),
            )));
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
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let mut sidebar = div()
            .flex()
            .flex_col()
            .gap(px(4.0))
            .w(px(SIDEBAR_WIDTH))
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
                self.overview(window, cx).into_any_element()
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
                    .min_w_0()
                    .p(px(CONTENT_PADDING))
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
