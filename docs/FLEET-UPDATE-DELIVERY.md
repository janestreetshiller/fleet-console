# Fleet contextual actions: delivery handoff

This is the delivery route for the sole native updater. No command in this
file has been used to install, launch, notarize or publish this candidate.
Backend execution and live inference remain outside this work.

## Verified source and installed baseline

- Shared repository: `/Users/main/Metal/Code/Fleet/fleet-console`.
- Matching installed-artifact checkout: `/Users/main/Metal/Code/Fleet/fleet-terminal-output`.
- Baseline: `2d7b41b58b0de62758eed2ba5b97dc6cb1c74a01`.
- Candidate branch: `codex/fleet-context-actions-20261015` in the same Git object
  store, isolated at `/Users/main/Documents/Codex/2026-10-15/task/fleet-context`.
- The installed build 4 and the matching checkout's
  `build-release-1.1.0/FleetConsole.app` are byte-identical for the executable,
  helpers, plist and signature resources. Preserve that signed artifact and the
  installed app until the updater owns the actual replacement operation.
- The candidate is a descendant of 2d7b41b. Its FixAgent.swift, Rust agent and
  terminal-output tests preserve that baseline. Do not rebase onto canonical
  root HEAD b1ae71e or restore the earlier local-loopback investigation path.

## Supported installation route

`Scripts/update-installed.sh <exact-commit>` resolves a committed revision from
the shared repository, creates a clean detached worktree, builds there, verifies
the staged app, asks the installed client to quit, moves its old bundle to Trash,
copies the new app, verifies it and launches the canonical installed path.
It does not restart fleetd unless `--restart-controller` is explicitly supplied.
Moving the old bundle preserves the running controller's old binary inode;
this avoids overwriting that executable in place. No controller protocol,
registry schema or service-supervision behavior changes in this candidate.

Do not run that wrapper while the current launch/UI prohibition remains in force:
its last step always launches the app. The standalone `Scripts/build-app.sh`
route stages only and never launches the client or controller. The internal
`assemble-app.sh` worker is not a standalone entry point; retain the fd-anchored
staging/signing guarantees in `release-staging.py`.

No cherry-pick into a dirty canonical checkout is required. The shared object
store already contains the candidate commits. The sole updater should verify
these read-only predicates using the final reviewed tip from the task handoff:

```sh
git -C /Users/main/Metal/Code/Fleet/fleet-console rev-parse --verify '<candidate-tip>^{commit}'
git -C /Users/main/Metal/Code/Fleet/fleet-console merge-base --is-ancestor 2d7b41b58b0de62758eed2ba5b97dc6cb1c74a01 '<candidate-tip>'
```

Then create the clean detached source tree from that exact tip. Do not merge or
reset unrelated branches. Apply the final combined patch only to that baseline
if using a separate repository; the obsolete initial patches are superseded.

## Implemented updater preparation

- Swift and Rust build invocations now use one job.
- `FLEETCONSOLE_SCRATCH_PATH` selects an absolute private scratch; the updater
  sets it inside its fresh detached `/tmp` worktree, avoiding Documents metadata.
- `FLEETCONSOLE_OFFLINE=1` restricts Git to local protocols, disables dependency
  resolution/updates and netrc, and forces Cargo offline. Missing cached
  dependencies fail rather than download. The release CMO workaround remains.
- `FLEETCONSOLE_DEPENDENCY_CACHE` seeds only pinned checkouts/repositories/state
  into the detached source; compiled products are not reused. The license comes
  from the selected scratch's actual SwiftTerm checkout.
- The packaged app is 1.1.0/build 5 and records `FleetSourceRevision` and
  `FleetSourceDirty` before signing. The updater refuses a revision mismatch or
  dirty source before quitting or moving the installed client.
- Same-publisher identity is required for replacing the existing Developer ID
  app. This preserves the production account signing identity. Existing optional
  notarization is supported through `FLEETCONSOLE_NOTARY_PROFILE`; no profile,
  credentials or ACLs are created or changed. A local source update without
  requested notarization is reported as such; it is not represented as a
  notarized download. The original stapled artifact remains recoverable.
- `--no-launch` suppresses the wrapper's final canonical-app launch.
- Copy/signature failure after the swap restores the preserved original bundle
  and leaves it unlaunched. No controller restart is requested by default.

Bash syntax checks passed. Existing mocked PackagingTests passed 18 cases;
focused reruns passed both new offline/scratch/build-metadata cases. These mocks
substitute build/signing tools and do not create real signatures or installers.
The live Applications swap and real release signing/notarization are not run by
this task.

## Exact remaining owner action

The routine source integration is complete: the final reviewed commit already
contains the installed 2d7b41b baseline, feature changes, credential isolation,
transport checks and updater preparation in the shared Git object store. The
sole updater can use that immutable ref directly; no cherry-pick, reset or extra
app copy is needed.

After the current slot owner finishes, the remaining concrete operation is a
serial release build/sign and replacement of the canonical installed app through
the **candidate's** helper, using the existing authorized signing identity.
Do not invoke the old canonical checkout's launcher with new flags. Exact form,
not executed here:

```sh
cd /Users/main/Documents/Codex/2026-10-15/task/fleet-context
FLEETCONSOLE_OFFLINE=1 \
FLEETCONSOLE_DEPENDENCY_CACHE=/tmp/fleet-context-ee056fa-validation \
Scripts/update-installed.sh '<final-reviewed-tip>' --no-launch
```

The candidate helper resolves that exact commit from the same shared repository
and creates its own clean detached source tree. Optional existing notarization
can be requested by also setting `FLEETCONSOLE_NOTARY_PROFILE`; no new profile or
credentials should be created for this operation.

