#!/bin/bash
# Draws Resources/AppIcon.icns from Scripts/appicon/Icon.swift.
#
#   Scripts/make-icon.sh          # regenerate the .icns
#   Scripts/make-icon.sh --sheet  # also write a contact sheet to build/design
#
# The icon is code, not a binary asset: the mark comes from the same geometry
# MenuBarItem.swift draws, and every size in the iconset is rendered at its own
# scale rather than downsampled from 1024, so the mesh can thin out as the canvas
# shrinks. Re-run this after changing either one.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICONSET="$(mktemp -d)/AppIcon.iconset"
trap 'rm -rf "$(dirname "$ICONSET")"' EXIT

mkdir -p "$ICONSET" "$ROOT/Resources"

echo "▸ rendering…"
swift "$ROOT/Scripts/appicon/Icon.swift" "$ICONSET"

echo "▸ packing…"
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"

if [[ "${1:-}" == "--sheet" ]]; then
    mkdir -p "$ROOT/build/design"
    cp "$ICONSET/icon_512x512@2x.png" "$ROOT/build/design/appicon-1024.png"
    echo "→ $ROOT/build/design/appicon-1024.png"
fi

echo
echo "✓ $ROOT/Resources/AppIcon.icns ($(du -h "$ROOT/Resources/AppIcon.icns" | cut -f1))"
echo "  Scripts/build-app.sh copies it into the bundle."
