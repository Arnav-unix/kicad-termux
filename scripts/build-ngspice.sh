#!/data/data/com.termux/files/usr/bin/bash
set -uo pipefail

PREFIX=/data/data/com.termux/files/usr
ROOT="$HOME/kicad-build"
SRCROOT="$ROOT/src"
LOG="$ROOT/logs"
mkdir -p "$LOG"

VER=47
TGZ="$SRCROOT/ngspice-$VER.tar.gz"
SRCDIR="$SRCROOT/ngspice-$VER"
PREFIXNG="$PREFIX/opt/ngspice"

if [ ! -f "$TGZ" ]; then
  echo "[dl] ngspice $VER"
  curl -fSL --retry 3 -o "$TGZ" \
    "https://downloads.sourceforge.net/project/ngspice/ng-spice-rework/$VER/ngspice-$VER.tar.gz" \
    >> "$LOG/ngspice-fetch.log" 2>&1 || {
      echo "NGSPICE_FETCH_FAIL"; exit 1; }
fi

if [ ! -d "$SRCDIR" ]; then
  echo "[untar] ngspice"
  tar -xzf "$TGZ" -C "$SRCROOT" || { echo "NGSPICE_UNTAR_FAIL"; exit 1; }
fi

cd "$SRCDIR" || exit 1

# Always reconfigure: the flags below matter (xspice in particular).
{
  echo "[configure] ngspice (ngshared, xspice, pthread-forced)"
  # Termux drives clang as aarch64-unknown-linux-android24, but ngspice's
  # frontend/parser/complete.c calls getpwent(), which bionic only declares
  # from API 26 (guarded by __BIONIC_AVAILABILITY_GUARD ->
  # __ANDROID_MIN_SDK_VERSION__). This device is API 36, so retargeting the
  # ngspice build to android26 is safe.
# --disable-xspice is NOT usable: upstream ngspice only ever builds with
  # xspice enabled, and cktsopt.c references OPT_ENH_RSHUNT (defined only
  # under #ifdef XSPICE) unconditionally. So keep xspice on and shim the one
  # bionic-incompatible call instead.
  # ngspice's configure REPLACES CFLAGS with its own hardening set
  # (-O2 -s -Wall ...), so flags passed via CFLAGS are silently discarded.
  # CC is substituted verbatim into the Makefiles and is also used for the
  # link step, so the target triple has to be injected there.
  CC="cc --target=aarch64-unknown-linux-android26" \
  CXX="c++ --target=aarch64-unknown-linux-android26" \
  CPPFLAGS="-include $ROOT/compat/pthread_cancel_compat.h -DHAVE_LIBPTHREAD=1 -D_GNU_SOURCE -D_DEFAULT_SOURCE" \
  ./configure --prefix="$PREFIXNG" \
    --with-ngshared \
    --enable-xspice \
    --without-x \
    --without-readline \
    --disable-debug \
    --disable-openmp \
    >> "$LOG/ngspice-configure.log" 2>&1 || {
      echo "NGSPICE_CONFIGURE_FAIL"; exit 1; }
}

echo "[make] ngspice"
# EXTRA_CFLAGS lets us adjust flags on an already-configured tree without
# paying for a full reconfigure.
make -j"${JOBS:-5}" ${EXTRA_CFLAGS:+CFLAGS="$EXTRA_CFLAGS"} \
  >> "$LOG/ngspice-build.log" 2>&1 || {
  echo "NGSPICE_BUILD_FAIL"; exit 1; }

echo "[install] ngspice"
make install >> "$LOG/ngspice-build.log" 2>&1 || {
  echo "NGSPICE_INSTALL_FAIL"; exit 1; }

find "$PREFIXNG" -name 'libngspice*' -o -name 'ngspice.h' | head
echo "NGSPICE_BUILD_OK"