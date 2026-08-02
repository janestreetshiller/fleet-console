# Technical Debt Audit — 2026-08-02

Scope: the whole repository. 92 Swift files, 27,186 lines across four targets
(`FleetCore`, `fleetd`, `fleetctl`, `FleetConsoleApp`), plus two Rust crates
(`fleet-proto`, `fleet-conformance`) and eleven scripts.

## Baseline (measured, not assumed)

| Check | Result |
|---|---|
| `swift build` | clean, exit 0. One warning, and it is SwiftPM's own build-graph note about the vendored `SwiftTerm` bundle — not our code. |
| `swift test` | 37 tests, 0 failures. |
| `Scripts/design-audit.sh` | clean — all 16 checks, including the four doc/code sync checks. |
| Force unwraps (`try!`, `as!`, `!`-unwrap) in `Sources/` | zero |
| `[weak self]` captures | 52 — every escaping closure that stores `self` uses one |

## The headline finding

**The premise of the overhaul does not match the codebase.** This is not an MVC
app with accumulated debt. There are no view controllers to extract logic from —
the app is SwiftUI end to end, with `@Observable @MainActor AppModel` as the
single source of truth and per-row observable boxes (`ServiceRow`, `DeviceRow`)
so a snapshot that moves one service's CPU number re-renders one row rather than
the list. The folder structure is already layered by concern
(`Design/`, `Probes/`, `Views/Console/`, `Views/Console/Chrome/`), the shared
model sits in its own dependency-free target, and the design system is enforced
by a 441-line audit script that fails the build on literal fonts, off-ladder
metrics, and docs drifting from code.

A "structural refactor" here would be motion, not progress, and against 27k
lines with no version control it would be destructive. The real debt is
narrower, and specific.

## Ranked debt

### 1. There is no git repository — blocking

`.git` does not exist. 27,186 lines of Swift, a signed and notarized app bundle
pipeline, and no history, no branches, no undo. Every other item below is
cheaper and safer once this is fixed, and no structural change should happen
before it. `.build/`, `build/`, `rust/target/` and `.DS_Store` all need a
`.gitignore` in the same commit.

### 2. Swift 6 language mode is opted out on all four targets — the actual concurrency debt

`Package.swift` declares `swift-tools-version: 6.0` but pins every target to
`.swiftLanguageMode(.v5)`. This is the modernization the mission is reaching for
— not MVVM, which is already there. Strict concurrency checking is what would
have caught items 3 and 4 at compile time. The migration is target-by-target and
`FleetCore` is the natural first one: it is dependency-free and has the test
coverage.

### 3. `Notifier`'s mutable static state is an actual data race

`Sources/FleetConsoleApp/Notifier.swift:12-13` — `authorized` and `requested`
are unsynchronized `static var`s. `authorized` is written inside the
`UNUserNotificationCenter.requestAuthorization` completion handler, which runs on
an arbitrary queue, and read from `post(_:)` on the main actor. Small, real, and
exactly what strict concurrency would reject.

### 4. `HealthChecker.httpGet` can have its result overwritten on the timeout path

`Sources/fleetd/HealthChecker.swift:47-80`. The happy path is ordered correctly
by the semaphore. The timeout path is not: after `semaphore.wait` reports
`.timedOut`, the function writes `outcome`, then calls `task.cancel()` — which
fires the completion handler, which writes `outcome` again, concurrently with the
`return outcome` on this thread. A timed-out health check can report the
cancellation error instead of the timeout, or read a torn value. Separately, the
blocking `semaphore.wait` parks a `workQueue` thread for the whole check
duration; `async`/`await` removes both problems at once.

### 5. `fleetd/Controller.swift` is 1,555 lines and 38 `queue.sync` call sites

The single largest file, and the only one where size is a genuine hazard rather
than an aesthetic complaint. It holds RPC dispatch, lease reaping, reconcile,
health scheduling, device probing, and subscriber broadcast, all coordinated by a
hand-rolled serial-queue discipline. The discipline is consistent and the
comments carry the reasoning — this is disciplined code, not spaghetti — but 38
`queue.sync` sites in one file is a standing re-entrancy risk (a `sync` reached
from inside the queue deadlocks), and that risk is invisible to the reader and to
the compiler. Splitting the RPC dispatch table out from the state machine is the
highest-value structural change in the repo, and it is a change that wants git
underneath it first.

### 6. `FleetCore/Models.swift` is 1,158 lines

A grab-bag: records, events, snapshot types, attention derivation. Splitting it
along those seams is low-risk and mechanical, but it is cosmetic next to items
1–5 and should not jump the queue.

## Deliberately not on this list

- **The gauges.** `Design/RetroGauge.swift` already draws its 40 ticks in a
  single `Canvas` rather than 40 rotated leaf views, animates through an
  `animatableData` `Shape` so the arc interpolates instead of snapping, honours
  Reduce Motion and Differentiate Without Colour, distinguishes "zero" from "not
  sampled", and samples at 2 s. There is no frame-rate problem to solve; a
  rewrite would trade working code for risk.
- **The notification feed.** `Notifier` is 51 lines and deliberately narrow —
  only an awaiting-reply or a problem message interrupts, so a chatty agent
  cannot become a notification storm. The only defect is item 3.
- **Claiming and labelling.** The claim path in `Controller.swift:669-745` is the
  most carefully reasoned code in the repository: the refusal rules are
  centralized, the "claim buys no exemption" invariant is enforced on the wire
  and in the UI, and an expired claim is reported rather than reaped. It is
  correct under the existing queue discipline. It should be migrated with
  item 2, not redesigned.
