# KiCad → Termux official packages: migration plan

Status of the prerequisite research + exact recipe drafts for upstreaming the
Kicad build into the official Termux OSS packaging (PR-ready). Based on the
successful on-device build of **KiCad 10.0.6** (see README.md / docs/HANDOFF.md).

References (what this document is derived from):

- `termux/termux-packages` — main package repo (clone: `/tmp/opencode/termux-packages`)
- `termux/x11-packages` — GUI/X11 package repo (clone: `/tmp/opencode/x11-packages`)
- On-phone artifacts: `scripts/configure-kicad.sh`, `scripts/build-occt.sh`,
  `patches/kicad-android.patch` (8 files), `patches/compat/pthread_cancel_compat.h`

All draft recipes live in this repo under `termux-recipes/`. Nothing here has
been pushed to the official Termux repos.

---

## 1. Where each piece goes

The Termux ecosystem builds from *two* repos, each with its own CI:

| Repo                     | Hosts | Terminal? |
|--------------------------|-------|-----------|
| `termux/termux-packages` | ngspice (needs change), user's build system | Android app "Termux" |
| `termux/x11-packages`    | wxwidgets, glew, gtk3, mesa, ... | Android app "Termux:X11" |

KiCad links `wxwidgets` (GTK3) → it must live in **`termux/x11-packages`**.
OCCT and libspnav exist **nowhere** yet → new packages (x11 repo, next to their
only consumer). The ngspice shared library is missing from **`termux-packages`**
(a prerequisite PR there).

### PR set (dependency order)

1. **`termux/termux-packages` — ngspice**: add `--enable-ngshared` +
   `TERMUX_PKG_REVISION=1` + new `subpackage.sh` shipping `libngspice.so`.
   *Draft:* `termux-recipes/ngspice/` (build.sh, subpackage.sh).
2. **`termux/x11-packages` — libspnav** (new): small cmake lib.
   *Draft:* `termux-recipes/libspnav/build.sh`.
3. **`termux/x11-packages` — occt** (new): Open CASCADE 7.8.1, module subset.
   *Draft:* `termux-recipes/occt/build.sh`.
4. **`termux/x11-packages` — wxwidgets bump** (probably required): the
   published x11 suite ships `wxwidgets 3.3.1-1` (on-device), but current
   `x11-packages` master shows `3.1.5-2` while KiCad 10 requires **≥ 3.2.0**
   (`CMakeLists.txt:1090`). Verify published version at submission; a bump PR
   may be needed first.
5. **`termux/x11-packages` — kicad** (new): the app itself.
   *Draft:* `termux-recipes/kicad/build.sh`.

Everything is OSS and matches Termux's package conventions (single `build.sh`,
`patches/` dir, auto-split `subpackage.sh`, TERMUX_PKG_* variables; **no
`control` file** — the build system synthesizes the Debian control from
build.sh metadata).

---

## 2. Dependency state

### Already packaged (main repo)
`boost`, `brotli`, `freetype`, `glm`, `harfbuzz`, `libcurl`, `libicu`,
`libjpeg-turbo`, `liblzma`, `libpng`, `libprotobuf` (2:35.1, + `abseil-cpp`,
`libprotobuf-c`), `openssl`, `pybind11`, `python`, `swig`, `tree-sitter`,
`tree-sitter-markdown`, `unixodbc` (2.3.14), `zlib`.

### Already packaged (x11 repo)
`wxwidgets` (3.1.5 in master git; **3.3.1-1 in the published suite**),
`glew`, `glu`, `gtk3`, `mesa`, `libx11`.

### Missing → covered by the PR set
- `libngspice.so` → ngspice `--enable-ngshared` + subpackage (PR 1). The main
  recipe otherwise already handles Termux specifics (10 patches incl. getpwent).
- `occt` → new package (PR 3).
- `libspnav` → new package (PR 2).
- `wxwidgets ≥ 3.2.0` → verify/`bump` (PR 4).

### Not needed
`tree-sitter`/`tree-sitter-markdown` — KiCad 10 vendors its own markdown
renderer; only a leak from the phone build's `pip list`. Excluded.

---

## 3. Recipe notes (phone scripts → official recipes)

The on-phone scripts were shaped by the native Termux build environment and
**must not** be copied verbatim:

