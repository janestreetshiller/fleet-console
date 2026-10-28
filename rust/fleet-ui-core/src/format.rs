//! Text forms shared by both clients. Unavailable values render as `--`.

use crate::observe::Metric;

pub const UNAVAILABLE: &str = "--";

pub fn percent(metric: Metric) -> String {
    match metric.value() {
        Some(v) => format!("{v:.0}%"),
        None => UNAVAILABLE.to_string(),
    }
}

pub fn bytes(value: u64) -> String {
    const UNITS: [&str; 6] = ["B", "KB", "MB", "GB", "TB", "PB"];
    let mut size = value as f64;
    let mut unit = 0;
    while size >= 1024.0 && unit < UNITS.len() - 1 {
        size /= 1024.0;
        unit += 1;
    }
    if unit == 0 {
        format!("{value} B")
    } else if size >= 100.0 {
        format!("{size:.0} {}", UNITS[unit])
    } else {
        format!("{size:.1} {}", UNITS[unit])
    }
}

pub fn megabytes(mb: Option<f64>) -> String {
    match mb {
        Some(v) if v.is_finite() && v >= 0.0 => bytes((v * 1024.0 * 1024.0) as u64),
        _ => UNAVAILABLE.to_string(),
    }
}

pub fn rate(metric: Metric) -> String {
    match metric.value() {
        Some(v) if v >= 0.0 => format!("{}/s", bytes(v as u64)),
        _ => UNAVAILABLE.to_string(),
    }
}

/// `3d 4h`, `14m`, `42s`. Two units at most, matching `Fmt.duration` in Swift.
pub fn duration(seconds: f64) -> String {
    if !seconds.is_finite() || seconds < 0.0 {
        return UNAVAILABLE.to_string();
    }
    let s = seconds as u64;
    let (d, h, m) = (s / 86_400, (s % 86_400) / 3_600, (s % 3_600) / 60);
    if d > 0 {
        format!("{d}d {h}h")
    } else if h > 0 {
        format!("{h}h {m}m")
    } else if m > 0 {
        format!("{m}m")
    } else {
        format!("{s}s")
    }
}

/// `12s ago`, `4m ago`; `in 20m` for a future time such as a lease expiry.
pub fn relative(then: f64, now: f64) -> String {
    let delta = now - then;
    if delta >= 0.0 {
        format!("{} ago", duration(delta))
    } else {
        format!("in {}", duration(-delta))
    }
}

pub fn ports(ports: &[i64]) -> String {
    if ports.is_empty() {
        return "no ports".to_string();
    }
    let shown: Vec<String> = ports.iter().take(4).map(|p| format!(":{p}")).collect();
    let more = ports.len().saturating_sub(4);
    if more > 0 {
        format!("{} and {more} more", shown.join(" "))
    } else {
        shown.join(" ")
    }
}

/// Clip to a display width in characters, never splitting a code point.
pub fn clip(text: &str, width: usize) -> String {
    if text.chars().count() <= width {
        return text.to_string();
    }
    if width == 0 {
        return String::new();
    }
    let mut out: String = text.chars().take(width.saturating_sub(1)).collect();
    out.push('…');
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::observe::Reason;

    #[test]
    fn unavailable_is_dashes() {
        assert_eq!(percent(Metric::Unavailable(Reason::NotMeasured)), "--");
        assert_eq!(rate(Metric::Unavailable(Reason::AwaitingSample)), "--");
        assert_eq!(megabytes(None), "--");
    }

    #[test]
    fn sizes_and_durations() {
        assert_eq!(bytes(512), "512 B");
        assert_eq!(bytes(1536), "1.5 KB");
        assert_eq!(bytes(250 * 1024 * 1024), "250 MB");
        assert_eq!(duration(42.0), "42s");
        assert_eq!(duration(3_700.0), "1h 1m");
        assert_eq!(duration(3.0 * 86_400.0 + 4.0 * 3_600.0), "3d 4h");
        assert_eq!(relative(100.0, 160.0), "1m ago");
        assert_eq!(relative(200.0, 80.0), "in 2m");
    }

    #[test]
    fn clip_respects_code_points() {
        assert_eq!(clip("añb", 3), "añb");
        assert_eq!(clip("ñññññ", 3), "ññ…");
    }

    #[test]
    fn port_lists_are_bounded() {
        assert_eq!(ports(&[]), "no ports");
        assert_eq!(ports(&[1, 2, 3, 4, 5, 6]), ":1 :2 :3 :4 and 2 more");
    }
}
