//! Synthetic controller snapshots and host samples.
//!
//! Compiled only for tests and with the `fixtures` feature, which capture and
//! screenshot builds enable and release builds do not. Every name, pid, path
//! and number here is invented. The controller version is `MARKER`, so a
//! capture made from fixtures says so on screen, and a release binary that
//! contains the marker string has fixtures compiled in and fails the check in
//! `Scripts/verify-rust-clients.sh`.

use crate::model::{decode_snapshot, Snapshot};
use crate::observe::{Feed, Metric, Phase, Reason};
use crate::platform::{HostSample, ProcessRow, Volume};
use std::sync::Arc;
use std::time::{Duration, SystemTime};

pub const MARKER: &str = "synthetic-fixture-4c1e";

/// The fixed clock fixtures are built around: 2027-01-15 09:20 UTC.
pub fn now() -> SystemTime {
    SystemTime::UNIX_EPOCH + Duration::from_secs(1_800_004_800)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Scenario {
    Loading,
    Healthy,
    Warning,
    Critical,
    Stale,
    Disconnected,
    Error,
    /// Far more rows than any list keeps, to exercise the bounds.
    Flood,
}

impl Scenario {
    pub const ALL: [Scenario; 8] = [
        Self::Loading,
        Self::Healthy,
        Self::Warning,
        Self::Critical,
        Self::Stale,
        Self::Disconnected,
        Self::Error,
        Self::Flood,
    ];

    pub fn name(self) -> &'static str {
        match self {
            Self::Loading => "loading",
            Self::Healthy => "healthy",
            Self::Warning => "warning",
            Self::Critical => "critical",
            Self::Stale => "stale",
            Self::Disconnected => "disconnected",
            Self::Error => "error",
            Self::Flood => "flood",
        }
    }

    pub fn parse(name: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|s| s.name() == name)
    }
}

fn epoch(now: SystemTime) -> f64 {
    crate::observe::epoch_seconds(now)
}

fn service(
    id: &str,
    name: &str,
    owner: &str,
    state: &str,
    pid: Option<i32>,
    started_ago: f64,
    now: f64,
) -> serde_json::Value {
    let healthy = state == "healthy";
    serde_json::json!({
        "id": format!("{id}-0000-4000-8000-000000000000"),
        "friendlyName": name,
        "ownerAgent": owner,
        "purpose": format!("{name} for the fixture workspace"),
        "command": ["/usr/local/bin/example", "--serve"],
        "cwd": "/srv/example/project",
        "pid": pid,
        "pgid": pid,
        "declaredPorts": [8080],
        "startedAt": now - started_ago,
        "leaseExpiresAt": now + 1_800.0,
        "leaseTTLSec": 3_600.0,
        "state": state,
        "health": {"kind": if healthy { "http" } else { "none" }, "target": if healthy { "http://127.0.0.1:8080/health" } else { "" }},
        "evidence": {
            "processExists": pid.is_some(),
            "listeningPorts": if pid.is_some() { vec![8080] } else { vec![] },
            "portScanRan": true,
            "healthCheckRan": healthy,
            "healthPassed": if healthy { serde_json::json!(true) } else { serde_json::Value::Null },
            "healthLatencyMs": if healthy { serde_json::json!(12.0) } else { serde_json::Value::Null },
            "checkedAt": now - 3.0
        },
        "resources": {"cpuPct": pid.map(|p| f64::from(p % 23)), "memMB": pid.map(|p| f64::from(p % 900) + 40.0), "processCount": 2},
        "restartCount": if state == "unhealthy" { 3 } else { 0 },
        "updatedAt": now - 2.0
    })
}

