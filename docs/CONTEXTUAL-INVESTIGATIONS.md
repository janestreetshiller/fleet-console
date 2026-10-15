# Contextual investigations and compact Fleet navigation

Source candidate: branch `codex/fleet-context-actions-20261015`, based on `b1ae71e`.
This document records implementation and deferred acceptance separately.

## Baseline and containment

The installed `/Applications/FleetConsole.app/Contents/Info.plist` reports version
1.1.0, build 4 and executable `FleetConsole`. It contains no FleetSourceRevision
key. Matching its executable to this checkout remains unverified; the updater
must reconcile that before replacing the app. Current source was located at
`/Users/main/Metal/Code/Fleet/fleet-console` through the Fleet donor reference in
`/Users/main/Code/ouros-x/apps/desktop/ouros/docs/plugin-boundary-working-record.md`.

All changes were prepared in an isolated worktree. No builds, package installs,
test executions, app launches, UI automation, screenshots, model requests or
background pollers were run for this work. Ouros build 507 was not changed.
The native containment task `01a137a4-495f-7202-907c-5938b789c006` owns process
containment, runtime validation coordination and canonical app updating.

## Implemented source paths

- Dropdown: `FleetPopover` has intrinsic meter height, no tall body frame or
  section picker, and a small top-right dashboard button. `QuickView` preserves
  both 90-point dials, disk cells and network readouts; vertical meter padding
  changes from 44 to 16 points. The requested roughly half-height result needs
  measurement in the actual app; source dimensions do not establish that result.
- Navigation: sidebar destinations are Overview, Trends, Processes and Operations.
  Overview reuses the attention list, mailbox/reply flow and agent roster, and
  adds up to 100 persistent, reversible local Later reminders. These reminders
  do not start jobs. Operations retains Services, Network, Agents, Storage,
  Events, Launch Services and Account. Old menu routes/shortcuts remain valid.
- Trends: selectable CPU interval plus keyboard date controls, real process
  snapshots and controller agent/service observations joined by timestamps.
  Process history retains 120 captures of the top 24 by CPU and memory (at most
  48 rows/capture); controller history retains 120 snapshots, up to 32 sessions
  and 32 service associations each, at least four seconds apart. Existing probes
  supply the data: no additional collectors or polling timers. History is memory
  only, starts with this app run, and does not represent a complete census.
- Processes: Relationships, Table, Heatmap and Scatter views. The graph shows
  sampled parent/child links with up to six ancestors and twelve children;
  service-owner and detected-agent badges use actual registry/PID associations.
  It does not infer causal edges or job ancestry. Heatmap groups identify their
  heaviest process; the remainder remains informational. Scatter uses actual
  CPU/memory observations, selects the nearest memory coordinate and states
  what it selects. No synthetic attribution data is generated.

## Surface inventory and investigation actions

| Surface | Source hook | Status |
| --- | --- | --- |
| Dropdown CPU, memory, disk, network | QuickView instrument modifier | Implemented, runtime unverified |
| CPU/memory charts and core grid | OverviewModule primary card modifiers | Implemented; core grid uses CPU context |
| Disk/GPU/sensors/battery details | OverviewModule detail card modifiers | Implemented; each card shares its diagnostic context |
| Secondary metric glance | OverviewMetricGlance metric modifier | Implemented, runtime unverified |
| Full process table, all scopes | Native table primary action, Return and row context menu | Implemented, runtime unverified |
| Compact CPU/memory rankings | ProcessPopoverRow modifier | Retained source and actions; dropdown routes now open dashboard |
| Overview instrument process preview | OverviewProcessPreview row modifier | Implemented, reachable in All instruments |
| Process inspector and ancestry/children | Actions button and treeLine modifier | Implemented, runtime unverified |
| Unmanaged process rows and inspector | Reference modifier/button | Implemented; requires current inventory identity |
| Managed-service process inspector | Explicit investigation button | Implemented; services without a PID have no process action |
| Detected agent-session rows | Current-inventory reference modifier | Implemented, runtime unverified |
| Parent/child graph nodes | Shared modifier and inspector selection | Implemented, runtime unverified |
| Heatmap process groups | Signature-bound heaviest-process context/double-click/VoiceOver action | Implemented, runtime unverified |
| Scatter selected process | Shared modifier and inspector button | Implemented, runtime unverified |
| Historical process observations | Explicit keyboard-accessible Investigate button | Implemented; historical scope and original timestamp retained |

