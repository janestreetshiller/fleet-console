# FleetConsole

<img width="552" height="318" alt="FleetConsole menu bar and dashboard" src="https://github.com/user-attachments/assets/2f653aa7-6c6a-4df6-8225-9c1a920917c7" />

## Overview

FleetConsole places CPU and memory dials one click from the Mac's menu bar, with a full dashboard for deeper review. Load can be reviewed in Quick View and traced through timed charts, processes, and service logs in the Dashboard. A local controller and the `fleetctl` CLI monitor the tasks coding agents initiate. macOS 14 or later is required. The complete source — core, controller, CLI, Rust protocol, and native application — is available under the MIT license; local monitoring and service control are free. Source and downloads: https://github.com/janestreetshiller/fleet-console. Optional multi-device access costs $10 USD/month through Ouros (operated by Ouros AI, LLC); SwiftTerm retains its own MIT notices.

## How it works

- **Menu-bar cluster**: CPU, memory, and disk use, connection state, and an attention count. The dropdown Quick View shows CPU/memory dials, a thin disk-capacity track, and directional upload/download rates in one horizontal strip. Three action buttons open Agent, Diagnostics, and Preferences. Right-click offers Needs Attention, Agents, the dashboard, named destinations, configuration, logs, and Help; `fleetctl Setup…` explains the bundled CLI and can copy a controller-check command. Both views share the same resource probes and sampling cadence.
- **Dashboard**: opens to an agent-first spatial awareness map. Detected sessions show their actual published activity in project clusters, with evidence-backed connections to matching process identities, observed process children, registered owners, managed services and listeners. Drag the canvas to pan, pinch or use the zoom buttons, fit the map, and select a node to explore its relationships and provenance. Search finds activity and its immediate context; process/service inspectors remain available without leaving the map. Tool names, PIDs and shared folders never establish inferred ownership or code dependencies. Stale registry evidence remains explicitly retained and cannot verify a process. The activity projection is bounded and event-driven, with no physics animation or paid request. Diagnostic process tables, storage and other detailed views remain under Tools and the View menu. The device sidebar starts tucked away; its toggle reveals local/linked machines.
- **Directory roots**: a crystalline folder-containment structure sits behind activity. Roots form foundations; child folders branch along a triangular lattice and show immediate child-folder counts. Select a vertex or use its child navigator to inspect, focus, open, expand or collapse a branch. Roots → Choose roots… selects and remembers local folders; an existing `~/Code` is the default workspace root. Fit roots shows the complete observed structure; Roots → Focus activity restores readable agent context. Actual project paths anchor to observed directory vertices. Reads are metadata-only, asynchronous, cancellable, and refreshed from the existing observation pulse at most every 30 seconds, or on explicit refresh/expansion. The initial view is three levels deep and bounded to 600 folders/12,000 directory entries; coverage limits and unreadable counts are explicit, and expansion prioritizes the chosen branch. Hidden/generated folders and symbolic links are excluded. Automatically discovered roots do not request private-folder or volume access; native picker selections remain subject to OS permissions. Facets group siblings, not code dependencies.
- **Controller and CLI**: launch through `fleetctl` to record an owner, purpose, lease, and logs. The application can pause, resume, renew, and stop controller-launched services. Services with unrenewed leases have their process groups cleaned up even after the launching agent disappears; paused services retain their groups and resources, with expiry cleanup resuming on unpause. The controller verifies process identity before signalling and records the action. Processes started elsewhere remain unmanaged; `fleetctl claim` records ownership and a lease for an existing process but grants no signalling authority — the controller will not stop, restart, pause, kill, or reap it. Optional user-initiated End Process is a separate owner-only SIGTERM control, disabled by default.
- **Agent sessions**: choosing an installed fixer hands it a Needs Attention finding; Claude Code, Codex, and Fleet Agent open in separate terminal sessions rather than typing into the shell. The Session picker switches between the warm shell, up to four agent sessions, and the latest account-backed read-only investigation; starting another agent never replaces a running one, and requests are never evicted automatically. Details shows the request, working directory, permission/billing policy, and troubleshooting options. Suggestions are ranked by matching events in the latest 200 supplied events within six hours — counts are local observations, not global prevalence, probabilities, or proof of a root cause; zero means no matching attributable event was supplied; legacy unmanaged events are not guessed into fabricated counts. Stop… confirms termination of the application-owned agent process group (SIGTERM, then SIGKILL after two seconds while child identity is verified); closing the PTY is not proof of exit. Application quit signals all remaining owned groups and waits the same escalation window. Detached work or descendants outliving a reaped group leader require separate supervision. Stop does not undo edits, stop controller-managed services, or guarantee cancellation of provider billing; Stop waiting cancels an account investigation without clearing an unconfirmed paid-operation identity; exit status is not proof a problem was fixed. External agents keep their own permissions and provider billing. Fleet Agent remains proposal-only; account-backed investigations remain output-only; generic commands are accepted only in the Shell, never injected into an agent or investigation. Panel toggles keep processes warm; window close ends agent children. Session metadata and scrollback are not restored after quitting. Saved request files remain local and owner-only under `Library/Application Support/FleetConsole/fix-reports`.

