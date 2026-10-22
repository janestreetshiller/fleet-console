//! Views for the Core Operational Planes:
//! - Brain & Agents (Ouros-X Adapter Plane)
//! - Execution & Telemetry (Processes & Resources)
//! - Substrate (Storage & Volumes)

use crate::theme::SpatialPalette;
use fleet_telemetry::{HardwareProfile, TelemetrySnapshot};
use ouros_adapter::AgentTaskGraph;
use gpui::{AnyElement, div, prelude::*, px};

/// Plane 2: Brain & Agents View (Ouros-X Adapter Plane)
pub fn render_brain_agents_plane(
    brain: &AgentTaskGraph,
    palette: &SpatialPalette,
) -> AnyElement {
    let mut container = div()
        .id("brain-agents-plane")
        .flex()
        .flex_col()
        .size_full()
        .p_4()
        .gap_4()
        .overflow_scroll()
        .bg(palette.bg_deep);

    let header = div()
        .flex()
        .items_center()
        .justify_between()
        .child(
            div()
                .text_lg()
                .font_weight(gpui::FontWeight::BOLD)
                .text_color(palette.text_bright)
                .child("Brain & Agents (Ouros-X Adapter Plane)"),
        )
        .child(
            div()
                .text_xs()
                .text_color(palette.accent_cyan)
                .child(format!("Active Agents: {}", brain.nodes.len())),
        );

    container = container.child(header);

    // Cards for each active agent
    for (_agent_id, agent) in &brain.nodes {
        let state_color = match agent.state {
            ouros_adapter::AgentState::Reasoning => palette.accent_cyan,
            ouros_adapter::AgentState::ToolExecution => palette.status_warning,
            ouros_adapter::AgentState::Idle => palette.text_dim,
            ouros_adapter::AgentState::AwaitingInput => palette.accent_purple,
            ouros_adapter::AgentState::Suspended => palette.status_critical,
            ouros_adapter::AgentState::Terminated => palette.text_dim,
        };

        let mut card = div()
            .flex()
            .flex_col()
            .p_3()
            .rounded_lg()
            .bg(palette.bg_card)
            .border_1()
            .border_color(palette.border_subtle)
            .gap_2()
            .child(
                div()
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
                                    .bg(state_color),
                            )
                            .child(
                                div()
                                    .font_weight(gpui::FontWeight::BOLD)
                                    .text_sm()
                                    .text_color(palette.text_bright)
                                    .child(agent.name.clone()),
                            ),
                    )
                    .child(
                        div()
                            .text_xs()
                            .px_2()
                            .py_0p5()
                            .rounded_sm()
                            .bg(palette.bg_surface)
                            .text_color(state_color)
                            .child(format!("{:?}", agent.state)),
                    ),
            )
            .child(
                div()
                    .text_xs()
                    .text_color(palette.text_muted)
                    .child(format!("Goal: {}", agent.current_goal)),
            );

        // Context Memory & Token Budget Meters
        let token_util = agent.context_memory.utilization_ratio();
        let meter_bar = div()
            .flex()
            .flex_col()
            .gap_1()
            .child(
                div()
                    .flex()
                    .justify_between()
                    .text_xs()
                    .text_color(palette.text_dim)
                    .child(format!(
                        "Context Window: {} / {} tokens ({:.1}%)",
                        agent.context_memory.total_tokens,
                        agent.context_memory.max_context_tokens,
                        token_util * 100.0
                    ))
                    .child(format!(
                        "Heap: {} MB | Cache: {} MB",
                        agent.context_memory.working_heap_bytes / (1024 * 1024),
                        agent.context_memory.prompt_cache_bytes / (1024 * 1024)
                    )),
            )
            .child(
                div()
                    .w_full()
                    .h(px(6.0))
                    .rounded_full()
                    .bg(palette.bg_surface)
                    .child(
                        div()
                            .h_full()
                            .w(px((token_util * 280.0).max(4.0)))
                            .rounded_full()
                            .bg(if token_util > 0.8 {
                                palette.status_critical
                            } else {
                                palette.accent_cyan
                            }),
                    ),
            );

        card = card.child(meter_bar);

        // Decision Tree Trace
        if !agent.recent_decisions.is_empty() {
            let mut decisions_box = div()
                .flex()
                .flex_col()
                .gap_1()
                .p_2()
                .rounded_md()
                .bg(palette.bg_surface);

            decisions_box = decisions_box.child(
                div()
                    .text_xs()
                    .font_weight(gpui::FontWeight::BOLD)
                    .text_color(palette.text_bright)
                    .child("Recent Decision Rationale:"),
            );

            for dec in &agent.recent_decisions {
                decisions_box = decisions_box.child(
                    div()
                        .text_xs()
                        .text_color(palette.text_muted)
                        .child(format!("→ Action: {} (Confidence: {:.2})", dec.chosen_action, dec.confidence)),
                );
            }

            card = card.child(decisions_box);
        }

        container = container.child(card);
    }

    container.into_any_element()
}

