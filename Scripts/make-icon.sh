#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICONSET="$(mktemp -d)/AppIcon.iconset"
trap 'rm -rf "$(dirname "$ICONSET")"' EXIT

mkdir -p "$ICONSET" "$ROOT/Resources"

echo "▸ rendering…"
swift "$ROOT/Scripts/appicon/Icon.swift" "$ICONSET" "$ROOT/Sources/FleetConsoleApp/Brand/fleet-letter.png"

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
