#!/data/data/com.termux/files/usr/bin/bash
# Is the KiCad build actually alive?   ->   bash ~/chk.sh

H=/data/data/com.termux/files/home
L=$H/kicad-build/logs
export PATH=/data/data/com.termux/files/usr/bin:/system/bin

n=$(pgrep -x ninja | head -1)
if [ -n "$n" ]; then
    echo "BUILD ALIVE   (ninja pid $n)"
    echo "uptime: $(ps -o etime= -p "$n" 2>/dev/null | tr -d ' ')"
else
    echo "!! BUILD NOT RUNNING !!"
    echo "   start it with:  bash ~/cpme.sh"
fi

w=$(pgrep -f live-progress.sh | head -1)
[ -n "$w" ] && echo "watcher alive (pid $w)" || echo "watcher: not running (progress.txt will be stale)"

echo
echo "last build line: $(tail -1 "$L/kicad-build.log" 2>/dev/null | cut -c1-80)"
echo "progress.txt:"
cat "$H/kicad-build/progress.txt" 2>/dev/null
echo "errors so far: $(grep -ac 'error:' "$L/kicad-build.log" 2>/dev/null)"
free -m | awk '/^Mem:/{print "mem avail: "$7"MB"} /^Swap:/{print "swap used: "$3"MB"}'
grep -h KICAD_BUILD "$L/run-manual.log" 2>/dev/null