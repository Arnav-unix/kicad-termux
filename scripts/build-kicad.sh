#!/data/data/com.termux/files/usr/bin/bash
# Builds a KiCad target. Pass TARGET=kicad-cli for the fast CLI-only build,
# or TARGET=all (default) once the CLI milestone is banked.
set -uo pipefail

PREFIX=/data/data/com.termux/files/usr
ROOT="$HOME/kicad-build"
BLD="$ROOT/build-kicad"
LOG="$ROOT/logs"
TARGET="${TARGET:-kicad-cli}"
JOBS="${JOBS:-5}"
MARK="KICAD_BUILD_OK"
FAILMARK="KICAD_BUILD_FAIL"

mkdir -p "$LOG"
cd "$BLD" || exit 1

prev_fail=""
same_fail=0
while true; do
  echo "[build] ninja -j$JOBS $TARGET"
  ninja -j"$JOBS" $TARGET 2>&1 | tee -a "$LOG/kicad-build.log"
  rc=${PIPESTATUS[0]}
  [ "$rc" -eq 0 ] && break

  # Identify the target that just failed. Retrying is only useful for flaky
  # resource errors; the same target failing twice in a row means a real
  # compile error, so stop instead of burning battery in a loop.
  fail=$(grep -aoE 'FAILED: \[[0-9]+/[0-9]+\] [^ ]+' "$LOG/kicad-build.log" | tail -1)
  if [ -n "$fail" ] && [ "$fail" = "$prev_fail" ]; then
    same_fail=$(( same_fail + 1 ))
  else
    same_fail=1
    prev_fail="$fail"
  fi
  echo "[supervise] ninja rc=$rc; failing target: ${fail:-unknown}; repeat=$same_fail"
  if [ "$same_fail" -ge 2 ]; then
    echo "[supervise] same target failed twice; treating as a real error."
    echo "$FAILMARK"
    exit 1
  fi
  sleep 10
done

echo "[install] $TARGET"
ninja install >> "$LOG/kicad-install.log" 2>&1 || {
  echo "KICAD_INSTALL_FAIL"; exit 1; }

echo "$MARK"
ls -la "$PREFIX/opt/kicad/bin" 2>/dev/null
