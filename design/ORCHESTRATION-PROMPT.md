# Orchestration prompt: Fleet Console TUI and GPUI, macOS and Linux

Paste everything below the line into the orchestrating agent as one context dump.

---

You are the orchestrator for building two new Fleet Console clients, a terminal UI (TUI) and a GPUI desktop app, that run on both macOS and Linux and share one data and view-model layer. The shipping native macOS app (SwiftUI menu-bar popover) stays working throughout; it is the behavioral and visual reference, not something to replace or break.

## 0. Read first, before any edit

1. The owner's workspace instructions (host-level `AGENTS.md` files the owner names for this task). Re-read after compaction or owner corrections. Pass these paths to every worker and require the same read.
2. The owning repository is `janestreetshiller/fleet-console` (clone into a fresh worktree; never build over a running installed bundle). Read its `AGENTS.md`, `CONTRIBUTING.md`, `README.md`, `docs/RUST-PORT.md`, `docs/THREAT-MODEL.md`, `docs/DESIGN-SYSTEM.md`, `docs/AGENTS.md`, `docs/PRODUCT-SPEC.md`.
3. Design inputs: open PR `janestreetshiller/fleet-console#16` (`design/`): `tokens.css`, `tui.html` (six-view TUI mockup), `gauges.html` (cluster gauge panel), logo `assets/fleet-console-logo-terminal.svg`, `README.md` (keymap, thresholds, data contract).
4. The Mac popover (reference for the GPUI window and menu-bar item): header with logo, "FleetConsole" and "N services running", a grid icon, an Agent button and an overflow menu; four columns: CPU dial gauge with percent, Memory dial gauge with percent, Disk as a 5x4 block grid with percent, Network as download and upload rates each with a bar. Dials show a green arc, a needle, tick marks and a red zone near the top. Match this information design, not its pixels, in GPUI.

Current source and observed state outrank this prompt and any handoff doc. Resolve discrepancies for the affected action only.

## 1. Ground truth (verified against the repo)

