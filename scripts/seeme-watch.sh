#!/data/data/com.termux/files/usr/bin/bash
# Watches for messages Vansh drops into ~/seeme.txt and pings him when the
# file changes, so he never has to interrupt a running build to reach me.
#
# Safe by design: this script never touches the build processes.

HOME_DIR=/data/data/com.termux/files/home
INBOX="$HOME_DIR/seeme.txt"
SEEN="$HOME_DIR/.seeme.seen"
LOG="$HOME_DIR/kicad-build/logs/seeme.log"

mkdir -p "$(dirname "$LOG")"
last=""
touch "$SEEN"

while true; do
  if [ -s "$INBOX" ]; then
    cur=$(cat "$INBOX" 2>/dev/null)
    if [ "$cur" != "$last" ]; then
      last="$cur"
      printf '%s new message\n' "$(date '+%H:%M:%S')" >> "$LOG"
      cp "$INBOX" "$SEEN"
      termux-notification -t "New message from you - Vansh" \
        -c "$(printf '%s' "$cur" | head -c 160)"
    fi
  else
    last=""
  fi
  sleep 20
done