Use the already authorized existing identity/profile when required by the native
release workflow; do not configure credentials or answer new keychain prompts.
A missing signing identity or offline dependency is a concrete pre-install
failure and must be reported, not worked around by changing trust/security.

This operation has not been performed because this delegated task is explicitly
forbidden to install or launch; the native task remains the sole updater owner.
No new user approval is requested for routine integration. UI acceptance and
launch remain subject to the existing explicit prohibition. After that restriction
is lifted, launch only `/Applications/FleetConsole.app`; never replay UI or open
an additional staged copy. Do not describe the current installed build 4 as updated.

## Minimal prepared transport checks

`InvestigationTransportTests` uses a private URLProtocol that handles every
request, including unknown paths/hosts. It has no live-network fallback, uses a
synthetic token only, disables keychain access and the browser callback, and
stores request markers in a private disposable defaults suite. It does not
instantiate AppModel or a view. Explicit synthetic tokens are injected through `TestOurosCredentialStore`;
the transport matrix performs no device connection or account initialization.

Prepared coverage:

- Signed-out refusal without any request.
- Server-authorized model dispatch despite inactive Fleet multi-device membership.
- Exact JSON starter and server-selected model, no tools, synthetic bearer header
  and per-operation idempotency key.
- Catalog scope denial, nonrunnable catalog and malformed catalog: no completion.
- Server-rejected account session: clear the stale local sign-in state and do not dispatch.
- Selection invalidated during catalog verification: no completion.
- Authoritative 402 refusal: no pending request left behind.
- Malformed, oversized and timed-out completion: durable unconfirmed marker,
  reconstruction after relaunch, no blind retry and acknowledgement without send.
- Controlled held completion: concurrent request refuses without another dispatch.

`InvestigationTests` covers serialization, bounds, argv/secret omission and
current/historical timestamps. The source-only review corrected over-escaped JSON
fixtures so refusal classification exercises actual JSON bodies.

Run only these suites in the coordinated slot, one job and no parallel tests,
with the existing `/tmp/fleet-context-ee056fa-validation` dependency/cache state.
Filtering is required: the repository also contains UI suites that must not run.
The filtered run completed: 12 tests in 3 suites passed in 0.978 seconds after
a 107.57-second single-job build. No real credential, browser, network fallback,
inference or UI path was used.

## Read-only token contract comparison

Fleet's existing device client requests `client_id=ouros-desktop` and stores a
43-character opaque bearer from `/auth/device/token` in its own account session.
It must not borrow Ouros X credentials, request broader scopes or configure a
second provider key. The legacy-compatible gateway instrumentation retains the
legacy account verifier/provider refresh and injects completion handling only
after account and subscription resolution. `legacy-completion.mjs` filters the
model catalog by that entitlement and forwards POSTs to the existing reservation
and settlement route.

`Cloud/src/auth.ts` also defines a separate issuer/audience-checked JWT verifier.
That is not evidence that Fleet's opaque token is a JWT or is accepted by every
Cloud deployment. This candidate deliberately stays on the existing public
legacy-compatible routes. Deployment routing, token scope and runnable catalog
availability remain integration checks. Synthetic URLProtocol tests prove client
behavior only; they cannot establish actual server/token interoperability.
A 401/403/nonrunnable result must remain a refusal, without credential fallback.

## Final acceptance and rollback ownership

Before installation, the sole updater needs the staged release revision/hash,
signature and license evidence, passing transport checks and a scheduled path
for the currently prohibited UI acceptance. Required UI checks include compact
dropdown height/content, every contextual row action, keyboard focus, terminal
transcript/shell preservation, graph edges, interval evidence and truthful empty
states. Native acceptance must use the single canonical app after replacement;
no staged second app is to be launched.

The updater moves the old app into Trash before copying the new one. Retain the
exact backup location and existing matching signed release artifact. The wrapper now restores the preserved original after a copy/signature failure.
The sole owner still verifies the restored known artifact and launches only the
canonical path when launch is allowed. Do not restart or signal managed processes as part of investigation
acceptance. Publication or production deployment is not part of this update.

## Credential isolation incident and verified structural fix

The reported historical caller was swift-frontend PID 21059 and service
`com.ouros.bar.native-account`. Live process checks could not reconstruct the
exited caller's ancestry. No Fleet transport test had executed before that
incident, and attribution to this task is not established. Fleet's own service
is `com.fleetconsole.ouros`. At 12:10:16 UTC no Swift/test/SecurityAgent process
was live; no password, Allow, Always Allow, ACL or security-setting interaction
was performed by this task.

`CredentialIsolation.swift` now makes credentials an explicit injected store.
Development/debug builds, interpreters, test runners, harness flags and unbundled
executables deny real storage before the lazy production backend factory runs.
Missing test injection refuses locally, including before any account connection
or request. The raw private read/save/clear entry points repeat the context guard
before Security APIs; eligible release apps additionally verify the existing
publisher/code identity before accessing an account item. Signed production
account login keeps its existing store and identity. No global account singleton
or real credential backend is initialized by the fixtures.

The standalone `Scripts/credential-isolation-proof.swift` is compiled with only
the pure policy/store source. It has no app module or Keychain implementation and
no direct Security API symbols. It passed: 10 denied contexts, 30 blocked
operations, zero backend initializations and three explicit fake operations.
The filtered Swift test run then passed 12 tests across serialization, mocked
transport and credential isolation, with `FLEET_TEST_HARNESS=1` and explicit fake
stores. No production credentials or endpoints were used.
