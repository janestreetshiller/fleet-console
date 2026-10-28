//! The 50/70/90 percent bands from the design package.
//!
//! Dark green to 50, bright green 50 to 70, amber 70 to 90, red above 90. Color
//! is never the only signal: every band has a word, and a tile's word comes from
//! its worst measured gauge.

use crate::observe::Metric;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Level {
    Normal,
    Elevated,
    Warning,
    Critical,
}

impl Level {
    pub fn for_percent(percent: f64) -> Self {
        if percent > 90.0 {
            Self::Critical
        } else if percent > 70.0 {
            Self::Warning
        } else if percent > 50.0 {
            Self::Elevated
        } else {
            Self::Normal
        }
    }

    /// `None` when the metric was not measured: an unmeasured gauge has no band.
    pub fn for_metric(metric: Metric) -> Option<Self> {
        metric.value().map(Self::for_percent)
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Normal => "normal",
            Self::Elevated => "above 50%",
            Self::Warning => "warning",
            Self::Critical => "critical",
        }
    }
}

/// The text state a node tile carries next to its border color.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum NodeState {
    Healthy,
    Pressure,
    Critical,
    Offline,
    /// Reachable, but it reported no measurements to judge.
    Unmeasured,
}

impl NodeState {
    pub fn label(self) -> &'static str {
        match self {
            Self::Healthy => "healthy",
            Self::Pressure => "pressure",
            Self::Critical => "critical",
            Self::Offline => "offline",
            Self::Unmeasured => "no measurements",
        }
    }

    pub fn from_gauges<'a>(gauges: impl IntoIterator<Item = &'a Metric>) -> Self {
        let worst = gauges
            .into_iter()
            .filter_map(|m| Level::for_metric(*m))
            .max();
        match worst {
            None => Self::Unmeasured,
            Some(Level::Critical) => Self::Critical,
            Some(Level::Warning) => Self::Pressure,
            Some(_) => Self::Healthy,
        }
    }
}

/// Lit cells for a segmented gauge, and the band of each lit cell. Segment i
/// is colored by its own position, so a 95% bar shows all four bands.
pub fn segments(metric: Metric, count: usize) -> Vec<Option<Level>> {
    let lit = metric
        .fraction()
        .map(|f| (f * count as f64).round() as usize)
        .unwrap_or(0);
    (0..count)
        .map(|i| (i < lit).then(|| Level::for_percent((i + 1) as f64 / count as f64 * 100.0)))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::observe::Reason;

    #[test]
    fn bands_match_the_design_package() {
        assert_eq!(Level::for_percent(50.0), Level::Normal);
        assert_eq!(Level::for_percent(50.1), Level::Elevated);
        assert_eq!(Level::for_percent(70.0), Level::Elevated);
        assert_eq!(Level::for_percent(70.1), Level::Warning);
        assert_eq!(Level::for_percent(90.0), Level::Warning);
        assert_eq!(Level::for_percent(90.1), Level::Critical);
    }

    #[test]
    fn unmeasured_gauges_do_not_make_a_node_healthy() {
        let gauges = [
            Metric::Unavailable(Reason::NotMeasured),
            Metric::Unavailable(Reason::Failed),
        ];
        assert_eq!(NodeState::from_gauges(&gauges), NodeState::Unmeasured);
        let gauges = [
            Metric::Measured(12.0),
            Metric::Unavailable(Reason::NotMeasured),
            Metric::Measured(93.0),
        ];
        assert_eq!(NodeState::from_gauges(&gauges), NodeState::Critical);
    }

    #[test]
    fn segments_light_by_position() {
        let cells = segments(Metric::Measured(100.0), 20);
        assert_eq!(cells.iter().filter(|c| c.is_some()).count(), 20);
        assert_eq!(cells[0], Some(Level::Normal));
        assert_eq!(cells[19], Some(Level::Critical));
        assert!(segments(Metric::Unavailable(Reason::Offline), 20)
            .iter()
            .all(Option::is_none));
    }
}