| Phone script           | Keep                                                              | Drop in official recipe                          |
|------------------------|-------------------------------------------------------------------|--------------------------------------------------|
| `configure-kicad.sh`   | KICAD_* feature switches, NGSPICE/SPNAV/OCC hint vars             | `-DCMAKE_C*_FLAGS=--target=aarch64-...android36` (CI sets the triple), `USE_CCACHE`, `CMAKE_PREFIX_PATH=/opt/...` (packages install to `$TERMUX_PREFIX`), `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` |
| `build-occt.sh`        | module toggles: Draw/AppFramework off, Mesh/DataExchange/Vis on; USE_TK/TCL/FREETYPE/TBB/VTK off; no tests/docs | the resume-on-OOM supervisor loop (CI owns process management) |
| ngspice shell builds   | n/a                                                               | `--with-ngshared` now comes from the official recipe |

Feature parity decisions baked into `kicad/build.sh`:

- `-DKICAD_USE_PCH=OFF` **instead of** the custom `-DKICAD_ANDROID_SKIP_PCH`
  fork option.
- `-DKICAD_IPC_API=OFF` — proven stable on-device, avoids a hard
  libprotobuf/abseil ABI dependency. (Policy choice; can be ON for strict
  upstream parity — see rejection risks.)
- `-DKICAD_BUILD_I18N=OFF`, `-DKICAD_SCRIPTING_WXPYTHON=OFF`,
  `-DKICAD_SPICE_QA=OFF`, `-DKICAD_BUILD_QA_TESTS=OFF`,
  `-DKICAD_WAYLAND=OFF` — smaller first release; all are switchable later.
- `-DKICAD_SCRIPTING_PYTHON3=ON` — Python scripting via python+pybind11.

### NGSPICE/OCCT/SPNAV plumbing in the kicad recipe
Official packages install to `$TERMUX_PREFIX`, so the hint variables become
plain prefix paths (`$TERMUX_PREFIX/include`, `$TERMUX_PREFIX/lib/...`).
Two paths need confirmation with a real CI build (terms the Find* modules
match can vary between releases):
- `-DNGSPICE_CM_DIR` — where ngspice drops its `.cmd`/cm model files under an
  official install (on-device it was `<prefix>/lib/ngspice`).
- OCCT cmake config discovery — KiCad uses `find_package(OpenCASCADE)`;
  OCCT installs its config to `$TERMUX_PREFIX/lib/cmake/OpenCASCADE` and CI
  passes `-DCMAKE_PREFIX_PATH=$TERMUX_PREFIX`.

---

## 4. Patch triage — `patches/kicad-android.patch` (8 files)

Target: termux `packages/kicad/patches/` (applied with `patch -p1`). Split and
re-evaluated per file:

| Patch site                          | Verdict   | Why                                                                                        |
|-------------------------------------|-----------|--------------------------------------------------------------------------------------------|
| `api/CMakeLists.txt`    `-femulated-tls` | **Drop** | Artifact of our API-36 target vs repo-built-at-API-24 protobuf TLS mismatch. In official CI everything builds with the same toolchain target → consistent TLS. |
| `common/CMakeLists.txt` (pcbcommon emutls) | **Drop** | Same as above. (`fselect` is the only package that *adds* emutls → it is not the default.) |
| `eeschema/pcbnew/router` PCH guards | **Drop** | Replaced by `-DKICAD_USE_PCH=OFF`. |
| `libs/json/json_common.h` (`__ANDROID__` shim) | **Keep** | Real portability fix for Android libc++ (Apple-only upstream). Worth upstreaming to KiCad. |
| `libs/kiplatform/compoundfilereader.h` (char16_t) | **Keep** | Genuine Unicode/portability fix (Apple-only upstream). Worth upstreaming. |
| `libs/nanodbc/nanodbc.cpp` (size()) | **Keep** | unixODBC on Linux LP64 type-mismatch (`SQL_WCHART_CONVERT` → non-wchar SQLWCHAR). Re-verify in CI; termux's unixodbc uses default configure so the same mismatch is expected. |
| `patches/compat/pthread_cancel_compat.h` | **Drop** | Upstream ngspice recipe already ships the getpwent/parser-complete patches covering this. |

