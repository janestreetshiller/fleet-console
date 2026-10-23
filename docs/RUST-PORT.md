# Rust and GPUI: current implementation and next work

Reviewed 2026-10-22 against FleetConsole main `03f0073`, before this sprint's
working changes. This replaces the October 5 assessment, which said the repository
had no GPUI dependency. Recheck the working diff and manifests before acting.

## Can we port it instantly?

An experimental GPUI window already exists in `rust/fleet-gpui`. Replacing the
working menu-bar app immediately is not supported by the current implementation.
The prototype needs real controller state, working actions, native menu-bar
behavior, keyboard/accessibility acceptance, account integration and a terminal
before it can replace the existing app.

GPUI is a GPU-rendered Rust UI framework. Its published 0.2.2 documentation says
it is pre-1.0, supports macOS and Linux, and uses Metal on macOS. It is a framework
for implementing the UI, rather than a converter for SwiftUI screens. See the
[official introduction](https://gpui.rs/) and
[versioned documentation](https://docs.rs/gpui/0.2.2/gpui/).

## What is already reusable

| Component | Current responsibility | Implication for a GPUI client |
| --- | --- | --- |
| `Package.swift` | Swift app, FleetCore, fleetd, fleetctl and two test targets | Keep the working controller and CLI while a second UI is built. |
| `rust/fleet-proto` | JSON socket requests, response envelopes and a bounded request path | Reuse the protocol; keep blocking calls off the render thread. Subscription support is missing. |
| `rust/fleet-conformance` | Wire checks against a selected live Swift controller | Verify the seam with an isolated controller, including refusal/error cases. |
| `rust/fleet-agent` | Resident operations helper | Separate from Agent-RX and the GPUI shell. |
| `rust/fleet-telemetry` | Local machine/process sampling | Distinguish measured values, unavailable fields and snapshots from live streams. |
| `rust/ouros-adapter`, `rust/fleet-spatial` | Graph/state and layout structures | Seeded graphs are not evidence of a connected agent. |
| `rust/fleet-gpui` | Experimental workspace rendering | Continue as a development client until real workflows pass. |

## Confirmed gaps at the start of this sprint

- The workspace's `[patch.crates-io]` points at a removed machine-local Ouros
  checkout. A fresh `cargo check -p fleet-gpui --all-targets --locked` fails before
  compilation. Resolution also affects other workspace packages: app assembly
  builds `fleet-agent` from this workspace. Repair dependency reproducibility
  before claiming a new build is ready. Pointing at another mutable checkout
  would not establish a portable dependency.
- The app samples telemetry on startup rather than maintaining a controller
  subscription. Its sampling error path supplied simulated values.
- The default brain bridge supplied invented process/context/decision data.
  Several navigation and diagnostic callbacks were empty; remediation described
  a signal without performing it. A text terminal preview has no PTY.
- The old headless verification checked seeded objects and printed that all
  planes were active. That did not verify a live controller, a connected agent,
  working controls or a terminal.
- The telemetry model derives a thermal label from CPU use and supplies disk
  I/O defaults without a corresponding hardware measurement. These must not
  appear as measured sensor values in a shipping interface.

The sprint's first repair removes misleading operational claims from the GPUI
client. Removing a claim does not implement the missing connection or action.
Check the actual diff and sprint handoff for the repair's verification scope.

The dependency repair now uses the already-declared published GPUI 0.2.2 and
its registry checksum, with no version upgrades. A canonical locked workspace
check including all targets passed. The old path failure above is the starting
condition, not the current build result. The workspace's inherited Rust 1.80
metadata does not establish the GPUI dependency tree's minimum toolchain;
published GPUI uses edition 2024 and the locked uuid package requires Rust 1.89.
Use the recorded toolchain for these checks until the actual minimum is tested.

## Implementation sequence

1. Restore a pinned, reproducible dependency resolution and build affected Rust
   packages from a fresh checkout. Keep the existing Swift runtime working.
2. Feed a read-only GPUI service list from real controller snapshots with explicit
   loading, disconnected, stale and error states. Bound response sizes and time;
   cancel abandoned work. Do socket/process work on background workers.
3. Add native menu-bar routing, keyboard navigation and accessible controls.
   Connect service actions through fleetd, preserving owner, lease and process
   start-identity checks. Claimed and remote processes keep their current limits.
4. Implement remaining workflows, including account/billing, logs and real
   terminal integration. Compare the same actions and datasets in both UIs.

## Memory safety and low latency

Keep unsafe OS/FFI code narrow and reviewed; Rust dependency choice alone does
not establish the safety of the whole application. Bound retained telemetry,
logs, socket payloads and background queues. Preserve cancellation and stale
result rejection.

Before a replacement decision, record build identity, machine, service/process
counts, refresh cadence and active surface. Measure menu-open and action-to-row
median/p95, app plus collector CPU, peak RSS, and redraws while idle. Repeat the
same workload on Swift and GPUI. No comparable GPUI latency or memory measurement
was established by this assessment, so no improvement percentage is claimed.
