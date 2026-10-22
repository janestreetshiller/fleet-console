//! FleetConsole GPUI Main Workspace Application Controller.

use crate::{
    contextual_terminal::render_contextual_terminal,
    diagnostics_drawer::render_diagnostics_drawer,
    plane_views::{
        render_brain_agents_plane, render_execution_telemetry_plane, render_substrate_plane,
    },
    sidebar_view::render_sidebar_tree,
    theme::SpatialPalette,
    topography_view::render_topography_canvas,
};
use fleet_spatial::{OperationalPlane, RelationalTopologyGraph, RemediationAction};
use fleet_telemetry::{
    SimulatedTelemetryProvider, SysinfoTelemetryProvider, TelemetryProvider, TelemetrySnapshot,
};
use gpui::{Context, Render, SharedString, Window, div, prelude::*, px};
use ouros_adapter::{AgentTaskGraph, OurosAdapter, OurosBrainBridge};

pub struct FleetWorkspaceApp {
    pub graph: RelationalTopologyGraph,
    pub telemetry_provider: Box<dyn TelemetryProvider>,
    pub current_telemetry: TelemetrySnapshot,
    pub brain_bridge: OurosBrainBridge,
    pub current_brain_graph: AgentTaskGraph,
    pub palette: SpatialPalette,
    pub terminal_logs: Vec<String>,
}

impl FleetWorkspaceApp {
    pub fn new() -> Self {
        let mut telemetry_provider: Box<dyn TelemetryProvider> =
            Box::new(SysinfoTelemetryProvider::new());
        let current_telemetry = telemetry_provider
            .sample()
            .unwrap_or_else(|_| SimulatedTelemetryProvider::new().current_snapshot);

        let mut brain_bridge = OurosBrainBridge::new();
        let current_brain_graph = brain_bridge
            .poll_task_graph()
            .unwrap_or_else(|_| AgentTaskGraph::default());

        let mut graph = RelationalTopologyGraph::new();
        graph.update_from_telemetry_and_brain(&current_telemetry, &current_brain_graph);

        let terminal_logs = brain_bridge.stream_logs("ouros-core");

        Self {
            graph,
            telemetry_provider,
            current_telemetry,
            brain_bridge,
            current_brain_graph,
            palette: SpatialPalette::default(),
            terminal_logs,
        }
    }

    pub fn set_plane(&mut self, plane: OperationalPlane) {
        self.graph.active_plane = plane;
    }

    pub fn focus_node(&mut self, node_id: &str) {
        self.graph.focus_entity(node_id);
        self.terminal_logs = self.brain_bridge.stream_logs(node_id);
    }

    pub fn handle_remediation(&mut self, action: RemediationAction) {
        match action {
            RemediationAction::CompactContext(ref agent_id) => {
                let _ = self.brain_bridge.trigger_remediation(agent_id, "CompactContext");
                if let Ok(graph) = self.brain_bridge.poll_task_graph() {
                    self.current_brain_graph = graph;
                    self.graph
                        .update_from_telemetry_and_brain(&self.current_telemetry, &self.current_brain_graph);
                }
            }
            RemediationAction::ThrottleAgent(ref agent_id) => {
                let _ = self.brain_bridge.trigger_remediation(agent_id, "ThrottleAgent");
                if let Ok(graph) = self.brain_bridge.poll_task_graph() {
                    self.current_brain_graph = graph;
                    self.graph
                        .update_from_telemetry_and_brain(&self.current_telemetry, &self.current_brain_graph);
                }
            }
            RemediationAction::KillProcess(pid) => {
                self.terminal_logs.push(format!("[remediation] Kill signal SIGTERM sent to PID {pid}"));
            }
            _ => {
                self.terminal_logs.push(format!("[remediation] Executed action: {:?}", action));
            }
        }
    }

    pub fn tick_physics(&mut self) {
        self.graph.tick_simulation(0.016);
    }
}

impl Render for FleetWorkspaceApp {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let palette = self.palette;
        let active_plane = self.graph.active_plane;
        let sidebar_hierarchy = self.graph.build_sidebar_hierarchy();
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

        // Host Summary / Thermal Badge
        let host_status = div()
            .flex()
            .items_center()
            .gap_3()
            .child(
                div()
                    .text_xs()
                    .text_color(palette.text_muted)
                    .child(format!("Host: {}", self.telemetry_provider.hardware_profile().host_name)),
            )
            .child(
                div()
                    .text_xs()
                    .px_2()
                    .py_0p5()
                    .rounded_sm()
                    .bg(match self.current_telemetry.thermal_level {
                        fleet_telemetry::ThermalLevel::Nominal => palette.status_nominal,
                        fleet_telemetry::ThermalLevel::Fair => palette.status_warning,
                        _ => palette.status_critical,
                    })
                    .text_color(palette.bg_deep)
                    .font_weight(gpui::FontWeight::BOLD)
                    .child(format!("{:?}", self.current_telemetry.thermal_level)),
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
                    .child("TOPOLOGY MINI-MAP"),
            )
            .child(render_sidebar_tree(
                &sidebar_hierarchy,
                0,
                self.graph.selected_node_id.as_deref(),
                &palette,
                |_node_id| {},
            ));

        // 3. Center Stage: Selected Operational Plane
        let center_plane = match active_plane {
            OperationalPlane::Topography => render_topography_canvas(
                &self.graph,
                &palette,
                |_selected_id| {},
                |_action| {},
            ),
            OperationalPlane::BrainAndAgents => {
                render_brain_agents_plane(&self.current_brain_graph, &palette)
            }
            OperationalPlane::ExecutionAndTelemetry => render_execution_telemetry_plane(
                &self.current_telemetry,
                self.telemetry_provider.hardware_profile(),
                &palette,
            ),
            OperationalPlane::Substrate => {
                render_substrate_plane(&self.current_telemetry, &palette)
            }
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
        let right_rail = render_contextual_terminal(
            &terminal_binding,
            &self.terminal_logs,
            &palette,
        );

        // Root Window Workspace
        div()
            .id("fleet-gpui-workspace")
            .flex()
            .flex_col()
            .size_full()
            .bg(palette.bg_deep)
            .child(top_bar)
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
