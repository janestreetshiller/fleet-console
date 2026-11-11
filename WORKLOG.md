# FleetConsole current source handoff

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
