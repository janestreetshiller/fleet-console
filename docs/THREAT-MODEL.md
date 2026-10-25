# FleetConsole — Threat Model

Scope: a single-user macOS workstation where autonomous coding agents can execute shell
commands as that user. The adversary is **not** primarily a remote attacker — it is
*entropy*: agents that leak processes, stale records that lie, and destructive buttons
that fire on bad evidence. Remote attack surface is minimised by construction (no
listeners, local socket only).

Trust boundaries:

```
  agent (untrusted-ish, same uid) ──fleetctl──▶ [ fleetd ] ◀──subscribe── menu-bar app
                                                   │
                                          SQLite (0600) · logs (0600)
```

`fleetd` and the agent run as the same uid, so this is **not** a security boundary in the
kernel sense — it is an *accountability* boundary. Anything relying on the agent being
unable to bypass it is called out explicitly below.

---

## T1 — Accidental process leaks (agent starts something and forgets it)

| | |
|---|---|
| **Impact** | Ports held, battery/CPU burned, port collisions on the next run, "why is 8787 taken" archaeology. |
| **Root cause** | Cleanup depends on the agent remembering. Agents die, get interrupted, or are context-truncated. |

**Mitigations**
- **Mandatory lease.** Every launch carries a TTL. `fleetd` reaps on expiry with no agent
  involvement. There is no "no lease" option; `--lease` defaults to 1h and is capped by
  `maxLeaseSec` in config.
- **Max runtime budget** — a hard ceiling independent of lease renewals, so a looping
  agent that renews forever still gets stopped.
- **Reap is a process-group kill**, so `npm run dev`-style shells that fork children do not
  leave orphans behind. Children are tracked via `pgid`, not just the direct pid.
- **Abandonment detection**: lease within 10% of expiry ⇒ state `expiring`, surfaced in
  *Needs attention* before it is killed, so a legitimately long job can be renewed
  manually from the dashboard.
- **Reconciler** catches the leak that escaped the model entirely (see T4).

**Residual risk** — a process that daemonises itself and escapes its process group.
Recorded as an event (`reap_incomplete`) when the pgid dies but a listener on the
declared port survives; it then shows up as Unmanaged rather than silently vanishing.

---

## T2 — Unsafe stop actions (killing the wrong thing)

| | |
|---|---|
| **Impact** | Killing an unrelated process that inherited a recycled PID; destroying an editor, a build, or the user's own long-running work. |
| **Root cause** | PIDs are recycled. A stale record + a fast-cycling PID space = a loaded gun. |

**Mitigations**
- **PID reuse guard.** Before any signal, `fleetd` re-verifies the target: the pid must
  still exist, its **process start time** must match the value recorded at launch
  (`ps -o lstart`), and its `pgid` must match. Any mismatch ⇒ no signal is sent, the
  record is marked `crashed`/`stale`, and a `pid_reuse_suspected` event is written.
- **Signal the process group, never `-1`, never pid 0.** Group id is validated to be
  a positive integer equal to the recorded pgid, and never equal to `fleetd`'s own pgid.
- **Graceful first.** `SIGTERM` → 10s grace → `SIGKILL`, each step recorded.
- **Confirmation sheets** state the pid, ports, owner, purpose and age — the evidence the
  action is based on — so a wrong target is visible before you click.
- **No kill for unmanaged processes.** The UI exposes only "Reveal in Activity Monitor".
  FleetConsole cannot be used to kill something it never started, which removes the entire
  class of "the dashboard nuked my editor".
- **`claim` does not widen that.** Adopting a running process into the registry
  (`fleetctl claim`, or the button on an unmanaged row) sets `ServiceRecord.claimed`, and
  `isSignallableByController` is false for the life of the record. Every signal path in
  the daemon consults it: the stop RPC (`ControllerRPC.swift`) and `restart` refuse with a
  message,
  `verifiedTarget` refuses before pause/resume/kill can resolve a pid, `beginStop` refuses
  as the invariant underneath both, and the lease reaper records the expiry and then leaves
  the process alone. The UI draws none of those controls for a claimed record rather than
  offering buttons that can only fail. So the registry can grow to cover a process the
  controller did not start — with an owner, a purpose, a lease and a timeline — without the
  set of things it may signal growing at all. Claiming buys visibility, not authority.
