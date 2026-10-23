//! Fleet GPUI Application Entry Point.
//!
//! Provides the GPUI prototype and headless snapshot inspection
//! (`--headless`, `--verify`, `--identity`). These do not prove live integration.

use fleet_gpui::app::FleetWorkspaceApp;
use gpui::{px, size, App, AppContext, Application, Bounds, WindowBounds, WindowOptions};

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
                "adapter": "unavailable (prototype)",
                "status": "prototype; not a replacement for FleetConsole",
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
        if let Err(error) = run_headless_verification() {
            eprintln!("Snapshot unavailable: {error}");
            std::process::exit(1);
        }
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

fn run_headless_verification() -> Result<(), String> {
    let app = FleetWorkspaceApp::new();
    let snapshot = app.current_telemetry.snapshot().ok_or_else(|| {
        app.current_telemetry
            .error()
            .unwrap_or("No measured sample")
            .to_string()
    })?;
    println!(
        "{}",
        serde_json::json!({
            "status": "captured_snapshot_only",
            "sample_timestamp_seconds": snapshot.timestamp_seconds,
            "observed_processes": snapshot.processes.len(),
            "observed_storage_pools": snapshot.storage_pools.len(),
            "continuous_sampling": "unavailable",
            "daemon_connection": "unavailable",
            "agent_connection": "unavailable",
            "thermal_measurement": "unavailable",
            "terminal": "unavailable",
            "service_control": "unavailable",
            "latency_benchmark": "not measured",
            "acceptance": "This checks one system snapshot, not GUI interaction or live feature parity."
        })
    );
    Ok(())
}
