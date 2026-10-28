//! Where the window's data comes from: the live controller and telemetry
//! threads in `fleet-ui-core`, or, in fixture builds only, a fixed synthetic
//! scenario with no threads at all.
//!
//! The window never waits on a socket or a process scan. It asks for a
//! `Fingerprint` (two atomic loads and a clock comparison) and rebuilds the
//! `Dashboard` only when the fingerprint changed: a new controller read, a
//! new telemetry sample, an action queued or finished, or a phase change such
//! as a live feed aging into stale.

use crate::cli::Options;
use fleet_ui_core::controller::{display_path, ActionPayload, Wake};
use fleet_ui_core::model::LogChunk;
use fleet_ui_core::observe::Phase;
use fleet_ui_core::platform::TelemetryWorker;
use fleet_ui_core::views::{Dashboard, Inputs};
use fleet_ui_core::{Action, Controller, ControllerConfig};
use std::time::{Duration, SystemTime};

/// Everything the window renders, built at one instant.
#[derive(Debug, Clone, PartialEq)]
pub struct Built {
    pub dashboard: Dashboard,
    /// (mount, total bytes, used bytes) per volume, in the order of
    /// `dashboard.storage.volumes`, for the proportional volume map.
    pub volumes: Vec<(String, u64, u64)>,
    /// The newest log text read through the controller, by service id.
    pub logs: Option<(String, LogChunk)>,
    /// Set in fixture mode, so every window says the data is synthetic.
    pub fixture: Option<&'static str>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Fingerprint {
    controller: u64,
    telemetry: u64,
    controller_phase: Phase,
    telemetry_phase: Phase,
    /// Age of the last controller read while it is not live, so the "last
    /// read 40s ago" text advances; `None` while live.
    age_step: Option<u64>,
}

pub struct LiveFeeds {
    controller: Controller,
    telemetry: TelemetryWorker,
    socket_label: String,
    read_only: bool,
    assume_remote: bool,
}

#[cfg(feature = "fixtures")]
pub struct FixtureFeeds {
    scenario: fleet_ui_core::fixtures::Scenario,
}

pub enum Feeds {
    Live(Box<LiveFeeds>),
    #[cfg(feature = "fixtures")]
    Fixture(FixtureFeeds),
}

pub const FIXTURE_REFUSAL: &str = "fixture mode: no controller";

pub fn controller_config(options: &Options) -> ControllerConfig {
    let mut config = ControllerConfig {
        poll_interval: options.poll,
        read_only: options.read_only,
        ..ControllerConfig::default()
    };
    if let Some(socket) = &options.socket {
        config.socket = socket.clone();
    }
    config
}

impl Feeds {
    /// Start the controller poller and the telemetry sampler, or the fixture.
    pub fn start(options: &Options, wake: Wake) -> Self {
        #[cfg(feature = "fixtures")]
        if let Some(scenario) = options.fixture {
            drop(wake);
            return Self::Fixture(FixtureFeeds { scenario });
        }
        let config = controller_config(options);
        let socket_label = display_path(&config.socket);
        let read_only = config.read_only;
        let controller = Controller::spawn(config, wake.clone());
        let telemetry = TelemetryWorker::spawn(options.poll, wake);
        Self::Live(Box::new(LiveFeeds {
            controller,
            telemetry,
            socket_label,
            read_only,
            assume_remote: options.remote_controller,
        }))
    }

    /// Fixture data never changes, so the window has nothing to watch.
    pub fn is_static(&self) -> bool {
        !matches!(self, Self::Live(_))
    }

    pub fn now(&self) -> SystemTime {
        match self {
            Self::Live(_) => SystemTime::now(),
            #[cfg(feature = "fixtures")]
            Self::Fixture(_) => fleet_ui_core::fixtures::now(),
        }
    }

    pub fn fingerprint(&self, now: SystemTime) -> Fingerprint {
        match self {
            Self::Live(live) => {
                let controller_feed_phase = live.controller.phase(now);
                let telemetry = live.telemetry.feed();
                let age_step = if controller_feed_phase == Phase::Live {
                    None
                } else {
                    live.controller
                        .feed()
                        .age(now)
                        .map(|age| age_step(age.as_secs()))
                };
                Fingerprint {
                    controller: live.controller.generation(),
                    telemetry: live.telemetry.generation(),
                    controller_phase: controller_feed_phase,
                    telemetry_phase: telemetry.at(now, live.telemetry.stale_after()),
                    age_step,
                }
            }
            #[cfg(feature = "fixtures")]
            Self::Fixture(_) => Fingerprint {
                controller: 0,
                telemetry: 0,
                controller_phase: Phase::Loading,
                telemetry_phase: Phase::Loading,
                age_step: None,
            },
        }
    }

