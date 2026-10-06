#!/data/data/com.termux/files/usr/bin/bash
# KiCad launcher for a native Termux install. Paths are resolved relative to
# this script, so it works from any prefix (opt/kicad extracted anywhere).
#
# KiCad's binaries carry a bogus RUNPATH (<prefix>/usr/usr/lib), so we fix the
# library path here instead. The invoked name ($0, i.e. which symlink you used)
# selects the real executable.
#
# Usage:  symlink any tool name to this script, e.g.
#         ln -sf kicad-launch.sh ~/bin/pcbnew
#         ln -sf kicad-launch.sh "$PREFIX/bin/pcbnew"
set -u

TOOL="$(basename "$0")"
SELF="$(readlink -f -- "$0")"
ROOT="$(cd "$(dirname -- "$SELF")/.." && pwd)"   # .../opt/kicad
OPT="$(dirname -- "$ROOT")"                       # .../opt (siblings: occt/spnav/ngspice)

[ -x "$ROOT/bin/$TOOL" ] || { echo "kicad-launch: no such tool '$TOOL' in $ROOT/bin"; exit 1; }

export LD_LIBRARY_PATH="$ROOT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
for s in occt spnav ngspice; do
    [ -d "$OPT/$s/lib" ] && LD_LIBRARY_PATH="$OPT/$s/lib:$LD_LIBRARY_PATH"
done
export PYTHONPATH="$ROOT/lib/python3.14/site-packages${PYTHONPATH:+:$PYTHONPATH}"
export XDG_DATA_DIRS="$ROOT/share${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

exec "$ROOT/bin/$TOOL" "$@"