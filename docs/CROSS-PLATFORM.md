# Cross-platform clients: decisions and status

Recorded 2026-10-25 on branch `feat/cross-platform-clients`, stacked on the
design package (`design/terminal-ui-package`). It covers the terminal client
(`rust/fleet-tui`), the GPUI client (`rust/fleet-gpui`) and the shared core
(`rust/fleet-ui-core`) on macOS and Linux. The SwiftUI menu-bar app, `fleetd`
and `fleetctl` are unchanged apart from one opt-in path override. Current
source and observed results outrank this record; recheck before acting on it.

## 1. Controller on Linux

**Decision: the Linux clients attach to a macOS controller now (option c).
A Swift build of `fleetd` for Linux (option a) is the recommended path to a
Linux controller. A Rust controller (option b) is not chosen.** The Swift
controller stays authoritative on macOS.

### Evidence: a real Linux build of `fleetd`

`swift build --product fleetd` ran in the `swift:6.2-noble` container on the
Linux workstation (Swift 6.2.4, x86_64). Each pass stops at the first missing
module, so later passes patched a scratch copy, never the repository:

| Pass | Change in the scratch copy | Result |
| --- | --- | --- |
| 1 | none | `no such module 'CoreGraphics'` (FleetCore, 3 files) |
| 2 | CoreGraphics imports replaced by Foundation; `Darwin` guarded with `Glibc`; IOKit and CryptoKit guarded | `no such module 'SQLite3'` |
| 3 | `CSQLite` system-library target with `libsqlite3-dev` | 57 errors in 7 FleetCore files, before any `fleetd` source compiled |

Pass 3 errors by file: `UnixSocket.swift` 18 (peer credentials use Darwin's
`xucred`/`LOCAL_PEERCRED`, `SO_NOSIGPIPE`, `sun_len`), `NativeNetworkCounters`
14 (`sysctl` interface MIB), `SystemTelemetry` 12 (IOKit power sources),
`TCPProbe` 5 (`fd_set` layout, `addrinfo` order), `SMC` 3, `StopMarker` 2,
`License` 1 (`@Observable` is unavailable on Linux). `fleetd` itself has
further Darwin dependencies that pass 3 did not reach: `ProcessLauncher`
(`posix_spawn` attributes, start identity read with `ps -o lstart`),
`SessionScanner` (`sysctl KERN_PROCARGS2`), `DeviceProber` (`getifaddrs`), and
launchd assumptions in `main.swift` and `fleetctl`.

### Why (a) over (b)

The errors are platform shims, not design problems: peer credentials become
`SO_PEERCRED`, sysctl reads become `/proc` and `/sys`, IOKit telemetry becomes
unavailable or sysfs, SQLite links through a system-library target, launchd
becomes a systemd user unit. Porting them keeps one registry, one lease and reap
implementation, one start-identity check and one wire encoder, which is what
`fleet-conformance` can then verify on both systems. A Rust controller would
have to reproduce all of that, including the SQLite schema and event log, and
`fleet-conformance` only proves the wire format, not those semantics. The peer
credential check and process identity are security-relevant, so either port
needs review against `docs/THREAT-MODEL.md`. Whether FleetConsole should follow
the wider Ouros direction of moving subsystems into Rust is an owner decision
outside this work.

### How a Linux client attaches today

No network listener is added (threat model T5). The client reaches a
controller socket on a Mac through SSH. On the Mac used for verification, sshd
refused OpenSSH's socket forwarding (`ssh -L local.sock:remote.sock` failed with
`connect failed: open failed` for the controller socket and for a symlink to
it), while a stdio bridge worked. The supported form is therefore:

```bash
mkdir -p -m 700 "$XDG_RUNTIME_DIR/fleetconsole"
socat "UNIX-LISTEN:$XDG_RUNTIME_DIR/fleetconsole/fleetd.sock,fork,mode=600,unlink-early" \
  "EXEC:ssh -o BatchMode=yes mac-host nc -U '/Users/you/Library/Application Support/FleetConsole/fleetd.sock'"
```

`$XDG_RUNTIME_DIR/fleetconsole/fleetd.sock` is the Linux default the clients
and `fleet-conformance` use (see section 3). Anyone who can open the forwarded
socket can operate the remote controller, so the socket is created `0600` in a
`0700` directory and the bridge runs only while needed.

