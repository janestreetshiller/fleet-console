//! Rendering tests over every fixture scenario, view and size.

use crate::app::{App, Key, Pane, View};
use crate::output;
use crate::source::tests::dashboard;
use crate::theme::{ColorMode, Theme};
use fleet_ui_core::fixtures::Scenario;
use ratatui::style::Color;

const SIZES: [(u16, u16); 3] = [(80, 24), (120, 40), (200, 60)];

fn screen(scenario: Scenario, app: &App, mode: ColorMode, (cols, rows): (u16, u16)) -> String {
    let dash = dashboard(scenario, app.read_only);
    output::text(&output::render(&dash, app, &Theme::new(mode), cols, rows), false)
}

/// Rules from the workstation UI baseline that apply to terminal text.
fn assert_baseline(text: &str, context: &str) {
    for ornament in [" · ", " | ", "//", "→", "←", "»", "«", "›", "‹", "•"] {
        assert!(
            !text.contains(ornament),
            "{context}: ornament {ornament:?} in\n{text}"
        );
    }
}

#[test]
fn every_view_renders_for_every_scenario_and_size() {
    for scenario in Scenario::ALL {
        for size in SIZES {
            for view in View::ALL {
                let app = App::new(view, false);
                let text = screen(scenario, &app, ColorMode::TrueColor, size);
                let context = format!("{} {} {}x{}", scenario.name(), view.name(), size.0, size.1);
                assert!(text.contains("Fleet Console"), "{context}");
                assert!(text.contains(view.title()), "{context}");
                assert_baseline(&text, &context);
            }
        }
    }
}

#[test]
fn every_pane_renders_for_every_scenario() {
    for scenario in Scenario::ALL {
        let dash = dashboard(scenario, false);
        for size in SIZES {
            for view in View::ALL {
                for pane in [Pane::Detail, Pane::Handoff] {
                    let mut app = App::new(view, false);
                    app.sync(&dash);
                    app.pane = pane;
                    let text = output::text(
                        &output::render(&dash, &app, &Theme::new(ColorMode::Ansi256), size.0, size.1),
                        false,
                    );
                    assert_baseline(&text, &format!("{} {} {pane:?}", scenario.name(), view.name()));
                    if pane == Pane::Handoff && crate::content::len(view, &dash) > 0 && size.1 >= 40 {
                        assert!(
                            text.contains("Dispatching work to an agent"),
                            "{} {}:\n{text}",
                            scenario.name(),
                            view.name()
                        );
                    }
                }
            }
        }
    }
}

#[test]
fn disconnected_banner_is_present() {
    let app = App::new(View::Overview, false);
    for size in SIZES {
        let text = screen(Scenario::Disconnected, &app, ColorMode::None, size);
        assert!(text.contains(" disconnected "), "{text}");
        assert!(text.contains("Controller unavailable"), "{text}");
        assert!(text.contains("no controller socket"), "{text}");
        assert!(text.contains("controller disconnected"), "header names the phase:\n{text}");
    }
    let stale = screen(Scenario::Stale, &app, ColorMode::None, (120, 40));
    assert!(stale.contains("Controller data is stale, last read 45s ago"), "{stale}");
    let error = screen(Scenario::Error, &app, ColorMode::None, (120, 40));
    assert!(error.contains("did not answer before the deadline"), "{error}");
    let loading = screen(Scenario::Loading, &app, ColorMode::None, (120, 40));
    assert!(loading.contains("Connecting to the controller"), "{loading}");
    let live = screen(Scenario::Healthy, &app, ColorMode::None, (120, 40));
    assert!(!live.contains("Controller unavailable"));
}

#[test]
fn confirmation_line_is_drawn_before_a_stop_is_sent() {
    let dash = dashboard(Scenario::Healthy, false);
    let mut app = App::new(View::Services, false);
    app.sync(&dash);
    let i = dash.services.iter().position(|r| r.name == "render-studio").unwrap();
    let p = app.visible(View::Services, &dash).iter().position(|&v| v == i).unwrap();
    app.click_row(&dash, p);
    assert_eq!(app.handle_key(Key::Char('s'), &dash), crate::app::Command::None);
    let text = output::text(
        &output::render(&dash, &app, &Theme::new(ColorMode::TrueColor), 120, 40),
        false,
    );
    assert!(text.contains("Stop render-studio? pid 3302"), "{text}");
    assert!(text.contains("y confirm  n cancel"), "{text}");
}

