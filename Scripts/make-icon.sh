#!/bin/bash
# Draws Resources/AppIcon.icns from Scripts/appicon/Icon.swift and the emblem.
#
#   Scripts/make-icon.sh          # regenerate the .icns
#   Scripts/make-icon.sh --sheet  # also write a contact sheet to build/design
#
# The plate is code and the emblem is Sources/FleetConsoleApp/Brand/fleet-emblem.png,
# the same file the app's badge loads. Every size in the iconset is drawn at its
# own scale rather than downsampled from 1024. Re-run this after changing either.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICONSET="$(mktemp -d)/AppIcon.iconset"
trap 'rm -rf "$(dirname "$ICONSET")"' EXIT

mkdir -p "$ICONSET" "$ROOT/Resources"

echo "▸ rendering…"
swift "$ROOT/Scripts/appicon/Icon.swift" "$ICONSET" "$ROOT/Sources/FleetConsoleApp/Brand/fleet-emblem.png"

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
