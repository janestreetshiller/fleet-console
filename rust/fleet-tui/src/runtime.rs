//! The full-screen event loop.
//!
//! One channel carries everything that can change the screen: terminal
//! events from an input thread blocked in `crossterm::event::read`, and wake
//! notes from the controller and telemetry workers. The loop blocks on that
//! channel. It wakes for input, for new data (the workers' generation
//! counters), for the log tail's next two-second read while the tail is open,
//! and for the moment a live feed would turn stale. There is no clock and no
//! periodic redraw.

use crate::app::{App, Command, Key, Pane};
use crate::source::{Settings, Source};
use crate::theme::Theme;
use crate::ui::{self, Geometry};
use fleet_ui_core::controller::{Action, ActionPayload, Wake};
use ratatui::backend::CrosstermBackend;
use ratatui::crossterm::event::{
    self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEvent, KeyEventKind,
    KeyModifiers, MouseButton, MouseEventKind,
};
use ratatui::crossterm::execute;
use ratatui::crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
};
use ratatui::layout::Position;
use ratatui::Terminal;
use std::io::{self, Stdout};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, SyncSender};
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime};

/// How often the open log tail asks for the end of the log.
pub const TAIL_INTERVAL: Duration = Duration::from_secs(2);
/// Upper bound on a blocking wait, so a missed wake cannot leave the screen
/// unchanged indefinitely.
const IDLE_CEILING: Duration = Duration::from_secs(60);

pub enum Msg {
    Event(Event),
    Line(String),
    Eof,
    InputError(String),
    Wake,
}

pub fn channel() -> (SyncSender<Msg>, Receiver<Msg>) {
    mpsc::sync_channel(256)
}

/// A wake note for the workers. A full channel already holds a pending
/// wake, so a failed send loses nothing.
pub fn wake(tx: &SyncSender<Msg>) -> Wake {
    let tx = tx.clone();
    Arc::new(move || {
        let _ = tx.try_send(Msg::Wake);
    })
}

/// Block until the controller has answered once and telemetry has two
/// samples (CPU needs two), or until `limit` passes.
pub fn wait_for_data(source: &Source, rx: &Receiver<Msg>, limit: Duration) {
    let deadline = Instant::now() + limit;
    while !(source.controller_answered() && source.has_telemetry_samples(2)) {
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return;
        }
        match rx.recv_timeout(left) {
            Ok(_) | Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => return,
        }
    }
}

pub fn spawn_stdin_lines(tx: SyncSender<Msg>) {
    std::thread::Builder::new()
        .name("fleet-tui-stdin".into())
        .spawn(move || {
            use std::io::BufRead;
            for line in io::stdin().lock().lines() {
                match line {
                    Ok(line) => {
                        if tx.send(Msg::Line(line)).is_err() {
                            return;
                        }
                    }
                    Err(_) => break,
                }
            }
            let _ = tx.send(Msg::Eof);
        })
        .expect("spawn stdin thread");
}

fn spawn_terminal_events(tx: SyncSender<Msg>) {
    std::thread::Builder::new()
        .name("fleet-tui-input".into())
        .spawn(move || loop {
            match event::read() {
                Ok(ev) => {
                    if tx.send(Msg::Event(ev)).is_err() {
                        return;
                    }
                }
                Err(e) => {
                    let _ = tx.send(Msg::InputError(e.to_string()));
                    return;
                }
            }
        })
        .expect("spawn input thread");
}

pub fn map_key(ev: KeyEvent) -> Option<Key> {
    if ev.kind == KeyEventKind::Release {
        return None;
    }
    if ev.modifiers.contains(KeyModifiers::CONTROL) {
        return match ev.code {
            KeyCode::Char('c') | KeyCode::Char('d') => Some(Key::Interrupt),
            _ => None,
        };
    }
    Some(match ev.code {
        KeyCode::Char(c) => Key::Char(c),
        KeyCode::Enter => Key::Enter,
        KeyCode::Esc => Key::Esc,
        KeyCode::Up => Key::Up,
        KeyCode::Down => Key::Down,
        KeyCode::PageUp => Key::PageUp,
        KeyCode::PageDown => Key::PageDown,
        KeyCode::Home => Key::Home,
        KeyCode::End => Key::End,
        KeyCode::Tab | KeyCode::BackTab => Key::Tab,
        KeyCode::Backspace => Key::Backspace,
        _ => return None,
    })
}

/// Raw mode, alternate screen and optional mouse capture, undone on drop and
/// on panic so a crash never leaves the terminal unusable.
struct TerminalGuard {
    mouse: bool,
}

