#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECONDS_ARG="${1:-45}"

cd "$ROOT"
echo "▸ building…"
swift build -c debug -Xswiftc -DFLEET_SURFACE_RENDERER 2>&1 \
    | grep -vE '^\[|warning: missing creator' || true
BIN="$(swift build -c debug -Xswiftc -DFLEET_SURFACE_RENDERER --show-bin-path)"

echo "▸ watching for ${SECONDS_ARG}s…"
"$BIN/FleetConsoleApp" --measure-churn "$SECONDS_ARG"
