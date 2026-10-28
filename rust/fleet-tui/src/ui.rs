//! The full-screen renderer. Draws one frame from the dashboard and the
//! interface state; owns no state of its own. Returns the geometry the mouse
//! handler needs (tab positions, the selectable list's rows and scroll offset).

use crate::app::{App, Pane, Tone as StatusTone, View};
use crate::content::{self, Fact};
use crate::theme::{Theme, Tone};
use fleet_ui_core::controller::LogStream;
use fleet_ui_core::thresholds::{self, NodeState};
use fleet_ui_core::views::{Control, Dashboard, Freshness, ProcessRole};
use fleet_ui_core::{format, Phase};
use ratatui::layout::{Alignment, Constraint, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{
    Block, Borders, Cell, Clear, HighlightSpacing, Paragraph, Row, Table, TableState, Wrap,
};
use ratatui::Frame;

pub const MIN_WIDTH: u16 = 60;
pub const MIN_HEIGHT: u16 = 16;
/// Below this width every view uses one column.
pub const WIDE: u16 = 100;

#[derive(Debug, Clone, Default)]
pub struct Geometry {
    pub tabs_y: u16,
    pub tabs: Vec<(u16, u16, View)>,
    pub list: Option<ListGeometry>,
}

#[derive(Debug, Clone, Copy)]
pub struct ListGeometry {
    pub view: View,
    /// The rows region, header excluded.
    pub rows: Rect,
    pub offset: usize,
}

pub fn draw(frame: &mut Frame, dash: &Dashboard, app: &App, theme: &Theme) -> Geometry {
    let area = frame.area();
    frame.render_widget(Block::default().style(theme.base), area);
    let mut geometry = Geometry::default();
    if area.width < MIN_WIDTH || area.height < MIN_HEIGHT {
        too_small(frame, area, theme);
        return geometry;
    }

    let banner = banner_lines(dash, theme);
    let banner_height = if banner.is_empty() {
        0
    } else {
        wrapped_height(&banner, area.width).clamp(banner.len() as u16, 5)
    };
    let [header, tabs, banner_area, body, status, footer] = Layout::vertical([
        Constraint::Length(1),
        Constraint::Length(1),
        Constraint::Length(banner_height),
        Constraint::Fill(1),
        Constraint::Length(1),
        Constraint::Length(1),
    ])
    .areas(area);

    draw_header(frame, header, dash, theme);
    geometry.tabs_y = tabs.y;
    geometry.tabs = draw_tabs(frame, tabs, app, theme);
    if !banner.is_empty() {
        frame.render_widget(
            Paragraph::new(banner).wrap(Wrap { trim: false }),
            banner_area,
        );
    }

    let (list_area, pane_area) = split_for_pane(body, app.pane);
    geometry.list = draw_view(frame, list_area, dash, app, theme);
    if let Some(pane_area) = pane_area {
        match app.pane {
            Pane::Detail => draw_detail(frame, pane_area, dash, app, theme),
            Pane::Handoff => draw_handoff(frame, pane_area, dash, app, theme),
            Pane::Tail => draw_tail(frame, pane_area, app, theme),
            Pane::None => {}
        }
    }
    draw_status(frame, status, dash, app, theme);
    draw_footer(frame, footer, app, theme);
    if app.help {
        draw_help(frame, body, theme);
    }
    geometry
}

fn too_small(frame: &mut Frame, area: Rect, theme: &Theme) {
    let text = vec![
        Line::from(Span::styled("Terminal too small", theme.tone(Tone::Warn))),
        Line::from(format!(
            "{}x{}; Fleet Console needs at least {MIN_WIDTH}x{MIN_HEIGHT}.",
            area.width, area.height
        )),
        Line::from("Enlarge the window, or press q to quit."),
    ];
    let height = (text.len() as u16).min(area.height);
    let y = area.y + area.height.saturating_sub(height) / 2;
    frame.render_widget(
        Paragraph::new(text)
            .alignment(Alignment::Center)
            .wrap(Wrap { trim: true }),
        Rect::new(area.x, y, area.width, height),
    );
}

fn split_for_pane(body: Rect, pane: Pane) -> (Rect, Option<Rect>) {
    if pane == Pane::None {
        return (body, None);
    }
    if body.width >= WIDE {
        let [a, b] =
            Layout::horizontal([Constraint::Percentage(58), Constraint::Percentage(42)]).areas(body);
        (a, Some(b))
    } else {
        let [a, b] =
            Layout::vertical([Constraint::Percentage(50), Constraint::Percentage(50)]).areas(body);
        (a, Some(b))
    }
}

fn pane<'a>(title: String, theme: &Theme) -> Block<'a> {
    Block::default()
        .borders(Borders::ALL)
        .border_style(theme.border)
        .title(Span::styled(format!(" {title} "), theme.title))
}

/// Header text in priority order. When the row is too narrow, the awaiting
/// count goes first (the Agents and Attention views repeat it), then the
/// version's prefix, then the remote marker, then the version. Read-only and
/// the connection phase always stay.
fn draw_header(frame: &mut Frame, area: Rect, dash: &Dashboard, theme: &Theme) {
    let c = &dash.connection;
    let version = c.controller_version.as_deref().map(content::clean);
    let remote = c.locality == fleet_ui_core::views::Locality::Remote;
    let awaiting = dash.header.awaiting_reply.filter(|n| *n > 0);
    // "services disconnected" repeats the phase; only a live count is shown.
    let subtitle = (c.phase == Phase::Live).then(|| dash.header.subtitle.clone());
    let build = |shown: bool, awaiting: bool, prefix: bool, remote: bool, version: bool| {
        let mut left = vec![
            Span::styled(
                " Fleet Console",
                theme.tone(Tone::Bright).add_modifier(Modifier::BOLD),
            ),
            Span::raw("  "),
            Span::styled(
                format!("controller {}", c.phase.label()),
                theme.tone(content::phase_tone(c.phase)),
            ),
        ];
        if let (true, Some(s)) = (shown, &subtitle) {
            left.push(Span::raw("  "));
            left.push(Span::styled(s.clone(), theme.tone(Tone::Text)));
        }
        if let (true, Some(n)) = (awaiting, dash.header.awaiting_reply.filter(|n| *n > 0)) {
            left.push(Span::raw("  "));
            left.push(Span::styled(
                format!("{n} awaiting reply"),
                theme.tone(Tone::Warn),
            ));
        }
        let mut right: Vec<Span> = Vec::new();
        if c.read_only {
            right.push(Span::styled("read-only", theme.tone(Tone::Warn)));
        }
        if remote {
            right.push(Span::styled("remote controller", theme.tone(Tone::Info)));
        }
        if let (true, Some(v)) = (version, &c.controller_version) {
            let v = content::clean(v);
            right.push(Span::styled(
                if prefix { format!("controller {v}") } else { v },
                theme.tone(Tone::Dim),
            ));
        }
        let mut right_spans = Vec::new();
        for (i, s) in right.into_iter().enumerate() {
            if i > 0 {
                right_spans.push(Span::raw("  "));
            }
            right_spans.push(s);
        }
        right_spans.push(Span::raw(" "));
        (Line::from(left), Line::from(right_spans))
    };
    let attempts = [
        (true, true, true, remote, true),
        (true, false, true, remote, true),
        (true, false, false, remote, true),
        (true, false, false, false, true),
        (true, false, false, false, false),
        (false, false, false, false, false),
    ];
    let mut chosen = build(false, false, false, false, false);
    for (s, a, p, r, v) in attempts {
        let (left, right) = build(s, a && awaiting.is_some(), p, r, v && version.is_some());
        if left.width() + 2 + right.width() <= usize::from(area.width) {
            chosen = (left, right);
            break;
        }
    }
    let (left_line, right_line) = chosen;
    let left_width = (left_line.width() as u16).min(area.width);
    frame.render_widget(Paragraph::new(left_line), area);
    frame.render_widget(
        Paragraph::new(right_line).alignment(Alignment::Right),
        Rect::new(area.x + left_width, area.y, area.width - left_width, 1),
    );
}

fn draw_tabs(frame: &mut Frame, area: Rect, app: &App, theme: &Theme) -> Vec<(u16, u16, View)> {
    let mut spans = Vec::new();
    let mut ranges = Vec::new();
    let mut x = area.x;
    for (i, view) in View::ALL.into_iter().enumerate() {
        let active = view == app.view;
        let label_width = 1 + 1 + 1 + view.title().len() as u16 + 1;
        if active {
            spans.push(Span::styled(
                format!(" {} {} ", i + 1, view.title()),
                theme.tab_active,
            ));
        } else {
            spans.push(Span::raw(" "));
            spans.push(Span::styled(format!("{}", i + 1), theme.tab_number));
            spans.push(Span::styled(
                format!(" {} ", view.title()),
                theme.tone(Tone::Dim),
            ));
        }
        ranges.push((x, x + label_width, view));
        x += label_width + 1;
        spans.push(Span::raw(" "));
    }
    frame.render_widget(Paragraph::new(Line::from(spans)), area);
    ranges
}

/// The connection banner: present whenever the controller feed is not live,
/// and when local telemetry is not live.
pub fn banner_lines<'a>(dash: &Dashboard, theme: &Theme) -> Vec<Line<'a>> {
    let c = &dash.connection;
    let mut lines = Vec::new();
    if c.phase != Phase::Live {
        let tone = content::phase_tone(c.phase);
        lines.push(Line::from(vec![
            Span::styled(
                format!(" {} ", c.phase.label()),
                theme.tone(tone).add_modifier(Modifier::REVERSED | Modifier::BOLD),
            ),
            Span::raw(" "),
            Span::styled(c.summary.clone(), theme.tone(tone)),
        ]));
        let mut second = match (c.phase, &c.detail) {
            (_, Some(detail)) => format!("{}.", content::clean(detail).trim_end_matches('.')),
            (Phase::Loading, None) => format!("Socket {}.", c.socket_label),
            _ => String::new(),
        };
        if c.phase != Phase::Loading {
            if !second.is_empty() {
                second.push(' ');
            }
            second.push_str("Service controls are disabled until controller data is current.");
        }
        lines.push(Line::from(Span::styled(
            format!(" {second}"),
            theme.tone(Tone::Dim),
        )));
    }
    if c.telemetry_phase != Phase::Live {
        lines.push(Line::from(Span::styled(
            format!(
                " local telemetry {}{}",
                c.telemetry_phase.label(),
                if c.telemetry_phase == Phase::Loading {
                    ", waiting for the first sample"
                } else {
                    ""
                }
            ),
            theme.tone(content::phase_tone(c.telemetry_phase)),
        )));
    }
    lines
}

fn draw_view(
    frame: &mut Frame,
    area: Rect,
    dash: &Dashboard,
    app: &App,
    theme: &Theme,
) -> Option<ListGeometry> {
    match app.view {
        View::Overview => overview(frame, area, dash, app, theme),
        View::Processes => processes(frame, area, dash, app, theme),
        View::Services => services(frame, area, dash, app, theme),
        View::Agents => agents(frame, area, dash, app, theme),
        View::Storage => storage(frame, area, dash, app, theme),
        View::Attention => attention(frame, area, dash, app, theme),
    }
}

fn list_title(base: &str, view: View, dash: &Dashboard, app: &App) -> String {
    let filter = app.filter(view);
    if filter.is_empty() {
        base.to_string()
    } else {
        format!(
            "{base}, filter \"{}\", {} of {}",
            filter,
            app.visible(view, dash).len(),
            content::len(view, dash)
        )
    }
}

/// Render a selectable table and report where its rows landed.
#[allow(clippy::too_many_arguments)]
fn selectable(
    frame: &mut Frame,
    area: Rect,
    view: View,
    header: Row<'_>,
    rows: Vec<Row<'_>>,
    widths: &[Constraint],
    app: &App,
    dash: &Dashboard,
    theme: &Theme,
) -> Option<ListGeometry> {
    let table = Table::new(rows, widths.to_vec())
        .header(header.style(theme.tone(Tone::Dim)))
        .column_spacing(2)
        .row_highlight_style(theme.selected)
        .highlight_spacing(HighlightSpacing::Never);
    let mut state = TableState::default()
        .with_offset(app.offsets[view.index()])
        .with_selected(app.position(view, dash));
    frame.render_stateful_widget(table, area, &mut state);
    Some(ListGeometry {
        view,
        rows: Rect::new(
            area.x,
            area.y.saturating_add(1),
            area.width,
            area.height.saturating_sub(1),
        ),
        offset: state.offset(),
    })
}

fn empty(frame: &mut Frame, area: Rect, text: String, theme: &Theme) {
    frame.render_widget(
        Paragraph::new(Span::styled(text, theme.tone(Tone::Dim))).wrap(Wrap { trim: true }),
        area,
    );
}

fn segment_bar<'a>(metric: fleet_ui_core::Metric, cells: usize, theme: &Theme) -> Line<'a> {
    let mut spans = Vec::new();
    for cell in thresholds::segments(metric, cells) {
        spans.push(match cell {
            Some(level) => Span::styled("█", theme.level(level)),
            None => Span::styled("░", theme.segment_off),
        });
    }
    Line::from(spans)
}

fn not_current_note(dash: &Dashboard) -> Option<String> {
    let phase = dash.connection.phase;
    (phase != Phase::Live).then(|| format!("Controller {}: controller data is not current.", phase.label()))
}

fn overview(
    frame: &mut Frame,
    area: Rect,
    dash: &Dashboard,
    app: &App,
    theme: &Theme,
) -> Option<ListGeometry> {
    let tiles = dash.cluster.tiles.len() as u16;
    let cluster_height = (tiles + 6).min(area.height.saturating_sub(4)).max(6);
    let wide = area.width >= WIDE && app.pane == Pane::None;
    let (cluster_area, attention_area, agents_area, machine_area) = if wide {
        let [top, bottom] = Layout::vertical([
            Constraint::Length(cluster_height.max(9)),
            Constraint::Fill(1),
        ])
        .areas(area);
        let [left, right] =
            Layout::horizontal([Constraint::Percentage(56), Constraint::Percentage(44)]).areas(top);
        let [agents, right_column] =
            Layout::horizontal([Constraint::Percentage(56), Constraint::Percentage(44)])
                .areas(bottom);
        let [machine, requests] = Layout::vertical([
            Constraint::Length(MACHINE_ROWS + 2),
            Constraint::Fill(1),
        ])
        .areas(right_column);
        if requests.height >= 3 {
            draw_requests(frame, requests, dash, theme);
        }
        (left, right, agents, Some(machine))
    } else {
        let attention_rows = (dash.attention.len().min(4) as u16).max(1) + 2;
        // The local machine panel only when the agents list still gets room.
        let machine_rows = MACHINE_ROWS + 2;
        let with_machine = area.height >= cluster_height + attention_rows + machine_rows + 4;
        let [a, b, m, c] = Layout::vertical([
            Constraint::Length(cluster_height),
            Constraint::Length(attention_rows),
            Constraint::Length(if with_machine { machine_rows } else { 0 }),
            Constraint::Fill(1),
        ])
        .areas(area);
        (a, b, c, with_machine.then_some(m))
    };

    // Cluster: summary line and one selectable row per node.
    let block = pane(list_title("Cluster", View::Overview, dash, app), theme);
    let inner = block.inner(cluster_area);
    frame.render_widget(block, cluster_area);
    let s = &dash.cluster.summary;
    let summary = vec![
        Line::from(vec![
            Span::styled(
                format!("{} of {} nodes online", s.online, s.total),
                theme.tone(Tone::Text),
            ),
            Span::styled(
                if s.needs_attention > 0 {
                    format!("  {} under pressure", s.needs_attention)
                } else {
                    String::new()
                },
                theme.tone(Tone::Warn),
            ),
            Span::styled(
                format!(
                    "  agents {}",
                    s.agents
                        .map(|a| a.to_string())
                        .unwrap_or_else(|| format::UNAVAILABLE.into())
                ),
                theme.tone(Tone::Dim),
            ),
        ]),
        Line::from(Span::styled(
            format!(
                "average of online nodes  cpu {}  mem {}  gpu {}",
                format::percent(s.average_cpu),
                format::percent(s.average_memory),
                format::percent(s.average_gpu)
            ),
            theme.tone(Tone::Dim),
        )),
    ];
    let [summary_area, table_area] =
        Layout::vertical([Constraint::Length(2), Constraint::Fill(1)]).areas(inner);
    frame.render_widget(Paragraph::new(summary), summary_area);

    let bar_cells = if inner.width >= 90 { 20 } else { 10 };
    let visible = app.visible(View::Overview, dash);
    let rows: Vec<Row> = visible
        .iter()
        .map(|&i| {
            let t = &dash.cluster.tiles[i];
            let offline = t.state == NodeState::Offline;
            let state_text = format!(
                "{}{}",
                t.state.label(),
                match t.freshness {
                    Freshness::Current => "",
                    Freshness::Stale => ", stale",
                    Freshness::Disconnected => ", not current",
                }
            );
            let state_style = if offline {
                theme.tone(Tone::Dim)
            } else {
                theme.tone(Tone::for_level(t.worst_level()))
            };
            let gauge = |label: &str| -> Cell {
                match t.gauges.iter().find(|g| g.label == label) {
                    Some(g) => Cell::from(Span::styled(
                        g.text.clone(),
                        if offline && g.label != "disk" {
                            theme.tone(Tone::Dim)
                        } else {
                            theme.tone(Tone::for_level(g.level))
                        },
                    )),
                    None => Cell::from(format::UNAVAILABLE),
                }
            };
            let cpu = t
                .gauges
                .iter()
                .find(|g| g.label == "cpu")
                .map(|g| g.metric)
                .unwrap_or(fleet_ui_core::Metric::Unavailable(fleet_ui_core::Reason::NotMeasured));
            let row = Row::new(vec![
                Cell::from(content::clean(&t.name)),
                Cell::from(Span::styled(state_text, state_style)),
                gauge("cpu"),
                gauge("mem"),
                gauge("gpu"),
                gauge("disk"),
                Cell::from(segment_bar(cpu, bar_cells, theme)),
            ]);
            if offline {
                row.style(theme.tone(Tone::Dim))
            } else {
                row
            }
        })
        .collect();
    let geometry = selectable(
        frame,
        table_area,
        View::Overview,
        Row::new(["node", "state", "cpu", "mem", "gpu", "disk", "cpu use"]),
        rows,
        &[
            Constraint::Fill(2),
            Constraint::Fill(2),
            Constraint::Length(4),
            Constraint::Length(4),
            Constraint::Length(4),
            Constraint::Length(4),
            Constraint::Length(bar_cells as u16),
        ],
        app,
        dash,
        theme,
    );

    // Needs attention: the most severe reports; actions live in view 6.
    let block = pane(
        format!("Needs attention, {}", dash.attention.len()),
        theme,
    );
    let inner = block.inner(attention_area);
    frame.render_widget(block, attention_area);
    let mut lines: Vec<Line> = Vec::new();
    let room = inner.height as usize;
    for r in dash.attention.iter().take(room.saturating_sub(usize::from(dash.attention.len() > room))) {
        lines.push(Line::from(vec![
            Span::styled(
                format!("{:<5}", r.severity.label()),
                theme.tone(content::severity_tone(r.severity)),
            ),
            Span::raw(content::clean(&r.title)),
            Span::styled(format!("  {}", r.source), theme.tone(Tone::Dim)),
        ]));
    }
    if dash.attention.len() > lines.len() && !dash.attention.is_empty() {
        lines.push(Line::from(Span::styled(
            format!("{} more in 6 Attention", dash.attention.len() - lines.len()),
            theme.tone(Tone::Dim),
        )));
    }
    if dash.attention.is_empty() {
        lines.push(Line::from(Span::styled(
            match dash.connection.phase {
                Phase::Live => "Nothing needs attention.".to_string(),
                phase => format!("Controller {}: only local telemetry is checked.", phase.label()),
            },
            theme.tone(Tone::Dim),
        )));
    }
    frame.render_widget(Paragraph::new(lines).wrap(Wrap { trim: true }), inner);

    if let Some(machine_area) = machine_area {
        this_machine(frame, machine_area, dash, theme);
    }

    // Active agents.
    let block = pane(format!("Agents, {}", dash.agents.rows.len()), theme);
    let inner = block.inner(agents_area);
    frame.render_widget(block, agents_area);
    if dash.agents.rows.is_empty() {
        empty(
            frame,
            inner,
            not_current_note(dash).unwrap_or_else(|| "No agents reported.".into()),
            theme,
        );
    } else {
        let rows: Vec<Row> = dash
            .agents
            .rows
            .iter()
            .map(|a| {
                Row::new(vec![
                    Cell::from(content::clean(&a.name)),
                    Cell::from(content::clean(&a.target)),
                    Cell::from(Span::styled(
                        a.state.clone(),
                        theme.tone(match a.level {
                            Some(level) => Tone::Level(level),
                            None => Tone::Bright,
                        }),
                    )),
                    Cell::from(a.runtime.clone()),
                ])
            })
            .collect();
        frame.render_widget(
            Table::new(
                rows,
                [
                    Constraint::Fill(1),
                    Constraint::Fill(1),
                    Constraint::Fill(2),
                    Constraint::Length(8),
                ],
            )
            .header(Row::new(["agent", "target", "state", "runtime"]).style(theme.tone(Tone::Dim)))
            .column_spacing(2),
            inner,
        );
    }
    geometry
}

/// Rows in the local machine panel: five gauges and the CPU history.
const MACHINE_ROWS: u16 = 7;
const SPARK: [char; 8] = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];

