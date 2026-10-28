#!/bin/bash
# Measures how often the live model republishes.
#
#   Scripts/churn.sh          # 45 second window
#   Scripts/churn.sh 120      # longer window
#
# "Nothing rebuilds when nothing changed" is a design rule, and a rule about a
# running app is worth what it is measured at. This boots the real AppModel —
# real timers, real `ps`, real `netstat`, real `scutil` — with the activation
# policy set to .prohibited so nothing appears in the menu bar, watches each
# published surface with `withObservationTracking`, and prints the counts.
#
# What to expect, and why each number matters:
#
#   routing    ~1  regardless of window length. The snapshot carries the whole
#                  interface inventory and its `checkedAt` moves on every pass,
#                  so a plain `!=` would publish on every probe forever;
#                  `RoutingStatus.sameContent(as:)` is what makes this 1.
#   processes  one per sample. This is the control — CPU and resident memory
#                  really do change every few seconds, and a zero here would mean
#                  the harness was watching a dead model.
#   menu-bar   0   on a quiet fleet. The 1 Hz lease clock must never reach the
#                  status item.
#
# The harness lives in SurfaceRenderer.swift behind -DFLEET_SURFACE_RENDERER,
# the same flag that gates the design sheet, so none of it ships.
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
