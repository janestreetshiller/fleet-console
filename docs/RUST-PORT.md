# Rust port and trimming

Audit of what could move from Swift to Rust, and what could be trimmed, so the
app gets leaner without losing honesty. 2026-10-05.

## What already exists

- `rust/fleet-proto` — the controller's socket protocol as Rust types.
- `rust/fleet-conformance` — round-trips those types against the live Swift
  daemon. `cargo check` clean; the seam is real, not decorative.
- The daemon and CLI are dependency-light: `FleetCore` is models, evidence,
  registry (SQLite), socket, license gate — no UI. `fleetd` is launcher,
  supervisor, health, reconciler, devices. `fleetctl` is one file.

## Target order

1. **`fleetd`** (~2k lines). The controller is the natural Rust citizen:
   long-lived, headless, one socket, SQLite registry, no UI. The protocol is
   already modeled in Rust; a port replaces process supervision, health ticks,
   and the reconciler with Rust equivalents and keeps the wire identical.
2. **`fleetctl`** (~0.6k lines). Thin client over the daemon socket plus a
   few direct reads. Once `fleet-proto` covers the verbs, the CLI is the
   smallest honest port.
3. **The shell** — candidate only. GPUI (`gpui 0.2.2`, Apache-2.0, Zed's
   framework) runs on macOS Metal via `gpui_platform` + `font-kit` and is
   pre-1.0. There is no GPUI dependency in this repo today. A GPUI console
   would replace the SwiftUI view layer, not `fleetd`; that is a much larger
   move and should not start until the daemon port proves the protocol in Rust.

## What stays Swift for now

- `FleetConsoleApp` (~22k lines). SwiftUI popover + AppKit chrome + SwiftTerm.
  SwiftTerm is the project's one deliberate external dependency, and GPUI has
  no equivalent VT parser to swap in.
- `FleetCore` models until the daemon port defines the shared types.

## Trimming candidates (no port required)

- `Sources/FleetConsoleApp/Views/Console/Chrome/ToolSurface.swift` and the
  resize coalescer: one settled grid per gesture, already honest — keep.
- `DashboardWindowGeometry`'s history shows the aspect lock was once removed;
  the floors derived in `ConsoleLayout.swift` are the reason the free-form
  window still holds. Do not reintroduce a lock.
- Free-form resize per view is currently *window-level*: cards flow in an
  adaptive grid, telemetry charts are not aspect-constrained, heatmaps keep
  squarified-treemap semantics (area encodes bytes). If per-view aspect-ratio
  behavior is wanted — e.g., a fixed-ratio card that scales inside a
  free-form grid — it should land as a layout modifier on the card container,
  not as a window lock. Unimplemented; flagged here so it is a decision, not
  an accident.

## Rule

Do not start a Rust port until `fleet-conformance` is running in CI against a
live daemon. The seam only holds if the wire is checked continuously.
