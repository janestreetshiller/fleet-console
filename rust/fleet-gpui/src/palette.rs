//! Colors and font for the window, from `design/tokens.json` through
//! `fleet_ui_core::theme`. Dark mode uses the glass fog palette by default —
//! a translucent panel over the blurred window material with a vibrant level
//! ramp — or the phosphor palette when `--theme phosphor` says so; light mode
//! uses the paper palette. The window re-reads the choice when the system
//! appearance changes.

use fleet_ui_core::map::NodeKind;
use fleet_ui_core::theme::{tokens, Palette, Rgb};
use fleet_ui_core::thresholds::Level;
use gpui::{rgb, Hsla, WindowAppearance, WindowBackgroundAppearance};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Appearance {
    Dark,
    Light,
}

/// Which dark palette the window uses. Fog is the default; phosphor stays
/// available from the command line.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DarkTheme {
    Fog,
    Phosphor,
}

impl DarkTheme {
    pub fn parse_text(text: &str) -> Option<Self> {
        match text {
            "fog" => Some(Self::Fog),
            "phosphor" => Some(Self::Phosphor),
            _ => None,
        }
    }

    fn palette(self) -> &'static Palette {
        match self {
            Self::Fog => &tokens().fog,
            Self::Phosphor => &tokens().phosphor,
        }
    }
}

/// The dark theme the windows were opened with, set once at start-up.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UiDarkTheme(pub DarkTheme);

impl gpui::Global for UiDarkTheme {}

fn dark_theme(cx: &gpui::App) -> DarkTheme {
    cx.try_global::<UiDarkTheme>()
        .map(|t| t.0)
        .unwrap_or(DarkTheme::Fog)
}

/// The window's background material. Only fog draws its chrome over the
/// system blur; phosphor and paper need the plain backdrop because their
/// fills are opaque, and a blur under them would only cost.
pub fn window_background(cx: &gpui::App) -> WindowBackgroundAppearance {
    if dark_theme(cx) == DarkTheme::Fog {
        WindowBackgroundAppearance::Blurred
    } else {
        WindowBackgroundAppearance::Opaque
    }
}

impl Appearance {
    pub fn from_window(appearance: WindowAppearance) -> Self {
        match appearance {
            WindowAppearance::Dark | WindowAppearance::VibrantDark => Self::Dark,
            WindowAppearance::Light | WindowAppearance::VibrantLight => Self::Light,
        }
    }
}

fn color(value: Rgb) -> Hsla {
    rgb(value.hex()).into()
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Colors {
    pub appearance: Appearance,
    pub dark_theme: DarkTheme,
    pub bg: Hsla,
    pub panel: Hsla,
    pub line: Hsla,
    pub dim: Hsla,
    pub dark: Hsla,
    pub bright: Hsla,
    pub text: Hsla,
    pub warn: Hsla,
    pub crit: Hsla,
    pub info: Hsla,
    pub segment_off: Hsla,
    pub selected_text: Hsla,
}

/// The translucent layered panel: the fog look. `Chrome` values are alphas
/// layered over the window's blurred background material; every one stays
/// behind opaque text, so no value or reason is drawn translucent.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Glass;

impl Glass {
    /// The window root: mostly transparent so the blurred material reads as
    /// fog behind the chrome.
    pub fn window(&self, bg: Hsla) -> Hsla {
        bg.opacity(0.78)
    }
    /// Cards and panels.
    pub fn panel(&self, panel: Hsla) -> Hsla {
        panel.opacity(0.62)
    }
    /// The soft glow ring behind a node. Always behind the node plate.
    pub fn glow(&self, accent: Hsla) -> Hsla {
        accent.opacity(0.16)
    }
    /// Edge strokes on the map; the faint route lines between nodes.
    pub fn edge(&self, line: Hsla) -> Hsla {
        line.opacity(0.7)
    }
    /// A filled swatch in the legend or a badge plate.
    pub fn swatch(&self, accent: Hsla) -> Hsla {
        accent.opacity(0.22)
    }
}

/// Vibrant category colors for the relational map, one per node kind. They
/// label nothing on their own: every surface also carries the kind's word, in
/// the inspector, the legend or the node label itself.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MapAccents {
    pub controller: Hsla,
    pub device: Hsla,
    pub service: Hsla,
    pub agent: Hsla,
    pub process: Hsla,
    pub volume: Hsla,
}

