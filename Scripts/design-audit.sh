#!/bin/bash
# Checks the view layer against the rules at the bottom of docs/DESIGN-SYSTEM.md.
#
# Those rules exist because the first build accumulated ~130 literal font sizes
# across twelve values and four separate row implementations that had each drifted
# apart by a point here and a pixel there. A written rule does not stop that; the
# sediment came back the moment nobody was counting. This counts.
#
#   Scripts/design-audit.sh            # report, exit 0 unless a hard rule broke
#   Scripts/design-audit.sh --strict   # any finding, including budgets, fails
#
# Hard rules fail the build. Budgeted rules print a number you have to argue with:
# they cover legitimate one-offs (a chart's plot inset, a glyph's optical nudge)
# mixed in with real drift, so the honest signal is "this got worse", not "zero".
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIEWS="$ROOT/Sources/FleetConsoleApp/Views"
DESIGN="$ROOT/Sources/FleetConsoleApp/Design"
DOCS="$ROOT/docs"
MODULES="$DESIGN/ConsoleModule.swift"
TOOLSRC="$VIEWS/Console/Chrome/ToolSurface.swift"
STRICT=0
[[ "${1:-}" == "--strict" ]] && STRICT=1

hard_fail=0
soft_fail=0

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
dim()  { printf '\033[2m%s\033[0m\n' "$1"; }

# hard <name> <explanation> <grep-args...>
hard() {
  local name="$1" why="$2"; shift 2
  local hits; hits="$("$@" 2>/dev/null)"
  local n; n="$(printf '%s' "$hits" | grep -c . || true)"
  if [[ "$n" -eq 0 ]]; then
    printf '  \033[32m✓\033[0m %s\n' "$name"
  else
    printf '  \033[31m✗\033[0m %s \033[31m(%s)\033[0m\n' "$name" "$n"
    dim "      $why"
    printf '%s\n' "$hits" | sed 's|'"$ROOT"'/||' | sed 's/^/      /'
    hard_fail=$((hard_fail + 1))
  fi
}

# budget <name> <allowed> <explanation> <grep-args...>
budget() {
  local name="$1" allowed="$2" why="$3"; shift 3
  local n; n="$("$@" 2>/dev/null | grep -c . || true)"
  if [[ "$n" -le "$allowed" ]]; then
    printf '  \033[32m✓\033[0m %s \033[2m(%s, budget %s)\033[0m\n' "$name" "$n" "$allowed"
  else
    printf '  \033[33m!\033[0m %s \033[33m(%s, budget %s)\033[0m\n' "$name" "$n" "$allowed"
    dim "      $why"
    soft_fail=$((soft_fail + 1))
  fi
}

bold "Rule 3 — status colour comes from StatusTone, never inline"
# The literal rule from the doc. A bare system hue in a view is either a status
# the vocabulary already owns, or a category that deserves its own token.
# StorageCategory and TelemetrySeries are those tokens, so Design/ is exempt.
#
# The first version anchored every hue to a call site — `Color.green`,
# `fill(.green)`, `tint(.green)` — which is the shape a hue takes when it is
# written where it is used. It is not the shape it takes when a view factors the
# choice out into a computed property, and `InterpreterPanel.captionColor` did
# exactly that: `case .available: return .green.opacity(0.85)`. Two inline hues
# encoding "is the local model installed", green and orange, invisible to this
# check for as long as it existed, because no anchor preceded the dot. Type
# inference is the whole point of that spelling, so the anchor set now includes
# the positions a bare leading dot can appear in — after `return`, after `=`,
# and in either arm of a ternary.
#
# Comment lines are dropped, because widening the anchors made the rule match the
# prose that explains it — a check that fails on its own documentation teaches
# people to stop writing the documentation.
hard "no inline system hues in view code" \
     "Route through StatusTone, or add a named token beside StorageCategory/TelemetrySeries." \
     bash -c '
       grep -rnE "(Color\.|foregroundStyle\(\.|foregroundColor\(\.|fill\(\.|tint\(\.|return \.|= \.|\? \.|: \.)(green|red|orange|yellow|purple|pink|teal|indigo|mint|cyan|brown)\b" \
         --include="*.swift" "'"$VIEWS"'" \
       | grep -vE "^[^:]+:[0-9]+: *(//|\*)"'

