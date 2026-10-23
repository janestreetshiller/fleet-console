//! Diagnostics from a captured sample. The prototype clears action lists until
//! controller-backed remediation is connected.

use crate::theme::SpatialPalette;
use fleet_spatial::{DiagnosticBadge, DiagnosticSeverity, RemediationAction, SpatialNode};
use gpui::{div, prelude::*, px, AnyElement};

pub fn render_diagnostics_drawer<F>(
    badges: &[(&SpatialNode, &DiagnosticBadge)],
    palette: &SpatialPalette,
    on_remediate: F,
) -> AnyElement
where
    F: Fn(RemediationAction) + Clone + 'static,
{
    let count = badges.len();
    let has_critical = badges
        .iter()
        .any(|(_, b)| b.severity == DiagnosticSeverity::Critical);

    let mut drawer = div()
        .id("diagnostics-drawer")
        .flex()
        .flex_col()
        .border_t_1()
        .border_color(palette.border_subtle)
        .bg(palette.bg_surface)
        .p_3()
        .gap_2();

    let header = div()
        .flex()
        .items_center()
        .justify_between()
        .child(
            div()
                .flex()
                .items_center()
                .gap_2()
                .child(
                    div()
                        .w(px(8.0))
                        .h(px(8.0))
                        .rounded_full()
                        .bg(if has_critical {
                            palette.status_critical
                        } else if count > 0 {
                            palette.status_warning
                        } else {
                            palette.text_dim
                        }),
                )
                .child(
                    div()
                        .font_weight(gpui::FontWeight::BOLD)
                        .text_xs()
                        .text_color(palette.text_bright)
                        .child(format!("Integrated Diagnostics ({count} Active Warnings)")),
                ),
        )
        .child(
            div()
                .text_xs()
                .text_color(palette.text_dim)
                .child(if count == 0 {
                    "Service and agent health unavailable"
                } else {
                    "Captured observations; controls unavailable"
                }),
        );

    drawer = drawer.child(header);

    if badges.is_empty() {
        drawer = drawer.child(div().text_xs().text_color(palette.text_dim).child(
            "No warnings in this captured sample. Service and agent health have not been checked.",
        ));
    } else {
        let mut list = div()
            .id("diagnostics.badge-list")
            .flex()
            .gap_2()
            .overflow_x_scroll();

        for (node, badge) in badges {
            let badge_color = match badge.severity {
                DiagnosticSeverity::Critical => palette.status_critical,
                DiagnosticSeverity::Warning => palette.status_warning,
                DiagnosticSeverity::Info => palette.accent_cyan,
            };

            let mut badge_card = div()
                .flex()
                .flex_col()
                .p_2()
                .rounded_md()
                .bg(palette.bg_card)
                .border_1()
                .border_color(badge_color)
                .gap_1()
                .min_w(px(240.0))
                .child(
                    div()
                        .flex()
                        .items_center()
                        .justify_between()
                        .child(
                            div()
                                .font_weight(gpui::FontWeight::BOLD)
                                .text_xs()
                                .text_color(palette.text_bright)
                                .child(badge.title.clone()),
                        )
                        .child(
                            div()
                                .text_xs()
                                .text_color(palette.text_dim)
                                .child(node.label.clone()),
                        ),
                )
                .child(
                    div()
                        .text_xs()
                        .text_color(palette.text_muted)
                        .child(badge.message.clone()),
                );

            if let Some(action) = badge.actions.first() {
                let action_captured = action.clone();
                let remediate_cb = on_remediate.clone();
                let label = match action {
                    RemediationAction::KillProcess(pid) => format!("Kill PID {pid}"),
                    RemediationAction::ThrottleAgent(_) => "Throttle Agent".to_string(),
                    RemediationAction::CompactContext(_) => "Compact Context".to_string(),
                    RemediationAction::PurgeCache(_) => "Purge Cache".to_string(),
                    RemediationAction::DrainSockets(_) => "Drain Sockets".to_string(),
                    RemediationAction::RestartDaemon(_) => "Restart Daemon".to_string(),
                };

                badge_card = badge_card.child(
                    div()
                        .mt_1()
                        .px_2()
                        .py_0p5()
                        .rounded_sm()
                        .bg(badge_color)
                        .text_xs()
                        .font_weight(gpui::FontWeight::BOLD)
                        .text_color(palette.bg_deep)
                        .cursor_pointer()
                        .hover(|this| this.opacity(0.85))
                        .on_mouse_down(gpui::MouseButton::Left, move |_, _, _cx| {
                            remediate_cb(action_captured.clone());
                        })
                        .child(format!("⚡ {}", label)),
                );
            }

            list = list.child(badge_card);
        }

        drawer = drawer.child(list);
    }

    drawer.into_any_element()
}