- **Claiming re-verifies like a signal does.** An `UnmanagedProcess.id` is
  `pid:hash(startSignature)`; a pid recycled between the reconcile sweep and the click is
  refused by the same start-time comparison as above, as are a pid owned by another uid, a
  pid already in the registry, and the controller's own process group.
- Stop/Restart are the only mutating verbs the UI aims at a **managed service**. No field
  invents an argv — Restart replays the one recorded at launch. The chrome's embedded
  terminal (**T7**) is a different surface and is not a path into the controller: nothing
  typed there becomes a supervised service, and the PID-reuse guard above still gates
  every signal the daemon sends.

**Residual risk** — the user restarts a service whose recorded argv is now wrong for the
project state. Bounded: argv is displayed verbatim in the restart sheet. A claimed record
cannot reach this at all: its argv came off `ps` rather than from a caller who declared it,
so `restart` refuses it on that ground as well as on the signalling one.

---

## T3 — Stale process records (the registry lies)

| | |
|---|---|
| **Impact** | Dashboard claims "healthy" for a dead process; a human trusts it and stops investigating. |

**Mitigations**
- **Every state is timestamped with its evidence.** The UI never renders a status without
  `checkedAt`. Anything older than 3 supervisor ticks renders as **Unknown (stale)** in
  grey, not as its last-known-good value.
- **Four-pillar evidence** (process / port / reachable / health) prevents the most common
  lie: "the pid exists, therefore it works". A running pid with a failing health check
  shows `unhealthy`, not `running`.
- **Health checks are never inferred.** If none is configured, the service can only reach
  *Running (unverified)*. "Healthy" requires a check that ran and passed.
- **Append-only event log** with SQLite triggers rejecting `UPDATE`/`DELETE`, so the
  history of what the daemon believed and when cannot be quietly rewritten — including by
  a future bug in FleetConsole itself.
- **Crash-consistent startup**: on boot, `fleetd` re-verifies every non-terminal record
  against live processes (pid + start-time match) before serving a snapshot, and writes
  `reconcile_missing` for records whose process is gone.
- Daemon liveness is itself displayed. If `fleetd` is down the app shows `○ controller not
  running` and greys the whole services section rather than showing the last snapshot as
  if it were current.

---

## T4 — Agents bypassing the launcher

| | |
|---|---|
| **Impact** | The console shows a tidy fiction while the real workload runs outside it. |
| **Reality check** | An agent with shell access **can** always spawn a process directly. This cannot be prevented at the same uid without a privileged enforcement layer, which is explicitly out of scope. So the goal is **detection and visibility**, not prevention. |

**Mitigations**
- **Reconciliation sweep** every 20s: all TCP listeners owned by this uid, plus processes
  whose argv matches dev-server shapes (`node`, `vite`, `next`, `python -m http.server`,
  `uvicorn`, `gunicorn`, `flask`, `rails`, `bun`, `deno`, `ng serve`, `webpack`…), joined
  against the registry by process group. Anything unmatched is surfaced as **Unmanaged**
  with the reason it was flagged, its full command line, and first-seen time.
- **Unmanaged is a first-class state**, not a footnote. Two cases interrupt you:
  a process that **leaked** (it outlived a record we created — the strongest possible
  evidence of a cleanup failure) and one that is **new** (first seen within
  `unmanagedGraceSec`, default 15 min). Everything else stays permanently visible in
  the Services list and the dashboard's Unmanaged view but stops raising an alert.
  This is a deliberate trade: an alert list that is permanently full of your own
  known-good daemons is an alert list you stop reading, and then a real bypass
  arrives into a panel nobody looks at. Detection is unchanged — only the
  interruption is rate-limited by age.
- **One-click allow-listing** (*This is expected*, or `fleetctl ignore <command>`)
  appends to `ignoredListenerCommands` in `config.json` and writes an event. There is
  no way to silence a finding without leaving a reviewable trace.
