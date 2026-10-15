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

## Starter and safety contract

`InvestigationRequest` encodes schema version, subject, kind, actual observation
time, numeric values/units, diagnostic context and bounded process evidence.
JSONEncoder escapes controls and shell syntax is never evaluated: the bundled
`fleet-agent` launches directly with argv `propose`, starter in a separate PTY
inside FleetConsole. The terminal displays that same starter. It never types
into, restarts or terminates an existing shell or agent session. Concurrent
investigation requests are refused until the previous session exits; normal
terminal commands are refused while the investigation surface is selected.

Every surface uses the existing `OurosBilling.signedIn` and `active` checks;
no account IDs or customer exceptions are hardcoded. Gate checks run before
serialization/dispatch and again at the terminal observer. The current billing
contract exposes active account membership through the existing multi-device
entitlement response; it does not expose a distinct agent entitlement. This
change grants no cloud-agent SKU or paid inference permission. Product/backend
confirmation of the intended premium SKU remains necessary if it differs from
that existing account membership contract.

The agent executable must exist in this app's resource bundle; no PATH fallback
or arbitrary configured fixer receives these requests. Its existing read-only
proposal dispatcher, model-endpoint configuration requirement, headroom and
inference-lease guards stay unchanged. No model server is started by this path.
Clicking investigation does not enable `allowProcessTermination`, signal a PID,
call a service mutation or authorize remediation. Existing destructive actions
retain their own controller/confirmation policy.

Current requests older than 30 seconds, future timestamps, absent samples and
missing/reused process identities are refused. Unmanaged and detected-session references
also require an exact command-line match with the current inventory; argv is
compared locally and is never serialized. Selected rows carry PID and
start signature; the inventory must still match at dispatch. This is snapshot
identity validation, not a fresh kernel probe; an exit between capture and
investigation remains possible. The starter instructs the agent to revalidate
before live inspection. Historical requests retain their timestamp, explicitly
say the PID is not current and expire after one hour.

Raw argv, environment, usernames, filesystem paths, addresses, transcripts and
log bodies are excluded from process evidence. Executable basename is limited
to 80 safe characters; token/secret-looking labels are redacted. Ports cap at
16, metric process context at five, JSON at 16 KiB. Nonfinite metrics become
unknown or fail serialization; unknown is not fabricated as zero. Context is
untrusted data, not agent instructions. CPU/memory rankings and job associations
are labeled correlation rather than proof of a cause.

## Acceptance checklist

- [x] Locate source and inventory meter/process surfaces through bounded reads.
- [x] Prepare isolated source edits; preserve canonical checkout and frozen Ouros snapshot.
- [x] Shared investigation request/action path and separate embedded PTY source implemented.
- [x] Compact dropdown, consolidated navigation, relationship graph and real telemetry views source implemented.
- [x] `git diff --check` passed (source whitespace check only).
- [x] Add source regression cases for serialization, sensitive argv omission, bounds, unknown metrics and stale/historical timestamps.
- [ ] Compile and execute focused regression tests after containment owner authorizes validation.
- [ ] Reconcile installed build 4 executable with source revision before updating.
- [ ] Measure dropdown height, verify no clipped meters/network and compare existing styling.
- [ ] Exercise right-click, double-click, keyboard and VoiceOver on every inventory row.
- [ ] Verify signed-out, inactive, expired and active entitlement states with isolated fixtures, not paid requests.
- [ ] Verify local endpoint absent, agent missing, low-memory and concurrent-investigation refusal states.
- [ ] Verify terminal output contains starter JSON and existing shell/scrollback survives investigation switching.
- [ ] Verify graph selection, PID reuse/exit, interval selection, retention caps and missing-history states.
- [ ] Obtain independent UI review of the candidate and let the sole updater owner package/install the approved result.
