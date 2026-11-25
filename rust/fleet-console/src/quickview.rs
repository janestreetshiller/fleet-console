
use gpui::{
    canvas, div, point, px, relative, rgb, rgba, AppContext, Context, Hsla, IntoElement, Path,
    PathBuilder, Pixels, Render, Window,
};
use gpui::{InteractiveElement, ParentElement, StatefulInteractiveElement, Styled};

use crate::sampler::{Pressure, Sample};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tone {
    Good,
    Warn,
    Bad,
    Neutral,
    Unknown,
}

pub fn utilization_tone(share: f64) -> Tone {
    if share < 0.75 {
        Tone::Good
    } else if share < 0.90 {
        Tone::Warn
    } else {
        Tone::Bad
    }
}

pub fn free_space_tone(used_share: f64) -> Tone {
    if used_share < 0.85 {
        Tone::Good
    } else if used_share < 0.95 {
        Tone::Warn
    } else {
        Tone::Bad
    }
}

pub fn memory_tone(share: f64, pressure: Pressure) -> Tone {
    match pressure {
        Pressure::Critical => Tone::Bad,
        Pressure::Warning => Tone::Warn,
        Pressure::Normal => Tone::Good,
        Pressure::Unknown => utilization_tone(share),
    }
}

pub fn tone_color(tone: Tone, alpha_scale: f32) -> Hsla {
    let mut hsla: Hsla = match tone {
        Tone::Good => rgb(0x34C759).into(),
        Tone::Warn => rgb(0xFF9500).into(),
        Tone::Bad => rgb(0xFF3B30).into(),
        Tone::Neutral => rgb(0x8E8E93).into(),
        Tone::Unknown => rgba(0x8E8E9380).into(),
    };
    hsla.a *= alpha_scale;
    hsla
}

fn indicator_off() -> Hsla {
    rgba(0x8E8E9340).into()
}

fn valid_share(value: Option<f64>) -> Option<f64> {
    value.filter(|share| share.is_finite() && (0.0..=1.0).contains(share))
}

pub fn fmt_percent(value: Option<f64>) -> String {
    match value {
        Some(share) => format!("{}%", (share * 100.0).round() as i64),
        None => "—".to_string(),
    }
}

pub fn fmt_bytes(bytes: u64) -> String {
    if bytes == 0 {
        return "0 bytes".to_string();
    }
    const UNITS: [&str; 6] = ["bytes", "KB", "MB", "GB", "TB", "PB"];
    let mut value = bytes as f64;
    let mut unit = 0;
    while value >= 1000.0 && unit < UNITS.len() - 1 {
        value /= 1000.0;
        unit += 1;
    }
    if unit == 0 {
        format!("{} bytes", bytes)
    } else if value < 10.0 {
        let text = format!("{value:.1}");
        format!("{} {}", text.trim_end_matches(".0"), UNITS[unit])
    } else {
        format!("{} {}", value.round() as i64, UNITS[unit])
    }
}

pub fn fmt_rate(bytes_per_second: Option<f64>) -> String {
    match bytes_per_second {
        None => "—".to_string(),
        Some(rate) if !rate.is_finite() || rate < 0.0 => "—".to_string(),
        Some(rate) if rate < 1024.0 => "0 KB/s".to_string(),
        Some(rate) => format!("{}/s", fmt_bytes(rate as u64)),
    }
}

fn rate_fraction(bytes_per_second: Option<f64>) -> Option<f64> {
    bytes_per_second
        .filter(|rate| rate.is_finite() && *rate >= 0.0)
        .map(|rate| (rate.ln_1p() / 1_000_000_000f64.ln_1p()).clamp(0.0, 1.0))
}

const INSTRUMENT: f32 = 90.0;
const SWEEP_START: f32 = 150.0;
const SWEEP_DEGREES: f32 = 240.0;
const REDLINE_START: f64 = 0.90;

fn arc_path(
    cx: f32,
    cy: f32,
    radius: f32,
    start_deg: f32,
    end_deg: f32,
    width: f32,
) -> Path<Pixels> {
    let mut builder = PathBuilder::stroke(px(width));
    let steps = 48;
    for i in 0..=steps {
        let deg = start_deg + (end_deg - start_deg) * (i as f32 / steps as f32);
        let rad = deg.to_radians();
        let p = point(px(cx + radius * rad.cos()), px(cy + radius * rad.sin()));
        if i == 0 {
            builder.move_to(p);
        } else {
            builder.line_to(p);
        }
    }
    builder.build().expect("arc path")
}

