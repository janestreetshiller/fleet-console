#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/design/surfaces"

rm -rf "$OUT"
mkdir -p "$OUT"

echo "▸ building renderer…"
cd "$ROOT"
if ! swift build -c debug --disable-index-store -Xswiftc -DFLEET_SURFACE_RENDERER; then
    echo "✗ the surface renderer does not compile — see the errors above"
    exit 1
fi
BIN="$(swift build -c debug --disable-index-store -Xswiftc -DFLEET_SURFACE_RENDERER --show-bin-path)"
if [ ! -x "$BIN/FleetConsoleApp" ]; then
    echo "✗ renderer executable missing → $BIN/FleetConsoleApp" >&2
    exit 1
fi

echo "▸ rendering…"
"$BIN/FleetConsoleApp" --render-surfaces "$OUT"

COUNT=$(find "$OUT" -name '*.png' | wc -l | tr -d ' ')
if [ "$COUNT" -eq 0 ]; then
    echo "✗ the renderer ran but produced nothing → $OUT"
    exit 1
fi
echo
echo "✓ $COUNT surfaces → $OUT"
echo
echo "  Note: chrome-terminal and chrome-files capture the panel but not the"
echo "  emulator body — SwiftTerm draws through a Metal layer that AppKit's"
echo "  cacheDisplay path cannot read. See SurfaceRenderer.swift."

if [[ "${1:-}" == "--open" ]]; then
    open "$OUT"
fi
