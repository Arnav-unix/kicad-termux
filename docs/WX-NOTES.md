# wxWidgets Notes for KiCad on Termux

Findings from diagnosing a `SIGABRT` crash in KiCad's file dialog on Termux, plus a
**wxWidgets 3.3.4 ABI break that breaks any hand-built binary**, including the
prebuilt tarball shipped with this repo.

Read this before building KiCad here, or if your build suddenly stops launching
after a `pkg upgrade`.

---

## 1. wxwidgets 3.3.4 is an ABI break (important)

Upgrading wxwidgets from **3.3.1** to **3.3.4** makes KiCad 10.0.6 fail to launch.
This is a **link-time failure**, not a crash:

```
cannot locate symbol "_ZNK8wxDialog7IsModalEv"  referenced by kicad
cannot locate symbol "_ZN13wxGLCanvasEGLD2Ev"    referenced by libkigal.so.10.0.6
```

Both `kicad` (the project manager) and `kicad-cli` are affected.

### What changed

| Symbol | Status in 3.3.4 | Effect on an existing binary |
|---|---|---|
| `wxDialog::IsModal()` | Now **pure virtual** — `wx/dialog.h:75` | Fails to **link**. Source-compatible, only binary-incompatible. |
| `wxGLCanvas::EGL()` | **Removed from the API** — no declaration in `wx/glcanvas.h` | Fails to **link**, and prevents a clean **recompile**. |

Verify on your own device:

```sh
nm -D $PREFIX/lib/libwx_gtk3u_core-3.3.so | grep -c IsModal   # 0 on 3.3.4
grep -n 'wxHAS_EGL' $PREFIX/include/wx-*/wx/setup.h            # still defined as 1
```

### Why a plain rebuild does not fix it

The nasty part is `wxGLCanvas::EGL()`. Downstream code that calls it is normally
guarded on `wxHAS_EGL`, and Termux's build **still defines `wxHAS_EGL 1`**. So
KiCad's guarded code still references a function that no longer exists, and the
**compile fails** — not just the link.

So rebuilding KiCad against 3.3.4 requires **patching KiCad's source** to stop
calling `wxGLCanvas::EGL()`. Treat it as a small port, not a clean rebuild.

### Scope: who is affected

This is **not** a Termux packaging defect. Termux rebuilds its own packages
together when a dependency is bumped, so in-repo packages stay consistent.
The break only hits **hand-built, out-of-tree binaries** — which is exactly what
the prebuilt tarball in this repo is.

Anyone building software from source against Termux's `wxwidgets` must rebuild
after every wx major/minor bump.

---

## 2. The file dialog crash (intermittent, not reproducible)

KiCad's **Open Project** / **Ctrl+O** would abort:

```
wxFileDialog::ShowModal() -> gtk_native_dialog_run -> gtk_native_dialog_show
  -> gtk_window_present_with_time -> gtk_widget_show
  -> g_signal_emit_by_name / g_signal_emit_valist / g_signal_emit
  -> g_object_new -> <frame in libgio-2.0.so> -> g_log -> g_logv -> abort()
```

Signal 6 (`SIGABRT`), code -1 (`SI_QUEUE`). No `Abort message:` line in the
tombstone, and stderr is empty — GLib aborts without printing a diagnostic.

wxWidgets 3.3 switched `wxFileDialog`/`wxDirDialog` to `GtkFileChooserNative`
(wxWidgets PR #25152, commit `071b4dd`, Feb 2025), which is the path in the
trace.

### Status: could not reproduce

- Small C programs calling `gtk_file_chooser_native_new()` + `gtk_native_dialog_run()`
  and `gtk_file_chooser_dialog_new()` + `gtk_dialog_run()` both ran cleanly.
- A Termux maintainer could not reproduce it with a standalone `wxFileDialog`
  sample either, and suggested it may be KiCad-specific rather than a wx bug.
- The reporter eventually **did** open the dialog successfully, with no change we
  could identify — so the failure is intermittent, not deterministic.

Because there is no reliable reproducer, this was reported and closed upstream:

**https://github.com/termux/termux-packages/issues/32350**

If you hit a reproducible case, the tombstone above is the useful artifact —
please add it to that issue.

### Workarounds that do work

- Open projects by path on the command line — avoids the dialog entirely.
- Use the `kopen` script shipped in this repo (see below).
- Inside KiCad, the **recent projects** list on the start page does not use the
  crashing path.

---

## 3. `kopen` — open a project without the dialog

```sh
cp /sdcard/KiCad-Termux/kopen $PREFIX/bin/ && chmod +x $PREFIX/bin/kopen
```

| Command | Effect |
|---|---|
| `kopen` | Reopen the last project used |
| `kopen ~/dir` | Open the project in `~/dir`, or create one if empty |
| `kopen --new ~/dir` | Force-create a fresh empty project |
| `kopen ~/dir/file.kicad_pro` | Open that file directly |

It picks the right tool automatically: `kicad` for `.kicad_pro`,
`eeschema` for `.kicad_sch`, `pcbnew` for `.kicad_pcb`.

If a `kicad_pro` is missing it writes a minimal valid one, so a folder holding
only a `.kicad_sch` or `.kicad_pcb` still opens sensibly.

---

## 4. Rebuilding here

Recipes live in `termux-recipes/` in this repo:

- `x11-packages/kicad/` — KiCad 10.0.6, with the Android portability patches
- `x11-packages/occt/` — OCCT 7.8.1
- `x11-packages/libspnav/` — libspnav 0.5
- `packages/ngspice/` — ngspice 47

Build scripts are in `scripts/` (`build-kicad.sh`, `build-occt.sh`,
`build-libspnav.sh`, `build-ngspice.sh`).

Remember: building against wx 3.3.4 additionally needs the
`wxGLCanvas::EGL()` patch described in section 1.

---

## 5. Related upstream issues

- termux-packages [#32350](https://github.com/termux/termux-packages/issues/32350)
  — this file dialog crash (closed, not reproducible)
- termux-packages [#27745](https://github.com/termux/termux-packages/issues/27745)
  — `[Package]: Kicad`, an upstream request for a KiCad package
- wxWidgets [#25152](https://github.com/wxWidgets/wxWidgets/pull/25152) — the
  change that introduced `GtkFileChooserNative` for `wxFileDialog`