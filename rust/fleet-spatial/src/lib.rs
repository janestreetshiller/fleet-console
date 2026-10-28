//! Relational Spatial Mapping Engine for FleetConsole.
//!
//! Replaces isolated tabular silos with four operational planes:
//! 1. Topography: Interactive spatial & relational graph
//! 2. Brain & Agents: Ouros-X adapter plane
//! 3. Execution & Telemetry: Live process & resource mapping
//! 4. Substrate: Storage and volume memory maps

use fleet_telemetry::TelemetrySnapshot;
use ouros_adapter::{AgentState, AgentTaskGraph};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// The four core operational planes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum OperationalPlane {
    Topography,
    BrainAndAgents,
    ExecutionAndTelemetry,
    Substrate,
}

impl OperationalPlane {
    pub fn title(&self) -> &'static str {
        match self {
            Self::Topography => "Topography (Spatial Map)",
            Self::BrainAndAgents => "Brain & Agents (Ouros-X)",
            Self::ExecutionAndTelemetry => "Execution & Telemetry",
            Self::Substrate => "Substrate (Storage & Volumes)",
        }
    }
}

/// Subsystem classification for nodes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum SubsystemCategory {
    ClusterHost,
    RuntimeCore,
    Agent,
    WorkerProcess,
    StoragePool,
    MemoryPool,
    SocketEndpoint,
}

