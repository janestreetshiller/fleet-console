//! Honest state: a value that exists, or the reason it does not.

use std::sync::Arc;
use std::time::{Duration, SystemTime};

/// Why a value is not shown. Each reason has its own wording because "this
/// platform cannot measure it" and "the controller is down" call for different
/// actions from the person reading the screen.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Reason {
    /// No source for this value exists on this operating system.
    NotMeasured,
    /// The first interval has not elapsed; rates and CPU need two samples.
    AwaitingSample,
    /// The node is offline; the last value is no longer current.
    Offline,
    /// The controller is unreachable, so nothing it reports is current.
    Disconnected,
    /// The read was attempted and failed.
    Failed,
}

impl Reason {
    pub fn label(self) -> &'static str {
        match self {
            Self::NotMeasured => "not measured on this platform",
            Self::AwaitingSample => "awaiting second sample",
            Self::Offline => "node offline",
            Self::Disconnected => "controller disconnected",
            Self::Failed => "read failed",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Metric {
    Measured(f64),
    Unavailable(Reason),
}

impl Metric {
    pub fn from_option(value: Option<f64>, missing: Reason) -> Self {
        match value {
            Some(v) if v.is_finite() => Self::Measured(v),
            Some(_) => Self::Unavailable(Reason::Failed),
            None => Self::Unavailable(missing),
        }
    }

    pub fn value(self) -> Option<f64> {
        match self {
            Self::Measured(v) => Some(v),
            Self::Unavailable(_) => None,
        }
    }

    pub fn reason(self) -> Option<Reason> {
        match self {
            Self::Measured(_) => None,
            Self::Unavailable(r) => Some(r),
        }
    }

    pub fn is_measured(self) -> bool {
        matches!(self, Self::Measured(_))
    }

    /// Clamp a percentage for drawing. The unclamped value is still what the
    /// label shows, so an over-100 reading is visible rather than hidden.
    pub fn fraction(self) -> Option<f64> {
        self.value().map(|v| (v / 100.0).clamp(0.0, 1.0))
    }
}

/// Where a feed is. Clients render this before they render any value.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Phase {
    /// No attempt has finished.
    Loading,
    /// The latest attempt succeeded within the freshness window.
    Live,
    /// A value exists but is older than the freshness window.
    Stale,
    /// The socket is missing or refused the connection.
    Disconnected,
    /// The controller answered with an error, timed out, or sent something
    /// that did not decode or exceeded the size limit.
    Error,
}

impl Phase {
    pub fn label(self) -> &'static str {
        match self {
            Self::Loading => "loading",
            Self::Live => "live",
            Self::Stale => "stale",
            Self::Disconnected => "disconnected",
            Self::Error => "error",
        }
    }

    /// Values may be shown as current only when live.
    pub fn is_current(self) -> bool {
        self == Self::Live
    }
}

/// A value read in the background plus everything needed to say how current it is.
#[derive(Debug, Clone)]
pub struct Feed<T> {
    pub phase: Phase,
    /// The last value that decoded. Retained across failures so a client can
    /// show it as last-known, never as current.
    pub value: Option<Arc<T>>,
    pub received_at: Option<SystemTime>,
    /// Error or disconnection detail for the current phase.
    pub detail: Option<String>,
    /// Successful reads since start, for diagnostics.
    pub reads: u64,
}

impl<T> Default for Feed<T> {
    fn default() -> Self {
        Self {
            phase: Phase::Loading,
            value: None,
            received_at: None,
            detail: None,
            reads: 0,
        }
    }
}

impl<T> Feed<T> {
    /// Re-evaluate staleness against a clock. Workers record outcomes; the age
    /// check happens at render time so a hung worker shows up as stale.
    pub fn at(&self, now: SystemTime, stale_after: Duration) -> Phase {
        match self.phase {
            Phase::Live => match self.received_at.and_then(|t| now.duration_since(t).ok()) {
                Some(age) if age > stale_after => Phase::Stale,
                _ => Phase::Live,
            },
            other => other,
        }
    }

    pub fn age(&self, now: SystemTime) -> Option<Duration> {
        self.received_at.and_then(|t| now.duration_since(t).ok())
    }
}

pub fn epoch_seconds(time: SystemTime) -> f64 {
    time.duration_since(SystemTime::UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_is_not_zero() {
        assert_eq!(Metric::from_option(None, Reason::NotMeasured).value(), None);
        assert_eq!(
            Metric::from_option(Some(f64::NAN), Reason::NotMeasured).reason(),
            Some(Reason::Failed)
        );
        assert_eq!(Metric::Measured(0.0).value(), Some(0.0));
    }

    #[test]
    fn live_feed_ages_into_stale() {
        let start = SystemTime::UNIX_EPOCH + Duration::from_secs(1_000);
        let feed = Feed::<u8> {
            phase: Phase::Live,
            value: Some(Arc::new(1)),
            received_at: Some(start),
            detail: None,
            reads: 1,
        };
        assert_eq!(
            feed.at(start + Duration::from_secs(5), Duration::from_secs(6)),
            Phase::Live
        );
        assert_eq!(
            feed.at(start + Duration::from_secs(7), Duration::from_secs(6)),
            Phase::Stale
        );
    }

    #[test]
    fn disconnected_stays_disconnected_regardless_of_age() {
        let feed = Feed::<u8> {
            phase: Phase::Disconnected,
            ..Feed::default()
        };
        assert_eq!(
            feed.at(SystemTime::now(), Duration::from_secs(1)),
            Phase::Disconnected
        );
    }
}