impl MapAccents {
    pub fn for_colors(colors: &Colors) -> Self {
        match colors.appearance {
            Appearance::Dark => Self {
                controller: rgb(0xffad56).into(),
                device: rgb(0x8caaff).into(),
                service: rgb(0xb08aee).into(),
                agent: rgb(0x4dd0e1).into(),
                process: rgb(0x55d58a).into(),
                volume: rgb(0xf480bc).into(),
            },
            // The paper appearance has its own accents, slightly deeper so
            // they hold on the light substrate.
            Appearance::Light => Self {
                controller: rgb(0xd97706).into(),
                device: rgb(0x2563eb).into(),
                service: rgb(0x7c3aed).into(),
                agent: rgb(0x0e7490).into(),
                process: rgb(0x15803d).into(),
                volume: rgb(0xdb2777).into(),
            },
        }
    }

    /// The accent of a node kind, for the renderer that walks nodes by kind.
    pub fn map_accent(self, kind: NodeKind) -> Hsla {
        match kind {
            NodeKind::Controller => self.controller,
            NodeKind::Device => self.device,
            NodeKind::Service => self.service,
            NodeKind::Agent => self.agent,
            NodeKind::Process => self.process,
            NodeKind::Volume => self.volume,
        }
    }
}

impl Colors {
    pub fn for_app(appearance: WindowAppearance, cx: &gpui::App) -> Self {
        Self::new(Appearance::from_window(appearance), dark_theme(cx))
    }

    pub fn new(appearance: Appearance, theme: DarkTheme) -> Self {
        let p = match appearance {
            Appearance::Dark => theme.palette(),
            Appearance::Light => &tokens().paper,
        };
        Self {
            appearance,
            dark_theme: theme,
            bg: color(p.bg),
            panel: color(p.panel),
            line: color(p.line),
            dim: color(p.dim),
            dark: color(p.dark),
            bright: color(p.bright),
            text: color(p.text),
            warn: color(p.warn),
            crit: color(p.crit),
            info: color(p.info),
            segment_off: color(p.segment_off),
            selected_text: color(p.selected_text),
        }
    }

    pub fn for_window(appearance: WindowAppearance, cx: &gpui::App) -> Self {
        Self::for_app(appearance, cx)
    }

    /// The window root: translucent over the blurred material in the fog
    /// theme, opaque elsewhere.
    pub fn window_fill(&self) -> Hsla {
        self.glass()
            .map(|g| g.window(self.bg))
            .unwrap_or(self.bg)
    }

    /// Panel and card fills.
    pub fn panel_fill(&self) -> Hsla {
        self.glass().map(|g| g.panel(self.panel)).unwrap_or(self.panel)
    }

    /// Whether the window's background material is up: only the fog theme is
    /// translucent over the blurred window; phosphor and paper draw opaque.
    pub fn glass(&self) -> Option<Glass> {
        if self.appearance == Appearance::Dark && self.dark_theme == DarkTheme::Fog {
            Some(Glass)
        } else {
            None
        }
    }

    /// The band color for a lit segment.
    pub fn level(&self, level: Level) -> Hsla {
        let p = self.palette();
        color(p.level(level))
    }

    fn palette(&self) -> &'static Palette {
        match self.appearance {
            Appearance::Dark => self.dark_theme.palette(),
            Appearance::Light => &tokens().paper,
        }
    }

    /// Text color for a value in a band: ordinary text until warning, then
    /// amber and red. The band's word is always shown next to it.
    pub fn level_text(&self, level: Option<Level>) -> Hsla {
        match level {
            Some(Level::Warning) => self.warn,
            Some(Level::Critical) => self.crit,
            _ => self.text,
        }
    }

    /// Border color for something whose worst band is `level`.
    pub fn level_border(&self, level: Option<Level>) -> Hsla {
        match level {
            Some(Level::Warning) => self.warn,
            Some(Level::Critical) => self.crit,
            _ => self.line,
        }
    }
}

/// Monospace families in preference order: the design font first, then the
/// common system monospace families on macOS and Linux.
pub const FONT_CANDIDATES: &[&str] = &[
    "Geist Mono",
    "SF Mono",
    "Menlo",
    "JetBrains Mono",
    "DejaVu Sans Mono",
    "Noto Sans Mono",
    "Liberation Mono",
    "Ubuntu Mono",
    "Monaco",
    "Courier New",
];

