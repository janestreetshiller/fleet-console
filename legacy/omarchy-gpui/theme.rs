//! FleetConsole Spatial Theme and Palette.

use gpui::{Hsla, hsla};

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SpatialPalette {
    pub bg_deep: Hsla,
    pub bg_surface: Hsla,
    pub bg_card: Hsla,
    pub border_subtle: Hsla,
    pub border_active: Hsla,
    pub text_bright: Hsla,
    pub text_muted: Hsla,
    pub text_dim: Hsla,
    pub accent_cyan: Hsla,
    pub accent_purple: Hsla,
    pub glow_agent: Hsla,
    pub status_nominal: Hsla,
    pub status_warning: Hsla,
    pub status_critical: Hsla,
}

impl Default for SpatialPalette {
    fn default() -> Self {
        Self {
            bg_deep: hsla(220.0 / 360.0, 0.20, 0.07, 1.0),
            bg_surface: hsla(220.0 / 360.0, 0.16, 0.11, 1.0),
            bg_card: hsla(220.0 / 360.0, 0.14, 0.15, 0.85),
            border_subtle: hsla(220.0 / 360.0, 0.15, 0.22, 1.0),
            border_active: hsla(185.0 / 360.0, 0.80, 0.45, 1.0),
            text_bright: hsla(210.0 / 360.0, 0.10, 0.95, 1.0),
            text_muted: hsla(215.0 / 360.0, 0.15, 0.70, 1.0),
            text_dim: hsla(215.0 / 360.0, 0.12, 0.45, 1.0),
            accent_cyan: hsla(185.0 / 360.0, 0.85, 0.50, 1.0),
            accent_purple: hsla(270.0 / 360.0, 0.75, 0.60, 1.0),
            glow_agent: hsla(190.0 / 360.0, 0.90, 0.55, 0.35),
            status_nominal: hsla(145.0 / 360.0, 0.70, 0.45, 1.0),
            status_warning: hsla(38.0 / 360.0, 0.90, 0.50, 1.0),
            status_critical: hsla(355.0 / 360.0, 0.85, 0.55, 1.0),
        }
    }
}
