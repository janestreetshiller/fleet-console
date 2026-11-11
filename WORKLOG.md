# FleetConsole current source handoff

## Terminal persistence — 2026-11-11

- Issue #9: the shell previously belonged to the window's PTY and was killed
  on window close; changing context also restarted it. Fleet now attaches its
  Shell to a separate `fleet-console` tmux server, and detaches the client
  when the window closes or the app quits. The existing server session is
  reattached when the shell opens again. tmux is required and its absence is
  shown in the panel. Dedicated agent sessions retain their existing
  stop-on-close ownership and are not restored.
- Persistence is limited to the lifetime of the tmux server; logout, reboot,
  ending the shell, or `tmux -L fleet-console kill-server` can end the work.
  The initial context selects the directory for a new session; switching
  selection does not change the directory of an existing shell.
- `swift build --jobs 2` passed. An independent real-PTY tmux exercise
  terminated the attached client, reattached a new client and observed both
  an exported shell variable and completion of a background job. This proves
  the multiplexer lifecycle, not the Fleet UI integration.
- Native acceptance is not yet proven: the first targeted test reached the
  test body but failed while the SwiftUI host was not yet available; the test
  now waits for the host. A subsequent targeted run timed out while sampled in
  `NSApplication.shared` → SkyLight `SLSCopyDisplayUUID` → `mach_msg`.
  `launchctl asuser 502` was denied; a temporary service in the logged-in
  Aqua domain also failed to return the targeted test result within 150s and
  was removed. Rerun `swift test --filter
  'TerminalAgentSessionTests/durableShell'` in a responsive GUI session before
  closing issue #9.
- Release integration: local `main` started at `ed9ba3d` and origin/main at
  `31db7f6`. The local root `2f4beaa` was a recovered snapshot with no parent.
  Integration temporarily used the last upstream commit before that recovery,
  `129c474`, as the three-way base, then merged origin/main with both real
  histories retained. The temporary replacement is removed after the merge.
  No installed app or controller is replaced.
- After integrating, `swift test --jobs 2 --filter
  'ConsoleNavigationTests|AwarenessGraphTests|DirectoryCrystalTests'` built the
  merged targets and passed 24 tests in three suites.
- The post-merge `durableShell` GUI test timed out after 100 seconds without a
  result. Do not close issue #9 until it passes in a responsive GUI session.
- Do not push this merge as-is: preserving the recovered history would
  publish historical maintainer identifiers removed in `4c7b81a` (six home
  and six host matches in the removed lines). The existing source scanner
  checks current files, not history, and the public-source exporter explicitly
  excludes private Git history. Publication requires an approved history-safe
  release approach, not a force-push.

## Optimized local GPUI companion — 2026-11-10

- Source revision `ea42e85af6ec9bd19fd34391d8b9b72ecfa89a2c`;
  integration documentation commit `4ad105d9a5aa244421d5ae79de0d5a667390d09e`
  changes no Rust source or lockfile. Both builds used Rust 1.98.0 and
  `cargo build --manifest-path rust/Cargo.toml --locked --release -p fleet-gpui`.
- macOS 27.3 arm64: local launcher
  `dist/gpui-ea42e85/Fleet GPUI.app` (open in Finder or with
  `open 'dist/gpui-ea42e85/Fleet GPUI.app'`). Its executable SHA256 is
  `2bde96540b362eafaef6001f5b6fef37fe65e1906ca395e4377b2bbe0f5f0b23`.
  `lipo -archs` reported arm64; `--identity` reported 0.1.0 and fixtures
  disabled. `--verify --read-only --socket /tmp/fleet-gpui-release-ea42e85-nonexistent.sock`
  reported disconnected and two measured local telemetry samples. Launching
  the app with those same read-only/socket arguments produced an on-screen
  FleetConsole window (CoreGraphics, 1156×796); input was not tested.