fn restore(mouse: bool) {
    let mut out = io::stdout();
    if mouse {
        let _ = execute!(out, DisableMouseCapture);
    }
    let _ = execute!(out, LeaveAlternateScreen, ratatui::crossterm::cursor::Show);
    let _ = disable_raw_mode();
}

impl TerminalGuard {
    fn enter(mouse: bool) -> io::Result<Self> {
        let previous = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            restore(mouse);
            previous(info);
        }));
        enable_raw_mode()?;
        let mut out = io::stdout();
        execute!(out, EnterAlternateScreen, ratatui::crossterm::cursor::Hide)?;
        if mouse {
            execute!(out, EnableMouseCapture)?;
        }
        Ok(Self { mouse })
    }
}

impl Drop for TerminalGuard {
    fn drop(&mut self) {
        restore(self.mouse);
    }
}

/// Read or request the tail's log text. Returns whether anything changed and
/// when the next read is due, if one is.
pub fn service_tail(app: &mut App, source: &Source, now: Instant) -> (bool, Option<Instant>) {
    let Some(tail) = app.tail.as_mut() else {
        return (false, None);
    };
    let mut changed = false;
    if let Some(id) = tail.request {
        match source.outcome(id) {
            None => return (false, None),
            Some(outcome) => {
                tail.request = None;
                let current = matches!(&outcome.action,
                    Action::Logs { service_id, stream }
                        if *service_id == tail.service_id && *stream == tail.stream);
                if current {
                    tail.chunk = Some(match outcome.result {
                        Ok(ActionPayload::Logs(chunk)) => Ok(chunk),
                        Ok(_) => Err("the controller answered without log text".into()),
                        Err(e) => Err(e),
                    });
                    changed = true;
                } else {
                    // The stream switched while this read was in flight.
                    tail.last_sent = None;
                }
            }
        }
    }
    let due = tail.last_sent.map(|t| t + TAIL_INTERVAL).unwrap_or(now);
    if now < due {
        return (changed, Some(due));
    }
    match source.submit(Action::Logs {
        service_id: tail.service_id.clone(),
        stream: tail.stream,
    }) {
        Ok(id) => {
            tail.request = Some(id);
            tail.last_sent = Some(now);
            (true, None)
        }
        Err(e) => {
            tail.chunk = Some(Err(e));
            tail.last_sent = Some(now);
            (true, Some(now + TAIL_INTERVAL))
        }
    }
}

/// When a live feed would turn stale with no new data.
fn stale_deadline(source: &Source) -> Option<Instant> {
    let now_system = SystemTime::now();
    let now = Instant::now();
    source
        .freshness()
        .into_iter()
        .filter(|(_, _, live)| *live)
        .filter_map(|(received, stale_after, _)| {
            let at = received? + stale_after + Duration::from_millis(50);
            at.duration_since(now_system).ok().map(|left| now + left)
        })
        .min()
}

fn handle_mouse(
    app: &mut App,
    dash: &fleet_ui_core::Dashboard,
    geometry: &Geometry,
    kind: MouseEventKind,
    column: u16,
    row: u16,
) -> bool {
    if app.confirm.is_some() || app.help || app.editing_filter {
        return false;
    }
    match kind {
        MouseEventKind::Down(MouseButton::Left) => {
            if row == geometry.tabs_y {
                if let Some((_, _, view)) = geometry
                    .tabs
                    .iter()
                    .find(|(x0, x1, _)| column >= *x0 && column < *x1)
                {
                    app.switch(*view);
                    return true;
                }
                return false;
            }
            if let Some(list) = geometry.list {
                if list.view == app.view && list.rows.contains(Position::new(column, row)) {
                    let position = list.offset + usize::from(row - list.rows.y);
                    if position < app.visible(app.view, dash).len() {
                        app.click_row(dash, position);
                        return true;
                    }
                }
            }
            false
        }
        MouseEventKind::ScrollDown => {
            app.handle_key(Key::Down, dash);
            true
        }
        MouseEventKind::ScrollUp => {
            app.handle_key(Key::Up, dash);
            true
        }
        _ => false,
    }
}

pub struct Interactive<'a> {
    pub source: &'a Source,
    pub settings: &'a Settings,
    pub app: App,
    pub theme: &'a Theme,
    pub mouse: bool,
}

