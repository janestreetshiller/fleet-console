#!/bin/bash
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
hard "no inline system hues in view code" \
     "Route through StatusTone, or add a named token beside StorageCategory/TelemetrySeries." \
     bash -c '
       grep -rnE "(Color\.|foregroundStyle\(\.|foregroundColor\(\.|fill\(\.|tint\(\.|return \.|= \.|\? \.|: \.)(green|red|orange|yellow|purple|pink|teal|indigo|mint|cyan|brown)\b" \
         --include="*.swift" "'"$VIEWS"'" \
       | grep -vE "^[^:]+:[0-9]+: *(//|\*)"'

bold "Rule 11 — no opacity literals on a colour in view code"
hard "no .opacity() on primary, secondary or a tone in view code" \
     "Use StatusTone.wash/chipFill/edge/stroke, or a SurfaceInk token via FleetColor/ConsoleColor." \
     bash -c '
       grep -rnE "(Color\.primary|Color\.secondary|\.primary|\.secondary|tone\.color|StatusTone\.[a-z]+\.color)\.opacity\(" \
         --include="*.swift" "'"$VIEWS"'" \
       | grep -vE "^[^:]+:[0-9]+: *(//|\*)"'

bold "Colour-only state encoding"
hard "no bare shape filled straight from a tone colour" \
     "Use StatusTone.verdict, or put the state in adjacent text." \
     grep -rnE '(Circle|Capsule)\(\)[^\n]*\.(fill|foregroundStyle)\([^)]*tone\.color' \
     --include='*.swift' "$VIEWS" "$DESIGN"

bold "Rule 8 — tone.color fills, tone.ink writes"
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
hard "Tag pins its own width" \
     "Tag must keep .lineLimit(1) and .fixedSize()." \
     bash -c 'sed -n "/^struct Tag: View/,/^}/p" "'"$VIEWS"'/Components.swift" \
              | grep -q "fixedSize" || echo "Tag lost its .fixedSize()"'

hard "a row's trailing text pins its own width" \
     "FleetRowLabel's trailingText must keep .lineLimit(1) and .fixedSize()." \
     bash -c '
       sed -n "/if let trailingText/,/^            }/p" "'"$DESIGN"'/FleetRow.swift" \
       | grep -qE "^[[:space:]]*\.fixedSize\(\)[[:space:]]*$" \
         || echo "FleetRowLabel.trailingText lost its .fixedSize()"'

bold "Geometry containment"
hard "no .offset inside a fixed-size decorative stack" \
     "Anchor with a ZStack alignment instead, or reserve the space with padding." \
     grep -rnE '\.offset\(x: size \*|\.offset\(y: size \*' \
     --include='*.swift' "$VIEWS" "$DESIGN"

bold "Rule 1 — no literal type or metrics in view code"
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
hard "ConsoleLayout's mirrored dimensions match the view layer" \
     "A value in FleetCore/ConsoleLayout.swift disagrees with the token it mirrors." \
     bash -c '
       mirrored="$(sed -n "/^public enum ConsoleLayout/,/^}/p" "'"$ROOT"'/Sources/FleetCore/ConsoleLayout.swift" \
                   | sed -nE "s/^[[:space:]]*public static let ([a-zA-Z]+): CGFloat = ([0-9.]+).*/\1 \2/p")"
       printf "%s\n" "$mirrored" | grep . | while read -r name value; do
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
hard "Differentiate Without Colour is read somewhere" \
     "StatusPip and any other lone indicator must degrade to a shape." \
     bash -c 'grep -rq "accessibilityDifferentiateWithoutColor" --include="*.swift" "'"$DESIGN"'" || echo "no view reads accessibilityDifferentiateWithoutColor"'

bold "Docs track the code"
hard "the documented token tables match Design/Theme.swift" \
     "Update the FleetFont / FleetMetrics tables in docs/DESIGN-SYSTEM.md, or the tokens." \
     bash -c '
       THEME="'"$DESIGN"'/Theme.swift"
       DOC="'"$DOCS"'/DESIGN-SYSTEM.md"

       pairs() { sed -nE "s/^\|[^A-Za-z]*([A-Za-z]+)[^|]*\| *([0-9.]+).*/\1 \2/p"; }

       doc_fonts="$(sed -n "/fleet-font-table/,/^### /p" "$DOC" | pairs | sort)"
       doc_metrics="$(sed -n "/fleet-metrics-table/,/^#### /p" "$DOC" | pairs | sort)"

       code_fonts="$(sed -n "/^enum FleetFont/,/^}/p" "$THEME" \
                     | sed -nE "s/^[[:space:]]*static let ([A-Za-z]+) = Font\.system\(size: ([0-9.]+).*/\1 \2/p" \
                     | sort)"
       code_metrics="$(sed -n "/^enum FleetMetrics/,/^}/p" "$THEME" \
                     | sed -nE "s/^[[:space:]]*static let ([A-Za-z]+): CGFloat = ([0-9.]+).*/\1 \2/p" \
                     | sort)"

       compare() {
         comm -23 <(printf "%s\n" "$2" | grep .) <(printf "%s\n" "$3" | grep .) \
           | sed "s/^/$1./;s/\$/ is in the code at that value and not in the docs/"
         comm -13 <(printf "%s\n" "$2" | grep .) <(printf "%s\n" "$3" | grep .) \
           | sed "s/^/$1./;s/\$/ is in the docs at that value and not in the code/"
       }
       compare FleetFont "$code_fonts" "$doc_fonts"
       compare FleetMetrics "$code_metrics" "$doc_metrics"

       sed -n "/^enum FleetMetrics/,/^}/p" "$THEME" \
       | sed -nE "s/^[[:space:]]*static let ([A-Za-z]+): CGFloat = [^0-9].*/\1/p" \
       | while IFS= read -r name; do
           [ -z "$name" ] && continue
           sed -n "/fleet-metrics-table/,/^#### /p" "$DOC" | grep -q "$name" \
             || echo "FleetMetrics.$name is derived and appears in no token table"
         done'

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

hard "the documented menu-bar items are exactly the ones the app puts up" \
     "Update the <!-- menu-bar-items: --> marker in docs/DESIGN-SYSTEM.md and the table beside it." \
     bash -c '
       built="$(find "'"$ROOT"'/Sources/FleetConsoleApp" -name "*.swift" -print0 \
                | xargs -0 perl -0ne '"'"'print "$1\n" while /MenuBarItemController\(\s*identifier:\s*"([a-z]+)"/gs'"'"' \
                | grep . | sort -u)"
       documented="$(grep -hoE "<!-- menu-bar-items:[^>]*-->" "'"$DOCS"'"/*.md \
                | sed -E "s/<!-- menu-bar-items:|-->//g" | tr ", " "\n\n" | grep . | sort -u)"
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

hard "no menu entry for a window behaviour that is disabled" \
     "The window sets .fullScreenNone, so a Full Screen menu item can never enable." \
     bash -c '
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
