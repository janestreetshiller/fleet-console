//! `fleet-tui`: the FleetConsole terminal client for macOS and Linux.
//!
//! Every value comes from `fleet-ui-core`: the controller connection and the
//! local telemetry sampler run on background threads there, and
//! `views::Dashboard::build` derives everything drawn here. Actions are
//! controller requests with `fleetctl` semantics; nothing in this binary
//! signals a process.

mod app;
#[cfg(any(test, feature = "fixtures"))]
mod capture;
mod cli;
mod content;
mod output;
mod plain;
mod runtime;
mod source;
mod theme;
mod ui;

#[cfg(test)]
mod tests;

use app::{App, View};
use cli::{Options, Parsed, StartView};
use fleet_ui_core::controller::{display_path, ControllerConfig};
use source::{Settings, Source, TAIL_BYTES};
use std::io::IsTerminal;
use std::time::Duration;
use theme::{ColorMode, Theme};

/// How long `--once` waits for the controller's first answer and a second
/// telemetry sample before printing what it has.
const ONCE_SETTLE: Duration = Duration::from_secs(8);
/// Size used for `--once` (and captures) when standard output is not a terminal.
const ONCE_SIZE: (u16, u16) = (120, 40);

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let code = match cli::parse(args.iter().map(String::as_str)) {
        Err(error) => {
            eprintln!("fleet-tui: {error}");
            2
        }
        Ok(Parsed::Help) => {
            print!("{}", cli::usage());
            0
        }
        Ok(Parsed::Version) => {
            println!("fleet-tui {}", fleet_ui_core::version());
            0
        }
        Ok(Parsed::Run(options)) => run(*options),
    };
    // Exit without joining the worker threads: an in-flight stop or restart
    // holds the action thread until its deadline, and the request has
    // already reached the controller.
    std::process::exit(code);
}

fn run(options: Options) -> i32 {
    let color = ColorMode::from_environment(options.no_color || options.plain);
    let theme = Theme::new(color);
    let mut settings = Settings {
        read_only: options.read_only,
        assume_remote_controller: options.remote_controller,
        socket_label: String::new(),
    };

    #[cfg(feature = "fixtures")]
    if let (Some(dir), Some(scenario)) = (&options.capture, options.fixture) {
        settings.socket_label = "fixture, no socket".into();
        let size = options.size.unwrap_or(ONCE_SIZE);
        return match capture::write(dir, scenario, size, &settings, &theme) {
            Ok(paths) => {
                for p in paths {
                    println!("{}", display_path(&p));
                }
                0
            }
            Err(e) => {
                eprintln!("fleet-tui: {e}");
                1
            }
        };
    }

    let (tx, rx) = runtime::channel();
    let source = make_source(&options, &mut settings, &tx);

    let start = match options.view {
        StartView::One(view) => view,
        StartView::All => View::Overview,
    };
    let code = if options.once {
        runtime::wait_for_data(&source, &rx, ONCE_SETTLE);
        let views: Vec<View> = match options.view {
            StartView::One(view) => vec![view],
            StartView::All => View::ALL.to_vec(),
        };
        if options.plain {
            plain::print_once(&source, &settings, &views);
        } else {
            let tty = std::io::stdout().is_terminal();
            let (cols, rows) = if tty {
                ratatui::crossterm::terminal::size().unwrap_or(ONCE_SIZE)
            } else {
                ONCE_SIZE
            };
            let dash = source.dashboard(&settings);
            for (i, view) in views.iter().enumerate() {
                let app = App::new(*view, options.read_only);
                let buffer = output::render(&dash, &app, &theme, cols, rows);
                if i > 0 {
                    println!();
                }
                print!("{}", output::text(&buffer, tty && color != ColorMode::None));
            }
        }
        0
    } else if options.plain {
        runtime::spawn_stdin_lines(tx);
        plain::run(&source, &settings, start, &rx)
    } else if !std::io::stdout().is_terminal() {
        eprintln!("fleet-tui: standard output is not a terminal; use --plain or --once");
        2
    } else {
        let interactive = runtime::Interactive {
            source: &source,
            settings: &settings,
            app: App::new(start, options.read_only),
            theme: &theme,
            mouse: options.mouse,
        };
        match runtime::run(interactive, tx, rx) {
            Ok(code) => code,
            Err(e) => {
                eprintln!("fleet-tui: {e}");
                1
            }
        }
    };
    // The workers end with the process; see `main`.
    std::mem::forget(source);
    code
}

fn make_source(
    options: &Options,
    settings: &mut Settings,
    tx: &std::sync::mpsc::SyncSender<runtime::Msg>,
) -> Source {
    #[cfg(feature = "fixtures")]
    if let Some(scenario) = options.fixture {
        settings.socket_label = "fixture, no socket".into();
        return Source::fixture(scenario);
    }
    let config = ControllerConfig {
        socket: options
            .socket
            .clone()
            .unwrap_or_else(|| ControllerConfig::default().socket),
        poll_interval: options.poll,
        read_only: options.read_only,
        max_log_bytes: TAIL_BYTES,
        ..ControllerConfig::default()
    };
    settings.socket_label = display_path(&config.socket);
    // `--once` samples telemetry every second so its second sample, the
    // first with CPU figures, arrives quickly.
    let telemetry_interval = if options.once {
        Duration::from_secs(1)
    } else {
        options.poll
    };
    Source::live(config, telemetry_interval, runtime::wake(tx))
}
