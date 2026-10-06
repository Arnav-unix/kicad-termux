#!/data/data/com.termux/files/usr/bin/bash
set -uo pipefail

PREFIX=/data/data/com.termux/files/usr
ROOT="$HOME/kicad-build"
SRC="$ROOT/src/kicad"
BLD="$ROOT/build-kicad"
LOG="$ROOT/logs"
mkdir -p "$LOG"

cmake -S "$SRC" -B "$BLD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX/opt/kicad" \
  -DCMAKE_PREFIX_PATH="$PREFIX/opt/occt;$PREFIX/opt/spnav;$PREFIX/opt/ngspice" \
  -DSPNAV_INCLUDE_DIR="$PREFIX/opt/spnav/include" \
  -DSPNAV_LIBRARY="$PREFIX/opt/spnav/lib/libspnav.so" \
  -DNGSPICE_INCLUDE_DIR="$PREFIX/opt/ngspice/include" \
  -DNGSPICE_LIBRARY="$PREFIX/opt/ngspice/lib/libngspice.so" \
  -DNGSPICE_CM_DIR="$PREFIX/opt/ngspice/lib/ngspice" \
  -DOCC_INCLUDE_DIR="$PREFIX/opt/occt/include/opencascade" \
  -DOCC_LIBRARY_DIR="$PREFIX/opt/occt/lib" \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_C_FLAGS="--target=aarch64-unknown-linux-android36 -D_GNU_SOURCE" \
  -DCMAKE_CXX_FLAGS="--target=aarch64-unknown-linux-android36 -D_GNU_SOURCE" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DKICAD_USE_PCH=ON \
  -DKICAD_IPC_API=OFF \
  -DKICAD_ANDROID_SKIP_PCH=ON \
  -DKICAD_IDF_TOOLS=ON \
  -DKICAD_BUILD_QA_TESTS=OFF \
  -DKICAD_SPICE_QA=OFF \
  -DKICAD_BUILD_I18N=OFF \
  -DKICAD_SCRIPTING_WXPYTHON=OFF \
  -DKICAD_WAYLAND=OFF \
  -DUSE_CCACHE=ON \
  2>&1 | tee "$LOG/kicad-configure.log"

rc=${PIPESTATUS[0]}
echo "CONFIGURE_RC=$rc"
exit $rc