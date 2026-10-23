# Release notes

## 1.2.0 — 2026-10-23

- Preserve the installed metric investigation menu and consolidated Operations
  workspace, with account-backed transport and isolated development credentials.
- Add direct menu access to Needs Attention, Agents with waiting-reply counts,
  and Help with bundle-aware fleetctl setup. Keep the existing dashboard
  shortcuts and controller actions.
- Correct fleetctl help and its guide to name the commands that support JSON
  output, and document read-only offline event history.
- Replace the obsolete Rust-port assessment with the existing GPUI prototype's
  actual scope and required verification. Prepare plain-language app/CLI copy.
- Restore Rust workspace builds using pinned published GPUI 0.2.2 instead of
  a removed local checkout. Make the GPUI prototype's missing integrations
  explicit, bound its diagnostic history and fix Unicode label truncation.

App bundle: 1.2.0 (6), arm64. The existing controller protocol remains 1.1.0.

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
- **Local proposals.** `propose` and its `ask` alias run a read-only, serialized
  loop against an explicitly configured, already running loopback endpoint.
  There is no default RX connection or model startup. Memory admission, byte
  limits, and an overall deadline bound the work. Bundling the binary does not
  select it as the fixer or register another resident launch job.
- **Metered billing through Ouros.** Every turn appends one HMAC-signed
  `FLTA-` record (agent, UTC period, model, input/output tokens, turns) to
  `<support>/agent-billing/meter-ledger.txt`, readable offline by the Ouros
  bar; invalid signatures are counted and excluded, never summed. Same
  offline-HMAC family as `FLT1` license keys, so a mint and a bill validate
  with the same machinery.
- **Verification.** 34 Rust tests (meter signing/tampering, knowledge
  classifications, schema byte-stability and pin, MCP protocol, engine loop
  with usage accounting), `cargo clippy` clean for the new crate, and a
  passive `self-check` for the pinned hash, live controller, and configuration;
  it performs no model inference.

Controller version string: `fleetd 1.1.0`. App bundle:
`CFBundleShortVersionString 1.1.0`.

## 1.0.0 — initial release

Menu-bar console, launchd controller daemon, CLI, freemium seam, Rust
protocol port with live conformance.
