//! The phosphor palette from `design/tokens.json`, reduced to what the
//! terminal can show.
//!
//! Truecolor terminals get the token colors; 256-color terminals the nearest
//! xterm-256 index from the color cube or gray ramp (indices 0 to 15 vary by
//! terminal theme, so they are never chosen); 16-color terminals the `ansi16`
//! indices from the tokens. With no color, emphasis is bold, dim and reverse
//! video, and every state also has a word, so nothing depends on color.

use fleet_ui_core::theme::{tokens, Rgb};
use fleet_ui_core::thresholds::Level;
use ratatui::style::{Color, Modifier, Style};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ColorMode {
    TrueColor,
    Ansi256,
    Ansi16,
    None,
}

impl ColorMode {
    /// `env` reads one environment variable; empty values count as unset.
    pub fn detect(no_color_flag: bool, env: impl Fn(&str) -> Option<String>) -> Self {
        let get = |name: &str| env(name).filter(|v| !v.is_empty());
        if no_color_flag || get("NO_COLOR").is_some() {
            return Self::None;
        }
        let term = get("TERM").unwrap_or_default();
        if term == "dumb" {
            return Self::None;
        }
        match get("COLORTERM").as_deref() {
            Some("truecolor") | Some("24bit") => return Self::TrueColor,
            _ => {}
        }
        if term.contains("256color") {
            Self::Ansi256
        } else {
            Self::Ansi16
        }
    }

    pub fn from_environment(no_color_flag: bool) -> Self {
        Self::detect(no_color_flag, |name| std::env::var(name).ok())
    }
}

/// The nearest xterm-256 index for a color, from the 6x6x6 cube (16 to 231)
/// and the gray ramp (232 to 255), by squared RGB distance.
pub fn nearest_256(c: Rgb) -> u8 {
    const LEVELS: [u8; 6] = [0, 95, 135, 175, 215, 255];
    let distance = |r: u8, g: u8, b: u8| {
        let d = |x: u8, y: u8| (i32::from(x) - i32::from(y)).pow(2);
        d(r, c.r) + d(g, c.g) + d(b, c.b)
    };
    let mut best = (i32::MAX, 16u8);
    for (ri, r) in LEVELS.iter().enumerate() {
        for (gi, g) in LEVELS.iter().enumerate() {
            for (bi, b) in LEVELS.iter().enumerate() {
                let index = 16 + 36 * ri + 6 * gi + bi;
                let dist = distance(*r, *g, *b);
                if dist < best.0 {
                    best = (dist, index as u8);
                }
            }
        }
    }
    for i in 0..24u8 {
        let v = 8 + 10 * i;
        let dist = distance(v, v, v);
        if dist < best.0 {
            best = (dist, 232 + i);
        }
    }
    best.1
}

/// What a piece of text means; the theme decides how that looks.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tone {
    Text,
    Dim,
    Bright,
    Dark,
    Warn,
    Crit,
    Info,
    Level(Level),
}

impl Tone {
    pub fn for_level(level: Option<Level>) -> Self {
        level.map(Tone::Level).unwrap_or(Tone::Text)
    }
}

#[derive(Debug, Clone)]
pub struct Theme {
    /// Applied to the whole screen. Empty in 16-color and no-color modes so the
    /// terminal's own background stays.
    pub base: Style,
    pub border: Style,
    pub title: Style,
    pub selected: Style,
    pub tab_active: Style,
    pub tab_number: Style,
    pub key: Style,
    pub segment_off: Style,
    text: Style,
    dim: Style,
    bright: Style,
    dark: Style,
    warn: Style,
    crit: Style,
    info: Style,
}

