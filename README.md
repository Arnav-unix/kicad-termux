# KiCad 10.0.6 — native build for Termux (Android / aarch64 / bionic)

Built and verified on an OPPO A6 Pro 5G (Android API 36, aarch64), running in a
plain Termux environment — **no proot, no chroot** for the build itself. Everything
compiles with Termux's own clang/lld against Android's bionic C library.

This folder is the complete, shareable record of the build: scripts, patches and
this guide. The point is that you do **not** have to rediscover the five Android
weirdnesses that ate our days. The patches and flag choices below already encode
them.

---

## What you get when it's done

- `kicad-cli` — full CLI: DRC, STEP export (OpenCASCADE), Gerbers, netlists, ...
- `kicad`, `pcbnew`, `eeschema`, `gerbview`, `bitmap2component`, `pl_editor`,
  `pcb_calculator`, plus IDF tools (`idfcyl`, `idfrect`, `dxf2idf`, `idf2vrml`)
- All binaries run with zero missing shared libraries (`ldd` clean) — a small
  launcher script points at the hand-built libraries.

---

## Requirements

- Device: Android 12+ (API 36 ideal), **aarch64**, Termux from F-Droid.
- Patience. The full build on a mid-range phone takes hours. See "Caveats".
- ~6 GB free in Termux's data dir (sources + build tree live under
  `$PREFIX/opt` and `~/kicad-build`).
- A swap file helps a lot (low-memory killer will otherwise eat your compilers).
- Keep the phone plugged in, keep Termux open, and **do not let anyone turn the
  phone off mid-build** (ninja is resumable, but a power cut at a bad moment is
  wasted battery life).

---

## Step 0 — Termux packages

```bash
pkg update
pkg install ninja cmake clang llvm lld ccache git curl wget unzip \
  python python-pip swig boost boost-headers \
  wxwidgets protobuf libprotobuf glew glm freetype \
  libpng libjpeg-turbo zlib liblzma openssl brotli libicu harfbuzz \
  libcurl markdown tree-sitter
```

`wxwidgets` from Termux is a **GTK3** build — the GUI therefore needs a display
server (termux-x11) later. That is expected, not a bug.

---

## Step 1 — Fetch sources

```bash
mkdir -p ~/kicad-build/src ~/kicad-build/logs ~/kicad-build/run
cd ~/kicad-build/src

# KiCad (10.0.6 tag)
git clone --recursive --depth 1 --branch 10.0.6 \
  https://gitlab.com/kicad/code/kicad.git

# OpenCASCADE 7.8.1 (STEP/IGES engine)
curl -fL --retry 3 -o occt.tgz \
  https://github.com/Open-Cascade-SAS/OCCT/archive/refs/tags/V7_8_1.tar.gz
tar xzf occt.tgz && rm occt.tgz   # -> OCCT-7_8_1

# libspnav (rarely-used 3D-nav lib, but KiCad links it unconditionally)
git clone --depth 1 https://github.com/FreeSpacenav/libspnav

# ngspice 47 (SPICE simulator)
curl -fSL --retry 3 -o ngspice-47.tar.gz \
  https://downloads.sourceforge.net/project/ngspice/ng-spice-rework/47/ngspice-47.tar.gz
tar xzf ngspice-47.tar.gz           # -> ngspice-47
```

---

## Step 2 — Apply the Android patch

```bash
cd ~/kicad-build/src/kicad
git apply /path/to/this/folder/patches/kicad-android.patch
cp -r /path/to/this/folder/patches/compat ~/kicad-build/compat   # ngspice shim
```

What that patch does and why — **read this before applying**:

| Problem | Fix | Where |
|---|---|---|
| PCH OOM-deadlocks the build (each heavy PCH ~2–3 GB) | Gate heavy PCHs behind `KICAD_ANDROID_SKIP_PCH`; configure with `-DKICAD_ANDROID_SKIP_PCH=ON` | `eeschema/`, `pcbnew/`, `pcbnew/router/` `CMakeLists.txt` |
| `nlohmann::json` fails on `wxString` (shim was Apple-only) | Extend the `json_common.h` shim guard to `__ANDROID__` | `include/json_common.h` |
| Protobuf TLS: Termux ships an API-24 emutls build; API-36 clang emits real TLS → dlopen fails | `-femulated-tls` on `kiapi` **and** `pcbcommon` | `api/`, `common/` `CMakeLists.txt` |
| `libidf3` missing at link (target never built) | Leave `KICAD_IDF_TOOLS=ON` (the script defaults it ON) | `configure-kicad.sh` |
| `nanodbc` / `compoundfilereader` won't compile on Android | Small portable tweaks | `thirdparty/nanodbc`, `thirdparty/compoundfilereader` |

---

## Step 3 — Build the hand libraries (order matters)

Those scripts live in `scripts/`. They are the exact ones used.

