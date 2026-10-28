//! The relational map: one graph joining the controller, the devices it
//! serves, the services it supervises, the agents it routes for, the local
//! process tree and the mounted volumes, with the needs-attention reports
//! pinned on the node they are about.
//!
//! Like `views::Dashboard::build`, this is a pure function of a dashboard.
//! Every value on a node comes from a feed that measured it; when a feed is
//! loading, stale or disconnected, its group is left out and the note says so
//! instead of an estimated or simulated value. The layout is deterministic:
//! the same dashboard always produces the same coordinates, and neither the
//! model nor the window has an animation loop.

use crate::format;
use crate::observe::{Metric, Phase, Reason};
use crate::thresholds::Level;
use crate::views::{Dashboard, Freshness, NodeTile, ProcessLine, ProcessRole, Severity};

/// Most linked devices drawn; the note names the rest.
pub const MAX_DEVICES: usize = 6;
/// Most services drawn; sorted by worst CPU, so the busy ones always win.
pub const MAX_SERVICES: usize = 10;
/// Most processes drawn; the local tree's heaviest rows first, plus every row
/// a drawn service owns through its pid.
pub const MAX_PROCESSES: usize = 8;
/// Most volumes drawn; the least headroom first.
pub const MAX_VOLUMES: usize = 5;
/// Most reports pinned on one node; the rest collapse into a "+k more" line.
pub const MAX_BADGES_PER_NODE: usize = 3;
/// Force-layout steps applied once per build. With the bounded node count
/// this stays well under a millisecond, so a rebuild never lags.
pub const LAYOUT_STEPS: usize = 120;
/// Map radius in map units; the renderer scales this to the viewport.
pub const MAP_RADIUS: f32 = 340.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NodeKind {
    Controller,
    Device,
    Service,
    Agent,
    Process,
    Volume,
}

impl NodeKind {
    pub fn label(self) -> &'static str {
        match self {
            Self::Controller => "controller",
            Self::Device => "device",
            Self::Service => "service",
            Self::Agent => "agent",
            Self::Process => "process",
            Self::Volume => "volume",
        }
    }
}

/// Why an edge exists, in the words the legend uses.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EdgeKind {
    /// A linked device the controller reports on.
    ReportsOn,
    /// The controller supervises a managed service.
    Supervises,
    /// The controller routes agent turns and answers.
    RoutesTo,
    /// A mounted volume the local machine reads and writes.
    MountedOn,
    /// A service or the controller owns this process by pid.
    Owns,
    /// One local process started another.
    ParentOf,
}

impl EdgeKind {
    pub fn label(self) -> &'static str {
        match self {
            Self::ReportsOn => "reports on",
            Self::Supervises => "supervises",
            Self::RoutesTo => "routes to",
            Self::MountedOn => "mounted on",
            Self::Owns => "owns",
            Self::ParentOf => "parent of",
        }
    }
}