/// This machine's own telemetry, read by this client: the popover's quick
/// view in terminal form.
fn this_machine(frame: &mut Frame, area: Rect, dash: &Dashboard, theme: &Theme) {
    let q = &dash.quick;
    let block = pane(
        format!(
            "This machine{}",
            match dash.connection.telemetry_phase {
                Phase::Live => String::new(),
                phase => format!(", telemetry {}", phase.label()),
            }
        ),
        theme,
    );
    let inner = block.inner(area);
    frame.render_widget(block, area);
    let cells = if inner.width >= 70 {
        20
    } else if inner.width >= 50 {
        8
    } else {
        6
    };
    let gauge_line = |label: &str, g: &fleet_ui_core::views::Gauge| -> Line {
        let mut spans = vec![Span::styled(format!("{label:<9}"), theme.tone(Tone::Dim))];
        spans.extend(segment_bar(g.metric, cells, theme).spans);
        spans.push(Span::styled(
            format!("  {:>4}", g.text),
            theme.tone(Tone::for_level(g.level)),
        ));
        let detail = match (g.metric.reason(), g.detail.is_empty(), g.level) {
            (Some(reason), _, _) => reason.label().to_string(),
            (None, false, _) => g.detail.clone(),
            (None, true, Some(level)) => level.label().to_string(),
            (None, true, None) => String::new(),
        };
        spans.push(Span::styled(format!("  {detail}"), theme.tone(Tone::Dim)));
        Line::from(spans)
    };
    let rate_line = |label: &str, r: &fleet_ui_core::views::Rate| -> Line {
        let lit = r
            .fraction
            .map(|f| (f * cells as f64).round() as usize)
            .unwrap_or(0)
            .min(cells);
        let mut spans = vec![Span::styled(format!("{label:<9}"), theme.tone(Tone::Dim))];
        spans.push(Span::styled("█".repeat(lit), theme.tone(Tone::Dark)));
        spans.push(Span::styled("░".repeat(cells - lit), theme.segment_off));
        spans.push(Span::styled(format!("  {}", r.text), theme.tone(Tone::Text)));
        let note = match r.metric.reason() {
            Some(reason) => reason.label(),
            None => "of recent peak",
        };
        spans.push(Span::styled(format!("  {note}"), theme.tone(Tone::Dim)));
        Line::from(spans)
    };
    let history: String = dash
        .cluster
        .tiles
        .first()
        .map(|t| {
            t.cpu_history
                .iter()
                .rev()
                .take(usize::from(inner.width.saturating_sub(9)))
                .collect::<Vec<_>>()
                .into_iter()
                .rev()
                .map(|v| match v {
                    Some(v) => SPARK[((v.clamp(0.0, 100.0) / 100.0) * 7.0).round() as usize],
                    None => ' ',
                })
                .collect()
        })
        .unwrap_or_default();
    let lines = vec![
        gauge_line("cpu", &q.cpu),
        gauge_line("memory", &q.memory),
        gauge_line("disk", &q.disk.gauge),
        gauge_line("gpu", &q.gpu),
        rate_line("download", &q.download),
        rate_line("upload", &q.upload),
        Line::from(vec![
            Span::styled(format!("{:<9}", "trend"), theme.tone(Tone::Dim)),
            Span::styled(
                if history.trim().is_empty() {
                    "no cpu samples yet".to_string()
                } else {
                    history
                },
                theme.tone(Tone::Dark),
            ),
        ]),
    ];
    frame.render_widget(Paragraph::new(lines), inner);
}

