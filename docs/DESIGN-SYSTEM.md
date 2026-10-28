# FleetKit — the UI toolbox

Every surface in FleetConsole (menu-bar item, popover Overview, popover Details,
console window, inspectors) is built from the components below. Nothing draws its
own row chrome any more.

The toolbox has two scales and one substrate. `Design/Theme.swift` is the
**popover ramp** (menu density, 13pt rows). `Design/Tokens.swift` is the **window
ramp** (`ConsoleFont` on dynamic text styles, `ConsoleMetrics`, `ConsoleColor`,
`StorageCategory` colours) used by the console window and its inspectors. A
surface uses one ramp or the other, never a mixture.

`Design/Sketchfield.swift` is neither: it is how everything is *drawn*, at both
scales — the page a window is on and the plate a card is. See **The substrate**
below.

**Why this exists.** The first build grew four separate row implementations that
each re-did hover state, highlight background, chevron rotation, expansion
animation and padding — and had drifted apart by a point here and a pixel there.
An audit found ~130 literal font sizes across twelve values, including pairs
separated by half a point (9/9.5, 10/10.5, 12/12.5). That is not a style, it is
sediment.

---

## Tokens — `Design/Theme.swift`

### Type ramp (`FleetFont`)

Sizes follow AppKit's own menu-bar extras — Wi-Fi, Control Center, Now Playing —
at 13pt primary and 12pt secondary. The first draft ran 9–12.5pt, which is
Xcode-inspector density rather than menu density: technically legible, and
immediately readable as *not a Mac app*.

<!-- fleet-font-table -->

| Token | Size | Used for |
|---|---|---|
| `marker` | 8 | a glyph that annotates a row without being part of its text |
| `plateLabel` | 8 mono | the plotted legend struck into a plate's top border |
| `nano` | 11 | stat-tile captions |
| `micro` | 11 medium | tags, badges, evidence chips |
| `chevron` | 10 semibold | the disclosure chevron, used only by `DisclosureRow` |
| `subtitle` | 12 | secondary line under a row title |
| `caption` | 12 | timestamps, counts, hints |
| `sectionLabel` | 12 semibold | section headers — sentence case, secondary |
| `rowTitleCompact` | 13 | primary text of a fixed-height row |
| `body` | 13 | body copy, table cells |
| `rowTitle` | 13 | primary text of a standard row — AppKit's menu item size |
| `title` | 14 semibold | popover title |
| `stat` | 22 semibold | stat-tile numerals |
| `mono(_:)` | — | ports, PIDs, paths, addresses |

Anything numeric that changes in place uses `monospacedDigit()` so it does not
jitter — including the menu-bar count.

### Metrics (`FleetMetrics`)

<!-- fleet-metrics-table -->

| Token | Value | What it is |
|---|---|---|
| `gutter` | 16 | horizontal inset for section content; AppKit menus use 14–16 |
| `rowInset` | 10 | inset for rows, which sit inside a hover-highlight margin |
| `rowHighlightMargin` | 6 | the margin that highlight sits in |
| `rowGap` | 10 | gap between a row's icon and its text |
| `rowVerticalPadding` | 7 | a standard row's vertical padding |
| `compactRowHeight` | 36 | fixed height for compact rows |
| `detailInset` | 28 | left inset of an expanded row's detail, aligning it under the text |
| `iconCompact` | 26 | icon in a fixed-height row |
| `iconRow` | 28 | icon in a standard row |
| `iconRowLarge` | 30 | icon in a standard row that leads a section |
| `iconButtonSize` | 28 | one `IconButton`'s hit target |
| `actionSlot` | — | `iconButtonSize` × 2 + 2 — a trailing cluster of two icon buttons, reserved at a constant width |
| `meterWidth` | 54 | utilisation meter — 5% and 15% distinguishable, still fits a row |
| `meterHeight` | 5 | the meter's bar |
| `coreCellWidth` | 7 | one column of the per-core grid |
| `coreCellHeight` | 22 | that column's height |
| `verdictColumn` | 8 | fixed column for a leading `StatusTone.verdict` glyph |
| `corner` | 5 | row highlight radius; AppKit menus use 5–6 |
| `tileCorner` | 8 | tiles, which sit above highlights |
| `tagCorner` | 3 | tags and micro capsules |
| `barCorner` | 2 | one core column, and any bar that narrow |
| `popoverWidth` | 480 | the popover, at every section |
| `popoverBodyHeight` | 300 | the clamp on the popover's body under its header |
| `sectionMaxHeight` | 540 | the scroll clamp on a section's body |

`EntityIcon`'s internals are ratios of its own `size`, not fixed points, so a
26pt row icon and a 38pt inspector icon are the same drawing at two scales:

| Token | Value | What it is |
|---|---|---|
| `iconCornerRatio` | 0.26 | the tile's radius, as a fraction of the tile |
| `iconGlyphRatio` | 0.46 | the identity glyph inside it |
| `iconBadgeRatio` | 0.34 | the corner status badge |
| `iconBadgeRing` | 1.5 | the badge's contrast ring, drawn with `strokeBorder` |

#### The two constants that hold a layout still

`actionSlot` and `sectionMaxHeight` are the popover ramp's answer to the same
question the console ramp answers with the Fibonacci ladder: *what stops a
number moving when nothing about the data moved.*

**`actionSlot` is reserved, never inserted.** A cluster of verbs that appears on
hover, or on one tab and not another, is a width that arrives and leaves — and
everything to its left slides to make room. The popover header hit this first:
Connections and Processes put up two buttons, Services and Agents one, and the
segmented picker beside them is `maxWidth: .infinity`, so *selecting a tab*
resized the control you select tabs with. The process rows had it one level
down and worse, because a row's trailing figure is the column the list is read
by: the usage numeral moved 46pt left the moment the pointer landed, and a long
process name truncated on hover and untruncated when the pointer left. Both hold
the slot at `iconButtonSize × 2 + 2` whether or not anything is in it. The verbs
still only appear on hover; the room does not.

**`sectionMaxHeight` is one number for four sections.** They share a popover —
the same header and picker above them, and nothing below — so a section that clamps
higher than its neighbour drags the popover's bottom edge with it on every tab
switch. It was four literals at two values (540 on Services, Agents and
Processes; 560 on Connections), which is the 9/9.5pt pair one layer up. Nobody
chose 560. It was typed beside the longest section, which is also the only one
carrying an admin footer — so the outlier was adding height to the tab that
least needed it, and the popover grew 20pt when you moved to Connections and
shrank 20pt when you moved away.

---

## Native surfaces — `Design/Sketchfield.swift`

The native app follows Apple’s Human Interface Guidelines: system text styles,
adaptive AppKit backgrounds, SF Symbols, native controls, and the user’s accent
color. Supporting console text uses `callout`; small values and badges use
`footnote`. Popover numeric text defaults to 12 points. Field labels use sentence
case and stay visible after entry.

The shared surface respects Reduce Motion. Card outlines strengthen with
Increase Contrast. Process and storage controls support keyboard activation.
Native material views follow the system’s Reduce Transparency setting.

The Devices sheet presents account access first. One prominent footer action
advances through **Sign In to Ouros → Subscribe for $10/month → Link Device**.
Device input remains unavailable until the server confirms paid access.
Subscription management, credits, refresh, and sign-out are secondary actions.

