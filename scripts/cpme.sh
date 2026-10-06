#!/data/data/com.termux/files/usr/bin/bash
# ------------------------------------------------------------------
# Take over the KiCad 10.0.6 GUI build and run it in YOUR session.
#
#   bash ~/cpme.sh
#
# Safe to look at before running: cat ~/cpme.sh
# ------------------------------------------------------------------

H=/data/data/com.termux/files/home
B=$H/kicad-build/build-kicad
L=$H/kicad-build/logs
export PATH=/data/data/com.termux/files/usr/bin:/system/bin

# --- 0. never start a second ninja on top of a running one ----------
if pgrep -x ninja >/dev/null 2>&1; then
    echo "A build is ALREADY running (ninja pid $(pgrep -x ninja | tr '\n' ' '))."
    echo "Nothing started. Just watch it with:"
    echo "    watch -n5 'cat ~/kicad-build/progress.txt'"
    exit 0
fi

# --- 1. stop any leftover driver / watcher --------------------------
echo "==> stopping leftover build driver + watcher"
pkill -f pch-then-all.sh   2>/dev/null
pkill -f live-progress.sh  2>/dev/null
pkill -x ninja             2>/dev/null
sleep 3

# --- 2. sanity: is the memory fix still in place? -------------------
# If these are back in the build graph we WILL hit the OOM hang again.
heavy=$(grep -ac 'eeschema_kiface_objects.dir/cmake_pch\|pcbnew_kiface_objects.dir/cmake_pch' "$B/build.ninja" 2>/dev/null)
if [ "${heavy:-0}" != "0" ]; then
    echo "!! WARNING: heavy PCH targets are back in build.ninja."
    echo "!! The memory fix was lost. Re-run:"
    echo "!!   cmake -DKICAD_ANDROID_SKIP_PCH=ON .   (in $B)"
    exit 1
fi
echo "==> memory fix confirmed (heavy PCHs absent)"

# --- 3. start the build, detached so it survives screen lock --------
echo "==> starting build (detached)"
cd "$B" || exit 1
setsid nohup bash -c '
    ninja -j3 all >> ~/kicad-build/logs/kicad-build.log 2>&1
    if [ $? -eq 0 ]; then echo KICAD_BUILD_OK   >> ~/kicad-build/logs/run-manual.log
    else                    echo KICAD_BUILD_FAIL >> ~/kicad-build/logs/run-manual.log; fi
' >> "$L/run-manual.log" 2>&1 < /dev/null &

# --- 4. live progress + lock-screen notification --------------------
echo "==> starting progress watcher"
setsid nohup env PHASE=GUI PROGLOG="$L/kicad-build.log" \
    bash "$H/kicad-build/live-progress.sh" >> "$L/lp-manual.log" 2>&1 < /dev/null &

sleep 25
echo
echo "==> status:"
tail -1 "$L/kicad-build.log" 2>/dev/null
cat "$H/kicad-build/progress.txt" 2>/dev/null
echo
echo "watch it:   watch -n5 'cat ~/kicad-build/progress.txt'"
echo "finished?:  grep KICAD_BUILD ~/kicad-build/logs/run-manual.log"
echo "run ONCE only - running it twice starts two ninjas."