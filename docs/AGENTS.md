# Rules for agents

**Do not start persistent background processes directly.**

No `&`, no `nohup`, no `screen`, no `launchctl`, no detached `Popen`. Anything that
outlives the command you are running goes through the controller.

## Ask for a process instead

```bash
fleetctl launch \
  --name "hermes-api" \
  --owner "claude" \
  --purpose "local API the inbox triage task queries" \
  --cwd ~/Workspace/hermes \
  --port 8787 \
  --lease 2h \
  --max-runtime 8h \
  --health-http http://127.0.0.1:8787/healthz \
  --json \
  -- python3 -m hermes.api --port 8787
```

You get back a managed service record:

```json
{
  "id": "33368D95-2CF9-41D3-A9FE-BF5EEA7433DC",
  "pid": 37978,
  "leaseExpiresAt": 1785123456,
  "stdoutPath": "/Users/…/Library/Logs/FleetConsole/services/33368D95….out"
}
```

Keep the `id`. That is your handle.

## While you still need it

```bash
fleetctl renew <id> --lease 30m
```

## When you are done

```bash
fleetctl stop <id> --reason "task finished"
```

## If you forget

Nothing breaks. The lease runs out, the controller sends SIGTERM to the whole
process group, then SIGKILL, and records why. **Cleanup never depends on you
remembering** — that is the entire point of the design.

## What you must supply, and why

| Flag | Why it is mandatory |
|---|---|
| `--name` | so a human scanning the menu bar knows what it is |
| `--owner` | so a leaked process can be traced back to the agent that asked for it |
| `--purpose` | so "can I kill this?" has an answer six hours later |
| `--cwd` | so the console can open the project folder |

`--port` is not mandatory but you should give it: it lets the controller tell your
service's listener apart from a stray one, and it seeds the allowed-port budget.

## Health checks

If your service has a health endpoint, pass `--health-http`. Without one, the
console can only ever report **Running (unverified)** — it will not claim your
service is healthy on the strength of a live PID, because that is not evidence.

HTTP health checks must target localhost. The controller is not a general-purpose
outbound HTTP client.

## Talking to the operator

You have a mailbox. Use it instead of printing something important into a log
nobody is reading.

```bash
# Just saying what happened — appears in the Agents item, never interrupts.
fleetctl notify --agent claude --message "Reindex finished, 41k docs"

# You need a decision before you can continue. Raises a notification.
fleetctl notify --agent claude --ask \
  --message "Migration 0042 drops the legacy sessions table. Proceed?"

# Something broke and you have stopped. Also raises a notification.
fleetctl notify --agent claude --problem --message "Cannot reach staging DB"

# Collect your answer.
fleetctl inbox --agent claude --unanswered --json
```

`--ask` messages sit in **Waiting on you** until answered. Poll `inbox` rather
than blocking, and do not re-post the same question every few seconds: the
mailbox is append-only, so a loop leaves a permanent record of the loop.

## Things you cannot do through the controller

- Run something as root, or with elevated privileges.
- Start a process outside a directory you own.
- Kill a process the controller did not start.
- Hold a lease forever (`--lease` is clamped to `maxLeaseSec`, default 12h).

## If you bypass this

A reconciliation sweep runs every 20 seconds. Any listener owned by your user
that is not in the registry, and any dev-server-shaped process, is surfaced in the
console as **Unmanaged**, with its full command line and the time it first
appeared. Bypassing the launcher does not hide the process; it just removes the
owner, the purpose, the logs, and the automatic cleanup.

`fleetctl claim <pid>` files an already-running process under an owner, a purpose
and a lease, which gets back the timeline and stops it being flagged. It does
**not** get back the cleanup: the controller will not signal a process it did not
start, so a claimed process is never reaped and stopping it stays yours. Claim is
for something that was already running before you got here — not a way to launch
first and register afterwards. Ask for the process properly and you get the whole
contract; claim it and you get the half that can be honestly reconstructed after
the fact.
