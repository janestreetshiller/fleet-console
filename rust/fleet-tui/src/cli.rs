//! Command-line options. The flag names match the GPUI client's so the two
//! can be started the same way.

use crate::app::View;
use std::path::PathBuf;
use std::time::Duration;

#[derive(Debug, Clone, PartialEq)]
pub struct Options {
    pub socket: Option<PathBuf>,
    pub read_only: bool,
    pub remote_controller: bool,
    pub poll: Duration,
    pub no_color: bool,
    pub mouse: bool,
    pub plain: bool,
    pub once: bool,
    /// The view to open on, or every view with `--once`.
    pub view: StartView,
    #[cfg(feature = "fixtures")]
    pub fixture: Option<fleet_ui_core::fixtures::Scenario>,
    #[cfg(feature = "fixtures")]
    pub capture: Option<PathBuf>,
    #[cfg(feature = "fixtures")]
    pub size: Option<(u16, u16)>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StartView {
    One(View),
    /// Every view in order; only meaningful with `--once`.
    All,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            socket: None,
            read_only: false,
            remote_controller: false,
            poll: Duration::from_secs(2),
            no_color: false,
            mouse: false,
            plain: false,
            once: false,
            view: StartView::One(View::Overview),
            #[cfg(feature = "fixtures")]
            fixture: None,
            #[cfg(feature = "fixtures")]
            capture: None,
            #[cfg(feature = "fixtures")]
            size: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Parsed {
    Run(Box<Options>),
    Help,
    Version,
}

pub fn usage() -> String {
    let mut text = String::from(
        "fleet-tui: terminal client for the FleetConsole controller\n\
         \n\
         Usage: fleet-tui [options]\n\
         \n\
         Options:\n\
         \x20 --socket <path>       controller socket (default: FLEETCONSOLE_SOCKET, then the platform path)\n\
         \x20 --read-only           refuse every mutating action in this client\n\
         \x20 --remote-controller   treat the controller as running on another machine\n\
         \x20 --poll <seconds>      controller and telemetry interval, 1 to 60 (default 2)\n\
         \x20 --no-color            no color; meaning stays in words, bold and reverse video\n\
         \x20 --mouse               click tabs and rows, scroll lists\n\
         \x20 --plain               line mode for screen readers: no alternate screen, no box drawing\n\
         \x20 --once                print one rendering and exit\n\
         \x20 --view <name|1-6>     view to open on; with --once, \"all\" prints every view\n\
         \x20 --version             print the version\n\
         \x20 --help                print this help\n",
    );
    #[cfg(feature = "fixtures")]
    text.push_str(
        "\nFixture build only:\n\
         \x20 --fixture <scenario>  synthetic data: loading, healthy, warning, critical, stale,\n\
         \x20                       disconnected, error, flood; no controller, actions refused\n\
         \x20 --capture <dir>       write every view of the fixture as text files and exit\n\
         \x20 --size <cols>x<rows>  capture size (default 120x40)\n",
    );
    text.push_str(
        "\nEnvironment: NO_COLOR disables color; COLORTERM=truecolor or 24bit selects 24-bit color;\n\
         TERM with 256color selects the 256-color palette; TERM=dumb disables color.\n",
    );
    text
}

fn value<'a>(flag: &str, args: &mut impl Iterator<Item = &'a str>) -> Result<&'a str, String> {
    args.next()
        .filter(|v| !v.is_empty())
        .ok_or_else(|| format!("{flag} needs a value"))
}

pub fn parse_view(text: &str) -> Option<StartView> {
    if text == "all" {
        return Some(StartView::All);
    }
    if let Some(view) = text
        .parse::<usize>()
        .ok()
        .and_then(|n| n.checked_sub(1))
        .and_then(|i| View::ALL.get(i).copied())
    {
        return Some(StartView::One(view));
    }
    View::ALL
        .into_iter()
        .find(|v| v.name() == text.to_ascii_lowercase())
        .map(StartView::One)
}

