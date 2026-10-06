# KiCad → Termux official packages: migration plan

Research + PR-ready recipe drafts for upstreaming the successful on-device
build of **KiCad 10.0.6** (see README.md / docs/HANDOFF.md) into the official
Termux packaging. No changes have been pushed to the official repos.

References:

- `termux/termux-packages` — **the only** living package repo (git monorepo;
  source of truth for this plan). Clone: `/tmp/opencode/termux-packages`.
- `termux/x11-packages` — **ARCHIVED 2022**. X11 packages live in the monorepo
  under `x11-packages/`. Contribute there, not to the archived repo.
- On-phone artifacts: `scripts/configure-kicad.sh`, `scripts/build-occt.sh`,
  `patches/kicad-android.patch` (8 files), `patches/compat/pthread_cancel_compat.h`.

Draft recipes live in this repo under `termux-recipes/{packages,x11-packages}/`,
mirroring the monorepo paths exactly.

---

## 1. Target repo & PR set

Everything submits to **`github.com/termux/termux-packages`**:
`packages/<name>` holds base packages, `x11-packages/<name>` GUI/X11 packages.
One repo, one CI, one `build-package.sh`.

### PR order (dependencies first, single concern per PR)

1. **`packages/ngspice`** — add `--enable-ngshared` + `TERMUX_PKG_REVISION=1` +
   new `subpackage.sh` shipping `libngspice.so` (KiCad's simulator link target).
   *Draft:* `termux-recipes/packages/ngspice/`.
2. **`x11-packages/libspnav`** (new) — small cmake lib used by KiCad's 3D viewer.
   *Draft:* `termux-recipes/x11-packages/libspnav/`.
3. **`x11-packages/occt`** (new) — Open CASCADE 7.8.1, module subset.
   *Draft:* `termux-recipes/x11-packages/occt/`.
4. **`x11-packages/kicad`** (new) — the app itself.
   *Draft:* `termux-recipes/x11-packages/kicad/`.

KiCad's wxWidgets gate (≥ 3.2.0, `CMakeLists.txt:1090`) is **already met**: the
monorepo's `x11-packages/wxwidgets/build.sh` is version **3.3.1**, and the
published `termux-x11` appendable repo ships `3.3.1-1` (verified in the
official `packages.termux.dev` index). **No bump PR needed** — only a runtime
`wxwidgets` dependency.

Convention: recipes contain no `control` file — the build system synthesizes
the Debian control from TERMUX_PKG_* metadata. Patches go in `patches/` under
each package dir (applied with `patch -p1`, sorted lexically).

---

## 2. Dependency state

### In the monorepo already
Base (`packages/`): `boost`, `brotli`, `freetype`, `glm`, `harfbuzz`,
`libcurl`, `libicu`, `libjpeg-turbo`, `liblzma`, `libpng`, `libprotobuf`
(2:35.1, + `abseil-cpp`), `openssl`, `pybind11`, `python`, `swig`,
`tree-sitter`, `tree-sitter-markdown`, `unixodbc` (2.3.14), `zlib`.
X11 (`x11-packages/`): `wxwidgets` (3.3.1), `glew`, `glu`, `gtk3`, `mesa`,
`libx11`.

### Missing → covered by the PR set
- `libngspice.so` → ngspice `--enable-ngshared` + subpackage (PR 1). The recipe
  already carries 10 Termux patches (incl. getpwent/parser-complete fixes).
- `occt` → new package (PR 3).
- `libspnav` → new package (PR 2).

### Explicitly not needed
`tree-sitter`/`tree-sitter-markdown` — KiCad 10 vendors its own markdown
renderer. Excluded from the kicad recipe.

---

## 3. Recipe notes (phone scripts → official recipes)

The on-phone scripts (native Termux build) must **not** be copied verbatim:

| Phone script           | Keep                                                              | Drop in official recipe                          |
|------------------------|-------------------------------------------------------------------|--------------------------------------------------|
| `configure-kicad.sh`   | KICAD_* feature switches, NGSPICE/SPNAV/OCC hint vars             | `-DCMAKE_C*_FLAGS=--target=aarch64-...android36` (CI sets the triple), `USE_CCACHE`, `/opt/...` install prefixes (packages install to `$TERMUX_PREFIX`), `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` |
| `build-occt.sh`        | module toggles (Draw/AppFramework off, Mesh/DataExchange/Vis on; USE_TK/TCL/FREETYPE/TBB/VTK off; no tests/docs) | the resume-on-OOM supervisor loop (CI owns process management) |

Feature-parity choices in `x11-packages/kicad/build.sh`:

- `-DKICAD_USE_PCH=OFF` **instead of** the custom `-DKICAD_ANDROID_SKIP_PCH`
  project option.
- `-DKICAD_IPC_API=OFF` — proven stable on-device; avoids a hard
  libprotobuf/abseil runtime ABI dependency. (Policy choice; ON is also fine
  for strict upstream parity — see risks.)
- `-DKICAD_BUILD_I18N=OFF`, `-DKICAD_SCRIPTING_WXPYTHON=OFF`,
  `-DKICAD_SPICE_QA=OFF`, `-DKICAD_BUILD_QA_TESTS=OFF`, `-DKICAD_WAYLAND=OFF`.
- `-DKICAD_SCRIPTING_PYTHON3=ON` — Python scripting via python + pybind11.

Official packages install to `$TERMUX_PREFIX`, so the hint variables in the
recipe are plain `$TERMUX_PREFIX/...` paths. Two paths must be confirmed by a
first CI build (Find* module expectations can vary by release):
- `-DNGSPICE_CM_DIR` — where ngspice's `.cmd`/cm model files land under an
  official install (on-device: `<prefix>/lib/ngspice`).
- OCCT cmake-config discovery — KiCad uses `find_package(OpenCASCADE)`;
  OCCT installs its config to `$TERMUX_PREFIX/lib/cmake/OpenCASCADE`.

---

## 4. Patch triage — `patches/kicad-android.patch` (8 files)

Moves to `x11-packages/kicad/patches/`. Verdict per file:

| Patch site                          | Verdict   | Why                                                                                        |
|-------------------------------------|-----------|--------------------------------------------------------------------------------------------|
| `api/CMakeLists.txt`    `-femulated-tls` | **Drop** | Artifact of our API-36 target vs repo-built-at-API-24 protobuf TLS mismatch. In official CI everything builds with the same toolchain target → consistent TLS. |
| `common/CMakeLists.txt` (pcbcommon emutls) | **Drop** | Same as above. (`fselect` is the only package that *adds* emutls → it is not the default.) |
| `eeschema/pcbnew/router` PCH guards | **Drop** | Replaced by `-DKICAD_USE_PCH=OFF`. |
| `libs/json/json_common.h` (`__ANDROID__` shim) | **Keep** | Real portability fix for Android libc++ (Apple-only upstream). Worth upstreaming to KiCad. |
| `libs/kiplatform/compoundfilereader.h` (char16_t) | **Keep** | Genuine Unicode/portability fix (Apple-only upstream). Worth upstreaming. |
| `libs/nanodbc/nanodbc.cpp` (size()) | **Keep** | unixODBC on Linux LP64 type mismatch (`SQL_WCHART_CONVERT`). Termux's unixodbc uses default configure so the same mismatch is expected — re-verify in CI. |
| `patches/compat/pthread_cancel_compat.h` | **Drop** | Upstream ngspice recipe already ships the getpwent/parser-complete patches covering this. |

---

## 5. Architectures

Official CI builds `aarch64`, `arm`, `i686`, `x86_64` (Docker per arch).
Expected on first submission:
- aarch64 / x86_64: fine.
- arm (32-bit) / i686: OCCT/KiCad compile, but CI memory/time is the constraint
  and the wxwidgets/gtk3 chain must be available per arch. If unpractical, gate
  via `TERMUX_PKG_BLACKLISTED_ARCHES` — decide with CI evidence, not assumption.

---

## 6. Licensing

| Package   | Path in monorepo | TERMUX_PKG_LICENSE          | License file to set                                   |
|-----------|------------------|-----------------------------|-------------------------------------------------------|
| kicad     | `x11-packages/kicad` | `GPL-3.0-or-later`      | KiCad root license files (bundles several thirdparty licenses) |
| occt      | `x11-packages/occt` | `LGPL-2.1`              | OCCT LGPL text in tarball root                       |
| libspnav  | `x11-packages/libspnav` | `BSD 3-Clause`       | `LICENSE` (library is BSD; GPL is only the separate `spacenavd` daemon) |
| ngspice   | `packages/ngspice` (edit) | `BSD 3-Clause, LGPL-2.1` | `COPYING` (unchanged)                              |

All OSS; compatible with Termux's OSS-only policy. No secrets/blobs.

---

## 7. Rejection-risk checklist

1. **Never ship the phone build scaffolding** (`--target=...android36`,
   `/opt` prefixes, ccache flags, OOM-resume loops, custom CMake options).
2. **Use existing switches** — `-DKICAD_USE_PCH=OFF`; do **not** add a
   project-local `KICAD_ANDROID_SKIP_PCH` option to upstream CMake.
3. **Drop emutls patches** — they only matter for mixed-API-level linking,
   impossible inside the repo build (same toolchain, same target).
4. **Separate PRs, deps first** (ngspice → libspnav → occt → kicad). A
   4-in-1 mega-PR will be bounced.
5. **Pin real values at submission**: SHA256s are set and verified; confirm
   `NGSPICE_CM_DIR`, OCCT cmake-config path, per-arch x11 CI evidence.
   `TERMUX_PKG_MAINTAINER` usually reads `@termux` — check current guidance.
6. **Data/libraries**: PR ships the KiCad *app* only. The default
   symbol/footprint/template trees (`kicad-symbols` etc.) are separate projects
   — ship an empty library table + install instructions, or plan follow-up
   `kicad-data` PRs. Say so explicitly in the PR body.
7. **CI time budget** for OCCT + KiCad is non-trivial; expect retry/tuning of
   `TERMUX_PKG_MAKE_PROCESSES`. Note it up-front.

---

## 8. Build & test path (reproducibility)

Fast local loop, no Docker needed:

```sh
# from a clone of termux/termux-packages (monorepo)
bash scripts/lint-packages.sh                                  # format/metadata lint
bash -n x11-packages/kicad/build.sh
git apply --check x11-packages/kicad/patches/*.patch           # against pristine kicad
```

Official builds run in Docker per arch via the repo CI; build-package.sh
resolves subdir packages (`build-package.sh:717`:
`TERMUX_PKG_BUILDER_DIR="$TERMUX_SCRIPTDIR/$package_directory/$TERMUX_PKG_NAME"`):

```sh
./build-package.sh packages/ngspice
./build-package.sh x11-packages/libspnav
./build-package.sh x11-packages/occt
./build-package.sh -i x11-packages/kicad     # -i = install the .deb at the end
```

On-device route (phone, hours): `pkg install proot-distro` +
`proot-distro install debian`, clone the monorepo inside, follow the repo
README/wiki on-device build steps, then the same `./build-package.sh ...`
commands. The authoritative gate is the CI build itself — open draft PRs and
let CI compile.

This sandbox lacks Docker, so drafts were validated with `bash -n`, the repo
lint script, and SHA256 curation only; CI is the real test.

---

## 9. Out of scope (future work)

- `kicad-data` (symbols/footprints/packages3d/templates) follow-up PRs.
- Phone-only artifacts (launcher shim, desktop entries, prebuilt tarball)
  already live in this repo's `scripts/`, `docs/HANDOFF.md`, and the v1.0
  GitHub release — independent of upstreaming.