#!/bin/bash
# Derives Resources/yazi/theme-light.toml from theme-dark.toml.
#
# The Yazi surface is achromatic on purpose — see the header of theme-dark.toml:
# colour in this app is a *status* vocabulary, and a file browser spending green
# on "+x" two feet from a services list where green means verified is a second
# meaning on the console's most loaded signal.
#
# But achromatic is not appearance-independent. The dark theme is a five-step
# ramp built for a dark terminal background, and `PTYSurface.applyAppearance`
# makes that background follow the system: in Light Mode the panel turned white
# while Yazi went on painting #C8C9CD text and #55565A rules onto it — about
# 1.3:1, which is not "low contrast", it is invisible.
#
# Both themes are therefore the same file with the ramp inverted, generated
# rather than hand-maintained, because two hand-kept copies of a 240-line theme
# is precisely the drift this repo counts everywhere else.
#
#   dark            light           role
#   #F2F3F5   →     #16181C         ink    — the focused row, brightest/darkest
#   #C8C9CD   →     #3C3E44         plain  — ordinary entries
#   #86878C   →     #74767C         muted  — chrome, parent column, metadata
#   #55565A   →     #B9BBC0         faint  — dividers and rules
#   #0B0D11   →     #FFFFFF         page   — the reversed row's own text
#
# The reversal survives the inversion, which is the point: `hovered` stays
# page-on-ink, so in dark mode it is a light row on a dark column and in light
# mode a dark row on a light one. Either way exactly one row is high-contrast.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/Resources/yazi/theme-dark.toml"
OUT="$ROOT/Resources/yazi/theme-light.toml"

[ -f "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }

python3 - "$SRC" "$OUT" <<'PY'
import sys, re

src, out = sys.argv[1], sys.argv[2]
# Simultaneous substitution — a sequential sed would map #F2F3F5 to #16181C and
# then something else onto #16181C. Case-insensitive because a hand edit may
# lowercase a literal.
ramp = {
    "#f2f3f5": "#16181C",
    "#c8c9cd": "#3C3E44",
    "#86878c": "#74767C",
    "#55565a": "#B9BBC0",
    "#0b0d11": "#FFFFFF",
}

text = open(src).read()
pattern = re.compile("|".join(re.escape(k) for k in ramp), re.IGNORECASE)
missing = pattern.sub(lambda m: ramp[m.group(0).lower()], text)

# Any hex that is not in the ramp is a colour nobody accounted for, and it will
# be wrong in one appearance or the other. Fail rather than ship it.
strays = sorted(set(re.findall(r"#[0-9A-Fa-f]{6}", missing))
                - set(ramp.values()))
if strays:
    sys.exit("theme-dark.toml uses colours outside the ramp: " + ", ".join(strays))

header = (
    "# GENERATED — do not edit. Run Scripts/make-yazi-light.sh.\n"
    "# Source: theme-dark.toml, with the five-step ramp inverted for a light\n"
    "# terminal background. Edit the dark theme and regenerate.\n\n"
)
open(out, "w").write(header + missing)
print(f"wrote {out}")
PY