fn snapshot_json(scenario: Scenario, now: f64) -> serde_json::Value {
    let mut services = vec![
        service(
            "a1",
            "api-gateway",
            "codex-3",
            "unhealthy",
            Some(4119),
            40.0,
            now,
        ),
        service(
            "b2",
            "render-studio",
            "codex-1",
            "healthy",
            Some(3302),
            273_600.0,
            now,
        ),
        service(
            "c3",
            "llama-serve",
            "codex-1",
            "running",
            Some(2210),
            522_000.0,
            now,
        ),
        service(
            "d4",
            "n8n",
            "agent-ops",
            "healthy",
            Some(2218),
            522_000.0,
            now,
        ),
        service(
            "e5",
            "drive-sync",
            "agent-ops",
            "crashed",
            None,
            9_000.0,
            now,
        ),
    ];
    let mut claimed = service(
        "f6",
        "notebook",
        "codex-1",
        "running",
        Some(5120),
        7_200.0,
        now,
    );
    claimed["claimed"] = serde_json::json!(true);
    services.push(claimed);
    if scenario == Scenario::Flood {
        for i in 0..900 {
            services.push(service(
                &format!("{i:08x}"),
                &format!("worker-{i}"),
                "agent-flood",
                "running",
                Some(10_000 + i),
                60.0,
                now,
            ));
        }
    }

    let mut messages = vec![
        serde_json::json!({"id": 41, "agent": "codex-3", "serviceID": "a1-0000-4000-8000-000000000000", "serviceName": "api-gateway",
                           "kind": "status", "body": "read fleetctl logs api-gateway --tail 200", "createdAt": now - 420.0, "needsReply": false}),
        serde_json::json!({"id": 42, "agent": "codex-3", "serviceID": "a1-0000-4000-8000-000000000000", "serviceName": "api-gateway",
                           "kind": "status", "body": "port 8443 already bound by pid 3990", "createdAt": now - 300.0, "needsReply": false}),
        serde_json::json!({"id": 43, "agent": "codex-3", "serviceID": "a1-0000-4000-8000-000000000000", "serviceName": "api-gateway",
                           "kind": "question", "body": "restart api-gateway after pid 3990 releases port 8443?", "createdAt": now - 240.0, "needsReply": true}),
    ];
    if scenario == Scenario::Flood {
        for i in 0..400 {
            messages.push(serde_json::json!({"id": 1_000 + i, "agent": "agent-flood", "kind": "status",
                                             "body": format!("status {i}"), "createdAt": now - 10_000.0 + f64::from(i), "needsReply": false}));
        }
    }

    let (node_c_cpu, node_c_gpu) = match scenario {
        Scenario::Warning => (82.0, 93.0),
        Scenario::Critical => (97.0, 88.0),
        _ => (34.0, 12.0),
    };
    let devices = serde_json::json!([
        {"id": "dev-b", "name": "node-b", "model": "workstation",
         "evidence": {"icmpOK": true, "tcpOK": true, "checkedAt": now - 5.0, "isSelf": false},
         "remoteServices": [service("r1", "llm-batch", "codex-2", "healthy", Some(812), 3_600.0, now)],
         "metrics": {"cpuPct": 58.0, "memUsedGB": 14.0, "memTotalGB": 32.0, "diskUsedGB": 640.0, "diskTotalGB": 1000.0, "gpuPct": 71.0, "collectedAt": now - 6.0}},
        {"id": "dev-c", "name": "node-c", "model": "workstation",
         "evidence": {"icmpOK": true, "tcpOK": true, "checkedAt": now - 5.0, "isSelf": false},
         "remoteServices": [],
         "metrics": {"cpuPct": node_c_cpu, "memUsedGB": 25.0, "memTotalGB": 32.0, "diskUsedGB": 710.0, "diskTotalGB": 1000.0, "gpuPct": node_c_gpu, "collectedAt": now - 4.0}},
        {"id": "dev-e", "name": "node-e", "model": "laptop",
         "evidence": {"icmpOK": false, "tcpOK": false, "checkedAt": now - 5.0, "isSelf": false},
         "lastReachableAt": now - 86_400.0,
         "metrics": {"diskUsedGB": 550.0, "diskTotalGB": 1000.0, "collectedAt": now - 86_400.0}}
    ]);

    serde_json::json!({
        "generatedAt": now,
        "daemon": {"version": MARKER, "pid": 902, "startedAt": now - 530_000.0, "lastTickAt": now - 2.0,
                   "tickIntervalSec": 5.0, "socketPath": "/srv/example/fleetd.sock"},
        "services": services,
        "unmanaged": [{"id": "41822:sig", "pid": 41822, "command": "node", "commandLine": "node", "user": "example",
                        "ports": [5173], "firstSeen": now - 600.0, "lastSeen": now - 2.0, "reason": "devServerShape"}],
        "devices": devices,
        "attention": [
            {"id": "svc-a1", "severity": "critical", "title": "api-gateway is unhealthy",
             "detail": "health check failed 3 times", "serviceID": "a1-0000-4000-8000-000000000000", "since": now - 40.0},
            {"id": "svc-e5", "severity": "warning", "title": "drive-sync crashed",
             "detail": "exited with status 1", "serviceID": "e5-0000-4000-8000-000000000000", "since": now - 9_000.0}
        ],
        "recentEvents": [],
        "messages": messages,
        "sessions": [
            {"id": "sess-1", "tool": "codex-3", "pid": 6110, "project": "/srv/example/gateway", "startedAt": now - 840.0,
             "cpuPct": 6.0, "memMB": 410.0, "previewTurn": "tool", "previewAt": now - 30.0, "preview": "fleetctl logs api-gateway"}
        ]
    })
}

