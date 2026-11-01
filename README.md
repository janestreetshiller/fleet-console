# FleetConsole

<img width="552" height="318" alt="FleetConsole menu bar and dashboard" src="https://github.com/user-attachments/assets/2f653aa7-6c6a-4df6-8225-9c1a920917c7" />

## Overview

FleetConsole places CPU and memory dials one click from the Mac's menu bar, with a full dashboard for deeper review. Load can be reviewed in Quick View and traced through timed charts, processes, and service logs in the Dashboard. A local controller and the `fleetctl` CLI monitor the tasks coding agents initiate. macOS 14 or later is required. The complete source — core, controller, CLI, Rust protocol, and native application — is available under the MIT license; local monitoring and service control are free. Source and downloads: https://github.com/janestreetshiller/fleet-console. Optional multi-device access costs $10 USD/month through Ouros (operated by Ouros AI, LLC); SwiftTerm retains its own MIT notices.

## How it works

- **Menu-bar cluster**: CPU, memory, and disk use, connection state, and an attention count. The dropdown Quick View shows CPU/memory dials, a thin disk-capacity track, and directional upload/download rates in one horizontal strip. Three action buttons open Agent, Diagnostics, and Preferences. Right-click offers Needs Attention, Agents, the dashboard, named destinations, configuration, logs, and Help; `fleetctl Setup…` explains the bundled CLI and can copy a controller-check command. Both views share the same resource probes and sampling cadence.
- **Dashboard**: opens to an agent-first spatial awareness map. Detected sessions show their actual published activity in project clusters, with evidence-backed connections to matching process identities, observed process children, registered owners, managed services and listeners. Drag the canvas to pan, pinch or use the zoom buttons, fit the map, and select a node to explore its relationships and provenance. Search finds activity and its immediate context; process/service inspectors remain available without leaving the map. Tool names, PIDs and shared folders never establish inferred ownership or code dependencies. Stale registry evidence remains explicitly retained and cannot verify a process. The projection is bounded and event-driven, with no physics animation, additional collector or paid request. Diagnostic process tables, storage and other detailed views remain under Tools and the View menu. The device sidebar starts tucked away; its toggle reveals local/linked machines.
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

| Action | Shortcut |
|---|---|
| Open Dashboard | ⌘0 |
| Agent awareness / Processes / Storage | ⌘1 / ⌘2 / ⌘3 |
| Services / Events / Launch Services | ⌘4 / ⌘5 / ⌘6 |
| Needs Attention | ⇧⌘H |
| Search / Refresh | ⌘K / ⌘R |
| Toggle inspector | ⌥⌘I |
| Terminal / Files | ⇧⌘T / ⇧⌘F |

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

Alongside [Stats](https://github.com/exelban/stats) (combined menu-bar monitoring, broader hardware features), FleetConsole adds the owner, purpose, lease, evidence, logs, and supervision needed to manage agent work. See [CLI reference](docs/CLI.md), [source preview and agent workflow](docs/SOURCE-PREVIEW.md), [threat model](docs/THREAT-MODEL.md), [CONTRIBUTING.md](CONTRIBUTING.md), [design system](docs/DESIGN-SYSTEM.md), [launch copy](docs/LAUNCH-COPY.md), and the [Rust/GPUI assessment](docs/RUST-PORT.md). Report sanitized bugs in [GitHub issues](https://github.com/janestreetshiller/fleet-console/issues); use [SECURITY.md](SECURITY.md) for private security reports.