- **Allow-list, not deny-list, for "boring" listeners** (`rapportd`, `Spotify`, `Raycast`,
  `ARDAgent`, Docker, IDEs…) lives in `config.json`. Adding an entry is an explicit,
  reviewable act; an unknown listener always shows up.
- **Port-ownership violations**: a managed service listening on a port outside its
  `allowedPorts` is flagged (`port_violation`) but *not* killed — the flag is the point.
- **Ergonomics as enforcement.** The realistic control is making the sanctioned path the
  easy one: one `fleetctl launch` line, logs captured, restart for free. Agent
  instructions (`docs/AGENTS.md`) state the rule; the reconciler verifies compliance.

**Residual risk** — a determined or badly-prompted agent can `nohup` something with no
listener and a non-matching argv. It will be invisible until it binds a port. Accepted,
and stated here rather than papered over.

---

## T5 — Local IPC abuse

The socket is the only control channel and it can launch processes.

- Path `~/Library/Application Support/FleetConsole/fleetd.sock`, created `0600` inside a
  `0700` directory, `umask` set before `bind`.
- **Peer credential check**: `getsockopt(LOCAL_PEERCRED)` on every accepted connection;
  the peer euid must equal the daemon's euid or the connection is closed and a
  `rejected_peer` event is written.
- **No network socket, ever.** No TCP bind, no localhost port. Nothing to scan, nothing to
  reach from another host, including over Tailscale.
- **Launch requests are bounded**: cwd must exist and be a directory the user owns; argv
  must be non-empty; the executable is resolved and must be executable; environment is
  the daemon's own plus an explicit allow-list of passed keys; lease and budgets are
  clamped to configured maxima. Rejections are recorded as events.
- Same-uid processes can still talk to the socket — again, accountability not isolation.
  The mitigation is that everything that happens through it is logged immutably.

---

## T6 — Data at rest and secret leakage

- Registry, config and logs live under the user's home, `0600`/`0700`, never in `/tmp`.
- Environment values passed at launch are **not** stored in the registry — only the keys
  are — so tokens do not end up in an append-only database.
- Captured stdout/stderr **can** contain secrets. Log files are `0600`, are never sent
  anywhere, and the inspector's log pane is read-only tail with no export button.
- Terminal scrollback and assembled interpreter prompts are **not** covered by the
  guarantees above — they live in the app's memory, not in a `0600` file. See T7.
- Outbound traffic includes configured health checks and device probes. Optional
  Ouros account and subscription actions use HTTPS to `ouros.md`; browser checkout
  and subscription management use Stripe. Opening Devices while signed out stays
  local; an explicit billing action starts the offers or account request. Connected
  accounts refresh their subscription when Devices opens or the app becomes active.
  Account tokens stay in macOS Keychain and accompany authenticated Ouros requests.
  Analytics, crash reporting and automatic update services are absent.

---

## T7 — The embedded terminal, Yazi, and the local interpreter

| | |
|---|---|
| **Impact** | The window can now execute arbitrary commands as this user. Anything able to drive the GUI gets a shell instead of two buttons. |
| **What changed** | This document used to claim the UI "can never become a remote shell". That was a real guarantee and it has been **deliberately spent** to gain an integrated terminal, a Yazi file surface, and a local-model panel. It is recorded here rather than quietly dropped. |

**Why it is defensible**

The adversary model was never a remote attacker (see the scope note at the top) and
defending against code execution as this user is already explicitly out of scope. T4's own
reality check states that an agent with shell access can always spawn a process directly.
So the terminal hands the *operator* a capability the agents on this machine already had.
It does not lower a kernel boundary, because there was never one to lower — `fleetd` and
the agent share a uid, and this was always an accountability boundary.

**Mitigations**

- **No elevation, of any kind.** Runs as the logged-in user. No setuid path, no
  `SMJobBless` helper, no authorization prompt, no root. Identical uid to everything else.
- **No new listener.** A PTY is not a socket. A tool panel spawns its child as a one-shot
  child process and never starts a server, binds a port, or manages a model lifecycle, so
  T5's "no network socket, ever" is unchanged and remains true.
