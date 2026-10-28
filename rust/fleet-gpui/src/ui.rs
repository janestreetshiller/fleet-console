//! Elements shared by the quick view and the full window: the logo, dials,
//! segmented gauges, the disk grid, rate bars, history sparks, buttons and
//! the connection banner. Hard edges, 1px line borders, monospace text; color
//! always travels with a word.

use crate::geometry::{self, Pt};
use crate::logo::{self, Tone};
use crate::palette::Colors;
use fleet_ui_core::observe::Phase;
use fleet_ui_core::thresholds::Level;
use fleet_ui_core::views::{Connection, Control, DiskGrid, Gauge, Rate};
use gpui::{
    canvas, div, fill, point, prelude::*, px, relative, size, AnyView, App, Bounds, Div,
    ElementId, FontWeight, Hsla, PathBuilder, Pixels, Point, SharedString, Stateful, Window,
};

pub const TEXT_SIZE: f32 = 12.0;
pub const SMALL_SIZE: f32 = 11.0;

/// The font chosen at start-up from what the system has installed.
pub struct UiFont(pub SharedString);

impl gpui::Global for UiFont {}

pub fn ui_font(cx: &App) -> SharedString {
    cx.try_global::<UiFont>()
        .map(|f| f.0.clone())
        .unwrap_or_else(|| "Menlo".into())
}

fn to_screen(origin: Point<Pixels>, p: Pt) -> Point<Pixels> {
    point(origin.x + px(p.0), origin.y + px(p.1))
}

pub fn stroke(window: &mut Window, origin: Point<Pixels>, points: &[Pt], width: f32, color: Hsla) {
    if points.len() < 2 {
        return;
    }
    let mut builder = PathBuilder::stroke(px(width));
    builder.move_to(to_screen(origin, points[0]));
    for p in &points[1..] {
        builder.line_to(to_screen(origin, *p));
    }
    if let Ok(path) = builder.build() {
        window.paint_path(path, color);
    }
}

/// A dashed polyline stroke, for the map's route lines between the
/// controller and the agents it talks to.
pub fn stroke_dashed(
    window: &mut Window,
    origin: Point<Pixels>,
    points: &[Pt],
    width: f32,
    color: Hsla,
    dash: &[f32],
) {
    if points.len() < 2 || dash.is_empty() {
        return;
    }
    let dash: Vec<Pixels> = dash.iter().map(|d| px(*d)).collect();
    let mut builder = PathBuilder::stroke(px(width)).dash_array(&dash);
    builder.move_to(to_screen(origin, points[0]));
    for p in &points[1..] {
        builder.line_to(to_screen(origin, *p));
    }
    if let Ok(path) = builder.build() {
        window.paint_path(path, color);
    }
}

/// A filled disc, the map's node plate. A 24-gon reads as a circle at the
/// sizes the map draws and settles without going through lyon's arc handling.
pub fn disc(window: &mut Window, origin: Point<Pixels>, center: Pt, radius: f32, color: Hsla) {
    if radius <= 0.0 {
        return;
    }
    let center = to_screen(origin, center);
    let mut builder = PathBuilder::fill();
    let segments = 24;
    for i in 0..=segments {
        let angle = std::f32::consts::TAU * i as f32 / segments as f32;
        let p = point(
            center.x + px(angle.cos() * radius),
            center.y + px(angle.sin() * radius),
        );
        if i == 0 {
            builder.move_to(p);
        } else {
            builder.line_to(p);
        }
    }
    if let Ok(path) = builder.build() {
        window.paint_path(path, color);
    }
}

/// The F/C logo drawn from its cell grid. `cell` is the cell edge in points.
pub fn logo(colors: Colors, cell: f32) -> impl IntoElement {
    let (bright, dark, bg) = (colors.bright, colors.dark, colors.bg);
    canvas(
        |_, _, _| {},
        move |bounds, _, window, _| {
            let o = bounds.origin;
            for (row, column, tone) in logo::cells() {
                let x = o.x + px(column as f32 * cell);
                let y = o.y + px(row as f32 * cell);
                match tone {
                    Tone::Bright | Tone::Dark => {
                        let c = if tone == Tone::Bright { bright } else { dark };
                        window.paint_quad(fill(Bounds::new(point(x, y), size(px(cell), px(cell))), c));
                    }
                    Tone::Dither => {
                        let half = cell / 2.0;
                        for (dx, dy, c) in [
                            (0.0, 0.0, bright),
                            (half, 0.0, dark),
                            (0.0, half, dark),
                            (half, half, bright),
                        ] {
                            window.paint_quad(fill(
                                Bounds::new(point(x + px(dx), y + px(dy)), size(px(half), px(half))),
                                c,
                            ));
                        }
                    }
                }
                // The scanline through each cell, at sizes where it reads.
                if cell >= 6.0 {
                    window.paint_quad(fill(
                        Bounds::new(
                            point(x, y + px(cell * 0.46)),
                            size(px(cell), px((cell * 0.08).max(1.0))),
                        ),
                        bg,
                    ));
                }
            }
        },
    )
    .w(px(cell * logo::COLUMNS as f32))
    .h(px(cell * logo::ROWS as f32))
    .flex_shrink_0()
}