**Bundling Kicad patches**: group as `patches/*.patch` pre-fixing our repo
with an issue number when filing (Termux applies alphabetically).

---

## 5. Architectures

Official CI builds `aarch64`, `arm`, `i686`, `x86_64` (Docker per arch).
Expected on the first submission:
- aarch64/x86_64: fine.
- arm (32-bit) & i686: OCCT/KiCad compile but memory/time in CI is the real
  constraint; wxwidgets/gtk3 availability per-arch in x11-packages must be
  confirmed. If unpractical, either arch gets excluded via
  `TERMUX_PKG_BLACKLISTED_ARCHES` — a maintainer decision to make with CI
  evidence, *not* asserted blindly here.

---

## 6. Licensing

| Package   | License in  | TERMUX_PKG_LICENSE          | License file to set                                |
|-----------|-------------|-----------------------------|----------------------------------------------------|
| kicad     | x11         | `GPL-3.0-or-later`          | KiCad root license files (Kicad bundles several thirdparty licenses) |
| occt      | x11         | `LGPL-2.1`                  | OCCT LGPL text in tarball root                     |
| libspnav  | x11         | `BSD-3-Clause, GPL-3.0`     | `COPYING` (verify exact scheme in tarball at submission) |
| ngspice   | main (edit) | `BSD 3-Clause, LGPL-2.1`    | `COPYING` (unchanged)                              |

All compatible with Termux's OSS-only repo policy. No blob/secret concerns.

---

## 7. Rejection-risk checklist

1. **Never ship the phone build scaffolding** (`--target==android36`,
   `/opt` prefixes, ccache flags, OOM-resume loops, custom CMake options).
2. **Use existing switches** — `-DKICAD_USE_PCH=OFF`; do **not** introduce a
   new project-local option (`KICAD_ANDROID_SKIP_PCH`) in upstream CMake.
3. **Drop emutls patches** — they only matter for mixed-API-level linking,
   which cannot happen inside the repo build (same toolchain, same target).
4. **Separate PRs, deps first** (ngspice → libspnav → occt → kicad). A 4-in-1
   mega-PR will be bounced.
5. **Pin real values at submission**: SHA256s, wxwidgets published version,
   NGSPICE_CM_DIR, OCCT cmake-config path, per-arch x11 CI evidence. Leave no
   `TODO` behind. `TERMUX_PKG_MAINTAINER` normally reads `@termux`; check the
   current guidance for community submitters.
6. **Data/libraries**: this package ships the KiCad *app* only. The default
   symbol/footprint/template trees (`kicad-symbols` etc.) are separate projects
   — either ship an empty table + install instructions, or plan follow-up
   `kicad-data` PRs. State the choice explicitly in the PR description.
7. **CI time budget**: OCCT + KiCad are large; expect CI tweaks
   (`TERMUX_PKG_MAKE_PROCESSES`, possible cancelled-build retries). Note it
   up-front for maintainers.

---

## 8. Build & test path (reproducibility)

Local loop while iterating (validates quickly, no Docker needed):

```sh
bash -n packages/kicad/build.sh            # syntax
# lint (format/metadata checker used by CI):
bash scripts/lint-packages.sh             # from each repo root
git apply --check packages/kicad/patches/*.patch   # against pristine kicad
```

Full official builds happen in Docker per arch inside the repo CI
(`./scripts/run-docker.sh ./build-package.sh kicad`) or on-device via
proot-distro Debian/Ubuntu (following the repo's own on-device-build.md
assuming one still exists; the phone's environment can be reused:
`pkg install proot-distro` + `proot-distro install debian`, then the repo's
`scripts/setup-termux`. Expect hours for occt/kicad on-device).

This sandbox cannot run the Docker arch builds (no Docker here), so the drafts
were validated with `bash -n` and the repo lint script only — the CI build is
the authoritative gate and should be the first thing run on the PR branches.

---

## 9. Out of scope (future work)

- `kicad-data` (symbols/footprints/packages3d/templates) follow-up PRs.
- Termux package versions of the phone-only artifacts (launcher shim,
  desktop entries, prebuilt tarball) already live in this repo's `scripts/`,
  `docs/HANDOFF.md`, and the v1.0 GitHub release — independent of upstreaming.