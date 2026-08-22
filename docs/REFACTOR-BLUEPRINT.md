# FleetConsole — Refactor Blueprint
**Role:** Principal Product Designer / Full-Stack UX Architect
**Scope:** Full visual + UX + portfolio overhaul ahead of launch
**Evidence base:** 42 surface renders (`build/design/surfaces/`), `docs/DESIGN-SYSTEM.md`, `docs/PRODUCT-SPEC.md`, `Design/*.swift` token layer, `Scripts/design-audit.sh`, all Console module views.

---

## Phase 1 — The Audit (Redline Critique)

### What is already elite (do not touch, build on it)
| Asset | Why it's professional-grade |
|---|---|
| Token governance | `design-audit.sh` passes clean: zero literal fonts in view code, no opacity-on-colour, tones on a documented contrast ladder, Fibonacci metric ladder, mirrored constants, docs verified against code. This is rarer than any visual polish — it is the foundation of the whole story. |
| Semantic status system | Shape-before-colour encoding, five-tone ladder with per-tone ink, Differentiate-Without-Colour support. |
| Data typography | Monospace digits, right-aligned metric columns, dimmed root/system processes, tabular timestamps. This reads as a serious instrument. |
| Three-column console IA | Fleet / Module / Inspector is the correct spine. Keep it. |

### Redlines — the amateur tells, in severity order

**A. Trust breakers (fix before anything cosmetic)**

| # | Redline | Evidence | Verdict |
|---|---|---|---|
| A1 | Memory card reads "18.24 GB of 17.18 GB" | `console-overview-*` renders; `SystemMetrics.usedBytes = app + wired + compressed` (compressed counted pre-compression can exceed physical RAM) | A monitoring console that shows used > total looks broken, even when the math is defensible. Cap the display or relabel to "footprint". This is the single most damaging pixel in the app. |
| A2 | "air" sidebar row drops its metrics line | Overview render: three rows show `CPU% · RAM%`, the offline row shows only transport | Row schema must be invariant. Offline = `unreachable · last seen Xh ago`, same line count. |
| A3 | Raw OS strings leak into UI | Network popover: "name needs Location access" | Never surface Apple's permission copy. Summarize: "SSID hidden — Location access required", with a fix-action. |
| A4 | Identical "11s ago" on all four agent cards | `popover-agents-dark` | Either real relative times or absolute clock times. Same timestamp ×4 reads as mock data instantly. |

**B. Contrast floor violations (systemic, not local)**

The `.tertiary` rung sits too low against `backgroundPrimary` in dark mode. Recurring offenders:

- "Search the map" placeholder (Overview) — near-invisible
- "14.15 GB reclaimable" (Storage header) — the module's headline number, buried
- "Could it move?" rationale lines (Service inspector) — critical diagnostic info styled like disabled text
- Agent metric labels ("running", "launched") — 9pt-equivalent grey on charcoal
- Footer telemetry ("Thermal state nominal", "controller connected") — debug-text energy
- Process Map legend ("area = resident memory · colour = CPU") — the key to the whole viz is squinting-size

Rule: **nothing a user must read may sit below 4.5:1; nothing a user may act on below 3:1.** Raise the tertiary floor or promote these strings to secondary.

**C. Flatness where there should be depth**

| # | Redline | Fix direction |
|---|---|---|
| C1 | Service status strings ("Healthy", "Degraded") render as bare coloured text | They're not components, they're paint. Wrap in the Tag pill (tint fill + tone ink) the system already defines. |
| C2 | Light mode is the weak mode | White cards on white with no border/shadow read clinical and flat; chart strokes wash out. Light mode needs explicit elevation (hairline border + soft shadow) and darkened chart strokes. |
| C3 | Dark cards have no edge definition | One 1px top highlight (`ink @ 4–6%`) + inner shadow gives the "machined glass" depth Linear/Vercel use, without glassmorphism blur. |
| C4 | Empty terminal pane is a black void | A shell surface must always show a prompt, host banner, or "session starting…" line. Never raw void. |

**D. Clutter & cognitive load**

| # | Redline | Fix |
|---|---|---|
| D1 | Popover lists "search" in both Needs-attention and Services | Dedupe: items in the attention stack get a status pin inline in Services and are not repeated. |
| D2 | Agent cards show 5 metrics incl. "0 crashed · 0 left running · 0 to answer" | Zero suppression: show the metric, hide the zero; card collapses to one stats row of live numbers only. |
| D3 | "llama" row carries name + truncated subtitle + 2 tags + "8080 +2" + timestamp | One row = one job. Overflow tags become `+N`; subtitle truncates to one slot; ports pin width. |
| D4 | Lease explanation paragraph inside the inspector | Docs leakage. Move to a `ⓘ` disclosure; the inspector shows data, not essays. |
| D5 | Network popover truncates "Interfaces 3 of 26" mid-row | The popover must scroll or grow to its content budget; nothing clips mid-glyph. |
| D6 | "Load 300" floats disconnected from the list it paginates | Pagination belongs in the list footer, aligned with the list's right edge. |

