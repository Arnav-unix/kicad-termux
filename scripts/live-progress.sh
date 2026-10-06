#!/data/data/com.termux/files/usr/bin/bash
# Live progress display for the KiCad build.
#
# Two outputs:
#   1. One notification (fixed id) that is overwritten in place, so swiping the
#      shade shows a progress bar that moves. --alert-once keeps edits silent.
#   2. ~/kicad-build/progress.txt, for `watch -n2 cat` in Termux.
#
# Real errors, completion and failure go out on separate ids so they still
# buzz. This only reads logs; it never touches the build.

HOME_DIR=/data/data/com.termux/files/home
ROOT="$HOME_DIR/kicad-build"
LOG="$ROOT/logs"
RUNLOG="$LOG/kicad-run.log"
BUILDLOG="$LOG/kicad-build.log"
# Progress is tracked from whichever log ninja is currently writing to. During
# the CLI milestone that is kicad-build.log; once `ninja install` pulls in the
# full GUI it becomes kicad-install.log.
PROGLOG="${PROGLOG:-}"
if [ -z "$PROGLOG" ]; then
  if [ -s "$LOG/kicad-install.log" ] && grep -qaE '\[[0-9]+/[0-9]+\]' "$LOG/kicad-install.log" 2>/dev/null; then
    PROGLOG="$LOG/kicad-install.log"
  else
    PROGLOG="$BUILDLOG"
  fi
fi
PROGFILE="$ROOT/progress.txt"
TARGET="${TARGET:-kicad-cli}"

ID_LIVE=9911     # silent, constantly overwritten
ID_ALERT=9912    # loud, only for problems
PHASE="${PHASE:-kicad-cli}"

mkdir -p "$LOG"

bar() { # $1=pct
  local n=$(( $1 * 30 / 100 ))
  printf '[%s%s] %s%%' \
    "$(printf '%*s' "$n" '' | tr ' ' '#')" \
    "$(printf '%*s' $(( 30 - n )) '' | tr ' ' '.')" "$1"
}

prev_errs=0
# Byte offset in PROGLOG at watcher start; errors before this are stale.
LOG_BASE=0
if [ -f "$PROGLOG" ]; then LOG_BASE=$(stat -c %s "$PROGLOG" 2>/dev/null || echo 0); fi
hot=0
SAMPLES="$(dirname "$0")/run/.rate-samples"

while true; do
  # Completion / failure markers get the loud channel.
  if grep -qa KICAD_BUILD_OK "$RUNLOG" 2>/dev/null; then
    termux-notification -i $ID_ALERT -t "kicad-cli DONE" \
      -c "Build finished and installed. Verifying now."
    printf '%s\n' "$(bar 100) DONE" > "$PROGFILE"
    exit 0
  fi
  if grep -qa KICAD_BUILD_FAIL "$RUNLOG" 2>/dev/null; then
    termux-notification -i $ID_ALERT -t "kicad-cli FAILED" \
      -c "Build stopped on a real error. Fixing it."
    exit 0
  fi

  # Only count errors written since this watcher started. The build log is
  # append-only and spans many restarts, so a whole-file count keeps reporting
  # errors that were already fixed and would stay non-zero forever.
  errs=0
  if [ -f "$PROGLOG" ]; then
    errs=$(tail -c "+$((LOG_BASE + 1))" "$PROGLOG" 2>/dev/null | grep -caiE ' error:|FAILED:' || true)
    firsterr=$(tail -c "+$((LOG_BASE + 1))" "$PROGLOG" 2>/dev/null | grep -aiE ' error:|FAILED:' | tail -1 | cut -c1-130)
  fi
  if [ "$errs" -gt "$prev_errs" ]; then
    termux-notification -i $ID_ALERT -t "New error ($errs)" -c "$firsterr"
    prev_errs=$errs
  fi

  # ---- progress -------------------------------------------------------
  line=$(grep -aoE '\[[0-9]+/[0-9]+\]' "$PROGLOG" 2>/dev/null | tail -1)
  if [ -n "$line" ]; then
    n=${line#\[}; n=${n%%/*}
    total=${line#*/}; total=${total%\]}
    pct=0
    [ "${total:-0}" -gt 0 ] && pct=$(( n * 100 / total ))

    # Rolling-window rate. Averaging since startup makes the ETA swing wildly:
    # a few huge files in flight early on look like a stall, then it snaps back.
    # rate10 is edges-per-minute * 10, integer-only, so it can never divide by 0.
    now=$(date +%s)
    read -r prev_n < <( tail -1 "$SAMPLES" 2>/dev/null | cut -d' ' -f2 )
    # Ninja restarts its edge counter on a fresh invocation (reconfigure, new
    # target). Detect that reset, otherwise the rate goes negative.
    if [ -n "$prev_n" ] && [ "$n" -lt "$prev_n" ]; then : > "$SAMPLES"; fi
    printf '%s %s\n' "$now" "$n" >> "$SAMPLES"
    tail -12 "$SAMPLES" > "$SAMPLES.tmp" 2>/dev/null && mv "$SAMPLES.tmp" "$SAMPLES"
    read -r last_t last_n < <( tail -1 "$SAMPLES" )
    read -r win_t  win_n  < <( head -1 "$SAMPLES" )
    dt=$(( last_t - win_t ))
    rate10=0
    [ "$dt" -gt 0 ] && rate10=$(( (last_n - win_n) * 600 / dt ))
    rate=$(awk -v r="$rate10" 'BEGIN{printf "%.1f", r/10}')
    left=""
    if [ "$rate10" -ge 5 ]; then
      mins=$(( (total - n) * 10 / rate10 ))
      if [ "$mins" -ge 60 ]; then
        left=" ~$(( mins / 60 ))h$(( mins % 60 ))m left"
      else
        left=" ~${mins}m left"
      fi
    else
      left=" (warming up)"
    fi

    body="$(bar "$pct")  ${n}/${total} edges  ${rate}/min${left}  ${errs} errors"
    printf '%s   %s\n' "$body" "$(date '+%H:%M:%S')" > "$PROGFILE"
    termux-notification -i $ID_LIVE --alert-once -t "$PHASE ${pct}%" \
      -c "$(bar "$pct")  ${n}/${total}  ${rate}/min${left}  ${errs} err"
  fi

  # ---- thermal --------------------------------------------------------
  t=$(termux-battery-status 2>/dev/null | sed -n 's/.*"temperature": *\([0-9.]*\).*/\1/p')
  if [ -n "$t" ]; then
    t=${t%%.*}
    if [ "$t" -ge 45 ] 2>/dev/null; then
      [ "$hot" -eq 0 ] && { termux-notification -i $ID_ALERT -t "Phone HOT ${t}C" \
        -c "Consider the fridge. Build keeps going."; hot=1; }
    elif [ "$t" -le 41 ] 2>/dev/null; then
      [ "$hot" -eq 1 ] && { termux-notification -i $ID_ALERT -t "Phone cool ${t}C" \
        -c "Back to normal, no worries."; hot=0; }
    fi
  fi

  sleep 20
done