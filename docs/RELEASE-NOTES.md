# Release notes

## 1.1.0 — the resident agent

`fleet-agent`: a dedicated operations and routing agent that lives beside the
controller and helps with all things memory and process, with metered usage
billed through Ouros. An rx-basis component specialized for console residency.

- **Typed tools, never raw shell.** Fifteen tools over the `fleetd` socket:
  snapshot, ps, memory ranking, specialist memory advice, logs, events,
  launch/stop/restart/pause/resume/kill, renew, reconcile, operator mailbox.
  Mutating tools require `confirm:true` and a reason recorded in the
  append-only event log. Unmanaged processes are reported, never signalled.
- **Specialist memory knowledge.** Memory-trend classification
  (Climbing/Creeping/Oscillating/Steady) over each service's history window,
  process-memory triage, macOS pressure verdicts from compressor/swap
  counters, and a routing rank where unanswered operator mail outranks every
  technical finding. See `docs/AGENT.md`.
- **MCP stdio server.** Hosts (rx harnesses, editors, agent frameworks) drive
  the same tool surface over JSON-RPC 2.0 with a byte-stable, hash-pinned
  `tools/list` and fail-closed `tools/call` that names the socket when the
  controller is down.
- **Local engine.** The `ask` command runs a bounded tool-call loop on the
  machine's local inference (`qwen3.5-9b-local` at llama-server), loopback
  pinned — the model endpoint cannot be pointed at the network.
- **Metered billing through Ouros.** Every turn appends one HMAC-signed
  `FLTA-` record (agent, UTC period, model, input/output tokens, turns) to
  `<support>/agent-billing/meter-ledger.txt`, readable offline by the Ouros
  bar; invalid signatures are counted and excluded, never summed. Same
  offline-HMAC family as `FLT1` license keys, so a mint and a bill validate
  with the same machinery.
- **Verification.** 34 Rust tests (meter signing/tampering, knowledge
  classifications, schema byte-stability and pin, MCP protocol, engine loop
  with usage accounting), `cargo clippy` clean for the new crate, and a
  `self-check` that proves the pinned hash, the live controller and the live
  model in one command.

Controller version string: `fleetd 1.1.0`. App bundle:
`CFBundleShortVersionString 1.1.0`.

## 1.0.0 — initial release

Menu-bar console, launchd controller daemon, CLI, freemium seam, Rust
protocol port with live conformance.