pub fn snapshot(scenario: Scenario, now: SystemTime) -> Snapshot {
    decode_snapshot(snapshot_json(scenario, epoch(now))).expect("fixture snapshot decodes")
}

pub fn controller_feed(scenario: Scenario, now: SystemTime) -> Feed<Snapshot> {
    let value = Some(Arc::new(snapshot(scenario, now)));
    match scenario {
        Scenario::Loading => Feed::default(),
        Scenario::Disconnected => Feed {
            phase: Phase::Disconnected,
            value: None,
            received_at: None,
            detail: Some(
                "no controller socket at ~/Library/Application Support/FleetConsole/fleetd.sock"
                    .into(),
            ),
            reads: 0,
        },
        Scenario::Error => Feed {
            phase: Phase::Error,
            value,
            received_at: Some(now - Duration::from_secs(4)),
            detail: Some("controller did not answer before the deadline".into()),
            reads: 12,
        },
        Scenario::Stale => Feed {
            phase: Phase::Live,
            value,
            received_at: Some(now - Duration::from_secs(45)),
            detail: None,
            reads: 30,
        },
        _ => Feed {
            phase: Phase::Live,
            value,
            received_at: Some(now - Duration::from_secs(1)),
            detail: None,
            reads: 30,
        },
    }
}

/// A host sample; `seed` varies the numbers for history.
pub fn host_sample(seed: f64) -> HostSample {
    host_sample_for(Scenario::Healthy, seed, now())
}

