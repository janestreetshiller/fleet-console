//! Command-line options. Flag names match the terminal client's (`fleet-tui`)
//! so both clients start the same way.

use crate::palette::DarkTheme;
use crate::state::View;
use std::path::PathBuf;
use std::time::Duration;

#[derive(Debug, Clone, PartialEq)]
pub struct Options {
    pub socket: Option<PathBuf>,
    pub read_only: bool,
    pub remote_controller: bool,
    /// Controller poll and telemetry sample interval, 1 to 60 seconds.
    pub poll: Duration,
    /// Open the compact quick view instead of the full window.
    pub quick: bool,
    /// The full window's first view.
    pub view: View,
    /// The dark palette: fog glass, or the terminal phosphor green.
    pub theme: DarkTheme,
    /// Size of the first window, in points.
    pub window_size: Option<(f32, f32)>,
    #[cfg(feature = "fixtures")]
    pub fixture: Option<fleet_ui_core::fixtures::Scenario>,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            socket: None,
            read_only: false,
            remote_controller: false,
            poll: Duration::from_secs(2),
            quick: false,
            view: View::Overview,
            theme: DarkTheme::Fog,
            window_size: None,
            #[cfg(feature = "fixtures")]
            fixture: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Command {
    Run(Box<Options>),
    /// Static identity JSON; reads nothing.
    Identity,
    /// One controller read and one telemetry sample, reported as JSON.
    Verify(Box<Options>),
    Help,
    Version,
}

pub fn usage() -> String {
    let mut text = String::from(
        "fleet-gpui: desktop client for the FleetConsole controller\n\
         \n\
         Usage: fleet-gpui [options]\n\
         \n\
         Options:\n\
         \x20 --socket <path>         controller socket (default: FLEETCONSOLE_SOCKET, then the platform path)\n\
         \x20 --read-only             refuse every mutating action in this client\n\
         \x20 --remote-controller     treat the controller as running on another machine\n\
         \x20 --poll <seconds>        controller and telemetry interval, 1 to 60 (default 2)\n\
         \x20 --quick                 open the compact quick view instead of the full window\n\
         \x20 --view <1-7|name>       first view of the full window: overview, processes, services,\n\
         \x20                         agents, storage, attention, map\n\
         \x20 --theme <theme>         dark palette of the window: fog (glass, default) or phosphor\n\
         \x20 --window-size <w>x<h>   size of the first window in points, for example 1180x780\n\
         \x20 --identity              print static identity JSON and exit\n\
         \x20 --verify                read the controller once and sample telemetry, print JSON, exit\n\
         \x20 --version               print the version\n\
         \x20 --help                  print this help\n",
    );
    #[cfg(feature = "fixtures")]
    text.push_str(
        "\nFixture build only:\n\
         \x20 --fixture <scenario>    synthetic data: loading, healthy, warning, critical, stale,\n\
         \x20                         disconnected, error, flood; no controller, actions refused\n",
    );
    text.push_str(
        "\nKeys: 1-7 views, j/k or arrows move, enter inspect, r restart, s stop, n renew,\n\
         t logs, y/n answer the selected question, esc close, cmd-q or ctrl-q quit.\n",
    );
    text
}

fn value<'a>(flag: &str, args: &mut impl Iterator<Item = &'a str>) -> Result<&'a str, String> {
    args.next()
        .filter(|v| !v.is_empty())
        .ok_or_else(|| format!("{flag} needs a value"))
}

pub fn parse_window_size(text: &str) -> Result<(f32, f32), String> {
    let error = || format!("--window-size {text}: expected <width>x<height>, each 200 to 10000");
    let (w, h) = text.split_once('x').ok_or_else(error)?;
    let w: u32 = w.trim().parse().map_err(|_| error())?;
    let h: u32 = h.trim().parse().map_err(|_| error())?;
    if !(200..=10_000).contains(&w) || !(200..=10_000).contains(&h) {
        return Err(error());
    }
    Ok((w as f32, h as f32))
}