**E. Iconography inconsistency**

- EntityIcons are outline style; StorageCategory legend icons are filled. Pick one register (outline for UI chrome, filled only where semantic legend needs weight) and document it.
- Process column mixes brand icons, folder icons, generic boxes, and circles. Rule: app icon if resolvable, otherwise the FleetKit default glyph — never three different fallbacks.
- The "?" on unmanaged listeners reads as placeholder. Give unmanaged its own deliberate glyph (e.g., dashed-contour box) so "unknown" looks designed.

**F. Motion & state**
Currently zero perceptible motion: no value transitions on gauges, no pulse on status change, no skeleton states. The boot-volume spinner is the only loading treatment and it looks unfinished. A console that never moves feels dead between snapshots.

---

## Phase 2 — Refactor Roadmap

### Tier 1 · Quick Wins (hours — pure token/data fixes, no layout risk)
1. Fix memory total (A1): display `min(used, total)` with "footprint" semantics; add swap as a separate labelled fact only.
2. Raise tertiary floor: dark `.tertiary` to ≥4.5:1 on `backgroundPrimary`; re-audit all six B-list surfaces.
3. Promote headline numbers off tertiary: "GB reclaimable", process-map legend, footer telemetry → `.secondary` at minimum.
4. Sidebar row schema invariant (A2): offline rows keep the line slot with `unreachable · last seen`.
5. Scrub raw OS strings (A3) behind a `UserFacing` formatter.
6. Wrap all status strings in Tag pills (C1); verify against the existing no-wrap rule.
7. Agent cards: zero-suppress metrics, real timestamps (A4, D2).
8. Popover dedupe attention items (D1); pin trailing column so "+2" can't drift (D3).
9. Process map label floor: minimum label size, drop labels below threshold instead of shrinking to illegible.
10. Terminal surface: prompt/banner instead of void (C4).

### Tier 2 · Structural Changes (days — UX flow)
1. **Inspector never empty** — replace the generic empty state with a Context Panel: device summary, snapshot age, top-3 movers. The right column is prime real estate; a dead panel is the most visible flaw in every screenshot.
2. **Unify Preferences/Settings** — one Settings window, one entry point; popover footer opens the same window anchored to the relevant pane. Kill dual terminology.
3. **Loading states as skeletons** — boot-volume breakdown, process table refresh, storage scan: shimmer-on-card skeletons matching final layout, never bare spinners.
4. **Event log pagination** — footer-anchored, right-aligned with the list; keyboard: `J/K` or arrows to page.
5. **Popover section grammar** — refresh/settings affordances either on every data section or on none; make "Listening" rows navigable (chevron) or explicitly read-only with a lock affordance.
6. **Evidence chips: restore icon opacity** — chip icons at ~10% are noise; raise to readable or remove.

### Tier 3 · Signature Features (weeks — the immersive layer)
1. **Hero 1 — The Fleet Map** (process treemap): hover-lift on blocks, animated re-pack on snapshot diff, click-to-inspect synced to the Context Panel, legend promoted to an interactive key. This is the one screen nobody else has.
2. **Hero 2 — Signal Glass depth system** (dark mode): the C2/C3 layer — 1px ink highlight, inner shadow, tone-tinted glow on critical chips — applied as one token set so every card gets depth for free.
3. **Hero 3 — Status Choreography**: one motion language for state change. A service going degraded pulses once (same curve, same duration) in the sidebar dot, the list row, the popover card, and the map block. Plus a ⌘K command palette across devices/modules/services — the fastest "pro" signal available.

---

## Phase 3 — Design Specs (top changes, buildable values)

### 1. Contrast floor (fixes all of B)
```
dark.tertiary:   raise ink ladder rung to 4.6:1 vs backgroundPrimary
                 (≈ #9A9A9F on the current charcoal; verify with audit script)
light.tertiary:  verify ≥4.5:1 on backgroundPrimary, same rule
Rule addition:   headline numbers and section summaries are forbidden on
                 .tertiary — they sit on .secondary at minimum.
                 Encode as a design-audit.sh check (grep for the three
                 known headline usages on tertiary).
```

### 2. Status Tag pill (fixes C1)
```
Container:  tint = tone.fill (2pt corner radius per token scale),
            1pt stroke = tone.color @ 35%,
            padding: 5pt horizontal, 2pt vertical
Text:       ConsoleFont.badge, tone.ink, kerning 0.4
Motion:     on tone change, cross-fade fill+ink 160ms ease-out
Never:      bare coloured status text anywhere; audit rule:
            no foregroundStyle(tone.color) outside Tag/StatusDot/Verdict
```

