# FleetConsole — source of truth

Follow [/Users/main/AGENTS.md](/Users/main/AGENTS.md), the canonical working agreement. This file adds scoped project facts.

One local-first operations console: menu-bar app + launchd controller daemon +
CLI. This file is the project index; source and manifests establish implementation facts.

## Project facts

- Swift 6, SwiftPM package, macOS 14. Everything dependency-free except
  SwiftTerm (terminal emulation only, kept off FleetCore/fleetd/fleetctl).
- `Scripts/build-app.sh release` packages/signs `build/FleetConsole.app`;
  `/Applications/FleetConsole.app` is the installation target. Verify current artifacts.
- Rust seam: `rust/fleet-proto` (protocol types) + `rust/fleet-conformance`
  (round-trips them against the live daemon).
- MIT source candidate: `FleetCore/License.swift` permanently unlocks features.
  Legacy license APIs remain for compatibility; no activation or trial is required.

The prior 2026-10-05 status recorded 141 passing Swift tests and a clean Rust check; these are historical results, not verification of subsequent edits.

## Composition

| Piece | Path | Role |
|---|---|---|
| `FleetConsole.app` | `Sources/FleetConsoleApp` | Menu-bar item, popover, console window. Client only — it never signals a process. |
| `fleetd` | `Sources/fleetd` | The controller. Supervises, health-checks, reaps, reconciles. Owns the SQLite registry and the append-only event log. `0600` Unix socket. |
| `fleetctl` | `Sources/fleetctl` | The operations CLI agents call instead of spawning processes themselves. |
| `FleetCore` | `Sources/FleetCore` | Models, evidence, registry, socket protocol, license gate, layout geometry. |
| `rust/fleet-proto` | `rust/fleet-proto` | The controller protocol in Rust — the port seam. |
| `rust/fleet-conformance` | `rust/fleet-conformance` | Proves the Rust types agree with the live Swift daemon. |
| Scripts | `Scripts/` | `build-app.sh`, `notarize.sh`, `install-agent.sh`, `design-audit.sh`, `surface-sheet.sh`, `churn.sh`. |
| Resources | `Resources/` | App icon, launchd plist, Yazi theme. |
| Tests | `Tests/FleetCoreTests` | Core behavior, including the license gate. |

## Documents

- `README.md` — what the app is, build/install, the three pieces, the rules.
- `docs/PRODUCT-SPEC.md` — screen-by-screen spec.
- `docs/DESIGN-SYSTEM.md` — FleetKit tokens and components.
- `docs/CLI.md` — every `fleetctl` verb.
- `docs/RUNBOOKS.md` — what a model is allowed to do.
- `docs/THREAT-MODEL.md` — entropy as adversary.
- `docs/AGENTS.md` — the contract for agents.
- `docs/SWIFT-6-MIGRATION.md` — concurrency record.
- `docs/TECH-DEBT-AUDIT.md` — full-repo audit (2026-08-02).
- `docs/REFACTOR-BLUEPRINT.md` — launch overhaul record.
- `docs/FREEMIUM.md` — trial, key format, offline mint, Ouros path.
- `docs/RUST-PORT.md` — rustification candidates, GPUI candidacy, resize.

## Decisions that shape the next work

1. **Rustification order.** `fleetd` → `fleetctl` → shell. The socket contract
   is already modeled in Rust; the daemon is ~2k lines and dependency-free, so
   it is the cheapest honest port. There is no GPUI dependency yet — a GPUI
   shell is a candidate, not a plan. See `docs/RUST-PORT.md`.
2. **Freemium through Ouros.** A store webhook (or the Ouros bar on the user's
   behalf) shells out to `fleetctl license --secret …`, the user pastes the key
   into the app, and the gate in `FleetCore/License.swift` opens. Ouros talks to
   the local socket already (`AgentMailClient.swift`); the license flow uses the
   same locality — no cloud validation.
3. **Limited source.** Not decided which targets open. Candidates: keep
   `FleetConsoleApp` closed, open `FleetCore`/`fleetctl`/`rust`.
4. **Resize.** The console window resizes freely on both axes (aspect lock
   removed); layout floors are derived in `FleetCore/ConsoleLayout.swift`.
   "Full free-form resizing within aspect-ratio views" remains unimplemented
   per-view — the window is free-form, the card grid flows, and charts are not
   aspect-constrained. See `docs/RUST-PORT.md`.

## Component verification

```bash
swift build
swift test
cargo check --manifest-path rust/Cargo.toml
```

For authorized release work, use `Scripts/build-app.sh release` and `Scripts/notarize.sh`; packaging is not required for documentation-only work. Live daemon conformance requires its own runtime evidence.