fn gauge_canvas(value: Option<f64>, tone: Tone) -> impl IntoElement {
    let element = canvas(
        move |bounds, _window, _cx| {
            let d: f32 = bounds.size.width.min(bounds.size.height).into();
            let cx: f32 =
                f32::from(bounds.origin.x) + f32::from(bounds.size.width) / 2.0;
            let cy: f32 =
                f32::from(bounds.origin.y) + f32::from(bounds.size.height) / 2.0;
            let mut paths: Vec<(Path<Pixels>, Hsla)> = Vec::new();
            paths.push((
                arc_path(cx, cy, d / 2.0 - 1.0, 0.0, 360.0, 1.0),
                rgba(0xFFFFFF2E).into(),
            ));
            let outer = d / 2.0 - d * 0.09;
            for step in 0..=40 {
                let major = step % 5 == 0;
                let inner = outer - d * if major { 0.085 } else { 0.045 };
                let rad =
                    (SWEEP_START + SWEEP_DEGREES * (step as f32 / 40.0)).to_radians();
                let mut builder = PathBuilder::stroke(px(if major { 1.2 } else { 0.7 }));
                builder.move_to(point(
                    px(cx + inner * rad.cos()),
                    px(cy + inner * rad.sin()),
                ));
                builder.line_to(point(
                    px(cx + outer * rad.cos()),
                    px(cy + outer * rad.sin()),
                ));
                paths.push((
                    builder.build().expect("tick path"),
                    if major {
                        rgba(0xFFFFFFBF).into()
                    } else {
                        indicator_off()
                    },
                ));
            }
            let fraction = value.map(|share| share.clamp(0.0, 1.0)).unwrap_or(0.0) as f32;
            let arc_radius = d * 0.40;
            let arc_width = d * 0.075;
            paths.push((
                arc_path(
                    cx,
                    cy,
                    arc_radius,
                    SWEEP_START,
                    SWEEP_START + SWEEP_DEGREES,
                    arc_width,
                ),
                indicator_off(),
            ));
            paths.push((
                arc_path(
                    cx,
                    cy,
                    arc_radius,
                    SWEEP_START + SWEEP_DEGREES * (REDLINE_START as f32),
                    SWEEP_START + SWEEP_DEGREES,
                    arc_width,
                ),
                tone_color(Tone::Bad, 0.35),
            ));
            if value.is_some() {
                paths.push((
                    arc_path(
                        cx,
                        cy,
                        arc_radius,
                        SWEEP_START,
                        SWEEP_START + SWEEP_DEGREES * fraction,
                        arc_width,
                    ),
                    tone_color(tone, 0.75),
                ));
            }
            let angle = (SWEEP_START + SWEEP_DEGREES * fraction).to_radians();
            let (sin, cos) = angle.sin_cos();
            let rotate = |x: f32, y: f32| {
                point(px(cx + x * cos - y * sin), px(cy + x * sin + y * cos))
            };
            let length = d * 0.36;
            let tail = d * 0.09;
            let half = d * 0.022;
            let mut needle = PathBuilder::fill();
            needle.move_to(rotate(-tail, -half * 0.7));
            needle.line_to(rotate(length, -half * 0.45));
            needle.line_to(rotate(length, half * 0.45));
            needle.line_to(rotate(-tail, half * 0.7));
            needle.close();
            paths.push((
                needle.build().expect("needle path"),
                if value.is_some() {
                    tone_color(tone, 1.0)
                } else {
                    rgb(0x636366).into()
                },
            ));
            let hub_radius = d * 0.07;
            let mut hub = PathBuilder::fill();
            let steps = 32;
            for i in 0..=steps {
                let rad = (i as f32 / steps as f32) * std::f32::consts::TAU;
                let p = point(
                    px(cx + hub_radius * rad.cos()),
                    px(cy + hub_radius * rad.sin()),
                );
                if i == 0 {
                    hub.move_to(p);
                } else {
                    hub.line_to(p);
                }
            }
            hub.close();
            paths.push((hub.build().expect("hub path"), rgb(0x2C2C2E).into()));
            paths
        },
        move |_bounds, paths, window, _cx| {
            for (path, color) in paths {
                window.paint_path(path, color);
            }
        },
    );
    element.w(px(INSTRUMENT)).h(px(INSTRUMENT))
}

fn gauge(value: Option<f64>, tone: Tone, readout: String) -> impl IntoElement {
    div()
        .relative()
        .w(px(INSTRUMENT))
        .h(px(INSTRUMENT))
        .child(gauge_canvas(value, tone))
        .child(
            div()
                .absolute()
                .bottom(px(8.0))
                .w_full()
                .text_center()
                .text_xs()
                .text_color(if value.is_some() {
                    rgb(0xFFFFFF)
                } else {
                    rgb(0x636366)
                })
                .child(readout),
        )
}

