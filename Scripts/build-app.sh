#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$ROOT/.design-core/generate.py" --check
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
OUTPUT_DIR="$(python3 "$ROOT/Scripts/release-staging.py" check "$OUTPUT_DIR")"

CMO_WORKAROUND=(-Xswiftc -disable-cmo)

SCRATCH_PATH="${FLEETCONSOLE_SCRATCH_PATH:-$ROOT/.build}"
case "$SCRATCH_PATH" in
    /*) ;;
    *) echo "✗ FLEETCONSOLE_SCRATCH_PATH must be absolute" >&2; exit 2 ;;
esac
BUILD_ARGS=(--jobs 1 -c "$CONFIG" --disable-index-store --scratch-path "$SCRATCH_PATH" "${CMO_WORKAROUND[@]}")
if [ "${FLEETCONSOLE_OFFLINE:-0}" = "1" ]; then
    export GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0 CARGO_NET_OFFLINE=true
    export SWIFTPM_MODULECACHE_OVERRIDE="$SCRATCH_PATH/module-cache"
    export CLANG_MODULE_CACHE_PATH="$SCRATCH_PATH/module-cache"
    BUILD_ARGS+=(--skip-update --disable-automatic-resolution --disable-netrc
                 --cache-path "$SCRATCH_PATH/offline-cache"
                 --config-path "$SCRATCH_PATH/swiftpm-config"
                 --security-path "$SCRATCH_PATH/swiftpm-security")
fi
export FLEETCONSOLE_DEPENDENCY_CHECKOUTS="$SCRATCH_PATH/checkouts"
echo "▸ building ($CONFIG; one job)…"
cd "$ROOT"
swift build "${BUILD_ARGS[@]}"
BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

echo "▸ assembling bundle…"
python3 "$ROOT/Scripts/release-staging.py" assemble "$OUTPUT_DIR" "$ROOT" "$BIN" "$CONFIG"
