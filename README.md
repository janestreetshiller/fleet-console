# FleetConsole

See what your Mac is doing and keep track of the background work your agents start.
FleetConsole combines a native macOS menu-bar monitor, a local controller, and the
`fleetctl` command-line tool. Requires macOS 14 or later.

FleetConsole is MIT licensed. Every feature is available without an account,
activation key, trial deadline, or payment. SwiftTerm retains its own MIT notices.

## One place to look

One menu-bar cluster shows CPU and memory use, connection state, and an attention
count when needed. Click it for **Services**, **Agents**, **Processes**, and
**Network**. Right-click or Control-click for the dashboard, named destinations,
configuration, and logs.

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

The app can pause, resume, renew, and stop controller-launched services. Unrenewed
leases clean up their process groups even when the agent has gone away. The
controller verifies process identity before signalling it and records the action.

Processes started elsewhere remain unmanaged. `fleetctl claim` records ownership
and a lease for an existing process but grants no signalling authority: the
controller will not stop, restart, pause, kill, or reap it. Optional user-initiated
**End Process** is a separate, owner-only SIGTERM control, disabled by default.

This is FleetConsole's benefit alongside [Stats](https://github.com/exelban/stats):
Stats already offers combined menu-bar monitoring and broader hardware features.
FleetConsole adds the owner, purpose, lease, evidence, logs, and supervision needed
to manage agent work. A single cluster alone is not a novel feature, and this
project does not claim lower resource use or superiority across every metric.

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

The dashboard's **Tools** menu opens Terminal, Files, and Interpret. Terminal is
your shell; commands entered there become supervised only when launched through
`fleetctl`. Files requires [Yazi](https://github.com/sxyazi/yazi). Interpret uses
your existing `orcs` wrapper and local model. Missing tools show an explanation.

| Action | Shortcut |
|---|---|
| Open Dashboard | ⌘0 |
| Overview / Processes / Storage | ⌘1 / ⌘2 / ⌘3 |
| Services / Events / Launch Services | ⌘4 / ⌘5 / ⌘6 |
| Needs Attention | ⇧⌘H |
| Search / Refresh | ⌘K / ⌘R |
| Toggle inspector | ⌥⌘I |
| Terminal / Files / Interpret | ⇧⌘T / ⇧⌘F / ⇧⌘D |

## Local data and configuration

Registry and configuration live in
`~/Library/Application Support/FleetConsole`; daemon and service logs live in
`~/Library/Logs/FleetConsole`. The controller communicates over an owner-only Unix
socket. Network probes inspect connections and routing; they do not change them.

**Edit Configuration** in the dropdown opens `config.json`. It controls visible
sections, polling intervals, known computers, expected listeners, and optional
process termination. Agent spend is off by default because its price table needs
verification. See [CLI reference](docs/CLI.md), [agent contract](docs/AGENTS.md), and
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