#[test]
fn no_color_rendering_has_no_colors() {
    for view in View::ALL {
        let dash = dashboard(Scenario::Critical, false);
        let mut app = App::new(view, false);
        app.sync(&dash);
        let buffer = output::render(&dash, &app, &Theme::new(ColorMode::None), 120, 40);
        for cell in buffer.content() {
            assert_eq!(cell.fg, Color::Reset, "{view:?} cell {:?}", cell.symbol());
            assert_eq!(cell.bg, Color::Reset, "{view:?} cell {:?}", cell.symbol());
        }
        // Meaning survives without color: states are words.
        let text = output::text(&buffer, false);
        if view == View::Overview {
            assert!(text.contains("critical") && text.contains("offline"), "{text}");
        }
    }
}

#[test]
fn unavailable_values_render_as_dashes() {
    let app = App::new(View::Overview, false);
    let text = screen(Scenario::Critical, &app, ColorMode::None, (120, 40));
    let offline = text.lines().find(|l| l.contains("node-e")).expect("offline node row");
    assert!(offline.contains("--"), "{offline}");
    assert!(offline.contains("offline"), "{offline}");
}

#[test]
fn terminal_too_small_message() {
    let app = App::new(View::Overview, false);
    let text = screen(Scenario::Healthy, &app, ColorMode::None, (59, 15));
    assert!(text.contains("Terminal too small"), "{text}");
    assert!(text.contains("59x15"), "{text}");
    let text = screen(Scenario::Healthy, &app, ColorMode::None, (60, 16));
    assert!(!text.contains("Terminal too small"), "{text}");
}

#[test]
fn help_overlay_lists_every_key() {
    let dash = dashboard(Scenario::Healthy, false);
    let mut app = App::new(View::Overview, false);
    app.handle_key(Key::Char('?'), &dash);
    let text = output::text(&output::render(&dash, &app, &Theme::new(ColorMode::None), 120, 40), false);
    for key in ["1-6", "enter", "renew", "tail", "approve or deny", "ctrl-c"] {
        assert!(text.contains(key), "{key} missing:\n{text}");
    }
}

#[test]
fn processes_view_draws_the_tree_and_remote_note() {
    let app = App::new(View::Processes, false);
    let text = screen(Scenario::Healthy, &app, ColorMode::None, (120, 40));
    assert!(text.contains("fleetd"), "{text}");
    assert!(text.contains("├─ ") || text.contains("└─ "), "{text}");

    let dash = {
        let source = crate::source::Source::fixture(Scenario::Healthy);
        source.dashboard(&crate::source::Settings {
            read_only: false,
            assume_remote_controller: true,
            socket_label: String::new(),
        })
    };
    let text = output::text(&output::render(&dash, &app, &Theme::new(ColorMode::None), 120, 40), false);
    assert!(text.contains("another machine"), "{text}");
}

#[test]
fn storage_shows_largest_paths_honestly() {
    let app = App::new(View::Storage, false);
    let text = screen(Scenario::Healthy, &app, ColorMode::None, (120, 40));
    assert!(text.contains("unavailable: per-path scanning runs in the macOS app only"), "{text}");
    assert!(text.contains("/Volumes/Archive"), "{text}");
}

#[test]
fn read_only_header_and_reply_column() {
    let mut app = App::new(View::Agents, true);
    let dash = dashboard(Scenario::Healthy, true);
    app.sync(&dash);
    let text = output::text(&output::render(&dash, &app, &Theme::new(ColorMode::None), 160, 40), false);
    assert!(text.contains("read-only client"), "reply column:\n{text}");
    app.handle_key(Key::Enter, &dash);
    let text = output::text(&output::render(&dash, &app, &Theme::new(ColorMode::None), 160, 40), false);
    assert!(text.contains("unavailable: this client is read-only"), "detail pane:\n{text}");
}

#[test]
fn ansi_capture_uses_the_selected_bar() {
    let dash = dashboard(Scenario::Healthy, false);
    let mut app = App::new(View::Services, false);
    app.sync(&dash);
    let buffer = output::render(&dash, &app, &Theme::new(ColorMode::TrueColor), 120, 40);
    let selected = buffer
        .content()
        .iter()
        .filter(|c| c.bg == Color::Rgb(0x00, 0xaa, 0x00) && c.fg == Color::Rgb(0, 0, 0))
        .count();
    assert!(selected >= 50, "selected row is a dark green bar with black text ({selected} cells)");
}