When no controller is reachable, both clients run in Linux-local mode: the
controller phase reads *disconnected*, every service and agent control is
disabled with that reason, and local telemetry, the process list and storage
keep updating. `--read-only` refuses mutating actions in the client even when a
controller is reachable.

When the controller runs on another machine, its pids name processes on that
machine. The core detects this (no local `fleetd` with the controller's pid)
and stops joining service pids with the local process tree; `--remote-controller`
forces that interpretation.

## 2. Shared core: `fleet-ui-core`

No UI dependencies. Both clients consume only this crate:

- `model`: the controller snapshot typed from Swift's JSON (epoch-second dates,
  Swift key spellings, unknown enum values decode to `Unknown`, missing required
  fields are errors, never defaults).
- `observe`: `Metric::{Measured, Unavailable(Reason)}` and `Feed<T>` with
  `Phase::{Loading, Live, Stale, Disconnected, Error}`. Staleness is evaluated at
  render time against the clock, so a hung worker shows as stale.
- `controller`: a poller thread and an action thread, one fresh connection per
  request through `Client::send_bounded`. Actions map one-to-one to controller
  operations with `fleetctl` semantics; nothing signals a process.
- `platform`: background telemetry sampling and the OS seam (section 3).
- `views`: `Dashboard::build`, a pure function of the feeds, pending actions and
  a clock, producing every row, gauge, control state and message the clients
  draw. Controls carry the refusal reason (read-only, not current, claimed
  process, request in flight) instead of letting a client send a doomed request.
- `thresholds`, `format`, `theme`: the 50/70/90 bands, text forms, and tokens.
- `fixtures`: synthetic snapshots, compiled only for tests and the `fixtures`
  feature (section 7).

Bounds:

| What | Bound |
| --- | --- |
| Poll interval | 2 s default, clamped to 1 to 60 s |
| Snapshot request | 5 s deadline, 16 MiB response limit |
| Stop and restart | 30 s deadline (the controller waits out its grace period) |
| Log tail | 256 KiB requested, response limit twice that |
| Action queue | 16 queued; further submissions are refused, not buffered |
| Outcome history | 64 |
| Telemetry | 2 s interval; 2,048 process rows, 32 volumes, 40-sample history |
| View rows | 500 services, 300 process lines, 200 transcript lines, 100 attention rows |
| Stale threshold | three polls plus one deadline (11 s at defaults) |

## 3. Platform seam

`fleet_ui_core::platform` holds one `macos` and one `linux` module behind the
same functions. `platform::capabilities()` returns the table below at runtime.

| Value | macOS | Linux |
| --- | --- | --- |
| CPU | measured: host processor load via sysinfo | measured: `/proc/stat` via sysinfo |
| Memory | measured: sysinfo used memory (`host_statistics64`); may differ from the Swift app's figure | measured: `MemTotal - MemAvailable` |
| Disk | measured: `statfs` of `/System/Volumes/Data`; excludes purgeable space the Swift app counts as free | measured: `statvfs` of `/` |
| Network | measured: `en*` interface counters | measured: `/proc/net/dev`, excluding loopback, bridges, container and tunnel interfaces |
| GPU | not measured in the Rust clients (the Swift app reads IOAccelerator statistics) | measured only where amdgpu exposes `gpu_busy_percent`; Intel i915/xe and NVIDIA are unavailable |
| Processes | measured: names, parent, CPU, RSS via libproc; arguments are never collected | measured: same fields via `/proc` |
| Temperature | not measured; CPU load is never relabelled as thermal state | not measured |

CPU and network rates need two samples; the first reading is *awaiting second
sample*, not zero. Network as a percentage needs a link capacity that is not
measured, so the cluster tile shows the rate and an unavailable percent.
Linked-device tiles use the controller's `HostMetrics`; network, history and
uptime are not reported for them.

Other seams:

- **Socket path** (`fleet_proto::default_socket_path`): `FLEETCONSOLE_SOCKET`,
  then `FLEETCONSOLE_STATE_ROOT`, then `~/Library/Application Support/FleetConsole/fleetd.sock`
  on macOS, or `$XDG_RUNTIME_DIR/fleetconsole/fleetd.sock` (falling back to
  `~/.local/state/fleetconsole/fleetd.sock`) on Linux.
