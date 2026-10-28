//! Design tokens from `design/tokens.json`, the one source for the terminal
//! palette, the GPUI theme and `design/tokens.css`.
//!
//! The JSON is compiled into the binary and parsed once. A test renders the
//! CSS from the same file and fails when `design/tokens.css` has drifted;
//! `FLEET_WRITE_TOKENS=1` rewrites it instead.

use crate::thresholds::Level;
use serde::Deserialize;
use std::sync::OnceLock;

const SOURCE: &str = include_str!("../../../design/tokens.json");

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rgb {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

impl Rgb {
    /// `0xRRGGBB`, the form `gpui::rgb` takes.
    pub fn hex(self) -> u32 {
        (u32::from(self.r) << 16) | (u32::from(self.g) << 8) | u32::from(self.b)
    }

    fn parse(text: &str) -> Result<Self, String> {
        let digits = text.strip_prefix('#').ok_or_else(|| format!("{text}: expected #RRGGBB"))?;
        if digits.len() != 6 {
            return Err(format!("{text}: expected #RRGGBB"));
        }
        let value = u32::from_str_radix(digits, 16).map_err(|e| format!("{text}: {e}"))?;
        Ok(Self { r: (value >> 16) as u8, g: (value >> 8) as u8, b: value as u8 })
    }

    fn css(self) -> String {
        format!("#{:06x}", self.hex())
    }
}

impl<'de> Deserialize<'de> for Rgb {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let text = String::deserialize(d)?;
        Rgb::parse(&text).map_err(serde::de::Error::custom)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Palette {
    pub bg: Rgb,
    pub panel: Rgb,
    pub line: Rgb,
    pub dim: Rgb,
    pub dark: Rgb,
    pub bright: Rgb,
    pub text: Rgb,
    pub warn: Rgb,
    pub crit: Rgb,
    pub info: Rgb,
    pub segment_off: Rgb,
    pub selected_text: Rgb,
}

impl Palette {
    /// The design package's band colors: dark green, bright green, amber, red.
    pub fn level(&self, level: Level) -> Rgb {
        match level {
            Level::Normal => self.dark,
            Level::Elevated => self.bright,
            Level::Warning => self.warn,
            Level::Critical => self.crit,
        }
    }
}

/// ANSI 16-color indices for terminals without truecolor or 256 colors.
/// `None` means the terminal's own default foreground or background.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Ansi16 {
    pub bg: Option<u8>,
    pub panel: Option<u8>,
    pub line: Option<u8>,
    pub dim: Option<u8>,
    pub dark: Option<u8>,
    pub bright: Option<u8>,
    pub text: Option<u8>,
    pub warn: Option<u8>,
    pub crit: Option<u8>,
    pub info: Option<u8>,
    pub segment_off: Option<u8>,
    pub selected_text: Option<u8>,
}

impl Ansi16 {
    pub fn level(&self, level: Level) -> Option<u8> {
        match level {
            Level::Normal => self.dark,
            Level::Elevated => self.bright,
            Level::Warning => self.warn,
            Level::Critical => self.crit,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct Font {
    pub stack: String,
    pub family: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
pub struct Grid {
    pub cell: u32,
    pub gap: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Deserialize)]
pub struct Thresholds {
    pub elevated: f64,
    pub warning: f64,
    pub critical: f64,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct Tokens {
    pub font: Font,
    pub grid: Grid,
    pub thresholds: Thresholds,
    /// The dark terminal palette from the design package.
    pub phosphor: Palette,
    /// The light appearance for the GPUI window, contrast-checked against
    /// `bg` (see the tests below).
    pub paper: Palette,
    /// The dark glass appearance for the GPUI window: a near-black substrate
    /// with a vibrant level ramp. The bands stay a heat ladder — green,
    /// yellow, orange, red — so the words normal, elevated, warning and
    /// critical keep naming the same hues.
    pub fog: Palette,
    pub ansi16: Ansi16,
}

pub fn tokens() -> &'static Tokens {
    static TOKENS: OnceLock<Tokens> = OnceLock::new();
    TOKENS.get_or_init(|| serde_json::from_str(SOURCE).expect("design/tokens.json is valid; see theme tests"))
}

/// `design/tokens.css`, rendered from the tokens.
pub fn render_css(tokens: &Tokens) -> String {
    let p = &tokens.phosphor;
    let l = &tokens.paper;
    let f = &tokens.fog;
    let rows = |palette: &Palette| {
        [
            ("bg", palette.bg),
            ("panel", palette.panel),
            ("line", palette.line),
            ("dim", palette.dim),
            ("dark", palette.dark),
            ("bright", palette.bright),
            ("text", palette.text),
            ("warn", palette.warn),
            ("crit", palette.crit),
            ("info", palette.info),
            ("segment-off", palette.segment_off),
            ("selected-text", palette.selected_text),
        ]
        .iter()
        .map(|(name, rgb)| format!("  --fc-{name}: {};\n", rgb.css()))
        .collect::<String>()
    };
    format!(
        "/* Fleet Console design tokens. Generated from tokens.json by fleet-ui-core; edit tokens.json, not this file. */\n\
         :root {{\n{}  --fc-font: {};\n  --fc-cell: {}px;\n  --fc-gap: {}px;\n}}\n\
         /* Glass appearance: a near-black substrate with a vibrant level ramp,\n\
            used by the GPUI window in dark mode over the blurred material. */\n\
         [data-fc-appearance=\"fog\"] {{\n{}}}\n\
         /* Paper appearance, used by surfaces that offer a light mode. */\n\
         [data-fc-appearance=\"paper\"] {{\n{}}}\n\
         @media (prefers-reduced-motion: reduce) {{ * {{ animation: none !important; transition: none !important; }} }}\n",
        rows(p),
        tokens.font.stack,
        tokens.grid.cell,
        tokens.grid.gap,
        rows(f),
        rows(l),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn luminance(c: Rgb) -> f64 {
        let channel = |v: u8| {
            let s = f64::from(v) / 255.0;
            if s <= 0.03928 {
                s / 12.92
            } else {
                ((s + 0.055) / 1.055).powf(2.4)
            }
        };
        0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    fn contrast(a: Rgb, b: Rgb) -> f64 {
        let (x, y) = (luminance(a), luminance(b));
        (x.max(y) + 0.05) / (x.min(y) + 0.05)
    }

    #[test]
    fn tokens_parse() {
        let t = tokens();
        assert_eq!(t.phosphor.bright.hex(), 0x55ff55);
        assert_eq!(t.grid.cell, 10);
    }

    #[test]
    fn thresholds_match_the_band_code() {
        let t = tokens().thresholds;
        for (edge, below, above) in [
            (t.elevated, Level::Normal, Level::Elevated),
            (t.warning, Level::Elevated, Level::Warning),
            (t.critical, Level::Warning, Level::Critical),
        ] {
            assert_eq!(Level::for_percent(edge), below);
            assert_eq!(Level::for_percent(edge + 0.1), above);
        }
    }

    #[test]
    fn text_tokens_meet_contrast_on_their_background() {
        for (name, palette) in [
            ("phosphor", tokens().phosphor),
            ("paper", tokens().paper),
            ("fog", tokens().fog),
        ] {
            for (role, color, minimum) in [
                ("text", palette.text, 7.0),
                ("bright", palette.bright, 4.5),
                ("dim", palette.dim, 3.0),
                ("warn", palette.warn, 4.5),
                ("crit", palette.crit, 4.5),
                ("info", palette.info, 4.5),
            ] {
                let ratio = contrast(color, palette.bg);
                assert!(ratio >= minimum, "{name} {role} contrast {ratio:.2} below {minimum}");
            }
            let selected = contrast(palette.selected_text, palette.dark);
            assert!(selected >= 4.5, "{name} selected row contrast {selected:.2}");
        }
    }

    #[test]
    fn tokens_css_is_generated_from_tokens_json() {
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../design/tokens.css");
        let expected = render_css(tokens());
        if std::env::var_os("FLEET_WRITE_TOKENS").is_some() {
            std::fs::write(path, &expected).unwrap();
        }
        let actual = std::fs::read_to_string(path).unwrap_or_default();
        assert_eq!(
            actual, expected,
            "design/tokens.css differs from tokens.json; rerun with FLEET_WRITE_TOKENS=1"
        );
    }
}
