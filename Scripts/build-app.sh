#!/bin/bash
# Builds FleetConsole.app — the menu-bar client, with fleetd and fleetctl bundled.
#
# Everything runs as the logged-in user: no root, no installer, no privileged helper.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
OUTPUT_DIR="${FLEETCONSOLE_OUTPUT_DIR:-$ROOT/build}"

case "$CONFIG" in
    debug|release) ;;
    *) echo "✗ configuration must be debug or release" >&2; exit 2 ;;
esac
case "$OUTPUT_DIR" in
    /*) ;;
    *) OUTPUT_DIR="$ROOT/$OUTPUT_DIR" ;;
esac
# Preflight without writes: protect Applications aliases by ancestor device/inode
# identity, and refuse every existing bundle, file or symlink before building.
OUTPUT_DIR="$(python3 "$ROOT/Scripts/release-staging.py" check "$OUTPUT_DIR")"

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
swift build --jobs 2 -c "$CONFIG" --disable-index-store "${CMO_WORKAROUND[@]}"
BIN="$(swift build --jobs 2 -c "$CONFIG" --disable-index-store "${CMO_WORKAROUND[@]}" --show-bin-path)"

echo "▸ assembling bundle…"
# Keep the reservation and every destination operation in one fd-anchored
# lifetime. Returning a pathname here would let an ancestor swap redirect writes.
python3 "$ROOT/Scripts/release-staging.py" assemble "$OUTPUT_DIR" "$ROOT" "$BIN" "$CONFIG"
