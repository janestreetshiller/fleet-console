# FleetConsole

A local-first operations console for one person: a macOS menu-bar app plus a
launchd-managed controller that owns every background process your agents start.

**MIT licensed, with every feature permanently available.** No activation key,
trial expiry, account or payment is required. SwiftTerm keeps its own MIT notices.

The Overview opens first and shows native CPU/GPU/memory/disk instruments,
physical-interface download/upload history, and battery state on portable Macs.
Unavailable hardware readings stay unavailable. Two-second resource samples and
bounded histories drive the charts; decorative backgrounds and status indicators
are static instead of continuously animating behind the measurements.

For a repeatable live release check, run `Scripts/benchmark.sh 60`. It records
process CPU usage, exercises navigation, and captures light/dark layouts at three
window sizes without registering a helper or activating the app. Each invocation
creates a fresh `run.*` directory beneath the supplied output directory and prints
its location, so an earlier receipt cannot satisfy a later check. Review the
output before sharing: it contains real machine and process data.

Report sanitized bugs through [GitHub issues](https://github.com/janestreetshiller/fleet-console/issues)
and security issues through [the private reporting policy](SECURITY.md). See
[CONTRIBUTING.md](CONTRIBUTING.md) and [docs/RELEASE.md](docs/RELEASE.md) for build,
test and staged-release instructions. Donation setup is optional and not enabled.

```
  menu bar  ●3            ← at-a-glance rollup
     ↓ click                            ↓ right-click
  popover                            dropdown  ← Open Dashboard ⌘0 · the six
     ← Services · Agents ·                       modules ⌘1…⌘6 · Network ·
       Processes · Connections                   reconcile · config · logs
     ↓ Open Dashboard (⌘0)                ↓ a module
  console window          ← fleet mesh → home ⇧⌘H / modules (⌘1…⌘6) → inspector
                            ⌘K search · ⌘R refresh · ⌃⌘S sidebar · ⌥⌘I inspector
     ↓ chrome toggles
  tool panel              ← terminal ⇧⌘T · files ⇧⌘F · interpret ⇧⌘D
```

The popover has four sections. **Services** and **Agents** are the controller's
two halves. **Processes** is the machine's top five by CPU and top five by
memory, with pid, owner, state and usage — and, behind a config flag that is off
by default, an owner-only **End Process**. **Connections** is the network
administration layer: link state, default gateway, DNS, interfaces with their
addresses and subnets, VPN, Tailscale, plus copy / ping / traceroute, a sanitised
support bundle, and a footer that opens the router's admin console.

The dropdown lists the modules directly, so **Processes** is one gesture from
the menu bar rather than a window away. It is generated from the same
`ConsoleModule.allCases` the View menu is built from, by one builder, so the two
menus cannot come to disagree about what the modules are or which digit each
takes. **Network** is the exception: it is a popover section rather than a
module, so choosing it opens the popover on that section.

The six modules are **Overview** ⌘1 · **Processes** ⌘2 · **Storage** ⌘3 ·
**Services** ⌘4 · **Events** ⌘5 · **Launch Services** ⌘6. ⇧⌘H returns to Home,
the landing surface — it sits above the modules in the View menu but is not one
of them, which is why it takes a shifted key and leaves ⌘1…⌘n bound to exactly
the module indices however many there are.

The window resizes freely on both axes and goes full screen (⌃⌘F). It used to be
aspect-locked and capped at its opening size, on the argument that it is one
composition at a range of sizes rather than a canvas that stretches — but that
argument is about the *layout*, and the layout holds it unaided: the side
columns clamp between two rungs, the module column takes the remainder, and the
cards flow in an adaptive grid. What the lock actually did was make dragging one
edge move the other, and refuse to grow on a display with room to spare. Floors
on both axes are derived in `FleetCore/ConsoleLayout.swift`: the narrowest width
every column still fits at, and the shortest height that holds a module header
and one whole card.

Everything runs as the logged-in user. No root, no privileged helper, no network
listener, no telemetry.

## Build and install

Each build needs a fresh `FleetConsole.app` destination. The script refuses any
existing bundle, file or symlink and all Applications aliases; it never replaces
an app or stops a controller. For repeat builds, choose a new
`FLEETCONSOLE_OUTPUT_DIR` as shown in [docs/RELEASE.md](docs/RELEASE.md).

```bash
Scripts/build-app.sh release  # builds/signs build/FleetConsole.app only if absent
Scripts/notarize.sh           # submits to Apple and staples the ticket
Scripts/install-agent.sh      # registers fleetd with launchd (no sudo)
open build/FleetConsole.app   # starts the menu-bar app
ln -sf "$PWD/build/FleetConsole.app/Contents/Resources/bin/fleetctl" /usr/local/bin/fleetctl
```

`build-app.sh` signs with a Developer ID identity when the keychain has one —
hardened runtime, secure timestamp, inner binaries signed before the bundle (no
`--deep`). Without one it falls back to an ad-hoc signature, which is fine on the
machine that built it and useless anywhere else. **Signing is not enough on its
own**: until `notarize.sh` has run, Gatekeeper reports *Unnotarized Developer ID*
and refuses to open the app on any other Mac. Notarization needs a `notarytool`
keychain profile you create once with your own Apple ID; the script tells you the
command and refuses to prompt for a password itself.

`Scripts/install-agent.sh` writes a user LaunchAgent to `~/Library/LaunchAgents`
and loads it into `gui/$UID`. The bundled app also tries `SMAppService.agent`
first; that path needs a real signing identity, so the script is the supported
route for local builds. Either way **launchd** keeps the controller alive — the
menu-bar app never does.

## The three pieces

| | |
|---|---|
| **`fleetd`** | the controller. Launches, supervises, health-checks, reaps and reconciles. Keeps the SQLite registry and the append-only event log. Serves a `0600` Unix socket. |
| **`fleetctl`** | what agents call instead of spawning processes themselves. |
| **`FleetConsole.app`** | menu bar + popover + dashboard. A client and a controller UI — it never signals a process itself. |

## Using it

```bash
fleetctl launch --name api --owner claude --purpose "local API for triage" \
  --cwd ~/Workspace/hermes --port 8787 --lease 2h \
  --health-http http://127.0.0.1:8787/healthz -- python3 -m hermes.api

fleetctl list          # what is running, what is unmanaged, what needs attention
fleetctl renew <id> --lease 30m
fleetctl logs <id> --err
fleetctl events <id>   # the append-only timeline for one service
fleetctl stop <id>
fleetctl reconcile     # sweep for processes started outside the controller
fleetctl claim <pid>   # adopt a running process: owner, purpose, lease, timeline
fleetctl ignore <cmd>  # "this listener is expected" → allow-list in config.json
fleetctl prune         # drop old stopped/crashed records (never touches events)
```

See [docs/AGENTS.md](docs/AGENTS.md) for the rule agents must follow.

## What it refuses to do

- **Claim a service is healthy without evidence.** "PID exists", "port is
  listening", "host is reachable" and "health check passed" are four separate
  facts, shown separately. With no health check configured, the best state a
  service can reach is *Running (unverified)*.
- **Kill a process it did not start.** The *controller* signals only what
  `fleetctl launch` handed it; unmanaged processes get visibility and "Reveal in
  Activity Monitor", nothing else. **`claim` does not buy an exemption** — that
  is the whole design of the verb. Adopting a running process gets it an owner, a
  purpose, a lease, an event timeline and a row that is no longer labelled
  *unmanaged*; stop, restart, pause, resume, kill and the lease reaper all refuse
  a claimed record, on the wire and in the UI, which draws none of those controls
  for one. An expired claim is reported and left alone rather than reaped. Claiming
  buys visibility, not authority. This rule is unchanged, and it is narrower
  than it reads: the Processes section can send a SIGTERM **you** initiate, and
  only when all three of these hold — the process's uid is yours, the
  `ui.features.allowProcessTermination` flag is on (it is off by default), and
  the pid's start signature still matches the row you clicked. There is no
  escalation to SIGKILL, because the controller escalates for services it owns
  the consequences of and this is not one of them.
- **Signal a PID it has not re-verified.** Process start time is captured at
  launch and re-checked before every signal, so a recycled PID cannot be hit —
  including for the user-initiated SIGTERM above, which re-reads `lstart` inside
  the call rather than trusting the snapshot the alert was drawn from.
- **Reconfigure your network.** Every network probe and verb is read-only or
  clipboard-only. `ping` and `traceroute` observe a path; nothing sets one.
- **Invent VLAN topology.** The 802.1Q tag on a local interface is read from
  `ifconfig` and shown. A *segment* — its name, purpose, subnet — comes from a
  registered `VLANSource` or from nowhere, and with none registered no segment
  chrome renders at all.
- **Rewrite history.** SQLite triggers reject `UPDATE` and `DELETE` on the event
  table.
- **Invent a managed service from the UI.** Restart re-runs the argv recorded at
  launch and there is no field that makes up a new one; the controller only ever
  supervises what `fleetctl launch` handed it. This is narrower than it used to
  be — the window now has a real terminal in its chrome (below). That terminal is
  yours, not the controller's: nothing typed into it becomes a supervised
  service, and the controller still refuses to signal anything it did not start.
- **Depend on agents behaving.** Leases expire and processes get reaped whether
  or not the agent that asked for them still exists.

## The chrome tools

Three toggles in the console window's chrome, each opening a panel in the side
field. All three run as you, with no elevation and nothing new listening.

| | |
|---|---|
| **Terminal** ⇧⌘T | A real shell, in the working directory of whatever is selected. Backed by SwiftTerm — the project's only external dependency, taken on deliberately because a hand-rolled emulator cannot host a full-screen TUI honestly. |
| **Files** ⇧⌘F | [Yazi](https://github.com/sxyazi/yazi), spawned as a fixed argv with no shell in between. Absent binary means the panel says so; it never quietly degrades into a shell prompt. Achromatic on purpose — colour in this app is a status vocabulary — and themed per appearance: the panel background follows the system, so the light theme is generated from the dark one by `Scripts/make-yazi-light.sh` rather than kept as a second hand-edited copy. |
| **Interpret** ⇧⌘D | A local model, asked about what you are looking at. Runs through your own `orcs` wrapper as a one-shot process — this app never starts a server, binds a port, or manages a model. The prompt it assembles is inspectable, because an answer you cannot audit is not evidence. |

Panels are cell-quantized and only resize when the layout settles: a PTY hosting
a three-pane TUI gets one `SIGWINCH` per gesture, not one per animation frame.
Below 40×10 a panel says it is too narrow instead of drawing a mangled TUI.

## Layout

```
Sources/FleetCore              models · evidence · registry · socket · tailscale
Sources/fleetd                 launcher · supervisor · health · reconciler · devices
Sources/fleetctl               the CLI agents call
Sources/FleetConsoleApp/Design FleetKit — popover tokens · console window tokens
                               · chrome primitives (hairline, card, pip) · formatters
Sources/FleetConsoleApp/Probes network status · routing (gateway, DNS, interfaces)
                               · the VLAN adapter point · host resources (CPU/GPU/memory/SSD)
                               · reclaimable space · storage breakdown · process
                               inventory · host capabilities
Sources/FleetConsoleApp/Views  popover sections (Services, Agents, Processes,
                               Connections + network admin) · shared row primitives
Sources/FleetConsoleApp/Views/Console  the console window: fleet sidebar · modules
                               (overview, processes, storage, services, events,
                               launch services) · inspectors · charts · main menu
       …/Console/Chrome        home surface · the tool rail: surface contract
                               · grid quantization · resize coalescer
       …/Console/Terminal      SwiftTerm-backed shell and the Yazi file surface
       …/Console/Interpreter   the local-model panel and its prompt assembly
rust/fleet-proto               the controller protocol in Rust (the port seam)
rust/fleet-conformance         proves those types agree with the live Swift daemon
Scripts/design-audit.sh        checks the view layer against the design rules
Scripts/churn.sh               boots the live model and counts what republishes
docs/DESIGN-SYSTEM.md          the UI toolbox: tokens, components, rules
docs/RUNBOOKS.md               what a model is allowed to do, and why it is a closed list
docs/CLI.md                    the operations toolbox: every fleetctl verb
docs/PRODUCT-SPEC.md           screen-by-screen spec
docs/THREAT-MODEL.md           process leaks, unsafe stops, stale records, bypass
docs/AGENTS.md                 the contract for agents
docs/FREEMIUM.md               trial · key format · offline mint · Ouros path
docs/RUST-PORT.md              rustification candidates · GPUI candidacy · resize
AGENTS.md                      source of truth: composition, status, decisions
```

## Two toolboxes

**FleetKit** (`docs/DESIGN-SYSTEM.md`) — one type ramp, one metrics set, one status
vocabulary, and two row primitives (`FleetRowLabel`, `DisclosureRow`) that every
surface composes. Rows supply content, never chrome. Everything is drawn on one
substrate — a drifting spectral field under graph-paper ruling, with every card,
panel and popover floating on it as a plate: one hairline, a second pass 3pt down
and right, and a plotted label struck into its own top border.
`Scripts/design-audit.sh` checks the parts of that contract a script can check,
and `Scripts/surface-sheet.sh` renders all 42 surfaces to `build/design/surfaces`
in both appearances.

**fleetctl** (`docs/CLI.md`) — `launch · renew · stop · restart · list · show ·
agents · events · logs · ping · doctor · reconcile · ignore · prune · config`,
with `--json` on every read command and `doctor` for the whole install.

Data lives in `~/Library/Application Support/FleetConsole` (registry, config) and
`~/Library/Logs/FleetConsole` (daemon log, per-service stdout/stderr), all `0600`
inside `0700` directories.

## Configuration

`~/Library/Application Support/FleetConsole/config.json` holds tick intervals,
lease caps, the devices you want probed, and the allow-list of listeners that
should not be flagged as unmanaged. Edit it from the menu-bar dropdown
(**Edit Configuration**); the controller reloads it on request, and the app
re-reads the file the moment it changes — a `DispatchSource` on the containing
directory, not a poll, and on the directory rather than the file because an
atomic write replaces the inode.

### `ui` — what the app shows and what it is allowed to do

Every field has a default that is correct with no config file at all. The block
exists so a section can be turned **off**, not so one can be turned on.

```jsonc
"ui": {
  "sections":  { "services": true, "agents": true, "processes": true,
                 "network": true, "devices": true, "listening": true },
  "intervals": { "networkRefreshSec": 20, "processSampleSec": 4 },
  "features":  { "allowProcessTermination": false, "showAgentSpend": false },
  "consoles":  { "network": null, "vlan": null }
}
```

A section that is off is **absent**, not greyed. Intervals are clamped on read
(5 s / 2 s floors): a hand-edited `0` would otherwise mean "run `ps -Ao` over
every process on the machine in a tight loop". There were three intervals until
`routingRefreshSec` turned out to control nothing — routing is captured inside
the network probe's single pass, off the same hardware-port read, so it has
always run on `networkRefreshSec`; the key is gone rather than wired to a second
timer that would fork `netstat` and `scutil` again to produce a *less* coherent
picture. An old config.json that still names it loads unchanged. `consoles.network` defaults
to `http://<default gateway>` when unset, so the footer works on first launch;
`consoles.vlan` is the seam for a future VLAN admin console and renders only
alongside a registered `VLANSource`.

`allowProcessTermination` unlocks **End Process** on the Processes section. It is
off by default and it does not weaken the controller's rule — see
[docs/DESIGN-SYSTEM.md](docs/DESIGN-SYSTEM.md) for the three gates it holds.

`showAgentSpend` puts today's cost on each agent in the **Agents** section, read
out of each tool's own usage record — Claude Code and Codex transcripts priced
against a table in `AgentPricing`, opencode's own database read as-is. It is off
by default because the prices are written down rather than fetched, and an
unverified spend figure is worse than none: it will be believed. Compare a day
against a provider's bill, then turn it on.

**An agent that cannot be priced reads as `Unknown`, never as `$0.00`.** Gemini
CLI and aider publish no usage record at all, so no figure for them is honest;
a total that is short by an agent you can see is marked with a trailing `+`.

### `networkSegments` — naming your VLANs

A Mac on a **trunk** port reads its own 802.1Q tag off `ifconfig`. A Mac on an
**access** port — which is almost every Mac, and every Mac behind a firewall
doing the segmentation — never sees a tag at all: the switch strips it before the
frame reaches the NIC. All the host gets is an address, a subnet and a gateway.

FleetConsole will not close that gap by guessing. `10.10.40.0/24` looks like
VLAN 40, and an app that reads the third octet is right on your network and wrong
on the next one. So you say it, and the app attributes it to you:

```jsonc
"networkSegments": [
  { "tag": 40, "name": "Guest", "cidr": "10.10.40.0/24",
    "gateway": "10.10.40.1", "purpose": "isolated wireless" }
]
```

An interface is matched to a segment by tag when it has one, and otherwise by
**subnet containment** — so the Wi-Fi interface at `10.10.40.12/24` picks up
`VLAN 40 · Guest` even though nothing tagged ever reached it. The expanded row
says `Named by: config.json`, and a tag that did not come off the wire is marked
`(not carried on this link)`.

Empty by default: with nothing declared there is no Segments section and no VLAN
chrome anywhere. Delete the last entry and it all goes away again. A real
controller source (`VLANSource`) supersedes this list when one is registered.

Devices are seeded on first run with this machine and one peer — adjust
`tailscaleHost`, `localHost` and `probePort` to match your fleet.