bold "Rule 11 — no opacity literals on a colour in view code"
# The same sediment as the font sizes, in colour. An audit of the view layer
# found a tone used at NINE strengths — 0.07 and 0.08 and 0.10 for one row wash,
# 0.12 and 0.13 and 0.14 and 0.16 for one chip fill, plus 0.35 and 0.75 — and
# `Color.primary` at SEVEN — 0.04, 0.06, 0.7, 0.75, 0.8, 0.85, 0.9 — across
# eleven files, for what turned out to be four tone jobs and six achromatic ones.
# Nobody chose those numbers; each was typed once beside whatever was already on
# screen, which is exactly how 9pt and 9.5pt ended up meaning the same thing.
#
# The tokens are `StatusTone.wash/chipFill/edge/stroke` and `SurfaceInk`, exposed
# on both ramps as `FleetColor.*` and `ConsoleColor.*`. Design/ is exempt because
# that is where the numbers are supposed to be written down.
hard "no .opacity() on primary, secondary or a tone in view code" \
     "Use StatusTone.wash/chipFill/edge/stroke, or a SurfaceInk token via FleetColor/ConsoleColor." \
     bash -c '
       grep -rnE "(Color\.primary|Color\.secondary|\.primary|\.secondary|tone\.color|StatusTone\.[a-z]+\.color)\.opacity\(" \
         --include="*.swift" "'"$VIEWS"'" \
       | grep -vE "^[^:]+:[0-9]+: *(//|\*)"'

bold "Colour-only state encoding"
# A bare Circle/Capsule filled with a tone and no glyph, no label and no length
# carries its meaning in hue alone. Enclosed status symbols measure ~0.87
# silhouette IoU against each other at row size; bare verdict glyphs measure
# 0.24, which is why StatusTone.verdict exists.
hard "no bare shape filled straight from a tone colour" \
     "Use StatusTone.verdict, or put the state in adjacent text." \
     grep -rnE '(Circle|Capsule)\(\)[^\n]*\.(fill|foregroundStyle)\([^)]*tone\.color' \
     --include='*.swift' "$VIEWS" "$DESIGN"

bold "Rule 8 — tone.color fills, tone.ink writes"
# A tone hue as small text on its own 14% tint measures 1.98–2.95:1 in light
# mode. `ink` is the same hue moved toward the label colour by the solved
# minimum. Text and glyphs take ink; fills, bars and strokes keep color.
# Two earlier versions of this rule under-matched and each time the gap hid real
# sites: the first caught only bare `tone.color` and missed thirteen
# `StatusTone.warn.color`; the second was line-based and missed every ternary
# split across lines. This one slurps the file and matches the whole
# `foregroundStyle( … )` call, balanced one level deep, so spelling and line
# breaks cannot hide anything.
#
# The third version still under-matched, and for the third time the gap held real
# sites. It keyed on the *receiver* — `StatusTone.warn` or a variable literally
# spelled `tone` — so a tone that arrived from anywhere else was invisible:
# `cpuTone(row).color` on the Processes table's CPU column, `verdictTone.color`
# on the popover's verdict glyph, `SystemThresholds.thermal(…).color` in the
# Overview footer. Three tone hues writing text, on three of the surfaces most
# looked at, under a check reported green.
#
# So it no longer tries to recognise a tone. The invariant is total in the other
# direction: a fill uses `.fill()` or `.background()`, so **any** `.color` inside
# a `foregroundStyle` is a fill style doing the ink's job. The one exception is
# `TelemetrySeries`, and it is not really an exception — a Swift Charts `LineMark`
# has no `.fill`, and `foregroundStyle` is the only API for a mark's colour.
hard "no .color inside any foregroundStyle" \
     "Text and glyphs take tone.ink. Shapes take .fill(tone.color)." \
     bash -c '
       for f in $(find "'"$VIEWS"'" "'"$DESIGN"'" -name "*.swift"); do
         perl -0ne '"'"'while (/foregroundStyle\(((?:[^()]|\([^()]*\))*)\)/gs) {
              my $a = $1;
              next unless $a =~ /\.color\b/;
              next if $a =~ /\bTelemetrySeries\b/;
              my $n = 1 + substr($_, 0, pos($_)) =~ tr/\n//;
              $a =~ s/\s+/ /g;
              print "$ARGV:$n: foregroundStyle($a)\n"; }'"'"' "$f"
       done'