/// The first candidate the system has. When none is installed, fall back to
/// the platform's usual monospace family name and let GPUI's own fallback
/// stack resolve it.
pub fn choose_font(available: &[String]) -> &'static str {
    FONT_CANDIDATES
        .iter()
        .copied()
        .find(|candidate| available.iter().any(|name| name == candidate))
        .unwrap_or(if cfg!(target_os = "macos") {
            "Menlo"
        } else {
            "monospace"
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn appearance_selects_the_palette() {
        assert_eq!(
            Appearance::from_window(WindowAppearance::VibrantDark),
            Appearance::Dark
        );
        assert_eq!(
            Appearance::from_window(WindowAppearance::Light),
            Appearance::Light
        );
        assert_eq!(DarkTheme::Phosphor.palette().bright.hex(), 0x55ff55);
        assert_eq!(tokens().paper.bg.hex(), 0xfbfaf5);
        assert_eq!(DarkTheme::Fog.palette().bg.hex(), 0x09090b);
        let fog = Colors::new(Appearance::Dark, DarkTheme::Fog);
        let phosphor = Colors::new(Appearance::Dark, DarkTheme::Phosphor);
        let light = Colors::new(Appearance::Light, DarkTheme::Fog);
        assert_ne!(fog.bg, phosphor.bg);
        assert_ne!(fog.bg, light.bg);
    }

    #[test]
    fn the_level_ramp_stays_a_heat_ladder() {
        let c = Colors::new(Appearance::Dark, DarkTheme::Fog);
        let band = [
            c.level(Level::Normal),
            c.level(Level::Elevated),
            c.level(Level::Warning),
            c.level(Level::Critical),
        ];
        for (i, a) in band.iter().enumerate() {
            for b in band.iter().skip(i + 1) {
                assert_ne!(a, b, "two bands share one hue");
            }
        }
    }

    #[test]
    fn glass_chrome_belongs_to_fog_only() {
        assert!(Colors::new(Appearance::Dark, DarkTheme::Fog).glass().is_some());
        assert!(Colors::new(Appearance::Dark, DarkTheme::Phosphor)
            .glass()
            .is_none());
        assert!(Colors::new(Appearance::Light, DarkTheme::Fog).glass().is_none());
    }

    #[test]
    fn translucency_stays_between_washout_and_opaque() {
        let glass = Glass;
        let fog = Colors::new(Appearance::Dark, DarkTheme::Fog);
        for (name, hsla) in [
            ("window", glass.window(fog.bg)),
            ("panel", glass.panel(fog.panel)),
        ] {
            assert!(
                hsla.a > 0.05 && hsla.a < 0.95,
                "{name} alpha {:.2} is not glass",
                hsla.a
            );
        }
    }

    #[test]
    fn map_accents_are_one_hue_per_kind() {
        let fog = Colors::new(Appearance::Dark, DarkTheme::Fog);
        let accents = MapAccents::for_colors(&fog);
        let hues = [
            accents.controller,
            accents.device,
            accents.service,
            accents.agent,
            accents.process,
            accents.volume,
        ];
        for (i, a) in hues.iter().enumerate() {
            for b in hues.iter().skip(i + 1) {
                assert_ne!(a, b, "two node kinds share one accent");
            }
        }
        let paper = Colors::new(Appearance::Light, DarkTheme::Fog);
        assert_ne!(
            accents.device,
            MapAccents::for_colors(&paper).device,
            "the light accents are deeper than the dark ones"
        );
    }

    #[test]
    fn warning_and_critical_change_text_color() {
        let c = Colors::new(Appearance::Dark, DarkTheme::Fog);
        assert_eq!(c.level_text(None), c.text);
        assert_eq!(c.level_text(Some(Level::Elevated)), c.text);
        assert_eq!(c.level_text(Some(Level::Warning)), c.warn);
        assert_eq!(c.level_border(Some(Level::Critical)), c.crit);
        assert_eq!(c.level_border(Some(Level::Normal)), c.line);
    }

    #[test]
    fn font_prefers_geist_mono_then_system_monospace() {
        let names = |list: &[&str]| list.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert_eq!(choose_font(&names(&["Menlo", "Geist Mono"])), "Geist Mono");
        assert_eq!(choose_font(&names(&["Helvetica", "Menlo"])), "Menlo");
        assert_eq!(
            choose_font(&names(&["DejaVu Sans Mono", "Noto Sans Mono"])),
            "DejaVu Sans Mono"
        );
        let fallback = choose_font(&names(&["Helvetica"]));
        assert!(fallback == "Menlo" || fallback == "monospace");
    }
}