/// A dial: track, red zone at the top of the scale, tick marks, the value
/// arc and the needle. An unavailable value draws no arc and no needle.
pub fn dial(gauge: &Gauge, colors: Colors, width: f32, height: f32) -> impl IntoElement {
    let fraction = gauge.metric.fraction().map(|f| f as f32);
    canvas(
        |_, _, _| {},
        move |bounds, _, window, _| {
            let o = bounds.origin;
            let (center, radius) = geometry::dial_layout(width, height, 8.0);
            let ring = radius - 4.0;
            stroke(
                window,
                o,
                &geometry::arc_points(center, ring, 0.0, 1.0, 3.0),
                5.0,
                colors.segment_off,
            );
            stroke(
                window,
                o,
                &geometry::arc_points(center, radius + 1.0, geometry::RED_ZONE.0, geometry::RED_ZONE.1, 2.0),
                3.0,
                colors.crit,
            );
            for (outer, inner, major) in geometry::ticks(center, ring - 5.0, 3.0, 6.0) {
                stroke(window, o, &[outer, inner], if major { 1.5 } else { 1.0 }, colors.dim);
            }
            if let Some(f) = fraction {
                stroke(
                    window,
                    o,
                    &geometry::arc_points(center, ring, 0.0, f, 3.0),
                    5.0,
                    colors.bright,
                );
                let (hub, tip) = geometry::needle(center, ring - 9.0, f);
                stroke(window, o, &[hub, tip], 2.0, colors.text);
                window.paint_quad(fill(
                    Bounds::new(
                        to_screen(o, (center.0 - 3.0, center.1 - 3.0)),
                        size(px(6.0), px(6.0)),
                    ),
                    colors.text,
                ));
            }
        },
    )
    .w(px(width))
    .h(px(height))
    .flex_shrink_0()
}

/// The words under a gauge: its detail when measured, the reason when not,
/// and the band's name when it is warning or critical.
pub fn gauge_caption(gauge: &Gauge) -> String {
    match gauge.metric.reason() {
        Some(reason) => reason.label().to_string(),
        None => match gauge.level {
            Some(level @ (Level::Warning | Level::Critical)) if gauge.detail.is_empty() => {
                level.label().to_string()
            }
            Some(level @ (Level::Warning | Level::Critical)) => {
                format!("{}, {}", level.label(), gauge.detail)
            }
            _ => gauge.detail.clone(),
        },
    }
}

/// `Gauge::spoken` without the trailing separator it leaves when a measured
/// gauge has no detail.
pub fn spoken(gauge: &Gauge) -> String {
    gauge
        .spoken()
        .trim_end_matches(|c| c == ',' || c == ' ')
        .to_string()
}

/// Twenty segments, each colored by its own position's band.
pub fn segments(cells: &[Option<Level>], colors: Colors, height: f32) -> Div {
    div()
        .flex()
        .flex_row()
        .gap(px(2.0))
        .h(px(height))
        .w_full()
        .children(cells.iter().map(|cell| {
            div()
                .flex_1()
                .h_full()
                .bg(cell.map(|l| colors.level(l)).unwrap_or(colors.segment_off))
        }))
}

/// The quick view's 5 by 4 disk grid, filled in reading order.
pub fn disk_grid(disk: &DiskGrid, colors: Colors, cell: f32) -> Div {
    let gap = 2.0;
    div()
        .flex()
        .flex_col()
        .gap(px(gap))
        .children(disk.cells.chunks(5).map(|row| {
            div().flex().flex_row().gap(px(gap)).children(row.iter().map(|c| {
                div()
                    .w(px(cell))
                    .h(px(cell))
                    .bg(c.map(|l| colors.level(l)).unwrap_or(colors.segment_off))
            }))
        }))
}