The shared modifier provides right-click “Investigate with agent”, double-click,
focused Return/Space, a visible focus outline and a named accessibility action.
Native table actions preserve table selection and its existing context verbs.
A group represents multiple processes and explicitly investigates its heaviest
member. Nonprocess storage heatmap tiles keep their existing Finder actions.

## Starter, entitlement and transport contract (source-review correction)

The first candidate `03076aa` incorrectly treated Fleet multi-device membership
as an inference gate and dispatched the starter to a CLI that requires explicit
loopback model setup. That path is superseded by the follow-up source correction.
No local agent executable is launched by contextual investigation.

`InvestigationRequest` encodes schema version, subject, kind, original observation
time, numeric values/units, bounded diagnostic context and process evidence.
The existing embedded SwiftTerm surface displays the JSON starter, availability
result and reply as an output-only investigation transcript. It preserves the
user's shell and scrollback; it never types into a live shell or executes provider
output. Escape/control characters and directional overrides are removed from
untrusted output before rendering. Concurrent investigation requests are refused.

Every surface requires the existing Fleet Ouros account session. That same
private bearer credential stays inside `OurosBilling`'s HTTPS transport; it is
never put in argv, environment, starter JSON or terminal output. A fresh
`GET /ouros/v1/models` must return a runnable catalog for this account. The model
comes from the server catalog, not a local grant. The final
`POST /v1/chat/completions` uses the existing Ouros Agent request contract and
again passes through server entitlement, usage reservation and settlement.
Fleet's `/hvy/v1/fleet-console/entitlement` response authorizes multi-device
membership only and is no longer used to grant inference. No account exceptions,
new subscription SKU, purchase, fallback endpoint or local model setup is added.

The request contains one system instruction and the selected evidence, with no
tools or function execution permissions. This provides remote analysis of the
snapshot; it does not provide live inspection, remediation or a background job.
The complete completion envelope must fit 16 KiB. Response collection is capped
at 64 KiB and reply text at 32 KiB. The model catalog preflight does not spend
inference usage. No network request or paid call was made during implementation.

An idempotency key is saved before dispatch. Ambiguous completion failures retain
the outstanding request ID across relaunch and block another investigation until
explicit receipt-review acknowledgement; the request is never automatically
replayed. Confirmed pre-dispatch refusals use the same classification as the
existing Ouros Agent client. Unknown 400/422 errors, 429, upstream errors and
transport failures remain uncertain. Response/rejection handling is source-only
and still needs isolated transport-fixture tests after coordination.

Current requests older than 30 seconds, future timestamps, absent samples and
missing/reused process identities are refused. Freshness and PID/start signature
are checked again after catalog verification, immediately before submission.
Unmanaged and session references require a matching command line in the current
inventory; that comparison stays local. These are inventory checks, not a fresh
kernel probe: an exit after capture remains possible. Historical requests retain
their original timestamp and explicit historical scope, and expire after one hour.

Raw argv, environment, usernames, paths, addresses, transcripts and log bodies are
excluded from process evidence. Executable basename is limited to 80 safe
characters; token/secret-looking labels are redacted. Ports cap at 16, metric
process context at five. Nonfinite metrics become unknown or fail serialization.
CPU/memory rankings and job associations are correlation, not demonstrated cause.
Clicking investigation changes no termination setting and grants no process,
service or file mutation tools. Existing destructive actions retain their policy.

## Source contract evidence

- Existing entitled gateway: `/Users/main/Code/ouros-md-landing/gateway/legacy-completion.mjs`
  handles `/ouros/v1/models` and `/v1/chat/completions`, filters the catalog by
  account entitlement, and forwards completions to the reservation/settlement route.