### 3. Card depth — "Signal Glass" (fixes C2/C3)
```
Dark card:
  fill:            surfacePrimary (existing)
  top edge:        1pt LinearGradient, ink @ 6% → 0% (first 24pt)
  inner shadow:    black @ 28%, radius 8pt, y +1 (top inset)
  outer shadow:    black @ 40%, radius 12pt, y 4pt — only for elevated
                   surfaces (popover, inspector, floating panels)
Light card:
  fill:            surfacePrimary (existing)
  border:          1pt, primary @ 8%
  shadow:          black @ 6%, radius 10pt, y 2pt
Charts (light):    stroke weight +0.5pt and darkened 10% vs dark-mode values
```

### 4. Fleet Map spec (Hero 1)
```
Labels:     name at caption; size value at badge; hide both below 44×28pt
            block; never shrink type — cull instead
Hover:      block lifts 1pt (shadow radius 6pt @ 30%), ink border 1pt,
            120ms ease-out; tooltip card with pid/cpu/rss
Selection:  1.5pt tone-neutral ring + sync to Context Panel
Re-pack:    animate rect frames 220ms ease-in-out when snapshot deltas
            change area ≥2%; no animation on colour-only updates
Legend:     interactive key, secondary text, pinned top-right of the map
            header with 8pt minimum touch target
```

### 5. Context Panel default state (fixes the dead inspector)
```
Layout (top → bottom):
  Device header      entity icon + name + StatusDot + transport line
  Snapshot line      "sampled 17:25:56 · 0.8s sweep" (mono, secondary)
  Top movers         3 rows, sorted by CPU, sparkline + delta arrow
  Attention          inline verdict stack if any warn/bad
  Shortcut footer    "⌘K to jump anywhere" tertiary hint
No icon-and-sentence empty state remains in the product.
```

### 6. Status Choreography (Hero 3)
```
Pulse:      any tone transition → one scale pulse 1.0→1.06→1.0, 240ms,
            ease-out, applied identically to StatusDot, Tag, sidebar row
            badge, map block border
Respect:    Reduce Motion → pulse becomes 160ms cross-fade
Snapshot:   value changes on gauges/counters tween 300ms ease-out;
            never hard-swap numbers
Skeleton:   shimmer = surfaceSecondary sweep @ 12% ink, 1.4s loop,
            only on first load of a module, never on refresh
```

### 7. ⌘K Command Palette (Hero 3)
```
Trigger:    ⌘K anywhere; popover-style panel, 520pt wide, top-third anchor
Rows:       entity icon + name + section tag + shortcut, 8 max, fuzzy match
Actions:    devices, modules, services, agents, "Open Settings",
            "Copy support bundle"
Motion:     140ms scale-fade in (0.98→1.0), matches popover entrance
```

---

## The FleetConsole Design Language (consolidated identity)

The system already has rules; what it lacks is a **name and a voice**. Proposed codification:

> **"Quiet chrome, loud signal."**

| Principle | Meaning | Enforcement |
|---|---|---|
| Signal over chrome | Every pixel of colour is data; the chrome stays neutral | tone ladder + audit rule 8 (fills/inks) |
| Shape before colour | State is geometry first, hue second | StatusDot/Verdict encoding (existing) |
| Evidence over opinion | The UI shows receipts (chips, logs, leases), never vibes | EvidenceChips as the honesty component |
| The ladder | Type, ink, spacing, and metrics climb fixed rungs (Fibonacci for metrics) | Tokens + audit rules 1/13 |
| Nothing dead | No void panels, no bare spinners, no identical timestamps | Context Panel + skeleton spec |
| Motion is state | Animation only communicates transitions, never decorates | Choreography spec |

Portfolio framing: FleetConsole is not "a dashboard with nice cards" — it is **a design system that compiles into an app**, with a CI-enforced styleguide (`design-audit.sh`), a single-file token layer, and docs that are mechanically verified against code. That governance story, plus the Fleet Map and the Evidence system, is the differentiator.

## Three Hero Elements for the Portfolio

1. **The Fleet Map** — custom treemap with live re-pack animation and synced inspection. Shot: dark mode, one hovered block, tooltip visible, inspector synced.
2. **The Evidence System** — EvidenceChips + lease + "Could it move?" verdicts in the service inspector. Shot: crashed service, failing chips in red, verdict stack visible. This demonstrates *design for trust*, which is rare in portfolios.
3. **The Governance Pipeline** — token ladder → audit script → docs parity, shown as a triptych: the token file, the passing audit output, and the resulting UI. No bootcamp portfolio has this. Lead the case study with it.

## Suggested capture order (for launch assets)
1. Overview dark, Fleet Map hovered (Hero 1)
2. Service inspector, crashed state (Hero 2)
3. Popover, attention stack deduped (quick-win proof)
4. Light-mode Storage with skeleton mid-scan (loading-state proof)
5. ⌘K palette over dimmed console (pro-tool proof)

---

*Every Tier-1 item is a token or data fix and can be landed without touching layout. Tier-2 changes are additive (Context Panel, skeletons) with no IA migration. Tier-3 is isolated behind feature flags if launch timing gets tight — ship Tier 1+2 first; the app already passes its own audit, so the launch risk surface is small.*
