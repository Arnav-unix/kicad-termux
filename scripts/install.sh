#!/data/data/com.termux/files/usr/bin/bash
# install.sh — one-shot installer for KiCad on Termux.
#
# Works for both the prebuilt tarball and a source-built install: it installs
# the opt/ trees, puts every tool (`kicad`, `eeschema`, `pcbnew`, ...) on PATH
# via $PREFIX/bin, and adds desktop entries + icons. Idempotent — safe to re-run.
#
# Run from the directory that contains the kicad/ (occt/, spnav/, ngspice/)
# trees, i.e. from an extracted tarball:
#
#     tar -xJf kicad-prebuilt-aarch64-api36.tar.xz -C .
#     bash install.sh
set -euo pipefail

# --- location + overrides (KICAD_* only used for testing) ---
SRC="${KICAD_SRC:-$(cd "$(dirname -- "$(readlink -f -- "$0")")" && pwd)}"
PREFIX="${KICAD_PREFIX:-${PREFIX:-/data/data/com.termux/files/usr}}"
DATADIR="${KICAD_HOME:-$HOME}/.local/share"

kicad_tree="$SRC/kicad"
launcher="$kicad_tree/bin/kicad-launch.sh"

[ -x "$kicad_tree/bin/kicad-cli" ] || {
    echo "!! KiCad tree not found: expected '$kicad_tree/bin/kicad-cli'."
    echo "   Run this script from the directory you extracted the tarball into."
    exit 1
}
[ -f "$launcher" ] || {
    echo "!! launcher missing: $launcher"
    exit 1
}

echo "Installing into $PREFIX/opt ..."

mkdir -p "$PREFIX/opt" "$PREFIX/bin" "$DATADIR/applications" "$DATADIR/icons"

# --- 1. copy the install trees side by side (matches the launcher's layout) ---
for d in kicad occt spnav ngspice; do
    if [ -d "$SRC/$d" ]; then
        rm -rf "$PREFIX/opt/$d"
        cp -r "$SRC/$d" "$PREFIX/opt/$d"
    fi
done
chmod +x "$PREFIX/opt/kicad/bin"/* 2>/dev/null || true

# --- 2. put every tool on PATH via $PREFIX/bin (already on Termux's PATH) ---
n=0
for f in "$PREFIX/opt/kicad/bin"/*; do
    b="$(basename "$f")"
    case "$b" in _*|*.so*|*launch*|*.kiface) continue ;; esac
    [ -f "$PREFIX/opt/kicad/bin/$b" ] || continue
    ln -sf "$PREFIX/opt/kicad/bin/kicad-launch.sh" "$PREFIX/bin/$b"
    n=$((n+1))
done

# --- 3. desktop entries (pointed at the launcher) + icons ---
m=0
cp -r "$PREFIX/opt/kicad/share/icons/hicolor" "$DATADIR/icons/" 2>/dev/null || true
for df in "$PREFIX/opt/kicad"/share/applications/org.kicad.*.desktop; do
    [ -e "$df" ] || continue
    exec_line=$(grep '^Exec=' "$df" | sed 's/^Exec=//')
    bin="${exec_line%% *}"
    if [[ "$exec_line" == *" "* ]]; then args="${exec_line#* }"; else args=""; fi
    sed "s|^Exec=.*|Exec=$PREFIX/bin/$bin ${args}|" "$df" \
        > "$DATADIR/applications/$(basename "$df")"
    m=$((m+1))
done
command -v update-desktop-database >/dev/null 2>&1 && \
    update-desktop-database -q "$DATADIR/applications" 2>/dev/null || true

# --- 4. keep uninstall.sh discoverable ---
if [ -f "$SRC/uninstall.sh" ]; then
    cp "$SRC/uninstall.sh" "$PREFIX/opt/uninstall.sh"
    chmod +x "$PREFIX/opt/uninstall.sh"
fi

# --- 5. verify ---
echo "linked $n tools into $PREFIX/bin, installed $m desktop entries."
"$PREFIX/bin/kicad-cli" --version
echo
echo "Done. Type 'kicad' (or eeschema/pcbnew) — GUI needs termux-x11 running."
echo "Uninstall later with:  bash $PREFIX/opt/uninstall.sh"