References: [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/),
[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility),
and [Fonts](https://developer.apple.com/documentation/technologyoverviews/fonts).

Window and card backgrounds use AppKit’s adaptive `windowBackgroundColor` and
`controlBackgroundColor`. Popovers retain their system material and arrow.
Cards have one separator border. Decorative layers neither intercept input nor
appear in the accessibility tree. There is no animated field, grain, graph
ruling, double border or tiny numbered legend.

Use system text styles for the window and the named popover ramp below.
Secondary text uses `secondaryLabelColor`; status text uses `StatusTone.ink`.
Color carries a reading or a status alongside a label, never the only meaning.
The user’s accent color marks selection and chart traces.

Navigation lives in a native sidebar with named destinations. The toolbar has
one search field, refresh, inspector visibility and a Tools menu. Search clears
when changing destinations; returning to the same destination preserves it.

---

## Status vocabulary

`StatusTone` — `good · warn · bad · neutral · unknown` — is the only place a
status colour is chosen. `ServiceState`, `DeviceHealth` and `AttentionSeverity`
all map into it, so one concept cannot be green in one view and blue in another.

It lives in `Design/StatusTone.swift`. It used to live at the top of
`Views/Components.swift`, which made the sentence above false in the one way that
mattered to the audit: rule 3 exempts `Design/` precisely because that is where
naming a hue is the point, so with the vocabulary in the view layer the exemption
did not reach it and `case .good: return .green` was indistinguishable from drift.
A rule whose single legitimate exception has to be special-cased by filename is a
rule with the file in the wrong place.

A tone has **two colours**, because a fill and a word need different ones.
`color` fills; `ink` writes. Reusing the fill hue as small text on a 14% tint of
itself measures **1.98:1** (`good`), **2.06:1** (`warn`) and **2.95:1** (`bad`) in
light mode — every tone under AA's 4.5:1, on labels like "Expired", "Leaked" and
"Unmanaged" that exist to be read at a glance. Dark mode passed all along at
4.17–6.34:1, because a saturated hue against a dark fill is doing a different job
than against a pale one, so the correction is per-appearance rather than one
darker green: `ink` moves the hue toward the label colour by the smallest fraction
that clears AA, solved against `NSColor.blended` itself (light needed 26–43%, dark
0–8%). `Tag`, `ConsoleBadge` and `EvidenceChips` all draw with `ink` and fill with
`color`. `Meter`, `CoreGrid` and the heatmaps are fills only, and keep `color`.

`neutral` and `unknown` resolve to the system's own secondary label instead. They
are greys derived from `secondaryLabelColor`, which is translucent by definition,
so their text and their fill darken together and no blend reaches 4.5:1 — 3.83:1
is what macOS itself ships for secondary text, and clears the 3:1 floor for UI
components. `unknown` used to halve that again to 1.82:1, which was the part that
actually needed fixing.

### Tints — the four strengths

A tone is used at four strengths, and before they were named it was used at
**nine**: `0.07` and `0.08` and `0.10` for one row wash, `0.12` and `0.13` and
`0.14` and `0.16` for one chip fill, plus `0.35` and `0.75`, across seven files.
Nobody chose those numbers. Each was typed once beside whatever was already on
screen, which is precisely how 9pt and 9.5pt came to mean the same thing.

| Token | Strength | Job |
|---|---|---|
| `wash` | 8% | a tinted background behind a whole row or banner |
| `chipFill` | 14% | the fill under a chip, tag or badge — the tint `ink` was solved against |
| `edge` | 35% | a tinted border, strong enough to read at one point wide |
| `stroke` | 75% | a tinted line: a sparkline, a meter outline |

### `SurfaceInk` — the achromatic half

`Color.primary` was carrying seven strengths — `0.04, 0.06, 0.7, 0.75, 0.8,
0.85, 0.9` — for four ideas. `SurfaceInk` names them once:

`numeral` (a measured value — mono digits, a stat numeral, a byte count; one step
under `.primary`, because `.secondary` means *supporting text* and would put a
resident-memory figure at the same weight as the word beside it) ·
`surfaceWash` (a chip or card at rest) · `hoverWash` · `selectedWash` ·
`indicatorOn` / `indicatorOff` (a signal bar, lit and unlit) · `dim` (a value
that is absent, or a control that is unavailable) · `outline` / `outlineStrong`
(an untinted border; the strong one survives a saturated fill under it).

The ramps share these through `SurfaceInk` and `ConsoleColor`, and both resolve
to the same values. That is deliberate, and it is a refinement of the sentence at
the top of this file: the ramps differ in **type and metrics**, because a 13pt
menu row and a dynamic-type window row are different reading distances. They do
not differ in what a colour *means*. Giving each its own `numeral` at 0.80 and
0.85 would be the 9/9.5 pair again, one layer down.

`FleetColor` keeps only the popover-specific names still used by the popover
surface: `numeral`, `surfaceWash`, `indicatorOn`, `indicatorOff` and `countPill`.

---

A tone also has **two** glyphs, because one cannot do both jobs.

`symbol` is the enclosed badge — `circle.fill`, `exclamationmark.triangle.fill`,
`xmark.octagon.fill` — for a standalone dot, where the ring is what makes it read
as a deliberate indicator rather than a stray mark.

`verdict` is the bare glyph — `checkmark · exclamationmark · xmark · minus ·
questionmark` — for anywhere the state has to survive without colour.

This split is measured, not stylistic. Rendering the tones as silhouettes at
8–13pt and comparing them pairwise by intersection-over-union puts `good` against
`bad` at **0.87**: a filled circle and a filled octagon are the same blob once the
mark inside them is two points wide, so the app's single most important
distinction — healthy against failed — was carried by hue alone. Reshuffling the
set does not fix it. Every enclosed vocabulary bottoms out at 0.85–0.91, and the
obvious "more native" swap to `checkmark.circle.fill` / `questionmark.circle.fill`
scores **worse** (0.91), because those two are near-identical. The enclosure is
the problem: it is most of the ink and it is common to every tone. Drop it and the
worst pair falls to **0.24**.

So: colour plus `symbol` where colour is available, `verdict` where it is not.
`EvidenceChips` uses `verdict` unconditionally — its label names the subject
("process", "port", "health"), so nothing else there was carrying pass from fail.
`StatusPip` swaps to `verdict` under **Differentiate Without Colour**, since a lone
pip has no text beside it to fall back on. `EntityIcon`'s corner badge carries one
too, white on the tone fill, the way macOS draws an overlay badge.

`unknown` is a real tone, not a fallback. Stale evidence and un-run probes render
grey rather than inheriting their last-known-good colour.

`SystemThresholds` is the matching single source for *when* a resource number
turns amber or red, so CPU and GPU cannot disagree about what "busy" means. The
bands are deliberately generous (amber at 75%, red at 90%) because a monitor that
goes red whenever a build runs teaches you to ignore red. Free space is the one
exception and warns early, since a disk at 99% is already failing writes.

---

## Components

### `EntityIcon(symbol:tone:size:badge:)`
The rounded tinted tile that leads every row. **Tint = status, symbol = identity.**
A service does not change what it *is* when it becomes unhealthy, so the symbol
stays put and only the colour moves.

The corner badge is anchored **inside** the tile. It used to be pushed out past
the corner with `.offset(x: size * 0.08, y: size * 0.08)`, and because `.offset`
is a draw-time transform that never changes the size a view reports, the tile
still measured `size × size` while painting **2.1–3.0pt outside it** at the four
icon sizes the app uses. That is unreserved overflow: it ate into the row's
icon-to-text gap on badged rows only, so a badged row and an unbadged row did not
start on the same vertical, and any ancestor that bounds its content would have
cut the badge off. Anchoring it with the `ZStack` alignment and no offset measures
0.00pt of spill at every size.

### `Iconography`
Maps a thing to its symbol by role, not by state: `curlybraces` (Python),
`hexagon` (Node), `diamond` (Ruby), `shippingbox` (containers),
`cylinder.split.1x2` (databases), `server.rack` (anything listening),
`gearshape.2` (a job with no port), plus machine and interface symbols.

`Iconography.Metric` covers the host resources: `cpu`, `circle.hexagongrid.fill`
(GPU), `memorychip`, `internaldrive`, `thermometer.medium`. These four rows are
adjacent and permanent, so they follow the menu-bar rule about silhouettes — the
GPU symbol is a cluster of small units precisely so it cannot be read as the
square chip outline next to it. SF Symbols' own `gpu` is not available on
macOS 14, which is the deployment target.

### `FleetRowLabel(icon:tone:badge:title:subtitle:trailingText:accessory:)`
Icon + title + subtitle + optional trailing text and accessory view.
`inlineSubtitle` puts the subtitle beside the title (compact rows) instead of
under it (standard rows). Combines into a single accessibility element.

`trailingText` is `fixedSize`, for the reason `Tag` is — and it was not, for as
long as it existed. The two sit in the same `HStack`, opposite a title holding
`layoutPriority(1)`, and a trailing text is a timestamp, a port or a duration:
short, complete, already abbreviated. Unpinned it loses the width contest and
truncates, which the surface sheet caught doing all three Needs-attention rows
at once — `12…`, `2m a…`, and one clipped to the single character `1`. A
truncated timestamp is not a shorter timestamp; `12…` is twelve minutes or
twelve hours or twelve days. The title is the right loser, since it is one line
already and its full text is in the subtitle and the tooltip.

Worth recording as a *checking* failure rather than a coding one. `Tag` carries
six lines of comment making this exact argument and an audit check of its own
named "Tag pins its own width" — one check per struct, so the rule protected the
instance it was written against and not the invariant it states. The check is
now two, and the second one is anchored on a line that is only the modifier, so
the paragraph explaining why `fixedSize` is there cannot pass for its being
there.

### `DisclosureRow(id:expanded:label:detail:)`
The expand-in-place row. Owns hover state, highlight, chevron, animation, padding,
help text and accessibility traits. Rows supply content, never chrome.

### `SectionHeader(title:subtitle:trailing:)`
Uppercased label with an optional count and trailing `IconButton`s.

### `EvidenceChips(evidence:health:stale:)`
The four-pillar honesty component — process / port / health, plus a `stale` chip.
Each chip is grey when its fact was never established, and its tooltip states what
was actually checked. The chip leads with the tone's `verdict` glyph, sized to the
label beside it, so pass / fail / never-ran is readable without colour — a
coloured dot next to the word "port" says nothing about the port.

### `Meter(value:tone:caption:)`
The horizontal utilisation bar, with its numeral beside it. `value` is optional:
a rate is the difference between two samples, so there is a real moment — the
first tick after launch, or a key the GPU driver declined to publish — when there
is nothing to draw. That renders an empty grey track and a dash, never a
confident bar at zero. Rule 4, applied to a number instead of a chip.

### `CoreGrid(values:topology:)`
One column per logical core, grouped into efficiency and performance clusters.
A single aggregate CPU number hides what you actually want to know on Apple
Silicon — whether the machine is busy or merely tidying up in the background.
The cluster split comes from `hw.perflevel*`, and the fact that Mach enumerates
efficiency cores first is asserted against a loaded core, not assumed.

### `StatTile` · `CompactRow` · `Tag` · `KeyValue` · `ProbeLine` · `IconButton` · `RowActions` · `ConnectionPip`
Stat tiles head the Overview; `CompactRow` is the fixed-height row that makes it
scroll-free; `ProbeLine` renders one reachability probe identically in the device
row and the device inspector; `ConnectionPip` is the one place a bare dot survives,
because a footer has no entity to identify — only a state.

---

## Console window — `Views/Console/`

The console is a three-column `NavigationSplitView` in an AppKit-hosted window
(unified-compact toolbar, hidden title, `.fullSizeContentView`). Column one is
the fleet mesh (This Mac + remote nodes with reachability, latency and path
evidence), column two is the active surface — Home (⇧⌘H) or one of the six
modules (⌘1…⌘6) — and column three is the inspector: a *view of* the current
selection, never a selection of its own.

Column one is **one list**, not two. This Mac and the remote nodes were split
across an unlabelled section and a "Fleet" section, which drew a boundary where
there is no distinction — they are all machines you own, and all of them are the
fleet. The local machine leads because it is what every local module describes,
and it is marked as *this* one by its row rather than by being fenced off above a
header. The column is also sized to what it actually holds: at the previous 224pt
ideal both lines elided — "crw's Mac…" over "59% CPU · 67%…" — which turns the
one always-visible column into a column of abbreviations and hides exactly the
digits it exists to show.

### Chrome primitives — `Design/ViewModifiers.swift`

| Primitive | What it is |
|---|---|
| `Hairline` / `.hairline()` | `Color.primary.opacity(0.08)` surface edges. Replaces `Divider()` wherever a *boundary*, not a separator, is drawn |
| `.elevatedCard(_:)` | An adaptive native card fill with one separator border. See **Native surfaces** |
| `.hoverHighlight()` | 6% fill on hover; rows never scale or change weight |
| `StatusPip(tone:pulsing:)` | The live health dot; reachable nodes breathe on the probe cadence, Reduced Motion stills it |
| `ConsoleBadge` | Mono-digit capsule for counts and latencies |
| `VisualEffectBackground` | NSVisualEffectView for spots that need guaranteed behind-window material |

### Telemetry — `TelemetryCharts.swift`

Swift Charts plots timestamped local observations. CPU and memory lead the
Overview, with 233pt plots together and a 377pt plot when one metric is focused.
Time zoom offers 15s, 30s, 1min and 2min; the visible observations retain peaks and
sampling gaps. Linear interpolation connects observations without inventing
smooth overshoot. The logo, series hues and gradient fill remain pending owner
artwork and color choices.

Utilization uses a labelled linear y window with a minimum 15-point span.
Throughput uses a labelled log axis with a 1 KB/s floor. Secondary charts use
144pt plots. Compact service history, which carries no timestamps in the wire
contract, keeps its sample axis hidden rather than inventing wall-clock times.

Components: `TelemetryCard`, `LoadWaveChart`, `ThroughputChart`, `LegendDot`.

### `RetroGauge(value:tone:caption:readout:)` — `Design/RetroGauge.swift`

A 240° analog dial for a bounded 0…1 metric, beside the trace that carries its
history. It earns its place by doing something the flat vocabulary cannot: a
needle is read as a *position on a fixed scale* without being decoded, while a
numeral has to be compared against a range you hold in your head. "77%" does not
tell you whether 77% is anywhere near the top; a needle two ticks under the red
band does, before you have read the number.

It used to be a machined instrument — a filled face, a radial shade to recess
it, a two-stop gradient bezel lighting it from the top-left, and an Aqua
highlight over the top third. All four were arguing with the substrate: a lit
plastic dial floating over a drifting field is an object photographed onto a
page. What is drawn now is what a compass leaves —
the outer circle, the dashed inner circle the tick ladder was measured from, and
a pivot in the plate's own colour with an ink ring round it. Nothing is filled,
so the plate and the field show through the scale. Every dimension, threshold
and accessibility behaviour below is unchanged.

It inherits the rest of the system unchanged:

* **Colour stays a status vocabulary.** Construction, ticks, hub and readout are
  achromatic in both appearances. The only hue is the tone, in exactly two
  places — the value arc and the needle.
* **Nothing depends on colour alone.** The angle carries the value, the readout
  carries the number, and Differentiate Without Colour adds the tone's `verdict`
  glyph to the face.
* **No confident zero.** `value: nil` — a rate with no previous sample, a GPU
  that withheld its utilisation key — parks the needle at the zero stop *dimmed*,
  drops the value arc entirely rather than drawing it zero-length, and reads
  "—". A needle at rest and a needle with no reading must not look alike.
* **The redline is drawn on the track, not on the value**, because it is a
  property of the scale and has to be visible when the needle is nowhere near
  it. Its threshold comes from `SystemThresholds`, so the band and the needle's
  colour cannot disagree about what "bad" means.
* **Reduce Motion** stops the sweep; the needle steps between samples instead.

The face carries no label: the card two points to the right already says
"Memory", and at 92pt the word is set across the arc rather than inside it.
`caption` survives as the accessibility label, the one place the name is not
already on screen.

One case is worth knowing: the **disk** card's dial reads capacity while its
trace reads throughput. Deliberate — a needle needs a bounded scale, and byte
rates are the unbounded series that made the chart below it logarithmic. A dial
whose full deflection meant "the fastest rate seen this session" would be a scale
that silently rewrites itself.

### The scale — `FleetCore/ConsoleLayout.swift`

Two rules, and everything fixed in the window follows from them.

**The ladder.** Every fixed dimension is a Fibonacci rung — 2, 3, 5, 8, 13, 21,
34, 55, 89, 144, 233, 377. Adjacent rungs are a φ ratio apart, which is far
enough that any two sizes read as a deliberate relationship and never as the
9pt/9.5pt pair the audit exists to prevent. This is less an invention than a
confession: the values already in the app were reaching for the ladder and
missing — 236 against 233, 88 against 89, 20 against 21, 12 against 13.

**The golden section.** Anything dividing the *window* divides it at φ. The
content column takes the major section; the two side columns share the minor one
**equally**, which is what makes them mirror images. The content column was
already 62.3% of the composed width — 1/φ to within half a point — so this too
was latent.

Strokes are deliberately below the ladder's floor: a 1pt line and a 2pt line are
two weights of one mark, not two steps of a hierarchy.

Rule 13 of `Scripts/design-audit.sh` checks every `ConsoleMetrics` dimension
against the ladder, and `Tests/FleetCoreTests/ConsoleLayoutTests.swift` checks
the budget those feed — that the ladder is Fibonacci, that the two side columns
are equal at every width, that the content column really is the major section
where unclamped, and that the arrangement fits at the minimum window size *and
does not one point below it*.

That last one is a regression test. `columnReserve` — what the three columns and
the rail must keep — summed to 786pt against a window whose minimum content
width was `defaultContentSize.width / 2` = 780. At the narrowest size the user
could drag to, the reserve exceeded the whole window and the module column fell
under its own floor. The comment beside it cited a 1060pt minimum that had not
existed for some time. Three numbers, two of them wrong, none of them checkable.
The window's minimum is now *derived* — one side column, the module column, the
rail and a panel's floor — and comes to 982.

Height joined it. For as long as the window was aspect-locked there was no
height budget to have: the minimum height was `minimumContentWidth /
contentAspectRatio`, which is not a statement about content, it is the lock
talking. With the lock gone height is a free dimension and gets a floor derived
the same way — a module header plus one whole card, because below one card the
window is showing a cropped instrument, and a cropped dial is exactly the
confident-wrong-answer failure the rest of this document is organised against.

`ConsoleLayout` also restates four view-layer dimensions it cannot import
(`chartHeight`, `cardPadding`, `toggleSize`, `railSpacing`). A restated number
drifts, so the audit compares every mirrored name against the token of the same
name and fails if they disagree. That check exists because `railWidth`'s comment
claimed to be "asserted equal by test" from the day it was written and never
was — `FleetCoreTests` cannot see `ConsoleMetrics`, so the assertion it named
was not a thing that could be written. A mirror guarded by a sentence is not
guarded, which is this document's oldest lesson applied to itself again.

### The butterfly — mirrored side columns

The fleet mesh and the inspector are one column reflected: same width at every
window size, same easing (`ConsoleAnimation.column`, critically damped so a
column carrying a table never overshoots and settles back), same floors and
ceilings. They had drifted to 236/268/320 against 280/320/420 — 52pt more
inspector than sidebar at rest.

Getting there meant taking the inspector **out** of `NavigationSplitView`. It was
column three, and hiding it swapped the whole split view for a two-column one — a
different view type, so SwiftUI tore the tree down and built a new one. That is
why the inspector blinked while the sidebar slid: there was no transition to
animate, there was a structural replacement, and every toggle rebuilt the sidebar
and the module column for a change concerning neither. It is now a sibling in the
same `HStack` as the tool rail, which is the arrangement the rail has always used.

The sidebar takes the **exact-width** `navigationSplitViewColumnWidth(_:)`, not
`min:ideal:max:`. With the three-argument form the two sides did not mirror, and
measuring a render is what showed it: 224pt of sidebar against 275pt of
inspector, from one number handed to both. SwiftUI treats `ideal` on a split-view
column as a preference it may override. A mirror where one half is advisory is
not a mirror.

### Heatmap tiles — a gutter, not a stroke

Neighbouring tiles are separated by `ConsoleMetrics.mapTileGutter`, half taken
off each side of a tile's computed rectangle, rather than by a border. The stroke
it replaces was `Color.black.opacity(0.18)` at 0.5pt, documented as reading "on
the pale fills as well as the saturated ones". It did not: against a saturated
fill it was invisible, so two adjacent tiles of similar colour merged into one
shape and the map lost the boundary it exists to show. A gutter costs no colour
decision, survives both appearances against every fill the maps produce, and
lands on whole pixels at any scale factor. Every tile gives up the same margin,
so the ratios between masses — the only thing a treemap claims — are preserved,
while no tile pretends its rectangle is a measurement.

Tiles animate on **their own frame**, not on the data. The map used to carry one
`.animation(_:value: items)` outside the `GeometryReader`, so a data change
animated and a *size* change did not — and every tile's rectangle is computed
from `geometry.size` inside that reader. Resizing the window, opening the
inspector or dragging a tool panel changed all forty rectangles with `items`
untouched, and the map snapped in a single frame. That was the case you see most
often and the one case not animated. Keying each tile on its frame covers both
causes, because a squarified relayout *is* a set of frame changes whatever
provoked it.

### Module layout — quantized peer footprints

`QuantizedCardGrid` measures every visible peer at its final equal column width,
then rounds the tallest height **up** to `ConsoleMetrics.gridQuantum` (8 points).
Every peer in that section uses that complete footprint, including the last row.
Cards expand before their fill and border are painted. A common minimum height
alone does not align cards with wrapped subtitles or additional facts.

Telemetry and reclaim grids retain their respective content width floors. The
column helper avoids a lone last item in grids of three or more columns. The
layout responds directly to width proposals without publishing measured width
through view state. GPU and battery visibility determine the actual peer count.

Compact storage chips, tool badges, interpreter presets, agent statistics and
memory facts derive their cell width from the widest intrinsic peer, rounded up
to the same quantum. Device capability cells and popover metrics share equal
cells within their width budget. Reclaimable caches and reported user data remain
separate sections with separate actions. Each section recomputes its footprint
when text, readings, membership or window width changes.

Interpreter presets live in a bounded vertical scroll area so a one-column
chooser remains accessible at the shortest supported tool-panel height and
leaves room for Run/Cancel and the answer. Treemap areas, storage-bar proportions
and graph values continue to encode actual measurements. Narrative lists and
expanded inspectors retain content-driven heights; their fields are distinct
from a section of interchangeable peers.

`TelemetrySeries` (`Design/Tokens.swift`) owns the colour *and* the label of the
two throughput series. Both were previously written twice — `Color.teal` /
`Color.orange` on the `LineMark`s here, and `.teal` / `.orange` again on the
`LegendDot`s over in `OverviewModule`. A legend is a claim about what a trace
means, so a legend that can drift from its trace by one careless edit is the
exact failure this toolbox exists to prevent. Naming the series makes the chart
and its key the same fact.

### Modules and inspectors

The module list is `ConsoleModule`, in `Design/ConsoleModule.swift`. It is a
design declaration before it is navigation state: `ConsoleMetrics.modulePickerWidth`
is `modulePickerSegment × allCases.count`, so adding a module widens the toolbar
picker rather than clipping the last segment. It used to sit at the top of
`Views/Console/ConsoleModel.swift`, which pointed the dependency the wrong way —
a token in `Design/` reaching up into the view layer — and put the enum out of
reach of `Scripts/fleetkit-sheet.sh`, which symlinks only the design sources, so
the contact sheet could not render the real picker width without either a stubbed
module list or the whole console object graph. The enum touches neither
`ConsoleModel` nor `AppModel`; the state that navigates *between* modules still
lives in `ConsoleModel`.

`HomeModule` (`Console/Chrome/`) is the landing surface, not a module — it has no
⌘-digit and no entry in `ConsoleModule`, because the digits are an index into that
enum and a surface that is not in it must not consume one. ⇧⌘H reaches it.

No surface carries a page header. The sidebar's selection already names the
page, and a title row restating it — `ModuleHeader`, with a subtitle beside it —
was a second toolbar charged to the content's height: on Overview it was most of
why a 1560-wide window drew its traces 82pt tall. A module whose page has
controls opens with a `ModuleControlBar` holding only those controls (Overview's
chart focus and time range, Processes' scope, Launch Services' reload); a module
without controls opens on its content. Storage's *Scan Now* sits on the
breakdown card it re-measures, and a remote device is named by its reachability
card. Its second card is labelled **Modules**, not
"Go deeper": the rows under it are exactly `ConsoleModule.allCases`, the same six
names the picker and the View menu use, and a section label names its contents
rather than instructing the reader.

The six modules are `OverviewModule` (CPU wave + core grid, memory, process map,
disk I/O, GPU, and the SMC **Sensors** card — fan RPM and CPU/GPU die
temperature, a premium feature that renders its three states honestly: locked,
no SMC (VMs, very old Macs), no keys (Apple silicon)), `ProcessModule` (below), `StorageModule` (`SegmentedStorageBar` +
disk map + volumes + reclaim), `ServicesModule`, `EventsModule`, and
`PlistsModule` — **Launch Services**, the launchd jobs on this machine across
three scopes (`~/Library/LaunchAgents`, `/Library/LaunchAgents`,
`/Library/LaunchDaemons`). It shows label, `RunAtLoad`, program or program
arguments, `KeepAlive`, and whether `launchctl list` reports the job loaded —
and the inspector shows *every* raw plist key, so nothing is hidden behind a
field mapping that has not been written yet. **Read-only throughout**: it never
loads, unloads or edits a plist. That is the services rule applied to launchd —
a job someone else registered gets visibility, not a button. It is also the one
surface that shows fleetd from the outside, since the controller's own agent
lives in the first of those directories. `DeviceDetailView` covers remote nodes.
Inspectors: `ProcessInspector` (libproc task info, process tree,
ports, connections), `VolumeInspector` (capacity, purgeable, APFS snapshots),
`ServiceInspectorView` (evidence, lease, fleet placement verdicts, log tail,
timeline), `UnmanagedInspectorView`, `DeviceInspectorView`. Shared inspector
chrome is `InspectorCard` / `InspectorLine` / `InspectorActionButton`.

### `ProcessModule` — the process table

A native SwiftUI `Table` with `KeyPathComparator` sorting, a scope filter
(All / Managed / Listening / Heavyweight), and a per-row context menu whose verbs
are the threat model rendered honestly — managed services are signalled *through
the controller*, everything else gets read-only verbs and a disabled **Kill
Process** carrying its reason. `.tableStyle(.inset(alternatesRowBackgrounds:))`,
so the row height, header, sort indicators, alternating fills and column
resizing are AppKit's, not a hand-drawn imitation of them.

Columns: Process · PID · User · CPU · Memory · Ports. The four that are
*measurements* draw in `ConsoleFont.mono` with `monospacedDigit()`, so a number
that changes in place does not shift the column under it; Process and User are
names and stay in SF Pro. Every column has a `min`/`ideal`/`max` width rather
than a fixed one, so the table is one composition across the window's size range
instead of a layout with a correct width.

Two cells were saying things the module did not mean:

* **CPU** drew in `tone.color`, the *fill* hue, as text on the window background
  — rule 8, on the one column whose colour carries the reading. It is `tone.ink`
  now, which is the same hue moved toward the label colour by the smallest
  fraction that clears AA.
* **Ports** drew its em dash in `Color.clear` when a process had none. That paints
  nothing while still handing VoiceOver a "—" to read: blank to the eye, dashed to
  the ear, and an empty cell in a table is ambiguous between "no ports" and "not
  sampled yet". The dash is drawn, in `.tertiary`, with an accessibility label
  that says *No listening ports* — rule 4, on the smallest thing it applies to.

### `ProcessesContent` — the menu-bar processes surface

Two short lists, not a small copy of the module's table: **top by CPU** and **top
by memory**, five each. Those are usually different processes, and one ranking
hides whichever axis you did not sort by. Everything past that question is one
click away in the dashboard, which is where a table belongs.

`ps -o state` is now captured (`ProcessTable.Proc.state`) and interpreted by
`ProcessState`. Three of its seven cases are **neutral** — running, sleeping and
idle are all completely normal, and colouring "running" green makes a process
list a wall of green that says nothing. Only `stopped` and `uninterruptible`
(amber) and `zombie` (red) get a hue, because those are the two you would act on.
The state word only appears on a row whose tone is not neutral: a tag on every
row is a tag on no row.

CPU severity comes from `SystemThresholds.cpuActivity`, the same source the
console module uses, so "busy" cannot mean one thing in the menu bar and another
in the window. The memory list is deliberately achromatic — 400 MB is normal for
a browser tab and alarming for a shell, so there is no honest single-machine
threshold, and the ordering carries the ranking instead.

#### End Process — three gates

The app's standing rule is unchanged: **the controller never signals a process it
did not start.** This verb is not the controller. It is a signal *you* send, from
a row you are looking at, and it holds three gates that must all pass:

1. **Ownership.** `uid == geteuid()`, compared as a number rather than by
   username, because a name can repeat across a uid boundary and the kernel only
   cares about the number.
2. **The flag.** `ui.features.allowProcessTermination`, **off by default**.
3. **Identity.** The pid's `lstart` is re-read and compared to the signature the
   row was built from — the PID-reuse guard (threat model T2) applied to a
   process nobody supervises. The sampler runs every few seconds and a row can
   sit on screen for minutes, so "the pid in front of me" and "the pid I am about
   to signal" are genuinely different claims.

All three are re-evaluated inside `terminate`, not trusted from the caller: the
alert you confirmed was drawn from a snapshot, and that is the last moment before
the syscall. The signal is **SIGTERM only** — there is no escalation to SIGKILL,
because the controller escalates for services it launched and owns the
consequences, and this does not.

A blocked verb renders **disabled with its reason attached**, never hidden. The
reason is usually "the flag is off", which is a thing you can go and change;
hiding the button would leave no trace that the setting exists.

### `NetworkAdminSection` — routing, resolvers, interfaces

The connection rows answer *what am I attached to*. This answers the two
questions you ask next: **where do my packets go** and **who do I ask for
names**. Both were missing, which meant the surface could tell you Wi-Fi was
associated and could not tell you the gateway had stopped answering.

`RoutingProbe` reads `netstat -rn` (both families), `scutil --dns` and
`ifconfig -a`. Only the first `scutil` block is parsed: the scoped section
repeats the same resolvers once per interface and would read as a
misconfiguration.

**Two parsing bugs are worth recording, because both shipped a confident wrong
answer rather than an error.**

`ifconfig` prints exactly two link values and one of them is **inactive**, which
*contains* the string `active` — so `line.contains("active")` reports link on
every interface that has none. The first render of this section listed **22 of 26
interfaces** as linked, including three empty Thunderbolt ports and eight spare
tunnels. The same substring test was in `probeEthernet`, where it had been
invisible for as long as it existed because a later `ipv4 == nil` guard happened
to override the wrong answer. Both compare the parsed value now.

The interface filter had the same shape of failure. `isInteresting` accepted
`!ipv6.isEmpty`, and macOS auto-configures an `fe80::` on essentially every
interface it brings up — so the filter written to stop the section burying the
four interfaces that matter listed all 22 of them. The bar is a **routable**
address, a VLAN tag, or a live link on a port you can physically plug into. On
the machine this was written on that is *2 of 26*.

Link is also not asked of interfaces that cannot answer: `ifconfig` omits
`status:` for tunnels and bridges, and treating that absence as *no link* painted
a working Tailscale tunnel amber. `hasCarrier` decides whether the question
applies; `tone` and `statusLabel` are derived once on the model, so a row's
subtitle and its expanded detail cannot describe the same interface differently.

Actions are read-only or clipboard-only: copy an address, copy a subnet, ping,
traceroute. Both diagnostics run off the main actor with a hard deadline
(`-c 4 -t 6`; `-n -w 1 -q 1 -m 12`), because a traceroute to a dead gateway takes
as long as its own patience and a menu that hangs is not a menu. Output lands in
place, monospaced and horizontally scrollable — a popover that opens a window to
show four lines of text has lost the argument for being a popover.

The rows say **As of**, not *Checked*. `RoutingStatus` is republished only when
its content changes, because `checkedAt` moves on every pass and a plain `!=`
would reassign an `@Observable` array of a dozen interfaces every refresh
interval forever. The timestamp is therefore when the picture was established,
which is what the label says.

#### The admin-console footer

`AdminConsole` is an enum with a `network` case and a `vlan` case, not two
hard-coded buttons, so the VLAN console is a `case` and a config key rather than
a second footer with its own layout.

The network console's URL **resolves**: with nothing in config it is
`http://<default gateway>`, which is the router admin page on essentially every
home and small-office network and needs no setup. With no gateway there is no
URL and the button is absent — the capability rule, applied to a link.

Beside it, **Support Bundle** copies a sanitised JSON snapshot. It is an
*encoding of the model the screen already renders* — the probe structs are
`Codable` precisely so a diagnostic cannot drift from the thing it claims to
describe. Private addresses (RFC 1918, link-local, and the CGNAT range Tailscale
uses) are kept, because they describe your topology and are the whole reason to
send it; public addresses become `‹public IPv4›`, MACs become `‹mac›`, and the
Wi-Fi SSID becomes `‹ssid›` while *associated or not* survives, because
association is the diagnostic and the network's name is a location fingerprint.
Resolvers are deliberately **not** masked: "which DNS am I using" is usually the
question, and `1.1.1.1` is a well-known service rather than your address. Nothing
here can reach a key — there is no field for one, and the assembler cannot see
the config file, the keychain or the registry.

### VLAN — how membership is shown

Segment membership is an **identity, not a status**. The tag is always
`.neutral` and never takes a tone hue: "which segment am I on" has no good/bad
axis, and routing it through `StatusTone` would make one VLAN green and another
amber for no reason a reader could reconstruct. If segments ever need to be told
apart *from each other*, that is a category palette — the `StorageCategory` /
`TelemetrySeries` pattern — and only once a source has named them, because
colouring unnamed segments is colouring noise.

Four states, four treatments, in `vlanLabel(_:)`:

| What is true | Evidence | Row |
|---|---|---|
| Host has an 802.1Q sub-interface | `ifconfig` prints `vlan: 40 parent: en0` | `VLAN 40`, plus the name if a source has one |
| A source named the segment | `VLANSource` matched it | `VLAN 40 · Guest`, or the name alone for a segment with no tag |
| Untagged, unnamed, distinct L3 | its own subnet and gateway | **nothing** — the subnet in the subtitle is the honest artifact |
| No VLAN anywhere | — | absent |

The third row is the one that matters. A Mac on a **trunk** port reads its own
tag; a Mac on an **access** port — which is almost every Mac, and every Mac
behind a firewall doing the segmentation — never sees one, because the switch
strips it before the frame reaches the NIC. `10.10.40.0/24` looks like VLAN 40,
and an implementation that reads the third octet is right on one network and
confidently wrong on the next. So the app does not guess, and shows the subnet
instead.

The acceptance bar, in five parts:

1. **Survives desaturation.** The tag carries its number as text. A coloured
   swatch meaning "VLAN 40" fails the moment `fleetkit-sheet.sh` renders grey.
2. **Never inferred from an address.**
3. **Provenance travels with the claim** — the expanded detail carries
   *Named by: config.json*, and a tag that did not come off the wire says so
   explicitly: `40 (not carried on this link)`.
4. **Degrades to the subnet**, which is true on every host regardless of the
   switch.
5. **Nothing in the menu-bar item.** Membership is not a number you would act on.

### VLAN — the adapter point

`VLANSource` defines what a source is; `VLANRegistry` is the only thing the UI
depends on. Adding one is a registration:

```swift
VLANRegistry.shared.register(UniFiVLANSource(controller: url, token: token))
```

`isAvailable` is the capability flag — false with no source, and false with a
source that has reported nothing — and every segment surface is gated on it.
Until then there is no Segments header, no empty state and no "coming soon" row.
**Absent, not disabled**: an empty state is a claim that there are no segments,
and the truth is that nobody asked.

The protocol is deliberately small — "what segments are there, and which of this
host's interfaces sits on each" — so a first implementation against a router API
is a day's work rather than a port of the model. It is `async` because every
plausible implementation is a network call; the registry caches the last answer,
refreshes off the main actor, and keeps the previous segments when a source
fails, since a controller that is briefly unreachable has not deleted your VLANs.

#### `ConfiguredVLANSource` — the declared source

The first real implementation, and the honest floor for the whole seam: a fleet
with no controller API still gets true labels instead of no labels. It reads
`networkSegments` from `config.json`:

```jsonc
"networkSegments": [
  { "tag": 40, "name": "Guest", "cidr": "10.10.40.0/24",
    "gateway": "10.10.40.1", "purpose": "isolated wireless" }
]
```

An operator writing that is **not** the heuristic the app refuses to run. It is
an assertion with an author, which is the same distinction
`ignoredListenerCommands` draws — and `sourceName` carries the author into the
UI, so a segment on screen can always be traced back.

Matching is tag first, then **subnet containment** — which is what makes it work
on an access port, where there is no tag to match on. Containment rather than
string equality, because an interface at `10.10.40.12/24` belongs to a segment
declared as `10.10.40.0/24` *and* to one declared as `10.10.0.0/16`; the most
specific wins, for the same reason a routing table prefers the longest prefix.
The arithmetic is `RoutingProbe.networkAddress(of:prefix:)`, shared with subnet
derivation, so a segment and an interface cannot disagree about what network
they are on.

`VLANRegistry.adopt(_:)` follows the config file. Deleting the last declaration
unregisters, which puts every segment surface back off screen rather than
leaving the last-known set behind — deliberately asymmetric with the *failure*
path, where the previous segments are kept: a controller that timed out has not
deleted your VLANs, but you deleting the lines has. A registered non-config
source is never evicted by a config reload, because a real controller outranks a
hand-written list.

This is a narrower rule than the one `ConnectionsPopover` states ("rows that are
not configured say so rather than being hidden"), and the two do not conflict.
*We ran `networksetup -listVLANs` and this host has none* is an answer, and it
keeps its row. *No one has told us what segments exist* is not an answer, and it
gets no row.

### Default routes

`RoutingStatus.routes` is every default route, not the first one.

The parser used to `break` on the first `default` line per family. That is
correct only on a singly-homed machine: attach to a wired LAN and a segmented
wireless network at once and `netstat` prints two, of which macOS uses the first
by service order. The app reported that one and gave no sign the other existed —
on the surface whose entire subject is *where do my packets go*.

Which interface is the path in use is the **routing row's** question, and it
answers it twice: the summary names the winning interface and appends `+2` for
the others, and the expanded detail lists every route with the one in use marked
*In use* and the rest *Also*. It is deliberately **not** restated on each
interface row — a third copy of the same fact, competing for the width the
address needs. Two drafts of the interface subtitle truncated something that
mattered (first the device name, then the word it had been shortened for) before
the answer turned out to be separation rather than abbreviation.

### `HeatmapView` · `SquarifiedLayout`

One engine for both maps (disk, processes). Layout is squarified
(Bruls–Huizing–van Wijk) — slice-and-dice degenerates into slivers. Encoding:
**area is the quantity** (allocated bytes / resident memory), **colour never
repeats area** (storage category on the disk map, CPU activity on the process
map), and **every byte is accounted for** — small entries and the capped tail
roll into a dimmed remainder tile rather than vanishing. Labels draw only
where they fit, with per-category static label colours for contrast; hover and
the readout line carry the rest. Tiles act: disk tiles reveal in Finder,
process tiles select the pid in the Processes inspector.

The storage bar's categories and colours live in `StorageCategory`
(`Design/Tokens.swift`): one colour per APFS vocabulary word, drawn in
About-This-Mac order, with "System & Other" openly a subtraction and
"Purgeable" the APFS important-usage gap — never a scan result.

### `ConsoleColor.numeral`

A measured value — the monospaced numerals in a table cell, a chart's live
readout, a byte count. Data rather than a label, so it sits one step below
`.primary` without dropping to `.secondary`, which in this window means
*supporting text* and would put a resident-memory figure at the same weight as
the word beside it.

It is a token because it was four hand-written `.primary.opacity(0.85)` across
four files, next to two `0.8`s doing the same job in the popover ramp. Six
literals across two values, for one idea: that is how the ~130 font sizes
started, and it is the shape rule 1 exists to catch.

### Menu and shortcuts

The app bootstraps AppKit (status items), so there is no scene for
`CommandGroup`; `MainMenu.install` builds the same contract in AppKit and
routes commands through `ConsoleCommand` notifications: ⌘0 open dashboard, ⇧⌘H
home, ⌘1…⌘6 modules, ⇧⌘T/⇧⌘F/⇧⌘D the chrome tools, ⌘K focus search, ⌘R refresh,
⌃⌘S toggle sidebar, ⌥⌘I toggle inspector, ⎋ clears search then selection.

⌥⌘I and its toolbar button exist because AppKit supplies a toggle for the
*leading* column and nothing for the trailing one. Column three could previously
only be dismissed by narrowing the window until the layout gave up on it — a
layout accident standing in for a control, on the one column that is a view of
your current selection. `ConsoleModel.inspectorRevealed` is the intent; width can
still overrule it, and when it does the button's tooltip says so rather than
appearing to do nothing.

The search field's placeholder and the inspector's empty hint are both derived on
`ConsoleModel`, once. They used to be written twice — `RootView.searchPrompt` and
`InspectorPanel.prompt` held two copies of the same switch — and only the
inspector's ever reached the screen, because the search field bridges into the
toolbar from that column. Editing the other one changed nothing, silently. The
hint also now answers Home first: falling through to `module` there described
whichever surface you had visited last, so the inspector offered to inspect "a
launch entry" while Home was on screen. Neither placeholder ends in an ellipsis —
macOS reserves that for a control that opens something needing more input, and in
a placeholder it reads as a hint that was itself truncated.
`ConsoleModel` owns *where you are*; `AppModel` owns *data*. A selection
pointing at a dead row clears itself (`reconcileSelection`).

The two commands that say *where to be* — `selectModule` and `showHome` — are
observed in `ConsoleWindowController`, not in `ConsoleRootView` beside the rest.
Every sender opens the window and posts in the same turn, which was harmless for
as long as every sender was a ⌘-equivalent in the main menu: an `.accessory`
app's main menu is live only while the app is active, so the window already
existed. The status-item dropdown is live with **no window at all**, so choosing
*Processes* from a cold start runs the path that was never exercised — `show()`
builds the hosting controller, the notification posts, and SwiftUI installs its
`.onReceive` subscriptions at a later point of its own choosing. The window would
have opened on Home. `ConsoleModel` exists from the controller's `init`, before
any view does, so an observer there cannot be late. The commands that genuinely
need the view — focusing the toolbar search field, toggling a tool whose context
is measured from the layout — stay in the view, and neither is reachable without
a window to be late for.

The digit range is generated from `ConsoleModule.allCases`, and the tool keys
from `ConsoleTool.shortcut`, so neither the menu nor the rail can drift from the
enum that defines them. **Enter Full Screen** ⌃⌘F is bound to AppKit's own
`toggleFullScreen:` through the responder chain.

That item was deliberately absent for a long time, and while it was absent that
was right: the window set `.fullScreenNone`, so AppKit would never have
validated the selector and the entry could only ever render grey — rule 10, and
the case rule 10 was written against. The window now resizes freely and takes
`.fullScreenPrimary`, so the capability is real and the chrome returns with it.
Rule 10 is symmetric and this is the other direction of it: the menu entry and
the window behaviour move together, and a restriction kept after the constraint
that justified it has gone is the same decay as an entry kept after its
capability has.

---

## Menu-bar item

<!-- menu-bar-items: fleet -->

`MenuBarItemController` owns the status item, the popover and the dropdown menu,
and renders a `Summary` (meters, alert, tint, tooltip, accessibility label)
through `MenuBarItemController.render`, which the surface sheet's
`menubar-*.png` captures draw through too. A
surface supplies content and a summary closure; it knows nothing about
`NSStatusItem`.

**One item, not five.** The count came down in three steps and each step merged a
pair that turned out to be one subject:

| Item | Glyph | Count shown | Tint |
|---|---|---|---|
| **Fleet** | `MenuBarMeters` — CPU · RAM · DISK, label over value, one template image | an attention count or Offline after the meters, nothing otherwise | the alert only: red critical / orange warning or waiting |

Servers and Agents went first: an agent *owns* services, so they were one subject
split across two icons. Connections followed. They are now the three sections of
one popover — `FleetSection` — each tab carrying its own count so you can see
which half needs you before switching, and the popover opens on **Agents**
automatically when something is waiting for an answer.

The HTML comment above is the machine-readable half. This section spent a while
describing **two** items, `Fleet` and `Connections`, complete with an argument
about why their silhouettes were chosen to be opposites — after the app had
collapsed to one. `MenuBarItemController`'s own doc comment said "FleetConsole
puts up two of these", `FleetPopover`'s said "Item 1 of 2", and `PopoverView`'s
said the surfaces "are separate items because they answer different questions".
Four places describing a menu bar that had not existed for some time, which is
rule 9's failure mode exactly, so it is checked the same way rule 9 is: the
audit reads the `identifier:` of every `MenuBarItemController` the app constructs
and compares that set against the list in the comment, in **both** directions.
Adding an item the docs do not name fails; leaving an item named here after it is
gone fails too, which is the half a one-way check would have missed.

The silhouette is **fixed**: three meter columns, each as wide as its widest
possible value ("100%"), so the item keeps one width and every number keeps one
position however the readings move. That is the same *symbol = identity, tint =
status* rule as every row, and the reason a drawn wordmark was retired: the
readings are the identity now. The first version morphed it with state — checkmark → question mark →
warning triangle. That destroyed the one thing a menu-bar icon must have: a
constant shape you can find without reading. It was also actively misleading,
since `questionmark.circle` reads as a Help menu, and the count it showed was
*unmanaged processes* — so a machine with nothing running displayed a confident
"5". The count is now only ever a number you would act on.

**Colour appears only when something is wrong.** A permanently tinted icon is one
more thing you learn to stop seeing. Counts use monospaced digits so the item does
not jitter, and it sets an `autosaveName` so its position survives a relaunch.
The tooltip carries the detail: ownership, next lease expiry, who is waiting.

### The designated fixer

One agent outside the app is designated to fix what the app finds
(`FixAgent.swift`): Claude Code, Codex or the resident Fleet agent, whichever
are installed, chosen on the Agents tab. *Send N problems* there — or *Send to …*
on Home's Needs attention card and on each of its rows — writes a Markdown
report (the problems, each service's record, its recent events, its log paths)
to `~/Library/Application Support/FleetConsole/fix-reports/`, opens the
dashboard terminal in the service's working directory, and starts the fixer on
the report. It runs where you can watch, answer and stop it; it acts through
`fleetctl`, and it reports back with `fleetctl notify`, which is how its
progress reaches the Agents tab.

The Cloud Agent card is the hosted version's purchase path. Its price and its
checkout come from the Ouros catalog offer `fleet-console-cloud-agent`; until
the catalog lists that offer for the account, the card says it is not offered
rather than showing a price nobody set.

### Identity: badge, row and profile card

`Design/OurosIdentity.swift` holds the three pieces every Ouros app wears the
same way, with the product's mark and words supplied by the caller:

- **`OurosAppBadge`** — the mark, optionally on an icon plate at the macOS icon
  corner ratio. Inside the app it has no plate: the mark is ink on the surface
  it sits on, because a tile of another colour in the popover header reads as a
  sticker on the menu rather than part of it.
- **`OurosIdentityRow`** — badge, product name, one live line.
- **`OurosProfileCard`** — that row in a card with one ⋯ menu, closing the
  dashboard sidebar in its bottom-left corner. It replaced the window footer
  strip (status pip, *Controller connected*, Ouros link, source link): the
  account and links live in its menu, and its line reads *Controller offline* in
  the bad tone only when that is true.

FleetConsole's mark is the blackletter F, `Sources/FleetConsoleApp/Brand/fleet-letter.png`
— ink on a transparent ground, loaded by `FleetBrand.letter` as a template image
and drawn in the secondary ink, so it follows light and dark like a symbol.
`Scripts/make-icon.sh` prints the same F on a paper plate for the app icon, at
every size, so the Dock icon and the in-app mark are one letter.

The popover header carries no rule beneath it and its Dashboard action is a
plain label, not a bordered button: the identity, the tabs and the body read as
one surface, separated by space.

### Popover sections

<!-- popover-sections: Quick View, Services, Agents, Processes, Connections -->

`FleetSection` — **Quick View · Services · Agents · Processes · Connections**
(labelled *Network*, via `menuTitle`). One segmented picker, one body each, and
each tab carries its own count where a count is something you would act on.

The popover has a header and no footer. The header's first row is the app's
identity — `OurosIdentityRow`: badge, name, and `AppModel.fleetStatusLine` in the
tone's ink when something is wrong — then *Dashboard*, refresh, and one ⋯ menu
for configuration and links. The second row is the section picker at the full
width of the content under it. The status pip, the Ouros link and the source
link that used to sit in a ribbon under every tab are the identity line and the
⋯ menu now; nothing is pinned below the content, so a tab ends where it ends.

**Network** is `NetworkGlance`: one tile per segment — Internet, Gateway,
Ethernet, Wi-Fi, Tailscale, DNS, VPN, Thunderbolt, Devices, Listening — two
columns, every one visible inside the 300pt body. A tile carries the one reading
worth a glance in the tone's ink when it needs you; any tile, or **Details…**,
opens the full rows, probes and admin consoles in a sheet. The tab used to be
those rows inline, a screen and a half tall, scrolled to learn whether the VPN
was up.

**Agents** is four bands in the same 300pt: the designated fixer and its one
action, the latest three mailbox entries (waiting-for-you first), the roster as
a one-line count with *Register* and *Show all*, and the Cloud Agent card.

**Services** set the state beside the name (`FleetRowLabel.titleDetail`, in the
tone's ink when it is one to act on) so the line under it is the purpose the
agent declared — what the service is *for*. The state's plain meaning
(`ServiceState.meaning`) and the owner are in the tooltip. **Processes** lead
with a role from `ProcessRole` — managed service and its purpose, agent session,
app, server on a port, macOS system process — and keep the pid in the tooltip.

Processes does not carry one. "Processes 641" is the size of the process table:
the same number on every Mac at every moment, and nothing you would do anything
about. The menu-bar rule about counts applies inside the popover too — the states
worth a number (zombie, stopped) are named in the section's own census line.

Sections are switchable in `config.json` (`ui.sections`). A section that is off
is **absent from the picker**, not present-and-greyed — rule 10 again. Turning
every section off leaves Services standing, because a configuration that renders
a void is a configuration error and the honest response is to keep one surface.

The marker above is the machine-readable half, checked in both directions like
the menu-bar items. It is a marker rather than a prose grep — which is what the
module check uses — because the first draft of the section check passed the
moment it was written: "Processes" was already in these docs as the name of a
console *module*, and a check that cannot tell two surfaces apart because they
share a word reports green straight through the drift it exists to catch.

### The dropdown

Right-click (or ⌃-click) the item. Built in `AppDelegate.contextMenu()`, and it
is the one surface in the app that is a plain `NSMenu` rather than SwiftUI —
AppKit draws it, so it gets the system's own menu metrics, materials, highlight
and Reduce Transparency behaviour for free, and there is nothing to keep in step
with them.

```
Open Dashboard                ⌘0
── Dashboard ──                    ← NSMenuItem.sectionHeader
Overview                      ⌘1
Processes                     ⌘2
Storage · Services · Events · Launch Services   ⌘3…⌘6
── Fleet ──
Network                            ← a popover section, so it opens the popover
Run Reconciliation Sweep
──────
Edit Configuration
Reveal Logs in Finder
──────
Quit FleetConsole             ⌘Q
```

Three things were wrong with the version before it, and all three were one
mistake — a menu describing something the app does not do.

**Key equivalents bound nowhere.** It drew ⌘D beside *Open Dashboard…* and ⌘R
beside *Run Reconciliation Sweep*. A status-item menu's equivalents are live only
while that menu is open, and nothing registered either key anywhere else, so the
dropdown advertised a second, non-working shortcut for a command that already had
a working one (⌘0) — and a ⌘R that collides on sight with View → Refresh. That is
rule 10 with the window swapped for the menu bar. The equivalents shown now are
the real ones.

**Ellipses on commands that complete immediately.** macOS reserves the ellipsis
for a command that needs further input before it can finish. Opening a window and
opening a file in your editor both complete on the click, so *Open Dashboard* and
*Edit Configuration* lost theirs. The popover's destructive service verbs keep
theirs, because those really do raise a confirmation.

**No route to what the app is for.** The dropdown listed maintenance verbs and no
destinations, so reaching the process table from the menu bar meant opening the
dashboard and then navigating to it. `MainMenu.moduleItems()` builds the module
entries once, from `ConsoleModule.allCases`, and both the View menu and this menu
use it — duplicating the loop would have produced two lists that drift the moment
a module is added, which is the failure `allCases` and `shortcutIndex` exist to
prevent.

One command also had three labels: this menu said *Open Dashboard…*, the View
menu said *Show Console*, and the popover's Dashboard button said *Open Dashboard*.
Three names read as three destinations to anyone who has not opened all three.
It is **Open Dashboard** everywhere now, which is what `README.md` documents.
`FleetSection.menuTitle` does the same job for the popover's third section, which
the segmented control has always labelled *Network*.

---

## Rules

1. No literal font sizes or paddings in view code. Add a token instead.
2. No new row chrome. Compose `DisclosureRow` + `FleetRowLabel`.
3. Status colour comes from `StatusTone`, never from `Color.green` inline. A
   colour that is a *category* rather than a status gets its own named token —
   `StorageCategory`, `TelemetrySeries` — and a colour that describes what a
   control will *do* rather than what is true gets `ConsoleColor.destructive`.
4. A fact that was never established renders grey and says so — never as its
   last-known-good value.
5. Fixed-height rows in any layout that promises not to scroll.
6. Nothing is drawn outside the bounds it reports. `.offset` does not reserve
   space, so anything offset inside a fixed frame is overflow — anchor it with a
   stack alignment, or reserve the room with padding.
7. State never rests on colour alone. Pair it with `StatusTone.verdict`, a
   length, or adjacent text.
8. `tone.color` fills; `tone.ink` writes. A tone hue used as text on its own tint
   fails contrast in light mode.
9. A surface that ships is a surface that is written down. Every `ConsoleModule`
   case and every `ConsoleTool` title has to appear verbatim in `README.md` or a
   file under `docs/`. Adding a module and leaving the prose at the previous set
   is the same decay as a stray font size, and it is checked the same way.
10. No chrome for a behaviour the window has disabled, **and no restriction kept
   past the reason for it**. A menu item bound to a selector AppKit will never
   validate — a Full Screen entry on a `.fullScreenNone` window — renders
   permanently grey. Remove the item or remove the restriction; do not ship a
   shortcut that cannot be pressed. The rule has since been exercised in the
   other direction, which is the half that was easy to miss: the window dropped
   its aspect lock, `.fullScreenNone` had been justified by that lock and
   nothing else, and a restriction whose only argument has expired is dead
   chrome the same way a grey menu item is. The item and the behaviour move
   together, whichever way they are moving.
11. No `.opacity()` on a colour in view code. A tone takes `wash`, `chipFill`,
   `edge` or `stroke`; an achromatic ink takes a `SurfaceInk` token through
   `FleetColor` / `ConsoleColor`. This is rule 1 for colour, and it was written
   after an audit found nine tone strengths and seven `Color.primary`
   strengths across eleven files, for ten actual jobs.
12. A capability nothing can supply renders **nothing** — no header, no empty
   state, no placeholder row. An empty state is a claim that the set is empty;
   "no one has told us" is a different fact and gets no chrome. `VLANRegistry`
   is the pattern: one flag, gated at the section.
13. Every fixed dimension is a **Fibonacci rung**, and anything dividing the
   window divides it at **φ**. Not a style: it is what makes the set of sizes
   checkable at all, and the set turned out not to hold — `columnReserve` came
   to 786pt against a 780pt minimum window. Strokes are the one exception, and
   are named rather than pattern-matched. See `FleetCore/ConsoleLayout.swift`.

### Checking them

```bash
Scripts/design-audit.sh            # hard rules fail; budgets report
Scripts/design-audit.sh --strict   # budgets fail too
Scripts/fleetkit-sheet.sh --open   # render every primitive, light/dark + greyscale
Scripts/churn.sh 60                # boot the live model, count what republishes
```

### Churn

"Do not rebuild the menu when nothing changed" is a claim, and a claim about a
running app is worth what it is measured at. `Scripts/churn.sh` boots the real
`AppModel` — real timers, real `ps`, real `netstat` — with the activation policy
set to `.prohibited` so nothing reaches the menu bar, puts a
`withObservationTracking` loop on each published surface, and prints how often
each one fired. It is compiled only under `-DFLEET_SURFACE_RENDERER`, the same
flag that gates the surface sheet, so none of it is in the shipped binary.

A 120-second run on the machine this was written on, attached to two networks:

```
churn over 120s
  network probe ran ~6x, process sampler ~30x
  routing published 2x
  processes published 30x
  menu-bar published 0x
```

Three numbers, each meaning something different:

* **routing 2× against six probe runs** — and the same 2 over a 45-second window
  with two runs, which is how you tell a fixed cost from a per-probe one. Those
  two are the transitions: empty to first capture, then one settle as the second
  attachment finishes coming up. The snapshot carries the whole interface
  inventory and its `checkedAt` moves every pass, so a plain `!=` would have
  published all six, and all six of the next six, forever.
* **processes 30×**, once per sample. That is correct and it is the control: CPU
  and resident memory genuinely change every four seconds, and a zero here would
  mean the harness was watching a dead model rather than proving anything.
* **menu-bar 0×**. The 1 Hz lease clock never reaches the status item, which is
  the oldest of these rules and the one most likely to be broken by accident.

The sheet is the visual half. It symlinks the design sources into a throwaway
package, so it always shows what ships, and it writes each appearance twice —
once normally and once desaturated. The greyscale pair is the useful one:
`accessibilityDifferentiateWithoutColor` is read-only and cannot be injected into
a render, but stripping the hue from finished pixels answers the same question
more directly. Anything that turns into an undifferentiated grey blob is encoding
state in colour alone. That is how the sidebar's node health was caught.

Rules 3, 6, 7, 8, 9 and 10 are exact enough to check mechanically, so the script
fails on them. Rule 1 is a **budget** instead: the counts it prints (0 font
sizes, 96 paddings, 24 frame dimensions at the time of writing) mix real drift
with legitimate one-offs, so the honest signal is that a number went up, not that
it is nonzero. A written rule did not prevent the ~130 literal font sizes this
toolbox was built to clean up. Counting them does.

**Rules 3 and 8 have each been widened once more, and each time the gap held
real code.** Rule 8's check keyed on the *receiver* — `StatusTone.warn`, or a
variable literally spelled `tone` — so a tone arriving from anywhere else was
invisible to it: `cpuTone(row).color` on the Processes table's CPU column,
`verdictTone.color` on the popover's verdict glyph,
`SystemThresholds.thermal(…).color` in the Overview footer. Three tone hues
writing text, on three of the most-looked-at surfaces, under a check reported
green. It no longer tries to recognise a tone: **any** `.color` inside a
`foregroundStyle` is a fill style doing the ink's job, and the one exemption is
`TelemetrySeries`, which is not really an exemption — a Swift Charts `LineMark`
has no `.fill`, so `foregroundStyle` is the only API for a mark's colour.

Rule 3's check anchored every hue to a call site — `Color.green`, `fill(.green)`,
`tint(.green)` — which is the shape a hue takes where it is *used* and not the
shape it takes when a view factors the choice into a computed property.
`InterpreterPanel.captionColor` did exactly that (`case .available: return
.green.opacity(0.85)`): two inline hues encoding whether the local model is
installed, invisible for as long as the check existed, because no anchor preceded
the dot. Type inference is the whole point of that spelling, so the anchor set now
includes the positions a bare leading dot can occupy — after `return`, after `=`,
and in either arm of a ternary. Widening it also made the rule match the prose
explaining it, so comment lines are dropped: a check that fails on its own
documentation teaches people to stop writing the documentation.

Rule 9 is the same argument turned on this document. "Update the docs" is a
written rule, and it failed the same way: a session added `ConsoleModule.plists`
and the Home surface, and both this file and `README.md` went on describing the
previous set — while still being quoted as the standard. So the script now reads
the enums and greps the prose. `Launch Services` is in this paragraph's sense the
proof: the check was written first, it failed with *module "Launch Services"
appears in no document*, and it went green only once the module list above
actually described it.

Both new checks were positive-controlled — re-introducing the Full Screen binding
makes rule 10 fail, removing it makes it pass — because a check that has only
ever been observed green is not yet evidence of anything. The first draft of rule
10 passed in both states: it matched `collectionBehavior[^\n]*fullScreenNone`,
and in a POSIX bracket expression `[^\n]` excludes the letter `n`, so
`.insert(.fullScreenNone)` never matched. It is `.*` now. A silent-pass audit is
worse than no audit, which is the whole reason these are run against a known-bad
tree before they are trusted.

Every check added or widened since has been run the same way, and two of them
needed it. The widened rule 8 was controlled by putting `cpuTone(row).color` back
on the CPU column; rule 3 by restoring both the ternary arm
(`last.kind == .problem ? .red : .secondary`) and the bare `return .green`, since
those are two different spellings and one passing does not vouch for the other.
The menu-bar check is controlled in **both** directions — naming a `connections`
item the app no longer builds, and emptying the marker while the app still builds
`fleet` — because its whole reason for existing is the direction a one-way check
misses. Its first draft failed the second control for the wrong reason: it read
the identifiers with a line-based `grep`, the call site wraps after the open
paren, so it found zero items and reported the one real item as deleted. A check
that fails is not the same as a check that works.