fn disk_grid(share: Option<f64>) -> impl IntoElement {
    let filled = share
        .map(|value| (value * 20.0).round() as i32)
        .unwrap_or(0);
    let mut rows = Vec::new();
    for row in 0..4 {
        let mut cells = div().flex().flex_row().gap(px(3.0));
        for col in 0..5 {
            let index = row * 5 + col;
            let color = if index < filled {
                tone_color(free_space_tone((index + 1) as f64 / 20.0), 1.0)
            } else {
                indicator_off()
            };
            cells = cells.child(
                div()
                    .flex_1()
                    .h(px(12.0))
                    .rounded(px(2.0))
                    .bg(color),
            );
        }
        rows.push(cells);
    }
    let mut grid = div().flex().flex_col().gap(px(3.0)).w(px(INSTRUMENT));
    for row in rows {
        grid = grid.child(row);
    }
    div()
        .flex()
        .flex_col()
        .gap(px(8.0))
        .child(grid)
        .child(
            div()
                .w_full()
                .text_center()
                .text_xs()
                .text_color(rgb(0xFFFFFF))
                .child(fmt_percent(share)),
        )
}

fn rate_row(arrow: &str, value: Option<f64>) -> impl IntoElement {
    let fraction = rate_fraction(value);
    div()
        .flex()
        .flex_col()
        .gap(px(5.0))
        .child(
            div()
                .flex()
                .flex_row()
                .gap(px(4.0))
                .text_xs()
                .child(div().text_color(rgb(0x8E8E93)).child(arrow.to_string()))
                .child(div().text_color(rgb(0xFFFFFF)).child(fmt_rate(value))),
        )
        .child(
            div()
                .relative()
                .w_full()
                .h(px(7.0))
                .rounded(px(2.0))
                .bg(indicator_off())
                .children(fraction.map(|fraction| {
                    div()
                        .absolute()
                        .left_0()
                        .top_0()
                        .h_full()
                        .w(relative(fraction as f32))
                        .rounded(px(2.0))
                        .bg(rgb(0xF17B33))
                })),
        )
}

fn network(sample: Option<&Sample>) -> impl IntoElement {
    div()
        .flex()
        .flex_col()
        .gap(px(12.0))
        .w(px(INSTRUMENT))
        .pt(px(6.0))
        .child(rate_row("↓", sample.and_then(|s| s.net_down_bps)))
        .child(rate_row("↑", sample.and_then(|s| s.net_up_bps)))
}

struct TextTooltip(String);

impl Render for TextTooltip {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .px(px(8.0))
            .py(px(4.0))
            .rounded(px(6.0))
            .bg(rgb(0x2C2C2E))
            .text_xs()
            .text_color(rgb(0xFFFFFF))
            .child(self.0.clone())
    }
}

fn instrument(
    title: &str,
    help: Option<String>,
    content: impl IntoElement,
) -> impl IntoElement {
    let column = div()
        .id(gpui::SharedString::from(format!("qv-{title}")))
        .flex()
        .flex_col()
        .gap(px(12.0))
        .flex_1()
        .child(
            div()
                .text_xs()
                .text_color(rgb(0x8E8E93))
                .child(title.to_string()),
        )
        .child(div().h(px(INSTRUMENT)).child(content));
    match help {
        Some(help) => column
            .tooltip(move |_window, cx| {
                let help = help.clone();
                cx.new(|_| TextTooltip(help)).into()
            })
            .into_any_element(),
        None => column.into_any_element(),
    }
}

pub fn quick_view(sample: Option<&Sample>) -> impl IntoElement {
    let cpu_share = valid_share(sample.and_then(|s| s.cpu_share));
    let cpu_tone = cpu_share.map(utilization_tone).unwrap_or(Tone::Unknown);
    let mem_share = valid_share(sample.and_then(|s| s.mem_share));
    let mem_tone = match (sample, mem_share) {
        (Some(s), Some(share)) => memory_tone(share, s.mem_pressure),
        _ => Tone::Unknown,
    };
    let disk = valid_share(sample.and_then(|s| s.disk_share));
    let cpu_help = sample.map(|s| s.cpu_help.clone());
    let mem_help = sample.map(|s| {
        format!(
            "{} used · pressure {}",
            fmt_bytes(s.mem_used_bytes),
            s.mem_pressure.label()
        )
    });
    let disk_help = match sample {
        Some(s) if s.disk_total > 0 => Some(format!(
            "{} available of {} · capacity, not temperature",
            fmt_bytes(s.disk_available),
            fmt_bytes(s.disk_total)
        )),
        _ => Some("Disk capacity unavailable".to_string()),
    };
    div()
        .flex()
        .flex_row()
        .gap(px(10.0))
        .pt(px(6.0))
        .pb(px(10.0))
        .child(instrument(
            "CPU",
            cpu_help,
            gauge(cpu_share, cpu_tone, fmt_percent(cpu_share)),
        ))
        .child(instrument(
            "Memory",
            mem_help,
            gauge(mem_share, mem_tone, fmt_percent(mem_share)),
        ))
        .child(instrument("Disk", disk_help, disk_grid(disk)))
        .child(instrument(
            "Network",
            Some(
                "Live physical-interface traffic. Bars use a fixed logarithmic scale from 0 to 1 GB/s, not link utilization."
                    .to_string(),
            ),
            network(sample),
        ))
}