bold "Chips and numerals cannot wrap"
# A Tag or a port number in a row accessory competes for width against a title
# holding layoutPriority(1). Unconstrained it loses and compresses — truncating,
# or breaking mid-word one character per line. Both need lineLimit(1)+fixedSize.
hard "Tag pins its own width" \
     "Tag must keep .lineLimit(1) and .fixedSize()." \
     bash -c 'sed -n "/^struct Tag: View/,/^}/p" "'"$VIEWS"'/Components.swift" \
              | grep -q "fixedSize" || echo "Tag lost its .fixedSize()"'

# The same invariant, on the other element that sits in a row's trailing slot —
# and this is where it was actually broken. `FleetRowLabel.trailingText` is the
# timestamp / port / duration column, and it had `lineLimit(1)` and nothing else
# while `Tag`, six lines of argument and a check of its own, sat next to it in
# the same HStack. The surface sheet caught it: all three Needs-attention rows
# rendered their age as "12…", "2m a…" and a lone "1". One check per struct is
# how a rule ends up protecting the instance it was written against rather than
# the invariant it states.
hard "a row's trailing text pins its own width" \
     "FleetRowLabel's trailingText must keep .lineLimit(1) and .fixedSize()." \
     bash -c '
       # Anchored on a line that is only the modifier, so the paragraph of
       # comment above it explaining why fixedSize is there cannot satisfy the
       # check that it is there.
       sed -n "/if let trailingText/,/^            }/p" "'"$DESIGN"'/FleetRow.swift" \
       | grep -qE "^[[:space:]]*\.fixedSize\(\)[[:space:]]*$" \
         || echo "FleetRowLabel.trailingText lost its .fixedSize()"'

bold "Geometry containment"
# .offset() is a draw-time transform: it never changes the size a view reports.
# Offsetting a child inside a fixed frame therefore paints outside the parent's
# layout bounds — unreserved overflow that eats a neighbour's gap, and gets cut
# by any ancestor that bounds its content. EntityIcon's badge did exactly this,
# spilling 2.1–3.0pt at the four icon sizes the app uses.
hard "no .offset inside a fixed-size decorative stack" \
     "Anchor with a ZStack alignment instead, or reserve the space with padding." \
     grep -rnE '\.offset\(x: size \*|\.offset\(y: size \*' \
     --include='*.swift' "$VIEWS" "$DESIGN"

bold "Rule 1 — no literal type or metrics in view code"
# Only a bare numeral counts. `size * FleetMetrics.iconGlyphRatio` is a token
# scaled by its container, which is the pattern EntityIcon is built on.
budget "literal font sizes" 0 \
     "Add a token to FleetFont or ConsoleFont, or derive the size from one." \
     grep -rnE '(\.font\(\.system|Font\.system)\(size: *[0-9]' --include='*.swift' "$VIEWS"