fn host_sample_for(scenario: Scenario, seed: f64, taken_at: SystemTime) -> HostSample {
    let (cpu, mem_used, disk_free) = match scenario {
        Scenario::Warning => (78.0, 26.0, 180.0),
        Scenario::Critical => (96.0, 30.5, 40.0),
        _ => (24.0 + (seed % 7.0), 14.2, 410.0),
    };
    let gib = 1024.0 * 1024.0 * 1024.0;
    let mem_total = 32.0;
    let disk_total = 994.7;
    let mut processes = vec![
        ProcessRow {
            pid: 1,
            ppid: None,
            name: "init".into(),
            cpu_pct: Metric::Measured(0.1),
            rss_bytes: 12 << 20,
            start_time: 1,
        },
        ProcessRow {
            pid: 902,
            ppid: Some(1),
            name: "fleetd".into(),
            cpu_pct: Metric::Measured(1.0),
            rss_bytes: 88 << 20,
            start_time: 2,
        },
        ProcessRow {
            pid: 4119,
            ppid: Some(902),
            name: "api-gateway".into(),
            cpu_pct: Metric::Measured(12.0),
            rss_bytes: 1_200 << 20,
            start_time: 3,
        },
        ProcessRow {
            pid: 4120,
            ppid: Some(4119),
            name: "node".into(),
            cpu_pct: Metric::Measured(8.0),
            rss_bytes: 640 << 20,
            start_time: 4,
        },
        ProcessRow {
            pid: 4121,
            ppid: Some(4119),
            name: "node".into(),
            cpu_pct: Metric::Measured(3.0),
            rss_bytes: 590 << 20,
            start_time: 4,
        },
        ProcessRow {
            pid: 3302,
            ppid: Some(902),
            name: "render-studio".into(),
            cpu_pct: Metric::Measured(4.0),
            rss_bytes: 900 << 20,
            start_time: 5,
        },
        ProcessRow {
            pid: 6100,
            ppid: Some(1),
            name: "zsh".into(),
            cpu_pct: Metric::Measured(0.0),
            rss_bytes: 6 << 20,
            start_time: 6,
        },
        ProcessRow {
            pid: 6110,
            ppid: Some(6100),
            name: "codex".into(),
            cpu_pct: Metric::Measured(6.0),
            rss_bytes: 410 << 20,
            start_time: 7,
        },
        ProcessRow {
            pid: 7001,
            ppid: Some(1),
            name: "browser".into(),
            cpu_pct: Metric::Measured(14.0),
            rss_bytes: 2_100 << 20,
            start_time: 8,
        },
    ];
    if scenario == Scenario::Flood {
        for i in 0..3_000u32 {
            processes.push(ProcessRow {
                pid: 20_000 + i,
                ppid: Some(if i % 10 == 0 { 4119 } else { 20_000 + i - 1 }),
                name: format!("job-{i}"),
                cpu_pct: Metric::Measured(0.1),
                rss_bytes: 1 << 20,
                start_time: 9,
            });
        }
    }
    let disk = Volume {
        mount: "/".into(),
        filesystem: "apfs".into(),
        total_bytes: (disk_total * gib) as u64,
        available_bytes: (disk_free * gib) as u64,
        removable: false,
    };
    let history: Vec<Option<f64>> = (0..40)
        .map(|i| Some(20.0 + f64::from(i % 9) * 3.0))
        .collect();
    let mut cpu_history = history.clone();
    cpu_history[12] = None;
    HostSample {
        taken_at,
        os: "fixture",
        cpu_pct: Metric::Measured(cpu),
        memory_pct: Metric::Measured(mem_used / mem_total * 100.0),
        memory_used_bytes: Some((mem_used * gib) as u64),
        memory_total_bytes: Some((mem_total * gib) as u64),
        swap_used_bytes: Some(512 << 20),
        disk_pct: disk.used_percent(),
        disk: Some(disk.clone()),
        net_rx_bytes_per_sec: Metric::Measured(1_250_000.0),
        net_tx_bytes_per_sec: Metric::Measured(310_000.0),
        gpu_pct: Metric::Unavailable(Reason::NotMeasured),
        uptime_sec: Some(530_000),
        process_count: processes.len(),
        processes,
        volumes: vec![
            disk,
            Volume {
                mount: "/Volumes/Archive".into(),
                filesystem: "exfat".into(),
                total_bytes: (2_000.0 * gib) as u64,
                available_bytes: if scenario == Scenario::Critical {
                    (120.0 * gib) as u64
                } else {
                    (900.0 * gib) as u64
                },
                removable: true,
            },
        ],
        cpu_history,
        rx_history: history.iter().map(|v| v.map(|x| x * 40_000.0)).collect(),
        tx_history: history.iter().map(|v| v.map(|x| x * 9_000.0)).collect(),
    }
}

pub fn telemetry_feed(scenario: Scenario, now: SystemTime) -> Feed<HostSample> {
    match scenario {
        Scenario::Loading => Feed::default(),
        _ => Feed {
            phase: Phase::Live,
            value: Some(Arc::new(host_sample_for(
                scenario,
                3.0,
                now - Duration::from_secs(1),
            ))),
            received_at: Some(now - Duration::from_secs(1)),
            detail: None,
            reads: 20,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_scenario_builds() {
        for scenario in Scenario::ALL {
            let _ = controller_feed(scenario, now());
            let _ = telemetry_feed(scenario, now());
            assert_eq!(Scenario::parse(scenario.name()), Some(scenario));
        }
    }

    #[test]
    fn fixtures_disclose_themselves() {
        assert_eq!(snapshot(Scenario::Healthy, now()).daemon.version, MARKER);
    }
}
