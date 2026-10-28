# FleetConsole — Product Spec

A local-first operations console for one person. Menu-bar app + a launchd-managed
controller daemon that owns every agent-started background process on this Mac.

**Deployment target:** the operator's own Mac, with optional configured peers.
Everything runs as the logged-in user. No root, no admin helper, no network listeners.

Public source fixtures use synthetic identities and documentation-only addresses;
they do not identify a maintainer's machine or tailnet. Surface rendering still
uses local telemetry probes, so inspect generated captures before publishing them.

---

## 1. Object model

| Object | Owner | Storage |
|---|---|---|
| **Managed service** — a process launched *through* the controller | `fleetd` | SQLite `services` |
| **Event** — immutable fact about a service | `fleetd` | SQLite `events` (append-only) |
| **Unmanaged process** — a listener or dev-server-shaped process with no registry record | `fleetd` reconciler | SQLite `unmanaged` (cache of first/last seen) |
| **Device** — a machine you care about | `fleetd` | SQLite `devices` + `config.json` |
| **Network interface state** | menu-bar app | not persisted (live probe) |

### Evidence, not vibes

The single most important modelling rule: **four independent facts, never collapsed into one.**

| Pillar | How it is established | What it does *not* prove |
|---|---|---|
| `processExists` | `kill(pid, 0)` succeeds | that it is doing anything |
| `portListening` | pid appears in `lsof -iTCP -sTCP:LISTEN` | that the app behind it works |
| `reachable` | ICMP echo or TCP connect completes | that the service on it is healthy |
| `healthPassed` | configured HTTP/TCP health check returned the expected result | nothing beyond the check itself |

The UI renders these as four separate chips. A row is only "Healthy" when a health
check *ran* and *passed*. If no health check is configured, the best state a service
can reach is **Running (unverified)** — never "Healthy".

### Service states

`starting` → `running` → `healthy` / `degraded` / `unhealthy` → `expiring` → `expired` → `stopping` → `stopped` / `crashed`

Plus the non-service state **`unmanaged`** for reconciler findings.

Roll-up used by the menu-bar glyph, in precedence order:
`attention` (unhealthy, crashed, expired, budget breach, port violation) >
`unmanaged` > `degraded` > `healthy` > `idle`.

---

## 2. Screens

### 2.0 One menu-bar item, four sections

FleetConsole puts up exactly **one** status item. It carried two for a while —
Fleet and Connections — and five before that; each collapse merged a pair that
turned out to be one subject. `docs/DESIGN-SYSTEM.md` holds the argument and the
machine-checked list.

The item's popover has four sections (`FleetSection`), switchable in
`config.json` under `ui.sections`:

| Section | Question it answers |
|---|---|
| **Services** | "What is running, who owns it, and does anything need a decision?" A verdict line, needs-attention, then service rows that expand in place to evidence, CPU+memory sparklines and the safe actions (pause · restart · stop · kill). |
| **Agents** | "Is anyone waiting on me?" A profile card per agent — running now, track record, projects, recent services, messages — plus *waiting on you* with an inline reply box. |
| **Processes** | "What is this machine spending itself on?" Top five by CPU and top five by memory, with pid, owner, state and usage. Inspect opens the dashboard at that pid. **End Process** is owner-only, off by default, and re-verifies the pid's start signature before it signals. |
| **Connections** | "Am I connected, where do my packets go, and do my machines answer?" Unmanaged listening sockets · Internet · Ethernet · Wi-Fi · Tailscale · **default gateway · DNS · interfaces with addresses and subnets** · VPN · VLAN · Thunderbolt · exo · devices. Actions: copy an address, ping, traceroute, copy a sanitised support bundle. A footer opens the router's admin console. |

**Local tools.** The Services section also lists your own long-running tools —
declared in `config.json` as `knownServices`, matched by command line or port.

**VLAN.** A local 802.1Q interface shows its tag, read from `ifconfig`. Segment
information — names, purposes, subnets — requires a registered `VLANSource`;
with none, no segment chrome renders at all. See `Probes/VLANSource.swift`.

### 2.1 The status item (always visible)

Compact, one glance, no colour-only signalling (glyph changes shape too).

```
 ●  3          all managed services healthy, 3 running
 ▲  2          2 items need attention
 ◐  1·2        1 attention · 2 unmanaged
 ○             controller not running
```

- SF Symbol + count. Template-rendered so it obeys menu-bar tint.
- Tooltip: `3 managed · 2 unmanaged · fleetd up 4h12m`.
- Left click → popover. Right click → the dropdown: Open Dashboard ⌘0, the six
  console modules with their real ⌘-digits, Network, Run Reconciliation Sweep,
  Edit Configuration, Reveal Logs in Finder, Quit.