/// Requests this client sent: in flight first, then the latest outcomes.
fn draw_requests(frame: &mut Frame, area: Rect, dash: &Dashboard, theme: &Theme) {
    let block = pane("Requests from this client".into(), theme);
    let inner = block.inner(area);
    frame.render_widget(block, area);
    let lines: Vec<Line> = if dash.activity.is_empty() {
        vec![Line::from(Span::styled(
            "None sent yet. Restart, stop, renew and replies appear here with the controller's answer.",
            theme.tone(Tone::Dim),
        ))]
    } else {
        dash.activity
            .iter()
            .map(|a| {
                let (word, tone) = match a.ok {
                    None => ("waiting ", Tone::Warn),
                    Some(true) => ("done    ", Tone::Bright),
                    Some(false) => ("failed  ", Tone::Crit),
                };
                Line::from(vec![
                    Span::styled(word, theme.tone(tone)),
                    Span::raw(content::clean(&a.text)),
                ])
            })
            .collect()
    };
    frame.render_widget(Paragraph::new(lines).wrap(Wrap { trim: true }), inner);
}

fn role_style(role: ProcessRole, tag: Option<&str>, theme: &Theme) -> Style {
    match (role, tag) {
        (ProcessRole::Controller, _) | (ProcessRole::Agent, _) => theme.tone(Tone::Bright),
        (_, Some(t)) if t.contains("process table") => theme.tone(Tone::Dim),
        (_, Some(_)) => theme.tone(Tone::Warn),
        _ => theme.tone(Tone::Text),
    }
}

