
#[derive(Debug, Clone, PartialEq)]
pub struct MemoryTrend {
    pub classification: TrendClass,
    pub slope_mb_per_sample: Option<f64>,
    pub samples: usize,
    pub note: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TrendClass {
    Climbing,
    Oscillating,
    Steady,
    Creeping,
    InsufficientData,
}

pub const LEAK_SLOPE_MB_PER_SAMPLE: f64 = 1.0;
pub const CREEP_SLOPE_MB_PER_SAMPLE: f64 = 0.1;
pub const MIN_SAMPLES_FOR_TREND: usize = 6;

pub fn classify_memory_trend(history_mb: &[f64]) -> MemoryTrend {
    let samples = history_mb.len();
    if samples < MIN_SAMPLES_FOR_TREND {
        return MemoryTrend {
            classification: TrendClass::InsufficientData,
            slope_mb_per_sample: None,
            samples,
            note: format!(
                "{samples} sample(s) — fleetd keeps 40; wait for more ticks before calling this a trend."
            ),
        };
    }

    let n = samples as f64;
    let xs: f64 = (0..samples).map(|i| i as f64).sum();
    let ys: f64 = history_mb.iter().sum();
    let xys: f64 = history_mb
        .iter()
        .enumerate()
        .map(|(i, y)| i as f64 * y)
        .sum();
    let xx: f64 = (0..samples).map(|i| (i * i) as f64).sum();
    let denom = n * xx - xs * xs;
    let slope = if denom.abs() > f64::EPSILON {
        Some((n * xys - xs * ys) / denom)
    } else {
        None
    };

    let span = history_mb.iter().cloned().fold(f64::MIN, f64::max)
        - history_mb.iter().cloned().fold(f64::MAX, f64::min);
    let mean = ys / n;
    let band = if mean > 0.0 { span / mean } else { span };

    match slope {
        Some(slope) if slope >= LEAK_SLOPE_MB_PER_SAMPLE => MemoryTrend {
            classification: TrendClass::Climbing,
            slope_mb_per_sample: Some(slope),
            samples,
            note: format!(
                "resident memory climbing ~{slope:.1} MB/sample sustained across {samples} samples \
                 — leak candidate. Check `fleet_logs` for growth patterns and `fleetctl stop` if it \
                 is not supposed to be a big-memory service; renewing the lease does not help this."
            ),
        },
        Some(slope) if slope >= CREEP_SLOPE_MB_PER_SAMPLE => MemoryTrend {
            classification: TrendClass::Creeping,
            slope_mb_per_sample: Some(slope),
            samples,
            note: format!(
                "creeping ~{slope:.2} MB/sample over {samples} samples — not urgent, but re-check in \
                 an hour. If it crosses {} MB/sample it becomes a leak candidate.",
                LEAK_SLOPE_MB_PER_SAMPLE
            ),
        },
        Some(slope) if band > 0.10 => MemoryTrend {
            classification: TrendClass::Oscillating,
            slope_mb_per_sample: Some(slope),
            samples,
            note: format!(
                "oscillating in a {span:.0} MB band with near-zero net slope ({slope:.2} MB/sample) — \
                 normal allocator/cache behavior, no action needed."
            ),
        },
        Some(slope) => MemoryTrend {
            classification: TrendClass::Steady,
            slope_mb_per_sample: Some(slope),
            samples,
            note: format!(
                "steady within noise ({slope:.2} MB/sample over {samples} samples) — healthy RSS."
            ),
        },
        None => MemoryTrend {
            classification: TrendClass::InsufficientData,
            slope_mb_per_sample: None,
            samples,
            note: "window degenerate — cannot compute a slope.".into(),
        },
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct ProcessMemoryAdvice {
    pub rss_mb: f64,
    pub classification: RssClass,
    pub note: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RssClass {
    Heavy,
    Normal,
    Light,
    Unknown,
}

pub const HEAVY_RSS_MB: f64 = 1024.0;
pub const NORMAL_RSS_MB: f64 = 200.0;

pub fn classify_process_memory(rss_mb: Option<f64>, name: &str) -> ProcessMemoryAdvice {
    let Some(rss) = rss_mb else {
        return ProcessMemoryAdvice {
            rss_mb: 0.0,
            classification: RssClass::Unknown,
            note: format!(
                "no resident-memory sample for {name} — the service may be paused or was just \
                 launched; wait one fleetd tick (5s) and re-run `fleet_snapshot`."
            ),
        };
    };
    let (class, note) = if rss >= HEAVY_RSS_MB {
        (
            RssClass::Heavy,
            format!(
                "{name} holds {rss:.0} MB resident — heavy. Before stopping anything, check whether \
                 this is its documented behavior (a build, an index, a model server); if the \
                 memHistory trend is Climbing, treat it as a leak candidate, not a working set."
            ),
        )
    } else if rss >= NORMAL_RSS_MB {
        (
            RssClass::Normal,
            format!(
                "{name} holds {rss:.0} MB resident — within the ordinary daemon band \
                 ({}–{} MB). No action needed.",
                NORMAL_RSS_MB as i64,
                HEAVY_RSS_MB as i64
            ),
        )
    } else {
        (
            RssClass::Light,
            format!("{name} holds {rss:.0} MB resident — light; not a memory concern."),
        )
    };
    ProcessMemoryAdvice { rss_mb: rss, classification: class, note }
}

#[derive(Debug, Clone, PartialEq)]
pub struct PressureVerdict {
    pub level: PressureLevel,
    pub note: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PressureLevel {
    Healthy,
    Elevated,
    Critical,
}

pub fn classify_pressure(compressor_mb: f64, swap_used_mb: f64, total_physical_mb: f64) -> PressureVerdict {
    let compressed_ratio = if total_physical_mb > 0.0 {
        compressor_mb / total_physical_mb
    } else {
        0.0
    };
    let (level, note) = if swap_used_mb > 512.0 || compressed_ratio > 0.25 {
        (
            PressureLevel::Critical,
            format!(
                "critical memory pressure: {swap_used_mb:.0} MB swapped ({compressed_ratio:.0}% of \
                 physical compressed). Top memory holders are the candidates: run `fleet_top_memory`, \
                 then prefer `fleet_pause` on a heavy non-critical service to free its CPU while \
                 keeping its pages; `fleet_stop` only with an explicit reason — it does not restart."
            ),
        )
    } else if swap_used_mb > 64.0 || compressed_ratio > 0.10 {
        (
            PressureLevel::Elevated,
            format!(
                "elevated pressure: {swap_used_mb:.0} MB swapped, {compressor_mb:.0} MB compressed. \
                 Identify the top resident holders with `fleet_top_memory` and check their trends \
                 before acting; a Climbing trend outranks a high absolute number."
            ),
        )
    } else {
        (
            PressureLevel::Healthy,
            format!(
                "memory healthy: {swap_used_mb:.0} MB swapped, {compressor_mb:.0} MB compressed — \
                 within normal macOS housekeeping. Note the console clamps memory-used to the \
                 physical total because compressor counters can drift above it."
            ),
        )
    };
    PressureVerdict { level, note }
}

pub fn triage_rank(
    trend: &MemoryTrend,
    rss_class: RssClass,
    has_unanswered_mail: bool,
) -> u8 {
    let mut rank: u8 = 0;
    match trend.classification {
        TrendClass::Climbing => rank += 4,
        TrendClass::Creeping => rank += 2,
        TrendClass::Oscillating | TrendClass::Steady => {}
        TrendClass::InsufficientData => rank += 1,
    }
    match rss_class {
        RssClass::Heavy => rank += 2,
        RssClass::Normal => rank += 1,
        RssClass::Light | RssClass::Unknown => {}
    }
    if has_unanswered_mail {
        rank += 8;
    }
    rank
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn flat_history_is_steady() {
        let trend = classify_memory_trend(&[100.0; 12]);
        assert_eq!(trend.classification, TrendClass::Steady);
        assert!(trend.slope_mb_per_sample.unwrap().abs() < 0.01);
    }

    #[test]
    fn sustained_climb_is_a_leak_candidate() {
        let history: Vec<f64> = (0..20).map(|i| 200.0 + i as f64 * 4.0).collect();
        let trend = classify_memory_trend(&history);
        assert_eq!(trend.classification, TrendClass::Climbing);
        assert!(trend.slope_mb_per_sample.unwrap() > LEAK_SLOPE_MB_PER_SAMPLE);
        assert!(trend.note.contains("leak candidate"));
    }

    #[test]
    fn slow_creep_is_noted_not_alarmed() {
        let history: Vec<f64> = (0..20).map(|i| 200.0 + i as f64 * 0.2).collect();
        let trend = classify_memory_trend(&history);
        assert_eq!(trend.classification, TrendClass::Creeping);
    }

    #[test]
    fn oscillation_is_normal() {
        let history: Vec<f64> = (0..20)
            .map(|i| 500.0 + if i % 2 == 0 { 300.0 } else { 0.0 })
            .collect();
        let trend = classify_memory_trend(&history);
        assert_eq!(trend.classification, TrendClass::Oscillating);
    }

    #[test]
    fn short_history_is_honest_about_it() {
        let trend = classify_memory_trend(&[100.0, 102.0]);
        assert_eq!(trend.classification, TrendClass::InsufficientData);
        assert!(trend.note.contains("wait for more ticks"));
    }

    #[test]
    fn heavy_rss_gets_advice_not_a_command() {
        let advice = classify_process_memory(Some(2048.0), "model-server");
        assert_eq!(advice.classification, RssClass::Heavy);
        assert!(advice.note.contains("Before stopping"));
    }

    #[test]
    fn missing_rss_is_unknown_never_zero() {
        let advice = classify_process_memory(None, "fresh");
        assert_eq!(advice.classification, RssClass::Unknown);
        assert!(advice.note.contains("no resident-memory sample"));
    }

    #[test]
    fn pressure_thresholds_hold() {
        assert_eq!(
            classify_pressure(512.0, 32.0, 16_384.0).level,
            PressureLevel::Healthy
        );
        assert_eq!(
            classify_pressure(2_048.0, 128.0, 16_384.0).level,
            PressureLevel::Elevated
        );
        assert_eq!(
            classify_pressure(5_000.0, 2_048.0, 16_384.0).level,
            PressureLevel::Critical
        );
    }

    #[test]
    fn unanswered_mail_outranks_everything() {
        let steady = triage_rank(
            &MemoryTrend { classification: TrendClass::Steady, slope_mb_per_sample: Some(0.0), samples: 10, note: String::new() },
            RssClass::Light,
            true,
        );
        let leak = triage_rank(
            &MemoryTrend { classification: TrendClass::Climbing, slope_mb_per_sample: Some(4.0), samples: 10, note: String::new() },
            RssClass::Heavy,
            false,
        );
        assert!(steady > leak, "unanswered operator mail must outrank a leak candidate");
    }
}
