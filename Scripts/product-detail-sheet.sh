#!/bin/bash
# Renders the two privacy-bounded FleetConsole product-detail views.
#
#   Scripts/product-detail-sheet.sh          # render, print the directory
#   Scripts/product-detail-sheet.sh --open   # render and open it
#
# The app runs with a disposable CFFIXED_USER_HOME inside the controlled output
# directory. The bounded renderer uses synthetic data, disables keychain access,
# and never visits Terminal, Files, account, or other tool surfaces.
set -euo pipefail

if [[ "${1:-}" != "" && "${1:-}" != "--open" ]] || [[ "$#" -gt 1 ]]; then
    echo "Usage: Scripts/product-detail-sheet.sh [--open]" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/design/product-detail"
FIXTURE_HOME="$OUT/fixture-home"

rm -rf "$OUT"
mkdir -p "$FIXTURE_HOME"

cleanup() {
    rm -rf "$FIXTURE_HOME"
}
trap cleanup EXIT

echo "▸ building bounded renderer…"
cd "$ROOT"
if ! swift build -c debug --disable-index-store -Xswiftc -DFLEET_SURFACE_RENDERER; then
    echo "✗ the bounded surface renderer does not compile — see the errors above" >&2
    exit 1
fi
BIN="$(swift build -c debug --disable-index-store -Xswiftc -DFLEET_SURFACE_RENDERER --show-bin-path)"
if [ ! -x "$BIN/FleetConsoleApp" ]; then
    echo "✗ renderer executable missing → $BIN/FleetConsoleApp" >&2
    exit 1
fi

echo "▸ rendering two isolated fixture views…"
CFFIXED_USER_HOME="$FIXTURE_HOME" \
    "$BIN/FleetConsoleApp" --render-surfaces "$OUT" --render-surfaces-only

EXPECTED=(
    "$OUT/console-overview-dark.png"
    "$OUT/popover-quick-view-dark.png"
)
for path in "${EXPECTED[@]}"; do
    if [ ! -s "$path" ]; then
        echo "✗ missing product-detail render → $path" >&2
        exit 1
    fi
done

COUNT="$(find "$OUT" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')"
if [ "$COUNT" -ne 2 ]; then
    echo "✗ bounded renderer produced $COUNT PNGs instead of 2 → $OUT" >&2
    exit 1
fi

echo
echo "✓ 2 isolated fixture views → $OUT"

if [[ "${1:-}" == "--open" ]]; then
    open "$OUT"
fi