budget "literal paddings" 101 \
     "Add a token to FleetMetrics or ConsoleMetrics. Was 101 at the time this audit was written." \
     grep -rnoE '\.padding\([^)]*[0-9][^)]*\)' --include='*.swift' "$VIEWS"
budget "literal frame dimensions" 25 \
     "Add a token to FleetMetrics or ConsoleMetrics. Was 25 at the time this audit was written." \
     grep -rnoE '\.frame\((width|height): [0-9]' --include='*.swift' "$VIEWS"

bold "Rule 13 — console metrics sit on the Fibonacci ladder"
# The tokens were ~25 independent judgement calls (236, 268, 280, 320, 88, 120,
# 260, 300, 14, 20, 12…), each defensible alone and none related to any other, so
# the set could not be checked — and it turned out not to hold: the column
# reserve summed to 786 against a 780pt minimum window. They are now rungs of
# `Scale.ladder`, and `ConsoleLayoutTests` asserts the budget they feed.
#
# This catches the other direction: a future edit typing a number *near* a rung.
# That is exactly how the 9pt/9.5pt font pair happened, and how 236 came to sit
# three points off 233 while claiming to be a considered width.
#
# `chartStroke` is the one allowed exception and is named rather than pattern-
# matched: a 1pt line and a 2pt line are two weights of one mark, not two steps
# of a size hierarchy, so stroke widths are below the ladder's floor by design.
hard "every ConsoleMetrics dimension is a rung" \
     "Use a Fibonacci rung (…13, 21, 34, 55, 89, 144, 233, 377…) or document it beside chartStroke." \
     bash -c '
       sed -n "/^enum ConsoleMetrics/,/^}/p" "'"$DESIGN"'/Tokens.swift" \
       | grep -vE "chartStroke" \
       | sed -nE "s/^[[:space:]]*static let ([a-zA-Z]+): CGFloat = ([0-9.]+).*/\1 \2/p" \
       | while read -r name value; do
           case " 1 2 3 5 8 13 21 34 55 89 144 233 377 610 987 " in
             *" $value "*) ;;
             *) echo "ConsoleMetrics.$name = $value is not a Fibonacci rung" ;;
           esac
         done'

bold "Mirrored constants"
# FleetCore cannot import the app target, so ConsoleLayout restates the handful
# of view-layer dimensions its budget is computed from. A restated number is a
# number that drifts, and `railWidth`'s comment has claimed to be "asserted
# equal by test" since it was written while no such assertion existed —
# FleetCoreTests cannot see ConsoleMetrics or ConsoleToolMetrics, so the test it
# named was not possible to write. The mirror was guarded by a sentence.
#
# Every `static let <name>` in ConsoleLayout that shares a name with one in the
# view layer has to carry the same value.
hard "ConsoleLayout's mirrored dimensions match the view layer" \
     "A value in FleetCore/ConsoleLayout.swift disagrees with the token it mirrors." \
     bash -c '
       mirrored="$(sed -n "/^public enum ConsoleLayout/,/^}/p" "'"$ROOT"'/Sources/FleetCore/ConsoleLayout.swift" \
                   | sed -nE "s/^[[:space:]]*public static let ([a-zA-Z]+): CGFloat = ([0-9.]+).*/\1 \2/p")"
       printf "%s\n" "$mirrored" | grep . | while read -r name value; do
         # Only names the view layer also declares are mirrors; the rest are
         # ConsoleLayout own values (sideColumnMin, panelMin, …).
         theirs="$(grep -rhoE "static let $name: CGFloat = [0-9.]+" \
                     --include="*.swift" "'"$ROOT"'/Sources/FleetConsoleApp" \
                   | sed -E "s/.*= //" | sort -u)"
         [ -z "$theirs" ] && continue
         if [ "$(printf "%s\n" "$theirs" | grep -c .)" -gt 1 ]; then
           echo "ConsoleLayout.$name mirrors a name the view layer declares at more than one value: $(printf "%s" "$theirs" | tr "\n" " ")"
         elif [ "$theirs" != "$value" ]; then
           echo "ConsoleLayout.$name = $value but the view layer says $theirs"
         fi
       done'

