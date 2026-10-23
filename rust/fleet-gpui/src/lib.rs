//! Fleet GPUI Workspace Library.
//!
//! Provides a prototype workspace with captured system measurements.
//! Live controller, agent, and terminal connections remain unavailable.

pub mod app;
pub mod contextual_terminal;
pub mod diagnostics_drawer;
pub mod plane_views;
pub mod sidebar_view;
pub mod snapshot_state;
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
        // Prototype construction must not invent a daemon or agent connection.
        assert!(app.current_brain_graph.nodes.is_empty());
        assert!(!app.graph.nodes.contains_key("runtime-core"));
        assert!(!app.graph.nodes.contains_key("ouros-core"));
        assert!(app.graph.edges.is_empty());
        assert!(app
            .graph
            .nodes
            .values()
            .all(|node| node.badges.iter().all(|badge| badge.actions.is_empty())));

        // Switch to Brain & Agents
        app.set_plane(OperationalPlane::BrainAndAgents);
        assert_eq!(app.graph.active_plane, OperationalPlane::BrainAndAgents);

        // Switch to Execution & Telemetry
        app.set_plane(OperationalPlane::ExecutionAndTelemetry);
        assert_eq!(
            app.graph.active_plane,
            OperationalPlane::ExecutionAndTelemetry
        );

        // Switch to Substrate
        app.set_plane(OperationalPlane::Substrate);
        assert_eq!(app.graph.active_plane, OperationalPlane::Substrate);

        // Focus node
        app.focus_node("unobserved-agent");
        assert_ne!(
            app.graph.selected_node_id.as_deref(),
            Some("unobserved-agent")
        );

        // Remediation trigger
        let result =
            app.handle_remediation(RemediationAction::CompactContext("ouros-core".to_string()));
        assert!(result.is_err());
        assert!(app.current_brain_graph.nodes.is_empty());
        let result = app.handle_remediation(RemediationAction::KillProcess(1001));
        assert!(result.is_err());
        assert!(app
            .terminal_logs
            .iter()
            .all(|line| !line.contains("SIGTERM sent")));
        for _ in 0..150 {
            assert!(app
                .handle_remediation(RemediationAction::KillProcess(1001))
                .is_err());
        }
        assert_eq!(app.terminal_logs.len(), 128);

        // Physics tick
        app.tick_physics();
    }
}