/// Rows a wrapped paragraph needs, estimated from line widths (word wrapping
/// can need one more row per line; callers leave room or clip).
fn wrapped_height(lines: &[Line], width: u16) -> u16 {
    let width = usize::from(width.max(1));
    lines
        .iter()
        .map(|l| l.width().max(1).div_ceil(width) as u16)
        .sum()
}

fn processes(
    frame: &mut Frame,
    area: Rect,
    dash: &Dashboard,
    app: &App,
    theme: &Theme,
) -> Option<ListGeometry> {
    let p = &dash.processes;
    let block = pane(list_title("Process tree", View::Processes, dash, app), theme);
    let inner = block.inner(area);
    frame.render_widget(block, area);
    if p.lines.is_empty() {
        empty(
            frame,
            inner,
            if p.phase == Phase::Loading {
                "Waiting for the first process sample.".into()
            } else {
                "No processes sampled.".into()
            },
            theme,
        );
        return None;
    }
    let mut head = vec![Line::from(Span::styled(
        format!(
            "{} processes sampled on this machine; {} rows: controller, services and agents first, then the busiest others",
            p.total_processes
                .map(|n| n.to_string())
                .unwrap_or_else(|| format::UNAVAILABLE.into()),
            p.lines.len()
        ),
        theme.tone(Tone::Dim),
    ))];
    if let Some(note) = &p.note {
        head.push(Line::from(Span::styled(note.clone(), theme.tone(Tone::Info))));
    }
    let head_height = wrapped_height(&head, inner.width).min(inner.height / 2);
    let [head_area, table_area] =
        Layout::vertical([Constraint::Length(head_height), Constraint::Fill(1)]).areas(inner);
    frame.render_widget(Paragraph::new(head).wrap(Wrap { trim: true }), head_area);

    let prefixes = content::tree_prefixes(&p.lines);
    let visible = app.visible(View::Processes, dash);
    let rows: Vec<Row> = visible
        .iter()
        .map(|&i| {
            let l = &p.lines[i];
            let name_style = match l.role {
                ProcessRole::Controller | ProcessRole::Agent | ProcessRole::Service => {
                    theme.tone(Tone::Bright)
                }
                ProcessRole::Other => theme.tone(Tone::Text),
            };
            Row::new(vec![
                Cell::from(Line::from(vec![
                    Span::styled(prefixes[i].clone(), theme.tone(Tone::Dim)),
                    Span::styled(content::clean(&l.name), name_style),
                ])),
                Cell::from(l.pid.map(|p| p.to_string()).unwrap_or_default()),
                Cell::from(if l.pid.is_some() {
                    format::percent(l.cpu)
                } else {
                    String::new()
                }),
                Cell::from(l.memory.clone()),
                Cell::from(Span::styled(
                    l.tag.as_deref().map(content::clean).unwrap_or_default(),
                    role_style(l.role, l.tag.as_deref(), theme),
                )),
            ])
        })
        .collect();
    selectable(
        frame,
        table_area,
        View::Processes,
        Row::new(["process", "pid", "cpu", "mem", "note"]),
        rows,
        &[
            Constraint::Fill(5),
            Constraint::Length(7),
            Constraint::Length(5),
            Constraint::Length(8),
            Constraint::Fill(4),
        ],
        app,
        dash,
        theme,
    )
}

