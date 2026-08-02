#!/bin/bash
# Renders every FleetConsole surface to build/design/surfaces/.
#
#   Scripts/surface-sheet.sh          # render, print the directory
#   Scripts/surface-sheet.sh --open   # render and open it
#
# The renderer lives in the app target (Sources/FleetConsoleApp/SurfaceRenderer.swift)
# behind -DFLEET_SURFACE_RENDERER, so what is captured is the shipping view code
# driven by fixtures — not a reimplementation of it beside the app. The flag is
# passed here and nowhere else; Scripts/build-app.sh never defines it, so neither
# the renderer nor its fixtures reach the signed bundle.
#
# Companion to Scripts/fleetkit-sheet.sh, which does the same for the primitives
# a surface is composed of.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/design/surfaces"

rm -rf "$OUT"
mkdir -p "$OUT"

echo "▸ building renderer…"
cd "$ROOT"
swift build -c debug -Xswiftc -DFLEET_SURFACE_RENDERER 2>&1 \
    | grep -vE '^\[|warning: missing creator' || true
BIN="$(swift build -c debug -Xswiftc -DFLEET_SURFACE_RENDERER --show-bin-path)"

echo "▸ rendering…"
# The renderer sets its activation policy to .prohibited, so this never steals
# focus and never shows a window — but it is still a GUI process and needs a
# session to draw into, which is why it runs here rather than over ssh.
"$BIN/FleetConsoleApp" --render-surfaces "$OUT"

COUNT=$(find "$OUT" -name '*.png' | wc -l | tr -d ' ')
echo
echo "✓ $COUNT surfaces → $OUT"
echo
echo "  Note: chrome-terminal and chrome-files capture the panel but not the"
echo "  emulator body — SwiftTerm draws through a Metal layer that AppKit's"
echo "  cacheDisplay path cannot read. See SurfaceRenderer.swift."

if [[ "${1:-}" == "--open" ]]; then
    open "$OUT"
fi