/// Relationship classification for edges.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum RelationKind {
    IpcPipe,
    SharedMemory,
    SocketConnection,
    ParentChild,
    AgentToolLink,
    StorageAccess,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DiagnosticSeverity {
    Info,
    Warning,
    Critical,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum RemediationAction {
    KillProcess(u32),
    ThrottleAgent(String),
    CompactContext(String),
    PurgeCache(String),
    DrainSockets(String),
    RestartDaemon(String),
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DiagnosticBadge {
    pub id: String,
    pub severity: DiagnosticSeverity,
    pub title: String,
    pub message: String,
    pub actions: Vec<RemediationAction>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NodeDetails {
    pub cpu_pct: f32,
    pub memory_bytes: u64,
    pub associated_pid: Option<u32>,
    pub socket_addr: Option<String>,
    pub agent_state: Option<AgentState>,
    pub context_tokens: Option<u64>,
    pub volume_available_bytes: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SpatialNode {
    pub id: String,
    pub label: String,
    pub category: SubsystemCategory,
    pub x: f32,
    pub y: f32,
    pub vx: f32,
    pub vy: f32,
    /// Scaled by RAM footprint / volume
    pub radius: f32,
    /// Heat factor [0.0, 1.0] derived from CPU / thermal pressure
    pub heat: f32,
    pub details: NodeDetails,
    pub badges: Vec<DiagnosticBadge>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SpatialEdge {
    pub id: String,
    pub source: String,
    pub target: String,
    pub relation: RelationKind,
    pub bandwidth_bytes_sec: u64,
    /// Pulse rate derived from activity/throughput
    pub pulse_speed: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Viewport {
    pub pan_x: f32,
    pub pan_y: f32,
    pub zoom: f32,
}

impl Default for Viewport {
    fn default() -> Self {
        Self {
            pan_x: 0.0,
            pan_y: 0.0,
            zoom: 1.0,
        }
    }
}

/// Context bound to the selected entity for the persistent contextual terminal.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContextualTerminalBinding {
    pub entity_id: String,
    pub title: String,
    pub pty_command: String,
    pub target_directory: Option<String>,
    pub inspection_summary: String,
}

/// Descriptive topology hierarchy node for the live sidebar mini-map.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TopologyHierarchyNode {
    pub id: String,
    pub label: String,
    pub category: SubsystemCategory,
    pub glow_intensity: f32, // [0.0, 1.0]
    pub children: Vec<TopologyHierarchyNode>,
}

/// Force-directed relational graph engine.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RelationalTopologyGraph {
    pub nodes: HashMap<String, SpatialNode>,
    pub edges: Vec<SpatialEdge>,
    pub selected_node_id: Option<String>,
    pub active_plane: OperationalPlane,
    pub viewport: Viewport,
}

impl Default for RelationalTopologyGraph {
    fn default() -> Self {
        Self {
            nodes: HashMap::new(),
            edges: Vec::new(),
            selected_node_id: None,
            active_plane: OperationalPlane::Topography,
            viewport: Viewport::default(),
        }
    }
}

impl RelationalTopologyGraph {
    pub fn new() -> Self {
        Self::default()
    }

    /// Ingest telemetry and Ouros-X brain graph to construct unified spatial topology.
    pub fn update_from_telemetry_and_brain(
        &mut self,
        telemetry: &TelemetrySnapshot,
        brain: &AgentTaskGraph,
    ) {
        let mut new_nodes = HashMap::new();
        let mut new_edges = Vec::new();

        // 1. Host Node
        new_nodes.insert(
            "host-cluster".to_string(),
            SpatialNode {
                id: "host-cluster".to_string(),
                label: "Host Cluster (Metal-01)".to_string(),
                category: SubsystemCategory::ClusterHost,
                x: 0.0,
                y: -180.0,
                vx: 0.0,
                vy: 0.0,
                radius: 46.0,
                heat: (telemetry.cpu_usage_pct / 100.0).clamp(0.0, 1.0),
                details: NodeDetails {
                    cpu_pct: telemetry.cpu_usage_pct,
                    memory_bytes: telemetry.used_memory_bytes,
                    associated_pid: None,
                    socket_addr: None,
                    agent_state: None,
                    context_tokens: None,
                    volume_available_bytes: None,
                },
                badges: Vec::new(),
            },
        );

        // 2. Runtime Core Node
        new_nodes.insert(
            "runtime-core".to_string(),
            SpatialNode {
                id: "runtime-core".to_string(),
                label: "Fleet Runtime Core".to_string(),
                category: SubsystemCategory::RuntimeCore,
                x: 0.0,
                y: -80.0,
                vx: 0.0,
                vy: 0.0,
                radius: 36.0,
                heat: 0.25,
                details: NodeDetails {
                    cpu_pct: 4.5,
                    memory_bytes: 120 * 1024 * 1024,
                    associated_pid: Some(50917),
                    socket_addr: Some("/var/run/fleetd.sock".to_string()),
                    agent_state: None,
                    context_tokens: None,
                    volume_available_bytes: None,
                },
                badges: Vec::new(),
            },
        );

        new_edges.push(SpatialEdge {
            id: "edge-host-core".to_string(),
            source: "host-cluster".to_string(),
            target: "runtime-core".to_string(),
            relation: RelationKind::ParentChild,
            bandwidth_bytes_sec: 1024 * 1024,
            pulse_speed: 1.0,
        });

        // 3. Active Agents from Brain Adapter
        let mut agent_idx = 0;
        for (agent_id, task_node) in &brain.nodes {
            let angle = (agent_idx as f32) * 1.5 - 0.75;
            let pos_x = angle.cos() * 160.0;
            let pos_y = angle.sin() * 80.0;
            agent_idx += 1;

            let heat = match task_node.state {
                AgentState::Reasoning => 0.85,
                AgentState::ToolExecution => 0.95,
                AgentState::Idle => 0.15,
                AgentState::AwaitingInput => 0.35,
                AgentState::Suspended => 0.10,
                AgentState::Terminated => 0.0,
            };

            // Calculate radius proportional to context memory tokens
            let token_ratio = task_node.context_memory.utilization_ratio();
            let radius = 28.0 + (token_ratio * 22.0);

            let mut badges = Vec::new();
            if token_ratio > 0.80 {
                badges.push(DiagnosticBadge {
                    id: format!("badge-token-{agent_id}"),
                    severity: DiagnosticSeverity::Warning,
                    title: "High Context Lock".to_string(),
                    message: format!("Agent context memory is {:.1}% full.", token_ratio * 100.0),
                    actions: vec![RemediationAction::CompactContext(agent_id.clone())],
                });
            }

            new_nodes.insert(
                agent_id.clone(),
                SpatialNode {
                    id: agent_id.clone(),
                    label: task_node.name.clone(),
                    category: SubsystemCategory::Agent,
                    x: pos_x,
                    y: pos_y,
                    vx: 0.0,
                    vy: 0.0,
                    radius,
                    heat,
                    details: NodeDetails {
                        cpu_pct: if task_node.state == AgentState::Reasoning { 35.0 } else { 8.0 },
                        memory_bytes: task_node.context_memory.working_heap_bytes,
                        associated_pid: task_node.active_pid,
                        socket_addr: task_node.listening_socket.clone(),
                        agent_state: Some(task_node.state),
                        context_tokens: Some(task_node.context_memory.total_tokens),
                        volume_available_bytes: None,
                    },
                    badges,
                },
            );

            new_edges.push(SpatialEdge {
                id: format!("edge-core-{agent_id}"),
                source: "runtime-core".to_string(),
                target: agent_id.clone(),
                relation: RelationKind::AgentToolLink,
                bandwidth_bytes_sec: 256 * 1024,
                pulse_speed: if task_node.state == AgentState::Reasoning { 2.5 } else { 0.8 },
            });
        }

        // Connect agent sub-edges
        for edge in &brain.edges {
            new_edges.push(SpatialEdge {
                id: format!("edge-brain-{}-{}", edge.source_task_id, edge.target_task_id),
                source: edge.source_task_id.clone(),
                target: edge.target_task_id.clone(),
                relation: RelationKind::IpcPipe,
                bandwidth_bytes_sec: (edge.throughput_messages_sec * 4096.0) as u64,
                pulse_speed: (edge.throughput_messages_sec / 10.0).max(0.5),
            });
        }

        // 4. Worker Processes from Telemetry
        let mut proc_idx = 0;
        for proc in &telemetry.processes {
            // Include high-resource or relevant processes
            if proc.name == "swift-frontend"
                || proc.name == "WindowServer"
                || proc.name == "ouros-x"
                || proc.cpu_pct > 15.0
                || proc.memory_rss_bytes > 500 * 1024 * 1024
            {
                let proc_id = format!("proc-{}", proc.pid);
                let x = -200.0 + (proc_idx as f32 * 130.0);
                let y = 140.0 + ((proc_idx % 2) as f32 * 60.0);
                proc_idx += 1;

                let heat = (proc.cpu_pct / 100.0).clamp(0.0, 1.0);
                let radius = 20.0 + ((proc.memory_rss_bytes as f32 / (1024.0 * 1024.0 * 1024.0)) * 8.0).min(30.0);

                let mut badges = Vec::new();
                if proc.cpu_pct > 90.0 {
                    badges.push(DiagnosticBadge {
                        id: format!("badge-cpu-{}", proc.pid),
                        severity: DiagnosticSeverity::Critical,
                        title: "CPU Saturation (100%)".to_string(),
                        message: format!("Process {} is saturating CPU at {:.1}%.", proc.name, proc.cpu_pct),
                        actions: vec![RemediationAction::KillProcess(proc.pid)],
                    });
                }

                new_nodes.insert(
                    proc_id.clone(),
                    SpatialNode {
                        id: proc_id.clone(),
                        label: format!("{} ({})", proc.name, proc.pid),
                        category: SubsystemCategory::WorkerProcess,
                        x,
                        y,
                        vx: 0.0,
                        vy: 0.0,
                        radius,
                        heat,
                        details: NodeDetails {
                            cpu_pct: proc.cpu_pct,
                            memory_bytes: proc.memory_rss_bytes,
                            associated_pid: Some(proc.pid),
                            socket_addr: None,
                            agent_state: None,
                            context_tokens: None,
                            volume_available_bytes: None,
                        },
                        badges,
                    },
                );

                // Associate process to agent or runtime core
                let parent_key = if proc.name.contains("ouros") {
                    "ouros-core"
                } else if proc.name.contains("codex") {
                    "codex-worker"
                } else {
                    "runtime-core"
                };

                if new_nodes.contains_key(parent_key) {
                    new_edges.push(SpatialEdge {
                        id: format!("edge-proc-{proc_id}"),
                        source: parent_key.to_string(),
                        target: proc_id,
                        relation: RelationKind::ParentChild,
                        bandwidth_bytes_sec: 128 * 1024,
                        pulse_speed: if proc.cpu_pct > 50.0 { 3.0 } else { 1.0 },
                    });
                }
            }
        }

        // 5. Storage Pools (Substrate)
        let mut store_idx = 0;
        for store in &telemetry.storage_pools {
            let store_id = format!("storage-{}", store_idx);
            let x = 220.0;
            let y = -60.0 + (store_idx as f32 * 120.0);
            store_idx += 1;

            let free_ratio = store.available_bytes as f32 / store.total_bytes.max(1) as f32;
            let heat = if free_ratio < 0.15 { 0.90 } else { 0.10 };

            let mut badges = Vec::new();
            if free_ratio < 0.15 {
                badges.push(DiagnosticBadge {
                    id: format!("badge-storage-{store_id}"),
                    severity: DiagnosticSeverity::Critical,
                    title: "Volume Headroom < 15%".to_string(),
                    message: format!("Mount {} has less than {:.1}% free space.", store.mount_point, free_ratio * 100.0),
                    actions: vec![RemediationAction::PurgeCache(store.mount_point.clone())],
                });
            }

            new_nodes.insert(
                store_id.clone(),
                SpatialNode {
                    id: store_id.clone(),
                    label: format!("Vol: {}", store.mount_point),
                    category: SubsystemCategory::StoragePool,
                    x,
                    y,
                    vx: 0.0,
                    vy: 0.0,
                    radius: 32.0,
                    heat,
                    details: NodeDetails {
                        cpu_pct: 0.0,
                        memory_bytes: store.total_bytes - store.available_bytes,
                        associated_pid: None,
                        socket_addr: None,
                        agent_state: None,
                        context_tokens: None,
                        volume_available_bytes: Some(store.available_bytes),
                    },
                    badges,
                },
            );

            new_edges.push(SpatialEdge {
                id: format!("edge-storage-{store_id}"),
                source: "host-cluster".to_string(),
                target: store_id,
                relation: RelationKind::StorageAccess,
                bandwidth_bytes_sec: store.read_bytes_per_sec + store.write_bytes_per_sec,
                pulse_speed: 1.2,
            });
        }

        // Preserve coordinates of existing nodes if available
        for (id, node) in new_nodes.iter_mut() {
            if let Some(existing) = self.nodes.get(id) {
                node.x = existing.x;
                node.y = existing.y;
                node.vx = existing.vx;
                node.vy = existing.vy;
            }
        }

        self.nodes = new_nodes;
        self.edges = new_edges;

        // Auto-select first agent or core if selection is empty
        if self.selected_node_id.is_none() {
            self.selected_node_id = Some("ouros-core".to_string());
        }
    }

    /// Step the force-directed layout simulation.
    pub fn tick_simulation(&mut self, dt: f32) {
        let k_repulsion = 45000.0;
        let k_spring = 0.05;
        let natural_length = 130.0;
        let damping = 0.82;
        let center_gravity = 0.015;

        let node_keys: Vec<String> = self.nodes.keys().cloned().collect();
        let mut fx: HashMap<String, f32> = HashMap::new();
        let mut fy: HashMap<String, f32> = HashMap::new();

        for key in &node_keys {
            fx.insert(key.clone(), 0.0);
            fy.insert(key.clone(), 0.0);
        }

        // 1. Repulsive forces between every node pair
        for i in 0..node_keys.len() {
            for j in (i + 1)..node_keys.len() {
                let id1 = &node_keys[i];
                let id2 = &node_keys[j];
                let n1 = &self.nodes[id1];
                let n2 = &self.nodes[id2];

                let dx = n2.x - n1.x;
                let dy = n2.y - n1.y;
                let dist_sq = (dx * dx + dy * dy).max(100.0);
                let dist = dist_sq.sqrt();

                let rep_force = k_repulsion / dist_sq;
                let f_x = (dx / dist) * rep_force;
                let f_y = (dy / dist) * rep_force;

                *fx.get_mut(id1).unwrap() -= f_x;
                *fy.get_mut(id1).unwrap() -= f_y;
                *fx.get_mut(id2).unwrap() += f_x;
                *fy.get_mut(id2).unwrap() += f_y;
            }
        }

        // 2. Spring forces along edges
        for edge in &self.edges {
            if let (Some(n1), Some(n2)) = (self.nodes.get(&edge.source), self.nodes.get(&edge.target)) {
                let dx = n2.x - n1.x;
                let dy = n2.y - n1.y;
                let dist = (dx * dx + dy * dy).sqrt().max(1.0);
                let delta = dist - natural_length;
                let spring_force = k_spring * delta;

                let f_x = (dx / dist) * spring_force;
                let f_y = (dy / dist) * spring_force;

                if let Some(force_x) = fx.get_mut(&edge.source) {
                    *force_x += f_x;
                }
                if let Some(force_y) = fy.get_mut(&edge.source) {
                    *force_y += f_y;
                }
                if let Some(force_x) = fx.get_mut(&edge.target) {
                    *force_x -= f_x;
                }
                if let Some(force_y) = fy.get_mut(&edge.target) {
                    *force_y -= f_y;
                }
            }
        }

        // 3. Center gravity and integration
        for (id, node) in self.nodes.iter_mut() {
            // Root host node stays anchor near center
            if id == "host-cluster" {
                continue;
            }

            let grav_x = -node.x * center_gravity;
            let grav_y = -node.y * center_gravity;

            let total_fx = fx.get(id).cloned().unwrap_or(0.0) + grav_x;
            let total_fy = fy.get(id).cloned().unwrap_or(0.0) + grav_y;

            node.vx = (node.vx + total_fx * dt) * damping;
            node.vy = (node.vy + total_fy * dt) * damping;

            node.x += node.vx * dt;
            node.y += node.vy * dt;
        }
    }

    /// Focus viewport onto a specific subsystem node.
    pub fn focus_entity(&mut self, entity_id: &str) {
        if let Some(node) = self.nodes.get(entity_id) {
            self.selected_node_id = Some(entity_id.to_string());
            self.viewport.pan_x = -node.x;
            self.viewport.pan_y = -node.y;
            self.viewport.zoom = 1.35;
        }
    }

    /// Build the live Descriptive Topology Map hierarchy for the sidebar.
    pub fn build_sidebar_hierarchy(&self) -> TopologyHierarchyNode {
        let mut agent_children = Vec::new();
        let mut proc_children = Vec::new();
        let mut storage_children = Vec::new();

        for (id, node) in &self.nodes {
            let glow = node.heat.max(if !node.badges.is_empty() { 1.0 } else { 0.0 });
            let h_node = TopologyHierarchyNode {
                id: id.clone(),
                label: node.label.clone(),
                category: node.category,
                glow_intensity: glow,
                children: Vec::new(),
            };

            match node.category {
                SubsystemCategory::Agent => agent_children.push(h_node),
                SubsystemCategory::WorkerProcess => proc_children.push(h_node),
                SubsystemCategory::StoragePool => storage_children.push(h_node),
                _ => {}
            }
        }

        let mut core_children = agent_children;
        core_children.extend(proc_children);
        core_children.extend(storage_children);

        TopologyHierarchyNode {
            id: "host-cluster".to_string(),
            label: "Cluster / Host (Metal-01)".to_string(),
            category: SubsystemCategory::ClusterHost,
            glow_intensity: self.nodes.get("host-cluster").map(|n| n.heat).unwrap_or(0.2),
            children: vec![TopologyHierarchyNode {
                id: "runtime-core".to_string(),
                label: "Runtime Core".to_string(),
                category: SubsystemCategory::RuntimeCore,
                glow_intensity: 0.3,
                children: core_children,
            }],
        }
    }

    /// Get all diagnostic badges across all nodes (Diagnostics Drawer view).
    pub fn collect_all_diagnostic_badges(&self) -> Vec<(&SpatialNode, &DiagnosticBadge)> {
        let mut badges = Vec::new();
        for node in self.nodes.values() {
            for badge in &node.badges {
                badges.push((node, badge));
            }
        }
        badges.sort_by_key(|(_, b)| match b.severity {
            DiagnosticSeverity::Critical => 0,
            DiagnosticSeverity::Warning => 1,
            DiagnosticSeverity::Info => 2,
        });
        badges
    }

    /// Bind contextual terminal session to the currently selected entity.
    pub fn get_contextual_terminal_binding(&self) -> ContextualTerminalBinding {
        let selected_id = self
            .selected_node_id
            .as_deref()
            .unwrap_or("ouros-core");

        if let Some(node) = self.nodes.get(selected_id) {
            match node.category {
                SubsystemCategory::Agent => ContextualTerminalBinding {
                    entity_id: selected_id.to_string(),
                    title: format!("Agent REPL: {}", node.label),
                    pty_command: format!(
                        "ouros-cli attach --agent {} --socket {}",
                        selected_id,
                        node.details.socket_addr.as_deref().unwrap_or("127.0.0.1:50139")
                    ),
                    target_directory: None,
                    inspection_summary: format!(
                        "State: {:?} | Context Tokens: {} | Heap: {} MB",
                        node.details.agent_state.unwrap_or(AgentState::Idle),
                        node.details.context_tokens.unwrap_or(0),
                        node.details.memory_bytes / (1024 * 1024)
                    ),
                },
                SubsystemCategory::WorkerProcess => {
                    let pid = node.details.associated_pid.unwrap_or(1);
                    ContextualTerminalBinding {
                        entity_id: selected_id.to_string(),
                        title: format!("Process Shell: {}", node.label),
                        pty_command: format!("lldb -p {pid} || top -pid {pid}"),
                        target_directory: None,
                        inspection_summary: format!(
                            "PID: {pid} | CPU: {:.1}% | RSS: {} MB",
                            node.details.cpu_pct,
                            node.details.memory_bytes / (1024 * 1024)
                        ),
                    }
                }
                SubsystemCategory::StoragePool => ContextualTerminalBinding {
                    entity_id: selected_id.to_string(),
                    title: format!("Substrate Mount: {}", node.label),
                    pty_command: "df -h && ls -la".to_string(),
                    target_directory: Some("/".to_string()),
                    inspection_summary: format!(
                        "Available Headroom: {} GB",
                        node.details.volume_available_bytes.unwrap_or(0) / (1024 * 1024 * 1024)
                    ),
                },
                _ => ContextualTerminalBinding {
                    entity_id: selected_id.to_string(),
                    title: format!("Host Console: {}", node.label),
                    pty_command: "zsh".to_string(),
                    target_directory: None,
                    inspection_summary: format!(
                        "System Cores: Active | CPU Load: {:.1}%",
                        node.details.cpu_pct
                    ),
                },
            }
        } else {
            ContextualTerminalBinding {
                entity_id: "host-cluster".to_string(),
                title: "Terminal Console".to_string(),
                pty_command: "zsh".to_string(),
                target_directory: None,
                inspection_summary: "No entity selected.".to_string(),
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use fleet_telemetry::SimulatedTelemetryProvider;
    use fleet_telemetry::TelemetryProvider;
    use ouros_adapter::OurosBrainBridge;
    use ouros_adapter::OurosAdapter;

    #[test]
    fn test_spatial_topology_construction_and_simulation() {
        let mut telemetry_provider = SimulatedTelemetryProvider::new();
        let snapshot = telemetry_provider.sample().unwrap();
        let mut brain_bridge = OurosBrainBridge::new();
        let brain_graph = brain_bridge.poll_task_graph().unwrap();

        let mut spatial_graph = RelationalTopologyGraph::new();
        spatial_graph.update_from_telemetry_and_brain(&snapshot, &brain_graph);

        assert!(spatial_graph.nodes.contains_key("host-cluster"));
        assert!(spatial_graph.nodes.contains_key("runtime-core"));
        assert!(spatial_graph.nodes.contains_key("ouros-core"));
        assert!(spatial_graph.nodes.contains_key("codex-worker"));
        assert!(spatial_graph.nodes.len() >= 4);

        // Tick simulation
        let prev_x = spatial_graph.nodes.get("ouros-core").unwrap().x;
        spatial_graph.tick_simulation(0.016);
        let next_x = spatial_graph.nodes.get("ouros-core").unwrap().x;
        assert_ne!(prev_x, next_x);

        // Sidebar hierarchy check
        let sidebar = spatial_graph.build_sidebar_hierarchy();
        assert_eq!(sidebar.id, "host-cluster");
        assert_eq!(sidebar.children.len(), 1);

        // Diagnostics check: swift-frontend is saturating CPU at 95.5% in simulated telemetry
        let badges = spatial_graph.collect_all_diagnostic_badges();
        assert!(!badges.is_empty());
        assert!(badges.iter().any(|(_, b)| b.title.contains("CPU Saturation")));

        // Terminal binding
        spatial_graph.focus_entity("ouros-core");
        let terminal = spatial_graph.get_contextual_terminal_binding();
        assert_eq!(terminal.entity_id, "ouros-core");
        assert!(terminal.pty_command.contains("ouros-cli attach"));
    }
}