fn services(
    frame: &mut Frame,
    area: Rect,
    dash: &Dashboard,
    app: &App,
    theme: &Theme,
) -> Option<ListGeometry> {
    let block = pane(
        list_title(
            &format!("Managed services, {}", dash.services.len()),
            View::Services,
            dash,
            app,
        ),
        theme,
    );
    let inner = block.inner(area);
    frame.render_widget(block, area);
    let [table_area, hint_area] =
        Layout::vertical([Constraint::Fill(1), Constraint::Length(1)]).areas(inner);
    frame.render_widget(
        Paragraph::new(Span::styled(
            if inner.width >= WIDE {
                "r restart  s stop  t tail logs  n renew lease 30m  a hand to an agent. Agents act through fleetctl only."
            } else {
                "Controller requests with fleetctl semantics; restart and stop confirm first."
            },
            theme.tone(Tone::Dim),
        )),
        hint_area,
    );
    if dash.services.is_empty() {
        empty(
            frame,
            table_area,
            match not_current_note(dash) {
                Some(note) if dash.connection.controller_version.is_none() => {
                    format!("{note} No service data has been read.")
                }
                _ => "No managed services.".into(),
            },
            theme,
        );
        return None;
    }
    let wide = table_area.width >= WIDE;
    let visible = app.visible(View::Services, dash);
    let rows: Vec<Row> = visible
        .iter()
        .map(|&i| {
            let r = &dash.services[i];
            let mut name = vec![Span::raw(content::clean(&r.name))];
            if r.claimed {
                name.push(Span::styled(" claimed", theme.tone(Tone::Dim)));
            }
            let state = match &r.in_flight {
                Some(text) => Span::styled(text.clone(), theme.tone(Tone::Warn)),
                None => Span::styled(r.state_text, theme.tone(Tone::for_level(r.level))),
            };
            let mut cells = vec![
                Cell::from(Line::from(name)),
                Cell::from(state),
                Cell::from(
                    r.pid
                        .map(|p| p.to_string())
                        .unwrap_or_else(|| format::UNAVAILABLE.into()),
                ),
                Cell::from(r.uptime.clone()),
                Cell::from(r.restarts.to_string()),
            ];
            if wide {
                cells.push(Cell::from(r.ports.clone()));
            }
            cells.push(Cell::from(format::percent(r.cpu)));
            cells.push(Cell::from(r.memory.clone()));
            if wide {
                cells.push(Cell::from(r.lease.clone()));
            }
            Row::new(cells)
        })
        .collect();
    let (header, widths): (Vec<&str>, Vec<Constraint>) = if wide {
        (
            vec![
                "service", "state", "pid", "uptime", "restarts", "ports", "cpu", "mem", "lease",
            ],
            vec![
                Constraint::Fill(2),
                Constraint::Length(19),
                Constraint::Length(6),
                Constraint::Length(7),
                Constraint::Length(8),
                Constraint::Fill(1),
                Constraint::Length(4),
                Constraint::Length(8),
                Constraint::Fill(2),
            ],
        )
    } else {
        (
            vec!["service", "state", "pid", "uptime", "rst", "cpu", "mem"],
            vec![
                Constraint::Fill(1),
                // "running, unverified" in full.
                Constraint::Length(19),
                Constraint::Length(6),
                Constraint::Length(6),
                Constraint::Length(3),
                Constraint::Length(4),
                Constraint::Length(8),
            ],
        )
    };
    selectable(
        frame,
        table_area,
        View::Services,
        Row::new(header),
        rows,
        &widths,
        app,
        dash,
        theme,
    )
}