- Omarchy x86_64: exported that exact committed source using `git archive`,
  built it at `/home/algorithm/ouros-project/workspaces/.release-builds/fleet-console-ea42e85`
  with `CARGO_TARGET_DIR` set to the previous export's `rust/target`, then
  copied the release binary to
  `/home/algorithm/.local/share/fleet-gpui/releases/ea42e85/fleet-gpui`.
  Its SHA256 is
  `3b616057051c93b7bd7858d433fd381be45db665f0e9e98f9e82fe849531685e`.
  `file` reported x86-64 ELF; `--identity` reported 0.1.0 and fixtures
  disabled. The same disconnected read-only `--verify` invocation reported
  two local telemetry samples. A `systemd-run --user --collect` launch with
  `--theme phosphor` and the same read-only/socket options produced a mapped,
  visible, input-accepting native Wayland client (Hyprland, 737×958); input
  and visual contents were not tested.
- Linux app menu entry: `~/.local/share/applications/fleet-gpui-ea42e85.desktop`
  launches the local binary with phosphor theme. The macOS bundle and Linux
  entry are separate from installed applications and controllers. These are
  local artifacts, not Developer ID signed, notarized, or publicly distributed;
  Linux dynamic-library compatibility beyond this host has not been tested.
  Neither live controller actions nor full app feature parity were verified.

## Retro GPUI companion — 2026-11-10

- The phosphor design and GPUI companion were already present on main; the
  surviving Claude session records an unfinished worker, not a recoverable
  final worker commit. This is a companion, not a replacement for the Swift
  application or controller.
- Integration commit `101c8c4` pins libc 0.2.189 to repair a Linux build
  failure in GPUI's transitive `xattr` 0.2.3, and documents the existing
  `--theme phosphor` entry point and its limitations.
- macOS arm64: locked debug build, `--identity`, disconnected read-only
  `--verify`, and an actual phosphor dashboard window with local telemetry
  observed. Binary SHA256
  `21bd5f56a1e4f7ad9c00653f1ff0566a1f275e287da1bb190e5f99cf4eb15704`.
- Linux x86_64: locked debug build from the `7f880f0` source export with the
  identical lockfile from `101c8c4`; `--identity`, disconnected read-only
  `--verify`, and a real Wayland phosphor dashboard window observed. Binary
  SHA256 `fedf39597ab4946833aa5553ae7067ae759aeb5c3bbe7cd890bd3e9abe23113e`.
- No signed package, download, installation, native Windows/mobile build,
  Linux controller, live controller actions, or accessibility-tree support
  is claimed. Linux uses local telemetry without a controller or an SSH
  bridge to a Mac controller; the client does not publish a Linux tray item.

## Source privacy and design-core handoff

- Intended branch: main. Design/privacy implementation commit: 4c7b81afcce9045de77cf2d10e25976e4d2ea197.
- Integrated the existing installed-source branch through 0f5628ceda11d4421e0abf862a7b94e51b79f7ca by fast-forward; its dynamic core-identity test and ignored release-artifact policy are now on main.
- Fixed the genuine source-privacy failure upstream: six native consumer ownership labels now identify repositories instead of private workstations. The privacy scanner and all its refusal rules are unchanged.
- Canonical design-core implementation is e029444fd5771bcdac7309de029eeac815436ecc on the application's main branch. Fleet consumes the generated self-contained 1.1.13 capsule, SHA256 8a9900dbbfe1d771b173ee7457d028136640336ff040a96ba0878d2e6f9d1ac1.
- All six Fleet runtime templates are byte-identical; runtime token values are unchanged. Capsule import verified every archive path, source identity and existing-source preimage.
- Executed: source privacy 10 tests passed; capsule generator check passed (7 exports); Swift token parse passed; git diff check passed. Canonical core regression demonstrated six failures before the repair, then all 4 core tests and hosted checker passed; final application main passed 19 product/source-integration tests.
- Current Loop source metadata was rebound only after proving its CSS, brand and existing JS/CSS artifact bytes identical; no artifact rebuild or historical acceptance rewrite is claimed.
- Evidence and exact helper outputs: artifacts/source-privacy-20261110/.
- No installed app replacement, controller restart, signing, public push/deploy, paid request or guard change occurred. Installed-output memory admission and paid/device acceptance remain separate open requirements.
