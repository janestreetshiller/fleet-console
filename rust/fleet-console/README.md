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
- Launch: no main window. The app lives in the macOS menubar / Linux
  system tray and stays resident with zero windows open.
- Shell: three meter columns (CPU / RAM / DISK) with live local
  readings; a click toggles a small popover that says the controller is
  not connected yet and shows the same readings; a Quit item in the
  popover, in the tray menu (Linux) / right-click menu (macOS), and on
  Cmd-Q / Ctrl-Q.
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