/// Plane 3: Execution & Telemetry View (Processes & Resources)
pub fn render_execution_telemetry_plane(
    telemetry: &TelemetrySnapshot,
    profile: &HardwareProfile,
    palette: &SpatialPalette,
) -> AnyElement {
    let mut container = div()
        .id("execution-telemetry-plane")
        .flex()
        .flex_col()
        .size_full()
        .p_4()
        .gap_4()
        .overflow_scroll()
        .bg(palette.bg_deep);

    let header = div()
        .flex()
        .items_center()
        .justify_between()
        .child(
            div()
                .text_lg()
                .font_weight(gpui::FontWeight::BOLD)
                .text_color(palette.text_bright)
                .child("Execution & Telemetry (Processes & Hardware Topology)"),
        )
        .child(
            div()
                .text_xs()
                .text_color(palette.accent_purple)
                .child(format!("{} | {} Cores", profile.host_name, profile.logical_cores)),
        );

    container = container.child(header);

    // Compute Resource Overview Cards
    let metrics_row = div()
        .flex()
        .gap_3()
        .child(render_stat_card("Global CPU Usage", &format!("{:.1}%", telemetry.cpu_cpu_pct()), palette.accent_cyan, palette))
        .child(render_stat_card("Memory Utilized", &format!("{:.1} / {:.1} GB", (telemetry.used_memory_bytes as f32 / (1024.0*1024.0*1024.0)), (telemetry.total_memory_bytes as f32 / (1024.0*1024.0*1024.0))), palette.accent_purple, palette))
        .child(render_stat_card("Thermal Pressure", &format!("{:?}", telemetry.thermal_level), match telemetry.thermal_level {
            fleet_telemetry::ThermalLevel::Nominal => palette.status_nominal,
            fleet_telemetry::ThermalLevel::Fair => palette.status_warning,
            _ => palette.status_critical,
        }, palette));

    container = container.child(metrics_row);

    // Top processes tied to owners
    let mut proc_table = div()
        .flex()
        .flex_col()
        .gap_1()
        .p_3()
        .rounded_lg()
        .bg(palette.bg_card)
        .border_1()
        .border_color(palette.border_subtle);

    proc_table = proc_table.child(
        div()
            .flex()
            .justify_between()
            .pb_2()
            .border_b_1()
            .border_color(palette.border_subtle)
            .text_xs()
            .font_weight(gpui::FontWeight::BOLD)
            .text_color(palette.text_muted)
            .child(div().w(px(80.0)).child("PID"))
            .child(div().flex_1().child("Process / Agent Owner"))
            .child(div().w(px(70.0)).child("CPU %"))
            .child(div().w(px(90.0)).child("Memory RSS")),
    );

    for proc in telemetry.processes.iter().take(12) {
        let is_heavy = proc.cpu_pct > 80.0;
        proc_table = proc_table.child(
            div()
                .flex()
                .justify_between()
                .py_1()
                .text_xs()
                .text_color(if is_heavy { palette.status_critical } else { palette.text_bright })
                .child(div().w(px(80.0)).child(format!("{}", proc.pid)))
                .child(div().flex_1().child(proc.name.clone()))
                .child(div().w(px(70.0)).child(format!("{:.1}%", proc.cpu_pct)))
                .child(div().w(px(90.0)).child(format!("{} MB", proc.memory_rss_bytes / (1024 * 1024)))),
        );
    }

    container = container.child(proc_table);

    container.into_any_element()
}

