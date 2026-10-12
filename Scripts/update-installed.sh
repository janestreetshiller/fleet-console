#!/bin/bash
# Builds a committed revision and swaps it in for /Applications/FleetConsole.app.
#
#   Scripts/update-installed.sh              # HEAD
#   Scripts/update-installed.sh <git-ref>    # any commit, branch or tag
#
# The build comes from a clean, detached worktree of the ref, so uncommitted
# edits in this checkout — yours or another session's — never reach the
# installed app. Then:
#
#   1. the running app is asked to quit;
#   2. the installed bundle is moved to the Trash, not deleted, so the update is
#      one drag to undo. Moving it is a rename on the same volume: the running
#      fleetd keeps executing its old binary and every managed service stays up;
#   3. the new bundle is copied in, its signature verified, and the app relaunched.
#
# fleetd is not restarted. It picks up the new binary the next time launchd
# starts it; pass --restart-controller to kickstart it now.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF="HEAD"
RESTART_CONTROLLER=0
for arg in "$@"; do
    case "$arg" in
        --restart-controller) RESTART_CONTROLLER=1 ;;
        -*) echo "✗ unknown option $arg" >&2; exit 2 ;;
        *) REF="$arg" ;;
    esac
done

COMMIT="$(git -C "$ROOT" rev-parse --verify "$REF^{commit}")"
SHORT="${COMMIT:0:7}"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/fleetconsole-update.XXXXXX")"
WORKTREE="$STAGE/source"
OUTPUT="$STAGE/out"
INSTALLED="/Applications/FleetConsole.app"
cleanup() {
    git -C "$ROOT" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
    rm -rf "$STAGE"
}
trap cleanup EXIT

echo "▸ building $SHORT from a clean worktree…"
git -C "$ROOT" worktree add --detach "$WORKTREE" "$COMMIT" >/dev/null
FLEETCONSOLE_OUTPUT_DIR="$OUTPUT" "$WORKTREE/Scripts/build-app.sh" release
NEW="$OUTPUT/FleetConsole.app"
codesign --verify --deep --strict "$NEW"

echo "▸ quitting the running app…"
osascript -e 'quit app id "com.fleetconsole.app"' >/dev/null 2>&1 || true
for _ in $(seq 1 40); do
    pgrep -f "$INSTALLED/Contents/MacOS/FleetConsole" >/dev/null || break
    sleep 0.25
done
if pgrep -f "$INSTALLED/Contents/MacOS/FleetConsole" >/dev/null; then
    echo "✗ FleetConsole did not quit; nothing was changed." >&2
    exit 1
fi

if [ -d "$INSTALLED" ]; then
    OLD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALLED/Contents/Info.plist" 2>/dev/null || echo unknown)"
    TRASHED="$HOME/.Trash/FleetConsole-$OLD_VERSION-$(date +%Y%m%d-%H%M%S).app"
    mv "$INSTALLED" "$TRASHED"
    echo "▸ previous app moved to $TRASHED"
fi
ditto "$NEW" "$INSTALLED"
codesign --verify --deep --strict "$INSTALLED"

if [ "$RESTART_CONTROLLER" = 1 ]; then
    echo "▸ restarting fleetd…"
    launchctl kickstart -k "gui/$(id -u)/com.fleetconsole.fleetd"
fi

open "$INSTALLED" --args --dashboard
echo
echo "✓ installed $SHORT at $INSTALLED and relaunched it"
