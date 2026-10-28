#!/bin/bash
# Live native-window verification, using optimized code and real host probes.
# Usage: Scripts/benchmark.sh [seconds=60] [output-directory]
# Optional: FLEET_BENCHMARK_CPU_BUDGET limits percent of ONE core, not the host.
# The window stays offscreen. RUSAGE_SELF excludes collector subprocesses and
# WindowServer; this is not a composited on-screen rendering or idle benchmark.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECONDS_ARG="${1:-60}"
OUTPUT_DIR="${2:-$(mktemp -d "${TMPDIR:-$HOME/Library/Caches}/fleet-benchmark.XXXXXX")}"
CPU_BUDGET="${FLEET_BENCHMARK_CPU_BUDGET:-}"
cd "$ROOT"
mkdir -p "$OUTPUT_DIR"
FLAGS=(--disable-index-store -Xswiftc -disable-cmo -Xswiftc -DFLEET_SURFACE_RENDERER)
swift build -c release "${FLAGS[@]}"
BIN="$(swift build -c release "${FLAGS[@]}" --show-bin-path)"
# A successful producer exit is not evidence. Give each invocation an empty,
# exclusive directory so no previous receipt/screenshots can satisfy this gate.
EVIDENCE_DIR="$(mktemp -d "$OUTPUT_DIR/run.XXXXXX")"
"$BIN/FleetConsoleApp" --verify-live "$EVIDENCE_DIR" "$SECONDS_ARG"
python3 - "$EVIDENCE_DIR/receipt.json" "$CPU_BUDGET" <<'PY'
import json
import math
import sys
from pathlib import Path

def fail(message):
    # Acceptance is a release gate, not a debug assertion: -O must not disable it.
    raise SystemExit(f"✗ {message}")


def measurement(value, message, *, positive=False):
    if type(value) not in (int, float):  # bool and numeric strings are not measurements.
        fail(message)
    try:
        finite = math.isfinite(value)
    except OverflowError:
        finite = False
    if not finite or (value <= 0 if positive else value < 0):
        fail(message)
    return value


try:
    receipt = json.loads(Path(sys.argv[1]).read_text())
except (OSError, ValueError) as error:
    fail(f"Invalid verification receipt: {error}")
if not isinstance(receipt, dict):
    fail('Invalid verification receipt: expected a JSON object')
if receipt.get('valid') is not True:
    fail('Native live verification failed: valid must be literal true')
if receipt.get('configuration') != 'release':
    fail('Expected optimized code: configuration must be release')
cpu = measurement(receipt.get('processCPUPercent'), 'Invalid CPU measurement')
seconds = measurement(receipt.get('benchmarkSeconds'), 'Invalid benchmark duration', positive=True)
if sys.argv[2]:
    try:
        budget = float(sys.argv[2])
    except (ValueError, OverflowError):
        fail('CPU budget must be finite and positive')
    measurement(budget, 'CPU budget must be finite and positive', positive=True)
    if cpu > budget:
        fail(f'CPU budget exceeded: {cpu:.2f}% > {budget:.2f}%')
print(f"Live offscreen overview: {cpu:.2f}% of one core over {seconds:.1f}s")
print(f"Evidence: {Path(sys.argv[1]).resolve().parent}")
PY
