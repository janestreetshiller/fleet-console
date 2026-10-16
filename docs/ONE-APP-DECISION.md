# One app, one menu bar — decision sheet

**Status:** awaiting owner sign-off. Nothing here has been executed. FleetConsole
is unchanged, `fleet-relay` is unchanged as a surface, and `fleet-agent-menu` has
not been touched or removed.

The plan of record (`../WORK-PLAN.md`, §2) proposes collapsing three surfaces
into one `Fleet.app`. That collides with the console's own release state — a
signed, notarized 1.1.0 is already in `releases/fleetconsole-finished-20261011/`
— so it needs an explicit decision rather than a default.

## What exists today (verified 2026-10-16, not restated from the plan)

| Surface | What it is | Gate |
|---|---|---|
| `fleet-console` | `MenuBarExtra` status item + popover with Quick View and four sections; console window with six modules; **Agents tab already implements the notification centre** (roster, per-agent state badges, "Waiting on you", "Working now", "Recent messages", reply loop) and the status item already carries an `awaitingReplyCount` badge; **Task Composer window already exists** (⌘N from the status-item context menu, `main.swift:238`); `fleetd` + `fleetctl`; SwiftTerm chrome tools | `swift build` and `swift build -c release` clean; 299 tests pass; `Scripts/design-audit.sh` exit 0 |
| `fleet-relay` | Its own SwiftUI `MenuBarExtra` app: a **second status item** plus an inspector window, over a Rust engine (`sysinfo` sampler, `insight.rs` EW-baseline anomaly selection, `store.rs` tags + protection rules) joined by a hand-written C ABI that verifies its own layout at startup | Rust 42/42 tests; Swift build clean, 19/19 tests |
| `fleet-agent-menu` | Rust `objc2` `NSStatusItem` app. Read-only telemetry (system, interface, process) — a second process sampler and a third status item | builds, 11/11 tests (not re-run in this pass) |

So two of the three proposed ports are **already done**: the notification centre
is the console's Agents tab, and the composer is the console's Task Composer.
What is actually left is not a port.

## The decision

**Option A — execute §2 (one app, one menu bar).** Remaining work is only:

1. **One process sampler.** Fold relay's snapshot sampler into `fleetd` so the
   machine has a single `ps` walk, and let the app + `fleetctl` read snapshots
   over `fleetd`'s existing `0600` Unix socket. Extend the C ABI to expose the
   snapshot over RPC; do **not** instantiate a second `relay_engine` in the app.
   This retires the app-side `ProcessInventory` timer and the daemon-tick walk.
2. **Relay's inspector becomes a console module**, keeping `store.rs`
   (tags/protection) and `insight.rs` (EW baselines) in Rust, where they are
   already unit-tested.
3. **One status item.** Reuse agent-menu's `NSStatusItem`/`NSMenu` plumbing
   (one item, `ui.rs` metric rows) and repoint its background poller at Fleet's
   own data — or drop the item entirely, since the console's Agents tab covers
   the notification-centre behaviour it was meant to gain.

**Option B — keep the surfaces separate.** Each app keeps its own status item
and sampler. Cost is the one §2 names: two or three independent samplers that
can disagree, three status items, three release artifacts.

**Option C — retire `fleet-agent-menu` only** (the plan already calls it
redundant at §1) and leave the console/relay boundary alone for now. This is
the smallest step that removes a duplicate without touching a shipped surface.

Work-plan §5.1's own merge plan is Option A's step 1, and its argument is the
strongest thing in the document: it is the only arrangement where the two
process views *cannot* disagree. That is the reason to take A rather than C if
the machine is going to keep having an operations console at all.

## What each option costs the release

- Option A changes the app that is already at 1.1.0 and notarized: a new module
  in the console window, a new RPC verb on `fleetd`'s socket, a new engine
  linked into the app. It invalidates the current 1.1.0 assessment
  (`releases/fleetconsole-finished-20261011/RELEASE-ASSESSMENT.md`) and would
  want the surface-render pass re-run (`Scripts/surface-sheet.sh`) plus the
  measured 60-second workload re-measured — §5.1's step 1 removes a timer, so
  the numbers should improve, but "should" is not a measurement.
- Option B costs nothing now and repeats the duplication on every future
  process-table feature.
- Option C costs one deletion of a component the plan already marks redundant
  (not performed here — the task forbids removing subrepos) and no change to
  either remaining app.

## Blocked behind this decision

- **`fleet-agent-menu` is not retired.** `../WORK-PLAN.md` §1 says "Retire this
  component; do not port it". Until someone signs that, the directory stays.
  Its working tree also carries two uncommitted edits that should not be
  committed as-is — see *Loose ends* below.
- **The paywall direction is self-contradictory.** §5 / D4 say the free build
  gates `PremiumFeature`s and Polar issues the key. `docs/FREEMIUM.md`
  (2026-10-05) now says the opposite: "the current MIT build permanently unlocks
  every feature … There is no checkout or donation requirement", and it is
  labelled *legacy reference only*. The paywall cannot be built until one of
  those is deleted.
- **D5 is still open**: what an "agent" is (the default assumption is Claude
  Code / Codex / opencode sessions) is a data-model decision, and the Agents tab
  already ships a shape for it.
- **Stage 6 (public repo) is not blocked by signing.** §6 records a
  `fleetd` codesign failure (`errSecInternalComponent`); the 2026-10-11 release
  assessment records the opposite — Developer ID signed, hardened runtime,
  submission accepted, ticket stapled, Gatekeeper `Notarized Developer ID`
  verified after unzipping the download. The remaining blocker is the GitHub
  account (`janestreetshiller`, both tokens invalid), which is an owner action,
  not a code change.

## Loose ends in `fleet-agent-menu` (left uncommitted, deliberately)

Two files are modified on `main` at `c303bcf`:

- `README.md` — the tracked README is replaced by a three-line "Documentation
  moved" stub pointing at
  `../../../Workspace/Knowledge/vaults/Projects/Workspace Documentation/AI Harness/agent-menubar — README.md`.
  **That path does not exist**, and neither does `~/Workspace/Knowledge` — the
  only entry under `~/Workspace` is `demo-sandbox`. Committing this deletes the
  component's documentation and replaces it with a broken link.
- `src/config.rs` — one overlay path changes from
  `Workspace/developer/applications/ai-pocket-menu/config/viewer.json` to
  `Workspace/dev/apps/ai-pocket-menu/config/viewer.json`. **Neither path exists
  on this machine**, so which one is correct cannot be verified here.

They are unrelated (a doc relocation and a config path change) and the
documentation half is verifiably broken, so they were left exactly as found.
If the vault README is real on the machine that holds the vault, commit that
file alone and fix or revert `src/config.rs` separately.
