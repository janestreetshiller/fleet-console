#!/bin/bash
# Builds FleetConsole.app — the menu-bar client, with fleetd and fleetctl bundled.
#
# Everything runs as the logged-in user: no root, no installer, no privileged helper.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/FleetConsole.app"

# Cross-module optimization is off, and this is a compiler bug rather than a
# preference. SwiftPM passes -enable-default-cmo for release builds, and with it
# Swift 6.4 (swiftlang-6.4.0.25.4, the Xcode beta toolchain) hits an assertion
# optimizing ConsoleWindowController.show():
#
#   While running pass SILFunctionTransform "SILCombine" on SILFunction
#   "@$s15FleetConsoleApp0B16WindowControllerC4showyyF"
#   Assertion failed: (), function at Operand.swift:83
#
# It is not caused by anything in that function: the crash reproduces with the
# window controller's observers removed and with the root view's notification
# handlers restored, which were the two most recent changes anywhere near it.
# -disable-cmo is scope-only — it stops the optimizer inlining across module
# boundaries and changes no semantics — so the cost is a little performance and
# the alternative is no release build at all. Re-test on each toolchain bump and
# delete this when it builds clean.
CMO_WORKAROUND=(-Xswiftc -disable-cmo)

echo "▸ building ($CONFIG)…"
cd "$ROOT"
swift build -c "$CONFIG" "${CMO_WORKAROUND[@]}"
BIN="$(swift build -c "$CONFIG" "${CMO_WORKAROUND[@]}" --show-bin-path)"

# Replacing the binary of a *running* process invalidates its code signature and
# macOS kills it (OS_REASON_CODESIGNING). Unload the agent first if it is loaded,
# and remember to put it back afterwards.
AGENT_LABEL="com.fleetconsole.fleetd"
AGENT_WAS_LOADED=0
if launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1; then
    AGENT_WAS_LOADED=1
    echo "▸ stopping the controller while its binary is replaced…"
    launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true
    sleep 1
fi

echo "▸ assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" \
         "$APP/Contents/Resources/bin" \
         "$APP/Contents/Library/LaunchAgents"

cp "$BIN/FleetConsoleApp" "$APP/Contents/MacOS/FleetConsole"
cp "$BIN/fleetd"          "$APP/Contents/Resources/bin/fleetd"
cp "$BIN/fleetctl"        "$APP/Contents/Resources/bin/fleetctl"
cp "$ROOT/Resources/com.fleetconsole.fleetd.plist" "$APP/Contents/Library/LaunchAgents/"

# The icon is generated, not checked in as an opaque asset — Scripts/make-icon.sh
# draws it from the same geometry MenuBarItem.swift uses. Build it if it is
# missing so a fresh clone does not silently produce an unbranded bundle.
if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
    echo "▸ no AppIcon.icns — drawing one…"
    "$ROOT/Scripts/make-icon.sh" >/dev/null
fi
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# The Files panel's Yazi configuration. Shipped so the panel does not run against
# ~/.config/yazi — see FilesPanel.configHome.
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
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
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

# Signing.
#
# A Developer ID identity is used when one exists, because that is what lets the
# app open on a machine that is not this one — and what makes SMAppService
# registration work instead of falling back to install-agent.sh. Without one we
# still sign ad-hoc, which is fine locally and useless for distribution.
#
# `--deep` is deliberately not used: it is discouraged by Apple and signs nested
# code with the *outer* settings. The bundled tools are signed first, then the
# bundle that contains them. `--options runtime` and `--timestamp` are both
# required before Apple will notarize anything.
IDENTITY="${FLEETCONSOLE_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/{print $2; exit}')}"

if [ -n "$IDENTITY" ]; then
    echo "▸ signing with: $IDENTITY"
    for BINARY in "$APP/Contents/Resources/bin/fleetd" "$APP/Contents/Resources/bin/fleetctl"; do
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$BINARY"
    done
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/  /'
    echo "  team: $(codesign -dv --verbose=2 "$APP" 2>&1 | awk -F= '/TeamIdentifier/{print $2}')"
    echo "  ▸ not notarized yet — run Scripts/notarize.sh to make it open on other Macs"
else
    echo "▸ signing (ad-hoc — no Developer ID identity found)…"
    codesign --force --sign - "$APP" 2>/dev/null || echo "  (codesign unavailable; the app will still run locally)"
fi

if [ "$AGENT_WAS_LOADED" = "1" ]; then
    echo "▸ restarting the controller…"
    launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$AGENT_LABEL.plist" 2>/dev/null || true
    # launchd throttles restarts, and the controller reconciles before it binds;
    # 45s covers both. Silence here used to look like success — if the installed
    # plist still points at an old build path, this is the only place that shows it.
    BACK=0
    for _ in $(seq 1 45); do
        sleep 1
        if "$APP/Contents/Resources/bin/fleetctl" ping >/dev/null 2>&1; then
            echo "  controller is back up"
            BACK=1
            break
        fi
    done
    if [ "$BACK" = "0" ]; then
        echo "  ! controller did NOT come back — the agent is loaded but not answering."
        echo "    Most likely the LaunchAgent points at a stale path. Check:"
        echo "      launchctl print gui/$(id -u)/$AGENT_LABEL | grep program"
        echo "    and re-register it with: Scripts/install-agent.sh"
    fi
fi

echo
echo "✓ built $APP"
echo
echo "Next:"
echo "  Scripts/install-agent.sh      # register the controller with launchd"
echo "  open $APP                     # start the menu-bar app"