fn agents(
    frame: &mut Frame,
    area: Rect,
    dash: &Dashboard,
    app: &App,
    theme: &Theme,
) -> Option<ListGeometry> {
    let a = &dash.agents;
    let rows_height = ((a.rows.len() as u16).max(1) + 3).min(area.height / 3).max(4);
    let [rows_area, transcript_area] =
        Layout::vertical([Constraint::Length(rows_height), Constraint::Fill(1)]).areas(area);

    let block = pane(format!("Agents, {}", a.rows.len()), theme);
    let inner = block.inner(rows_area);
    frame.render_widget(block, rows_area);
    if a.rows.is_empty() {
        empty(
            frame,
            inner,
            not_current_note(dash).unwrap_or_else(|| "No agents reported.".into()),
            theme,
        );
    } else {
        let rows: Vec<Row> = a
            .rows
            .iter()
            .map(|r| {
                Row::new(vec![
                    Cell::from(content::clean(&r.name)),
                    Cell::from(content::clean(&r.target)),
                    Cell::from(Span::styled(
                        r.state.clone(),
                        theme.tone(match r.level {
                            Some(level) => Tone::Level(level),
                            None => Tone::Bright,
                        }),
                    )),
                    Cell::from(r.runtime.clone()),
                    Cell::from(if r.awaiting_reply > 0 {
                        format!("{} waiting", r.awaiting_reply)
                    } else {
                        String::new()
                    }),
                ])
            })
            .collect();
        frame.render_widget(
            Table::new(
                rows,
                [
                    Constraint::Fill(1),
                    Constraint::Fill(1),
                    Constraint::Fill(2),
                    Constraint::Length(8),
                    Constraint::Length(10),
                ],
            )
            .header(
                Row::new(["agent", "target", "state", "runtime", "questions"])
                    .style(theme.tone(Tone::Dim)),
            )
            .column_spacing(2),
            inner,
        );
    }

    let block = pane(
        list_title(
            &format!(
                "Transcript, times in UTC, {} open question{}",
                a.open_questions,
                if a.open_questions == 1 { "" } else { "s" }
            ),
            View::Agents,
            dash,
            app,
        ),
        theme,
    );
    let inner = block.inner(transcript_area);
    frame.render_widget(block, transcript_area);
    if a.transcript.is_empty() {
        empty(
            frame,
            inner,
            not_current_note(dash).unwrap_or_else(|| "No agent messages.".into()),
            theme,
        );
        return None;
    }
    let visible = app.visible(View::Agents, dash);
    let rows: Vec<Row> = visible
        .iter()
        .map(|&i| {
            let l = &a.transcript[i];
            let verb_tone = match l.verb.as_str() {
                "ask" => Tone::Warn,
                "problem" => Tone::Crit,
                _ => Tone::Text,
            };
            let reply = match &l.question {
                Some(q) if q.in_flight => Line::from(Span::styled("reply in progress", theme.tone(Tone::Warn))),
                Some(q) => match &q.reply {
                    Control::Allowed => Line::from(vec![
                        Span::styled("y", theme.key),
                        Span::styled(" approve  ", theme.tone(Tone::Text)),
                        Span::styled("n", theme.key),
                        Span::styled(" deny", theme.tone(Tone::Text)),
                    ]),
                    // The full reason is in the detail pane.
                    Control::Refused(reason) => Line::from(Span::styled(
                        if reason.contains("read-only") {
                            "read-only client"
                        } else if reason.contains("not current") {
                            "data not current"
                        } else if reason.contains("in progress") {
                            "reply in progress"
                        } else {
                            "unavailable"
                        },
                        theme.tone(Tone::Dim),
                    )),
                },
                None => Line::default(),
            };
            Row::new(vec![
                Cell::from(Span::styled(l.time.clone(), theme.tone(Tone::Dim))),
                Cell::from(content::clean(&l.agent)),
                Cell::from(Span::styled(l.verb.clone(), theme.tone(verb_tone))),
                Cell::from(content::clean(&l.text)),
                Cell::from(reply),
            ])
        })
        .collect();
    selectable(
        frame,
        inner,
        View::Agents,
        Row::new(["utc", "agent", "kind", "message", "reply"]),
        rows,
        &[
            Constraint::Length(5),
            Constraint::Length(10),
            Constraint::Length(7),
            Constraint::Fill(1),
            Constraint::Length(if a.open_questions > 0 { 17 } else { 5 }),
        ],
        app,
        dash,
        theme,
    )
}

fn storage(
    frame: &mut Frame,
    area: Rect,
    dash: &Dashboard,
    app: &App,
    theme: &Theme,
) -> Option<ListGeometry> {
    let s = &dash.storage;
    let block = pane(
        list_title(
            "Volume map, bar length is capacity, filled share is used",
            View::Storage,
            dash,
            app,
        ),
        theme,
    );
    let inner = block.inner(area);
    frame.render_widget(block, area);
    let paths_lines: Vec<Line> = match &s.largest_paths {
        Ok(paths) if paths.is_empty() => vec![Line::from(Span::styled(
            "Largest paths: none reported.",
            theme.tone(Tone::Dim),
        ))],
        Ok(paths) => {
            let mut v = vec![Line::from(Span::styled("Largest paths", theme.title))];
            for (size, path) in paths {
                v.push(Line::from(format!("{size:>8}  {}", content::clean(path))));
            }
            v
        }
        Err(reason) => vec![
            Line::from(Span::styled("Largest paths", theme.title)),
            Line::from(Span::styled(
                format!("unavailable: {reason}"),
                theme.tone(Tone::Dim),
            )),
        ],
    };
    let paths_height = (paths_lines.len() as u16 + 1).min(inner.height / 2);
    let [table_area, paths_area] =
        Layout::vertical([Constraint::Fill(1), Constraint::Length(paths_height)]).areas(inner);
    frame.render_widget(
        Paragraph::new(
            std::iter::once(Line::default())
                .chain(paths_lines)
                .collect::<Vec<_>>(),
        )
        .wrap(Wrap { trim: true }),
        paths_area,
    );
    if s.volumes.is_empty() {
        empty(
            frame,
            table_area,
            if s.phase == Phase::Loading {
                "Waiting for the first telemetry sample.".into()
            } else {
                "No volumes reported.".into()
            },
            theme,
        );
        return None;
    }
    let bar_width: usize = if table_area.width >= WIDE { 40 } else { 16 };
    let largest = s
        .volumes
        .iter()
        .filter_map(|v| content::parse_size(&v.total))
        .fold(0.0_f64, f64::max);
    let visible = app.visible(View::Storage, dash);
    let rows: Vec<Row> = visible
        .iter()
        .map(|&i| {
            let v = &s.volumes[i];
            let length = match content::parse_size(&v.total) {
                Some(total) if largest > 0.0 => {
                    ((total / largest) * bar_width as f64).round() as usize
                }
                _ => bar_width,
            }
            .clamp(4, bar_width);
            let filled = v
                .gauge
                .metric
                .fraction()
                .map(|f| (f * length as f64).round() as usize)
                .unwrap_or(0);
            let style = theme.tone(Tone::for_level(v.gauge.level));
            let bar = Line::from(vec![
                Span::styled("█".repeat(filled), style),
                Span::styled("░".repeat(length - filled), theme.segment_off),
            ]);
            let share = match (v.gauge.metric.reason(), v.gauge.level) {
                (Some(_), _) => format::UNAVAILABLE.to_string(),
                (None, Some(level)) => format!("{} {}", v.gauge.text, level.label()),
                (None, None) => v.gauge.text.clone(),
            };
            Row::new(vec![
                Cell::from(content::clean(&v.mount)),
                Cell::from(bar),
                Cell::from(v.used.clone()),
                Cell::from(v.free.clone()),
                Cell::from(v.total.clone()),
                Cell::from(Span::styled(share, style)),
            ])
        })
        .collect();
    selectable(
        frame,
        table_area,
        View::Storage,
        Row::new(["volume", "map", "used", "free", "capacity", "used share"]),
        rows,
        &[
            Constraint::Fill(1),
            Constraint::Length(bar_width as u16),
            Constraint::Length(8),
            Constraint::Length(8),
            Constraint::Length(8),
            Constraint::Fill(1),
        ],
        app,
        dash,
        theme,
    )
}

