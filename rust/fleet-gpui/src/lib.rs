//! Fleet GPUI Workspace Library.
//!
//! Provides the GPUI-driven workspace, relational spatial mapping,
//! Ouros-X brain adapter integration, and OS-agnostic telemetry views.

pub mod app;
pub mod contextual_terminal;
pub mod diagnostics_drawer;
pub mod plane_views;
pub mod sidebar_view;
pub mod theme;
pub mod topography_view;

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

#[cfg(test)]
mod tests {
    use super::*;
    use app::FleetWorkspaceApp;
    use fleet_spatial::{OperationalPlane, RemediationAction};

    #[test]
    fn test_app_initialization_and_planes() {
        let mut app = FleetWorkspaceApp::new();
        assert_eq!(app.graph.active_plane, OperationalPlane::Topography);
        assert!(!app.graph.nodes.is_empty());
        assert!(!app.graph.edges.is_empty());

        // Switch to Brain & Agents
        app.set_plane(OperationalPlane::BrainAndAgents);
        assert_eq!(app.graph.active_plane, OperationalPlane::BrainAndAgents);

        // Switch to Execution & Telemetry
        app.set_plane(OperationalPlane::ExecutionAndTelemetry);
        assert_eq!(app.graph.active_plane, OperationalPlane::ExecutionAndTelemetry);

        // Switch to Substrate
        app.set_plane(OperationalPlane::Substrate);
        assert_eq!(app.graph.active_plane, OperationalPlane::Substrate);

        // Focus node
        app.focus_node("ouros-core");
        assert_eq!(app.graph.selected_node_id.as_deref(), Some("ouros-core"));

        // Remediation trigger
        app.handle_remediation(RemediationAction::CompactContext("ouros-core".to_string()));

        // Physics tick
        app.tick_physics();
    }
}
