//! One-shot renderings: a frame drawn into ratatui's `TestBackend` and written
//! as text, with ANSI styling when the output is a color terminal. Used by
//! `--once` and by fixture captures.

use crate::app::App;
use crate::theme::Theme;
use crate::ui;
use fleet_ui_core::views::Dashboard;
use ratatui::backend::TestBackend;
use ratatui::buffer::Buffer;
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::Span;
use ratatui::Terminal;

pub fn render(dash: &Dashboard, app: &App, theme: &Theme, cols: u16, rows: u16) -> Buffer {
    let mut terminal = Terminal::new(TestBackend::new(cols, rows)).expect("test backend");
    let mut app = app.clone();
    app.sync(dash);
    terminal
        .draw(|frame| {
            ui::draw(frame, dash, &app, theme);
        })
        .expect("draw into test backend");
    terminal.backend().buffer().clone()
}

fn sgr_color(color: Color, foreground: bool) -> Option<String> {
    let base = if foreground { 38 } else { 48 };
    match color {
        Color::Reset => None,
        Color::Rgb(r, g, b) => Some(format!("{base};2;{r};{g};{b}")),
        Color::Indexed(i) => Some(format!("{base};5;{i}")),
        other => {
            // Named colors are not produced by the theme; map them through
            // their 256-color index for completeness.
            let index = match other {
                Color::Black => 0,
                Color::Red => 1,
                Color::Green => 2,
                Color::Yellow => 3,
                Color::Blue => 4,
                Color::Magenta => 5,
                Color::Cyan => 6,
                Color::Gray => 7,
                Color::DarkGray => 8,
                Color::LightRed => 9,
                Color::LightGreen => 10,
                Color::LightYellow => 11,
                Color::LightBlue => 12,
                Color::LightMagenta => 13,
                Color::LightCyan => 14,
                _ => 15,
            };
            Some(format!("{base};5;{index}"))
        }
    }
}

fn sgr(style: Style) -> String {
    let mut codes = vec!["0".to_string()];
    for (flag, code) in [
        (Modifier::BOLD, "1"),
        (Modifier::DIM, "2"),
        (Modifier::ITALIC, "3"),
        (Modifier::UNDERLINED, "4"),
        (Modifier::REVERSED, "7"),
    ] {
        if style.add_modifier.contains(flag) {
            codes.push(code.into());
        }
    }
    if let Some(c) = style.fg.and_then(|c| sgr_color(c, true)) {
        codes.push(c);
    }
    if let Some(c) = style.bg.and_then(|c| sgr_color(c, false)) {
        codes.push(c);
    }
    format!("\u{1b}[{}m", codes.join(";"))
}

/// The buffer as lines of text. Wide characters occupy their cells once;
/// trailing spaces are trimmed when no styling is written.
pub fn text(buffer: &Buffer, ansi: bool) -> String {
    let area = buffer.area;
    let mut out = String::new();
    for y in 0..area.height {
        let mut line = String::new();
        let mut current: Option<Style> = None;
        let mut skip = 0usize;
        for x in 0..area.width {
            if skip > 0 {
                skip -= 1;
                continue;
            }
            let cell = &buffer[(area.x + x, area.y + y)];
            let symbol = cell.symbol();
            if ansi {
                let style = cell.style();
                if current != Some(style) {
                    line.push_str(&sgr(style));
                    current = Some(style);
                }
            }
            line.push_str(symbol);
            skip = Span::raw(symbol).width().saturating_sub(1);
        }
        if ansi {
            line.push_str("\u{1b}[0m");
        } else {
            let trimmed = line.trim_end().len();
            line.truncate(trimmed);
        }
        out.push_str(&line);
        out.push('\n');
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::app::View;
    use crate::source::tests::dashboard;
    use crate::theme::ColorMode;
    use fleet_ui_core::fixtures::Scenario;

    #[test]
    fn plain_text_has_no_escape_sequences() {
        let dash = dashboard(Scenario::Healthy, false);
        let app = App::new(View::Services, false);
        let buffer = render(&dash, &app, &Theme::new(ColorMode::TrueColor), 100, 30);
        let plain = text(&buffer, false);
        assert!(!plain.contains('\u{1b}'));
        assert!(plain.contains("Managed services"));
        let styled = text(&buffer, true);
        assert!(styled.contains("\u{1b}[0;"), "ansi output carries styles");
    }
}
