//! What the FleetConsole terminal and GPUI clients share.
//!
//! Both clients are views over the same two feeds: the controller's snapshot,
//! read through `fleet-proto`, and this machine's own telemetry, read through
//! the platform module. Everything a client renders is derived here so the two
//! cannot disagree about a number, a threshold or whether a value exists.
//!
//! The honesty rules from the Swift app carry over unchanged. A value that was
//! not observed is `Metric::Unavailable`, never zero. Process existence,
//! listening ports, reachability and a configured health check stay separate
//! facts. Every feed reports loading, live, stale, disconnected or error, and a
//! client renders that phase rather than guessing.
//!
//! Nothing in this crate blocks the caller's thread on a socket or a process
//! scan: `controller::Controller` and `platform::TelemetryWorker` own background
//! threads with bounded queues, bounded payloads and bounded history.

pub mod controller;
pub mod format;
pub mod map;
pub mod model;
pub mod observe;
pub mod platform;
pub mod theme;
pub mod thresholds;
pub mod views;

#[cfg(any(test, feature = "fixtures"))]
pub mod fixtures;

pub use controller::{Action, ActionOutcome, Controller, ControllerConfig};
pub use observe::{Feed, Metric, Phase, Reason};
pub use platform::{HostSample, TelemetryWorker};
pub use views::Dashboard;

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}