impl Theme {
    pub fn new(mode: ColorMode) -> Self {
        let t = tokens();
        let p = &t.phosphor;
        let a = &t.ansi16;
        let color = |rgb: Rgb, ansi: Option<u8>| -> Option<Color> {
            match mode {
                ColorMode::TrueColor => Some(Color::Rgb(rgb.r, rgb.g, rgb.b)),
                ColorMode::Ansi256 => Some(Color::Indexed(nearest_256(rgb))),
                ColorMode::Ansi16 => ansi.map(Color::Indexed),
                ColorMode::None => None,
            }
        };
        let fg = |rgb: Rgb, ansi: Option<u8>| {
            let mut s = Style::default();
            if let Some(c) = color(rgb, ansi) {
                s = s.fg(c);
            }
            s
        };
        if mode == ColorMode::None {
            return Self {
                base: Style::default(),
                border: Style::default(),
                title: Style::default().add_modifier(Modifier::BOLD),
                selected: Style::default().add_modifier(Modifier::REVERSED),
                tab_active: Style::default().add_modifier(Modifier::REVERSED | Modifier::BOLD),
                tab_number: Style::default(),
                key: Style::default().add_modifier(Modifier::BOLD),
                segment_off: Style::default(),
                text: Style::default(),
                dim: Style::default().add_modifier(Modifier::DIM),
                bright: Style::default().add_modifier(Modifier::BOLD),
                dark: Style::default(),
                warn: Style::default().add_modifier(Modifier::BOLD),
                crit: Style::default().add_modifier(Modifier::BOLD),
                info: Style::default(),
            };
        }
        let mut base = fg(p.text, a.text);
        if let Some(bg) = color(p.bg, a.bg) {
            base = base.bg(bg);
        }
        let selected_bg = color(p.dark, a.dark);
        let selected_fg = color(p.selected_text, a.selected_text);
        let mut selected = Style::default();
        if let Some(bg) = selected_bg {
            selected = selected.bg(bg);
        }
        if let Some(fg) = selected_fg {
            selected = selected.fg(fg);
        }
        let mut tab_active = Style::default().add_modifier(Modifier::BOLD);
        if let Some(bg) = color(p.bright, a.bright) {
            tab_active = tab_active.bg(bg);
        }
        if let Some(fg) = selected_fg {
            tab_active = tab_active.fg(fg);
        }
        Self {
            base,
            border: fg(p.line, a.line),
            title: fg(p.bright, a.bright),
            selected,
            tab_active,
            tab_number: fg(p.dark, a.dark),
            key: fg(p.bright, a.bright),
            segment_off: fg(p.segment_off, a.segment_off),
            text: fg(p.text, a.text),
            dim: fg(p.dim, a.dim),
            bright: fg(p.bright, a.bright),
            dark: fg(p.dark, a.dark),
            warn: fg(p.warn, a.warn),
            crit: fg(p.crit, a.crit).add_modifier(Modifier::BOLD),
            info: fg(p.info, a.info),
        }
    }

    pub fn tone(&self, tone: Tone) -> Style {
        match tone {
            Tone::Text => self.text,
            Tone::Dim => self.dim,
            Tone::Bright => self.bright,
            Tone::Dark => self.dark,
            Tone::Warn => self.warn,
            Tone::Crit => self.crit,
            Tone::Info => self.info,
            Tone::Level(level) => self.level(level),
        }
    }

    /// Band styles from the design package: dark green, bright green, amber, red.
    pub fn level(&self, level: Level) -> Style {
        match level {
            Level::Normal => self.dark,
            Level::Elevated => self.bright,
            Level::Warning => self.warn,
            Level::Critical => self.crit,
        }
    }

