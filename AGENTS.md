# FleetConsole development contract

Build a useful local operations console: help a person understand machine load,
identify the work consuming it, and safely manage background services with an
owner, purpose, lease, logs and explicit health evidence. Use the current task's
user outcome to choose work; old audit queues, port proposals and release receipts
are context, not prerequisites for unrelated improvements.

## Establish the working source

Read `README.md`, the affected manifest and code, then inspect branch, HEAD,
worktrees and dirty files. Preserve work outside the task. The verified local
entrypoint `/Users/main/Metal/Code/Fleet/fleet-console` resolves to
`/Users/main/Scratch/fleet-apple-hig-e2e-20261013`. For this named repository,
that explicit checkout is an authorized exception to the Scratch container's
project-location rule; it does not authorize general Scratch discovery. Recheck
the symlink before using it. Git identity and the current task establish the
working source, not a folder's date or an installed app's version.

## Architecture and constraints

- `Package.swift` defines the Swift 6, macOS 14+ app, `FleetCore`, `fleetd`,
  `fleetctl`, and core/app test targets. SwiftTerm belongs to the app target.
- `fleetd` owns the registry, event log and controller-launched service lifecycle.
  App/CLI service actions use its protocol. Claiming an external process grants
  visibility, not controller signalling authority. Preserve owner, lease and
  process-identity checks; see `docs/AGENTS.md` and `docs/THREAT-MODEL.md`.
- Keep process existence, listening ports, reachability and configured health
  checks separate. Missing observations are unavailable, not healthy or zero.
- `rust/Cargo.toml` defines a separate workspace, including protocol, conformance,
  agent, telemetry, adapter, spatial and GPUI crates. Their presence does not
  make a Rust port or replacement shell the next assignment. Inspect its local
  GPUI path patch when resolving dependencies; do not silently repoint it.
- Local monitoring/service control, Ouros account billing for linked devices,
  and legacy offline licence scaffolding are distinct paths. Inspect current
  call sites before changing entitlements; `License.swift` alone does not
  describe the whole product. Preserve MIT and third-party notices.

## Verification proportional to the change

Use relevant targets/tests while iterating. The current CI reference is
`.github/workflows/ci.yml`; commonly needed checks from this repository are:

```sh
swift build --disable-index-store
swift test --disable-index-store
cargo check --manifest-path rust/Cargo.toml --workspace --all-targets --locked
```

Run Swift checks for affected Swift code and Rust checks for affected Rust code.
Release-sensitive Swift changes also need the CI release compiler workaround:
`swift build -c release --disable-index-store -Xswiftc -disable-cmo`. For script
changes, run `bash -n` on changed shell scripts and the relevant policy regression
listed in CI. Policy/prose-only edits need reference and diff checks, not app
builds or packaging. Report pre-existing failures separately from regressions.

For interface changes, inspect affected states, resizing, keyboard access and
appearance; native surface sheets and `Scripts/benchmark.sh` have the measurement
boundaries documented in README. A rendered sheet does not establish menu-bar or
installed-app acceptance. Live daemon conformance needs an intentionally selected
daemon and runtime evidence. Use isolated state; inspect captures for private data.

## Delivery

Finish the requested behavior and relevant checks; report what changed, actual
results and any remaining limitation. An old passing count or signed bundle is
not evidence for the current source. Packaging, installing/restarting a controller,
publishing, and charging an account are separate effects requiring scope in the
current request. For authorized distribution use `docs/RELEASE.md` and the existing
scripts, fresh `FLEETCONSOLE_OUTPUT_DIR` staging, signing and notarization checks.
Never build over a running installed bundle. Development does not require a release.