- **Isolated controllers**: `FleetPaths` honors `FLEETCONSOLE_STATE_ROOT` for
  `fleetd`, `fleetctl` and the clients. Setting `HOME` does not isolate on macOS:
  Foundation's home lookup ignores it, and a test controller started that way
  found the user's socket and exited. Keep the root short; macOS limits socket
  paths to 104 bytes.
- **Notifications**: `osascript` on macOS, `notify-send` on Linux, each with a
  3 s deadline; the function returns the reason when neither works.
- **Status area**: the macOS menu bar; on Linux, a StatusNotifierItem host is
  detected with `busctl` on the session bus. Without one (GNOME without the
  AppIndicator extension, or a compositor bar without a tray module) the client
  runs as an ordinary window and says why. The Linux workstation used here has
  no host registered.
- **Service supervision backend**: not needed by the clients. A Linux
  controller (option a) would run as a systemd user unit in place of launchd.

## 4. Protocol

Bounded polling, no `subscribe`. The Swift controller supports `subscribe`, but
`fleet-proto` does not model it, and section 8 shows polling within the idle
budget. Add subscriptions only if a measurement shows polling failing the idle
CPU or latency budget.

## 5. Toolchain and dependencies

- `rust-toolchain.toml` pins Rust 1.98.0, the version exercised on both systems.
  The workspace declares `rust-version = "1.89"`, the highest floor among the
  locked dependencies (`uuid 1.28`); 66 locked crates use edition 2024. The 1.89
  floor is declared from metadata, not compiled.
- New dependency: `ratatui 0.30` (MIT) for the terminal client, with default
  features off and only its crossterm backend. The client uses ratatui's
  re-exported `crossterm 0.29` (MIT) rather than a second, separately versioned
  crossterm. Reason: correct terminal state handling (raw mode, alternate
  screen, resize, mouse and key events on macOS and Linux), a tested layout and
  diffing renderer, and a `TestBackend` for deterministic captures; writing
  these over raw escape codes would add unreviewed unsafe terminal code. The new
  transitive crates are MIT, Apache-2.0 or Zlib licensed.
- `Cargo.lock` moved from format 3 to format 4 when Cargo 1.98 added the new
  crates; format 4 needs Cargo 1.78 or later, below the declared floor.

## 6. Design tokens

`design/tokens.json` is the single source. `fleet_ui_core::theme` compiles it
into both Rust clients, and a test renders `design/tokens.css` from it and fails
on drift (`FLEET_WRITE_TOKENS=1` regenerates). It carries the phosphor palette
from the design package, a paper palette for the GPUI window's light appearance,
ANSI 16-color indices for terminals without truecolor, the grid unit and the
threshold edges. Tests check text contrast against each background and that the
threshold edges match the band code.

The native SwiftUI app keeps following `docs/DESIGN-SYSTEM.md`: system semantic
colors and the paper/ink tone rules. The phosphor direction applies to the
terminal client, the GPUI client and the product page; the paper palette is the
GPUI light appearance, not a restyle of the Swift app.

## 7. No simulated data in release builds

Fixture data exists only under `#[cfg(any(test, feature = "fixtures"))]` in
`fleet-ui-core`, and the clients expose `--fixture` only with their own
`fixtures` feature. Fixture snapshots report the controller version
`synthetic-fixture-4c1e`, so a capture made from them says so on screen, and
`Scripts/verify-rust-clients.sh` fails if a default release binary contains that
string.

## 8. Verification

Recorded with toolchain 1.98.0 on an Apple silicon Mac (macOS) and an x86_64
Linux workstation, against an isolated controller built from this branch
(`FLEETCONSOLE_STATE_ROOT` under `/private/tmp`), never the installed one.

| Check | macOS | Linux |
| --- | --- | --- |
| `fleet-ui-core` and `fleet-proto` tests | 42 and 4 passed | 46 and 4 passed (adds sysfs and interface tests) |
| `fleet-conformance` against the isolated macOS controller | 13 passed, local socket | 13 passed, Linux-built binary through the SSH bridge at the default XDG path |
| Swift `fleetd` and `fleetctl` build with the path override | passed | not applicable (section 1) |

Client checks, captures, the keyboard walkthrough and idle measurements are
recorded in section 9 when they complete.

## Open decisions

- Port FleetCore and `fleetd` to Linux in Swift (recommended) or write a Rust
  controller.
- Add `fleetctl tui` as an entry point to `fleet-tui`: needs the CLI owner's
  agreement; not added.
- Publishing the product-page section is a separate, explicitly scoped step.
