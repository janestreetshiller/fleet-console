#!/bin/bash
# Internal build-app.sh worker; release-staging.py pins cwd to the reserved bundle.
# Never cd or use a staging pathname: ALL destinations remain relative to that cwd,
# including the outer signature and verification target (.).
set -euo pipefail
ROOT="$1"
BIN="$2"
CONFIG="$3"
APP=.

mkdir -p "$APP/Contents/MacOS" \
         "$APP/Contents/Resources/bin" \
         "$APP/Contents/Resources/licenses" \
         "$APP/Contents/Frameworks" \
         "$APP/Contents/Library/LaunchAgents"

cp "$BIN/FleetConsoleApp" "$APP/Contents/MacOS/FleetConsole"
cp "$BIN/fleetd"          "$APP/Contents/Resources/bin/fleetd"
cp "$BIN/fleetctl"        "$APP/Contents/Resources/bin/fleetctl"
# The resident operations agent ships beside the controller and CLI. Build it
# from the Rust workspace (release profile to match a release bundle).
if [ "$CONFIG" = "release" ]; then
    RUST_PROFILE="release"; RUST_OUTPUT="release"
else
    RUST_PROFILE="dev"; RUST_OUTPUT="debug"
fi
(cd "$ROOT/rust" && cargo build --locked --jobs 1 --quiet --profile "$RUST_PROFILE" --bin fleet-agent)
cp "$ROOT/rust/target/$RUST_OUTPUT/fleet-agent" "$APP/Contents/Resources/bin/fleet-agent"
cp "$ROOT/Resources/com.fleetconsole.fleetd.plist" "$APP/Contents/Library/LaunchAgents/"

# Keep debug symbols in SwiftPM's build outputs, not the shipping release bundle.
# Strip the copied executables before signing; never mutate signed code later.
if [ "$CONFIG" = "release" ]; then
    for BINARY in "$APP/Contents/MacOS/FleetConsole" \
                  "$APP/Contents/Resources/bin/fleetd" \
                  "$APP/Contents/Resources/bin/fleetctl" \
                  "$APP/Contents/Resources/bin/fleet-agent"; do
        xcrun strip -S "$BINARY"
    done
fi

# SwiftTerm's Metal shaders live in a SwiftPM resource bundle. Preserve any
# framework-style outputs as well as the statically linked build's resources.
shopt -s nullglob
for RESOURCE_BUNDLE in "$BIN"/*.bundle; do
    cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
done
for FRAMEWORK in "$BIN"/*.framework "$BIN"/*.dylib; do
    cp -R "$FRAMEWORK" "$APP/Contents/Frameworks/"
done
shopt -u nullglob

# Authored code is MIT; SwiftTerm retains its upstream copyright notices.
cp "$ROOT/LICENSE" "$APP/Contents/Resources/licenses/FleetConsole-LICENSE.txt"
SWIFTTERM_LICENSE="${FLEETCONSOLE_DEPENDENCY_CHECKOUTS:-$ROOT/.build/checkouts}/SwiftTerm/LICENSE"
if [ ! -f "$SWIFTTERM_LICENSE" ]; then
    echo "✗ SwiftTerm license missing at $SWIFTTERM_LICENSE" >&2
    exit 1
fi
cp "$SWIFTTERM_LICENSE" "$APP/Contents/Resources/licenses/SwiftTerm-LICENSE.txt"

# Generate a missing icon so a fresh clone is not silently unbranded.
if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
    echo "▸ no AppIcon.icns — drawing one…"
    "$ROOT/Scripts/make-icon.sh" >/dev/null
fi
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Ship the Files panel's configuration separately from ~/.config/yazi.
cp -R "$ROOT/Resources/yazi" "$APP/Contents/Resources/yazi"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>FleetConsole</string>
    <key>CFBundleDisplayName</key><string>FleetConsole</string>
    <key>CFBundleIdentifier</key><string>com.fleetconsole.app</string>
    <key>CFBundleExecutable</key><string>FleetConsole</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.2.0</string>
    <key>CFBundleVersion</key><string>6</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>

    <!-- LSUIElement keeps the icon out of the Dock, but not out of Finder, Get
         Info, notification banners, the login-items list or the About panel —
         all of which fall back to a blank page without this. -->
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>

    <!-- Menu-bar only: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key><true/>

    <!-- macOS withholds the Wi-Fi SSID from apps without Location access. Signal
         strength, link rate and IP work without it; only the network name needs this. -->
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>FleetConsole shows the name of the Wi-Fi network you are connected to. macOS treats the network name as location data, so it requires this permission. Nothing is collected, stored or transmitted.</string>

    <key>NSHumanReadableCopyright</key><string>Local-first. No telemetry, no network listeners.</string>
</dict>
</plist>
PLIST

# Stamp the exact source before signing. Source archives without Git remain
# explicitly unrecorded; the installed updater accepts only its clean commit.
SOURCE_REVISION="$(git -C "$ROOT" rev-parse --verify HEAD 2>/dev/null || true)"
SOURCE_DIRTY=1
if [ -n "$SOURCE_REVISION" ] && [ -z "$(git -C "$ROOT" status --porcelain --untracked-files=normal)" ]; then
    SOURCE_DIRTY=0
fi
python3 - "$APP/Contents/Info.plist" "$SOURCE_REVISION" "$SOURCE_DIRTY" <<'SOURCE_PLIST'
import plistlib
import re
import sys
path, revision, dirty = sys.argv[1:]
with open(path, "rb") as stream:
    info = plistlib.load(stream)
info["FleetSourceRevision"] = revision if re.fullmatch(r"[0-9a-f]{40,64}", revision) else "unrecorded"
info["FleetSourceDirty"] = dirty != "0"
with open(path, "wb") as stream:
    plistlib.dump(info, stream, sort_keys=False)
SOURCE_PLIST

# Reject inference runtimes, model weights and additional resident launch jobs
# before any code is signed. The bundled fleet-agent is a small client only.
python3 "$ROOT/Scripts/verify-agent-bundle.py" "$APP"

# Explicit ad-hoc signing avoids keychain lookup and timestamps. Developer ID
# retains hardened runtime/timestamps; nested code is signed inside out.
IDENTITY="${FLEETCONSOLE_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    IDENTITY="$(printf '%s\n' "$IDENTITIES" | awk -F'"' '/Developer ID Application/ && !found {print $2; found=1}')"
fi
IDENTITY="${IDENTITY:--}"
SIGN_FLAGS=(--force --sign "$IDENTITY")
if [ "$IDENTITY" = "-" ]; then
    echo "▸ signing (ad-hoc; local use, not notarized)…"
    SIGN_FLAGS+=(--timestamp=none)
else
    echo "▸ signing with: $IDENTITY"
    SIGN_FLAGS+=(--options runtime --timestamp)
fi

sign_code() {
    codesign "${SIGN_FLAGS[@]}" "$1"
    codesign --verify --strict --verbose=2 "$1"
}

find "$APP/Contents/Frameworks" -depth \
    \( -type d -name '*.framework' -o -type f -name '*.dylib' \) -print0 \
    | while IFS= read -r -d '' CODE; do sign_code "$CODE"; done
for BINARY in "$APP/Contents/Resources/bin/fleetd" "$APP/Contents/Resources/bin/fleetctl" "$APP/Contents/Resources/bin/fleet-agent"; do
    sign_code "$BINARY"
done
sign_code "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
if [ "$IDENTITY" != "-" ]; then
    echo "  ▸ not notarized yet; see docs/RELEASE.md before distributing"
fi
