//! Descriptive Topology Map Sidebar.
//!
//! Replaces static tab buttons with a live, zoomable structural tree:
//! Cluster / Host -> Runtime Core -> Active Agents -> Worker Processes -> Memory & IPC Links
//! with telemetry-driven status glow and direct spatial focus navigation.

use crate::theme::SpatialPalette;
use fleet_spatial::{SubsystemCategory, TopologyHierarchyNode};
use gpui::{AnyElement, SharedString, div, prelude::*, px};

pub fn render_sidebar_tree<F>(
    node: &TopologyHierarchyNode,
    depth: usize,
    selected_id: Option<&str>,
    palette: &SpatialPalette,
    on_select: F,
) -> AnyElement
where
    F: Fn(String) + Clone + 'static,
{
    let is_selected = selected_id == Some(node.id.as_str());
    let indent = px((depth as f32) * 14.0);

    let glow_color = if node.glow_intensity > 0.8 {
        palette.status_critical
    } else if node.glow_intensity > 0.5 {
        palette.status_warning
    } else {
        match node.category {
            SubsystemCategory::Agent => palette.accent_cyan,
            SubsystemCategory::ClusterHost | SubsystemCategory::RuntimeCore => palette.accent_purple,
            SubsystemCategory::StoragePool => palette.accent_cyan,
            SubsystemCategory::WorkerProcess => palette.text_muted,
            _ => palette.text_dim,
        }
    };

    let icon = match node.category {
        SubsystemCategory::ClusterHost => "⬡",
        SubsystemCategory::RuntimeCore => "◈",
        SubsystemCategory::Agent => "●",
        SubsystemCategory::WorkerProcess => "⚡",
        SubsystemCategory::StoragePool => "■",
        SubsystemCategory::MemoryPool => "▫",
        SubsystemCategory::SocketEndpoint => "⇌",
    };

    let node_id_for_click = node.id.clone();
    let click_cb = on_select.clone();

    let mut row = div()
        .id(SharedString::from(format!("sidebar.node.{}", node.id)))
        .flex()
        .items_center()
        .gap_2()
        .py_1()
        .px_2()
        .ml(indent)
        .rounded_md()
        .cursor_pointer()
        .when(is_selected, |this| {
            this.bg(palette.bg_card).border_1().border_color(palette.border_active)
        })
        .hover(|this| this.bg(palette.bg_card))
        .on_mouse_down(gpui::MouseButton::Left, move |_, _, _cx| {
            click_cb(node_id_for_click.clone());
        })
        .child(
            div()
                .text_sm()
                .text_color(glow_color)
                .child(icon),
        )
        .child(
            div()
                .flex_1()
                .text_xs()
                .font_weight(if is_selected { gpui::FontWeight::BOLD } else { gpui::FontWeight::NORMAL })
                .text_color(if is_selected { palette.text_bright } else { palette.text_muted })
                .child(node.label.clone()),
        );

    // Glow indicator dot
    if node.glow_intensity > 0.25 {
        row = row.child(
            div()
                .w(px(6.0))
                .h(px(6.0))
                .rounded_full()
                .bg(glow_color),
        );
    }

    let mut container = div().flex().flex_col().child(row);

    for child in &node.children {
        container = container.child(render_sidebar_tree(
            child,
            depth + 1,
            selected_id,
            palette,
            on_select.clone(),
        ));
    }

    container.into_any_element()
}