/// A horizontal bar: `fraction` of the width lit, the rest unlit.
pub fn bar(fraction: Option<f64>, colors: Colors, height: f32) -> Div {
    let lit = fraction.map(|f| f.clamp(0.0, 1.0) as f32).unwrap_or(0.0);
    div()
        .w_full()
        .h(px(height))
        .bg(colors.segment_off)
        .child(div().h_full().w(relative(lit)).bg(colors.dark))
}

/// A network rate: label, value, bar and, when unavailable, the reason.
pub fn rate(rate: &Rate, colors: Colors) -> Div {
    div()
        .flex()
        .flex_col()
        .gap(px(3.0))
        .w_full()
        .child(
            div()
                .flex()
                .flex_row()
                .justify_between()
                .child(div().text_color(colors.dim).child(rate.label))
                .child(div().text_color(colors.text).child(rate.text.clone())),
        )
        .child(bar(rate.fraction, colors, 8.0))
        .when_some(rate.metric.reason(), |d, reason| {
            d.child(
                div()
                    .text_size(px(SMALL_SIZE))
                    .text_color(colors.dim)
                    .child(reason.label()),
            )
        })
}

/// A history spark: one bar per sample, a gap where nothing was measured.
pub fn spark(history: &[Option<f64>], colors: Colors, count: usize, height: f32) -> Div {
    div()
        .flex()
        .flex_row()
        .items_end()
        .gap(px(1.0))
        .h(px(height))
        .w_full()
        .children(geometry::spark_heights(history, count).into_iter().map(|h| {
            let bar = div().flex_1();
            match h {
                Some(h) => bar.h(relative(h.max(0.04))).bg(colors.dark),
                None => bar.h(px(0.0)),
            }
        }))
}

/// A one-line hover text. GPUI 0.2.2 has no accessibility tree, so the same
/// text is always also visible somewhere on screen; this is a convenience.
pub struct TextTooltip {
    text: SharedString,
    colors: Colors,
    font: SharedString,
}

impl Render for TextTooltip {
    fn render(&mut self, _window: &mut Window, _cx: &mut gpui::Context<Self>) -> impl IntoElement {
        div()
            .font_family(self.font.clone())
            .text_size(px(SMALL_SIZE))
            .bg(self.colors.panel_fill())
            .text_color(self.colors.text)
            .border_1()
            .border_color(self.colors.line)
            .px(px(6.0))
            .py(px(3.0))
            .max_w(px(420.0))
            .child(self.text.clone())
    }
}

pub fn tooltip(text: impl Into<SharedString>, colors: Colors) -> impl Fn(&mut Window, &mut App) -> AnyView + 'static {
    let text = text.into();
    move |_window, cx| {
        let font = ui_font(cx);
        let text = text.clone();
        cx.new(|_| TextTooltip { text, colors, font }).into()
    }
}

/// A bordered text button. A refused control is drawn dim, takes no clicks,
/// and carries its reason as a tooltip; callers also print the reason.
pub fn button(
    id: impl Into<ElementId>,
    label: impl Into<SharedString>,
    control: &Control,
    colors: Colors,
) -> Stateful<Div> {
    let label = label.into();
    let base = div()
        .id(id)
        .flex_shrink_0()
        .px(px(8.0))
        .py(px(2.0))
        .border_1()
        .whitespace_nowrap();
    match control {
        Control::Allowed => base
            .border_color(colors.dark)
            .text_color(colors.bright)
            .cursor_pointer()
            .hover(|s| s.bg(colors.panel_fill()))
            .active(|s| s.bg(colors.dark).text_color(colors.selected_text))
            .child(label),
        Control::Refused(reason) => base
            .border_color(colors.segment_off)
            .text_color(colors.dim)
            .tooltip(tooltip(format!("{label} unavailable: {reason}"), colors))
            .child(label),
    }
}

/// A row in a list: the selected row is a solid dark-green bar with the
/// selected-text color, as in the design package.
pub fn row(id: impl Into<ElementId>, selected: bool, colors: Colors) -> Stateful<Div> {
    div()
        .id(id)
        .flex()
        .flex_row()
        .w_full()
        .px(px(6.0))
        .cursor_pointer()
        .when(selected, |d| d.bg(colors.dark).text_color(colors.selected_text))
        .when(!selected, |d| d.hover(|s| s.bg(colors.panel_fill())))
}

/// A fixed-width table cell that clips instead of wrapping.
pub fn cell(width: f32, text: impl Into<SharedString>) -> Div {
    div()
        .w(px(width))
        .flex_shrink_0()
        .overflow_hidden()
        .whitespace_nowrap()
        .text_ellipsis()
        .pr(px(8.0))
        .child(text.into())
}