- **Yazi is a fixed argv with no shell interposed.** A missing binary renders an
  unavailable state; it never degrades into a shell prompt, because a file browser that
  silently becomes a command line is the kind of dishonest surface this project refuses.
- **The terminal is not a control channel.** It cannot register, signal or mutate a managed
  service except by invoking `fleetctl` — which goes through the same socket, the same
  `LOCAL_PEERCRED` check and the same bounded-launch validation as any other client, and
  is logged immutably like any other client.
- **Explicit agent sessions, not inferred authority.** Fixer handoffs launch the
  resolved executable with fixed argument arrays in distinct PTYs, never by
  typing a command into a running shell or another agent. The four-session cap
  refuses new work rather than evicting a live child. Generic commands are
  accepted only in Shell. Stop is confirmed for the selected app-owned process
  group. A waitable-child check gates the initial signal even when SwiftTerm's
  I/O flag says stopped; child and group identity are checked again before
  escalation after two seconds. Natural exit callbacks release ownership even
  when SwiftTerm has not yet cleared its I/O flag. The session remains stopping
  during cleanup. App termination signals all groups first, then joins pending
  cleanup (including jobs whose session has closed) before exiting; UI completions
  do not block that join. Escaped/daemonized jobs, and descendants outliving an
  already-reaped group leader, are not supervised by this path; losing a reservable
  leader identity does not authorize signalling a potentially reused group. It is not controller signalling and does not roll back edits or guarantee
  provider cancellation. External agents retain their own permissions; the
  bundled Fleet Agent remains read-only. No account token is added to argv/env.
- **Suggestions do not execute.** Up to eight options use bounded, recent local
  event counts, not global statistical claims. Saved requests and session details
  share those options; unknown evidence grants no signalling authority. Findings
  and event text remain untrusted data, not instructions. Request files are
  created exclusively with mode `0600`, and a write failure prevents dispatch.
  Claimed records are labelled observation-only and never choose a project cwd
  for a handoff. Embedded newlines/control characters are escaped in report
  values. Unattributable unmanaged events are never merged across processes.
- **Paid cancellation is not a refund.** Stop waiting/window close cancels the
  investigation task. A cancellation check before paid dispatch prevents a
  stopped catalog lookup from becoming an analysis request. Once dispatched,
  its saved unconfirmed identity remains available for receipt review; no blind retry.
- **The interpreter's prompt is inspectable** before and alongside the answer. A local
  model's output is only usable as evidence if you can see what it was told.

**Residual risk — four, none of them papered over**

1. **The terminal is unaudited.** The event log records what the *controller* did, not what
   you typed. A shell in the window sits outside the accountability boundary this whole
   project is built on. Accepted because the operator is the same principal that already
   has shell access — but it is now the largest hole in the immutable-history story, and
   it is the first thing to revisit if this app ever grows a second user.
2. **Scrollback holds whatever it holds.** Secrets echoed into the terminal live in the
   app's memory and are not covered by T6's `0600` files. Nothing persists it to disk, so
   it dies with the window.
3. **Evidence can contain secrets, and evidence is what the interpreter sends.** The
   assembled prompt is built from service state, events and captured output, which T6
   already warns can contain tokens. It goes to a local child process with no network
   egress — but it does cross into a process this app does not control.
4. **Third-party code now runs in-process.** SwiftTerm is the app bundle's first external
   dependency, and its job is parsing untrusted byte streams — terminal escape sequences
   emitted by whatever you run. That is a genuine parsing surface, in-process, signed as
   part of the app and inheriting its entitlements. The mitigation is that it is a widely
   used implementation rather than one we wrote; the risk is that it is no longer only our
   code in the bundle.

---

## Deliberately out of scope

- Defending against an attacker who already has code execution as this user.
- Multi-user or shared-machine deployments.
- Managing processes on remote machines (devices are *observed*, never controlled).
- Any privileged (root) component. Every requirement above is satisfiable at user level,
  so a `SMAppService.daemon` + `SMJobBless` helper would add attack surface for nothing.
