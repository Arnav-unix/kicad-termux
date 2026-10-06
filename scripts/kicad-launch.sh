#!/data/data/com.termux/files/usr/bin/bash
# Launcher for the native Termux KiCad 10.0.6 install.
#
# KiCad installs to $PREFIX/opt/kicad but its binaries do not carry a correct
# RUNPATH (it bakes in a bogus <prefix>/usr/lib path instead). The libraries
# live in three separate prefixes we built by hand, so point at them here.
#
# Usage:  symlink one of ~/bin/<name> -> this script, e.g.
#         ln -sf ~/bin/kicad-launch.sh ~/bin/pcbnew
# The invoked name ($0) is used to pick the real executable.

PREFIX=/data/data/com.termux/files/usr

export LD_LIBRARY_PATH="$PREFIX/opt/kicad/lib:$PREFIX/opt/spnav/lib:$PREFIX/opt/occt/lib:$PREFIX/opt/ngspice/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export XDG_DATA_DIRS="$PREFIX/opt/kicad/share${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

exec "$PREFIX/opt/kicad/bin/$(basename "$0")" "$@"