# Contextual investigations and compact Fleet navigation

Source candidate: branch `codex/fleet-context-actions-20261015`, based on `2d7b41b`.
This document records implementation and deferred acceptance separately.

## Baseline and containment

The installed `/Applications/FleetConsole.app/Contents/Info.plist` reports version
1.1.0, build 4 and executable `FleetConsole`. It contains no FleetSourceRevision
key. Follow-up provenance reads found an exact matching release artifact in
`/Users/main/Metal/Code/Fleet/fleet-terminal-output/build-release-1.1.0/FleetConsole.app`.
The candidate has been rebased onto that checkout's `2d7b41b` commit to preserve
its installed terminal-output behavior. Source was initially located at
`/Users/main/Metal/Code/Fleet/fleet-console` through the Fleet donor reference in
`/Users/main/Code/ouros-x/apps/desktop/ouros/docs/plugin-boundary-working-record.md`.

All changes were prepared in an isolated worktree. The initial implementation
was source-only. After the coordinator granted the non-UI slot, syntax validation
and a serial offline FleetConsoleApp target build passed. No dependency downloads,
test executions, app launches, UI automation, screenshots, model requests or
background pollers were run. Ouros build 507 was not changed.
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
- Revised baseline commit: `2d7b41b58b0de62758eed2ba5b97dc6cb1c74a01`.
  It is the sole commit after the initially assumed `b1ae71e` baseline and adds
  readable Fleet Agent terminal output. The task commits have been rebased onto
  it; FixAgent.swift, the Rust agent and its terminal-output tests are unchanged
  by the candidate relative to this revised baseline.
- Matching artifact checkout: `/Users/main/Metal/Code/Fleet/fleet-terminal-output`,
  HEAD `2d7b41b58b0de62758eed2ba5b97dc6cb1c74a01`, no tracked differences;
  only its `build-release-1.1.0/` artifact directory is untracked.
- Installed app: `/Applications/FleetConsole.app`, `com.fleetconsole.app`,
  version `1.1.0`, build `4`, executable `Contents/MacOS/FleetConsole`.
- Installed executable: 11,907,680 bytes, SHA-256
  `8a97b7da2c5a1e50788db5beb61bbee2d24fa0b8606da443b910bef1c42d8e1b`.
- Canonical checkout's built executable: 11,887,056 bytes, SHA-256
  `83d57490ea39e7230d3600b5ff6b96034fdd948ed4f39cf1e0c921f4264344a8`.
- `fleet-terminal-output` worktree's built executable SHA-256:
  `03720ca63d9919c3682045d5f508a04389d00f84381595eae9dec95b52a89ba1`.
- Exact matching signed release artifact:
  `/Users/main/Metal/Code/Fleet/fleet-terminal-output/build-release-1.1.0/FleetConsole.app`.
  Installed and release copies are byte-identical for Info.plist, the executable,
  all three helper binaries, `_CodeSignature/CodeResources` and `CodeResources`.
  Both executable SHA-256 values are
  `8a97b7da2c5a1e50788db5beb61bbee2d24fa0b8606da443b910bef1c42d8e1b`.
  Both Mach-O UUIDs are `66515B41-7F1D-335D-B775-E30E9D6DDD55`.
- The unsigned/development terminal-output build has that same Mach-O UUID;
  its differing full-file hash reflects a different artifact, not evidence that
  the terminal-output source should be discarded. The canonical root build has
  a different UUID (`5E1B8EB7-D4AA-381F-9E1D-68DDA7F9B2A1`).
- The plist still contains no embedded revision or signed source attestation.
  The baseline selection is grounded in the exact installed release artifact's
  matching checkout and history, rather than the canonical root's HEAD alone.
- Fleet build 4 is a separate app and identity from Ouros X build 508. This work
  neither reconciles nor updates Ouros X. Frozen Ouros build 507 was untouched.

Coordinated syntax-only command (now executed successfully, exit 0):

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
- [x] Syntax-only validation passed (exit 0) on the final corrected source.
- [x] Single-job offline FleetConsoleApp target build passed (exit 0).
- [x] Filtered synthetic checks passed: 12 tests in 3 suites, including mocked transport and fail-closed credential isolation.
- [x] Packaging mocks passed 18 tests; two focused offline/scratch/metadata cases passed after fully mocking Git tooling.
- [x] Match installed build 4 to the terminal-output release artifact and rebase onto its matching checkout/history; preserve the lack of embedded revision attestation.
- [ ] Measure dropdown height, verify no clipped meters/network and compare existing styling.
- [ ] Exercise right-click, double-click, keyboard and VoiceOver on every inventory row.
- [x] Synthetic fixtures verified signed-out/runnable/nonrunnable catalogs, scope denial, revoked account session, authoritative refusal, stale selection, ambiguous outcomes and concurrent refusal.
- [ ] Verify deployed token scope, allowance/credit and production account interoperability; no live account calls were made.
- [x] Synthetic timeout, oversized/malformed response, preflight staleness, concurrent refusal and unconfirmed-operation persistence/review checks passed.
- [ ] Verify terminal output contains starter JSON and existing shell/scrollback survives transcript switching.
- [ ] Verify graph selection, PID reuse/exit, interval selection, retention caps and missing-history states.
- [ ] Obtain independent UI review of the candidate and let the sole updater owner package/install the approved result.