### 3a. OpenCASCADE (14 min intro; ~1–2 h build)
```bash
JOBS=5 bash ~/kicad-build/build-occt.sh
```
Configured with only the modules KiCad actually needs (Mesh, DataExchange,
Visualization); Draw/TK/FreeType/TBB all OFF. Installs to `$PREFIX/opt/occt`.

### 3b. libspnav
```bash
cd ~/kicad-build/src/libspnav
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=$PREFIX/opt/spnav \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build -j5
cmake --install build
```

### 3c. ngspice
```bash
JOBS=5 bash ~/kicad-build/build-ngspice.sh
```
The `compat/pthread_cancel_compat.h` shim is forced in via CPPFLAGS, and the
whole build is retargeted to `android26` (the `getpwent()` symbol bionic only
declares from API 26). Installs to `$PREFIX/opt/ngspice` with `--with-ngshared`.

---

## Step 4 — Configure KiCad

```bash
bash ~/kicad-build/configure-kicad.sh
```

Key points baked into the script:

- `--target=aarch64-unknown-linux-android36 -D_GNU_SOURCE` on both C and CXX.
- `CMAKE_PREFIX_PATH` = the three hand-built prefixes.
- `KICAD_IPC_API=OFF` (KI_API is why `protobuf` is needed; OFF keeps the surface
  smaller — only some generated `.pb.cc` still get built and linked).
- `KICAD_IDF_TOOLS=ON` — **do not** set this OFF or the `idf3` target vanishes
  and `_pcbnew.kiface` fails to link with `-lidf3`.
- `KICAD_ANDROID_SKIP_PCH=ON` — kills the 2–3 GB PCHs that OOM your compilers.
- `KICAD_BUILD_QA_TESTS=OFF`, `KICAD_SPICE_QA=OFF`, `KICAD_BUILD_I18N=OFF`,
  `KICAD_SCRIPTING_WXPYTHON=OFF`, `KICAD_WAYLAND=OFF`.

---

## Step 5 — Build (and survive Android's OOM killer)

Clang regularly gets OOM-killed by the low-memory killer (no error, just a
capsized `cc1plus` — ninja thinks the world ended). Two things make this a
non-event:

1. **ninja is incremental.** When a compiler dies, the edge is simply redone on
   the next run. Never delete the build dir.
2. **`supervise.sh`** auto-restarts `ninja -j5 all` until it returns 0, then runs
   `ninja install`. On a hang it kills the stuck clang children and retries. When
   it prints `KICAD_BUILD_OK` then `KICAD_INSTALL_OK` in `logs/supervise.log`
   (and the markers are back-to-back), you are done.

```bash
bash ~/kicad-build/supervise.sh
```

Handy companion: `chk.sh` reports live build state and remaining edge counts.

> `-j5` beats `-j3` by ~5× on this phone — the governor ramps, not your memory.
> If memory is tight (free < ~2 GB), back off to `-j3`.

---

## Step 6 — Make it runnable

KiCad's install (`ninja install`) puts everything in `$PREFIX/opt/kicad` but the
binaries carry a **wrong RUNPATH** (`<prefix>/usr/usr/lib`). Point at the four
library prefixes with the launcher — `scripts/kicad-launch.sh` — and symlink
every binary name to it:

```bash
PREFIX=/data/data/com.termux/files/usr
for n in kicad kicad-cli pcbnew eeschema gerbview bitmap2component pcb_calculator pl_editor dxf2idf idf2vrml idfcyl idfrect; do
  ln -sf ~/bin/kicad-launch.sh ~/bin/$n
done
```

Prepend `~/bin` to `PATH` (`fish_add_path ~/bin` on fish; `export PATH="$HOME/bin:$PATH"` in `~/.bashrc` otherwise).

The launcher exports:
```bash
export LD_LIBRARY_PATH="$PREFIX/opt/kicad/lib:$PREFIX/opt/spnav/lib:$PREFIX/opt/occt/lib:$PREFIX/opt/ngspice/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
```

---

## Step 7 — Verify

```bash
kicad-cli --version                          # 10.0.6
kicad-cli pcb drc -o /tmp/drc.rpt board.kicad_pcb
kicad-cli pcb export step -o /tmp/board.step board.kicad_pcb
kicad-cli pcb export gerbers -o /tmp/gerb board.kicad_pcb
kicad-cli sch export netlist -o /tmp/net.csv board.kicad_sch
```

All of the above were run successfully on the phone before this folder was
written.

---

## Step 7b — Desktop entries + icons (any launcher: rofi, i3, sway, menus, ...)

KiCad installs `.desktop` files and a full hicolor icon set, but its `Exec=`
lines call the raw binaries (which fail without the launcher fix). Install
rewritten, launcher-aware entries with:

```bash
bash /path/to/this/folder/scripts/install-desktop.sh
```

This puts entries + icons into `~/.local/share/{applications,icons}` and
rewrites `Exec=` to go through `~/bin/<name>`. Idempotent, uses nothing
desktop-specific, so it works with any app menu:
- rofi: `rofi -show drun`
- i3-dmenu-desktop: `$mod+d`
- file managers / any GTK menu: picked up automatically

