//! Proves the Rust protocol types and the running Swift controller agree.
//!
//! This is the test that makes the port safe to attempt. Every check is a full
//! round trip across the language boundary — Rust encodes a request, the Swift
//! daemon decodes and acts on it, Swift encodes a reply, Rust decodes that. A
//! unit test in either language proves only that it agrees with itself.
//!
//! Read-only operations only. `ping`, `snapshot` and `events` observe; nothing
//! here launches, stops or signals anything, so it is safe to run against the
//! controller that is supervising real work.
//!
//!     cargo run -p fleet-conformance

use fleet_proto::{Client, RpcOp, RpcRequest};
use std::process::ExitCode;

fn main() -> ExitCode {
    let path = fleet_proto::default_socket_path();
    println!("socket: {}\n", path.display());

    let mut client = match Client::connect(&path) {
        Ok(client) => client,
        Err(error) => {
            eprintln!("✗ cannot reach the controller: {error}");
            eprintln!("  is fleetd running? `fleetctl ping`");
            return ExitCode::FAILURE;
        }
    };

    let mut checks = Checks::default();

    // 1. Envelope round trip, and the one struct we model completely.
    match client.send(&RpcRequest::new(RpcOp::Ping)) {
        Ok(response) => {
            checks.assert("ping returns ok", response.ok, String::new());
            match response.daemon {
                Some(daemon) => {
                    checks.assert(
                        "DaemonInfo decodes",
                        daemon.pid > 0 && !daemon.version.is_empty(),
                        format!("v{} pid {}", daemon.version, daemon.pid),
                    );
                    checks.assert(
                        "dates are epoch seconds, not ISO strings",
                        daemon.started_at > 1_000_000_000.0,
                        format!("startedAt {:.0}", daemon.started_at),
                    );
                    checks.assert(
                        "tickIntervalSec present",
                        daemon.tick_interval_sec > 0.0,
                        format!("{}s", daemon.tick_interval_sec),
                    );
                }
                None => checks.fail("DaemonInfo decodes", "no daemon field in ping reply"),
            }
        }
        Err(error) => checks.fail("ping returns ok", &error.to_string()),
    }

    // 2. A large real payload decodes without the envelope losing anything.
    match client.send(&RpcRequest::new(RpcOp::Snapshot)) {
        Ok(response) => {
            checks.assert("snapshot returns ok", response.ok, String::new());
            match response.snapshot {
                Some(value) => {
                    let keys: Vec<&str> = value
                        .as_object()
                        .map(|o| o.keys().map(String::as_str).collect())
                        .unwrap_or_default();
                    checks.assert(
                        "snapshot is an object",
                        !keys.is_empty(),
                        format!("{} keys: {}", keys.len(), keys.join(", ")),
                    );
                    // These are the fields the app reads on every tick. If the
                    // Rust daemon ever stops emitting one, the GUI goes quietly
                    // wrong rather than loudly failing — so assert them here.
                    for required in ["services", "devices", "unmanaged", "attention", "daemon"] {
                        checks.assert(
                            &format!("snapshot carries `{required}`"),
                            value.get(required).is_some(),
                            String::new(),
                        );
                    }
                }
                None => checks.fail("snapshot is an object", "no snapshot field"),
            }
        }
        Err(error) => checks.fail("snapshot returns ok", &error.to_string()),
    }

    // 3. Optional fields we serialise must be understood, not merely tolerated.
    let mut events = RpcRequest::new(RpcOp::Events);
    events.limit = Some(3);
    match client.send(&events) {
        Ok(response) => checks.assert(
            "request with optional fields is accepted",
            response.ok,
            response
                .events
                .map(|e| format!("{} events", e.len()))
                .unwrap_or_else(|| "no events".into()),
        ),
        Err(error) => checks.fail("request with optional fields is accepted", &error.to_string()),
    }

    // 4. The daemon must reject what it does not understand, rather than
    //    succeeding vaguely — otherwise a Rust bug looks like a working call.
    match client.send(&RpcRequest::new(RpcOp::Logs)) {
        Ok(response) => checks.assert(
            "logs without a serviceID is refused",
            !response.ok && response.error.is_some(),
            response.error.unwrap_or_default(),
        ),
        Err(error) => checks.fail("logs without a serviceID is refused", &error.to_string()),
    }

    println!();
    checks.report()
}

#[derive(Default)]
struct Checks {
    passed: usize,
    failed: usize,
}

impl Checks {
    fn assert(&mut self, name: &str, condition: bool, detail: String) {
        if condition {
            self.passed += 1;
            if detail.is_empty() {
                println!("  ✓ {name}");
            } else {
                println!("  ✓ {name} — {detail}");
            }
        } else {
            self.failed += 1;
            println!("  ✗ {name}{}", if detail.is_empty() { String::new() } else { format!(" — {detail}") });
        }
    }

    fn fail(&mut self, name: &str, detail: &str) {
        self.failed += 1;
        println!("  ✗ {name} — {detail}");
    }

    fn report(self) -> ExitCode {
        println!("{} passed, {} failed", self.passed, self.failed);
        if self.failed == 0 {
            println!("\nThe Rust types and the Swift controller agree on the wire.");
            ExitCode::SUCCESS
        } else {
            ExitCode::FAILURE
        }
    }
}