pub fn run(run: Interactive<'_>, tx: SyncSender<Msg>, rx: Receiver<Msg>) -> io::Result<i32> {
    let Interactive {
        source,
        settings,
        mut app,
        theme,
        mouse,
    } = run;
    let _guard = TerminalGuard::enter(mouse)?;
    let mut terminal: Terminal<CrosstermBackend<Stdout>> =
        Terminal::new(CrosstermBackend::new(io::stdout()))?;
    terminal.clear()?;
    spawn_terminal_events(tx);

    let mut dash = source.dashboard(&settings);
    app.sync(&dash);
    let mut drawn_generation = None;
    let mut redraw = true;
    let mut geometry = Geometry::default();
    let mut tail_due: Option<Instant> = None;

    loop {
        if redraw {
            dash = source.dashboard(&settings);
            app.sync(&dash);
            terminal.draw(|frame| {
                geometry = ui::draw(frame, &dash, &app, &theme);
            })?;
            if let Some(list) = geometry.list {
                app.offsets[list.view.index()] = list.offset;
            }
            drawn_generation = Some(source.generation());
            redraw = false;
        }

        let now = Instant::now();
        let deadline = [tail_due, stale_deadline(&source)]
            .into_iter()
            .flatten()
            .min()
            .unwrap_or(now + IDLE_CEILING);
        let message = rx.recv_timeout(deadline.saturating_duration_since(now));

        // Handle this message and anything else already queued before drawing.
        let mut pending = match message {
            Ok(m) => vec![m],
            Err(RecvTimeoutError::Timeout) => {
                redraw = true;
                Vec::new()
            }
            Err(RecvTimeoutError::Disconnected) => return Ok(0),
        };
        while let Ok(m) = rx.try_recv() {
            pending.push(m);
        }
        for message in pending {
            match message {
                Msg::Event(Event::Key(key)) => {
                    let Some(key) = map_key(key) else { continue };
                    let command = app.handle_key(key, &dash);
                    redraw = true;
                    match command {
                        Command::None => {}
                        Command::Quit => return Ok(0),
                        Command::Submit(action) => {
                            let result = source.submit(action.clone());
                            app.submitted(&action, result);
                        }
                        Command::TailChanged => {}
                    }
                }
                Msg::Event(Event::Mouse(m)) if mouse => {
                    redraw |= handle_mouse(&mut app, &dash, &geometry, m.kind, m.column, m.row);
                }
                Msg::Event(Event::Resize(_, _)) => {
                    terminal.autoresize()?;
                    redraw = true;
                }
                Msg::Event(_) => {}
                Msg::Wake => {
                    if Some(source.generation()) != drawn_generation {
                        redraw = true;
                    }
                }
                Msg::InputError(e) => {
                    return Err(io::Error::other(format!("terminal input failed: {e}")));
                }
                Msg::Line(_) | Msg::Eof => {}
            }
        }

        if app.pane == Pane::Tail {
            let (changed, due) = service_tail(&mut app, &source, Instant::now());
            redraw |= changed;
            tail_due = due;
        } else {
            tail_due = None;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::app::View;
    use fleet_ui_core::fixtures::Scenario;

    #[test]
    fn keys_map_from_terminal_events() {
        let key = |code, modifiers| KeyEvent::new(code, modifiers);
        assert_eq!(
            map_key(key(KeyCode::Char('c'), KeyModifiers::CONTROL)),
            Some(Key::Interrupt)
        );
        assert_eq!(
            map_key(key(KeyCode::Char('j'), KeyModifiers::NONE)),
            Some(Key::Char('j'))
        );
        assert_eq!(map_key(key(KeyCode::BackTab, KeyModifiers::SHIFT)), Some(Key::Tab));
        assert_eq!(map_key(key(KeyCode::F(5), KeyModifiers::NONE)), None);
    }

    #[test]
    fn fixture_tail_reports_the_refusal_and_schedules_the_next_read() {
        let source = Source::fixture(Scenario::Healthy);
        let dash = source.dashboard(&crate::source::tests::settings(false));
        let mut app = App::new(View::Services, false);
        app.sync(&dash);
        assert_eq!(app.handle_key(Key::Char('t'), &dash), Command::TailChanged);
        let now = Instant::now();
        let (changed, due) = service_tail(&mut app, &source, now);
        assert!(changed);
        assert_eq!(due, Some(now + TAIL_INTERVAL));
        match &app.tail.as_ref().unwrap().chunk {
            Some(Err(e)) => assert_eq!(e, crate::source::FIXTURE_REFUSAL),
            other => panic!("expected refusal, got {other:?}"),
        }
        // Not due yet: nothing is sent.
        let (changed, due) = service_tail(&mut app, &source, now + Duration::from_millis(500));
        assert!(!changed);
        assert_eq!(due, Some(now + TAIL_INTERVAL));
    }
}
