//! Layout and drawing math, free of GPUI types so it can be tested.
//!
//! Dial coordinates are screen coordinates in points: x to the right, y down,
//! relative to the dial's own box. Angles follow the mathematical convention
//! (counterclockwise from the positive x axis) and are converted when a point
//! is produced.

pub type Pt = (f32, f32);

/// The dial sweeps 240 degrees, from lower left (0%) over the top to lower
/// right (100%), like the Mac popover's gauges.
pub const DIAL_START_DEG: f32 = 210.0;
pub const DIAL_SWEEP_DEG: f32 = 240.0;
/// The red zone marks the top of the scale: the critical band above 90%.
pub const RED_ZONE: (f32, f32) = (0.9, 1.0);
/// Tick marks every 10%, longer at 0, 50 and 100.
pub const TICKS: usize = 11;

pub fn dial_angle(fraction: f32) -> f32 {
    (DIAL_START_DEG - DIAL_SWEEP_DEG * fraction.clamp(0.0, 1.0)).to_radians()
}

pub fn dial_point(center: Pt, radius: f32, fraction: f32) -> Pt {
    let a = dial_angle(fraction);
    (center.0 + radius * a.cos(), center.1 - radius * a.sin())
}

/// Center and radius of the largest dial that fits a `width` by `height`
/// box with `inset` points kept clear on every side. The 240 degree sweep
/// reaches 1.0 radius above the center and 0.5 below it.
pub fn dial_layout(width: f32, height: f32, inset: f32) -> (Pt, f32) {
    let radius = ((width - 2.0 * inset) / 2.0)
        .min((height - 2.0 * inset) / 1.5)
        .max(1.0);
    let center = (width / 2.0, inset + radius + ((height - 2.0 * inset) - 1.5 * radius) / 2.0);
    (center, radius)
}

/// Points along the dial arc from one fraction to another, no more than
/// `step_deg` apart, for drawing the arc as a polyline.
pub fn arc_points(center: Pt, radius: f32, from: f32, to: f32, step_deg: f32) -> Vec<Pt> {
    let (from, to) = (from.clamp(0.0, 1.0), to.clamp(0.0, 1.0));
    if to <= from {
        return Vec::new();
    }
    let span = (to - from) * DIAL_SWEEP_DEG;
    let steps = (span / step_deg.max(0.5)).ceil().max(1.0) as usize;
    (0..=steps)
        .map(|i| dial_point(center, radius, from + (to - from) * i as f32 / steps as f32))
        .collect()
}

/// Tick marks as (outer, inner, major) segments.
pub fn ticks(center: Pt, outer: f32, length: f32, major_length: f32) -> Vec<(Pt, Pt, bool)> {
    (0..TICKS)
        .map(|i| {
            let fraction = i as f32 / (TICKS - 1) as f32;
            let major = i == 0 || i == TICKS / 2 || i == TICKS - 1;
            let inner = outer - if major { major_length } else { length };
            (
                dial_point(center, outer, fraction),
                dial_point(center, inner, fraction),
                major,
            )
        })
        .collect()
}

/// The needle from the hub to its tip. Callers draw no needle at all when the
/// value is unavailable; there is no resting position that could be read as 0%.
pub fn needle(center: Pt, length: f32, fraction: f32) -> (Pt, Pt) {
    (center, dial_point(center, length, fraction))
}

/// How many cluster tiles fit per row and how wide each is.
pub fn tile_columns(available: f32, min_tile: f32, gap: f32) -> (usize, f32) {
    let available = available.max(min_tile);
    let columns = (((available + gap) / (min_tile + gap)).floor() as usize).max(1);
    let width = (available - gap * (columns - 1) as f32) / columns as f32;
    (columns, width)
}

