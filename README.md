# FleetConsole

FleetConsole puts CPU and memory dials one click from your Mac's menu bar, with a
full dashboard for a closer look. Check the load in **Quick View**, then follow it
through timed charts, processes and service logs in the **Dashboard**. A local
controller and `fleetctl` keep track of the work your coding agents start.
Requires macOS 14 or later.

The complete source — core, controller, CLI, Rust protocol and native app —
is published under MIT. Local monitoring and service control are free.
The source and downloads live at
https://github.com/janestreetshiller/fleet-console.
Optional multi-device access costs $10 USD/month through Ouros, operated by Ouros AI, LLC. Connect your Ouros
account in Devices, refresh the subscription options, and complete secure checkout;
refresh your subscription to link additional computers.
SwiftTerm retains its own MIT notices.

CPU and memory lead the Overview with taller plots. Choose CPU or Memory to focus
a single chart, then zoom between 15 seconds, 30 seconds, 1 minute and 2 minutes.
The horizontal axis shows actual observation times, including sampling gaps;
individual spikes are preserved. Disk, GPU, network and sensors expand below.

## One place to look

One menu-bar cluster shows CPU and memory use, connection state, and an attention
count when needed. Its dropdown starts on **Quick View** and remembers your last
tab. Quick View shows CPU and memory dials, a disk-capacity map, upload/download
bars and an **Open Dashboard** button. **Services**, **Agents**, **Processes**
and **Network** tabs remain available. Right-click or Control-click for **Quick
View**, the dashboard, named destinations, configuration and logs. Both views
share the same resource probes and sampling cadence.

The dashboard opens to **Overview**: CPU, GPU, memory, disk, network history, and
large process consumers. A native sidebar leads to **Processes**, **Storage**,
**Needs Attention**, **Services**, **Events**, and **Launch Services**. Other
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

The dashboard's **Tools** menu opens Terminal and Files. Terminal is
your shell; commands entered there become supervised only when launched through
`fleetctl`. Files requires [Yazi](https://github.com/sxyazi/yazi).

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

The device screen links to Ouros billing for prepaid AI credits. The Agents tab opens Ouros Agent for a credit-funded review of current problems and service records. It uses the connected Ouros account and the gateway's model catalog. Each model round is metered; a stopped or uncertain request is not retried automatically. The agent reads the supplied service snapshot and can propose a restart. You approve it separately, and the existing controller performs it only for a controller-launched service. This Mac must remain awake; deployable agents and FleetConsole MCP remain planned. The $10/month FleetConsole
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

See [CONTRIBUTING.md](CONTRIBUTING.md), [design system](docs/DESIGN-SYSTEM.md), and
[release guide](docs/RELEASE.md) for checks. Report sanitized bugs in
[GitHub issues](https://github.com/janestreetshiller/fleet-console/issues) and use
[SECURITY.md](SECURITY.md) for private security reports.
