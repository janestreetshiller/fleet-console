//! Workspace controller for the FleetConsole GPUI prototype.

use crate::{
    contextual_terminal::render_contextual_terminal,
    diagnostics_drawer::render_diagnostics_drawer,
    plane_views::{
        render_execution_telemetry_plane, render_substrate_plane, render_unavailable_plane,
    },
    sidebar_view::render_sidebar_tree,
    snapshot_state::SnapshotState,
    theme::SpatialPalette,
    topography_view::render_topography_canvas,
};
use fleet_spatial::{OperationalPlane, RelationalTopologyGraph, RemediationAction};
use fleet_telemetry::{SysinfoTelemetryProvider, TelemetryProvider, TelemetrySnapshot};
use gpui::{div, prelude::*, px, Context, Render, SharedString, Window};
use ouros_adapter::AgentTaskGraph;

pub struct FleetWorkspaceApp {
    pub graph: RelationalTopologyGraph,
    pub telemetry_provider: Box<dyn TelemetryProvider>,
    pub current_telemetry: SnapshotState<TelemetrySnapshot>,
    pub current_brain_graph: AgentTaskGraph,
    pub palette: SpatialPalette,
    pub terminal_logs: Vec<String>,
}

impl FleetWorkspaceApp {
    pub fn new() -> Self {
        let mut telemetry_provider: Box<dyn TelemetryProvider> =
            Box::new(SysinfoTelemetryProvider::new());
        let current_telemetry = SnapshotState::from_result(telemetry_provider.sample());
        // The adapter currently supplies example data, not a runtime connection.
        let current_brain_graph = AgentTaskGraph::default();
        let mut graph = RelationalTopologyGraph::new();
        if let Some(snapshot) = current_telemetry.snapshot() {
            graph.update_from_telemetry_and_brain(snapshot, &current_brain_graph);
            // The spatial engine adds an illustrative daemon and inferred links.
            // Neither is observed by this shell, so do not present them as facts.
            graph.nodes.remove("runtime-core");
            graph.edges.clear();
            if let Some(host) = graph.nodes.get_mut("host-cluster") {
                host.label = telemetry_provider.hardware_profile().host_name.clone();
            }
            for node in graph.nodes.values_mut() {
                for badge in &mut node.badges {
                    badge.actions.clear();
                }
            }
            graph.selected_node_id = Some("host-cluster".to_string());
        }
        let terminal_logs =
            vec!["Inspector preview: no shell, PTY, or live log stream is connected.".to_string()];

        Self {
            graph,
            telemetry_provider,
            current_telemetry,
            current_brain_graph,
            palette: SpatialPalette::default(),
            terminal_logs,
        }
    }

    pub fn set_plane(&mut self, plane: OperationalPlane) {
        self.graph.active_plane = plane;
    }

    pub fn focus_node(&mut self, node_id: &str) {
        if self.graph.nodes.contains_key(node_id) {
            self.graph.focus_entity(node_id);
        }
    }

    pub fn handle_remediation(&mut self, action: RemediationAction) -> Result<(), String> {
        let name = match action {
            RemediationAction::CompactContext(_) => "Context compaction",
            RemediationAction::ThrottleAgent(_) => "Agent throttling",
            RemediationAction::KillProcess(_) => "Process termination",
            RemediationAction::PurgeCache(_) => "Cache cleanup",
            RemediationAction::DrainSockets(_) => "Socket draining",
            RemediationAction::RestartDaemon(_) => "Daemon restart",
        };
        let error = format!(
            "{name} unavailable. This prototype is not connected to fleetd or an agent runtime."
        );
        self.terminal_logs.push(error.clone());
        // Keep diagnostic history bounded even if a caller repeatedly requests actions.
        let excess = self.terminal_logs.len().saturating_sub(128);
        self.terminal_logs.drain(..excess);
        Err(error)
    }

    pub fn tick_physics(&mut self) {
        self.graph.tick_simulation(0.016);
    }
}

impl Render for FleetWorkspaceApp {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let palette = self.palette;
        let active_plane = self.graph.active_plane;
        let mut sidebar_hierarchy = self.graph.build_sidebar_hierarchy();
        sidebar_hierarchy.label = self.telemetry_provider.hardware_profile().host_name.clone();
        // The spatial prototype groups everything under an invented runtime core.
        // Display observed entities directly under this host instead.
        sidebar_hierarchy.children = sidebar_hierarchy
            .children
            .into_iter()
            .flat_map(|group| group.children)
            .collect();
        let terminal_binding = self.graph.get_contextual_terminal_binding();
        let all_badges = self.graph.collect_all_diagnostic_badges();

        // 1. Top Navigation Bar (Operational Plane Tabs + Host Status)
        let mut top_bar = div()
            .flex()
            .items_center()
            .justify_between()
            .px_4()
            .py_2()
            .bg(palette.bg_surface)
            .border_b_1()
            .border_color(palette.border_subtle);