pub fn parse<'a>(args: impl IntoIterator<Item = &'a str>) -> Result<Command, String> {
    let mut options = Options::default();
    let mut identity = false;
    let mut verify = false;
    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        // `--flag=value` is accepted as well as `--flag value`.
        let (flag, inline) = match arg.split_once('=') {
            Some((f, v)) if f.starts_with("--") => (f, Some(v)),
            _ => (arg, None),
        };
        let mut take = |name: &str| -> Result<&'a str, String> {
            match inline {
                Some(v) if !v.is_empty() => Ok(v),
                Some(_) => Err(format!("{name} needs a value")),
                None => value(name, &mut args),
            }
        };
        match flag {
            "--help" | "-h" => return Ok(Command::Help),
            "--version" | "-V" => return Ok(Command::Version),
            "--identity" => identity = true,
            "--verify" => verify = true,
            "--socket" => options.socket = Some(PathBuf::from(take("--socket")?)),
            "--read-only" => options.read_only = true,
            "--remote-controller" => options.remote_controller = true,
            "--poll" => {
                let text = take("--poll")?;
                let seconds: f64 = text
                    .parse()
                    .map_err(|_| format!("--poll {text}: expected seconds, 1 to 60"))?;
                if !(1.0..=60.0).contains(&seconds) {
                    return Err(format!("--poll {text}: expected seconds, 1 to 60"));
                }
                options.poll = Duration::from_secs_f64(seconds);
            }
            "--quick" => options.quick = true,
            "--theme" => {
                let text = take("--theme")?;
                options.theme = DarkTheme::parse_text(text).ok_or_else(|| {
                    format!("--theme {text}: expected fog or phosphor")
                })?;
            }
            "--view" => {
                let text = take("--view")?;
                options.view = View::parse(text).ok_or_else(|| {
                    format!("--view {text}: expected 1-7 or one of overview, processes, services, agents, storage, attention, map")
                })?;
            }
            "--window-size" => options.window_size = Some(parse_window_size(take("--window-size")?)?),
            #[cfg(feature = "fixtures")]
            "--fixture" => {
                let text = take("--fixture")?;
                options.fixture = Some(
                    fleet_ui_core::fixtures::Scenario::parse(text)
                        .ok_or_else(|| format!("--fixture {text}: unknown scenario"))?,
                );
            }
            #[cfg(not(feature = "fixtures"))]
            "--fixture" => {
                return Err(
                    "--fixture is available only in builds with the fixtures feature".into(),
                )
            }
            other => return Err(format!("unknown option {other}; see --help")),
        }
    }
    #[cfg(feature = "fixtures")]
    if options.fixture.is_some() {
        if options.socket.is_some() {
            return Err("--fixture and --socket are exclusive: fixture mode has no controller".into());
        }
        if verify {
            return Err("--verify reads the real controller and telemetry; it does not take --fixture".into());
        }
    }
    if identity {
        return Ok(Command::Identity);
    }
    if verify {
        return Ok(Command::Verify(Box::new(options)));
    }
    Ok(Command::Run(Box::new(options)))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(args: &[&str]) -> Options {
        match parse(args.iter().copied()).unwrap() {
            Command::Run(options) => *options,
            other => panic!("expected run, got {other:?}"),
        }
    }

    #[test]
    fn defaults_open_the_full_window_on_overview() {
        let options = run(&[]);
        assert_eq!(options, Options::default());
        assert!(!options.quick);
        assert_eq!(options.view, View::Overview);
        assert_eq!(options.poll, Duration::from_secs(2));
    }

    #[test]
    fn flags_and_values_parse_in_both_spellings() {
        let options = run(&[
            "--socket",
            "/tmp/x.sock",
            "--read-only",
            "--remote-controller",
            "--poll=5",
            "--quick",
            "--view",
            "4",
            "--window-size=900x600",
        ]);
        assert_eq!(options.socket, Some(PathBuf::from("/tmp/x.sock")));
        assert!(options.read_only && options.remote_controller && options.quick);
        assert_eq!(options.poll, Duration::from_secs(5));
        assert_eq!(options.view, View::Agents);
        assert_eq!(options.window_size, Some((900.0, 600.0)));
        assert_eq!(run(&["--view=storage"]).view, View::Storage);
        assert_eq!(run(&["--view", "7"]).view, View::Map);
        assert_eq!(run(&["--view=map"]).view, View::Map);
        assert_eq!(run(&["--theme=phosphor"]).theme, DarkTheme::Phosphor);
        assert_eq!(run(&[]).theme, DarkTheme::Fog);
    }

    #[test]
    fn bad_values_are_errors_not_defaults() {
        for args in [
            &["--poll", "0.5"][..],
            &["--poll", "61"],
            &["--poll", "fast"],
            &["--view", "0"],
            &["--view", "8"],
            &["--view", "terminal"],
            &["--theme", "aqua"],
            &["--theme"],
            &["--window-size", "100x100"],
            &["--window-size", "wide"],
            &["--socket"],
            &["--bogus"],
        ] {
            assert!(parse(args.iter().copied()).is_err(), "{args:?} should fail");
        }
    }

    #[test]
    fn identity_and_verify_are_commands() {
        assert_eq!(parse(["--identity"]).unwrap(), Command::Identity);
        match parse(["--verify", "--socket", "/nonexistent.sock"]).unwrap() {
            Command::Verify(options) => {
                assert_eq!(options.socket, Some(PathBuf::from("/nonexistent.sock")))
            }
            other => panic!("expected verify, got {other:?}"),
        }
        assert_eq!(parse(["--help"]).unwrap(), Command::Help);
    }

    #[cfg(not(feature = "fixtures"))]
    #[test]
    fn fixture_flag_is_refused_without_the_feature() {
        let error = parse(["--fixture", "healthy"]).unwrap_err();
        assert!(error.contains("fixtures feature"), "{error}");
        assert!(!usage().contains("--fixture"));
    }

    #[cfg(feature = "fixtures")]
    #[test]
    fn fixture_flag_parses_known_scenarios() {
        use fleet_ui_core::fixtures::Scenario;
        assert_eq!(
            run(&["--fixture", "disconnected"]).fixture,
            Some(Scenario::Disconnected)
        );
        assert!(parse(["--fixture", "imaginary"]).is_err());
        assert!(parse(["--fixture", "healthy", "--socket", "/x"]).is_err());
        assert!(parse(["--fixture", "healthy", "--verify"]).is_err());
    }
}