pub fn parse<'a>(args: impl IntoIterator<Item = &'a str>) -> Result<Parsed, String> {
    let mut options = Options::default();
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
            "--help" | "-h" => return Ok(Parsed::Help),
            "--version" | "-V" => return Ok(Parsed::Version),
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
            "--no-color" => options.no_color = true,
            "--mouse" => options.mouse = true,
            "--plain" => options.plain = true,
            "--once" => options.once = true,
            "--view" => {
                let text = take("--view")?;
                options.view = parse_view(text).ok_or_else(|| {
                    format!("--view {text}: expected 1-6, all, or one of overview, processes, services, agents, storage, attention")
                })?;
            }
            #[cfg(feature = "fixtures")]
            "--fixture" => {
                let text = take("--fixture")?;
                options.fixture = Some(
                    fleet_ui_core::fixtures::Scenario::parse(text)
                        .ok_or_else(|| format!("--fixture {text}: unknown scenario"))?,
                );
            }
            #[cfg(feature = "fixtures")]
            "--capture" => options.capture = Some(PathBuf::from(take("--capture")?)),
            #[cfg(feature = "fixtures")]
            "--size" => {
                let text = take("--size")?;
                options.size = Some(parse_size(text)?);
            }
            other => return Err(format!("unknown option {other}; see --help")),
        }
    }
    if options.view == StartView::All && !options.once {
        return Err("--view all needs --once".into());
    }
    #[cfg(feature = "fixtures")]
    if options.capture.is_some() && options.fixture.is_none() {
        return Err("--capture needs --fixture".into());
    }
    #[cfg(feature = "fixtures")]
    if options.fixture.is_some() && options.socket.is_some() {
        return Err("--fixture and --socket are exclusive: fixture mode has no controller".into());
    }
    Ok(Parsed::Run(Box::new(options)))
}

#[cfg(feature = "fixtures")]
pub fn parse_size(text: &str) -> Result<(u16, u16), String> {
    let (c, r) = text
        .split_once('x')
        .ok_or_else(|| format!("--size {text}: expected <cols>x<rows>"))?;
    let cols: u16 = c
        .parse()
        .map_err(|_| format!("--size {text}: expected <cols>x<rows>"))?;
    let rows: u16 = r
        .parse()
        .map_err(|_| format!("--size {text}: expected <cols>x<rows>"))?;
    if !(20..=500).contains(&cols) || !(5..=300).contains(&rows) {
        return Err(format!("--size {text}: columns 20 to 500, rows 5 to 300"));
    }
    Ok((cols, rows))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(args: &[&str]) -> Options {
        match parse(args.iter().copied()).unwrap() {
            Parsed::Run(o) => *o,
            other => panic!("expected options, got {other:?}"),
        }
    }

    #[test]
    fn flags_parse() {
        let o = run(&[
            "--socket",
            "/x/fleetd.sock",
            "--read-only",
            "--remote-controller",
            "--poll=5",
            "--no-color",
            "--mouse",
            "--plain",
            "--once",
            "--view",
            "3",
        ]);
        assert_eq!(o.socket.as_deref(), Some(std::path::Path::new("/x/fleetd.sock")));
        assert!(o.read_only && o.remote_controller && o.no_color && o.mouse && o.plain && o.once);
        assert_eq!(o.poll, Duration::from_secs(5));
        assert_eq!(o.view, StartView::One(View::Services));
        assert_eq!(run(&["--view", "agents"]).view, StartView::One(View::Agents));
    }

    #[test]
    fn bad_input_is_reported() {
        assert!(parse(["--poll", "0"]).is_err());
        assert!(parse(["--poll", "abc"]).is_err());
        assert!(parse(["--socket"]).is_err());
        assert!(parse(["--bogus"]).is_err());
        assert!(parse(["--view", "all"]).is_err(), "all needs --once");
        assert_eq!(parse(["--help"]), Ok(Parsed::Help));
        assert_eq!(parse(["--version"]), Ok(Parsed::Version));
    }

    #[cfg(not(feature = "fixtures"))]
    #[test]
    fn fixture_flags_do_not_exist_in_default_builds() {
        assert!(parse(["--fixture", "healthy"]).is_err());
        assert!(parse(["--capture", "/tmp"]).is_err());
        assert!(!usage().contains("--fixture"));
    }
}
