#!/bin/bash
# Packages a staged FleetConsole.app into a drag-and-drop DMG.
#
# Usage: Scripts/package-dmg.sh <output-dir> [--volname <name>]
#
# The DMG is the distribution shape Apple users expect: open it, drag the app
# onto the Applications symlink, done. Built with a bare APFS UDZO image — no
# third-party tooling, no network access, no privileges.
#
# Requirements: a staged, signed and notarized FleetConsole.app inside
# <output-dir> (see Scripts/build-app.sh and Scripts/notarize.sh). The app is
# copied verbatim; this script never re-signs.
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

# A DMG that ships an unsigned or unnotarized app is a support incident waiting
# to happen. Refuse rather than package a build Gatekeeper will reject.
if ! codesign -dv --verbose=2 "$APP" 2>&1 | grep -q "Developer ID Application"; then
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

# Notarize the DMG itself and staple, so the disk image passes Gatekeeper too.
# Uses the same keychain profile as Scripts/notarize.sh.
PROFILE="${FLEETCONSOLE_NOTARY_PROFILE:-nokie-notary}"
if xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait >/dev/null 2>&1; then
    xcrun stapler staple "$DMG" >/dev/null 2>&1 && echo "✓ DMG notarized and stapled"
else
    echo "! DMG notarization skipped or failed (profile: $PROFILE). The app inside is notarized; the DMG itself may prompt." >&2
fi

shasum -a 256 "$DMG" > "$DMG.sha256"
echo "✓ packaged $DMG"
cat "$DMG.sha256"
