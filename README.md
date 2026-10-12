# KiCad 10.0.6 for Termux (Android / aarch64)

> Vibe-coded & vibe-compiled. No warranty, but it works.

A native build of KiCad for Android, compiled with Termux's bionic toolchain
(no proot, no chroot required). Includes the full CLI (`kicad-cli`) and the
GTK3 GUI suite (`kicad`, `pcbnew`, `eeschema`, `gerbview`, others).

Two ways to obtain it:

1. **Prebuilt** — the release tarball, for identical architecture/API devices.
2. **From source** — everything needed to reproduce the build on any device.

---

## Installation — prebuilt

### Requirements
- **Termux** installed (F-Droid version recommended).
- **aarch64** device running **Android 12+ (API 36 or newer)**.
- ~700 MB free in Termux's data directory.

### Install
One command — the tarball carries its own installer:

```bash
cd ~
wget -qO- https://github.com/Arnav-unix/kicad-termux/releases/latest/download/kicad-prebuilt-aarch64-api36.tar.xz | tar -xJ
bash install.sh
```

What `install.sh` does:

| Step | Effect |
|---|---|
| copy | installs the `kicad`, `occt`, `spnav`, `ngspice` trees into `$PREFIX/opt/` |
| link | puts `kicad`, `pcbnew`, `eeschema`, ... on your **PATH** via `$PREFIX/bin` (a self-contained launcher fixes the library paths) |
| desktop | installs `.desktop` entries + icons for your launcher/menu |

Re-run it to reinstall/upgrade (idempotent). Uninstall with `bash $PREFIX/opt/uninstall.sh`.

Offline/SD-card route (same tarball, local):
```bash
cd ~ && tar -xJf /sdcard/KiCad-Termux/prebuilt/kicad-prebuilt-aarch64-api36.tar.xz && bash install.sh
```

### Verify

```bash
kicad-cli --version                     # → 10.0.6
kicad-cli pcb drc -o /tmp/drc.rpt some_board.kicad_pcb
```

### GUI

The GUI is GTK3, so it needs the X server from **termux-x11**:

```bash
termux-x11 &
# in the termux-x11 session:
kicad      # project manager
pcbnew     # board editor
eeschema   # schematic editor
```

Optional — app menu / launcher entries with icons:

`install.sh` already installs these (into `~/.local/share`). Only needed for older
installations made before v1.1.0:

```bash
wget -qO- https://raw.githubusercontent.com/Arnav-unix/kicad-termux/main/scripts/install-desktop.sh | bash
# then use your preferred launcher (rofi -show drun, dmenu, sway, file managers, ...)
```

### Compatibility notes (read before filing bugs)

- The tarball links against standard Termux libraries (`wxwidgets`, `protobuf`,
  `zlib`, ...). If a future Termux package update breaks the ABI, binaries may
  fail to dlopen. Compare `MANIFEST.txt` (bundled in the tarball and in the
  repo) against `dpkg -l` before reporting a regression.
- Only for **Android API 36+, aarch64**. Other targets must rebuild from source
  (lower the `--target=...-androidN` triple in `configure-kicad.sh` first).

> **Heads up — this already happened.** Upgrading `wxwidgets` to **3.3.4** breaks
> the prebuilt binaries: `wxDialog::IsModal()` and `wxGLCanvas::EGL()` were
> removed/changed, so `kicad` and `kicad-cli` fail with `cannot locate symbol`.
> See **[docs/WX-NOTES.md](docs/WX-NOTES.md)** for the details, the affected
> symbols, how to rebuild, and the `kopen` workaround for the file dialog.

---

## Building from source

Reproduces the exact binaries shipped above. Everything lives in `scripts/`.
Do these in order.

### 1. Install Termux packages

```bash
pkg update && pkg install ninja cmake clang llvm lld ccache git curl wget \
  python python-pip swig boost boost-headers \
  wxwidgets protobuf libprotobuf glew glm freetype \
  libpng libjpeg-turbo zlib liblzma openssl brotli libicu harfbuzz \
  libcurl markdown tree-sitter
```

### 2. Fetch sources

