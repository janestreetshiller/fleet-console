# The contract for agents

Follow [/Users/main/AGENTS.md](/Users/main/AGENTS.md), the canonical working agreement. This file adds scoped project facts.

FleetConsole exists because agents start background processes and forget them.
See [the project contract](../AGENTS.md). This file describes Fleet-managed operations: what a client does instead of forking and hoping, and
what the controller will and will not do about it. The reconciler detects selected
unmanaged listeners/processes using filtered heuristics; the controller applies
ownership, lease and process-identity safeguards (see `THREAT-MODEL.md`). Neither
mechanism enforces arbitrary agent-policy prose.

## Do

- **Launch through the CLI.** `fleetctl launch --name … --owner … --purpose …
  --lease … -- python3 -m hermes.api`. The controller supervises what only the CLI
  hands it.
- **Set a lease, then renew it.** `fleetctl renew <id> --lease 30m`. A lease
  that expires is reaped whether or not the agent still exists — that is the
  design, not a bug.
- **Read before acting.** `fleetctl list`, `fleetctl show <id>`, `fleetctl
  logs <id>`, `fleetctl events <id>`. Every read command takes `--json`.
- **Take what you need, stop what you don't.** `fleetctl stop <id>` when the
  work is done. Stopped and crashed records are pruned with `fleetctl prune`.
- **Claim, don't squat.** Adopting a running process is `fleetctl claim <pid>`:
  it files the process under an owner and a lease. Claimed processes get
  visibility only — stop/restart/kill still refuse a claimed record, on the
  wire and in the UI.

## Don't

- **Don't launch Fleet-managed services outside fleetctl.** A process the controller did
  not start is *unmanaged*: visible, listed, and nothing more.
- **Don't signal other people's processes.** Only the controller signals, and
  only what `fleetctl launch` handed it. A recycled PID is never hit — start
  time is re-checked before every signal.
- **Don't write your own pid file or port registry.** `fleetctl` and the
  controller own those. An agent-side registry lies within a week.
- **Don't keep network tools open you don't need.** A dev server left listening
  after the task is an unmanaged process the reconciler will flag.

## If you're unsure

`fleetctl doctor` checks the whole install: daemon answering, supervisor
ticking, registry, config, socket permissions. Run it before assuming the
problem is fleetd.