bold "Accessibility"
# The doc claims "nothing depends on colour alone". Reduced Motion was honoured
# from the start; Differentiate Without Colour was not read anywhere, which is
# what left the lone pips encoding health in hue only.
hard "Differentiate Without Colour is read somewhere" \
     "StatusPip and any other lone indicator must degrade to a shape." \
     bash -c 'grep -rq "accessibilityDifferentiateWithoutColor" --include="*.swift" "'"$DESIGN"'" || echo "no view reads accessibilityDifferentiateWithoutColor"'

bold "Docs track the code"
# Rule 9, turned on the tokens themselves.
#
# Every check below this line grew out of one enumerated set drifting from its
# prose — modules, chrome tools, popover sections, menu-bar items. All four are
# *names*. Nothing read the numbers, and the numbers were the part that had
# rotted worst: the FleetFont and FleetMetrics tables in docs/DESIGN-SYSTEM.md
# were wrong in **every single row**, and had been since the ramp was rewritten.
# They described the 9–12.5pt draft — 9/9.5, 12/12.5, gutter 12, popoverWidth
# 400 — which is the exact sediment the paragraph above them cites as the reason
# the toolbox exists. The document's worked example of drift was the document.
#
# A written rule ("update the docs") did not hold for the font sizes and did not
# hold here either, so this counts instead. Both directions, like the menu-bar
# check: a token added and not written down fails, and a token written down after
# it is gone — or written down at a size it no longer has — fails too. Value
# mismatches surface as one line on each side, which reads as what it is.
#
# `mono(_:)` takes its size from the call site and is documented with an em dash,
# so it carries no number to compare and drops out on its own. `actionSlot` is
# derived from `iconButtonSize` rather than typed, which is the point of it, so
# it is checked by name only.
hard "the documented token tables match Design/Theme.swift" \
     "Update the FleetFont / FleetMetrics tables in docs/DESIGN-SYSTEM.md, or the tokens." \
     bash -c '
       THEME="'"$DESIGN"'/Theme.swift"
       DOC="'"$DOCS"'/DESIGN-SYSTEM.md"

       # A documented row is "| <anything with a name in it> | <number> | … |".
       # Matched without backticks on purpose: a backtick inside this script
       # would be command substitution, and escaping one through three levels of
       # quoting is how a check ends up matching nothing and reporting green.
       pairs() { sed -nE "s/^\|[^A-Za-z]*([A-Za-z]+)[^|]*\| *([0-9.]+).*/\1 \2/p"; }

       doc_fonts="$(sed -n "/fleet-font-table/,/^### /p" "$DOC" | pairs | sort)"
       doc_metrics="$(sed -n "/fleet-metrics-table/,/^#### /p" "$DOC" | pairs | sort)"

       code_fonts="$(sed -n "/^enum FleetFont/,/^}/p" "$THEME" \
                     | sed -nE "s/^[[:space:]]*static let ([A-Za-z]+) = Font\.system\(size: ([0-9.]+).*/\1 \2/p" \
                     | sort)"
       code_metrics="$(sed -n "/^enum FleetMetrics/,/^}/p" "$THEME" \
                     | sed -nE "s/^[[:space:]]*static let ([A-Za-z]+): CGFloat = ([0-9.]+).*/\1 \2/p" \
                     | sort)"

       compare() { # <label> <code list> <doc list>
         comm -23 <(printf "%s\n" "$2" | grep .) <(printf "%s\n" "$3" | grep .) \
           | sed "s/^/$1./;s/\$/ is in the code at that value and not in the docs/"
         comm -13 <(printf "%s\n" "$2" | grep .) <(printf "%s\n" "$3" | grep .) \
           | sed "s/^/$1./;s/\$/ is in the docs at that value and not in the code/"
       }
       compare FleetFont "$code_fonts" "$doc_fonts"
       compare FleetMetrics "$code_metrics" "$doc_metrics"

       # Tokens derived from another token carry no literal to compare, so they
       # are checked for a mention only.
       sed -n "/^enum FleetMetrics/,/^}/p" "$THEME" \
       | sed -nE "s/^[[:space:]]*static let ([A-Za-z]+): CGFloat = [^0-9].*/\1/p" \
       | while IFS= read -r name; do
           [ -z "$name" ] && continue
           sed -n "/fleet-metrics-table/,/^#### /p" "$DOC" | grep -q "$name" \
             || echo "FleetMetrics.$name is derived and appears in no token table"
         done'

