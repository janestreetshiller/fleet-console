#!/bin/bash
# Registers fleetd as a per-user launchd agent.
#
# This is the fallback path for unsigned local builds, where SMAppService cannot
# register the bundled agent. It uses the same mechanism launchd would use either
# way: a user LaunchAgent in ~/Library/LaunchAgents, loaded into the gui/$UID
# domain. No sudo, no root, no system-wide daemon.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="com.fleetconsole.fleetd"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ -x "$ROOT/build/FleetConsole.app/Contents/Resources/bin/fleetd" ]; then
    FLEETD="$ROOT/build/FleetConsole.app/Contents/Resources/bin/fleetd"
elif [ -x "/Applications/FleetConsole.app/Contents/Resources/bin/fleetd" ]; then
    FLEETD="/Applications/FleetConsole.app/Contents/Resources/bin/fleetd"
else
    FLEETD="$(swift build -c release --package-path "$ROOT" --show-bin-path)/fleetd"
    if [ ! -x "$FLEETD" ]; then
        echo "error: fleetd not found. Run Scripts/build-app.sh first." >&2
        exit 1
    fi
fi

echo "▸ controller binary: $FLEETD"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$FLEETD</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>ProcessType</key><string>Background</string>
    <key>StandardOutPath</key><string>$HOME/Library/Logs/FleetConsole/launchd.out.log</string>
    <key>StandardErrorPath</key><string>$HOME/Library/Logs/FleetConsole/launchd.err.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
PLIST

chmod 644 "$PLIST"
mkdir -p "$HOME/Library/Logs/FleetConsole"

echo "▸ (re)loading into gui/$(id -u)…"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/$LABEL"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

# The controller does its first reconcile sweep before it binds the socket, and
# that sweep shells out to lsof/ps — measured at 1s on an idle machine but 39s
# after a burst of restarts. A single `sleep 2` reports a healthy install as
# broken, so poll until it answers.
READY=0
for _ in $(seq 1 45); do
    if "$(dirname "$FLEETD")/fleetctl" ping >/dev/null 2>&1; then
        READY=1
        break
    fi
    sleep 1
done

if [ "$READY" = "1" ]; then
    echo "✓ controller is running and answering on the local socket"
    "$(dirname "$FLEETD")/fleetctl" ping
else
    echo "! controller did not answer within 45s — check:"
    echo "    launchctl print gui/$(id -u)/$LABEL"
    echo "    tail -n 40 ~/Library/Logs/FleetConsole/fleetd.log"
fi

echo
echo "To put fleetctl on your PATH:"
echo "    ln -sf \"$(dirname "$FLEETD")/fleetctl\" /usr/local/bin/fleetctl"
echo
echo "To remove the agent:"
echo "    launchctl bootout gui/$(id -u)/$LABEL && rm $PLIST"
