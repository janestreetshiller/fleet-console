# Operating Fleet-managed services

Repository development follows [the development contract](../AGENTS.md). This
reference covers agents using FleetConsole to manage background work. The daemon
and protocol enforce ownership and process identity; prose is not a sandbox.

- Launch managed work through `fleetctl launch --name … --owner … --purpose …
  --lease … -- PROGRAM ARG…`. Set an appropriate working directory, expected
  ports and health check when needed; see [the CLI reference](CLI.md).
- Read `fleetctl list`, `show <id>`, `logs <id>` and `events <id>` before acting.
  Use supported `--json` output for integrations. Process existence alone does
  not establish application health.
- Renew a needed lease with `fleetctl renew <id> --lease 30m`; stop your launched
  service with `fleetctl stop <id>` when its work ends. Running services expire;
  paused services retain resources and defer expiry cleanup until resumed.
- `fleetctl claim <pid>` records ownership and a lease for visibility. It does
  not grant stop, restart, pause, kill or reap authority over that process.
  Preserve the controller's start-identity recheck before signalling a launched
  service; never replace it with a bare PID kill or an agent-side registry.
- Optional user-initiated **End Process** is a separate, owner-only control,
  disabled by default. Its existence does not authorize an agent to terminate
  arbitrary observed or remote processes. Linked-device process views are
  read-only. See [the threat model](THREAT-MODEL.md).
- Use `fleetctl doctor` to inspect controller connectivity and local state.
  A development build does not authorize installing or restarting the user's
  controller, modifying live registry data, or signalling unrelated work.

Consult [runbooks](RUNBOOKS.md) when changing typed diagnosis/action behavior;
their approval and target limits are product safeguards. Historical roadmap
statements in runbooks do not assign implementation work to every agent task.
