
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
