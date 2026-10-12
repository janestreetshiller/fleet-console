# FleetConsole release assessment

## Grades

- Resource usage: **B+, 8.5/10**. Two optimized 60-second Quick View runs used
  2.11% and 2.75% of one CPU core, with 64.7–64.8 MiB peak resident memory.
  Reaped collector children used another 2.68% and 3.33%, for 4.79% and 6.08%
  combined. Two optimized 60-second offscreen Overview runs used 6.19% and 7.50%
  of one core, with peak resident memory around 140 MiB. These are distinct
  active views, rather than an idle measurement or a whole-system power estimate.
  The live existing client plus controller averaged 6.63% of one core over a
  separate 60-second observation. The existing client's RSS decreased during that
  interval. The 8% app-process budget passed on both optimized runs.
- Controlled source preview: **B+, 8.5/10**. The current MIT tree has focused
  release repairs, passing local checks and a reviewable source snapshot. GitHub
  hosted CI requires restored account billing capacity. Public visibility and a
  downloadable app follow the separate maintainer distribution workflow.
- Humanized copy: **A-, 9/10**, an editorial grade. The [launch copy](LAUNCH-COPY.md)
  names specific actions and separates free local tools from optional paid remote
  access; an independent review checked its material claims against implementation.

## Measured workload

Apple M4, 10 logical cores, 16 GiB memory, macOS 27.2; Swift 6.4. Release builds use
`--disable-index-store -Xswiftc -disable-cmo`. Overview samples resources every two
seconds and process inventory every four seconds. `Scripts/benchmark.sh 60` runs
the native console with live probes and observational `snapshot`/`subscribe` RPCs.
The offscreen runs measure app-process CPU with `RUSAGE_SELF`, separately from
collector children and WindowServer. They exercise Overview, Processes, search
focus, the empty-search recovery state and Needs Attention, with light/dark
captures at compact, standard and wide sizes. These are bounded workload samples,
with host load and sample timing contributing to variation.

The independent 60-second observation used cumulative process CPU deltas and RSS
samples every five seconds for the already-running client and controller. It
preserved their current UI and service state. Raw captures, receipts and profiles
stay local because they include actual host and process details.

## Verified behavior and repairs

The integrated Swift run passed **210 tests**: 186 XCTest cases and 24 Swift
Testing cases across both test bundles. Shell syntax and Rust workspace checks passed.
Python release-policy, artifact-identity and source-privacy suites passed all
**54 tests** in both normal and optimized execution. The native app was assembled
into a fresh stage, and nested plus outer ad-hoc signatures verified. Its real
ZIP archive preserved the `FleetConsole.app` root and resource/license entries.
Targeted regressions demonstrated failing
fresh-account defaults and an inherited service inventory before their fixes.
An alternate-home run passed the composer checks using a scratch home. Billing
privacy tests cover signed-out automatic silence, explicit catalog retrieval,
first-time account connection loading subscription offers and signed-in refresh;
the connection-availability assertion failed before its repair. Test transport,
browser and credential persistence are isolated from the maintainer's account.

Fresh configurations start with an empty explicit known-service inventory;
existing configured entries remain compatible. Composer directories follow the
current user's home. Automatic signed-out billing refresh stays local, while
explicit account actions and connected-account refresh use Ouros. The threat
model describes Ouros and Stripe traffic. Product fixtures use synthetic identity
and network data. Release staging protects installed app locations and keeps
artifact operations anchored to the opened bundle. The archive writer uses an
inherited file descriptor, while submission and cleanup retain the private scratch
directory identity. Repository, ancestor and private-scratch replacement tests
preserve replacement archives and submit the original artifact. A native `ditto`
probe verified descriptor-backed ZIP creation, and the routing regression compares
the archive writer's descriptor identity with the submitted file identity.

## Two native views

The first menu-bar opening presents Quick View: two static CPU/memory dials,
network rates, memory pressure and current service/attention counts. The existing
operational tabs remain available, and the right-click menu names Quick View
explicitly. Open Dashboard retains the detailed window with time-based charts,
process inspection and service controls. Both views share the current probes and
cadence; Quick View adds display components, rather than additional collectors.

Native light/dark Quick View captures were inspected at 480-point width. Memory
pressure appears with Memory, every tab remains readable, and Open Dashboard is
visible. The updated verification mode also rejected a missing daemon using an
observational socket override while the installed controller stayed running.
The optional-duration regression also failed against the native renderer before
its repair; `--verify-live <directory> --verify-quick-view` then passed with the
20-second default. Argument tests cover reordered flags, socket paths and invalid
durations. The README documents that the dropdown remembers the selected tab.

The copy describes expiry cleanup of running, controller-launched services.
Pausing retains process groups and resources and suspends expiry cleanup until
resume; the existing controller behavior is preserved.

## Delivery scope

Use the [controlled source preview](SOURCE-PREVIEW.md) for reviewer access and
source-archive instructions. The private Git repository preserves its existing
history; the reviewed source archive contains the current tree and its license
notices, with machine-local instruction adapters excluded through `.gitattributes`.
The README and launch announcement are ready for editorial use. The staged app
and source snapshot live together in the project release folder. Local app staging
and its signatures are checked separately from Apple ticket acceptance; the
configured FleetConsole Apple credential profile requires maintainer setup for
a downloadable release.