### 2.2 Popover — one section at a time

380pt wide. The segmented picker at the top is the whole navigation; each section
owns its own body and its own contextual actions in the header strip beside the
picker. Rows expand in place, so there is no "overview vs details" mode to choose
between — one less control, and the actions are always one click away.

This replaced a two-mode popover (**Overview** / **Details**) whose mode was
remembered between launches. Two modes over one dataset is a preference the app
was asking you to hold; sections over four datasets is navigation.

```
┌─ [Services 6 | Agents 3 | Processes | Network] ⟳ ⋯ ─┐
│ ✓ Nothing needs a decision                          │
│   6 services running · 5 unmanaged                  │
│ NEEDS ATTENTION                                   2 │
│ ▣ search failed its health check 6 times       12m  │
│ SERVICES                        6 managed · 5 unman.│
│ ▣ api    claude · local            :8787   2h 3m > │
│ ▣ web    claude · fleet-web         :5173     35m > │
│ + 9 more…                                           │
├─────────────────────────────────────────────────────┤
│ ● controller up 4h12m               Open Dashboard  │
└─────────────────────────────────────────────────────┘
```

Every list is capped and overflow is **stated** — `+ 9 more…`, which opens the
dashboard — rather than hidden below a scroll edge. Rows are fixed-height, so a
section's total height is bounded by construction and nothing can clip.

When the controller is down, Services hides the attention list entirely: the last
snapshot describes what *was* true, and presenting it as current would be exactly
the stale claim this app refuses to make.

Calm by default: nothing is expanded, nothing animates on a timer. The one moving
part is `StatusPip`, which breathes on the probe cadence and stills under Reduced
Motion.

**Processes** and **Connections** are specified in `docs/DESIGN-SYSTEM.md` under
their view names — `ProcessesContent` and `NetworkAdminSection` — because what is
interesting about both is where the numbers come from and what the app refuses to
claim about them, which is design-system material rather than layout.

### 2.3 Console window (three columns, ⌘K / ⌘R / ⌘1…⌘6 / ⎋)

Three-column `NavigationSplitView` in a unified-compact toolbar window (hidden
title, full-size content, controller status pill as a titlebar accessory):

- **Column 1 — fleet mesh.** "This Mac" pinned at the top with live CPU/RAM
  summary; below it the remote nodes with a health pip, an ICMP latency badge,
  and the path (tailnet/LAN + SSH probe port) each row is reached over. Footer:
  controller connectivity and internet state.
- **Column 2 — module.** A segmented picker in the toolbar (⌘1…⌘6):
  **Overview** (an analog dial per metric beside its trace — CPU wave + per-core
  grid, memory pressure, disk capacity over read/write throughput, GPU — laid out
  in a grid that flows to as many columns as the width allows, with the process
  map full width below),
  **Processes** (native `Table` with column sorting, scope filter, right-click
  menu), **Storage** (segmented APFS-style breakdown bar, squarified disk map
  of surveyed directories, volumes, reclaimable-space catalogue),
  **Services** (managed / unmanaged / agents), **Events** (the append-only
  log). Selecting a remote node replaces the module with that device's
  read-only detail (reachability evidence, SSH capabilities, its controller's
  services). Both heatmaps follow one rule: area is the quantity, colour is
  the category or the CPU tone, and the tail rolls into an "Other" tile rather
  than vanishing.
- **Column 3 — inspector**, a view of the current selection:
  - *Process* — identity (pid/ppid/pgid/user/start signature), activity (CPU,
    RSS, threads and priority via `proc_pidinfo`, CPU time), the process tree,
    listening ports and live connections, environment keys for managed services
    (keys only — threat model T6), and actions. Managed processes are signalled
    through the controller; everything else offers Sample / Copy PID / Reveal
    in Activity Monitor only. FleetConsole never kills a process it did not
    start, and the menu says why.
  - *Service* — evidence chips, lease, live resources, **placement verdicts**
    across the fleet (hard constraints: architecture, tools, memory, link
    quality), stderr tail, per-service timeline.
  - *Volume / segment* — capacity arithmetic, purgeable accounting, APFS local
    snapshots, I/O history; for bar segments, the basis of the number
    (measured where, or arithmetic of what).
  - *Device* — addressing, link quality (direct vs relayed, worst-sample RTT),
    last-reported load.