- Swift package: `FleetCore` (shared logic), `fleetd` (controller: registry, event log, service lifecycle, health checks, device prober, session scanner), `fleetctl` (CLI), `FleetConsoleApp` (SwiftUI app). Swift 6, macOS 14+.
- Rust workspace `rust/` (rust-version 1.80 declared; GPUI's tree needs a newer toolchain, so use the recorded one, do not assume 1.80): `fleet-proto` (newline-delimited JSON over a `0600` Unix socket; enum `RpcOp`; `default_socket_path()`; blocking client, no async runtime, no subscriptions yet), `fleet-conformance` (wire checks against a live Swift controller), `fleet-agent` (resident ops helper, separate from the UI), `fleet-telemetry` (`sysinfo` 0.31; `TelemetrySnapshot`, `ProcessMetric`, `StoragePoolMetric`, `SocketEndpointMetric`, `MemoryPoolMetric`; also a `SimulatedTelemetryProvider`), `ouros-adapter`, `fleet-spatial`, `fleet-gpui` (experimental, gpui `=0.2.2`, about 1.7k lines: app, sidebar, plane, topography, diagnostics drawer, contextual terminal, theme).
- `docs/RUST-PORT.md` records that the GPUI prototype had invented data (simulated fallback values, derived thermal label, default disk I/O, empty callbacks, a terminal preview without a PTY). Honest-state rules below exist because of this.
- The controller `fleetd` is Swift. Whether it builds and runs on Linux is unverified. This is the central architecture question; see section 3.

## 2. Non-negotiable rules

- Missing observations are unavailable, never zero, healthy or simulated. Keep process existence, listening ports, reachability and configured health checks as separate facts. Every view needs explicit loading, disconnected, stale and error states. Simulated providers may exist for tests and screenshots only and must be unreachable from release builds.
- Agents and both UIs act through the controller protocol (`fleetctl` semantics), never by signalling processes directly. Claiming an external process grants visibility, not signalling authority. Preserve owner, lease and process-identity checks. Destructive actions show a confirmation first.
- Bound everything: response sizes, request time, polling frequency, history buffers. Blocking socket calls stay off the render thread. Report idle CPU and allocation growth for both clients.
- Use synthetic fixtures in tests, screenshots and docs. No real hostnames, home paths, tailnet names, IPs, process arguments or credentials in anything committed or uploaded.
- Do not add dependencies without a stated reason; discuss new ones (for example `ratatui`, `crossterm`) in the plan before use. Preserve MIT and third-party notices and the `Package.resolved` / `Cargo.lock` commit discipline.
- No precautionary backup copies. No deploying, packaging, installing, restarting a controller, publishing or pushing to a default branch without scope in the current request. Branches and PRs for review are fine.
- UI baseline: no uppercase letter-spaced eyebrows, no `//` label prefixes, no decorative separator glyphs or ornamental arrows. Run the baseline lint where it applies and report the result.

## 3. Architecture to decide in the first pass (recommend, then proceed)

Decide and record in `docs/CROSS-PLATFORM.md` within the first work unit:

1. **Controller on Linux.** Options: (a) build `fleetd` with Swift on Linux if feasible; (b) write a Rust controller implementing the same wire protocol and on-disk registry; (c) ship the UIs as clients of macOS controllers only at first, with a Linux-local read-only mode. Test (a) first with a real Linux build on an available Linux machine. Recommend one, with evidence, and keep the Swift controller authoritative on macOS. Any Rust controller must pass `fleet-conformance` unchanged.
2. **Shared core.** New crate `fleet-ui-core` (no UI deps): controller client wrapper with a poll or subscription thread, normalized snapshot model, derived view models (cluster tiles, gauge values, service rows, process tree, needs-attention reports), thresholds (50, 70, 90 percent), formatting, and the honest-state enum. Both clients consume only this crate.
3. **Platform seam.** One `platform` module behind traits, with `macos` and `linux` implementations: telemetry (CPU, memory, GPU where measurable, disk, network, per-process; document exactly what is measured versus unavailable per OS; Linux via `sysinfo` plus `/proc`, `/sys` and cgroups where needed), service supervision backend (launchd versus systemd user units, only if the controller design requires it), paths (`default_socket_path` per OS, XDG on Linux), notifications, and the tray or menu-bar item (macOS status item; Linux StatusNotifierItem, with a clear degraded mode when no tray exists, such as GNOME without the extension).
4. **Protocol.** Add subscription or long-poll support to `fleet-proto` only if polling measurably fails the idle-CPU or latency budget; otherwise keep bounded polling.

## 4. Deliverables and workstreams

Assign each to a capable worker with clear file ownership; no two workers write the same files. Each worker returns changed paths, commands run, actual results and limitations.

- **W1 Foundation (blocking):** reproducible fresh-checkout build of the Rust workspace on macOS and Linux, pinned toolchain file, CI matrix additions (macOS and Linux) alongside the existing Swift CI, the `docs/CROSS-PLATFORM.md` decision record, and the Linux `fleetd` feasibility result.
- **W2 Core and platform:** `fleet-ui-core` plus `platform` implementations with unit tests using synthetic fixtures; telemetry honesty table; remove or quarantine simulated fallbacks from non-test paths.
- **W3 TUI:** new crate `fleet-tui` (binary also reachable as `fleetctl tui` if the CLI owner agrees). Six views from the design package (Overview, Processes, Services, Agents, Storage, Attention), keymap from the README (`1-6`, `j/k`, `enter`, `/`, `r`, `s`, `t`, `a`, `y/n`, `?`, `q`), phosphor palette from `tokens.css` with automatic reduction for 16-color and no-color terminals (`NO_COLOR` respected), resize handling, mouse optional, screen-reader-friendly plain mode (`--plain`), confirmation line for destructive actions, live tail of service logs, and an agent transcript view with inline approve or deny that goes through the controller.
- **W4 GPUI app:** evolve `fleet-gpui` into the real client: popover-style quick view (CPU and memory dials, 5x4 disk grid, network bars, services count) and a full window (cluster gauge tiles per the design package, process tree, services, agents, storage map, attention). Real controller state only. Native-feeling menu-bar or tray behavior per OS, keyboard navigation and accessibility labels, light and dark appearance, a real PTY-backed contextual terminal or removal of the terminal until one exists.
- **W5 Design system:** a single token source (`tokens.json`) generating `tokens.css`, the TUI palette and GPUI theme constants, so the three never drift. Document how the existing paper and ink native design relates to the phosphor direction; do not restyle the Swift app.
- **W6 Verification and QA:** isolated controller instance and state directory for all runs; `fleet-conformance` green on macOS and Linux against the same fixtures; rendered captures of every view and state (loading, disconnected, stale, error, warn, critical, offline node) at three terminal sizes and two window sizes with private data scrubbed; keyboard-only walkthrough; idle CPU and memory numbers for TUI and GPUI after 10 minutes; reduced-motion and no-color checks.
- **W7 Site and docs (after W3 and W4 land):** port the cluster view section to the live product page per `design/README.md` shipping notes, update `docs/RUST-PORT.md` and README with the cross-platform status. Live deployment is a separate, explicitly scoped step.

Sequence: W1 first; W2 and W5 in parallel once W1's decision record exists; W3 and W4 in parallel against `fleet-ui-core`; W6 continuously with a final pass; W7 last.

## 5. Acceptance (do not claim done without these)

- Fresh checkout on macOS and on Linux: Rust workspace builds with the pinned toolchain; Swift build and tests still pass on macOS; `fleet-conformance` passes against an isolated controller on each supported OS.
- Both clients show real controller data end to end, including a service restart and an agent approval, and show correct unavailable, stale and disconnected states when the controller is stopped or the socket is missing.
- No simulated values reachable in release builds (prove with a test or a build-feature check).
- Captures and keyboard walkthrough attached; idle CPU and allocation measurements reported with workload, toolchain and hardware.
- A statement of what is measured versus unavailable per OS, including GPU on Linux.

## 6. Reporting

Maintain a running plan. After each work unit report: what changed (paths), checks run and actual results, pre-existing failures separately from regressions, open decisions, and remaining limitations. Ask the owner only for consequential unresolved decisions (for example the Linux controller choice if evidence is split, new dependencies, or any publishing or deployment step). Otherwise proceed with reasonable assumptions and say what you assumed.