# The surfaces the app ships are enumerated in exactly two enums, and both are
# described in prose in README.md and docs/DESIGN-SYSTEM.md. Prose does not
# recompile, so it drifts silently: a session added ConsoleModule.plists and the
# Home surface and left both documents naming the previous set. That is the same
# failure mode as the ~130 literal font sizes — a written rule ("update the docs")
# did not hold, so this counts instead. Every case has to appear verbatim in at
# least one document.
# The popover's sections are the same kind of thing as the window's modules — an
# enumerated set of surfaces the app ships — so they are checked, but not the same
# way. The module check greps the prose for each name, which works because
# "Launch Services" is a phrase nothing else in the docs uses. The section names
# are not like that: the first draft of this check passed the moment it was
# written, because "Processes" was already in the docs as the name of a *console
# module*, and a check that cannot tell two surfaces apart because they share a
# word is a check that will report green through the drift it exists to catch.
#
# So it uses the marker form, like the menu-bar items, and compares both ways:
#
#     <!-- popover-sections: Services, Agents, Processes, Connections -->
hard "the documented popover sections are exactly the ones the app builds" \
     "Update the <!-- popover-sections: --> marker in docs/DESIGN-SYSTEM.md and the prose beside it." \
     bash -c '
       built="$(sed -n "/^enum FleetSection/,/^}/p" "'"$VIEWS"'/FleetPopover.swift" \
                | sed -nE "s/^[[:space:]]*case [a-zA-Z]+ = \"([^\"]+)\".*/\1/p" \
                | grep . | sort -u)"
       documented="$(grep -hoE "<!-- popover-sections:[^>]*-->" "'"$DOCS"'"/*.md \
                | sed -E "s/<!-- popover-sections:|-->//g" | tr "," "\n" \
                | sed -E "s/^ +| +$//g" | grep . | sort -u)"
       comm -23 <(printf "%s\n" "$built" | grep .) <(printf "%s\n" "$documented" | grep .) \
         | sed "s/^/popover section \"/;s/$/\" is built but not documented/"
       comm -13 <(printf "%s\n" "$built" | grep .) <(printf "%s\n" "$documented" | grep .) \
         | sed "s/^/popover section \"/;s/$/\" is documented but no longer built/"'

