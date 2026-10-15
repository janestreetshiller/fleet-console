#!/bin/bash
# Builds a committed revision and swaps it in for /Applications/FleetConsole.app.
#
#   Scripts/update-installed.sh              # HEAD
#   Scripts/update-installed.sh <git-ref>    # any commit, branch or tag
#   Scripts/update-installed.sh <git-ref> --no-launch  # replace without launch
# Offline mode: FLEETCONSOLE_OFFLINE=1 and an existing FLEETCONSOLE_DEPENDENCY_CACHE.
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
RELAUNCH=1
for arg in "$@"; do
    case "$arg" in
        --restart-controller) RESTART_CONTROLLER=1 ;;
        --no-launch) RELAUNCH=0 ;;
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
# Offline mode consumes an existing pinned cache; it never fetches a package.
# Copy only dependency state into the new worktree, not compiled products.
if [ "${FLEETCONSOLE_OFFLINE:-0}" = "1" ]; then
    CACHE="${FLEETCONSOLE_DEPENDENCY_CACHE:-}"
    case "$CACHE" in
        /*) ;;
        *) echo "✗ Set an absolute FLEETCONSOLE_DEPENDENCY_CACHE for offline updating" >&2; exit 2 ;;
    esac
    for ENTRY in checkouts repositories workspace-state.json; do
        if [ ! -e "$CACHE/$ENTRY" ] || [ -L "$CACHE/$ENTRY" ]; then
            echo "✗ Offline dependency cache is missing a regular $ENTRY entry" >&2
            exit 1
        fi
    done
    mkdir -p "$WORKTREE/.build"
    # -X omits file-provider/Finder metadata that resource signing rejects.
    cp -RX "$CACHE/checkouts" "$CACHE/repositories" "$WORKTREE/.build/"
    cp -X "$CACHE/workspace-state.json" "$WORKTREE/.build/workspace-state.json"
fi
FLEETCONSOLE_OUTPUT_DIR="$OUTPUT" FLEETCONSOLE_SCRATCH_PATH="$WORKTREE/.build" \
    "$WORKTREE/Scripts/build-app.sh" release
NEW="$OUTPUT/FleetConsole.app"
codesign --verify --deep --strict "$NEW"
if [ -n "${FLEETCONSOLE_NOTARY_PROFILE:-}" ]; then
    FLEETCONSOLE_OUTPUT_DIR="$OUTPUT" "$WORKTREE/Scripts/notarize.sh"
fi
# A local replacement must not silently downgrade the installed publisher or
# identity. Optional notarization uses only the existing configured workflow.
# Publisher checks precede quitting or moving the app.
if [ -d "$INSTALLED" ]; then
    OLD_SIGNATURE="$(codesign -dv --verbose=2 "$INSTALLED" 2>&1)"
    OLD_TEAM="$(printf '%s\n' "$OLD_SIGNATURE" | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
    OLD_STAPLED="$(printf '%s\n' "$OLD_SIGNATURE" | awk '/^Notarization Ticket=stapled$/{print "yes"; exit}')"
    NEW_TEAM="$(codesign -dv --verbose=2 "$NEW" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
    if [ -n "$OLD_TEAM" ] && [ "$OLD_TEAM" != "not set" ] && [ "$OLD_TEAM" != "$NEW_TEAM" ]; then
        echo "✗ Publisher team differs from installed FleetConsole; installed app was not touched." >&2
        exit 1
    fi
    if [ "$OLD_STAPLED" = "yes" ] && [ -z "${FLEETCONSOLE_NOTARY_PROFILE:-}" ]; then
        echo "▸ local source update: no notarization requested; preserving the old stapled app for rollback"
    fi
fi
SOURCE_REVISION="$(/usr/libexec/PlistBuddy -c 'Print :FleetSourceRevision' "$NEW/Contents/Info.plist")"
SOURCE_DIRTY="$(/usr/libexec/PlistBuddy -c 'Print :FleetSourceDirty' "$NEW/Contents/Info.plist")"
if [ "$SOURCE_REVISION" != "$COMMIT" ] || [ "$SOURCE_DIRTY" != "false" ]; then
    echo "✗ Staged app does not attest to the requested clean commit; installed app was not touched." >&2
    exit 1
fi

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
if ! ditto "$NEW" "$INSTALLED" || ! codesign --verify --deep --strict "$INSTALLED"; then
    echo "✗ Replacement copy/signature failed; restoring the preserved installed app." >&2
    if [ -e "$INSTALLED" ]; then
        mv "$INSTALLED" "$STAGE/failed-replacement.app"
    fi
    if [ -n "${TRASHED:-}" ] && [ -d "$TRASHED" ]; then
        mv "$TRASHED" "$INSTALLED"
        codesign --verify --deep --strict "$INSTALLED"
        echo "▸ original FleetConsole restored; not launched"
    fi
    exit 1
fi

if [ "$RESTART_CONTROLLER" = 1 ]; then
    echo "▸ restarting fleetd…"
    launchctl kickstart -k "gui/$(id -u)/com.fleetconsole.fleetd"
fi

if [ "$RELAUNCH" = 1 ]; then
    open "$INSTALLED" --args --dashboard
    echo "✓ installed $SHORT at $INSTALLED and relaunched it"
else
    echo "✓ installed $SHORT at $INSTALLED; not launched (--no-launch)"
fi