fn attention(
    frame: &mut Frame,
    area: Rect,
    dash: &Dashboard,
    app: &App,
    theme: &Theme,
) -> Option<ListGeometry> {
    let block = pane(
        list_title(
            &format!("Fix reports, {}", dash.attention.len()),
            View::Attention,
            dash,
            app,
        ),
        theme,
    );
    let inner = block.inner(area);
    frame.render_widget(block, area);
    let [table_area, hint_area] =
        Layout::vertical([Constraint::Fill(1), Constraint::Length(1)]).areas(inner);
    frame.render_widget(
        Paragraph::new(Span::styled(
            "enter opens the report. a shows the read-only fleetctl commands for an agent.",
            theme.tone(Tone::Dim),
        )),
        hint_area,
    );
    if dash.attention.is_empty() {
        empty(
            frame,
            table_area,
            match not_current_note(dash) {
                Some(note) => format!("{note} Only local telemetry is checked, and it reports nothing."),
                None => "Nothing needs attention.".into(),
            },
            theme,
        );
        return None;
    }
    let wide = table_area.width >= WIDE;
    let visible = app.visible(View::Attention, dash);
    let rows: Vec<Row> = visible
        .iter()
        .map(|&i| {
            let r = &dash.attention[i];
            let mut cells = vec![
                Cell::from(Span::styled(
                    r.severity.label(),
                    theme.tone(content::severity_tone(r.severity)),
                )),
                Cell::from(content::clean(&r.title)),
                Cell::from(Span::styled(r.source, theme.tone(Tone::Dim))),
            ];
            if wide {
                cells.push(Cell::from(Span::styled(
                    r.available.clone(),
                    theme.tone(Tone::Dim),
                )));
            }
            Row::new(cells)
        })
        .collect();
    let (header, widths) = if wide {
        (
            vec!["level", "report", "source", "available"],
            vec![
                Constraint::Length(5),
                Constraint::Fill(3),
                Constraint::Length(15),
                Constraint::Fill(3),
            ],
        )
    } else {
        (
            vec!["level", "report", "source"],
            vec![
                Constraint::Length(5),
                Constraint::Fill(3),
                Constraint::Length(15),
            ],
        )
    };
    selectable(
        frame,
        table_area,
        View::Attention,
        Row::new(header),
        rows,
        &widths,
        app,
        dash,
        theme,
    )
}

fn fact_lines<'a>(facts: &[Fact], theme: &Theme) -> Vec<Line<'a>> {
    let width = facts.iter().map(|f| f.label.len()).max().unwrap_or(0).min(12);
    facts
        .iter()
        .map(|f| {
            Line::from(vec![
                Span::styled(format!("{:<width$}  ", f.label), theme.tone(Tone::Dim)),
                Span::styled(f.text.clone(), theme.tone(f.tone)),
            ])
        })
        .collect()
}

fn draw_detail(frame: &mut Frame, area: Rect, dash: &Dashboard, app: &App, theme: &Theme) {
    let detail = app
        .selected(app.view, dash)
        .and_then(|i| content::detail(app.view, dash, i));
    let (title, lines) = match detail {
        Some((title, facts)) => (title, fact_lines(&facts, theme)),
        None => (
            "Inspect".to_string(),
            vec![Line::from(Span::styled(
                "Nothing selected.",
                theme.tone(Tone::Dim),
            ))],
        ),
    };
    let block = pane(title, theme);
    frame.render_widget(Clear, area);
    frame.render_widget(
        Paragraph::new(lines)
            .block(block)
            .style(theme.base)
            .wrap(Wrap { trim: false }),
        area,
    );
}

fn draw_handoff(frame: &mut Frame, area: Rect, dash: &Dashboard, app: &App, theme: &Theme) {
    let handoff = app
        .selected(app.view, dash)
        .and_then(|i| content::handoff(app.view, dash, i));
    let mut lines: Vec<Line> = Vec::new();
    match handoff {
        Some(h) => {
            lines.push(Line::from(vec![
                Span::styled("target  ", theme.tone(Tone::Dim)),
                Span::raw(h.target),
            ]));
            lines.push(Line::default());
            if h.read_only.is_empty() {
                lines.push(Line::from(Span::styled(
                    "No read-only fleetctl command targets this item.",
                    theme.tone(Tone::Dim),
                )));
            } else {
                lines.push(Line::from(Span::styled(
                    "Read-only commands for an agent",
                    theme.title,
                )));
                for c in h.read_only {
                    lines.push(Line::from(Span::styled(
                        format!("  {c}"),
                        theme.tone(Tone::Bright),
                    )));
                }
            }
            if !h.changes.is_empty() {
                lines.push(Line::default());
                lines.push(Line::from(Span::styled(
                    "Changes controller state, not read-only",
                    theme.tone(Tone::Warn),
                )));
                for c in h.changes {
                    lines.push(Line::from(format!("  {c}")));
                }
            }
            if let Some(note) = h.note {
                lines.push(Line::default());
                lines.push(Line::from(Span::styled(note, theme.tone(Tone::Dim))));
            }
        }
        None => lines.push(Line::from(Span::styled(
            "Nothing selected.",
            theme.tone(Tone::Dim),
        ))),
    }
    lines.push(Line::default());
    lines.push(Line::from(content::HANDOFF_LIMIT));
    frame.render_widget(Clear, area);
    frame.render_widget(
        Paragraph::new(lines)
            .block(pane("Hand to an agent".into(), theme))
            .style(theme.base)
            .wrap(Wrap { trim: false }),
        area,
    );
}

fn draw_tail(frame: &mut Frame, area: Rect, app: &App, theme: &Theme) {
    frame.render_widget(Clear, area);
    let Some(tail) = &app.tail else {
        return;
    };
    let (stream, other) = match tail.stream {
        LogStream::Out => ("stdout", "stderr"),
        LogStream::Err => ("stderr", "stdout"),
    };
    let block = pane(format!("Log tail, {} {stream}", tail.name), theme);
    let inner = block.inner(area);
    frame.render_widget(Block::default().style(theme.base), area);
    frame.render_widget(block, area);
    let [info_area, text_area] =
        Layout::vertical([Constraint::Length(1), Constraint::Fill(1)]).areas(inner);
    let mut info = vec![
        Span::styled("read every 2 s  ", theme.tone(Tone::Dim)),
        Span::styled("tab", theme.key),
        Span::styled(format!(" {other}  "), theme.tone(Tone::Dim)),
        Span::styled("esc", theme.key),
        Span::styled(" close", theme.tone(Tone::Dim)),
    ];
    if tail.request.is_some() {
        info.push(Span::styled("  reading", theme.tone(Tone::Dim)));
    }
    frame.render_widget(Paragraph::new(Line::from(info)), info_area);
    let room = text_area.height as usize;
    let lines: Vec<Line> = match &tail.chunk {
        None => vec![Line::from(Span::styled(
            "Waiting for the first read.",
            theme.tone(Tone::Dim),
        ))],
        Some(Err(error)) => vec![Line::from(Span::styled(
            format!("Read failed: {}", content::clean(error)),
            theme.tone(Tone::Crit),
        ))],
        Some(Ok(chunk)) if chunk.text.trim().is_empty() => vec![Line::from(Span::styled(
            format!("The {stream} log is empty."),
            theme.tone(Tone::Dim),
        ))],
        Some(Ok(chunk)) => {
            let all: Vec<&str> = chunk.text.lines().collect();
            let mut out = Vec::new();
            let keep = if chunk.truncated { room.saturating_sub(1) } else { room };
            if chunk.truncated {
                out.push(Line::from(Span::styled(
                    format!("showing the end of the log, last {}", format::bytes(chunk.bytes.max(0) as u64)),
                    theme.tone(Tone::Dim),
                )));
            }
            for line in all.iter().skip(all.len().saturating_sub(keep)) {
                out.push(Line::from(content::clean(line)));
            }
            out
        }
    };
    frame.render_widget(Paragraph::new(lines), text_area);
}

