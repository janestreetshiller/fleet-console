//! `--identity` and `--verify`.
//!
//! `--identity` is static: it reads nothing and says what this build is.
//! `--verify` performs one real controller read and two telemetry samples
//! (CPU use and network rates are differences, so the first sample alone has
//! none), then reports what was observed. Anything it did not exercise, such
//! as drawing a window or creating the status-area item, is listed as not
//! checked rather than implied.

use crate::cli::Options;
use crate::feeds::controller_config;
use fleet_ui_core::controller::display_path;
use fleet_ui_core::observe::{Feed, Metric, Phase};
use fleet_ui_core::platform::{self, HostSample, Sampler, StatusArea, Support};
use fleet_ui_core::views::{Dashboard, Inputs, Locality};
use fleet_ui_core::Controller;
use serde_json::{json, Value};
use std::sync::Arc;
use std::time::{Duration, Instant};

pub fn identity() -> Value {
    json!({
        "name": "FleetConsole GPUI client",
        "binary": "fleet-gpui",
        "version": crate::version(),
        "os": std::env::consts::OS,
        "arch": std::env::consts::ARCH,
        "ui": "gpui 0.2.2",
        "fixtures_compiled": cfg!(feature = "fixtures"),
        "data": "controller snapshots polled through fleet-proto and local telemetry from fleet-ui-core",
        "actions": "submitted to the controller only; the client never signals a process",
        "terminal": "not included: no PTY-backed terminal exists in this client",
        "accessibility": "gpui 0.2.2 exposes no platform accessibility tree; every gauge and state is also shown as text",
    })
}

fn metric(m: Metric) -> Value {
    match m.reason() {
        None => json!({"measured": true}),
        Some(reason) => json!({"measured": false, "reason": reason.label()}),
    }
}

fn locality(l: Locality) -> &'static str {
    match l {
        Locality::Local => "local",
        Locality::Remote => "remote",
        Locality::Unknown => "unknown",
    }
}

fn support(s: Support) -> &'static str {
    match s {
        Support::Measured => "measured",
        Support::NotMeasured => "not measured",
        Support::Conditional => "conditional",
    }
}

/// What one verification run observed.
pub struct Observed<'a> {
    pub controller: &'a Feed<fleet_ui_core::model::Snapshot>,
    pub controller_stale_after: Duration,
    pub sample: &'a HostSample,
    pub samples_taken: u32,
    pub socket_label: String,
    pub read_only: bool,
    pub assume_remote: bool,
    pub status_area: &'a StatusArea,
}

/// Fold an observed controller feed and telemetry sample into the report.
/// Separate from the I/O so the wording can be tested with fixtures.
pub fn report(observed: Observed<'_>) -> Value {
    let Observed {
        controller,
        controller_stale_after,
        sample,
        samples_taken,
        socket_label,
        read_only,
        assume_remote,
        status_area,
    } = observed;
    let telemetry = Feed {
        phase: Phase::Live,
        value: Some(Arc::new(sample.clone())),
        received_at: Some(sample.taken_at),
        detail: None,
        reads: u64::from(samples_taken),
    };
    let dash = Dashboard::build(&Inputs {
        controller,
        controller_stale_after,
        telemetry: &telemetry,
        telemetry_stale_after: Duration::from_secs(60),
        pending: &[],
        outcomes: &[],
        read_only,
        socket_label,
        assume_remote_controller: assume_remote,
        now: sample.taken_at,
    });
    let snapshot = controller
        .value
        .as_deref()
        .filter(|_| dash.connection.phase == Phase::Live);
    let status = match status_area {
        StatusArea::MenuBar => json!({"kind": "menu bar", "item_created": "not checked"}),
        StatusArea::StatusNotifier => json!({
            "kind": "StatusNotifierItem host present",
            "item_created": "not implemented in this client; it runs as an ordinary window"
        }),
        StatusArea::Unavailable(reason) => json!({"kind": "unavailable", "reason": reason}),
    };
    json!({
        "client": "fleet-gpui",
        "version": crate::version(),
        "os": std::env::consts::OS,
        "controller": {
            "socket": dash.connection.socket_label,
            "phase": dash.connection.phase.label(),
            "summary": dash.connection.summary,
            "detail": dash.connection.detail,
            "controller_version": snapshot.map(|s| s.daemon.version.clone()),
            "services_running": dash.header.services_running,
            "services_total": snapshot.map(|s| s.services.len()),
            "awaiting_reply": dash.header.awaiting_reply,
            "locality": locality(dash.connection.locality),
            "read_only": read_only,
        },
        "telemetry": {
            "samples": samples_taken,
            "metrics": {
                "cpu": metric(sample.cpu_pct),
                "memory": metric(sample.memory_pct),
                "disk": metric(sample.disk_pct),
                "network_download": metric(sample.net_rx_bytes_per_sec),
                "network_upload": metric(sample.net_tx_bytes_per_sec),
                "gpu": metric(sample.gpu_pct),
            },
            "process_rows": sample.processes.len(),
            "volumes": sample.volumes.len(),
            "capabilities": platform::capabilities().iter().map(|c| json!({
                "value": c.value,
                "support": support(c.support),
                "source": c.source,
            })).collect::<Vec<_>>(),
        },
        "status_area": status,
        "not_checked": [
            "window drawing and input",
            "status-area item creation",
            "service actions and replies (verify sends no mutating request)",
        ],
    })
}

