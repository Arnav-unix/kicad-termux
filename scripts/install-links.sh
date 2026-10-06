#!/data/data/com.termux/files/usr/bin/bash
# install-links.sh — make a KiCad install runnable on a (fresh) Termux device.
#
# Use this AFTER the opt dirs are in place, i.e. either:
#   A) you built from source per README (scripts/build-*.sh + supervise.sh), or
#   B) you extracted a prebuilt tarball:
#        tar -xJf kicad-prebuilt-*.tar.xz -C "$PREFIX/opt/"
#
# It creates ~/bin/kicad-launch.sh (LD_LIBRARY_PATH fixer) and symlinks every
# KiCad binary name to it, then prints the PATH hint. Safe to run twice.
set -eu

PREFIX="/data/data/com.termux/files/usr"
KICAD="$PREFIX/opt/kicad/bin"

need() { [ -x "$1" ] || { echo "!! missing: $1"; return 1; }; }

need "$PREFIX/opt/kicad/bin/kicad-cli"
need "$PREFIX/opt/occt/lib"
need "$PREFIX/opt/spnav/lib/libspnav.so" || true
need "$PREFIX/opt/ngspice/lib/libngspice.so"

BIN="$HOME/bin"
mkdir -p "$BIN"

cat > "$BIN/kicad-launch.sh" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
# KiCad launcher (LD_LIBRARY_PATH fixer). See README "Make it runnable".
PREFIX="$PREFIX"
export LD_LIBRARY_PATH="\$PREFIX/opt/kicad/lib:\$PREFIX/opt/spnav/lib:\$PREFIX/opt/occt/lib:\$PREFIX/opt/ngspice/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export XDG_DATA_DIRS="\$PREFIX/opt/kicad/share\${XDG_DATA_DIRS:+:\$XDG_DATA_DIRS}"
export XDG_CONFIG_HOME=\${XDG_CONFIG_HOME:-\$HOME/.config}
exec "\$PREFIX/opt/kicad/bin/\$(basename "\$0")" "\$@"
EOF
chmod +x "$BIN/kicad-launch.sh"

n=0
for f in "$KICAD"/*; do
  b="$(basename "$f")"
  case "$b" in _*|*.so*) continue;; esac
  [ -x "$f" ] || continue
  ln -sf "$BIN/kicad-launch.sh" "$BIN/$b"
  n=$((n+1))
done

echo "linked $n binaries into ~/bin"
echo
case ":$PATH:" in
  *":$BIN:"*) echo "PATH already contains ~/bin ✓" ;;
  *) echo 'Add ~/bin to PATH:   fish_add_path ~/bin   (or append it to PATH in ~/.bashrc)' ;;
esac
echo
"$BIN/kicad-cli" --version && echo "KiCad is runnable."