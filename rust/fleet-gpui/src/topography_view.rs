//! Relational Topology Canvas View.
//!
//! Visualizes how agents, processes, storage pools, and memory relate in space
//! with heat scaling, edge pulsation, and direct contextual diagnostic badges.

use crate::theme::SpatialPalette;
use fleet_spatial::{
    DiagnosticSeverity, RelationalTopologyGraph, RemediationAction, SubsystemCategory,
};
use gpui::{AnyElement, SharedString, div, prelude::*, px};

pub fn render_topography_canvas<FNode, FAction>(
    graph: &RelationalTopologyGraph,
    palette: &SpatialPalette,
    on_select_node: FNode,
    on_remediate: FAction,
) -> AnyElement
where
    FNode: Fn(String) + Clone + 'static,
    FAction: Fn(RemediationAction) + Clone + 'static,
{
    let center_offset_x = 380.0 + graph.viewport.pan_x;
    let center_offset_y = 280.0 + graph.viewport.pan_y;
    let zoom = graph.viewport.zoom;

    let mut canvas_container = div()
        .id("topography-canvas-plane")
        .relative()
        .size_full()
        .overflow_hidden()
        .bg(palette.bg_deep);

    // 1. Render Edge Connectors and Relationship Badges
    for edge in &graph.edges {
        if let (Some(source_node), Some(target_node)) =
            (graph.nodes.get(&edge.source), graph.nodes.get(&edge.target))
        {
            let x1 = center_offset_x + (source_node.x * zoom);
            let y1 = center_offset_y + (source_node.y * zoom);
            let x2 = center_offset_x + (target_node.x * zoom);
            let y2 = center_offset_y + (target_node.y * zoom);

            let mid_x = (x1 + x2) / 2.0;
            let mid_y = (y1 + y2) / 2.0;

            let relation_label = match edge.relation {
                fleet_spatial::RelationKind::IpcPipe => "IPC",
                fleet_spatial::RelationKind::SharedMemory => "SHM",
                fleet_spatial::RelationKind::SocketConnection => "SOCK",
                fleet_spatial::RelationKind::ParentChild => "PROC",
                fleet_spatial::RelationKind::AgentToolLink => "LINK",
                fleet_spatial::RelationKind::StorageAccess => "IO",
            };

            let edge_color = if edge.pulse_speed > 2.0 {
                palette.status_warning
            } else {
                palette.border_subtle
            };

            // Edge relation badge in middle of edge line
            canvas_container = canvas_container.child(
                div()
                    .absolute()
                    .left(px(mid_x - 16.0))
                    .top(px(mid_y - 8.0))
                    .px_1()
                    .rounded_sm()
                    .bg(palette.bg_surface)
                    .border_1()
                    .border_color(edge_color)
                    .text_xs()
                    .text_color(palette.text_dim)
                    .child(relation_label),
            );
        }
    }

    // 2. Render Spatial Nodes
    for (node_id, node) in &graph.nodes {
        let is_selected = graph.selected_node_id.as_deref() == Some(node_id.as_str());
        let scaled_radius = (node.radius * zoom).max(18.0);
        let screen_x = center_offset_x + (node.x * zoom) - scaled_radius;
        let screen_y = center_offset_y + (node.y * zoom) - scaled_radius;

        let node_id_captured = node_id.clone();
        let select_cb = on_select_node.clone();

        let ring_color = if node.heat > 0.85 {
            palette.status_critical
        } else if node.heat > 0.50 {
            palette.status_warning
        } else {
            match node.category {
                SubsystemCategory::Agent => palette.accent_cyan,
                SubsystemCategory::ClusterHost | SubsystemCategory::RuntimeCore => {
                    palette.accent_purple
                }
                SubsystemCategory::StoragePool => palette.accent_cyan,
                SubsystemCategory::WorkerProcess => palette.text_muted,
                _ => palette.text_dim,
            }
        };

        let mut node_element = div()
            .id(SharedString::from(format!("node.canvas.{}", node.id)))
            .absolute()
            .left(px(screen_x))
            .top(px(screen_y))
            .w(px(scaled_radius * 2.0))
            .h(px(scaled_radius * 2.0))
            .rounded_full()
            .bg(palette.bg_card)
            .border_2()
            .border_color(if is_selected {
                palette.border_active
            } else {
                ring_color
            })
            .flex()
            .flex_col()
            .items_center()
            .justify_center()
            .cursor_pointer()
            .hover(|this| this.border_color(palette.border_active))
            .on_mouse_down(gpui::MouseButton::Left, move |_, _, _cx| {
                select_cb(node_id_captured.clone());
            })
            .child(
                div()
                    .text_xs()
                    .font_weight(gpui::FontWeight::BOLD)
                    .text_color(palette.text_bright)
                    .child(truncate_label(&node.label, 14)),
            );

        let sub_metric = if let Some(tokens) = node.details.context_tokens {
            format!("{}k tok", tokens / 1000)
        } else if node.details.cpu_pct > 0.0 {
            format!("{:.0}% CPU", node.details.cpu_pct)
        } else if let Some(avail) = node.details.volume_available_bytes {
            format!("{}GB free", avail / (1024 * 1024 * 1024))
        } else {
            format!("{}MB", node.details.memory_bytes / (1024 * 1024))
        };

        node_element = node_element.child(
            div()
                .text_xs()
                .text_color(palette.text_dim)
                .child(sub_metric),
        );

        canvas_container = canvas_container.child(node_element);

        // 3. Render Contextual Diagnostic Badges Pinned to Affected Node
        for badge in &node.badges {
            let badge_bg = match badge.severity {
                DiagnosticSeverity::Critical => palette.status_critical,
                DiagnosticSeverity::Warning => palette.status_warning,
                DiagnosticSeverity::Info => palette.accent_cyan,
            };

            let mut badge_elem = div()
                .absolute()
                .left(px(screen_x + scaled_radius * 1.6))
                .top(px(screen_y - 12.0))
                .p_2()
                .rounded_lg()
                .bg(palette.bg_surface)
                .border_1()
                .border_color(badge_bg)
                .flex()
                .flex_col()
                .gap_1()
                .shadow_md()
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap_1()
                        .child(
                            div()
                                .w(px(6.0))
                                .h(px(6.0))
                                .rounded_full()
                                .bg(badge_bg),
                        )
                        .child(
                            div()
                                .text_xs()
                                .font_weight(gpui::FontWeight::BOLD)
                                .text_color(palette.text_bright)
                                .child(badge.title.clone()),
                        ),
                )
                .child(
                    div()
                        .text_xs()
                        .text_color(palette.text_muted)
                        .child(badge.message.clone()),
                );

            if let Some(first_action) = badge.actions.first() {
                let action_captured = first_action.clone();
                let remediate_cb = on_remediate.clone();
                let action_title = match first_action {
                    RemediationAction::KillProcess(pid) => format!("Kill PID {pid}"),
                    RemediationAction::ThrottleAgent(_) => "Throttle Agent".to_string(),
                    RemediationAction::CompactContext(_) => "Compact Context".to_string(),
                    RemediationAction::PurgeCache(_) => "Purge Cache".to_string(),
                    RemediationAction::DrainSockets(_) => "Drain Sockets".to_string(),
                    RemediationAction::RestartDaemon(_) => "Restart Daemon".to_string(),
                };

                badge_elem = badge_elem.child(
                    div()
                        .mt_1()
                        .px_2()
                        .py_0p5()
                        .rounded_sm()
                        .bg(badge_bg)
                        .text_xs()
                        .font_weight(gpui::FontWeight::BOLD)
                        .text_color(palette.bg_deep)
                        .cursor_pointer()
                        .hover(|this| this.opacity(0.85))
                        .on_mouse_down(gpui::MouseButton::Left, move |_, _, _cx| {
                            remediate_cb(action_captured.clone());
                        })
                        .child(format!("⚡ {}", action_title)),
                );
            }

            canvas_container = canvas_container.child(badge_elem);
        }
    }

    // 4. Viewport HUD / Controls
    let hud = div()
        .absolute()
        .bottom_4()
        .left_4()
        .flex()
        .items_center()
        .gap_2()
        .p_1()
        .rounded_md()
        .bg(palette.bg_surface)
        .border_1()
        .border_color(palette.border_subtle)
        .child(
            div()
                .px_2()
                .text_xs()
                .text_color(palette.text_muted)
                .child(format!("Zoom: {:.1}x | Nodes: {}", zoom, graph.nodes.len())),
        );

    canvas_container.child(hud).into_any_element()
}

fn truncate_label(s: &str, max_len: usize) -> String {
    if s.len() > max_len {
        format!("{}…", &s[..max_len])
    } else {
        s.to_string()
    }
}
