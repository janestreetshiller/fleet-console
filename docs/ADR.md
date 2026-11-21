# Decision records

## ADR-0001: Comment policy

Source carries no comments except license headers, Rust SAFETY contracts, tooling directives and generated-file markers. Decision records moved here from source; the comment ratchet in policy/comment-budget.json blocks new comment debt. Tautologies and stale notes were deleted; excuse comments were deleted and filed as issues.

## Package.swift

Line 1:

```text
swift-tools-version: 6.0
```

Line 8:

```text
The app's only external dependency, and it buys one thing this package
```

Line 9:

```text
cannot honestly fake: a real VT100/xterm emulator for the chrome's
```

Line 10:

```text
terminal and Yazi panels. Kept off FleetCore, fleetd and fleetctl so
```

Line 11:

```text
the daemon and CLI stay dependency-free.
```

Line 33:

```text
The blackletter F: the mark in the window and popover, and the
```

Line 34:

```text
source `Scripts/appicon/Icon.swift` draws the app icon from.
```

## Release/PublicPackage.swift

Line 1:

```text
swift-tools-version: 6.0
```

Line 4:

```text
Public snapshot: the desktop UI and SwiftTerm are not part of this package.
```

## Resources/yazi/init.lua

Line 1:

```text
FleetConsole's Yazi surface.
```

Line 3:

```text
The panel borrows Yazi as a file *view*. It is not a terminal the operator
```

Line 4:

```text
lives in, and it is not their own Yazi: `FilesPanel` points YAZI_CONFIG_HOME
```

Line 5:

```text
at this directory, so nothing here inherits ~/.config/yazi and nothing here
```

Line 6:

```text
changes it.
```

Line 8:

```text
The status line is removed. Yazi's footer carries mode, size, permissions,
```

Line 9:

```text
position and a second copy of the hovered name — all of it either duplicated
```

Line 10:

```text
by the inspector column two feet to the left, or irrelevant in a panel that
```

Line 11:

```text
cannot be operated as a shell. What it mostly did was put a second, differently
```

Line 12:

```text
formatted path under a panel that already has one in its header.
```

## Resources/yazi/theme-dark.toml

Line 1:

```text
FleetConsole's Yazi surface — white and grey, nothing else.
```

Line 3:

```text
Yazi's stock theme colours by file type: green executables, magenta archives,
```

Line 4:

```text
cyan links, a dozen hues down the column. That is a legible scheme in a
```

Line 5:

```text
full-window file manager and the wrong one here. In this app colour is a status
```

Line 6:

```text
vocabulary — `StatusTone` spends green, amber and red on healthy, degraded and
```

Line 7:

```text
failing, and every surface honours that. A file browser spending the same green
```

Line 8:

```text
on "this file has +x" puts a second, unrelated meaning on the console's most
```

Line 9:

```text
loaded signal, two feet from a services list where green means verified.
```

Line 11:

```text
So the file column is achromatic and attention is carried by *weight and
```

Line 12:

```text
reversal* instead: the hovered row is the only high-contrast thing on screen.
```

Line 14:

```text
One ramp, four steps. Named here rather than repeated, because the whole point
```

Line 15:

```text
is that no fifth value quietly appears.
```

Line 16:

```text
ink    #F2F3F5  the focused row
```

Line 17:

```text
plain  #C8C9CD  ordinary entries
```

Line 18:

```text
muted  #86878C  directories' chrome, parent column, metadata
```

Line 19:

```text
faint  #55565A  dividers and rules
```

Line 24:

```text
Reversed, not tinted. This is the "focus attention to a specific path" rule:
```

Line 25:

```text
one row is inverted, everything else is flat, and the eye has exactly one place
```

Line 26:

```text
to land no matter how long the listing is.
```

Line 42:

```text
The dividers, fixed rather than inherited. One glyph, one weight, one colour,
```

Line 43:

```text
dim enough to read as structure instead of as content.
```

Line 121:

```text
One rule per structural distinction, and no rule that encodes a *status*.
```

Line 122:

```text
Directories read brightest because they are the thing you navigate; everything
```

Line 123:

```text
else is one step down; unreadable entries drop to muted so a permission problem
```

Line 124:

```text
is still visible without spending a hue on it.
```

Line 127:

```text
`url`, not `name`: a filetype rule matches on url or mime and is rejected at
```

Line 128:

```text
parse time otherwise — the same rule [open] enforces.
```

Line 137:

```text
Icons.
```

Line 139:

```text
`[filetype]` colours the *name*; the glyph in front of it is coloured by these
```

Line 140:

```text
rules, which are a separate set with their own `fg`. Leaving them at Yazi's
```

Line 141:

```text
defaults left an orange Rust glyph and a blue TOML glyph in a column that is
```

Line 142:

```text
otherwise achromatic — the exact thing this theme exists to prevent. Declaring
```

Line 143:

```text
`[icon]` replaces the default set outright, so the set below is deliberately
```

Line 144:

```text
a working operator's set rather than an exhaustive one: the file kinds that
```

Line 145:

```text
actually appear next to a supervised service.
```

Line 147:

```text
Every glyph is a Nerd Font codepoint. `TerminalFont` resolves a Nerd Font for
```

Line 148:

```text
the panel and falls back to SF Mono when none is installed — in that case these
```

Line 149:

```text
render as tofu, which is why the panel says so rather than pretending.
```

Line 181:

```text
Code
```

Line 197:

```text
Config and data
```

Line 206:

```text
Operational — what a supervised service leaves behind
```

Line 212:

```text
Docs and media
```

Line 222:

```text
Archives
```

Line 229:

```text
The fallbacks, in order. `conds` is consulted last, so these catch everything
```

Line 230:

```text
the lists above do not name.
```

## Resources/yazi/theme-light.toml

Line 2:

```text
Source: theme-dark.toml, with the five-step ramp inverted for a light
```

Line 3:

```text
terminal background. Edit the dark theme and regenerate.
```

Line 5:

```text
FleetConsole's Yazi surface — white and grey, nothing else.
```

Line 7:

```text
Yazi's stock theme colours by file type: green executables, magenta archives,
```

Line 8:

```text
cyan links, a dozen hues down the column. That is a legible scheme in a
```

Line 9:

```text
full-window file manager and the wrong one here. In this app colour is a status
```

Line 10:

```text
vocabulary — `StatusTone` spends green, amber and red on healthy, degraded and
```

Line 11:

```text
failing, and every surface honours that. A file browser spending the same green
```

Line 12:

```text
on "this file has +x" puts a second, unrelated meaning on the console's most
```

Line 13:

```text
loaded signal, two feet from a services list where green means verified.
```

Line 15:

```text
So the file column is achromatic and attention is carried by *weight and
```

Line 16:

```text
reversal* instead: the hovered row is the only high-contrast thing on screen.
```

Line 18:

```text
One ramp, four steps. Named here rather than repeated, because the whole point
```

Line 19:

```text
is that no fifth value quietly appears.
```

Line 20:

```text
ink    #16181C  the focused row
```

Line 21:

```text
plain  #3C3E44  ordinary entries
```

Line 22:

```text
muted  #74767C  directories' chrome, parent column, metadata
```

Line 23:

```text
faint  #B9BBC0  dividers and rules
```

Line 28:

```text
Reversed, not tinted. This is the "focus attention to a specific path" rule:
```

Line 29:

```text
one row is inverted, everything else is flat, and the eye has exactly one place
```

Line 30:

```text
to land no matter how long the listing is.
```

Line 46:

```text
The dividers, fixed rather than inherited. One glyph, one weight, one colour,
```

Line 47:

```text
dim enough to read as structure instead of as content.
```

Line 125:

```text
One rule per structural distinction, and no rule that encodes a *status*.
```

Line 126:

```text
Directories read brightest because they are the thing you navigate; everything
```

Line 127:

```text
else is one step down; unreadable entries drop to muted so a permission problem
```

Line 128:

```text
is still visible without spending a hue on it.
```

Line 131:

```text
`url`, not `name`: a filetype rule matches on url or mime and is rejected at
```

Line 132:

```text
parse time otherwise — the same rule [open] enforces.
```

Line 141:

```text
Icons.
```

Line 143:

```text
`[filetype]` colours the *name*; the glyph in front of it is coloured by these
```

Line 144:

```text
rules, which are a separate set with their own `fg`. Leaving them at Yazi's
```

Line 145:

```text
defaults left an orange Rust glyph and a blue TOML glyph in a column that is
```

Line 146:

```text
otherwise achromatic — the exact thing this theme exists to prevent. Declaring
```

Line 147:

```text
`[icon]` replaces the default set outright, so the set below is deliberately
```

Line 148:

```text
a working operator's set rather than an exhaustive one: the file kinds that
```

Line 149:

```text
actually appear next to a supervised service.
```

Line 151:

```text
Every glyph is a Nerd Font codepoint. `TerminalFont` resolves a Nerd Font for
```

Line 152:

```text
the panel and falls back to SF Mono when none is installed — in that case these
```

Line 153:

```text
render as tofu, which is why the panel says so rather than pretending.
```

Line 185:

```text
Code
```

Line 201:

```text
Config and data
```

Line 210:

```text
Operational — what a supervised service leaves behind
```

Line 216:

```text
Docs and media
```

Line 226:

```text
Archives
```

Line 233:

```text
The fallbacks, in order. `conds` is consulted last, so these catch everything
```

Line 234:

```text
the lists above do not name.
```

## Resources/yazi/yazi.toml

Line 1:

```text
FleetConsole's Yazi surface — layout only; colour lives in theme.toml.
```

Line 3:

```text
Not a copy of ~/.config/yazi. The panel is a fixed-purpose file view inside a
```

Line 4:

```text
40-column-minimum side field, so it makes different choices than a full-window
```

Line 5:

```text
file manager would.
```

Line 8:

```text
No parent column. The default 1:4:3 assumes a full window; this panel's floor
```

Line 9:

```text
is 40 columns, where a 1-part parent resolves to about six cells and shows a
```

Line 10:

```text
stack of one-letter truncations — "f…", "i…", "n…" — which is noise, not
```

Line 11:

```text
orientation. The header already prints the full path, so the column was paying
```

Line 12:

```text
a seventh of a narrow panel to say something less clearly than the line above
```

Line 13:

```text
it. Current gets the weight; preview keeps enough to identify a file by.
```

Line 21:

```text
The panel opens on a service's recorded cwd and is read for orientation, so
```

Line 22:

```text
symlink targets matter more here than in a general browser.
```

Line 25:

```text
Off: the panel is not where files get counted, and the size probe walks the
```

Line 26:

```text
tree on every hover, which is real work for a number the inspector already has.
```

Line 30:

```text
A file view inside a 40-column panel is for identifying files, not reading
```

Line 31:

```text
them. Keeping the budget small keeps a hover on a large file from stalling the
```

Line 32:

```text
pane.
```

Line 38:

```text
Reveal rather than edit. The panel deliberately does not become a launcher:
```

Line 39:

```text
opening an editor from here would put a second, unmanaged interactive process
```

Line 40:

```text
behind a surface whose whole point is that it only shows things.
```

Line 46:

```text
`url`, not `name` — an [open] rule matches on url or mime and rejects anything
```

Line 47:

```text
else at parse time.
```

## Scripts/appicon/Icon.swift

Line 4:

```text
FleetConsole's app icon: the blackletter F printed on a sheet of paper.
```

Line 6:

```text
The F is `Sources/FleetConsoleApp/Brand/fleet-letter.png` — the same file the
```

Line 7:

```text
window and the popover draw their mark from — so the Finder icon and the
```

Line 8:

```text
in-app mark are one letter, not two drawings of one. It is ink on a
```

Line 9:

```text
transparent ground, so the plate supplies the paper and the icon stays crisp
```

Line 10:

```text
on any background the Dock or Finder puts behind it. Every size is drawn at
```

Line 11:

```text
its own scale rather than downsampled from 1024.
```

Line 19:

```text
MARK: - Plate
```

Line 21:

```text
/ A superellipse. `NSBezierPath(roundedRect:)` draws circular arcs, which read
```

Line 22:

```text
/ visibly pinched against macOS's own continuous corners at 512pt and up.
```

Line 38:

```text
/ macOS ships app icons as an 824pt plate inside a 1024pt canvas.
```

Line 48:

```text
MARK: - Drawing helpers
```

Line 75:

```text
MARK: - Palette
```

Line 80:

```text
MARK: - The icon
```

Line 87:

```text
Lifted off the desktop the way every macOS icon plate is.
```

Line 109:

```text
MARK: - Output
```

Line 126:

```text
/ Every slot `iconutil` expects. Each one is *drawn* at its own size rather
```

Line 127:

```text
/ than downsampled from 1024, which is the whole point of the detail ramp.
```

## Scripts/assemble-app.sh

Line 2:

```text
Internal build-app.sh worker; release-staging.py pins cwd to the reserved bundle.
```

Line 3:

```text
Never cd or use a staging pathname: ALL destinations remain relative to that cwd,
```

Line 4:

```text
including the outer signature and verification target (.).
```

Line 20:

```text
The resident operations agent ships beside the controller and CLI. Build it
```

Line 21:

```text
from the Rust workspace (release profile to match a release bundle).
```

Line 31:

```text
Keep debug symbols in SwiftPM's build outputs, not the shipping release bundle.
```

Line 32:

```text
Strip the copied executables before signing; never mutate signed code later.
```

Line 42:

```text
SwiftTerm's Metal shaders live in a SwiftPM resource bundle. Preserve any
```

Line 43:

```text
framework-style outputs as well as the statically linked build's resources.
```

Line 53:

```text
Authored code is MIT; SwiftTerm retains its upstream copyright notices.
```

Line 62:

```text
Generate a missing icon so a fresh clone is not silently unbranded.
```

Line 69:

```text
Ship the Files panel's configuration separately from ~/.config/yazi.
```

Line 105:

```text
Stamp the exact source before signing. Source archives without Git remain
```

Line 106:

```text
explicitly unrecorded; the installed updater accepts only its clean commit.
```

Line 132:

```text
Reject inference runtimes, model weights and additional resident launch jobs
```

Line 133:

```text
before any code is signed. The bundled fleet-agent is a small client only.
```

Line 136:

```text
Explicit ad-hoc signing avoids keychain lookup and timestamps. Developer ID
```

Line 137:

```text
retains hardened runtime/timestamps; nested code is signed inside out.
```

## Scripts/benchmark.sh

Line 2:

```text
Live native-window verification, using optimized code and real host probes.
```

Line 3:

```text
Usage: Scripts/benchmark.sh [seconds=60] [output-directory]
```

Line 4:

```text
Optional: FLEET_BENCHMARK_CPU_BUDGET limits percent of ONE core, not the host.
```

Line 5:

```text
The window stays offscreen. RUSAGE_SELF excludes collector subprocesses and
```

Line 6:

```text
WindowServer; this is not a composited on-screen rendering or idle benchmark.
```

Line 17:

```text
A successful producer exit is not evidence. Give each invocation an empty,
```

Line 18:

```text
exclusive directory so no previous receipt/screenshots can satisfy this gate.
```

## Scripts/build-app.sh

Line 2:

```text
Builds FleetConsole.app — the menu-bar client, with fleetd and fleetctl bundled.
```

Line 4:

```text
Everything runs as the logged-in user: no root, no installer, no privileged helper.
```

Line 20:

```text
Preflight without writes: protect Applications aliases by ancestor device/inode
```

Line 21:

```text
identity, and refuse every existing bundle, file or symlink before building.
```

Line 24:

```text
Cross-module optimization is off, and this is a compiler bug rather than a
```

Line 25:

```text
preference. SwiftPM passes -enable-default-cmo for release builds, and with it
```

Line 26:

```text
Swift 6.4 (swiftlang-6.4.0.25.4, the Xcode beta toolchain) hits an assertion
```

Line 27:

```text
optimizing ConsoleWindowController.show():
```

Line 29:

```text
While running pass SILFunctionTransform "SILCombine" on SILFunction
```

Line 30:

```text
"@$s15FleetConsoleApp0B16WindowControllerC4showyyF"
```

Line 31:

```text
Assertion failed: (), function at Operand.swift:83
```

Line 33:

```text
It is not caused by anything in that function: the crash reproduces with the
```

Line 34:

```text
window controller's observers removed and with the root view's notification
```

Line 35:

```text
handlers restored, which were the two most recent changes anywhere near it.
```

Line 36:

```text
-disable-cmo is scope-only — it stops the optimizer inlining across module
```

Line 37:

```text
boundaries and changes no semantics — so the cost is a little performance and
```

Line 38:

```text
the alternative is no release build at all. Re-test on each toolchain bump and
```

Line 39:

```text
delete this when it builds clean.
```

Line 42:

```text
Keep source, compiler output and dependency cache separate. The installed-app
```

Line 43:

```text
updater supplies a private scratch outside Documents/file-provider storage.
```

Line 66:

```text
Keep the reservation and every destination operation in one fd-anchored
```

Line 67:

```text
lifetime. Returning a pathname here would let an ancestor swap redirect writes.
```

## Scripts/churn.sh

Line 2:

```text
Measures how often the live model republishes.
```

Line 4:

```text
Scripts/churn.sh          # 45 second window
```

Line 5:

```text
Scripts/churn.sh 120      # longer window
```

Line 7:

```text
"Nothing rebuilds when nothing changed" is a design rule, and a rule about a
```

Line 8:

```text
running app is worth what it is measured at. This boots the real AppModel —
```

Line 9:

```text
real timers, real `ps`, real `netstat`, real `scutil` — with the activation
```

Line 10:

```text
policy set to .prohibited so nothing appears in the menu bar, watches each
```

Line 11:

```text
published surface with `withObservationTracking`, and prints the counts.
```

Line 13:

```text
What to expect, and why each number matters:
```

Line 15:

```text
routing    ~1  regardless of window length. The snapshot carries the whole
```

Line 16:

```text
interface inventory and its `checkedAt` moves on every pass,
```

Line 17:

```text
so a plain `!=` would publish on every probe forever;
```

Line 18:

```text
`RoutingStatus.sameContent(as:)` is what makes this 1.
```

Line 19:

```text
processes  one per sample. This is the control — CPU and resident memory
```

Line 20:

```text
really do change every few seconds, and a zero here would mean
```

Line 21:

```text
the harness was watching a dead model.
```

Line 22:

```text
menu-bar   0   on a quiet fleet. The 1 Hz lease clock must never reach the
```

Line 23:

```text
status item.
```

Line 25:

```text
The harness lives in SurfaceRenderer.swift behind -DFLEET_SURFACE_RENDERER,
```

Line 26:

```text
the same flag that gates the design sheet, so none of it ships.
```

## Scripts/design-audit.sh

Line 2:

```text
Checks the view layer against the rules at the bottom of docs/DESIGN-SYSTEM.md.
```

Line 4:

```text
Those rules exist because the first build accumulated ~130 literal font sizes
```

Line 5:

```text
across twelve values and four separate row implementations that had each drifted
```

Line 6:

```text
apart by a point here and a pixel there. A written rule does not stop that; the
```

Line 7:

```text
sediment came back the moment nobody was counting. This counts.
```

Line 9:

```text
Scripts/design-audit.sh            # report, exit 0 unless a hard rule broke
```

Line 10:

```text
Scripts/design-audit.sh --strict   # any finding, including budgets, fails
```

Line 12:

```text
Hard rules fail the build. Budgeted rules print a number you have to argue with:
```

Line 13:

```text
they cover legitimate one-offs (a chart's plot inset, a glyph's optical nudge)
```

Line 14:

```text
mixed in with real drift, so the honest signal is "this got worse", not "zero".
```

Line 32:

```text
hard <name> <explanation> <grep-args...>
```

Line 47:

```text
budget <name> <allowed> <explanation> <grep-args...>
```

Line 61:

```text
The literal rule from the doc. A bare system hue in a view is either a status
```

Line 62:

```text
the vocabulary already owns, or a category that deserves its own token.
```

Line 63:

```text
StorageCategory and TelemetrySeries are those tokens, so Design/ is exempt.
```

Line 65:

```text
The first version anchored every hue to a call site — `Color.green`,
```

Line 66:

```text
`fill(.green)`, `tint(.green)` — which is the shape a hue takes when it is
```

Line 67:

```text
written where it is used. It is not the shape it takes when a view factors the
```

Line 68:

```text
choice out into a computed property, and `InterpreterPanel.captionColor` did
```

Line 69:

```text
exactly that: `case .available: return .green.opacity(0.85)`. Two inline hues
```

Line 70:

```text
encoding "is the local model installed", green and orange, invisible to this
```

Line 71:

```text
check for as long as it existed, because no anchor preceded the dot. Type
```

Line 72:

```text
inference is the whole point of that spelling, so the anchor set now includes
```

Line 73:

```text
the positions a bare leading dot can appear in — after `return`, after `=`,
```

Line 74:

```text
and in either arm of a ternary.
```

Line 76:

```text
Comment lines are dropped, because widening the anchors made the rule match the
```

Line 77:

```text
prose that explains it — a check that fails on its own documentation teaches
```

Line 78:

```text
people to stop writing the documentation.
```

Line 87:

```text
The same sediment as the font sizes, in colour. An audit of the view layer
```

Line 88:

```text
found a tone used at NINE strengths — 0.07 and 0.08 and 0.10 for one row wash,
```

Line 89:

```text
0.12 and 0.13 and 0.14 and 0.16 for one chip fill, plus 0.35 and 0.75 — and
```

Line 90:

```text
`Color.primary` at SEVEN — 0.04, 0.06, 0.7, 0.75, 0.8, 0.85, 0.9 — across
```

Line 91:

```text
eleven files, for what turned out to be four tone jobs and six achromatic ones.
```

Line 92:

```text
Nobody chose those numbers; each was typed once beside whatever was already on
```

Line 93:

```text
screen, which is exactly how 9pt and 9.5pt ended up meaning the same thing.
```

Line 95:

```text
The tokens are `StatusTone.wash/chipFill/edge/stroke` and `SurfaceInk`, exposed
```

Line 96:

```text
on both ramps as `FleetColor.*` and `ConsoleColor.*`. Design/ is exempt because
```

Line 97:

```text
that is where the numbers are supposed to be written down.
```

Line 106:

```text
A bare Circle/Capsule filled with a tone and no glyph, no label and no length
```

Line 107:

```text
carries its meaning in hue alone. Enclosed status symbols measure ~0.87
```

Line 108:

```text
silhouette IoU against each other at row size; bare verdict glyphs measure
```

Line 109:

```text
0.24, which is why StatusTone.verdict exists.
```

Line 116:

```text
A tone hue as small text on its own 14% tint measures 1.98–2.95:1 in light
```

Line 117:

```text
mode. `ink` is the same hue moved toward the label colour by the solved
```

Line 118:

```text
minimum. Text and glyphs take ink; fills, bars and strokes keep color.
```

Line 119:

```text
Two earlier versions of this rule under-matched and each time the gap hid real
```

Line 120:

```text
sites: the first caught only bare `tone.color` and missed thirteen
```

Line 121:

```text
`StatusTone.warn.color`; the second was line-based and missed every ternary
```

Line 122:

```text
split across lines. This one slurps the file and matches the whole
```

Line 123:

```text
`foregroundStyle( … )` call, balanced one level deep, so spelling and line
```

Line 124:

```text
breaks cannot hide anything.
```

Line 126:

```text
The third version still under-matched, and for the third time the gap held real
```

Line 127:

```text
sites. It keyed on the *receiver* — `StatusTone.warn` or a variable literally
```

Line 128:

```text
spelled `tone` — so a tone that arrived from anywhere else was invisible:
```

Line 129:

```text
`cpuTone(row).color` on the Processes table's CPU column, `verdictTone.color`
```

Line 130:

```text
on the popover's verdict glyph, `SystemThresholds.thermal(…).color` in the
```

Line 131:

```text
Overview footer. Three tone hues writing text, on three of the surfaces most
```

Line 132:

```text
looked at, under a check reported green.
```

Line 134:

```text
So it no longer tries to recognise a tone. The invariant is total in the other
```

Line 135:

```text
direction: a fill uses `.fill()` or `.background()`, so **any** `.color` inside
```

Line 136:

```text
a `foregroundStyle` is a fill style doing the ink's job. The one exception is
```

Line 137:

```text
`TelemetrySeries`, and it is not really an exception — a Swift Charts `LineMark`
```

Line 138:

```text
has no `.fill`, and `foregroundStyle` is the only API for a mark's colour.
```

Line 153:

```text
A Tag or a port number in a row accessory competes for width against a title
```

Line 154:

```text
holding layoutPriority(1). Unconstrained it loses and compresses — truncating,
```

Line 155:

```text
or breaking mid-word one character per line. Both need lineLimit(1)+fixedSize.
```

Line 161:

```text
The same invariant, on the other element that sits in a row's trailing slot —
```

Line 162:

```text
and this is where it was actually broken. `FleetRowLabel.trailingText` is the
```

Line 163:

```text
timestamp / port / duration column, and it had `lineLimit(1)` and nothing else
```

Line 164:

```text
while `Tag`, six lines of argument and a check of its own, sat next to it in
```

Line 165:

```text
the same HStack. The surface sheet caught it: all three Needs-attention rows
```

Line 166:

```text
rendered their age as "12…", "2m a…" and a lone "1". One check per struct is
```

Line 167:

```text
how a rule ends up protecting the instance it was written against rather than
```

Line 168:

```text
the invariant it states.
```

Line 172:

```text
Anchored on a line that is only the modifier, so the paragraph of
```

Line 173:

```text
comment above it explaining why fixedSize is there cannot satisfy the
```

Line 174:

```text
check that it is there.
```

Line 180:

```text
.offset() is a draw-time transform: it never changes the size a view reports.
```

Line 181:

```text
Offsetting a child inside a fixed frame therefore paints outside the parent's
```

Line 182:

```text
layout bounds — unreserved overflow that eats a neighbour's gap, and gets cut
```

Line 183:

```text
by any ancestor that bounds its content. EntityIcon's badge did exactly this,
```

Line 184:

```text
spilling 2.1–3.0pt at the four icon sizes the app uses.
```

Line 191:

```text
Only a bare numeral counts. `size * FleetMetrics.iconGlyphRatio` is a token
```

Line 192:

```text
scaled by its container, which is the pattern EntityIcon is built on.
```

Line 204:

```text
The tokens were ~25 independent judgement calls (236, 268, 280, 320, 88, 120,
```

Line 205:

```text
260, 300, 14, 20, 12…), each defensible alone and none related to any other, so
```

Line 206:

```text
the set could not be checked — and it turned out not to hold: the column
```

Line 207:

```text
reserve summed to 786 against a 780pt minimum window. They are now rungs of
```

Line 208:

```text
`Scale.ladder`, and `ConsoleLayoutTests` asserts the budget they feed.
```

Line 210:

```text
This catches the other direction: a future edit typing a number *near* a rung.
```

Line 211:

```text
That is exactly how the 9pt/9.5pt font pair happened, and how 236 came to sit
```

Line 212:

```text
three points off 233 while claiming to be a considered width.
```

Line 214:

```text
`chartStroke` is the one allowed exception and is named rather than pattern-
```

Line 215:

```text
matched: a 1pt line and a 2pt line are two weights of one mark, not two steps
```

Line 216:

```text
of a size hierarchy, so stroke widths are below the ladder's floor by design.
```

Line 231:

```text
FleetCore cannot import the app target, so ConsoleLayout restates the handful
```

Line 232:

```text
of view-layer dimensions its budget is computed from. A restated number is a
```

Line 233:

```text
number that drifts, and `railWidth`'s comment has claimed to be "asserted
```

Line 234:

```text
equal by test" since it was written while no such assertion existed —
```

Line 235:

```text
FleetCoreTests cannot see ConsoleMetrics or ConsoleToolMetrics, so the test it
```

Line 236:

```text
named was not possible to write. The mirror was guarded by a sentence.
```

Line 238:

```text
Every `static let <name>` in ConsoleLayout that shares a name with one in the
```

Line 239:

```text
view layer has to carry the same value.
```

Line 246:

```text
Only names the view layer also declares are mirrors; the rest are
```

Line 247:

```text
ConsoleLayout own values (sideColumnMin, panelMin, …).
```

Line 260:

```text
The doc claims "nothing depends on colour alone". Reduced Motion was honoured
```

Line 261:

```text
from the start; Differentiate Without Colour was not read anywhere, which is
```

Line 262:

```text
what left the lone pips encoding health in hue only.
```

Line 268:

```text
Rule 9, turned on the tokens themselves.
```

Line 270:

```text
Every check below this line grew out of one enumerated set drifting from its
```

Line 271:

```text
prose — modules, chrome tools, popover sections, menu-bar items. All four are
```

Line 272:

```text
names*. Nothing read the numbers, and the numbers were the part that had
```

Line 273:

```text
rotted worst: the FleetFont and FleetMetrics tables in docs/DESIGN-SYSTEM.md
```

Line 274:

```text
were wrong in **every single row**, and had been since the ramp was rewritten.
```

Line 275:

```text
They described the 9–12.5pt draft — 9/9.5, 12/12.5, gutter 12, popoverWidth
```

Line 276:

```text
400 — which is the exact sediment the paragraph above them cites as the reason
```

Line 277:

```text
the toolbox exists. The document's worked example of drift was the document.
```

Line 279:

```text
A written rule ("update the docs") did not hold for the font sizes and did not
```

Line 280:

```text
hold here either, so this counts instead. Both directions, like the menu-bar
```

Line 281:

```text
check: a token added and not written down fails, and a token written down after
```

Line 282:

```text
it is gone — or written down at a size it no longer has — fails too. Value
```

Line 283:

```text
mismatches surface as one line on each side, which reads as what it is.
```

Line 285:

```text
`mono(_:)` takes its size from the call site and is documented with an em dash,
```

Line 286:

```text
so it carries no number to compare and drops out on its own. `actionSlot` is
```

Line 287:

```text
derived from `iconButtonSize` rather than typed, which is the point of it, so
```

Line 288:

```text
it is checked by name only.
```

Line 295:

```text
A documented row is "| <anything with a name in it> | <number> | … |".
```

Line 296:

```text
Matched without backticks on purpose: a backtick inside this script
```

Line 297:

```text
would be command substitution, and escaping one through three levels of
```

Line 298:

```text
quoting is how a check ends up matching nothing and reporting green.
```

Line 311:

```text
<label> <code list> <doc list>
```

Line 320:

```text
Tokens derived from another token carry no literal to compare, so they
```

Line 321:

```text
are checked for a mention only.
```

Line 330:

```text
The surfaces the app ships are enumerated in exactly two enums, and both are
```

Line 331:

```text
described in prose in README.md and docs/DESIGN-SYSTEM.md. Prose does not
```

Line 332:

```text
recompile, so it drifts silently: a session added ConsoleModule.plists and the
```

Line 333:

```text
Home surface and left both documents naming the previous set. That is the same
```

Line 334:

```text
failure mode as the ~130 literal font sizes — a written rule ("update the docs")
```

Line 335:

```text
did not hold, so this counts instead. Every case has to appear verbatim in at
```

Line 336:

```text
least one document.
```

Line 337:

```text
The popover's sections are the same kind of thing as the window's modules — an
```

Line 338:

```text
enumerated set of surfaces the app ships — so they are checked, but not the same
```

Line 339:

```text
way. The module check greps the prose for each name, which works because
```

Line 340:

```text
"Launch Services" is a phrase nothing else in the docs uses. The section names
```

Line 341:

```text
are not like that: the first draft of this check passed the moment it was
```

Line 342:

```text
written, because "Processes" was already in the docs as the name of a *console
```

Line 343:

```text
module*, and a check that cannot tell two surfaces apart because they share a
```

Line 344:

```text
word is a check that will report green through the drift it exists to catch.
```

Line 346:

```text
So it uses the marker form, like the menu-bar items, and compares both ways:
```

Line 348:

```text
<!-- popover-sections: Services, Agents, Processes, Connections -->
```

Line 374:

```text
The menu bar is the one surface a user cannot avoid, and its prose rotted
```

Line 375:

```text
hardest: docs/DESIGN-SYSTEM.md carried a two-row table of items — Fleet and
```

Line 376:

```text
Connections, with an argument about their opposite silhouettes — long after the
```

Line 377:

```text
app had collapsed to one, and three source comments said the same. The module
```

Line 378:

```text
and tool checks above would not have caught it, because both are one-way: they
```

Line 379:

```text
ask whether every case in an enum is described, never whether every thing
```

Line 380:

```text
described still exists. That is the direction this one failed in.
```

Line 382:

```text
So it compares both ways, against an explicit marker in the doc:
```

Line 384:

```text
<!-- menu-bar-items: fleet -->
```

Line 386:

```text
against the identifier of every MenuBarItemController the app constructs.
```

Line 390:

```text
Slurped, not line-based: the call site wraps after the open paren, which
```

Line 391:

```text
is how the first draft of this check found zero items and then reported
```

Line 392:

```text
the one real item as deleted.
```

Line 398:

```text
`grep .` again on each side: an empty variable still prints one empty
```

Line 399:

```text
line through printf, which comm then reports as a nameless item.
```

Line 417:

```text
A menu item bound to a selector the window has disabled is dead chrome: it draws
```

Line 418:

```text
a shortcut the user can read and cannot use. .fullScreenNone and a Full Screen
```

Line 419:

```text
menu entry cannot both be intended.
```

Line 423:

```text
Matches a real binding — #selector(...toggleFullScreen...) — not the word
```

Line 424:

```text
in a comment, so the note explaining the absence does not trip the check.
```

## Scripts/export-public-source.py

Line 72:

```text
No replacement, merges, history, remotes or working-tree reads.
```

## Scripts/fleetkit-sheet.sh

Line 2:

```text
Renders a contact sheet of every FleetKit primitive to build/design/.
```

Line 4:

```text
Scripts/fleetkit-sheet.sh          # render, print paths
```

Line 5:

```text
Scripts/fleetkit-sheet.sh --open   # render and open them
```

Line 7:

```text
Four images: light and dark, each also desaturated. The greyscale pair is the
```

Line 8:

```text
point. `accessibilityDifferentiateWithoutColor` is a read-only environment
```

Line 9:

```text
value that cannot be injected into a render, but the question it exists to
```

Line 10:

```text
answer — does this still read without hue — is answered better by stripping
```

Line 11:

```text
the hue from the finished pixels and looking. Anything that turns into an
```

Line 12:

```text
undifferentiated grey blob was encoding state in colour alone.
```

Line 14:

```text
The design sources are **symlinked** into a throwaway package, never copied,
```

Line 15:

```text
so the sheet always shows what actually ships. `Scripts/fleetkit-sheet/Sheet.swift`
```

Line 16:

```text
is the only file that belongs to this tool; add a primitive there when you add
```

Line 17:

```text
one to FleetKit.
```

Line 27:

```text
FleetCore as its own target: the app's FleetConsoleApp target is an executable,
```

Line 28:

```text
so its types cannot be imported from outside the package.
```

## Scripts/fleetkit-sheet/Sheet.swift

Line 6:

```text
A contact sheet of the real FleetKit primitives. The design files are
```

Line 7:

```text
symlinked into this target, not copied, so what renders here is what ships.
```

Line 9:

```text
MARK: - Sheet content
```

Line 120:

```text
The whole substrate, at a size where all three layers are
```

Line 121:

```text
separable: the field's wash, the 13/65 ruling over it, the
```

Line 122:

```text
grain over that. Anything that turns into a flat rectangle in
```

Line 123:

```text
the desaturated pair has lost a layer.
```

Line 128:

```text
The substrate ignores the safe area, which is right on
```

Line 129:

```text
a window and wrong in a swatch on a contact sheet.
```

Line 151:

```text
The alignment proof: badged and unbadged rows must start on the
```

Line 152:

```text
same vertical. A hairline behind both makes any drift visible.
```

Line 164:

```text
A faithful stand-in for DeviceNodeRow: same EntityIcon call, same
```

Line 165:

```text
trailing pip and latency badge, same detail line that states the
```

Line 166:

```text
path and not the health. This is the row the sidebar is made of.
```

Line 232:

```text
Regression case. A chip in a row accessory competes with a title
```

Line 233:

```text
that holds layoutPriority(1); squeeze the row and the loser is
```

Line 234:

```text
the chip. Unconstrained it compresses by *wrapping*, one
```

Line 235:

```text
character per line, which is what turned "Unmanaged" into a
```

Line 236:

```text
four-line orange block in the popover.
```

Line 237:

```text
The real UnmanagedRowView, at the real popover width, with the
```

Line 238:

```text
real strings. The long subtitle is the whole mechanism: its
```

Line 239:

```text
VStack holds layoutPriority(1), so it claims the width first
```

Line 240:

```text
and the accessory gets whatever is left.
```

Line 311:

```text
MARK: - Render
```

Line 313:

```text
/ Strips hue, keeping luminance. `accessibilityDifferentiateWithoutColor` is a
```

Line 314:

```text
/ read-only environment value, so it cannot be injected into a render — but the
```

Line 315:

```text
/ question that flag exists to answer is "does this still read without hue",
```

Line 316:

```text
/ and desaturating the finished pixels answers it directly and more honestly.
```

## Scripts/install-agent.sh

Line 2:

```text
Registers fleetd as a per-user launchd agent.
```

Line 4:

```text
This is the fallback path for unsigned local builds, where SMAppService cannot
```

Line 5:

```text
register the bundled agent. It uses the same mechanism launchd would use either
```

Line 6:

```text
way: a user LaunchAgent in ~/Library/LaunchAgents, loaded into the gui/$UID
```

Line 7:

```text
domain. No sudo, no root, no system-wide daemon.
```

Line 63:

```text
The controller does its first reconcile sweep before it binds the socket, and
```

Line 64:

```text
that sweep shells out to lsof/ps — measured at 1s on an idle machine but 39s
```

Line 65:

```text
after a burst of restarts. A single `sleep 2` reports a healthy install as
```

Line 66:

```text
broken, so poll until it answers.
```

## Scripts/install-cli.sh

Line 2:

```text
First-run helper: puts fleetctl on the user's PATH.
```

Line 4:

```text
FleetConsole ships its CLI inside the bundle at
```

Line 5:

```text
FleetConsole.app/Contents/Resources/bin/fleetctl. The app itself never needs
```

Line 6:

```text
this; the terminal does. This script symlinks the bundled binary into
```

Line 7:

```text
/usr/local/bin — falling back to ~/.local/bin when /usr/local/bin is not
```

Line 8:

```text
writable without sudo — so `fleetctl` works from any shell.
```

Line 10:

```text
Run it from the DMG's window or after copying the app to /Applications:
```

Line 11:

```text
/Applications/FleetConsole.app/Contents/Resources/bin/install-cli
```

## Scripts/make-icon.sh

Line 2:

```text
Draws Resources/AppIcon.icns from Scripts/appicon/Icon.swift and the emblem.
```

Line 4:

```text
Scripts/make-icon.sh          # regenerate the .icns
```

Line 5:

```text
Scripts/make-icon.sh --sheet  # also write a contact sheet to build/design
```

Line 7:

```text
The plate is code and the F is Sources/FleetConsoleApp/Brand/fleet-letter.png,
```

Line 8:

```text
the same file the app's mark loads. Every size in the iconset is drawn at its
```

Line 9:

```text
own scale rather than downsampled from 1024. Re-run this after changing either.
```

## Scripts/make-yazi-light.sh

Line 2:

```text
Derives Resources/yazi/theme-light.toml from theme-dark.toml.
```

Line 4:

```text
The Yazi surface is achromatic on purpose — see the header of theme-dark.toml:
```

Line 5:

```text
colour in this app is a *status* vocabulary, and a file browser spending green
```

Line 6:

```text
on "+x" two feet from a services list where green means verified is a second
```

Line 7:

```text
meaning on the console's most loaded signal.
```

Line 9:

```text
But achromatic is not appearance-independent. The dark theme is a five-step
```

Line 10:

```text
ramp built for a dark terminal background, and `PTYSurface.applyAppearance`
```

Line 11:

```text
makes that background follow the system: in Light Mode the panel turned white
```

Line 12:

```text
while Yazi went on painting #C8C9CD text and #55565A rules onto it — about
```

Line 13:

```text
1.3:1, which is not "low contrast", it is invisible.
```

Line 15:

```text
Both themes are therefore the same file with the ramp inverted, generated
```

Line 16:

```text
rather than hand-maintained, because two hand-kept copies of a 240-line theme
```

Line 17:

```text
is precisely the drift this repo counts everywhere else.
```

Line 19:

```text
dark            light           role
```

Line 20:

```text
#F2F3F5   →     #16181C         ink    — the focused row, brightest/darkest
```

Line 21:

```text
#C8C9CD   →     #3C3E44         plain  — ordinary entries
```

Line 22:

```text
#86878C   →     #74767C         muted  — chrome, parent column, metadata
```

Line 23:

```text
#55565A   →     #B9BBC0         faint  — dividers and rules
```

Line 24:

```text
#0B0D11   →     #FFFFFF         page   — the reversed row's own text
```

Line 26:

```text
The reversal survives the inversion, which is the point: `hovered` stays
```

Line 27:

```text
page-on-ink, so in dark mode it is a light row on a dark column and in light
```

Line 28:

```text
mode a dark row on a light one. Either way exactly one row is high-contrast.
```

## Scripts/measure-idle.sh

Line 2:

```text
Idle cost of one running process: CPU time used and resident memory over a
```

Line 3:

```text
window, sampled once a minute. Reads only; it does not start, signal or stop
```

Line 4:

```text
the process. Works on macOS (ps) and Linux (/proc).
```

Line 5:

```text
Usage: Scripts/measure-idle.sh <pid> [seconds=600]
```

Line 14:

```text
utime and stime are fields 14 and 15, in clock ticks; the command
```

Line 15:

```text
name in field 2 may contain spaces, so count from the closing paren.
```

Line 21:

```text
macOS: [[dd-]hh:]mm:ss.cc
```

## Scripts/notarize.sh

Line 2:

```text
Notarizes the staged FleetConsole.app and staples the ticket to that artifact.
```

Line 4:

```text
Signing proves who built the app. Notarization is Apple confirming they have
```

Line 5:

```text
scanned that exact build — without it Gatekeeper reports "Unnotarized Developer
```

Line 6:

```text
ID" and refuses to open it on any Mac but the one that compiled it. Stapling
```

Line 7:

```text
attaches the result so the app opens even with no network.
```

Line 9:

```text
Credentials are never handled here. `notarytool` reads them from a keychain
```

Line 10:

```text
profile you create once, interactively, with your own Apple ID. This script
```

Line 11:

```text
refuses to run rather than prompting for a password.
```

Line 22:

```text
PINNED NOTARY WORKER
```

Line 23:

```text
The helper reads this section; it is unreachable via script CLI arguments.
```

Line 24:

```text
All artifact operations use '.', never the replaceable supplied pathname.
```

Line 32:

```text
Refuse to submit an ad-hoc build: notarization requires a Developer ID signature
```

Line 33:

```text
with the hardened runtime, and failing here is clearer than failing at Apple.
```

Line 44:

```text
Two credential types, in preference order. An App Store Connect API key is the
```

Line 45:

```text
better one: it is a file plus two identifiers, so it works unattended and in CI
```

Line 46:

```text
with no password anywhere. A keychain profile is fine but has to be created
```

Line 47:

```text
interactively first.
```

Line 49:

```text
FLEETCONSOLE_ASC_KEY      path to AuthKey_XXXXXXXX.p8
```

Line 50:

```text
FLEETCONSOLE_ASC_KEY_ID   the key ID (the XXXXXXXX in the filename)
```

Line 51:

```text
FLEETCONSOLE_ASC_ISSUER   the issuer UUID from App Store Connect
```

Line 83:

```text
ditto, not zip: it preserves the bundle's symlinks and extended attributes,
```

Line 84:

```text
which a plain zip silently mangles.
```

Line 88:

```text
Switch the submission child by directory identity; its relative ZIP name
```

Line 89:

```text
survives repository, ancestor and private-scratch renames/replacements.
```

Line 103:

```text
The helper cleans the archive through its pinned private directory.
```

## Scripts/package-dmg.sh

Line 2:

```text
Packages a staged FleetConsole.app into a drag-and-drop DMG.
```

Line 4:

```text
Usage: Scripts/package-dmg.sh <output-dir> [--volname <name>]
```

Line 6:

```text
The DMG is the distribution shape Apple users expect: open it, drag the app
```

Line 7:

```text
onto the Applications symlink, done. Built with a bare APFS UDZO image — no
```

Line 8:

```text
third-party tooling, no network access, no privileges.
```

Line 10:

```text
Requirements: a staged, signed and notarized FleetConsole.app inside
```

Line 11:

```text
<output-dir> (see Scripts/build-app.sh and Scripts/notarize.sh). The app is
```

Line 12:

```text
copied verbatim; this script never re-signs.
```

Line 38:

```text
A DMG that ships an unsigned or unnotarized app is a support incident waiting
```

Line 39:

```text
to happen. Refuse rather than package a build Gatekeeper will reject.
```

Line 40:

```text
(codesign -dv always exits nonzero; its evidence is on stderr. Capture first,
```

Line 41:

```text
then grep — never pipe a nonzero producer straight into grep under pipefail.)
```

Line 66:

```text
Sign the disk image with the identity that signed the app. An unsigned image
```

Line 67:

```text
can be notarized and stapled, yet Gatekeeper's install check still rejects it
```

Line 68:

```text
with "no usable signature".
```

Line 73:

```text
Notarize the DMG itself and staple, so the disk image passes Gatekeeper too.
```

Line 74:

```text
Uses the same keychain profile as Scripts/notarize.sh.
```

## Scripts/product-detail-sheet.sh

Line 2:

```text
Renders the two privacy-bounded FleetConsole product-detail views.
```

Line 4:

```text
Scripts/product-detail-sheet.sh          # render, print the directory
```

Line 5:

```text
Scripts/product-detail-sheet.sh --open   # render and open it
```

Line 7:

```text
The app runs with a disposable CFFIXED_USER_HOME inside the controlled output
```

Line 8:

```text
directory. The bounded renderer uses synthetic data, disables keychain access,
```

Line 9:

```text
and never visits Terminal, Files, account, or other tool surfaces.
```

## Scripts/release-policy-mock-tool.py

Line 56:

```text
Packaging fixtures have no source repository. Never run a system Git shim
```

Line 57:

```text
(which can initialize Xcode tooling) to obtain a synthetic revision.
```

## Scripts/release-staging.py

Line 36:

```text
Only the missing suffix is normalized; existing symlinks were resolved first.
```

Line 49:

```text
~/Applications (or /Applications on non-macOS test hosts) may not exist.
```

Line 50:

```text
Its canonical path is still forbidden, and all other errors fail closed.
```

Line 141:

```text
cwd is an OS-held directory identity, not a path passed to the
```

Line 142:

```text
child. Neither ancestor nor bundle renames can redirect '.'.
```

Line 148:

```text
Shell pwd can resolve a stale PWD through a replacement
```

Line 149:

```text
symlink. getcwd reports this still-pinned directory instead.
```

Line 236:

```text
Private archive scratch is independent of the mutable output path.
```

Line 237:

```text
Keep its root pinned for creation/cleanup too; a renamed stage
```

Line 238:

```text
cannot redirect archive writes or remove a pre-existing archive.
```

## Scripts/surface-sheet.sh

Line 2:

```text
Renders every FleetConsole surface to build/design/surfaces/.
```

Line 4:

```text
Scripts/surface-sheet.sh          # render, print the directory
```

Line 5:

```text
Scripts/surface-sheet.sh --open   # render and open it
```

Line 7:

```text
The renderer lives in the app target (Sources/FleetConsoleApp/SurfaceRenderer.swift)
```

Line 8:

```text
behind -DFLEET_SURFACE_RENDERER, so what is captured is the shipping view code
```

Line 9:

```text
driven by fixtures — not a reimplementation of it beside the app. The flag is
```

Line 10:

```text
passed here and nowhere else; Scripts/build-app.sh never defines it, so neither
```

Line 11:

```text
the renderer nor its fixtures reach the signed bundle.
```

Line 13:

```text
Companion to Scripts/fleetkit-sheet.sh, which does the same for the primitives
```

Line 14:

```text
a surface is composed of.
```

Line 25:

```text
`|| true` used to sit on the end of this, which made a build failure look like a
```

Line 26:

```text
successful run that happened to render nothing. The renderer only compiles under
```

Line 27:

```text
-DFLEET_SURFACE_RENDERER, so it is exactly the code a normal build never checks,
```

Line 28:

```text
and "✓ 0 surfaces" is not a thing this script should ever be able to print.
```

Line 40:

```text
The renderer sets its activation policy to .prohibited, so this never steals
```

Line 41:

```text
focus and never shows a window — but it is still a GUI process and needs a
```

Line 42:

```text
session to draw into, which is why it runs here rather than over ssh.
```

## Scripts/test-public-source.py

Line 62:

```text
The fixture deliberately commits both public and private inputs.
```

Line 63:

```text
User/global ignore rules must not silently omit either category.
```

## Scripts/test-release-policy.py

Line 21:

```text
Loading the production helper must not leave __pycache__ in the checkout.
```

Line 61:

```text
No rewritten guards: the fixture always runs current production bytes.
```

Line 101:

```text
Intercept absolute tool names too, including the old /usr/sbin/lsof call.
```

Line 314:

```text
TEST DATA injection at the actual reservation syscall, after stage fd
```

Line 315:

```text
open. Production scripts are copied unchanged; no production race hook.
```

Line 633:

```text
TEST DATA ONLY: different path spelling, same device/inode as Applications.
```

Line 648:

```text
check-only production entry point: no real Applications writes, even if it regresses.
```

## Scripts/test-source-privacy.py

Line 124:

```text
A tracked deletion is not in the current deliverable.
```

Line 127:

```text
Binary assets are outside this source-text check.
```

## Scripts/test-terminal-integration.py

Line 57:

```text
Preserve a visible preparing state before the deterministic reply.
```

Line 101:

```text
SwiftPM normally supplies these when launching the helper. Invoke it
```

Line 102:

```text
directly to add --verify-live, enabling the observational Overview test.
```

Line 122:

```text
Suites share process-wide AppKit state; .serialized only serializes
```

Line 123:

```text
cases within one suite. Isolate the native suites from each other.
```

## Scripts/update-installed.sh

Line 2:

```text
Builds a committed revision and swaps it in for /Applications/FleetConsole.app.
```

Line 4:

```text
Scripts/update-installed.sh              # HEAD
```

Line 5:

```text
Scripts/update-installed.sh <git-ref>    # any commit, branch or tag
```

Line 6:

```text
Scripts/update-installed.sh <git-ref> --no-launch  # replace without launch
```

Line 7:

```text
Scripts/update-installed.sh <full-source-revision> --prebuilt  # reviewed signed artifact
```

Line 8:

```text
Offline mode: FLEETCONSOLE_OFFLINE=1 and an existing FLEETCONSOLE_DEPENDENCY_CACHE.
```

Line 10:

```text
The build comes from a clean, detached worktree of the ref, so uncommitted
```

Line 11:

```text
edits in this checkout — yours or another session's — never reach the
```

Line 12:

```text
installed app. Then:
```

Line 14:

```text
1. the running app is asked to quit;
```

Line 15:

```text
2. the installed bundle is moved to the Trash, not deleted, so the update is
```

Line 16:

```text
one drag to undo. Moving it is a rename on the same volume: the running
```

Line 17:

```text
fleetd keeps executing its old binary and every managed service stays up;
```

Line 18:

```text
3. the new bundle is copied in, its signature verified, and the app relaunched.
```

Line 20:

```text
fleetd is not restarted. It picks up the new binary the next time launchd
```

Line 21:

```text
starts it; pass --restart-controller to kickstart it now.
```

Line 76:

```text
Offline mode consumes an existing pinned cache; it never fetches a package.
```

Line 77:

```text
Copy only dependency state into the new worktree, not compiled products.
```

Line 91:

```text
-X omits file-provider/Finder metadata that resource signing rejects.
```

Line 103:

```text
A local replacement must not silently downgrade the installed publisher or
```

Line 104:

```text
identity. Optional notarization uses only the existing configured workflow.
```

Line 105:

```text
Publisher checks precede quitting or moving the app.
```

## Scripts/verify-rust-clients.sh

Line 2:

```text
Local verification for the Rust clients on macOS or Linux. No controller is
```

Line 3:

```text
started, no network is used beyond Cargo's cache, nothing is installed.
```

Line 4:

```text
Usage: Scripts/verify-rust-clients.sh [--skip-gpui]
```

Line 5:

```text
--skip-gpui  for a host without GPUI's system libraries (the terminal client
```

Line 6:

```text
and the core are still checked).
```

Line 7:

```text
CARGO_TARGET_DIR is respected. The pinned toolchain comes from
```

Line 8:

```text
rust-toolchain.toml.
```

Line 36:

```text
Fixture snapshots report this controller version. A default release binary
```

Line 37:

```text
that contains it has synthetic data compiled in. The marker is assembled so
```

Line 38:

```text
this script itself does not contain it verbatim.
```

Line 55:

```text
Leave default binaries in place for anyone running them after this script.
```

## Sources/FleetConsoleApp/AgentRegistration.swift

Line 6:

```text
/ Shared by the Agents pane and task ownership picker. It has no daemon client
```

Line 7:

```text
/ or polling task: a roster edit is only an atomic client-local file write.
```

## Sources/FleetConsoleApp/AppModel.swift

Line 5:

```text
/ One observable box per service. Rows observe *their own* record, so a snapshot
```

Line 6:

```text
/ that changes one service's CPU number re-renders one row, not the whole list.
```

Line 32:

```text
Membership-level state: reassigned only when the *set* changes.
```

Line 44:

```text
/ Local monotonic receipt time, independent of the daemon's wall clock.
```

Line 45:

```text
/ Cleared on connection transitions so a reconnect cannot reuse old evidence.
```

Line 50:

```text
/ `config.json`, watched. Every section toggle, cadence and feature flag
```

Line 51:

```text
/ resolves here, so no view invents its own answer. Built first because the
```

Line 52:

```text
/ probes below take their intervals from it.
```

Line 57:

```text
/ Licensing and the trial clock. Declared before the probes that gate on
```

Line 58:

```text
/ it (`system` reads its answer every sample), so property order is also
```

Line 59:

```text
/ the dependency order. See FleetCore/License.swift.
```

Line 67:

```text
/ Today's agent spend. Sampled on its own slow cadence rather than the
```

Line 68:

```text
/ snapshot's — see `AgentCostProbe` — and only when the feature is on.
```

Line 71:

```text
/ Drives lease countdowns and "x ago" labels without touching the data model.
```

Line 74:

```text
/ Which popover section the next opening should land on, set by the
```

Line 75:

```text
/ status item's dropdown and cleared by the popover once it has moved.
```

Line 76:

```text
/ `nil` means no one asked, and the popover falls back to its own rule.
```

Line 79:

```text
Nonisolated so `deinit` can invalidate it; nothing observes this handle.
```

Line 85:

```text
Cadences come from config, clamped there. Read once at construction:
```

Line 86:

```text
a live interval change would mean tearing down and rebuilding the two
```

Line 87:

```text
timers, and the honest cost of editing a sampling rate is a relaunch.
```

Line 115:

```text
/ The run loop holds the timer even though the closure is weak, so it has to
```

Line 116:

```text
/ be invalidated here or a per-view instance would strand a live tick.
```

Line 121:

```text
MARK: - Snapshot application
```

Line 132:

```text
Services: update in place; only reassign the array when membership changes.
```

Line 174:

```text
Notify once, for messages we have not seen before.
```

Line 177:

```text
don't replay the backlog on launch
```

Line 184:

```text
Retain bounded metadata from actual pushes. No transcript, purpose, argv or paths.
```

Line 200:

```text
Rides the snapshot tick as a heartbeat only: the probe throttles
```

Line 201:

```text
itself, so this asks far more often than it scans.
```

Line 205:

```text
MARK: - Derived state
```

Line 211:

```text
/ Actually up, as opposed to merely on the books. An expired lease still has
```

Line 212:

```text
/ a row; it does not have a running process.
```

Line 219:

```text
/ The mailbox as the operator sees it: everything the controller holds,
```

Line 220:

```text
/ less what was dismissed here.
```

Line 222:

```text
/ The controller's mailbox, unfiltered.
```

Line 235:

```text
/ Uses the existing app clock, invalidating the graph only at an evidence
```

Line 236:

```text
/ boundary. No additional poller, animation or per-frame graph layout.
```

Line 250:

```text
MARK: - Menu-bar summary
```

Line 252:

```text
One item, because the app puts up one — see `MenuBarItemController`, whose
```

Line 253:

```text
own comment records the collapse from five to two to one.
```

Line 255:

```text
This block used to open by explaining "two items, two deliberately
```

Line 256:

```text
different silhouettes", and to carry a full second set of properties —
```

Line 257:

```text
`connectionsGlyph`, `connectionsText`, `connectionsTint`,
```

Line 258:

```text
`connectionsTooltip` — computing a live summary of the network for an item
```

Line 259:

```text
that no longer existed. Nothing read them. They were the same drift the
```

Line 260:

```text
design audit's menu-bar check was added to catch in the *documentation*,
```

Line 261:

```text
one layer down where a script comparing prose against
```

Line 262:

```text
`MenuBarItemController(identifier:)` could not see them: every fact they
```

Line 263:

```text
assembled is on the Connections tab of the popover, which is where it is
```

Line 264:

```text
actually read. Deleted rather than kept as a seam — the popover is the
```

Line 265:

```text
seam, and a second item would start from it.
```

Line 267:

```text
/ CPU, RAM and disk, in that order, as the menu bar draws them. A reading
```

Line 268:

```text
/ that has not been taken yet is a dash, never a confident zero.
```

Line 278:

```text
/ The one thing worth acting on, after the meters: someone waiting on you,
```

Line 279:

```text
/ then anything wrong. Empty when there is nothing to do.
```

Line 287:

```text
/ The same precedence as one sentence, for the identity rows in the
```

Line 288:

```text
/ popover header and the dashboard sidebar.
```

Line 323:

```text
One line of network, and only when something is wrong with it.
```

Line 325:

```text
The collapse to a single menu-bar item took the network summary off the
```

Line 326:

```text
menu bar with the Connections item, and nothing replaced it: with the
```

Line 327:

```text
link down or the tailnet stopped, the one always-visible surface said
```

Line 328:

```text
"3 running" and explained none of the health checks that were about to
```

Line 329:

```text
start failing. This is not the second item coming back — it makes no
```

Line 330:

```text
claim in the glyph and never changes `fleetTint`, because a dropped
```

Line 331:

```text
Wi-Fi is not a fact about the fleet. It is the sentence that saves you
```

Line 332:

```text
opening the popover to find out why.
```

Line 338:

```text
/ The network in one line, or nil when there is nothing to say.
```

Line 340:

```text
/ Only the conditions that break something: no route off the machine, and a
```

Line 341:

```text
/ tailnet that is installed but not running — which silently strips every
```

Line 342:

```text
/ `100.x` address the device probes depend on. A working network produces no
```

Line 343:

```text
/ line at all, on the same rule as the VLAN chrome: absent, not "all fine".
```

Line 360:

```text
/ Evidence older than this is rendered as "unknown (stale)" rather than as its
```

Line 361:

```text
/ last-known-good value.
```

Line 370:

```text
MARK: - Actions
```

Line 372:

```text
/ `surfacesErrors` is the difference between a verb and a poll.
```

Line 374:

```text
/ A failed **action** — stop, restart, kill — has to interrupt: you asked
```

Line 375:

```text
/ for something, it did not happen, and you need to know before you assume
```

Line 376:

```text
/ it did. A failed **refresh** must not. `refreshAll()` runs on every
```

Line 377:

```text
/ popover open, so routing its failure to `actionError` meant that with the
```

Line 378:

```text
/ controller down, clicking the menu-bar item raised a modal alert saying
```

Line 379:

```text
/ the socket was missing — every single time, on top of the
```

Line 380:

```text
/ `ControllerDownBanner` and the footer pip that were already saying the
```

Line 381:

```text
/ same thing in the same window. Three copies of one fact, one of them
```

Line 382:

```text
/ blocking, for a condition the user did not cause and cannot dismiss by
```

Line 383:

```text
/ acknowledging it.
```

Line 385:

```text
/ A refresh failure is ambient state, and the app already has a place for
```

Line 386:

```text
/ ambient state: `connected` / `connectionError`, which the banner reads.
```

Line 394:

```text
`then` runs on both paths deliberately. It is a *finally*, not a
```

Line 395:

```text
success handler: its callers use it to clear an in-flight flag,
```

Line 396:

```text
and a flag cleared only on success leaves a control spinning for
```

Line 397:

```text
ever the one time the controller does not answer — which is
```

Line 398:

```text
precisely when you are looking at it.
```

Line 429:

```text
/ Adopts an unmanaged process into the registry.
```

Line 431:

```text
/ The third answer on an unmanaged row, between "this is expected, stop
```

Line 432:

```text
/ telling me" (allow-list) and "I will go look at it myself" (Activity
```

Line 433:

```text
/ Monitor): *this one matters, watch it*. It gets an owner, a purpose, a
```

Line 434:

```text
/ lease and a timeline, and the controller still refuses to signal it — so
```

Line 435:

```text
/ unlike End Process this is not a destructive verb and needs no feature
```

Line 436:

```text
/ flag, no uid check and no confirmation.
```

Line 441:

```text
/ The same verb from the process table, where a row is a pid rather than an
```

Line 442:

```text
/ entry in the reconciler's list. The controller accepts a bare pid and
```

Line 443:

```text
/ re-verifies it either way, so this is the same call with a weaker
```

Line 444:

```text
/ identifier — not a second, looser path in.
```

Line 458:

```text
/ Adds a command to the expected-listener allow-list in config.json. This is
```

Line 459:

```text
/ the explicit, reviewable act the threat model asks for — one click, but it
```

Line 460:

```text
/ leaves a config entry and an event behind, not a hidden dismissal.
```

Line 486:

```text
/ Takes messages off every surface — the Agents tab, the mailbox, Home and
```

Line 487:

```text
/ the menu-bar count. A view decision, not a deletion: the controller keeps
```

Line 488:

```text
/ its history, so `fleetctl inbox` still shows an agent what it said.
```

Line 501:

```text
/ True while a re-evidence request is in flight, so the control that
```

Line 502:

```text
/ started it can say so. A refresh that completes in 200 ms and changes
```

Line 503:

```text
/ nothing visible is indistinguishable from a button that does nothing —
```

Line 504:

```text
/ which is exactly what the old one was.
```

Line 515:

```text
/ The refresh a *person* asked for: re-probe everything this app samples
```

Line 516:

```text
/ itself, and make the controller re-capture the process table and re-run
```

Line 517:

```text
/ the sweep.
```

Line 519:

```text
/ Distinct from `refreshAll()`, and the distinction is the bug this fixes.
```

Line 520:

```text
/ `refreshAll` sends `.snapshot`, which the controller answers out of
```

Line 521:

```text
/ memory without sampling anything — correct for the automatic call on
```

Line 522:

```text
/ every popover open, and worthless as a button, because the subscription
```

Line 523:

```text
/ already pushes that same state every supervisor tick. Services, unmanaged
```

Line 524:

```text
/ processes and agent sessions are only rebuilt inside `runReconcile`, so
```

Line 525:

```text
/ `.reconcile` is the only request that can change what the Services and
```

Line 526:

```text
/ Agents tabs are showing.
```

Line 544:

```text
A poll, not a verb — see `perform`. The banner reports a down
```

Line 545:

```text
controller; a modal must not.
```

Line 587:

```text
/ Dismissed message IDs, kept in user defaults. Bounded: message IDs only
```

Line 588:

```text
/ grow, so the oldest dismissals are the ones the controller has already
```

Line 589:

```text
/ rotated out of the snapshot.
```

## Sources/FleetConsoleApp/CredentialIsolation.swift

Line 19:

```text
/ Pure context checks precede any Security.framework entry. Debug builds,
```

Line 20:

```text
/ interpreters, test runners and unbundled tools cannot select real storage.
```

Line 67:

```text
/ Missing test injection fails locally. There is deliberately no fallback.
```

Line 75:

```text
/ The backend is a lazy factory: a denied context cannot initialize production
```

Line 76:

```text
/ storage or a singleton as a side effect of deciding whether it is allowed.
```

## Sources/FleetConsoleApp/DaemonClient.swift

Line 4:

```text
/ Talks to fleetd over the local socket. The app is a client and a dashboard —
```

Line 5:

```text
/ it never supervises the controller and never touches processes directly.
```

Line 7:

```text
/ `@unchecked Sendable`: mutable state is behind `lock`; the request queue
```

Line 8:

```text
/ and policy are immutable. The subscription runs on its own `Thread`, so this really
```

Line 9:

```text
/ is shared across threads.
```

Line 46:

```text
/ Read every pass of the subscribe loop, written by `stop()` from the main
```

Line 47:

```text
/ thread. It is the only thing that ends that loop, so a missed write is a
```

Line 48:

```text
/ thread that never stops.
```

Line 53:

```text
/ Long-lived subscription with automatic reconnect. fleetd pushes a snapshot
```

Line 54:

```text
/ on every state change, so the UI never polls.
```

Line 56:

```text
/ The callbacks are `@MainActor` in the signature rather than by convention.
```

Line 57:

```text
/ Delivery goes through `DispatchQueue.main.async` rather than
```

Line 58:

```text
/ `Task { @MainActor }` because snapshots must be applied in arrival order,
```

Line 59:

```text
/ and the queue is FIFO where unstructured tasks are not.
```

Line 63:

```text
Fixture sheets must not race a live subscription. Live verification
```

Line 64:

```text
takes the ordinary subscription path and uses real controller data.
```

Line 72:

```text
timeout 0 = block indefinitely: this connection stays open.
```

Line 74:

```text
Both the write and the reads below throw when fleetd restarts,
```

Line 75:

```text
and this loop reconnects forever — the fd has to go back on
```

Line 76:

```text
every exit path, not just the clean one.
```

Line 139:

```text
/ The one verb the Task Composer uses: hand the controller a supervised
```

Line 140:

```text
/ service. It is a request, not a command — the controller alone launches
```

Line 141:

```text
/ and reaps, and this reply carries the resulting `ServiceRecord`.
```

Line 147:

```text
/ Whether the launchd agent is registered, so the UI can tell "not installed"
```

Line 148:

```text
/ apart from "installed but down".
```

Line 154:

```text
/ Hop to the main actor while keeping `DispatchQueue.main`'s FIFO ordering.
```

Line 155:

```text
/ The block is already on the main thread, so `assumeIsolated` states a fact
```

Line 156:

```text
/ rather than escaping a check.
```

## Sources/FleetConsoleApp/Design/AwarenessInk.swift

Line 4:

```text
/ Semantic canvas materials. Relationships use the user accent; selection is
```

Line 5:

```text
/ an outline, not an orange surface with appearance-dependent text.
```

## Sources/FleetConsoleApp/Design/ConsoleModule.swift

Line 3:

```text
/ The middle column's modules. Order is the order in the toolbar picker and
```

Line 4:

```text
/ the order of the ⌘1…⌘6 shortcuts.
```

Line 6:

```text
/ It lives in `Design/` rather than beside `ConsoleModel`, for the same reason
```

Line 7:

```text
/ `StatusTone` does: the list is a design declaration before it is navigation
```

Line 8:

```text
/ state. `ConsoleMetrics.modulePickerWidth` is a function of `allCases.count`,
```

Line 9:

```text
/ so with the enum in the view layer a token in `Design/Tokens.swift` reached
```

Line 10:

```text
/ *up* into `Views/Console/` for its value — and `Scripts/fleetkit-sheet.sh`,
```

Line 11:

```text
/ which symlinks the design sources into a throwaway package so the contact
```

Line 12:

```text
/ sheet renders what actually ships, could not resolve the picker width at all
```

Line 13:

```text
/ without dragging `ConsoleModel`, `AppModel` and the rest of the console in
```

Line 14:

```text
/ behind it. The alternatives were a stubbed module list in the sheet, which
```

Line 15:

```text
/ makes the one number the sheet exists to show a fiction, or this.
```

Line 17:

```text
/ Nothing here depends on the console's object graph — the symbol, the raw
```

Line 18:

```text
/ label and the digit index are all the enum's own.
```

Line 47:

```text
/ Keyboard equivalent in the View menu (⌘1…).
```

## Sources/FleetConsoleApp/Design/FleetRow.swift

Line 4:

```text
The two primitives every list row in FleetConsole is built from.
```

Line 6:

```text
Before this, the hover state, highlight background, chevron rotation, expansion
```

Line 7:

```text
animation and padding were reimplemented in four different row views, which is
```

Line 8:

```text
why they had drifted apart by a point here and a pixel there. There is now one
```

Line 9:

```text
implementation; a row supplies content, not chrome.
```

Line 11:

```text
/ Icon + title + subtitle + optional trailing text and accessory.
```

Line 21:

```text
/ A short word set beside the title — a state — in the tone's ink when
```

Line 22:

```text
/ it is one to act on, so the subtitle line is left for what the row is.
```

Line 29:

```text
/ Subtitle sits under the title (regular rows) or beside it (compact rows).
```

Line 68:

```text
Tail, not middle. A row subtitle is composed prose
```

Line 69:

```text
read left to right — "pid 54610 · first seen 13h
```

Line 70:

```text
17m ago", "claude · local API for triage" — where
```

Line 71:

```text
the leading tokens identify and the trailing ones
```

Line 72:

```text
qualify. Middle truncation ate the qualifier and
```

Line 73:

```text
kept a meaningless tail, turning summaries into
```

Line 74:

```text
"pid…p 8h 10m". Middle stays where both ends are
```

Line 75:

```text
load-bearing: paths, socket pairs, reverse-DNS
```

Line 76:

```text
labels. Those are identifiers, not sentences.
```

Line 90:

```text
`fixedSize` for the same reason `Tag` has it, and it was
```

Line 91:

```text
missing here while `Tag` was guarded by its own audit
```

Line 92:

```text
check. A trailing text is a timestamp, a port or a
```

Line 93:

```text
duration — a short, complete, already-abbreviated value —
```

Line 94:

```text
competing for width against a title holding
```

Line 95:

```text
`layoutPriority(1)`. Without this it loses and truncates,
```

Line 96:

```text
and the surface sheet showed all three Needs-attention
```

Line 97:

```text
rows doing it at once: "12…", "2m a…", and one clipped to
```

Line 98:

```text
the single character "1". A timestamp that truncates is
```

Line 99:

```text
not a shorter timestamp, it is no timestamp — "12…" is
```

Line 100:

```text
twelve minutes or twelve hours or twelve days.
```

Line 102:

```text
The title is the right loser: it is one line already, and
```

Line 103:

```text
its full text is in the subtitle and the row's tooltip.
```

Line 127:

```text
/ A row that expands in place. Owns every piece of interaction chrome so that
```

Line 128:

```text
/ individual rows cannot drift apart from one another again.
```

Line 195:

```text
/ Small actions strip shown inside an expanded row.
```

Line 209:

```text
/ The connection pip used in footers: the one place a bare dot is still the
```

Line 210:

```text
/ right primitive, because there is no entity to identify — only a state.
```

## Sources/FleetConsoleApp/Design/Formatters.swift

Line 3:

```text
Console formatting — window-precise counterparts to `SystemFmt` (popover) and
```

Line 4:

```text
`Fmt` (shared with the CLI).
```

Line 6:

```text
The window shows numbers a popover never would: full-precision byte counts,
```

Line 7:

```text
per-second rates with a decimal, load averages, latencies. All of them are
```

Line 8:

```text
formatted in exactly one place, so "1.42 GB/s" cannot render three different
```

Line 9:

```text
ways across three modules. Everything here pairs with `.monospacedDigit()`
```

Line 10:

```text
at the call site — a formatter cannot enforce that, the view must.
```

Line 12:

```text
/ A `ByteCountFormatter` that can be shared across threads.
```

Line 14:

```text
/ `ByteCountFormatStyle` is the Sendable value type that would replace it, and it
```

Line 15:

```text
/ renders kilobytes as "kB" where this app has always shown "KB". So the
```

Line 16:

```text
/ formatter stays and the sharing is made safe instead.
```

Line 36:

```text
MARK: Bytes
```

Line 38:

```text
/ "994.66 GB" — the full-precision count for capacities and totals.
```

Line 43:

```text
/ "1.42 GB/s" for live throughput; nil is a genuine "not sampled" em dash,
```

Line 44:

```text
/ and sub-KB rates floor at zero rather than implying precision they lack.
```

Line 50:

```text
MARK: Rates and ratios
```

Line 52:

```text
/ One-decimal percentage for process CPU ("37.4%"), where Activity
```

Line 53:

```text
/ Monitor parity matters. Whole percentages are reserved for utilisation
```

Line 54:

```text
/ tiles, where the decimal would claim precision a 2 s average lacks.
```

Line 65:

```text
/ Load averages: two decimals, always, so columns align.
```

Line 70:

```text
/ "12 ms" / "0.8 ms" — latency with one significant decimal under 10.
```

Line 76:

```text
MARK: Processes
```

Line 78:

```text
/ PIDs are identifiers, not quantities: no grouping separators, ever.
```

Line 89:

```text
/ Thread/user-time pair from `proc_taskinfo`, seconds with one decimal.
```

Line 97:

```text
MARK: Clock
```

Line 105:

```text
/ Event-log timestamps. Twenty-four hour, seconds included, because the
```

Line 106:

```text
/ event log is where ordering disputes get settled.
```

## Sources/FleetConsoleApp/Design/OurosIdentity.swift

Line 4:

```text
The Ouros app identity, in three sizes of one idea: the badge, the badge with
```

Line 5:

```text
its name and one live line, and that row as the profile card that closes a
```

Line 6:

```text
sidebar. Nothing here knows about FleetConsole — the mark and the words are
```

Line 7:

```text
the caller's — so every Ouros app can wear the same three pieces.
```

Line 9:

```text
/ The product's mark, on its icon plate or on nothing at all.
```

Line 11:

```text
/ With no plate the mark is ink on whatever surface it sits on, which is how
```

Line 12:

```text
/ it appears inside the app: a tile of another colour in the popover header
```

Line 13:

```text
/ or the sidebar reads as a sticker on the surface rather than part of it.
```

Line 14:

```text
/ The plate is for places that show the app *as an icon*.
```

Line 18:

```text
/ Handed the badge's side length; the mark sets its own margin.
```

Line 37:

```text
/ Badge, product name and one live line. The line carries state, so it takes
```

Line 38:

```text
/ the tone's ink when there is something wrong and stays secondary otherwise.
```

Line 64:

```text
/ The bottom-left card: who this is, and the one menu for account and app
```

Line 65:

```text
/ links. A card rather than a footer, so it sits inside the sidebar's margins
```

Line 66:

```text
/ instead of ruling a line across the whole window.
```

Line 99:

```text
/ FleetConsole's mark: the blackletter F, drawn as a template so it takes the
```

Line 100:

```text
/ surface's own ink in light and dark — quiet beside the name, never a tile.
```

Line 102:

```text
/ The badge's side length.
```

Line 119:

```text
/ FleetConsole's brand asset: the blackletter F, ink on a transparent ground.
```

Line 122:

```text
/ Looked up by hand rather than through SwiftPM's `Bundle.module`, whose
```

Line 123:

```text
/ generated accessor checks the .app's root — where a signed bundle cannot
```

Line 124:

```text
/ hold a resource bundle — and then a build-machine path, and traps when
```

Line 125:

```text
/ both miss. `assemble-app.sh` copies the bundle into Contents/Resources;
```

Line 126:

```text
/ in a development build it sits beside the executable.
```

## Sources/FleetConsoleApp/Design/QuantizedCardGrid.swift

Line 4:

```text
/ One footprint for every peer in a section, including its last row.
```

Line 5:

```text
/ Measure at the final column width so wrapped content sets the height budget.
```

Line 6:

```text
/ No preference/state feedback loop is needed when the window resizes.
```

Line 9:

```text
/ Compact artifacts use the widest peer rather than an arbitrary minimum.
```

## Sources/FleetConsoleApp/Design/RetroGauge.swift

Line 3:

```text
An analog dial for a bounded 0…1 metric — the instrument half of the Overview
```

Line 4:

```text
module, beside the traces that carry its history.
```

Line 6:

```text
Why an analog gauge at all, in an app that is otherwise flat and typographic:
```

Line 7:

```text
a needle is read as a *position on a fixed scale* without being decoded. A
```

Line 8:

```text
numeral has to be compared against a range you hold in your head ("is 77%
```

Line 9:

```text
memory bad?"); a needle sitting two ticks under the red band answers that
```

Line 10:

```text
before you have read the number. The five stacked cards this replaces each
```

Line 11:

```text
spent a full card header on a numeral that told you nothing without that
```

Line 12:

```text
context. So the dial is not nostalgia looking for a job — it is the densest
```

Line 13:

```text
honest encoding of "where in its range is this, right now".
```

Line 15:

```text
The name is older than the drawing. It was a machined instrument once: a
```

Line 16:

```text
filled face, a gradient bezel, an Aqua highlight. The Sketchfield pass took
```

Line 17:

```text
all three off — a lit plastic dial floating over a drifting field is an
```

Line 18:

```text
object photographed onto a page — and what is left is the construction a
```

Line 19:

```text
compass leaves. Nothing about the geometry, the thresholds or the
```

Line 20:

```text
accessibility behaviour changed with it.
```

Line 22:

```text
Why it lives in Design/ rather than beside the module that uses it: this is
```

Line 23:

```text
where the design audit allows a hue and an opacity literal to be written down,
```

Line 24:

```text
because this is where they are *chosen* rather than typed next to whatever was
```

Line 25:

```text
already on screen. Every number below is named and argued for on that basis.
```

Line 27:

```text
What it inherits from the rest of FleetKit, unchanged:
```

Line 29:

```text
**Colour is a status vocabulary.** The bezel, face, ticks and readout plate
```

Line 30:

```text
are achromatic in both appearances. The only hue on the dial is the tone,
```

Line 31:

```text
and it appears in exactly two places — the value arc and the needle.
```

Line 32:

```text
**Nothing depends on colour alone.** The needle's angle carries the value,
```

Line 33:

```text
the readout carries the number, and under Differentiate Without Colour the
```

Line 34:

```text
tone's `verdict` glyph appears on the face.
```

Line 35:

```text
**No confident zero.** `value: nil` is a metric that has not been sampled
```

Line 36:

```text
— the first tick after launch, a GPU that withheld its utilisation key —
```

Line 37:

```text
and it parks the needle at the zero stop, drops the value arc entirely and
```

Line 38:

```text
reads "—". A needle resting at zero and a needle resting at *no reading*
```

Line 39:

```text
must not look the same, which is why the parked needle is dimmed and the
```

Line 40:

```text
arc is absent rather than zero-length.
```

Line 42:

```text
/ A 240° analog dial for a value in 0…1.
```

Line 44:

```text
/ 0…1, or nil when the metric has not been sampled yet.
```

Line 47:

```text
/ The metric's name, on the face. Two or three characters: CPU, MEM, GPU.
```

Line 49:

```text
/ The formatted current value, under the hub. Already includes its unit.
```

Line 55:

```text
MARK: Geometry
```

Line 57:

```text
240° with the gap at the bottom: the two dead quadrants are where the
```

Line 58:

```text
readout goes, so the dial spends none of its diameter on chrome. A full
```

Line 59:

```text
360° ring has nowhere to put the number and no unambiguous zero.
```

Line 64:

```text
/ Where the redline starts, taken from the same thresholds the tones use
```

Line 65:

```text
/ rather than a number chosen to look right. A dial whose red band and whose
```

Line 66:

```text
/ needle colour disagree about "bad" is worse than a dial with no band.
```

Line 69:

```text
/ Ring widths as a share of the diameter, so a gauge at any size keeps its
```

Line 70:

```text
/ proportions. Solved at 92pt and then expressed as ratios.
```

Line 72:

```text
/ How far inside the outer circle the dashed construction circle sits.
```

Line 93:

```text
Show the measured position directly. Animating every telemetry sample
```

Line 94:

```text
keeps the dashboard laying out and redrawing between probe ticks.
```

Line 101:

```text
MARK: Face and bezel
```

Line 103:

```text
/ The construction the dial was struck against, left on the page.
```

Line 105:

```text
/ This used to be a machined instrument: a filled face, a radial shade to
```

Line 106:

```text
/ recess it, a two-stop gradient bezel lighting it from the top-left, and
```

Line 107:

```text
/ an Aqua highlight over the top third. All four were arguing with the
```

Line 108:

```text
/ substrate — a lit plastic dial floating over a drifting field is an
```

Line 109:

```text
/ object photographed onto a page, and the page is the point. What is left
```

Line 110:

```text
/ is what a compass leaves: the outer circle, and the dashed inner circle
```

Line 111:

```text
/ the tick ladder was measured from. Nothing is filled, so the plate — and
```

Line 112:

```text
/ the field through it — shows behind the scale.
```

Line 125:

```text
MARK: Scale
```

Line 134:

```text
/ The redline band, drawn on the track rather than over the value: it is a
```

Line 135:

```text
/ property of the *scale*, so it has to be visible when the needle is
```

Line 136:

```text
/ nowhere near it. That is the whole reason to have one.
```

Line 151:

```text
/ Nine major ticks — one every 30° — with four minors between each pair.
```

Line 152:

```text
/ Drawn in a single `Canvas` rather than as forty rotated `Rectangle`s: this
```

Line 153:

```text
/ view redraws on a 2 s cadence, and forty leaf views per gauge is a layout
```

Line 154:

```text
/ pass nobody sees the benefit of.
```

Line 180:

```text
MARK: Needle
```

Line 182:

```text
/ A tapered needle with a short counterweight past the hub — the shape that
```

Line 183:

```text
/ makes the pivot read as a pivot rather than as a dot the line happens to
```

Line 184:

```text
/ start at.
```

Line 192:

```text
/ The pivot, drawn rather than machined: the plate's own colour with an ink
```

Line 193:

```text
/ ring around it, so the needle reads as pinned *through* the page instead
```

Line 194:

```text
/ of resting on a metal boss.
```

Line 204:

```text
MARK: Legend
```

Line 206:

```text
/ The readout, and nothing else.
```

Line 208:

```text
/ The face used to carry the metric's name across its top, which was wrong
```

Line 209:

```text
/ twice over: the card header two points to the right already says "Memory",
```

Line 210:

```text
/ and at 92pt the word set inside the scale rather than under it — "MEMORY"
```

Line 211:

```text
/ crossed the arc it was supposed to sit inside. A dial in a titled card does
```

Line 212:

```text
/ not need to introduce itself. `caption` survives as the accessibility
```

Line 213:

```text
/ label, which is the one place the name is genuinely not already present.
```

Line 217:

```text
Under the hub, in the dial's dead sector. Monospaced digits for the
```

Line 218:

```text
same reason every live number in this app is: a value that changes
```

Line 219:

```text
every two seconds must not move the glyphs around it.
```

Line 229:

```text
The tone, as a shape, for anyone who cannot rely on the needle's
```

Line 230:

```text
hue. Sits in the lower sector beside the readout rather than on
```

Line 231:

```text
the scale, where it would be mistaken for a tick.
```

Line 243:

```text
MARK: - Shapes
```

Line 245:

```text
/ The dial's arc, as an animatable shape. `fraction` is the animatable data, so
```

Line 246:

```text
/ the value arc sweeps between samples instead of jumping — a `Canvas` capturing
```

Line 247:

```text
/ a `Double` would redraw at the new value in one frame however it was animated.
```

Line 270:

```text
/ The needle, drawn pointing along 0° (three o'clock) and rotated into place.
```

Line 271:

```text
/ Tapered from the hub to a blunt tip: a needle that comes to a point loses its
```

Line 272:

```text
/ last two pixels to antialiasing and reads as shorter than it is.
```

## Sources/FleetConsoleApp/Design/Sketchfield.swift

Line 4:

```text
Shared native surfaces and the FleetConsole mark.
```

Line 20:

```text
Retains the existing surface API; AppKit supplies the appearance colors.
```

Line 35:

```text
/ Honor the system motion setting at every window and popover root.
```

Line 70:

```text
Labels belong in the content hierarchy rather than a tiny border legend.
```

Line 78:

```text
MARK: - The mark
```

Line 80:

```text
/ The FleetConsole mark: one continuous stroke, the pen-down dot it started
```

Line 81:

```text
/ from, and the construction circle it was struck against.
```

Line 83:

```text
/ The outgoing mark was a bordered plate holding the letters "FC" in a
```

Line 84:

```text
/ typewriter face, rotated two degrees to read as pressed. It was a stamp, and
```

Line 85:

```text
/ a stamp is a thing you apply to a page rather than a thing you draw on one.
```

Line 86:

```text
/ This is drawn: an F built from three strokes of a single path, sitting on the
```

Line 87:

```text
/ circle a compass would have laid down first — the construction line left in,
```

Line 88:

```text
/ which is the whole argument of the restyle in one 26pt glyph.
```

Line 91:

```text
/ Whether the construction circle is drawn. The menu bar gets the stroke
```

Line 92:

```text
/ alone: at 14pt in a bar full of system glyphs, the circle is the
```

Line 93:

```text
/ difference between a mark and a smudge.
```

Line 95:

```text
/ The stroke's ink. White on the app badge's dark plate, the sketch accent
```

Line 96:

```text
/ on the paper.
```

Line 122:

```text
The pen-down dot: where the stroke began, left visible.
```

## Sources/FleetConsoleApp/Design/StatusTone.swift

Line 4:

```text
Shared vocabulary for status. Shape carries the meaning as well as colour, so
```

Line 5:

```text
the menu bar and the dashboard stay readable without relying on colour alone.
```

Line 7:

```text
Lives in Design/ rather than in Views/Components.swift, where it started.
```

Line 8:

```text
The design system has always said this is "the only place a status colour is
```

Line 9:

```text
chosen", and the audit exempts Design/ from the no-inline-hues rule on exactly
```

Line 10:

```text
that basis — but the enum was in the view layer, so the exemption did not
```

Line 11:

```text
reach it and the vocabulary's own definition read as three violations.
```

Line 12:

```text
A rule whose one legitimate exception has to be special-cased by filename is
```

Line 13:

```text
a rule with the file in the wrong place.
```

Line 15:

```text
/ The achromatic inks and washes, named once.
```

Line 17:

```text
/ `FleetColor` (popover ramp) and `ConsoleColor` (window ramp) both expose
```

Line 18:

```text
/ these rather than defining their own, and that is deliberate: the two ramps
```

Line 19:

```text
/ differ in **type and metrics** — a 13pt menu row and a dynamic-type window row
```

Line 20:

```text
/ are different reading distances — but "a measured value" and "a surface at
```

Line 21:

```text
/ rest" mean the same thing on both, and giving them two values would be the
```

Line 22:

```text
/ 9/9.5 font-size pair again. The ramp separation is about size, not about
```

Line 23:

```text
/ vocabulary.
```

Line 25:

```text
/ Before these there were seven strengths of `Color.primary.opacity(…)` across
```

Line 26:

```text
/ the view layer — 0.04, 0.06, 0.7, 0.75, 0.8, 0.85, 0.9 — for four ideas.
```

Line 29:

```text
/ A measured value: monospaced digits in a row, a stat tile's numeral, a
```

Line 30:

```text
/ byte count. Data rather than a label, so it sits one step below
```

Line 31:

```text
/ `.primary` without dropping to `.secondary`, which means *supporting
```

Line 32:

```text
/ text* and would put a resident-memory figure at the same weight as the
```

Line 33:

```text
/ word beside it.
```

Line 36:

```text
/ An untinted surface at rest — a chip, a card, a capsule that is not
```

Line 37:

```text
/ carrying a status.
```

Line 40:

```text
/ The same surface under the pointer. Rows never scale or change weight;
```

Line 41:

```text
/ this is the whole hover vocabulary.
```

Line 44:

```text
/ The same surface, selected. Distinct from hover, because a row can be
```

Line 45:

```text
/ both and the two states have to be told apart without colour.
```

Line 48:

```text
/ A filled indicator segment that is not a status — a signal bar that is
```

Line 49:

```text
/ lit, a step that is complete.
```

Line 52:

```text
/ The unlit half of the same indicator. Grey rather than faint-primary, so
```

Line 53:

```text
/ the pair reads as *four bars, two lit* rather than as a gradient.
```

Line 56:

```text
/ A value that is absent, or a control that is unavailable. One step under
```

Line 57:

```text
/ `.secondary`, which is as far as text can go and still be read — the two
```

Line 58:

```text
/ literals this replaced were 0.5 and 0.6, and nothing distinguished them.
```

Line 61:

```text
/ An untinted border on a control — a capsule, a chip, a picker segment.
```

Line 64:

```text
/ The same border where it has to survive a saturated fill underneath it:
```

Line 65:

```text
/ a selection ring on a heatmap tile, where `outline` would vanish.
```

Line 82:

```text
/ The tone at *text* weight — what a word or glyph is drawn in when it sits
```

Line 83:

```text
/ on that tone's own tinted fill (`Tag`, `ConsoleBadge`, `EvidenceChips`).
```

Line 85:

```text
/ `color` is a **fill** colour, and reusing it as small text on a 14% tint of
```

Line 86:

```text
/ itself measures 1.98:1 for `good`, 2.06:1 for `warn` and 2.95:1 for `bad`
```

Line 87:

```text
/ in light mode — every tone under WCAG AA's 4.5:1, on operational labels
```

Line 88:

```text
/ like "Expired", "Leaked" and "Unmanaged" that are meant to be read at a
```

Line 89:

```text
/ glance. The same colours measure 4.17–6.34:1 in dark mode, because a
```

Line 90:

```text
/ saturated system hue against a dark fill is doing a different job than
```

Line 91:

```text
/ against a pale one. So the correction is per-appearance rather than one
```

Line 92:

```text
/ darker green: the hue moves toward the label colour by the smallest
```

Line 93:

```text
/ fraction that clears AA on its own fill, solved per appearance against
```

Line 94:

```text
/ `NSColor.blended` itself (light needed 26–43%, dark 0–8%) and rounded up
```

Line 95:

```text
/ once for all three rather than tuned per tone.
```

Line 97:

```text
/ `neutral` and `unknown` are greys derived from `secondaryLabelColor`, which
```

Line 98:

```text
/ is translucent by definition — their text and their fill darken together,
```

Line 99:

```text
/ so no blend reaches 4.5:1. They resolve to the system's own secondary label
```

Line 100:

```text
/ instead, which is 3.83:1 here: the contrast macOS itself ships for
```

Line 101:

```text
/ secondary text, and above the 3:1 floor for UI components. `unknown`
```

Line 102:

```text
/ previously halved that again to 1.82:1, which is what actually needed
```

Line 103:

```text
/ fixing.
```

Line 118:

```text
MARK: Tints
```

Line 120:

```text
A tone is used at four strengths, and before these existed it was used at
```

Line 121:

```text
nine: 0.07 and 0.08 and 0.10 for the same row wash, 0.12 and 0.13 and 0.14
```

Line 122:

```text
and 0.16 for the same chip fill, across seven files. That is the ~130
```

Line 123:

```text
literal font sizes again, in colour — nobody chose those numbers, they were
```

Line 124:

```text
each typed once next to whatever was already on screen.
```

Line 126:

```text
Four strengths, because there are four jobs. Anything that needs a fifth
```

Line 127:

```text
is either one of these four or a new named token, never a fresh literal.
```

Line 129:

```text
/ A tinted background behind a whole row or banner. The faintest of the
```

Line 130:

```text
/ four: it has to read as *this row is warm* under body text, without the
```

Line 131:

```text
/ text having to fight it.
```

Line 134:

```text
/ The fill under a chip, tag or badge — a small shape whose own bounds
```

Line 135:

```text
/ carry the tint, so it can be stronger than a row wash without shouting.
```

Line 136:

```text
/ This is the 14% the `ink` contrast solution was solved against.
```

Line 139:

```text
/ A tinted border. Strong enough to read as a deliberate edge at one point
```

Line 140:

```text
/ wide, which a wash is not.
```

Line 143:

```text
/ A tinted line — a sparkline, a meter's outline. A stroke is one point of
```

Line 144:

```text
/ coverage against the background, so it needs most of the hue to survive.
```

Line 157:

```text
/ The tone as a *bare* glyph, for anywhere status has to survive without
```

Line 158:

```text
/ colour: an evidence chip, a badge, a pip under Differentiate Without Colour.
```

Line 160:

```text
/ This exists because `symbol` cannot do that job, and the reason is
```

Line 161:

```text
/ measurable rather than aesthetic. Rendered as silhouettes at 8–13pt and
```

Line 162:

```text
/ compared pairwise by intersection-over-union, every *enclosed* badge
```

Line 163:

```text
/ vocabulary bottoms out around 0.85–0.91 on its worst pair — `circle.fill`
```

Line 164:

```text
/ against `xmark.octagon.fill` is 0.87, and the obvious "more native" swap to
```

Line 165:

```text
/ `checkmark.circle.fill` / `questionmark.circle.fill` makes it *worse* (0.91),
```

Line 166:

```text
/ because a filled circle and a filled octagon are the same blob once the
```

Line 167:

```text
/ glyph inside them is two points wide. The enclosure is the problem: it is
```

Line 168:

```text
/ most of the ink and it is common to every tone. Dropping it takes the worst
```

Line 169:

```text
/ pair to **0.24**. So the enclosed `symbol` stays for the standalone dot,
```

Line 170:

```text
/ where colour is doing the work and the ring is what makes it read as a
```

Line 171:

```text
/ deliberate indicator — and `verdict` is what gets used when colour cannot
```

Line 172:

```text
/ be relied on.
```

Line 198:

```text
/ What the state means for you, in one sentence.
```

Line 215:

```text
/ Never says "healthy" unless a health check actually passed.
```

## Sources/FleetConsoleApp/Design/Theme.swift

Line 3:

```text
FleetKit — the app's design tokens.
```

Line 5:

```text
Before this existed the views carried ~130 literal font sizes across twelve
```

Line 6:

```text
distinct values, including pairs that differ by half a point (9/9.5, 10/10.5,
```

Line 7:

```text
12/12.5) for no reason anyone could reconstruct. A type ramp you can name is
```

Line 8:

```text
the difference between a design system and a pile of magic numbers.
```

Line 10:

```text
Sizes follow AppKit's own menu-bar extras (Wi-Fi, Control Center, Now Playing):
```

Line 11:

```text
13pt primary, 11pt secondary, generous leading. The first draft ran 9–12.5pt,
```

Line 12:

```text
which is Xcode-inspector density, not menu density — technically legible and
```

Line 13:

```text
immediately readable as "not a Mac app".
```

Line 15:

```text
/ Popover title.
```

Line 17:

```text
/ Primary text of a standard row — AppKit's menu item size.
```

Line 19:

```text
/ Primary text of a compact (fixed-height) row.
```

Line 21:

```text
/ Body copy and table cells.
```

Line 23:

```text
/ Secondary line under a row title.
```

Line 25:

```text
/ Timestamps, counts, hints.
```

Line 27:

```text
/ Tags, badges, evidence chips.
```

Line 29:

```text
/ The smallest label in the system: stat-tile captions.
```

Line 31:

```text
/ Disclosure chevron, used only by `DisclosureRow`.
```

Line 33:

```text
/ A glyph that annotates a row without becoming part of its text — the
```

Line 34:

```text
/ reply arrow on an answered agent message, and marks like it. The popover
```

Line 35:

```text
/ ramp's counterpart to `ConsoleFont.marker`.
```

Line 37:

```text
/ The plotted legend struck into a plate's top border. The popover ramp's
```

Line 38:

```text
/ counterpart to `ConsoleFont.plateLabel`, one point smaller for the same
```

Line 39:

```text
/ reason every token here is: menu density, not window density.
```

Line 41:

```text
/ Section labels — sentence case, secondary. Apple stopped shipping
```

Line 42:

```text
/ kerned all-caps headers in menus years ago.
```

Line 44:

```text
/ Big numerals in stat tiles.
```

Line 53:

```text
/ Horizontal inset for section content. AppKit menus use 14–16.
```

Line 55:

```text
/ Inset for rows, which sit inside a hover-highlight margin.
```

Line 58:

```text
/ Gap between a row's icon and its text.
```

Line 61:

```text
/ Fixed height for compact rows.
```

Line 67:

```text
/ Utilisation meters. Wide enough that 5% and 15% are distinguishable at a
```

Line 68:

```text
/ glance, narrow enough to sit in a row's accessory slot without pushing the
```

Line 69:

```text
/ subtitle into truncation.
```

Line 72:

```text
/ One column of the per-core grid.
```

Line 76:

```text
/ Menu highlights in AppKit are 5–6pt radius; tiles sit above them. Both
```

Line 77:

```text
/ track the console ramp in `ConsoleMetrics` — the two surfaces are
```

Line 78:

```text
/ different scales, not different shapes, so their corners stay in step.
```

Line 81:

```text
/ Tags and micro capsules-with-corners.
```

Line 83:

```text
/ One column of the per-core grid, and any bar that narrow.
```

Line 85:

```text
/ `EntityIcon`'s tile radius as a fraction of its size. Proportional so a
```

Line 86:

```text
/ 22pt row icon and a 38pt inspector icon are the same shape, and squarer
```

Line 87:

```text
/ than an app icon on purpose: this is a status tile, not an app.
```

Line 89:

```text
/ The identity glyph inside an `EntityIcon` tile, as a fraction of the tile.
```

Line 91:

```text
/ The corner status badge, as a fraction of the tile it is anchored to.
```

Line 92:

```text
/ Large enough to carry a legible verdict glyph, small enough to stay
```

Line 93:

```text
/ inside the tile without an offset — see `EntityIcon`.
```

Line 95:

```text
/ The badge's contrast ring. Drawn with `strokeBorder`, so it insets rather
```

Line 96:

```text
/ than growing the badge past the tile edge.
```

Line 98:

```text
/ Left inset of an expanded row's detail block, aligning it under the text.
```

Line 100:

```text
/ Fixed column for a leading `StatusTone.verdict` glyph. The glyphs have
```

Line 101:

```text
/ different widths — a checkmark is wider than a minus — so stacked probe
```

Line 102:

```text
/ lines need a reserved column or their labels step in and out by a point.
```

Line 105:

```text
/ Natural-height tabs share a ceiling; long lists scroll within the body.
```

Line 107:

```text
/ One `IconButton`'s hit target. Named because three places need to agree
```

Line 108:

```text
/ on it: the button draws it, the action slot below is two of them wide,
```

Line 109:

```text
/ and the `ProgressView` that stands in for a refresh button has to occupy
```

Line 110:

```text
/ exactly the same room or the header twitches while a sweep runs.
```

Line 112:

```text
/ A trailing cluster of two icon buttons, reserved at a constant width
```

Line 113:

```text
/ whether or not both are on screen.
```

Line 115:

```text
/ The popover header holds it because a tab that puts up one button and a
```

Line 116:

```text
/ tab that puts up two would otherwise resize the segmented control you
```

Line 117:

```text
/ switch tabs with. A process row holds it for the same reason one step
```

Line 118:

```text
/ down: its two verbs appear on hover, and without the reservation the
```

Line 119:

```text
/ usage numeral — the column the list exists to be read down — slides
```

Line 120:

```text
/ 46pt left the moment the pointer lands on it, and a long process name
```

Line 121:

```text
/ truncates on hover and untruncates when you move away.
```

Line 123:

```text
/ The scroll clamp on a popover section's body — how tall State B is
```

Line 124:

```text
/ allowed to get before the section scrolls inside itself.
```

Line 126:

```text
/ One number, because the four sections share one popover: the picker
```

Line 127:

```text
/ above them and the footer below them are the same views whichever tab is
```

Line 128:

```text
/ selected, so a section that clamps higher than its neighbour drags the
```

Line 129:

```text
/ popover's bottom edge with it when you switch. It was written four times
```

Line 130:

```text
/ at two values — 540 on Services, Agents and Processes, 560 on
```

Line 131:

```text
/ Connections — which is the 9/9.5pt pair one layer up. Nobody chose 560;
```

Line 132:

```text
/ it was typed beside the section that happened to be longest, and that
```

Line 133:

```text
/ section is already the tallest of the four because it is the only one
```

Line 134:

```text
/ carrying an admin footer.
```

Line 138:

```text
MARK: - Color
```

Line 140:

```text
/ The popover ramp's colour names.
```

Line 142:

```text
/ Thin on purpose. Status colour is `StatusTone` and nothing else; the
```

Line 143:

```text
/ achromatic inks are `SurfaceInk`, shared verbatim with the window ramp
```

Line 144:

```text
/ because the ramp split is about type and metrics rather than about what a
```

Line 145:

```text
/ colour means. What is left is the handful of popover-specific surfaces, named
```

Line 146:

```text
/ here so no view has to write an opacity literal.
```

Line 153:

```text
/ The pill behind a count in a section header — a shape whose job is to
```

Line 154:

```text
/ separate a numeral from the words either side of it, carrying no state.
```

## Sources/FleetConsoleApp/Design/Tokens.swift

Line 4:

```text
Console design tokens — the window-scaled half of FleetKit.
```

Line 6:

```text
`Theme.swift` carries the popover ramp (13pt rows, menu-bar density). The
```

Line 7:

```text
console window is a different surface with a different reading distance, so
```

Line 8:

```text
it gets its own ramp built on the dynamic type styles Apple reserves for
```

Line 9:

```text
window content (`title2`, `headline`, `subheadline`, `caption`). Nothing in
```

Line 10:

```text
the window should reach for a popover token, and vice versa.
```

Line 12:

```text
MARK: - Type
```

Line 15:

```text
/ Module heading at the top of the content column.
```

Line 17:

```text
/ The welcome's one-line pitch. The only display-size text in the app,
```

Line 18:

```text
/ and it exists because a first-run window that types like a settings
```

Line 19:

```text
/ pane is a first-run window that says nothing.
```

Line 21:

```text
/ Card and group headings inside a module.
```

Line 23:

```text
/ Primary row text in the content column.
```

Line 25:

```text
/ Card numerals beside a gauge — the same emphasis as the dial's own
```

Line 26:

```text
/ readout plate, in text form.
```

Line 29:

```text
/ Body copy in a card or a welcome paragraph.
```

Line 31:

```text
/ Secondary row text, evidence, hints.
```

Line 33:

```text
/ Timestamps, units, legend labels.
```

Line 35:

```text
/ Smaller than caption: the sensor metric's unit line.
```

Line 37:

```text
/ Badge numerals and micro labels.
```

Line 39:

```text
/ A glyph that annotates a row without becoming part of its text — the
```

Line 40:

```text
/ supervised-by-the-controller shield, and anything else that sits after a
```

Line 41:

```text
/ title as a mark rather than a word.
```

Line 44:

```text
/ The plotted legend struck into a plate's top border — "03 · I/O".
```

Line 46:

```text
/ The one type token the Sketchfield pass adds, and the only fixed size in
```

Line 47:

```text
/ the console ramp besides `marker`. It is fixed because it is drawn *into
```

Line 48:

```text
/ a border*: the break in the stroke is measured from this text, and a
```

Line 49:

```text
/ label that grew with Dynamic Type would open a gap wider than the plate
```

Line 50:

```text
/ while the border it interrupts stayed put. Everything a plate label says
```

Line 51:

```text
/ is repeated by the card title beside it in a ramped size, so nothing is
```

Line 52:

```text
/ only legible here.
```

Line 54:

```text
/ The single large glyph over an empty panel. A dynamic `.title` rather than
```

Line 55:

```text
/ a fixed 22pt: it lands on the same size at the default text setting and,
```

Line 56:

```text
/ unlike the literal it replaces, grows when the user asks the system for
```

Line 57:

```text
/ larger text — which is the whole point of an empty state being legible.
```

Line 60:

```text
/ SF Mono for the things that *are* numbers: PIDs, ports, bytes, rates,
```

Line 61:

```text
/ addresses, load averages. Anything else in a technical row stays SF Pro.
```

Line 67:

```text
MARK: - Layout
```

Line 69:

```text
Every fixed size below is a rung of `Scale.ladder` — the Fibonacci sequence —
```

Line 70:

```text
and the column widths are `ConsoleLayout`'s golden division of the window.
```

Line 71:

```text
Neither is a new invention: the values that were here were already reaching
```

Line 72:

```text
for both and missing by a point or two (236 against 233, 88 against 89, 20
```

Line 73:

```text
against 21, 12 against 13), which is why snapping them changes almost nothing
```

Line 74:

```text
visually and changes everything about whether the set can be checked.
```

Line 76:

```text
`Tests/FleetCoreTests/ConsoleLayoutTests.swift` asserts the budget these feed.
```

Line 79:

```text
/ Content-column gutter. Windows want more air than menus.
```

Line 82:

```text
/ Common peer footprints round up from their largest content measurement.
```

Line 85:

```text
retained metric; the interpreter panel is gone
```

Line 86:

```text
/ Inset a panel's content from its own edges — the welcome's header and
```

Line 87:

```text
/ footer bars. Smaller than a card's interior, because a panel edge is
```

Line 88:

```text
/ already a boundary and needs less air than content inside it.
```

Line 90:

```text
/ One horizontal managed-work or detected-session line; never a flexible panel.
```

Line 92:

```text
/ Corner ramp, one rung per level of nesting: card, then a row inside it,
```

Line 93:

```text
/ then a control inside that, then a bar, then a heatmap tile. Adjacent
```

Line 94:

```text
/ rungs are a φ ratio apart, which is what makes a highlighted row inside a
```

Line 95:

```text
/ card read as *nested* rather than as a second card — the relationship the
```

Line 96:

```text
/ old 10/7 pair was approximating.
```

Line 98:

```text
/ Tiles stay at the bottom rung because a treemap is read as contiguous
```

Line 99:

```text
/ area, and a visible corner gap breaks the reading.
```

Line 102:

```text
/ Chips and compact bordered buttons inside a card.
```

Line 104:

```text
/ Utilisation and storage bar segments.
```

Line 106:

```text
/ One tile on a heatmap.
```

Line 108:

```text
/ The channel between neighbouring tiles — half of it taken off each side
```

Line 109:

```text
/ of a tile's computed rectangle. Replaces the hairline stroke that could
```

Line 110:

```text
/ not be seen on a saturated fill. One rung: below it the separation is not
```

Line 111:

```text
/ legible at a glance, above it the map starts reading as a grid of gaps
```

Line 112:

```text
/ rather than a partition of an area.
```

Line 114:

```text
/ Sidebar and inspector bounds.
```

Line 115:

```text
/ The toolbar's module picker. One number per segment, times
```

Line 116:

```text
/ `ConsoleModule.allCases.count`, so adding a module widens the picker
```

Line 117:

```text
/ instead of silently pushing the last segment past the slot's edge —
```

Line 118:

```text
/ which is how the sixth module shipped clipped down its middle.
```

Line 123:

```text
/ The process presentation picker occupies the toolbar's centred slot.
```

Line 124:

```text
/ One ladder rung keeps all four full labels legible without claiming the
```

Line 125:

```text
/ remaining width that belongs to Tools, refresh and search.
```

Line 128:

```text
MARK: The two side columns
```

Line 130:

```text
One set of numbers, used on both sides. The fleet mesh and the inspector
```

Line 131:

```text
are the same column pointing in opposite directions — one names what you
```

Line 132:

```text
are looking at, the other describes what you picked — and they had drifted
```

Line 133:

```text
to 236/268/320 against 280/320/420, which is what made the window
```

Line 134:

```text
measurably lopsided: 52pt more inspector than sidebar at rest.
```

Line 136:

```text
The floor is the longest thing either side actually has to hold: a device
```

Line 137:

```text
name beside a latency badge, over a subtitle like "59% CPU · 67% RAM". At
```

Line 138:

```text
224 both lines elided, turning the one always-visible column into a column
```

Line 139:

```text
of abbreviations. 233 clears it, and it is a rung.
```

Line 141:

```text
There is no separate *ideal*: the resting width is the golden section of
```

Line 142:

```text
whatever the split view has to divide, computed per window size by
```

Line 143:

```text
`ConsoleLayout.sideColumn(splitWidth:)`. A fixed ideal is what a ratio
```

Line 144:

```text
replaces.
```

Line 149:

```text
/ Kept as the names the call sites use, both resolving to the same pair, so
```

Line 150:

```text
/ a future edit cannot make one side wider than the other by touching one
```

Line 151:

```text
/ of them. The mirroring is enforced here rather than remembered.
```

Line 157:

```text
/ Inspector header icon.
```

Line 159:

```text
/ The glyph in a table cell or a compact row — an app's own icon where the
```

Line 160:

```text
/ system has one, otherwise an SF Symbol at text weight. A rung, and the
```

Line 161:

```text
/ smallest at which a real application icon is still recognisable rather
```

Line 162:

```text
/ than a coloured smudge.
```

Line 164:

```text
/ Live charts.
```

Line 169:

```text
/ Trace weight, and the inset that keeps it whole. A stroke centred on the
```

Line 170:

```text
/ plot boundary loses half its width to the edge, so the plot area is held
```

Line 171:

```text
/ off the frame by more than half a line — the trace is the content here,
```

Line 172:

```text
/ and a sheared trace reads as a rendering bug.
```

Line 173:

```text
/ Strokes sit below the ladder's floor deliberately: a 1pt line and a 2pt
```

Line 174:

```text
/ line are two weights of one mark, not two steps of a size hierarchy.
```

Line 177:

```text
/ Room held clear on the trailing edge for the two labels that state the y
```

Line 178:

```text
/ window. Without it the plot runs the full width and a trace that reaches
```

Line 179:

```text
/ its own upper bound — which auto-ranging guarantees it does — is drawn
```

Line 180:

```text
/ through the label naming that bound. 55 is the rung that clears the widest
```

Line 181:

```text
/ label these charts produce ("38.2 MB/s").
```

Line 183:

```text
/ Below this a chart has no room for the two labels that state its y
```

Line 184:

```text
/ window, so it keeps its plain domain instead of auto-ranging. A zoomed
```

Line 185:

```text
/ axis nobody can read is worse than a flat one.
```

Line 187:

```text
/ Analog gauges. 89pt is the smallest rung at which a 240° dial carries its
```

Line 188:

```text
/ nine ticks, a needle and a readout and still reads as an instrument
```

Line 189:

```text
/ rather than as a decorative ring: below it the tick pitch falls under a
```

Line 190:

```text
/ point and the minor ticks merge into a grey band. It is also the same
```

Line 191:

```text
/ rung as `chartHeight`, which is what makes a dial and the trace beside it
```

Line 192:

```text
/ the same height without either being told about the other.
```

Line 194:

```text
/ The width a telemetry card needs before another fits beside it.
```

Line 196:

```text
/ **377 was wrong and made the module worse.** Snapping this up from 320
```

Line 197:

```text
/ during the ladder pass cut the Overview from three columns to two at the
```

Line 198:

```text
/ composed width, which is the opposite of the density the grid was added
```

Line 199:

```text
/ for: the cards got wider, the module got taller, and it went back to
```

Line 200:

```text
/ needing a scroll. A rung is only the right number if it is the right
```

Line 201:

```text
/ number.
```

Line 203:

```text
/ At 233 the content column fits three cards (3×233 + 2×13 = 725 inside
```

Line 204:

```text
/ 944) and each lands near 306pt — a 89pt dial and a 200pt trace, which is
```

Line 205:

```text
/ over three points per sample at sixty samples. Four would need 971 and
```

Line 206:

```text
/ does not fit, so this cannot silently become a chart nobody can read.
```

Line 208:

```text
/ Gap between cards in the module grid, in both axes.
```

Line 210:

```text
/ Vertical rhythm between stacked cards in a scrolling module and between
```

Line 211:

```text
/ the welcome's zones. Same Fibonacci rung as `cardGap` — the gap is a
```

Line 212:

```text
/ gap whether it separates horizontally or vertically.
```

Line 214:

```text
/ The width a catalogue row needs before another fits beside it: icon, two
```

Line 215:

```text
/ lines of label, a right-aligned size and its button.
```

Line 217:

```text
/ 233 was tried, on the argument that four columns make the whole catalogue
```

Line 218:

```text
/ readable without scrolling. It does not give four — the module column is
```

Line 219:

```text
/ around 900pt, so it gives three — and the width it takes comes out of the
```

Line 220:

```text
/ name: nine of thirteen entries truncated to "Spotify offline ca…",
```

Line 221:

```text
/ "Hugging Face m…", "Xcode Derived…". A catalogue you cannot read the names
```

Line 222:

```text
/ in is not readable, whatever it costs in scrolling, and the module has the
```

Line 223:

```text
/ vertical room regardless: the bottom half of the window was empty while
```

Line 224:

```text
/ those names were being clipped.
```

Line 226:

```text
/ Heatmaps. A squarified map needs far more room than a trace — under
```

Line 227:

```text
/ ~250pt the fortieth tile stops being clickable. One shared height keeps
```

Line 228:

```text
/ the process and disk maps aligned while preserving readable tiles.
```

Line 230:

```text
/ The colour swatch in a legend chip or a hover readout: identity by
```

Line 231:

```text
/ colour only, with the label beside it.
```

Line 233:

```text
/ The you-are-here marker in the process tree. Smaller than a swatch on
```

Line 234:

```text
/ purpose: it marks a row, it does not name a colour.
```

Line 236:

```text
The two shadow tokens that were here are gone with the shadow itself.
```

Line 237:

```text
Elevation in this app is `PlateSecondPass` — one hairline 3pt down and
```

Line 238:

```text
right — because a blur behind a translucent plate over a blurred field is
```

Line 239:

```text
three soft things stacked, and the plate stops having an edge at all.
```

Line 242:

```text
MARK: - Color
```

Line 245:

```text
/ Hairline borders — the replacement for `Divider()` wherever a surface
```

Line 246:

```text
/ edge, not a content separator, is being drawn. Chosen to survive both
```

Line 247:

```text
/ appearances without ever looking like a ruled line.
```

Line 251:

```text
/ A plate's fill, over the field. `SketchInk.plate` and nothing else — the
```

Line 252:

```text
/ name is kept because forty call sites read it, but the value is no
```

Line 253:

```text
/ longer a system surface colour.
```

Line 255:

```text
/ It used to be `controlBackgroundColor`: white cards on grey in light,
```

Line 256:

```text
/ lifted panels in dark, exactly like System Settings. That is the right
```

Line 257:

```text
/ answer for a settings pane and the wrong one for this app, because it is
```

Line 258:

```text
/ opaque — and an opaque card over a drifting field is a hole cut in the
```

Line 259:

```text
/ page. A plate is glass held over the sketch; you can see the field
```

Line 260:

```text
/ through it, which is what makes it read as *on* the page rather than
```

Line 261:

```text
/ *instead of* it.
```

Line 263:

```text
/ The page. Every window and popover is drawn on this and then has the
```

Line 264:

```text
/ field, the ruling and the tooth laid over it — see `sketchSubstrate`.
```

Line 267:

```text
/ Selected-row fill. The same value `RowBackground` uses in the popover
```

Line 268:

```text
/ ramp, named here so a selected row in the window cannot be a different
```

Line 269:

```text
/ strength of the same idea.
```

Line 272:

```text
The achromatic inks are `SurfaceInk`, shared with the popover ramp. The
```

Line 273:

```text
ramps differ in type and metrics, not in what a colour means — see the
```

Line 274:

```text
note on `SurfaceInk` for why giving them separate values would be the
```

Line 275:

```text
9/9.5 font-size pair all over again.
```

Line 285:

```text
/ The dimmed remainder tile on a heatmap — the roll-up of everything too
```

Line 286:

```text
/ small to draw. Not a status and not a surface: it is the category's own
```

Line 287:

```text
/ colour, held back so the tile reads as *the rest* rather than as another
```

Line 288:

```text
/ entry competing with the ones that earned their area.
```

Line 291:

```text
/ The tint for a destructive verb — Stop, Restart, Kill.
```

Line 293:

```text
/ Deliberately *not* `StatusTone.bad.color`, even though today they resolve
```

Line 294:

```text
/ to the same red. `StatusTone` answers "what is true about this service";
```

Line 295:

```text
/ this answers "what will this control do to it". A healthy service still
```

Line 296:

```text
/ gets a red Kill button, so routing the button through the status
```

Line 297:

```text
/ vocabulary would be a category error that happens to look right.
```

Line 300:

```text
MARK: Ink on saturated fills
```

Line 302:

```text
The heatmap tiles are the one surface in the app whose background is a
```

Line 303:

```text
saturated category or tone colour rather than a system material. That
```

Line 304:

```text
breaks the usual rule: `Color.primary` flips with the *appearance*, but a
```

Line 305:

```text
tile fill does not, so a primary-derived line goes black-on-red in light
```

Line 306:

```text
mode and white-on-red in dark mode — one of which always loses. These
```

Line 307:

```text
three are therefore deliberately fixed inks, chosen against the actual
```

Line 308:

```text
`StorageCategory` and `StatusTone` fills rather than against the window.
```

Line 310:

```text
`tileEdge` used to live here — a 0.18 black hairline, described as reading
```

Line 311:

```text
"on the pale fills as well as the saturated ones". It did not: at 0.5pt
```

Line 312:

```text
over a saturated fill it was invisible, which is why two adjacent tiles of
```

Line 313:

```text
similar colour merged into one shape. Tiles are separated by a gutter now
```

Line 314:

```text
(`ConsoleMetrics.mapTileGutter`), which is a layout decision rather than a
```

Line 315:

```text
colour one and therefore cannot fail against a fill.
```

Line 317:

```text
/ Hover ring, drawn as two plies. White reads on every saturated fill;
```

Line 318:

```text
/ the dark ply just inside it is what carries the ring on the two pale
```

Line 319:

```text
/ greys, where white alone would vanish. One of the two always has
```

Line 320:

```text
/ contrast, in either appearance, on every fill the maps can produce.
```

Line 325:

```text
/ The two throughput series, and the one place their colour and label live.
```

Line 327:

```text
/ These were previously four literals in two files — `Color.teal` / `Color.orange`
```

Line 328:

```text
/ on the `LineMark`s in `TelemetryCharts`, and `.teal` / `.orange` again on the
```

Line 329:

```text
/ `LegendDot`s in `OverviewModule`. A legend is a claim about what a trace means,
```

Line 330:

```text
/ so a legend that can drift from its trace by one careless edit is the exact
```

Line 331:

```text
/ failure this toolbox exists to prevent. Naming the series makes the chart and
```

Line 332:

```text
/ its key the same fact.
```

Line 347:

```text
/ The APFS storage vocabulary. One colour per category, in the order the
```

Line 348:

```text
/ segmented bar draws them, matched to what About This Mac → Storage uses so
```

Line 349:

```text
/ the bar reads as a Mac native rather than as a dashboard widget.
```

Line 391:

```text
/ In-tile label colour on this category's fill. The fills are saturated
```

Line 392:

```text
/ system colours; one global label colour fails contrast on at least two
```

Line 393:

```text
/ of them in each appearance, so the choice is per category and static.
```

Line 402:

```text
MARK: - Motion
```

Line 405:

```text
/ Live telemetry easing: fast enough to feel alive, slow enough that a
```

Line 406:

```text
/ 2 s sample cadence does not strobe.
```

Line 408:

```text
/ Selection and disclosure motion in the window.
```

Line 410:

```text
/ Storage bar segment growth after a scan completes.
```

Line 413:

```text
/ A side column opening or closing.
```

Line 415:

```text
/ Both sides take this one value, which is the whole of what makes the
```

Line 416:

```text
/ butterfly read as a butterfly: two panels on the same easing look like
```

Line 417:

```text
/ one gesture, and two panels a hundred milliseconds apart look like a bug.
```

Line 418:

```text
/ Critically damped — a column that overshoots its width and settles back
```

Line 419:

```text
/ reads as the layout being unsure, and this one is carrying a table.
```

Line 422:

```text
/ A treemap relaying out: tiles moving to new rectangles as the data
```

Line 423:

```text
/ changes or the panel is resized.
```

Line 425:

```text
/ Slower than `selection` and slower than a column, deliberately. A
```

Line 426:

```text
/ squarified layout can reorder tiles wholesale when one process grows, and
```

Line 427:

```text
/ at 0.15s that is a flicker rather than a movement you can follow — the
```

Line 428:

```text
/ point of animating it at all is that you can see *this tile became that
```

Line 429:

```text
/ tile* instead of the map simply being different.
```

Line 433:

```text
/ One-off, non-repeating motion. The welcome's entrance and its gauge sweep
```

Line 434:

```text
/ are the two places the app moves *at* you rather than with you, and they
```

Line 435:

```text
/ are named here so a third one-off cannot quietly invent its own timing.
```

Line 437:

```text
/ The welcome gauge's 0 → 78% → 12% spin-up. 3.2 s is long enough to
```

Line 438:

```text
/ read as a demonstration and short enough that the Skip button is never
```

Line 439:

```text
/ impatient.
```

Line 441:

```text
/ The welcome window's entrance as a whole — the panel fading in while
```

Line 442:

```text
/ the gauge sweeps. Slightly quicker than the sweep so the stage is
```

Line 443:

```text
/ present before the demonstration is over.
```

## Sources/FleetConsoleApp/Design/ViewModifiers.swift

Line 4:

```text
Window chrome primitives: vibrancy, hairlines, elevation, hover.
```

Line 6:

```text
These exist for the same reason `FleetRow` exists: the first version of the
```

Line 7:

```text
window reimplemented each effect inline, and inline effects drift. A surface
```

Line 8:

```text
asks for a named treatment; it never mixes its own shadows and borders.
```

Line 10:

```text
MARK: - Vibrancy
```

Line 12:

```text
/ AppKit-backed material fill. SwiftUI's `Material` does not expose
```

Line 13:

```text
/ `NSVisualEffectView`'s blending state in every context, so the pre-Liquid
```

Line 14:

```text
/ Glass scene fallback goes through the real thing.
```

Line 35:

```text
MARK: - Window scene
```

Line 37:

```text
/ One continuous, opaque glass field for the console window.
```

Line 39:

```text
/ Liquid Glass is the scene's substrate, rather than a stack of glass cards:
```

Line 40:

```text
/ the sidebar, module, inspector and tool chrome all share this one field. A
```

Line 41:

```text
/ fully opaque AppKit window colour remains behind the effect, so wallpaper
```

Line 42:

```text
/ and windows below FleetConsole never reduce telemetry contrast.
```

Line 58:

```text
The scene is intentionally opaque: glass supplies the native
```

Line 59:

```text
light response, while this veil guarantees a stable field in
```

Line 60:

```text
screen capture, inactive windows and high-contrast desktops.
```

Line 96:

```text
MARK: - Hairlines
```

Line 98:

```text
/ A one-pixel surface edge, not a content separator. `Divider()` draws a
```

Line 99:

```text
/ semantic separator with its own insets and appearance-dependent weight; a
```

Line 100:

```text
/ hairline draws the boundary of a surface and nothing else.
```

Line 114:

```text
/ Draws a hairline along one edge of the view.
```

Line 122:

```text
MARK: - Elevation
```

Line 124:

```text
/ The one elevated surface in the console: a plate over the field.
```

Line 126:

```text
/ Kept as `elevatedCard` because that is the name every module calls, but the
```

Line 127:

```text
/ treatment underneath it is `Sketchfield`'s: a translucent fill, one hairline
```

Line 128:

```text
/ border, and a second pass 3pt down and right in place of the drop shadow.
```

Line 129:

```text
/ Fill, border and second pass are a single treatment — a plate with an edge
```

Line 130:

```text
/ but no second pass is a different component that does not exist here.
```

Line 132:

```text
/ `label` is the plotted legend struck into the top border. It is optional and
```

Line 133:

```text
/ almost always given: a module's instruments are the plates the module is
```

Line 134:

```text
/ made of, and they number themselves. Nested plates — a chip inside a card —
```

Line 135:

```text
/ pass nothing.
```

Line 143:

```text
MARK: - Hover
```

Line 145:

```text
/ Uniform hover treatment for selectable surfaces in the content column:
```

Line 146:

```text
/ a 6% fill, no scale, no colour shift on the content itself. macOS rows do
```

Line 147:

```text
/ not grow or change weight on hover; they quietly acknowledge the pointer.
```

Line 170:

```text
MARK: - Status pip
```

Line 172:

```text
/ The live connection/health dot. A static ring marks live states without
```

Line 173:

```text
/ forcing an otherwise idle monitor to redraw continuously. Shape carries
```

Line 174:

```text
/ meaning alongside colour (HIG: never encode state in colour alone).
```

Line 190:

```text
A lone pip has no text beside it, so with Differentiate Without
```

Line 191:

```text
Colour on, a filled circle conveys nothing at all. The bare
```

Line 192:

```text
verdict glyph is what separates here — enclosed status symbols
```

Line 193:

```text
measure ~0.87 silhouette IoU against each other at this size,
```

Line 194:

```text
bare ones 0.24. It draws at 1.6x the dot inside the halo's
```

Line 195:

```text
existing 2.1x frame, so nothing reflows and nothing clips.
```

Line 200:

```text
The dot keeps `color`, not `ink`, and that is deliberate: a
```

Line 201:

```text
saturated indicator dot is the platform's own convention
```

Line 202:

```text
(Control Center, Wi-Fi, recording indicators), and this one
```

Line 203:

```text
carries its own contrast ring rather than relying on the hue
```

Line 204:

```text
to separate it from the surface. Every *glyph* in the system
```

Line 205:

```text
takes ink; this is the one fill that stays a fill.
```

Line 218:

```text
MARK: - Badge
```

Line 220:

```text
/ Small rounded count/latency badge used in the fleet sidebar and section
```

Line 221:

```text
/ headers. Mono digits by default — badges here carry numbers, not words.
```

Line 251:

```text
MARK: - Live resize
```

Line 253:

```text
/ Whether a window-edge drag is in progress, as reported by AppKit.
```

Line 255:

```text
/ Read by anything that animates a dimension derived from the window's width,
```

Line 256:

```text
/ so that a drag moves the layout directly and a *discrete* change — a column
```

Line 257:

```text
/ toggled, a map reordering because a process grew — still animates.
```

Line 259:

```text
/ An environment value rather than a parameter because the views that need it
```

Line 260:

```text
/ are not neighbours: the root's two side columns and every tile inside a
```

Line 261:

```text
/ treemap four levels down. Threading a Bool through four initialisers to
```

Line 262:

```text
/ reach `HeatmapView.tile` would put a window-management detail in the
```

Line 263:

```text
/ signature of every view in between.
```

## Sources/FleetConsoleApp/Design/WorkspaceHeading.swift

Line 3:

```text
/ Page identity is distinct from card headings and supporting observations.
```

Line 4:

```text
/ Keep the system type ramp and allow the explanation to wrap at narrow widths.
```

## Sources/FleetConsoleApp/FixAgent.swift

Line 5:

```text
The designated fixer: one agent outside the app that FleetConsole hands its
```

Line 6:

```text
problems to.
```

Line 8:

```text
The app observes and the controller supervises; neither edits your code or
```

Line 9:

```text
your configuration. When something needs a fix, the app extracts what it knows
```

Line 10:

```text
— the problem, the service's record, its recent events, where its logs are —
```

Line 11:

```text
into a report file, and starts the agent you designated on that report in the
```

Line 12:

```text
dashboard's own terminal, in the service's working directory. You watch it,
```

Line 13:

```text
answer it, stop it. External fixers act through `fleetctl` and report through
```

Line 14:

```text
its mailbox. The bundled fleet-agent reads the complete saved request and returns
```

Line 15:

```text
a read-only proposal for the operator to review.
```

Line 17:

```text
/ The agents FleetConsole knows how to start on a report.
```

Line 33:

```text
/ The executable name and the agent's mailbox ID.
```

Line 36:

```text
/ The command line typed into the terminal. The bundled agent produces a
```

Line 37:

```text
/ read-only proposal; external agents retain their interactive workflow.
```

Line 49:

```text
/ Bundled fleet-agent has the app's proposal policy. An older copy on
```

Line 50:

```text
/ PATH must not replace it; external fixers keep their existing resolution.
```

Line 66:

```text
/ Which fixer is designated, and which are installed. One per Mac.
```

Line 79:

```text
/ The installed fixers, in `FixAgentKind` order.
```

Line 99:

```text
/ External fixers can be selected by availability. Fleet Agent always
```

Line 100:

```text
/ requires an explicit designation, and an explicit None stays disabled.
```

Line 114:

```text
/ What the fixer is handed: the problems, and everything the app knows about
```

Line 115:

```text
/ the services they concern, as one Markdown file.
```

Line 176:

```text
/ Values cannot inject new Markdown sections or terminal/directional controls.
```

Line 189:

```text
/ Writes the report where the fixer can read it and returns its location.
```

Line 196:

```text
/ Choose the location before writing so the complete first turn can be
```

Line 197:

```text
/ validated before any report is saved or command is dispatched.
```

Line 202:

```text
The shell can read after a second handoff is queued. Each request
```

Line 203:

```text
must retain its own contents even when both arrive in the same second.
```

Line 210:

```text
A unique owner-only file from its first byte; do not follow a symlink or
```

Line 211:

```text
overwrite another queued request. Dispatch happens only after the write closes.
```

Line 225:

```text
/ The first turn: read the report, fix through the controller, report back.
```

Line 239:

```text
/ fleet-agent has read-only observation tools and cannot open a report
```

Line 240:

```text
/ file. Give it the findings directly and ask only for a proposal.
```

Line 254:

```text
/ Hands `items` to the designated fixer: writes the report, then opens the
```

Line 255:

```text
/ dashboard's terminal in the service's directory and starts the agent.
```

Line 256:

```text
/ Returns a sentence to show when it could not.
```

Line 282:

```text
Reject the complete request before writing or dispatching;
```

Line 283:

```text
external fixers retain their report-file workflow.
```

Line 288:

```text
Keep the exact proposal prompt in the saved report instead of
```

Line 289:

```text
echoing all findings and instructions into the shell command.
```

Line 316:

```text
/ POSIX single-quoting: safe to type into any login shell.
```

## Sources/FleetConsoleApp/Investigation.swift

Line 4:

```text
/ Immutable observation captured by the rendered surface, never a shell fragment.
```

Line 19:

```text
Omit argv, paths, environment, usernames, addresses and log bodies.
```

Line 128:

```text
/ Account presence is a local prerequisite. The gateway alone authorizes analysis.
```

Line 159:

```text
/ Right-click, double-click, VoiceOver action and focused Return/Space share one path.
```

Line 185:

```text
/ The same server-enforced completion contract used by Ouros Agent. No tools or
```

Line 186:

```text
/ shell execution are advertised: this turn analyzes the supplied snapshot only.
```

Line 188:

```text
/ Match the existing Ouros Agent refusal contract: unknown 400/422, 429,
```

Line 189:

```text
/ upstream errors and timeouts remain uncertain and must not be replayed.
```

## Sources/FleetConsoleApp/LiveVerification.swift

Line 7:

```text
/ Runs the actual window, probes and navigation with no fixture injection,
```

Line 8:

```text
/ helper registration, notification prompts or foreground activation.
```

## Sources/FleetConsoleApp/LiveVerificationArguments.swift

Line 1:

```text
/ Separates observational verifier options from its optional duration.
```

Line 2:

```text
/ Kept independent of AppKit so tests exercise the shipping argument parser.
```

## Sources/FleetConsoleApp/MenuBarItem.swift

Line 5:

```text
/ One menu-bar item: live meters, popover, dropdown menu.
```

Line 7:

```text
/ FleetConsole puts up exactly one of these. The class stayed generic through
```

Line 8:

```text
/ the collapse from five items to two to one — it knows how to render a summary
```

Line 9:

```text
/ and show a popover, and nothing about a surface's *content* lives here — but
```

Line 10:

```text
/ the count in this comment did not, and it went on claiming a second Network
```

Line 11:

```text
/ item for as long as `docs/DESIGN-SYSTEM.md` did.
```

Line 15:

```text
/ The live readings, drawn as fixed-width meters so a value changing
```

Line 16:

```text
/ never shifts its neighbours along the menu bar.
```

Line 18:

```text
/ Attention after the meters — "!2" or "Offline" — and empty when
```

Line 19:

```text
/ there is nothing to act on.
```

Line 21:

```text
/ Colours the alert. Nil while there is none.
```

Line 40:

```text
macOS remembers a named item's position, so ⌘-dragging the three
```

Line 41:

```text
together survives relaunch instead of scattering again.
```

Line 51:

```text
`sizingOptions` is what makes the hosting controller keep
```

Line 52:

```text
`preferredContentSize` in step with SwiftUI's ideal size. Without it
```

Line 53:

```text
the controller reports nothing until after its first layout, so
```

Line 54:

```text
`NSPopover` positions itself against a size it does not have yet — and
```

Line 55:

```text
the repositioning it would otherwise do to keep a popover on screen
```

Line 56:

```text
never happens. On a status item near the right edge of the display,
```

Line 57:

```text
the 380pt content then ran off the screen with its trailing column
```

Line 58:

```text
cut off.
```

Line 72:

```text
/ Re-renders only when the summary actually changed, so the 1 Hz clock that
```

Line 73:

```text
/ drives lease countdowns never touches the menu bar.
```

Line 82:

```text
/ Puts a summary on a button. The status item and the surface sheet's
```

Line 83:

```text
/ menu-bar capture both draw through here, so the sheet shows the item the
```

Line 84:

```text
/ menu bar shows.
```

Line 87:

```text
Colour only when something is wrong; a permanently coloured item is
```

Line 88:

```text
one more thing you learn to stop seeing.
```

Line 120:

```text
/ Opens the popover as a left-click would, including the `onWillOpen`
```

Line 121:

```text
/ refresh. Used by the dropdown's Network item, which is a request to see a
```

Line 122:

```text
/ popover section rather than to open the console window.
```

Line 135:

```text
MARK: - Meters
```

Line 137:

```text
/ One reading in the menu bar: a short label set over its value.
```

Line 143:

```text
/ CPU, RAM and disk as three stacked label-over-value meters.
```

Line 145:

```text
/ Drawn as one template image, so the readings follow the menu bar through
```

Line 146:

```text
/ light, dark and tinted variants exactly as an SF Symbol does. Every column is
```

Line 147:

```text
/ as wide as its widest possible value ("100%"), so the item keeps one width
```

Line 148:

```text
/ and each number keeps one position however the readings move.
```

Line 151:

```text
/ Fits the 22pt menu bar and the 24pt notched one with the same baseline.
```

Line 158:

```text
Template images keep alpha and drop colour: this is the secondary ink.
```

Line 176:

```text
Drawn through the handler rather than `lockFocus()`, so AppKit
```

Line 177:

```text
re-rasterizes per backing scale instead of keeping the first one.
```

## Sources/FleetConsoleApp/NetworkActions.swift

Line 5:

```text
The verbs on the network surface.
```

Line 7:

```text
Everything here is read-only or clipboard-only. FleetConsole does not
```

Line 8:

```text
reconfigure a network, the same way it does not signal a process it did not
```

Line 9:

```text
start — `ping` and `traceroute` observe a path, they do not change one.
```

Line 11:

```text
Both diagnostics run off the main actor with a hard timeout, because a
```

Line 12:

```text
traceroute to an unreachable gateway takes as long as its own patience and a
```

Line 13:

```text
menu that hangs while it waits is not a menu.
```

Line 18:

```text
/ The most recent diagnostic, so the row can show a result in place instead
```

Line 19:

```text
/ of opening a window or a modal for four lines of text.
```

Line 33:

```text
MARK: - Clipboard
```

Line 35:

```text
/ One place, so "Copy" means the same thing on every row and the
```

Line 36:

```text
/ confirmation feedback cannot drift between them.
```

Line 47:

```text
MARK: - Diagnostics
```

Line 49:

```text
/ Four probes, two-second deadline each, hard-capped by `Shell.run`. Enough
```

Line 50:

```text
/ to tell "the gateway answers" from "it does not"; not a latency study.
```

Line 56:

```text
/ `-n` skips reverse DNS on every hop, which is most of what makes an
```

Line 57:

```text
/ interactive traceroute feel stuck. `-w 1 -q 1 -m 12` keeps the worst case
```

Line 58:

```text
/ bounded: twelve hops, one probe each, one second of patience.
```

Line 67:

```text
/ Seeds an outcome so the surface sheet can capture the diagnostic panel.
```

Line 68:

```text
/ Compiled only into the renderer, never into the signed bundle.
```

Line 91:

```text
MARK: - Support bundle
```

Line 93:

```text
/ A copyable snapshot of the network picture, sanitised.
```

Line 95:

```text
/ The bundle is a serialisation of the model the screen already renders — the
```

Line 96:

```text
/ probe structs are `Codable` precisely so this is an encoding rather than a
```

Line 97:

```text
/ second implementation that can drift from what you were looking at.
```

Line 99:

```text
/ **What is masked and why.** A support bundle is a thing you paste into a chat
```

Line 100:

```text
/ with someone you are asking for help, so the threat it has to survive is
```

Line 101:

```text
/ ordinary carelessness rather than an attacker. Two rules:
```

Line 103:

```text
/   * **Addresses.** Private addresses (RFC 1918, link-local, CGNAT/Tailscale)
```

Line 104:

```text
/     are kept, because they describe your topology and are the entire reason
```

Line 105:

```text
/     to send the thing. Anything else is a public address that identifies where
```

Line 106:

```text
/     you are, and is replaced with its family — `‹public IPv4›`.
```

Line 107:

```text
/   * **Names and secrets.** The Wi-Fi SSID is a location fingerprint and is
```

Line 108:

```text
/     masked. Nothing in this bundle reads a key, a token or a password from
```

Line 109:

```text
/     anywhere: there is no field for one, and the assembler below cannot reach
```

Line 110:

```text
/     the config file, the keychain or the registry. The one credential-shaped
```

Line 111:

```text
/     thing the app knows about — a VLAN source's controller token — is not
```

Line 112:

```text
/     part of `NetworkSegment` for exactly this reason.
```

Line 142:

```text
/ Builds the payload from live model values and returns it as pretty JSON.
```

Line 156:

```text
Associated-or-not is the diagnostic fact; *which*
```

Line 157:

```text
network is a location fingerprint.
```

Line 187:

```text
Resolvers are the exception worth keeping legible: "which DNS am I
```

Line 188:

```text
using" is usually the question, and a public resolver like 1.1.1.1 is
```

Line 189:

```text
not your address — it is a well-known service. Masking it would remove
```

Line 190:

```text
the answer and protect nothing.
```

Line 195:

```text
A MAC is a stable hardware identifier and never diagnostic here.
```

## Sources/FleetConsoleApp/Notifier.swift

Line 5:

```text
/ macOS notifications for agent messages.
```

Line 7:

```text
/ Deliberately narrow: only a question awaiting an answer or a reported problem
```

Line 8:

```text
/ interrupts you. Status messages appear in the popover and nowhere else — an
```

Line 9:

```text
/ agent that chats every thirty seconds must not be able to turn itself into a
```

Line 10:

```text
/ notification storm.
```

Line 12:

```text
/ Main-actor isolated: `authorized` is written by the authorization callback on
```

Line 13:

```text
/ whatever queue UserNotifications chose, and read by `post(_:)` on the main
```

Line 14:

```text
/ actor. Both call sites are already main-actor, so the write hops instead of
```

Line 15:

```text
/ racing the read.
```

## Sources/FleetConsoleApp/OurosBilling.swift

Line 17:

```text
/ The hosted fixer. Its price comes from the catalog, never from here.
```

Line 20:

```text
/ "$10/month", from the catalog's own figures.
```

Line 45:

```text
Release app identity is verified without querying an account item.
```

Line 46:

```text
An ad-hoc/development app cannot provoke a Keychain permission dialog.
```

Line 95:

```text
/ `useKeychain: false` isolates a billing instance from production storage
```

Line 96:

```text
/ entirely: credentials live in memory only, so captures and tests can connect
```

Line 97:

```text
/ without touching the Keychain or its permission dialogs.
```

Line 124:

```text
/ The catalog as last loaded; empty until a load succeeds.
```

Line 239:

```text
/ The existing Ouros Agent gateway rechecks account entitlement and reserves
```

Line 240:

```text
/ usage on POST. Fleet's multi-device membership does not authorize inference.
```

Line 275:

```text
Closing/stopping during catalog lookup must not dispatch paid work.
```

Line 278:

```text
Persist before dispatch. Never retry an ambiguous paid operation, even after relaunch.
```

Line 306:

```text
Failure after dispatch may already have incurred usage. No blind replay.
```

Line 311:

```text
/ Explicit acknowledgement only; never resends the old request.
```

Line 322:

```text
/ Automatic refresh follows an account connection; unsigned-in requests
```

Line 323:

```text
/ require an explicit billing action such as Refresh.
```

Line 404:

```text
/ The cloud agent, when the catalog offers it to this account.
```

Line 412:

```text
/ Checkout for one catalog offer. Each offer keeps its own idempotency key,
```

Line 413:

```text
/ so starting a second purchase can never resume the first one's session.
```

Line 422:

```text
The in-memory key belongs to the multi-device checkout alone; any
```

Line 423:

```text
other offer reads and writes only its own stored key.
```

## Sources/FleetConsoleApp/Probes/AgentCostProbe.swift

Line 4:

```text
/ Today's agent spend, sampled off the main thread.
```

Line 6:

```text
/ This lives in the app rather than in `fleetd`, and that is a boundary
```

Line 7:

```text
/ decision rather than a convenience. The controller's job is to own processes;
```

Line 8:

```text
/ reading another tool's transcripts is neither supervision nor something that
```

Line 9:

```text
/ needs to survive the app being closed. Putting it here leaves the daemon, the
```

Line 10:

```text
/ socket protocol and the process-safety rules exactly as they were — which the
```

Line 11:

```text
/ merge gate for this port requires.
```

Line 13:

```text
/ The scan walks real directories and memory-maps real files, so it never runs
```

Line 14:

```text
/ on the snapshot cadence: `refresh()` is called freely and the probe itself
```

Line 15:

```text
/ decides whether enough time has passed. See `minimumInterval`.
```

Line 22:

```text
/ A day's transcripts do not change fast enough to be worth re-reading on
```

Line 23:

```text
/ every popover open, and a working directory of Claude sessions is large
```

Line 24:

```text
/ enough that doing so is visible.
```

Line 30:

```text
/ Samples if the last scan has aged out. `force` is for the one case that
```

Line 31:

```text
/ is not a cadence — an operator pressing refresh and expecting the number
```

Line 32:

```text
/ under their cursor to be the one on disk right now.
```

Line 48:

```text
/ What one agent cost, or `nil` when it is unknown — which is not the same
```

Line 49:

```text
/ as zero, and is why this returns the whole snapshot rather than a Double.
```

## Sources/FleetConsoleApp/Probes/AppIcon.swift

Line 4:

```text
Real application icons, where the system can supply one.
```

Line 6:

```text
A row that says "Claude" over a generic `sparkle` is doing recognition work the
```

Line 7:

```text
operating system will do better: you know an app by its icon before you have
```

Line 8:

```text
read its name. But an icon is a *claim about identity*, and this app does not
```

Line 9:

```text
make claims without evidence — so there are exactly two sources here, both of
```

Line 10:

```text
them things macOS already knows, and no third.
```

Line 12:

```text
1. **The process is the app.** `NSRunningApplication(processIdentifier:)`
```

Line 13:

```text
answers for anything registered with the window server, and its `icon` is
```

Line 14:

```text
that app's own artwork. This covers Claude.app, ChatGPT.app,
```

Line 15:

```text
Music.app and every other bundled process in the maps — most of the large
```

Line 16:

```text
tiles on the process map, as it happens.
```

Line 18:

```text
2. **A declared mapping to an installed app.** A CLI agent is not a GUI
```

Line 19:

```text
process: `claude` running in a terminal is a Node binary under
```

Line 20:

```text
`~/Library/Application Support/`, it is not registered with the window
```

Line 21:

```text
server, and `NSRunningApplication` returns nil for it. There is no logo
```

Line 22:

```text
on disk to read. What there *may* be is a desktop app for the same tool
```

Line 23:

```text
already installed on this machine, and LaunchServices can find it by
```

Line 24:

```text
bundle identifier — so `Claude Code` borrows `Claude.app`'s icon, and
```

Line 25:

```text
borrows nothing at all when Claude.app is not installed.
```

Line 27:

```text
What is deliberately absent is a third source: guessing. The `claude` binary
```

Line 28:

```text
lives inside `~/Library/Application Support/Claude/claude-code/…`, so the app
```

Line 29:

```text
bundle could be *inferred* from the executable path — and that inference is
```

Line 30:

```text
right on this machine and wrong on the next one, which is the same argument
```

Line 31:

```text
`networkSegments` makes about reading a VLAN tag off the third octet of a
```

Line 32:

```text
subnet. The mapping below is a declaration. It is right because someone wrote
```

Line 33:

```text
it down, and where nobody has written one down the row keeps its SF Symbol.
```

Line 35:

```text
No artwork is vendored. Every pixel here belongs to an application already
```

Line 36:

```text
installed on this machine, which is also why the icons stay correct when those
```

Line 37:

```text
applications are updated and why this file adds nothing to the bundle.
```

Line 42:

```text
MARK: - The declaration
```

Line 44:

```text
Tool name — as `SessionScanner.tools` spells it — to the bundle identifier
```

Line 45:

```text
of the desktop app that shares its identity. Absent from this table, or
```

Line 46:

```text
present and not installed, both mean "no icon", which is a legitimate and
```

Line 47:

```text
common answer: `aider` and `opencode` have no desktop app to borrow from,
```

Line 48:

```text
and an SF Symbol is the honest and native rendering for them.
```

Line 50:

```text
Identifiers are the real ones, read off the running applications rather
```

Line 51:

```text
than assumed from the vendor's name — `ChatGPT.app` reports
```

Line 52:

```text
`com.openai.codex`, which is not what anyone would have guessed.
```

Line 53:

```text
/ Tool name → the desktop app whose artwork stands for it.
```

Line 55:

```text
/ Keyed on the **tool name as the sessions carry it**, lowercased, and
```

Line 56:

```text
/ looked up through `bundleIdentifier(forTool:)` rather than by subscript.
```

Line 57:

```text
/ It used to be keyed on display names — `"Claude Code"`, `"Codex"`,
```

Line 58:

```text
/ `"Gemini CLI"` — and every caller subscripted it with `session.tool`,
```

Line 59:

```text
/ which is `codex`, `claude`, and friends. Not one lookup could ever match, so
```

Line 60:

```text
/ every agent everywhere fell through to the generic symbol tile and the
```

Line 61:

```text
/ whole `AppGlyph` path was dead on arrival. Two of the four keys were not
```

Line 62:

```text
/ even the shape of a tool name: nothing is ever called "Gemini CLI" by
```

Line 63:

```text
/ the thing that reports it.
```

Line 71:

```text
/ The declared app for a tool, matched without caring about case.
```

Line 73:

```text
/ A tool name arrives from `ps` and from the controller, and those two do
```

Line 74:

```text
/ not agree about capitalisation. Case-sensitivity here is not a rule
```

Line 75:

```text
/ anyone chose, it is the default behaviour of a dictionary — and it is
```

Line 76:

```text
/ what silently disabled this feature.
```

Line 81:

```text
MARK: - Cache
```

Line 83:

```text
The process table samples every few seconds and the map draws forty tiles,
```

Line 84:

```text
so an uncached lookup would mean hundreds of LaunchServices round trips a
```

Line 85:

```text
minute for artwork that changes when an app is updated and at no other
```

Line 86:

```text
time. Icons are cached by bundle identifier — the thing that is actually
```

Line 87:

```text
stable — and the negative answer is cached too, because "this tool has no
```

Line 88:

```text
desktop app" is the common case and is just as expensive to re-derive.
```

Line 91:

```text
/ pid → bundle identifier, keyed with the process's start signature.
```

Line 93:

```text
/ The signature is not decoration. Pids are recycled, and a cache keyed on
```

Line 94:

```text
/ the number alone would hand a dead app's icon to whatever inherited its
```

Line 95:

```text
/ pid — the same failure the controller refuses to make when it signals a
```

Line 96:

```text
/ process, applied to the far less serious business of drawing a picture.
```

Line 99:

```text
MARK: - Lookup
```

Line 101:

```text
/ The icon for a running process, or nil when the system has none.
```

Line 103:

```text
/ `startSignature` is `ps -o lstart` for the pid, which every row in this
```

Line 104:

```text
/ app already carries for exactly this reason.
```

Line 115:

```text
/ The icon of an installed application, by bundle identifier.
```

Line 125:

```text
/ The icon for a detected agent session.
```

Line 127:

```text
/ The session's own pid first — a tool *could* be a GUI app on some machine
```

Line 128:

```text
/ — and the declared mapping second. Both can miss, and missing is fine.
```

Line 136:

```text
MARK: - View
```

Line 138:

```text
/ An entity's icon: the application's own artwork when macOS has it, and the
```

Line 139:

```text
/ existing `EntityIcon` symbol tile when it does not.
```

Line 141:

```text
/ The two are the same size and sit on the same baseline, so a list mixing
```

Line 142:

```text
/ bundled apps and CLI processes does not go ragged — which is most lists in
```

Line 143:

```text
/ this app.
```

Line 145:

```text
/ **On colour.** The design system says colour is a status vocabulary, and an
```

Line 146:

```text
/ app icon is full-colour by definition. It is not a violation for the same
```

Line 147:

```text
/ reason a VLAN tag is `.neutral`: this is *identity*, which has no good/bad
```

Line 148:

```text
/ axis, and it is drawn in a channel status never uses. The status tone still
```

Line 149:

```text
/ arrives where it always did — the badge, the row's text, the tile's fill — so
```

Line 150:

```text
/ nothing that was legible without colour becomes dependent on it. An icon that
```

Line 151:

```text
/ is missing costs the row nothing, because the symbol tile behind it carries
```

Line 152:

```text
/ the tone exactly as before.
```

Line 154:

```text
/ How the *fallback* draws. A real icon is always itself.
```

Line 156:

```text
/ Both are needed because the app already has both, and swapping one for
```

Line 157:

```text
/ the other would be a visible regression rather than a refinement: rows in
```

Line 158:

```text
/ the popover carry a tinted `EntityIcon` tile, while a table cell carries a
```

Line 159:

```text
/ bare secondary-coloured symbol at text weight. A table that suddenly grew
```

Line 160:

```text
/ forty tinted tiles would be a different table.
```

Line 162:

```text
/ `EntityIcon` — the tinted, rounded tile used in lists and headers.
```

Line 164:

```text
/ A bare SF Symbol at the size given, as table cells and compact rows
```

Line 165:

```text
/ have always drawn it.
```

Line 169:

```text
/ The fallback symbol, used whenever no real icon resolves.
```

Line 175:

```text
/ The running process this glyph stands for, if it is one.
```

Line 178:

```text
/ A tool name from `AppIcon.declaredBundleIdentifiers`, for CLI agents.
```

## Sources/FleetConsoleApp/Probes/ConnectionProbes.swift

Line 4:

```text
The extra connection surfaces. Each one reports what it actually found —
```

Line 5:

```text
including "not configured" and "not installed", which are answers, not gaps.
```

Line 27:

```text
/ Tailscale owns one utun; saying so stops it being read as a second VPN.
```

Line 32:

```text
/ Configured VPN services from `scutil --nc list`, with their state.
```

Line 109:

```text
/ A TCP connect to a well-known host. This is the only probe in FleetConsole
```

Line 110:

```text
/ that leaves the machine by default, it is a bare TCP handshake carrying no
```

Line 111:

```text
/ data, and the target is configurable.
```

Line 128:

```text
Configured services, e.g. "* (Disconnected)   ABC-123 PPP (L2TP) "Work" [...]"
```

Line 134:

```text
The service name is the quoted field.
```

Line 142:

```text
Active tunnel interfaces, with Tailscale's identified so it is not
```

Line 143:

```text
double-counted as "a VPN you did not know about".
```

Line 183:

```text
Fall back to interface names if the friendly names were not printed.
```

Line 207:

```text
/ exo (the distributed inference cluster). Reports what is actually present:
```

Line 208:

```text
/ a binary, running processes, and whether its local endpoint answers. No
```

Line 209:

```text
/ cluster details are claimed that were not observed.
```

## Sources/FleetConsoleApp/Probes/HostProbe.swift

Line 4:

```text
/ Read-only capability probe for the other machines in the fleet.
```

Line 6:

```text
/ This asks a host what it *is*; it never asks it to do anything. The remote
```

Line 7:

```text
/ command is a fixed string compiled into the binary — no part of it comes from
```

Line 8:

```text
/ config, and `Shell.run` passes an argv array rather than a shell string, so
```

Line 9:

```text
/ there is nothing to inject into. `BatchMode=yes` means a host that would prompt
```

Line 10:

```text
/ for a password fails immediately instead of hanging a background queue forever.
```

Line 12:

```text
/ The point of collecting this is `Placement`: "you can move this there" is a
```

Line 13:

```text
/ claim, and this app does not make claims without evidence. Architecture, free
```

Line 14:

```text
/ memory, disk headroom and link quality are the evidence.
```

Line 17:

```text
/ Nil when the path was never measured.
```

Line 28:

```text
/ A relay adds latency *and* jitter. Interactive work is unusable across one
```

Line 29:

```text
/ long before throughput becomes the problem.
```

Line 56:

```text
/ MLX and Metal compute are Apple-Silicon-only. This is the single fact that
```

Line 57:

```text
/ decides most of the interesting placement questions in this fleet.
```

Line 71:

```text
/ Everything the probe needs to know, emitted as key=value so parsing cannot be
```

Line 72:

```text
/ confused by a login banner. Works on both macOS and Linux. File scope so the
```

Line 73:

```text
/ background probe can read it without crossing the main actor.
```

Line 99:

```text
Prefer an ssh_config alias that points at this device, because the
```

Line 100:

```text
alias carries the User. Probing the tailnet name directly logs in as
```

Line 101:

```text
whoever is running this app, which is usually the wrong account.
```

Line 106:

```text
Two different names for the same machine: ssh needs the alias that
```

Line 107:

```text
carries the login, `tailscale ping` needs the tailnet identity and
```

Line 108:

```text
does not know what an ssh_config alias is.
```

Line 125:

```text
/ Maps every `HostName` in `~/.ssh/config` to the first alias that declares it.
```

Line 126:

```text
/ Read-only, and only used to pick a login target the user has already set up.
```

Line 143:

```text
Wildcards are catch-alls, not a way to reach one machine.
```

Line 164:

```text
No point SSHing to ourselves, and it would fail on a machine without
```

Line 165:

```text
Remote Login enabled even though we can read all of this directly.
```

Line 222:

```text
/ `tailscale ping` is the only thing that distinguishes a direct path from a
```

Line 223:

```text
/ relayed one, and that distinction decides whether interactive work can move.
```

Line 246:

```text
The worst sample, not the mean: a path that is sometimes 8 ms and
```

Line 247:

```text
sometimes 125 ms is a 125 ms path for anything interactive.
```

## Sources/FleetConsoleApp/Probes/NetworkMonitor.swift

Line 7:

```text
/ Network probes run in the app, not the daemon: Wi-Fi SSID needs Location
```

Line 8:

```text
/ authorisation, which is granted to a GUI app bundle, not to a launchd agent.
```

Line 9:

```text
/ Everything here is read-only — FleetConsole never reconfigures your network.
```

Line 26:

```text
/ True when we are associated but macOS withholds the SSID pending Location access.
```

Line 35:

```text
/ 0…4 bars from RSSI, or nil when not associated.
```

Line 86:

```text
/ Default route, resolvers and the interface inventory. See `RoutingProbe`.
```

Line 93:

```text
Nonisolated so `deinit` can invalidate it; nothing observes this handle.
```

Line 104:

```text
/ The cadence comes from config, clamped there. A hand-edited `0` would
```

Line 105:

```text
/ otherwise mean "fork `netstat`, `ifconfig` and `scutil` continuously".
```

Line 113:

```text
/ The run loop holds the timer even though the closure is weak, so it has to
```

Line 114:

```text
/ be invalidated here or a per-view instance would strand a live probe cycle.
```

Line 136:

```text
Segments are grafted on here rather than inside the probe: the
```

Line 137:

```text
probe reports what this machine can see, and the registry
```

Line 138:

```text
reports what something else told us. Keeping the join at the
```

Line 139:

```text
boundary is what lets the VLAN source be absent without the
```

Line 140:

```text
probe knowing anything about it.
```

Line 142:

```text
The overlay is named here for the same reason and by the same
```

Line 143:

```text
kind of join: `RoutingProbe` sees a `utun` with a CGNAT
```

Line 144:

```text
address and cannot know whose it is, while `probeTailscale`
```

Line 145:

```text
already reported that exact address as this node's. Matching
```

Line 146:

```text
them turns an opaque `utun4` into `Tailscale`, using two facts
```

Line 147:

```text
the app already had and inventing neither.
```

Line 157:

```text
`checkedAt` moves on every pass, so comparing whole snapshots
```

Line 158:

```text
would report a change every time and rebuild the menu for
```

Line 159:

```text
nothing. The equality that matters is the content.
```

Line 168:

```text
The Wi-Fi probe used to run here on the main actor, and one
```

Line 169:

```text
CoreWiFi XPC reply (`ssid()` under a pending Location
```

Line 170:

```text
authorization) never arrived — freezing the main thread and
```

Line 171:

```text
with it the whole app, quit included. It is a synchronous
```

Line 172:

```text
system call, so it runs on the probe queue like its siblings,
```

Line 173:

```text
where a late reply can only stall the next refresh.
```

Line 204:

```text
MARK: - Interfaces
```

Line 206:

```text
These probes use only local values and synchronous system tools. They are
```

Line 207:

```text
intentionally safe on `probeQueue`; keeping them off the main actor avoids
```

Line 208:

```text
making every network refresh borrow the UI actor.
```

Line 209:

```text
/ Gives the Tailscale tunnel its name.
```

Line 211:

```text
/ A `utun` is anonymous by construction — macOS hands them out to anything
```

Line 212:

```text
/ that asks, and this machine has eight. Matching one against the address
```

Line 213:

```text
/ `tailscale status` reported for this node identifies it exactly, with no
```

Line 214:

```text
/ guessing from the CGNAT range: another WireGuard client on 100.64/10
```

Line 215:

```text
/ would not match, because the comparison is to *our* address.
```

Line 217:

```text
/ It stays `.tunnel` rather than becoming its own kind. What changes is the
```

Line 218:

```text
/ label; a tunnel is still a tunnel, and `hasCarrier` still says link is not
```

Line 219:

```text
/ a question you ask of it.
```

Line 247:

```text
The built-in wired port is the one named exactly "Ethernet"; adapters are
```

Line 248:

```text
"Ethernet Adapter (enN)" and are only used when the built-in is absent.
```

Line 259:

```text
`== "active"`, not `contains("active")` — the other value
```

Line 260:

```text
`ifconfig` prints is *inactive*, which contains it. The bug
```

Line 261:

```text
was invisible here only because the `ipv4 == nil` guard below
```

Line 262:

```text
overrode the wrong answer; it was not invisible in
```

Line 263:

```text
`RoutingProbe`, where it reported link on 22 of 26 interfaces.
```

Line 267:

```text
media: autoselect (1000baseT <full-duplex>)
```

Line 302:

```text
Associated is inferred from the radio, not from the SSID: macOS hides the
```

Line 303:

```text
SSID without Location access, and "no SSID" must not read as "offline".
```

Line 354:

```text
MARK: - System Settings deep links
```

Line 368:

```text
/ Asking for Location is the only way macOS will reveal the SSID to us.
```

Line 375:

```text
The manager exists only to trigger the prompt; holding it past the
```

Line 376:

```text
lookup keeps a location client alive for the life of the app.
```

## Sources/FleetConsoleApp/Probes/Placement.swift

Line 4:

```text
/ Where should this run — answered with reasons, or not answered at all.
```

Line 6:

```text
/ This is the same rule the rest of the app lives by, applied to placement
```

Line 7:

```text
/ instead of health. "You can move this" is a claim. It requires evidence:
```

Line 8:

```text
/ a compatible architecture, a host that has been probed recently enough to
```

Line 9:

```text
/ believe, enough free memory, and a link good enough for how the thing is used.
```

Line 10:

```text
/ Where the evidence is missing the verdict is `unknown`, not `yes`.
```

Line 12:

```text
/ The rules are deliberately blunt and few. A placement advisor that scores
```

Line 13:

```text
/ hosts on a continuous fitness function produces confident-looking numbers no
```

Line 14:

```text
/ one can audit; a short list of hard constraints produces answers you can argue
```

Line 15:

```text
/ with, which is what you actually want before moving a workload.
```

Line 17:

```text
MARK: - What a workload needs
```

Line 20:

```text
/ MLX and Metal compute do not exist off Apple Silicon. Not a preference.
```

Line 22:

```text
/ Has a window. Moving it to a headless box is meaningless.
```

Line 24:

```text
/ Chatty against the working tree — language servers, file watchers, agents
```

Line 25:

```text
/ editing code. Latency and jitter matter far more than throughput.
```

Line 27:

```text
/ Needs a container runtime on the target.
```

Line 29:

```text
/ Runtimes that must exist on the host.
```

Line 31:

```text
/ Rough resident footprint, used to check the target has room.
```

Line 35:

```text
/ Classifies a running process group by name.
```

Line 37:

```text
/ A catalogue rather than a heuristic, for the same reason the reclaim scanner
```

Line 38:

```text
/ is one: guessing from a process name is how you tell someone they can move
```

Line 39:

```text
/ their inference server onto a machine that cannot run it.
```

Line 46:

```text
Apple-Silicon-only compute.
```

Line 51:

```text
Things with a window.
```

Line 57:

```text
Coding agents and editors: they live against your working tree.
```

Line 63:

```text
Headless runtimes that move well.
```

Line 76:

```text
/ A managed service is classified from the argv the controller recorded,
```

Line 77:

```text
/ which is better evidence than a process name.
```

Line 81:

```text
A service the controller supervises is by definition headless — it was
```

Line 82:

```text
launched with an argv and a health check, not a window.
```

Line 88:

```text
MARK: - Verdict
```

Line 114:

```text
/ Why. Always populated — a verdict with no reason is not a verdict.
```

Line 121:

```text
/ Evaluates one workload against one host.
```

Line 123:

```text
/ Order matters: hard architectural blocks are reported before soft ones, so
```

Line 124:

```text
/ the first reason you read is the one that actually decides it.
```

## Sources/FleetConsoleApp/Probes/ProcessInventory.swift

Line 4:

```text
/ The machine's full process table, as rows you can sort, filter and inspect.
```

Line 6:

```text
/ The first sampler collapsed everything into named groups for the treemap —
```

Line 7:

```text
/ the right shape for a market map, the wrong shape for a console. A console
```

Line 8:

```text
/ needs the rows themselves: one row per process, with its parent, its user,
```

Line 9:

```text
/ its listening ports, and enough of the command line to know what it is.
```

Line 11:

```text
/ Everything comes from the same `ps` + `lsof` pair the controller already
```

Line 12:

```text
/ trusts (`ProcessTable.capture`), so the app and the daemon can never
```

Line 13:

```text
/ disagree about what a process is. No root: `lsof` scope is this user's
```

Line 14:

```text
/ listeners, which is the scope FleetConsole claims everywhere else too.
```

Line 16:

```text
/ What `ps -o state` means, in words, with a tone.
```

Line 18:

```text
/ The raw field is one letter plus BSD modifiers (`S+`, `Ss`, `R<`). Only the
```

Line 19:

```text
/ first letter carries the scheduler state; the modifiers say things like
```

Line 20:

```text
/ "session leader" and "foreground process group", which are real but are not
```

Line 21:

```text
/ health, so they are kept on the row and not folded in here.
```

Line 23:

```text
/ The tones are the interesting part. Three of these seven are *neutral* —
```

Line 24:

```text
/ sleeping, idle and running are all completely normal, and colouring "running"
```

Line 25:

```text
/ green would make a machine's process list a wall of green that says nothing.
```

Line 26:

```text
/ Only the two states you would act on get a hue.
```

Line 56:

```text
A stopped process was SIGSTOPped and is not coming back on its own;
```

Line 57:

```text
a zombie is holding a table entry its parent never reaped. Both are
```

Line 58:

```text
things you would do something about. The rest is Tuesday.
```

Line 68:

```text
/ The pid. Stable for the life of the process; the row's identity is the
```

Line 69:

```text
/ process's identity.
```

Line 80:

```text
/ Listening TCP ports bound by this process (this user's processes only —
```

Line 81:

```text
/ `lsof` without root sees no further, and the row says so rather than
```

Line 82:

```text
/ drawing an empty port list for a root daemon).
```

Line 84:

```text
/ `ps -o lstart` — the PID-reuse signature. Carried so an inspector can
```

Line 85:

```text
/ prove it is looking at the same process the list showed a second ago.
```

Line 87:

```text
/ Raw `ps -o state`, modifiers included. Interpreted by `state`.
```

Line 92:

```text
/ What a human would call it: bundle-style display name with the helper
```

Line 93:

```text
/ suffixes left intact at row level (helpers are real processes; only the
```

Line 94:

```text
/ map used to fold them).
```

Line 99:

```text
/ Whether this process belongs to the logged-in user.
```

Line 101:

```text
/ The first of the three gates on **End Process**. It is a comparison
```

Line 102:

```text
/ against the real effective uid rather than a name match, because a
```

Line 103:

```text
/ username can repeat across a uid boundary and the kernel only cares
```

Line 104:

```text
/ about the number.
```

Line 117:

```text
/ At most 120 captures × 48 redacted rows. No argv, environment or user names.
```

Line 121:

```text
/ pid → children, rebuilt with each capture. The inspector's process tree
```

Line 122:

```text
/ reads this rather than re-walking the table.
```

Line 125:

```text
/ Slower than the meter cadence: `ps -Ao` over every process on the
```

Line 126:

```text
/ machine costs far more than reading a Mach counter, and process weights
```

Line 127:

```text
/ do not meaningfully change in two seconds.
```

Line 131:

```text
Nonisolated so `deinit` can invalidate it; nothing observes this handle.
```

Line 150:

```text
/ The run loop holds the timer even though the closure is weak, so it has to
```

Line 151:

```text
/ be invalidated here or a per-view instance would strand a live `ps` tick.
```

Line 185:

```text
/ The heaviest processes, by each of the two weights that actually cost you
```

Line 186:

```text
/ something. Two lists rather than one sorted table, because the process
```

Line 187:

```text
/ eating your battery and the process eating your RAM are usually different
```

Line 188:

```text
/ processes and a single ranking hides whichever one you did not sort by.
```

Line 190:

```text
/ `kernel_task` is dropped from the CPU list on purpose: it is pid 0's
```

Line 191:

```text
/ sibling, it is permanently near the top on a warm Mac, and it is the one
```

Line 192:

```text
/ row on the list you can do nothing about.
```

Line 207:

```text
MARK: - Termination
```

Line 209:

```text
/ Why a process cannot be ended, in the words the UI shows.
```

Line 211:

```text
/ Modelled as a reason rather than a `Bool` because a disabled control that
```

Line 212:

```text
/ does not say why invites exactly the question it is refusing to answer —
```

Line 213:

```text
/ the same argument the Processes module's disabled **Kill Process** item
```

Line 214:

```text
/ already makes.
```

Line 216:

```text
/ The config flag is off. This is the default and it is not a failure.
```

Line 218:

```text
/ The process belongs to another user, or to the system.
```

Line 220:

```text
/ The pid is gone, or is no longer the process the row was drawn from.
```

Line 237:

```text
/ The gates that can be answered from memory. `nil` means the verb is
```

Line 238:

```text
/ offered — not that the signal will be sent.
```

Line 240:

```text
/ **This is called from a view body, so it must not touch the process
```

Line 241:

```text
/ table.** It used to end with `if !stillTheSameProcess(row)`, which shells
```

Line 242:

```text
/ out to `/bin/ps` and blocks in `waitUntilExit`, and `waitUntilExit` spins
```

Line 243:

```text
/ the run loop: the layout pass that called this got re-entered by
```

Line 244:

```text
/ CoreAnimation's commit, SwiftUI's AttributeGraph hit
```

Line 245:

```text
/ `AG::precondition_failure`, and the app aborted. Every render of the
```

Line 246:

```text
/ Processes popover, for every row, the moment the feature was switched on
```

Line 247:

```text
/ — which is why turning `allowProcessTermination` on had never once
```

Line 248:

```text
/ produced a working End Process button. The flag being off by default is
```

Line 249:

```text
/ the only reason this had not been seen.
```

Line 251:

```text
/ The third gate is not lost, it has moved to where it belongs. Whether the
```

Line 252:

```text
/ pid is *still* the process this row was drawn from cannot be answered at
```

Line 253:

```text
/ render time anyway: the answer would be seconds stale by the time anyone
```

Line 254:

```text
/ clicked. It is re-read inside `terminate(_:)`, immediately before the
```

Line 255:

```text
/ signal, which is both correct and what the README already claims happens.
```

Line 262:

```text
/ Re-reads the pid's start signature and compares it to the one the row was
```

Line 263:

```text
/ built with.
```

Line 265:

```text
/ This is the PID-reuse guard the controller has always applied to its own
```

Line 266:

```text
/ services (threat model T2), applied here to a process nobody supervises.
```

Line 267:

```text
/ The sampler runs every few seconds and a row can sit on screen for
```

Line 268:

```text
/ minutes, so "the pid in front of me" and "the pid I am about to signal"
```

Line 269:

```text
/ are genuinely different claims — a pid freed and reallocated in between
```

Line 270:

```text
/ would otherwise take the signal meant for something else.
```

Line 279:

```text
/ SIGTERM, and only SIGTERM.
```

Line 281:

```text
/ There is no escalation to SIGKILL here, deliberately. The controller
```

Line 282:

```text
/ escalates for services it launched, because it knows what it started and
```

Line 283:

```text
/ owns the consequences of stopping it. This verb does not: it asks a
```

Line 284:

```text
/ process you own to exit, and a process that declines is a process you
```

Line 285:

```text
/ should look at rather than one the menu bar should overrule.
```

Line 287:

```text
/ Returns the block that stopped it, or `nil` on a signal sent. The guards
```

Line 288:

```text
/ are re-run *here* rather than trusted from the caller — the alert the user
```

Line 289:

```text
/ confirmed was drawn from a snapshot, and this is the last moment before
```

Line 290:

```text
/ the syscall.
```

Line 294:

```text
The PID-reuse gate, here and only here. It re-reads `lstart` for the
```

Line 295:

```text
pid and compares it to the signature this row was built with, so a pid
```

Line 296:

```text
freed and reallocated between the sample and the click cannot take a
```

Line 297:

```text
signal meant for something else (threat model T2).
```

Line 299:

```text
It used to run in `terminationBlock` as well, which put a synchronous
```

Line 300:

```text
`/bin/ps` inside a SwiftUI view body and crashed the app. This is the
```

Line 301:

```text
right place for it regardless of that: a check performed at render
```

Line 302:

```text
time is already stale by the time anyone acts on it, and this runs in
```

Line 303:

```text
the same call as the `kill`.
```

Line 310:

```text
/ Walks ppid links to launchd. Cycle-safe: a reused or missing parent
```

Line 311:

```text
/ stops the walk rather than looping.
```

Line 325:

```text
MARK: - Collection
```

Line 358:

```text
/ `getpwuid` once per uid per sample run — never per row.
```

## Sources/FleetConsoleApp/Probes/RoutingProbe.swift

Line 4:

```text
Where this machine's packets go, and who it asks for names.
```

Line 6:

```text
The connection surfaces already covered *link* state — is Wi-Fi associated, is
```

Line 7:

```text
the wire up, is Tailscale running. They did not cover the two facts you
```

Line 8:

```text
actually reach for when something is broken: the default gateway and the
```

Line 9:

```text
resolvers. This probe adds those, plus the interface inventory the two of them
```

Line 10:

```text
index into.
```

Line 12:

```text
Read-only, like every other probe here. `netstat`, `ifconfig` and `scutil` are
```

Line 13:

```text
queried; nothing is configured. Everything is `Codable`, because the support
```

Line 14:

```text
bundle is a serialisation of this model rather than a second implementation of
```

Line 15:

```text
it — a diagnostic that can drift from the screen it claims to describe is worth
```

Line 16:

```text
less than no diagnostic.
```

Line 18:

```text
MARK: - Model
```

Line 20:

```text
/ A subnet, kept as its parts rather than as a formatted string, so a caller
```

Line 21:

```text
/ that needs the prefix length does not have to parse the label back apart.
```

Line 28:

```text
/ RFC 1918 / RFC 4193 / link-local. The support-bundle sanitiser keeps
```

Line 29:

```text
/ these and masks everything else: a private address describes your own
```

Line 30:

```text
/ topology, a public one identifies you.
```

Line 37:

```text
172.16.0.0/12 is the one that needs arithmetic rather than a prefix.
```

Line 42:

```text
Tailscale's CGNAT range. Not RFC 1918, but it is overlay-internal and
```

Line 43:

```text
reveals nothing about where you are.
```

Line 51:

```text
/ A VLAN segment, as an administrative object rather than as a local interface.
```

Line 53:

```text
/ Nothing populates this today: the host's own 802.1Q interfaces carry a tag and
```

Line 54:

```text
/ a parent (both real, both read off `ifconfig`), but a *segment* — its name, its
```

Line 55:

```text
/ CIDR, its gateway, what it is for — is knowledge a switch or a controller has
```

Line 56:

```text
/ and this machine does not. That is what `VLANSource` is for. Until one is
```

Line 57:

```text
/ registered the field is `nil` and no segment UI renders.
```

Line 67:

```text
/ One interface, as the app models it.
```

Line 69:

```text
/ The three VLAN fields are the forward-looking part. `vlanTag` and `vlanParent`
```

Line 70:

```text
/ are populated for real from `ifconfig` on any host that has an 802.1Q
```

Line 71:

```text
/ interface configured; `segment` is the seam a `VLANSource` fills. All three
```

Line 72:

```text
/ are optional and every renderer treats `nil` as *absent*, not as *unknown* —
```

Line 73:

```text
/ so a machine with no VLANs shows no VLAN chrome at all.
```

Line 88:

```text
MARK: VLAN-ready
```

Line 96:

```text
/ Identity, not state — the same rule every row icon in the app follows.
```

Line 111:

```text
/ Addresses something else can reach. A `fe80::` is auto-configured on
```

Line 112:

```text
/ essentially every interface macOS brings up and reaches exactly one link,
```

Line 113:

```text
/ so it is not an address in the sense this section means.
```

Line 116:

```text
/ The address a human means when they say "my IP on this interface".
```

Line 119:

```text
/ A `169.254.x.x` address is what macOS assigns itself when DHCP does not
```

Line 120:

```text
/ answer. The interface is up, the cable is in, and it is on a network of
```

Line 121:

```text
/ one — which is a *fault*, not a working link, and rendering it the same
```

Line 122:

```text
/ green as a real lease is the third version of the same mistake this file
```

Line 123:

```text
/ has already made twice (`inactive` matching `active`, and `fe80::`
```

Line 124:

```text
/ counting as an address).
```

Line 129:

```text
/ Whether "link" is a meaningful question for this kind of interface.
```

Line 131:

```text
/ `ifconfig` prints `status:` for hardware ports and omits it for tunnels,
```

Line 132:

```text
/ bridges and loopback — there is no carrier to report. Treating that
```

Line 133:

```text
/ absence as *no link* renders a working Tailscale tunnel amber, which is
```

Line 134:

```text
/ the app claiming a fault where the field simply does not apply.
```

Line 142:

```text
/ The row tone. A carrier interface is judged on its link; everything else
```

Line 143:

```text
/ on whether it carries a routable address, which for a tunnel is the whole
```

Line 144:

```text
/ of what "up" means.
```

Line 146:

```text
A self-assigned address outranks link state: the carrier is fine and
```

Line 147:

```text
the interface still cannot reach anything.
```

Line 156:

```text
/ The status in words, written once so the row subtitle and the expanded
```

Line 157:

```text
/ detail cannot describe the same interface differently.
```

Line 167:

```text
/ Interfaces with no address and no link are the long tail of `ifconfig -a`
```

Line 168:

```text
/ — `gif0`, `stf0`, `awdl0` when idle, a dozen `utun`s macOS keeps spare.
```

Line 169:

```text
/ Listing them is not thoroughness; it is burying the four that matter.
```

Line 171:

```text
/ The bar is a **routable** address, a VLAN tag, or a live link on a port
```

Line 172:

```text
/ you could plug something into. Link-local alone does not qualify: this
```

Line 173:

```text
/ machine has 26 interfaces and 22 of them carry an `fe80::` — an earlier
```

Line 174:

```text
/ version accepted `!ipv6.isEmpty` and listed all 22, which is the exact
```

Line 175:

```text
/ failure the paragraph above describes, committed by the filter written to
```

Line 176:

```text
/ prevent it.
```

Line 178:

```text
/ A linked port with no address is kept on purpose, and only for the kinds
```

Line 179:

```text
/ you physically attach to: a plugged-in Ethernet port that never got a
```

Line 180:

```text
/ lease is one of the more useful things this section can show you.
```

Line 191:

```text
/ One default route. A multi-homed machine has several, and which one wins is
```

Line 192:

```text
/ a separate fact from which ones exist.
```

Line 197:

```text
/ The route macOS is actually using for this family — the first one
```

Line 198:

```text
/ `netstat` prints, which is service order.
```

Line 204:

```text
/ The routing and resolver picture, plus the interfaces it refers to.
```

Line 206:

```text
/ Every default route, in the order `netstat` prints them. The first per
```

Line 207:

```text
/ family is the one in use.
```

Line 209:

```text
/ This used to be a single gateway and a single interface, because the
```

Line 210:

```text
/ parser took the first `default` line and stopped. On a machine attached
```

Line 211:

```text
/ to two networks at once — a wired LAN and a segmented wireless one, which
```

Line 212:

```text
/ is an ordinary way to be set up — that reported one of two answers and
```

Line 213:

```text
/ gave no sign there was another. "Where do my packets go" has as many
```

Line 214:

```text
/ answers as there are default routes; the app's job is to say which one
```

Line 215:

```text
/ wins, not to pretend the others do not exist.
```

Line 217:

```text
/ The interface the winning route leaves by — the answer to "which link am
```

Line 218:

```text
/ I actually using", which is not always the one that looks connected.
```

Line 229:

```text
/ Routes that exist but are not the one in use. Named rather than derived
```

Line 230:

```text
/ at the call site because "you have a second way out and it is not the one
```

Line 231:

```text
/ being used" is the fact this section exists to surface.
```

Line 243:

```text
/ Everything except the timestamp.
```

Line 245:

```text
/ This snapshot carries the whole interface inventory, and `checkedAt` moves
```

Line 246:

```text
/ on every pass by construction — so a plain `!=` is true every single time
```

Line 247:

```text
/ and reassigning on it would invalidate an `@Observable` array of a dozen
```

Line 248:

```text
/ interfaces every refresh interval, forever, whether or not a single byte
```

Line 249:

```text
/ of it changed. The comparison that decides whether to publish has to be
```

Line 250:

```text
/ the content.
```

Line 252:

```text
/ The consequence is deliberate and is why the UI labels this **As of**
```

Line 253:

```text
/ rather than *Checked*: the timestamp on screen is when this picture was
```

Line 254:

```text
/ established, not when the probe last ran. Those differ exactly when
```

Line 255:

```text
/ nothing has changed, which is the case where the distinction costs
```

Line 256:

```text
/ nothing and the redraw would have been free of information.
```

Line 270:

```text
The count of *other* ways out, stated. A second default route is
```

Line 271:

```text
invisible on a machine that is working and is the first thing you want
```

Line 272:

```text
to know on one that is not. Written `+2` rather than `· +2 more`,
```

Line 273:

```text
because this line sits in a 380pt row behind an icon and the long form
```

Line 274:

```text
truncated the interface name it exists to report.
```

Line 291:

```text
MARK: - Probe
```

Line 295:

```text
/ One pass: routes, resolvers, interfaces. Called on a background queue —
```

Line 296:

```text
/ it forks three tools and parses their output, which is not main-thread
```

Line 297:

```text
/ work.
```

Line 308:

```text
MARK: Routes
```

Line 310:

```text
/ `netstat -rn` for both families. The IPv4 default line looks like:
```

Line 312:

```text
/     default            192.168.1.1        UGScg            en0
```

Line 314:

```text
/ The interface is taken from the v4 route when there is one, because that
```

Line 315:

```text
/ is the family almost everything on a LAN actually uses; the v6 gateway is
```

Line 316:

```text
/ still reported beside it.
```

Line 317:

```text
/ **Every** default line, not the first.
```

Line 319:

```text
/ The earlier version `break`ed out of the loop on the first match per
```

Line 320:

```text
/ family, which is correct only on a singly-homed machine. Attach to a
```

Line 321:

```text
/ wired LAN and a segmented wireless network at once and `netstat` prints
```

Line 322:

```text
/ two, of which macOS uses the first by service order — the parser reported
```

Line 323:

```text
/ that one and gave no sign the other existed.
```

Line 336:

```text
A gateway that is an interface name rather than an address is
```

Line 337:

```text
a point-to-point link (`default  link#22  UCSIg  utun4`).
```

Line 338:

```text
Real, but not something you can ping, so it is carried as a
```

Line 339:

```text
route with no gateway rather than as a fake address.
```

Line 351:

```text
MARK: DNS
```

Line 353:

```text
/ `scutil --dns` prints the resolver list twice — once for general queries
```

Line 354:

```text
/ and again under "DNS configuration (for scoped queries)", where every
```

Line 355:

```text
/ interface repeats its own copy. Only the first block is read: the scoped
```

Line 356:

```text
/ section would list the same three servers four times and read as a
```

Line 357:

```text
/ misconfiguration.
```

Line 380:

```text
MARK: Interfaces
```

Line 382:

```text
/ `ifconfig -a`, parsed into the model. The display names come from
```

Line 383:

```text
/ `networksetup -listallhardwareports`, which is the only place macOS says
```

Line 384:

```text
/ that `en0` is called "Wi-Fi".
```

Line 435:

```text
The zone suffix (`fe80::1%en0`) names the interface we are
```

Line 436:

```text
already inside, so it is noise in this position.
```

Line 442:

```text
Compared, not `contains`. `ifconfig` prints exactly two values
```

Line 443:

```text
here and one of them is **inactive**, which contains the
```

Line 444:

```text
string "active" — so a substring test reports link on every
```

Line 445:

```text
interface that has none. That is not hypothetical: the first
```

Line 446:

```text
render of this section listed 22 of 26 interfaces as linked,
```

Line 447:

```text
including three empty Thunderbolt ports and eight spare
```

Line 448:

```text
tunnels, because of this one word.
```

Line 452:

```text
`vlan: 40 parent interface: en0` — a real 802.1Q tag, read off
```

Line 453:

```text
the host. This is the one VLAN fact this machine genuinely
```

Line 454:

```text
knows about itself.
```

Line 467:

```text
Addressed and linked first, then by name, so `en0` leads and the
```

Line 468:

```text
spare tunnels sink whatever order ifconfig happened to print.
```

Line 487:

```text
/ `ifconfig` prints the mask as `0xffffff00`. Counting bits is the whole
```

Line 488:

```text
/ conversion; the leading-`0x` form is the only one it emits.
```

## Sources/FleetConsoleApp/Probes/StorageBreakdown.swift

Line 4:

```text
/ The volume picture the reclaim catalogue cannot give you.
```

Line 6:

```text
/ `StorageScanner` answers "what can I safely delete?". This answers the
```

Line 7:

```text
/ question you ask first: "where did the disk go?" The two are deliberately
```

Line 8:

```text
/ separate scans — the catalogue is a list of known caches, the breakdown is
```

Line 9:

```text
/ a bounded survey of fixed top-level buckets, and neither guesses from
```

Line 10:

```text
/ directory names.
```

Line 12:

```text
/ Honesty rules, applied:
```

Line 13:

```text
/   * The "System & Other" segment is *arithmetic*, not a measurement —
```

Line 14:

```text
/     consumed minus everything measured, and minus purgeable. Its label says
```

Line 15:

```text
/     exactly that.
```

Line 16:

```text
/   * "Purgeable" is the APFS difference between `availableCapacity` and
```

Line 17:

```text
/     `availableCapacityForImportantUsage` — what the system believes it can
```

Line 18:

```text
/     claw back under pressure — never a scan result. It is *inside* consumed
```

Line 19:

```text
/     space, so it is subtracted out of "System & Other" rather than added
```

Line 20:

```text
/     alongside it: the segments must sum to the volume, not to more.
```

Line 21:

```text
/   * Buckets are measured with allocated size (what the volume actually
```

Line 22:

```text
/     gets back), same as the reclaim catalogue.
```

Line 24:

```text
MARK: - Volumes
```

Line 27:

```text
mount path — stable and unique per mount
```

Line 32:

```text
/ Space macOS counts as reclaimable under pressure (local snapshots,
```

Line 33:

```text
/ caches, iCloud evictions). Included in `availableForImportantUsage`.
```

Line 44:

```text
MARK: - Breakdown
```

Line 50:

```text
/ Where the number came from, shown verbatim in the UI.
```

Line 56:

```text
/ The root volume's capacity *as read for this scan*. The bar divides by
```

Line 57:

```text
/ this rather than by today's volume reading, so the segments and their
```

Line 58:

```text
/ denominator always come from the same moment. Zero means the volume
```

Line 59:

```text
/ could not be read at all — see `capacityKnown`.
```

Line 62:

```text
/ One tile per surveyed directory — the heatmap behind the bar. Only the
```

Line 63:

```text
/ measured buckets appear here; "System & Other" stays honestly unmappable.
```

Line 73:

```text
/ False when the scan ran without a readable root volume: there is then no
```

Line 74:

```text
/ free, purgeable or "System & Other" segment, and the bar has to say the
```

Line 75:

```text
/ buckets are all it covers instead of implying they cover the disk.
```

Line 79:

```text
/ One tile in the disk heatmap: a directory the scanner actually walked.
```

Line 81:

```text
path (or bucket root + "/.remainder")
```

Line 86:

```text
/ True for the per-bucket roll-up tile (small entries, loose files, the
```

Line 87:

```text
/ capped tail). The map accounts for every measured byte — a tile that
```

Line 88:

```text
/ silently drops the tail would imply the bucket is tidier than it is.
```

Line 92:

```text
MARK: - Scanner
```

Line 108:

```text
MARK: Volumes
```

Line 110:

```text
/ Mounted local volumes with real capacity figures. Cheap (resource values,
```

Line 111:

```text
/ no I/O walk), so it runs on demand from the module and on launch.
```

Line 152:

```text
Root first, then internal, then by name — the order About This Mac uses.
```

Line 158:

```text
/ `statfs` f_fstypename — "apfs", "hfs", "exfat"… — without parsing mount(8).
```

Line 169:

```text
MARK: Breakdown scan
```

Line 171:

```text
/ Measures the fixed buckets for the root volume. On demand only — this
```

Line 172:

```text
/ walks real directories and costs real I/O, so like the reclaim scan it
```

Line 173:

```text
/ never runs on a timer.
```

Line 178:

```text
Capacity is re-read here rather than taken from `volumes`:
```

Line 179:

```text
`refreshVolumes` publishes back through the main actor, so a
```

Line 180:

```text
caller that refreshed and scanned in the same turn would have
```

Line 181:

```text
measured System & Other / Purgeable / Free against the *previous*
```

Line 182:

```text
snapshot. Reading both on this hop makes the scan and its
```

Line 183:

```text
capacity one fact, published together.
```

Line 195:

```text
/ The fixed survey: category, where it lives, and the one-line basis the
```

Line 196:

```text
/ inspector shows verbatim. A catalogue rather than a heuristic, for the
```

Line 197:

```text
/ same reason the reclaim catalogue is one.
```

Line 232:

```text
Sub-megabyte buckets are noise in a chart about gigabytes; their
```

Line 233:

```text
bytes stay honestly accounted for inside "System & Other".
```

Line 246:

```text
The three arithmetic segments, sized so that measured + other +
```

Line 247:

```text
purgeable + free == totalBytes exactly. `availableBytes` is
```

Line 248:

```text
`volumeAvailableCapacity`, which already excludes purgeable, so
```

Line 249:

```text
purgeable lives inside `usedBytes`: adding it alongside Free and a
```

Line 250:

```text
full-size Other would count it twice and ask the bar to draw more
```

Line 251:

```text
than the volume holds. It is taken out of the unmeasured share
```

Line 252:

```text
instead, and clamped to it so Other can never go negative.
```

Line 275:

```text
/ Measures the immediate children of a bucket — one tile per directory.
```

Line 276:

```text
/ The walk is the same enumeration the bucket total already paid for, so
```

Line 277:

```text
/ the heatmap adds listing cost only, not another disk traversal.
```

Line 279:

```text
/ Two honest caps: entries under 4 MB roll into the bucket's remainder
```

Line 280:

```text
/ tile (they are texture, not signal at this zoom level), and a bucket
```

Line 281:

```text
/ keeps at most 24 tiles before its tail joins the remainder — a heatmap
```

Line 282:

```text
/ with 300 slivers answers no question the row above it didn't.
```

Line 307:

```text
Everything the tiles did not claim: small entries, loose files at
```

Line 308:

```text
the bucket root, and the capped tail. Drawn as its own tile so the
```

Line 309:

```text
map's areas sum to the segment above it.
```

Line 319:

```text
MARK: APFS local snapshots
```

Line 321:

```text
/ Local Time Machine snapshots are the most common reason "purgeable" is
```

Line 322:

```text
/ tens of gigabytes. Listed read-only via `tmutil`; without permission the
```

Line 323:

```text
/ note says why the list is empty instead of implying there are none.
```

## Sources/FleetConsoleApp/Probes/StorageScanner.swift

Line 4:

```text
/ Finds space worth reclaiming, and is careful about the difference between a
```

Line 5:

```text
/ cache and your data.
```

Line 7:

```text
/ The rule that shapes everything here: **a directory being large is not a reason
```

Line 8:

```text
/ to delete it.** A local model weighs 7 GB and takes an hour to fetch again; a
```

Line 9:

```text
/ package cache weighs 2 GB and comes back on its own the next time you build.
```

Line 10:

```text
/ A cleaner that treats those the same is not a tool, it is a trap. So every
```

Line 11:

```text
/ candidate declares what actually happens when it goes, and anything holding
```

Line 12:

```text
/ real data is reported but never offered for deletion.
```

Line 14:

```text
/ Nothing in this file deletes anything on its own. `reclaim(_:)` runs only when
```

Line 15:

```text
/ something calls it, and the UI only calls it after an explicit confirmation
```

Line 16:

```text
/ that names the paths and the consequence.
```

Line 18:

```text
MARK: - Model
```

Line 21:

```text
/ How much you lose by deleting it — not how large it is.
```

Line 23:

```text
/ Regenerates transparently. Deleting costs you nothing but the next
```

Line 24:

```text
/ build being slightly slower.
```

Line 26:

```text
/ Regenerates, but at a real cost in bandwidth or time.
```

Line 28:

```text
/ Not a cache. Reported so you can see where the disk went; never offered
```

Line 29:

```text
/ for deletion, because this tool does not delete your data.
```

Line 55:

```text
/ What happens after it is gone. Shown before anything is deleted.
```

Line 60:

```text
/ `safe` entries are removed outright, the way `brew cleanup` and
```

Line 61:

```text
/ `npm cache clean` already do. Anything that costs something to rebuild goes
```

Line 62:

```text
/ to the Trash instead, so a wrong call is recoverable — at the price of not
```

Line 63:

```text
/ freeing the space until the Trash is emptied. That trade is stated in the
```

Line 64:

```text
/ confirmation rather than decided quietly.
```

Line 68:

```text
/ One entry in the catalogue, before it has been resolved against the disk.
```

Line 75:

```text
/ Paths relative to the home directory.
```

Line 79:

```text
MARK: - Catalogue
```

Line 81:

```text
Deliberately a list of known things rather than a heuristic. A cleaner that
```

Line 82:

```text
guesses from directory names is how people lose work: `~/Library/Application
```

Line 83:

```text
Support/<some app>` is enormous on this machine and every byte of it matters.
```

Line 117:

```text
── Costly to rebuild ──────────────────────────────────────────────────
```

Line 137:

```text
── Reported, never offered ────────────────────────────────────────────
```

Line 145:

```text
MARK: - Scan result
```

Line 163:

```text
MARK: - Scanner
```

Line 169:

```text
/ Set when a reclaim partially failed — usually a path macOS protects.
```

Line 175:

```text
/ Walks the catalogue and measures what is actually on disk.
```

Line 177:

```text
/ Explicitly on demand. Measuring these trees costs real I/O, so it does not
```

Line 178:

```text
/ run on the sampling timer — a monitor that thrashes the disk to tell you the
```

Line 179:

```text
/ disk is busy is its own bug.
```

Line 194:

```text
The three helpers below do the actual filesystem work and are called from the
```

Line 195:

```text
reclaim queue, never the main actor.
```

Line 207:

```text
Anything under a megabyte is noise in a list about gigabytes.
```

Line 217:

```text
/ Sums allocated size, which is what the volume actually gets back — not
```

Line 218:

```text
/ logical file size, which overstates on a compressed or sparse tree.
```

Line 219:

```text
/ Shared with `StorageBreakdown`, which measures its buckets the same way.
```

Line 236:

```text
MARK: - Reclaim
```

Line 238:

```text
/ Deletes or trashes one candidate. Called only from an explicit confirmation.
```

Line 240:

```text
/ `keep` candidates are refused here as well as hidden in the UI, so a future
```

Line 241:

```text
/ caller cannot route around the rule by constructing the action itself.
```

Line 242:

```text
/ `completion` is `@MainActor` because that is where it has always been
```

Line 243:

```text
/ called from. Saying so makes it `Sendable`, which is what lets it cross
```

Line 244:

```text
/ onto `queue` and back.
```

Line 265:

```text
Empty the directory rather than removing it: several of these
```

Line 266:

```text
are recreated by their owning tool only at install time, and a
```

Line 267:

```text
missing cache root is a worse failure than an empty one.
```

## Sources/FleetConsoleApp/Probes/SystemMetrics.swift

Line 7:

```text
/ Host resource sampling — CPU, GPU, memory, SSD, network and battery.
```

Line 9:

```text
/ Like `NetworkMonitor`, this runs in the app rather than the daemon, and for the
```

Line 10:

```text
/ same reason: it is read-only, needs no privilege, and nothing here is worth
```

Line 11:

```text
/ waking the controller for. Every number comes from a kernel interface the
```

Line 12:

```text
/ logged-in user can already read — Mach `host_statistics`, the IOKit registry,
```

Line 13:

```text
/ and `sysctl`. There is no `powermetrics`, because that wants root, and a
```

Line 14:

```text
/ resource monitor that prompts for an admin password to draw a bar chart is a
```

Line 15:

```text
/ worse trade than not drawing it.
```

Line 17:

```text
/ The honesty rules from the rest of the app apply unchanged. A utilisation
```

Line 18:

```text
/ figure is a *difference between two samples*, so the first tick after launch
```

Line 19:

```text
/ has no value to report and says so rather than drawing a confident 0%. A key
```

Line 20:

```text
/ missing from the IOKit registry renders `unknown`, never zero.
```

Line 22:

```text
MARK: - Samples
```

Line 24:

```text
/ CPU load, derived from per-core Mach tick counters.
```

Line 26:

```text
/ False until two ticks have been differenced. Nothing is drawn as a value
```

Line 27:

```text
/ before this is true — a rate needs an interval.
```

Line 29:

```text
/ 0…1 across all cores.
```

Line 34:

```text
/ 0…1 per logical core, in Mach's enumeration order.
```

Line 36:

```text
/ 0…1 averaged over each cluster, or nil when the split is unknown.
```

Line 45:

```text
/ Static facts about the CPU, read once.
```

Line 51:

```text
/ Index range of each cluster within `perCore`, when Apple Silicon reports one.
```

Line 64:

```text
/ Apple Silicon GPU statistics from the IOAccelerator registry entry.
```

Line 66:

```text
/ False when no accelerator published `PerformanceStatistics` — the honest
```

Line 67:

```text
/ state for a machine or OS build that does not expose it.
```

Line 71:

```text
/ 0…1. Nil when the accelerator exists but withheld the key.
```

Line 80:

```text
/ Unified memory, split the way Activity Monitor splits it.
```

Line 85:

```text
/ Reads as the object of "pressure …", which is where it is always shown.
```

Line 112:

```text
/ The boot volume plus throughput for the physical device behind it.
```

Line 116:

```text
/ What Finder reports as available — purgeable space counted the way the
```

Line 117:

```text
/ system will actually let you use it.
```

Line 121:

```text
/ Nil until two samples have been differenced.
```

Line 137:

```text
/ `ProcessInfo.thermalState` — the one thermal fact macOS gives an unprivileged
```

Line 138:

```text
/ process, and the one that explains a sudden drop in clock speed.
```

Line 153:

```text
/ Typed `sysctlbyname`. Shared with `HostProbe`, which reports the same facts
```

Line 154:

```text
/ about this machine that it asks other machines for.
```

Line 172:

```text
MARK: - Sampler
```

Line 174:

```text
Owns the previous counter values, and is touched only from the monitor's serial
```

Line 175:

```text
probe queue. Kept separate from the `@MainActor` monitor so the delta state can
```

Line 176:

```text
never be read from two threads at once — which is also what makes the
```

Line 177:

```text
`@unchecked Sendable` below true rather than merely convenient.
```

Line 192:

```text
MARK: CPU
```

Line 194:

```text
/ Differences the per-core tick counters against the previous call. The first
```

Line 195:

```text
/ call establishes a baseline and reports `sampled == false`.
```

Line 233:

```text
Tick counters are monotonic but can be reset by a core going offline;
```

Line 234:

```text
a negative delta means the baseline is meaningless, so skip the core.
```

Line 274:

```text
MARK: GPU
```

Line 296:

```text
The accelerator reports whole percentages; absent keys stay nil so the
```

Line 297:

```text
UI can say "not reported" instead of drawing an idle GPU.
```

Line 313:

```text
MARK: Memory
```

Line 329:

```text
`host_page_size` rather than the `vm_kernel_page_size` global, which is a
```

Line 330:

```text
`var` Swift 6 cannot tell apart from writable state. It is also the
```

Line 331:

```text
documented pairing for the counts `host_statistics64` just returned.
```

Line 343:

```text
Activity Monitor's "Memory Used" = app + wired + compressed, where file-backed
```

Line 344:

```text
and purgeable pages are cache the system can reclaim, not memory in use.
```

Line 349:

```text
The buckets this sums are counters the kernel updates independently, and
```

Line 350:

```text
under heavy compressor churn their total can drift above physical RAM —
```

Line 351:

```text
a real reading, but one that renders "18.2 GB of 17.2 GB" on the one card
```

Line 352:

```text
whose arithmetic a reader checks first. A used figure is clamped to what it
```

Line 353:

```text
is used *of*; the overshoot is noise in the counters, not extra memory.
```

Line 380:

```text
MARK: Storage
```

Line 426:

```text
/ The registry lists a driver per block device, including the synthesised ones
```

Line 427:

```text
/ backing disk images. The internal SSD is the one with the largest whole-media
```

Line 428:

```text
/ child, which is a more durable rule than assuming `disk0`.
```

Line 474:

```text
MARK: Network
```

Line 478:

```text
A failed read breaks the interval; the next success is a baseline.
```

Line 490:

```text
Replace even after reset, hot-plug or a gap so the next tick can recover.
```

Line 495:

```text
MARK: Power
```

Line 511:

```text
MARK: Topology
```

Line 518:

```text
Apple Silicon publishes one perflevel per cluster type, ordered fastest
```

Line 519:

```text
first. Mach enumerates logical CPUs the other way round — efficiency
```

Line 520:

```text
cores lead — which is asserted by a test, not assumed here.
```

Line 551:

```text
MARK: - Monitor
```

Line 553:

```text
/ Samples the host on a fixed cadence and publishes immutable value types.
```

Line 555:

```text
/ The cadence is 2 s. `NetworkMonitor` re-probes every 20 s because a Wi-Fi SSID
```

Line 556:

```text
/ does not change faster than that, but utilisation is only meaningful as a
```

Line 557:

```text
/ recent average, and a slower tick makes a bar that is always describing the
```

Line 558:

```text
/ past. Two seconds also keeps the sampler's own cost off the graph.
```

Line 570:

```text
/ Fan and die temperatures from the SMC. `available == false` is a
```

Line 571:

```text
/ normal answer on VMs and very old Macs; see FleetCore's SMC.swift.
```

Line 574:

```text
/ Ring buffers behind the live charts. Bounded so a long-running app
```

Line 575:

```text
/ cannot grow them without limit. Disk I/O is kept as separate read/write
```

Line 576:

```text
/ series — a combined "I/O" number hides a write storm behind idle reads,
```

Line 577:

```text
/ which is precisely the case the chart exists to catch.
```

Line 599:

```text
/ Premium gate for the SMC. Injected so the monitor can be exercised
```

Line 600:

```text
/ without dragging a UserDefaults suite into every preview.
```

Line 603:

```text
Nonisolated so `deinit` can invalidate it; nothing observes this handle.
```

Line 607:

```text
The default is *unlocked*, not locked: a monitor constructed without a
```

Line 608:

```text
licence is one being previewed, tested, or run by the developer, and a
```

Line 609:

```text
preview whose premium card is a lock screen previews the wrong product.
```

Line 610:

```text
The app injects the real gate; the default exists so every other call
```

Line 611:

```text
site reads the hardware.
```

Line 621:

```text
/ The run loop holds the timer even though the closure is weak, so it has to
```

Line 622:

```text
/ be invalidated here or a per-view instance would strand a live sampler.
```

Line 627:

```text
/ Re-samples now. Safe to call from a refresh button — an in-flight sample is
```

Line 628:

```text
/ not queued behind another.
```

Line 634:

```text
The SMC is premium-gated at the source, not at the card: when it is
```

Line 635:

```text
locked the keys are never read, so the free tier cannot pay the I/O
```

Line 636:

```text
cost of a feature it cannot see.
```

Line 654:

```text
/ Assigns only what changed, so one moving number does not invalidate every
```

Line 655:

```text
/ row that reads this object.
```

Line 687:

```text
MARK: - Thresholds
```

Line 689:

```text
One place decides when a number turns amber or red, so CPU and GPU cannot
```

Line 690:

```text
disagree about what "busy" means. The bands are deliberately generous: a
```

Line 691:

```text
resource monitor that goes red whenever a build runs teaches you to ignore red.
```

Line 702:

```text
/ Free space is the one metric where the warning has to arrive early — by the
```

Line 703:

```text
/ time a disk is 99% full, macOS is already failing writes.
```

Line 721:

```text
/ Colour for a process on the map. Deliberately *not* derived from its size:
```

Line 722:

```text
/ area already encodes that, and a heatmap whose colour repeats its geometry
```

Line 723:

```text
/ carries one dimension of information while looking like two. Size is the
```

Line 724:

```text
/ market cap, CPU is the day's move.
```

Line 744:

```text
MARK: - Formatting
```

Line 747:

```text
/ The same shared formatter the console uses. This was a second
```

Line 748:

```text
/ identically-configured `ByteCountFormatter`, i.e. two places for a byte
```

Line 749:

```text
/ count to drift apart.
```

Line 762:

```text
/ Percentages are shown whole. A utilisation figure with a decimal point
```

Line 763:

```text
/ implies a precision that a two-second average does not have.
```

Line 769:

```text
/ Whole degrees. The SMC reports tenths; a tenth of a degree on a
```

Line 770:

```text
/ two-second sample is noise wearing a decimal point.
```

Line 776:

```text
/ Whole RPM, thousands-separated ("1,912 rpm" reads at a glance;
```

Line 777:

```text
/ "1912 rpm" makes the eye count digits).
```

## Sources/FleetConsoleApp/Probes/VLANSource.swift

Line 4:

```text
The seam a real VLAN source plugs into.
```

Line 6:

```text
This machine knows two VLAN facts about itself and no more: whether it has an
```

Line 7:

```text
802.1Q interface, and what tag and parent that interface carries. Both are read
```

Line 8:

```text
off `ifconfig` by `RoutingProbe` and both are real. Everything else a VLAN
```

Line 9:

```text
admin console shows — what a segment is called, what it is for, which subnet it
```

Line 10:

```text
owns, which gateway serves it, what else is on it — lives in a switch, a
```

Line 11:

```text
controller, or a router API. A Mac cannot derive it.
```

Line 13:

```text
So this file does not implement a VLAN source. It defines what one is, and it
```

Line 14:

```text
is the *only* thing the UI depends on, so adding a real one later is a
```

Line 15:

```text
registration and not a rewrite:
```

Line 17:

```text
VLANRegistry.shared.register(UniFiVLANSource(controller: url, token: token))
```

Line 19:

```text
Until something is registered, `VLANRegistry.shared.isAvailable` is false and
```

Line 20:

```text
every VLAN segment surface is absent from the UI. Not disabled, not a
```

Line 21:

```text
"coming soon" row, not an empty state — absent. An empty state is a claim that
```

Line 22:

```text
there are no segments; the truth is that nobody asked.
```

Line 24:

```text
MARK: - The protocol
```

Line 26:

```text
/ Anything that can name the segments this fleet is divided into.
```

Line 28:

```text
/ Deliberately small. A source has to answer one question — "what segments are
```

Line 29:

```text
/ there, and which of this host's interfaces sits on each" — and the app will
```

Line 30:

```text
/ not ask it anything else, so a first implementation against a router API is a
```

Line 31:

```text
/ day's work rather than a port of the whole model.
```

Line 33:

```text
/ `Sendable` and async because every plausible implementation is a network call
```

Line 34:

```text
/ to a controller. Nothing about the UI blocks on it: `VLANRegistry` caches the
```

Line 35:

```text
/ last answer and refreshes off the main actor, and a source that times out
```

Line 36:

```text
/ leaves the previous snapshot in place rather than blanking the section.
```

Line 38:

```text
/ Shown in the support bundle and in the section's provenance line, so a
```

Line 39:

```text
/ segment on screen can always be traced to who claimed it.
```

Line 42:

```text
/ Every segment this source knows about.
```

Line 45:

```text
/ Which segment a given host interface belongs to, if the source can say.
```

Line 46:

```text
/ The default implementation matches on the 802.1Q tag the host already
```

Line 47:

```text
/ reads for itself, which is enough for any source that reports tags.
```

Line 60:

```text
MARK: - The declared source
```

Line 62:

```text
/ Segments as the operator declares them in `config.json`.
```

Line 64:

```text
/ This is the first real `VLANSource`, and it exists because of the gap a host
```

Line 65:

```text
/ on an access port cannot close. A Mac on a **trunk** port reads its own
```

Line 66:

```text
/ 802.1Q tag off `ifconfig`. A Mac on an **access** port — which is almost
```

Line 67:

```text
/ every Mac, and every Mac behind a firewall doing the segmentation — never
```

Line 68:

```text
/ sees a tag at all: the switch strips it before the frame reaches the NIC. All
```

Line 69:

```text
/ the host gets is an address, a subnet and a gateway.
```

Line 71:

```text
/ The app will not close that gap by inference. `10.10.40.0/24` looks like
```

Line 72:

```text
/ VLAN 40, and an implementation that reads the third octet is right on one
```

Line 73:

```text
/ network and confidently wrong on the next. But an operator writing
```

Line 74:

```text
/ `{"tag": 40, "cidr": "10.10.40.0/24", "name": "Guest"}` is not a heuristic —
```

Line 75:

```text
/ it is an assertion with an author, which is exactly what `sourceName`
```

Line 76:

```text
/ carries into the UI so a segment on screen can be traced to whoever claimed
```

Line 77:

```text
/ it.
```

Line 79:

```text
/ It is also the honest floor for the whole seam: a controller-backed source
```

Line 80:

```text
/ can replace it, but a fleet with no controller API still gets true labels
```

Line 81:

```text
/ instead of no labels.
```

Line 95:

```text
/ Tag first, then subnet.
```

Line 97:

```text
/ The tag is the stronger claim and is used whenever the host actually has
```

Line 98:

```text
/ one. Falling back to the subnet is what makes this work on an access
```

Line 99:

```text
/ port, and it is containment rather than string equality: an interface at
```

Line 100:

```text
/ `10.10.40.12/24` belongs to a segment declared as `10.10.40.0/24`, and
```

Line 101:

```text
/ also to one declared as `10.10.0.0/16`, because both are true. The most
```

Line 102:

```text
/ specific match wins, for the same reason a routing table prefers the
```

Line 103:

```text
/ longest prefix.
```

Line 119:

```text
/ IPv4 containment. Both sides are masked to the declared prefix and
```

Line 120:

```text
/ compared — the same arithmetic `RoutingProbe` uses to derive a subnet
```

Line 121:

```text
/ from a netmask, so a segment and an interface cannot disagree about what
```

Line 122:

```text
/ network they are on.
```

Line 137:

```text
MARK: - The registry
```

Line 139:

```text
/ The one place a source is installed, and the one place the UI asks whether
```

Line 140:

```text
/ there is one.
```

Line 142:

```text
/ This is the capability flag from the design rules, as an object rather than a
```

Line 143:

```text
/ boolean: `isAvailable` is false whenever no source is registered *or* the
```

Line 144:

```text
/ registered source has not yet produced a segment, and every VLAN view is
```

Line 145:

```text
/ gated on it. There is no path that renders a segment row from nothing.
```

Line 156:

```text
/ The capability flag. False with no source, and false with a source that
```

Line 157:

```text
/ has told us about nothing — in both cases there is no segment to draw and
```

Line 158:

```text
/ therefore no section.
```

Line 167:

```text
/ Install a source. One call — this is the whole integration surface.
```

Line 182:

```text
/ Installs (or removes) the declared source to match `config.json`.
```

Line 184:

```text
/ Called on launch and again whenever the file changes, so declaring a
```

Line 185:

```text
/ segment and coming back to a UI that already shows it is the behaviour
```

Line 186:

```text
/ you would expect. Deleting the last declaration unregisters — which puts
```

Line 187:

```text
/ `isAvailable` back to false and takes every segment surface off screen
```

Line 188:

```text
/ rather than leaving the last-known set behind. That asymmetry with the
```

Line 189:

```text
/ *failure* path above is deliberate: a controller that times out has not
```

Line 190:

```text
/ deleted your VLANs, but you deleting the lines has.
```

Line 192:

```text
/ A registered non-config source is left alone. A real controller outranks
```

Line 193:

```text
/ a hand-written list, and a config reload must not silently evict one.
```

Line 203:

```text
/ Re-asks the source. Never throws into the UI and never leaves the section
```

Line 204:

```text
/ half-drawn: a failure records the message and keeps the previous
```

Line 205:

```text
/ segments, because a controller that is briefly unreachable has not
```

Line 206:

```text
/ deleted your VLANs.
```

Line 222:

```text
/ Decorates the host's interfaces with the segment each one sits on.
```

Line 223:

```text
/ A no-op when no source is registered, which is what keeps `segment` nil
```

Line 224:

```text
/ and every VLAN affordance out of the tree.
```

## Sources/FleetConsoleApp/ServiceLabels.swift

Line 7:

```text
/ Local presentation preferences shared by popover and dashboard, never sent over RPC.
```

Line 23:

```text
First use: do not create anything until a label is actually saved.
```

Line 61:

```text
/ The editor owns a draft. Dismissal never writes, and failed saves keep the draft open.
```

Line 214:

```text
/ Tags use their own glyph and neutral text. They never recolor a service's status icon.
```

## Sources/FleetConsoleApp/Settings.swift

Line 4:

```text
/ The app's read-only view of `config.json`.
```

Line 6:

```text
/ The controller owns the file — it writes the defaults on first run and it is
```

Line 7:

```text
/ the only thing that mutates it, so this never writes. What it does is give
```

Line 8:

```text
/ every surface one place to ask "is this section on", "how often should I
```

Line 9:

```text
/ look", "is this verb unlocked", instead of each view inventing its own
```

Line 10:

```text
/ answer.
```

Line 12:

```text
/ **Reloaded on change, not polled.** A `DispatchSource` on the file descriptor
```

Line 13:

```text
/ costs nothing while the file sits still, which is almost always. Editing the
```

Line 14:

```text
/ config from the menu-bar dropdown and coming back to a UI that already
```

Line 15:

```text
/ reflects it is the behaviour you would expect from a Mac app; making that
```

Line 16:

```text
/ work by re-reading the file every few seconds is not.
```

Line 21:

```text
/ Non-nil when the file exists and could not be parsed. Surfaced rather
```

Line 22:

```text
/ than swallowed: silently running on defaults because a file is malformed
```

Line 23:

```text
/ is how you lose an afternoon.
```

Line 45:

```text
The declared segments are config, so the registry follows the file
```

Line 46:

```text
the same way every other setting does.
```

Line 53:

```text
A missing file is the zero-setup case and is not an error: the
```

Line 54:

```text
defaults *are* the configuration until the controller writes one.
```

Line 64:

```text
/ Watches the directory rather than the file.
```

Line 66:

```text
/ `FleetConfig.save()` writes atomically, which replaces the inode — a
```

Line 67:

```text
/ descriptor held on the old file would go on reporting nothing forever
```

Line 68:

```text
/ while the config on disk changed underneath it. The containing directory
```

Line 69:

```text
/ survives the swap, so that is what is watched.
```

## Sources/FleetConsoleApp/SurfaceRenderer.swift

Line 6:

```text
Renders every FleetConsole surface to PNG.
```

Line 8:

```text
This lives in the app target rather than in a throwaway package beside it,
```

Line 9:

```text
because the console's views need `AppModel`, `ConsoleModel`, `ChromeTools` and
```

Line 10:

```text
the probes — the whole target. Reaching them from outside would mean
```

Line 11:

```text
symlinking the target into a second package and keeping the two in step, and a
```

Line 12:

```text
design sheet that drifts from the app is worse than no sheet.
```

Line 14:

```text
It is compiled only when `FLEET_SURFACE_RENDERER` is defined, which only
```

Line 15:

```text
`Scripts/surface-sheet.sh` does. `Scripts/build-app.sh` does not, so none of
```

Line 16:

```text
this — including the fixtures — is in the shipped binary.
```

Line 18:

```text
The fixtures below are the point. Rendering the *live* fleet gives whatever
```

Line 19:

```text
happens to be running, which on a quiet machine is six empty states; a sheet
```

Line 20:

```text
is meant to show each surface carrying its full vocabulary at once — every
```

Line 21:

```text
status tone, evidence in all four of its separate facts, an expiring lease, a
```

Line 22:

```text
crash, an unmanaged listener.
```

Line 27:

```text
/ A bounded product-detail export: two fixture views, no tool or account surfaces.
```

Line 30:

```text
/ The console window's canonical size, and the popover's own width.
```

Line 33:

```text
MARK: - Entry point
```

Line 59:

```text
Model construction reads settings and initializes a trial clock.
```

Line 60:

```text
Keep both in a process-local fixture home, never the operator's state.
```

Line 69:

```text
Offscreen windows still need a running NSApplication for layout,
```

Line 70:

```text
fonts and appearance resolution — but not an activated one.
```

Line 79:

```text
MARK: - Churn
```

Line 81:

```text
/ Counts how many times the live probes publish over a fixed window.
```

Line 83:

```text
/ "Do not rebuild the menu when nothing changed" is a claim, and a claim
```

Line 84:

```text
/ about a running app is worth exactly what it is measured at. This boots
```

Line 85:

```text
/ the real `AppModel` — real timers, real `ps`, real `netstat` — puts an
```

Line 86:

```text
/ `withObservationTracking` loop on each published surface, and prints how
```

Line 87:

```text
/ often each one actually fired.
```

Line 89:

```text
/ The interesting number is `routing`. Its snapshot carries the whole
```

Line 90:

```text
/ interface inventory and its `checkedAt` moves on every pass, so a plain
```

Line 91:

```text
/ `!=` would publish on every single refresh forever. `sameContent(as:)`
```

Line 92:

```text
/ is what makes the expected count **0** on a machine whose network is not
```

Line 93:

```text
/ changing — and 0 is only meaningful next to a `processes` count that is
```

Line 94:

```text
/ non-zero, which proves the harness is watching a live model rather than a
```

Line 95:

```text
/ dead one.
```

Line 129:

```text
/ Re-arms itself on every change, counting as it goes. A static method rather
```

Line 130:

```text
/ than three mutually-recursive local functions: `onChange` is `@Sendable`, and
```

Line 131:

```text
/ a local function captured into it is not.
```

Line 149:

```text
MARK: - The run
```

Line 155:

```text
Only aggregate system telemetry stays live. Process and network
```

Line 156:

```text
identity collectors are disabled in this explicit fixture mode.
```

Line 167:

```text
The client-local roster is separate from Snapshot. Never let fixture
```

Line 168:

```text
views fall back to the operator's persistent singleton.
```

Line 177:

```text
A declared VLAN segment, so the sheet shows the segment vocabulary
```

Line 178:

```text
rather than the absence of it. Same rule as every other fixture here:
```

Line 179:

```text
rendering only what happens to be true on the build machine gives a
```

Line 180:

```text
sheet of empty states, and the segment surfaces are exactly the ones
```

Line 181:

```text
that render *nothing* until something is declared.
```

Line 183:

```text
It goes in through `adopt` — the config path — rather than by
```

Line 184:

```text
constructing a `NetworkSegment` directly, so what the sheet proves is
```

Line 185:

```text
the chain a real `config.json` takes.
```

Line 187:

```text
Always use synthetic declarations, never the operator's configured
```

Line 188:

```text
network names, subnets or gateways. Live network inspection belongs
```

Line 189:

```text
to the running app, not to the public fixture sheet.
```

Line 195:

```text
These are the shipping view implementations with synthetic data.
```

Line 196:

```text
Do not traverse tool panels: terminal/files can create processes.
```

Line 255:

```text
/ The Task Composer window on its own — a surface the sheet should prove
```

Line 256:

```text
/ renders without defects (the assign picker, the plate labels, the launch
```

Line 257:

```text
/ footer) before it ever reaches a launch.
```

Line 287:

```text
/ Apply a state change with animation suppressed. Every surface here is
```

Line 288:

```text
/ reached by mutating `ConsoleModel`/`ChromeTools`, and each of those
```

Line 289:

```text
/ mutations animates — a module cross-fade, a panel slide. Captured
```

Line 290:

```text
/ mid-flight the result is two frames composited into one backing store,
```

Line 291:

```text
/ which is what put a doubled, offset "Files" in the panel header.
```

Line 298:

```text
/ Turn the run loop so SwiftUI lays out, then reassert the synthetic
```

Line 299:

```text
/ snapshot and turn it again so the fixture is what gets drawn.
```

Line 303:

```text
The connection banner and the titlebar pill read these directly rather
```

Line 304:

```text
than inferring them from the snapshot, so a sheet rendered with the
```

Line 305:

```text
subscription deliberately shut down would otherwise show every surface
```

Line 306:

```text
wearing a red "controller offline" pill.
```

Line 318:

```text
MARK: - Menu bar
```

Line 320:

```text
/ The status item on a strip of menu bar, drawn through the same
```

Line 321:

```text
/ `MenuBarItemController.render` the live item uses: once with nothing to
```

Line 322:

```text
/ act on, once with an attention count beside the meters.
```

Line 352:

```text
MARK: - Popover
```

Line 357:

```text
Capture the whole shared chrome on every tab, not detached tab bodies.
```

Line 365:

```text
The administration rows on their own. Inside the Connections tab they
```

Line 366:

```text
sit below a scroll fold that a still capture cannot reach, and a
```

Line 367:

```text
surface the sheet cannot show is a surface nobody reviews.
```

Line 371:

```text
The diagnostic panel carrying output far taller than its 132pt bound.
```

Line 372:

```text
It shipped for a release drawing straight over the rows beneath it, and
```

Line 373:

```text
no surface caught that because no fixture ever put enough text in it.
```

Line 374:

```text
A four-line ping never reaches the bound; a support bundle is hundreds.
```

Line 391:

```text
/ Deliberately far taller than the panel's bound — the whole point of the
```

Line 392:

```text
/ surface is to prove the overflow is clipped and scrolled, not painted.
```

Line 419:

```text
A hosting view has to be in a window before SwiftUI will lay it out
```

Line 420:

```text
against a real appearance and give a usable `fittingSize`.
```

Line 424:

```text
The real popover draws on `NSPopover`'s own backdrop, so this content
```

Line 425:

```text
is transparent by itself. Without a fill behind it the dark capture
```

Line 426:

```text
came out as white-on-white — every label invisible, which reads as a
```

Line 427:

```text
broken surface rather than a missing backdrop.
```

Line 439:

```text
The window, not the hosting view — same as the console path. A view
```

Line 440:

```text
captured on its own carries no window backdrop.
```

Line 445:

```text
MARK: - Console
```

Line 453:

```text
Park it where it cannot be seen. `cacheDisplay` needs the window
```

Line 454:

```text
ordered in — it renders the view's backing store, not the screen — so
```

Line 455:

```text
it cannot simply be left unordered.
```

Line 470:

```text
The relations workspace uses shipping view code and controller fixtures.
```

Line 471:

```text
Capture at both widths without activating or foregrounding a window.
```

Line 479:

```text
The narrow layout is a separate acceptance surface for every module.
```

Line 489:

```text
Home — the priority view the window opens on.
```

Line 494:

```text
Inspectors, each driven by the selection that produces it.
```

Line 523:

```text
The chrome tool panels.
```

Line 525:

```text
Terminal and Files come out with their header, close button and panel
```

Line 526:

```text
frame drawn and the emulator body **blank**. `cacheDisplay` walks the
```

Line 527:

```text
AppKit drawing path, and SwiftTerm renders the grid through its own
```

Line 528:

```text
Metal layer, which that path cannot see — the same reason the package
```

Line 529:

```text
compiles a .metal shader at build time.
```

Line 531:

```text
Capturing the emulator would mean CGWindowListCreateImage, which needs
```

Line 532:

```text
Screen Recording consent and would put a permission prompt in the
```

Line 533:

```text
middle of a build script. A blank body that is visibly blank is a
```

Line 534:

```text
better outcome than a screenshot tool that silently starts asking for
```

Line 535:

```text
recording rights, so the limitation stays and is stated here.
```

Line 548:

```text
MARK: - Capture
```

Line 550:

```text
/ SwiftUI lays out on the run loop, and an `@Observable` write does not
```

Line 551:

```text
/ take effect until it has turned. One turn is enough for a module switch;
```

Line 552:

```text
/ a tool panel spawning a process needs more.
```

Line 561:

```text
The frame view, not the content view — the titlebar, its accessory
```

Line 562:

```text
pill and the toolbar are part of the surface being documented.
```

Line 572:

```text
`bitmapImageRepForCachingDisplay` can hand back a rep the view is
```

Line 573:

```text
already using, and `cacheDisplay` only repaints what is dirty — so
```

Line 574:

```text
without marking the whole frame dirty first, a capture can carry
```

Line 575:

```text
pixels from the previous surface.
```

Line 585:

```text
MARK: - Fixtures
```

Line 589:

```text
Stable display-only identity. These paths are never opened by the fixture.
```

Line 592:

```text
Demo process identities are injected before any collector/timer starts.
```

Line 593:

```text
Live verification does not use this branch or these measurements.
```

Line 607:

```text
/ Synthetic config declarations using RFC 5737 documentation subnets.
```

Line 608:

```text
/ They need not match the rendering machine's live interfaces.
```

Line 639:

```text
MARK: Services — one per status tone, so the sheet carries the whole
```

Line 640:

```text
vocabulary rather than five rows of green.
```

Line 644:

```text
Healthy: a check ran and passed. The only state that earns green.
```

Line 665:

```text
Running (unverified): alive, listening, but no check configured —
```

Line 666:

```text
the best state a service without a health check can reach.
```

Line 681:

```text
Degraded: passing its check, breaching a budget.
```

Line 701:

```text
Expiring: the lease is nearly up and nobody has renewed it.
```

Line 716:

```text
Unhealthy: the check ran and failed, repeatedly.
```

Line 736:

```text
Crashed: exited without being asked to. Terminal, so it drops out
```

Line 737:

```text
of `activeServices` and only shows where history is shown.
```

Line 751:

```text
Claimed, expired, three ports. The case the row layout actually
```

Line 752:

```text
fails on: every accessory in a row is `fixedSize`, so "Claimed" +
```

Line 753:

```text
"Expired" + a three-port list claimed the whole width and the row
```

Line 754:

```text
took it out of the only compressible thing left — the title. The
```

Line 755:

```text
real fleet had one of these and 42 surfaces had none, so the sheet
```

Line 756:

```text
showed rows with names while the app showed one without.
```

Line 846:

```text
/ Newest first, and monotonic — which is what the daemon delivers.
```

Line 848:

```text
/ `registry.events` is `ORDER BY seq DESC` and the module does not re-sort, so
```

Line 849:

```text
/ the header's "newest first" is a claim the daemon backs and the view passes
```

Line 850:

```text
/ through. This fixture used to be in neither order, which rendered a scrambled
```

Line 851:

```text
/ log on the one surface anybody reviews the Event Log from — a sheet that
```

Line 852:

```text
/ disagrees with the app teaches reviewers to stop trusting the sheet.
```

Line 854:

```text
Descending age, so `seq` and `ts` agree the way an append-only log's do.
```

## Sources/FleetConsoleApp/Views/AgentProfileCard.swift

Line 4:

```text
/ One agent's profile.
```

Line 6:

```text
/ The first version showed only "N services · said Xm ago", which is blank for
```

Line 7:

```text
/ any agent that is not running something *right now* — which is most of them,
```

Line 8:

```text
/ most of the time. An agent that launched fourteen services this morning and
```

Line 9:

```text
/ left two of them running is not "0 services"; that is the single most
```

Line 10:

```text
/ important thing to know about it. So the card always shows: what it is doing,
```

Line 11:

```text
/ what it has done, where it works, and what it last said.
```

Line 19:

```text
/ `nil` when the feature is off or nothing has been sampled yet. A
```

Line 20:

```text
/ snapshot whose `amountUSD` is nil is a different thing entirely — the
```

Line 21:

```text
/ agent exists and could not be priced — and the detail says so.
```

Line 70:

```text
MARK: - Header
```

Line 85:

```text
Knowns only. An agent nobody can price says so in its
```

Line 86:

```text
detail rather than putting a caveat in the title row.
```

Line 135:

```text
MARK: - Detail
```

Line 153:

```text
The unknown is spelled out rather than shown as a zero,
```

Line 154:

```text
and the source line is what makes it actionable: a tool
```

Line 155:

```text
that publishes nothing is not the same as one whose log
```

Line 156:

```text
would not open.
```

Line 275:

```text
/ Compact labelled number used across the agent profile header.
```

## Sources/FleetConsoleApp/Views/AgentsPopover.swift

Line 5:

```text
/ Ownership IDs are a local address book. Detected sessions and the mailbox
```

Line 6:

```text
/ remain evidence from their existing sources, never fabricated by registration.
```

Line 49:

```text
/ Waiting-for-you first, then the newest of everything else.
```

Line 62:

```text
/ The Agents tab: who fixes things, what the agents are saying, who they are,
```

Line 63:

```text
/ and the hosted fixer. No scroll view, expanding detail or inline editor —
```

Line 64:

```text
/ four bands that fit the 300pt body, with the full roster and the mailbox one
```

Line 65:

```text
/ click away in their sheets.
```

Line 154:

```text
/ The designated fixer and the one action it exists for.
```

Line 198:

```text
/ One mailbox entry on one line: who, what kind when it matters, what, when.
```

Line 238:

```text
/ Credit-funded review through the connected Ouros account.
```

Line 282:

```text
/ The complete roster and detected sessions live outside the fixed menu budget.
```

Line 333:

```text
/ All provided messages remain reachable, with pending replies first. Reuse the
```

Line 334:

```text
/ existing reply loop rather than routing into a nonexistent dashboard module.
```

Line 382:

```text
/ The registration workflow is usable even when the controller is offline and
```

Line 383:

```text
/ the roster is empty. The same observable roster feeds the task composer.
```

## Sources/FleetConsoleApp/Views/Components.swift

Line 4:

```text
The popover-ramp components. The status vocabulary they draw with —
```

Line 5:

```text
`StatusTone` and the `ServiceState` / `DeviceHealth` mappings into it — is in
```

Line 6:

```text
`Design/StatusTone.swift`.
```

Line 20:

```text
/ The colour swatch that stands in for a name: a legend chip, a heatmap hover
```

Line 21:

```text
/ readout, a chart series key.
```

Line 23:

```text
/ Not a `StatusPip` and not a `ConnectionPip`. Those carry a *state* and have
```

Line 24:

```text
/ to be legible as the only thing on screen, which is why they own a pulse and
```

Line 25:

```text
/ a popover-ramp label. A swatch carries nothing on its own — it exists to tie
```

Line 26:

```text
/ a colour to the text beside it — so it is one dot at one size, and every
```

Line 27:

```text
/ legend in the console gets the same one.
```

Line 40:

```text
/ The evidence row. Four independent facts, never merged: this is the component
```

Line 41:

```text
/ that keeps the UI honest.
```

Line 77:

```text
The verdict glyph, not a coloured dot. The chip's word names the
```

Line 78:

```text
subject* — "process", "port", "health" — so with a dot here the
```

Line 79:

```text
only thing carrying pass/fail/never-ran was hue, in the one
```

Line 80:

```text
component whose whole job is to be honest about what is known.
```

Line 81:

```text
The glyph is the same size as the label beside it, so the chip's
```

Line 82:

```text
metrics are unchanged.
```

Line 95:

```text
/ The leading icon for every row in the app. The tile *tint* carries status, the
```

Line 96:

```text
/ *symbol* carries identity — so a row is scannable at a glance without reading
```

Line 97:

```text
/ a word, and the two meanings never fight each other.
```

Line 102:

```text
/ Small corner dot, used when status needs to be legible independently of tint.
```

Line 112:

```text
`ink`, not `color`: this glyph sits on a 16% tint of its own
```

Line 113:

```text
hue, which is the same arrangement that measured 1.98–2.95:1
```

Line 114:

```text
in light mode for `Tag`. The tile fill still carries the tone,
```

Line 115:

```text
so status is unchanged — the symbol just stops dissolving
```

Line 116:

```text
into the thing behind it.
```

Line 132:

```text
/ The corner verdict dot on an icon tile.
```

Line 134:

```text
/ Extracted from `EntityIcon` when `AppGlyph` needed the same badge over a real
```

Line 135:

```text
/ application icon. Duplicating twenty lines of geometry would have been the
```

Line 136:

```text
/ start of the two-implementations-that-drift problem this design system exists
```

Line 137:

```text
/ to prevent — and this particular geometry has already been got wrong once,
```

Line 138:

```text
/ which is what the note below is about.
```

Line 144:

```text
Sits *inside* the tile's bounds. It used to be pushed out by
```

Line 145:

```text
`size * 0.08`, and because `.offset` is a draw-time transform
```

Line 146:

```text
that never changes reported layout size, the ZStack still
```

Line 147:

```text
measured `size × size` while painting 2.1–3.0pt past its own
```

Line 148:

```text
edge: unreserved overflow into the row's icon-to-text gap on
```

Line 149:

```text
every badged row, and clipped outright by any ancestor that
```

Line 150:

```text
bounds its content. Corner-anchored with no offset, the badge
```

Line 151:

```text
is contained at every size the app uses, so a badged row and
```

Line 152:

```text
an unbadged row still start on the same vertical.
```

Line 170:

```text
/ Role-based symbols. What a thing *is* should not change when it becomes
```

Line 171:

```text
/ unhealthy — only its colour should.
```

Line 202:

```text
/ Host resources. Each silhouette is deliberately unlike the others, for the
```

Line 203:

```text
/ same reason the two menu-bar items are: these four rows sit adjacent and
```

Line 204:

```text
/ permanently, so they have to be told apart without reading the label.
```

Line 205:

```text
/ `gpu` looks like the obvious symbol and is not available on macOS 14 —
```

Line 206:

```text
/ a hexagon cluster reads as "many small parallel units" and, unlike the
```

Line 207:

```text
/ square chip outline of `cpu`, cannot be confused with it at row size.
```

Line 298:

```text
A chip is a fixed word, not a paragraph. Without these it competes
```

Line 299:

```text
for width against a row title that holds `layoutPriority(1)`, loses,
```

Line 300:

```text
and compresses — truncating to "U…", or breaking mid-word into a
```

Line 301:

```text
stack one character tall per line, which is how "Unmanaged" became a
```

Line 302:

```text
four-line block in the popover. `fixedSize` makes it refuse to
```

Line 303:

```text
compress at all, so the row's variable-length element truncates
```

Line 304:

```text
instead. That is the right loser: the title already limits to one
```

Line 305:

```text
line and its full text is in the subtitle and the tooltip.
```

Line 335:

```text
/ Confirmation payload for the two destructive verbs. It carries the evidence the
```

Line 336:

```text
/ action is based on so a wrong target is visible *before* clicking.
```

Line 337:

```text
/ Tiny inline chart for a service's recent CPU / memory. Deliberately unlabelled
```

Line 338:

```text
/ on the axes: it shows shape and trend, and the exact number sits beside it.
```

Line 373:

```text
/ A horizontal utilisation bar with its numeral beside it.
```

Line 375:

```text
/ `value` is optional on purpose. A rate is a difference between two samples, so
```

Line 376:

```text
/ there is a real moment — the first tick after launch, or a key the accelerator
```

Line 377:

```text
/ declined to publish — when there is no value to draw. That case renders an empty
```

Line 378:

```text
/ grey track and a dash, never a confident bar sitting at zero.
```

Line 413:

```text
/ One column per logical core, grouped by cluster.
```

Line 415:

```text
/ Apple Silicon schedules background work onto the efficiency cores and
```

Line 416:

```text
/ foreground work onto the performance ones, so a single aggregate number hides
```

Line 417:

```text
/ the thing you actually want to know: whether the machine is busy, or merely
```

Line 418:

```text
/ tidying up. Mach enumerates efficiency cores first; the ranges come from
```

Line 419:

```text
/ `hw.perflevel*` rather than from that assumption.
```

Line 425:

```text
Each cluster is as wide as its cores and no wider, set side by side
```

Line 426:

```text
from the leading edge. Clusters used to divide the card's width
```

Line 427:

```text
between them, which parked P halfway across the card with nothing
```

Line 428:

```text
between it and E. The wrapping grid is only the fallback for a core
```

Line 429:

```text
count that cannot fit one row.
```

## Sources/FleetConsoleApp/Views/ConnectionsPopover.swift

Line 5:

```text
/ Item 1 — Connections. Everything about how this machine is attached to
```

Line 6:

```text
/ anything else: internet, LAN, Tailscale, VPN, VLAN, Thunderbolt, exo.
```

Line 8:

```text
/ Rows that are not configured say so rather than being hidden: "no VLANs
```

Line 9:

```text
/ configured" is an answer, and hiding it would leave you wondering whether the
```

Line 10:

```text
/ app checked at all.
```

Line 19:

```text
/ `true` when this view is shown inside Fleet's unified popover rather than
```

Line 20:

```text
/ owning a second status item and its own chrome.
```

Line 58:

```text
Routing, resolvers and the interface inventory — the
```

Line 59:

```text
administration layer. It sits under the link rows because the
```

Line 60:

```text
order is the order you ask the questions in: am I attached,
```

Line 61:

```text
then where do my packets go.
```

Line 85:

```text
/ What on this machine is actually holding a socket.
```

Line 87:

```text
/ This tab opened on four `StatTile`s — Internet, Link, Tailnet, Devices —
```

Line 88:

```text
/ and every one of those facts is restated, with its evidence, in the rows
```

Line 89:

```text
/ immediately below: the Internet row says "reachable · 6 ms", the Tailscale
```

Line 90:

```text
/ row gives the tailnet IP, Devices has its own section. So the tiles were
```

Line 91:

```text
/ a second, thinner copy of the page under them.
```

Line 93:

```text
/ What was missing is the thing a network surface is opened *for*: which
```

Line 94:

```text
/ processes are listening, on what. The controller already knows —
```

Line 95:

```text
/ `activeServices` carries the ports it verified, and `unmanaged` is
```

Line 96:

```text
/ everything holding a socket it did not launch. Those two together are the
```

Line 97:

```text
/ listening set, and the split between them is the interesting part.
```

Line 119:

```text
/ Observed sockets only — `evidence.listeningPorts`, not `effectivePorts`,
```

Line 120:

```text
/ which falls back to what a service *declared*. A section titled
```

Line 121:

```text
/ "Listening" that lists a port nobody has seen listening would be exactly
```

Line 122:

```text
/ the kind of claim the rest of this app refuses to make.
```

Line 123:

```text
/ Unmanaged listeners only.
```

Line 125:

```text
/ This section used to list managed services too, on the argument that a
```

Line 126:

```text
/ network surface is opened to find out what is holding a socket. The
```

Line 127:

```text
/ argument is sound and the result was not: a managed service already has a
```

Line 128:

```text
/ row on the Services tab with its state, its owner, its lease and its verbs,
```

Line 129:

```text
/ so listing it again here made every managed service appear on two tabs and
```

Line 130:

```text
/ left neither one authoritative. Services live on Services. What this tab
```

Line 131:

```text
/ adds is the half the controller does not own — the sockets held by things
```

Line 132:

```text
/ it never launched.
```

Line 139:

```text
/ Two ports fit the trailing column at this width; past that the count
```

Line 140:

```text
/ carries it rather than a list that would truncate mid-number.
```

Line 147:

```text
MARK: - Rows
```

Line 213:

```text
MARK: - Tile values
```

Line 239:

```text
MARK: - Overlays
```

Line 241:

```text
/ VPN and VLAN — the two things layered *over* the link rather than carried by
```

Line 242:

```text
/ it. Its own view, like `NetworkSection` and `NetworkAdminSection`, so the
```

Line 243:

```text
/ design sheet can capture it: inside the tab these rows sit below the
```

Line 244:

```text
/ `FleetMetrics.sectionMaxHeight` scroll clamp that a still capture cannot reach, and a
```

Line 245:

```text
/ surface the sheet cannot show is a surface nobody reviews. That is not
```

Line 246:

```text
/ hypothetical — the VLAN row shipped reading "none on this Mac" directly under
```

Line 247:

```text
/ a Segments list naming four VLANs, and it took a screenshot from the running
```

Line 248:

```text
/ app to catch it.
```

Line 297:

```text
/ Two sources answer VLAN questions and they answer *different* ones, so
```

Line 298:

```text
/ this row has to say which it is answering or it contradicts the Segments
```

Line 299:

```text
/ list a few rows above it.
```

Line 301:

```text
/ It shipped as "none on this Mac" while Segments listed four VLANs read
```

Line 302:

```text
/ from `config.json`. Both statements were true — this host has no 802.1Q
```

Line 303:

```text
/ sub-interface, *and* it sits on VLAN 40 through an untagged access port —
```

Line 304:

```text
/ but put one under the other with no reconciliation and the surface reads
```

Line 305:

```text
/ as broken. "None" was also doing too much work: the question is not
```

Line 306:

```text
/ whether VLANs exist, it is whether **this Mac carries tags itself**.
```

Line 308:

```text
/ So the subtitle leads with membership when a segment matched, and the
```

Line 309:

```text
/ local-trunk answer moves into the detail where it belongs.
```

Line 321:

```text
What this host is *on*, which is the thing you actually want,
```

Line 322:

```text
and which no amount of looking at `ifconfig` will tell you.
```

Line 335:

```text
What this host *carries*, which is a separate fact and the one
```

Line 336:

```text
the local probe can actually establish.
```

Line 348:

```text
/ Which of this host's interfaces landed on a declared segment.
```

Line 364:

```text
No segment source and no local tag: say what was checked, not "none".
```

Line 370:

```text
/ `OverlaySection` with its disclosure state owned locally, so the design sheet
```

Line 371:

```text
/ can capture it on its own.
```

## Sources/FleetConsoleApp/Views/Console/AgentAwarenessWorkspace.swift

Line 5:

```text
/ Agent-first spatial awareness. The projection is bounded and refreshed by
```

Line 6:

```text
/ existing observations; folder metadata has a bounded asynchronous cache,
```

Line 7:

```text
/ with no physics loop, extra process collector or paid request.
```

Line 18:

```text
Observation bounds can change without moving any existing world node.
```

Line 19:

```text
Only fitting or focusing changes this camera anchor, never refresh().
```

Line 278:

```text
A spatial reference grid moves with the camera, not a data trace.
```

Line 475:

```text
NSHostingView measures provisional tiny frames before the shipping
```

Line 476:

```text
window is sized. Never commit those measurements as a fitted camera.
```

## Sources/FleetConsoleApp/Views/Console/AgentTopologyWorkspace.swift

Line 4:

```text
/ Fixed ownership lanes. Nothing moves unless the controller supplies new data;
```

Line 5:

```text
/ session detection stays separate from registered ownership.
```

## Sources/FleetConsoleApp/Views/Console/AwarenessGraph.swift

Line 5:

```text
/ Observational projection only. Detected sessions and registry ownership have
```

Line 6:

```text
/ independent provenance; proximity on the canvas never establishes ownership.
```

Line 23:

```text
/ Card center in world coordinates, not its top-left corner.
```

Line 110:

```text
Walk the actual closure so omitted descendants cannot be
```

Line 111:

```text
silently relabelled as unassociated high-load context.
```

Line 122:

```text
A small context sample balances CPU and resident memory, not a table
```

Line 123:

```text
of the entire inventory. These rows carry no inferred agent owner.
```

Line 159:

```text
Detected sessions come only from the actual session source.
```

Line 186:

```text
Sessions get the budget first. Secondary detail never evicts an
```

Line 187:

```text
observed agent; every edge is pruned to the selected endpoints.
```

Line 202:

```text
MARK: - Stable world placement
```

Line 204:

```text
/ A finite identity-seeded packing pass, never a force simulation. Only
```

Line 205:

```text
/ identities, card geometry and observed relationships affect placement.
```

Line 226:

```text
Place primary project/session geometry before optional process context,
```

Line 227:

```text
so a changing high-load sample cannot displace the agent clusters.
```

Line 228:

```text
A missing root in cyclic input gets a deterministic independent anchor.
```

Line 284:

```text
Guaranteed non-overlap even for adversarial hash collisions; bounded
```

Line 285:

```text
search and at most 120 cards keep this off the normal path.
```

Line 289:

```text
/ Unlike Swift.Hasher this is deliberately stable across launches.
```

## Sources/FleetConsoleApp/Views/Console/Chrome/ChromeToolRail.swift

Line 5:

```text
The chrome rail and its spring-loaded panel — the host side of the seam
```

Line 6:

```text
declared in `ToolSurface.swift`.
```

Line 8:

```text
Everything here is laid out as *reserved space*, never as an overlay. The
```

Line 9:

```text
window's top ribbon (the module picker, the fleet device label, the search
```

Line 10:

```text
field, the refresh button and the controller pill) lives in the titlebar
```

Line 11:

```text
strip, which is AppKit's NSToolbar plus a titlebar accessory; this rail lives
```

Line 12:

```text
in the window's content view, attached with `safeAreaInset(edge: .trailing)`.
```

Line 13:

```text
Two independent facts keep it off the ribbon's words:
```

Line 15:

```text
1. `safeAreaInset` *subtracts* width from the split view rather than
```

Line 16:

```text
floating over it, so the rail and the panel take their room out of the
```

Line 17:

```text
layout at every window width — there is no ZStack and no `.overlay`
```

Line 18:

```text
anywhere in this file.
```

Line 19:

```text
2. The inset content is laid out inside the container's safe area, whose
```

Line 20:

```text
top inset is the titlebar+toolbar strip of a `.fullSizeContentView`
```

Line 21:

```text
window. Even if the two frames did meet, AppKit composites the titlebar
```

Line 22:

```text
container above the content view, so content cannot draw over toolbar
```

Line 23:

```text
text.
```

Line 25:

```text
Because the rail is reserved rather than floating, the ribbon's own content
```

Line 26:

```text
is the thing that has to give — which is why the module header, the fleet
```

Line 27:

```text
label and the controller pill all truncate with a tail ellipsis.
```

Line 29:

```text
MARK: - Rail metrics
```

Line 31:

```text
/ Derived from `ConsoleToolMetrics` and `ConsoleMetrics` rather than measured
```

Line 32:

```text
/ by eye. Kept local for the same reason `ConsoleToolMetrics` is: the chrome
```

Line 33:

```text
/ work should land without touching the token file. Fold both in afterwards.
```

Line 35:

```text
/ One toggle wide, with the rail's own spacing as its side padding.
```

Line 38:

```text
/ The panel's drag edge, as drawn — a hairline, like every other divider
```

Line 39:

```text
/ in the window.
```

Line 42:

```text
/ The edge's *hit* region, which is a different number and has to be.
```

Line 43:

```text
/ AppKit's own split dividers draw a hairline and accept the pointer for
```

Line 44:

```text
/ about ten points around it; this drew five and accepted five, which is
```

Line 45:

```text
/ under half the target macOS trains people to expect and is why the panel
```

Line 46:

```text
/ could not be dragged in practice.
```

Line 49:

```text
/ What the three columns must keep no matter how wide the panel is asked
```

Line 50:

```text
/ to be.
```

Line 52:

```text
/ This used to sum its own four numbers, and the sum was wrong in a way
```

Line 53:

```text
/ nothing could see: 786pt of reserve against a window whose minimum
```

Line 54:

```text
/ content width was 780. `ConsoleLayout` owns the budget now and
```

Line 55:

```text
/ `ConsoleLayoutTests` proves it balances at both the minimum and the
```

Line 56:

```text
/ composed size, so this is one subtraction from a checked total rather
```

Line 57:

```text
/ than a fifth independent opinion about how wide a column should be.
```

Line 62:

```text
MARK: - State
```

Line 64:

```text
/ Owns the three surfaces, which one is revealed, and the geometry discipline
```

Line 65:

```text
/ between the panel's pixels and a child process's columns.
```

Line 67:

```text
/ Lives on the window controller, not in a view: the surfaces hold child
```

Line 68:

```text
/ processes, and a terminal must not be torn down because SwiftUI rebuilt a
```

Line 69:

```text
/ struct.
```

Line 77:

```text
/ Only ever written from a coalescer callback, never from a layout pass —
```

Line 78:

```text
/ which is also why the "too narrow" state is derived from it rather than
```

Line 79:

```text
/ from the raw proposed size.
```

Line 82:

```text
/ What the operator dragged the panel to. Clamped at render against the
```

Line 83:

```text
/ window's actual width; stored unclamped so widening the window restores
```

Line 84:

```text
/ the width they chose.
```

Line 91:

```text
/ The panel's last measured content size, kept so `regrid()` can recompute
```

Line 92:

```text
/ against a re-measured cell without waiting for the panel to move.
```

Line 95:

```text
MARK: Reveal
```

Line 97:

```text
/ One implementation for all three toggles. The only per-tool branch in the
```

Line 98:

```text
/ whole rail is `ToolSurfaceRegistry.surface(for:)`, which is where it
```

Line 99:

```text
/ belongs.
```

Line 105:

```text
Switching tools tears the outgoing panel down through the same path a
```

Line 106:

```text
dismissal takes, so a tool cannot be left half-revealed.
```

Line 114:

```text
/ Opens the terminal on `context` and runs `commandLine` in it. The way an
```

Line 115:

```text
/ outside agent is started from inside the app: in a shell you can watch,
```

Line 116:

```text
/ answer and stop, not as a hidden child.
```

Line 148:

```text
/ Re-open the live panel against a new selection. Cheap when nothing moved,
```

Line 149:

```text
/ because `ToolContext` is `Equatable`.
```

Line 157:

```text
MARK: Geometry
```

Line 159:

```text
/ Called as often as the layout system likes. Nothing reaches a child
```

Line 160:

```text
/ process from here — the coalescer decides when a size has stopped moving.
```

Line 166:

```text
/ Re-derive the grid from the last measured panel size.
```

Line 168:

```text
/ Split out from `propose(size:)` because the grid is a function of two
```

Line 169:

```text
/ things, and only one of them is the panel: moving the window to a display
```

Line 170:

```text
/ with a different backing scale re-measures the character cell without the
```

Line 171:

```text
/ panel changing size by a single point, and the grid has to follow.
```

Line 175:

```text
The surface owns the font, so it owns the cell. This measured against
```

Line 176:

```text
`TerminalCellMetrics.placeholder` — a 7×15 stand-in — while the panel
```

Line 177:

```text
was drawing an 8×16 cell (JetBrains Mono NFM at 12pt) and reserving a
```

Line 178:

```text
further 17pt for the scroller it never subtracted. At the default
```

Line 179:

```text
420pt panel that asked a child for 59×40 and then laid it out at
```

Line 180:

```text
489×640 inside a 415×600 hole, and `PTYHostView` clipped the
```

Line 181:

```text
difference: nine of Yazi's columns sliced off the trailing edge, and
```

Line 182:

```text
two and a half rows of the shell — the ones a fresh prompt is printed
```

Line 183:

```text
on — pushed off the top. The same panel now settles 49×37.
```

Line 185:

```text
The placeholder stays as the answer for a surface that has not
```

Line 186:

```text
published a cell yet, which is the only thing it was ever good for.
```

Line 204:

```text
/ The end of a drag, or a panel that has just been revealed and should not
```

Line 205:

```text
/ wait out the quiet period before its first paint.
```

Line 222:

```text
/ The panel's actual width: what was asked for, bounded by the seam's
```

Line 223:

```text
/ limits, and bounded again by what the three columns can spare. At the
```

Line 224:

```text
/ window's 1060pt minimum this yields 346pt — above `panelMin`, so the
```

Line 225:

```text
/ panel never has to squeeze a column below its floor to exist.
```

Line 232:

```text
/ True when the settled grid cannot honestly draw a full-screen TUI. Only
```

Line 233:

```text
/ PTY-backed tools ever settle a grid.
```

Line 240:

```text
MARK: - The reserved field
```

Line 242:

```text
/ Rail plus panel, as one trailing inset. The rail is always present so the
```

Line 243:

```text
/ space it occupies never changes; only the panel's width comes and goes.
```

Line 249:

```text
/ The window's full content width, measured behind the inset. Needed to
```

Line 250:

```text
/ clamp the panel; read from a background rather than from the panel itself
```

Line 251:

```text
/ so the clamp cannot depend on its own result.
```

Line 261:

```text
No transition and no spring.
```

Line 263:

```text
This carried `.transition(.move(edge: .trailing))` under a comment
```

Line 264:

```text
explaining that the panel slides in. It never did: a move transition
```

Line 265:

```text
needs a container whose frame is stable across the change, and this
```

Line 266:

```text
one inserts a view into an `HStack` whose width changes on the same
```

Line 267:

```text
frame, so SwiftUI fell back to its default opacity fade. The result
```

Line 268:

```text
was a panel that dissolved into place — motion that belongs to a
```

Line 269:

```text
popover, on a thing that is a column.
```

Line 271:

```text
The panel is a screen in a fixed frame. It is either showing or it is
```

Line 272:

```text
not, and switching tools swaps what is on it. Appearing immediately is
```

Line 273:

```text
what that reads as, and it also means a PTY-backed surface is handed
```

Line 274:

```text
exactly one grid instead of one per frame of a spring.
```

Line 278:

```text
MARK: - The rail
```

Line 280:

```text
/ The reserved strip of chrome: home, then one toggle per `ConsoleTool`.
```

Line 286:

```text
/ `ToolSurfaceRegistry.live` is a plain computed property, so nothing
```

Line 287:

```text
/ observes it. The 1 Hz clock the lease countdowns already run on is a
```

Line 288:

```text
/ truthful cadence for a running indicator and costs no second timer.
```

Line 335:

```text
/ One button, four call sites. Selection, hover, running indicator and help
```

Line 336:

```text
/ text all live here, so no tool can grow its own affordance.
```

Line 357:

```text
The indicator sits *outside* the glyph's box so a live tool
```

Line 358:

```text
and a revealed tool read as two different facts.
```

Line 374:

```text
MARK: - The panel
```

Line 376:

```text
/ The embedded field the tools draw into. Owns its drag edge, its header, and
```

Line 377:

```text
/ the one place a measured size becomes a proposed grid.
```

Line 393:

```text
Nothing this panel contains may draw outside it. `frame(width:)`
```

Line 394:

```text
proposes a width; it does not enforce one, so a subview that reports a
```

Line 395:

```text
larger ideal size — a chip row, a terminal laid out to a stale grid —
```

Line 396:

```text
simply overflows and paints across the rail and the titlebar strip.
```

Line 397:

```text
The panel is a container with a hard edge, and this is that edge.
```

Line 401:

```text
/ The surface's measured character cell, read here so the panel *observes*
```

Line 402:

```text
/ it: `PTYSession` is `@Observable`, so a re-measure on a display change
```

Line 403:

```text
/ invalidates this body and the `onChange` below re-derives the grid.
```

Line 416:

```text
MARK: Header
```

Line 430:

```text
Yields before the tool's own name does when the panel is
```

Line 431:

```text
narrow, rather than pushing it out of the header.
```

Line 448:

```text
MARK: Content
```

Line 462:

```text
Identity, because the two pty-backed surfaces are the same
```

Line 463:

```text
type*. Terminal and Files both resolve to a
```

Line 464:

```text
`PTYTerminalView` at the same position in the tree, so
```

Line 465:

```text
switching between them looks to SwiftUI like the same view
```

Line 466:

```text
with new values: it calls `updateNSView`, which is
```

Line 467:

```text
deliberately empty, instead of `makeNSView`. The panel kept
```

Line 468:

```text
whichever host it was given first — open the shell, then
```

Line 469:

```text
Files, and the header said Files over the shell's prompt.
```

Line 475:

```text
The measured size of the panel's content region — the only input
```

Line 476:

```text
to the grid. `onChange` runs after layout, and the coalescer
```

Line 477:

```text
holds the value until it stops moving, so no child process is
```

Line 478:

```text
ever handed a size from inside a layout pass or an animation.
```

Line 490:

```text
The other half of the grid's inputs. The panel has not moved, but the
```

Line 491:

```text
cell it is drawing has, so the same pixels now mean a different number
```

Line 492:

```text
of columns.
```

Line 498:

```text
MARK: Drag edge
```

Line 501:

```text
Drawn as a hairline, hit as a ten-point strip. The overhang is split
```

Line 502:

```text
evenly either side and taken out of the layout with a negative inset,
```

Line 503:

```text
so widening the target does not widen the seam you can see.
```

Line 518:

```text
No animation while a pointer is driving the width:
```

Line 519:

```text
the panel should track the hand, and the coalescer is
```

Line 520:

```text
already suppressing the resizes this produces.
```

## Sources/FleetConsoleApp/Views/Console/Chrome/HomeModule.swift

Line 4:

```text
The landing surface: what needs attention first, and where to go next.
```

Line 6:

```text
Five equally-weighted modules answered "where is everything" but never "what
```

Line 7:

```text
should I look at" — every screen was one click away and none of them was the
```

Line 8:

```text
first one. Home is the answer to the second question, and it does not invent
```

Line 9:

```text
one: the controller already decides what needs a decision in
```

Line 10:

```text
`computeAttention`, including the crash loop in the controller itself, which
```

Line 11:

```text
has no service row anywhere and was previously only findable by reading the
```

Line 12:

```text
database by hand. Those items are this view's spine.
```

Line 14:

```text
The modules are not deleted, or demoted, or merged. They keep ⌘1…⌘n and their
```

Line 15:

```text
indices; home is a sixth destination with its own shortcut, and every priority
```

Line 16:

```text
row hands off *into* a module with the row already selected.
```

Line 18:

```text
It lives under Chrome/ only because the file-ownership split during this work
```

Line 19:

```text
put new files here; it belongs beside the other modules in Views/Console/.
```

Line 57:

```text
MARK: - Priority
```

Line 79:

```text
The last snapshot describes what *was* true. Presenting it as
```

Line 80:

```text
current would be exactly the stale claim this app refuses to
```

Line 81:

```text
make, so the list is withheld rather than greyed out.
```

Line 90:

```text
Kept apart from the attention list on purpose: the daemon
```

Line 91:

```text
deliberately never files agent chatter as an incident, and
```

Line 92:

```text
a question waiting for an answer is a decision only you
```

Line 93:

```text
can make, not a fault to diagnose.
```

Line 137:

```text
/ The window is already open, so the hand-off needs no dashboard to open.
```

Line 142:

```text
MARK: - Drill-down
```

Line 147:

```text
"Modules", not "Go deeper". The list under it is exactly
```

Line 148:

```text
`ConsoleModule.allCases` — the same six names the toolbar
```

Line 149:

```text
picker and the View menu use — so calling it anything else
```

Line 150:

```text
makes the user map an invented phrase onto a vocabulary the
```

Line 151:

```text
rest of the window already taught them. A section label names
```

Line 152:

```text
its contents; it is not an instruction to the reader.
```

Line 156:

```text
Derived, not written out: the list under this label is
```

Line 157:

```text
`ConsoleModule.allCases`, and a hard-coded "⌘1…⌘5" went stale
```

Line 158:

```text
the moment a sixth module was added.
```

Line 173:

```text
/ The live one-liner under each module name — enough to tell you whether
```

Line 174:

```text
/ going there is worth it. Every value is one the module itself shows.
```

Line 188:

```text
Capacity comes from the volume, not from the throughput
```

Line 189:

```text
differencing that `sampled` describes — so it is gated on having a
```

Line 190:

```text
total, and says nothing when it does not have one.
```

Line 195:

```text
"active", not "managed", because this row is the Services module's
```

Line 196:

```text
own summary and that module's header says active. They are the same
```

Line 197:

```text
number from the same set, and a stopped service is still managed —
```

Line 198:

```text
so "managed" was both the wrong word and the wrong count for it.
```

Line 212:

```text
MARK: - Rows
```

Line 214:

```text
/ One priority line. Clicking it is navigation, not selection — home hands you
```

Line 215:

```text
/ to the surface that can act on the thing, which is why there is no selected
```

Line 216:

```text
/ state here to disagree with the module's own.
```

Line 261:

```text
/ A statement rather than a row: nothing to click, because the answer is that
```

Line 262:

```text
/ there is nothing to go to.
```

Line 289:

```text
/ A module, its live summary, and its shortcut. The badge is the contract:
```

Line 290:

```text
/ the index shown here is the same one `MainMenu` binds.
```

## Sources/FleetConsoleApp/Views/Console/Chrome/ToolSurface.swift

Line 3:

```text
The chrome tool rail — the seam shared by the panels that hang off the
```

Line 4:

```text
console window's chrome: a terminal and a Yazi file surface.
```

Line 6:

```text
This file exists for one reason. The panels live in a spring-loaded sidebar
```

Line 7:

```text
field, and both are backed by a PTY running a full-screen TUI. A
```

Line 8:

```text
panel whose width animates would hand that TUI a new column count on every
```

Line 9:

```text
frame of the spring, and Yazi would redraw through the whole animation — the
```

Line 10:

```text
tearing this design is explicitly meant to avoid. So geometry is never
```

Line 11:

```text
forwarded to a child process while it is still in motion: the panel proposes
```

Line 12:

```text
sizes, `ToolResizeCoalescer` waits for them to stop changing, and only a
```

Line 13:

```text
settled, cell-aligned `TerminalGrid` ever reaches a surface.
```

Line 15:

```text
MARK: - Identity
```

Line 17:

```text
/ The chrome tools. One case per toggle in the window chrome; the rail
```

Line 18:

```text
/ draws itself from `allCases`, so adding a tool here is the only edit needed
```

Line 19:

```text
/ to give it a toggle.
```

Line 33:

```text
/ Chrome toggle glyph. Deliberately plain SF Symbols.
```

Line 41:

```text
/ Intended chrome shortcut. ⌘0 and ⌘1…⌘n are already spoken for by the
```

Line 42:

```text
/ dashboard and the modules — `n` is `ConsoleModule.allCases.count`, not a
```

Line 43:

```text
/ number written down here — ⇧⌘H by Home and ⌘K/⌘R by search and refresh,
```

Line 44:

```text
/ so the tools take the rest of the shifted range.
```

Line 52:

```text
/ Whether this tool drives a pseudo-terminal.
```

Line 60:

```text
MARK: - Geometry
```

Line 62:

```text
/ Character-cell size for the panel's monospaced font, measured once by the
```

Line 63:

```text
/ surface that owns the font and handed back here so the math is shared.
```

Line 68:

```text
/ A sane non-zero default so a grid computed before the first text
```

Line 69:

```text
/ measurement is merely wrong rather than a divide-by-zero.
```

Line 75:

```text
/ A whole-cell terminal size. Never fractional: a PTY has no concept of half a
```

Line 76:

```text
/ column, and rounding at the last moment is what produces a torn frame.
```

Line 81:

```text
/ The floor below which a full-screen TUI cannot be honestly drawn. Yazi's
```

Line 82:

```text
/ three-pane layout collapses under roughly 40 columns, and anything under
```

Line 83:

```text
/ 10 rows loses its status line. A panel narrower than this shows a
```

Line 84:

```text
/ "too narrow" state instead of a mangled one — the same principle the rest
```

Line 85:

```text
/ of the app follows by refusing to display a number it cannot stand behind.
```

Line 92:

```text
/ Quantize an available pixel size down to whole cells. Floors rather than
```

Line 93:

```text
/ rounds, so the grid always fits inside the panel and the last column is
```

Line 94:

```text
/ never clipped mid-glyph.
```

Line 96:

```text
/ `reservedWidth` is the part of the panel a surface spends before it can
```

Line 97:

```text
/ draw a single column — for a SwiftTerm view, the scroller's width, which
```

Line 98:

```text
/ it subtracts whatever the scroller's visibility
```

Line 99:

```text
/ (`TerminalView.getEffectiveWidth`). Measuring the columns against the
```

Line 100:

```text
/ whole panel instead is how a grid ends up wider than the panel that asked
```

Line 101:

```text
/ for it, and `PTYHostView` clips the difference off the trailing edge.
```

Line 112:

```text
MARK: - Resize discipline
```

Line 114:

```text
/ Holds a proposed grid until it stops changing, then emits it once.
```

Line 116:

```text
/ SwiftUI hands us a new size on every frame of the sidebar spring. Forwarding
```

Line 117:

```text
/ each one costs a `TIOCSWINSZ` plus a `SIGWINCH` and a full TUI repaint, which
```

Line 118:

```text
/ is both the visible tearing and a real cost — Yazi redraws its whole tree per
```

Line 119:

```text
/ signal. Waiting for quiescence turns an entire animation into one resize.
```

Line 122:

```text
/ Long enough to outlast `ConsoleAnimation`-class springs, short enough that
```

Line 123:

```text
/ a deliberate drag still feels like it lands immediately.
```

Line 136:

```text
/ Called as often as the layout system likes. Cheap when the grid has not
```

Line 137:

```text
/ actually changed cells, which is the common case mid-spring: a few pixels
```

Line 138:

```text
/ of width usually map to the same column count.
```

Line 151:

```text
/ Emit immediately — for the end of an explicit drag, or a panel that has
```

Line 152:

```text
/ just been revealed and should not wait out the quiet period before its
```

Line 153:

```text
/ first paint.
```

Line 162:

```text
/ Forget the settled value so the next proposal is treated as fresh. Used
```

Line 163:

```text
/ when a surface is torn down and rebuilt against a new process.
```

Line 174:

```text
MARK: - Context
```

Line 176:

```text
/ What a tool should open against. Assembled by the chrome from the console's
```

Line 177:

```text
/ current selection so that opening the file surface on a selected service
```

Line 178:

```text
/ lands in that service's working directory rather than `$HOME`.
```

Line 180:

```text
/ Working directory for a PTY-backed tool.
```

Line 182:

```text
/ Human-readable description of the current selection, for the panel's
```

Line 183:

```text
/ header.
```

Line 185:

```text
/ The selected service's id, when a service is selected.
```

Line 197:

```text
MARK: - Surface contract
```

Line 199:

```text
/ Implemented by each tool panel. The host owns visibility and geometry; the
```

Line 200:

```text
/ surface owns its child process and its rendering.
```

Line 202:

```text
/ Deliberately class-bound and main-actor: every implementation wraps either an
```

Line 203:

```text
/ `NSView` or an `@Observable` model, and none of them is a value type.
```

Line 208:

```text
/ Whether the surface currently holds a live child process. The chrome uses
```

Line 209:

```text
/ this to draw the toggle's running indicator, and to decide whether
```

Line 210:

```text
/ revealing the panel needs to start something.
```

Line 213:

```text
/ Reveal or first-open against a context. Called on toggle-on, and again
```

Line 214:

```text
/ when the selection changes while the panel is open.
```

Line 217:

```text
/ A settled, cell-aligned size. Only ever called by the host through a
```

Line 218:

```text
/ `ToolResizeCoalescer`, never directly from a layout pass.
```

Line 221:

```text
/ Toggle-off. Whether this tears down the child process or leaves it warm
```

Line 222:

```text
/ is the surface's decision — a shell with scrollback is worth keeping.
```

Line 225:

```text
/ The panel's content. Type-erased on purpose: the host embeds the
```

Line 226:

```text
/ `NSViewRepresentable` PTY wrappers behind one rail, and the rail should
```

Line 227:

```text
/ not be generic over which one is showing.
```

Line 231:

```text
/ Resolves a tool to its surface, one instance per tool for the window's
```

Line 232:

```text
/ lifetime. The host holds this; the surfaces hold the child processes.
```

Line 248:

```text
/ Live tools, for the chrome's running indicators.
```

Line 266:

```text
/ Shared "this panel cannot draw itself yet" state. Used by a surface whose
```

Line 267:

```text
/ backing tool is missing or whose panel is too narrow to render honestly —
```

Line 268:

```text
/ the same instinct as the rest of the app, which would rather say it does not
```

Line 269:

```text
/ know than show something it cannot stand behind.
```

Line 294:

```text
MARK: - Panel tokens
```

Line 296:

```text
/ Chrome-panel metrics. Kept in its own namespace rather than appended to
```

Line 297:

```text
/ `ConsoleMetrics` so the tool rail can land without touching the token file;
```

Line 298:

```text
/ fold it in once the chrome work settles.
```

Line 300:

```text
/ A representative character cell for the panel font at the default text
```

Line 301:

```text
/ size — JetBrains Mono NFM and SF Mono both measure 8×16 at 12pt. Used
```

Line 302:

```text
/ only to size the *panel*; the grid handed to a child process is always
```

Line 303:

```text
/ computed from the cell the surface actually measured.
```

Line 306:

```text
/ What SwiftTerm takes off the drawable width for its scroller, whatever
```

Line 307:

```text
/ the scroller's visibility (`TerminalView.getEffectiveWidth`). 17pt at
```

Line 308:

```text
/ macOS's overlay scroller style.
```

Line 311:

```text
/ Panel bounds inside the sidebar field.
```

Line 313:

```text
/ The minimum is what `TerminalGrid.minimum` actually costs — its columns
```

Line 314:

```text
/ at the reference cell, *plus* the scroller reserve and the drag edge,
```

Line 315:

```text
/ neither of which can draw a column. This said it was "derived from
```

Line 316:

```text
/ `TerminalGrid.minimum`" while being 40 × 8 exactly, which left the two
```

Line 317:

```text
/ non-drawing strips out and made 320pt a width at which the file surface
```

Line 318:

```text
/ could only ever report itself too narrow to draw.
```

Line 320:

```text
/ The claim that used to sit here — "the window's 1060pt minimum leaves the
```

Line 321:

```text
/ panel 346pt" — was false twice over: the minimum was 780, not 1060, and
```

Line 322:

```text
/ at 780 the column reserve alone was 786, so the panel's floor did not fit
```

Line 323:

```text
/ at the narrowest window by a margin of −440pt. The window's minimum is now
```

Line 324:

```text
/ *derived from* this floor (`ConsoleLayout.minimumContentWidth`) rather
```

Line 325:

```text
/ than asserted to accommodate it, and `ConsoleLayoutTests` proves the
```

Line 326:

```text
/ arrangement balances there exactly.
```

Line 330:

```text
/ The resting width: the minor section of the composed window, snapped to
```

Line 331:

```text
/ the ladder. 377 rather than the previous 420 — a panel is a guest of the
```

Line 332:

```text
/ three columns, and taking the golden minor rather than an arbitrary 420
```

Line 333:

```text
/ is what lets the inspector stay up beside it at the composed size.
```

Line 337:

```text
/ Toggle button in the chrome rail.
```

Line 341:

```text
/ The spring the panel opens with. Slower than `ConsoleAnimation.selection`
```

Line 342:

```text
/ because it moves a whole column, and the coalescer above absorbs the cost.
```

## Sources/FleetConsoleApp/Views/Console/ConsoleModel.swift

Line 4:

```text
Console navigation state — one object that owns what the three columns show.
```

Line 6:

```text
`AppModel` owns *data*; this owns *where you are*. The distinction matters
```

Line 7:

```text
for the same reason rows observe their own record: a search keystroke should
```

Line 8:

```text
not invalidate the daemon snapshot, and a snapshot should never move your
```

Line 9:

```text
selection.
```

Line 11:

```text
The module list itself is a design declaration — `ConsoleMetrics` sizes the
```

Line 12:

```text
toolbar picker from `allCases.count` — so it lives in `Design/ConsoleModule.swift`.
```

Line 14:

```text
/ What the inspector column is looking at. Derived from module + selection,
```

Line 15:

```text
/ never set independently — the inspector is a *view of* a selection, and a
```

Line 16:

```text
/ selection that lives in two places is a selection that desynchronises.
```

Line 20:

```text
/ `VolumeInfo.id` (a mount path) or a `BreakdownSegment.id` (a
```

Line 21:

```text
/ `StorageCategory`). One inspector resolves both, because a bar segment
```

Line 22:

```text
/ and a volume are two views of the same disk.
```

Line 24:

```text
ServiceRecord.id
```

Line 25:

```text
UnmanagedProcess.id
```

Line 26:

```text
DeviceRecord.id
```

Line 29:

```text
/ Menu-bar and keyboard commands reach the window through these. The main
```

Line 30:

```text
/ menu is AppKit (the app bootstraps with AppKit for the status items), so
```

Line 31:

```text
/ `CommandGroup` does not apply; notifications are the honest bridge.
```

Line 33:

```text
/ `showHome` is also the welcome window's exit — its "Open Console" button
```

Line 34:

```text
/ lands on Home, the one place that can honestly say "start here".
```

Line 43:

```text
/ Runs a command line in the window's terminal panel. Carries
```

Line 44:

```text
/ `userInfoCommand`, `userInfoDirectory` and `userInfoSubject`.
```

Line 58:

```text
/ "self" or a `DeviceRecord.id`. The first column's selection.
```

Line 61:

```text
/ Home is a *destination*, not another module: the module indices and
```

Line 62:

```text
/ their ⌘1…⌘n equivalents stay exactly where they were, and every
```

Line 63:

```text
/ inspector that switches exhaustively over `ConsoleModule` keeps
```

Line 64:

```text
/ compiling. The window opens on Overview. `module` still remembers where
```

Line 65:

```text
/ you were, so leaving home and coming back does not reset it.
```

Line 68:

```text
/ The active module for the selected device.
```

Line 70:

```text
/ Overview controls belong to the window ribbon, not a second row inside
```

Line 71:

```text
/ the module. Window-scoped state keeps those controls and the charts in
```

Line 72:

```text
/ sync while preserving the selection across navigation.
```

Line 75:

```text
/ The process module's presentation belongs to window navigation state so
```

Line 76:

```text
/ its selector can live in the native toolbar instead of spending a second
```

Line 77:

```text
/ horizontal band inside the module. Keeping it here also preserves the
```

Line 78:

```text
/ choice while someone checks another module and returns.
```

Line 91:

```text
/ Toolbar search. Applies to the module in view — processes, services and
```

Line 92:

```text
/ events each decide what fields it matches.
```

Line 95:

```text
/ The local console uses the full viewport. Device navigation remains
```

Line 96:

```text
/ available through the native sidebar toggle.
```

Line 101:

```text
/ Whether the inspector column is wanted. The leading sidebar has had a
```

Line 102:

```text
/ toggle since the toolbar bridged onto NSToolbar — AppKit supplies it —
```

Line 103:

```text
/ but the trailing column had none, so the one column that is a *view of
```

Line 104:

```text
/ your selection* could only be taken away by the window getting narrow.
```

Line 105:

```text
/ That is a layout accident standing in for a control. This is the intent;
```

Line 106:

```text
/ width can still overrule it, never the other way round.
```

Line 108:

```text
/ Actual visibility, published by the root layout for the titlebar control.
```

Line 111:

```text
/ True for the duration of a window-edge drag.
```

Line 113:

```text
/ Every animated dimension in this window is a function of the content
```

Line 114:

```text
/ width — the two side columns, the module column, every treemap tile's
```

Line 115:

```text
/ rectangle — and those animations exist for *discrete* causes: a column
```

Line 116:

```text
/ toggled, a tool panel revealed, a squarified map reordering because a
```

Line 117:

```text
/ process grew. A drag is not a discrete cause. It is sixty new target
```

Line 118:

```text
/ values a second, each one restarting a spring that was still settling
```

Line 119:

```text
/ toward the last, so the layout lags behind the pointer, keeps catching
```

Line 120:

```text
/ up, and never arrives while you are still dragging.
```

Line 122:

```text
/ That is what made resizing feel springy and chewy rather than direct.
```

Line 123:

```text
/ AppKit already knows when a drag is in progress and says so through
```

Line 124:

```text
/ `windowWillStartLiveResize` / `windowDidEndLiveResize`; this carries that
```

Line 125:

```text
/ answer into SwiftUI, where `\.isLiveResizing` suppresses layout animation
```

Line 126:

```text
/ for the length of the gesture. Nothing about the *resting* animations
```

Line 127:

```text
/ changes — open the inspector and the columns still slide.
```

Line 130:

```text
/ Selection state, one per module, so switching modules never loses your
```

Line 131:

```text
/ place — the behaviour Finder and Music both have.
```

Line 134:

```text
/ The storage module's *other* selection: a breakdown segment (bar stripe
```

Line 135:

```text
/ or legend chip). Kept apart from `selectedVolumeID` because the two are
```

Line 136:

```text
/ reconciled against different lists — volume ids are mount paths, segment
```

Line 137:

```text
/ ids are `StorageCategory` values — and validating a segment against the
```

Line 138:

```text
/ mount table cleared it on the next process sample.
```

Line 143:

```text
/ Process-list scope filter.
```

Line 154:

```text
/ The scope filter is the "advanced heatmap filters" premium feature:
```

Line 155:

```text
/ the process table's own filter is also the heatmap's, because the
```

Line 156:

```text
/ heatmap is drawn from the filtered rows. `all` — the unfiltered
```

Line 157:

```text
/ view — is free; everything that narrows it is not.
```

Line 180:

```text
MARK: - Chrome copy
```

Line 182:

```text
The search placeholder and the inspector's empty hint both describe *the
```

Line 183:

```text
surface you are on*, so they are derived here, once, from the state that
```

Line 184:

```text
decides it. They used to be written twice — `RootView.searchPrompt` and
```

Line 185:

```text
`InspectorPanel.prompt` held two copies of the same switch — and only the
```

Line 186:

```text
inspector's was ever on screen, because the search field bridges into the
```

Line 187:

```text
toolbar from that column. Editing the other one changed nothing, silently.
```

Line 188:

```text
Same failure the toolbox exists to prevent, in prose instead of colour.
```

Line 190:

```text
/ The search field's placeholder. No trailing ellipsis: macOS reserves that
```

Line 191:

```text
/ for a control that opens something needing more input, and in a
```

Line 192:

```text
/ placeholder it reads as a hint that was itself truncated.
```

Line 206:

```text
/ What the inspector says when nothing is selected. Home is handled first:
```

Line 207:

```text
/ it is not a module, so falling through to `module` here described whatever
```

Line 208:

```text
/ surface you had visited last — the inspector offered to inspect "a launch
```

Line 209:

```text
/ entry" while Home was on screen.
```

Line 227:

```text
MARK: - Destinations
```

Line 229:

```text
Home is what needs attention; a module is a specific process. Navigation
```

Line 230:

```text
is therefore one-way work: home hands you off to a module with the row
```

Line 231:

```text
already selected, and the module keeps that selection when you come back.
```

Line 253:

```text
/ Drill down from a priority row to the surface that can act on it. The
```

Line 254:

```text
/ daemon's `AttentionItem` already says what it is about, so the routing
```

Line 255:

```text
/ reads that rather than re-deriving priority from the raw records.
```

Line 269:

```text
Device items carry no id field of their own; match by the id the
```

Line 270:

```text
controller builds rather than parsing the string, so a change to that
```

Line 271:

```text
format fails to match instead of selecting the wrong node.
```

Line 277:

```text
Controller-level items — a crash loop in fleetd itself — have no row
```

Line 278:

```text
anywhere, because the controller restarting leaves no service behind.
```

Line 279:

```text
The append-only log is the only place that fact is evidenced.
```

Line 283:

```text
MARK: - Inspector routing
```

Line 287:

```text
Home borrows the inspector for whatever its selected priority row is
```

Line 288:

```text
about, so reading an attention item does not cost a navigation.
```

Line 311:

```text
/ Compact work rows inspect in place rather than sending the user to
```

Line 312:

```text
/ another module. Clear competing selection so the target is unambiguous.
```

Line 329:

```text
MARK: - Storage selection
```

Line 331:

```text
Two kinds of selection, one inspector. Setting either clears the other —
```

Line 332:

```text
the inspector shows one thing, and a stale pair would decide which by
```

Line 333:

```text
accident of evaluation order.
```

Line 345:

```text
MARK: - Selection hygiene
```

Line 347:

```text
Live data deletes things: a process exits, a service stops, a volume
```

Line 348:

```text
unmounts. A selection pointing at a dead row must clear itself or the
```

Line 349:

```text
inspector renders a ghost. Called from the root view's onChange handlers.
```

Line 364:

```text
A segment is only stale once the breakdown has actually been scanned;
```

Line 365:

```text
before that the segment list is empty and a selection made from a
```

Line 366:

```text
previous scan's bar would be cleared for no reason.
```

Line 377:

```text
/ What the Esc key does, in order: clear search, then clear the module
```

Line 378:

```text
/ selection. Returns false when there was nothing to clear.
```

Line 382:

```text
Home's rows navigate rather than select, so there is nothing of its
```

Line 383:

```text
own to clear — clearing the module's selection here would silently
```

Line 384:

```text
undo a choice you cannot see.
```

Line 401:

```text
MARK: - Refresh
```

Line 403:

```text
/ The one place ⌘R and the toolbar button both call: everything the
```

Line 404:

```text
/ window shows, re-evidenced now.
```

Line 405:

```text
/ Everything the window can re-measure, because that is what the button says.
```

Line 407:

```text
/ The storage scan and the host probe were missing. Both are deliberately off
```

Line 408:

```text
/ the sampling timer — walking cache trees and ssh-probing every device costs
```

Line 409:

```text
/ real I/O, and a monitor that thrashes the disk to report disk usage is its
```

Line 410:

```text
/ own bug — but "not on a timer" was silently implemented as "not on demand
```

Line 411:

```text
/ either". `StorageScanner.rescan()` had no caller outside its own module,
```

Line 412:

```text
/ which ran it once on first appearance; every ⌘R after that left the Storage
```

Line 413:

```text
/ figures frozen at whatever they were the first time the module was opened.
```

Line 414:

```text
/ An explicit refresh *is* the on-demand case those probes were built for.
```

## Sources/FleetConsoleApp/Views/Console/ConsoleWindowController.swift

Line 5:

```text
The console window: native chrome for a SwiftUI content tree.
```

Line 7:

```text
The app bootstraps with AppKit (status items, single-instance handoff,
```

Line 8:

```text
SMAppService), so the window is built here rather than in a `WindowGroup`
```

Line 9:

```text
scene. Everything the scene API would configure is set explicitly:
```

Line 11:

```text
`.fullSizeContentView` + hidden title → the unified look, where the
```

Line 12:

```text
toolbar and content share one surface (Safari, Freeform, Xcode).
```

Line 13:

```text
`.unifiedCompact` toolbar style → the compact inline bar. SwiftUI's
```

Line 14:

```text
`.toolbar` content in `RootView` bridges onto the window's NSToolbar,
```

Line 15:

```text
including the automatic sidebar toggle.
```

Line 16:

```text
A titlebar accessory carries the controller connection status, so the
```

Line 17:

```text
one fact that changes what every number means is visible on every screen
```

Line 18:

```text
without spending content-column space on it.
```

Line 25:

```text
/ Internal rather than private so `SurfaceRenderer` can drive the module
```

Line 26:

```text
/ and selection while capturing the window. Nothing in the app writes it
```

Line 27:

```text
/ from outside — navigation still goes through `ConsoleCommand`.
```

Line 29:

```text
/ Held here, not in a view: the tool surfaces own child processes, and a
```

Line 30:

```text
/ terminal must outlive every SwiftUI rebuild of the tree that shows it.
```

Line 33:

```text
/ Appended on the main thread when the window is built, released in `deinit`.
```

Line 34:

```text
/ `deinit` is nonisolated in Swift 6 and the tokens are not Sendable, so the
```

Line 35:

```text
/ access is spelled out as unchecked.
```

Line 37:

```text
/ `NSWindow.delegate` is a weak reference, so the observer has to be owned
```

Line 38:

```text
/ somewhere that outlives the window's construction or it deallocates on
```

Line 39:

```text
/ the way out of `show()` and the window quietly has no delegate again.
```

Line 53:

```text
/ The two commands that say *where to be* are observed here, in AppKit, at
```

Line 54:

```text
/ init — not in `ConsoleRootView` alongside the rest.
```

Line 56:

```text
/ Every `ConsoleCommand` sender calls `openConsole()` and then posts, in the
```

Line 57:

```text
/ same turn. When the window is already up that is fine, and it was always
```

Line 58:

```text
/ fine in practice, because the only senders were ⌘-equivalents in the main
```

Line 59:

```text
/ menu and an `.accessory` app's main menu is live only while the app is
```

Line 60:

```text
/ active — which meant the window existed. The status item's dropdown is
```

Line 61:

```text
/ live with no window at all, so choosing **Processes** from a cold start
```

Line 62:

```text
/ now runs exactly the path that was never exercised: `show()` builds the
```

Line 63:

```text
/ hosting controller, the notification posts, and SwiftUI installs the
```

Line 64:

```text
/ `.onReceive` subscriptions at some later point of its own choosing. The
```

Line 65:

```text
/ window would have opened on Home.
```

Line 67:

```text
/ `console` exists from `init`, before any view does, so an observer here
```

Line 68:

```text
/ cannot be late. The commands that genuinely need the view — focusing the
```

Line 69:

```text
/ toolbar's search field, toggling a tool whose context is measured from the
```

Line 70:

```text
/ layout — stay in `ConsoleRootView`, and neither is reachable without a
```

Line 71:

```text
/ window to be late for.
```

Line 119:

```text
A hand-off to the designated agent arrives from the popover with no
```

Line 120:

```text
window up, so it is observed here for the same reason as the two above.
```

Line 167:

```text
The titlebar remains draggable. Treating the entire live dashboard as
```

Line 168:

```text
a drag region makes AppKit walk every chart/gauge path on each update.
```

Line 170:

```text
Resizes on both axes, with a floor on each and no ceiling.
```

Line 172:

```text
It used to be aspect-locked (`contentAspectRatio`) and capped at the
```

Line 173:

```text
composed size (`contentMaxSize`), on the argument that the console is
```

Line 174:

```text
"one composition at a range of sizes rather than a canvas that
```

Line 175:

```text
stretches". The argument is about the *layout*, and the layout holds
```

Line 176:

```text
it on its own: the side columns clamp between two rungs, the module
```

Line 177:

```text
column takes the remainder, and the cards flow in an adaptive grid
```

Line 178:

```text
that spends width when it has it. None of that needed the window's
```

Line 179:

```text
help. What the lock actually did was make dragging the right edge
```

Line 180:

```text
move the bottom edge, and make the window refuse to grow past its
```

Line 181:

```text
default on a display with room to spare — two behaviours no other Mac
```

Line 182:

```text
window has, on the surface you resize most.
```

Line 184:

```text
Both floors are derived rather than picked, because the last picked
```

Line 185:

```text
one here was wrong and unfalsifiable: it was "half the composed
```

Line 186:

```text
width", 780, against a column reserve of 786, so the window could be
```

Line 187:

```text
dragged to a size where the columns did not fit and the module column
```

Line 188:

```text
went under the width its own comment called a floor.
```

Line 189:

```text
`minimumContentWidth` is one side column, the module column, the rail
```

Line 190:

```text
and a tool panel's floor; `minimumContentHeight` is a module header
```

Line 191:

```text
and one whole card. `ConsoleLayoutTests` asserts one point under
```

Line 192:

```text
either does not fit.
```

Line 196:

```text
Full screen follows the lock. `.fullScreenNone` was set for one stated
```

Line 197:

```text
reason — the window is "one composition at a range of sizes, not a
```

Line 198:

```text
canvas that stretches" — and that reason was the aspect lock, which
```

Line 199:

```text
is gone. Keeping the restriction and citing a constraint that no
```

Line 200:

```text
longer exists is the same decay rule 9 is about, one layer under the
```

Line 201:

```text
prose. The View menu gains its Full Screen item in the same change,
```

Line 202:

```text
which is what rule 10 requires: the chrome and the capability move
```

Line 203:

```text
together, in either direction.
```

Line 206:

```text
Deliberately no frame autosave: a saved frame from a previous build
```

Line 207:

```text
would restore a size this one does not support.
```

Line 210:

```text
No titlebar status pill. "fleetd 1.0.0 · up 1d 0h" is a version string
```

Line 211:

```text
and an uptime — neither is a thing you act on, and the sidebar's own
```

Line 212:

```text
footer already carries whether the controller is connected, which is
```

Line 213:

```text
the part that matters. It was decoration occupying the ribbon's most
```

Line 214:

```text
valuable corner.
```

Line 216:

```text
The delegate exists for exactly one question: is the user dragging an
```

Line 217:

```text
edge right now. Everything animated in this window is a function of
```

Line 218:

```text
the content width, so without this the whole composition springs
```

Line 219:

```text
after the pointer instead of tracking it. See `LiveResizeObserver`.
```

Line 234:

```text
SwiftUI's split view can fit the window to its content's minimum on
```

Line 235:

```text
first show; assert the intended default size afterwards so the
```

Line 236:

```text
console never opens cramped.
```

Line 241:

```text
/ Keep the system toolbar and the SwiftUI scene on one continuous glass
```

Line 242:

```text
/ field while guaranteeing that the window itself remains opaque.
```

Line 243:

```text
/ Internal so the release contract is testable without opening the live
```

Line 244:

```text
/ dashboard and starting its refresh cycle.
```

Line 252:

```text
/ Reserve the right titlebar edge independently of SwiftUI toolbar ordering.
```

Line 253:

```text
/ The same command is used by this control and the View menu shortcut.
```

Line 281:

```text
MARK: - Live resize
```

Line 283:

```text
/ Reports whether a window-edge drag is in progress.
```

Line 285:

```text
/ AppKit has always known this — `inLiveResize` on the view, and these two
```

Line 286:

```text
/ delegate callbacks around the gesture — and SwiftUI has no equivalent. The
```

Line 287:

```text
/ window had no delegate at all, so the answer was there and nobody asked for
```

Line 288:

```text
/ it, and every spring in the console ran against a width that was changing
```

Line 289:

```text
/ sixty times a second.
```

Line 291:

```text
/ A separate object rather than conformance on `ConsoleWindowController`,
```

Line 292:

```text
/ because `NSWindowDelegate` is a wide protocol and the controller adopting it
```

Line 293:

```text
/ would be an invitation to answer other questions here later. This one
```

Line 294:

```text
/ answers one.
```

Line 308:

```text
The final size lands with this callback, so clearing the flag here
```

Line 309:

```text
means the last frame of the drag is unanimated too. Anything that
```

Line 310:

```text
should* animate — a column toggled while the pointer was down — is
```

Line 311:

```text
keyed on its own discrete value and is unaffected.
```

## Sources/FleetConsoleApp/Views/Console/DashboardWorkspaces.swift

Line 7:

```text
/ Legacy operations stay intact, grouped under one destination.
```

Line 78:

```text
/ A bounded ego graph: only observed parent/child links, never inferred causal edges.
```

Line 168:

```text
/ The main workspace is the agent-awareness map and directory substrate.
```

Line 179:

```text
/ Area is resident memory and colour is CPU. Search matches the process table:
```

Line 180:

```text
/ name or command line. Tiles still open the heaviest process.
```

Line 239:

```text
/ CPU interval selection joins only real retained process observations by timestamp.
```

Line 243:

```text
/ The overview page already scrolls. A nested scroll traps the interval chart.
```

Line 245:

```text
/ The instrument graphs are the page above this chart. The sheet is the
```

Line 246:

```text
/ standalone entry, used only when this workspace is the whole column.
```

## Sources/FleetConsoleApp/Views/Console/DeviceDetailView.swift

Line 4:

```text
Column two for a remote node: what the machine *is*, proven by probes.
```

Line 6:

```text
FleetConsole never controls a remote process — it reports one. Everything on
```

Line 7:

```text
this screen is read-only evidence: the capability probe (SSH, fixed argv,
```

Line 8:

```text
BatchMode so a password prompt fails instead of hanging), the link probe
```

Line 9:

```text
(`tailscale ping`, worst sample not the mean), and the services that node's
```

Line 10:

```text
own controller manages, fetched read-only.
```

Line 48:

```text
MARK: Health evidence
```

Line 52:

```text
The device is named by the card that proves it is there, not by
```

Line 53:

```text
a page heading above it.
```

Line 93:

```text
MARK: Capabilities
```

Line 138:

```text
MARK: Remote services
```

Line 194:

```text
MARK: - Bits
```

Line 196:

```text
/ One evidence fact: name, state, and the measurement behind the state.
```

## Sources/FleetConsoleApp/Views/Console/DirectoryCrystal.swift

Line 4:

```text
/ A bounded metadata observation, not a dependency graph. Every branch is an
```

Line 5:

```text
/ observed immediate directory relationship; exclusions are reported separately.
```

Line 33:

```text
/ Automatic workspace discovery avoids privacy prompts. A folder chosen
```

Line 34:

```text
/ through the native picker is an explicit metadata scope, not an OS grant.
```

Line 96:

```text
Default discovery never requests private-folder/volume access. Native
```

Line 97:

```text
picker selections define a read-only metadata scope; OS grants still apply.
```

Line 102:

```text
/ Walk every component relative to an open descriptor. O_NOFOLLOW also
```

Line 103:

```text
/ rejects symlink roots and symlink ancestors, including a swap race.
```

Line 125:

```text
Do not resolve symlinks or silently reinterpret relative paths.
```

Line 138:

```text
Finish all actual priority chains globally, then expansion windows,
```

Line 139:

```text
before ordinary folders. Cached enumeration shares one entry budget.
```

Line 255:

```text
Revalidate against a concurrent replacement before admitting it.
```

Line 286:

```text
Swift's randomized Hasher must not affect persistent geometry.
```

## Sources/FleetConsoleApp/Views/Console/DirectoryCrystalLayer.swift

Line 3:

```text
/ The faceted substrate encodes folder containment. Filled sibling fans are
```

Line 4:

```text
/ grouping planes, never extra dependency edges between sibling directories.
```

## Sources/FleetConsoleApp/Views/Console/DirectoryCrystalStore.swift

Line 5:

```text
/ Folder metadata follows the existing process-observation pulse. A root change
```

Line 6:

```text
/ or explicit expansion cancels the obsolete scan; there is no extra timer.
```

## Sources/FleetConsoleApp/Views/Console/EventsModule.swift

Line 4:

```text
Module: Events — the append-only log, filterable.
```

Line 6:

```text
The registry's event table rejects UPDATE and DELETE; this view honours that
```

Line 7:

```text
by being a pure projection. Timestamps are HH:mm:ss in mono digits because
```

Line 8:

```text
this is where ordering disputes get settled, and bad events carry their
```

Line 9:

```text
tone through shape (octagon/triangle) as well as colour.
```

Line 58:

```text
The table sits on the page like every other surface: without
```

Line 59:

```text
this it paints AppKit's own table background over the field and
```

Line 60:

```text
the module reads as a panel dropped on top of the window rather
```

Line 61:

```text
than as part of it.
```

## Sources/FleetConsoleApp/Views/Console/FleetSidebarView.swift

Line 4:

```text
Column one: the fleet mesh.
```

Line 6:

```text
"This Mac" is pinned at the top because it is the device every local module
```

Line 7:

```text
describes. Below it, the remote nodes with the evidence that matters before
```

Line 8:

```text
you trust a number from them: are they reachable *at all*, over which path,
```

Line 9:

```text
and at what latency. Reachability, latency and encryption are three separate
```

Line 10:

```text
facts and are drawn as three separate affordances — a green dot over a
```

Line 11:

```text
relayed 180 ms path is a different machine from a green dot over direct 4 ms.
```

Line 19:

```text
Keep both the awareness canvas and the detailed operations map reachable.
```

Line 49:

```text
The mesh shares the window-wide glass field. Letting List install its
```

Line 50:

```text
own scroll backdrop would turn the sidebar into a second material
```

Line 51:

```text
layer and break the scene at the split-view seam.
```

Line 54:

```text
The column width is set by `ConsoleRootView`, not here: the resting
```

Line 55:

```text
width is the golden section of whatever the split view has to divide,
```

Line 56:

```text
which is a function of the window and of whether a tool panel is open.
```

Line 57:

```text
This view cannot see either, and the number it used to declare was the
```

Line 58:

```text
half of the mirror that drifted — 236/268/320 against the inspector's
```

Line 59:

```text
280/320/420.
```

Line 65:

```text
/ The bottom-left corner: the app, the account, and the links the window
```

Line 66:

```text
/ footer used to carry. The live line stays quiet unless the controller is
```

Line 67:

```text
/ down, which is the one fact here that changes what the window can do.
```

Line 113:

```text
MARK: - Remote node
```

Line 129:

```text
The badge, not just the tint. `detailLine` states the *path* to a
```

Line 130:

```text
node — "tailnet · ssh :22" — and never its health, so in the one
```

Line 131:

```text
column that is always on screen, reachability used to live in the
```

Line 132:

```text
pip's hue and nowhere else. Desaturate the sidebar and all four
```

Line 133:

```text
health states looked identical. The badge carries a verdict glyph,
```

Line 134:

```text
and appears only when something is off, so a reachable node stays
```

Line 135:

```text
clean.
```

Line 140:

```text
Name and latency share the first line and the route takes the
```

Line 141:

```text
second, so the name gets the row's width instead of a third
```

Line 142:

```text
column of pip and badge squeezing it to "demo-stu…". Health is
```

Line 143:

```text
the icon's badge, which appears only when something is off.
```

Line 179:

```text
/ Path and encryption as one glanceable line: the transport (Tailscale or
```

Line 180:

```text
/ LAN) and the probe channel (SSH). A node you reach through an encrypted
```

Line 181:

```text
/ mesh over SSH reads differently from a bare LAN ping, and should.
```

Line 182:

```text
/ The model name is deliberately absent. This line exists to say *how the
```

Line 183:

```text
/ node is reached* — the transport and the probe channel — and the sidebar
```

Line 184:

```text
/ gives it about 130pt. With the model in front, "Intel · tailnet · ssh :22"
```

Line 185:

```text
/ overran that and truncated to "Intel · t… · ssh :22", destroying the one
```

Line 186:

```text
/ token the line is for. The machine is already identified twice above it,
```

Line 187:

```text
/ by the row's name and by its icon, and the full model is in the inspector.
```

## Sources/FleetConsoleApp/Views/Console/HeatmapView.swift

Line 4:

```text
One heatmap engine for every map in the console.
```

Line 6:

```text
The first operations map shipped its own layout; the storage map was about
```

Line 7:

```text
to grow a second. There is now one: a squarified (Bruls–Huizing–van Wijk)
```

Line 8:

```text
treemap, because the naive slice-and-dice layout degenerates into slivers,
```

Line 9:

```text
and a sliver is neither readable nor clickable.
```

Line 11:

```text
Encoding rules, applied to both maps:
```

Line 13:

```text
**Area is the quantity.** Area is the only visual channel people read
```

Line 14:

```text
accurately without a legend, and "where did it go" is always an area
```

Line 15:

```text
question.
```

Line 16:

```text
**Colour never repeats area.** On the disk map colour is the storage
```

Line 17:

```text
category; on the process map it is CPU activity (the market-cap/day's-
```

Line 18:

```text
move rule — size says how much, colour says whether to act).
```

Line 19:

```text
**Every byte is accounted for.** A capped tail and small entries roll
```

Line 20:

```text
into a remainder tile rather than vanishing, so the map's areas sum to
```

Line 21:

```text
the number above it.
```

Line 22:

```text
**Labels only where they fit.** Hover and the readout line carry the
```

Line 23:

```text
rest; a truncated word in a 20pt tile is noise.
```

Line 25:

```text
MARK: - Model
```

Line 28:

```text
/ What tapping the tile does.
```

Line 30:

```text
/ Reveal this path in Finder.
```

Line 32:

```text
/ Select this pid in the Processes module.
```

Line 34:

```text
/ Informational only (remainder tiles).
```

Line 40:

```text
/ Secondary line for the readout (path, process count…).
```

Line 42:

```text
/ Area.
```

Line 44:

```text
/ Category or tone colour — never size.
```

Line 47:

```text
/ Roll-up tile: small entries, the capped tail. Drawn dimmed.
```

Line 53:

```text
MARK: - Squarified layout
```

Line 56:

```text
/ Frames for `values` packed into `rect`, one per value, in input order.
```

Line 57:

```text
/ Degenerate input yields an empty array, never NaN frames.
```

Line 73:

```text
Grow the current row while adding the next tile *improves* the
```

Line 74:

```text
row's worst aspect ratio — the entire trick in one comparison.
```

Line 91:

```text
/ The row's worst side ratio, in the closed Bruls form: for a row of area
```

Line 92:

```text
/ R laid along a side of length s, the extremes depend only on the row's
```

Line 93:

```text
/ largest and smallest tile.
```

Line 108:

```text
/ Commits one row: a vertical strip down the left when the remaining
```

Line 109:

```text
/ space is wider than tall, a horizontal strip across the top otherwise.
```

Line 137:

```text
MARK: - View
```

Line 141:

```text
/ The honesty line shown when nothing is hovered.
```

Line 143:

```text
/ Live process samples should not animate dozens of tile frames each tick.
```

Line 155:

```text
/ Tiles move on their own frame, not on the data.
```

Line 157:

```text
/ The map used to carry one `.animation(_:value: items)` on the stack
```

Line 158:

```text
/ outside the `GeometryReader`, which animated a *data* change and nothing
```

Line 159:

```text
/ else. Every tile's rectangle is computed from `geometry.size` inside that
```

Line 160:

```text
/ reader, so resizing the window, opening the inspector or dragging a tool
```

Line 161:

```text
/ panel changed all forty rectangles with `items` untouched — the one value
```

Line 162:

```text
/ being watched — and the whole map snapped to its new layout in a single
```

Line 163:

```text
/ frame. That is the case you actually see most often, and it was the one
```

Line 164:

```text
/ case not animated.
```

Line 166:

```text
/ Keying each tile on its own `frame` covers both causes with one rule,
```

Line 167:

```text
/ because a squarified relayout *is* a set of frame changes whatever
```

Line 168:

```text
/ provoked it.
```

Line 170:

```text
A live drag is the third case, and it was the one this rule got
```

Line 171:

```text
wrong. Keying tiles on their own frame was right — a squarified
```

Line 172:

```text
relayout *is* a set of frame changes — but a resize changes all forty
```

Line 173:

```text
rectangles on every frame of the gesture, so a 0.55s spring was being
```

Line 174:

```text
restarted forty times over, sixty times a second. The map turned to
```

Line 175:

```text
jelly under the pointer, which is the most visible thing in the
```

Line 176:

```text
window and the reason resizing felt chewy. The container is already
```

Line 177:

```text
tracking the drag directly; the tiles inside it have to as well.
```

Line 197:

```text
Tiles entering and leaving — a process starting, a scan finishing —
```

Line 198:

```text
still fade rather than blink into existence. The movement of the ones
```

Line 199:

```text
that stay is the tile's own business, above.
```

Line 203:

```text
MARK: Tile
```

Line 213:

```text
The tile is drawn inside its computed rectangle, not on it. Neighbours
```

Line 214:

```text
are separated by a channel of the card behind them rather than by a
```

Line 215:

```text
stroke, which is what makes a mass read as a mass:
```

Line 217:

```text
A 0.5pt edge at 18% black — what this drew before — is invisible
```

Line 218:

```text
against the saturated fills and nearly invisible in dark mode, so
```

Line 219:

```text
two adjacent green tiles of similar size merged into one shape and
```

Line 220:

```text
the map lost exactly the boundary it exists to show.
```

Line 221:

```text
A heavier stroke would only trade that for a grid of dark lines
```

Line 222:

```text
over a map whose subject is area.
```

Line 223:

```text
A gutter costs no colour decision at all, survives both
```

Line 224:

```text
appearances and every fill the maps can produce, and lands on
```

Line 225:

```text
whole pixels at any scale factor, so the edges stay crisp instead
```

Line 226:

```text
of half-covering a pixel row.
```

Line 228:

```text
It is also the honest encoding. Every tile gives up the same margin,
```

Line 229:

```text
so the *ratios* between masses — the only thing a treemap actually
```

Line 230:

```text
claims — are preserved, while no tile pretends its rectangle is a
```

Line 231:

```text
measurement you could read a byte count off.
```

Line 238:

```text
Two-ply ring: see `ConsoleColor.tileHoverRing`. A single
```

Line 239:

```text
ink cannot survive both a saturated fill and a pale grey.
```

Line 288:

```text
Tiles act — reveal in Finder, select the pid — so they have to be
```

Line 289:

```text
buttons to VoiceOver too. A tap gesture is invisible to it, which put
```

Line 290:

```text
the map's whole way-in behind a pointer. Remainder tiles do nothing
```

Line 291:

```text
and say so by not claiming the trait.
```

Line 297:

```text
/ What activating the tile does, said before it happens.
```

Line 306:

```text
MARK: Readout
```

## Sources/FleetConsoleApp/Views/Console/InspectorPanel.swift

Line 4:

```text
Column three: the inspector. A view *of* the current selection — never a
```

Line 5:

```text
selection of its own (see `InspectorTarget`). The empty state names what it
```

Line 6:

```text
is waiting for, per module, instead of showing a grey void.
```

Line 17:

```text
Bounded like the sidebar is — under ~280pt every value truncates, and
```

Line 18:

```text
past ~420pt the column stops being a margin note and starts competing
```

Line 19:

```text
with the module it is annotating. The bounds themselves are applied by
```

Line 20:

```text
`ConsoleRootView`.
```

Line 44:

```text
/ Composed from the app's own primitive rather than `ContentUnavailableView`.
```

Line 46:

```text
/ The system view was corrupting this text. At the inspector's old 320pt it
```

Line 47:

```text
/ read correctly; the moment the two side columns were mirrored onto the
```

Line 48:

```text
/ same 283pt it rendered as "P c:i a qr e s s in the n a to inspect it." —
```

Line 49:

```text
/ glyphs drawn on advances measured for a different layout pass. Removing
```

Line 50:

```text
/ the caption-font override on the description did not fix it, which is the
```

Line 51:

```text
/ part worth recording: the corruption is in how that container measures a
```

Line 52:

```text
/ wrapping description at a width it did not expect, not in the font.
```

Line 54:

```text
/ `EmptyPanelView` is the app's own empty state — the one the chrome panels
```

Line 55:

```text
/ have always used, and the one place `ConsoleFont.emptyGlyph` was written
```

Line 56:

```text
/ for. It carries `fixedSize(horizontal: false, vertical: true)`, which is
```

Line 57:

```text
/ the incantation that makes a centred, wrapping caption measure its own
```

Line 58:

```text
/ height honestly, and it renders correctly at every column width. It was
```

Line 59:

```text
/ called `ToolUnavailableView` until this used it; the name was about where
```

Line 60:

```text
/ it happened to be first, not what it is.
```

Line 68:

```text
MARK: - Device inspector
```

Line 70:

```text
/ Column three for a remote node: how you reach it, at what quality, and what
```

Line 71:

```text
/ it is carrying. Read-only, like everything else across the mesh.
```

## Sources/FleetConsoleApp/Views/Console/MainMenu.swift

Line 4:

```text
The application's main menu.
```

Line 6:

```text
The app is AppKit-bootstrapped (status items predate the console window, and
```

Line 7:

```text
`MenuBarExtra` cannot render the custom summary glyphs those items use), so
```

Line 8:

```text
there is no SwiftUI scene to hang `CommandGroup` on. This is the same
```

Line 9:

```text
contract expressed in AppKit: named commands, standard key equivalents,
```

Line 10:

```text
routed through `ConsoleCommand` notifications the console window observes.
```

Line 12:

```text
Navigation opens the dashboard before posting its destination command. The
```

Line 13:

```text
window controller installs those observers at init, before SwiftUI renders.
```

Line 15:

```text
/ `@MainActor` on the enum rather than each member: every function here touches
```

Line 16:

```text
/ `NSApp`, `NSMenu` or `NSMenuItem`. The isolation was always required.
```

Line 31:

```text
MARK: Application
```

Line 54:

```text
MARK: Edit
```

Line 56:

```text
Standard responder-chain items. Without an Edit menu, ⌘C/⌘V/⌘A stop
```

Line 57:

```text
working inside text fields — including the toolbar search field — which
```

Line 58:

```text
is the kind of bug that makes an app feel not-native before you can say
```

Line 59:

```text
why.
```

Line 77:

```text
MARK: View
```

Line 86:

```text
"Open Dashboard", not "Show Console". One command had three labels —
```

Line 87:

```text
this menu said Show Console, the status-item dropdown said Open
```

Line 88:

```text
Dashboard…, and the popover footer's button said Open Dashboard —
```

Line 89:

```text
which reads as three destinations to anyone who has not opened all
```

Line 90:

```text
three. README documents it as Open Dashboard (⌘0), so that is the name.
```

Line 99:

```text
Attention is the landing surface, so it sits above the modules — but it is
```

Line 100:

```text
not one of them, which is why it takes a shifted equivalent and leaves
```

Line 101:

```text
⌘1…⌘n bound to exactly the module indices, whatever their count.
```

Line 108:

```text
The chrome tools. `ConsoleTool.shortcut` is the declared key and this
```

Line 109:

```text
is the only place it is bound, so the rail's tooltips and the menu
```

Line 110:

```text
cannot drift apart.
```

Line 140:

```text
The inspector's menu entry. The sidebar's toggle comes free from
```

Line 141:

```text
AppKit; the trailing column's does not, so both halves of the window
```

Line 142:

```text
are reachable from the keyboard by the same route.
```

Line 151:

```text
There was no Full Screen item here for as long as the window set
```

Line 152:

```text
`.fullScreenNone`, and that was correct: AppKit would never have
```

Line 153:

```text
validated `toggleFullScreen:`, so the entry could only ever render
```

Line 154:

```text
grey, which is rule 10 exactly. The window resizes freely on both
```

Line 155:

```text
axes now and takes `.fullScreenPrimary`, so the capability is real
```

Line 156:

```text
and the chrome comes back with it. `toggleFullScreen:` is AppKit's
```

Line 157:

```text
own responder-chain action — nil target, no shim.
```

Line 166:

```text
MARK: Shared items
```

Line 186:

```text
/ The console modules as menu items, generated from `ConsoleModule.allCases`
```

Line 187:

```text
/ and targeted at the shared action object.
```

Line 189:

```text
/ Built once and used twice — the View menu and the status item's dropdown.
```

Line 190:

```text
/ The dropdown previously offered no route to a module at all: reaching the
```

Line 191:

```text
/ process table from the menu bar meant opening the dashboard and then
```

Line 192:

```text
/ finding it, on the app's most-used surface. Duplicating the loop over
```

Line 193:

```text
/ there would have meant two lists that drift the moment a module is added,
```

Line 194:

```text
/ which is the failure `shortcutIndex` and `allCases` exist to prevent, so
```

Line 195:

```text
/ there is one builder instead.
```

Line 197:

```text
/ The equivalents shown are the real ones. They are live whenever the app is
```

Line 198:

```text
/ active — the deployment is `.accessory`, so that means the console window
```

Line 199:

```text
/ is focused, which is the only context in which selecting a module means
```

Line 200:

```text
/ anything anyway.
```

Line 213:

```text
MARK: Window
```

Line 239:

```text
/ Setup reads the current bundle rather than assuming an installation path or
```

Line 240:

```text
/ modifying the person's shell. Copying the quoted command never executes it.
```

Line 284:

```text
/ Obj-C reachable target for menu items. Menus outlive any one window, so the
```

Line 285:

```text
/ target is a shared instance rather than a view controller.
```

Line 287:

```text
/ `@MainActor` states what AppKit guarantees: menu actions dispatch on the main
```

Line 288:

```text
/ thread, and `openConsole` is installed from `applicationDidFinishLaunching`.
```

## Sources/FleetConsoleApp/Views/Console/OverviewModule.swift

Line 4:

```text
CPU and memory are the primary instruments. Time zoom preserves individual
```

Line 5:

```text
observations; focusing one metric gives it the full width and a taller plot.
```

Line 6:

```text
Secondary instruments have a glance and a sheet, never an expanding main page.
```

Line 9:

```text
/ Read for one reason: the toolbar's search field is present on this module
```

Line 10:

```text
/ and nothing here used to consume it. Typing a process name — the obvious
```

Line 11:

```text
/ thing to type while looking at a process map — filtered nothing and gave
```

Line 12:

```text
/ no sign it had done nothing, which reads as a frozen window rather than
```

Line 13:

```text
/ as a field that does not apply here.
```

Line 25:

```text
`geometry.size` is already the unobscured module column: the
```

Line 26:

```text
toolbar's safe area is outside it, so nothing is subtracted twice.
```

Line 54:

```text
/ Detailed instruments have their own scrollable surface. Opening them must
```

Line 55:

```text
/ not move the primary traces or push the process actions below the window.
```

Line 118:

```text
MARK: Sensors
```

Line 176:

```text
MARK: CPU
```

Line 184:

```text
Nil until two tick samples have been differenced, which parks the
```

Line 185:

```text
needle instead of resting it on a confident zero.
```

Line 217:

```text
MARK: Memory
```

Line 225:

```text
Always sampled: a share of physical memory is a ratio of two
```

Line 226:

```text
absolute numbers, not a rate, so it needs no previous tick.
```

Line 228:

```text
The used figure in the units you act on sits with the pressure,
```

Line 229:

```text
so the facts under the trace stay one row wide or two rows tall.
```

Line 237:

```text
Wrapped rather than laid out in one row of five. At a grid cell's
```

Line 238:

```text
width the old row hyphenated "COMPRESSED" and then pushed the total
```

Line 239:

```text
off the card; a flow lays out as many as fit and moves the rest down
```

Line 240:

```text
one line, which is the same answer at any column count.
```

Line 247:

```text
MARK: Process map
```

Line 253:

```text
MARK: Disk
```

Line 259:

```text
Was `.neutral`, because throughput has no good or bad value. The
```

Line 260:

```text
dial reads capacity, which does — and it gets the early-warning
```

Line 261:

```text
band, since by the time a volume is 99% full macOS is failing
```

Line 262:

```text
writes rather than warning about them.
```

Line 267:

```text
The dial reads **capacity**, not throughput, and that is the one
```

Line 268:

```text
place the gauge and the card's trace show different quantities. It
```

Line 269:

```text
is deliberate: a needle needs a bounded scale, and byte rates are
```

Line 270:

```text
the genuinely unbounded series in this app — the reason the chart
```

Line 271:

```text
below it is the only logarithmic one. A dial whose full deflection
```

Line 272:

```text
meant "the fastest rate seen so far this session" would be a scale
```

Line 273:

```text
that silently rewrites itself, which is the failure the throughput
```

Line 274:

```text
chart's fixed floor already exists to avoid. Used space is bounded,
```

Line 275:

```text
it has a real redline, and it is the disk fact worth a glance.
```

Line 301:

```text
MARK: GPU
```

Line 309:

```text
Nil when the accelerator is present but withheld the key — the
```

Line 310:

```text
honest reading is "not reported", never an idle GPU.
```

Line 329:

```text
MARK: Network and power
```

Line 394:

```text
MARK: - Process preview
```

Line 396:

```text
/ Filter first, then cap a memory ranking. The complete table and inspector
```

Line 397:

```text
/ keep their existing navigation paths instead of being duplicated here.
```

Line 430:

```text
The ranking key, marked where the eye reads the column.
```

Line 480:

```text
MARK: - Secondary glance
```

Line 482:

```text
/ Small current readings remain on Overview; their full charts and hardware
```

Line 483:

```text
/ facts belong to the adjacent Details action. Absence is never an idle zero.
```

Line 542:

```text
MARK: - Shared bits
```

Line 544:

```text
/ App / Wired / Compressed / Swap: one row where it fits, two rows of two where
```

Line 545:

```text
/ it does not — never three, which made the memory card set its row's height
```

Line 546:

```text
/ and left the CPU card beside it with a band of nothing under its cores.
```

Line 579:

```text
A four-column row of these divides the card evenly, which gives
```

Line 580:

```text
"COMPRESSED" less width than it needs at the kerned badge size —
```

Line 581:

```text
and SwiftUI's default response is to hyphenate, so the card read
```

Line 582:

```text
"COM-PRESSED" stacked over its number. A label that is one word is
```

Line 583:

```text
one line: it holds its intrinsic width and the row distributes
```

Line 584:

```text
what is left, rather than the longest label being broken to keep
```

Line 585:

```text
four columns nominally equal.
```

Line 601:

```text
/ The row a module opens with when it has controls, and only then.
```

Line 603:

```text
/ No title, no subtitle, no symbol. The sidebar's selection already names the
```

Line 604:

```text
/ page, so a heading restating it was a second toolbar spending the height the
```

Line 605:

```text
/ content needs. What is left is what the row is for: the controls that change
```

Line 606:

```text
/ the page, leading and trailing, on one line that never wraps.
```

## Sources/FleetConsoleApp/Views/Console/PlistsModule.swift

Line 4:

```text
Module: Launch Services — launchd agents, daemons, and their plists.
```

Line 6:

```text
Three scopes, each from a well-known directory that launchd reads at login
```

Line 7:

```text
or boot:
```

Line 9:

```text
~/Library/LaunchAgents        — current user, user-session scope
```

Line 10:

```text
/Library/LaunchAgents         — all users, user-session scope
```

Line 11:

```text
/Library/LaunchDaemons        — system scope (root) — loaded at boot
```

Line 13:

```text
This module is read-only throughout. It never loads, unloads, or modifies
```

Line 14:

```text
a plist — visibility with no escalation. The design principle is the same
```

Line 15:

```text
one the services module follows: a process launched by someone else gets
```

Line 16:

```text
"Reveal in Finder" and nothing else. The same applies to launchd jobs.
```

Line 18:

```text
What it surfaces:
```

Line 19:

```text
- Label, run-at-load flag, program (or program arguments), keepalive
```

Line 20:

```text
flag, and whether the job appears loaded per `launchctl list`.
```

Line 21:

```text
- The raw plist keys, all of them, shown in the inspector so nothing is
```

Line 22:

```text
hidden by a field mapping that hasn't been written yet.
```

Line 23:

```text
- The state from launchctl: loaded / not loaded / error reading.
```

Line 25:

```text
MARK: - Model
```

Line 27:

```text
/ A single plist key/value pair, used in the inspector.
```

Line 105:

```text
All plist keys, sorted, values as strings
```

Line 114:

```text
MARK: - Scanner
```

Line 134:

```text
Enrich with launchctl state.
```

Line 175:

```text
Flatten all keys to string pairs for the inspector.
```

Line 210:

```text
`launchctl list` returns every loaded job with its PID and status.
```

Line 211:

```text
The output format: PID | Status | Label, tab-separated, where `-`
```

Line 212:

```text
means no PID (not running but loaded).
```

Line 216:

```text
Parse into a dictionary: label → (pid, status)
```

Line 218:

```text
skip header
```

Line 274:

```text
MARK: - Module view
```

Line 342:

```text
The table sits on the page like every other surface: without
```

Line 343:

```text
this it paints AppKit's own table background over the field and
```

Line 344:

```text
the module reads as a panel dropped on top of the window rather
```

Line 345:

```text
than as part of it.
```

Line 373:

```text
MARK: - Row
```

## Sources/FleetConsoleApp/Views/Console/ProcessHeatmap.swift

Line 4:

```text
The process map: what is actually on the machine, as areas.
```

Line 6:

```text
The successor to the original operations map, rebuilt on the shared
```

Line 7:

```text
squarified engine with three concrete improvements:
```

Line 9:

```text
**Every byte is accounted for.** The old map drew its top 40 groups and
```

Line 10:

```text
silently dropped the rest; the tail now rolls into an "Other processes"
```

Line 11:

```text
tile, so the map's areas sum to the resident total it claims to show.
```

Line 12:

```text
**Tiles act.** Tapping a tile selects its heaviest process in the
```

Line 13:

```text
Processes module and opens its inspector — the map is a way in, not
```

Line 14:

```text
just a picture.
```

Line 15:

```text
**Grouping is honest about what it folds.** Helpers are collapsed onto
```

Line 16:

```text
their parent app (Activity Monitor's rule), and the tile's detail line
```

Line 17:

```text
says how many processes the tile represents.
```

Line 19:

```text
Encoding is unchanged because it was right: area is resident memory, colour
```

Line 20:

```text
is CPU activity. Size is the market cap, colour is the day's move — the tile
```

Line 21:

```text
that is both large *and* red is the one to act on.
```

Line 24:

```text
/ One tile per app group. Pure and nonisolated so the view body stays a
```

Line 25:

```text
/ projection; called with the inventory's current rows.
```

Line 53:

```text
Below 8 MB a group is texture at this zoom level; its bytes still
```

Line 54:

```text
count toward the remainder tile.
```

Line 59:

```text
Forty tiles is the most a map can show before the smallest becomes
```

Line 60:

```text
a sliver. The tail is rolled up, not dropped.
```

Line 90:

```text
The remainder is a *quantity with no CPU story*, which is
```

Line 91:

```text
exactly what the neutral tone means — it went through the same
```

Line 92:

```text
axis as every other tile rather than around it.
```

Line 100:

```text
/ Collapses "Foo Helper (Renderer)" and friends onto "Foo" — the app is
```

Line 101:

```text
/ the thing you act on, its fifteen helper processes are not fifteen
```

Line 102:

```text
/ tiles.
```

Line 113:

```text
MARK: - Label contrast on tone colours
```

Line 116:

```text
/ In-tile label colour for a tile filled with this tone's colour.
```

## Sources/FleetConsoleApp/Views/Console/ProcessInspector.swift

Line 5:

```text
Inspector: one process, deeply.
```

Line 7:

```text
Everything here is gathered the same way the rest of the app gathers facts:
```

Line 8:

```text
Mach/libproc for what the kernel will tell an unprivileged peer, `ps`/`lsof`
```

Line 9:

```text
for the rest. What macOS will not tell us — another user's environment, a
```

Line 10:

```text
root daemon's sockets — is labelled "not collected" rather than left blank,
```

Line 11:

```text
because a blank panel reads as a bug and a label reads as a policy.
```

Line 13:

```text
/ The kernel's account of one process, via `proc_pidinfo(PROC_PIDTASKINFO)`.
```

Line 14:

```text
/ Available for any process this user can see; thread *names* would need
```

Line 15:

```text
/ `task_threads`, which the kernel quite reasonably refuses for other users'
```

Line 16:

```text
tasks.
```

Line 56:

```text
/ The service that owns this pid, if the controller launched it.
```

Line 100:

```text
MARK: Header
```

Line 117:

```text
MARK: Identity
```

Line 130:

```text
MARK: Activity
```

Line 151:

```text
MARK: Tree
```

Line 156:

```text
Root-most ancestor first: [grandparent, parent], depth = position.
```

Line 178:

```text
Filled for you-are-here, hollow for the rest. Shapes rather than
```

Line 179:

```text
● / ○ glyphs, which sat on the text baseline and drifted with the
```

Line 180:

```text
font's own metrics.
```

Line 212:

```text
MARK: Network
```

Line 271:

```text
MARK: Environment
```

Line 295:

```text
MARK: Actions
```

Line 301:

```text
Claimed: supervised, reported on, and deliberately without a
```

Line 302:

```text
single control. The sentence is the card's whole content, which
```

Line 303:

```text
is the honest shape — there is nothing to press.
```

Line 351:

```text
MARK: - Shared inspector primitives
```

Line 353:

```text
/ The block at the top of every inspector: what you are looking at, and the one
```

Line 354:

```text
/ fact that qualifies it.
```

Line 356:

```text
/ There were five of these, hand-built, and they had already drifted — two
```

Line 357:

```text
/ spacings, three subtitle fonts, and a title that truncated in one and wrapped
```

Line 358:

```text
/ in none. Same reason `FleetRowLabel` exists: the header is chrome, and chrome
```

Line 359:

```text
/ belongs to one implementation.
```

Line 361:

```text
/ How the qualifying line under the title is rendered. The distinction is
```

Line 362:

```text
/ semantic, not cosmetic — a state word is coloured by the tone, an
```

Line 363:

```text
/ identifier is monospaced because you will compare it character by
```

Line 364:

```text
/ character, and a quantity is the headline fact so it keeps its weight.
```

Line 383:

```text
Wraps rather than truncates: the name of the thing under
```

Line 384:

```text
inspection is the one string on the panel that must survive a
```

Line 385:

```text
narrow column intact.
```

Line 435:

```text
/ The inspector's card: one titled group of facts. Same elevation treatment
```

Line 436:

```text
/ as content-column cards, tighter padding for the narrower column.
```

Line 455:

```text
/ One key/value line inside an inspector card.
```

Line 476:

```text
A single-line value in a 280pt column truncates, and a
```

Line 477:

```text
truncated path or command is not a fact. Selectable already,
```

Line 478:

```text
now also readable without selecting it.
```

Line 484:

```text
/ Compact bordered action used inside the actions card.
```

## Sources/FleetConsoleApp/Views/Console/ProcessModule.swift

Line 4:

```text
Module: Processes — the machine's process table as a first-class citizen.
```

Line 6:

```text
A native `Table` with column sorting, a scope filter, and a contextual menu
```

Line 7:

```text
per row. The action policy is the threat model, rendered honestly:
```

Line 9:

```text
Managed services are signalled *through the controller* (stop, restart,
```

Line 10:

```text
kill) — the app never calls kill(2) itself, so the PID-reuse guard and
```

Line 11:

```text
the audit event both come for free.
```

Line 12:

```text
Everything else gets read-only verbs — Sample, Copy PID, Reveal in
```

Line 13:

```text
Activity Monitor — plus Claim, which files the process under an owner and
```

Line 14:

```text
a lease without granting anyone the right to signal it. That slot used to
```

Line 15:

```text
hold a permanently disabled "Kill Process" carrying the rule in its
```

Line 16:

```text
tooltip; a control no state can enable is dead chrome however good its
```

Line 17:

```text
explanation, and the rule is better stated by what the menu does.
```

Line 28:

```text
/ pid → owning service id, rebuilt when either side changes. A process is
```

Line 29:

```text
/ "managed" when its pid *or its process group* matches a live service
```

Line 30:

```text
/ record — helpers of `npm run dev` belong to the service that started
```

Line 31:

```text
/ them, same rule the supervisor uses.
```

Line 44:

```text
A premium scope without a licence silently widens to `all` rather
```

Line 45:

```text
than rendering an empty table under a locked label. The subtitle
```

Line 46:

```text
says what happened, so the fallback is stated, not hidden.
```

Line 73:

```text
KeyPathComparator application: later comparators break earlier ties.
```

Line 124:

```text
Rule 8: a tone hue used as text on the window
```

Line 125:

```text
background is the fill colour doing the ink's job.
```

Line 126:

```text
`ink` is the same hue moved toward the label colour by
```

Line 127:

```text
the solved minimum that clears AA — which matters most
```

Line 128:

```text
here, on the one column whose colour *is* the reading.
```

Line 143:

```text
A process with no ports gets the em dash, drawn — not painted
```

Line 144:

```text
in `Color.clear`, which is what this cell used to do. That
```

Line 145:

```text
renders nothing while still handing VoiceOver a "—" to read,
```

Line 146:

```text
so the column was blank to the eye and dashed to the ear, and
```

Line 147:

```text
an empty cell in a table is ambiguous between "no ports" and
```

Line 148:

```text
"not sampled yet". Rule 4: a fact renders, and says what it is.
```

Line 189:

```text
The table sits on the page like every other surface: without
```

Line 190:

```text
this it paints AppKit's own table background over the field and
```

Line 191:

```text
the module reads as a panel dropped on top of the window rather
```

Line 192:

```text
than as part of it.
```

Line 196:

```text
Deferred to the next runloop tick: `.onAppear` fires while the table
```

Line 197:

```text
is still inside its first NSTableView delegate pass, and any observed
```

Line 198:

```text
state touched here re-enters the delegate mid-reload (macOS logs the
```

Line 199:

```text
"reentrant operation in its NSTableView delegate" warning there, and
```

Line 200:

```text
will assert on it). Sampling from a fresh tick keeps the delegate
```

Line 201:

```text
callback read-only.
```

Line 215:

```text
Premium scopes are labelled, not locked away: a paywalled
```

Line 216:

```text
segment you cannot see is a feature you cannot buy. The
```

Line 217:

```text
picker still lets the selection land on it — the module
```

Line 218:

```text
applies `all` and says why, which is the same honesty the
```

Line 219:

```text
Sensors card uses.
```

Line 226:

```text
Four scopes need enough intrinsic room to preserve their labels;
```

Line 227:

```text
when the tool rail is open, 340pt truncates “Heavyweight”.
```

Line 237:

```text
MARK: - Context menu
```

Line 253:

```text
Claimed and launched records are both "managed", and the menu has to say
```

Line 254:

```text
which: the verbs below exist for one and are refused for the other.
```

Line 276:

```text
This slot held `Button("Kill Process") {}.disabled(true)` — an empty
```

Line 277:

```text
closure behind a permanent `disabled`, with the rule in its tooltip.
```

Line 278:

```text
No state enabled it, which makes it precisely the dead chrome the
```

Line 279:

```text
design audit already forbids for the Full Screen menu item: a control
```

Line 280:

```text
you can read, cannot press, and will never be able to press.
```

Line 282:

```text
What replaces it is not a shorter menu but the verb that does exist
```

Line 283:

```text
for a process the controller did not start. Claiming files it under an
```

Line 284:

```text
owner, a purpose and a lease so it is supervised and reported on — and
```

Line 285:

```text
it still cannot be signalled, so the rule the disabled button was
```

Line 286:

```text
explaining is intact and is now enforced by what the menu *does*
```

Line 287:

```text
rather than by a sentence about what it does not.
```

Line 306:

```text
MARK: - Name cell
```

Line 314:

```text
The application's own icon when this process is a bundled app, and
```

Line 315:

```text
the runtime symbol when it is not. `startSignature` is passed for
```

Line 316:

```text
the same reason every signal path re-reads it: pids are recycled,
```

Line 317:

```text
and a cache keyed on the number alone would eventually draw a dead
```

Line 318:

```text
app's icon beside a live process's name.
```

Line 341:

```text
MARK: - Actions
```

Line 349:

```text
/ `/usr/bin/sample` on the pid for one second, written next to the app's
```

Line 350:

```text
/ own logs and revealed in Finder. Read-only: sampling observes a process,
```

Line 351:

```text
/ it does not signal one.
```

## Sources/FleetConsoleApp/Views/Console/RootView.swift

Line 5:

```text
A native navigation sidebar, content column, optional trailing inspector and
```

Line 6:

```text
optional tool panel. Keep toolbar/search on the split view for AppKit bridging.
```

Line 25:

```text
/ The window's content width, measured behind the tool field so the panel's
```

Line 26:

```text
/ clamp has something stable to divide up.
```

Line 28:

```text
/ Seeded with the composed width rather than zero. The side columns are a
```

Line 29:

```text
/ function of this, so a zero first frame meant `Scale.minor(-34)/2`
```

Line 30:

```text
/ clamping to the floor: both columns opened at 233 and the sidebar elided
```

Line 31:

```text
/ the device names it is sized to show, then corrected on the next layout
```

Line 32:

```text
/ pass. The window cannot be *narrower* than its own minimum and cannot be
```

Line 33:

```text
/ wider than the composed size, so the composed size is the only honest
```

Line 34:

```text
/ starting guess.
```

Line 44:

```text
One easing for both sides. `showsInspector` is the value that changes
```

Line 45:

```text
when the inspector is toggled *or* when width takes it away, so both
```

Line 46:

```text
routes animate identically instead of one sliding and one snapping.
```

Line 48:

```text
Keyed on the *cause*, not on the measurement.
```

Line 50:

```text
This was `value: sideColumnWidth`, and that width is a pure function
```

Line 51:

```text
of `contentWidth`, which is measured live from the window. So the one
```

Line 52:

```text
gesture it fired on constantly was the one it should never have fired
```

Line 53:

```text
on: dragging an edge handed a 0.34s spring a new target every frame,
```

Line 54:

```text
each restarting before the last had settled, and the columns swam
```

Line 55:

```text
after the pointer instead of tracking it. Revealing a tool panel is
```

Line 56:

```text
the only *discrete* thing that changes this width, so it is what the
```

Line 57:

```text
animation watches now — the slide is unchanged, the drag is direct.
```

Line 62:

```text
Measured on the full frame — the inset's own width is derived from
```

Line 63:

```text
this, so reading it from inside the inset would be circular.
```

Line 81:

```text
showHome and selectModule are deliberately absent: they are observed in
```

Line 82:

```text
ConsoleWindowController, which exists before this view does. A sender
```

Line 83:

```text
opens the window and posts in the same turn, and the status item's
```

Line 84:

```text
dropdown does that with no window up at all, so a subscription
```

Line 85:

```text
installed on appearance is a subscription installed too late.
```

Line 102:

```text
Live data deletes rows; selections pointing at ghosts clear themselves.
```

Line 103:

```text
Deferred one runloop tick: these fire while SwiftUI is still pushing
```

Line 104:

```text
new rows through the table's NSTableView delegate, and clearing a
```

Line 105:

```text
selection bound to that table re-enters the delegate mid-pass (the
```

Line 106:

```text
"reentrant operation" warning macOS will assert on).
```

Line 120:

```text
Remote nodes have one module — their own detail. Switching back
```

Line 121:

```text
to This Mac restores the last module implicitly via state.
```

Line 124:

```text
A revealed panel follows the selection: opening Files on a service and
```

Line 125:

```text
then picking a different one should land in the new working directory.
```

Line 133:

```text
MARK: - The split view
```

Line 135:

```text
Held separately so the toolbar and the search field stay attached to the
```

Line 136:

```text
`NavigationSplitView` itself — they bridge onto the window's NSToolbar
```

Line 137:

```text
from here, and moving them out to the `HStack` is not the same thing.
```

Line 139:

```text
/ The width below which column three and a tool panel stop both fitting.
```

Line 140:

```text
/ Derived and asserted in `ConsoleLayout` — see `ConsoleLayoutTests`, which
```

Line 141:

```text
/ proves the arrangement lands exactly on the module column's floor here.
```

Line 142:

```text
/ This was previously summed inline from four tokens and a bare `360`, and
```

Line 143:

```text
/ the bare 360 was the only statement anywhere of what a module column
```

Line 144:

```text
/ needs.
```

Line 147:

```text
/ Column three yields only when it has to: at the composed 1560 everything
```

Line 148:

```text
/ stands at once, and only a window dragged toward its floor *with a tool
```

Line 149:

```text
/ open* makes the inspector give way — because the module column going
```

Line 150:

```text
/ under `ConsoleLayout.moduleColumnMin` turns its tables into horizontal
```

Line 151:

```text
/ scrollbars.
```

Line 157:

```text
/ Whether width — rather than the button — is what is hiding column three.
```

Line 158:

```text
/ The toggle reports this in its tooltip instead of silently doing nothing,
```

Line 159:

```text
/ so a button that cannot take effect says why.
```

Line 164:

```text
/ The inspector uses the available content width after any tool panel.
```

Line 185:

```text
/ Column three, mirrored onto the sidebar's geometry and easing.
```

Line 187:

```text
/ Clipped to its frame so the panel slides out of the window edge instead
```

Line 188:

```text
/ of being drawn outside it during the transition, and given a leading
```

Line 189:

```text
/ hairline because it no longer gets the split view's own column separator.
```

Line 205:

```text
MARK: - Content column
```

Line 227:

```text
/ Kept under ~130pt at 13pt, because the toolbar search field does not get a
```

Line 228:

```text
/ width — it gets whatever the toolbar has left, which on a narrower window
```

Line 229:

```text
/ is around 150pt of text area. The previous prompts ran 168–207pt and five
```

Line 230:

```text
/ of the eight clipped mid-word ("Filter what needs attent"). A hint that is
```

Line 231:

```text
/ cut off is worse than a short one: it reads as a rendering fault.
```

Line 233:

```text
/ They are also not elided. The first fix for the clipping was to shorten
```

Line 234:

```text
/ each prompt and end it in "…", which is the wrong punctuation twice over:
```

Line 235:

```text
/ macOS reserves a trailing ellipsis for a control that opens something
```

Line 236:

```text
/ needing more input, and putting one in a placeholder says the *hint* was
```

Line 237:

```text
/ abbreviated — so a field that fit perfectly still looked truncated. These
```

Line 238:

```text
/ are whole phrases that fit, naming the noun being searched, because the
```

Line 239:

```text
/ field's own magnifying glass already supplies the verb.
```

Line 242:

```text
MARK: - Tool context
```

Line 244:

```text
What a chrome tool should open against. A selected service has a recorded
```

Line 245:

```text
cwd — that is the whole reason `--cwd` is mandatory for agents — and
```

Line 246:

```text
anything else falls back to home, never to a directory guessed from a
```

Line 247:

```text
process's argv.
```

Line 261:

```text
MARK: - Toolbar
```

Line 263:

```text
The ribbon. Its structure and wording are fixed: the same module
```

Line 264:

```text
segments in the same order, the same device label when a remote node is
```

Line 265:

```text
selected, the same refresh verb. The only thing the tool rail changes
```

Line 266:

```text
about it is that its text now truncates with a tail ellipsis instead of
```

Line 267:

```text
being allowed to grow into space that is no longer there.
```

Line 327:

```text
MARK: - Search focus (⌘K)
```

Line 329:

```text
`.searchFocused` is macOS 15; this app targets 14. The toolbar search
```

Line 330:

```text
field is a real NSSearchField once SwiftUI bridges the toolbar onto the
```

Line 331:

```text
AppKit window, so focusing it is a first-responder call away — found
```

Line 332:

```text
recursively rather than by toolbar-item index, which SwiftUI does not
```

Line 333:

```text
promise to keep stable.
```

Line 336:

```text
A beat after the menu command: the window may have been ordered in
```

Line 337:

```text
by the same click, and the field must exist before it can take focus.
```

Line 342:

```text
Native toolbar controls live beside the content view in its frame.
```

Line 359:

```text
/ Overview's complete control surface in one native-toolbar row. The module
```

Line 360:

```text
/ itself starts immediately with the charts; it never draws a second ribbon.
```

## Sources/FleetConsoleApp/Views/Console/ServiceInspectorView.swift

Line 4:

```text
Inspector: one managed service, or one unmanaged process.
```

Line 6:

```text
The managed view keeps the old inspector's load-bearing parts — the four
```

Line 7:

```text
evidence facts, the lease, the placement verdict across the fleet — and adds
```

Line 8:

```text
the live resource numbers the console already has. Placement matters here:
```

Line 9:

```text
"can this move to another node" is the question a fleet console exists to
```

Line 10:

```text
answer, and it is answered with the same hard-constraint rules the evidence
```

Line 11:

```text
chips use.
```

Line 66:

```text
MARK: Header
```

Line 69:

```text
`state.label` verbatim: "Running (unverified)" is not a placeholder
```

Line 70:

```text
for "Healthy", and the header is exactly where that would get lost.
```

Line 89:

```text
MARK: Evidence
```

Line 104:

```text
How the record got here, because it decides what the controller may
```

Line 105:

```text
do to it. Provenance travels with the claim — the same rule the
```

Line 106:

```text
network segments follow.
```

Line 113:

```text
A working directory is a fact you act on — wrapped, not middle-
```

Line 114:

```text
truncated into "/Users/…/src".
```

Line 119:

```text
MARK: Activity
```

Line 133:

```text
MARK: Lease
```

Line 140:

```text
"Ran for" once it is over. A terminal record's figure is a span that
```

Line 141:

```text
ended, not a clock still going.
```

Line 158:

```text
MARK: Placement
```

Line 189:

```text
MARK: Log tail
```

Line 214:

```text
MARK: Events
```

Line 249:

```text
MARK: - Unmanaged
```

Line 292:

```text
Three answers to "what is this doing here", in the
```

Line 293:

```text
order you reach for them: watch it, expect it,
```

Line 294:

```text
go and look at it.
```

## Sources/FleetConsoleApp/Views/Console/ServicesModule.swift

Line 4:

```text
Services owns service identity and evidence. Owners remain in each row; the
```

Line 5:

```text
agent roster has its own destination, and unmanaged processes stay disclosed.
```

Line 96:

```text
MARK: - Rows
```

Line 155:

```text
A claimed record still keeps lease renewal, never signal controls.
```

## Sources/FleetConsoleApp/Views/Console/StorageInspectors.swift

Line 4:

```text
Inspector: one volume, or one breakdown segment.
```

Line 6:

```text
A volume gets capacity arithmetic, purgeable accounting, file-system facts
```

Line 7:

```text
and its local APFS snapshots. A segment gets its byte count and — more
```

Line 8:

```text
important — its *basis*: measured where, or arithmetic of what. The honesty
```

Line 9:

```text
rules apply to colours too: "System & Other" is the one segment that is
```

Line 10:

```text
openly a subtraction, and it says so in its own inspector.
```

Line 20:

```text
/ A segment id that is not a mount path means the user tapped a bar
```

Line 21:

```text
/ segment or legend chip — route to the segment inspector instead.
```

Line 50:

```text
MARK: Volume
```

Line 117:

```text
MARK: Segment
```

## Sources/FleetConsoleApp/Views/Console/StorageModule.swift

Line 4:

```text
Module: Storage — where the disk went, and what can safely come back.
```

Line 6:

```text
Four layers, in the order you actually ask the questions:
```

Line 7:

```text
1. The segmented bar: every byte of the boot volume, colour-coded by
```

Line 8:

```text
category, animated in when the scan lands. Segments are selectable —
```

Line 9:

```text
the inspector explains each one's basis.
```

Line 10:

```text
2. The disk map: a squarified heatmap of the surveyed directories —
```

Line 11:

```text
area is allocated bytes, colour is the same category as the bar.
```

Line 12:

```text
3. Volumes: each mounted APFS volume with its own capacity meter and
```

Line 13:

```text
purgeable accounting.
```

Line 14:

```text
4. Reclaimable space: the catalogue of known caches, with the consequence
```

Line 15:

```text
stated before anything is deleted. Data is reported, never offered.
```

Line 51:

```text
`scan()` re-reads volume capacity on its own worker hop, so it is
```

Line 52:

```text
never asked to measure against a snapshot that has not landed yet.
```

Line 53:

```text
The bare refresh is only for the volumes list below, which shows
```

Line 54:

```text
even when the breakdown has already been scanned.
```

Line 67:

```text
No refreshVolumes() first: it publishes asynchronously through the
```

Line 68:

```text
main actor, so it could not land before scan() read the capacity.
```

Line 69:

```text
scan() refreshes capacity itself, on the hop that measures.
```

Line 74:

```text
MARK: - Segmented bar
```

Line 106:

```text
The app's own empty state, for the reason recorded on
```

Line 107:

```text
`InspectorPanel.emptyState`: `ContentUnavailableView` mis-lays
```

Line 108:

```text
a wrapping description at a width it did not expect.
```

Line 120:

```text
Rule 4: the bar covers the surveyed buckets and nothing
```

Line 121:

```text
else here, so it says so rather than looking like a full disk.
```

Line 149:

```text
/ Denominator for the bar. The capacity the scan itself read, not today's
```

Line 150:

```text
/ volume reading — those differ for as long as a scan takes, and a bar
```

Line 151:

```text
/ whose segments and total come from different moments does not add up.
```

Line 152:

```text
/ With no capacity at all the segments are their own total, and the note
```

Line 153:

```text
/ above says what the bar is therefore not showing.
```

Line 161:

```text
MARK: - Disk map
```

Line 197:

```text
MARK: - Volumes
```

Line 220:

```text
MARK: - Reclaim
```

Line 258:

```text
Two columns where there is room for two. A reclaim row is an
```

Line 259:

```text
icon, a name, a size and a button — about 300pt of content —
```

Line 260:

```text
and the module column is over 700pt at the composed window
```

Line 261:

```text
size, so a single stack spent more than half its width on
```

Line 262:

```text
nothing and made a fourteen-entry catalogue a scroll. The
```

Line 263:

```text
hairline between rows becomes the grid's own gap, which is
```

Line 264:

```text
why it is dropped rather than drawn per cell: a separator
```

Line 265:

```text
that only runs down one column reads as a broken table.
```

Line 323:

```text
MARK: - Segmented bar
```

Line 325:

```text
/ The volume as one contiguous bar, one segment per category. Segments under
```

Line 326:

```text
/ ~1.5% are drawn inside "System & Other" (a 200 MB sliver is not a segment,
```

Line 327:

```text
/ it is noise with a colour) — but only their *width* moves there. Every byte
```

Line 328:

```text
/ count the UI prints stays the number the scan produced, so the bar's
```

Line 329:

```text
/ tooltip, the legend chip and the inspector cannot disagree.
```

Line 335:

```text
/ One drawn stripe. `widthBytes` is what the stripe *occupies* — the
```

Line 336:

```text
/ segment's own bytes plus anything rolled into it — while `segment.bytes`
```

Line 337:

```text
/ stays the segment's own figure for every label and tooltip.
```

Line 351:

```text
"System & Other" is never a sliver, because it is the roll-up
```

Line 352:

```text
target: fold it away and the rolled-up bytes have nowhere to go.
```

Line 365:

```text
No "System & Other" segment at all (capacity unreadable). A
```

Line 366:

```text
crowded bar is a smaller lie than a bar that does not add up,
```

Line 367:

```text
so the slivers are drawn as themselves.
```

Line 376:

```text
Normally identical to `total` — the scan's segments sum to the volume.
```

Line 377:

```text
Allocated-size measurement can still exceed used space when APFS
```

Line 378:

```text
clones are counted twice, and a bar that overflows its own width is
```

Line 379:

```text
worse than one that renormalises.
```

Line 401:

```text
Each stripe is its own element: the bar used to
```

Line 402:

```text
collapse to one label, which made the segment
```

Line 403:

```text
inspector unreachable without a pointer.
```

Line 431:

```text
Say it rather than let the stripe look bigger than its number.
```

Line 464:

```text
MARK: - Volume row
```

Line 517:

```text
/ Thin capacity meter inside a volume row.
```

Line 536:

```text
MARK: - Reclaim row
```

Line 574:

```text
The menu carries Move to Trash / Delete; an ellipsis glyph is not
```

Line 575:

```text
a name for that, so VoiceOver gets one that says whose it is.
```

Line 586:

```text
MARK: - Category ordering
```

Line 589:

```text
/ Draw order in the bar: real data left to right, then purgeable, then
```

Line 590:

```text
/ free at the trailing edge — the same reading order as About This Mac.
```

Line 606:

```text
MARK: - Flow layout
```

Line 608:

```text
/ Simple wrapping layout for the legend chips.
```

## Sources/FleetConsoleApp/Views/Console/TelemetryCharts.swift

Line 5:

```text
Live telemetry, drawn with Swift Charts.
```

Line 7:

```text
The popover keeps the hand-rolled `Sparkline` (14pt tall, no axes by design).
```

Line 8:

```text
The window's charts are a different instrument: current values rendered as
```

Line 9:

```text
monospaced-digit text beside the plot rather than as axis clutter, gradient
```

Line 10:

```text
area fills for the "wave", and a y scale chosen per *kind* of series rather
```

Line 11:

```text
than one rule for both. A chart here shows shape and trend; the exact number
```

Line 12:

```text
sits next to it. Both are honest: a rate with no second sample draws an empty
```

Line 13:

```text
track, never a confident flat line.
```

Line 15:

```text
Why the scales differ, since this is the interesting decision:
```

Line 17:

```text
A **bounded** series (utilisation, memory share — anything 0…1) gets a
```

Line 18:

```text
linear* axis over an auto-ranged window. Not a log axis: log compresses
```

Line 19:

```text
the top of a bounded range, so 50→100% becomes 1.70→2.00 and a machine
```

Line 20:

```text
spiking off a 50% floor looks flatter than it did before. What you
```

Line 21:

```text
actually want above a high baseline is resolution, and the honest way to
```

Line 22:

```text
get resolution is to move the window and then *say where the window is*.
```

Line 23:

```text
An **unbounded** series (byte rates) gets a *log* axis, because it really
```

Line 24:

```text
does span decades and spends most of its life near zero.
```

Line 26:

```text
Both rules have the same guard: a chart too short to carry its axis labels
```

Line 27:

```text
keeps its plain domain. A rescaled axis you cannot read is the failure this
```

Line 28:

```text
change exists to avoid.
```

Line 70:

```text
MARK: - Bounded window
```

Line 72:

```text
/ The y window for a bounded 0…1 series, and whether it is narrower than the
```

Line 73:

```text
/ full range — which is the same question as "must this chart label itself".
```

Line 79:

```text
/ The floor on how far the window may close. A flat series has to stay
```

Line 80:

```text
/ flat: without this, idle jitter of two points fills the plot and the
```

Line 81:

```text
/ chart cries wolf every two seconds. 0.15 is picked against the 2 s
```

Line 82:

```text
/ cadence — idle CPU wobble of 2–5 points lands at a fifth of the plot
```

Line 83:

```text
/ height, which is visible without being an event.
```

Line 85:

```text
/ Headroom above and below the observed band, as a share of the span.
```

Line 86:

```text
/ Keeps the trace — and Catmull-Rom's overshoot between samples — off the
```

Line 87:

```text
/ plot boundary.
```

Line 110:

```text
Clamping at 0 or 1 can eat the span back; re-grow off the other end
```

Line 111:

```text
rather than shipping a window narrower than the floor.
```

Line 122:

```text
A hair inside 0 and 1 still counts as the full range: labelling
```

Line 123:

```text
"0%–100%" on a chart that is showing 0…1 is furniture, not honesty.
```

Line 128:

```text
MARK: - Load wave
```

Line 130:

```text
/ CPU / GPU / memory utilisation as a filled wave over the last two minutes.
```

Line 132:

```text
/ The y window tracks the observed band rather than sitting fixed at 0…1, so
```

Line 133:

```text
/ the volatility on top of a high baseline is the thing you see — and the two
```

Line 134:

```text
/ axis labels state the window, because a trace that fills the plot must never
```

Line 135:

```text
/ be mistakable for a machine at 100%.
```

Line 159:

```text
Two marks, the window's own bounds, and nothing else: no ticks,
```

Line 160:

```text
no domain line, hairline gridlines. The axis is here to state the
```

Line 161:

```text
range, not to let you read values off the plot — that is what the
```

Line 162:

```text
live numeral in the card header is for.
```

Line 209:

```text
MARK: - Throughput
```

Line 211:

```text
/ Disk read/write bandwidth, two series on one shared scale.
```

Line 213:

```text
/ Log, when there is room to label it. Byte rates are the genuinely unbounded
```

Line 214:

```text
/ series in the app: on a linear axis a 40 KB/s log write and a 900 MB/s file
```

Line 215:

```text
/ copy share the bottom pixel row, which is four decades of difference thrown
```

Line 216:

```text
/ away. Zero is a real sample — an idle disk — and log(0) is not a number, so
```

Line 217:

```text
/ samples are lifted to the axis floor instead of being dropped. The trace
```

Line 218:

```text
/ rests on the bottom gridline, and that gridline is labelled with the floor.
```

Line 229:

```text
/ Axis floor. Below a kilobyte per second there is nothing to tell apart,
```

Line 230:

```text
/ and `ConsoleFmt.byteRate` already floors its text at the same place.
```

Line 232:

```text
/ The axis never closes in tighter than this, so an idle disk's 12 KB/s
```

Line 233:

```text
/ housekeeping cannot become a full-height event.
```

Line 243:

```text
/ Log above the floor when labelled; the previous linear-with-a-floor
```

Line 244:

```text
/ scale when not, because an unlabelled log axis makes a 4 KB/s blip look
```

Line 245:

```text
/ like a write storm.
```

Line 248:

```text
/ Three labels at most: the floor, the geometric middle (the midpoint of a
```

Line 249:

```text
/ log axis is its geometric mean, not its arithmetic one) and the top.
```

Line 282:

```text
/ Split out so the scale type can differ without duplicating the marks.
```

Line 322:

```text
/ Lifts a sample onto the axis. On the log scale this is what keeps an
```

Line 323:

```text
/ idle disk on the bottom gridline instead of producing a broken path.
```

Line 329:

```text
MARK: - Chart card
```

Line 331:

```text
/ An instrument: one metric's dial, its history, and the facts underneath.
```

Line 333:

```text
/ This used to be a title row carrying the live numeral, over a full-width
```

Line 334:

```text
/ trace. Four of them stacked meant four cards of roughly 200–260pt for four
```

Line 335:

```text
/ numbers — one screenful of scroll per metric on a window whose content column
```

Line 336:

```text
/ was already sharing its width with a sidebar and an inspector, and a header
```

Line 337:

```text
/ numeral that told you 77% without telling you whether 77% was anywhere near
```

Line 338:

```text
/ the top of the range.
```

Line 340:

```text
/ The dial answers that in the same space the numeral occupied, so the header
```

Line 341:

```text
/ loses the number rather than gaining a gauge — and the card is laid out
```

Line 342:

```text
/ horizontally, gauge beside trace, which is what lets two of them sit side by
```

Line 343:

```text
/ side in the grid instead of stacking.
```

Line 346:

```text
/ The plotted legend struck into this plate's top border — "01 · CPU".
```

Line 347:

```text
/ Given at the call site rather than derived from `title`, because the
```

Line 348:

```text
/ number is the card's position in the module's grid and the grid is the
```

Line 349:

```text
/ caller's. A card that numbered itself would be a card that renumbered
```

Line 350:

```text
/ itself when the GPU withheld its key and the module dropped to three.
```

Line 353:

```text
/ The formatted current value, shown on the dial's face.
```

Line 355:

```text
/ 0…1 for the needle. Nil parks it: the metric has not been sampled.
```

Line 390:

```text
MARK: - Chart legend dot
```

Line 403:

```text
A rate is one token. In the wider card this never came up; in a grid
```

Line 404:

```text
cell "5.3 MB/s" broke after the numeral and the legend became two
```

Line 405:

```text
lines tall, which then set the height of every card in its row.
```

## Sources/FleetConsoleApp/Views/Console/Terminal/FilesPanel.swift

Line 3:

```text
The Yazi file surface.
```

Line 5:

```text
Design decisions:
```

Line 6:

```text
- `refusesBelowMinimum: true` — Yazi's three-pane layout collapses under
```

Line 7:

```text
40 columns. Below that, PTYSession itself refuses to forward the grid to
```

Line 8:

```text
the child, and PTYPanelView shows the honest "too narrow" state instead.
```

Line 9:

```text
- The binary is resolved at activate time, not at init: the user may install
```

Line 10:

```text
Yazi between flips of the panel, and the panel should pick it up without
```

Line 11:

```text
requiring a relaunch.
```

Line 12:

```text
- When Yazi is absent, `EmptyPanelView` says so with the exact paths
```

Line 13:

```text
searched, so the user knows what to install and where to put it. No silent
```

Line 14:

```text
fallback to a plain shell — the README's "absent binary means the panel
```

Line 15:

```text
says so" rule.
```

Line 16:

```text
- Directory changes restart the child, same as TerminalPanel, because Yazi
```

Line 17:

```text
opens a tree at its argv path and cannot navigate to a different root from
```

Line 18:

```text
inside the TUI.
```

Line 29:

```text
MARK: PTYBackedSurface
```

Line 37:

```text
MARK: ToolSurface
```

Line 45:

```text
Binary not found — makeView() will show the unavailable state.
```

Line 69:

```text
Keep warm — Yazi's tree is worth retaining across panel toggles.
```

Line 98:

```text
MARK: Private
```

Line 100:

```text
/ The panel's own Yazi configuration, shipped in the bundle.
```

Line 102:

```text
/ Without this the panel runs against `~/.config/yazi`, which means the file
```

Line 103:

```text
/ surface inside FleetConsole looks like whatever the user's own file
```

Line 104:

```text
/ manager looks like and changes when they change it. It also means
```

Line 105:

```text
/ inheriting their previewer plugins: this machine's config points two
```

Line 106:

```text
/ `prepend_previewers` at `piper`, which is declared in `package.toml` and
```

Line 107:

```text
/ not installed, so both previews fail.
```

Line 109:

```text
/ The bundled config is a different thing from a copy of theirs — a
```

Line 110:

```text
/ fixed-purpose file *view*: no status line, achromatic, one icon set. See
```

Line 117:

```text
Running from `swift run` rather than the bundle — the app is developed
```

Line 118:

```text
that way and the panel should look the same there.
```

Line 120:

```text
`Resources/` is a sibling of `Sources/`, not a child of it, so the
```

Line 121:

```text
walk has to reach the package root. Stopping at `Sources` pointed this
```

Line 122:

```text
at `Sources/Resources/yazi`, which does not exist — so `configHome`
```

Line 123:

```text
came back nil, `YAZI_CONFIG_HOME` was never set, and every dev build
```

Line 124:

```text
ran the panel against `~/.config/yazi` instead. That is the exact
```

Line 125:

```text
failure the bundled config exists to prevent: the surface came out in
```

Line 126:

```text
the user's own colour theme rather than achromatic, and inherited
```

Line 127:

```text
their `piper` previewers, which are declared and not installed.
```

Line 132:

```text
FleetConsoleApp
```

Line 134:

```text
package root
```

Line 140:

```text
/ `YAZI_CONFIG_HOME` for the current system appearance.
```

Line 142:

```text
/ Yazi reads exactly one `theme.toml` out of its config home, and the panel
```

Line 143:

```text
/ background follows the window (`PTYSurface.applyAppearance`), so the theme
```

Line 144:

```text
/ has to be chosen at launch rather than shipped as a single file. The
```

Line 145:

```text
/ template directory holds `theme-dark.toml` and `theme-light.toml`; this
```

Line 146:

```text
/ stages the right one, under its own name, into a per-appearance directory
```

Line 147:

```text
/ in Caches.
```

Line 149:

```text
/ Without this the Light Mode panel painted the dark ramp — #C8C9CD text on
```

Line 150:

```text
/ a white background, ~1.3:1 — onto a surface that had correctly turned
```

Line 151:

```text
/ white underneath it.
```

Line 153:

```text
/ Restaged on every launch. The files are a few KB and staging them fresh
```

Line 154:

```text
/ means editing the theme and reopening the panel shows the edit, instead of
```

Line 155:

```text
/ a stale copy surviving in Caches until someone works out why.
```

Line 174:

```text
Staging failed — fall back to the template directory. Its bundled
```

Line 175:

```text
theme.toml may be absent, in which case Yazi uses its own default
```

Line 176:

```text
theme: coloured, but readable. Never fall through to the user's
```

Line 177:

```text
~/.config/yazi, which is the case the bundled config exists to
```

Line 178:

```text
prevent.
```

Line 183:

```text
/ The appearance the panel will actually be drawn in. Read from the app
```

Line 184:

```text
/ rather than a SwiftUI `colorScheme`, because this is a class that builds
```

Line 185:

```text
/ an `execve` environment, not a view — and the child needs the answer
```

Line 186:

```text
/ before the view exists.
```

Line 201:

```text
Yazi needs $PATH to find its helpers (unar, ffmpeg, …). The full search
```

Line 202:

```text
path is given, same as we resolved the binary with, so those helpers
```

Line 203:

```text
are findable too.
```

Line 204:

```text
`environment` is execve's `KEY=VALUE` vector, not a dictionary.
```

Line 210:

```text
Exec Yazi directly — no shell between the panel and the child.
```

Line 211:

```text
The working directory is passed as an argument rather than inherited
```

Line 212:

```text
so that `cd` inside Yazi does not confuse the panel's context.
```

## Sources/FleetConsoleApp/Views/Console/Terminal/PTYSurface.swift

Line 5:

```text
Shared pseudo-terminal plumbing for the two PTY-backed chrome panels.
```

Line 7:

```text
The terminal and the file surface differ only in what they exec, so everything
```

Line 8:

```text
else lives here: measure the character cell, spawn a child in a pty, hand it a
```

Line 9:

```text
settled grid exactly once, and keep it warm across toggles.
```

Line 11:

```text
One structural decision drives the rest. `SwiftTerm.TerminalView` re-derives
```

Line 12:

```text
its own column count from its frame inside `setFrameSize`, which is precisely
```

Line 13:

```text
the per-frame `TIOCSWINSZ` + `SIGWINCH` that `ToolResizeCoalescer` exists to
```

Line 14:

```text
prevent. So the terminal is never the view SwiftUI resizes: it sits inside
```

Line 15:

```text
`PTYHostView`, whose bounds follow the sidebar spring freely while the
```

Line 16:

```text
terminal's own frame changes only when a settled `TerminalGrid` arrives. That
```

Line 17:

```text
makes "forward the settled grid straight to the pty" a single frame
```

Line 18:

```text
assignment, with no debounce of our own stacked on the host's.
```

Line 20:

```text
MARK: - Published cell metrics
```

Line 22:

```text
/ Additive to `ToolSurface` rather than folded into it: the seam file is shared
```

Line 23:

```text
/ with the rail, and only the two pty-backed panels have a
```

Line 24:

```text
/ cell to publish. The host reaches for this with `as?` when it needs to turn a
```

Line 25:

```text
/ panel's pixel size into a grid.
```

Line 30:

```text
/ Panel width that is spent before the first column can be drawn. See
```

Line 31:

```text
/ `TerminalGrid.fitting(_:cell:reservedWidth:)` — the host must measure the
```

Line 32:

```text
/ columns against what is actually left, or it hands back a grid that does
```

Line 33:

```text
/ not fit the panel it measured.
```

Line 35:

```text
/ Actual height spent on controls above the emulator, not terminal rows.
```

Line 43:

```text
MARK: - Font and cell
```

Line 46:

```text
/ A Nerd Font when one is installed, SF Mono when none is.
```

Line 48:

```text
/ SF Mono was the original choice — the same family `ConsoleFont.mono()`
```

Line 49:

```text
/ uses for ports, PIDs and paths — and it is a fine face for a shell. It
```

Line 50:

```text
/ carries no Private Use Area glyphs, though, and Yazi draws its entire
```

Line 51:

```text
/ file-type column out of that range. Every icon in the Files panel was
```

Line 52:

```text
/ rendering as tofu, which reads as a broken panel rather than as a missing
```

Line 53:

```text
/ font.
```

Line 55:

```text
/ The list is ordered most- to least-specific: a patched mono face first,
```

Line 56:

```text
/ then the symbols-only face, which CoreText will fall back into for the
```

Line 57:

```text
/ PUA range while keeping SF Mono for text. Nothing here is bundled — the
```

Line 58:

```text
/ app cannot ship JetBrains Mono — so the final fallback stays SF Mono and
```

Line 59:

```text
/ the panel keeps working with no Nerd Font at all, just without icons.
```

Line 60:

```text
/ PostScript names, not family names — `NSFont(name:)` takes the former and
```

Line 61:

```text
/ silently returns nil for the latter, which is how a plausible-looking
```

Line 62:

```text
/ "SymbolsNerdFontMono-Regular" sat in this list resolving to nothing. Each
```

Line 63:

```text
/ one below was verified against `NSFontManager.availableMembers`.
```

Line 65:

```text
JetBrainsMono NFM
```

Line 66:

```text
JetBrainsMono NF
```

Line 79:

```text
/ Whether `panel` resolved to a face that can draw Yazi's icons. The Files
```

Line 80:

```text
/ panel says so rather than leaving the user to wonder why the column is
```

Line 81:

```text
/ blank.
```

Line 88:

```text
/ Measures the cell the way SwiftTerm does: ascent + descent + leading for
```

Line 89:

```text
/ the height, the advance of the character `W` for the width, both snapped
```

Line 90:

```text
/ to the backing store so adjacent cells cannot land on a half pixel.
```

Line 92:

```text
/ The `W` advance is looked up through the character, not a glyph name:
```

Line 93:

```text
/ fonts whose glyphs are unnamed resolve a named lookup to `.notdef`,
```

Line 94:

```text
/ whose advance spreads text across twice as many columns. The snap uses
```

Line 95:

```text
/ rounding to match the engine, so a frame built from these metrics fits
```

Line 96:

```text
/ exactly the requested grid.
```

Line 98:

```text
/ Re-derived rather than read back, because SwiftTerm keeps its own
```

Line 99:

```text
/ `cellDimension` internal and the host needs a cell *before* the first
```

Line 100:

```text
/ frame is handed out. Matching the formula is what lets
```

Line 101:

```text
/ `PTYHostView.apply(_:)` land on the grid it asked for in one step instead
```

Line 102:

```text
/ of converging on it over several `SIGWINCH`es.
```

Line 119:

```text
MARK: - Child processes
```

Line 122:

```text
/ The user's login shell, from the password database rather than `$SHELL`.
```

Line 123:

```text
/ A GUI process does not inherit the user's interactive environment, so
```

Line 124:

```text
/ `$SHELL` is whatever launchd had; `getpwuid` is the same source
```

Line 125:

```text
/ Terminal.app reads.
```

Line 136:

```text
/ Finds `name` the way a login shell would, without running one. The
```

Line 137:

```text
/ inherited `PATH` comes first, then the prefixes package managers actually
```

Line 138:

```text
/ install into — a Finder-launched app inherits a four-entry `PATH`, so
```

Line 139:

```text
/ refusing to look past it would report a tool missing on a machine that
```

Line 140:

```text
/ has it.
```

Line 161:

```text
/ SwiftTerm's defaults carry `TERM`, `COLORTERM` and a UTF-8 locale, and
```

Line 162:

```text
/ deliberately omit `PATH` — a login shell rebuilds its own from the
```

Line 163:

```text
/ profile. A tool exec'd directly has no such chance, so it gets the same
```

Line 164:

```text
/ search path we resolved it with, otherwise its previewers and helpers
```

Line 165:

```text
/ (`file`, `unar`, `$EDITOR`) are simply absent.
```

Line 174:

```text
/ A directory the child can actually start in. `forkpty`'s `chdir` failure
```

Line 175:

```text
/ is silent, which would drop the child in the app bundle's cwd and quietly
```

Line 176:

```text
/ contradict the panel header.
```

Line 186:

```text
/ Sends the child its `SIGTERM` and waits for it, from an object that is *not*
```

Line 187:

```text
/ main-actor bound. `LocalProcess.deinit` deliberately never signals the child,
```

Line 188:

```text
/ and `LocalProcess.terminate()` cancels the very dispatch source that would
```

Line 189:

```text
/ have `waitpid`ed — so without this a closed window leaves a live shell, and a
```

Line 190:

```text
/ restart leaves a zombie for the life of the app.
```

Line 192:

```text
/ Only ever touched on the main queue; the `@unchecked Sendable` is for the
```

Line 193:

```text
/ notification closure.
```

Line 200:

```text
Main-queue-only registry; the group also retains cleanup jobs after a
```

Line 201:

```text
closed session's reaper has deallocated.
```

Line 207:

```text
Signal every owned group first, then share one escalation window.
```

Line 208:

```text
Detached tasks cannot survive app exit; they release the group before
```

Line 209:

```text
requesting their main-actor UI completion, so this cannot deadlock it.
```

Line 228:

```text
Transfer ownership once; deinit must not repeat it.
```

Line 231:

```text
`running` describes SwiftTerm's I/O, not child ownership. It can be
```

Line 232:

```text
false at PTY EOF, or true inside an exit callback after waitpid.
```

Line 233:

```text
WNOWAIT both proves this is still our child and reserves its PID.
```

Line 239:

```text
forkpty makes the child a new session/group leader. Never signal our
```

Line 240:

```text
own group, a recycled pid, or a group we did not create.
```

Line 243:

```text
Cancels SwiftTerm's monitor and closes the owned PTY.
```

Line 247:

```text
Keep the direct child unreaped until escalation, reserving its pid
```

Line 248:

```text
and group identity even if it exits before a stubborn descendant.
```

Line 258:

```text
Release a synchronous quit before hopping back to the main actor.
```

Line 265:

```text
/ SwiftTerm normally reaps before its delegate callback. If its nonblocking
```

Line 266:

```text
/ wait has not collected the child yet, finish through the same verified
```

Line 267:

```text
/ cleanup rather than dropping ownership of a future zombie.
```

Line 271:

```text
MARK: - The AppKit host
```

Line 273:

```text
/ Container for the terminal view. Exists so that SwiftUI can resize *this*
```

Line 274:

```text
/ view as often as it likes without any of those sizes reaching the child
```

Line 275:

```text
/ process: the terminal keeps whatever frame the last settled grid gave it, and
```

Line 276:

```text
/ the slack shows as terminal background at the trailing and bottom edges.
```

Line 282:

```text
/ Called when a display change makes the measured cell stale, so the host
```

Line 283:

```text
/ can recompute its grid against the new one.
```

Line 288:

```text
/ Written once in `init`, read once in `deinit` — both on the main thread.
```

Line 289:

```text
/ `deinit` is nonisolated in Swift 6 and the token is not Sendable, so the
```

Line 290:

```text
/ access is spelled out as unchecked.
```

Line 293:

```text
/ Absorbs float error in `width / cellWidth`, which floors: a settled 80
```

Line 294:

```text
/ columns must not become 79 because the last cell was a millionth of a
```

Line 295:

```text
/ point short. Cannot overshoot while a cell is wider than half a point.
```

Line 309:

```text
Frame-driven on purpose: the whole point is that the superview's
```

Line 310:

```text
layout does not propagate a size onto the terminal.
```

Line 316:

```text
A window can be closed while this panel is toggled off and detached,
```

Line 317:

```text
so the notification is matched against the window we last belonged to
```

Line 318:

```text
rather than the one we are in now.
```

Line 322:

```text
`queue: .main` already puts this on the main thread. The window's
```

Line 323:

```text
`ObjectIdentifier` crosses rather than the window, since `NSWindow`
```

Line 324:

```text
is not Sendable and identity is the only question asked of it.
```

Line 341:

```text
/ Hands a settled grid to the pty. One frame assignment, one `TIOCSWINSZ`,
```

Line 342:

```text
/ one `SIGWINCH`, one TUI repaint.
```

Line 344:

```text
/ Deliberately does *not* use `TerminalView.resize(cols:rows:)`, which
```

Line 345:

```text
/ appends a DECSTR soft reset — that clears application-cursor mode and
```

Line 346:

```text
/ unhides the cursor, so a running full-screen TUI would lose its arrow
```

Line 347:

```text
/ keys and grow a stray caret on every resize.
```

Line 352:

```text
Self-correcting second pass: if SwiftTerm's width→columns arithmetic
```

Line 353:

```text
ever disagrees with our re-derived cell, one extra signal is cheaper
```

Line 354:

```text
than a permanently wrong grid.
```

Line 364:

```text
/ SwiftTerm reserves the scroller's width out of the drawable area in the
```

Line 365:

```text
/ legacy style only; an overlay scroller floats above the grid. Published
```

Line 366:

```text
/ so the host that computes the grid measures against the same number this
```

Line 367:

```text
/ view lays out against.
```

Line 369:

```text
SwiftTerm reserves the scroller out of the drawable area only in the
```

Line 370:

```text
legacy style; an overlay scroller floats above the grid, so the
```

Line 371:

```text
columns have to be measured against the full frame width.
```

Line 385:

```text
Pinned top-left: the prompt stays where the eye left it, and the slack
```

Line 386:

```text
between the settled grid and the panel's bounds sits at the far edge.
```

Line 388:

```text
Not clamped to zero. A grid that overshoots its panel — which is a bug
```

Line 389:

```text
upstream, but one this view should degrade honestly under — used to be
```

Line 390:

```text
pushed *down* until its first rows sat above the top edge and were
```

Line 391:

```text
clipped away, so a freshly spawned shell showed a panel with no prompt
```

Line 392:

```text
in it. Letting the origin go negative keeps the top-left corner where
```

Line 393:

```text
the name says it is and loses the overshoot off the bottom instead.
```

Line 413:

```text
/ The cell is a function of the font *and* the display, so moving the window
```

Line 414:

```text
/ between a Retina and a non-Retina screen changes it.
```

Line 423:

```text
/ Text and background come from the system's semantic colours so the panel
```

Line 424:

```text
/ follows the window's appearance. Resolved inside the current drawing
```

Line 425:

```text
/ appearance because SwiftTerm snapshots the background into an RGB triple
```

Line 426:

```text
/ for its own fills.
```

Line 436:

```text
MARK: - Session
```

Line 438:

```text
/ Owns one child process and the view it draws into. The panels above are thin:
```

Line 439:

```text
/ they choose what to exec and answer the `ToolSurface` questions from here.
```

Line 447:

```text
/ Raw `wait` status, as SwiftTerm hands it over.
```

Line 454:

```text
/ Unix `argv[0]`. A leading dash is how a shell is asked to behave as a
```

Line 455:

```text
/ login shell.
```

Line 463:

```text
/ Last grid the host settled on, forwarded or not.
```

Line 465:

```text
/ Last grid the child was actually told about.
```

Line 472:

```text
/ A launch that is waiting for its first settled grid.
```

Line 475:

```text
/ Keystrokes sent before the child exists. The PTY would buffer them for
```

Line 476:

```text
/ a running shell anyway; this only covers the gap before `forkpty`.
```

Line 479:

```text
/ Whether a grid below `TerminalGrid.minimum` may reach the child at all.
```

Line 480:

```text
/ Yazi's three panes collapse under it, so the file surface refuses and
```

Line 481:

```text
/ shows a too-narrow state; a shell reflows honestly at any width, so the
```

Line 482:

```text
/ terminal panel does not.
```

Line 495:

```text
/ See `PTYHostView.reservedWidth`. Forwarded so a panel can answer
```

Line 496:

```text
/ `PTYBackedSurface` without reaching through to the view.
```

Line 504:

```text
/ Start the child if it is not already running. Never disturbs a live one —
```

Line 505:

```text
/ the whole point of keeping it warm.
```

Line 512:

```text
/ Replace a live child only after its monitor, I/O and owned group have
```

Line 513:

```text
/ finished cleanup. Reusing LocalProcess immediately can let an old EOF
```

Line 514:

```text
/ clear the replacement's I/O state before its first input arrives.
```

Line 520:

```text
/ A settled, cell-aligned grid from the host. Forwarded as-is; the host has
```

Line 521:

```text
/ already waited for the animation to stop.
```

Line 525:

```text
Leave the child at its last honest size. It keeps painting that
```

Line 526:

```text
grid behind the too-narrow state, and reappears without a reflow.
```

Line 539:

```text
/ Types `text` into the child, or holds it until the child starts.
```

Line 548:

```text
/ Ordinary stops are asynchronous; application termination must join the
```

Line 549:

```text
/ same bounded cleanup before the process (and its tasks) can disappear.
```

Line 571:

```text
The child inherits its window size at `forkpty`, so there is no point
```

Line 572:

```text
starting one before the host has settled a grid — it would open at
```

Line 573:

```text
SwiftTerm's default 80x25 and be resized a frame later.
```

Line 585:

```text
/ SwiftTerm 2 silently ignores a start while the previous session is
```

Line 586:

```text
/ still winding down after a stop. The checked entry point reports that
```

Line 587:

```text
/ instead of swallowing it, so a relaunch that races the wind-down retries
```

Line 588:

```text
/ until the engine accepts a child or the attempt is superseded.
```

Line 618:

```text
/ Focus for the panel that has just been opened. Called on first spawn only:
```

Line 619:

```text
/ a selection change while the panel is open must not steal the caret from
```

Line 620:

```text
/ the sidebar or the search field.
```

Line 626:

```text
SwiftTerm calls this after its waiter reaps, once the previous
```

Line 627:

```text
session is fully wound down — so a deferred relaunch is safe here.
```

Line 628:

```text
Stops cancel that monitor, so they finish through our reaper instead.
```

Line 632:

```text
The scrollback is the evidence for *why* it exited, so the view keeps
```

Line 633:

```text
showing it and the chrome's running indicator carries the fact. The
```

Line 634:

```text
notice goes into that scrollback rather than over it.
```

Line 642:

```text
/ SwiftTerm 2 reports the normalized exit status: the exit code 0 through
```

Line 643:

```text
/ 255, or nil when the child ended on a signal or the wait failed.
```

Line 649:

```text
/ SwiftTerm's process delegate is not main-actor bound, but every callback
```

Line 650:

```text
/ is delivered on the main queue (`LocalProcess` defaults its dispatch queue
```

Line 651:

```text
/ to `.main`), so the isolation is asserted rather than hopped — a hop would
```

Line 652:

```text
/ let a resize land between the exit and our record of it.
```

Line 654:

```text
/ The delegate protocol's methods are nonisolated, so the bridge must be
```

Line 655:

```text
/ Sendable to reach SwiftTerm at all. Safe for the reason above: every
```

Line 656:

```text
/ callback arrives on the main queue, the same thread that set this.
```

Line 663:

```text
The pty is the authority on its own size, and the child owns its title
```

Line 664:

```text
and its cwd. Nothing in the chrome reads them back.
```

Line 671:

```text
MARK: - SwiftUI surface
```

Line 673:

```text
/ The terminal itself. `makeNSView` returns a view the session already owns,
```

Line 674:

```text
/ which is what keeps the process and its scrollback alive across panel
```

Line 675:

```text
/ toggles and SwiftUI rebuilds.
```

Line 681:

```text
Geometry arrives through `ToolSurface.resize(to:)` after the host has
```

Line 682:

```text
coalesced it. Reacting here as well would put a second, un-coalesced path
```

Line 683:

```text
to the pty back in.
```

Line 687:

```text
/ A pty panel's content: the terminal, or an honest reason it is not showing.
```

Line 688:

```text
/ No padding of its own — the host measures this area to compute the grid, and
```

Line 689:

```text
/ an inset here would be an inset the grid does not know about.
```

## Sources/FleetConsoleApp/Views/Console/Terminal/TerminalAgentSession.swift

Line 5:

```text
/ Explicit app handoff, not a guess based on a process title or terminal output.
```

Line 6:

```text
/ Only these launches get agent controls; an arbitrary command in Shell remains a shell command.
```

Line 57:

```text
SwiftTerm 2 reports the normalized exit status: the exit code,
```

Line 58:

```text
or nil for a signal-ended or unwaitable child.
```

## Sources/FleetConsoleApp/Views/Console/Terminal/TerminalPanel.swift

Line 5:

```text
/ A warm shell, bounded dedicated agent PTYs and a separate output-only investigation.
```

Line 6:

```text
/ Agent launches never type into a shell or a previously running interactive agent.
```

Line 52:

```text
/ Starting is an explicit operator handoff. Refuse before touching any live PTY.
```

Line 60:

```text
The destination header must be measured before this fresh PTY inherits a grid.
```

Line 78:

```text
/ Only the app-owned foreground agent child is stopped, never a managed service.
```

Line 91:

```text
Also cancels a launch still waiting for geometry.
```

Line 97:

```text
/ Account-funded requests stay output-only; neither output nor tokens enter a PTY child.
```

Line 141:

```text
Selection/navigation cannot retarget or kill an agent or the background shell.
```

Line 150:

```text
A changed selection must not restart an interactive shell or its jobs.
```

Line 151:

```text
The directory is used only when creating a new server session.
```

Line 161:

```text
Warm PTYs survive a panel toggle, not a window close.
```

Line 165:

```text
Ended agents never rerun automatically.
```

Line 169:

```text
Include never-displayed and deferred sessions, whose host has no window observer yet.
```

Line 172:

```text
Keep any dispatched operation identity; never replay it.
```

Line 201:

```text
A new PTY needs an emission even when its grid equals the previously
```

Line 202:

```text
settled one (including a rapid switch that cancels an intervening resize).
```

Line 262:

```text
/ Shared with native surface acceptance tests; the popover renders this exact view.
```

Line 297:

```text
/ Generic commands are accepted only in Shell; never inject them into an agent TUI.
```

Line 315:

```text
/ Observation must happen in a SwiftUI body, not once when makeView constructs an AnyView.
```

## Sources/FleetConsoleApp/Views/DevicesSection.swift

Line 40:

```text
/ Names the probe that produced the verdict. "Online" on its own is the claim
```

Line 41:

```text
/ this app will not make.
```

Line 91:

```text
/ Shared by the device row and the device inspector — one probe, one rendering.
```

## Sources/FleetConsoleApp/Views/FleetPopover.swift

Line 5:

```text
/ Legacy section routes retained for menu commands; details now open in the dashboard.
```

Line 61:

```text
The meters determine the dropdown height; never offer a tall body frame.
```

Line 83:

```text
/ One Agent menu for the four meters. A label on every instrument repeated
```

Line 84:

```text
/ the same word across the dropdown.
```

Line 136:

```text
/ Pull-down with the bezel and the hover plate turned off. SwiftUI's
```

Line 137:

```text
/ borderless menu button still draws a hit-box border while the pointer is
```

Line 138:

```text
/ over it, and that border stays up in the menu-bar dropdown.
```

Line 197:

```text
Non-flipped view: y = 0 is the button's bottom edge, so the menu opens downward.
```

Line 208:

```text
/ Template image, tint on hover, no bezel. `showsBorderOnlyWhileMouseInside`
```

Line 209:

```text
/ is the plate the dropdown was keeping around this control.
```

## Sources/FleetConsoleApp/Views/NetworkAdminSection.swift

Line 5:

```text
/ The administration half of the Network tab: routing, resolvers, interfaces,
```

Line 6:

```text
/ and the verbs that go with them.
```

Line 8:

```text
/ The existing rows answer *what am I attached to* — Wi-Fi, wire, Tailscale,
```

Line 9:

```text
/ VPN. This answers the two questions you ask next when something is wrong:
```

Line 10:

```text
/ **where do my packets go** and **who do I ask for names**. Both were missing
```

Line 11:

```text
/ entirely, which meant the surface could tell you the Wi-Fi was associated and
```

Line 12:

```text
/ could not tell you the gateway had stopped answering.
```

Line 14:

```text
/ Every verb here is read-only or clipboard-only, and the diagnostics run off
```

Line 15:

```text
/ the main actor with a hard deadline — see `NetworkActions`.
```

Line 39:

```text
Segments render only when a source has told us about some. No
```

Line 40:

```text
source registered → no header, no empty state, no row. See
```

Line 41:

```text
`VLANSource` for why an empty state would be a claim we cannot
```

Line 42:

```text
make.
```

Line 64:

```text
MARK: - Gateway
```

Line 76:

```text
Every default route, with the one in use marked. A machine on
```

Line 77:

```text
two networks at once has two answers to "where do my packets
```

Line 78:

```text
go", and listing only the winner hides the fact that there is
```

Line 79:

```text
a second — which is the first thing you want to know when the
```

Line 80:

```text
winner stops working.
```

Line 95:

```text
"As of", not "Checked": the snapshot is only republished when
```

Line 96:

```text
its content changes, so this is when the picture was
```

Line 97:

```text
established. See `RoutingStatus.sameContent(as:)`.
```

Line 119:

```text
MARK: - DNS
```

Line 135:

```text
`100.100.100.100` is Tailscale's MagicDNS and
```

Line 136:

```text
nothing else — a fixed address the daemon
```

Line 137:

```text
installs. Saying so turns a resolver nobody
```

Line 138:

```text
recognises into the one fact that explains
```

Line 139:

```text
why name resolution still works on a segment
```

Line 140:

```text
whose own DNS is unreachable.
```

Line 165:

```text
/ Tailscale's resolver addresses, both families. Fixed values the daemon
```

Line 166:

```text
/ installs, so this is recognition rather than a heuristic.
```

Line 171:

```text
MARK: - Interfaces
```

Line 180:

```text
Segment membership is an **identity**, not a status, so the
```

Line 181:

```text
tag is `.neutral` and never takes a tone hue: "which segment
```

Line 182:

```text
am I on" has no good/bad axis, and routing it through
```

Line 183:

```text
`StatusTone` would make one VLAN green and another amber for
```

Line 184:

```text
no reason a reader could reconstruct.
```

Line 186:

```text
The label is only ever drawn from something that was told to
```

Line 187:

```text
us — the host's own 802.1Q tag, or a segment a `VLANSource`
```

Line 188:

```text
named. It is never inferred from an address: 10.10.40.0/24
```

Line 189:

```text
looks like VLAN 40 and reading the third octet is right on one
```

Line 190:

```text
network and confidently wrong on the next.
```

Line 206:

```text
One v6 address, not the six a modern Mac holds: the rest are
```

Line 207:

```text
temporary privacy addresses that rotate, and listing them
```

Line 208:

```text
turns a diagnostic row into a wall.
```

Line 231:

```text
Said explicitly, because it is the one number on this
```

Line 232:

```text
row that did not come off the wire. On an access port
```

Line 233:

```text
the switch strips the tag; this is a declaration.
```

Line 242:

```text
Provenance travels with the claim, the same argument
```

Line 243:

```text
`EvidenceChips` makes about health: a segment on screen
```

Line 244:

```text
can always be traced to whoever said so.
```

Line 261:

```text
/ The four states, in one place.
```

Line 263:

```text
/ 1. Host has an 802.1Q sub-interface → the tag, read off `ifconfig`.
```

Line 264:

```text
/    Both facts when a source also named it: `VLAN 40 · Guest`.
```

Line 265:

```text
/ 2. A source named the segment for an untagged interface → the segment's
```

Line 266:

```text
/    own tag if it declared one, otherwise just the name. This is the
```

Line 267:

```text
/    access-port case, where the switch strips the tag before the frame
```

Line 268:

```text
/    reaches the NIC and the host has no tag of its own to show.
```

Line 269:

```text
/ 3. Untagged and unnamed → **nil**. No badge, no placeholder. The subnet
```

Line 270:

```text
/    in the subtitle is the honest artifact and it is already there.
```

Line 271:

```text
/ 4. Nothing → nil.
```

Line 282:

```text
/ The subtitle competes for width against a `Tag` that pins its own size,
```

Line 283:

```text
/ so it is what truncates. Two drafts lost something that mattered — the
```

Line 284:

```text
/ first ate the device name, the second ate the word *secondary* — and both
```

Line 285:

```text
/ were symptoms of putting four facts in a 380pt row behind an icon.
```

Line 287:

```text
/ The fix is separation rather than abbreviation. **Which interface is the
```

Line 288:

```text
/ path in use is the routing row's question**, and the routing row already
```

Line 289:

```text
/ answers it twice: its summary names the winning interface, and its
```

Line 290:

```text
/ expanded detail lists every default route with the one in use marked.
```

Line 291:

```text
/ Restating it on each interface was a third copy competing for the width
```

Line 292:

```text
/ that the address needs.
```

Line 294:

```text
/ What is left is what an interface row is for: where it is, and what it is
```

Line 295:

```text
/ on. Address and prefix are one token in CIDR form — `10.10.40.12/24`
```

Line 296:

```text
/ rather than `10.10.40.12 · /24`, shorter and how anyone would write it —
```

Line 297:

```text
/ and `en1` is dropped when a segment name is already carrying the row's
```

Line 298:

```text
/ identity, since a BSD device name is the least interesting thing on a row
```

Line 299:

```text
/ that says *Guest*. It stays in the expanded detail.
```

Line 312:

```text
MARK: - Segments
```

Line 314:

```text
/ Only reachable when `VLANRegistry.shared.isAvailable`.
```

Line 330:

```text
MARK: - Diagnostic output
```

Line 332:

```text
/ The result of the last ping or traceroute, in place.
```

Line 334:

```text
/ Monospaced and scrollable rather than a sheet: the output is columns, and
```

Line 335:

```text
/ a popover that opens a window to show four lines of text has lost the
```

Line 336:

```text
/ argument for being a popover.
```

Line 351:

```text
Both axes, and clipped. `fixedSize` gives the text its full
```

Line 352:

```text
intrinsic height, so a horizontal-only ScrollView never clipped the
```

Line 353:

```text
vertical overflow — `maxHeight` bounded the frame while the content
```

Line 354:

```text
drew straight through it and over the rest of the popover. Four
```

Line 355:

```text
lines of ping never reached the bound; a support bundle is hundreds.
```

Line 376:

```text
/ The admin rows plus their footer, with the disclosure state owned locally.
```

Line 378:

```text
/ Exists so `SurfaceRenderer` can capture this section on its own — inside the
```

Line 379:

```text
/ Connections tab it lives below a scroll fold a still capture cannot reach.
```

Line 380:

```text
/ It is the shipping views, composed, not a second drawing of them.
```

Line 395:

```text
MARK: - Footer
```

Line 397:

```text
/ The admin-console footer, and the shape the VLAN console will take.
```

Line 399:

```text
/ Two links, one mechanism. `AdminConsole` is an enum rather than a pair of
```

Line 400:

```text
/ hard-coded buttons precisely so the VLAN case is a `case` and a config key,
```

Line 401:

```text
/ not a second footer with its own layout: adding it later means giving the
```

Line 402:

```text
/ enum a third case and giving `Consoles` a third field.
```

Line 404:

```text
/ The network console's URL **resolves** rather than being stored: with nothing
```

Line 405:

```text
/ in config it is `http://<default gateway>`, which is the router admin page on
```

Line 406:

```text
/ essentially every home and small-office network, and needs no setup. With no
```

Line 407:

```text
/ gateway there is no URL, so the button is absent — the capability rule applied
```

Line 408:

```text
/ to a link.
```

Line 429:

```text
/ Configured URL first, then whatever the case can derive on its own.
```

Line 444:

```text
Nothing to derive. A VLAN console is a controller somebody runs;
```

Line 445:

```text
this machine cannot guess its address, so with no config key and
```

Line 446:

```text
no registered source the entry does not render at all.
```

Line 451:

```text
/ Whether this entry appears. `vlan` additionally requires a registered
```

Line 452:

```text
/ source, so a stray config key alone cannot conjure a VLAN section that
```

Line 453:

```text
/ has no data behind it.
```

## Sources/FleetConsoleApp/Views/NetworkGlance.swift

Line 4:

```text
/ The Network tab: every segment at once, one tile each, no scrolling.
```

Line 6:

```text
/ This tab was the full administration list — internet, three links, routing,
```

Line 7:

```text
/ resolvers, overlays, local fabric, devices, listeners — as disclosure rows a
```

Line 8:

```text
/ screen and a half tall inside a 300pt menu. You scrolled to learn whether
```

Line 9:

```text
/ the VPN was up. Each segment is one tile now, carrying the one reading worth
```

Line 10:

```text
/ a glance; the rows, their probes and the admin consoles are one click away
```

Line 11:

```text
/ in Details, which is where reading at length belongs.
```

Line 47:

```text
MARK: Tiles
```

Line 143:

```text
/ One segment: what it is and its one reading. The whole tile opens Details.
```

Line 184:

```text
/ The full network rows, probes and admin consoles, at reading length.
```

## Sources/FleetConsoleApp/Views/NetworkSection.swift

Line 5:

```text
/ Network rows, built on the shared FleetKit primitives so an interface row and
```

Line 6:

```text
/ a service row are recognisably the same kind of object.
```

Line 21:

```text
MARK: - Ethernet
```

Line 48:

```text
MARK: - Wi-Fi
```

Line 99:

```text
MARK: - Tailscale
```

Line 153:

```text
0…4
```

## Sources/FleetConsoleApp/Views/OverviewView.swift

Line 4:

```text
Compact primitives shared by both menu-bar surfaces. The fixed row height is
```

Line 5:

```text
what lets either popover promise not to scroll.
```

Line 7:

```text
/ Fixed-height single-line row.
```

Line 15:

```text
/ When this row stands for a running process, the pid and its start
```

Line 16:

```text
/ signature — which is what lets the row draw the application's own icon
```

Line 17:

```text
/ instead of `icon`. Both nil is the ordinary case and changes nothing.
```

Line 20:

```text
/ A tool name from `AppIcon.declaredBundleIdentifiers`, for a CLI agent
```

Line 21:

```text
/ that has a desktop app installed to borrow an icon from.
```

Line 79:

```text
/ Uppercased header used inside the compact surfaces.
```

Line 101:

```text
/ "+ N more…" — overflow is stated, never hidden behind a scroll edge.
```

Line 133:

```text
/ Shared popover chrome: the header strip.
```

## Sources/FleetConsoleApp/Views/PopoverView.swift

Line 4:

```text
Services starts with the service rows. Verdict/count chrome lives in the shell;
```

Line 5:

```text
evidence, provenance and safe actions stay with the record they describe.
```

Line 30:

```text
MARK: - Shared alerts
```

Line 59:

```text
MARK: - Shared pieces
```

Line 138:

```text
/ Your own long-running tools, declared in config.json. These are not managed by
```

Line 139:

```text
/ the controller and never will be — but they are yours, so they get a name, a
```

Line 140:

```text
/ port and an uptime here instead of appearing as anonymous unmanaged processes.
```

Line 141:

```text
/ That is the point of the section: it is what the tools' own menu-bar apps were
```

Line 142:

```text
/ telling you, in one place.
```

## Sources/FleetConsoleApp/Views/ProcessesPopover.swift

Line 4:

```text
/ One process ranking, with CPU and memory as explicit sort choices.
```

Line 9:

```text
/ The row awaiting confirmation. Ending a process is not undoable, so it
```

Line 10:

```text
/ gets the same treatment the destructive service verbs get.
```

Line 12:

```text
/ Set when a signal was refused between the click and the syscall.
```

Line 73:

```text
MARK: - Summary
```

Line 76:

```text
/ States worth naming are named; the ordinary majority is not enumerated.
```

Line 77:

```text
/ A line reading "612 sleeping" every time would train you to skip it, and
```

Line 78:

```text
/ then you would skip it on the day it said "1 zombie".
```

Line 94:

```text
MARK: - Lists
```

Line 116:

```text
MARK: - Actions
```

Line 118:

```text
/ Opens the dashboard on Processes with this pid selected. The console
```

Line 119:

```text
/ already has a notification for exactly this — the process heatmap uses it
```

Line 120:

```text
/ to hand a tile off to the inspector — so the menu bar reuses it rather
```

Line 121:

```text
/ than inventing a second route to the same place.
```

Line 136:

```text
MARK: - Row
```

Line 138:

```text
/ One process, at popover density.
```

Line 140:

```text
/ Composed from `CompactRow`'s vocabulary rather than reimplementing it: fixed
```

Line 141:

```text
/ height (rule 5 — this list promises not to scroll within its section), the
```

Line 142:

```text
/ shared `EntityIcon`, the shared hover highlight. What it adds over
```

Line 143:

```text
/ `CompactRow` is a trailing usage figure that has to stay on the baseline
```

Line 144:

```text
/ while the number changes, and the two verbs.
```

Line 147:

```text
/ What the process is, in words — see `ProcessRole`.
```

Line 179:

```text
The state word, only when it is one you would act on. `neutral`
```

Line 180:

```text
covers running/sleeping/idle, which is every process almost all of
```

Line 181:

```text
the time, and a tag on every row is a tag on no row.
```

Line 193:

```text
Reserved, not conditional. The verbs still only appear on hover —
```

Line 194:

```text
a row full of buttons you are not pointing at is noise — but the
```

Line 195:

```text
room they take is held on every row, always.
```

Line 197:

```text
Inserting them into the stack instead moved 46pt of content the
```

Line 198:

```text
instant the pointer arrived: the usage figure is the column this
```

Line 199:

```text
list is read down, and it slid left under the cursor while the
```

Line 200:

```text
name beside it truncated and then untruncated as you moved away.
```

Line 201:

```text
The popover header two levels up already reserves this exact slot
```

Line 202:

```text
for this exact reason; a row is the same argument at row scale.
```

Line 224:

```text
/ Disabled with its reason attached rather than hidden.
```

Line 226:

```text
/ The Processes module already argues this for its context menu: a menu
```

Line 227:

```text
/ that hides the verb invites the question, and a menu that explains it
```

Line 228:

```text
/ teaches the model. Here the reason is usually "the flag is off", which
```

Line 229:

```text
/ is a thing you can go and change — hiding the button would leave no
```

Line 230:

```text
/ trace of the setting existing.
```

Line 241:

```text
/ What it is first; the pid and owner are in the tooltip and the
```

Line 242:

```text
/ inspector, which is where you go once you know you care.
```

Line 259:

```text
/ Colour-coded severity, from the same thresholds the console uses, so
```

Line 260:

```text
/ "busy" cannot mean one thing in the menu bar and another in the window.
```

Line 261:

```text
/ Memory has no equivalent single-machine threshold — 400 MB is normal for
```

Line 262:

```text
/ a browser tab and alarming for a shell — so that list stays achromatic
```

Line 263:

```text
/ and lets the ordering carry the ranking.
```

Line 278:

```text
/ Which of the two weights a list is ranked by.
```

Line 280:

```text
/ Top level rather than nested inside the section: the row is a separate type
```

Line 281:

```text
/ and has to name it, and a nested enum would mean the row referring back up to
```

Line 282:

```text
/ the view that happens to own it today.
```

Line 298:

```text
MARK: - Role
```

Line 300:

```text
/ A process described by what it is to you, from the evidence the app already
```

Line 301:

```text
/ holds: a service the controller launched (with the purpose its agent gave),
```

Line 302:

```text
/ an agent session, an app, a server on a port, or part of macOS. Nil when
```

Line 303:

```text
/ none of those is known, rather than a guess.
```

## Sources/FleetConsoleApp/Views/QuickView.swift

Line 38:

```text
/ A fixed logarithmic scale, not a percentage of a guessed link speed.
```

Line 50:

```text
/ Four instruments sharing the existing probes. No extra collectors or timers.
```

## Sources/FleetConsoleApp/Views/ServicesSection.swift

Line 82:

```text
The state beside the name; under it, what the service
```

Line 83:

```text
is *for* — the purpose its agent declared at launch.
```

Line 84:

```text
The owner and project are in the tooltip and detail.
```

Line 95:

```text
Provenance, not status: how the record entered the registry has
```

Line 96:

```text
no good/bad axis, and it decides what the row's verbs can do.
```

Line 97:

```text
`.neutral` for the same reason the VLAN tag is neutral.
```

Line 127:

```text
1 Hz redraw for the countdown only
```

Line 132:

```text
/ Expanded detail: ownership, evidence, resources, lease and the safe actions.
```

Line 233:

```text
Absent, not disabled, and not merely left to fail at the daemon:
```

Line 234:

```text
a claimed record is one the controller did not start, so every
```

Line 235:

```text
signal verb is refused on the wire. Drawing five buttons that can
```

Line 236:

```text
only return an error is the same mistake as a Full Screen menu
```

Line 237:

```text
item on a window that refuses full screen.
```

Line 286:

```text
/ Unmanaged processes get visibility and read-only actions only. FleetConsole
```

Line 287:

```text
/ will not kill something it did not start (threat model T2).
```

Line 301:

```text
A port number is not wrappable text. Unconstrained it broke as
```

Line 302:

```text
":876" / "5" beside the tag it shares an accessory slot with.
```

## Sources/FleetConsoleApp/Views/TaskComposer.swift

Line 5:

```text
MARK: - Model
```

Line 7:

```text
/ Composes a supervised task and hands it to the controller.
```

Line 9:

```text
/ This is the one surface where the app *asks* the controller to launch
```

Line 10:

```text
/ something — the controller alone launches and reaps, so this is a request
```

Line 11:

```text
/ against the existing `launch` verb, not a new authority. The distinction the
```

Line 12:

```text
/ whole product is built on is kept intact: `claim` buys visibility but not
```

Line 13:

```text
/ authority, while a task composed here is a *launch*, which the controller is
```

Line 14:

```text
/ entitled to supervise and reap.
```

Line 27:

```text
/ Result feedback, surfaced in the window footer.
```

Line 32:

```text
/ Ownership IDs from the local address book and controller profiles.
```

Line 33:

```text
/ Registration does not imply a detected session; operator stays selectable.
```

Line 89:

```text
`submit()` is @MainActor; the completion arrives on the main actor.
```

Line 109:

```text
MARK: - View
```

Line 111:

```text
/ A clean composition surface: define a task and assign it to an agent (or a
```

Line 112:

```text
/ category), then launch it under the controller.
```

Line 241:

```text
MARK: - Window
```

## Sources/FleetConsoleApp/Views/WelcomeView.swift

Line 5:

```text
The first-launch welcome.
```

Line 7:

```text
One window, shown once: a menu-bar app that opens a console window on first
```

Line 8:

```text
launch has buried its own premise — the app *is* the menu-bar item, and the
```

Line 9:

```text
welcome exists to say that, show what the console looks like, and get out of
```

Line 10:

```text
the way. The pitch is one sentence, then a live RetroGauge sweep — the
```

Line 11:

```text
instrument a new user has not met yet, doing the one thing that sells it.
```

Line 13:

```text
Shown once, persisted in UserDefaults. The animation can be skipped at any
```

Line 14:

```text
time (the button works from the first frame, and Escape dismisses), and the
```

Line 15:

```text
option to suppress the welcome entirely* is premium — the onboarding is
```

Line 16:

```text
part of what a trial evaluates. See FleetCore/License.swift.
```

Line 18:

```text
Colour and type: every visible value is a token — ConsoleColor, ConsoleFont,
```

Line 19:

```text
ConsoleMetrics, StatusTone. The audit's job is to keep it that way.
```

Line 21:

```text
/ First-launch state. Kept in one tiny type because three places need the
```

Line 22:

```text
/ same answer: the delegate (should it open), the view (did it already), and
```

Line 23:

```text
/ the menu (reset for support calls).
```

Line 34:

```text
/ Whether the welcome should appear for this launch. Reading it *marks*
```

Line 35:

```text
/ the welcome as shown, so it is called exactly once, by the delegate —
```

Line 36:

```text
/ a flag that two call sites both check is a welcome that appears twice.
```

Line 45:

```text
MARK: - Window controller
```

Line 47:

```text
/ The welcome's AppKit shell: a titled, hidden-titlebar window whose close
```

Line 48:

```text
/ button and the view's own dismiss are the same exit. `isReleasedWhenClosed
```

Line 49:

```text
/ = false` so the controller can hand the window back on replay without
```

Line 50:

```text
/ rebuilding it, and `windowWillClose` nils the reference so a closed window
```

Line 51:

```text
/ is never re-shown as a live one.
```

Line 91:

```text
The window's close button and the view's own dismiss are the same exit;
```

Line 92:

```text
without this the AppKit close would strand the controller's reference.
```

Line 98:

```text
MARK: - View
```

Line 104:

```text
/ The skip option is the premium feature; the *Skip button* below is not
```

Line 105:

```text
/ — skipping one showing and suppressing the welcome for every launch are
```

Line 106:

```text
/ different asks, and only the second is gated.
```

Line 119:

```text
Escape dismisses; the animation's own skip affordance is the button.
```

## Sources/FleetConsoleApp/main.swift

Line 6:

```text
FleetConsole — one menu-bar control over one controller.
```

Line 8:

```text
▣ Fleet — services, agents, and connections in one popover.
```

Line 10:

```text
One status item keeps one app represented by one persistent mark. Its popover
```

Line 11:

```text
carries the operational and network surfaces as tabs.
```

Line 15:

```text
/ Sent by a second launch to the instance that is already running.
```

Line 43:

```text
One instance, two items. Without this guard a second launch adds another
```

Line 44:

```text
set of icons to the menu bar and another subscription to the controller,
```

Line 45:

```text
and the copies are indistinguishable to anyone looking at the menu bar.
```

Line 50:

```text
The main menu: ⌘K/⌘R/⌘1…⌘6 and the standard Edit items that make
```

Line 51:

```text
text fields behave. Commands route to the console window via
```

Line 52:

```text
ConsoleCommand notifications; with no window open they are no-ops.
```

Line 67:

```text
The readings are the item: one fixed silhouette at every
```

Line 68:

```text
state, with urgency carried by the alert beside it.
```

Line 92:

```text
/ The welcome shows once, on the first launch that was not handed off to
```

Line 93:

```text
/ a running instance. `consumePending()` marks it as shown in the same
```

Line 94:

```text
/ read, so a `--dashboard` first launch still counts — burying the
```

Line 95:

```text
/ welcome because the console opened headless would be the app skipping
```

Line 96:

```text
/ its own onboarding.
```

Line 98:

```text
/ The *skip* preference is premium-gated at render: the setting can be
```

Line 99:

```text
/ toggled only where the license allows (see WelcomeView), and it is
```

Line 100:

```text
/ honoured here without re-checking the licence, so downgrading cannot
```

Line 101:

```text
/ resurrect the window.
```

Line 114:

```text
/ If FleetConsole is already running, hand this launch's intent to it and quit.
```

Line 132:

```text
/ One tracking loop drives both items; the 1 Hz lease clock is deliberately
```

Line 133:

```text
/ not read here, so countdowns never cause a menu-bar redraw.
```

Line 148:

```text
/ The status item's dropdown — right-click, or ⌃-click, on the menu-bar item.
```

Line 150:

```text
/ Three things were wrong with the previous version and all three were the
```

Line 151:

```text
/ same mistake, which is a menu describing something the app does not do.
```

Line 153:

```text
/ **Key equivalents that were not bound anywhere.** `Open Dashboard…` drew
```

Line 154:

```text
/ ⌘D and `Run Reconciliation Sweep` drew ⌘R, and nothing registered either
```

Line 155:

```text
/ one — a status-item menu's equivalents are live only while that menu is
```

Line 156:

```text
/ open, and the app's real binding for the dashboard is ⌘0 in the View menu.
```

Line 157:

```text
/ So the dropdown advertised a second, non-working shortcut for a command
```

Line 158:

```text
/ that already had a working one, and a ⌘R that collides on sight with
```

Line 159:

```text
/ View → Refresh. Rule 10 with the window swapped for the menu bar: a
```

Line 160:

```text
/ shortcut you can read and cannot press is worse than no shortcut.
```

Line 162:

```text
/ **Ellipses on commands that complete immediately.** macOS reserves the
```

Line 163:

```text
/ ellipsis for a command that needs more input before it can finish.
```

Line 164:

```text
/ Opening a window and opening a file in your editor both complete on the
```

Line 165:

```text
/ click, so neither gets one. The two destructive service actions in the
```

Line 166:

```text
/ popover keep theirs, because those really do raise a confirmation.
```

Line 168:

```text
/ **No route to what the app is for.** The dropdown listed maintenance
```

Line 169:

```text
/ verbs and no destinations, so reaching the process table from the menu
```

Line 170:

```text
/ bar meant opening the dashboard and then navigating. The modules are now
```

Line 171:

```text
/ listed directly, generated from `ConsoleModule.allCases` by the same
```

Line 172:

```text
/ builder the View menu uses.
```

Line 174:

```text
/ Grouping is `NSMenuItem.sectionHeader`, which is AppKit's own inline
```

Line 175:

```text
/ header — it draws the system's small-caps grey label and carries its own
```

Line 176:

```text
/ spacing, so a separator either side of it would be double-ruling.
```

Line 244:

```text
The welcome is shown once; this is the way back for a support call
```

Line 245:

```text
or a fresh look — re-marking it unseen and presenting it now.
```

Line 261:

```text
/ Named Quick View, Network and Agents actions select their section before
```

Line 262:

```text
/ opening it; dashboard commands keep their existing window route.
```

Line 278:

```text
/ Opens the Task Composer: compose a task and hand it to the controller.
```

Line 289:

```text
/ Replays the first-launch welcome. Resets the once-flag *and* honours
```

Line 290:

```text
/ the premium skip preference — replaying is an explicit ask, so the skip
```

Line 291:

```text
/ setting does not apply to it (it governs launches, not requests).
```

Line 307:

```text
MARK: - Service management
```

Line 309:

```text
The controller is a launchd user agent registered through SMAppService.
```

Line 310:

```text
launchd — not this app — keeps it alive, so leases keep expiring and leaked
```

Line 311:

```text
processes keep being reaped with the UI closed.
```

Line 332:

```text
Top-level code is not main-actor isolated in Swift 5 mode, but it does run on
```

Line 333:

```text
the main thread — which is exactly what assumeIsolated asserts.
```

Line 352:

```text
Compiled in only by Scripts/surface-sheet.sh, which passes
```

Line 353:

```text
-DFLEET_SURFACE_RENDERER. Runs the whole UI against fixtures, writes a PNG
```

Line 354:

```text
per surface, and exits without ever putting an item in the menu bar.
```

Line 356:

```text
Validate the bounded fixture mode before any live-verification entrypoint.
```

Line 366:

```text
Review bundles expose a normal window to native accessibility automation.
```

Line 367:

```text
Shipping builds remain menu-bar apps.
```

## Sources/FleetCore/AgentCost.swift

Line 3:

```text
Daily agent spend.
```

Line 5:

```text
What an agent cost you today, where the figure came from, and — the part that
```

Line 6:

```text
matters most — the difference between "nothing" and "nobody knows". Ported
```

Line 7:

```text
from Masterwork Bar's `src/spend.rs`, which is the only capability that app
```

Line 8:

```text
had and this one did not. See the vault's Apple Menu merge recommendation.
```

Line 10:

```text
Everything in this file is pure: no filesystem, no clock, no database. The
```

Line 11:

```text
day being priced arrives as a `DateInterval` and the transcript arrives as a
```

Line 12:

```text
`String`, so the whole pricing path is fixture-testable and none of it can
```

Line 13:

```text
drift with the machine's timezone at test time. `AgentCostScanner` owns the
```

Line 14:

```text
IO and nothing else does.
```

Line 16:

```text
MARK: - Where a number came from
```

Line 18:

```text
/ Provenance for one agent's figure, so an unknown can say *why* it is unknown
```

Line 19:

```text
/ rather than presenting itself as zero spend.
```

Line 21:

```text
/ The four cases are four genuinely different situations, and collapsing any
```

Line 22:

```text
/ two of them loses something the operator needs: a tool that publishes no
```

Line 23:

```text
/ usage record is a permanent gap you cannot close, while a directory that
```

Line 24:

```text
/ would not open is a fault you can go and fix.
```

Line 26:

```text
/ Session transcripts this app priced itself, from published list prices.
```

Line 28:

```text
/ A cost the tool had already computed, read back out of its own store.
```

Line 29:

```text
/ Nothing here is priced — the number is the tool's, and is authoritative.
```

Line 31:

```text
/ The tool records no usage this app can price. Not a fault, and not
```

Line 32:

```text
/ fixable: there is nothing on disk to read.
```

Line 34:

```text
/ The tool is not on this machine. Distinct from `unpublished` because it
```

Line 35:

```text
/ is not permanent — installing the tool closes it — and distinct from
```

Line 36:

```text
/ `unreadable` because nothing is broken.
```

Line 38:

```text
/ A record that should have been readable and was not.
```

Line 41:

```text
/ One short line for the row, in the operator's terms rather than ours.
```

Line 57:

```text
/ Whether the gap is worth a warning tone. An unpublished record is a
```

Line 58:

```text
/ permanent, blameless absence; an unreadable one is a fault.
```

Line 65:

```text
MARK: - The contract
```

Line 67:

```text
/ What one agent cost today.
```

Line 69:

```text
/ `amountUSD` is optional and that is the whole point of the type. Masterwork
```

Line 70:

```text
/ Bar carried the same distinction as a parallel `bool`, which is a shape that
```

Line 71:

```text
/ lets a caller read the number without reading the flag; here the compiler
```

Line 72:

```text
/ makes you handle the gap. **An unknown is never rendered as `$0.00`** — a
```

Line 73:

```text
/ zero is a claim that the agent ran for free, and for `gemini` and `aider` we
```

Line 74:

```text
/ have no grounds for that claim at all.
```

Line 76:

```text
/ Joins to `AgentProfile.id`, so the Agents section can render cost on the
```

Line 77:

```text
/ row it already draws rather than opening a second list of agents.
```

Line 79:

```text
/ `nil` means unknown. See the type's note.
```

Line 81:

```text
/ The most recent priced activity, which answers "is this figure stale?"
```

Line 82:

```text
/ without a second query.
```

Line 99:

```text
/ Every agent's figure plus the rollup, which has to be honest about its own
```

Line 100:

```text
/ coverage: a total that silently omits two unpriceable agents reads as the
```

Line 101:

```text
/ whole day's spend and is not.
```

Line 111:

```text
/ The sum of what could be priced. Unknowns are excluded rather than
```

Line 112:

```text
/ added as zero, and `unknownCount` is what stops that being a lie.
```

Line 117:

```text
/ How many agents could not be priced at all.
```

Line 122:

```text
/ Agents that are unknown because something broke, as opposed to agents
```

Line 123:

```text
/ that were never priceable. Only this kind is worth surfacing as a fault.
```

Line 133:

```text
MARK: - Prices
```

Line 135:

```text
/ Published list price per million tokens, in USD.
```

Line 150:

```text
/ Token counts for one priced turn, already normalised so that `input` never
```

Line 151:

```text
/ double-counts what `cacheRead` covers.
```

Line 153:

```text
/ The normalisation is load-bearing, because the two providers disagree about
```

Line 154:

```text
/ it: Claude reports cache reads in their own field alongside a separate
```

Line 155:

```text
/ `input_tokens`, while Codex reports a single `input_tokens` that *includes*
```

Line 156:

```text
/ `cached_input_tokens`. Subtracting at the parse boundary means one cost
```

Line 157:

```text
/ function serves both and neither provider's convention leaks past it.
```

Line 173:

```text
/ The rate tables, written down rather than fetched.
```

Line 175:

```text
/ A menu-bar app that phoned a pricing endpoint to draw a row would be trading
```

Line 176:

```text
/ its "no network listener, no telemetry" posture for two decimal places. The
```

Line 177:

```text
/ cost of writing them down is that they go stale — which is visible the first
```

Line 178:

```text
/ time the figure disagrees with a provider's own bill, and is the reason
```

Line 179:

```text
/ `AgentCostSource` records that *we* did the pricing.
```

Line 187:

```text
/ Codex bills a cached input token at a tenth of a fresh one and writes
```

Line 188:

```text
/ nothing, so `cacheWrite` is genuinely zero rather than unknown.
```

Line 192:

```text
/ Sonnet is the fallback for an unrecognised model, deliberately. A future
```

Line 193:

```text
/ Claude model priced as Sonnet is wrong by a factor of five at worst; one
```

Line 194:

```text
/ priced at zero is wrong by the whole amount and looks like a free day.
```

Line 210:

```text
MARK: - Parsing
```

Line 212:

```text
/ One priced turn out of a transcript.
```

Line 223:

```text
/ Transcript line → priced turn. Pure, and the only place a provider's on-disk
```

Line 224:

```text
/ shape is known.
```

Line 227:

```text
/ A cheap substring test before `JSONSerialization` touches the line.
```

Line 229:

```text
/ This is not premature: a working day of Claude transcripts is hundreds of
```

Line 230:

```text
/ megabytes across thousands of lines, the overwhelming majority of which
```

Line 231:

```text
/ carry no usage at all, and parsing each one to discover that is the
```

Line 232:

```text
/ difference between a menu-bar refresh and a visible stall.
```

Line 237:

```text
/ One line of a Claude Code transcript.
```

Line 239:

```text
/ Returns `nil` for a line with no usage, a line stamped outside `day`, and
```

Line 240:

```text
/ a **synthetic** model — those turns are replayed locally and were never
```

Line 241:

```text
/ billed, so pricing them would invent spend that no invoice will show.
```

Line 248:

```text
Two transcript generations: the usage and model either sit under
```

Line 249:

```text
`message` or at the top level. Both are still on disk on this machine.
```

Line 268:

```text
/ One line of a Codex session log.
```

Line 270:

```text
/ `input_tokens` here is inclusive of `cached_input_tokens`, so the cached
```

Line 271:

```text
/ share is subtracted before pricing — see `TokenUsage`. The subtraction is
```

Line 272:

```text
/ floored at zero: a malformed line reporting more cached than total input
```

Line 273:

```text
/ would otherwise produce a negative cost and quietly reduce the day's bill.
```

Line 294:

```text
/ One `message.data` blob out of opencode's own database. Nothing is priced
```

Line 295:

```text
/ here: opencode records the cost it was charged, so that figure is better
```

Line 296:

```text
/ than any table we could keep. A row with no creation time dates to
```

Line 297:

```text
/ `distantPast`, which loses to every real timestamp in the `max` the
```

Line 298:

```text
/ scanner runs — the same outcome as skipping it, without a second shape.
```

Line 307:

```text
MARK: Primitives
```

Line 316:

```text
/ Two formatters, built once.
```

Line 318:

```text
/ A day of transcripts reaches this path a few thousand times and each
```

Line 319:

```text
/ `ISO8601DateFormatter()` builds an internal `CFDateFormatter`, so
```

Line 320:

```text
/ allocating per line is pure waste. `nonisolated(unsafe)` is the honest
```

Line 321:

```text
/ declaration: the instances are configured at init and never mutated
```

Line 322:

```text
/ again, and `date(from:)` on an unmutated formatter is a read.
```

Line 335:

```text
/ RFC 3339 with or without fractional seconds, and only if it lands inside
```

Line 336:

```text
/ `day`. Both spellings appear in the same directory.
```

Line 338:

```text
/ Half-open on purpose: `DateInterval.contains` includes its end, which
```

Line 339:

```text
/ would price a turn stamped exactly at midnight into both days.
```

Line 348:

```text
/ A token count that may arrive as either JSON number type, or be absent.
```

## Sources/FleetCore/AgentCostScanner.swift

Line 3:

```text
The IO half of daily spend. Everything that touches the filesystem or a
```

Line 4:

```text
database lives here; `AgentCost.swift` stays pure so the pricing can be
```

Line 5:

```text
tested from fixtures. See the header there.
```

Line 7:

```text
This reads other tools' private records, read-only and never in place: a
```

Line 8:

```text
transcript is memory-mapped, opencode's database is opened `SQLITE_OPEN_READONLY`,
```

Line 9:

```text
and nothing here writes, moves or locks a file belonging to another app. A
```

Line 10:

```text
scan that cannot read something reports that as a source, never as a zero.
```

Line 12:

```text
/ Walks each agent's own usage record and prices today.
```

Line 14:

```text
/ Constructed with an explicit `home` and `calendar` so the whole scan can be
```

Line 15:

```text
/ pointed at a fixture tree in a test without a process-wide environment
```

Line 16:

```text
/ change, and so "today" is the operator's local day rather than UTC — spend
```

Line 17:

```text
/ is something you compare against a daily habit, not a billing period.
```

Line 28:

```text
/ Every tool this app knows how to look for, in the order the popover
```

Line 29:

```text
/ lists them. A tool absent from the machine still gets a snapshot — the
```

Line 30:

```text
/ display layer joins by agent id, so it simply never draws a row.
```

Line 46:

```text
/ The operator's local day, half-open. See `AgentCostParser.timestamp`.
```

Line 54:

```text
MARK: - Claude Code
```

Line 56:

```text
/ `~/.claude/projects/<project>/<session>.jsonl`, one JSON object per turn.
```

Line 90:

```text
MARK: - Codex
```

Line 92:

```text
/ `~/.codex/sessions/YYYY/MM/DD/*.jsonl`. Yesterday's directory is scanned
```

Line 93:

```text
/ too: a session opened before midnight keeps writing into the directory it
```

Line 94:

```text
/ started in, so today's turns land in yesterday's folder. The line-level
```

Line 95:

```text
/ timestamp is what actually decides the day — the directory is only a
```

Line 96:

```text
/ cheap way to avoid walking the whole archive.
```

Line 129:

```text
MARK: - opencode
```

Line 131:

```text
/ opencode keeps its own SQLite store and records the cost it was charged,
```

Line 132:

```text
/ so this reads rather than prices.
```

Line 134:

```text
/ Masterwork Bar shelled out to the `sqlite3` binary here. We already link
```

Line 135:

```text
/ libsqlite3 for the registry and `SQLiteDB` already handles the read-only
```

Line 136:

```text
/ open — including the WAL fallback, which matters precisely because the
```

Line 137:

```text
/ database being read belongs to a process that may be running right now.
```

Line 150:

```text
Milliseconds: opencode stamps `time_created` the way JavaScript does.
```

Line 172:

```text
MARK: - Reading
```

Line 174:

```text
/ `.jsonl` files in `directory` whose contents changed on or after `since`.
```

Line 176:

```text
/ The mtime filter is a prefilter and nothing more — a file it lets through
```

Line 177:

```text
/ still has every line's timestamp checked. It exists because the archive
```

Line 178:

```text
/ grows without bound and re-reading a year of transcripts to price one day
```

Line 179:

```text
/ would turn a menu-bar refresh into a stall.
```

Line 192:

```text
/ Memory-mapped and split on newlines, so a multi-hundred-megabyte
```

Line 193:

```text
/ transcript costs address space rather than resident memory. A file that
```

Line 194:

```text
/ will not map, or a line that is not UTF-8, is skipped: one unreadable
```

Line 195:

```text
/ transcript must not take the whole day's figure down with it.
```

Line 204:

```text
/ The message without the type name, so a row reads as a sentence.
```

## Sources/FleetCore/AgentRegistration.swift

Line 23:

```text
/ A client-local address book of agent ownership IDs, not a session registry.
```

Line 24:

```text
/ Adding an ID neither launches a process nor changes the controller's records.
```

Line 88:

```text
/ Registered IDs and controller-observed ownership stay distinct. A registered
```

Line 89:

```text
/ ID without a matching profile has no invented service, session or activity.
```

Line 121:

```text
/ A bounded menu glance, not a shortened source of truth. The full entries and
```

Line 122:

```text
/ explicit overflow count feed a separate manager; detected sessions lead.
```

## Sources/FleetCore/Agents.swift

Line 3:

```text
Agents: their sessions, their mailbox, and the profiles the UI groups them by.
```

Line 4:

```text
Sessions are ordinary processes rather than managed services; the mailbox lets
```

Line 5:

```text
one ask a question without the operator watching a terminal.
```

Line 6:

```text
MARK: - Agent sessions
```

Line 8:

```text
The coding agents you actually run — Claude Code, Codex, Gemini CLI, opencode,
```

Line 9:

```text
aider — are ordinary processes, not services launched through the controller.
```

Line 10:

```text
They are the thing you most want to see ("who is working right now, in which
```

Line 11:

```text
project"), so they are detected directly rather than requiring registration.
```

Line 13:

```text
/ Who wrote the line a preview is showing. A tool result and a sentence the
```

Line 14:

```text
/ agent wrote are different kinds of evidence about what it is doing, and
```

Line 15:

```text
/ flattening them into one grey line loses the distinction that matters.
```

Line 17:

```text
the agent said something
```

Line 18:

```text
you (or a tool result) said something to it
```

Line 19:

```text
the agent invoked a tool
```

Line 43:

```text
/ Working directory, i.e. the project it is operating on.
```

Line 50:

```text
MARK: Live transcript
```

Line 52:

```text
A session row that says "claude · fleet-console · pid 14446" answers *that*
```

Line 53:

```text
an agent is running, which you could already see in Activity Monitor. What
```

Line 54:

```text
you actually want to know is what it is doing right now, and for the tools
```

Line 55:

```text
that keep a transcript on disk that is readable without asking the agent.
```

Line 56:

```text
Everything below is nil when there is no transcript to read — an absent
```

Line 57:

```text
preview is the honest rendering of "this tool does not publish one".
```

Line 59:

```text
/ The session identifier the tool itself uses — the "uid" in the transcript
```

Line 60:

```text
/ filename. Shown so a row can be tied back to a resumable session.
```

Line 62:

```text
/ The tool's own name for the session, when it has one.
```

Line 64:

```text
/ Absolute path of the transcript the preview was read from.
```

Line 66:

```text
/ The most recent turn, trimmed to one line.
```

Line 97:

```text
/ "said 12s ago" — the age of the transcript line, not of the process.
```

Line 104:

```text
MARK: - Agent messages
```

Line 106:

```text
A local mailbox so an agent can say something and get an answer without the
```

Line 107:

```text
operator having to be watching a terminal. Messages are append-only; a reply is
```

Line 108:

```text
the one field that can be written afterwards, and it is written exactly once.
```

Line 111:

```text
"here is what I did"
```

Line 112:

```text
needs a human answer before the agent can continue
```

Line 113:

```text
something went wrong and the agent stopped
```

Line 140:

```text
/ Set when the agent wants an answer; drives the unanswered badge.
```

Line 144:

```text
/ Whether the operator has seen it (notifications fire once).
```

Line 167:

```text
MARK: - Agents
```

Line 169:

```text
Ownership is the point of the registry, so it deserves to be a view of its own:
```

Line 170:

```text
"what has this agent left running, and when does it all expire" is the question
```

Line 171:

```text
you actually ask when an agent has gone quiet.
```

Line 173:

```text
/ Everything known about one agent: what it is doing now, what it has done, and
```

Line 174:

```text
/ what it has said.
```

Line 178:

```text
Now
```

Line 179:

```text
/ Records owned and not finished; see `AgentSummary.owned`.
```

Line 189:

```text
History
```

Line 193:

```text
/ Services the controller had to reap because this agent stopped renewing.
```

Line 204:

```text
Mailbox
```

Line 213:

```text
/ One line that is true whether the agent is busy or has been idle for days.
```

Line 231:

```text
/ How trustworthy this agent's cleanup has been, as a plain fraction.
```

Line 252:

```text
/ Records this agent owns that are not finished — the set `running` is drawn
```

Line 253:

```text
/ from. It exists so a row can tell "owns nothing" apart from "owns
```

Line 254:

```text
/ something, none of it running", which are the same number and not the same
```

Line 255:

```text
/ fact: an agent whose only service expired had a blank where its siblings
```

Line 256:

```text
/ had counts, which reads as a row that failed to render.
```

Line 265:

```text
/ Distinct purposes, so a summary line can say what the agent is doing.
```

## Sources/FleetCore/CBuffer.swift

Line 3:

```text
The app's probes and the daemon's device prober both hand buffers to C, so the
```

Line 4:

```text
conversion they share lives here rather than once per target.
```

Line 7:

```text
/ A string from a NUL-terminated `CChar` buffer filled in by a C call.
```

Line 9:

```text
/ `String(cString:)`'s array overload is deprecated under Swift 6, which asks
```

Line 10:

```text
/ the caller to truncate where the invariant is known. It is known here —
```

Line 11:

```text
/ `sysctlbyname` and `getnameinfo` both NUL-terminate — so take everything
```

Line 12:

```text
/ before the first NUL. What follows it is leftover buffer, not text.
```

## Sources/FleetCore/Codec.swift

Line 3:

```text
/ One encoder/decoder pair shared by the daemon, the CLI and the app so wire
```

Line 4:

```text
/ formats can never drift (dates are always epoch seconds).
```

## Sources/FleetCore/Config.swift

Line 3:

```text
/ User-editable configuration. Written with defaults on first daemon start.
```

Line 4:

```text
/ The allow-list of "boring" listeners lives here, so adding one is an explicit,
```

Line 5:

```text
/ reviewable act (threat model T4).
```

Line 10:

```text
/ Leases longer than this are clamped. Prevents "effectively forever".
```

Line 13:

```text
/ Grace period between SIGTERM and SIGKILL.
```

Line 15:

```text
/ Evidence older than tick * this factor renders as "unknown (stale)".
```

Line 17:

```text
/ How long a newly discovered unmanaged process stays in "Needs attention".
```

Line 18:

```text
/ After this it is still listed as Unmanaged, but it stops being an alert:
```

Line 19:

```text
/ a listener that has been up for hours is furniture, not an incident.
```

Line 21:

```text
/ How long a crashed service stays in "Needs attention".
```

Line 24:

```text
/ Commands whose listeners are expected and are not flagged as unmanaged.
```

Line 26:

```text
/ Ports that are never flagged (e.g. system services you accept).
```

Line 28:

```text
/ Listeners at or above this port are treated as ephemeral and not flagged.
```

Line 29:

```text
/ The dynamic range is where short-lived helpers land; each one that appears
```

Line 30:

```text
/ and vanishes would otherwise write a `becameUnmanaged` event and briefly
```

Line 31:

```text
/ raise an alert for something nobody can act on. Set to 0 to flag everything.
```

Line 33:

```text
/ Argv substrings that make a *non-listening* process look like a dev server.
```

Line 36:

```text
/ Your own long-running tools. Anything matching one of these is shown as a
```

Line 37:

```text
/ named local tool instead of being flagged as an unmanaged process.
```

Line 43:

```text
/ Matched against the full command line, case-insensitively.
```

Line 45:

```text
/ Ports it is expected to listen on; also used for matching.
```

Line 47:

```text
/ Opened when you click the row.
```

Line 72:

```text
/ What the app shows, how often it looks, and which guarded verbs are
```

Line 73:

```text
/ unlocked. Every field has a default that makes the app correct with no
```

Line 74:

```text
/ config file at all — the block exists so a section can be turned *off*,
```

Line 75:

```text
/ not so it can be turned on.
```

Line 78:

```text
/ Zero setup by default. Each nested struct decodes field-by-field with a
```

Line 79:

```text
/ fallback, the same contract as `FleetConfig` itself: a key from a later
```

Line 80:

```text
/ version must not make the file undecodable, and a key you delete must
```

Line 81:

```text
/ fall back rather than fail the load.
```

Line 88:

```text
/ Which surfaces render. A section switched off is *absent*, not
```

Line 89:

```text
/ greyed: a control you can see and cannot use is the same dead chrome
```

Line 90:

```text
/ rule 10 bans from the menus.
```

Line 121:

```text
/ Cadences, clamped on read. A zero or negative interval in a
```

Line 122:

```text
/ hand-edited file would otherwise mean "sample continuously", which
```

Line 123:

```text
/ is a `ps -Ao` over every process on the machine in a tight loop.
```

Line 124:

```text
/ Two cadences, because the app runs two samplers.
```

Line 126:

```text
/ There was a third — `routingRefreshSec`, default 30 — and it was read
```

Line 127:

```text
/ by nothing. It was documented in README.md, clamped here and asserted
```

Line 128:

```text
/ by a test, which is three places agreeing about a knob that turned
```

Line 129:

```text
/ nothing: routing is captured *inside* `NetworkMonitor.refresh()`, in
```

Line 130:

```text
/ the same pass and off the same `readHardwarePorts()` as every other
```

Line 131:

```text
/ probe, so it has always run on `networkRefreshSec`.
```

Line 133:

```text
/ Removed rather than wired up, and that is the interesting half. A
```

Line 134:

```text
/ separate timer would mean a second overlapping probe pass forking its
```

Line 135:

```text
/ own `netstat`, `ifconfig` and `scutil` and re-reading the hardware
```

Line 136:

```text
/ ports that `RoutingProbe.capture` already takes as an argument —
```

Line 137:

```text
/ paying twice to make the picture *less* coherent, since the gateway
```

Line 138:

```text
/ and the Wi-Fi state it is read against would then come from two
```

Line 139:

```text
/ different moments. The single pass is the right design; the config key
```

Line 140:

```text
/ was describing one that was never built. An existing config.json with
```

Line 141:

```text
/ the key still loads — unknown keys are ignored — and now says nothing
```

Line 142:

```text
/ instead of saying something false.
```

Line 160:

```text
/ The floors are not taste. `ps -Ao` over every process costs far
```

Line 161:

```text
/ more than reading a Mach counter, and `netstat -rn` plus
```

Line 162:

```text
/ `scutil --dns` fork two more; below these a "refresh" is just a
```

Line 163:

```text
/ second copy of the previous one still running.
```

Line 168:

```text
/ Verbs that stay locked until you say otherwise.
```

Line 170:

```text
/ Unlocks **End Process** on the Processes surface.
```

Line 172:

```text
/ Off by default, and off is the honest default: FleetConsole's
```

Line 173:

```text
/ standing rule is that the *controller* never signals a process it
```

Line 174:

```text
/ did not start, because a recycled PID must never be hit. This
```

Line 175:

```text
/ flag does not weaken that rule — the controller still refuses.
```

Line 176:

```text
/ It unlocks a separate, narrower thing: a signal **you** send, to
```

Line 177:

```text
/ a process **you** own, from a row you are looking at, after the
```

Line 178:

```text
/ app has re-read the process's start signature and confirmed the
```

Line 179:

```text
/ PID is still the one the row was drawn from. Three gates, all of
```

Line 180:

```text
/ which have to hold; this is the one you control.
```

Line 183:

```text
/ Shows what each agent cost you today in the Agents section.
```

Line 185:

```text
/ Off until the figures have been checked against a provider's own
```

Line 186:

```text
/ bill on this machine. The prices are a table written down in
```

Line 187:

```text
/ `AgentPricing` rather than fetched, so the first thing a wrong
```

Line 188:

```text
/ entry does is put a confident, wrong number on screen — and a
```

Line 189:

```text
/ spend figure nobody has verified is worse than no figure, because
```

Line 190:

```text
/ it will be believed. Turn it on once, deliberately, after
```

Line 191:

```text
/ comparing a day.
```

Line 209:

```text
/ Where the "open the admin console" footers point.
```

Line 211:

```text
/ `network` is `nil` by default and *resolves* to `http://<default
```

Line 212:

```text
/ gateway>` at render time, so the footer works on first launch with no
```

Line 213:

```text
/ configuration and without this file inventing a URL it cannot know.
```

Line 214:

```text
/ A machine with no default route has no gateway, so the footer does
```

Line 215:

```text
/ not render — that is the capability rule, applied to a link.
```

Line 217:

```text
/ `vlan` is the documented seam for the VLAN admin console. It is
```

Line 218:

```text
/ `nil` here and there is no VLAN source registered, so nothing in the
```

Line 219:

```text
/ UI mentions VLAN segments today. See `VLANSource`.
```

Line 256:

```text
/ The VLAN segments this fleet is divided into, as **you** declare them.
```

Line 258:

```text
/ This exists because of a gap the host cannot close on its own. A Mac on a
```

Line 259:

```text
/ trunk port reads its own 802.1Q tag off `ifconfig`; a Mac on an access
```

Line 260:

```text
/ port — which is almost every Mac — never sees a tag at all, because the
```

Line 261:

```text
/ switch strips it before the frame reaches the NIC. All the host gets is a
```

Line 262:

```text
/ subnet and a gateway.
```

Line 264:

```text
/ FleetConsole will not bridge that gap by guessing. `10.10.40.0/24` looks
```

Line 265:

```text
/ like VLAN 40 and an app that infers it is right on your network and wrong
```

Line 266:

```text
/ on anyone who numbered theirs differently. But *you* know, and saying so
```

Line 267:

```text
/ here is an assertion with an author, which is a different thing from a
```

Line 268:

```text
/ heuristic — the same distinction `ignoredListenerCommands` draws.
```

Line 270:

```text
/ Empty by default. Nothing renders until something is declared.
```

Line 274:

```text
/ 802.1Q tag. Optional, because a segment can be a subnet you have
```

Line 275:

```text
/ separated without giving it a number.
```

Line 278:

```text
/ The subnet, in CIDR. This is what matches a host interface on an
```

Line 279:

```text
/ access port, where there is no tag to match on.
```

Line 314:

```text
/ Set for the machine FleetConsole itself runs on.
```

Line 316:

```text
/ Opt-in: fetch that machine's managed services read-only over SSH.
```

Line 317:

```text
/ Off by default — it runs a command on another host.
```

Line 319:

```text
/ `user@host` for SSH; falls back to the probe target.
```

Line 321:

```text
/ Path to fleetctl on that machine, if it is not on the default PATH.
```

Line 324:

```text
/ Services declared to be running *on that machine*, matched over SSH.
```

Line 326:

```text
/ `knownServices` is the same idea for this machine, and it cannot be
```

Line 327:

```text
/ used here: it matches the local process table. The two services that
```

Line 328:

```text
/ motivated this — a Buzz relay and an opencode server on another Mac —
```

Line 329:

```text
/ are reachable by none of the mechanisms that existed. The relay makes
```

Line 330:

```text
/ an *outbound* WebSocket connection and never listens, so there is no
```

Line 331:

```text
/ port to probe; the opencode server listens on the remote's loopback,
```

Line 332:

```text
/ so its port is unreachable from here by construction; and the
```

Line 333:

```text
/ `remoteQuery` path needs that machine to have `fleetctl` installed,
```

Line 334:

```text
/ which it does not.
```

Line 336:

```text
/ So: declare them, and match them over the SSH trust you already have.
```

Line 337:

```text
/ Read-only, like everything else across the mesh — the records these
```

Line 338:

```text
/ produce are marked `claimed`, which is what makes them unsignallable
```

Line 339:

```text
/ rather than merely undisplayed as controls.
```

Line 411:

```text
/ Hand-written and hand-edited: a key added in a later version must not make
```

Line 412:

```text
/ the whole file undecodable, and a key you delete must fall back to the
```

Line 413:

```text
/ default rather than failing the load.
```

Line 445:

```text
/ Inventory entries are explicit user configuration; fresh installs start empty.
```

Line 455:

```text
/ Only this machine is present until the user explicitly links a device.
```

Line 481:

```text
/ Loads config, creating it from defaults if missing. Never throws: a broken
```

Line 482:

```text
/ config must not stop the controller from reaping leaked processes.
```

## Sources/FleetCore/ConsoleLayout.swift

Line 4:

```text
The window's geometry, as arithmetic rather than as taste.
```

Line 6:

```text
Every fixed size in the console used to be an independent judgement call:
```

Line 7:

```text
236 here, 268 there, 280 opposite, 320 beside it, 360 written as a bare
```

Line 8:

```text
literal inside a `private static let` that summed four of the others. Each was
```

Line 9:

```text
defensible on its own and none of them related to any of the rest, so the set
```

Line 10:

```text
could not be checked — and it turned out not to hold. `columnReserve` (what
```

Line 11:

```text
the three columns and the rail must keep) came to 786pt against a window whose
```

Line 12:

```text
minimum content width is `defaultContentSize.width / 2` = 780pt: at the
```

Line 13:

```text
narrowest size the user can drag to, the reserve exceeded the whole window and
```

Line 14:

```text
the module column fell under the floor its own comment sets. The comment
```

Line 15:

```text
beside it described a 1060pt minimum that has not existed for some time.
```

Line 17:

```text
The fix is not better numbers. It is deriving the numbers from two rules and
```

Line 18:

```text
then testing that the derivation holds at every size the window can take:
```

Line 20:

```text
1. **The ladder.** Fixed sizes come from the Fibonacci sequence, so any two
```

Line 21:

```text
of them are in a ratio the eye already reads as ordered, and adjacent
```

Line 22:

```text
steps are far enough apart to be *decisions* rather than the 9pt/9.5pt
```

Line 23:

```text
pair the design audit exists to prevent. The values already in the app
```

Line 24:

```text
were closer to this than anyone had noticed — 236 vs 233, 88 vs 89, 20 vs
```

Line 25:

```text
21, 12 vs 13 — which is the argument for snapping to the ladder rather
```

Line 26:

```text
than inventing a scale: it is what the design was already reaching for.
```

Line 28:

```text
2. **The golden section.** Anything that divides the *window* divides it at
```

Line 29:

```text
φ. The content column was already 62.3% of the composed width, which is
```

Line 30:

```text
1/φ to within half a point, so this too is a latent rule being written
```

Line 31:

```text
down. The remainder — the minor section — is split equally between the
```

Line 32:

```text
two side columns, which is what makes them mirror images.
```

Line 34:

```text
This lives in FleetCore rather than beside the view tokens for one reason:
```

Line 35:

```text
FleetCore is the target with tests. A layout budget nobody can assert is the
```

Line 36:

```text
state this file was written to leave.
```

Line 41:

```text
/ The ladder. Every fixed dimension in the console is one of these.
```

Line 43:

```text
/ Starts at 1 and stops at 987 because 1597 is wider than the window: a rung
```

Line 44:

```text
/ no layout can reach is a rung that invites rounding to it.
```

Line 48:

```text
/ The nearest rung to an arbitrary measurement.
```

Line 50:

```text
/ For snapping a *derived* value — a golden-section division, a measured
```

Line 51:

```text
/ width — back onto the ladder, so a computed column and a declared one
```

Line 52:

```text
/ cannot land a point apart and read as a misalignment.
```

Line 60:

```text
/ The major section of a length — the larger part when it is cut at φ.
```

Line 63:

```text
/ The minor section — what is left over, and the smaller part.
```

Line 67:

```text
/ The console window's column budget, and its one height.
```

Line 69:

```text
/ It was all widths for as long as the window was aspect-locked: height
```

Line 70:

```text
/ followed from width, so nothing had to lay out against it. The lock is gone
```

Line 71:

```text
/ — dragging one edge moving the other is not how a Mac window behaves, and it
```

Line 72:

```text
/ was most of what made resizing this one feel wrong — so height is now a free
```

Line 73:

```text
/ dimension and needs a floor of its own, derived the same way the width's is.
```

Line 76:

```text
MARK: The rungs each part is pinned to
```

Line 78:

```text
/ Both side columns — the fleet mesh on the left and the inspector on the
```

Line 79:

```text
/ right — floor at the same rung, because they are the same thing pointing
```

Line 80:

```text
/ in opposite directions. The sidebar had 236 and the inspector 280, which
```

Line 81:

```text
/ is what made the window visibly lopsided at rest.
```

Line 85:

```text
/ The module column's floor. Was a bare `360` written inline in
```

Line 86:

```text
/ `ConsoleRootView`, where nothing could see it: below roughly this width
```

Line 87:

```text
/ the process table is more horizontal scrollbar than table.
```

Line 90:

```text
/ The chrome tool rail: one toggle with breathing room each side. Its two
```

Line 91:

```text
/ components are mirrored below and checked by the audit.
```

Line 94:

```text
/ The narrowest a tool panel can be and still draw its 40×10 floor: forty
```

Line 95:

```text
/ columns of an 8pt reference cell, plus SwiftTerm's 17pt scroller reserve
```

Line 96:

```text
/ and the 1pt drag edge, neither of which can draw a column.
```

Line 99:

```text
MARK: Derived budgets
```

Line 101:

```text
/ The narrowest window that honours every floor at once *with a tool panel
```

Line 102:

```text
/ open*: one side column, the module column, the rail and the panel.
```

Line 104:

```text
/ This is the window's real minimum, and it is 982 — comfortably above the
```

Line 105:

```text
/ 780 the window has been advertising. At exactly this width, with a panel
```

Line 106:

```text
/ open, the inspector has yielded and the module column sits precisely on
```

Line 107:

```text
/ its floor, which is the definition of a budget that balances.
```

Line 111:

```text
/ The width below which the inspector yields to a tool panel: both side
```

Line 112:

```text
/ columns, the module column, the rail and the panel.
```

Line 116:

```text
/ The view layer's own values, restated here so the budget can be computed
```

Line 117:

```text
/ without importing it — the same arrangement `railWidth` uses.
```

Line 119:

```text
/ A mirror is a thing that drifts, so `Scripts/design-audit.sh` compares
```

Line 120:

```text
/ every name in this block against the `static let` of the same name in
```

Line 121:

```text
/ the view layer and fails if they disagree. That check is new, and it is
```

Line 122:

```text
/ here because `railWidth`'s own comment has claimed to be "asserted equal
```

Line 123:

```text
/ by test" since it was written and never was: `FleetCoreTests` cannot
```

Line 124:

```text
/ import the app target, so the assertion it named could not exist. A
```

Line 125:

```text
/ mirror guarded by a sentence is not guarded.
```

Line 131:

```text
/ A card's title row — one `subtitle` line — and the space under it.
```

Line 135:

```text
/ One telemetry card down to the bottom of its trace: padding, the title
```

Line 136:

```text
/ row, the gap under it, the chart, padding again. 144, which is a rung,
```

Line 137:

```text
/ and it lands there by arithmetic rather than by being typed.
```

Line 139:

```text
/ Deliberately *not* the tallest card. Overview's CPU card carries a core
```

Line 140:

```text
/ grid and a load line under its trace and comes to about 185; sizing the
```

Line 141:

```text
/ window's floor to the largest instrument any module might grow would make
```

Line 142:

```text
/ the floor a hostage to one card's contents. Down to the trace is the
```

Line 143:

```text
/ point past which the card stops being an instrument and starts being a
```

Line 144:

```text
/ cropped one; what hangs below it scrolls.
```

Line 148:

```text
/ What the unified-compact toolbar takes off the top.
```

Line 150:

```text
/ The window is `.fullSizeContentView`, so the content view runs under the
```

Line 151:

```text
/ title bar and this is content height that the module never sees. Leaving
```

Line 152:

```text
/ it out is what made the first version of the height floor wrong: the
```

Line 153:

```text
/ arithmetic was about the module column and the window handed the module
```

Line 154:

```text
/ column 55 points less than the arithmetic assumed, so the card the floor
```

Line 155:

```text
/ was defined to hold was cut off at the floor.
```

Line 158:

```text
/ A module's control row and the space under it. Modules carry no title
```

Line 159:

```text
/ row; this is the budget for the controls that replaced it.
```

Line 162:

```text
/ The module's bottom padding, below the last card.
```

Line 165:

```text
/ The shortest window that still shows something honest: the toolbar, a
```

Line 166:

```text
/ module header, and one card down to the bottom of its trace.
```

Line 168:

```text
/ Derived rather than picked, because the last hand-picked window minimum
```

Line 169:

```text
/ in this file was wrong by six points and nobody could see it — the floor
```

Line 170:

```text
/ was "half the composed width", 780, against a column reserve of 786. A
```

Line 171:

```text
/ number nobody can check is a number that is eventually wrong.
```

Line 173:

```text
/ The first version of *this* number made the same mistake in miniature.
```

Line 174:

```text
/ It was `moduleHeaderHeight + cardHeight + 21` = 191, and rendering the
```

Line 175:

```text
/ window at exactly 191 showed the card sliced through the middle of its
```

Line 176:

```text
/ chart — because `.fullSizeContentView` puts the toolbar inside the
```

Line 177:

```text
/ content height and the arithmetic had not paid for it. The lesson is the
```

Line 178:

```text
/ one the file already teaches: a budget is worth what it is measured at.
```

Line 179:

```text
/ This one was measured, at 233, 246 and 288, before it was written down.
```

Line 181:

```text
/ Height was previously `minimumContentWidth / contentAspectRatio` — 567 —
```

Line 182:

```text
/ which was not a statement about content at all. It was the aspect lock
```

Line 183:

```text
/ talking.
```

Line 187:

```text
/ The complete instrument count, not just the four original metrics.
```

Line 188:

```text
/ Avoid a single orphan card when reducing a row still uses available width.
```

Line 197:

```text
MARK: The golden division
```

Line 199:

```text
/ The width one side column takes, given the width the split view has to
```

Line 200:

```text
/ divide (the window less the rail, and less a revealed panel).
```

Line 202:

```text
/ The content column takes the major section; the two side columns share
```

Line 203:

```text
/ the minor one, equally. Clamped to the ladder rungs above, so a window
```

Line 204:

```text
/ dragged narrow stops honouring the ratio before it stops honouring the
```

Line 205:

```text
/ floors — the ratio is what the layout *wants*, the floors are what it
```

Line 206:

```text
/ *needs*.
```

Line 212:

```text
/ What the module column is left with, for a given split width and how many
```

Line 213:

```text
/ side columns are showing. Nil when the arrangement does not fit, which is
```

Line 214:

```text
/ a question the caller has to be able to ask before it draws.
```

## Sources/FleetCore/DashboardContentGeometry.swift

Line 3:

```text
/ Keep Overview readable on wide screens without squeezing compact windows.
```

## Sources/FleetCore/DashboardWindowGeometry.swift

Line 3:

```text
/ The size the console opens at.
```

Line 5:

```text
/ It used to be more than that. The window was aspect-locked to this ratio and
```

Line 6:

```text
/ capped at this size, so it was "the console's one size" and every surface was
```

Line 7:

```text
/ composed against it. Both constraints are gone — the window resizes freely on
```

Line 8:

```text
/ both axes, with floors from `ConsoleLayout` and no ceiling — so this is a
```

Line 9:

```text
/ starting size again, which is all a Mac window's default ever is.
```

Line 11:

```text
/ Chosen so the full arrangement fits at once, rather than trading columns
```

Line 12:

```text
/ off against each other: 224 sidebar + 562 module + 320 inspector + 420
```

Line 13:

```text
/ tool panel + 34 rail. At the old 1240 the same set overflowed by ~280pt,
```

Line 14:

```text
/ which is why revealing a tool had to hide the inspector.
```

Line 16:

```text
/ `ConsoleLayoutTests` checks it clears both floors, which is now the only
```

Line 17:

```text
/ thing that has to be true of it.
```

## Sources/FleetCore/DeviceLinking.swift

Line 48:

```text
/ Change only the devices array. Preserve unrelated and future config keys.
```

Line 49:

```text
/ The existing reloadConfig RPC activates the change on the controller.
```

Line 81:

```text
Preserve unknown fields on existing device records too.
```

## Sources/FleetCore/Devices.swift

Line 3:

```text
The machine and the network around it: host metrics, local tools the app can
```

Line 4:

```text
see, and the other devices on the tailnet.
```

Line 5:

```text
MARK: - Host metrics
```

Line 46:

```text
MARK: - Local tools
```

Line 48:

```text
Long-lived tools you run yourself — a dashboard, an inference server, a driver.
```

Line 49:

```text
They are not launched through the controller and never will be, but they are
```

Line 50:

```text
not "unmanaged" in the sense of a leak either: you meant them to be there.
```

Line 51:

```text
Declaring them turns anonymous noise into an inventory, and it means their own
```

Line 52:

```text
menu-bar apps have nothing left to tell you.
```

Line 63:

```text
/ Opened when you click the row, if it has a UI.
```

Line 95:

```text
MARK: - Devices
```

Line 120:

```text
/ Reachability is only claimed when a probe actually succeeded.
```

Line 130:

```text
a probe succeeded
```

Line 131:

```text
some probes succeeded, others failed
```

Line 132:

```text
probes ran and all failed
```

Line 133:

```text
no probe has completed yet
```

Line 149:

```text
/ LAN hostname or IP, optional.
```

Line 151:

```text
/ Tailscale DNS name or magic-DNS short name.
```

Line 155:

```text
/ TCP port used as a reachability probe (e.g. 22).
```

Line 159:

```text
/ Services managed by *that* machine's controller, fetched read-only over SSH.
```

Line 160:

```text
/ FleetConsole never controls a remote process — it only reports one.
```

Line 164:

```text
/ CPU / RAM / SSD for this machine — what the AI-Pocket badge used to show.
```

## Sources/FleetCore/Events.swift

Line 3:

```text
The append-only event log's vocabulary. Every state change files one of these,
```

Line 4:

```text
and the log outlives the records it describes — `prune` drops terminal service
```

Line 5:

```text
rows and never touches events.
```

Line 6:

```text
MARK: - Events (append-only)
```

Line 10:

```text
an already-running process was adopted into the registry
```

Line 37:

```text
/ Written by the *next* generation on startup: a controller that dies through
```

Line 38:

```text
/ fatalError or SIGKILL never gets to record its own exit, so the only evidence is
```

Line 39:

```text
/ a `daemonStarted` with no `daemonStopping` after it.
```

Line 95:

```text
/ Evidence snapshot captured at the moment the event was written.
```

## Sources/FleetCore/FleetTopology.swift

Line 3:

```text
/ A projection of controller evidence, shared by the desktop and CLI. Edges
```

Line 4:

```text
/ express recorded ownership or observations, never inferred dependencies.
```

Line 29:

```text
/ Next evidence expiry; clients can update once at this boundary.
```

Line 96:

```text
Session detection has its own source. Never join tool names, paths or
```

Line 97:

```text
bare PIDs to service owners. Exact owner filtering omits this lane.
```

## Sources/FleetCore/Formatting.swift

Line 3:

```text
Formatting shared by the CLI and the UI, so a duration or a byte count reads
```

Line 4:

```text
the same in `fleetctl list` as it does in the window.
```

Line 5:

```text
MARK: - Formatting helpers shared by CLI and UI
```

Line 29:

```text
/ The same list, capped, for rows where the ports are one accessory among
```

Line 30:

```text
/ several. Every accessory in a row is `fixedSize`, so a three-port service
```

Line 31:

```text
/ claims its full width unconditionally and the row takes it out of the only
```

Line 32:

```text
/ compressible thing left — the title. The Services popover drew a claimed,
```

Line 33:

```text
/ expired service as an icon, "Claimed", "Expired" and ":8080 :8081 :8082"
```

Line 34:

```text
/ with no name at all. The full list is still in the row's detail.
```

Line 49:

```text
/ A spend figure. Two decimals, because that is what a bill has — but a
```

Line 50:

```text
/ real amount below a cent reads as `<$0.01` rather than `$0.00`, for the
```

Line 51:

```text
/ same reason an unknown is never rendered as zero: a turn that cost
```

Line 52:

```text
/ something must not display as having been free.
```

## Sources/FleetCore/License.swift

Line 6:

```text
Licensing and the trial clock.
```

Line 8:

```text
Everything in this file is *scaffolding*: the honest version of where the
```

Line 9:

```text
product is. There is a 14-day trial counted from first launch, a key format
```

Line 10:

```text
with real signature checking so support can issue keys before there is a
```

Line 11:

```text
store, and a single place that answers "is this feature premium" so the
```

Line 12:

```text
gating cannot drift between surfaces. There is deliberately no checkout,
```

Line 13:

```text
no network validation and no revocation list — the file says so at the
```

Line 14:

```text
bottom, because the worst kind of licence code is the kind that pretends
```

Line 15:

```text
to be a payment system.
```

Line 17:

```text
Threat-model note (see docs/THREAT-MODEL.md): this is not anti-piracy. An
```

Line 18:

```text
HMAC key can be shared and a UserDefaults date can be rolled back, and
```

Line 19:

```text
neither is defended, because defending them costs the honest user and stops
```

Line 20:

```text
nobody. The check exists so premium *features* have one gate, so a trial
```

Line 21:

```text
has a real clock, and so a purchased key can be validated offline forever.
```

Line 23:

```text
MARK: - Features
```

Line 25:

```text
/ The things a licence unlocks. Everything not listed here is free, forever.
```

Line 27:

```text
/ The gate lives in the core rather than in each view for the same reason
```

Line 28:

```text
/ the thresholds live in one enum: two surfaces that each decided "is SMC
```

Line 29:

```text
/ premium" would eventually disagree, and a premium feature that shows in
```

Line 30:

```text
/ one place and locks in another is a broken promise.
```

Line 32:

```text
/ Fan RPM and die temperatures from the SMC.
```

Line 34:

```text
/ Skipping the first-launch welcome. The welcome itself is free; the
```

Line 35:

```text
/ *skip* is premium — the onboarding is part of what a trial evaluates.
```

Line 37:

```text
/ The heatmap's advanced filtering (anything past the default view).
```

Line 39:

```text
/ Reconcile runs through the console: take a snapshot, compare it to the
```

Line 40:

```text
/ registry's desired state, apply the diff with an undo log. The free
```

Line 41:

```text
/ tier can *see* drift (the overview shows mismatches as they happen),
```

Line 42:

```text
/ but only a licence can act on it.
```

Line 55:

```text
MARK: - Key format
```

Line 57:

```text
/ `FLT1-<base32 payload>.<base32 HMAC-SHA256>`.
```

Line 59:

```text
/ The payload is an ISO-8601 issue date; the signature is HMAC-SHA256 over
```

Line 60:

```text
/ the payload string with the vendor secret. Validation is offline and
```

Line 61:

```text
/ deterministic — a key that validates today validates in ten years, which
```

Line 62:

```text
/ is the whole reason the format has a version prefix: `FLT2` can change
```

Line 63:

```text
/ everything after the dash and old keys still parse.
```

Line 65:

```text
/ Separator between the payload and the signature, inside the body.
```

Line 69:

```text
/ The signing secret.
```

Line 71:

```text
/ For a shipped app this would be generated once and held out of the
```

Line 72:

```text
/ repository; what matters for the gate is that issuer and validator use
```

Line 73:

```text
/ the same bytes. It lives here, visibly, because this is scaffolding —
```

Line 74:

```text
/ see the file header on why obscurity is not the defence.
```

Line 77:

```text
/ Builds the body (`payload.signature`) for a payload. The issuer side;
```

Line 78:

```text
/ exposed so a future `fleetctl license mint` — and the tests — sign
```

Line 79:

```text
/ exactly the way the validator verifies.
```

Line 85:

```text
/ Validates a full key, e.g. `FLT1-2026-08-21.ABCD…`.
```

Line 96:

```text
A syntactically valid key whose payload is not a date is a key we
```

Line 97:

```text
cannot interpret; reject rather than license on an unknown format.
```

Line 101:

```text
/ The issue date a valid key carries. Nil for anything that does not
```

Line 102:

```text
/ parse — callers that license on `isValid` only ever see a date.
```

Line 124:

```text
CryptoKit is present on every macOS this package targets; the
```

Line 125:

```text
fallback is for the Linux toolchain the core also compiles under.
```

Line 130:

```text
Base32 (RFC 4648, no padding — a key is typed by a human, and "=" at
```

Line 131:

```text
the end of a key is a character that breaks double-click selection).
```

Line 173:

```text
MARK: - Trial clock
```

Line 175:

```text
/ The trial arithmetic, pure so the tests can pin it against any clock.
```

Line 177:

```text
/ Days a first launch gets. Fourteen because a menu-bar app is judged in
```

Line 178:

```text
/ the first sitting, and the second week is for the person who meant to
```

Line 179:

```text
/ come back to it.
```

Line 182:

```text
/ Days left, whole days, never negative. `now` before the start (a
```

Line 183:

```text
/ rolled-back clock) counts as day zero — the trial is not extended by
```

Line 184:

```text
/ time travel, and it is not ended by it either.
```

Line 198:

```text
MARK: - Manager
```

Line 200:

```text
/ The one place licensing state lives. `@Observable` because the trial
```

Line 201:

```text
/ countdown is chrome, not data: the footer that shows it re-renders when
```

Line 202:

```text
/ the state changes, and nothing persists *through* this object — it reads
```

Line 203:

```text
/ and writes UserDefaults, which is the store.
```

Line 208:

```text
/ A valid key is installed.
```

Line 210:

```text
/ No key; trial clock running, N whole days left.
```

Line 212:

```text
/ No key; the trial ended.
```

Line 216:

```text
/ Trial, or licence. Recomputed from the store on every read of
```

Line 217:

```text
/ `status`, so rolling the system clock forward is reflected without an
```

Line 218:

```text
/ app restart — a countdown that cached would lie for days.
```

Line 224:

```text
Suite, not `.standard`: the daemon and any future CLI share the app's
```

Line 225:

```text
licensing state by reading the same suite, and a key typed into the app
```

Line 226:

```text
is honoured everywhere without a second entry point.
```

Line 239:

```text
/ The first-launch marker. Written exactly once: the trial clock starts
```

Line 240:

```text
/ the first time anything asks, and no amount of relaunching moves it.
```

Line 263:

```text
/ Installs a key. Returns whether the key validated; a rejected key is
```

Line 264:

```text
/ not stored, so a typo cannot wedge the app into the expired state.
```

Line 278:

```text
/ MIT distribution: every feature is available permanently. Legacy key
```

Line 279:

```text
/ and trial records remain readable for compatibility, never for access.
```

## Sources/FleetCore/LiveDaemonReadiness.swift

Line 3:

```text
/ Live-daemon verification requires a received snapshot, not an attempted RPC.
```

## Sources/FleetCore/Logging.swift

Line 3:

```text
/ Deliberately boring: line-oriented, timestamped, to stderr (launchd captures it)
```

Line 4:

```text
/ and optionally to a 0600 file. No os_log subsystem, no remote sink.
```

Line 6:

```text
/ `@unchecked Sendable` rather than an actor: `fileHandle` is touched only inside
```

Line 7:

```text
/ `queue`, `minimumLevel` only behind `levelLock`, and there is no other stored
```

Line 8:

```text
/ state. An actor would make every `FleetLog.info` an `await`, and this is called
```

Line 9:

```text
/ from `deinit` and teardown paths that cannot suspend.
```

Line 14:

```text
/ A stored rank rather than `firstIndex(of:)` over a fresh array —
```

Line 15:

```text
/ compared on every log call, including the ones about to be filtered.
```

Line 30:

```text
/ Only ever read or written inside `queue`.
```

Line 33:

```text
/ Its own lock rather than `queue`: the level check is the fast path, and
```

Line 34:

```text
/ routing it through `queue.sync` would put a filtered debug line onto the
```

Line 35:

```text
/ queue it is trying not to touch.
```

Line 62:

```text
/ Keeps the daemon log from growing without bound; rotates at ~2 MB.
```

## Sources/FleetCore/MetricHistory.swift

Line 14:

```text
/ Actual observation times survive delayed ticks and manual refreshes.
```

Line 15:

```text
/ No averaging: a single observation at a peak remains in the plotted series.
```

## Sources/FleetCore/Models.swift

Line 3:

```text
A service as the controller knows it: what it is, what evidence there is that
```

Line 4:

```text
it is alive, and what it is allowed to consume.
```

Line 6:

```text
One of seven files split from a 1,158-line Models.swift along its own MARKs.
```

Line 7:

```text
Nothing changed but which file each type sits in.
```

Line 8:

```text
MARK: - Evidence
```

Line 10:

```text
The central honesty rule of FleetConsole: "reachable", "process exists",
```

Line 11:

```text
"port is listening" and "application health check passed" are four different
```

Line 12:

```text
facts. They are recorded separately, timestamped separately, and never
```

Line 13:

```text
collapsed into a single boolean anywhere in the codebase or the UI.
```

Line 16:

```text
/ kill(pid, 0) succeeded *and* the process start time still matches the
```

Line 17:

```text
/ value recorded at launch (PID-reuse guard).
```

Line 19:

```text
/ Ports observed in LISTEN state for this service's process group.
```

Line 21:

```text
/ Whether a port scan actually ran (distinguishes "no ports" from "not checked").
```

Line 23:

```text
/ Whether a configured application health check ran, and its result.
```

Line 48:

```text
/ Evidence older than this many seconds must be rendered as "unknown (stale)".
```

Line 55:

```text
MARK: - Health
```

Line 58:

```text
no check configured — service can never be reported "healthy"
```

Line 59:

```text
TCP connect to host:port
```

Line 60:

```text
HTTP GET, expect a status code
```

Line 65:

```text
/ http: full URL. tcp: "host:port".
```

Line 70:

```text
/ Consecutive failures before the service is called unhealthy.
```

Line 84:

```text
MARK: - Budgets
```

Line 87:

```text
/ Hard ceiling on wall-clock runtime, independent of lease renewals.
```

Line 91:

```text
/ Ports this service is allowed to listen on. Empty = declared ports only are expected,
```

Line 92:

```text
/ but nothing is enforced. A listener outside this set raises `portViolation`.
```

Line 104:

```text
MARK: - Service state
```

Line 108:

```text
process alive, no health check configured — "unverified"
```

Line 109:

```text
health check ran and passed
```

Line 110:

```text
alive + passing, but a budget threshold is breached
```

Line 111:

```text
health check ran and failed past its threshold
```

Line 112:

```text
SIGSTOP — still resident, holding its ports, doing nothing
```

Line 113:

```text
lease nearly up
```

Line 114:

```text
lease/max-runtime exceeded, reap pending
```

Line 117:

```text
exited without being asked to
```

Line 123:

```text
/ Whether the process is meant to be up *right now*.
```

Line 125:

```text
/ Narrower than `!isTerminal`, and the difference is the whole point.
```

Line 126:

```text
/ `isTerminal` answers "is this record finished" — an expired lease is not,
```

Line 127:

```text
/ because an expired claim is reported and left alone rather than reaped, and
```

Line 128:

```text
/ it still belongs in `fleetctl list`. But it is not running either: the CLI
```

Line 129:

```text
/ renders `.expired` as **GONE**, and a header that counted it said "1 service
```

Line 130:

```text
/ running" about the same record. Two surfaces disagreeing about one service
```

Line 131:

```text
/ is worse than either answer alone, so the count that says "running" uses
```

Line 132:

```text
/ this and the list that says "what is on the books" keeps `isTerminal`.
```

Line 149:

```text
/ A paused process still holds its ports and memory — it is stopped in the
```

Line 150:

```text
/ scheduler sense only, which is a different thing from being stopped.
```

Line 157:

```text
/ Number of processes in the service's process group.
```

Line 169:

```text
/ The record the controller returns to an agent on launch, and the row the UI renders.
```

Line 178:

```text
/ Only the *keys* of any extra environment are stored — never the values (T6).
```

Line 183:

```text
/ `ps -o lstart` of the pid at launch. Used to detect PID reuse before signalling.
```

Line 206:

```text
/ Recent CPU% and resident MB samples, newest last, for the row sparklines.
```

Line 207:

```text
/ Capped so a long-lived service cannot grow its own record without bound.
```

Line 211:

```text
/ Set when the controller reaped this service because its lease or max
```

Line 212:

```text
/ runtime ran out — i.e. the owning agent walked away and left it running.
```

Line 213:

```text
/ Recorded on the row itself so an agent's leak count survives without
```

Line 214:

```text
/ re-reading the event log.
```

Line 216:

```text
/ Cumulative failed health checks over this service's life.
```

Line 218:

```text
/ True when this record was **claimed** from a process that was already
```

Line 219:

```text
/ running, rather than launched by the controller. The distinction is not
```

Line 220:

```text
/ cosmetic: the controller signals only what it started, so a claimed record
```

Line 221:

```text
/ is supervised and reported on but never stopped, reaped or restarted by it.
```

Line 283:

```text
/ Decoded field by field, with a default for everything that has one.
```

Line 285:

```text
/ The registry stores each record as a JSON blob, so the *only* schema
```

Line 286:

```text
/ migration this app has is what this initialiser tolerates. The synthesised
```

Line 287:

```text
/ decoder does not fall back to a property's default value — a missing key is
```

Line 288:

```text
/ a hard `keyNotFound` — so every field added after v1 (`cpuHistory`,
```

Line 289:

```text
/ `reapedForExpiry`, `healthFailureCount`, `claimed`, …) made every record
```

Line 290:

```text
/ written before it undecodable. The read path swallows that with `try?`, so
```

Line 291:

```text
/ the failure mode was not an error: it was terminal records quietly
```

Line 292:

```text
/ disappearing from the history on the first upgrade — the "stale records"
```

Line 293:

```text
/ row of the threat model, caused by us.
```

Line 295:

```text
/ Only the fields with no honest default are required.
```

Line 340:

```text
/ Wall time since `startedAt`, frozen at the moment the record went terminal.
```

Line 342:

```text
/ It ran off `Date()` unconditionally, so a service that crashed on Tuesday was
```

Line 343:

```text
/ still accruing uptime on Friday: the inspector drew the crashed `indexer`
```

Line 344:

```text
/ with no pid, "0 in group", every Activity figure an em dash — and
```

Line 345:

```text
/ "Uptime 3h 26m" underneath, which is a claim about a process that does not
```

Line 346:

```text
/ exist. `updatedAt` is stamped on every terminal transition, so it is when the
```

Line 347:

```text
/ record stopped.
```

Line 349:

```text
/ Only `isTerminal` freezes. An expired lease or a paused process has not
```

Line 350:

```text
/ stopped running — expired means the lease is up, and a claimed record that
```

Line 351:

```text
/ expires is reported and left alone — so those keep counting.
```

Line 357:

```text
/ Ports we *see* listening, falling back to what was declared (clearly labelled in UI).
```

Line 362:

```text
/ True when the state was derived from a health check that actually ran.
```

Line 365:

```text
/ Whether the *controller* may signal this record. False for anything it did
```

Line 366:

```text
/ not start, which is the one rule claiming does not buy its way out of: a
```

Line 367:

```text
/ claimed process gets an owner, a purpose, a lease and a timeline, and it
```

Line 368:

```text
/ still gets stopped by you rather than by the reaper.
```

Line 371:

```text
/ Why a controller verb is refused on this record, or nil when it is allowed.
```

## Sources/FleetCore/NativeNetworkCounters.swift

Line 3:

```text
/ Physical enN link counters from IFMIB's genuine 64-bit if_data64 fields.
```

Line 4:

```text
/ getifaddrs exposes 32-bit if_data counters, even on a 64-bit host.
```

Line 19:

```text
/ The same adapter used by live reads, with only the kernel query injected.
```

Line 20:

```text
/ Native ifmibdata fixtures exercise extraction without truncating counters.
```

## Sources/FleetCore/OverviewViewportGeometry.swift

Line 3:

```text
/ Overview receives the module viewport after the toolbar has taken its space —
```

Line 4:

```text
/ SwiftUI's geometry for the column already excludes the toolbar safe area.
```

Line 5:

```text
/ Reserve the readable chrome first; the charts spend what remains, and the
```

Line 6:

```text
/ process preview declares its cap rather than scrolling.
```

Line 8:

```text
/ The page heading has an explicit budget. Supporting readings and the process
```

Line 9:

```text
/ preview yield space before the primary plots become unreadable.
```

Line 16:

```text
/ A trace taller than this stops adding legibility and starts adding air.
```

Line 18:

```text
Measured in the shipping window, not estimated: the surface renderer's
```

Line 19:

```text
module column at 1560 and 982 wide, part by part.
```

Line 20:

```text
/ The secondary glance: one row of readings inside its card.
```

Line 22:

```text
/ The process card without rows: padding, title row and column labels.
```

Line 24:

```text
/ One process row and the spacing under it.
```

Line 26:

```text
/ A primary card around its plot: title, subtitle and the footer facts.
```

Line 27:

```text
/ Below `memoryFactsRowWidth` the memory facts take two rows of two.
```

Line 44:

```text
Five concise readings still fit beside the Details action with the
```

Line 45:

```text
sidebar open; wrapping that glance would spend another chart's height.
```

Line 52:

```text
The heading, primary cards, glance and processes share one viewport.
```

Line 53:

```text
Controls remain in the native toolbar.
```

Line 64:

```text
The plots take everything the fixed parts leave, so the page ends at
```

Line 65:

```text
the window's edge instead of stopping short of it.
```

## Sources/FleetCore/Paths.swift

Line 3:

```text
/ Every path FleetConsole touches lives under the user's home, mode 0700/0600.
```

Line 4:

```text
/ Nothing is written to /tmp, nothing is shared between users.
```

Line 9:

```text
/ Environment variable naming a directory that stands in for the user's home.
```

Line 12:

```text
/ Where `support` and `logs` live. Setting `FLEETCONSOLE_STATE_ROOT` to an
```

Line 13:

```text
/ absolute path gives a development controller, CLI or client its own
```

Line 14:

```text
/ registry, socket and logs. Setting `HOME` does not: Foundation's home
```

Line 15:

```text
/ lookup ignores it on macOS, so a second controller would find the
```

Line 16:

```text
/ user's socket and exit. Unset or empty, every path is the user's own.
```

Line 34:

```text
/ Written the instant a stop signal arrives, before any shutdown work — see
```

Line 47:

```text
createDirectory only applies attributes when it creates the directory.
```

## Sources/FleetCore/ProcessTable.swift

Line 3:

```text
/ A single snapshot of the machine's process and listener state, built from
```

Line 4:

```text
/ exactly two subprocess calls (`ps` and `lsof`) regardless of how many services
```

Line 5:

```text
/ are managed. Everything the supervisor and reconciler need is derived from this.
```

Line 14:

```text
/ `ps -o state` — `R`, `S`, `I`, `T`, `U`, `Z`, plus BSD modifier
```

Line 15:

```text
/ letters (`S+`, `Ss`, `R<`). Kept raw; `ProcessState` interprets it.
```

Line 16:

```text
/ The modifiers are deliberately not stripped here: "session leader"
```

Line 17:

```text
/ and "foreground process group" are facts about the process, and a
```

Line 18:

```text
/ field that silently discards them cannot get them back.
```

Line 20:

```text
/ `ps -o lstart` string — stable for the life of a pid, so comparing it to
```

Line 21:

```text
/ the value captured at launch detects PID reuse (threat model T2).
```

Line 44:

```text
/ Set when `ps` did not run to completion: `byPID` is then empty because we could
```

Line 45:

```text
/ not look, not because nothing is running.
```

Line 47:

```text
/ Same for `lsof` — a timeout or an error, as opposed to "nothing is listening".
```

Line 50:

```text
/ Anything that reconciles durable state must check this first. Treating a failed
```

Line 51:

```text
/ probe as "nothing found" erases exactly the records the probe could not see.
```

Line 58:

```text
MARK: - Capture
```

Line 77:

```text
/ nil means the probe itself failed. `ps -A` always lists at least itself, so an
```

Line 78:

```text
/ empty parse is a failure too, not an empty machine.
```

Line 80:

```text
`state` sits between rss and lstart: it is a single whitespace-free
```

Line 81:

```text
token, so it can be parsed positionally, which `command` (spaces) and
```

Line 82:

```text
`lstart` (five tokens) cannot. Every index after it moved by one.
```

Line 88:

```text
pid ppid pgid uid pcpu rss state + 5 lstart tokens + command…
```

Line 103:

```text
/ Without root, lsof reports only this user's processes — which is exactly the
```

Line 104:

```text
/ scope FleetConsole claims to cover. Documented rather than escalated.
```

Line 106:

```text
/ nil means the probe failed (missing lsof, an error, or the 15s timeout). It used
```

Line 107:

```text
/ to return an empty list for all three, which downstream read as "nothing is
```

Line 108:

```text
/ listening" and used to erase durable state.
```

Line 115:

```text
lsof exits 1 with no output when nothing matched, so a non-zero status only
```

Line 116:

```text
means failure when it also complained or was killed (timeout → signal).
```

Line 151:

```text
"*:8080", "127.0.0.1:8086", "[fe80::1]:5000", "*:8080->..." (not in LISTEN)
```

Line 158:

```text
MARK: - Queries
```

Line 162:

```text
/ All live pids in a process group — this is how children of `npm run dev`
```

Line 163:

```text
/ are attributed to the service that started them.
```

## Sources/FleetCore/Protocol.swift

Line 3:

```text
/ Newline-delimited JSON over a 0600 Unix domain socket. There is no network
```

Line 4:

```text
/ listener anywhere in FleetConsole (threat model T5).
```

Line 8:

```text
server pushes a Snapshot per state change / tick
```

Line 15:

```text
adopt an already-running unmanaged process into the registry
```

Line 16:

```text
force an immediate reconciliation sweep
```

Line 19:

```text
add a command to the expected-listener allow-list
```

Line 20:

```text
drop terminal service records (never events)
```

Line 21:

```text
SIGSTOP the process group
```

Line 22:

```text
SIGCONT the process group
```

Line 23:

```text
SIGKILL immediately, no grace period
```

Line 24:

```text
an agent says something to the operator
```

Line 25:

```text
read the mailbox
```

Line 26:

```text
the operator answers a message
```

Line 27:

```text
mark messages as seen so notifications fire once
```

Line 30:

```text
/ A request from an agent to run something. This is the *only* way a process
```

Line 31:

```text
/ enters the registry.
```

Line 38:

```text
/ Extra environment. Values are used for the spawn but never persisted (T6).
```

Line 68:

```text
"out" | "err"
```

Line 70:

```text
/ Free-text reason recorded in the event log for mutating operations.
```

Line 72:

```text
/ Executable name for `ignoreCommand`.
```

Line 74:

```text
/ `UnmanagedProcess.id` (or a bare pid) for `claim`.
```

Line 76:

```text
/ Human name to file a claimed process under. Defaults to its executable.
```

Line 78:

```text
/ Why a claimed process is allowed to exist. Recorded on the record, not just
```

Line 79:

```text
/ in the event log, which is what separates it from `reason`.
```

Line 81:

```text
/ The owning agent, for `postMessage`, `messages` — and for `claim`, where it
```

Line 82:

```text
/ is who is answering for the process from now on.
```

## Sources/FleetCore/RPCRequestPolicy.swift

Line 3:

```text
/ An observational client must never modify the controller's registry.
```

Line 4:

```text
/ The default remains interactive for the app and CLI's normal workflows.
```

Line 13:

```text
/ The renderer's missing-daemon probe must not change an interactive or
```

Line 14:

```text
/ normally compiled client's destination, even if it receives these flags.
```

## Sources/FleetCore/Registry.swift

Line 3:

```text
/ The registry: managed services, an append-only event history, the unmanaged
```

Line 4:

```text
/ cache and device state. Service/device rows keep indexed scalar columns for
```

Line 5:

```text
/ queries plus a JSON payload for the full record, so the schema can evolve
```

Line 6:

```text
/ without migrations for every new field.
```

Line 8:

```text
/ The `events` table is protected by triggers that make UPDATE and DELETE fail —
```

Line 9:

```text
/ history cannot be rewritten, including by a future bug in FleetConsole (T3).
```

Line 13:

```text
/ `readOnly` is for readers that must work while the daemon is down (`fleetctl
```

Line 14:

```text
/ events --offline`): no schema work, no writes, nothing that could disturb a
```

Line 15:

```text
/ controller that comes back up while the reader is still open.
```

Line 22:

```text
/ Forwarded so whoever owns the daemon lifecycle can bound the WAL and release
```

Line 23:

```text
/ the file explicitly — `deinit` never runs when the process leaves via exit().
```

Line 107:

```text
MARK: - Services
```

Line 143:

```text
/ Resolves a full id or a unique short-id prefix (what the CLI prints).
```

Line 157:

```text
Fall back to friendly name. Running services win; if none is running we
```

Line 158:

```text
return the most recent terminal record, because "why did it crash" is
```

Line 159:

```text
exactly when you reach for `fleetctl logs <name>`.
```

Line 183:

```text
/ Terminal records older than `age` are pruned so the services table does not
```

Line 184:

```text
/ grow forever. The event history is never pruned — it is the audit trail.
```

Line 189:

```text
Bulk deletes are the single largest WAL producer in this file, so this is
```

Line 190:

```text
where the WAL is actually reclaimed rather than left to grow.
```

Line 194:

```text
MARK: - Events (append-only)
```

Line 234:

```text
/ Most recent events restricted to a set of kinds. The daemon uses this to tell a
```

Line 235:

```text
/ clean shutdown from a generation that died without writing one.
```

Line 251:

```text
/ Column order is fixed by the two SELECTs above; kept in one place so they
```

Line 252:

```text
/ cannot drift apart.
```

Line 268:

```text
MARK: - Unmanaged
```

Line 270:

```text
/ Merges this sweep's unmanaged set into the table, preserving `firstSeen` for keys
```

Line 271:

```text
/ we have seen before so "how long has this been leaking" survives restarts.
```

Line 273:

```text
/ Upsert plus a targeted delete, never DELETE-all-and-reinsert: with the latter a
```

Line 274:

```text
/ single sweep that saw nothing (a `ps`/`lsof` failure upstream used to look
```

Line 275:

```text
/ exactly like an empty machine) wiped every row, lost every `first_seen`, and the
```

Line 276:

```text
/ next good sweep re-emitted the whole list as brand-new `becameUnmanaged` events.
```

Line 302:

```text
Only keys this sweep genuinely did not see are dropped.
```

Line 321:

```text
MARK: - Messages
```

Line 372:

```text
/ A reply is written exactly once: answering twice would silently rewrite
```

Line 373:

```text
/ what the agent already read.
```

Line 400:

```text
MARK: - Devices
```

## Sources/FleetCore/Runbook.swift

Line 3:

```text
Runbooks: what a model is allowed to do about one situation.
```

Line 5:

```text
A runbook is a versioned document written by a developer, shipped alongside a
```

Line 6:

```text
model, and read by the operator before anything happens. It says what symptom
```

Line 7:

```text
it addresses, what evidence to gather, what steps may be taken in what order,
```

Line 8:

```text
which of those need a human, and when to stop and hand back.
```

Line 10:

```text
## The one decision everything else follows from
```

Line 12:

```text
A step is a typed action from a closed vocabulary, never a command string.**
```

Line 14:

```text
The obvious design is `command: String` with the model filling in the blanks.
```

Line 15:

```text
That design is a remote shell with extra steps: the blast radius is whatever
```

Line 16:

```text
the model can spell, and no amount of prompting narrows it. Here the set of
```

Line 17:

```text
things any runbook can express is fixed by `RunbookAction` at compile time, so
```

Line 18:

```text
the worst a malicious or confused document can ask for is something already on
```

Line 19:

```text
the list — and everything on the list goes through `fleetctl`, which means
```

Line 20:

```text
leases, reaping and the event log apply to it unchanged.
```

Line 22:

```text
The cost is real: a situation nobody anticipated cannot be automated until the
```

Line 23:

```text
vocabulary grows, and growing it is a code change with a review. That is the
```

Line 24:

```text
trade, and it is the right way round for software that touches other people's
```

Line 25:

```text
machines.
```

Line 27:

```text
Everything in this file is pure data. Executing a runbook is `RunbookEngine`'s
```

Line 28:

```text
job and does not exist yet; validating one is `RunbookValidation`.
```

Line 30:

```text
MARK: - Parameters
```

Line 32:

```text
/ An input the runbook needs before it can do anything — the port that is
```

Line 33:

```text
/ taken, the agent that went quiet. Supplied by the operator or proposed by the
```

Line 34:

```text
/ model from evidence; either way it is named here first, so a step can never
```

Line 35:

```text
/ reference a value the document did not declare.
```

Line 46:

```text
/ What the operator is asked, in their words. Shown verbatim.
```

Line 58:

```text
MARK: - Evidence
```

Line 60:

```text
/ A read-only question about the machine. Gathering evidence changes nothing,
```

Line 61:

```text
/ which is what lets the whole diagnosis phase run without an approval gate.
```

Line 63:

```text
/ The controller's registry: what it owns and the state of each lease.
```

Line 65:

```text
/ Who is listening on the port named by a parameter.
```

Line 67:

```text
/ The heaviest processes on the machine, by CPU and by memory.
```

Line 69:

```text
/ Volume capacity and what is using it.
```

Line 71:

```text
/ Space that regenerates on its own, and what it costs to lose.
```

Line 73:

```text
/ The append-only log, most recent first.
```

Line 75:

```text
/ One service's stdout, tail only.
```

Line 79:

```text
MARK: - Targets
```

Line 81:

```text
/ Which services a mutating step acts on.
```

Line 83:

```text
/ There is no "everything" case, and there never will be. `each` carries a
```

Line 84:

```text
/ mandatory cap because an uncapped multi-target mutation is the shape that
```

Line 85:

```text
/ stops a whole fleet from one bad match — the cap is what turns a runaway into
```

Line 86:

```text
/ a bounded action the operator can read before approving.
```

Line 88:

```text
/ Exactly the one service named by a parameter.
```

Line 90:

```text
/ Every service the query matches, up to `max`.
```

Line 94:

```text
/ The closed set of ways a runbook may select services it did not name.
```

Line 96:

```text
/ Past its lease and still running — the leaked-daemon case.
```

Line 98:

```text
/ Owned by the agent named by a parameter.
```

Line 100:

```text
/ Holding the port named by a parameter.
```

Line 102:

```text
/ Restarted more times than a healthy service would.
```

Line 106:

```text
/ What a reclaim step is allowed to remove.
```

Line 108:

```text
/ One case, deliberately. Everything else the storage scanner finds — a model
```

Line 109:

```text
/ weight, a photo library, anything that does not come back on its own — is
```

Line 110:

```text
/ reported to the operator and never offered to a runbook. A ceiling with a
```

Line 111:

```text
/ second rung would eventually be raised.
```

Line 113:

```text
/ Caches that regenerate transparently, costing nothing but a slower next build.
```

Line 117:

```text
MARK: - Actions
```

Line 119:

```text
/ Everything a runbook step can be. The list is the safety boundary.
```

Line 121:

```text
/ Gather evidence. Changes nothing.
```

Line 123:

```text
/ Ask the controller to stop a service it owns.
```

Line 125:

```text
/ Extend a lease rather than let the reaper take it.
```

Line 127:

```text
/ Stop and start again, through the controller.
```

Line 129:

```text
/ Delete space that regenerates on its own.
```

Line 131:

```text
/ Stop here and give the operator the floor, with a reason they can read.
```

Line 134:

```text
/ Whether the step leaves the machine exactly as it found it.
```

Line 136:

```text
/ This drives the approval invariant and the read-only diagnosis pass, so
```

Line 137:

```text
/ the switch is exhaustive on purpose: a new action must be classified
```

Line 138:

```text
/ deliberately rather than inheriting a default.
```

Line 146:

```text
/ The services this action touches, if any. `nil` for actions that do not
```

Line 147:

```text
/ act on a service at all.
```

Line 158:

```text
MARK: - Approval
```

Line 160:

```text
/ Who has to say yes before a step runs.
```

Line 162:

```text
/ Runs on its own. Only ever legal for a read-only step.
```

Line 164:

```text
/ The operator sees the exact action and approves this one instance.
```

Line 168:

```text
MARK: - Stopping
```

Line 170:

```text
/ A condition that ends the run and hands the situation back to a human.
```

Line 172:

```text
/ Authored per runbook rather than assumed, because writing them down is the
```

Line 173:

```text
/ part that makes the author think about what they are automating. Validation
```

Line 174:

```text
/ enforces the one that is not optional — see `RunbookValidation`.
```

Line 176:

```text
/ The culprit is a process the controller does not own. Nothing in this
```

Line 177:

```text
/ product signals a process it did not start.
```

Line 179:

```text
/ More candidates matched than the runbook is willing to act on.
```

Line 181:

```text
/ Required evidence could not be gathered, so the diagnosis is a guess.
```

Line 183:

```text
/ The operator declined a step.
```

Line 185:

```text
/ A step reported failure. Later steps assumed it worked.
```

Line 187:

```text
/ Every step ran and the symptom is still there.
```

Line 190:

```text
/ One line for the operator, not for the log.
```

Line 209:

```text
MARK: - Steps
```

Line 213:

```text
/ What the operator reads in the approval list.
```

Line 216:

```text
/ Why the author put this step here. Required, and shown next to the
```

Line 217:

```text
/ action: an approval prompt the operator cannot reason about is a prompt
```

Line 218:

```text
/ they will learn to click through.
```

Line 234:

```text
MARK: - The document
```

Line 237:

```text
/ The schema this document is written against. A reader that does not know
```

Line 238:

```text
/ the version refuses the document rather than guessing at it.
```

Line 243:

```text
/ This document's own version, bumped by its author. Distinct from
```

Line 244:

```text
/ `formatVersion`: the schema and the content change for different reasons
```

Line 245:

```text
/ and by different hands.
```

Line 248:

```text
/ The situation in the operator's words — what they would say out loud,
```

Line 249:

```text
/ which is also what a model matches against.
```

Line 251:

```text
/ What the model is told before it sees any evidence. The author's voice:
```

Line 252:

```text
/ the domain knowledge that makes a general model useful about this one
```

Line 253:

```text
/ situation, and the reason a runbook is worth shipping at all.
```

Line 256:

```text
/ Gathered up front, before any step runs.
```

Line 277:

```text
/ The steps that change nothing, in order. This is the whole of what the
```

Line 278:

```text
/ read-only diagnosis pass may run, and it is derived rather than declared
```

Line 279:

```text
/ so the two can never disagree.
```

Line 282:

```text
/ The steps that need a human. What the approval sheet lists.
```

Line 285:

```text
/ Whether anything in here can change the machine at all. A runbook that
```

Line 286:

```text
/ cannot is safe to run unattended and is worth saying so about.
```

## Sources/FleetCore/RunbookLibrary.swift

Line 3:

```text
The runbooks that ship with the app.
```

Line 5:

```text
Three, and no more until these three have been run against real machines. A
```

Line 6:

```text
format proves nothing until something real is written in it, and the fastest
```

Line 7:

```text
way to end up with a format that fits nothing is to design a fourth situation
```

Line 8:

```text
before the first three have been used.
```

Line 10:

```text
They are declared here rather than loaded from JSON so the compiler checks
```

Line 11:

```text
them and the test suite validates them on every run. The type is `Codable`
```

Line 12:

```text
throughout, so exporting these as documents — and loading somebody else's —
```

Line 13:

```text
is a transport change, not a format change.
```

Line 15:

```text
The briefing is the product.** The model is interchangeable; what makes it
```

Line 16:

```text
useful about a port conflict at 3am is a paragraph from someone who has
```

Line 17:

```text
debugged one. Each briefing below is written to be read by a model that knows
```

Line 18:

```text
how computers work and nothing whatsoever about this machine.
```

Line 28:

```text
MARK: - Port conflict
```

Line 95:

```text
MARK: - Leaked daemon
```

Line 151:

```text
MARK: - Disk filling
```

## Sources/FleetCore/RunbookValidation.swift

Line 3:

```text
The runbook linter.
```

Line 5:

```text
A runbook arrives as data — eventually from outside this repository, shipped
```

Line 6:

```text
beside a model by someone who is not in the room. The type system stops it
```

Line 7:

```text
asking for an action that does not exist; this file stops the rest: an
```

Line 8:

```text
unattended deletion, a step nobody can justify, a sweep with no ceiling, a
```

Line 9:

```text
document that forgot to say what happens when the culprit turns out not to be
```

Line 10:

```text
ours.
```

Line 12:

```text
Every rule here exists because the shape it rejects is one a plausible author
```

Line 13:

```text
would otherwise write by accident.
```

Line 15:

```text
/ One thing wrong with a runbook.
```

Line 18:

```text
/ The document is refused. Loading it would mean running something
```

Line 19:

```text
/ whose safety cannot be established by reading it.
```

Line 21:

```text
/ The document loads. Something about it will make the operator's life
```

Line 22:

```text
/ worse, and the author should hear about it.
```

Line 27:

```text
/ The step at fault, or `nil` for a defect in the document as a whole.
```

Line 42:

```text
/ The most services one step may act on.
```

Line 44:

```text
/ Not a performance limit. The approval list is the control, and an
```

Line 45:

```text
/ operator asked to approve thirty stops at once will approve them without
```

Line 46:

```text
/ reading — at which point the gate has become a formality and the runbook
```

Line 47:

```text
/ is unattended in everything but name.
```

Line 59:

```text
MARK: - The document
```

Line 64:

```text
A reader that guesses at an unknown schema is a reader that will one
```

Line 65:

```text
day guess wrong about an action's meaning.
```

Line 81:

```text
The briefing is the domain knowledge the model does not have. Without
```

Line 82:

```text
it the runbook is a list of buttons and the model is guessing.
```

Line 99:

```text
MARK: - Steps
```

Line 104:

```text
The rule the whole format exists to enforce.
```

Line 110:

```text
The other direction is not dangerous, it is corrosive: approvals
```

Line 111:

```text
for steps that change nothing teach the operator to click through
```

Line 112:

```text
the ones that do.
```

Line 152:

```text
/ A stop or a hand-off with no reason gives the operator an event they
```

Line 153:

```text
/ cannot account for later.
```

Line 167:

```text
MARK: - Parameters
```

Line 196:

```text
An input the operator is asked for and nothing consumes is a question
```

Line 197:

```text
with no consequence, which is worse than not asking.
```

Line 231:

```text
MARK: - Stops
```

Line 237:

```text
The one stop that is not a matter of taste. Nothing in this product
```

Line 238:

```text
signals a process the controller did not start, and a runbook that
```

Line 239:

```text
does not say what it does when the culprit turns out to be somebody
```

Line 240:

```text
else's has not thought about the case that matters most.
```

Line 263:

```text
/ Everything wrong with this document, most severe first.
```

Line 271:

```text
/ Whether this document may be run at all. A warning is a note to its
```

Line 272:

```text
/ author; a critical is a refusal.
```

## Sources/FleetCore/SMC.swift

Line 6:

```text
Fan and die temperatures from the System Management Controller.
```

Line 8:

```text
`ProcessInfo.thermalState` is a four-band summary and knows nothing about
```

Line 9:

```text
fans; the numbers a person actually asks about — "how fast is the fan
```

Line 10:

```text
spinning", "how hot is the die" — live in the SMC. Apple publishes none of
```

Line 11:

```text
this as API, so the key set below is the empirically stable subset: the
```

Line 12:

```text
same four-letter keys every SMC-equipped Mac has answered for a decade.
```

Line 14:

```text
The value *formats* are published folklore of a firmer kind: the kernel's
```

Line 15:

```text
own SMC client headers (AppleSMC Family) define `sp78` as a signed 7.8
```

Line 16:

```text
fixed-point degrees-C and `fpe2` as an unsigned 14.2 fixed-point RPM. Both
```

Line 17:

```text
are decoded big-endian, which is what the byte order on the wire has always
```

Line 18:

```text
been.
```

Line 20:

```text
Two machine classes answer "unknown", and both are real:
```

Line 21:

```text
VMs and very old Macs simply have no AppleSMC service in the I/O
```

Line 22:

```text
Registry, so `open()` fails.
```

Line 23:

```text
Apple silicon Macs answer the connection but hold far fewer keys than
```

Line 24:

```text
Intel machines did; a key that returns a zero-length value is treated
```

Line 25:

```text
as absent rather than as a fan that is stopped or a die at 0 °C.
```

Line 27:

```text
Nothing here throws. A host without SMC data is a normal host, and the
```

Line 28:

```text
value types carry the absence explicitly.
```

Line 30:

```text
MARK: - Value types
```

Line 32:

```text
/ One fan's reading. `rpm == nil` means the key was absent or answered with
```

Line 33:

```text
/ no data — a stopped fan reports 0, so nil is never confused with stopped.
```

Line 44:

```text
/ What the SMC knows about this host right now.
```

Line 47:

```text
/ CPU die temperature in °C, nil when the key set answered nothing.
```

Line 49:

```text
/ GPU temperature in °C where the machine exposes one (Intel Macs with
```

Line 50:

```text
/ discrete graphics). Apple silicon reports no GPU key; nil, not 0.
```

Line 52:

```text
/ Whether the SMC connection itself opened. Distinguishes "no SMC on
```

Line 53:

```text
/ this machine" from "SMC answered, but it holds no keys we read".
```

Line 64:

```text
/ The loudest fan, for the one-line summary. Nil when no fan reported.
```

Line 70:

```text
MARK: - Key layout
```

Line 72:

```text
/ A four-character SMC key. Keys are compared by value, and building one
```

Line 73:

```text
/ from a literal is a compile-time act, so this is a struct rather than four
```

Line 74:

```text
/ loose bytes passed around.
```

Line 85:

```text
/ The data types this file knows how to decode. The SMC carries dozens more;
```

Line 86:

```text
/ adding one is adding a case and a decoder, not touching the read path.
```

Line 88:

```text
/ Signed 7.8 fixed point — every temperature key on Intel Macs.
```

Line 90:

```text
/ Unsigned 14.2 fixed point — every fan-actual key.
```

Line 92:

```text
/ IEEE 754 binary32 — the float encoding some Apple silicon keys use.
```

Line 96:

```text
MARK: - Decoding (pure, testable)
```

Line 99:

```text
/ `sp78`: big-endian signed 7.8 fixed point. Two bytes, nothing else is
```

Line 100:

```text
/ well-formed; a short read is absent data, not a cold sensor.
```

Line 107:

```text
/ `fpe2`: big-endian unsigned 14.2 fixed point.
```

Line 114:

```text
/ `flt `: a big-endian 32-bit float. SMC byte order is big-endian
```

Line 115:

```text
/ regardless of host endianness, so the bytes are assembled by hand.
```

Line 120:

```text
A NaN in a temperature register is a sensor that failed; report it
```

Line 121:

```text
as absent so it cannot render as a number.
```

Line 134:

```text
MARK: - Key discovery (pure, testable)
```

Line 137:

```text
/ Fan keys, in probe order. `F0Ac`/`F1Ac` cover every shipping layout
```

Line 138:

```text
/ (a Mac Pro reports more; the loop below is capped at what the UI can
```

Line 139:

```text
/ honestly show, and eight fans is past that).
```

Line 144:

```text
/ Temperature keys, most-preferred first. The first key that returns a
```

Line 145:

```text
/ value wins, so the order *is* the meaning: proximity sensors (TC0P)
```

Line 146:

```text
/ read a few degrees lower than die sensors (TC0D/TC0E/TC0F), and the
```

Line 147:

```text
/ die is what throttling is decided on.
```

Line 149:

```text
CPU proximity — the most consistently present
```

Line 150:

```text
CPU die
```

Line 151:

```text
CPU die (multi-die parts)
```

Line 152:

```text
CPU die digital
```

Line 153:

```text
CPU core 0 (older Macs)
```

Line 154:

```text
PECI package (2018+ Intel)
```

Line 157:

```text
/ GPU keys. Absent on every Apple silicon machine and on integrated-only
```

Line 158:

```text
/ Intel Macs; the absence is the normal case.
```

Line 160:

```text
GPU proximity
```

Line 161:

```text
GPU die
```

Line 162:

```text
GPU heatsink
```

Line 166:

```text
MARK: - Connection
```

Line 168:

```text
/ One open connection to the AppleSMC service.
```

Line 170:

```text
/ Reading is two round trips per key — read the key's descriptor for its
```

Line 171:

```text
/ type and size, then read the value — because the size is how the SMC says
```

Line 172:

```text
/ "I don't have that": a key it does not hold answers the descriptor call
```

Line 173:

```text
/ with an error, which is the absence signal every probe above relies on.
```

Line 176:

```text
/ No AppleSMC service in the I/O Registry (VMs, very old hardware).
```

Line 186:

```text
This mirrors AppleSMC's SMCKeyData_t. The key-info fields are separate
```

Line 187:

```text
fields in the kernel ABI; packing them into one UInt32 makes Swift send
```

Line 188:

```text
a 60-byte struct and the driver rejects every call with invalid input
```

Line 189:

```text
structure size. The ABI is 80 bytes, including the explicit padding.
```

Line 237:

```text
/ The input/output size required by the AppleSMC kernel ABI.
```

Line 243:

```text
/ Whether the SMC on this host can be talked to at all. Cached by the
```

Line 244:

```text
/ caller — `sample()` below is the cheap check for one polling loop.
```

Line 266:

```text
/ One key read: descriptor for type and size, then the value. Absent
```

Line 267:

```text
/ keys throw `keyNotFound`; callers probing a list of keys catch it and
```

Line 268:

```text
/ move to the next.
```

Line 271:

```text
Kernel constants from AppleSMC Family, stable since the service
```

Line 272:

```text
existed: 0 is the connection's own index, 5 is the "read one key"
```

Line 273:

```text
selector, 9 is "describe this key".
```

Line 287:

```text
kSMCGetKeyInfo
```

Line 291:

```text
kSMCHandleYPCEvent
```

Line 301:

```text
kSMCReadKey
```

Line 309:

```text
A type we do not decode is the same to the UI as no key: the
```

Line 310:

```text
alternative is rendering a number we cannot vouch for.
```

Line 319:

```text
/ Renders a big-endian four-char code back to its characters, for error
```

Line 320:

```text
/ messages that name the key that was missing.
```

Line 330:

```text
MARK: - Sampler
```

Line 332:

```text
/ Reads the whole sensor set once. Owns its connection; the polling loop in
```

Line 333:

```text
/ the app constructs one and reuses it, so the open cost is paid once.
```

Line 340:

```text
/ One full read. Never throws: every failure mode lands in the sample as
```

Line 341:

```text
/ `available == false` or a nil field, because the UI's question is
```

Line 342:

```text
/ "what can I show", not "what went wrong".
```

Line 373:

```text
Trust the descriptor's type when it disagrees with what we asked
```

Line 374:

```text
for: the SMC is the authority on its own encoding.
```

## Sources/FleetCore/SQLite.swift

Line 6:

```text
/ Minimal sqlite3 wrapper. No external dependencies: the registry must work on a
```

Line 7:

```text
/ clean machine with nothing but the OS.
```

Line 20:

```text
Reading a WAL database needs a shared-memory file, and a read-only
```

Line 21:

```text
connection cannot create one. Falling back to a read-write handle (never
```

Line 22:

```text
CREATE) is the difference between "history is readable when the daemon is
```

Line 23:

```text
down" and "the one moment you need it, you cannot have it".
```

Line 38:

```text
The 1000-page default lets the WAL grow to ~4 MB before SQLite trims it,
```

Line 39:

```text
and nothing here ever ran a checkpoint of its own — a 295 KB registry was
```

Line 40:

```text
observed carrying a 3.3 MB WAL. 256 pages caps it around 1 MB.
```

Line 42:

```text
NORMAL is the durability point WAL was designed for: a process crash
```

Line 43:

```text
cannot corrupt the file, only lose the last commits — and every writer
```

Line 44:

```text
here is a controller that re-verifies its state on startup anyway.
```

Line 53:

```text
/ Applies WAL frames back into the database. `truncate` also resets the WAL file
```

Line 54:

```text
/ to zero bytes instead of leaving already-applied frames on disk forever.
```

Line 62:

```text
/ Explicit, idempotent close. `deinit` is not a shutdown path here: fleetd always
```

Line 63:

```text
/ leaves through exit()/fatalError, so without this the WAL was simply abandoned
```

Line 64:

```text
/ for the next process to inherit.
```

## Sources/FleetCore/ServiceLabels.swift

Line 3:

```text
/ A personal tag, not a health/status vocabulary.
```

Line 11:

```text
/ Client-only presentation metadata. The controller's name and evidence stay intact.
```

## Sources/FleetCore/Shell.swift

Line 3:

```text
/ Holds what one drain closure read. `run` may read it while the other closure
```

Line 4:

```text
/ is still writing (the wait below can time out), so the bytes live behind a lock.
```

Line 5:

```text
/ A `Data` written by a drain thread and read by the caller after the group
```

Line 6:

```text
/ waits. Every access is under the lock.
```

Line 24:

```text
/ Small, bounded wrapper around read-only command-line probes (`ps`, `lsof`,
```

Line 25:

```text
/ `ping`, `ifconfig`, `tailscale`). Never used for user-supplied input: managed
```

Line 26:

```text
/ services are spawned by ProcessLauncher with an explicit argv, and the UI has
```

Line 27:

```text
/ no free-text command field at all.
```

Line 56:

```text
Drain both pipes concurrently so a chatty child cannot deadlock us on a
```

Line 57:

```text
full pipe buffer while we wait for exit.
```

Line 75:

```text
A grandchild that inherited the write ends keeps them open, so the
```

Line 76:

```text
reads above will never see EOF. Closing the read ends unblocks both
```

Line 77:

```text
drain threads and releases both descriptors.
```

Line 87:

```text
/ Resolves a tool by trying known locations then PATH.
```

## Sources/FleetCore/Snapshot.swift

Line 3:

```text
One consistent view of everything, and what the client derives from it. The
```

Line 4:

```text
daemon pushes a `Snapshot` on every state change and the UI never polls, so this
```

Line 5:

```text
is the whole contract between them. `AttentionItem` is derived client-side, so
```

Line 6:

```text
the CLI and the app cannot disagree about what needs looking at.
```

Line 7:

```text
MARK: - Attention
```

Line 34:

```text
MARK: - Snapshot
```

Line 88:

```text
/ On the books: everything not finished, including an expired lease that is
```

Line 89:

```text
/ being reported rather than reaped. This is what a list shows.
```

Line 92:

```text
/ Actually up. This is what a count worded "running" shows.
```

Line 97:

```text
/ Derived on the client so both the CLI and the app show the same thing
```

Line 98:

```text
/ without adding another server round trip.
```

Line 103:

```text
An agent with no services but an unanswered question still needs to
```

Line 104:

```text
appear — that is precisely the case you must not miss.
```

Line 113:

```text
`records` is everything not finished, which is right for ports and
```

Line 114:

```text
for attention: an expired record still holds its ports. It is
```

Line 115:

```text
wrong for a number labelled "running" — see ServiceState.isRunning.
```

Line 136:

```text
/ The full picture for one agent, including everything it has *done* — not
```

Line 137:

```text
/ just what it happens to be running this second. An idle agent still has a
```

Line 138:

```text
/ history worth showing; "0 services" on its own says nothing.
```

## Sources/FleetCore/StopMarker.swift

Line 3:

```text
/ Evidence that a controller generation was *told* to stop.
```

Line 5:

```text
/ The controller records a `daemonStopping` event on its way out, and the next
```

Line 6:

```text
/ generation reports "exited abnormally" when it finds a `daemonStarted` with
```

Line 7:

```text
/ no stop after it. That inference is sound but the write was unreachable in
```

Line 8:

```text
/ practice: `Controller.shutdown()` has to take the controller's serial queue
```

Line 9:

```text
/ before it can touch the registry, a supervisor tick can hold that queue for
```

Line 10:

```text
/ seconds doing health checks and `lsof`, and `launchctl bootout` follows its
```

Line 11:

```text
/ SIGTERM with a SIGKILL long before the tick finishes. The stop event never
```

Line 12:

```text
/ got written, so every deliberate restart was logged and displayed as a crash
```

Line 13:

```text
/ — 56 signals against 3 clean stops in this install's own log, and a critical
```

Line 14:

```text
/ "The controller has been restarting" item raised off the difference.
```

Line 16:

```text
/ So intent is recorded separately from the graceful path, by the signal
```

Line 17:

```text
/ handler itself, before any lock is taken: one `write(2)` to a file whose
```

Line 18:

```text
/ presence means "a stop signal arrived". A real abnormal exit — SIGKILL with
```

Line 19:

```text
/ no SIGTERM, a panic, power loss — still leaves no marker and is still
```

Line 20:

```text
/ reported as one. The marker only ever suppresses the claim in the case where
```

Line 21:

```text
/ the claim is false.
```

Line 23:

```text
/ Called from a signal handler, so this does the least possible work and
```

Line 24:

```text
/ never touches Foundation's higher-level file APIs.
```

Line 36:

```text
/ Reads the marker and removes it, so one signal can only ever explain one
```

Line 37:

```text
/ exit. Returns what the marker said, or nil if there was none.
```

## Sources/FleetCore/SystemTelemetry.swift

Line 4:

```text
/ Internal-battery state, not a UPS or a peripheral battery. Hosts without an
```

Line 5:

```text
/ internal battery leave charge and remaining time unavailable rather than 0.
```

Line 12:

```text
/ Minutes until full when charging, until empty when on battery; otherwise nil.
```

Line 27:

```text
/ Decodes the IOPS descriptions used by the live sampler, not a synthetic DTO.
```

Line 28:

```text
/ A nil collection represents a failed read.
```

Line 51:

```text
-1 means "still calculating" in the IOPS contract.
```

Line 61:

```text
/ Physical-interface throughput. Nil is an absent interval, not an idle link.
```

Line 63:

```text
/ A successful counter read can still lack an active link or a rate interval.
```

Line 81:

```text
/ Cumulative bytes from one link. Keep integers until after subtraction so a
```

Line 82:

```text
/ small delta is not lost when a long-lived interface has very large counters.
```

Line 93:

```text
/ Pure rate math; the caller owns sampling, the baseline and a monotonic clock.
```

Line 95:

```text
/ Five missed 2-second ticks are a gap, not a useful current average.
```

## Sources/FleetCore/TCPProbe.swift

Line 4:

```text
/ One TCP reachability implementation, shared by the daemon's health checks and
```

Line 5:

```text
/ the app's connection probes so the two can never disagree about what
```

Line 6:

```text
/ "reachable" means.
```

Line 14:

```text
/ Non-blocking connect + select, so the timeout is real rather than whatever
```

Line 15:

```text
/ the kernel's default happens to be.
```

Line 81:

```text
fd_set manipulation is not exposed to Swift; these are the standard shims.
```

Line 82:

```text
Darwin's fd_set is 1024 bits held as 32 Int32 words.
```

Line 89:

```text
/ Returns false when the descriptor is outside the fixed 1024-bit map, which
```

Line 90:

```text
/ `select` cannot represent — the caller has to report that as a probe failure
```

Line 91:

```text
/ rather than write past the end of the set.
```

Line 97:

```text
Bit 31 is Int32's sign bit, so `Int32(1 << 31)` traps on "not enough bits";
```

Line 98:

```text
build the mask unsigned and reinterpret it.
```

## Sources/FleetCore/Tailscale.swift

Line 3:

```text
/ Read-only view of `tailscale status --json`. Never issues control commands —
```

Line 4:

```text
/ FleetConsole observes the tailnet, it does not reconfigure it.
```

Line 21:

```text
/ Synthetic example: "demo-node.example.ts.net." → "demo-node"
```

Line 40:

```text
/ The peer currently being used as this machine's exit node, if any.
```

Line 57:

```text
/ Includes self, so a device configured with this machine's own name resolves.
```

Line 152:

```text
`Date.ISO8601FormatStyle` rather than `ISO8601DateFormatter`: a Sendable
```

Line 153:

```text
value with its options fixed at construction, so there is no shared mutable
```

Line 154:

```text
formatter to guard. Same two shapes: RFC 3339 with and without fractions.
```

Line 158:

```text
/ `0001-01-01…` is Go's zero `time.Time` — what tailscale sends for "never
```

Line 159:

```text
/ seen". Syntactically a date, so it is rejected by name before parsing.
```

## Sources/FleetCore/TelemetryReadiness.swift

Line 3:

```text
/ Verification distinguishes unsupported hardware from a failed live probe.
```

## Sources/FleetCore/TopologyOptions.swift

Line 3:

```text
/ Strict read-only command options; a boolean flag never consumes an operand.
```

## Sources/FleetCore/Troubleshooting.swift

Line 3:

```text
Bounded, evidence-based troubleshooting suggestions.
```

Line 5:

```text
The console observes; it does not act. This turns attention items, service
```

Line 6:

```text
records and a slice of recent events into a short list of common problems a
```

Line 7:

```text
person can look at, with checks and remedies as prose. Nothing here reads a
```

Line 8:

```text
log, opens a socket, or signals a process.
```

Line 10:

```text
Recurrence is the count of matching events in the bounded recent slice the
```

Line 11:

```text
caller passed — not a lifetime counter, not a fleet-wide rate. Missing
```

Line 12:

```text
observations stay unavailable. Process existence is never treated as health.
```

Line 13:

```text
Unmanaged and claimed processes are never offered a controller signal.
```

Line 15:

```text
MARK: - Suggestion
```

Line 17:

```text
/ One problem, the evidence it rests on, and what a person may inspect or do.
```

Line 19:

```text
/ `id` is stable for a (category, subject) pair so a UI can diff successive
```

Line 20:

```text
/ snapshots without inventing its own keys. `occurrences` is the number of
```

Line 21:

```text
/ matching events in the bounded recent log, or zero when only the current
```

Line 22:

```text
/ attention/record is present. It is not a failure probability or a lifetime total.
```

Line 42:

```text
MARK: - Entry point
```

Line 46:

```text
/ Hard caps so a large snapshot cannot grow a wall of advice.
```

Line 53:

```text
/ Same window the controller uses for a daemon crash loop: two abnormal
```

Line 54:

```text
/ exits inside six hours is a pattern; one is not.
```

Line 56:

```text
/ Evidence older than this is stale for listener/health claims. Wider than
```

Line 57:

```text
/ the controller's tick×factor (15s) so a snapshot a few seconds old is
```

Line 58:

```text
/ still usable, tight enough that an hour-old scan is not "current".
```

Line 61:

```text
/ Derive suggestions from the current attention list, the service records
```

Line 62:

```text
/ those items refer to, and a recent event slice. `now` is injected so the
```

Line 63:

```text
/ path is fixture-testable.
```

Line 113:

```text
MARK: Categories
```

Line 115:

```text
/ Closed set of problems this function will name. Unknown attention IDs
```

Line 116:

```text
/ and unrelated states are ignored rather than turned into a generic
```

Line 117:

```text
/ "something is wrong".
```

Line 140:

```text
MARK: Attention / state → key
```

Line 184:

```text
/ Missing listeners require a scan that actually ran, on a process that
```

Line 185:

```text
/ is not known to be gone, with evidence that is not stale. An empty
```

Line 186:

```text
/ `listeningPorts` array without `portScanRan` is "not checked", not
```

Line 187:

```text
/ "nothing is listening".
```

Line 199:

```text
MARK: Events
```

Line 229:

```text
/ Port conflicts and unmanaged leaks are offered only when evidence
```

Line 230:

```text
/ exists. Crash recurrence is offered when the bounded log shows a
```

Line 231:

```text
/ pattern (two or more), even if the process is currently up.
```

Line 247:

```text
Legacy unmanaged events have no process identity. Do not
```

Line 248:

```text
merge unrelated processes or guess identity from free text.
```

Line 342:

```text
MARK: Render
```

## Sources/FleetCore/UnixSocket.swift

Line 4:

```text
macOS peer-credential lookup constants (sys/socket.h, sys/un.h).
```

Line 28:

```text
/ One accepted connection. Framing is newline-delimited JSON.
```

Line 29:

```text
/ `@unchecked Sendable` under two different disciplines: `buffer` is confined to
```

Line 30:

```text
/ the one thread the server starts per accepted connection, while `closed` and
```

Line 31:

```text
/ every write are serialised by `writeLock` — the broadcast path writes while
```

Line 32:

```text
/ that owning thread is parked in `read`.
```

Line 45:

```text
Without a send timeout a subscriber that stops draining wedges writeLine
```

Line 46:

```text
forever. 5s is one daemon tick: a peer that far behind gets dropped.
```

Line 51:

```text
/ Backstop for callers that drop the connection on an error path; `close()`
```

Line 52:

```text
/ is idempotent so this cannot double-close a reissued descriptor.
```

Line 57:

```text
/ Blocking read of one newline-terminated message. nil = peer closed.
```

Line 124:

```text
/ Listening socket. Created 0600 inside a 0700 directory; every accepted peer's
```

Line 125:

```text
/ euid is verified against ours before a single byte is read (threat model T5).
```

Line 139:

```text
A stale socket file from a crash would block bind(); it is safe to remove
```

Line 140:

```text
because we already verified no live daemon answers on it (see probeAlive).
```

Line 149:

```text
resulting socket file is 0600
```

Line 168:

```text
/ Blocking accept loop. Each accepted connection is handed to `handler` on its
```

Line 169:

```text
/ own thread; the handler owns closing it.
```

Line 216:

```text
/ Blocking client used by fleetctl and by the app's background connections.
```

Line 241:

```text
/ One request, one response. Used for every non-streaming operation.
```

Line 258:

```text
/ Cheap liveness probe used before removing a stale socket file.
```

## Sources/FleetCore/Unmanaged.swift

Line 3:

```text
Processes the controller can see but did not start. An unmanaged row gets a
```

Line 4:

```text
name, a reason it was noticed and a "Reveal in Activity Monitor" — never a
```

Line 5:

```text
stop button.
```

Line 6:

```text
MARK: - Unmanaged processes
```

Line 11:

```text
declared port still held after its owning group died
```

Line 23:

```text
stable key: "pid:startsig"
```

Line 25:

```text
executable name
```

Line 26:

```text
full argv, truncated
```

Line 32:

```text
/ Set when this process was once managed by us (strongest possible signal of a leak).
```

## Sources/fleetctl/main.swift

Line 4:

```text
fleetctl — the launcher agents call instead of spawning background processes
```

Line 5:

```text
themselves. Every managed process in FleetConsole enters the registry here.
```

Line 108:

```text
/ Tiny argument reader. Everything after `--` is the command to run, untouched.
```

Line 169:

```text
/ String(format:) does not pad %@ arguments, so columns are padded by hand.
```

Line 228:

```text
MARK: - Dispatch
```

Line 349:

```text
Every other read verb goes over the socket and exits 69 when nothing answers —
```

Line 350:

```text
i.e. history becomes unreadable at exactly the moment you need it, which is
```

Line 351:

```text
after the controller died. This path opens the registry read-only instead.
```

Line 540:

```text
launchd throttles restarts (ThrottleInterval), so a controller that is simply
```

Line 541:

```text
coming back up looks identical to a broken one for ~10 seconds. Waiting is
```

Line 542:

```text
the difference between a useful diagnosis and a false alarm.
```

Line 577:

```text
Unmanaged processes are a state of the machine, not a fault in the
```

Line 578:

```text
install — reporting them as a failure here would contradict the whole
```

Line 579:

```text
point of the attention rules and make `doctor` cry wolf on every run.
```

Line 639:

```text
Said every time, not buried in --help. The whole point of the verb is
```

Line 640:

```text
that it changes what you can *see*, and someone who reads "claimed" as
```

Line 641:

```text
"now under control" will be surprised by `stop` at the worst moment.
```

Line 659:

```text
Offline key minting — the issuer side of License.swift's FLT1 format.
```

Line 660:

```text
This is the checkout seam for the freemium model: a store webhook (or the
```

Line 661:

```text
Ouros bar on the user's behalf) shells out here, prints a key, and the
```

Line 662:

```text
gate in the app opens. No daemon, no network: keys are deterministic
```

Line 663:

```text
HMAC over an issue date, so issuance works while the controller is down.
```

## Sources/fleetd/Controller.swift

Line 5:

```text
/ The controller. Owns every managed process, the registry, the reconciliation
```

Line 6:

```text
/ sweep and the local RPC surface.
```

Line 8:

```text
/ Concurrency model: one serial queue owns all mutable state and the SQLite
```

Line 9:

```text
/ handle. Anything that can block for a meaningful time (subprocess capture,
```

Line 10:

```text
/ health checks, socket writes to subscribers) happens off that queue and posts
```

Line 11:

```text
/ its result back onto it.
```

Line 13:

```text
/ That paragraph is the justification for `@unchecked Sendable`: the serial queue
```

Line 14:

```text
/ is what makes every stored property safe to touch from the other two.
```

Line 36:

```text
/ Broadcast coalescing state, owned by `queue`: one write in flight, one pending.
```

Line 40:

```text
/ Services we asked to stop, with the deadline after which SIGTERM becomes SIGKILL.
```

Line 42:

```text
/ Services with an in-flight health check, so ticks cannot pile them up.
```

Line 69:

```text
MARK: - Lifecycle
```

Line 86:

```text
The log is unconditional; only the registry write needs `self`, and
```

Line 87:

```text
it binds once rather than loading the weak reference twice.
```

Line 101:

```text
Blocking accept loop; each connection is handled on its own thread.
```

Line 108:

```text
Ticks and the accept loop stop first: they would otherwise keep writing to a
```

Line 109:

```text
registry we are about to close.
```

Line 115:

```text
The process leaves through exit() immediately after this, so `deinit` will
```

Line 116:

```text
not run: this is the only point where the WAL gets checkpointed and the
```

Line 117:

```text
database file is released cleanly.
```

Line 120:

```text
The stop event is on the timeline, so the marker has nothing left to
```

Line 121:

```text
explain. Clearing it here keeps the clean path from leaving a file
```

Line 122:

```text
that would otherwise be consumed by the next startup for no reason.
```

Line 127:

```text
/ A controller that dies through fatalError, SIGKILL or a panic writes nothing at
```

Line 128:

```text
/ all, so an abnormal exit is only visible as the *absence* of a `daemonStopping`
```

Line 129:

```text
/ after the previous `daemonStarted`. Recorded here, before this generation's own
```

Line 130:

```text
/ start event, so the crash lands on the timeline where it actually happened.
```

Line 132:

```text
/ The absence of a stop event is not on its own evidence of a crash, which is what
```

Line 133:

```text
/ this used to treat it as. A generation that was signalled and then killed before
```

Line 134:

```text
/ it could finish shutting down also leaves no stop event, and that is a deliberate
```

Line 135:

```text
/ restart — the overwhelmingly common case here, since `Scripts/build-app.sh`
```

Line 136:

```text
/ bootouts the agent on every build. `StopMarker` is written by the signal handler
```

Line 137:

```text
/ before any lock is taken, so it survives the kill and separates the two.
```

Line 139:

```text
Consumed unconditionally: one signal explains at most one exit, and a
```

Line 140:

```text
marker left behind by a clean stop must not excuse a later crash.
```

Line 163:

```text
/ Crash-consistent startup: every non-terminal record is re-verified against
```

Line 164:

```text
/ live processes before we serve a single snapshot (threat model T3).
```

Line 202:

```text
/ SIGCHLD gives us real exit codes. Without it, children would linger as zombies
```

Line 203:

```text
/ and "crashed vs stopped" would be a guess.
```

Line 221:

```text
negative = terminated by that signal
```

Line 248:

```text
MARK: - Supervisor tick
```

Line 251:

```text
Subprocess capture happens off the state queue.
```

Line 264:

```text
A `ps` that did not run tells us nothing about liveness. Judging services
```

Line 265:

```text
against an empty table would declare every one of them crashed, so the
```

Line 266:

```text
tick reports itself and stops — evidence simply goes stale, which the
```

Line 267:

```text
attention rules already surface honestly.
```

Line 285:

```text
Evidence captured before a service started says nothing about it.
```

Line 286:

```text
Capturing the process table takes a few hundred milliseconds and
```

Line 287:

```text
happens *before* this queue is entered, so a service launched inside
```

Line 288:

```text
that window used to be judged against a snapshot that predates it,
```

Line 289:

```text
declared "crashed" in the same second, and then survive as an orphan
```

Line 290:

```text
holding its port — precisely the leak this controller exists to stop.
```

Line 298:

```text
SIGCHLD usually gets here first; this is the backstop for a process
```

Line 299:

```text
that was never our direct child or whose signal we missed.
```

Line 314:

```text
A stop is in flight: refresh the evidence but never re-derive the
```

Line 315:

```text
state, or a healthy-but-dying service would flip back to "healthy"
```

Line 316:

```text
between SIGTERM and exit.
```

Line 333:

```text
Rolling history for the sparklines. Capped so a service that runs for
```

Line 334:

```text
a week cannot grow its own record without bound.
```

Line 344:

```text
A paused process is deliberately doing nothing: it keeps its ports and
```

Line 345:

```text
its memory, so liveness and resources still update, but no health check
```

Line 346:

```text
is run against it and no lease decision is re-derived from silence.
```

Line 375:

```text
Lease and hard runtime ceiling — the two independent leak defences (T1).
```

Line 377:

```text
Already-expired records are not re-evaluated. For a launched service
```

Line 378:

```text
that guard is invisible, because the stop below takes it out of this
```

Line 379:

```text
loop within a tick. For a *claimed* one it is what stops the loop:
```

Line 380:

```text
the record stays expired and the process stays alive by design, so
```

Line 381:

```text
without it every tick would append another `leaseExpired` event for
```

Line 382:

```text
as long as the process ran.
```

Line 400:

```text
this agent left something running
```

Line 404:

```text
A claimed record expires on the screen and nowhere else. The
```

Line 405:

```text
state, the event and the attention row all still fire — what
```

Line 406:

```text
does not fire is the signal, because the controller did not
```

Line 407:

```text
start this process and does not own the consequences of ending
```

Line 408:

```text
it. Stopping it is yours to do, where you started it.
```

Line 418:

```text
An expired record keeps that state. Nothing below can improve it, and
```

Line 419:

```text
re-deriving would walk a claimed one back to `expiring` — which
```

Line 420:

```text
re-arms the block above and reinstates the per-tick event storm the
```

Line 421:

```text
guard there exists to prevent.
```

Line 448:

```text
/ The honesty rule, encoded: "healthy" requires a check that ran and passed.
```

Line 449:

```text
/ Without a configured check the best available state is `running` — the UI
```

Line 450:

```text
/ renders that as "Running (unverified)".
```

Line 467:

```text
PID-reuse guard: same pid, different start time means a *different* process.
```

Line 479:

```text
/ A service whose group died but whose port is still held did not clean up
```

Line 480:

```text
/ properly; that is a leak and it must not disappear silently (T1 residual risk).
```

Line 491:

```text
MARK: - Health checks
```

Line 538:

```text
Only transitions are recorded, plus the moment a failure crosses its
```

Line 539:

```text
threshold — an event log full of identical lines is not a timeline.
```

Line 550:

```text
MARK: - Reconciliation
```

Line 553:

```text
A failed `ps`/`lsof` is not an empty machine. Sweeping on one would delete
```

Line 554:

```text
every unmanaged row (losing `firstSeen`) and then re-emit the whole set as new
```

Line 555:

```text
`becameUnmanaged` events on the next good sweep — 447 of 867 events in the live
```

Line 556:

```text
registry were duplicates produced exactly this way. Keep the prior state and
```

Line 557:

```text
do not mark the sweep as done, so the next tick retries.
```

Line 566:

```text
Declared local tools are resolved first; whatever they own is then
```

Line 567:

```text
excluded from the unmanaged sweep.
```

Line 571:

```text
The coding agents you are actually running, detected rather than registered.
```

Line 574:

```text
A failed write must not become a reset either: `found` carries a fresh
```

Line 575:

```text
`firstSeen` for everything, so falling back to it would age-reset the list.
```

Line 607:

```text
MARK: - Mutating operations
```

Line 632:

```text
keys only, never values (T6)
```

Line 660:

```text
/ Adopt an already-running process into the registry.
```

Line 662:

```text
/ The counterpart to `launch`, and deliberately not a weaker version of it.
```

Line 663:

```text
/ A launched service is one the controller started, so it owns the
```

Line 664:

```text
/ consequences of stopping it. A claimed one was already there when we
```

Line 665:

```text
/ arrived: it gets an owner, a purpose, a lease and a timeline, and the
```

Line 666:

```text
/ controller still refuses to signal it — see `isSignallableByController`,
```

Line 667:

```text
/ which every signal path in this file consults. Claiming buys
```

Line 668:

```text
/ **visibility**, not authority, which is why it is safe to offer for a
```

Line 669:

```text
/ process whose lifecycle somebody else owns.
```

Line 671:

```text
/ The target is re-verified here rather than trusted from the sweep that
```

Line 672:

```text
/ found it: an `UnmanagedProcess.id` is `pid:hash(startSignature)`, so a pid
```

Line 673:

```text
/ recycled between the sweep and the click is caught by the same comparison
```

Line 674:

```text
/ that guards every signal (threat model T2).
```

Line 681:

```text
Either an id from the unmanaged list, or a bare pid for the case where
```

Line 682:

```text
you are looking at Activity Monitor rather than at this app.
```

Line 696:

```text
The id carries the signature the process was seen with. A mismatch means
```

Line 697:

```text
the number was recycled and this is a different process wearing it.
```

Line 725:

```text
Its uptime is its own, not the moment we noticed
```

Line 726:

```text
it — a claimed record that resets the clock would
```

Line 727:

```text
hide exactly how long a leak has been running.
```

Line 732:

```text
No health check: nobody declared one, and the
```

Line 733:

```text
best state this can reach is Running (unverified).
```

Line 753:

```text
The sweep's own list is stale the moment this returns — the row the user
```

Line 754:

```text
clicked is now a service. Drop it here rather than leaving the process
```

Line 755:

```text
listed as both until the next reconcile.
```

Line 760:

```text
/ The one rule claiming does not buy its way out of, in one place.
```

Line 762:

```text
/ Every controller-initiated signal goes through here or through
```

Line 763:

```text
/ `verifiedTarget`, so a claimed record cannot be stopped, restarted, paused,
```

Line 764:

```text
/ resumed, killed or reaped by us — only reported on.
```

Line 794:

```text
/ Verify-then-signal. Nothing is ever signalled without re-proving the target
```

Line 795:

```text
/ is still the process we started (threat model T2).
```

Line 798:

```text
Defence in depth. The two callers that can be reached from outside —
```

Line 799:

```text
the stop RPC and `restart` — refuse a claimed record with a message
```

Line 800:

```text
first, because a verb that silently does nothing is worse than one that
```

Line 801:

```text
says no. This is the invariant underneath them, so a third caller added
```

Line 802:

```text
later cannot signal a process the controller did not start.
```

Line 877:

```text
/ Deliberately *not* run on the state queue: waiting for a process group to
```

Line 878:

```text
/ die must never stall the supervisor or the RPC surface.
```

Line 880:

```text
/ Restart re-executes the argv recorded at launch — it is not a general
```

Line 881:

```text
/ "run a command" entry point, which is why the UI can expose it safely.
```

Line 886:

```text
Restart is stop-then-relaunch, and a claimed record fails at both
```

Line 887:

```text
halves: we may not stop it, and its argv came off `ps` rather than
```

Line 888:

```text
from a caller who declared it, so re-running it would be the app
```

Line 889:

```text
inventing a service — the thing the README says it never does.
```

Line 936:

```text
/ Shared precondition for every signal we send: the pid must still exist and
```

Line 937:

```text
/ its start time must match what we recorded, or we are looking at a different
```

Line 938:

```text
/ process that merely inherited the number (threat model T2).
```

Line 940:

```text
Before "is this still the right process", the prior question: is it ours
```

Line 941:

```text
to signal at all. Pause, resume and kill all resolve their target here.
```

Line 1004:

```text
/ No grace period, by explicit request. Same verification as every other signal.
```

Line 1014:

```text
A stopped process cannot die; wake it first or SIGKILL just queues.
```

Line 1041:

```text
"No log file yet" is true for a service that has just started and
```

Line 1042:

```text
false for a claimed one, which will never have a log file here: its
```

Line 1043:

```text
descriptors were wired up by whoever started it, long before we
```

Line 1044:

```text
adopted it. Saying "yet" would promise output that is never coming.
```

Line 1063:

```text
MARK: - Snapshot
```

Line 1067:

```text
Read once and share: the attention rules need the same history the UI shows.
```

Line 1081:

```text
/ A crash loop in the controller itself is only news while it is recent, and one
```

Line 1082:

```text
/ abnormal exit is not yet a pattern — two inside this window is.
```

Line 1090:

```text
The controller restarting leaves no service row behind, so without this item a
```

Line 1091:

```text
crash loop is invisible in a UI built entirely out of services: 136 starts
```

Line 1092:

```text
against 43 clean stops was only discoverable by reading the database by hand.
```

Line 1112:

```text
Both halves of this detail are false for a claimed record, and
```

Line 1113:

```text
the second one dangerously so: "controller is reaping it" would
```

Line 1114:

```text
have you stop watching a process nobody is going to stop.
```

Line 1145:

```text
Only the most recent crash per name, and only while it is still news.
```

Line 1146:

```text
Five identical "crashed" rows from five restart attempts is noise that
```

Line 1147:

```text
buries the one line that matters.
```

Line 1160:

```text
Unmanaged processes are a *state*, not an incident. Only two kinds are
```

Line 1161:

```text
worth interrupting for: something that leaked out of our own control, and
```

Line 1162:

```text
something that has just appeared. A listener that has been up for hours is
```

Line 1163:

```text
part of the furniture — it stays visible in the Services list and in the
```

Line 1164:

```text
dashboard, but it does not sit in "Needs attention" forever nagging.
```

Line 1193:

```text
/ Always hops onto the state queue asynchronously: callers may or may not
```

Line 1194:

```text
/ already be running on it, and `queue.sync` from within the queue deadlocks.
```

Line 1199:

```text
/ Must be called on `queue`.
```

Line 1202:

```text
Coalesce. Ticks, health transitions and device probes all broadcast, and every
```

Line 1203:

```text
queued closure pins a whole Snapshot (all services, 60 events, 60 messages,
```

Line 1204:

```text
devices, sessions). Behind a subscriber that is not draining, those used to
```

Line 1205:

```text
pile up on `broadcastQueue` without bound. At most one write is in flight and
```

Line 1206:

```text
at most one is pending, and the pending one is built fresh when its turn comes
```

Line 1207:

```text
— a newer snapshot always supersedes an older one.
```

Line 1216:

```text
/ Must be called on `queue`, with `broadcastInFlight` already set.
```

Line 1220:

```text
Bind once. Five separate `self?` loads meant a controller torn down
```

Line 1221:

```text
mid-broadcast could drop a subscriber and then fail to clear
```

Line 1222:

```text
`broadcastInFlight`, wedging every later broadcast.
```

Line 1229:

```text
The write can now time out as well as fail outright; either way
```

Line 1230:

```text
this subscriber is not keeping up and is dropped rather than
```

Line 1231:

```text
allowed to stall every other one.
```

Line 1253:

```text
/ An empty string is not a name, an owner or a purpose. Collapsing it to nil
```

Line 1254:

```text
/ here is what lets `claim` fall through to its defaults with `??` instead of
```

Line 1255:

```text
/ filing a record whose `friendlyName` is "".
```

## Sources/fleetd/ControllerRPC.swift

Line 4:

```text
The wire protocol. Split from Controller.swift so the state machine and the
```

Line 5:

```text
switch that dispatches into it are not the same file.
```

Line 7:

```text
The cost: the members reached for below are `internal` rather than `private`.
```

Line 8:

```text
fleetd is a seven-file executable, so that is module-private either way.
```

Line 12:

```text
MARK: - Connection handling
```

Line 41:

```text
further pushes come from broadcastSnapshot()
```

Line 53:

```text
MARK: - Answer shapes
```

Line 55:

```text
Three shapes cover every verb. A mutating verb that forgets its broadcast
```

Line 56:

```text
leaves every open dashboard stale until the next supervisor tick, so the
```

Line 57:

```text
broadcast belongs in the shape rather than in ten copies of it.
```

Line 59:

```text
/ Anything that throws answers with the error's own description.
```

Line 68:

```text
/ On the state queue, broadcast, answer with the record. Every verb that
```

Line 69:

```text
/ changes one service.
```

Line 78:

```text
/ On the state queue, broadcast, answer with a fresh snapshot. Every verb
```

Line 79:

```text
/ that changes the fleet rather than one service.
```

Line 88:

```text
MARK: - Dispatch
```

Line 127:

```text
Not `answeringWithRecord`: `restart` is stop-then-relaunch and owns
```

Line 128:

```text
its own queue hops, so it must not be wrapped in another `sync`.
```

Line 138:

```text
An unknown id must fail loudly. Silently widening to the global
```

Line 139:

```text
log would answer a question nobody asked.
```

Line 162:

```text
Captured off the state queue and passed in, so the verification and
```

Line 163:

```text
the record are built from one table rather than two moments.
```

Line 179:

```text
No broadcast: `probeDevices` pushes its own once the probe lands.
```

Line 249:

```text
Answers bare: the caller knows which ids it marked, and the
```

Line 250:

```text
dashboards get the change by broadcast.
```

Line 270:

```text
Its own catch, for its own message: "could not update config" says
```

Line 271:

```text
the allow-list was not written; an error from inside save() does not.
```

Line 287:

```text
Terminal service rows only. The event log is append-only and is
```

Line 288:

```text
never touched by this — the audit trail outlives the records.
```

## Sources/fleetd/DeviceProber.swift

Line 4:

```text
/ Reachability probes for the machines you care about. Three independent pillars
```

Line 5:

```text
/ (ICMP, TCP, Tailscale's own view) so the UI never has to guess what "online" means.
```

Line 39:

```text
No point pinging ourselves: presence of this process is the evidence.
```

Line 67:

```text
Two independent sources for the same column, both read-only and both
```

Line 68:

```text
opt-in: that machine's own controller (`remoteQuery`, needs fleetctl
```

Line 69:

```text
installed there) and services declared here and matched over SSH
```

Line 70:

```text
(`services`, needs nothing installed there). A host can use either or
```

Line 71:

```text
both — intel runs a Buzz relay and an opencode server and has no
```

Line 72:

```text
fleetctl, which is precisely the case the second one exists for.
```

Line 97:

```text
/ Multi-device, read-only, over SSH.
```

Line 99:

```text
/ The obvious design — have each controller listen on the tailnet — is
```

Line 100:

```text
/ deliberately rejected: "no network listener, ever" is what makes the local
```

Line 101:

```text
/ socket's peer-uid check sufficient, and it is the reason there is nothing to
```

Line 102:

```text
/ scan or reach from another host. So instead we *shell out* to the other
```

Line 103:

```text
/ machine's own fleetctl over the SSH trust you already have, read its JSON,
```

Line 104:

```text
/ and render it as read-only. FleetConsole never controls a remote process.
```

Line 112:

```text
never prompt for a password
```

Line 127:

```text
Cap what a remote machine can put into our snapshot.
```

Line 131:

```text
/ Declared services on another machine, matched over SSH.
```

Line 133:

```text
/ One round trip per device, not one per service: the remote dumps its
```

Line 134:

```text
/ process table and its listener table once, and the matching happens here
```

Line 135:

```text
/ in Swift against the same rule `Reconciler.externalServices` uses for the
```

Line 136:

```text
/ local machine — command-line substring first, declared port second. Two
```

Line 137:

```text
/ declared services on one host cost one `ssh`.
```

Line 139:

```text
/ Everything it produces is `claimed`. That is not a label: it is the flag
```

Line 140:

```text
/ every signal path in `Controller` consults, so a record describing a
```

Line 141:

```text
/ process on another machine cannot be stopped, restarted or reaped from
```

Line 142:

```text
/ here even by a future caller that forgets these are remote. The rule the
```

Line 143:

```text
/ app already had — the controller signals only what it started — turns out
```

Line 144:

```text
/ to be exactly the rule remote services need.
```

Line 150:

```text
`lsof` is run without -u: the declared service may belong to a
```

Line 151:

```text
different account on that machine than the one we log in as, and a
```

Line 152:

```text
listener we cannot attribute is still a listener we can report.
```

Line 153:

```text
Failures inside the remote command are swallowed there rather than
```

Line 154:

```text
failing the whole probe — a machine without lsof still gets its
```

Line 155:

```text
process table read.
```

Line 172:

```text
Split on the **last** marker, not the first.
```

Line 174:

```text
The probe sees itself: the remote `zsh -c …` running this very command
```

Line 175:

```text
is in the process table it dumps, and its argv contains the marker
```

Line 176:

```text
verbatim. Splitting on the first occurrence therefore cut the output
```

Line 177:

```text
inside the `ps` section — the real ports section ended up buried in
```

Line 178:

```text
the tail with a few hundred process lines in front of it, and every
```

Line 179:

```text
declared service came back with no ports at all. It looked like `lsof`
```

Line 180:

```text
had failed remotely; nothing had failed but the parse.
```

Line 182:

```text
Any marker has this problem, including a random nonce, because the
```

Line 183:

```text
marker is always part of the command that gets listed. The last
```

Line 184:

```text
occurrence is the `echo`, always — so that is the seam.
```

Line 212:

```text
/ Separates the process table from the listener table in one round trip.
```

Line 213:

```text
/ See `fetchDeclaredServices` for why it is matched from the end.
```

Line 223:

```text
/ `pid pgid <lstart, 5 fields> args…`. `lstart` is a fixed five-token date
```

Line 224:

```text
/ in the C locale, which is what makes this splittable without a regex.
```

Line 228:

```text
Skip the probe's own shell. Its argv contains the marker and the
```

Line 229:

```text
whole remote command, so it can otherwise satisfy a declared
```

Line 230:

```text
`match` by quoting it — a service would appear "running" on the
```

Line 231:

```text
evidence of us having asked whether it was running.
```

Line 255:

```text
/ A declared remote service as a `ServiceRecord`, so it renders through the
```

Line 256:

```text
/ same inspector, the same evidence chips and the same row primitives as
```

Line 257:

```text
/ everything else. A service that is declared and *not* running still
```

Line 258:

```text
/ produces a record — absent from the list would be indistinguishable from
```

Line 259:

```text
/ "not declared", and the whole point of declaring it is to notice when it
```

Line 260:

```text
/ stops.
```

Line 284:

```text
Read-only across the mesh, enforced by the same flag a local claim uses.
```

Line 290:

```text
/ Uses /sbin/ping rather than a raw ICMP socket: no entitlement, no privilege.
```

Line 295:

```text
round-trip min/avg/max/stddev = 1.234/1.234/1.234/0.000 ms
```

Line 323:

```text
Prefer wired, then Wi-Fi, then anything that is not the tailnet interface.
```

## Sources/fleetd/HealthChecker.swift

Line 5:

```text
/ Application-level health checks. Deliberately separate from liveness: a pid that
```

Line 6:

```text
/ exists and a port that listens prove nothing about the app behind them.
```

Line 40:

```text
/ Delegates to the shared probe in FleetCore so the app's connection checks
```

Line 41:

```text
/ and the daemon's health checks cannot drift apart.
```

Line 76:

```text
Settle before cancelling: `cancel()` completes the task with a
```

Line 77:

```text
cancellation error, which would otherwise overwrite the timeout and
```

Line 78:

```text
report our own cancel as the server's fault.
```

Line 88:

```text
/ A verdict written from two threads that must only be decided once.
```

Line 90:

```text
/ The completion handler and the timeout branch are not mutually exclusive —
```

Line 91:

```text
/ cancelling a timed-out task fires the handler after the timeout has already
```

Line 92:

```text
/ decided. First writer wins, so the check reports why it actually stopped.
```

## Sources/fleetd/ProcessLauncher.swift

Line 5:

```text
/ Spawns managed processes. The only place in FleetConsole that creates a process,
```

Line 6:

```text
/ and it is reachable only through a validated `LaunchRequest` over the local socket.
```

Line 17:

```text
/ Validates a launch request. Every rejection here is recorded as an event so
```

Line 18:

```text
/ "the agent tried to do something odd" is visible after the fact (T5).
```

Line 59:

```text
Health checks are local-only by policy: the controller must not be usable
```

Line 60:

```text
as a generic outbound HTTP client.
```

Line 80:

```text
/ Spawns in its own process group so children (npm → node, poetry → uvicorn…)
```

Line 81:

```text
/ can be reaped as a unit. stdout/stderr go to 0600 files under ~/Library/Logs.
```

Line 112:

```text
New process group, id == child pid. This is what makes group-kill safe.
```

Line 115:

```text
The daemon sets SIGTERM/SIGINT/SIGHUP/SIGPIPE to SIG_IGN so it can handle
```

Line 116:

```text
them through dispatch sources. An *ignored* disposition survives exec, so
```

Line 117:

```text
without this reset every managed process would inherit immunity to SIGTERM
```

Line 118:

```text
and could only ever be SIGKILLed — no graceful shutdown, ever.
```

Line 150:

```text
guaranteed by POSIX_SPAWN_SETPGROUP with pgroup 0
```

Line 156:

```text
/ `ps -o lstart` for one pid. Captured at launch and re-checked before any
```

Line 157:

```text
/ signal, so a recycled PID can never be killed in place of ours (T2).
```

## Sources/fleetd/Reconciler.swift

Line 4:

```text
/ Detects processes that are running outside the registry. An agent with shell
```

Line 5:

```text
/ access can always bypass `fleetctl` — this is the layer that makes the bypass
```

Line 6:

```text
/ loud rather than preventing it (threat model T4).
```

Line 16:

```text
/ Matches declared local tools against what is actually running. A tool you
```

Line 17:

```text
/ declared is never "unmanaged" — you meant it to be there — so it gets a
```

Line 18:

```text
/ name, a port and an uptime instead of a warning.
```

Line 31:

```text
Match by command line first, then by any of its declared ports.
```

Line 48:

```text
Children of the tool count as part of it, not as strays.
```

Line 56:

```text
/ `ps -o lstart` format, e.g. "Sun Jul 27 15:33:49 2026".
```

Line 70:

```text
Ports that a still-registered service claims. If such a port is held by a
```

Line 71:

```text
process outside its group, the group did not die cleanly.
```

Line 77:

```text
Processes we launched in the past whose records are terminal: if one of
```

Line 78:

```text
those pids is still alive, we leaked it despite thinking we cleaned up.
```

Line 89:

```text
Identity must survive a controller restart, otherwise "first seen" resets
```

Line 90:

```text
and a process that has been leaking for a day looks brand new. Swift's
```

Line 91:

```text
String.hashValue is seeded per process, so it cannot be used here.
```

Line 96:

```text
1. Listeners with no registry record.
```

Line 101:

```text
a declared local tool
```

Line 103:

```text
Ephemeral-range listeners are short-lived helpers. Flagging them
```

Line 104:

```text
produces an event and an alert for something that is already gone by
```

Line 105:

```text
the time you look — the definition of noise.
```

Line 137:

```text
2. Dev-server-shaped processes that have not (yet) bound a port.
```

Line 141:

```text
a declared local tool
```

Line 144:

```text
A shell whose argv merely *mentions* a dev-server command is not a
```

Line 145:

```text
dev server. Without this, every `zsh -c "… http.server …"` is a
```

Line 146:

```text
false positive, and a noisy unmanaged list is an ignored one.
```

Line 151:

```text
A process whose parent is also flagged adds noise, not information.
```

Line 170:

```text
/ FNV-1a: deterministic across runs, unlike Swift's seeded hashValue.
```

Line 184:

```text
/ Allow-list, not deny-list: an unknown listener always surfaces.
```

## Sources/fleetd/SessionScanner.swift

Line 4:

```text
/ Detects the coding agents you are actually running, and collects host metrics.
```

Line 6:

```text
/ These two things previously lived in separate menu-bar apps: agent sessions in
```

Line 7:

```text
/ Agent Menubar, host CPU/RAM/SSD in the AI-Pocket SwiftBar plugin. Both are
```

Line 8:

```text
/ "pertinent info" that belongs in the two FleetConsole menus, so both are
```

Line 9:

```text
/ gathered here.
```

Line 15:

```text
/ Matched against the executable name, then the full command line.
```

Line 35:

```text
/ One pass over the process table; no extra subprocesses except a single
```

Line 36:

```text
/ `lsof` for the working directories of the sessions actually found.
```

Line 45:

```text
The desktop apps ship binaries with the same names as their CLIs
```

Line 46:

```text
("claude" inside Claude.app, Codex helpers inside ChatGPT.app). A GUI
```

Line 47:

```text
app is not a coding session, and counting its four helper processes
```

Line 48:

```text
as four sessions is worse than not detecting it at all.
```

Line 58:

```text
A tool's own helper processes share its name; keep the group leader
```

Line 59:

```text
so one session is one row.
```

Line 74:

```text
Working directory = the project being worked on. One lsof call for all.
```

Line 100:

```text
MARK: - Host metrics
```

Line 102:

```text
/ CPU, memory and whole-container SSD usage for this machine. Uses the APFS
```

Line 103:

```text
/ container rather than `df /`, which understates a Mac's real disk usage.
```

Line 124:

```text
The whole APFS container, not `df /` — a Mac's root volume understates
```

Line 125:

```text
real usage badly because of firmlinks and snapshots.
```

Line 126:

```text
diskutil indents with "|   ", so the pipes must be stripped before matching.
```

Line 145:

```text
e.g. "Size (Capacity Ceiling):   1000240963584 B (1.0 TB)"
```

Line 151:

```text
/ The same metrics from another machine, over the SSH trust you already have.
```

## Sources/fleetd/main.swift

Line 5:

```text
fleetd — the FleetConsole controller.
```

Line 7:

```text
Runs as an ordinary per-user launchd agent. No root, no setuid, no privileged
```

Line 8:

```text
helper, no network listener. launchd keeps it alive; the menu-bar app does not.
```

Line 31:

```text
Refuse to start a second controller: two supervisors reaping the same registry
```

Line 32:

```text
would race on stop decisions.
```

Line 52:

```text
First, before anything that can block. `shutdown()` waits on the
```

Line 53:

```text
controller's serial queue, and `launchctl bootout` sends SIGKILL a
```

Line 54:

```text
beat after its SIGTERM — so this handler usually does not survive to
```

Line 55:

```text
write the stop event. The marker is the record that the exit was
```

Line 56:

```text
asked for; without it the next generation reports a crash that did
```

Line 57:

```text
not happen. See `StopMarker`.
```

Line 70:

```text
blocking accept loop
```

## Tests/FleetConsoleAppTests/AgentAwarenessWorkspaceTests.swift

Line 67:

```text
Allow the production focus animation to finish.
```

## Tests/FleetConsoleAppTests/AgentsRegistrationViewTests.swift

Line 108:

```text
The roster is a one-line count on the tab; every entry is behind Show all.
```

Line 170:

```text
/ Public native event dispatch, scoped to this offscreen test window. Vision
```

Line 171:

```text
/ locates rendered controls because SwiftUI's AX tree is lazy without an AX client.
```

## Tests/FleetConsoleAppTests/AwarenessGraphTests.swift

Line 149:

```text
one verified root, twelve descendants, eight context rows
```

## Tests/FleetConsoleAppTests/CanonicalBillingRequestTests.swift

Line 10:

```text
/ A strict transport fixture: historical routes and invented routes return 404.
```

Line 11:

```text
/ It intercepts every request; no device grant, payment or browser is created.
```

## Tests/FleetConsoleAppTests/CardGridTests.swift

Line 49:

```text
The terminal panel at its shortest workable height: its emulator
```

Line 50:

```text
view must remain reachable, not clipped out of the viewport.
```

Line 63:

```text
The body must have something to show: a live surface always renders
```

Line 64:

```text
a view hierarchy rather than nothing.
```

Line 142:

```text
Largest 210-point content plus card insets.
```

## Tests/FleetConsoleAppTests/DesignCoreTests.swift

Line 54:

```text
Offscreen rendering still creates windows; .prohibited disallows them.
```

Line 126:

```text
Permit the offscreen test window without activating the application.
```

## Tests/FleetConsoleAppTests/InvestigationTransportTests.swift

Line 5:

```text
/ All requests terminate here, including unexpected paths. No sockets, keychain,
```

Line 6:

```text
/ browser, app model, live processes or real credentials are used by this suite.
```

Line 61:

```text
A runnable agent must not depend on this multi-device-only flag.
```

Line 93:

```text
This fixture deliberately has no live-network fallback.
```

Line 204:

```text
/ Explicit synthetic credentials avoid device login, polling and Keychain.
```

Line 205:

```text
/ All requests in this serial matrix terminate in the private URLProtocol.
```

## Tests/FleetConsoleAppTests/MenuBarMetersTests.swift

Line 33:

```text
SwiftUI builds its accessibility tree only for a client that asks;
```

Line 34:

```text
the other UI suites switch it on the same way.
```

Line 39:

```text
In a window, ordered in off-screen: the accessibility tree of a
```

Line 40:

```text
hosting view that has never been in one is not reliably populated.
```

## Tests/FleetConsoleAppTests/OurosCredentialIsolationTests.swift

Line 48:

```text
No credentials or URLProtocol are needed: a denied storage context
```

Line 49:

```text
must fail before constructing a network request or browser action.
```

## Tests/FleetConsoleAppTests/OverviewViewportTests.swift

Line 145:

```text
The shipping root requests refresh. Only the observational test harness
```

Line 146:

```text
may exercise its live controller/probe integration.
```

## Tests/FleetConsoleAppTests/ServiceLabelsViewTests.swift

Line 84:

```text
SwiftUI AccessibilityNode uses the informal NSObject AX contract, not
```

Line 85:

```text
NSAccessibilityProtocol conformance. The driver must traverse both.
```

## Tests/FleetConsoleAppTests/SyntheticClick.swift

Line 4:

```text
/ Sends a press and release to `window` at `location`, in window coordinates.
```

Line 6:

```text
/ On macOS 15 a SwiftUI button is an AppKit control, and a control tracks the
```

Line 7:

```text
/ press in a nested event loop that returns only once the release arrives. A
```

Line 8:

```text
/ release sent after the press returns never reaches that loop, and the test
```

Line 9:

```text
/ hangs until CI kills it. So the release is armed on a timer that fires inside
```

Line 10:

```text
/ the tracking loop; where nothing tracks the press, it is sent directly.
```

Line 27:

```text
/ The release, sent exactly once: posted to a tracking loop, or dispatched
```

Line 28:

```text
/ after a press nothing tracked.
```

## Tests/FleetConsoleAppTests/TerminalAgentSessionTests.swift

Line 105:

```text
Bound a failing regression too; never signal an unrelated/recycled PID.
```

Line 113:

```text
SwiftTerm 2 asks the child to terminate and keeps tracking it through
```

Line 114:

```text
its own waiter; a child that ignores the request stays live and owns
```

Line 115:

```text
nothing of the pty. Exercise the request, then stop it for real.
```

Line 203:

```text
Closing the owned window terminates its shell. Same-directory reopen must recover.
```

Line 301:

```text
Production invokes this on the newly measured header's layoutRevision.
```

Line 330:

```text
The acceptance harness selects only this case in its own process:
```

Line 331:

```text
posting a process-wide quit notification during other PTY tests
```

Line 332:

```text
would correctly stop their children too.
```

Line 391:

```text
A dead grandchild can briefly remain a zombie until launchd reaps it.
```

Line 470:

```text
Keyboard focus lands on the actual emulator, not a hidden shell.
```

Line 538:

```text
Other native suites share AppKit's main actor and can hold it for
```

Line 539:

```text
several seconds while capturing/OCRing views during a full test run.
```

## Tests/FleetConsoleAppTests/TerminalOutputTests.swift

Line 7:

```text
/ Exercises the shipping TerminalPanel -> shell PTY -> SwiftTerm view path.
```

Line 8:

```text
/ No desktop input, daemon mutation, clipboard mutation, or synthetic feed is involved.
```

Line 47:

```text
cat streams the bytes produced by the Rust production formatter.
```

Line 48:

```text
This verifies rendering, not model admission or inference success.
```

Line 70:

```text
SwiftTerm's existing selection trims line-ending padding.
```

Line 142:

```text
Keep the actual CLI's inference lock and controller discovery out of
```

Line 143:

```text
the operator's home. Only the owned loopback response is exercised.
```

Line 208:

```text
Closes and reaps only this test's owned shell.
```

Line 218:

```text
Standardize only this owned shell. Its login startup still ran through
```

Line 219:

```text
TerminalPanel.activate; no profile or user preference is changed.
```

Line 229:

```text
Cleared cells may copy as trailing padding depending on the SDK.
```

Line 230:

```text
Preserve hard line breaks and all spacing inside the actual output.
```

Line 234:

```text
The window server composites asynchronously; under a loaded run the
```

Line 235:

```text
first snapshot can predate the output paint, so re-sample briefly.
```

Line 264:

```text
A sleeping live shell creates a real chunk boundary in the PTY reader.
```

Line 288:

```text
The persistent multiplexer owns the scrollback. History scrolled out
```

Line 289:

```text
of the visible pane stays in the server, streaming does not disturb
```

Line 290:

```text
it, and the outer view keeps rendering the live tail.
```

Line 299:

```text
Narrow resize goes through the production coalesced-grid endpoint,
```

Line 300:

```text
which deliberately avoids a DECSTR reset of the running emulator.
```

Line 323:

```text
Isolate CLI presentation from the separate narrow-resize case;
```

Line 324:

```text
preserve its raw selection in the receipt for before/after review.
```

Line 333:

```text
The installed baseline copies this diagnostic with one physical
```

Line 334:

```text
wrap break at the original 56-column grid. Preserve that exact
```

Line 335:

```text
copy behavior while checking every original diagnostic character.
```

Line 384:

```text
The engine's pixel-snapped cells can leave the requested grid one
```

Line 385:

```text
column short on the first pass; the host's self-correcting second
```

Line 386:

```text
pass settles it on the next layout.
```

Line 421:

```text
/ The multiplexer, not the emulator, owns scrollback once the shell runs
```

Line 422:

```text
/ in a persistent tmux server; its capture is the durable record.
```

Line 451:

```text
Let the main-queue PTY delivery and display timer execute.
```

Line 455:

```text
LocalProcess delivers stdout on DispatchQueue.main. A nested run loop
```

Line 456:

```text
inside a synchronous main-actor test cannot drain that GCD delivery;
```

Line 457:

```text
suspending the test lets the real PTY bridge feed the terminal view.
```

Line 473:

```text
The engine paints through a frame driver into its own layers; a
```

Line 474:

```text
layer-tree render is the honest raster regardless of window
```

Line 475:

```text
occlusion, which view-cacheDisplay cannot see past.
```

Line 480:

```text
An independent snapshot makes blank/output pixel comparison meaningful.
```

## Tests/FleetConsoleAppTests/VisualHierarchyTests.swift

Line 42:

```text
Cached offscreen bitmaps omit the native vibrant selected-row layer.
```

Line 43:

```text
Render the awareness return destination while a diagnostic tool is selected.
```

## Tests/FleetCoreTests/AgentCostScannerTests.swift

Line 4:

```text
/ The scanner against a fixture home tree: real directories, real `.jsonl`
```

Line 5:

```text
/ files, real mtimes — but nowhere near the operator's own transcripts, and
```

Line 6:

```text
/ with `now` and the calendar injected so the day under test is fixed.
```

Line 8:

```text
/ The pricing itself is covered by `AgentCostTests`; what is being checked
```

Line 9:

```text
/ here is the part that only breaks on a real filesystem — which directories
```

Line 10:

```text
/ get walked, what a missing tool reports, and that an unreadable record comes
```

Line 11:

```text
/ back as unknown rather than as zero spend.
```

Line 14:

```text
/ 2026-08-22 11:00:00Z, inside the day the fixtures are stamped for.
```

Line 19:

```text
/ UTC, so the fixture timestamps and the scanner's idea of "today" agree
```

Line 20:

```text
/ wherever the suite runs.
```

Line 43:

```text
/ Writes `lines` as a `.jsonl` under `path`, stamped inside the day so the
```

Line 44:

```text
/ scanner's mtime prefilter lets it through.
```

Line 61:

```text
MARK: - Nothing installed
```

Line 63:

```text
/ An empty home is not a free day. Every tool comes back unknown, the
```

Line 64:

```text
/ total covers nothing, and none of it is a fault.
```

Line 84:

```text
MARK: - Claude
```

Line 86:

```text
/ 1M input @ $3 plus 1M output @ $15, across two projects, is $18.
```

Line 101:

```text
/ Turns from another day sit in the same file as today's. The day filter
```

Line 102:

```text
/ is per line, so the file counts and the spend does not.
```

Line 115:

```text
/ An installed tool that has not run today has genuinely spent nothing.
```

Line 116:

```text
/ That is a knowable zero, and it must not read as an unknown.
```

Line 125:

```text
/ A file last touched before midnight cannot hold today's turns, and is
```

Line 126:

```text
/ skipped without being opened.
```

Line 142:

```text
/ Only `.jsonl` is a transcript. A sibling file must not be counted as one.
```

Line 150:

```text
MARK: - Codex
```

Line 152:

```text
/ A session opened before midnight keeps writing into the directory it
```

Line 153:

```text
/ started in, so today's turns land in yesterday's folder. Missing that is
```

Line 154:

```text
/ how a morning's spend disappears.
```

Line 167:

```text
/ Two days back is not scanned — that is the boundary the directory walk
```

Line 168:

```text
/ draws, and a turn there would already have been billed to its own day.
```

Line 181:

```text
MARK: - opencode
```

Line 183:

```text
/ A file that is not a database is the shape of a real failure — a partial
```

Line 184:

```text
/ write, a different format after an upgrade. It has to come back as a
```

Line 185:

```text
/ fault, not as a day on which opencode was free.
```

Line 198:

```text
MARK: - The rollup
```

Line 200:

```text
/ The headline figure: what is knowable is summed, what is not is counted,
```

Line 201:

```text
/ and the two are never mixed.
```

## Tests/FleetCoreTests/AgentCostTests.swift

Line 4:

```text
/ Spend is money on a screen, and two mistakes in here are worse than showing
```

Line 5:

```text
/ nothing at all: pricing a turn that was never billed, and reporting an agent
```

Line 6:

```text
/ we cannot price as having cost zero. Both are tested directly, from fixture
```

Line 7:

```text
/ lines in the on-disk shapes this machine actually has, with the day injected
```

Line 8:

```text
/ so nothing here depends on the timezone the suite happens to run in.
```

Line 10:

```text
/ These are the read-only fixture tests the merge recommendation asks for
```

Line 11:

```text
/ *before* the parser moves — every expected figure below was computed by hand
```

Line 12:

```text
/ from the published rates, not by running the code.
```

Line 15:

```text
/ 2026-08-22 00:00:00Z, one day long. Fixed epoch rather than a calendar
```

Line 16:

```text
/ computation, so the fixture and the assertion cannot drift together.
```

Line 42:

```text
MARK: - Claude
```

Line 44:

```text
/ 1000 input @ $3 + 500 output @ $15 + 2000 cache reads @ $0.30 +
```

Line 45:

```text
/ 100 cache writes @ $3.75, per million = $0.011475.
```

Line 51:

```text
/ The older transcript generation put usage and model at the top level.
```

Line 52:

```text
/ Both shapes are still on disk, so both have to price identically.
```

Line 75:

```text
/ An unrecognised model prices as Sonnet, not as free. A future model
```

Line 76:

```text
/ silently costing nothing is the failure that makes the whole figure
```

Line 77:

```text
/ untrustworthy without ever looking wrong.
```

Line 85:

```text
/ Synthetic turns are replayed locally and never billed. Pricing them
```

Line 86:

```text
/ invents spend that no invoice will ever show.
```

Line 105:

```text
MARK: - The day boundary
```

Line 114:

```text
/ The interval is half-open. `DateInterval.contains` includes its end, and
```

Line 115:

```text
/ a turn stamped exactly at midnight would then be billed to both days.
```

Line 123:

```text
/ Both RFC 3339 spellings appear in the same directory.
```

Line 131:

```text
/ An offset timestamp is an instant, not a wall clock: 01:00+02:00 is
```

Line 132:

```text
/ 23:00 the previous day in UTC and belongs to the previous day's bill.
```

Line 140:

```text
MARK: - Codex
```

Line 142:

```text
/ Codex's `input_tokens` includes `cached_input_tokens`, so the cached
```

Line 143:

```text
/ share is priced once at the cache rate and not twice:
```

Line 144:

```text
/ 2000 fresh @ $1.25 + 8000 cached @ $0.125 + 500 output @ $10 = $0.0085.
```

Line 150:

```text
/ A line claiming more cached input than input at all would otherwise
```

Line 151:

```text
/ price negatively and quietly reduce the day's total.
```

Line 165:

```text
MARK: - opencode
```

Line 167:

```text
/ opencode records the cost it was charged. We read it and price nothing.
```

Line 179:

```text
/ A row with no creation time still carries its cost; it just loses every
```

Line 180:

```text
/ `max` for last-activity, which is the same outcome as skipping it.
```

Line 187:

```text
MARK: - Honest unknowns
```

Line 193:

```text
/ The whole reason `amountUSD` is optional: an agent we cannot price is
```

Line 194:

```text
/ left out of the sum rather than added as zero, and the count is what
```

Line 195:

```text
/ keeps the remaining total from reading as the day's whole spend.
```

Line 209:

```text
/ A priced zero and an unknown are different claims. An agent that ran
```

Line 210:

```text
/ and cost nothing is knowable; one with no usage record is not.
```

Line 223:

```text
/ Only a record that should have been readable counts as a fault. A tool
```

Line 224:

```text
/ that publishes nothing is a permanent absence and must not raise an
```

Line 225:

```text
/ alarm every refresh forever.
```

Line 250:

```text
/ The snapshot rides the socket to the app, so it has to survive a round
```

Line 251:

```text
/ trip — including the `nil` that carries the unknown.
```

## Tests/FleetCoreTests/ConfigTests.swift

Line 4:

```text
/ `FleetConfig` is hand-edited, so its decoding contract is a real contract: a
```

Line 5:

```text
/ key from a later version must not make the file undecodable, and a key you
```

Line 6:

```text
/ delete must fall back rather than fail the load. The `ui` block added that
```

Line 7:

```text
/ contract three levels deep, which is three more places for a `decode` to have
```

Line 8:

```text
/ been written where a `decodeIfPresent` was meant.
```

Line 25:

```text
/ The whole point of the nested `decodeIfPresent` chain: naming one field
```

Line 26:

```text
/ must not reset its siblings to zero.
```

Line 44:

```text
/ A hand-edited `0` would mean "run `ps -Ao` over every process on the
```

Line 45:

```text
/ machine in a tight loop". The floors are the reason `clamped*` exists
```

Line 46:

```text
/ rather than the raw value being read at the call site.
```

Line 48:

```text
`routingRefreshSec` is in the payload deliberately: it was a real key
```

Line 49:

```text
until it turned out to control nothing, and a config.json written
```

Line 50:

```text
before it was removed has to keep loading rather than throwing on an
```

Line 51:

```text
unrecognised field.
```

Line 68:

```text
/ Round-tripping matters because the controller rewrites this file: a field
```

Line 69:

```text
/ that encodes but does not decode would be silently reset on every save.
```

Line 83:

```text
/ The declared-segment block. This is the only place in the config where a
```

Line 84:

```text
/ human asserts something the host cannot observe, so its decoding has to be as
```

Line 85:

```text
/ forgiving as the rest — and its `name` has to survive a missing key, because
```

Line 86:

```text
/ a segment with no name would render a blank tag.
```

## Tests/FleetCoreTests/ConsoleLayoutTests.swift

Line 5:

```text
/ The layout budget, asserted rather than commented.
```

Line 7:

```text
/ The bug these exist to prevent already happened once: `columnReserve` summed
```

Line 8:

```text
/ to 786pt against a 780pt minimum window, and the comment beside it cited a
```

Line 9:

```text
/ 1060pt minimum that no longer existed. Three numbers, two of them wrong, none
```

Line 10:

```text
/ of them checkable. Everything below is a property of the arithmetic, so it
```

Line 11:

```text
/ fails the build rather than the user.
```

Line 14:

```text
MARK: The ladder
```

Line 31:

```text
/ Adjacent rungs approach φ going up the ladder. This is the reason the
```

Line 32:

```text
/ scale is worth having: two sizes drawn from it are never a half-point
```

Line 33:

```text
/ apart, and never so far apart that the relationship is unreadable.
```

Line 55:

```text
MARK: The golden division
```

Line 67:

```text
/ The whole point of the arrangement: the two side columns are the same
```

Line 68:

```text
/ width at every window size, so the window is symmetrical about its centre.
```

Line 85:

```text
/ Between the clamps, the content column really is the major section.
```

Line 96:

```text
MARK: The budget holds at every size the window can take
```

Line 98:

```text
/ The regression. At the window's minimum, with a tool panel open and the
```

Line 99:

```text
/ inspector yielded, every floor is still met — and the module column lands
```

Line 100:

```text
/ exactly on its own, which is what makes this the *minimum* rather than an
```

Line 101:

```text
/ arbitrary number above it.
```

Line 110:

```text
/ The same, one step up: at the inspector-and-panel floor both side columns
```

Line 111:

```text
/ fit alongside a panel, and the module column is again exactly on its floor.
```

Line 120:

```text
/ The composed window shows everything at once with room to spare — the
```

Line 121:

```text
/ property `defaultContentSize` was chosen for, now checked rather than
```

Line 122:

```text
/ asserted in a comment.
```

Line 131:

```text
/ Without a panel the three columns fit at every width the window allows,
```

Line 132:

```text
/ which is the arrangement the app is actually about.
```

Line 141:

```text
/ The ordering the cascade depends on. If these ever cross, the rule
```

Line 142:

```text
/ "the inspector yields to a panel" has no width range to happen in.
```

Line 150:

```text
/ The minimum must be a real minimum: one point narrower and the module
```

Line 151:

```text
/ column is under its floor.
```

Line 159:

```text
/ Every declared rung-pinned constant is actually on the ladder. Cheap, and
```

Line 160:

```text
/ it is the check that catches a future edit typing 240 into `sideColumnMin`.
```

Line 170:

```text
MARK: Height, now that it is a free dimension
```

Line 172:

```text
/ Height was `width / aspectRatio` for as long as the window was locked,
```

Line 173:

```text
/ which was a statement about the lock rather than about the content. It
```

Line 174:

```text
/ is derived from what has to fit now, and this is that claim: the
```

Line 175:

```text
/ toolbar's reserve, a module header, and one card down to the bottom of
```

Line 176:

```text
/ its trace.
```

Line 186:

```text
/ The regression, stated as what the *module column* gets.
```

Line 188:

```text
/ The first version of this floor left the toolbar out — the window is
```

Line 189:

```text
/ `.fullSizeContentView`, so the toolbar sits inside the content height —
```

Line 190:

```text
/ and came to 191. Rendering at exactly 191 sliced the card through the
```

Line 191:

```text
/ middle of its chart, because the module column was handed 191 − 55 = 136
```

Line 192:

```text
/ against the 199 a header and a card need. That subtraction is the thing
```

Line 193:

```text
/ that was wrong, so it is the thing asserted: whatever the floor is, what
```

Line 194:

```text
/ survives the toolbar still holds a header and a card.
```

Line 204:

```text
/ And is tight: no slack beyond the parts it is defined from.
```

Line 214:

```text
/ A card, down to the bottom of its trace: padding, title row, the gap
```

Line 215:

```text
/ under it, the chart, padding again.
```

Line 226:

```text
/ The rail is its toggle plus the space either side, rather than a 34
```

Line 227:

```text
/ that happens to agree with them.
```

Line 233:

```text
/ The composed window is comfortably above both floors, on both axes.
```

## Tests/FleetCoreTests/DashboardContentTests.swift

Line 16:

```text
/ The window has no footer strip any more; the floor pays for the
```

Line 17:

```text
/ titlebar, the module's control row and one card, and nothing else.
```

## Tests/FleetCoreTests/DashboardWindowGeometryTests.swift

Line 4:

```text
/ What is left to assert about the console's opening size now that it is only
```

Line 5:

```text
/ an opening size.
```

Line 7:

```text
/ These used to check `contentAspectRatio` against the composed size and that
```

Line 8:

```text
/ it was landscape. Both were properties of the aspect lock, and the lock is
```

Line 9:

```text
/ gone: `contentAspectRatio` existed solely to be handed to
```

Line 10:

```text
/ `NSWindow.contentAspectRatio`, so it went with it rather than staying as a
```

Line 11:

```text
/ constant nothing reads, proved by a test that a division still works.
```

Line 19:

```text
/ The floors are `ConsoleLayout`'s. This is the half that matters once the
```

Line 20:

```text
/ window can be dragged: it opens at neither floor, so there is room to
```

Line 21:

```text
/ shrink in both directions rather than one.
```

## Tests/FleetCoreTests/LicenseTests.swift

Line 4:

```text
/ The trial clock and the key format are the two halves of the licence that
```

Line 5:

```text
/ can be wrong without a UI: a clock that never expires makes the trial
```

Line 6:

```text
/ permanent, and a validator that accepts garbage makes the paid tier a
```

Line 7:

```text
/ label. Both are tested at the edge where they touch the outside world —
```

Line 8:

```text
/ UserDefaults for the clock, the key string for the validator — with the
```

Line 9:

```text
/ suite and the clock injected so nothing in here is timing-sensitive.
```

Line 33:

```text
MARK: - Trial clock
```

Line 35:

```text
/ First launch stamps the clock; a fresh install is a 14-day trial.
```

Line 45:

```text
/ The stamp is written on first *read*, and a second manager over the
```

Line 46:

```text
/ same suite sees the same start — two installs of the clock would be a
```

Line 47:

```text
/ trial that resets every launch.
```

Line 59:

```text
/ Day 13 is a trial with one day left; day 14 is over. The boundary is
```

Line 60:

```text
/ the licence's only sharp edge, so it is pinned exactly.
```

Line 78:

```text
/ A clock moved backwards must not *extend* the trial.
```

Line 83:

```text
Same stamp, `now` rewound to the start: the trial is computed from
```

Line 84:

```text
the stamp, so time travel re-runs the days it had, and never grants
```

Line 85:

```text
more than the period.
```

Line 101:

```text
Before the start is day zero, not negative days.
```

Line 105:

```text
MARK: - Premium gating
```

Line 125:

```text
/ The feature list is the product's paywall, stated once. A feature
```

Line 126:

```text
/ added to the enum without being gated here would silently be free.
```

Line 132:

```text
MARK: - Key validation
```

Line 134:

```text
/ A key signed the way the issuer signs validates; the round-trip is the
```

Line 135:

```text
/ whole point of keeping the signing side public.
```

Line 147:

```text
/ Different secrets sign differently — the validator and the issuer
```

Line 148:

```text
/ agreeing is the only property that makes the key a key.
```

Line 159:

```text
Valid HMAC, garbage payload: a key whose date we cannot read is not
```

Line 160:

```text
a key we license on.
```

Line 164:

```text
/ Forgiving input: keys arrive by paste, and paste carries whitespace.
```

Line 165:

```text
/ Rejecting that would be punishing the pasteboard, not the forger.
```

Line 171:

```text
/ Base32 survives its own round-trip at lengths the encoder pads.
```

Line 180:

```text
MARK: - Install
```

Line 182:

```text
/ Installing a key flips status to licensed and persists it; a bad key
```

Line 183:

```text
/ refuses and changes nothing.
```

Line 192:

```text
A second manager over the same suite sees the licence — the store
```

Line 193:

```text
is UserDefaults, not the object.
```

## Tests/FleetCoreTests/OverviewViewportGeometryTests.swift

Line 8:

```text
652 is the module column the shipping window hands Overview at its
```

Line 9:

```text
690pt rendering height, toolbar already excluded.
```

## Tests/FleetCoreTests/ProcessTableTests.swift

Line 4:

```text
/ `ProcessTable.readProcesses` parses `ps` output positionally, which is fine
```

Line 5:

```text
/ while every field before the command is whitespace-free — and `state` was
```

Line 6:

```text
/ inserted into the middle of that run. Every index after it moved by one, and
```

Line 7:

```text
/ an off-by-one there does not fail loudly: it shifts the start signature into
```

Line 8:

```text
/ the command line and quietly breaks the PID-reuse guard.
```

Line 11:

```text
/ The real thing, on the machine running the test. `ps -A` always lists at
```

Line 12:

```text
/ least itself, so an empty parse is a failure rather than an idle machine.
```

Line 18:

```text
launchd is pid 1 on every Mac, and it is the cheapest anchor for
```

Line 19:

```text
"the columns landed where they were supposed to".
```

Line 29:

```text
/ The signature is five tokens of `lstart` — "Fri Aug  1 09:12:03 2026" —
```

Line 30:

```text
/ and it is the whole PID-reuse guard. If the state column shifted it, this
```

Line 31:

```text
/ would be a date fragment plus a stray letter.
```

Line 41:

```text
/ Every state `ps` can print maps to something, and the three ordinary ones
```

Line 42:

```text
/ stay achromatic — a process list where "running" is green is a wall of
```

Line 43:

```text
/ green that says nothing.
```

Line 46:

```text
Session leaders and foreground processes carry modifiers; the parse
```

Line 47:

```text
must key on the first letter only.
```

## Tests/FleetCoreTests/RPCRequestPolicyTests.swift

Line 47:

```text
An empty socket path never targets the installed daemon. The policy
```

Line 48:

```text
must reject the request before attempting any connection.
```

## Tests/FleetCoreTests/RunbookTests.swift

Line 4:

```text
/ The runbook format is a safety boundary, and a boundary nobody tests is a
```

Line 5:

```text
/ boundary that has already moved. Two things are checked here: that the three
```

Line 6:

```text
/ documents actually shipping are clean, and that every rule in the linter
```

Line 7:

```text
/ rejects the shape it was written for.
```

Line 9:

```text
/ The second half matters more. Each rule exists because a plausible author
```

Line 10:

```text
/ would write that shape by accident, so each rule gets a test that writes it
```

Line 11:

```text
/ on purpose.
```

Line 14:

```text
MARK: - Fixtures
```

Line 16:

```text
/ A minimal document with no defects. Every linter test below starts here
```

Line 17:

```text
/ and breaks exactly one thing, so a failure names its own cause.
```

Line 53:

```text
MARK: - The shipped library
```

Line 55:

```text
/ The three documents that actually ship must be clean — not merely
```

Line 56:

```text
/ loadable. A warning in a shipped runbook is a warning nobody will ever
```

Line 57:

```text
/ action, and it teaches the next author that warnings are decoration.
```

Line 74:

```text
/ Diagnosis and mutation partition the steps: every step is in exactly one,
```

Line 75:

```text
/ because the read-only pass runs the first set and the approval sheet
```

Line 76:

```text
/ lists the second.
```

Line 86:

```text
/ Every mutation in a shipped runbook needs a human. This is the same rule
```

Line 87:

```text
/ the linter enforces, asserted directly against what ships so that a
```

Line 88:

```text
/ regression in the linter cannot hide a regression in the library.
```

Line 105:

```text
/ The reclaim ceiling has exactly one rung. A second one would eventually
```

Line 106:

```text
/ be raised — by a well-meaning author, in a document nobody re-read — and
```

Line 107:

```text
/ the thing on the other side of it is the operator's own data.
```

Line 112:

```text
MARK: - The rule the format exists for
```

Line 129:

```text
/ Not dangerous, corrosive: approvals for steps that change nothing teach
```

Line 130:

```text
/ the operator to click through the ones that do.
```

Line 140:

```text
MARK: - Rationale
```

Line 151:

```text
/ A read-only step with no rationale is sloppy, not unsafe.
```

Line 161:

```text
MARK: - Target caps
```

Line 177:

```text
/ A cap of zero matches nothing, which means the step silently does not
```

Line 178:

```text
/ happen and the runbook reports success.
```

Line 193:

```text
MARK: - Parameters
```

Line 207:

```text
/ A query inside a sweep resolves its parameter too — the reference is
```

Line 208:

```text
/ nested two levels down and is exactly the one an author would forget.
```

Line 216:

```text
/ Asking the operator for something nothing consumes is worse than not
```

Line 217:

```text
/ asking: it implies the answer mattered.
```

Line 225:

```text
MARK: - Stops
```

Line 227:

```text
/ The one stop that is not a matter of taste.
```

Line 237:

```text
/ The rule is about services specifically. A runbook that only deletes
```

Line 238:

```text
/ caches has no target to be unmanaged, and must not be asked to declare a
```

Line 239:

```text
/ stop that cannot occur — a rule that fires where it does not apply is a
```

Line 240:

```text
/ rule authors learn to work around.
```

Line 250:

```text
/ Observing a service is not acting on one.
```

Line 256:

```text
MARK: - The document
```

Line 288:

```text
One critical (unattended mutation) and one warning (unused parameter).
```

Line 297:

```text
/ Warnings never block; criticals always do.
```

## Tests/FleetCoreTests/SMCTests.swift

Line 4:

```text
/ SMC value decoding is the part of the sensor pipeline that can be wrong
```

Line 5:

```text
/ without the hardware noticing — the kernel just gives you bytes. These
```

Line 6:

```text
/ tests pin the three encodings FleetConsole understands and the byte order
```

Line 7:

```text
/ each one implies, because an sp78 read little-endian is a die at −1 °C
```

Line 8:

```text
/ reported as 255 °C, which is a number you only question once.
```

Line 15:

```text
MARK: Key packing
```

Line 17:

```text
/ A key's bytes, read back big-endian, are the fourCC it was made from —
```

Line 18:

```text
/ this is the whole contract with the kernel, and it failing means every
```

Line 19:

```text
/ read below is reading the wrong key.
```

Line 26:

```text
MARK: sp78  (signed fixed-point 7.8, big-endian)
```

Line 29:

```text
50.0625 °C = 0x3210 in sp78: 50<<8 | 0x10, and 0x10/256 = 0.0625.
```

Line 34:

```text
0xFF00 is -1.0 °C, not 255 — a sensor below freezing is a real
```

Line 35:

```text
reading, and treating the value as unsigned would report 255 °C.
```

Line 39:

```text
/ The byte-order canary: the two orders are both decodable, and only one
```

Line 40:

```text
/ is a plausible die temperature. 0x3210 read little-endian is 16.2 °C.
```

Line 51:

```text
MARK: fpe2  (unsigned fixed-point 14.2, big-endian)
```

Line 54:

```text
1639.5 rpm * 4 = 6558 = 0x199E, big-endian.
```

Line 59:

```text
A stopped fan is 0 rpm — real data, distinct from an absent key.
```

Line 63:

```text
MARK: flt   (IEEE-754, big-endian on the wire)
```

Line 73:

```text
A NaN in a temperature register is a failed sensor; rendering it
```

Line 74:

```text
would put "nan" in the UI.
```

Line 78:

```text
MARK: Dispatch
```

Line 87:

```text
/ `SensorSample` is what the UI actually renders, so its summaries are the
```

Line 88:

```text
/ contract worth testing: an empty probe is unavailable, and the fastest fan
```

Line 89:

```text
/ is the one the one-line summary names.
```

Line 108:

```text
A present key that refused a value is not a stopped fan. Rendering
```

Line 109:

```text
0 rpm for a fan the SMC would not quote is a false claim of failure.
```

Line 115:

```text
/ The probed-key lists are part of the format contract: adding a key means
```

Line 116:

```text
/ the sampler believes more hardware exists, and removing one is a silent
```

Line 117:

```text
/ regression for a machine that has it.
```

## Tests/FleetCoreTests/ServiceUptimeTests.swift

Line 4:

```text
/ `uptime` used to be `Date().timeIntervalSince(startedAt)` with no regard for
```

Line 5:

```text
/ whether the process was still alive, so a crashed record kept accruing uptime
```

Line 6:

```text
/ forever. That is the one thing this app is not allowed to do — state a fact
```

Line 7:

```text
/ about a process it has no evidence for — so the boundary gets a test rather
```

Line 8:

```text
/ than a comment.
```

Line 26:

```text
Started two hours ago, went terminal one hour ago: it ran for an hour,
```

Line 27:

```text
and it does not matter how long ago that was.
```

Line 42:

```text
/ An expired lease is not a stopped process — the reaper leaves a claimed
```

Line 43:

```text
/ record alone and reports it — and a paused one is resident and holding its
```

Line 44:

```text
/ ports. Neither has stopped running, so neither freezes.
```

Line 53:

```text
/ A clock adjustment can put `updatedAt` before `startedAt`. A negative
```

Line 54:

```text
/ duration renders as "-1h 4m", which reads as a bug in the app rather than a
```

Line 55:

```text
/ bug in the clock.
```

Line 61:

```text
/ The predicate the freeze depends on. If `.expired` were ever folded into
```

Line 62:

```text
/ `isTerminal`, an expired-but-running service would silently stop counting.
```

## Tests/FleetCoreTests/TailscaleDateTests.swift

Line 4:

```text
/ `TailscaleClient.parseDate` moved off `ISO8601DateFormatter` and onto
```

Line 5:

```text
/ `Date.ISO8601FormatStyle` to get out from under shared mutable state. That is a
```

Line 6:

```text
/ parser swap on a wire format we do not control, so the contract it has to keep
```

Line 7:

```text
/ is written down here rather than assumed: both RFC 3339 shapes tailscale emits
```

Line 8:

```text
/ still parse to the same instant, and Go's zero time still reads as "never".
```

Line 11:

```text
2025-08-02T14:45:30Z
```

Line 26:

```text
/ The fractional style is tried first and the plain one second. If that order
```

Line 27:

```text
/ ever inverts, the fractional case above starts losing its milliseconds
```

Line 28:

```text
/ silently — so assert the two disagree, which is what makes the order matter.
```

Line 35:

```text
/ `0001-01-01T00:00:00Z` is Go's zero `time.Time`. It is what tailscale sends
```

Line 36:

```text
/ for a node it has never seen, and it is syntactically a perfectly good date,
```

Line 37:

```text
/ which is exactly why it has to be refused by name rather than by parsing.
```

## Tests/FleetCoreTests/TroubleshootingTests.swift

Line 4:

```text
/ Suggestions are the product surface that tells a person what is going on
```

Line 5:

```text
/ without doing it for them. The failure modes that matter are inventing a
```

Line 6:

```text
/ problem from missing evidence, ranking on lifetime/global figures instead
```

Line 7:

```text
/ of the event slice, collapsing two categories that should both show, and
```

Line 8:

```text
/ offering a signal on something the controller does not own.
```

Line 11:

```text
/ Fixed instant so recency, staleness and lease remaining do not depend
```

Line 12:

```text
/ on when the suite runs.
```

Line 15:

```text
MARK: - Fixtures
```

Line 68:

```text
MARK: - Ranking
```

Line 154:

```text
MARK: - Unavailable / stale evidence
```

Line 218:

```text
MARK: - No invention
```

Line 315:

```text
MARK: - Bounded inputs
```

Line 377:

```text
MARK: - Dedup
```

## design/tokens.css

Line 1:

```text
Fleet Console design tokens. Generated from tokens.json by fleet-ui-core; edit tokens.json, not this file.
```

Line 19:

```text
Glass appearance: a near-black substrate with a vibrant level ramp,
used by the GPUI window in dark mode over the blurred material.
```

Line 35:

```text
Paper appearance, used by surfaces that offer a light mode.
```

## design/website-section.html

Line 103:

```text
terrain columns, gauge-like: bright cap, dithered body fading down
```

Line 111:

```text
the F/C mark rising out of the field: cells light up in sequence
```

Line 119:

```text
drifting motes, like pollen
```

## docs/design-canvas/Main.dc.html

Line 11:

```text
── ambient background grid & spectral field ─────────────────
```

Line 15:

```text
── 1. top bar: plane tabs + host status ─────────────────────
```

Line 18:

```text
Brand mark & title
```

Line 29:

```text
The 4 Core Operational Planes
```

Line 45:

```text
Host status badge & thermal sensor
```

Line 57:

```text
── 2. workspace main body (sidebar + center canvas + right terminal) ──
```

Line 60:

```text
══ Left Rail: Descriptive Topology Mini-Map ══
```

Line 68:

```text
Tree Hierarchy
```

Line 85:

```text
Agents Header
```

Line 104:

```text
Processes Header
```

Line 109:

```text
swift-frontend (Critical Saturation)
```

Line 123:

```text
Substrate Header
```

Line 142:

```text
Mini-Map Legend / Breadcrumb
```

Line 150:

```text
══ Center Stage: Relational Topology Canvas + Diagnostics Drawer ══
```

Line 153:

```text
Spatial Graph Canvas
```

Line 156:

```text
SVG Connections & Pulse Rays
```

Line 184:

```text
Node: Host Cluster
```

Line 190:

```text
Node: Runtime Core
```

Line 196:

```text
Node: Ouros Core Brain (Active & Focused)
```

Line 203:

```text
Relational Badge: IPC Conduit
```

Line 208:

```text
Node: Codex Worker
```

Line 215:

```text
Node: swift-frontend with Saturation Badge
```

Line 222:

```text
Contextual Badge attached to swift-frontend
```

Line 234:

```text
Node: WindowServer
```

Line 240:

```text
Node: Storage Mount /
```

Line 246:

```text
Node: Storage Mount Data
```

Line 252:

```text
Canvas HUD
```

Line 261:

```text
══ Bottom: Integrated Diagnostics Drawer ("Needs Attention" Overhaul) ══
```

Line 271:

```text
Badges Row
```

Line 274:

```text
Alert 1
```

Line 285:

```text
Alert 2
```

Line 301:

```text
══ Right Rail: Persistent Contextual Terminal & Inspector ══
```

Line 304:

```text
Terminal Header
```

Line 313:

```text
Entity Inspector Metadata Card
```

Line 333:

```text
Stream Log Lines
```

Line 344:

```text
Interactive REPL Prompt
```

## docs/design-canvas/Popover.dc.html

Line 34:

```text
── the menu bar, with FleetConsole's extra ───────────────
```

Line 39:

```text
the extra: mark + live count, highlighted because the popover is open
```

Line 51:

```text
the notch of the popover, pointing at the extra
```

Line 57:

```text
── the popover: 380pt, the app's only fixed width ───────
```

Line 60:

```text
header
```

Line 68:

```text
action slot: two hit targets wide, reserved whether or not both show
```

Line 99:

```text
entity tile: a ruled plate with a status badge struck into its corner
```

Line 115:

```text
utilisation meter: 54 × 5, the one width every row agrees on
```

Line 138:

```text
the plate's caption, written on the page beside it
```

## docs/design-canvas/Tokens.dc.html

Line 49:

```text
── row: ink ramps ─────────────────────────────────────
```

Line 81:

```text
── row: plate anatomy + marks ─────────────────────────
```

Line 131:

```text
── row: type ramp + instruments ───────────────────────
```

## docs/design-canvas/Welcome.dc.html

Line 39:

```text
the panel: 560 × 420, the size the app already opens at
```

Line 42:

```text
header
```

Line 54:

```text
stage
```

Line 59:

```text
the sweep: the instrument itself, drawn on its construction circles
```

Line 80:

```text
footer
```

## rust-toolchain.toml

Line 1:

```text
The Rust toolchain for rust/, pinned so a fresh checkout on macOS and Linux
```

Line 2:

```text
builds with the compiler these crates were verified with. The workspace's
```

Line 3:

```text
rust-version (1.89) is the floor declared by its locked dependencies; this
```

Line 4:

```text
file is the version actually exercised. See docs/CROSS-PLATFORM.md.
```

## rust/fleet-agent/src/engine.rs

Line 1:

```text
The agent loop, forked from rx's engine pattern: system instructions built
```

Line 2:

```text
once per session, a model client that emits tool calls, dispatch through
```

Line 3:

```text
the typed tool surface, and per-turn usage accounting that feeds the meter.
```

Line 5:

```text
The model client speaks the OpenAI-compatible chat API that llama-server
```

Line 6:

```text
exposes at 127.0.0.1 (the `RX_LOCAL_LLM_URL` convention), so the resident
```

Line 7:

```text
agent runs on the same local inference the machine already serves — no
```

Line 8:

```text
cloud call, no key, matching the console's locality doctrine.
```

Line 19:

```text
System prompt for the resident console agent. Byte-stable for a given
```

Line 20:

```text
toolset: no timestamps, no host state, so the provider's prompt cache (and
```

Line 21:

```text
our own determinism guarantees) survive across turns.
```

Line 67:

```text
One model round trip. Kept as a trait so tests can drive the loop without
```

Line 68:

```text
a live llama-server, while the real run goes over HTTP.
```

Line 70:

```text
Returns the *full* response object, not just the choice: usage accounting
```

Line 71:

```text
lives at the top level in the OpenAI shape, and dropping it would meter a
```

Line 72:

```text
real turn as a free one.
```

Line 81:

```text
OpenAI-compatible client against the local llama-server.
```

Line 125:

```text
The llama-server tool schema form (OpenAI function-calling shape), derived
```

Line 126:

```text
from the same definitions the MCP surface serves so the two clients can
```

Line 127:

```text
never disagree about what exists. The wire shapes differ — MCP lists
```

Line 128:

```text
`inputSchema` at the top level, the chat API nests under `function` —
```

Line 129:

```text
but the names, descriptions and parameter schemas are the single source
```

Line 130:

```text
in `TOOLS`.
```

Line 156:

```text
A scripted client for tests; never used by the executable inference path.
```

Line 173:

```text
Pop the next scripted reply; an exhausted script is an error so a
```

Line 174:

```text
test can never silently loop on the final reply.
```

Line 188:

```text
Result of one agent turn.
```

Line 202:

```text
Run one operator turn: model -> (tool call -> result)* -> final answer.
```

Line 203:

```text
Every iteration is bounded; usage is accumulated across the whole turn.
```

Line 221:

```text
The real loop takes an absolute deadline so transports and tool RPCs share
```

Line 222:

```text
one budget; tests can exercise deadline edges without waiting 45 seconds.
```

Line 353:

```text
Convenience for the CLI's one-shot path: fresh history, one turn.
```

Line 372:

```text
Bound the complete textual prompt separately from JSON overhead. A byte
```

Line 373:

```text
bound is predictable without a tokenizer and stays below a modest context.
```

Line 396:

```text
A scripted reply carrying a tool call, in the OpenAI shape.
```

Line 433:

```text
A turn that calls fleet_ps (unknown tool's read-only cousin — the
```

Line 434:

```text
dispatch fails closed with the socket error, which the model then
```

Line 435:

```text
answers from) and finishes.
```

Line 454:

```text
Both round trips metered: 100+120 input, 10+30 output.
```

## rust/fleet-agent/src/guard.rs

Line 1:

```text
Admission to inference is explicit, serialized and fail-closed. This module
```

Line 2:

```text
never starts, loads, restarts or reconfigures a model server.
```

Line 25:

```text
OS advisory locks are released on exit/crash; the persistent lock file is
```

Line 26:

```text
never removed, avoiding two live processes locking different inodes.
```

Line 46:

```text
LOCK_EX | LOCK_NB has the same values on Darwin and Linux.
```

Line 145:

```text
The revision-1 prefix is stable in Apple's SDK vm_statistics.h. Asking
```

Line 146:

```text
for this prefix works on the minimum supported macOS without relying on
```

Line 147:

```text
newer tagged-memory fields appended by current SDKs.
```

## rust/fleet-agent/src/http.rs

Line 1:

```text
Bounded HTTP to an existing loopback endpoint. No redirects, proxy, DNS,
```

Line 2:

```text
model startup, retry or unbounded allocation; every IO shares one deadline.
```

Line 142:

```text
Serializes through a cap rather than allocating arbitrarily large JSON first.
```

## rust/fleet-agent/src/knowledge.rs

Line 1:

```text
Specialized memory and process knowledge for the resident agent.
```

Line 3:

```text
This is the component that separates an agent from a script: concrete
```

Line 4:

```text
interpretations of the numbers fleetd reports, in the same voice as the
```

Line 5:

```text
project's own documentation (`docs/RUNBOOKS.md`, `THREAT-MODEL.md`), so the
```

Line 6:

```text
advice an operator gets from the agent matches the advice they would get
```

Line 7:

```text
from the project. Every function is pure and fixture-testable.
```

Line 9:

```text
Interpret a service's resident-memory trend from its history window.
```

Line 11:

```text
`memHistory` is newest-last (the `ServiceRecord` cap is 40 samples). A
```

Line 12:

```text
monotonic climb with a real slope is a leak candidate; oscillation is
```

Line 13:

```text
normal allocator behavior; flat is steady state. We deliberately do not
```

Line 14:

```text
call anything a leak without a sustained slope — one big sample is often a
```

Line 15:

```text
legitimate one-off (build, index, migration).
```

Line 19:

```text
MB per sample over the window, when a slope exists.
```

Line 21:

```text
How many samples the verdict rests on.
```

Line 28:

```text
Sustained growth across the window — a leak candidate worth watching.
```

Line 30:

```text
Oscillating within a band — normal allocator/cache behavior.
```

Line 32:

```text
Flat within noise.
```

Line 34:

```text
Rising but under the leak slope threshold — worth a note, not an alarm.
```

Line 36:

```text
Not enough samples to say anything honest.
```

Line 40:

```text
The sustained growth rate (MB/sample) above which we call a climb a leak
```

Line 41:

```text
candidate. Tuned against fleetd's 5s tick: 1 MB per 5s is ~17 GB/day, which
```

Line 42:

```text
no healthy service does, but a slow 0.1 MB/sample creep can run for days
```

Line 43:

```text
before it hurts — so creeping gets a note instead of an alarm.
```

Line 61:

```text
Least-squares slope over the window.
```

Line 130:

```text
Field triage for one process's memory: what the number means and what the
```

Line 131:

```text
honest next step is. This is advice, not a command — mutating tools stay
```

Line 132:

```text
behind explicit confirm fields at the tool layer.
```

Line 148:

```text
RSS thresholds in MB. 1024 is "this process dominates the machine's budget
```

Line 149:

```text
conversation"; 200 is an ordinary daemon.
```

Line 192:

```text
System-wide pressure verdict from the compressor/swap counters the
```

Line 193:

```text
console already surfaces (`SystemTelemetry`): macOS has no
```

Line 194:

```text
`/proc/meminfo`, so pressure is read from what the kernel reports through
```

Line 195:

```text
`vm_stat`-adjacent counters — compression activity and swap-ins.
```

Line 210:

```text
16 GB machine: ~4 GB compressed means the kernel is actively squeezing;
```

Line 211:

```text
swap used at all, at more than a token amount, means real pressure.
```

Line 249:

```text
Priority ordering for "what do I look at first" — the routing knowledge.
```

Line 250:

```text
A climbing leak candidate outranks a big-but-steady process; unanswered
```

Line 251:

```text
operator mail outranks everything (the project's own rule: an agent with
```

Line 252:

```text
no services but an unanswered question still must appear).
```

## rust/fleet-agent/src/lib.rs

Line 1:

```text
fleet-agent: the FleetConsole resident operations agent.
```

Line 3:

```text
An rx-basis component specialized for console residency: typed tools over
```

Line 4:

```text
the fleetd socket (never raw shell), a memory/process specialist system
```

Line 5:

```text
prompt, a local-LLM engine loop, an MCP stdio server so hosts can drive
```

Line 6:

```text
the same surface, and metered usage signed to a local ledger that Ouros
```

Line 7:

```text
reads to bill.
```

Line 20:

```text
Mirrors `FleetPaths.support`.
```

Line 30:

```text
Where meter records land. `agent-billing/` under the support directory, so
```

Line 31:

```text
the Ouros bar finds it next to the registry and socket it already reads.
```

Line 36:

```text
Open the controller connection once; `None` means fail-closed.
```

## rust/fleet-agent/src/main.rs

Line 1:

```text
Binary entry: `fleet-agent serve` (MCP stdio), `fleet-agent ask "…"`,
```

Line 2:

```text
`fleet-agent meter` (read/total the ledger), `fleet-agent self-check`.
```

Line 50:

```text
Fail closed but keep serving: the host sees per-call errors naming
```

Line 51:

```text
the socket, which is the contract. A server that refuses to start
```

Line 52:

```text
leaves the host with no tools/list at all.
```

Line 119:

```text
The status must reach the PTY while the request is still running.
```

Line 125:

```text
Meter the turn: one signed record appended per ask.
```

Line 172:

```text
File transport keeps the full request out of the shell's command echo. The
```

Line 173:

```text
same byte limit applies to inline questions and files, without truncation.
```

Line 204:

```text
The package targets Darwin and Linux; opening a FIFO must not wait for a
```

Line 205:

```text
writer before we can reject it. O_NONBLOCK does not alter regular files.
```

Line 236:

```text
Only Fleet Agent's own labels are styled. Reply/error content and terminal
```

Line 237:

```text
control sequences pass through unchanged; machine-readable output stays raw.
```

## rust/fleet-agent/src/meter.rs

Line 1:

```text
Metered usage, billed through Ouros.
```

Line 3:

```text
The same locality argument as the license keys (`docs/FREEMIUM.md`): Ouros
```

Line 4:

```text
already reaches this machine for the agent mailbox, so billing rides a local
```

Line 5:

```text
signed record instead of a cloud call. Every turn the engine runs appends
```

Line 6:

```text
one HMAC-signed record to the ledger under the FleetConsole support
```

Line 7:

```text
directory; the Ouros bar (or a store webhook) reads and totals it offline.
```

Line 9:

```text
Record format: `FLTA-<base32 payload>.<base32 HMAC-SHA256>` where the
```

Line 10:

```text
payload is a compact string of `|`-separated fields:
```

Line 12:

```text
```text
```

Line 13:

```text
v1|<agent>|<period yyyyMMdd>|<model>|<input tokens>|<output tokens>|<turns>
```

Line 14:

```text
```
```

Line 16:

```text
The signature is HMAC-SHA256 over the payload with the vendor secret — the
```

Line 17:

```text
same secret family as `FLT1` license keys, so a mint and a bill validate
```

Line 18:

```text
with the same offline machinery. `FLTB` can change everything after the
```

Line 19:

```text
dash without breaking old records.
```

Line 35:

```text
One metered turn: the raw counters the engine accumulated.
```

Line 48:

```text
A validated meter record (payload already parsed).
```

Line 60:

```text
The `|`-separated payload string this record signs.
```

Line 125:

```text
Signs one record into `FLTA-<payload-b32>.<sig-b32>`.
```

Line 137:

```text
Validates and parses a signed record. Mirrors `LicenseKey.isValid`: a
```

Line 138:

```text
record that validates today validates in ten years.
```

Line 178:

```text
The local period key (UTC `yyyyMMdd`) for a unix-seconds timestamp.
```

Line 185:

```text
Howard Hinnant's `civil_from_days` (canonical form, verified against the
```

Line 186:

```text
published algorithm), UTC, dependency-free.
```

Line 190:

```text
[0, 146096]
```

Line 191:

```text
[0, 399]
```

Line 193:

```text
[0, 365]
```

Line 194:

```text
[0, 11]
```

Line 195:

```text
[1, 31]
```

Line 196:

```text
[1, 12]
```

Line 200:

```text
Totals a ledger file's records: (valid records, invalid lines, summed usage).
```

Line 226:

```text
Appends one signed record to the ledger, creating it 0600 with 0700 dirs.
```

Line 269:

```text
Flip the last payload character (before the '.').
```

Line 321:

```text
2025-10-12T00:00:00Z
```

Line 323:

```text
Year boundary: 2027-01-01T00:00:00Z = 1798764800
```

## rust/fleet-agent/src/server.rs

Line 1:

```text
MCP stdio server for the fleet-agent surface.
```

Line 3:

```text
Forked from the rx MCP procedure: newline-delimited JSON-RPC 2.0 over
```

Line 4:

```text
stdio, byte-stable `tools/list`, fail-closed `tools/call` with the error
```

Line 5:

```text
naming the socket, and zero records written for rejected or unavailable
```

Line 6:

```text
calls. The schema hash is pinned in `tools::SCHEMA_SHA256` and asserted by
```

Line 7:

```text
the crate's own tests.
```

Line 25:

```text
Serve newline-delimited JSON-RPC on the given reader/writer until EOF.
```

Line 61:

```text
notification: no reply
```

Line 82:

```text
Tool errors are *results* in MCP, not protocol
```

Line 83:

```text
errors: the host sees isError and the model
```

Line 84:

```text
reads the reason.
```

Line 123:

```text
A leaked empty box satisfies the 'static borrow without unsafe.
```

Line 146:

```text
Byte-stable: the embedded list matches the pinned payload.
```

## rust/fleet-agent/src/tools.rs

Line 1:

```text
The agent's tool surface: typed operations over the fleetd socket.
```

Line 3:

```text
Forked from the rx MCP procedure: byte-stable tool definitions as module
```

Line 4:

```text
literals (no timestamps, counts, paths or host state in a schema), a pinned
```

Line 5:

```text
schema hash, canonical JSON serialization, and fail-closed behavior when
```

Line 6:

```text
the backing daemon is missing. The agent never gets raw shell execution —
```

Line 7:

```text
every capability is a typed RPC against the controller, which is the whole
```

Line 8:

```text
point of the console: agents call the CLI/daemon instead of spawning
```

Line 9:

```text
processes themselves (`docs/RUNBOOKS.md`).
```

Line 15:

```text
Pinned SHA-256 of the canonical `tools/list` payload. A host (or test)
```

Line 16:

```text
asserts against this constant; a drifting schema invalidates prompt caches,
```

Line 17:

```text
which is the entire reason it is pinned.
```

Line 24:

```text
One tool's schema, as a pre-serialized canonical JSON object literal.
```

Line 25:

```text
Written by hand (not built from structs) so the bytes are stable by
```

Line 26:

```text
construction and reviewable in one place.
```

Line 30:

```text
Canonical JSON: sorted keys, no whitespace.
```

Line 112:

```text
The canonical `tools/list` result: sorted keys, compact separators.
```

Line 128:

```text
Canonical JSON: sorted keys, compact separators — the cache-stable form.
```

Line 130:

```text
serde_json's Value preserves insertion order; canonicalize by
```

Line 131:

```text
re-serializing through a sorted map walk.
```

Line 188:

```text
Dispatch — every tool call becomes exactly one controller RPC.
```

Line 211:

```text
Executable proposal boundary. Model-supplied `confirm=true` cannot opt
```

Line 212:

```text
into controller mutations, including lease renewal and mailbox writes.
```

Line 260:

```text
A partial or oversized frame cannot be safely reused by a
```

Line 261:

```text
later tool request. Drop it instead of reading stale bytes.
```

Line 307:

```text
Fail closed with a reason when the daemon is missing: an agent
```

Line 308:

```text
surface that fabricates success over a dead socket is the defect
```

Line 309:

```text
class this codebase keeps having to remove.
```

Line 340:

```text
Present a stable, agent-friendly shape: ok/error first-class.
```

Line 347:

```text
Execute one tool call. Returns the JSON `result` object.
```

Line 521:

```text
The controller reply is half-opaque by design (`fleet-proto` docs); wrap it
```

Line 522:

```text
so serde keeps every field the daemon sent, none invented.
```

Line 570:

```text
Specialized analysis over a snapshot payload
```

Line 682:

```text
System-wide: read the telemetry block the snapshot carries when present.
```

Line 734:

```text
renew and message mutate controller state but not processes;
```

Line 735:

```text
they stay un-gated by design and are documented as such.
```

Line 773:

```text
Missing daemon means we never reach the confirm-passed path's send,
```

Line 774:

```text
so a true confirm must produce the *socket* error, not a panic.
```

Line 806:

```text
limit truncates
```

## rust/fleet-conformance/src/main.rs

Line 1:

```text
Proves the Rust protocol types and the running Swift controller agree.
```

Line 3:

```text
This is the test that makes the port safe to attempt. Every check is a full
```

Line 4:

```text
round trip across the language boundary — Rust encodes a request, the Swift
```

Line 5:

```text
daemon decodes and acts on it, Swift encodes a reply, Rust decodes that. A
```

Line 6:

```text
unit test in either language proves only that it agrees with itself.
```

Line 8:

```text
Read-only operations only. `ping`, `snapshot` and `events` observe; nothing
```

Line 9:

```text
here launches, stops or signals anything, so it is safe to run against the
```

Line 10:

```text
controller that is supervising real work.
```

Line 12:

```text
cargo run -p fleet-conformance
```

Line 32:

```text
1. Envelope round trip, and the one struct we model completely.
```

Line 60:

```text
2. A large real payload decodes without the envelope losing anything.
```

Line 75:

```text
These are the fields the app reads on every tick. If the
```

Line 76:

```text
Rust daemon ever stops emitting one, the GUI goes quietly
```

Line 77:

```text
wrong rather than loudly failing — so assert them here.
```

Line 92:

```text
3. Optional fields we serialise must be understood, not merely tolerated.
```

Line 107:

```text
4. The daemon must reject what it does not understand, rather than
```

Line 108:

```text
succeeding vaguely — otherwise a Rust bug looks like a working call.
```

## rust/fleet-gpui/Cargo.toml

Line 10:

```text
Synthetic data for captures and tests (`--fixture <scenario>`). Never enabled
```

Line 11:

```text
for release builds; without it no fixture code or data is compiled in.
```

Line 18:

```text
Unbounded channel and `select` used to wake the UI from fleet-ui-core's
```

Line 19:

```text
controller and telemetry threads and from the macOS status item. Already in
```

Line 20:

```text
Cargo.lock at 0.3.34 through gpui; no new package enters the lockfile.
```

Line 24:

```text
The menu bar status item (NSStatusItem) is created through the Objective-C
```

Line 25:

```text
runtime on the main thread. Both crates are already in Cargo.lock through
```

Line 26:

```text
gpui's macOS platform layer (objc 0.2.7, cocoa 0.26.0); no new package
```

Line 27:

```text
enters the lockfile.
```

## rust/fleet-gpui/src/app.rs

Line 1:

```text
The running application: one `Hub` entity that owns the feeds and the
```

Line 2:

```text
latest `Built` dashboard, the quick view and full window that observe it,
```

Line 3:

```text
the application actions and menus, and the status-area item.
```

Line 5:

```text
Idle cost: the hub waits on a channel that `fleet-ui-core`'s controller
```

Line 6:

```text
and telemetry threads signal after each change, plus a one-second timer
```

Line 7:

```text
for staleness. On either, it compares a cheap fingerprint (generation
```

Line 8:

```text
counters, phases at the current time); only when that changed does it
```

Line 9:

```text
rebuild the dashboard, and only when the dashboard differs does it notify
```

Line 10:

```text
the windows, which then re-render. There is no animation loop.
```

Line 34:

```text
Client-side notices (refusals before anything reached the controller)
```

Line 35:

```text
kept for the activity strip.
```

Line 48:

```text
Why there is no status-area item, shown in the windows. `None` when
```

Line 49:

```text
the item exists or the check has not finished.
```

Line 89:

```text
Send an action to the controller. A refusal before the socket (read
```

Line 90:

```text
only, queue full, fixture mode) becomes a notice; anything sent shows
```

Line 91:

```text
up in the dashboard's activity as pending, then as its outcome.
```

Line 137:

```text
Clear before reading so a change after this point sends a new wake.
```

Line 145:

```text
Open windows and the status item, kept as a global so actions and the
```

Line 146:

```text
status item can find them.
```

Line 151:

```text
The size requested with `--window-size`, used for the first window.
```

Line 155:

```text
When the popover last closed because it lost focus. A status-item
```

Line 156:

```text
click that arrives right after is the same click that took focus
```

Line 157:

```text
away, and toggles the popover closed rather than reopening it.
```

Line 169:

```text
The `--window-size` size for the first window opened, then the default.
```

Line 180:

```text
Open the full window, or bring it forward on `view`.
```

Line 224:

```text
Open the quick view as an ordinary window, or as a popover under the
```

Line 225:

```text
status item when one exists and `anchor` is known.
```

Line 296:

```text
Called by the quick view when its popover loses focus.
```

Line 303:

```text
A click on the status item: open the quick view under it, bring it
```

Line 304:

```text
forward, or close it if it is already in front.
```

Line 334:

```text
The quick view, as a popover when the status item exists.
```

Line 353:

```text
The dark palette every window opens with, picked once at start-up.
```

Line 375:

```text
Wake the hub from the background threads. The flag coalesces bursts
```

Line 376:

```text
so at most one wake waits in the channel.
```

Line 402:

```text
Without a status item, closing the last window ends the client; with
```

Line 403:

```text
one, the client stays in the menu bar.
```

Line 419:

```text
Create the status-area item where the platform supports it, and record
```

Line 420:

```text
why not otherwise.
```

Line 439:

```text
The Linux check asks the session bus; run it off the main thread.
```

## rust/fleet-gpui/src/cli.rs

Line 1:

```text
Command-line options. Flag names match the terminal client's (`fleet-tui`)
```

Line 2:

```text
so both clients start the same way.
```

Line 14:

```text
Controller poll and telemetry sample interval, 1 to 60 seconds.
```

Line 16:

```text
Open the compact quick view instead of the full window.
```

Line 18:

```text
The full window's first view.
```

Line 20:

```text
The dark palette: fog glass, or the terminal phosphor green.
```

Line 22:

```text
Size of the first window, in points.
```

Line 48:

```text
Static identity JSON; reads nothing.
```

Line 50:

```text
One controller read and one telemetry sample, reported as JSON.
```

Line 113:

```text
`--flag=value` is accepted as well as `--flag value`.
```

## rust/fleet-gpui/src/feeds.rs

Line 1:

```text
Where the window's data comes from: the live controller and telemetry
```

Line 2:

```text
threads in `fleet-ui-core`, or, in fixture builds only, a fixed synthetic
```

Line 3:

```text
scenario with no threads at all.
```

Line 5:

```text
The window never waits on a socket or a process scan. It asks for a
```

Line 6:

```text
`Fingerprint` (two atomic loads and a clock comparison) and rebuilds the
```

Line 7:

```text
`Dashboard` only when the fingerprint changed: a new controller read, a
```

Line 8:

```text
new telemetry sample, an action queued or finished, or a phase change such
```

Line 9:

```text
as a live feed aging into stale.
```

Line 20:

```text
Everything the window renders, built at one instant.
```

Line 24:

```text
(mount, total bytes, used bytes) per volume, in the order of
```

Line 25:

```text
`dashboard.storage.volumes`, for the proportional volume map.
```

Line 27:

```text
The newest log text read through the controller, by service id.
```

Line 29:

```text
Set in fixture mode, so every window says the data is synthetic.
```

Line 39:

```text
Age of the last controller read while it is not live, so the "last
```

Line 40:

```text
read 40s ago" text advances; `None` while live.
```

Line 78:

```text
Start the controller poller and the telemetry sampler, or the fixture.
```

Line 99:

```text
Fixture data never changes, so the window has nothing to watch.
```

Line 199:

```text
One step per second for the first minute, then per minute, matching the
```

Line 200:

```text
resolution of `format::duration`.
```

Line 220:

```text
The fixture dashboard, built exactly as the live one is. Test code builds
```

Line 221:

```text
it too, through `fleet_ui_core::fixtures`.
```

Line 248:

```text
How long the window waits between staleness checks when nothing wakes it.
```

Line 280:

```text
The poller reads once at start; wait for it.
```

## rust/fleet-gpui/src/full.rs

Line 1:

```text
The full window: six views over the same dashboard, tabs across the top
```

Line 2:

```text
as in `design/tui.html`, the connection banner whenever the controller is
```

Line 3:

```text
not live, an activity strip with action outcomes, and the confirmation
```

Line 4:

```text
step for destructive actions.
```

Line 32:

```text
Header, tabs, banners, the activity strip and the key hints above and
```

Line 33:

```text
below the map panel. The map sizes itself to what is left of the window.
```

Line 35:

```text
The legend and the notes strip at the bottom of the map panel.
```

Line 37:

```text
Clear space around the graph so labels never touch the panel edge.
```

Line 39:

```text
The width of every clickable node label.
```

Line 51:

```text
GPUI keystroke to state-machine key. Modified keys other than the quit
```

Line 52:

```text
chord are left for the system.
```

Line 488:

```text
Group unavailable gauges by reason: "cpu, mem, gpu: node offline".
```

Line 865:

```text
Refusal reasons, grouped so a shared reason prints once.
```

Line 1142:

```text
Proportional map: blocks per volume by total bytes, used blocks
```

Line 1143:

```text
colored by the volume's band, one empty block between volumes.
```

Line 1385:

```text
The relational map: the controller at the center, devices, services,
```

Line 1386:

```text
agents, processes and volumes around it, laid out once per dashboard
```

Line 1387:

```text
by `RelationalMap`. Edges and node plates are canvas strokes; labels
```

Line 1388:

```text
are clickable overlays; the inspector explains the selected node.
```

Line 1398:

```text
The map opens with its first node selected so the inspector has
```

Line 1399:

```text
something honest to show from the first frame, the way the Agents
```

Line 1400:

```text
view prefers an open question.
```

Line 1406:

```text
Only fog glass draws translucent chrome; phosphor and paper keep
```

Line 1407:

```text
solid fills and full-color accents.
```

Line 1415:

```text
Fit the settled layout into the drawing area. The margin leaves
```

Line 1416:

```text
room for the labels under the nodes.
```

Line 1432:

```text
Paint values precomputed here so the canvas closure only paints:
```

Line 1433:

```text
for each node its disc radius, its plate color, the glow behind it
```

Line 1434:

```text
and, while the level is warning or critical, its level ring.
```

Line 1452:

```text
Edges resolved to node indexes, in map order, with the overlay
```

Line 1453:

```text
color for the activity stroke: the target's accent when its feed
```

Line 1454:

```text
measured activity, `None` where it did not.
```

Line 1474:

```text
The selection ring, drawn for whichever node is selected now.
```

Line 1512:

```text
Edges first, under the node plates. The base
```

Line 1513:

```text
stroke's weight follows the edge kind; the
```

Line 1514:

```text
activity overlay rides on top only where a
```

Line 1515:

```text
feed measured it, so an unmeasured edge never
```

Line 1516:

```text
reads as active.
```

Line 1551:

```text
Node plates: the soft glow, the disc, the
```

Line 1552:

```text
level ring and the selection ring.
```

Line 1591:

```text
The worst pinned report's word rides on the label, so the
```

Line 1592:

```text
dot of severity never has to travel without its word.
```

Line 1664:

```text
The legend names every line shape and hue with the word it stands
```

Line 1665:

```text
for; color never travels alone.
```

Line 1709:

```text
The notes say which groups are not drawn and why, in feed words.
```

Line 1738:

```text
The inspector explains the selected node: its kind, heat, level,
```

Line 1739:

```text
freshness and the reports pinned on it. `enter` opens and closes
```

Line 1740:

```text
it over the selection.
```

Line 1898:

```text
Node plate sizes. The controller is the big center disc; groups get
```

Line 1899:

```text
smaller toward the periphery so the map reads from the center out.
```

Line 1911:

```text
Why a node's feed is not current, in the words the other views use. The
```

Line 1912:

```text
current feed needs no word: the values on the node speak for it.
```

## rust/fleet-gpui/src/geometry.rs

Line 1:

```text
Layout and drawing math, free of GPUI types so it can be tested.
```

Line 3:

```text
Dial coordinates are screen coordinates in points: x to the right, y down,
```

Line 4:

```text
relative to the dial's own box. Angles follow the mathematical convention
```

Line 5:

```text
(counterclockwise from the positive x axis) and are converted when a point
```

Line 6:

```text
is produced.
```

Line 10:

```text
The dial sweeps 240 degrees, from lower left (0%) over the top to lower
```

Line 11:

```text
right (100%), like the Mac popover's gauges.
```

Line 14:

```text
The red zone marks the top of the scale: the critical band above 90%.
```

Line 16:

```text
Tick marks every 10%, longer at 0, 50 and 100.
```

Line 28:

```text
Center and radius of the largest dial that fits a `width` by `height`
```

Line 29:

```text
box with `inset` points kept clear on every side. The 240 degree sweep
```

Line 30:

```text
reaches 1.0 radius above the center and 0.5 below it.
```

Line 39:

```text
Points along the dial arc from one fraction to another, no more than
```

Line 40:

```text
`step_deg` apart, for drawing the arc as a polyline.
```

Line 53:

```text
Tick marks as (outer, inner, major) segments.
```

Line 69:

```text
The needle from the hub to its tip. Callers draw no needle at all when the
```

Line 70:

```text
value is unavailable; there is no resting position that could be read as 0%.
```

Line 75:

```text
How many cluster tiles fit per row and how wide each is.
```

Line 83:

```text
Divide `cells` blocks among volumes in proportion to their total bytes,
```

Line 84:

```text
then split each volume's blocks into used and free in proportion to its
```

Line 85:

```text
used bytes. Every volume with bytes gets at least one block while there
```

Line 86:

```text
are enough blocks. Returns `(used, free)` per volume.
```

Line 92:

```text
Largest remainder allocation.
```

Line 109:

```text
A volume with bytes but no block would vanish from the map; take one
```

Line 110:

```text
block from the largest allocation for it.
```

Line 137:

```text
Tree-drawing prefixes for process lines given as (depth, last_child).
```

Line 138:

```text
Roots (depth 0) get no prefix; each deeper line gets one column per
```

Line 139:

```text
ancestor level, continuing the ancestor's vertical line while that
```

Line 140:

```text
ancestor has later siblings.
```

Line 167:

```text
Heights (0 to 1) for the last `count` history samples, right-aligned.
```

Line 168:

```text
`None` stays `None`: an interval without a measurement is a gap.
```

Line 199:

```text
Out-of-range fractions clamp to the ends of the scale.
```

Line 209:

```text
Right of center and descending toward the 100% end.
```

Line 279:

```text
fleetd
```

Line 280:

```text
api-gateway
```

Line 281:

```text
node
```

Line 282:

```text
node
```

Line 283:

```text
render-studio
```

Line 284:

```text
child
```

Line 285:

```text
other root
```

## rust/fleet-gpui/src/lib.rs

Line 1:

```text
FleetConsole GPUI client.
```

Line 3:

```text
A desktop window over the same two feeds the terminal client reads: the
```

Line 4:

```text
controller snapshot and this machine's telemetry, both owned by
```

Line 5:

```text
`fleet-ui-core`'s background threads. Everything drawn comes from
```

Line 6:

```text
`fleet_ui_core::views::Dashboard`, so this client and the terminal client
```

Line 7:

```text
cannot disagree about a count, a threshold or an unavailable value. Actions
```

Line 8:

```text
go only through `Controller::submit`; nothing here signals a process.
```

Line 10:

```text
The modules without GPUI types (`cli`, `state`, `geometry`, `logo`,
```

Line 11:

```text
`feeds`, `verify`) hold the logic and carry the unit tests. The GPUI
```

Line 12:

```text
modules (`app`, `ui`, `quick`, `full`, `status_item`) turn that state into
```

Line 13:

```text
elements and route input back into it.
```

## rust/fleet-gpui/src/logo.rs

Line 1:

```text
The F/C block logo as a cell grid, from
```

Line 2:

```text
`design/assets/fleet-console-logo-terminal.svg`: the F in the bright tone,
```

Line 3:

```text
the C in the dark tone, and the cells where they overlap dithered. Drawn
```

Line 4:

```text
from cells so the window and the menu bar item need no image file.
```

Line 10:

```text
A 2 by 2 checker of the two tones.
```

Line 19:

```text
Row-major, top row first. `None` is background.
```

Line 28:

```text
Every filled cell as (row, column, tone).
```

Line 43:

```text
The SVG fills 20 of the 30 cells: 7 F cells, 10 C cells and 3
```

Line 44:

```text
dithered overlap cells.
```

Line 50:

```text
The F's stem runs down the first column.
```

## rust/fleet-gpui/src/main.rs

Line 1:

```text
`fleet-gpui`: the FleetConsole desktop client. See `--help`.
```

## rust/fleet-gpui/src/palette.rs

Line 1:

```text
Colors and font for the window, from `design/tokens.json` through
```

Line 2:

```text
`fleet_ui_core::theme`. Dark mode uses the glass fog palette by default —
```

Line 3:

```text
a translucent panel over the blurred window material with a vibrant level
```

Line 4:

```text
ramp — or the phosphor palette when `--theme phosphor` says so; light mode
```

Line 5:

```text
uses the paper palette. The window re-reads the choice when the system
```

Line 6:

```text
appearance changes.
```

Line 19:

```text
Which dark palette the window uses. Fog is the default; phosphor stays
```

Line 20:

```text
available from the command line.
```

Line 44:

```text
The dark theme the windows were opened with, set once at start-up.
```

Line 56:

```text
The window's background material. Only fog draws its chrome over the
```

Line 57:

```text
system blur; phosphor and paper need the plain backdrop because their
```

Line 58:

```text
fills are opaque, and a blur under them would only cost.
```

Line 98:

```text
The translucent layered panel: the fog look. `Chrome` values are alphas
```

Line 99:

```text
layered over the window's blurred background material; every one stays
```

Line 100:

```text
behind opaque text, so no value or reason is drawn translucent.
```

Line 105:

```text
The window root: mostly transparent so the blurred material reads as
```

Line 106:

```text
fog behind the chrome.
```

Line 110:

```text
Cards and panels.
```

Line 114:

```text
The soft glow ring behind a node. Always behind the node plate.
```

Line 118:

```text
Edge strokes on the map; the faint route lines between nodes.
```

Line 122:

```text
A filled swatch in the legend or a badge plate.
```

Line 128:

```text
Vibrant category colors for the relational map, one per node kind. They
```

Line 129:

```text
label nothing on their own: every surface also carries the kind's word, in
```

Line 130:

```text
the inspector, the legend or the node label itself.
```

Line 152:

```text
The paper appearance has its own accents, slightly deeper so
```

Line 153:

```text
they hold on the light substrate.
```

Line 165:

```text
The accent of a node kind, for the renderer that walks nodes by kind.
```

Line 210:

```text
The window root: translucent over the blurred material in the fog
```

Line 211:

```text
theme, opaque elsewhere.
```

Line 218:

```text
Panel and card fills.
```

Line 223:

```text
Whether the window's background material is up: only the fog theme is
```

Line 224:

```text
translucent over the blurred window; phosphor and paper draw opaque.
```

Line 233:

```text
The band color for a lit segment.
```

Line 246:

```text
Text color for a value in a band: ordinary text until warning, then
```

Line 247:

```text
amber and red. The band's word is always shown next to it.
```

Line 256:

```text
Border color for something whose worst band is `level`.
```

Line 266:

```text
Monospace families in preference order: the design font first, then the
```

Line 267:

```text
common system monospace families on macOS and Linux.
```

Line 281:

```text
The first candidate the system has. When none is installed, fall back to
```

Line 282:

```text
the platform's usual monospace family name and let GPUI's own fallback
```

Line 283:

```text
stack resolve it.
```

## rust/fleet-gpui/src/quick.rs

Line 1:

```text
The quick view: the Mac popover's information in the phosphor system.
```

Line 3:

```text
Header: logo, "FleetConsole", the running-service count, a button that
```

Line 4:

```text
opens the full window, an Agents button that opens it on the Agents view,
```

Line 5:

```text
and a More menu (Refresh, Open window, Quit). Four columns: CPU and
```

Line 6:

```text
Memory dials, Disk as a 5 by 4 block grid, Network as download and upload
```

Line 7:

```text
rates with bars. Opened from the status item it is a popover that closes
```

Line 8:

```text
when it loses focus; opened with `--quick` it is an ordinary window.
```

## rust/fleet-gpui/src/state.rs

Line 1:

```text
What the full window is showing and what a key or click does.
```

Line 3:

```text
A pure state machine over `Dashboard`: `handle_key` and the request
```

Line 4:

```text
helpers return `Effect`s, and the window applies them (submit to the
```

Line 5:

```text
controller, post a notice, quit). Keeping GPUI out of this module is what
```

Line 6:

```text
lets the keyboard, selection and confirmation rules be tested against
```

Line 7:

```text
fixtures.
```

Line 12:

```text
Lease renewal requested by `n` in the Services view, matching the
```

Line 13:

```text
`fleetctl renew <id> --lease 30m` example in docs/AGENTS.md.
```

Line 24:

```text
The relational map: controller, devices, services, agents, processes
```

Line 25:

```text
and volumes as one graph.
```

Line 44:

```text
The `1` to `7` key that selects it.
```

Line 67:

```text
`1` to `6` or a view name, case-insensitive.
```

Line 79:

```text
A key as the state machine sees it. The window maps GPUI keystrokes here.
```

Line 87:

```text
`cmd-q` or `ctrl-q`.
```

Line 143:

```text
A destructive action waiting for the operator to confirm it.
```

Line 156:

```text
Bring this row of this view into the visible part of its list.
```

Line 163:

```text
A stable identity for the selected row, so a list that reorders or
```

Line 164:

```text
grows between polls keeps the same row selected.
```

Line 172:

```text
`enter` expands the selected tile, process, service or volume.
```

Line 194:

```text
The selected row of `view` in this dashboard, if the list has rows.
```

Line 231:

```text
The selected service row, from the Services view or from a selected
```

Line 232:

```text
Attention report that names a service.
```

Line 331:

```text
Process lines, volumes and transcript lines show everything
```

Line 332:

```text
they have inline; there is nothing more to expand.
```

Line 334:

```text
A map node's inspector is drawn beside the graph; `enter`
```

Line 335:

```text
opens and closes it over the selected node.
```

Line 361:

```text
Ask for a service action. A refused control becomes a notice with the
```

Line 362:

```text
refusal reason; a destructive action opens the confirmation step; any
```

Line 363:

```text
other action is submitted.
```

Line 408:

```text
Approve or deny an agent's open question.
```

Line 433:

```text
When the Agents view has never had a selection, start on the first
```

Line 434:

```text
open question so `y` and `n` act on it without moving first.
```

Line 474:

```text
Stable identities for the rows of a view, in display order.
```

Line 509:

```text
The question to select when the Agents view opens: the first one still
```

Line 510:

```text
waiting, so `y` and `n` act on it without moving first.
```

Line 614:

```text
Keys other than confirm or cancel do nothing while the step is open.
```

Line 755:

```text
The fixture question also names a service; open the question by
```

Line 756:

```text
removing that link, as for an agent asking without a service.
```

## rust/fleet-gpui/src/status_item.rs

Line 1:

```text
The status-area item.
```

Line 3:

```text
macOS: an `NSStatusItem` in the menu bar, created on the main thread
```

Line 4:

```text
through the Objective-C runtime. Its button shows the F/C logo as a
```

Line 5:

```text
template image; a click sends on a channel that a GPUI task reads, which
```

Line 6:

```text
opens, focuses or closes the quick view as a popover under the item.
```

Line 8:

```text
Linux: this client does not publish a StatusNotifierItem. The window shows
```

Line 9:

```text
`fleet_ui_core::platform::status_area()`'s answer in words: either that a
```

Line 10:

```text
host exists but no item is published, or why no host is available. The
```

Line 11:

```text
client then runs as an ordinary window and quits when it is closed.
```

Line 15:

```text
Where the status item sits, in points relative to the top-left corner of
```

Line 16:

```text
its display: the left edge and bottom edge of the item, and its width.
```

Line 27:

```text
No item, for this reason.
```

Line 29:

```text
The reason needs a session-bus query; run `describe(status_area())`
```

Line 30:

```text
off the main thread.
```

Line 34:

```text
Top-left corner for a popover of `window_width` under the item: right
```

Line 35:

```text
edges aligned, kept 8 points inside the display.
```

Line 42:

```text
The sentence a window shows when there is no status-area item.
```

Line 56:

```text
objc 0.2's `msg_send!`, `sel!` and `class!` expand to a test of
```

Line 57:

```text
`feature = "cargo-clippy"`, which this crate does not declare.
```

Line 72:

```text
`NSVariableStatusItemLength`.
```

Line 94:

```text
one object argument.
```

Line 105:

```text
An autoreleased NSString.
```

Line 113:

```text
The logo as an 18 by 15 point template image: the F opaque, the C at
```

Line 114:

```text
partial alpha, overlap cells between, so the menu bar tints it for
```

Line 115:

```text
light and dark appearances.
```

Line 149:

```text
The menu bar item. Lives for the rest of the process; AppKit objects
```

Line 150:

```text
here are touched only on the main thread.
```

Line 157:

```text
Must run on the main thread after the application has launched,
```

Line 158:

```text
which is where GPUI's `Application::run` callback runs.
```

Line 176:

```text
The status bar does not keep the item alive by itself.
```

Line 190:

```text
VoiceOver reads this native control even though the GPUI
```

Line 191:

```text
windows expose no accessibility tree.
```

Line 247:

```text
No status item is published on this platform; see the module notes.
```

## rust/fleet-gpui/src/ui.rs

Line 1:

```text
Elements shared by the quick view and the full window: the logo, dials,
```

Line 2:

```text
segmented gauges, the disk grid, rate bars, history sparks, buttons and
```

Line 3:

```text
the connection banner. Hard edges, 1px line borders, monospace text; color
```

Line 4:

```text
always travels with a word.
```

Line 20:

```text
The font chosen at start-up from what the system has installed.
```

Line 49:

```text
A dashed polyline stroke, for the map's route lines between the
```

Line 50:

```text
controller and the agents it talks to.
```

Line 73:

```text
A filled disc, the map's node plate. A 24-gon reads as a circle at the
```

Line 74:

```text
sizes the map draws and settles without going through lyon's arc handling.
```

Line 99:

```text
The F/C logo drawn from its cell grid. `cell` is the cell edge in points.
```

Line 129:

```text
The scanline through each cell, at sizes where it reads.
```

Line 147:

```text
A dial: track, red zone at the top of the scale, tick marks, the value
```

Line 148:

```text
arc and the needle. An unavailable value draws no arc and no needle.
```

Line 199:

```text
The words under a gauge: its detail when measured, the reason when not,
```

Line 200:

```text
and the band's name when it is warning or critical.
```

Line 216:

```text
`Gauge::spoken` without the trailing separator it leaves when a measured
```

Line 217:

```text
gauge has no detail.
```

Line 225:

```text
Twenty segments, each colored by its own position's band.
```

Line 241:

```text
The quick view's 5 by 4 disk grid, filled in reading order.
```

Line 258:

```text
A horizontal bar: `fraction` of the width lit, the rest unlit.
```

Line 268:

```text
A network rate: label, value, bar and, when unavailable, the reason.
```

Line 294:

```text
A history spark: one bar per sample, a gap where nothing was measured.
```

Line 312:

```text
A one-line hover text. GPUI 0.2.2 has no accessibility tree, so the same
```

Line 313:

```text
text is always also visible somewhere on screen; this is a convenience.
```

Line 345:

```text
A bordered text button. A refused control is drawn dim, takes no clicks,
```

Line 346:

```text
and carries its reason as a tooltip; callers also print the reason.
```

Line 377:

```text
A row in a list: the selected row is a solid dark-green bar with the
```

Line 378:

```text
selected-text color, as in the design package.
```

Line 391:

```text
A fixed-width table cell that clips instead of wrapping.
```

Line 403:

```text
A flexible table cell that takes the remaining width and clips.
```

Line 415:

```text
A bordered panel with a title in the top line.
```

Line 443:

```text
The controller's state in words, shown before any value whenever the
```

Line 444:

```text
controller feed is not live: loading, stale with its age, disconnected or
```

Line 445:

```text
error with the detail the controller connection reported.
```

Line 495:

```text
A small 2 by 2 grid icon for the "open window" button.
```

## rust/fleet-gpui/src/verify.rs

Line 3:

```text
`--identity` is static: it reads nothing and says what this build is.
```

Line 4:

```text
`--verify` performs one real controller read and two telemetry samples
```

Line 5:

```text
(CPU use and network rates are differences, so the first sample alone has
```

Line 6:

```text
none), then reports what was observed. Anything it did not exercise, such
```

Line 7:

```text
as drawing a window or creating the status-area item, is listed as not
```

Line 8:

```text
checked rather than implied.
```

Line 60:

```text
What one verification run observed.
```

Line 72:

```text
Fold an observed controller feed and telemetry sample into the report.
```

Line 73:

```text
Separate from the I/O so the wording can be tested with fixtures.
```

Line 159:

```text
Read the controller once and sample telemetry twice, one second apart.
```

Line 166:

```text
The poller's first read starts immediately and runs while telemetry is
```

Line 167:

```text
sampled on this thread.
```

## rust/fleet-proto/src/lib.rs

Line 1:

```text
The FleetConsole controller protocol, in Rust.
```

Line 3:

```text
This is the seam the port runs through. `FleetConsole.app` has always been a
```

Line 4:

```text
client — it speaks newline-delimited JSON over a `0600` Unix socket and never
```

Line 5:

```text
signals a process itself — so a Rust daemon can replace the Swift one without
```

Line 6:

```text
the GUI knowing, and a Rust TUI can be a second client of the same socket.
```

Line 7:

```text
That only holds if both sides agree on the bytes, which is what
```

Line 8:

```text
`fleet-conformance` exists to prove against the running daemon.
```

Line 10:

```text
Two details are load-bearing and easy to get wrong:
```

Line 12:

```text
**Dates are epoch seconds**, because Swift's `Codec` pins
```

Line 13:

```text
`dateEncodingStrategy = .secondsSince1970`. They are `f64` here, not a
```

Line 14:

```text
date type, so nothing can quietly reinterpret them.
```

Line 15:

```text
**Absent is not null.** Swift decodes a missing key into `nil`, but a
```

Line 16:

```text
present `null` is also valid; we skip serializing `None` so requests look
```

Line 17:

```text
exactly like the ones the Swift client sends.
```

Line 25:

```text
Operations the controller accepts. The wire values are Swift enum raw values,
```

Line 26:

```text
which are the case names verbatim — so `refreshDevices`, not `refresh_devices`.
```

Line 121:

```text
The controller's identity and liveness. Modelled fully because it is the
```

Line 122:

```text
smallest complete thing both implementations must agree on.
```

Line 127:

```text
Epoch seconds.
```

Line 140:

```text
The reply envelope.
```

Line 142:

```text
`snapshot`, `service` and `events` stay `serde_json::Value` deliberately.
```

Line 143:

```text
Porting the registry model is the large half of this work, and a half-modelled
```

Line 144:

```text
`ServiceRecord` that silently drops fields would be worse than an honest
```

Line 145:

```text
opaque one. They get real types as each subsystem is ported.
```

Line 186:

```text
An explicit socket for clients, such as an SSH-forwarded controller socket.
```

Line 188:

```text
Relocates controller state. Matches `FleetPaths.stateRootVariable`.
```

Line 193:

```text
Where the controller listens, in this order:
```

Line 195:

```text
1. `FLEETCONSOLE_SOCKET`, used as given.
```

Line 196:

```text
2. `FLEETCONSOLE_STATE_ROOT`, with the layout `FleetPaths` uses under it.
```

Line 197:

```text
3. On macOS, `FleetPaths.socket` under `HOME`.
```

Line 198:

```text
4. Elsewhere, `$XDG_RUNTIME_DIR/fleetconsole/fleetd.sock`, the place a
```

Line 199:

```text
forwarded or future local controller socket is expected, falling back to
```

Line 200:

```text
`$HOME/.local/state/fleetconsole/fleetd.sock`.
```

Line 222:

```text
A blocking client for one request/response exchange.
```

Line 224:

```text
Blocking on purpose: every operation here is a single round trip against a
```

Line 225:

```text
local socket, and an async runtime would be machinery without a job. The
```

Line 226:

```text
`subscribe` op is the exception and is not modelled yet.
```

Line 238:

```text
Callers that hardened the socket before connecting — owner-only path,
```

Line 239:

```text
connect timeout, descriptor identity — hand the stream over here. The
```

Line 240:

```text
read deadline matches `connect` so a stuck daemon cannot pin a client.
```

Line 263:

```text
Proposal traffic shares the operator turn's deadline and cannot read
```

Line 264:

```text
arbitrary daemon output into memory. Ordinary clients keep `send`.
```

Line 295:

```text
Darwin rejects Unix SO_SNDTIMEO; poll + O_NONBLOCK gives both writes
```

Line 296:

```text
and reads the same deadline, including partial and trickled frames.
```

Line 303:

```text
POLLOUT
```

Line 316:

```text
POLLIN
```

Line 344:

```text
The exact bytes we would put on the wire, for tests that assert shape
```

Line 345:

```text
rather than behaviour.
```

Line 357:

```text
The Swift client sends only `op` for a ping. Emitting explicit nulls
```

Line 358:

```text
would still decode, but it would make the two implementations
```

Line 359:

```text
distinguishable on the wire, which defeats the point.
```

## rust/fleet-spatial/src/lib.rs

Line 1:

```text
Relational Spatial Mapping Engine for FleetConsole.
```

Line 3:

```text
Replaces isolated tabular silos with four operational planes:
```

Line 4:

```text
1. Topography: Interactive spatial & relational graph
```

Line 5:

```text
2. Brain & Agents: Ouros-X adapter plane
```

Line 6:

```text
3. Execution & Telemetry: Live process & resource mapping
```

Line 7:

```text
4. Substrate: Storage and volume memory maps
```

Line 14:

```text
The four core operational planes.
```

Line 34:

```text
Subsystem classification for nodes.
```

Line 46:

```text
Relationship classification for edges.
```

Line 103:

```text
Scaled by RAM footprint / volume
```

Line 105:

```text
Heat factor [0.0, 1.0] derived from CPU / thermal pressure
```

Line 118:

```text
Pulse rate derived from activity/throughput
```

Line 139:

```text
Context bound to the selected entity for the persistent contextual terminal.
```

Line 149:

```text
Descriptive topology hierarchy node for the live sidebar mini-map.
```

Line 155:

```text
[0.0, 1.0]
```

Line 159:

```text
Force-directed relational graph engine.
```

Line 186:

```text
Ingest telemetry and Ouros-X brain graph to construct unified spatial topology.
```

Line 195:

```text
1. Host Node
```

Line 221:

```text
2. Runtime Core Node
```

Line 256:

```text
3. Active Agents from Brain Adapter
```

Line 273:

```text
Calculate radius proportional to context memory tokens
```

Line 323:

```text
Connect agent sub-edges
```

Line 335:

```text
4. Worker Processes from Telemetry
```

Line 338:

```text
Include high-resource or relevant processes
```

Line 389:

```text
Associate process to agent or runtime core
```

Line 411:

```text
5. Storage Pools (Substrate)
```

Line 468:

```text
Preserve coordinates of existing nodes if available
```

Line 481:

```text
Auto-select first agent or core if selection is empty
```

Line 487:

```text
Step the force-directed layout simulation.
```

Line 495:

```text
Snapshot positions in the existing map traversal order so pairwise
```

Line 496:

```text
accumulation keeps its floating-point operation order. Public IDs stay
```

Line 497:

```text
at the edge/integration boundary, outside the quadratic pairwise loop.
```

Line 506:

```text
1. Repulsive forces between every node pair
```

Line 525:

```text
2. Spring forces along edges
```

Line 531:

```text
Telemetry refreshes can leave an edge whose endpoint is gone.
```

Line 543:

```text
Keep these sequential: source and target may be the same node.
```

Line 550:

```text
3. Center gravity and integration
```

Line 552:

```text
Root host node stays anchor near center
```

Line 560:

```text
No nodes are added or removed between the snapshot and integration.
```

Line 573:

```text
Focus viewport onto a specific subsystem node.
```

Line 583:

```text
Build the live Descriptive Topology Map hierarchy for the sidebar.
```

Line 626:

```text
Get all diagnostic badges across all nodes (Diagnostics Drawer view).
```

Line 642:

```text
Bind contextual terminal session to the currently selected entity.
```

Line 744:

```text
Sidebar hierarchy check
```

Line 749:

```text
Diagnostics check: swift-frontend is saturating CPU at 95.5% in simulated telemetry
```

## rust/fleet-telemetry/src/lib.rs

Line 1:

```text
OS-agnostic telemetry provider and hardware capability abstraction.
```

Line 3:

```text
Abstracts system metric collection behind an OS-independent `TelemetryProvider`
```

Line 4:

```text
trait, replacing macOS-exclusive assumptions with configurable hardware profiles.
```

Line 152:

```text
Abstract, cross-platform telemetry provider.
```

Line 159:

```text
Portable telemetry provider backed by `sysinfo`.
```

Line 307:

```text
Deterministic mock telemetry provider for tests and simulation.
```

## rust/fleet-tui/Cargo.toml

Line 10:

```text
Synthetic data for captures and tests. Never enabled for release builds.
```

Line 15:

```text
Terminal rendering and input. ratatui re-exports the crossterm backend it is
```

Line 16:

```text
built against, so the client uses `ratatui::crossterm` instead of a second,
```

Line 17:

```text
independently versioned crossterm dependency.
```

## rust/fleet-tui/src/app.rs

Line 1:

```text
Interface state and the key-handling state machine.
```

Line 3:

```text
`App::handle_key` is a pure function of the current state, the key and the
```

Line 4:

```text
dashboard. It never talks to the controller: it returns a `Command`, and
```

Line 5:

```text
the runtime submits any action and reports the result back with
```

Line 6:

```text
`App::submitted`. That keeps the confirmation rule testable without a
```

Line 7:

```text
socket: a destructive action only ever leaves as `Command::Submit` after a
```

Line 8:

```text
`y` on its confirmation line.
```

Line 16:

```text
Lease length the `n` key renews to, matching `fleetctl renew --lease 30m`.
```

Line 54:

```text
Lowercase name for commands and capture file names.
```

Line 67:

```text
Keys the interface reacts to, independent of the terminal library.
```

Line 84:

```text
What the runtime does after a key.
```

Line 90:

```text
The log tail opened, closed or switched stream: poll now.
```

Line 126:

```text
The `Logs` request in flight, if any.
```

Line 134:

```text
Position in the filtered list.
```

Line 147:

```text
The filter being typed, if any; the view's filter is updated live.
```

Line 151:

```text
First visible row of each view's list, kept between frames.
```

Line 183:

```text
Position of the selection within the filtered list.
```

Line 201:

```text
Index into the view's underlying list for the selected row.
```

Line 220:

```text
Select a row by its position in the filtered list (mouse clicks).
```

Line 225:

```text
Re-anchor selections after the dashboard changed, so a selected row
```

Line 226:

```text
stays selected when rows above it come or go. On the Agents view the
```

Line 227:

```text
first open question is selected until the person moves.
```

Line 287:

```text
Record the runtime's result for a submitted action.
```

Line 317:

```text
Anything else leaves the question open.
```

Line 607:

```text
Keys other than y and n leave the question open and send nothing.
```

Line 697:

```text
A status line is not a question.
```

## rust/fleet-tui/src/capture.rs

Line 1:

```text
Documentation captures: every view of one fixture scenario rendered into
```

Line 2:

```text
`TestBackend` and written as plain text, one file per view, named
```

Line 3:

```text
`<scenario>-<view>-<cols>x<rows>.txt`. Fixture builds only.
```

## rust/fleet-tui/src/cli.rs

Line 1:

```text
Command-line options. The flag names match the GPUI client's so the two
```

Line 2:

```text
can be started the same way.
```

Line 18:

```text
The view to open on, or every view with `--once`.
```

Line 31:

```text
Every view in order; only meaningful with `--once`.
```

Line 126:

```text
`--flag=value` is accepted as well as `--flag value`.
```

## rust/fleet-tui/src/content.rs

Line 1:

```text
What each view lists, inspects and hands to an agent, derived from the
```

Line 2:

```text
dashboard. Pure functions shared by the full-screen and plain renderers,
```

Line 3:

```text
so both show the same rows, the same detail facts and the same commands.
```

Line 14:

```text
Remove terminal control sequences and control characters from text that
```

Line 15:

```text
came from the controller, an agent or a log. Tabs become spaces.
```

Line 22:

```text
CSI: parameters and intermediates up to a final byte.
```

Line 31:

```text
OSC, DCS, SOS, PM, APC: up to BEL or ST.
```

Line 56:

```text
Bytes from a size `format::bytes` produced (`512 B`, `1.5 KB`, `995 GB`).
```

Line 57:

```text
The storage view needs relative volume capacities and the view model
```

Line 58:

```text
carries only the formatted text; `None` when the text is not a size.
```

Line 68:

```text
Percent wording for speech: `34 percent`, `above 50 percent`.
```

Line 73:

```text
`cpu 34 percent, normal` or `gpu unavailable, not measured on this platform`.
```

Line 115:

```text
Tree glyphs for each process line from its depth and last-child flag:
```

Line 116:

```text
`├─ ` and `└─ ` for the line itself, `│  ` for an ancestor with siblings
```

Line 117:

```text
still to come.
```

Line 152:

```text
A stable identity for a row, so the selection follows it across refreshes.
```

Line 176:

```text
The text a filter matches against.
```

Line 224:

```text
Indices of the rows a filter keeps, in display order.
```

Line 232:

```text
The managed service a row refers to, for restart, stop, renew and tail.
```

Line 262:

```text
The open agent question a row refers to, for approve and deny.
```

Line 306:

```text
The evidence a destructive action rests on, shown before it is sent.
```

Line 334:

```text
One fact in a detail pane.
```

Line 350:

```text
Title and facts for the selected row.
```

Line 577:

```text
The read-only `fleetctl` commands that describe a target, for handing it
```

Line 578:

```text
to an agent session. Commands that change controller state are listed
```

Line 579:

```text
apart and labelled.
```

## rust/fleet-tui/src/main.rs

Line 1:

```text
`fleet-tui`: the FleetConsole terminal client for macOS and Linux.
```

Line 3:

```text
Every value comes from `fleet-ui-core`: the controller connection and the
```

Line 4:

```text
local telemetry sampler run on background threads there, and
```

Line 5:

```text
`views::Dashboard::build` derives everything drawn here. Actions are
```

Line 6:

```text
controller requests with `fleetctl` semantics; nothing in this binary
```

Line 7:

```text
signals a process.
```

Line 32:

```text
How long `--once` waits for the controller's first answer and a second
```

Line 33:

```text
telemetry sample before printing what it has.
```

Line 35:

```text
Size used for `--once` (and captures) when standard output is not a terminal.
```

Line 55:

```text
Exit without joining the worker threads: an in-flight stop or restart
```

Line 56:

```text
holds the action thread until its deadline, and the request has
```

Line 57:

```text
already reached the controller.
```

Line 143:

```text
The workers end with the process; see `main`.
```

Line 169:

```text
`--once` samples telemetry every second so its second sample, the
```

Line 170:

```text
first with CPU figures, arrives quickly.
```

## rust/fleet-tui/src/output.rs

Line 1:

```text
One-shot renderings: a frame drawn into ratatui's `TestBackend` and written
```

Line 2:

```text
as text, with ANSI styling when the output is a color terminal. Used by
```

Line 3:

```text
`--once` and by fixture captures.
```

Line 34:

```text
Named colors are not produced by the theme; map them through
```

Line 35:

```text
their 256-color index for completeness.
```

Line 81:

```text
The buffer as lines of text. Wide characters occupy their cells once;
```

Line 82:

```text
trailing spaces are trimmed when no styling is written.
```

## rust/fleet-tui/src/plain.rs

Line 1:

```text
Line mode for screen readers and logs: no alternate screen, no box
```

Line 2:

```text
drawing, no block glyphs, no color. Each view prints as sentences. The
```

Line 3:

```text
view reprints when a fact a person would act on changes (a phase, a state,
```

Line 4:

```text
a count, a band), at most every five seconds, or when asked; drifting
```

Line 5:

```text
numbers alone do not trigger a reprint. Commands are read one per line.
```

Line 22:

```text
Full text, or the reprint key: the same sentences without values that
```

Line 23:

```text
drift between samples (percentages, sizes, rates, ages).
```

Line 39:

```text
A drifting value: kept in full text, dropped from the reprint key.
```

Line 127:

```text
Header and one view, as printed.
```

Line 252:

```text
The tree reorders by CPU every sample; only its roots are facts.
```

Line 493:

```text
Resolve a service by exact name, full id or id prefix.
```

Line 521:

```text
What a typed line asks for.
```

Line 528:

```text
Text to print, nothing to send.
```

Line 671:

```text
The interactive line loop. Returns the process exit code.
```

Line 733:

```text
Without input the client keeps reporting changes, like a monitor.
```

Line 809:

```text
Box drawing, block elements and geometric shapes.
```

## rust/fleet-tui/src/runtime.rs

Line 1:

```text
The full-screen event loop.
```

Line 3:

```text
One channel carries everything that can change the screen: terminal
```

Line 4:

```text
events from an input thread blocked in `crossterm::event::read`, and wake
```

Line 5:

```text
notes from the controller and telemetry workers. The loop blocks on that
```

Line 6:

```text
channel. It wakes for input, for new data (the workers' generation
```

Line 7:

```text
counters), for the log tail's next two-second read while the tail is open,
```

Line 8:

```text
and for the moment a live feed would turn stale. There is no clock and no
```

Line 9:

```text
periodic redraw.
```

Line 32:

```text
How often the open log tail asks for the end of the log.
```

Line 34:

```text
Upper bound on a blocking wait, so a missed wake cannot leave the screen
```

Line 35:

```text
unchanged indefinitely.
```

Line 50:

```text
A wake note for the workers. A full channel already holds a pending
```

Line 51:

```text
wake, so a failed send loses nothing.
```

Line 59:

```text
Block until the controller has answered once and telemetry has two
```

Line 60:

```text
samples (CPU needs two), or until `limit` passes.
```

Line 140:

```text
Raw mode, alternate screen and optional mouse capture, undone on drop and
```

Line 141:

```text
on panic so a crash never leaves the terminal unusable.
```

Line 178:

```text
Read or request the tail's log text. Returns whether anything changed and
```

Line 179:

```text
when the next read is due, if one is.
```

Line 201:

```text
The stream switched while this read was in flight.
```

Line 228:

```text
When a live feed would turn stale with no new data.
```

Line 341:

```text
Handle this message and anything else already queued before drawing.
```

Line 435:

```text
Not due yet: nothing is sent.
```

## rust/fleet-tui/src/source.rs

Line 1:

```text
Where the dashboard's inputs come from: the controller and telemetry
```

Line 2:

```text
workers from `fleet-ui-core`, or, in fixture builds, synthetic feeds with no
```

Line 3:

```text
threads and no socket.
```

Line 13:

```text
The tail pane shows the end of a log; this bounds each read and the copy
```

Line 14:

```text
the controller's outcome history keeps of it.
```

Line 27:

```text
Pending and finished actions without log reads, recomputed only
```

Line 28:

```text
when the controller generation changes.
```

Line 68:

```text
Changes whenever anything the dashboard reads changes.
```

Line 81:

```text
Feeds as they stand, for deciding when to wake for a stale transition.
```

Line 184:

```text
Queue an action with `fleetctl` semantics. Fixture mode refuses.
```

## rust/fleet-tui/src/tests.rs

Line 1:

```text
Rendering tests over every fixture scenario, view and size.
```

Line 17:

```text
Rules from the workstation UI baseline that apply to terminal text.
```

Line 120:

```text
Meaning survives without color: states are words.
```

## rust/fleet-tui/src/theme.rs

Line 1:

```text
The phosphor palette from `design/tokens.json`, reduced to what the
```

Line 2:

```text
terminal can show.
```

Line 4:

```text
Truecolor terminals get the token colors; 256-color terminals the nearest
```

Line 5:

```text
xterm-256 index from the color cube or gray ramp (indices 0 to 15 vary by
```

Line 6:

```text
terminal theme, so they are never chosen); 16-color terminals the `ansi16`
```

Line 7:

```text
indices from the tokens. With no color, emphasis is bold, dim and reverse
```

Line 8:

```text
video, and every state also has a word, so nothing depends on color.
```

Line 23:

```text
`env` reads one environment variable; empty values count as unset.
```

Line 49:

```text
The nearest xterm-256 index for a color, from the 6x6x6 cube (16 to 231)
```

Line 50:

```text
and the gray ramp (232 to 255), by squared RGB distance.
```

Line 79:

```text
What a piece of text means; the theme decides how that looks.
```

Line 100:

```text
Applied to the whole screen. Empty in 16-color and no-color modes so the
```

Line 101:

```text
terminal's own background stays.
```

Line 210:

```text
Band styles from the design package: dark green, bright green, amber, red.
```

Line 220:

```text
Every style this theme can produce, for tests.
```

Line 291:

```text
An empty NO_COLOR does not disable color.
```

Line 307:

```text
#55ff55 sits between cube levels 95 and 255 on red and blue.
```

Line 310:

```text
A mid gray prefers the gray ramp.
```

## rust/fleet-tui/src/ui.rs

Line 1:

```text
The full-screen renderer. Draws one frame from the dashboard and the
```

Line 2:

```text
interface state; owns no state of its own. Returns the geometry the mouse
```

Line 3:

```text
handler needs (tab positions, the selectable list's rows and scroll offset).
```

Line 22:

```text
Below this width every view uses one column.
```

Line 35:

```text
The rows region, header excluded.
```

Line 134:

```text
Header text in priority order. When the row is too narrow, the awaiting
```

Line 135:

```text
count goes first (the Agents and Attention views repeat it), then the
```

Line 136:

```text
version's prefix, then the remote marker, then the version. Read-only and
```

Line 137:

```text
the connection phase always stay.
```

Line 143:

```text
"services disconnected" repeats the phase; only a live count is shown.
```

Line 245:

```text
The connection banner: present whenever the controller feed is not live,
```

Line 246:

```text
and when local telemetry is not live.
```

Line 324:

```text
Render a selectable table and report where its rows landed.
```

Line 413:

```text
The local machine panel only when the agents list still gets room.
```

Line 426:

```text
Cluster: summary line and one selectable row per node.
```

Line 545:

```text
Needs attention: the most severe reports; actions live in view 6.
```

Line 585:

```text
Active agents.
```

Line 634:

```text
Rows in the local machine panel: five gauges and the CPU history.
```

Line 638:

```text
This machine's own telemetry, read by this client: the popover's quick
```

Line 639:

```text
view in terminal form.
```

Line 735:

```text
Requests this client sent: in flight first, then the latest outcomes.
```

Line 773:

```text
Rows a wrapped paragraph needs, estimated from line widths (word wrapping
```

Line 774:

```text
can need one more row per line; callers leave room or clip).
```

Line 978:

```text
"running, unverified" in full.
```

Line 1110:

```text
The full reason is in the detail pane.
```

Line 1622:

```text
A read-only client sends nothing that changes state; do not offer it.
```

Line 1629:

```text
Drop hints until the row fits: navigation first (the help lists it),
```

Line 1630:

```text
then the view's actions from the last; `?` and `q` always stay.
```

## rust/fleet-ui-core/Cargo.toml

Line 10:

```text
Synthetic snapshots for tests, documentation captures and screenshots. Release
```

Line 11:

```text
builds never enable it; `Scripts/verify-rust-clients.sh` checks the shipped
```

Line 12:

```text
binaries for the fixture marker.
```

## rust/fleet-ui-core/src/controller.rs

Line 1:

```text
The controller connection both clients use.
```

Line 3:

```text
Two background threads, each opening a fresh connection per request: a
```

Line 4:

```text
poller that reads `snapshot` on a fixed interval, and an action worker that
```

Line 5:

```text
runs operator requests one at a time from a bounded queue. Every request
```

Line 6:

```text
carries a deadline and a response byte limit through
```

Line 7:

```text
`fleet_proto::Client::send_bounded`, so a stalled or oversized controller
```

Line 8:

```text
reply ends as an error instead of a frozen client or unbounded memory.
```

Line 10:

```text
The render thread only reads shared state behind a mutex and a generation
```

Line 11:

```text
counter. Nothing here signals a process: every action is a controller
```

Line 12:

```text
request with the same semantics as the matching `fleetctl` command, and the
```

Line 13:

```text
controller keeps enforcing owner, lease and start-identity checks.
```

Line 15:

```text
Polling, not `subscribe`: a snapshot every two seconds costs one local
```

Line 16:

```text
socket round trip and one JSON decode, which the idle measurements in
```

Line 17:

```text
docs/CROSS-PLATFORM.md show is within budget. Subscriptions are added to
```

Line 18:

```text
`fleet-proto` only if that measurement stops holding.
```

Line 42:

```text
Clamped to 1 to 60 seconds.
```

Line 44:

```text
Deadline for `snapshot`, `logs`, `events` and `reply`.
```

Line 46:

```text
Deadline for `stop` and `restart`, which wait out the controller's
```

Line 47:

```text
grace period before answering.
```

Line 51:

```text
Refuse every mutating action in the client. Logs and events still work.
```

Line 74:

```text
Three missed polls plus one request deadline. Past this, a value that
```

Line 75:

```text
was live is shown as stale even though no error was reported.
```

Line 96:

```text
An operator request. Each maps to exactly one controller operation.
```

Line 115:

```text
Answer an agent's question. Approve and deny are replies whose text the
```

Line 116:

```text
agent reads; the controller records it once and never rewrites it.
```

Line 136:

```text
Stop ends work and restart interrupts it; pause holds resources while
```

Line 137:

```text
doing nothing. Each is confirmed before it is sent.
```

Line 310:

```text
A copy of the feed. The snapshot itself is shared, not cloned.
```

Line 323:

```text
Increments whenever the feed, the pending list or an outcome changes.
```

Line 332:

```text
Queue an action. Refused in read-only mode for mutating actions, and
```

Line 333:

```text
when the bounded queue is full rather than growing without limit.
```

Line 364:

```text
Actions queued or in flight, oldest first.
```

Line 373:

```text
The most recent outcomes, newest last, at most 64.
```

Line 396:

```text
Blocking sends are bounded: each worker drains its queue promptly,
```

Line 397:

```text
and an in-flight request ends at its own deadline.
```

Line 453:

```text
Show the controller's new state now, not at the next tick.
```

Line 459:

```text
How one read ended, before it is folded into a feed.
```

Line 599:

```text
Replace the home directory with `~` so a socket path can appear on screen
```

Line 600:

```text
and in captures without naming the account.
```

Line 636:

```text
A one-request controller stand-in answering with `reply`.
```

Line 643:

```text
The client may hang up early on an oversized reply; that is the
```

Line 644:

```text
behavior under test, not a server failure.
```

## rust/fleet-ui-core/src/fixtures.rs

Line 1:

```text
Synthetic controller snapshots and host samples.
```

Line 3:

```text
Compiled only for tests and with the `fixtures` feature, which capture and
```

Line 4:

```text
screenshot builds enable and release builds do not. Every name, pid, path
```

Line 5:

```text
and number here is invented. The controller version is `MARKER`, so a
```

Line 6:

```text
capture made from fixtures says so on screen, and a release binary that
```

Line 7:

```text
contains the marker string has fixtures compiled in and fails the check in
```

Line 8:

```text
`Scripts/verify-rust-clients.sh`.
```

Line 18:

```text
The fixed clock fixtures are built around: 2027-01-15 09:20 UTC.
```

Line 32:

```text
Far more rows than any list keeps, to exercise the bounds.
```

Line 283:

```text
A host sample; `seed` varies the numbers for history.
```

## rust/fleet-ui-core/src/format.rs

Line 1:

```text
Text forms shared by both clients. Unavailable values render as `--`.
```

Line 45:

```text
`3d 4h`, `14m`, `42s`. Two units at most, matching `Fmt.duration` in Swift.
```

Line 63:

```text
`12s ago`, `4m ago`; `in 20m` for a future time such as a lease expiry.
```

Line 86:

```text
Clip to a display width in characters, never splitting a code point.
```

## rust/fleet-ui-core/src/lib.rs

Line 1:

```text
What the FleetConsole terminal and GPUI clients share.
```

Line 3:

```text
Both clients are views over the same two feeds: the controller's snapshot,
```

Line 4:

```text
read through `fleet-proto`, and this machine's own telemetry, read through
```

Line 5:

```text
the platform module. Everything a client renders is derived here so the two
```

Line 6:

```text
cannot disagree about a number, a threshold or whether a value exists.
```

Line 8:

```text
The honesty rules from the Swift app carry over unchanged. A value that was
```

Line 9:

```text
not observed is `Metric::Unavailable`, never zero. Process existence,
```

Line 10:

```text
listening ports, reachability and a configured health check stay separate
```

Line 11:

```text
facts. Every feed reports loading, live, stale, disconnected or error, and a
```

Line 12:

```text
client renders that phase rather than guessing.
```

Line 14:

```text
Nothing in this crate blocks the caller's thread on a socket or a process
```

Line 15:

```text
scan: `controller::Controller` and `platform::TelemetryWorker` own background
```

Line 16:

```text
threads with bounded queues, bounded payloads and bounded history.
```

## rust/fleet-ui-core/src/map.rs

Line 1:

```text
The relational map: one graph joining the controller, the devices it
```

Line 2:

```text
serves, the services it supervises, the agents it routes for, the local
```

Line 3:

```text
process tree and the mounted volumes, with the needs-attention reports
```

Line 4:

```text
pinned on the node they are about.
```

Line 6:

```text
Like `views::Dashboard::build`, this is a pure function of a dashboard.
```

Line 7:

```text
Every value on a node comes from a feed that measured it; when a feed is
```

Line 8:

```text
loading, stale or disconnected, its group is left out and the note says so
```

Line 9:

```text
instead of an estimated or simulated value. The layout is deterministic:
```

Line 10:

```text
the same dashboard always produces the same coordinates, and neither the
```

Line 11:

```text
model nor the window has an animation loop.
```

Line 18:

```text
Most linked devices drawn; the note names the rest.
```

Line 20:

```text
Most services drawn; sorted by worst CPU, so the busy ones always win.
```

Line 22:

```text
Most processes drawn; the local tree's heaviest rows first, plus every row
```

Line 23:

```text
a drawn service owns through its pid.
```

Line 25:

```text
Most volumes drawn; the least headroom first.
```

Line 27:

```text
Most reports pinned on one node; the rest collapse into a "+k more" line.
```

Line 29:

```text
Force-layout steps applied once per build. With the bounded node count
```

Line 30:

```text
this stays well under a millisecond, so a rebuild never lags.
```

Line 32:

```text
Map radius in map units; the renderer scales this to the viewport.
```

Line 58:

```text
Why an edge exists, in the words the legend uses.
```

Line 61:

```text
A linked device the controller reports on.
```

Line 63:

```text
The controller supervises a managed service.
```

Line 65:

```text
The controller routes agent turns and answers.
```

Line 67:

```text
A mounted volume the local machine reads and writes.
```

Line 69:

```text
A service or the controller owns this process by pid.
```

Line 71:

```text
One local process started another.
```

Line 88:

```text
A health report pinned on the node it is about.
```

Line 95:

```text
What can be done through the controller, as `AttentionRow` words it.
```

Line 101:

```text
Stable across rebuilds, in `kind:identity` form, used for selection.
```

Line 105:

```text
One honest secondary line: what was measured, or why nothing was.
```

Line 107:

```text
CPU as the heat of the node, measured only where a feed measured it.
```

Line 109:

```text
The node's worst reported band.
```

Line 111:

```text
Whether the node's feed is live, stale or disconnected. Devices age.
```

Line 114:

```text
Reports beyond `MAX_BADGES_PER_NODE`, so a "+k more" line is exact.
```

Line 116:

```text
Layout coordinates in map units, roughly -`MAP_RADIUS`..`MAP_RADIUS`.
```

Line 119:

```text
Layout velocity, used only inside one build's settle steps.
```

Line 129:

```text
Relative activity for strokes: the target's CPU fraction when it was
```

Line 130:

```text
measured, `None` when it was not.
```

Line 136:

```text
In drawing order: controller, devices, services, agents, processes,
```

Line 137:

```text
volumes. Selection indexes into this list.
```

Line 140:

```text
Lines about groups that are not drawn and why, in feed words.
```

Line 150:

```text
The controller at the center. Its heat is the local device tile's
```

Line 151:

```text
CPU, so the map's center is honest about the machine it runs on.
```

Line 191:

```text
Linked devices other than the local one, which is the center.
```

Line 240:

```text
Services, busiest CPU first so the map keeps the active ones when a
```

Line 241:

```text
controller manages more than the bound. When the controller feed is
```

Line 242:

```text
not live, its rows are last read, which the node's freshness says.
```

Line 284:

```text
Agents, routed by the controller. Their state and runtime are the
```

Line 285:

```text
transcript's words; no CPU is invented for them. Two sessions can
```

Line 286:

```text
share a name, so the id carries the target and, still with a
```

Line 287:

```text
collision, a stable ordinal.
```

Line 324:

```text
The local process tree, reduced to the rows worth drawing. A line a
```

Line 325:

```text
drawn service owns by pid keeps that edge; the rest hang from their
```

Line 326:

```text
nearest drawn ancestor or, without one, from the controller.
```

Line 356:

```text
A drawn service's process row must exist, or its "owns" edge
```

Line 357:

```text
would point at nothing.
```

Line 437:

```text
Volumes, least headroom first, only while storage telemetry is live.
```

Line 481:

```text
Needs-attention reports pinned on the node they name. A report with
```

Line 482:

```text
a service id pins to that service; the rest pin on the controller,
```

Line 483:

```text
where the operator starts from anyway.
```

Line 538:

```text
Keys the window's selection state uses for the map's rows.
```

Line 543:

```text
The number of pinned reports, including the overflowed ones.
```

Line 551:

```text
One force step: repulsion between every pair, springs along edges and
```

Line 552:

```text
a small pull toward the center. The controller stays at the center.
```

Line 567:

```text
Two nodes on the same spot are unseparated along no axis;
```

Line 568:

```text
give them a deterministic axis instead of dividing by zero.
```

Line 623:

```text
Speed clamp, in map units per settle step, so the bounded loop always
```

Line 624:

```text
settles instead of oscillating into floating-point overflow.
```

Line 626:

```text
Position clamp in map units; larger excursions cannot happen.
```

Line 648:

```text
The zero-based slot of a node within its kind group.
```

Line 656:

```text
A deterministic starting template, one group per arc around the center.
```

Line 723:

```text
Which pids a drawn process was started by, from the depth-first tree the
```

Line 724:

```text
process view already ordered and clipped. A line's parent is the most
```

Line 725:

```text
recent open line at the depth above it.
```

Line 748:

```text
`name@target`, with an ordinal when a controller runs two sessions of one
```

Line 749:

```text
name, so selection keys and edges stay unique.
```

Line 878:

```text
Local telemetry is independent of the controller, so the process
```

Line 879:

```text
tree and volumes are still drawn from the local feeds.
```

Line 884:

```text
The selection list has one entry per node and starts at the center.
```

Line 896:

```text
The healthy fixture carries two sessions named codex-3; the ids
```

Line 897:

```text
must differ without inventing state.
```

## rust/fleet-ui-core/src/model.rs

Line 1:

```text
The controller snapshot, typed.
```

Line 3:

```text
`fleet-proto` keeps the snapshot as opaque JSON so a half-modelled record
```

Line 4:

```text
cannot silently drop fields on the conformance path. The clients need typed
```

Line 5:

```text
access, so this module models exactly the fields they render, decoded the way
```

Line 6:

```text
Swift's `Codec` writes them: dates are epoch seconds, absent optionals are
```

Line 7:

```text
`None`, and keys keep Swift's spelling (`serviceID`, `memMB`, `leaseTTLSec`).
```

Line 8:

```text
Unknown enum values decode to `Unknown` so a newer controller does not take
```

Line 9:

```text
the whole client down; a missing required field is a decode error that the
```

Line 10:

```text
client reports, never a default.
```

Line 40:

```text
Everything not finished, including an expired lease still being reported.
```

Line 45:

```text
Actually up. This is what a count worded "running" shows, matching
```

Line 46:

```text
`Snapshot.runningServices` in Swift.
```

Line 102:

```text
The word a row shows. `running` without a health check is unverified,
```

Line 103:

```text
which is what the Swift app calls it too.
```

Line 122:

```text
Four separate facts. Never collapse them into one boolean.
```

Line 235:

```text
Observed listeners when a scan found any, otherwise what was declared.
```

Line 244:

```text
A claimed process is visible, not signallable. The controller refuses
```

Line 245:

```text
stop, restart, pause and kill for it; the clients disable those controls
```

Line 246:

```text
with the same reason instead of sending a request that will fail.
```

Line 298:

```text
Kept as the raw Swift case name; the clients show it, nothing branches on it.
```

Line 387:

```text
The project folder's last component, never the full path: the full
```

Line 388:

```text
path carries a home directory and does not belong on screen captures.
```

Line 481:

```text
A linked device. Host and address fields exist on the wire; they are not
```

Line 482:

```text
modelled because neither client displays them.
```

Line 502:

```text
Same rule as `DeviceRecord.health` in Swift: reachability is claimed only
```

Line 503:

```text
when a probe succeeded, and no completed probe is unknown, not down.
```

Line 538:

```text
Decode the opaque snapshot `fleet-proto` returns.
```

## rust/fleet-ui-core/src/observe.rs

Line 1:

```text
Honest state: a value that exists, or the reason it does not.
```

Line 6:

```text
Why a value is not shown. Each reason has its own wording because "this
```

Line 7:

```text
platform cannot measure it" and "the controller is down" call for different
```

Line 8:

```text
actions from the person reading the screen.
```

Line 11:

```text
No source for this value exists on this operating system.
```

Line 13:

```text
The first interval has not elapsed; rates and CPU need two samples.
```

Line 15:

```text
The node is offline; the last value is no longer current.
```

Line 17:

```text
The controller is unreachable, so nothing it reports is current.
```

Line 19:

```text
The read was attempted and failed.
```

Line 68:

```text
Clamp a percentage for drawing. The unclamped value is still what the
```

Line 69:

```text
label shows, so an over-100 reading is visible rather than hidden.
```

Line 75:

```text
Where a feed is. Clients render this before they render any value.
```

Line 78:

```text
No attempt has finished.
```

Line 80:

```text
The latest attempt succeeded within the freshness window.
```

Line 82:

```text
A value exists but is older than the freshness window.
```

Line 84:

```text
The socket is missing or refused the connection.
```

Line 86:

```text
The controller answered with an error, timed out, or sent something
```

Line 87:

```text
that did not decode or exceeded the size limit.
```

Line 102:

```text
Values may be shown as current only when live.
```

Line 108:

```text
A value read in the background plus everything needed to say how current it is.
```

Line 112:

```text
The last value that decoded. Retained across failures so a client can
```

Line 113:

```text
show it as last-known, never as current.
```

Line 116:

```text
Error or disconnection detail for the current phase.
```

Line 118:

```text
Successful reads since start, for diagnostics.
```

Line 135:

```text
Re-evaluate staleness against a clock. Workers record outcomes; the age
```

Line 136:

```text
check happens at render time so a hung worker shows up as stale.
```

## rust/fleet-ui-core/src/platform/linux.rs

Line 1:

```text
Linux specifics.
```

Line 100:

```text
amdgpu exposes `gpu_busy_percent`; take the busiest card. Other drivers do
```

Line 101:

```text
not publish a comparable counter in sysfs, so they stay unavailable.
```

## rust/fleet-ui-core/src/platform/macos.rs

Line 1:

```text
macOS specifics.
```

Line 59:

```text
Wi-Fi and wired links are `en*`. Tunnels (`utun*`), AirDrop (`awdl*`) and
```

Line 60:

```text
bridges are excluded, matching the Swift app's physical-interface rule.
```

## rust/fleet-ui-core/src/platform/mod.rs

Line 1:

```text
What differs between macOS and Linux, behind one interface.
```

Line 3:

```text
Telemetry is sampled with `sysinfo` on both systems, plus the few sources it
```

Line 4:

```text
does not cover (Linux GPU busy time from sysfs). Every value a source cannot
```

Line 5:

```text
provide is `Metric::Unavailable(Reason::NotMeasured)`, and `capabilities()`
```

Line 6:

```text
states which values are measured on the running system so a client or a
```

Line 7:

```text
document can say so in words. Paths, notifications and the status-area item
```

Line 8:

```text
are here too, because each has a macOS and a Linux answer.
```

Line 33:

```text
Process rows kept per sample, highest CPU first. A process tree needs
```

Line 34:

```text
parents, so this is generous, but it is a bound.
```

Line 36:

```text
Volumes kept per sample.
```

Line 38:

```text
Samples of history kept for sparklines, matching `ServiceRecord.historyLimit`.
```

Line 45:

```text
Executable name only. Arguments are never collected: they carry paths,
```

Line 46:

```text
tokens and hostnames that do not belong on a screen capture.
```

Line 48:

```text
Percent of one core, as `ps` reports it; can exceed 100.
```

Line 77:

```text
One reading of this machine.
```

Line 87:

```text
The volume that holds user data: `/System/Volumes/Data` on macOS when
```

Line 88:

```text
present, otherwise `/`.
```

Line 98:

```text
The last `HISTORY` readings, oldest first, filled by `TelemetryWorker`.
```

Line 99:

```text
`None` marks an interval with no measurement, which a chart leaves blank.
```

Line 105:

```text
Something that can read this machine. The real implementation is
```

Line 106:

```text
`Sampler`; tests substitute recorded samples.
```

Line 121:

```text
Measured only on some hardware; the sample says which.
```

Line 132:

```text
What this build measures on the running operating system.
```

Line 137:

```text
Bounded rings of recent readings.
```

Line 163:

```text
Background sampling. The render thread reads the latest sample; it never
```

Line 164:

```text
waits for a process scan.
```

Line 246:

```text
The controller socket this client connects to by default. See
```

Line 247:

```text
`fleet_proto::default_socket_path` for the override order.
```

Line 252:

```text
Whether a status-area item can be shown, and if not, why.
```

Line 255:

```text
macOS menu bar status item.
```

Line 257:

```text
A StatusNotifierItem host is registered on the session bus.
```

Line 259:

```text
No host is available; the client runs as an ordinary window.
```

Line 267:

```text
Post a desktop notification through the system's own tool. Returns the
```

Line 268:

```text
reason when none exists rather than failing silently.
```

Line 280:

```text
Run a short command with a hard deadline, returning stdout on success.
```

## rust/fleet-ui-core/src/platform/sampler.rs

Line 1:

```text
`sysinfo`-backed sampling shared by macOS and Linux.
```

Line 50:

```text
CPU use is a difference between two readings; the first has none.
```

Line 163:

```text
No physical link is a fact worth showing, not a zero rate.
```

## rust/fleet-ui-core/src/theme.rs

Line 1:

```text
Design tokens from `design/tokens.json`, the one source for the terminal
```

Line 2:

```text
palette, the GPUI theme and `design/tokens.css`.
```

Line 4:

```text
The JSON is compiled into the binary and parsed once. A test renders the
```

Line 5:

```text
CSS from the same file and fails when `design/tokens.css` has drifted;
```

Line 6:

```text
`FLEET_WRITE_TOKENS=1` rewrites it instead.
```

Line 22:

```text
`0xRRGGBB`, the form `gpui::rgb` takes.
```

Line 66:

```text
The design package's band colors: dark green, bright green, amber, red.
```

Line 77:

```text
ANSI 16-color indices for terminals without truecolor or 256 colors.
```

Line 78:

```text
`None` means the terminal's own default foreground or background.
```

Line 131:

```text
The dark terminal palette from the design package.
```

Line 133:

```text
The light appearance for the GPUI window, contrast-checked against
```

Line 134:

```text
`bg` (see the tests below).
```

Line 136:

```text
The dark glass appearance for the GPUI window: a near-black substrate
```

Line 137:

```text
with a vibrant level ramp. The bands stay a heat ladder — green,
```

Line 138:

```text
yellow, orange, red — so the words normal, elevated, warning and
```

Line 139:

```text
critical keep naming the same hues.
```

Line 149:

```text
`design/tokens.css`, rendered from the tokens.
```

## rust/fleet-ui-core/src/thresholds.rs

Line 1:

```text
The 50/70/90 percent bands from the design package.
```

Line 3:

```text
Dark green to 50, bright green 50 to 70, amber 70 to 90, red above 90. Color
```

Line 4:

```text
is never the only signal: every band has a word, and a tile's word comes from
```

Line 5:

```text
its worst measured gauge.
```

Line 30:

```text
`None` when the metric was not measured: an unmeasured gauge has no band.
```

Line 45:

```text
The text state a node tile carries next to its border color.
```

Line 52:

```text
Reachable, but it reported no measurements to judge.
```

Line 81:

```text
Lit cells for a segmented gauge, and the band of each lit cell. Segment i
```

Line 82:

```text
is colored by its own position, so a 95% bar shows all four bands.
```

## rust/fleet-ui-core/src/views.rs

Line 1:

```text
Everything a client draws, derived from the two feeds.
```

Line 3:

```text
`Dashboard::build` is a pure function of its inputs: the controller feed,
```

Line 4:

```text
the telemetry feed, the pending and finished actions, and a clock. Both
```

Line 5:

```text
clients call it on each change and render the result, so the terminal and
```

Line 6:

```text
the window cannot disagree about a count, a band or an unavailable value.
```

Line 7:

```text
It allocates a few hundred rows at most; every list has a bound.
```

Line 31:

```text
The reply text sent when the operator approves or denies an agent question.
```

Line 32:

```text
The agent reads it with `fleetctl inbox`.
```

Line 44:

```text
Socket path as it may be shown, home directory already replaced.
```

Line 46:

```text
Force the remote interpretation even when a local `fleetd` with the
```

Line 47:

```text
controller's pid exists.
```

Line 69:

```text
One sentence a person can act on.
```

Line 75:

```text
Whether the controller supervises this machine. When it does not (an
```

Line 76:

```text
SSH-forwarded socket from another machine), its pids are not joined
```

Line 77:

```text
with local processes.
```

Line 85:

```text
A local process with the controller's pid is named `fleetd`.
```

Line 87:

```text
No such local process; the controller runs elsewhere.
```

Line 89:

```text
Not decided yet: no snapshot or no local process sample.
```

Line 121:

```text
Accessible description: label, value and the reason when unavailable.
```

Line 133:

```text
20 cells, a 5 by 4 grid in reading order; `Some` cells are used space.
```

Line 142:

```text
Bar length relative to the highest rate in the retained history.
```

Line 172:

```text
Network rate text for the `net` row; the percent gauge needs a link
```

Line 173:

```text
capacity that is not measured.
```

Line 206:

```text
Why a control is unavailable for a row. Clients show this text instead of
```

Line 207:

```text
sending a request that the controller would refuse.
```

Line 237:

```text
The four separate facts, in words.
```

Line 295:

```text
Set for a question still awaiting an answer.
```

Line 327:

```text
The per-path breakdown the Swift app scans is not implemented in the
```

Line 328:

```text
Rust clients; this says so instead of showing an empty list.
```

Line 355:

```text
Where the report came from: the controller, or this client's own telemetry.
```

Line 359:

```text
What can be done through the controller, in words.
```

Line 361:

```text
The read-only commands an agent would run to investigate this target.
```

Line 730:

```text
An offline node keeps its last disk reading: disk does not change while
```

Line 731:

```text
it is down, and the design labels it last-known.
```

Line 992:

```text
Roots come from the controller only when it supervises this machine;
```

Line 993:

```text
a remote controller's pids name processes on another host.
```

Line 1151:

```text
UTC wall time. A local time zone needs a database this crate does not
```

Line 1152:

```text
carry; the clients label the column so it is not mistaken for local.
```

## rust/ouros-adapter/src/lib.rs

Line 1:

```text
Ouros-X brain adapter compatibility and bridge module.
```

Line 3:

```text
Ingests:
```

Line 4:

```text
- Agent task graphs and state machine transitions
```

Line 5:

```text
- Context memory allocation vs system RAM
```

Line 6:

```text
- Token budgets and consumption velocity
```

Line 7:

```text
- Decision logs and rationales
```

Line 114:

```text
"Subagent", "Dependency", "IpcChannel", "DataFlow"
```

Line 135:

```text
Ingestion interface for communicating with the Ouros-X brain adapter.
```

Line 146:

```text
Standard bridge module maintaining active state from Ouros-X runtime.
```

## work/native-auth-shell.cjs

Line 5:

```text
The approved login document owns artwork, layout, typography and controls.
```

Line 6:

```text
This adapter supplies only the already validated native authorization forms.
```

Line 19:

```text
Keep the server's hidden PKCE/state/redirect fields byte-for-byte.
```

Line 39:

```text
Ordinary account scripts redirect to Dashboard. Native forms retain
```

Line 40:

```text
their existing server-owned POST and callback/consent flow.
```

Line 87:

```text
Native consent submits a same-origin HTML form. no-referrer would make
```

Line 88:

```text
its Origin null, so the existing CSRF guard could not admit the POST.
```

Line 89:

```text
The callback/consent redirect response retains its no-referrer policy.
```
