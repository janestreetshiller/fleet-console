//! Where the dashboard's inputs come from: the controller and telemetry
//! workers from `fleet-ui-core`, or, in fixture builds, synthetic feeds with no
//! threads and no socket.

use fleet_ui_core::controller::{Action, ActionOutcome, ControllerConfig};
#[cfg(any(test, feature = "fixtures"))]
use fleet_ui_core::{model::Snapshot, Feed, HostSample};
use fleet_ui_core::views::{Dashboard, Inputs};
use fleet_ui_core::{Controller, TelemetryWorker};
use std::cell::RefCell;
use std::time::{Duration, SystemTime};

/// The tail pane shows the end of a log; this bounds each read and the copy
/// the controller's outcome history keeps of it.
pub const TAIL_BYTES: i64 = 16 * 1024;

pub struct Settings {
    pub read_only: bool,
    pub assume_remote_controller: bool,
    pub socket_label: String,
}

pub enum Source {
    Live {
        controller: Controller,
        telemetry: TelemetryWorker,
        /// Pending and finished actions without log reads, recomputed only
        /// when the controller generation changes.
        actions: RefCell<ActionCache>,
    },
    #[cfg(any(test, feature = "fixtures"))]
    Fixture {
        controller: Feed<Snapshot>,
        telemetry: Feed<HostSample>,
    },
}

#[derive(Default)]
pub struct ActionCache {
    generation: Option<u64>,
    pending: Vec<(u64, Action)>,
    outcomes: Vec<ActionOutcome>,
}

#[cfg(any(test, feature = "fixtures"))]
pub const FIXTURE_REFUSAL: &str = "fixture mode: no controller";

impl Source {
    pub fn live(config: ControllerConfig, telemetry_interval: Duration, wake: fleet_ui_core::controller::Wake) -> Self {
        let controller = Controller::spawn(config, wake.clone());
        let telemetry = TelemetryWorker::spawn(telemetry_interval, wake);
        Self::Live {
            controller,
            telemetry,
            actions: RefCell::new(ActionCache::default()),
        }
    }

    #[cfg(any(test, feature = "fixtures"))]
    pub fn fixture(scenario: fleet_ui_core::fixtures::Scenario) -> Self {
        let now = fleet_ui_core::fixtures::now();
        Self::Fixture {
            controller: fleet_ui_core::fixtures::controller_feed(scenario, now),
            telemetry: fleet_ui_core::fixtures::telemetry_feed(scenario, now),
        }
    }

    /// Changes whenever anything the dashboard reads changes.
    pub fn generation(&self) -> (u64, u64) {
        match self {
            Self::Live {
                controller,
                telemetry,
                ..
            } => (controller.generation(), telemetry.generation()),
            #[cfg(any(test, feature = "fixtures"))]
            Self::Fixture { .. } => (0, 0),
        }
    }

    /// Feeds as they stand, for deciding when to wake for a stale transition.
    pub fn freshness(&self) -> Vec<(Option<SystemTime>, Duration, bool)> {
        match self {
            Self::Live {
                controller,
                telemetry,
                ..
            } => {
                let c = controller.feed();
                let t = telemetry.feed();
                vec![
                    (
                        c.received_at,
                        controller.config().stale_after(),
                        c.phase == fleet_ui_core::Phase::Live,
                    ),
                    (
                        t.received_at,
                        telemetry.stale_after(),
                        t.phase == fleet_ui_core::Phase::Live,
                    ),
                ]
            }
            #[cfg(any(test, feature = "fixtures"))]
            Self::Fixture { .. } => Vec::new(),
        }
    }

    pub fn has_telemetry_samples(&self, count: u64) -> bool {
        match self {
            Self::Live { telemetry, .. } => telemetry.feed().reads >= count,
            #[cfg(any(test, feature = "fixtures"))]
            Self::Fixture { .. } => true,
        }
    }

    pub fn controller_answered(&self) -> bool {
        match self {
            Self::Live { controller, .. } => {
                controller.feed().phase != fleet_ui_core::Phase::Loading
            }
            #[cfg(any(test, feature = "fixtures"))]
            Self::Fixture { .. } => true,
        }
    }

    pub fn dashboard(&self, settings: &Settings) -> Dashboard {
        match self {
            Self::Live {
                controller,
                telemetry,
                actions,
            } => {
                let generation = controller.generation();
                let mut cache = actions.borrow_mut();
                if cache.generation != Some(generation) {
                    cache.pending = controller
                        .pending()
                        .into_iter()
                        .filter(|(_, a)| !matches!(a, Action::Logs { .. }))
                        .collect();
                    cache.outcomes = controller
                        .outcomes()
                        .into_iter()
                        .filter(|o| !matches!(o.action, Action::Logs { .. }))
                        .collect();
                    cache.generation = Some(generation);
                }
                let controller_feed = controller.feed();
                let telemetry_feed = telemetry.feed();
                Dashboard::build(&Inputs {
                    controller: &controller_feed,
                    controller_stale_after: controller.config().stale_after(),
                    telemetry: &telemetry_feed,
                    telemetry_stale_after: telemetry.stale_after(),
                    pending: &cache.pending,
                    outcomes: &cache.outcomes,
                    read_only: settings.read_only,
                    socket_label: settings.socket_label.clone(),
                    assume_remote_controller: settings.assume_remote_controller,
                    now: SystemTime::now(),
                })
            }
            #[cfg(any(test, feature = "fixtures"))]
            Self::Fixture {
                controller,
                telemetry,
                ..
            } => Dashboard::build(&Inputs {
                controller,
                controller_stale_after: ControllerConfig::default().stale_after(),
                telemetry,
                telemetry_stale_after: TelemetryWorker::DEFAULT_INTERVAL * 3,
                pending: &[],
                outcomes: &[],
                read_only: settings.read_only,
                socket_label: settings.socket_label.clone(),
                assume_remote_controller: settings.assume_remote_controller,
                now: fleet_ui_core::fixtures::now(),
            }),
        }
    }

    /// Queue an action with `fleetctl` semantics. Fixture mode refuses.
    pub fn submit(&self, action: Action) -> Result<u64, String> {
        match self {
            Self::Live { controller, .. } => controller.submit(action),
            #[cfg(any(test, feature = "fixtures"))]
            Self::Fixture { .. } => {
                let _ = action;
                Err(FIXTURE_REFUSAL.into())
            }
        }
    }

    pub fn outcome(&self, id: u64) -> Option<ActionOutcome> {
        match self {
            Self::Live { controller, .. } => controller.outcome(id),
            #[cfg(any(test, feature = "fixtures"))]
            Self::Fixture { .. } => {
                let _ = id;
                None
            }
        }
    }

}

#[cfg(test)]
pub mod tests {
    use super::*;
    use fleet_ui_core::fixtures::Scenario;

    pub fn settings(read_only: bool) -> Settings {
        Settings {
            read_only,
            assume_remote_controller: false,
            socket_label: "~/fixture/fleetd.sock".into(),
        }
    }

    pub fn dashboard(scenario: Scenario, read_only: bool) -> Dashboard {
        Source::fixture(scenario).dashboard(&settings(read_only))
    }

    #[test]
    fn fixture_source_refuses_actions() {
        let source = Source::fixture(Scenario::Healthy);
        let refused = source.submit(Action::Restart {
            service_id: "x".into(),
        });
        assert_eq!(refused, Err(FIXTURE_REFUSAL.to_string()));
    }
}