    pub fn build(&self, now: SystemTime) -> Built {
        match self {
            Self::Live(live) => {
                let controller = live.controller.feed();
                let telemetry = live.telemetry.feed();
                let pending = live.controller.pending();
                let outcomes = live.controller.outcomes();
                let dashboard = Dashboard::build(&Inputs {
                    controller: &controller,
                    controller_stale_after: live.controller.config().stale_after(),
                    telemetry: &telemetry,
                    telemetry_stale_after: live.telemetry.stale_after(),
                    pending: &pending,
                    outcomes: &outcomes,
                    read_only: live.read_only,
                    socket_label: live.socket_label.clone(),
                    assume_remote_controller: live.assume_remote,
                    now,
                });
                let logs = outcomes.iter().rev().find_map(|o| match &o.result {
                    Ok(ActionPayload::Logs(chunk)) => Some((chunk.service_id.clone(), chunk.clone())),
                    _ => None,
                });
                Built {
                    volumes: volume_bytes(telemetry.value.as_deref()),
                    dashboard,
                    logs,
                    fixture: None,
                }
            }
            #[cfg(feature = "fixtures")]
            Self::Fixture(fixture) => fixture_built(fixture.scenario, now),
        }
    }

    pub fn submit(&self, action: Action) -> Result<u64, String> {
        match self {
            Self::Live(live) => live.controller.submit(action),
            #[cfg(feature = "fixtures")]
            Self::Fixture(_) => {
                let _ = action;
                Err(FIXTURE_REFUSAL.into())
            }
        }
    }

    pub fn refresh(&self) {
        match self {
            Self::Live(live) => live.controller.refresh(),
            #[cfg(feature = "fixtures")]
            Self::Fixture(_) => {}
        }
    }
}

/// One step per second for the first minute, then per minute, matching the
/// resolution of `format::duration`.
fn age_step(seconds: u64) -> u64 {
    if seconds < 60 {
        seconds
    } else {
        60 + seconds / 60
    }
}

fn volume_bytes(sample: Option<&fleet_ui_core::HostSample>) -> Vec<(String, u64, u64)> {
    sample
        .map(|s| {
            s.volumes
                .iter()
                .map(|v| (v.mount.clone(), v.total_bytes, v.used_bytes()))
                .collect()
        })
        .unwrap_or_default()
}

/// The fixture dashboard, built exactly as the live one is. Test code builds
/// it too, through `fleet_ui_core::fixtures`.
#[cfg(feature = "fixtures")]
pub fn fixture_built(scenario: fleet_ui_core::fixtures::Scenario, now: SystemTime) -> Built {
    use fleet_ui_core::fixtures;
    let controller = fixtures::controller_feed(scenario, now);
    let telemetry = fixtures::telemetry_feed(scenario, now);
    let config = ControllerConfig::default();
    let dashboard = Dashboard::build(&Inputs {
        controller: &controller,
        controller_stale_after: config.stale_after(),
        telemetry: &telemetry,
        telemetry_stale_after: TelemetryWorker::DEFAULT_INTERVAL * 3,
        pending: &[],
        outcomes: &[],
        read_only: false,
        socket_label: display_path(&config.socket),
        assume_remote_controller: false,
        now,
    });
    Built {
        volumes: volume_bytes(telemetry.value.as_deref()),
        dashboard,
        logs: None,
        fixture: Some(scenario.name()),
    }
}

/// How long the window waits between staleness checks when nothing wakes it.
pub const STALENESS_CHECK: Duration = Duration::from_secs(1);

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    #[test]
    fn age_steps_slow_down_after_a_minute() {
        assert_eq!(age_step(5), 5);
        assert_eq!(age_step(59), 59);
        assert_eq!(age_step(60), age_step(119));
        assert_ne!(age_step(119), age_step(120));
    }

    #[test]
    fn missing_socket_builds_a_disconnected_dashboard() {
        let dir = std::env::temp_dir().join(format!("fleet-gpui-feeds-{}", std::process::id()));
        let options = Options {
            socket: Some(dir.join("absent.sock")),
            poll: Duration::from_secs(1),
            ..Options::default()
        };
        let (tx, rx) = std::sync::mpsc::channel();
        let feeds = Feeds::start(
            &options,
            Arc::new(move || {
                let _ = tx.send(());
            }),
        );
        assert!(!feeds.is_static());
        // The poller reads once at start; wait for it.
        let deadline = std::time::Instant::now() + Duration::from_secs(5);
        while feeds.fingerprint(feeds.now()).controller_phase == Phase::Loading
            && std::time::Instant::now() < deadline
        {
            let _ = rx.recv_timeout(Duration::from_millis(200));
        }
        let built = feeds.build(feeds.now());
        assert_eq!(built.dashboard.connection.phase, Phase::Disconnected);
        assert_eq!(built.dashboard.header.services_running, None);
        assert!(built.fixture.is_none());
        let fingerprint = feeds.fingerprint(feeds.now());
        assert!(fingerprint.controller >= 1, "the read bumped the generation");
        assert_eq!(fingerprint.controller_phase, Phase::Disconnected);
    }

    #[test]
    fn read_only_live_feeds_refuse_mutations_before_the_socket() {
        let options = Options {
            socket: Some(std::env::temp_dir().join("fleet-gpui-absent.sock")),
            read_only: true,
            ..Options::default()
        };
        let feeds = Feeds::start(&options, Arc::new(|| {}));
        let refused = feeds.submit(Action::Stop {
            service_id: "abc".into(),
        });
        assert!(refused.unwrap_err().contains("read-only"));
    }
}
