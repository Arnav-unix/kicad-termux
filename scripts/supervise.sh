#!/data/data/com.termux/files/usr/bin/bash
# ------------------------------------------------------------------
# Resilient KiCad build supervisor.
#
#   bash ~/supervise.sh        (runs detached, survives screen lock)
#
# Why this exists: the build kept dying in two different ways, and both
# needed a human to notice and restart it.
#
#   1) DEATH    - ninja's process tree gets reaped (memory pressure).
#                 Supervisor simply starts ninja again; ninja is
#                 incremental, so it resumes. No work lost.
#   2) HANG     - ninja survives but stops forking workers (deadlock on
#                 an orphaned pipe). Log stops growing, nothing progresses.
#                 A counter alone cannot detect this, so we watch the
#                 log's mtime and kill+restart if it stalls.
#
# STALL_LIMIT = seconds of log silence before we call it a hang.
# ------------------------------------------------------------------

H=/data/data/com.termux/files/home
B=$H/kicad-build/build-kicad
L=$H/kicad-build/logs
export PATH=/data/data/com.termux/files/usr/bin:/system/bin

STALL_LIMIT=420      # 7 min of log silence = hang
MAX_ATTEMPTS=60
JOBS=5               # 8 cores; safe to push now that hangs auto-recover
LOG="$L/kicad-build.log"
SUP="$L/supervise.log"

cd "$B" || exit 1

say() { echo "$(date '+%H:%M:%S')  $*" >> "$SUP"; }

# Kill any stragglers. -x matches the exact program name so this can
# never match this script or the shell that launched it.
reap() {
    pkill -x ninja    2>/dev/null
    pkill -x cc1plus  2>/dev/null
    pkill -x clang++  2>/dev/null
    sleep 2
}

reap
say "=== supervisor started (pid $$), stall_limit=${STALL_LIMIT}s ==="

attempt=0
while [ "$attempt" -lt "$MAX_ATTEMPTS" ]; do
    attempt=$((attempt + 1))
    say "--- attempt $attempt : ninja -j$JOBS all ---"

    ninja -j$JOBS all >> "$LOG" 2>&1 &
    npid=$!

    # watch for hang: poll log mtime, kill if silent too long
    last=$(stat -c %Y "$LOG" 2>/dev/null || echo 0)
    while kill -0 "$npid" 2>/dev/null; do
        sleep 60
        now_ts=$(stat -c %Y "$LOG" 2>/dev/null || echo 0)
        if [ "$now_ts" -eq "$last" ]; then
            idle=$(( $(date +%s) - now_ts ))
            if [ "$idle" -ge "$STALL_LIMIT" ]; then
                say "HANG: log silent ${idle}s -> killing and resuming"
                kill -9 "$npid" 2>/dev/null
                reap
                break
            fi
        else
            last=$now_ts
        fi
    done

    wait "$npid" 2>/dev/null
    rc=$?

    if [ "$rc" -eq 0 ]; then
        say "BUILD OK (attempt $attempt) -> installing"
        ninja -j$JOBS install >> "$L/kicad-install.log" 2>&1
        if [ $? -eq 0 ]; then say "KICAD_INSTALL_OK"
        else                     say "KICAD_INSTALL_FAIL"; fi
        say "KICAD_BUILD_OK"
        exit 0
    fi

    say "attempt $attempt exited rc=$rc -> resuming in 5s (work is kept)"
    sleep 5
done

say "KICAD_BUILD_FAIL after $MAX_ATTEMPTS attempts"
exit 1