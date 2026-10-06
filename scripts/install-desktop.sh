#!/data/data/com.termux/files/usr/bin/bash
# install-desktop.sh — install KiCad .desktop entries + icons (any WM, any menu).
#
# Works with rofi (rofi -show drun), i3-dmenu-desktop, sway, file managers, ...
# It rewrites each upstream .desktop file so Exec= goes through the launcher
# wrapper (~/bin/<name>), which is what fixes KiCad's bogus RUNPATH. Idempotent.
set -eu

PREFIX="/data/data/com.termux/files/usr"
KICAD="$PREFIX/opt/kicad"
BIN="$HOME/bin"
DATA="$HOME/.local/share"

[ -f "$KICAD/bin/kicad-cli" ] || { echo "!! KiCad not installed ($KICAD missing)"; exit 1; }
mkdir -p "$DATA/applications" "$DATA/icons"

# Icons (hicolor theme, all sizes + scalable)
cp -r "$KICAD/share/icons/hicolor" "$DATA/icons/" 2>/dev/null || true

# Rewrite each upstream desktop entry
n=0
for df in "$KICAD"/share/applications/org.kicad.*.desktop; do
    [ -e "$df" ] || continue
    exec_line=$(grep '^Exec=' "$df" | sed 's/^Exec=//')
    bin="${exec_line%% *}"
    if [[ "$exec_line" == *" "* ]]; then args="${exec_line#* }"; else args=""; fi
    base=$(basename "$df")
    sed "s|^Exec=.*|Exec=$BIN/$bin ${args}|" "$df" > "$DATA/applications/$base"
    n=$((n+1))
done

# Refresh caches if the system has them
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$DATA/applications" 2>/dev/null || true

echo "Installed $n KiCad desktop entries."
echo "Try:  rofi -show drun   (or i3-dmenu-desktop, or your app menu)"