    /// Every style this theme can produce, for tests.
    #[cfg(test)]
    pub fn all_styles(&self) -> Vec<Style> {
        let mut v = vec![
            self.base,
            self.border,
            self.title,
            self.selected,
            self.tab_active,
            self.tab_number,
            self.key,
            self.segment_off,
        ];
        for tone in [
            Tone::Text,
            Tone::Dim,
            Tone::Bright,
            Tone::Dark,
            Tone::Warn,
            Tone::Crit,
            Tone::Info,
            Tone::Level(Level::Normal),
            Tone::Level(Level::Elevated),
            Tone::Level(Level::Warning),
            Tone::Level(Level::Critical),
        ] {
            v.push(self.tone(tone));
        }
        v
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn env<'a>(pairs: &'a [(&'a str, &'a str)]) -> impl Fn(&str) -> Option<String> + 'a {
        move |name| {
            pairs
                .iter()
                .find(|(k, _)| *k == name)
                .map(|(_, v)| v.to_string())
        }
    }

    #[test]
    fn detection_follows_the_environment() {
        assert_eq!(
            ColorMode::detect(false, env(&[("COLORTERM", "truecolor"), ("TERM", "xterm")])),
            ColorMode::TrueColor
        );
        assert_eq!(
            ColorMode::detect(false, env(&[("COLORTERM", "24bit")])),
            ColorMode::TrueColor
        );
        assert_eq!(
            ColorMode::detect(false, env(&[("TERM", "xterm-256color")])),
            ColorMode::Ansi256
        );
        assert_eq!(
            ColorMode::detect(false, env(&[("TERM", "xterm")])),
            ColorMode::Ansi16
        );
        assert_eq!(
            ColorMode::detect(false, env(&[("TERM", "dumb"), ("COLORTERM", "truecolor")])),
            ColorMode::None
        );
        assert_eq!(
            ColorMode::detect(false, env(&[("NO_COLOR", "1"), ("COLORTERM", "truecolor")])),
            ColorMode::None
        );
        // An empty NO_COLOR does not disable color.
        assert_eq!(
            ColorMode::detect(false, env(&[("NO_COLOR", ""), ("TERM", "xterm-256color")])),
            ColorMode::Ansi256
        );
        assert_eq!(
            ColorMode::detect(true, env(&[("COLORTERM", "truecolor")])),
            ColorMode::None
        );
    }

    #[test]
    fn nearest_256_maps_token_colors() {
        let rgb = |r, g, b| Rgb { r, g, b };
        assert_eq!(nearest_256(rgb(0, 0, 0)), 16);
        assert_eq!(nearest_256(rgb(255, 255, 255)), 231);
        // #55ff55 sits between cube levels 95 and 255 on red and blue.
        assert_eq!(nearest_256(rgb(0x55, 0xff, 0x55)), 16 + 36 + 6 * 5 + 1);
        assert_eq!(nearest_256(rgb(0x00, 0xaa, 0x00)), 16 + 6 * 3);
        // A mid gray prefers the gray ramp.
        assert_eq!(nearest_256(rgb(128, 128, 128)), 244);
    }

    #[test]
    fn no_color_theme_has_no_colors() {
        let theme = Theme::new(ColorMode::None);
        for style in theme.all_styles() {
            assert_eq!(style.fg, None, "{style:?}");
            assert_eq!(style.bg, None, "{style:?}");
        }
        assert!(theme.selected.add_modifier.contains(Modifier::REVERSED));
    }

    #[test]
    fn sixteen_color_theme_uses_token_indices_only() {
        let theme = Theme::new(ColorMode::Ansi16);
        for style in theme.all_styles() {
            for color in [style.fg, style.bg].into_iter().flatten() {
                assert!(
                    matches!(color, Color::Indexed(i) if i < 16),
                    "{color:?} is not an ANSI 16 index"
                );
            }
        }
        assert_eq!(theme.base.bg, None, "16-color mode keeps the terminal background");
    }

    #[test]
    fn selected_row_is_dark_green_with_black_text() {
        let theme = Theme::new(ColorMode::TrueColor);
        assert_eq!(theme.selected.bg, Some(Color::Rgb(0x00, 0xaa, 0x00)));
        assert_eq!(theme.selected.fg, Some(Color::Rgb(0, 0, 0)));
    }
}
