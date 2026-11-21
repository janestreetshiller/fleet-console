#!/bin/bash
set -euo pipefail

usage() { echo "usage: $0 <output-dir> [--volname <name>]" >&2; exit 2; }
[[ $# -ge 1 ]] || usage

OUTPUT_DIR="$1"; shift || true
VOLNAME="FleetConsole"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --volname) VOLNAME="$2"; shift 2 ;;
        *) usage ;;
    esac
done

case "$OUTPUT_DIR" in
    /*) ;;
    *) OUTPUT_DIR="$PWD/$OUTPUT_DIR" ;;
esac

APP="$OUTPUT_DIR/FleetConsole.app"
DMG="$OUTPUT_DIR/FleetConsole.dmg"
STAGING="$OUTPUT_DIR/dmg-staging"

[[ -d "$APP" ]] || { echo "✗ $APP not found. Stage a build first." >&2; exit 1; }

signature="$(codesign -dv --verbose=2 "$APP" 2>&1 || true)"
if ! printf '%s' "$signature" | grep -q "Developer ID Application"; then
    echo "✗ $APP is not Developer ID signed." >&2
    exit 1
fi
xcrun stapler validate "$APP" >/dev/null 2>&1 || {
    echo "✗ $APP has no notarization ticket. Run Scripts/notarize.sh first." >&2
    exit 1
}

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/FleetConsole.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "$VOLNAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG" >/dev/null

rm -rf "$STAGING"

IDENTITY="$(printf '%s' "$signature" | sed -n 's/^Authority=\(Developer ID Application: .*\)$/\1/p' | head -1)"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
codesign --verify --strict "$DMG"

PROFILE="${FLEETCONSOLE_NOTARY_PROFILE:-nokie-notary}"
if xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait >/dev/null 2>&1; then
    xcrun stapler staple "$DMG" >/dev/null 2>&1 && echo "✓ DMG notarized and stapled"
else
    echo "! DMG notarization skipped or failed (profile: $PROFILE). The app inside is notarized; the DMG itself may prompt." >&2
fi

shasum -a 256 "$DMG" > "$DMG.sha256"
echo "✓ packaged $DMG"
cat "$DMG.sha256"
