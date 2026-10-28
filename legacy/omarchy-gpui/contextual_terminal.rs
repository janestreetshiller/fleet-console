//! Inspector and command preview for a captured spatial entity.
//! This renderer does not attach to a PTY, shell, REPL, or live log stream.

use crate::theme::SpatialPalette;
use fleet_spatial::ContextualTerminalBinding;
use gpui::{div, prelude::*, px, AnyElement};

pub fn render_contextual_terminal(
    binding: &ContextualTerminalBinding,
    logs: &[String],
    palette: &SpatialPalette,
) -> AnyElement {
    let mut container = div()
        .id("contextual-terminal-rail")
        .flex()
        .flex_col()
        .w(px(340.0))
        .h_full()
        .border_l_1()
        .border_color(palette.border_subtle)
        .bg(palette.bg_surface);

    // Header bar
    let header = div()
        .flex()
        .flex_col()
        .p_3()
        .border_b_1()
        .border_color(palette.border_subtle)
        .gap_1()
        .child(
            div()
                .flex()
                .items_center()
                .justify_between()
                .child(
                    div()
                        .font_weight(gpui::FontWeight::BOLD)
                        .text_sm()
                        .text_color(palette.text_bright)
                        .child(format!("Inspector preview: {}", binding.title)),
                )
                .child(
                    div()
                        .text_xs()
                        .px_1p5()
                        .py_0p5()
                        .rounded_sm()
                        .bg(palette.bg_card)
                        .text_color(palette.accent_cyan)
                        .child("No PTY connected"),
                ),
        )
        .child(
            div()
                .text_xs()
                .font_family(".AppleSystemUIFontMonospaced")
                .text_color(palette.text_dim)
                .child(format!(
                    "Command preview (not run): {}",
                    binding.pty_command
                )),
        );

    container = container.child(header);

    // Inspection metadata card
    let inspector = div()
        .p_2()
        .mx_3()
        .my_2()
        .rounded_md()
        .bg(palette.bg_card)
        .border_1()
        .border_color(palette.border_subtle)
        .child(
            div()
                .text_xs()
                .text_color(palette.text_muted)
                .child(binding.inspection_summary.clone()),
        );

    container = container.child(inspector);

    // Terminal log output area
    let mut log_area = div()
        .id("terminal.log-area")
        .flex_1()
        .p_3()
        .overflow_y_scroll()
        .bg(palette.bg_deep)
        .font_family(".AppleSystemUIFontMonospaced")
        .text_xs()
        .flex()
        .flex_col()
        .gap_1();

    if logs.is_empty() {
        log_area = log_area.child(
            div()
                .text_color(palette.text_dim)
                .child("Live logs unavailable; no session is connected."),
        );
    } else {
        for line in logs {
            log_area = log_area.child(div().text_color(palette.text_bright).child(line.clone()));
        }
    }

    container = container.child(log_area);

    // Interactive prompt footer
    let prompt = div()
        .flex()
        .items_center()
        .p_2()
        .border_t_1()
        .border_color(palette.border_subtle)
        .bg(palette.bg_card)
        .gap_2()
        .child(
            div()
                .text_xs()
                .font_weight(gpui::FontWeight::BOLD)
                .text_color(palette.accent_cyan)
                .child("❯"),
        )
        .child(
            div()
                .flex_1()
                .text_xs()
                .text_color(palette.text_muted)
                .child("Terminal input unavailable in this prototype"),
        );

    container.child(prompt).into_any_element()
}