## Requirements

Swift 6 toolchain with the macOS SDK. The application uses SwiftTerm; the controller and CLI have no external package dependencies.

## Build and check

```sh
swift test --disable-index-store -Xswiftc -disable-cmo
stage="$(mktemp -d "${TMPDIR:-/private/tmp}/fleet-console.XXXXXX")"
FLEETCONSOLE_OUTPUT_DIR="$stage" FLEETCONSOLE_IDENTITY=- \
  Scripts/build-app.sh release
open "$stage/FleetConsole.app" --args --dashboard
```

The build script creates a fresh bundle, signs it ad hoc, and validates it; it does not install the application or restart an existing controller. A local ad-hoc build is a review artifact; distributing a download requires Developer ID signing and notarization ([release guide](docs/RELEASE.md)). `fleetctl` is bundled at `FleetConsole.app/Contents/Resources/bin/fleetctl` (use the full path until it is on PATH); `fleetctl doctor` checks controller connectivity and local state.

Acceptance harnesses:

- `python3 Scripts/test-terminal-integration.py` — builds the production Rust formatter fixtures and Fleet Agent, then exercises real PTYs, session cleanup, rendered lifecycle labels, and both Overview appearances. Each native suite runs in a separate process (AppKit state is process-wide). The model response is a labelled loopback fixture: no model is started and no paid provider is called. The harness uses a temporary home and observational controller RPCs, writes evidence to a fresh private system-temp directory, and fails on skipped cases. Captures can include real local process data; review before sharing.
- `Scripts/benchmark.sh 60` — runs the optimized application with real probes in offscreen native windows, exercises navigation, and captures light/dark layouts at three sizes. The CPU result covers the application process only (excluding collector children and WindowServer) and is not an on-screen idle measurement.
- `Scripts/product-detail-sheet.sh` — renders only the dark Quick View and Overview from synthetic fixtures, uses a disposable home, avoids keychain access and tool/account surfaces, and fails unless exactly the two expected PNGs are produced.

## Usage

## Agent monitoring and relationships

Choose **Agents & Map** in the dashboard sidebar, or **Operations → Agents**.
The fixed columns connect recorded owners to active services, identity-verified
group leaders and observed listeners. Select a service to inspect its purpose,
lease, health evidence and existing logs/actions. Search owners, service names,
IDs or detected sessions; filter an exact recorded owner. The roster and inbox
remain available in the same workspace.

Detected agent sessions occupy a separate lane: a tool name or shared PID does
not establish ownership. Declared ports remain declarations. Missing or stale
samples are unavailable, and a disconnected controller retains clearly labelled
observations. Service nodes show their recorded state separately from health
check results. This map does not expose dependency-aware pruning or agent
reasoning/context telemetry, which the controller does not provide.

Ouros account/device management, usage credits and explicit problem review open
from this workspace using the existing account and review contracts. Opening the
map starts no paid request. Use `fleetctl topology [--owner <exact-id>] [--json]`
for the same evidence, or `--snapshot <path>` to inspect saved `fleetctl list
--json` output without a controller. See [CLI reference](docs/CLI.md).

