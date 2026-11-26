# FleetConsole — production GPUI app (scaffold)

The production rebuild of FleetConsole 1.3.0 in GPUI (Rust), per the parity
list in the repo `WORKLOG.md`. It replaces the two experimental front ends that never shipped — the
`fleet-gpui` desktop client and the `fleet-tui` terminal client — both removed
with their shared `fleet-ui-core` view models when the ecosystem standardised
on one GPUI app per product (owner decision, 2026-11-24). This crate is that
app for FleetConsole; the Swift 1.3.0 build stays the download until parity.

What exists in this scaffold:

- Identity: bundle id `com.fleetconsole.app`, name/executable
  `FleetConsole`, version 1.3.0. macOS bundle assembled by
  `scripts/build-macos-app.sh` from `macos/Info.plist` (`LSUIElement true`).
- Launch: the app lives in the macOS menubar / Linux system tray
  and stays resident with zero windows open.
- A second packaged macOS launch activates the existing app. An explicit
  dashboard request goes to that instance before the second process opens
  configuration or connects to fleetd. `--review` opens Overview; a
  Boolean `FleetConsoleReviewBuild` plist flag also enables a Dock icon.
- The packaged macOS app shows Welcome on first launch unless skipped.
  Replay Welcome is in the status-item menu. After notification permission
  is granted, only fresh unseen problems and requests awaiting an answer
  produce audible system notifications; the initial mailbox is silent.
  Review launches and isolated state roots skip automatic onboarding.
- Shell: three meter columns (CPU / RAM / DISK) with live local
  readings; a click toggles the 480pt popover, which shows the fleet
  status line, the Quick View instrument strip (CPU and Memory retro
  gauges, Disk cell grid, Network rate bars), a Dashboard button, and
  Quit; a Quit item also sits in the tray menu (Linux) / right-click
  menu (macOS), and on Cmd-Q / Ctrl-Q.
- Dashboard (`src/dashboard.rs`): a window with the six Swift modules
  in order — Overview (Agent awareness), Processes, Storage, Services
  (Operations), Events, Launch Services (Plists) — opened with ⌘0 or
  the popover's Dashboard button and switched with ⌘1 to ⌘6 or the
  View menu. Overview, Services, and Events render the controller
  snapshot; Processes shows the top local processes from a configurable
  sampler (4 seconds by default); Storage lists mounted disks; Launch Services
  reads `launchctl list` (macOS) or `systemctl --user` (Linux).
- Overview's native **Agent awareness map** separates recorded owners,
  registered services, verified process group leaders, observed group
  listeners, and unlinked detected sessions. Drag empty space to pan,
  use the zoom controls or **Fit all**, and select a card to inspect its
  evidence and follow recorded relationships. The map limits displayed
  cards on large snapshots; Services, Processes, and Events remain
  reachable from Overview diagnostics.
- Map lines show registry ownership, verified leaders, or observed group
  listeners—not session ownership, connections, or dependencies. A
  leader requires fleetd to match the recorded PID, process group, and
  start signature; a recorded PID or group liveness alone is not enough.
  Overview labels retained snapshots when live evidence is unavailable.
  Live evidence expires after three controller ticks, measured from each
  observation.
- Configuration: **Edit Configuration** opens the installed `config.json`
  in an editor; **Reveal Logs** opens the installed log folder. On macOS
  these are under `~/Library/Application Support/FleetConsole` and
  `~/Library/Logs/FleetConsole` respectively. `FLEETCONSOLE_STATE_ROOT`
  replaces `~` and preserves the same `Library` paths. Changes, atomic
  replacements, and deletion are
  picked up live without restarting the controller. A missing file
  uses defaults; a file that cannot be read or parsed also uses
  defaults and shows the error in Quick View and Dashboard.
  `ui.sections.agents`, `ui.sections.processes`, and `ui.sections.services`
  control their existing menu entries, not Dashboard navigation.
  `ui.intervals.processSampleSec` sets the live process sampler cadence
  (minimum 2 seconds). Other section keys and `networkRefreshSec`
  do not yet have corresponding GPUI destinations or probes.
- Controller connection (`src/controller.rs`, `src/snapshot.rs`): a
  thread subscribes to fleetd over the owner-only Unix socket and
  streams snapshots in, reconnecting with the Swift backoff (0.5s
  doubling to a 5s cap). The menubar title appends the Swift alert text
  (`Offline`, or `!N` for awaiting replies or attention) tinted red or
  orange, the tooltip carries the counts line, agent profile lines,
  next-lease line, and daemon uptime, and opening the popover sends
  markSeen and refreshDevices, all derived with the Swift rules.
- Local sampling (`src/sampler.rs`): a sampler thread reads this
  machine every 2 seconds and feeds the menubar status item (macOS),
  the tray title/menu/tooltip text (Linux), and the popover meter row.
  Until the first sample lands, and for any single reading a platform
  cannot produce, that meter shows `—`. Percents are rounded integers,
  matching the Swift format `Int((share * 100).rounded())`. Definitions
  copy the Swift build (`Sources/FleetConsoleApp/Probes/SystemMetrics.swift`,
  menubar wiring in `AppModel.fleetMeters`): CPU is total busy share
  from processor-tick deltas (user + system + nice over all ticks,
  i.e. 1 minus idle share; the first tick read only primes the delta,
  exactly as in Swift); RAM on macOS is
  (app + wired + compressed) / total physical memory from
  `host_statistics64`, where app is active + inactive + speculative
  minus (external + purgeable), clamped to the total; RAM elsewhere is
  sysinfo used / total (Linux: MemTotal minus MemAvailable over
  MemTotal); DISK is (total - available) / total for the volume mounted
  at `/`, the root/startup volume. CPU and the non-macOS readings come
  from the sysinfo crate, already a workspace dependency.
- `--popover` opens the popover at launch (verification aid);
  `--identity` and `--version` print and exit.

Platform bridges, kept as small as the platforms allow:

- macOS (`src/main.rs`, `mod mac_status`): GPUI 0.2 has no status-item API
  and hardcodes the Regular activation policy, so a small Objective-C
  bridge installs the `NSStatusItem` (autosave name
  `com.fleetconsole.item.fleet`) and sets the Accessory policy.
- Linux (`mod linux_tray`): GPUI 0.2 has no tray at all, so the crate
  publishes a StatusNotifierItem with ksni — pure Rust over the session
  D-Bus, blocking API on its own thread, clicks forwarded on a channel.

Build:

- macOS: `scripts/build-macos-app.sh` (builds and assembles the .app).
- Linux: `cargo build --release -p fleet-console` in `rust/`, then run
  `target/release/FleetConsole` inside the desktop session.

Run `Scripts/verify-rust-clients.sh` from the repository root for the
FleetConsole binary tests, controller protocol tests, and source identity check.