Only the 6 apps KiCad ships entries for are covered (`pl_editor` has no
official .desktop upstream).

---

## Step 8 — GUI

The binaries are GTK3, so they need the X server that ships with termux-x11.
`install-desktop.sh` handles the icons/menus; the apps themselves just need the
display (and a WM is helpful but optional):

```bash
# in Termux:
termux-x11 &                    # then in the termux-x11 session:
DISPLAY=:0 kicad                # project manager
DISPLAY=:0 pcbnew               # board editor
DISPLAY=:0 eeschema             # schematic editor
```
If you run a WM (i3, sway, xfce4, ...) the apps also appear in its launcher /
menu automatically (`rofi -show drun`, `mod+d`, etc.).

---

## Sharing this / installing on a *fresh* device

Two tiers exist. Know which one people mean when they ask for "pkg install kicad".

### Tier 1 — GitHub repo of the recipes (do this today)
Put the whole contents of this folder on GitHub (public). A fresh user does:
```bash
git clone https://yourrepo.git ~/kicad-src  # or download the ZIP
cd ~/kicad-src && cat README.md            # then follow Steps 0–7
```
One-time, zero maintenance after that. This is the path you can stand up in ten
minutes (use `gh repo create` + `git push`, or create the repo on the web UI and
push the /sdcard folder).

### Tier 2 — Prebuilt binary tarball (fast, but fragile)
`prebuilt/kicad-prebuilt-aarch64-api36.tar.xz` is the exact, working install
(opt/kicad + occt + spnav + ngspice) with a `MANIFEST.txt` listing the Termux
dependency versions it was built against. Upload it to a GitHub **Release**.
Fresh aarch64 device:
```bash
curl -fL -o kis.tar.xz <release-asset-url>
tar -xJf kis.tar.xz -C "$PREFIX/opt/"
# fetch install-links.sh from the repo, then:
bash install-links.sh
```
Fragility: the binaries link against Termux's *standard* C++ libs (wxwidgets,
protobuf, zlib, ...) from `$PREFIX/lib`. If those packages bump versions with
ABI changes, the tarball stops loading. Check `MANIFEST.txt` against
`dpkg -l` if it breaks. Also: it is only for **Android API 36+ / aarch64**
(older devices = different bionic ABI; recompile with a lower
`--target=...-androidN`).

### Tier 3 — the literal `pkg install kicad` (real, but a rabbit hole)
Making `pkg install kicad` work means registering in the Termux package project:
- Subscribe a package: a `packages/kicad/build.sh` in
  https://github.com/termux/termux-packages, plus packaging the three
  dependencies (`occt`, `libspnav`, `ngspice`) as packages with their own
  `build.sh`, building through their Docker/CI, and them merging your PR.
- OR run a **personal Termux repo**: fork termux-packages, add the four
  packages, build all debs on aarch64, sign with a GPG key, host the `.deb`
  files + `Packages` index on GitHub Pages/Releases, then users:
  ```bash
  pkg install wget gnupg
  wget -qO- <your-host>/kicad-repo.asc | gpg --dearmor -o $PREFIX/etc/apt/trusted.gpg.d/kicad.gpg
  echo "deb [trusted=yes] https://<your-host> termux x11" >> $PREFIX/etc/apt/sources.list.d/kicad.list
  pkg update && pkg install kicad
  ```
Realistic honesty: Tier 3 is a multi-day infrastructure project. The recipe +
patch files here are exactly the input that project needs. Ship Tier 1 now
(+Tier 2 if you want fast adopters), and talk to the termux-packages
maintainers before committing to Tier 3.

---

## Caveats / scars from the road

- **Build time**: on the OPPO A6 Pro it was ~5 h wall-clock at `-j5` once the
  PCH/OOM problem was fixed (it had been ~2 nights of failed attempts before).
  The slow part is `eeschema` (heavy templates, ~100 s per file).
- **The failure chain that cost days**: PCH OOM deadlock → fixed; then
  `-lidf3` missing (IDF_TOOLS=OFF) → fixed; then protobuf `thread_cache_` symbol
  missing at dlopen (real-TLS vs emutls) → fixed with `-femulated-tls`; then
  `libngspice.so.0` not on lib path → fixed in the launcher. Each was a "just one
  more hour" trap. The patch file encodes all of them.
- **Do not** re-run `configure-kicad.sh` mid-build; it rebuilds nothing by itself
  but changing flags can invalidate the whole tree again.
- If ninja reports "premature end of file; recovering", that is normal after a
  force-kill. The `.ninja_log` is just truncated; work is kept.
- Watch memory with `free -m`; if `Swap used` pins high and pages aren't moving,
  the build is genuinely slow (not thrashing) — leave it alone.
- Worst-case kill discipline: only `pkill -x ninja` (or clang), never delete the
  build dir.

Good luck. If this saves you from "just one more hour", it earned its keep.