## Coordinated validation record

The syntax-only command was authorized subject to a safe single-slot preflight.
It was initially held: the first two bounded checks found another compiler tree,
`xcodebuild` PID 94708 and `swift-frontend` PID 94944 (about 81–83% CPU), while
kernel memory pressure was `2`; reported free memory fell from 42% to 32%.
The final readiness check still found `xcodebuild` PID 94708, now with `clang`
PID 96392, and pressure remained `2`. The prerequisite was not met: syntax was
NOT RUN at that stage, rather than passing or failing. Later safe execution is recorded below. No process belonging
to that other task was stopped or altered. This task has no active compiler,
UI automation, app launch or polling process.

The final source review also renamed the nested process snapshot record to
`CapturedProcesses`, avoiding shadowing of the Observation module used by the
`@Observable` macro. This is a source correction, not a reported compiler result.

After the competing build finished, preflight found no compiler tree, pressure
`1` and 43% free memory. Syntax validation passed. Existing pinned checkouts were
copied into isolated caches without downloads: SwiftTerm revision
`dd2fb8ac5b861e7bf617c872895e338f38165648` and swift-argument-parser revision
`6a52f3251125d74daf04fcbd5e6f08a75d074382`, matching Package.resolved.

The first target build was blocked by nested manifest sandbox restrictions.
The approved tool-level retry reached compilation, but Documents file-provider
metadata caused resource-bundle signing to reject Finder information. Cleaning
only the isolated copy did not prevent metadata reappearing. Moving the build
scratch/cache to `/tmp` resolved that infrastructure failure without disabling
resource signing or changing installed files.

The full target compile then found three explicit-self errors in the Return to
shell closure. The closure now uses `self.investigationSession` and
`self.activate(context: self.currentContext)`. Syntax was rechecked successfully,
and the incremental target build passed: exit `0`, `Build complete! (31.51 sec)`.

Exact successful build command (environment variables restrict Git to local
protocols and keep caches in scratch):

```sh
GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0 SWIFTPM_MODULECACHE_OVERRIDE=/tmp/fleet-context-ee056fa-validation/module-cache CLANG_MODULE_CACHE_PATH=/tmp/fleet-context-ee056fa-validation/module-cache swift build --scratch-path /tmp/fleet-context-ee056fa-validation --jobs 1 --target FleetConsoleApp --disable-index-store --skip-update --disable-automatic-resolution --cache-path /tmp/fleet-context-ee056fa-validation/offline-cache --config-path /tmp/fleet-context-ee056fa-validation/swiftpm-config --security-path /tmp/fleet-context-ee056fa-validation/swiftpm-security
```

Debug executable, built but never launched:
`/tmp/fleet-context-ee056fa-validation/out/Products/Debug/FleetConsoleApp`.
The builder emitted nonfatal warnings about deprecated `--skip-update` and a
SwiftTerm resource-bundle creator node. The final preflight after completion
found no compiler process and pressure `1`; the slot is released.

Machine-readable results and hashes are in
`docs/validation/fleet-context-nonui-20261015.json`. No test suite, backend call,
application launch, UI acceptance, packaging or installation was performed.
Remaining work is mocked transport and policy tests, deployed token/scope
compatibility, and separately authorized UI acceptance by the sole updater.

## Subsequent isolated checks and updater preparation

The source now structurally prevents production credential access from development
harnesses. See `FLEET-UPDATE-DELIVERY.md` for the context/backend design, incident
attribution limits and exact owner update command. The account store is injected,
missing injection fails locally, and raw private Security entry points repeat the
guard. No ACL/security settings or production credentials were changed.

The standalone fake-only proof passed (30 blocked calls; zero denied backend
initializations), followed by the serial filtered run: **12 tests in 3 suites
passed**, runtime **0.978 seconds**, single-job build **107.57 seconds**. Only
`InvestigationTests`, `InvestigationTransportTests` and
`OurosCredentialIsolationTests` ran. UI tests were compiled but not executed.
The transport fixtures inject memory credentials and intercept every URL; the
runtime also sets `FLEET_TEST_HARNESS=1`. No real account/backend request or browser
was reached. The successful run rebuilt the new credential-isolated app source.

Updater preparation is now implemented: one-job/offline staging in private
scratch, build 5 plus clean source stamp, same-publisher verification,
`--no-launch`, and original-bundle restoration on copy/signature failure.
All three shell scripts passed Bash syntax checks. PackagingTests passed 18
mocked cases (80.946 seconds); the two new offline/scratch/metadata cases passed
again with system Git replaced by a fixture-only stub (2.319 seconds). No release,
private signing key, notarization, installation or app launch was performed.

The Mac build slot is released. The sole native updater owns the remaining
release build/sign and canonical replacement at the final immutable commit.
No staged second app or UI replay is authorized. The current installed app
remains the verified build 4 until that owner performs the swap.