## Keep background work accountable

Launch through `fleetctl` to record an owner, a purpose, a lease, and logs:

```sh
fleetctl launch --name "Local API" --owner codex \
  --purpose "API for the current task" --cwd "$PWD" \
  --lease 30m --port 8787 \
  --health-http http://127.0.0.1:8787/healthz -- python3 -m my_api

fleetctl list
fleetctl show "Local API"
fleetctl logs "Local API" --err
fleetctl renew "Local API" --lease 30m
fleetctl events "Local API"
fleetctl stop "Local API"
```

The View menu opens Terminal (the user's shell; commands become supervised only when launched through `fleetctl`) and Files (requires [Yazi](https://github.com/sxyazi/yazi)). The interface uses macOS fonts, appearance colors, and native controls; the sidebar toggle stays at the left edge and the inspector toggle at the right; shared surfaces honor Reduce Motion and Increase Contrast. Preferences includes Matte/Glass shell material, agent defaults, and account access; Reduce Transparency forces an opaque backing.

Linked devices: choose Link a Device…, connect the Ouros account, subscribe to multi-device access, then enter the device name and hostname or IP (optionally an SSH username and opt-in to reading its FleetConsole service inventory). The controller probes reachability and reads metrics through the existing SSH configuration; remote processes are read-only; unlinking removes only the configuration entry. The device screen links to Ouros billing for prepaid AI credits; the Agents section opens Ouros Agent for a credit-funded review of current problems and service records, using the connected account and the gateway's model catalog. Each model round is metered; a stopped or uncertain request is not retried automatically. The agent reads the supplied service snapshot and can propose a restart, which the operator approves separately and the controller performs only for a controller-launched service. This Mac must remain awake; deployable agents and the FleetConsole MCP remain planned. The $10/month subscription has a separate entitlement from Ouros Pro and does not include AI credits. See the [multi-device integration contract](docs/MULTI-DEVICE.md).

Local data: registry and configuration in `~/Library/Application Support/FleetConsole`; daemon and service logs in `~/Library/Logs/FleetConsole`; the controller communicates over an owner-only Unix socket; network probes inspect connections and routing without changing them. Edit Configuration opens `config.json` (visible sections, polling intervals, known computers, expected listeners, optional process termination). Local agent-spend estimates are off by default because their price table needs verification; Ouros Agent displays the charge returned by the gateway for each review.

## Build and try

Use a Swift 6 toolchain with the macOS SDK. The application uses SwiftTerm for its
terminal; the controller and CLI have no external package dependencies.

```sh
swift test --disable-index-store -Xswiftc -disable-cmo
stage="$(mktemp -d "${TMPDIR:-/private/tmp}/fleet-console.XXXXXX")"
FLEETCONSOLE_OUTPUT_DIR="$stage" FLEETCONSOLE_IDENTITY=- \
  Scripts/build-app.sh release
open "$stage/FleetConsole.app" --args --dashboard
```

The build script creates a fresh bundle, signs it ad hoc, and validates it. It does
not install the app or restart an existing controller. A local ad-hoc build is a
review artifact; distributing a download requires Developer ID signing and
notarization. See [the release guide](docs/RELEASE.md) for staging, controller
installation, and distribution. `fleetctl` is bundled at
`FleetConsole.app/Contents/Resources/bin/fleetctl`; use that full path until it is
on your PATH. `fleetctl doctor` checks controller connectivity and local state.

### Retro GPUI companion

The experimental Rust companion is separate from the Swift app and its
controller. On macOS or Linux, build an optimized local binary and open its
phosphor dashboard with:

```sh
cargo build --manifest-path rust/Cargo.toml --locked --release -p fleet-gpui
./rust/target/release/fleet-gpui --theme phosphor
```

These are local, architecture-specific builds, not signed or notarized
downloads. The GPUI binary is separate from `FleetConsole.app`; do not replace
the native app or its controller with it. Use `--identity` for build identity
and `--verify --read-only --socket /path/to/nonexistent.sock` to sample local
telemetry without contacting a controller.

Phosphor applies in dark system appearance; light appearance uses the paper
palette. The companion reads local telemetry and connects to `fleetd` when
available. Linux has no local controller or tray item in this implementation;
see [cross-platform clients](docs/CROSS-PLATFORM.md) for the SSH bridge and
its security requirements. Native Windows and mobile builds are not supported.
The companion has no PTY-backed terminal or platform accessibility tree and
is not a replacement for the native app.

## Tools and keyboard access

The interface uses macOS fonts, appearance colors and native controls. The sidebar
toggle stays at the left edge; the inspector toggle stays at the right edge.
Device fields retain their labels, selectable process rows work with the keyboard,
and shared surfaces honor Reduce Motion and Increase Contrast.

The dashboard's **View** menu opens Terminal and Files. Terminal requires
[tmux](https://github.com/tmux/tmux): install it on the Mac and reopen Terminal
if it is missing. Fleet attaches the shell to the `shell` session on the separate
`fleet-console` tmux server. Closing the window or quitting Fleet detaches the
client; shell state and running jobs remain until the session exits, the server
is stopped, the user logs out, or the machine restarts. Reopening Fleet attaches
to the existing session. To deliberately end it, exit its shell or run
`tmux -L fleet-console kill-server` (this terminates its jobs). The working
directory is selected when the session is first created; later navigation does
not change a running shell's directory. Commands entered there become supervised
only when launched through `fleetctl`. Files requires
[Yazi](https://github.com/sxyazi/yazi).

This persistence applies to the Shell session only. Dedicated agent sessions
remain app-owned and are stopped when the window closes or Fleet quits; they
are not restored or replayed.

### Agent-aware terminal sessions

Choose an installed fixer in the Fixer menu, then hand it a Needs Attention
finding. Claude Code, Codex and Fleet Agent now open in separate terminal
sessions rather than typing into your shell. The **Session** picker switches
between the warm shell, up to four agent sessions and the latest account-backed
read-only investigation. Starting another agent never replaces a running one.
Close an ended session to make room; requests are never evicted automatically.
These are explicit FleetConsole handoffs, not detection of arbitrary commands
or an automatic Agent-RX integration.

**Details** shows the request, working directory, permission/billing policy and
troubleshooting options. The same options are included in the saved request the
agent receives. Health-check failures, repeated recorded crashes, lease expiry,
missing declared listeners, port violations and unmanaged work have distinct
checks and remedies. Up to eight suggestions are ranked by matching events in
the latest 200 supplied events within six hours. Counts are local observations,
not global prevalence, probabilities or proof of a root cause. Zero means no
matching attributable event was supplied. Legacy unmanaged events without a
process identity are not guessed or merged into a fabricated count. Stale or
unavailable evidence remains labelled;
claimed and unmanaged processes do not gain controller signalling authority.

**Stop…** confirms termination of that app-owned agent process group (SIGTERM,
then SIGKILL after two seconds while the child identity is still verified). The
session remains **Stopping** until cleanup finishes. Closing the PTY is not
proof that its child exited: cleanup verifies waitable-child ownership before
signalling. App quit signals all remaining owned groups, then waits for the same
two-second escalation window, including stops already in progress. Detached work,
or descendants that outlive an already-reaped group leader, require separate
supervision: this path does not signal a group whose leader identity it can no
longer reserve. Use `fleetctl` leases for background services. Stop does not undo
edits, stop controller-managed services or guarantee cancellation of provider
billing. **Stop waiting** cancels an account investigation without clearing an
unconfirmed paid-operation identity or automatically retrying it; window close
also cancels waiting. Exit status is not proof that a problem was fixed. External agents keep
their own permissions and provider billing. Fleet Agent remains proposal-only,
and account-backed investigations remain output-only. Generic commands are
accepted only in **Shell**, never injected into an agent or investigation.
Returning to Shell reconnects to the tmux session if it still exists. Panel toggles
keep processes warm; window close ends agent children, including hidden or deferred sessions.
Agent session metadata and scrollback are not restored after quitting. Saved request files
remain local and owner-only under `Library/Application Support/FleetConsole/fix-reports`;
review their contents before sharing them.

| Action | Shortcut |
|---|---|
| Open Dashboard | ⌘0 |
| Agent awareness / Processes / Storage | ⌘1 / ⌘2 / ⌘3 |
| Services / Events / Launch Services | ⌘4 / ⌘5 / ⌘6 |
| Needs Attention | ⇧⌘H |
| Search / Refresh | ⌘K / ⌘R |
| Toggle inspector | ⌥⌘I |
| Terminal / Files | ⇧⌘T / ⇧⌘F |

## Linked devices and AI credits

Choose **Link a Device…** in the sidebar. Connect your Ouros account and subscribe
to multi-device access, then enter the device name and hostname or IP;
optionally enter an SSH username and opt into reading its FleetConsole service
inventory. The controller probes reachability and reads metrics through your
existing SSH configuration. Remote processes are read-only. Unlinking removes
only the configuration entry. First-run setup creates no example peers.

The device screen links to Ouros billing for prepaid AI credits. The Agents section in Operations opens Ouros Agent for a credit-funded review of current problems and service records. It uses the connected Ouros account and the gateway's model catalog. Each model round is metered; a stopped or uncertain request is not retried automatically. The agent reads the supplied service snapshot and can propose a restart. You approve it separately, and the existing controller performs it only for a controller-launched service. This Mac must remain awake; deployable agents and FleetConsole MCP remain planned. The $10/month FleetConsole
subscription has a separate entitlement from Ouros Pro and does not include
AI credits. Cancellation and payment status come from Ouros billing. See the
[multi-device integration contract](docs/MULTI-DEVICE.md).

## Local data and configuration

Registry and configuration live in
`~/Library/Application Support/FleetConsole`; daemon and service logs live in
`~/Library/Logs/FleetConsole`. The controller communicates over an owner-only Unix
socket. Network probes inspect connections and routing; they do not change them.

**Edit Configuration** in the dropdown opens `config.json`. It controls visible
sections, polling intervals, known computers, expected listeners, and optional
process termination. Local agent-spend estimates are off by default because their price table needs
verification. Ouros Agent displays the charge returned by the gateway for each review. See [CLI reference](docs/CLI.md), [source preview and agent workflow](docs/SOURCE-PREVIEW.md), and
[threat model](docs/THREAT-MODEL.md).

## Verification and contribution

Run the native terminal acceptance harness to supply the prerequisites for the
formatter, actual-agent HTTP and observational shipping-Overview tests:

```sh
python3 Scripts/test-terminal-integration.py
```

It builds the production Rust formatter fixtures and Fleet Agent, then exercises
real PTYs, session cleanup, rendered lifecycle labels and both Overview appearances.
Each native suite runs in a separate process because AppKit state is process-wide.
The model response is a labelled loopback fixture: no model is started, no paid
provider is called, and production memory-pressure admission remains enforced.
The actual agent uses a temporary home; the Overview uses observational controller
RPCs. Evidence is written to a fresh private system-temp directory, and the harness
fails on skipped cases. Captures can include real local process/telemetry data;
review them before sharing.

`Scripts/benchmark.sh 60` runs the optimized app with real probes in offscreen
native windows, exercises navigation, and captures light/dark layouts at three
sizes. Each run gets a fresh evidence directory. Its CPU result covers the app
process only; it excludes collector children and WindowServer and is not an
on-screen idle measurement. Menu-bar interactions require a separate running-app
check. Captures can contain real machine data; review them before sharing.

`Scripts/product-detail-sheet.sh` renders only the dark Quick View and Overview
from synthetic fixtures. It uses a disposable home, avoids keychain access and
tool/account surfaces, and fails unless exactly those two PNGs are produced.

See [CONTRIBUTING.md](CONTRIBUTING.md), [design system](docs/DESIGN-SYSTEM.md), and
[release guide](docs/RELEASE.md) for checks. Report sanitized bugs in
[GitHub issues](https://github.com/janestreetshiller/fleet-console/issues) and use
[SECURITY.md](SECURITY.md) for private security reports.

For plain-language product descriptions and listing copy, see
[launch copy](docs/LAUNCH-COPY.md). The [Rust/GPUI assessment](docs/RUST-PORT.md)
separates the existing prototype from the native app's working features.