        // Plane Selector Tabs
        let mut tabs = div().flex().items_center().gap_2();
        for plane in [
            OperationalPlane::Topography,
            OperationalPlane::BrainAndAgents,
            OperationalPlane::ExecutionAndTelemetry,
            OperationalPlane::Substrate,
        ] {
            let is_active = active_plane == plane;
            let title = plane.title();
            tabs = tabs.child(
                div()
                    .id(SharedString::from(format!("plane.tab.{:?}", plane)))
                    .px_3()
                    .py_1()
                    .rounded_md()
                    .text_xs()
                    .font_weight(if is_active {
                        gpui::FontWeight::BOLD
                    } else {
                        gpui::FontWeight::NORMAL
                    })
                    .cursor_pointer()
                    .when(is_active, |this| {
                        this.bg(palette.bg_card)
                            .text_color(palette.accent_cyan)
                            .border_1()
                            .border_color(palette.border_active)
                    })
                    .when(!is_active, |this| {
                        this.text_color(palette.text_muted)
                            .hover(|t| t.text_color(palette.text_bright))
                    })
                    .on_click(cx.listener(move |this, _, _window, cx| {
                        this.set_plane(plane);
                        cx.notify();
                    }))
                    .child(title),
            );
        }
        top_bar = top_bar.child(tabs);

        // Host summary and observation status; thermal pressure is not measured.
        let host_status = div()
            .flex()
            .items_center()
            .gap_3()
            .child(
                div()
                    .text_xs()
                    .text_color(palette.text_muted)
                    .child(format!(
                        "Host: {}",
                        self.telemetry_provider.hardware_profile().host_name
                    )),
            )
            .child(
                div()
                    .text_xs()
                    .px_2()
                    .py_0p5()
                    .rounded_sm()
                    .bg(palette.bg_card)
                    .text_color(palette.text_muted)
                    .child(if self.current_telemetry.snapshot().is_some() {
                        "Captured sample · refresh unavailable"
                    } else {
                        "Telemetry unavailable"
                    }),
            );
        top_bar = top_bar.child(host_status);

        // 2. Left Rail: Descriptive Topology Map Sidebar
        let sidebar = div()
            .flex()
            .flex_col()
            .w(px(260.0))
            .h_full()
            .p_3()
            .border_r_1()
            .border_color(palette.border_subtle)
            .bg(palette.bg_surface)
            .child(
                div()
                    .pb_2()
                    .text_xs()
                    .font_weight(gpui::FontWeight::BOLD)
                    .text_color(palette.text_dim)
                    .child("CAPTURED SYSTEM SAMPLE"),
            )
            .child(render_sidebar_tree(
                &sidebar_hierarchy,
                0,
                self.graph.selected_node_id.as_deref(),
                &palette,
            ));

        // 3. Center Stage: Selected Operational Plane
        let center_plane = match active_plane {
            OperationalPlane::Topography => match self.current_telemetry.snapshot() {
                Some(_) => render_topography_canvas(
                    &self.graph,
                    &palette,
                    |_action| {},
                ),
                None => render_unavailable_plane(
                    "System sample unavailable",
                    self.current_telemetry.error().unwrap_or("No measured sample is available."),
                    &palette,
                ),
            },
            OperationalPlane::BrainAndAgents => render_unavailable_plane(
                "Agent connection unavailable",
                "This prototype has no connection to the Ouros agent runtime. Agent state, context use, decisions, and logs are unavailable.",
                &palette,
            ),
            OperationalPlane::ExecutionAndTelemetry => match self.current_telemetry.snapshot() {
                Some(snapshot) => render_execution_telemetry_plane(
                    snapshot,
                    self.telemetry_provider.hardware_profile(),
                    &palette,
                ),
                None => render_unavailable_plane(
                    "Telemetry unavailable",
                    self.current_telemetry.error().unwrap_or("No measured sample is available."),
                    &palette,
                ),
            },
            OperationalPlane::Substrate => match self.current_telemetry.snapshot() {
                Some(snapshot) => render_substrate_plane(snapshot, &palette),
                None => render_unavailable_plane(
                    "Storage measurements unavailable",
                    self.current_telemetry.error().unwrap_or("No measured sample is available."),
                    &palette,
                ),
            },
        };

        // 4. Center Column (Center Stage + Bottom Diagnostics Drawer)
        let center_col = div()
            .flex()
            .flex_col()
            .flex_1()
            .h_full()
            .child(div().flex_1().relative().child(center_plane))
            .child(render_diagnostics_drawer(
                &all_badges,
                &palette,
                |_action| {},
            ));

        // 5. Right Rail: Persistent Contextual Terminal & Inspector
        let right_rail =
            render_contextual_terminal(&terminal_binding, &self.terminal_logs, &palette);

        // Root Window Workspace
        div()
            .id("fleet-gpui-workspace")
            .flex()
            .flex_col()
            .size_full()
            .bg(palette.bg_deep)
            .child(top_bar)
            .child(
                div().px_4().py_2().text_xs().text_color(palette.status_warning)
                    .child("GPUI prototype · one captured system sample · service control, agent connection, continuous sampling, and terminal input unavailable"),
            )
            .child(
                div()
                    .flex()
                    .flex_1()
                    .size_full()
                    .child(sidebar)
                    .child(center_col)
                    .child(right_rail),
            )
    }
}