- Existing native caller: `/Users/main/Code/ouros-x/apps/desktop/ouros/Sources/OurosBar/EveChatSession.swift`,
  `completionPayload`, `beginGatewayCompletion` and `completionRejectedBeforeDispatch`.
- Multi-device-only membership contract: `/Users/main/Code/ouros-md-landing/gateway/fleet-console-billing.mjs`,
  `fleetConsoleOffer` and the `/hvy/v1/fleet-console/entitlement` handler.
- The source exists; deployed gateway behavior, Fleet-token scopes and end-to-end
  account interoperability have not been exercised. They must be checked with
  isolated fixtures before an authorized live acceptance action. A failed scope
  check must stay a refusal, not trigger credential borrowing or broader permissions.

## Exact Fleet provenance for the sole updater

- Canonical repository: `/Users/main/Metal/Code/Fleet/fleet-console`.
- Candidate worktree: `/Users/main/Documents/Codex/2026-10-15/task/fleet-context`.
- Baseline commit: `b1ae71e29a25853ab4843d3bc5fca0ca90ebae81`.
- Installed app: `/Applications/FleetConsole.app`, `com.fleetconsole.app`,
  version `1.1.0`, build `4`, executable `Contents/MacOS/FleetConsole`.
- Installed executable: 11,907,680 bytes, SHA-256
  `8a97b7da2c5a1e50788db5beb61bbee2d24fa0b8606da443b910bef1c42d8e1b`.
- Canonical checkout's built executable: 11,887,056 bytes, SHA-256
  `83d57490ea39e7230d3600b5ff6b96034fdd948ed4f39cf1e0c921f4264344a8`.
- `fleet-terminal-output` worktree's built executable SHA-256:
  `03720ca63d9919c3682045d5f508a04389d00f84381595eae9dec95b52a89ba1`.
- The installed plist has no embedded FleetSourceRevision. None of the checked
  artifacts matches its executable hash, so its exact source revision remains
  unproven. Hash differences alone do not identify the source delta.
- Fleet build 4 is a separate app and identity from Ouros X build 508. This work
  neither reconciles nor updates Ouros X. Frozen Ouros build 507 was untouched.

Proposed first low-load, non-UI validation command (not executed; needs the sole
owner's single-slot coordination):

```sh
xcrun swiftc -frontend -parse Sources/FleetConsoleApp/Investigation.swift Sources/FleetConsoleApp/OurosBilling.swift Sources/FleetConsoleApp/Views/Console/Terminal/TerminalPanel.swift
```

This is one syntax-only compiler process, without dependency resolution, code
generation, test execution or app launch. It cannot establish type correctness,
server entitlement or UI behavior. Focused single-job mocked-transport tests and
UI acceptance remain separately deferred.

## Acceptance checklist

- [x] Locate source and inventory meter/process surfaces through bounded reads.
- [x] Prepare isolated source edits; preserve canonical checkout and frozen Ouros snapshot.
- [x] Shared investigation request/action path and separate embedded terminal transcript source implemented.
- [x] Compact dropdown, consolidated navigation, relationship graph and real telemetry views source implemented.
- [x] `git diff --check` passed (source whitespace check only).
- [x] Add source regression cases for serialization, sensitive argv omission, bounds, unknown metrics and stale/historical timestamps.
- [ ] Compile and execute focused regression tests after containment owner authorizes validation.
- [ ] Reconcile installed build 4 executable with source revision before updating.
- [ ] Measure dropdown height, verify no clipped meters/network and compare existing styling.
- [ ] Exercise right-click, double-click, keyboard and VoiceOver on every inventory row.
- [ ] Verify signed-out, expired-session, runnable/nonrunnable catalog, server-denied entitlement, insufficient credit and account-change states with isolated fixtures, not paid requests.
- [ ] Verify gateway unavailable, response limits, preflight staleness, concurrent refusal and ambiguous-operation persistence/review states.
- [ ] Verify terminal output contains starter JSON and existing shell/scrollback survives transcript switching.
- [ ] Verify graph selection, PID reuse/exit, interval selection, retention caps and missing-history states.
- [ ] Obtain independent UI review of the candidate and let the sole updater owner package/install the approved result.
