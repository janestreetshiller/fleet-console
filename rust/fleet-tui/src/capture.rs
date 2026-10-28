//! Documentation captures: every view of one fixture scenario rendered into
//! `TestBackend` and written as plain text, one file per view, named
//! `<scenario>-<view>-<cols>x<rows>.txt`. Fixture builds only.

use crate::app::{App, View};
use crate::output;
use crate::source::{Settings, Source};
use crate::theme::Theme;
use fleet_ui_core::fixtures::Scenario;
use std::path::{Path, PathBuf};

pub fn file_name(scenario: Scenario, view: View, cols: u16, rows: u16) -> String {
    format!("{}-{}-{cols}x{rows}.txt", scenario.name(), view.name())
}

pub fn write(
    dir: &Path,
    scenario: Scenario,
    (cols, rows): (u16, u16),
    settings: &Settings,
    theme: &Theme,
) -> Result<Vec<PathBuf>, String> {
    std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    let source = Source::fixture(scenario);
    let dash = source.dashboard(settings);
    let mut written = Vec::new();
    for view in View::ALL {
        let app = App::new(view, settings.read_only);
        let buffer = output::render(&dash, &app, theme, cols, rows);
        let path = dir.join(file_name(scenario, view, cols, rows));
        std::fs::write(&path, output::text(&buffer, false))
            .map_err(|e| format!("{}: {e}", path.display()))?;
        written.push(path);
    }
    Ok(written)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::ColorMode;

    #[test]
    fn capture_writes_one_file_per_view() {
        let dir = std::env::temp_dir().join(format!("fleet-tui-capture-{}", std::process::id()));
        let settings = crate::source::tests::settings(false);
        let written = write(
            &dir,
            Scenario::Warning,
            (80, 24),
            &settings,
            &Theme::new(ColorMode::None),
        )
        .unwrap();
        assert_eq!(written.len(), 6);
        assert!(dir.join("warning-services-80x24.txt").exists());
        let text = std::fs::read_to_string(dir.join("warning-overview-80x24.txt")).unwrap();
        assert!(text.contains("Fleet Console"));
        assert!(text.contains(fleet_ui_core::fixtures::MARKER), "captures disclose fixtures");
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
