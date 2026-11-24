# FleetConsole — production GPUI app (scaffold)

The production rebuild of FleetConsole 1.3.0 in GPUI (Rust), per the parity
list in the repo `WORKLOG.md`. It lives beside the experimental companion in
`rust/fleet-gpui`, which stays untouched as a development client: that crate
opens a main window at launch, shows no meters in its macOS status item, and
has no Linux tray, so it was not a clean base for the menubar-first
production shell.

What exists in this scaffold:

- Identity: bundle id `com.fleetconsole.app`, name/executable
  `FleetConsole`, version 1.3.0. macOS bundle assembled by
  `scripts/build-macos-app.sh` from `macos/Info.plist` (`LSUIElement true`).
- Launch: no main window. The app lives in the macOS menubar / Linux
  system tray and stays resident with zero windows open.
- Shell: three meter columns (CPU / RAM / DISK) with `—` placeholder
  readings; a click toggles a small popover that says the controller is
  not connected yet; a Quit item in the popover, in the tray menu
  (Linux) / right-click menu (macOS), and on Cmd-Q / Ctrl-Q.
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
