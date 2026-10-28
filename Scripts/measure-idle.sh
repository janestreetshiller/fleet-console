#!/bin/bash
# Idle cost of one running process: CPU time used and resident memory over a
# window, sampled once a minute. Reads only; it does not start, signal or stop
# the process. Works on macOS (ps) and Linux (/proc).
# Usage: Scripts/measure-idle.sh <pid> [seconds=600]
set -euo pipefail
PID="${1:?usage: measure-idle.sh <pid> [seconds]}"
WINDOW="${2:-600}"
STEP=60
[ "$WINDOW" -lt "$STEP" ] && STEP="$WINDOW"

cpu_seconds() {
    if [ -r "/proc/$PID/stat" ]; then
        # utime and stime are fields 14 and 15, in clock ticks; the command
        # name in field 2 may contain spaces, so count from the closing paren.
        local ticks hz
        ticks=$(sed 's/.*) //' "/proc/$PID/stat" | awk '{print $12 + $13}')
        hz=$(getconf CLK_TCK)
        awk -v t="$ticks" -v h="$hz" 'BEGIN { printf "%.2f", t / h }'
    else
        # macOS: [[dd-]hh:]mm:ss.cc
        ps -o time= -p "$PID" | awk '{
            t = $1; d = 0
            if (index(t, "-")) { split(t, dd, "-"); d = dd[1]; t = dd[2] }
            n = split(t, p, ":"); s = 0
            for (i = 1; i <= n; i++) s = s * 60 + p[i]
            printf "%.2f", s + d * 86400 }'
    fi
}

rss_kib() {
    ps -o rss= -p "$PID" | tr -d ' '
}

kill -0 "$PID" 2>/dev/null || { echo "no process $PID" >&2; exit 1; }
START_CPU=$(cpu_seconds)
START_RSS=$(rss_kib)
MAX_RSS=$START_RSS
echo "pid $PID: start cpu ${START_CPU}s rss ${START_RSS} KiB, window ${WINDOW}s"
ELAPSED=0
while [ "$ELAPSED" -lt "$WINDOW" ]; do
    sleep "$STEP"
    ELAPSED=$((ELAPSED + STEP))
    kill -0 "$PID" 2>/dev/null || { echo "process exited after ${ELAPSED}s" >&2; exit 1; }
    RSS=$(rss_kib)
    [ "$RSS" -gt "$MAX_RSS" ] && MAX_RSS=$RSS
    echo "  ${ELAPSED}s: cpu $(cpu_seconds)s rss ${RSS} KiB"
done
END_CPU=$(cpu_seconds)
END_RSS=$(rss_kib)
awk -v a="$START_CPU" -v b="$END_CPU" -v w="$WINDOW" -v r0="$START_RSS" -v r1="$END_RSS" -v rm="$MAX_RSS" 'BEGIN {
    used = b - a
    printf "cpu used %.2fs over %ds = %.3f%% of one core\n", used, w, used / w * 100
    printf "rss start %d KiB, end %d KiB, max %d KiB, growth %+d KiB\n", r0, r1, rm, r1 - r0
}'