/// Plane 4: Substrate View (Storage & Volumes)
pub fn render_substrate_plane(
    telemetry: &TelemetrySnapshot,
    palette: &SpatialPalette,
) -> AnyElement {
    let mut container = div()
        .id("substrate-plane")
        .flex()
        .flex_col()
        .size_full()
        .p_4()
        .gap_4()
        .overflow_scroll()
        .bg(palette.bg_deep);

    let header = div()
        .flex()
        .items_center()
        .justify_between()
        .child(
            div()
                .text_lg()
                .font_weight(gpui::FontWeight::BOLD)
                .text_color(palette.text_bright)
                .child("Substrate (Spatial Storage & Memory Pools)"),
        )
        .child(
            div()
                .text_xs()
                .text_color(palette.accent_cyan)
                .child(format!("Mounted Pools: {}", telemetry.storage_pools.len())),
        );

    container = container.child(header);

    for store in &telemetry.storage_pools {
        let used_bytes = store.total_bytes.saturating_sub(store.available_bytes);
        let used_ratio = if store.total_bytes > 0 {
            used_bytes as f32 / store.total_bytes as f32
        } else {
            0.0
        };

        let card = div()
            .flex()
            .flex_col()
            .p_3()
            .rounded_lg()
            .bg(palette.bg_card)
            .border_1()
            .border_color(palette.border_subtle)
            .gap_2()
            .child(
                div()
                    .flex()
                    .justify_between()
                    .child(
                        div()
                            .font_weight(gpui::FontWeight::BOLD)
                            .text_sm()
                            .text_color(palette.text_bright)
                            .child(format!("Mount: {}", store.mount_point)),
                    )
                    .child(
                        div()
                            .text_xs()
                            .text_color(palette.text_dim)
                            .child(format!("FS: {}", store.filesystem)),
                    ),
            )
            .child(
                div()
                    .flex()
                    .justify_between()
                    .text_xs()
                    .text_color(palette.text_muted)
                    .child(format!(
                        "{:.1} GB used / {:.1} GB total ({:.1}%)",
                        used_bytes as f32 / (1024.0*1024.0*1024.0),
                        store.total_bytes as f32 / (1024.0*1024.0*1024.0),
                        used_ratio * 100.0
                    ))
                    .child(format!(
                        "{:.1} GB headroom remaining",
                        store.available_bytes as f32 / (1024.0*1024.0*1024.0)
                    )),
            )
            .child(
                div()
                    .w_full()
                    .h(px(8.0))
                    .rounded_full()
                    .bg(palette.bg_surface)
                    .child(
                        div()
                            .h_full()
                            .w(px((used_ratio * 320.0).max(4.0)))
                            .rounded_full()
                            .bg(if used_ratio > 0.85 {
                                palette.status_critical
                            } else {
                                palette.accent_cyan
                            }),
                    ),
            );

        container = container.child(card);
    }

    container.into_any_element()
}

fn render_stat_card(
    label: &str,
    value: &str,
    accent: gpui::Hsla,
    palette: &SpatialPalette,
) -> AnyElement {
    div()
        .flex_1()
        .flex()
        .flex_col()
        .p_3()
        .rounded_lg()
        .bg(palette.bg_card)
        .border_1()
        .border_color(palette.border_subtle)
        .child(div().text_xs().text_color(palette.text_muted).child(label.to_string()))
        .child(div().text_lg().font_weight(gpui::FontWeight::BOLD).text_color(accent).child(value.to_string()))
        .into_any_element()
}

trait TelemetrySnapshotExt {
    fn cpu_cpu_pct(&self) -> f32;
}

impl TelemetrySnapshotExt for TelemetrySnapshot {
    fn cpu_cpu_pct(&self) -> f32 {
        self.cpu_usage_pct
    }
}