/// Read the controller once and sample telemetry twice, one second apart.
pub fn run(options: &Options) -> Value {
    let config = controller_config(options);
    let socket_label = display_path(&config.socket);
    let stale_after = config.stale_after();
    let deadline = Instant::now() + config.request_timeout + Duration::from_secs(2);
    let (tx, rx) = std::sync::mpsc::channel::<()>();
    // The poller's first read starts immediately and runs while telemetry is
    // sampled on this thread.
    let controller = Controller::spawn(
        config.clone(),
        Arc::new(move || {
            let _ = tx.send(());
        }),
    );
    let mut sampler = Sampler::new();
    let _ = sampler.sample();
    std::thread::sleep(Duration::from_secs(1));
    let sample = sampler.sample();
    while controller.feed().phase == Phase::Loading {
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() {
            break;
        }
        let _ = rx.recv_timeout(left.min(Duration::from_millis(200)));
    }
    let feed = controller.feed();
    drop(controller);
    report(Observed {
        controller: &feed,
        controller_stale_after: stale_after,
        sample: &sample,
        samples_taken: 2,
        socket_label,
        read_only: config.read_only,
        assume_remote: options.remote_controller,
        status_area: &platform::status_area(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use fleet_ui_core::fixtures::{self, Scenario};

    fn fixture_report(scenario: Scenario) -> Value {
        let now = fixtures::now();
        let controller = fixtures::controller_feed(scenario, now);
        let telemetry = fixtures::telemetry_feed(Scenario::Healthy, now);
        let mut sample = (*telemetry.value.unwrap()).clone();
        sample.taken_at = now;
        report(Observed {
            controller: &controller,
            controller_stale_after: Duration::from_secs(11),
            sample: &sample,
            samples_taken: 2,
            socket_label: "~/fleetd.sock".into(),
            read_only: true,
            assume_remote: false,
            status_area: &StatusArea::Unavailable("no session bus".into()),
        })
    }

    #[test]
    fn disconnected_controller_reports_no_service_count() {
        let r = fixture_report(Scenario::Disconnected);
        assert_eq!(r["controller"]["phase"], "disconnected");
        assert!(r["controller"]["services_running"].is_null());
        assert!(r["controller"]["services_total"].is_null());
        assert!(r["controller"]["controller_version"].is_null());
        assert!(r["controller"]["detail"]
            .as_str()
            .unwrap()
            .contains("no controller socket"));
    }

    #[test]
    fn live_controller_reports_counts() {
        let r = fixture_report(Scenario::Healthy);
        assert_eq!(r["controller"]["phase"], "live");
        assert_eq!(r["controller"]["services_running"], 5);
        assert_eq!(r["controller"]["services_total"], 6);
        assert_eq!(r["controller"]["read_only"], true);
    }

    #[test]
    fn stale_or_error_controller_does_not_claim_current_counts() {
        for scenario in [Scenario::Stale, Scenario::Error] {
            let r = fixture_report(scenario);
            assert_ne!(r["controller"]["phase"], "live");
            assert!(r["controller"]["services_running"].is_null(), "{scenario:?}");
        }
    }

    #[test]
    fn unmeasured_metrics_carry_their_reason() {
        let r = fixture_report(Scenario::Healthy);
        assert_eq!(r["telemetry"]["metrics"]["cpu"]["measured"], true);
        assert_eq!(r["telemetry"]["metrics"]["gpu"]["measured"], false);
        assert_eq!(
            r["telemetry"]["metrics"]["gpu"]["reason"],
            "not measured on this platform"
        );
        assert_eq!(r["status_area"]["kind"], "unavailable");
        assert!(!r["not_checked"].as_array().unwrap().is_empty());
    }

    #[test]
    fn identity_is_static_and_names_the_build() {
        let id = identity();
        assert_eq!(id["binary"], "fleet-gpui");
        assert_eq!(id["fixtures_compiled"], cfg!(feature = "fixtures"));
        assert!(id["terminal"].as_str().unwrap().contains("no PTY"));
    }
}
