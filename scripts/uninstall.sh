#!/data/data/com.termux/files/usr/bin/bash
# uninstall.sh — removes everything install.sh created.
set -euo pipefail

PREFIX="${KICAD_PREFIX:-${PREFIX:-/data/data/com.termux/files/usr}}"
DATADIR="${KICAD_HOME:-$HOME}/.local/share"

root="$PREFIX/opt/kicad"
if [ -d "$root" ]; then
    for f in "$root/bin"/*; do
        b="$(basename "$f")"
        case "$b" in _*|*.so*|*launch*|*.kiface) continue ;; esac
        [ -L "$PREFIX/bin/$b" ] && rm -f "$PREFIX/bin/$b"
    done
fi

rm -rf "$PREFIX/opt/kicad"
rm -rf "$PREFIX/opt/occt" "$PREFIX/opt/spnav" "$PREFIX/opt/ngspice"
rm -f  "$PREFIX/opt/uninstall.sh"

rm -f "$DATADIR/applications"/org.kicad.*.desktop
[ -d "$DATADIR/icons/hicolor" ] && rm -rf "$DATADIR/icons/hicolor"

# legacy ~/bin wrappers from install-links.sh (if present)
if [ -L "$HOME/bin/kicad-launch.sh" ]; then
    for b in "$HOME/bin"/*; do
        [ -L "$b" ] && [ "$(readlink "$b")" = "$HOME/bin/kicad-launch.sh" ] && rm -f "$b"
    done
    rm -f "$HOME/bin/kicad-launch.sh"
fi

echo "KiCad uninstalled from $PREFIX/opt."