/// Divide `cells` blocks among volumes in proportion to their total bytes,
/// then split each volume's blocks into used and free in proportion to its
/// used bytes. Every volume with bytes gets at least one block while there
/// are enough blocks. Returns `(used, free)` per volume.
pub fn volume_cells(volumes: &[(u64, u64)], cells: usize) -> Vec<(usize, usize)> {
    let total: u128 = volumes.iter().map(|(t, _)| u128::from(*t)).sum();
    if total == 0 || cells == 0 {
        return vec![(0, 0); volumes.len()];
    }
    // Largest remainder allocation.
    let mut alloc: Vec<usize> = Vec::with_capacity(volumes.len());
    let mut remainders: Vec<(u128, usize)> = Vec::with_capacity(volumes.len());
    for (i, (t, _)) in volumes.iter().enumerate() {
        let exact = u128::from(*t) * cells as u128;
        alloc.push((exact / total) as usize);
        remainders.push((exact % total, i));
    }
    let mut left = cells - alloc.iter().sum::<usize>();
    remainders.sort_by(|a, b| b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
    for (_, i) in remainders.iter() {
        if left == 0 {
            break;
        }
        alloc[*i] += 1;
        left -= 1;
    }
    // A volume with bytes but no block would vanish from the map; take one
    // block from the largest allocation for it.
    let nonzero = volumes.iter().filter(|(t, _)| *t > 0).count();
    if cells >= nonzero {
        for i in 0..volumes.len() {
            if volumes[i].0 > 0 && alloc[i] == 0 {
                if let Some(donor) = (0..alloc.len()).filter(|j| alloc[*j] > 1).max_by_key(|j| alloc[*j]) {
                    alloc[donor] -= 1;
                    alloc[i] = 1;
                }
            }
        }
    }
    volumes
        .iter()
        .zip(alloc)
        .map(|((t, u), blocks)| {
            if *t == 0 {
                return (0, blocks);
            }
            let used = ((u128::from((*u).min(*t)) * blocks as u128 + u128::from(*t) / 2)
                / u128::from(*t)) as usize;
            let used = used.min(blocks);
            (used, blocks - used)
        })
        .collect()
}

/// Tree-drawing prefixes for process lines given as (depth, last_child).
/// Roots (depth 0) get no prefix; each deeper line gets one column per
/// ancestor level, continuing the ancestor's vertical line while that
/// ancestor has later siblings.
pub fn tree_prefixes(lines: &[(usize, bool)]) -> Vec<String> {
    let mut open: Vec<bool> = Vec::new();
    lines
        .iter()
        .map(|&(depth, last)| {
            if depth == 0 {
                open.clear();
                return String::new();
            }
            let mut prefix = String::new();
            for level in 1..depth {
                prefix.push_str(if open.get(level).copied().unwrap_or(false) {
                    "│  "
                } else {
                    "   "
                });
            }
            prefix.push_str(if last { "└─ " } else { "├─ " });
            open.resize(depth + 1, false);
            open[depth] = !last;
            open.truncate(depth + 1);
            prefix
        })
        .collect()
}

/// Heights (0 to 1) for the last `count` history samples, right-aligned.
/// `None` stays `None`: an interval without a measurement is a gap.
pub fn spark_heights(history: &[Option<f64>], count: usize) -> Vec<Option<f32>> {
    let skip = history.len().saturating_sub(count);
    let mut out: Vec<Option<f32>> = vec![None; count.saturating_sub(history.len())];
    out.extend(
        history
            .iter()
            .skip(skip)
            .map(|v| v.filter(|x| x.is_finite()).map(|x| (x / 100.0).clamp(0.0, 1.0) as f32)),
    );
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn close(a: f32, b: f32) -> bool {
        (a - b).abs() < 0.01
    }

    #[test]
    fn dial_runs_from_lower_left_over_the_top_to_lower_right() {
        let c = (100.0, 100.0);
        let zero = dial_point(c, 50.0, 0.0);
        let half = dial_point(c, 50.0, 0.5);
        let full = dial_point(c, 50.0, 1.0);
        assert!(zero.0 < c.0 && zero.1 > c.1, "0% is lower left: {zero:?}");
        assert!(close(half.0, 100.0) && close(half.1, 50.0), "50% is straight up: {half:?}");
        assert!(full.0 > c.0 && full.1 > c.1, "100% is lower right: {full:?}");
        assert!(close(zero.1, full.1), "the sweep is symmetric");
        // Out-of-range fractions clamp to the ends of the scale.
        assert_eq!(dial_point(c, 50.0, 1.7), full);
        assert_eq!(dial_point(c, 50.0, -1.0), zero);
    }

    #[test]
    fn red_zone_sits_at_the_top_of_the_scale() {
        let c = (0.0, 0.0);
        let start = dial_point(c, 10.0, RED_ZONE.0);
        let end = dial_point(c, 10.0, RED_ZONE.1);
        // Right of center and descending toward the 100% end.
        assert!(start.0 > 0.0 && end.0 > 0.0, "red zone is on the high end");
        assert!(end.1 > start.1, "red zone ends at the bottom right");
        let arc = arc_points(c, 10.0, RED_ZONE.0, RED_ZONE.1, 2.0);
        assert!(arc.len() >= 13, "24 degrees at 2 degree steps");
        assert_eq!(arc.first().copied(), Some(start));
    }

    #[test]
    fn dial_fits_its_box() {
        for (w, h) in [(120.0, 100.0), (80.0, 200.0), (300.0, 90.0)] {
            let (c, r) = dial_layout(w, h, 6.0);
            for f in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let (x, y) = dial_point(c, r, f);
                assert!((5.9..=w - 5.9).contains(&x), "{w}x{h} f={f} x={x}");
                assert!((5.9..=h - 5.9).contains(&y), "{w}x{h} f={f} y={y}");
            }
        }
    }

    #[test]
    fn ticks_mark_every_tenth_with_three_majors() {
        let t = ticks((0.0, 0.0), 40.0, 4.0, 8.0);
        assert_eq!(t.len(), 11);
        assert_eq!(t.iter().filter(|(_, _, major)| *major).count(), 3);
        assert!(t[5].2, "50% is major");
    }

    #[test]
    fn empty_arc_for_zero_span() {
        assert!(arc_points((0.0, 0.0), 10.0, 0.4, 0.4, 3.0).is_empty());
        assert!(arc_points((0.0, 0.0), 10.0, 0.6, 0.4, 3.0).is_empty());
    }

    #[test]
    fn tile_columns_fill_the_width() {
        assert_eq!(tile_columns(300.0, 300.0, 14.0).0, 1);
        assert_eq!(tile_columns(614.0, 300.0, 14.0).0, 2);
        let (cols, w) = tile_columns(1000.0, 300.0, 14.0);
        assert_eq!(cols, 3);
        assert!(close(w * 3.0 + 28.0, 1000.0));
        assert_eq!(tile_columns(50.0, 300.0, 14.0).0, 1);
    }

    #[test]
    fn volume_cells_are_proportional_and_complete() {
        let gib = 1u64 << 30;
        let cells = volume_cells(&[(1000 * gib, 600 * gib), (500 * gib, 100 * gib)], 30);
        assert_eq!(cells.iter().map(|(u, f)| u + f).sum::<usize>(), 30);
        assert_eq!(cells[0].0 + cells[0].1, 20);
        assert_eq!(cells[0].0, 12);
        assert_eq!(cells[1], (2, 8));
    }

    #[test]
    fn tiny_volume_keeps_one_block() {
        let cells = volume_cells(&[(1_000_000, 0), (1, 1)], 10);
        assert_eq!(cells[1], (1, 0));
        assert_eq!(cells.iter().map(|(u, f)| u + f).sum::<usize>(), 10);
    }

    #[test]
    fn no_bytes_no_blocks() {
        assert_eq!(volume_cells(&[(0, 0)], 10), vec![(0, 0)]);
        assert!(volume_cells(&[], 10).is_empty());
    }

    #[test]
    fn tree_prefixes_continue_open_branches() {
        let lines = [
            (0, false), // fleetd
            (1, false), // api-gateway
            (2, false), // node
            (2, true),  // node
            (1, true),  // render-studio
            (2, true),  // child
            (0, false), // other root
        ];
        let p = tree_prefixes(&lines);
        assert_eq!(p[0], "");
        assert_eq!(p[1], "├─ ");
        assert_eq!(p[2], "│  ├─ ");
        assert_eq!(p[3], "│  └─ ");
        assert_eq!(p[4], "└─ ");
        assert_eq!(p[5], "   └─ ");
        assert_eq!(p[6], "");
    }

    #[test]
    fn spark_keeps_gaps_and_right_aligns() {
        let h = spark_heights(&[Some(50.0), None, Some(150.0)], 5);
        assert_eq!(h, vec![None, None, Some(0.5), None, Some(1.0)]);
        let long: Vec<Option<f64>> = (0..60).map(|i| Some(f64::from(i))).collect();
        let h = spark_heights(&long, 40);
        assert_eq!(h.len(), 40);
        assert_eq!(h[0], Some(0.2));
    }
}