Search lives in the toolbar and is scoped per module (process: name, PID, user,
command, port; services: name, owner, purpose, port, PID; events: kind,
service, detail). ⎋ clears search, then the selection. A selection whose row
disappears from live data clears itself.

### 2.4 Confirmation sheets

Stop and Restart are the only destructive actions in the UI, and both require a sheet
that states the exact consequence and the evidence it is acting on:

```
Stop “api-service”?
PID 41823 (process group 41823), listening on :8787.
Started 2h11m ago by agent “claude” — purpose: “local API for inbox triage”.
SIGTERM, then SIGKILL after 10s if it does not exit.
                                   [ Cancel ]  [ Stop ]
```

Restart adds: `Ports :8787 will be released and re-bound.`
No confirmation is required for read-only actions (logs, reveal, refresh, open folder).

### 2.5 First launch — the welcome

Shown exactly once, persisted in `UserDefaults`. One borderless panel: a
one-sentence pitch, a live `RetroGauge` sweeping 0 → 78% → 12% (the instrument
a new user has not met yet, demonstrating itself), and three numbered steps.
Skippable from the first frame (Skip button, Escape). The option to suppress
it (`skipWelcomeAnimation`) is unlocked in the MIT source build. A context-menu
item replays it for support calls.

### 2.6 Source licence and feature access

The source is MIT-licensed (see `LICENSE`). Features are permanently unlocked in
the source build, including SMC sensors, welcome-skip, advanced heatmap filters
and reconciliation. No activation, purchase or trial is required. Historical
trial and offline `FLT1` key APIs remain for compatibility; they do not restrict
feature access. `FleetCore/License.swift` defines the current access policy.

---

## 3. The controller (`fleetd`) and the launcher (`fleetctl`)

### Contract

Agents **must not** spawn persistent processes. They call:

```bash
fleetctl launch \
  --name "api-service" --owner "claude" --purpose "local API for inbox triage" \
  --cwd ~/Workspace/api --port 8787 --lease 2h --max-runtime 8h \
  --health-http http://127.0.0.1:8787/healthz --cpu-warn 80 --mem-warn 1024 \
  -- python3 -m local.api --port 8787
```

`fleetctl` returns the **managed service record** as JSON (id, pid, ports, lease expiry).
The agent keeps that id and renews the lease (`fleetctl renew <id> --lease 30m`) while it
still needs the process. If it stops renewing — because it crashed, was interrupted, or
simply forgot — the lease runs out and `fleetd` reaps the process. **Cleanup does not
depend on the agent doing anything.**

### Responsibilities of `fleetd`

1. **Launch** — `posix_spawn` in a new session/process group, stdout+stderr to
   `~/Library/Logs/FleetConsole/<id>.{out,err}`, record everything before returning.
2. **Supervise** (default 5s tick) — liveness (`kill(pid,0)`), CPU/RSS sampling,
   listening ports per process group, lease countdown, max-runtime, budget thresholds.
3. **Health-check** (per-service interval) — HTTP GET expecting a status, or TCP connect.
4. **Reap** — at lease expiry or max runtime: `SIGTERM` to the process group, `SIGKILL`
   after a grace period, record `leaseExpired` + `stopped` with the exit status.
5. **Reconcile** (default 20s) — one `ps -Ao pid,pgid,…` + one `lsof -iTCP -sTCP:LISTEN`
   sweep; anything owned by this uid that is a listener or dev-server-shaped, and whose
   process group is not in the registry, is surfaced as **Unmanaged** with a reason.
6. **Serve** — newline-delimited JSON over a `0600` Unix socket, with `snapshot`,
   `subscribe` (server-push stream), `launch`, `renew`, `stop`, `restart`, `events`, `logs`.

`fleetd` is kept alive by **launchd** (`KeepAlive`, `RunAtLoad`), registered through
`SMAppService.agent` from the app bundle, with a plain `~/Library/LaunchAgents` fallback
for unsigned local builds. The menu-bar app never supervises it — if the app is not
running, leases still expire and abandoned processes still get reaped.

---

## 4. Real-time without rebuilding the UI

The app opens one `subscribe` connection. `fleetd` pushes a snapshot on every state
change and on each supervisor tick. The app diffs by stable `id` into `@Observable`
row models, so SwiftUI re-renders only the rows whose fields actually changed. Timers in
the UI are limited to a single 1 Hz clock used for lease countdown text.

---

## 5. Non-goals

- No arbitrary command entry in the UI. Restart re-executes the **recorded** argv only.
- No killing of processes FleetConsole did not launch.
- No root, no privileged helper, no `sudo`, no remote control of other machines.
- No telemetry, no network egress except the probes you configure.