```bash
mkdir -p ~/kicad-build/{src,logs,run} && cd ~/kicad-build/src
git clone --recursive --depth 1 --branch 10.0.6 https://gitlab.com/kicad/code/kicad.git
curl -fL --retry 3 -o occt.tgz https://github.com/Open-Cascade-SAS/OCCT/archive/refs/tags/V7_8_1.tar.gz
tar xzf occt.tgz && rm occt.tgz
git clone --depth 1 https://github.com/FreeSpacenav/libspnav
curl -fSL --retry 3 -o ngspice-47.tar.gz https://downloads.sourceforge.net/project/ngspice/ng-spice-rework/47/ngspice-47.tar.gz
tar xzf ngspice-47.tar.gz
```

### 3. Apply patches

```bash
cd ~/kicad-build/src/kicad
git apply /path/to/this/repo/patches/kicad-android.patch
cp -r /path/to/this/repo/patches/compat ~/kicad-build/compat
```

The patch addresses the Android-specific issues:

| Issue | Fix |
|---|---|
| PCH generation OOMs/flatlines the build (2–3 GB per heavy PCH) | `KICAD_ANDROID_SKIP_PCH=ON` gates heavy PCHs off |
| `nlohmann::json` `wxString` support was gated Apple-only | extend shim to `__ANDROID__` |
| Termux's protobuf uses emulated TLS; API 36 clang emits real TLS → dlopen fails | `-femulated-tls` on `kiapi` and `pcbcommon` |
| `libidf3` missing at link time | keep `KICAD_IDF_TOOLS=ON` (default) |
| `nanodbc` / `compoundfilereader` don't compile on bionic | portable source tweaks |

### 4. Build the dependencies (order matters)

```bash
bash scripts/build-occt.sh      # OpenCASCADE → $PREFIX/opt/occt
# libspnav:
cmake -S ~/kicad-build/src/libspnav -B ~/kicad-build/src/libspnav/build \
  -DCMAKE_INSTALL_PREFIX=$PREFIX/opt/spnav -DCMAKE_BUILD_TYPE=Release
cmake --build ~/kicad-build/src/libspnav/build -j5 && cmake --install ~/kicad-build/src/libspnav/build
bash scripts/build-ngspice.sh   # ngspice 47 → $PREFIX/opt/ngspice
```

### 5. Configure and build KiCad

```bash
bash scripts/configure-kicad.sh     # aarch64-unknown-linux-android36 target
bash scripts/supervise.sh           # auto-resumes until ninja succeeds, then installs
```

`supervise.sh` compensates for Android's low-memory killer (which silently kills
compiler processes): it restarts `ninja -j5 all` on failure and only stops after
a green build + install. Success is marked by `KICAD_BUILD_OK` followed by
`KICAD_INSTALL_OK` in `~/kicad-build/logs/supervise.log`. Builds take several
hours on typical hardware; raise memory pressure, use `chk.sh` to monitor.

### 6. Make it runnable

```bash
bash scripts/install-links.sh        # launcher + ~/bin symlinks + PATH hint
bash scripts/install-desktop.sh      # optional: menu entries + icons
```

---

## Repository layout

```
README.md                       this file
MANIFEST.txt                    dependency versions for the prebuilt tarball
scripts/
  build-kicad.sh  build-occt.sh  build-ngspice.sh   source builds
  configure-kicad.sh            cmake configure (target triple + flags)
  supervise.sh  chk.sh          resilient build runner + status
  install-links.sh              launcher/~/bin setup for an extracted install
  install-desktop.sh            .desktop entries + icons
  install.sh  uninstall.sh      one-shot installer / remover (bundled in the prebuilt v1.1.0+ tarball)
  kicad-launch.sh               LD_LIBRARY_PATH fixer (used by install-links)
patches/
  kicad-android.patch           all source modifications (git apply)
  compat/pthread_cancel_compat.h  ngspice shim
docs/HANDOFF.md                 build notes
```

---

## FAQ

**Why do the binaries need wrappers?** KiCad's `ninja install` writes a bogus
RUNPATH (`<prefix>/usr/usr/lib`). The launcher sets `LD_LIBRARY_PATH` to the
four built prefixes instead; nothing else is modified.

**Is this a Termux package (`pkg install kicad`)?** Not yet. Doing so requires
packaging `kicad`, `occt`, `libspnav` and `ngspice` in the termux-packages
project. This repository is the exact recipe that would feed such a PR.

**Does the prebuilt work on my device?** Only aarch64 + Android API 36+ with the
Termux package versions in `MANIFEST.txt`. Otherwise, build from source.