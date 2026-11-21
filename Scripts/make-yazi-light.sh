#!/bin/bash
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
