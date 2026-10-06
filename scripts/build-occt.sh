#!/data/data/com.termux/files/usr/bin/bash
# Build OpenCASCADE 7.8.1 natively inside Termux (bionic/aarch64) for KiCad.
set -euo pipefail

PREFIX=/data/data/com.termux/files/usr
ROOT="$HOME/kicad-build"
SRC="$ROOT/src"
LOG="$ROOT/logs"
TAG=V7_8_1
JOBS="${JOBS:-5}"

mkdir -p "$SRC" "$LOG"
cd "$SRC"

# GitHub strips the leading "V" from the archive's root directory name
SRCDIR="OCCT-${TAG#V}"

if [ ! -d "$SRCDIR" ]; then
  echo "[dl] fetching OCCT $TAG"
  curl -fL --retry 3 --retry-delay 5 -o occt.tgz \
    "https://github.com/Open-Cascade-SAS/OCCT/archive/refs/tags/$TAG.tar.gz"
  tar xzf occt.tgz
  rm -f occt.tgz
fi

cd "$SRCDIR"
echo "[cfg] $(pwd)  JOBS=$JOBS"

# Kept: TKernel/TKMath/TKG2d/TKG3d/TKBRep/TKTopAlgo/TKShHealing/TKMesh (Mesh),
#       TKSTEP* + TKXSBase (DataExchange -> STEP/IGES), TKOpenGl (Visualization -> 3D viewer)
# Dropped: Draw (+ all DRAW plugins), ApplicationFramework, Tcl/Tk, FreeType, TBB,
#          tests, docs, 3rdparty binaries
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX/opt/occt" \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DBUILD_MODULE_Draw=OFF \
  -DBUILD_MODULE_ApplicationFramework=OFF \
  -DBUILD_MODULE_Mesh=ON \
  -DBUILD_MODULE_DataExchange=ON \
  -DBUILD_MODULE_Visualization=ON \
  -DUSE_TK=OFF \
  -DUSE_TCL=OFF \
  -DUSE_FREETYPE=OFF \
  -DUSE_TBB=OFF \
  -DBUILD_TESTING=OFF \
  -DBUILD_DOC_Overview=OFF \
  -D3RDPARTY_EXECUTABLES=OFF \
  -DBUILD_USE_PKG_CONFIG=OFF \
  -DBUILD_USE_CCACHE=ON \
  -DOCE_INTEGRATION=OFF \
  2>&1 | tee "$LOG/occt-configure.log"

echo "[build] ninja -j$JOBS  (this is the long one)"

# Android's low-memory killer kills our compiler processes without warning.
# ninja is incremental, so just resume until it finishes; only give up if it
# stops making progress three times in a row (that means a real compile error).
prev=0
stall=0
while true; do
  if ninja -C build -j"$JOBS" 2>&1 | tee -a "$LOG/occt-build.log"; then
    break
  fi
  cur=$(find build -name '*.o' 2>/dev/null | wc -l)
  echo "[supervise] ninja exited; objects=$cur (was $prev)"
  if [ "$cur" -le "$prev" ]; then
    stall=$((stall + 1))
    if [ "$stall" -ge 3 ]; then
      echo "OCCT_BUILD_FAIL"
      exit 1
    fi
  else
    stall=0
  fi
  prev=$cur
  echo "[supervise] resuming in 10s"
  sleep 10
done

ninja -C build install 2>&1 | tee "$LOG/occt-install.log"

echo "OCCT_BUILD_OK"
ls "$PREFIX/opt/occt/lib" 2>/dev/null | head -20