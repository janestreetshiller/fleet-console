# fleet-agent — the resident operations agent

The console's resident agent: a dedicated operations and routing agent that
lives beside the `fleetd` controller and helps with all things memory and
process, with metered usage billed through Ouros.

It is an rx-basis component, specialized for console residency:

- **Typed tools over the controller socket, never raw shell.** Every
  capability is one `fleetd` RPC (`fleet-proto`), so the controller stays the
  single owner of process lifecycle — the same rule `docs/RUNBOOKS.md`
  already imposes on agents. There is no `bash` tool and cannot be one.
- **Fail-closed surfaces.** A missing daemon produces a per-call error naming
  the socket path, and writes zero records. A surface that fabricates success
  over a dead socket is the defect class this codebase keeps removing.
- **Byte-stable schemas.** The MCP `tools/list` payload is a module literal,
  canonically serialized, with a pinned `SCHEMA_SHA256` asserted by tests —
  a drifting schema invalidates host prompt caches, which is the whole reason
  it is pinned.
- **Metered, signed, local.** Every agent turn appends one HMAC-signed record
  to a local ledger the Ouros bar can read; no cloud, no key, no telemetry —
  the same locality argument as `docs/FREEMIUM.md`.

## What it knows

The specialist layer (`knowledge.rs`) is what separates it from a script:

- **Memory trends.** A least-squares slope over a service's 40-sample
  `memHistory` window classifies resident memory as Climbing, Creeping,
  Oscillating or Steady. A sustained climb is a leak *candidate*; one big
  sample is usually a legitimate one-off. A trend outranks an absolute
  number.
- **Process memory triage.** Heavy (>1 GB), normal, light — each with the
  honest next step, including "check whether this is its documented behavior
  before stopping anything".
- **System pressure.** macOS pressure is read from compressor and swap
  activity, not a free-memory figure; cached pages leaving memory is not
  pressure. Healthy / Elevated / Critical with the thresholds the console's
  own telemetry uses.
- **Routing rank.** Unanswered operator mail outranks every technical finding;
  a leak candidate outranks a big-but-steady process.

## Commands

```bash
cargo build -p fleet-agent          # binary: rust/target/debug/fleet-agent
fleet-agent serve                   # MCP stdio server (JSON-RPC 2.0)
fleet-agent ask "what's eating memory?"
fleet-agent ask --json "…"          # machine-readable turn result
fleet-agent meter                   # signed ledger totals (default 7 days)
fleet-agent meter --days 30
fleet-agent self-check              # schema hash, daemon, model health
```

Environment: `FLEET_AGENT_LLM_URL` (default `http://127.0.0.1:53144`),
`FLEET_AGENT_MODEL` (default `qwen3.5-9b-local`), `FLEET_AGENT_LEDGER`
(default `<support>/agent-billing/meter-ledger.txt`). The model endpoint is
validated to be loopback — the resident agent cannot be pointed at the
network by environment variable alone.

## Tools

Read-only: `fleet_snapshot`, `fleet_ps`, `fleet_top_memory`,
`fleet_mem_advice`, `fleet_logs`, `fleet_events`.

Mutating (require `confirm:true`, and a `reason` recorded in the append-only
event log): `fleet_launch`, `fleet_stop`, `fleet_restart`, `fleet_pause`,
`fleet_resume`, `fleet_kill`, `fleet_reconcile`.

Ungated state changes: `fleet_renew` (extends a lease; mutates controller
state, not processes), `fleet_message` (posts to the operator mailbox).

Unmanaged processes are reported but never signalled — the controller only
signals what it started, so no tool offers to kill one.

## Metered billing through Ouros

Every turn appends `FLTA-<base32 payload>.<base32 HMAC-SHA256>` to the
ledger, where the payload is `v1|agent|period|model|input|output|turns` and
the signature is HMAC-SHA256 with the same vendor-secret family as `FLT1`
license keys. `FLTB` can change everything after the dash without breaking
old records.

The Ouros bar (or a store webhook) totals the ledger offline:
`fleet-agent meter` is the reference reader. Invalid signatures are counted
and excluded, never silently summed.

## Verification

`cargo test -p fleet-agent` — 34 tests: meter signing/tampering/ledger,
knowledge classifications, byte-stability and the pinned schema hash, MCP
stdio protocol (initialize/list/call/notification/fail-closed), engine loop
(scripted model, tool dispatch, iteration bound, usage accounting).

`fleet-agent self-check` proves the live wiring: pinned hash, real fleetd
round trip, real model round trip.