/// A health report pinned on the node it is about.
#[derive(Debug, Clone, PartialEq)]
pub struct MapBadge {
    pub id: String,
    pub severity: Severity,
    pub title: String,
    pub detail: String,
    /// What can be done through the controller, as `AttentionRow` words it.
    pub available: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct MapNode {
    /// Stable across rebuilds, in `kind:identity` form, used for selection.
    pub id: String,
    pub kind: NodeKind,
    pub label: String,
    /// One honest secondary line: what was measured, or why nothing was.
    pub meta: String,
    /// CPU as the heat of the node, measured only where a feed measured it.
    pub cpu: Metric,
    /// The node's worst reported band.
    pub level: Option<Level>,
    /// Whether the node's feed is live, stale or disconnected. Devices age.
    pub freshness: Freshness,
    pub badges: Vec<MapBadge>,
    /// Reports beyond `MAX_BADGES_PER_NODE`, so a "+k more" line is exact.
    pub badge_overflow: usize,
    /// Layout coordinates in map units, roughly -`MAP_RADIUS`..`MAP_RADIUS`.
    pub x: f32,
    pub y: f32,
    /// Layout velocity, used only inside one build's settle steps.
    vx: f32,
    vy: f32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct MapEdge {
    pub source: String,
    pub target: String,
    pub kind: EdgeKind,
    /// Relative activity for strokes: the target's CPU fraction when it was
    /// measured, `None` when it was not.
    pub activity: Option<f64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RelationalMap {
    /// In drawing order: controller, devices, services, agents, processes,
    /// volumes. Selection indexes into this list.
    pub nodes: Vec<MapNode>,
    pub edges: Vec<MapEdge>,
    /// Lines about groups that are not drawn and why, in feed words.
    pub notes: Vec<String>,
}

impl RelationalMap {
    pub fn build(dash: &Dashboard) -> Self {
        let mut nodes: Vec<MapNode> = Vec::new();
        let mut edges: Vec<MapEdge> = Vec::new();
        let mut notes: Vec<String> = Vec::new();

        // The controller at the center. Its heat is the local device tile's
        // CPU, so the map's center is honest about the machine it runs on.
        let controller_id = "kind:controller".to_string();
        let local_tile = dash.cluster.tiles.iter().find(|t| t.is_local);
        let (controller_label, controller_meta, controller_cpu, controller_freshness) =
            match local_tile {
                Some(tile) => {
                    let cpu = tile
                        .gauges
                        .iter()
                        .find(|g| g.label == "cpu")
                        .map(|g| g.metric)
                        .unwrap_or(Metric::Unavailable(Reason::NotMeasured));
                    ("this machine".to_string(), tile_meta(tile), cpu, tile.freshness)
                }
                None => {
                    notes.push("device telemetry not drawn yet; controller only".to_string());
                    (
                        "controller".to_string(),
                        dash.connection.socket_label.clone(),
                        Metric::Unavailable(Reason::AwaitingSample),
                        freshness_of_phase(dash.connection.telemetry_phase),
                    )
                }
            };
        nodes.push(MapNode {
            id: controller_id.clone(),
            kind: NodeKind::Controller,
            label: controller_label,
            meta: controller_meta,
            cpu: controller_cpu,
            level: Level::for_metric(controller_cpu),
            freshness: controller_freshness,
            badges: Vec::new(),
            badge_overflow: 0,
            x: 0.0,
            y: 0.0,
            vx: 0.0,
            vy: 0.0,
        });

        // Linked devices other than the local one, which is the center.
        let remote_tiles: Vec<&NodeTile> = dash
            .cluster
            .tiles
            .iter()
            .filter(|t| !t.is_local)
            .collect();
        for tile in remote_tiles.iter().take(MAX_DEVICES) {
            let id = device_id(&tile.id);
            let cpu = tile
                .gauges
                .iter()
                .find(|g| g.label == "cpu")
                .map(|g| g.metric)
                .unwrap_or(Metric::Unavailable(Reason::NotMeasured));
            let mut meta = tile.state.label().to_string();
            if tile.freshness != Freshness::Current {
                meta = format!("{meta}, {}", freshness_text(tile.freshness));
            }
            nodes.push(MapNode {
                id: id.clone(),
                kind: NodeKind::Device,
                label: tile.name.clone(),
                meta,
                cpu,
                level: tile.worst_level(),
                freshness: tile.freshness,
                badges: Vec::new(),
                badge_overflow: 0,
                x: 0.0,
                y: 0.0,
                vx: 0.0,
                vy: 0.0,
            });
            edges.push(MapEdge {
                source: controller_id.clone(),
                target: id,
                kind: EdgeKind::ReportsOn,
                activity: None,
            });
        }
        if remote_tiles.len() > MAX_DEVICES {
            notes.push(format!(
                "{} more devices are not drawn; the first {} linked devices appear",
                remote_tiles.len() - MAX_DEVICES,
                MAX_DEVICES
            ));
        }

        // Services, busiest CPU first so the map keeps the active ones when a
        // controller manages more than the bound. When the controller feed is
        // not live, its rows are last read, which the node's freshness says.
        let mut services: Vec<&crate::views::ServiceRow> = dash.services.iter().collect();
        services.sort_by(|a, b| {
            b.cpu
                .value()
                .partial_cmp(&a.cpu.value())
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| a.id.cmp(&b.id))
        });
        for row in services.iter().take(MAX_SERVICES) {
            let id = service_id(&row.id);
            nodes.push(MapNode {
                id,
                kind: NodeKind::Service,
                label: row.name.clone(),
                meta: service_meta(row),
                cpu: row.cpu,
                level: row.level,
                freshness: freshness_of_phase(dash.connection.phase),
                badges: Vec::new(),
                badge_overflow: 0,
                x: 0.0,
                y: 0.0,
                vx: 0.0,
                vy: 0.0,
            });
        }
        for row in services.iter().take(MAX_SERVICES) {
            edges.push(MapEdge {
                source: controller_id.clone(),
                target: service_id(&row.id),
                kind: EdgeKind::Supervises,
                activity: row.cpu.fraction(),
            });
        }
        if services.len() > MAX_SERVICES {
            notes.push(format!(
                "{} more services are not drawn; the busiest services appear",
                services.len() - MAX_SERVICES
            ));
        }

        // Agents, routed by the controller. Their state and runtime are the
        // transcript's words; no CPU is invented for them. Two sessions can
        // share a name, so the id carries the target and, still with a
        // collision, a stable ordinal.
        let mut agent_seen: std::collections::HashMap<String, usize> = Default::default();
        for row in &dash.agents.rows {
            let mut meta = format!("{} · {}", row.state, row.runtime);
            if row.awaiting_reply > 0 {
                meta = format!("{meta} · {} awaiting reply", row.awaiting_reply);
            }
            let ordinal = {
                let count = agent_seen.entry(row.name.clone()).or_insert(0);
                let taken = *count;
                *count += 1;
                taken
            };
            let id = agent_id(&row.name, &row.target, ordinal);
            nodes.push(MapNode {
                id: id.clone(),
                kind: NodeKind::Agent,
                label: row.name.clone(),
                meta,
                cpu: Metric::Unavailable(Reason::NotMeasured),
                level: row.level,
                freshness: freshness_of_phase(dash.connection.phase),
                badges: Vec::new(),
                badge_overflow: 0,
                x: 0.0,
                y: 0.0,
                vx: 0.0,
                vy: 0.0,
            });
            edges.push(MapEdge {
                source: controller_id.clone(),
                target: id,
                kind: EdgeKind::RoutesTo,
                activity: None,
            });
        }

        // The local process tree, reduced to the rows worth drawing. A line a
        // drawn service owns by pid keeps that edge; the rest hang from their
        // nearest drawn ancestor or, without one, from the controller.
        if dash.processes.phase == Phase::Live {
            let parents = parent_map(&dash.processes.lines);
            let owned: Vec<u32> = dash
                .services
                .iter()
                .take(MAX_SERVICES)
                .filter_map(|s| s.pid.map(|pid| pid as u32))
                .collect();
            let mut ranked: Vec<usize> = dash
                .processes
                .lines
                .iter()
                .enumerate()
                .filter(|(_, l)| l.pid.is_some())
                .map(|(i, _)| i)
                .collect();
            ranked.sort_by(|&ai, &bi| {
                let a = &dash.processes.lines[ai];
                let b = &dash.processes.lines[bi];
                b.cpu
                    .value()
                    .partial_cmp(&a.cpu.value())
                    .unwrap_or(std::cmp::Ordering::Equal)
                    .then_with(|| ai.cmp(&bi))
            });
            let mut picks: Vec<usize> = Vec::new();
            for &i in ranked.iter().take(MAX_PROCESSES) {
                picks.push(i);
            }
            // A drawn service's process row must exist, or its "owns" edge
            // would point at nothing.
            for pid in owned {
                if picks.len() >= MAX_PROCESSES {
                    break;
                }
                if let Some(i) = dash
                    .processes
                    .lines
                    .iter()
                    .position(|l| l.pid == Some(pid))
                {
                    if !picks.contains(&i) {
                        picks.push(i);
                    }
                }
            }
            picks.sort_unstable();
            let drawn_pids: Vec<u32> = picks
                .iter()
                .filter_map(|&i| dash.processes.lines[i].pid)
                .collect();
            for &i in &picks {
                let line = &dash.processes.lines[i];
                let pid = line.pid.unwrap_or(0);
                let id = process_id(pid);
                let owner = match dash.services.iter().find(|s| s.pid == Some(pid as i32)) {
                    Some(row) => (service_id(&row.id), EdgeKind::Owns),
                    None if line.role == ProcessRole::Controller => {
                        (controller_id.clone(), EdgeKind::Owns)
                    }
                    None => {
                        let target = parents
                            .get(&pid)
                            .copied()
                            .flatten()
                            .filter(|p| drawn_pids.contains(p));
                        match target {
                            Some(parent) => (process_id(parent), EdgeKind::ParentOf),
                            None => (controller_id.clone(), EdgeKind::ParentOf),
                        }
                    }
                };
                nodes.push(MapNode {
                    id: id.clone(),
                    kind: NodeKind::Process,
                    label: line.name.clone(),
                    meta: format!("{} · {}", format::percent(line.cpu), line.memory),
                    cpu: line.cpu,
                    level: Level::for_metric(line.cpu),
                    freshness: Freshness::Current,
                    badges: Vec::new(),
                    badge_overflow: 0,
                    x: 0.0,
                    y: 0.0,
                    vx: 0.0,
                    vy: 0.0,
                });
                edges.push(MapEdge {
                    source: owner.0,
                    target: id,
                    kind: owner.1,
                    activity: line.cpu.fraction(),
                });
            }
            if dash.processes.lines.len() > drawn_pids.len() {
                notes.push(format!(
                    "{} further processes are not drawn; the busiest rows appear",
                    dash.processes.lines.len() - drawn_pids.len()
                ));
            }
        } else {
            notes.push(format!(
                "the process tree {} and is not drawn",
                match dash.processes.phase {
                    Phase::Loading => "is loading".to_string(),
                    other => format!("is {}", other.label()),
                }
            ));
        }

        // Volumes, least headroom first, only while storage telemetry is live.
        if dash.storage.phase == Phase::Live {
            let mut volumes: Vec<&crate::views::VolumeRow> = dash.storage.volumes.iter().collect();
            volumes.sort_by(|a, b| {
                a.gauge
                    .metric
                    .value()
                    .partial_cmp(&b.gauge.metric.value())
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
            for volume in volumes.iter().take(MAX_VOLUMES) {
                let id = volume_id(&volume.mount);
                nodes.push(MapNode {
                    id: id.clone(),
                    kind: NodeKind::Volume,
                    label: volume.mount.clone(),
                    meta: format!("{} free of {}", volume.free, volume.total),
                    cpu: volume.gauge.metric,
                    level: volume.gauge.level,
                    freshness: Freshness::Current,
                    badges: Vec::new(),
                    badge_overflow: 0,
                    x: 0.0,
                    y: 0.0,
                    vx: 0.0,
                    vy: 0.0,
                });
                edges.push(MapEdge {
                    source: controller_id.clone(),
                    target: id,
                    kind: EdgeKind::MountedOn,
                    activity: volume.gauge.metric.fraction(),
                });
            }
        } else {
            notes.push(format!(
                "volumes {} and are not drawn",
                match dash.storage.phase {
                    Phase::Loading => "are loading".to_string(),
                    other => format!("are {}", other.label()),
                }
            ));
        }

        // Needs-attention reports pinned on the node they name. A report with
        // a service id pins to that service; the rest pin on the controller,
        // where the operator starts from anyway.
        let mut pinned: Vec<(String, MapBadge)> = Vec::new();
        for row in &dash.attention {
            let target = row
                .service_id
                .as_ref()
                .map(|id| service_id(id))
                .unwrap_or_else(|| controller_id.clone());
            pinned.push((
                target,
                MapBadge {
                    id: row.id.clone(),
                    severity: row.severity,
                    title: row.title.clone(),
                    detail: row.detail.clone(),
                    available: row.available.clone(),
                },
            ));
        }
        let mut shown: std::collections::HashMap<String, usize> = Default::default();
        let mut overflow: std::collections::HashMap<String, usize> = Default::default();
        for (target, badge) in pinned {
            let shown_count = shown.entry(target.clone()).or_insert(0);
            if *shown_count >= MAX_BADGES_PER_NODE {
                *overflow.entry(target).or_default() += 1;
                continue;
            }
            if let Some(node) = nodes.iter_mut().find(|n| n.id == target) {
                node.badges.push(badge);
            }
            *shown_count += 1;
        }
        for node in &mut nodes {
            node.badge_overflow = overflow.get(&node.id).copied().unwrap_or(0);
        }

        let mut map = Self { nodes, edges, notes };
        let counts = group_counts(&map);
        for index in 0..map.nodes.len() {
            let (id, kind, _, _) = {
                let node = &map.nodes[index];
                (node.id.clone(), node.kind, node.x, node.y)
            };
            let slot = map_slot(&map, &id, kind);
            let (x, y) = template(kind, slot, counts);
            let node = &mut map.nodes[index];
            node.x = x;
            node.y = y;
        }
        for _ in 0..LAYOUT_STEPS {
            map.settle_step();
        }
        map
    }

    /// Keys the window's selection state uses for the map's rows.
    pub fn selection_keys(&self) -> Vec<String> {
        self.nodes.iter().map(|n| n.id.clone()).collect()
    }

    /// The number of pinned reports, including the overflowed ones.
    pub fn badge_count(&self) -> usize {
        self.nodes
            .iter()
            .map(|n| n.badges.len() + n.badge_overflow)
            .sum()
    }

    /// One force step: repulsion between every pair, springs along edges and
    /// a small pull toward the center. The controller stays at the center.
    fn settle_step(&mut self) {
        let count = self.nodes.len();
        if count < 2 {
            return;
        }
        let fx0 = self.nodes.clone();
        let mut fx = vec![0.0f32; count];
        let mut fy = vec![0.0f32; count];
        for i in 0..count {
            for j in (i + 1)..count {
                let (ax, ay) = (fx0[i].x, fx0[i].y);
                let (bx, by) = (fx0[j].x, fx0[j].y);
                let mut dx = bx - ax;
                let mut dy = by - ay;
                // Two nodes on the same spot are unseparated along no axis;
                // give them a deterministic axis instead of dividing by zero.
                if dx == 0.0 && dy == 0.0 {
                    dx = if i % 2 == 0 { 1.0 } else { -1.0 };
                    dy = if i % 3 == 0 { 1.0 } else { -1.0 };
                }
                let dist_sq = (dx * dx + dy * dy).clamp(2500.0, 1.0e6);
                let dist = dist_sq.sqrt();
                let force = 9_000.0 / dist_sq;
                fx[i] -= dx / dist * force;
                fy[i] -= dy / dist * force;
                fx[j] += dx / dist * force;
                fy[j] += dy / dist * force;
            }
        }
        for edge in &self.edges {
            let (Some(i), Some(j)) = (
                self.nodes.iter().position(|n| n.id == edge.source),
                self.nodes.iter().position(|n| n.id == edge.target),
            ) else {
                continue;
            };
            let dx = fx0[j].x - fx0[i].x;
            let dy = fx0[j].y - fx0[i].y;
            let dist = (dx * dx + dy * dy).sqrt().max(1.0);
            let spring = 0.012 * (dist - 150.0);
            fx[i] += dx / dist * spring;
            fy[i] += dy / dist * spring;
            fx[j] -= dx / dist * spring;
            fy[j] -= dy / dist * spring;
        }
        for index in 0..count {
            if self.nodes[index].kind == NodeKind::Controller {
                self.nodes[index].x = 0.0;
                self.nodes[index].y = 0.0;
                self.nodes[index].vx = 0.0;
                self.nodes[index].vy = 0.0;
                continue;
            }
            let node = &mut self.nodes[index];
            let gx = -node.x * 0.02;
            let gy = -node.y * 0.02;
            node.vx = (node.vx + (fx[index] + gx) * STEP) * 0.5;
            node.vy = (node.vy + (fy[index] + gy) * STEP) * 0.5;
            let speed = (node.vx * node.vx + node.vy * node.vy).sqrt();
            if speed > MAX_SPEED {
                node.vx *= MAX_SPEED / speed;
                node.vy *= MAX_SPEED / speed;
            }
            node.x = (node.x + node.vx * STEP).clamp(-BOUNDS, BOUNDS);
            node.y = (node.y + node.vy * STEP).clamp(-BOUNDS, BOUNDS);
        }
    }
}

const STEP: f32 = 16.0;
/// Speed clamp, in map units per settle step, so the bounded loop always
/// settles instead of oscillating into floating-point overflow.
const MAX_SPEED: f32 = 3.0;
/// Position clamp in map units; larger excursions cannot happen.
const BOUNDS: f32 = 1_200.0;

fn group_counts(map: &RelationalMap) -> [usize; 6] {
    let mut counts = [0usize; 6];
    for node in &map.nodes {
        counts[kind_index(node.kind)] += 1;
    }
    counts
}

fn kind_index(kind: NodeKind) -> usize {
    match kind {
        NodeKind::Controller => 0,
        NodeKind::Device => 1,
        NodeKind::Service => 2,
        NodeKind::Agent => 3,
        NodeKind::Process => 4,
        NodeKind::Volume => 5,
    }
}

/// The zero-based slot of a node within its kind group.
fn map_slot(map: &RelationalMap, id: &str, kind: NodeKind) -> usize {
    let Some(index) = map.nodes.iter().position(|n| n.id == id && n.kind == kind) else {
        return 0;
    };
    map.nodes[..index].iter().filter(|n| n.kind == kind).count()
}

/// A deterministic starting template, one group per arc around the center.
fn template(kind: NodeKind, index: usize, counts: [usize; 6]) -> (f32, f32) {
    let total = counts[kind_index(kind)];
    let (start, end, radius) = match kind {
        NodeKind::Controller => return (0.0, 0.0),
        NodeKind::Device => (55.0, 125.0, 270.0),
        NodeKind::Service => (95.0, 175.0, 240.0),
        NodeKind::Agent => (5.0, 55.0, 240.0),
        NodeKind::Process => (185.0, 265.0, 300.0),
        NodeKind::Volume => (275.0, 345.0, 300.0),
    };
    let span = if total > 1 {
        (end - start) / (total - 1) as f32
    } else {
        (start + end) / 2.0 - start
    };
    let index = index.min(total.saturating_sub(1));
    let angle = start + span * index as f32;
    let rad = angle.to_radians();
    (rad.cos() * radius, rad.sin() * radius)
}

fn freshness_of_phase(phase: Phase) -> Freshness {
    match phase {
        Phase::Live => Freshness::Current,
        Phase::Stale => Freshness::Stale,
        _ => Freshness::Disconnected,
    }
}

fn freshness_text(freshness: Freshness) -> &'static str {
    match freshness {
        Freshness::Current => "current",
        Freshness::Stale => "stale",
        Freshness::Disconnected => "controller disconnected",
    }
}

fn tile_meta(tile: &NodeTile) -> String {
    let mut parts: Vec<String> = Vec::new();
    for gauge in &tile.gauges {
        if gauge.label == "net" {
            continue;
        }
        parts.push(format!("{} {}", gauge.label, gauge.text));
    }
    if parts.is_empty() {
        "no measurements yet".to_string()
    } else {
        parts.join(" · ")
    }
}

fn service_meta(row: &crate::views::ServiceRow) -> String {
    let mut parts: Vec<String> = vec![row.state_text.to_string()];
    if row.cpu.is_measured() {
        parts.push(format!("cpu {}", format::percent(row.cpu)));
    }
    if row.memory != format::UNAVAILABLE {
        parts.push(format!("mem {}", row.memory));
    }
    if !row.ports.is_empty() && row.ports != format::UNAVAILABLE {
        parts.push(format!("ports {}", row.ports));
    }
    parts.join(" · ")
}

/// Which pids a drawn process was started by, from the depth-first tree the
/// process view already ordered and clipped. A line's parent is the most
/// recent open line at the depth above it.
fn parent_map(lines: &[ProcessLine]) -> std::collections::HashMap<u32, Option<u32>> {
    let mut parents = std::collections::HashMap::new();
    let mut stack: Vec<Option<u32>> = Vec::new();
    for line in lines {
        stack.truncate(line.depth);
        let parent = stack.last().copied().flatten();
        if let Some(pid) = line.pid {
            parents.insert(pid, parent);
        }
        stack.push(line.pid);
    }
    parents
}

pub fn device_id(device: &str) -> String {
    format!("kind:device:{device}")
}

pub fn service_id(service: &str) -> String {
    format!("kind:service:{service}")
}

/// `name@target`, with an ordinal when a controller runs two sessions of one
/// name, so selection keys and edges stay unique.
pub fn agent_id(agent: &str, target: &str, ordinal: usize) -> String {
    let base = format!("kind:agent:{agent}@{target}");
    if ordinal == 0 {
        base
    } else {
        format!("{base}#{ordinal}")
    }
}

pub fn process_id(pid: u32) -> String {
    format!("kind:process:{pid}")
}

pub fn volume_id(mount: &str) -> String {
    format!("kind:volume:{mount}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fixtures::{self, Scenario};
    use crate::model::Snapshot;
    use crate::observe::Feed;
    use crate::platform::HostSample;
    use std::time::{Duration, SystemTime};

    fn build_dashboard(
        controller: &Feed<Snapshot>,
        telemetry: &Feed<HostSample>,
        now: SystemTime,
    ) -> Dashboard {
        crate::views::Dashboard::build(&crate::views::Inputs {
            controller,
            controller_stale_after: Duration::from_secs(11),
            telemetry,
            telemetry_stale_after: Duration::from_secs(6),
            pending: &[],
            outcomes: &[],
            read_only: false,
            socket_label: "~/fleetd.sock".into(),
            assume_remote_controller: false,
            now,
        })
    }

    fn dashboard_of(controller: Scenario, telemetry: Scenario) -> Dashboard {
        let now = fixtures::now();
        build_dashboard(
            &fixtures::controller_feed(controller, now),
            &fixtures::telemetry_feed(telemetry, now),
            now,
        )
    }

    fn healthy() -> Dashboard {
        dashboard_of(Scenario::Healthy, Scenario::Healthy)
    }

    fn kind_of(map: &RelationalMap, kind: NodeKind) -> Vec<&MapNode> {
        map.nodes.iter().filter(|n| n.kind == kind).collect()
    }

    #[test]
    fn the_controller_centers_the_map_and_carries_local_heat() {
        let map = RelationalMap::build(&healthy());
        let controller = map.nodes.first().expect("a map always has a controller");
        assert_eq!(controller.kind, NodeKind::Controller);
        assert_eq!(controller.x, 0.0);
        assert_eq!(controller.y, 0.0);
        assert!(
            controller.cpu.is_measured(),
            "the center's heat is the local tile's CPU"
        );
        assert!(
            controller.meta.contains("cpu"),
            "the meta names what was measured: {:?}",
            controller.meta
        );
    }

    #[test]
    fn a_healthy_dashboard_draws_services_processes_and_volumes() {
        let map = RelationalMap::build(&healthy());
        for kind in [
            NodeKind::Service,
            NodeKind::Process,
            NodeKind::Volume,
        ] {
            assert!(
                !kind_of(&map, kind).is_empty(),
                "{kind:?} missing from a healthy map"
            );
        }
        assert!(
            map.edges
                .iter()
                .any(|e| e.kind == EdgeKind::Supervises),
            "the controller supervises its services"
        );
        assert!(map.edges.iter().any(|e| e.kind == EdgeKind::MountedOn));
    }

    #[test]
    fn every_edge_point_at_a_drawn_node() {
        let dash = healthy();
        let map = RelationalMap::build(&dash);
        for edge in &map.edges {
            assert!(
                map.nodes.iter().any(|n| n.id == edge.source),
                "edge source {} has no node",
                edge.source
            );
            assert!(
                map.nodes.iter().any(|n| n.id == edge.target),
                "edge target {} has no node",
                edge.target
            );
        }
    }

    #[test]
    fn a_disconnected_controller_draws_no_services_and_names_the_process_group() {
        let dash = dashboard_of(Scenario::Disconnected, Scenario::Healthy);
        let map = RelationalMap::build(&dash);
        assert!(
            kind_of(&map, NodeKind::Service).is_empty(),
            "no services were measured, so none are drawn"
        );
        // Local telemetry is independent of the controller, so the process
        // tree and volumes are still drawn from the local feeds.
        assert!(
            !kind_of(&map, NodeKind::Process).is_empty() || map.notes.iter().any(|n| n.contains("process tree")),
            "local telemetry draws processes or the note says why not"
        );
        // The selection list has one entry per node and starts at the center.
        let keys = map.selection_keys();
        assert_eq!(keys.first().map(String::as_str), Some("kind:controller"));
        assert_eq!(keys.len(), map.nodes.len());
        let mut unique = keys.clone();
        unique.sort();
        unique.dedup();
        assert_eq!(unique.len(), keys.len(), "every selection key is unique");
    }

    #[test]
    fn duplicate_agent_sessions_get_unique_node_ids() {
        // The healthy fixture carries two sessions named codex-3; the ids
        // must differ without inventing state.
        let map = RelationalMap::build(&healthy());
        let keys = map.selection_keys();
        let agent_keys: Vec<&String> = keys
            .iter()
            .filter(|k| k.starts_with("kind:agent:"))
            .by_ref()
            .collect();
        let mut unique = agent_keys.clone();
        unique.dedup();
        assert_eq!(agent_keys.len(), unique.len(), "same-name sessions got unique ids");
    }

    #[test]
    fn loading_telemetry_leaves_both_groups_out_and_says_so() {
        let dash = dashboard_of(Scenario::Disconnected, Scenario::Loading);
        let map = RelationalMap::build(&dash);
        assert!(
            map.notes
                .iter()
                .any(|n| n.contains("process tree")),
            "the note says the process tree is missing: {:?}",
            map.notes
        );
        assert!(
            map.notes.iter().any(|n| n.contains("volumes")),
            "the note says the volumes are missing: {:?}",
            map.notes
        );
    }

    #[test]
    fn the_layout_is_deterministic() {
        let dash = healthy();
        let first = RelationalMap::build(&dash);
        let second = RelationalMap::build(&dash);
        assert_eq!(first, second, "the same dashboard lays out identically");
    }

    #[test]
    fn flood_data_stays_bounded_and_overflows_are_named() {
        let dash = dashboard_of(Scenario::Flood, Scenario::Flood);
        let map = RelationalMap::build(&dash);
        let count = |kind| kind_of(&map, kind).len();
        assert!(count(NodeKind::Service) <= MAX_SERVICES);
        assert!(count(NodeKind::Process) <= MAX_PROCESSES);
        assert!(count(NodeKind::Device) <= MAX_DEVICES);
        assert!(count(NodeKind::Volume) <= MAX_VOLUMES);
        for node in &map.nodes {
            assert!(
                node.badges.len() <= MAX_BADGES_PER_NODE,
                "{:?} holds more than the badge bound",
                node.id
            );
            assert!(
                node.badge_overflow == 0 || !node.badges.is_empty(),
                "overflow is only ever counted with visible badges"
            );
        }
        assert!(
            map.notes.iter().any(|n| n.contains("not drawn")),
            "overflow is named, not hidden: {:?}",
            map.notes
        );
    }

    #[test]
    fn a_report_pins_on_the_service_it_names_or_the_controller() {
        let map = RelationalMap::build(&healthy());
        assert!(
            map.badge_count() > 0,
            "the healthy fixture carries reports worth pinning"
        );
        for node in &map.nodes {
            for badge in &node.badges {
                assert!(
                    node.id.starts_with("kind:service:") || node.id == "kind:controller",
                    "pinned on {:?}, which is not a service or the controller",
                    node.id
                );
                assert!(!badge.title.is_empty());
                assert!(!badge.available.is_empty());
            }
        }
    }

    #[test]
    fn agent_nodes_never_invent_a_cpu() {
        let map = RelationalMap::build(&healthy());
        for node in kind_of(&map, NodeKind::Agent) {
            assert!(
                !node.cpu.is_measured(),
                "{:?} shows a CPU no feed measured",
                node.label
            );
        }
    }

    #[test]
    fn owned_processes_keep_edge_to_their_service() {
        let map = RelationalMap::build(&healthy());
        let process_ids: Vec<&String> =
            kind_of(&map, NodeKind::Process).iter().map(|n| &n.id).collect();
        assert!(
            process_ids
                .iter()
                .any(|id| map.edges.iter().any(|e| e.kind == EdgeKind::Owns
                    && &e.target == *id)),
            "at least one drawn process is owned by a drawn service or controller"
        );
    }

    #[test]
    fn node_ids_and_metas_carry_unavailable_words_not_blanks() {
        let dash = dashboard_of(Scenario::Loading, Scenario::Loading);
        let map = RelationalMap::build(&dash);
        for node in &map.nodes {
            assert!(node.id.starts_with("kind:"), "{} has a plain id", node.id);
            assert!(!node.label.is_empty(), "{} has no label", node.id);
            assert!(!node.meta.is_empty(), "{} has no meta line", node.id);
        }
    }
}
