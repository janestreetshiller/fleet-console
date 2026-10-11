# fleetctl — the operations toolbox

The complete surface. Every read command accepts `--json`.

```
asking for a process      launch · renew · stop · restart · pause · resume · kill
looking at what is running list · show · agents · events · logs · ping · doctor
talking to the operator   notify · inbox · reply
housekeeping              reconcile · claim · ignore · prune · config
legacy compatibility     license (offline key mint; not required by MIT builds)
```

### `fleetctl pause <id|name>` / `resume`
SIGSTOP / SIGCONT to the process group, with the same verify-then-signal guard as
every other signal. A paused service **keeps its ports and its memory** — it is
stopped in the scheduler sense only, which is why it gets its own state rather
than being shown as stopped. The supervisor leaves paused services alone: no
health check is run against them and no lease decision is derived from silence.

### `fleetctl kill <id|name> [--reason "…"]`
SIGKILL immediately, no grace period. If the service is paused it is woken first —
a stopped process cannot die, so SIGKILL would otherwise just queue.

### `fleetctl notify --agent <a> --message "…" [--ask] [--problem] [--service <id>]`
Posts to the operator's mailbox. `--ask` marks it as needing a reply (and raises a
notification); `--problem` marks it as a failure. Plain status messages appear in
the popover and never interrupt.

### `fleetctl inbox [--agent <a>] [--unanswered] [--json]`
Reads the mailbox — this is how an agent collects its answer.

### `fleetctl reply <message-id> "…"`
Answers a message. Exactly once: a second attempt is refused.

---

## Asking for a process

### `fleetctl launch --name <n> --owner <agent> --purpose <why> [options] -- <cmd> [args…]`

The only way a process enters the registry. Returns the managed service record.

| Option | Default | |
|---|---|---|
| `--name` | *required* | what a human sees in the menu bar |
| `--owner` | *required* | which agent asked for it |
| `--purpose` | *required* | why it exists — answers "can I kill this?" later |
| `--cwd <path>` | current dir | project folder; must exist and be yours |
| `--port <n>` | — | repeatable; seeds the allowed-port budget |
| `--lease <dur>` | `1h` | time until the controller reaps it |
| `--max-runtime <dur>` | — | hard ceiling regardless of renewals |
| `--cpu-warn <pct>` / `--mem-warn <mb>` | — | budget warning thresholds |
| `--allow-port <n>` | `--port` values | repeatable; a listener outside this set is flagged |
| `--health-http <url>` | — | localhost only |
| `--health-tcp <host:port>` | — | |
| `--health-interval <dur>` / `--health-timeout <dur>` | `15s` / `4s` | |
| `--expect-status <n>` | `200` | |
| `--failure-threshold <n>` | `3` | consecutive failures before "unhealthy" |
| `--env KEY=VALUE` | — | repeatable; **values are never persisted** |
| `--json` | | print the record as JSON |

### `fleetctl renew <id|name> [--lease 30m]`
Extends the lease. Clamped to `maxLeaseSec` (default 12h).

### `fleetctl stop <id|name> [--reason "…"]`
Re-verifies the target (pid **and** recorded start time **and** process group),
then SIGTERM to the group, SIGKILL after the grace period.

### `fleetctl restart <id|name> [--reason "…"]`
Stops, waits for the group to actually die, re-runs the **recorded** argv.

---

## Looking at what is running

### `fleetctl list [--all] [--json]`
Managed services, unmanaged processes and the attention list. `--all` includes
stopped and crashed records.

### `fleetctl show <id|name> [--json]`
One service in full, including declared-vs-listening ports and whether a health
check has actually run.

### `fleetctl agents [--json]`
Ownership view: per agent, how many services are running, how many need attention,
which ports they hold, total CPU/memory, and when the next lease expires.

```
AGENT         RUNNING  ATTN  PORTS           CPU     MEM       NEXT LEASE
claude        2        —     :8931 :8932     0.0%    48 MB     in 2m
codex         1        —     —               0.0%    1 MB      in 2m
```

### `fleetctl events [<id|name>] [--limit 50] [--json]`
The append-only history — global, or for one service. An unknown id is an error,
never a silent fallback to the global log.

### `fleetctl logs <id|name> [--err] [--bytes 64000]`
Tail of captured stdout/stderr. Works for crashed services too — that is when you
need it most.

### `fleetctl ping`
Controller version, pid, uptime, last tick, last sweep.

### `fleetctl doctor`
Checks the whole install: socket present and `0600`, launchd agent loaded,
controller answering, supervisor ticking, reconciler sweeping, registry, config,
log directory, tailscale CLI, and current counts. If the controller does not
answer but the agent is loaded, it waits out launchd's restart throttle before
declaring a fault, and prints the job's last exit reason if it never comes back.
Unmanaged processes are reported informationally; only **leaked** ones (a process
that outlived its own record) count as a problem. Exit code 0 = healthy.

---

## Housekeeping

### `fleetctl reconcile`
Forces a sweep for listeners and dev-server-shaped processes outside the registry.

### `fleetctl claim <pid|unmanaged-id> [--name <s>] [--owner <a>] [--purpose <why>] [--lease 1h]`
Adopts an already-running process into the registry. It gets an owner, a purpose,
a lease, an event timeline and a row that is no longer labelled *unmanaged* — and
the controller still refuses to signal it.

That refusal is the point of the verb, not a limitation of it. A **launched**
service is one the controller started, so it owns the consequences of stopping
it; a **claimed** one was already running when the sweep found it. So `stop`,
`restart`, `pause`, `resume`, `kill` and the lease reaper all reject a claimed
record, the app draws none of those controls for one, and an expired claim is
reported and left alone rather than reaped. Claiming buys visibility, not
authority. Stop it where you started it.

The target is re-verified before adoption: an unmanaged id is `pid:hash(start
signature)`, and a pid recycled between the sweep and the command is refused by
the same comparison that guards every signal. A pid belonging to another user, a
pid already registered, and the controller's own process group are all refused.

Its uptime is the process's own, taken from `ps -o lstart`, not the moment it was
claimed — a claimed record that reset the clock would hide exactly how long a
leak had been running. Logs read as "(claimed, not launched — its output goes
wherever it was started)": its descriptors were wired up before we arrived, so
there is no log file here and never will be.

### `fleetctl ignore <command>`
"This listener is expected." Appends to `ignoredListenerCommands` in `config.json`
and writes an event — a reviewable act, not a hidden dismissal.

### `fleetctl prune [--older-than 1h]`
Drops stopped and crashed **service records**. The event history is append-only
and is never touched.

### `fleetctl config [--path | --reload]`
Prints the config, its path, or asks the controller to reload it.

### `fleetctl license --secret <s> [--date YYYY-MM-DD]`
Mints a licence key offline — the issuer half of `FLT1-…`. A store webhook or
the Ouros bar on the user's behalf shells out here, prints the key, and the
user pastes it into the app. `FLEET_LICENSE_SECRET` works instead of `--secret`.
See [FREEMIUM.md](FREEMIUM.md).

---

## Durations

`30s`, `15m`, `2h`, `1d`, or a plain number of seconds.

## Exit codes

`0` success · `1` rejected or not found · `69` controller unavailable
