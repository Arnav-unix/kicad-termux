# KiCad 10.0.6 native Termux build — session handoff

Device: OPPO A6 Pro 5G, Android API 36, Termux, aarch64, native bionic (NO proot).
Everything below is already running detached; nothing is tied to an agent session.

## Status

| Item | State |
|---|---|
| OCCT 7.8.1 | built + installed, verified native aarch64 |
| libspnav | built + installed |
| libngspice 47 | built + installed |
| unixodbc 2.3.14 | installed from Termux repos |
| KiCad 10.0.6 CMake | `CONFIGURE_RC=0` |
| **kicad-cli** | **BUILT and VERIFIED: `--version` -> `10.0.6`** |
| Full GUI | building now via `ninja install` |

`kicad-cli` lives at `/data/data/com.termux/files/home/kicad-build/build-kicad/kicad/kicad-cli`.
It needs `LD_LIBRARY_PATH` to include the build tree's `api/` dir until install completes.

## Running processes (all PPID 1, survive session close)

- Build supervisor: `~/kicad-build/build-kicad.sh` (guarded by `flock` on `~/kicad-build/run/build.lock`)
- Active command: `ninja install` — this pulls the `all` target, i.e. the GUI
- Live progress watcher: `~/kicad-build/live-progress.sh` (exactly one; runs `PHASE=GUI`)

## How to check status

```sh
cat ~/kicad-build/progress.txt     # live bar: pct, edges, rate, ETA, errors
```

That file is also pushed to a **single Android notification (id 9911)** that is
overwritten in place every 20s and is silent (`--alert-once`). Swipe the shade
any time. Real errors / completion / thermal alerts use id **9912** and do buzz.

Logs:
- `~/kicad-build/logs/kicad-install.log` — current ninja output (GUI phase)
- `~/kicad-build/logs/kicad-run.log` — supervisor log + `KICAD_BUILD_OK` / `KICAD_BUILD_FAIL` markers
- `~/kicad-build/logs/android-patches.diff` — the 3 source patches applied

## User input channel

Vansh can write to `~/seeme.txt` at any time. The watcher notices and notifies.
Clear it after reading (`: > ~/seeme.txt`) so it is not re-reported.

## Android incompatibilities found and fixed (4 real ones)

1. **CMake configure refused to proceed** — "can not find a suitable odbc driver
   manager". Fixed by `apt-get install unixodbc` (it IS packaged; `pkg search`
   misleadingly returned nothing).

2. **`nanodbc`: `std::char_traits<unsigned short>` undefined.**
   Termux's unixODBC defines `SQLWCHAR` as `unsigned short` (built with
   `SQL_WCHART_CONVERT`), and libc++ has no `char_traits` specialization for it.
   Patched `thirdparty/nanodbc/nanodbc/nanodbc.cpp`: rewrote the local `size()`
   helper to count the terminator manually and routed 3 call sites through it.

3. **`bs_thread_pool.hpp`: `pthread_getaffinity_np` / `pthread_setaffinity_np` undeclared.**
   These are `__INTRODUCED_IN(36)` in bionic, gated on `__BIONIC_AVAILABILITY_GUARD(36)`.
   Fixed by compiling with `--target=aarch64-unknown-linux-android36 -D_GNU_SOURCE`
   (verified with a standalone probe that it compiles, links AND runs on this device).
   NOTE: API 26 is NOT enough here — the guard really is 36.

4. **`compoundfilereader`: `std::basic_string<unsigned short>` failed to instantiate.**
   `typedef std::basic_string<uint16_t>` — `uint16_t` is `unsigned short` here.
   Changed to `char16_t` and added a `reinterpret_cast` at the one `append()` call
   that passes a raw `uint16_t*` buffer.

5. **Link failure `undefined reference to ThreadSafeArena::thread_cache_`** (caused by fix #3).
   Termux's protobuf is built for API 24 so it exports that symbol as *emulated* TLS
   (`__emutls_v.*`). Compiling for API 36 makes clang emit *real* TLS, which the
   emutls library cannot satisfy. Fixed surgically with
   `target_compile_options(kiapi PRIVATE -femulated-tls)` in `api/CMakeLists.txt`
   — only 12 rules changed, so no full rebuild. Keep this in mind if protobuf is
   ever upgraded: check `nm -D libprotobuf.so | grep thread_cache_` for `__emutls_`.

## Key scripts

- `~/kicad-build/configure-kicad.sh` — CMake flags (android36 + `_GNU_SOURCE`, PCH, ccache, explicit OCCT/ngspice/SPNAV paths; IPC API, IDF tools, QA, i18n, Wayland, wxPython all OFF)
- `~/kicad-build/build-kicad.sh` — supervised ninja; `TARGET=kicad-cli|all`, `JOBS=n`. Aborts when the *same* target fails twice (avoids pointless retry loops)
- `~/kicad-build/live-progress.sh` — progress/notification watcher
- `~/kicad-build/build-ngspice.sh` — ngspice Android build
- `~/kicad-build/compat/pthread_cancel_compat.h` — no-op `pthread_cancel` (ngspice only; XSPICE Verilog co-sim unsupported, irrelevant to KiCad)

## Gotchas learned (do not repeat these)

- `pgrep -f <script>` and `pkill -f` **self-match** the invoking shell. Kill by
  explicit PID instead. This caused several phantom "extra instances".
- Never `rm -f` a lock file that a running `flock` holder has open — it creates a
  new inode and lets a second builder in. That happened once; two `ninja`s raced
  on the same build dir.
- `ninja install` builds the `all` target, not just what you asked for. That is
  why the GUI started automatically after kicad-cli linked.
- Tool-level `sleep` timeouts do NOT kill detached builds (`setsid nohup`).
- `grep -c 'error:'` over an appended log double-counts across ninja restarts —
  dedupe with `sort -u` before believing an error count.

## Next steps after install finishes

1. Confirm `KICAD_BUILD_OK` in `~/kicad-build/logs/kicad-run.log`.
2. Verify installed binary: `$PREFIX/opt/kicad/bin/kicad-cli --version`.
3. Sanity-test a real operation, e.g. `kicad-cli pcb drc` / `kicad-cli create-project`
   or export a STEP/gerber to prove OCCT + the full stack work.
4. Try launching the GUI (`pcbnew`/`eeschema`) — needs a working display; likely
   `termux-x11` or similar, since wxWidgets GTK3 was used at build time.