hard "every console module is named in the docs" \
     "A module exists that no document mentions. Add it to README.md and docs/DESIGN-SYSTEM.md." \
     bash -c '
       sed -n "/^enum ConsoleModule/,/^}/p" "'"$MODULES"'" \
       | sed -nE "s/^[[:space:]]*case [a-zA-Z]+ = \"([^\"]+)\".*/\1/p" \
       | while IFS= read -r name; do
           [ -z "$name" ] && continue
           grep -qF -- "$name" "'"$ROOT"'/README.md" "'"$DOCS"'"/*.md 2>/dev/null \
             || echo "module \"$name\" appears in no document"
         done'

# The menu bar is the one surface a user cannot avoid, and its prose rotted
# hardest: docs/DESIGN-SYSTEM.md carried a two-row table of items — Fleet and
# Connections, with an argument about their opposite silhouettes — long after the
# app had collapsed to one, and three source comments said the same. The module
# and tool checks above would not have caught it, because both are one-way: they
# ask whether every case in an enum is described, never whether every thing
# described still exists. That is the direction this one failed in.
#
# So it compares both ways, against an explicit marker in the doc:
#
#     <!-- menu-bar-items: fleet -->
#
# against the identifier of every MenuBarItemController the app constructs.
hard "the documented menu-bar items are exactly the ones the app puts up" \
     "Update the <!-- menu-bar-items: --> marker in docs/DESIGN-SYSTEM.md and the table beside it." \
     bash -c '
       # Slurped, not line-based: the call site wraps after the open paren, which
       # is how the first draft of this check found zero items and then reported
       # the one real item as deleted.
       built="$(find "'"$ROOT"'/Sources/FleetConsoleApp" -name "*.swift" -print0 \
                | xargs -0 perl -0ne '"'"'print "$1\n" while /MenuBarItemController\(\s*identifier:\s*"([a-z]+)"/gs'"'"' \
                | grep . | sort -u)"
       documented="$(grep -hoE "<!-- menu-bar-items:[^>]*-->" "'"$DOCS"'"/*.md \
                | sed -E "s/<!-- menu-bar-items:|-->//g" | tr ", " "\n\n" | grep . | sort -u)"
       # `grep .` again on each side: an empty variable still prints one empty
       # line through printf, which comm then reports as a nameless item.
       comm -23 <(printf "%s\n" "$built" | grep .) <(printf "%s\n" "$documented" | grep .) \
         | sed "s/^/menu-bar item \"/;s/$/\" is built but not documented/"
       comm -13 <(printf "%s\n" "$built" | grep .) <(printf "%s\n" "$documented" | grep .) \
         | sed "s/^/menu-bar item \"/;s/$/\" is documented but no longer built/"'

hard "every chrome tool is named in the docs" \
     "A ConsoleTool exists that no document mentions. Add it to the chrome-tools table." \
     bash -c '
       sed -n "/^enum ConsoleTool/,/^}/p" "'"$TOOLSRC"'" \
       | sed -n "/var title: String/,/^    }/p" \
       | sed -nE "s/.*return \"([^\"]+)\".*/\1/p" \
       | while IFS= read -r name; do
           [ -z "$name" ] && continue
           grep -qF -- "$name" "'"$ROOT"'/README.md" "'"$DOCS"'"/*.md 2>/dev/null \
             || echo "chrome tool \"$name\" appears in no document"
         done'

# A menu item bound to a selector the window has disabled is dead chrome: it draws
# a shortcut the user can read and cannot use. .fullScreenNone and a Full Screen
# menu entry cannot both be intended.
hard "no menu entry for a window behaviour that is disabled" \
     "The window sets .fullScreenNone, so a Full Screen menu item can never enable." \
     bash -c '
       # Matches a real binding — #selector(...toggleFullScreen...) — not the word
       # in a comment, so the note explaining the absence does not trip the check.
       grep -qE "collectionBehavior.*fullScreenNone" "'"$VIEWS"'/Console/ConsoleWindowController.swift" 2>/dev/null \
         && grep -qE "#selector\([^)]*toggleFullScreen" "'"$VIEWS"'/Console/MainMenu.swift" 2>/dev/null \
         && echo "MainMenu binds toggleFullScreen while the window is .fullScreenNone" \
         || true'

echo
if [[ "$hard_fail" -gt 0 ]]; then
  printf '\033[31m%s hard rule(s) broken.\033[0m\n' "$hard_fail"
  exit 1
fi
if [[ "$soft_fail" -gt 0 ]]; then
  printf '\033[33m%s budget(s) exceeded.\033[0m\n' "$soft_fail"
  [[ "$STRICT" -eq 1 ]] && exit 1
  echo "Not a failure, but nothing in the view layer should be adding to these."
  exit 0
fi
bold "Clean."
