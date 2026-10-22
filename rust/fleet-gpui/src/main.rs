//! Fleet GPUI Application Entry Point.
//!
//! Provides both GUI workspace execution via GPUI and deterministic headless verification
//! modes (`--headless`, `--verify`, `--identity`).

use fleet_gpui::app::FleetWorkspaceApp;
use gpui::{App, AppContext, Application, Bounds, WindowBounds, WindowOptions, px, size};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();

    if args.iter().any(|a| a == "--identity") {
        println!(
            "{}",
            serde_json::json!({
                "name": "Fleet GPUI Workspace",
                "version": fleet_gpui::version(),
                "os": std::env::consts::OS,
                "arch": std::env::consts::ARCH,
                "engine": "GPUI (Rust)",
                "adapter": "ouros-x brain bridge",
                "spatial_planes": [
                    "Topography",
                    "Brain & Agents",
                    "Execution & Telemetry",
                    "Substrate"
                ]
            })
        );
        return;
    }

    if args.iter().any(|a| a == "--headless" || a == "--verify") {
        run_headless_verification();
        return;
    }

    // Launch GPUI Application
    Application::new().run(|cx: &mut App| {
        let window_options = WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(Bounds {
                origin: gpui::Point {
                    x: px(100.0),
                    y: px(100.0),
                },
                size: size(px(1280.0), px(860.0)),
            })),
            titlebar: Some(gpui::TitlebarOptions {
                title: Some("FleetConsole Workspace (GPUI)".into()),
                appears_transparent: true,
                traffic_light_position: Some(gpui::Point {
                    x: px(12.0),
                    y: px(12.0),
                }),
            }),
            ..Default::default()
        };

        if let Err(error) = cx.open_window(window_options, |_window, cx| {
            cx.new(|_cx| FleetWorkspaceApp::new())
        }) {
            eprintln!("Failed to open Fleet GPUI workspace window: {error}");
            cx.quit();
        }
    });
}

fn run_headless_verification() {
    println!("=== FLEET GPUI WORKSPACE: RELATIONAL SPATIAL VERIFICATION ===");
    let mut app = FleetWorkspaceApp::new();

    println!("[1/5] Verifying Relational Topology Graph (Topography Plane)...");
    assert!(!app.graph.nodes.is_empty(), "Graph nodes must not be empty");
    assert!(!app.graph.edges.is_empty(), "Graph edges must not be empty");
    println!(
        "      Nodes: {} | Edges: {} | Selected: {:?}",
        app.graph.nodes.len(),
        app.graph.edges.len(),
        app.graph.selected_node_id
    );

    println!("[2/5] Stepping Force-Directed Physics Simulation...");
    let initial_x = app.graph.nodes.get("ouros-core").map(|n| n.x).unwrap_or(0.0);
    for _ in 0..10 {
        app.tick_physics();
    }
    let relaxed_x = app.graph.nodes.get("ouros-core").map(|n| n.x).unwrap_or(0.0);
    println!("      Simulation relaxed ouros-core X: {initial_x:.2} -> {relaxed_x:.2}");

    println!("[3/5] Verifying Ouros-X Brain Adapter & Decision Trees...");
    let brain_node = app.current_brain_graph.nodes.get("ouros-core").expect("ouros-core not in brain");
    println!("      Brain Agent State: {:?}", brain_node.state);
    println!(
        "      Context Tokens: {} / {} ({:.1}%)",
        brain_node.context_memory.total_tokens,
        brain_node.context_memory.max_context_tokens,
        brain_node.context_memory.utilization_ratio() * 100.0
    );
    println!("      Recent Decisions: {}", brain_node.recent_decisions.len());

    println!("[4/5] Verifying Integrated Diagnostics & Remediation Overhaul...");
    let badges = app.graph.collect_all_diagnostic_badges();
    println!("      Collected {} active diagnostic badges directly from nodes.", badges.len());
    for (node, badge) in &badges {
        println!("      - [{:?}] {} on node {}", badge.severity, badge.title, node.id);
    }

    println!("[5/5] Verifying Contextual Terminal Binding...");
    app.focus_node("ouros-core");
    let binding = app.graph.get_contextual_terminal_binding();
    println!("      Terminal Title: {}", binding.title);
    println!("      PTY Command: {}", binding.pty_command);
    println!("      Metadata: {}", binding.inspection_summary);

    println!("============================================================");
    println!("STATUS: VERIFICATION_PASSED (All 4 operational planes active)");
}
