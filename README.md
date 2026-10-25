# FleetConsole

<img width="552" height="318" alt="image" src="https://github.com/user-attachments/assets/2f653aa7-6c6a-4df6-8225-9c1a920917c7" />




FleetConsole places CPU and memory dials one click from your Mac’s menu bar, offering a full dashboard for deeper review. You can review load in Quick View, then trace it through timed charts, processes, and service logs in the Dashboard. A local controller and fleetctl monitor the tasks your coding agents initiate. The system requires macOS 14 or later.

The complete source—core, controller, CLI, Rust protocol, and native app—is available under the MIT license. Local monitoring and service control continue to be free.

The source and downloads live at
https://github.com/janestreetshiller/fleet-console.
Optional multi-device access costs $10 USD/month through Ouros, operated by
Ouros AI, LLC. Choose **Link a Device…**, sign in to Ouros, and complete secure
checkout. Refresh the subscription after payment to link additional computers.
SwiftTerm retains its own MIT notices.

CPU and memory lead the Overview with taller plots. Choose CPU or Memory to focus
a single chart, then zoom between 15 seconds, 30 seconds, 1 minute and 2 minutes.
The horizontal axis shows actual observation times, including sampling gaps;
individual spikes are preserved. Disk, GPU, network and sensors expand below.

## One place to look

One menu-bar cluster shows CPU, memory and disk use, connection state, and an attention
count when needed. Its dropdown shows **Quick View**: CPU and memory dials,
a disk-capacity map, upload/download bars and a dashboard action. The **Agent**
menu starts an account-backed investigation of CPU, Memory, Disk or Network.
Right-click or Control-click for **Needs Attention**, **Agents**, the dashboard,
named destinations, configuration, logs and Help. **fleetctl Setup…** explains
where the bundled CLI lives and can copy a controller-check command. Both views
share the same resource probes and sampling cadence.

The dashboard opens to **Overview**: CPU, GPU, memory, disk, network history, and
large process consumers. A native sidebar leads to **Processes**, **Storage**,
**Needs Attention**, **Operations**, **Events**, and **Launch Services**.
Operations groups Services, Network, Agents, Storage, Events, Launch Services
and Account in one workspace. Other
computers appear separately with their reachability evidence.

Search matches the current destination. Changing destinations clears the previous
filter; reopening the same destination keeps it. An empty process search offers
**Clear Search**. Select a process or service to open its inspector.

Unavailable readings are labelled unavailable. Battery information appears only
when a battery exists; temperature and fan readings depend on hardware support.
A running process without a configured health check is **Running (unverified)**.
Process existence, listening ports, host reachability, and health-check results
remain separate facts.

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

The app can pause, resume, renew, and stop controller-launched services. Running
services with unrenewed leases have their process groups cleaned up even when the
agent has gone away. Paused services retain their process groups and resources;
expiry cleanup resumes when they do. The controller verifies process identity
before signalling a process and records the action.

Processes started elsewhere remain unmanaged. `fleetctl claim` records ownership
and a lease for an existing process but grants no signalling authority: the
controller will not stop, restart, pause, kill, or reap it. Optional user-initiated
**End Process** is a separate, owner-only SIGTERM control, disabled by default.

This is FleetConsole's benefit alongside [Stats](https://github.com/exelban/stats):
Stats offers combined menu-bar monitoring and broader hardware features.
FleetConsole adds the owner, purpose, lease, evidence, logs, and supervision needed
to manage agent work.

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

## Tools and keyboard access

The interface uses macOS fonts, appearance colors and native controls. The sidebar
toggle stays at the left edge; the inspector toggle stays at the right edge.
Device fields retain their labels, selectable process rows work with the keyboard,
and shared surfaces honor Reduce Motion and Increase Contrast.

The dashboard's **View** menu opens Terminal and Files. Terminal is
your shell; commands entered there become supervised only when launched through
`fleetctl`. Files requires [Yazi](https://github.com/sxyazi/yazi).

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
session remains **Stopping** until cleanup finishes. Detached work that escapes
the group requires its own supervision; use `fleetctl` leases for background
services. Stop does not undo
edits, stop controller-managed services or guarantee cancellation of provider
billing. **Stop waiting** cancels an account investigation without clearing an
unconfirmed paid-operation identity or automatically retrying it; window close
also cancels waiting. Exit status is not proof that a problem was fixed. External agents keep
their own permissions and provider billing. Fleet Agent remains proposal-only,
and account-backed investigations remain output-only. Generic commands are
accepted only in **Shell**, never injected into an agent or investigation.
Returning to an ended shell restarts it in the same directory. Panel toggles
keep processes warm; window close ends agent children, including hidden or deferred sessions. Session
metadata and scrollback are not restored after quitting. Saved request files
remain local and owner-only under `Library/Application Support/FleetConsole/fix-reports`;
review their contents before sharing them.

| Action | Shortcut |
|---|---|
| Open Dashboard | ⌘0 |
| Overview / Processes / Storage | ⌘1 / ⌘2 / ⌘3 |
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