fn draw_status(frame: &mut Frame, area: Rect, dash: &Dashboard, app: &App, theme: &Theme) {
    let line = if let Some(confirm) = &app.confirm {
        Line::from(vec![
            Span::styled(
                format!(" {} ", confirm.prompt),
                theme.tone(Tone::Warn).add_modifier(Modifier::REVERSED | Modifier::BOLD),
            ),
            Span::raw("  "),
            Span::styled("y", theme.key),
            Span::styled(" confirm  ", theme.tone(Tone::Text)),
            Span::styled("n", theme.key),
            Span::styled(" cancel", theme.tone(Tone::Text)),
        ])
    } else if app.editing_filter {
        Line::from(vec![
            Span::styled(" filter ", theme.tone(Tone::Dim)),
            Span::styled(app.filter(app.view).to_string(), theme.tone(Tone::Bright)),
            Span::styled(" ", theme.selected),
        ])
    } else if let Some(status) = &app.status {
        Line::from(Span::styled(
            format!(" {}", status.text),
            theme.tone(match status.tone {
                StatusTone::Info => Tone::Text,
                StatusTone::Ok => Tone::Bright,
                StatusTone::Refused => Tone::Warn,
            }),
        ))
    } else if let Some(activity) = dash.activity.first() {
        Line::from(Span::styled(
            format!(" {}", content::clean(&activity.text)),
            theme.tone(match activity.ok {
                Some(true) => Tone::Bright,
                Some(false) => Tone::Crit,
                None => Tone::Warn,
            }),
        ))
    } else {
        Line::default()
    };
    frame.render_widget(Paragraph::new(line), area);
}

fn hint<'a>(spans: &mut Vec<Span<'a>>, key: &'a str, text: &'a str, theme: &Theme) {
    if !spans.is_empty() {
        spans.push(Span::raw("  "));
    }
    spans.push(Span::styled(key, theme.key));
    spans.push(Span::styled(" ", theme.tone(Tone::Dim)));
    spans.push(Span::styled(text, theme.tone(Tone::Dim)));
}

pub fn footer_hints(app: &App) -> Vec<(&'static str, &'static str)> {
    if app.confirm.is_some() {
        return vec![("y", "confirm"), ("n", "cancel")];
    }
    if app.editing_filter {
        return vec![("type", "to filter"), ("enter", "keep"), ("esc", "clear")];
    }
    if app.help {
        return vec![("esc", "close help"), ("q", "quit")];
    }
    let mut keys = vec![("1-6", "view"), ("j/k", "move"), ("enter", "inspect"), ("/", "filter")];
    if app.pane == Pane::Tail {
        keys.push(("tab", "stream"));
        keys.push(("esc", "close tail"));
    }
    match app.view {
        View::Services => keys.extend([
            ("r", "restart"),
            ("s", "stop"),
            ("n", "renew"),
            ("t", "tail"),
            ("a", "agent"),
        ]),
        View::Agents => keys.extend([("y", "approve"), ("n", "deny"), ("a", "agent")]),
        View::Attention => keys.extend([
            ("r", "restart"),
            ("s", "stop"),
            ("t", "tail"),
            ("y n", "reply"),
            ("a", "agent"),
        ]),
        View::Processes => keys.extend([("t", "tail"), ("a", "agent")]),
        View::Overview | View::Storage => keys.push(("a", "agent")),
    }
    if app.read_only {
        // A read-only client sends nothing that changes state; do not offer it.
        keys.retain(|(k, _)| !matches!(*k, "r" | "s" | "n" | "y" | "y n"));
    }
    keys.extend([("?", "help"), ("q", "quit")]);
    keys
}

/// Drop hints until the row fits: navigation first (the help lists it),
/// then the view's actions from the last; `?` and `q` always stay.
pub fn fit_hints(
    mut hints: Vec<(&'static str, &'static str)>,
    width: usize,
) -> Vec<(&'static str, &'static str)> {
    let size = |h: &[(&str, &str)]| -> usize {
        1 + h.iter().map(|(k, t)| k.len() + 1 + t.len()).sum::<usize>() + 2 * h.len().saturating_sub(1)
    };
    for key in ["1-6", "j/k", "/", "enter"] {
        if size(&hints) <= width {
            return hints;
        }
        hints.retain(|(k, _)| *k != key);
    }
    while size(&hints) > width {
        let Some(i) = hints.iter().rposition(|(k, _)| *k != "?" && *k != "q") else {
            break;
        };
        hints.remove(i);
    }
    hints
}

fn draw_footer(frame: &mut Frame, area: Rect, app: &App, theme: &Theme) {
    let mut spans = vec![Span::raw(" ")];
    let mut inner = Vec::new();
    for (key, text) in fit_hints(footer_hints(app), usize::from(area.width)) {
        hint(&mut inner, key, text, theme);
    }
    spans.extend(inner);
    frame.render_widget(Paragraph::new(Line::from(spans)), area);
}

pub const HELP: &[(&str, &str)] = &[
    ("1-6", "switch view: Overview, Processes, Services, Agents, Storage, Attention"),
    ("j k, arrows", "move the selection; g and G jump to the first and last row"),
    ("enter", "inspect the selected row: evidence, unavailable reasons, controls"),
    ("/", "filter the current list; enter keeps the filter, esc clears it"),
    ("r", "restart the selected service; asks for confirmation first"),
    ("s", "stop the selected service; asks for confirmation first"),
    ("n", "renew the selected service's lease for 30 minutes"),
    ("t", "live tail of the selected service's logs; tab switches stdout and stderr"),
    ("a", "read-only fleetctl commands for handing the selection to an agent"),
    ("y n", "approve or deny the selected open agent question"),
    ("?", "show or hide this help"),
    ("q, ctrl-c", "quit"),
];

fn draw_help(frame: &mut Frame, body: Rect, theme: &Theme) {
    let width = body.width.saturating_sub(4).min(88);
    let height = body.height.min(22);
    let area = Rect::new(
        body.x + (body.width - width) / 2,
        body.y + (body.height - height) / 2,
        width,
        height,
    );
    let mut lines: Vec<Line> = HELP
        .iter()
        .map(|(key, text)| {
            Line::from(vec![
                Span::styled(format!("{key:<12}"), theme.key),
                Span::styled(*text, theme.tone(Tone::Text)),
            ])
        })
        .collect();
    lines.push(Line::default());
    lines.push(Line::from(Span::styled(
        "Every action is a controller request with fleetctl semantics. The controller keeps enforcing owner, lease and process identity checks, and never signals a claimed process.",
        theme.tone(Tone::Dim),
    )));
    lines.push(Line::from(Span::styled(
        "States are words as well as colors: normal, above 50%, warning, critical; healthy, pressure, offline. -- marks a value that was not measured; inspect shows why.",
        theme.tone(Tone::Dim),
    )));
    frame.render_widget(Clear, area);
    frame.render_widget(
        Paragraph::new(lines)
            .block(pane("Help".into(), theme))
            .style(theme.base)
            .wrap(Wrap { trim: false }),
        area,
    );
}