/// A flexible table cell that takes the remaining width and clips.
pub fn cell_flex(text: impl Into<SharedString>) -> Div {
    div()
        .flex_1()
        .min_w(px(0.0))
        .overflow_hidden()
        .whitespace_nowrap()
        .text_ellipsis()
        .pr(px(8.0))
        .child(text.into())
}

/// A bordered panel with a title in the top line.
pub fn panel(title: impl Into<SharedString>, colors: Colors) -> Div {
    div()
        .flex()
        .flex_col()
        .border_1()
        .border_color(colors.line)
        .bg(colors.panel_fill())
        .child(
            div()
                .px(px(8.0))
                .py(px(4.0))
                .border_b_1()
                .border_color(colors.line)
                .text_color(colors.bright)
                .child(title.into()),
        )
}

pub fn phase_color(phase: Phase, colors: Colors) -> Hsla {
    match phase {
        Phase::Live => colors.bright,
        Phase::Loading => colors.info,
        Phase::Stale => colors.warn,
        Phase::Disconnected | Phase::Error => colors.crit,
    }
}

/// The controller's state in words, shown before any value whenever the
/// controller feed is not live: loading, stale with its age, disconnected or
/// error with the detail the controller connection reported.
pub fn connection_banner(connection: &Connection, colors: Colors, compact: bool) -> Option<Div> {
    if connection.phase == Phase::Live {
        return None;
    }
    let accent = phase_color(connection.phase, colors);
    let mut lines: Vec<String> = Vec::new();
    if let Some(detail) = &connection.detail {
        lines.push(detail.clone());
    }
    if !matches!(connection.phase, Phase::Stale) {
        if let Some(age) = &connection.age {
            lines.push(format!("last successful read {age}"));
        }
    }
    if !compact {
        lines.push(format!("socket {}", connection.socket_label));
    }
    Some(
        div()
            .flex()
            .flex_col()
            .gap(px(2.0))
            .border_1()
            .border_color(accent)
            .bg(colors.panel_fill())
            .px(px(10.0))
            .py(px(6.0))
            .child(
                div()
                    .flex()
                    .flex_row()
                    .gap(px(8.0))
                    .child(
                        div()
                            .text_color(accent)
                            .font_weight(FontWeight::BOLD)
                            .child(connection.phase.label()),
                    )
                    .child(div().text_color(colors.text).child(connection.summary.clone())),
            )
            .children(lines.into_iter().map(|l| {
                div()
                    .text_size(px(SMALL_SIZE))
                    .text_color(colors.dim)
                    .child(l)
            })),
    )
}

/// A small 2 by 2 grid icon for the "open window" button.
pub fn grid_icon(color: Hsla) -> Div {
    let square = || div().w(px(4.0)).h(px(4.0)).bg(color);
    div()
        .flex()
        .flex_col()
        .gap(px(1.0))
        .child(div().flex().flex_row().gap(px(1.0)).child(square()).child(square()))
        .child(div().flex().flex_row().gap(px(1.0)).child(square()).child(square()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use fleet_ui_core::observe::{Metric, Reason};

    fn gauge(metric: Metric, level: Option<Level>, detail: &str) -> Gauge {
        Gauge {
            label: "Memory",
            metric,
            level,
            text: fleet_ui_core::format::percent(metric),
            detail: detail.into(),
        }
    }

    #[test]
    fn captions_say_why_a_value_is_missing() {
        let g = gauge(Metric::Unavailable(Reason::AwaitingSample), None, "");
        assert_eq!(gauge_caption(&g), "awaiting second sample");
        let g = gauge(Metric::Measured(40.0), Some(Level::Normal), "12 GB of 32 GB");
        assert_eq!(gauge_caption(&g), "12 GB of 32 GB");
        let g = gauge(Metric::Measured(95.0), Some(Level::Critical), "30 GB of 32 GB");
        assert_eq!(gauge_caption(&g), "critical, 30 GB of 32 GB");
    }

    #[test]
    fn spoken_text_has_no_dangling_separator() {
        let g = gauge(Metric::Measured(40.0), Some(Level::Normal), "");
        assert_eq!(spoken(&g), "Memory 40%");
        let g = gauge(Metric::Unavailable(Reason::NotMeasured), None, "");
        assert_eq!(spoken(&g), "Memory unavailable, not measured on this platform");
    }
}
