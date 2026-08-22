# Campaign journal

Newest first. Every entry: upstream rev, what was attempted, outcome.

## 2026-08-22 — module size: 59 MB -> 12.9 MB (3.6 MB gzipped)

`wasm-opt --strip-debug -Os` on top of the correctness passes; ~78% of
the module was DWARF. Engraved EPS verified byte-identical before and
after; now baked into nix/lilypond.nix (with explicit --enable-* feature
flags so binaryen parses the EH opcodes). Deliverable footprint: ~13 MB
engine + 13 MB assets + Guile Scheme tree; <10 MB compressed transport.

## 2026-08-22 — field test in InDesign: EPS out, PDF in

Placing the wasm-engraved EPS in InDesign: **glyphs vanish** — InDesign
ignores LilyPond's %%BeginFont/Resource-FontSet embedding (native EPS uses
the identical format, so this was a latent booklet-pipeline bug too, found
only by actually placing a file). Ghostscript pdfwrite re-embedding places
perfectly once CropBox/BleedBox/TrimBox/ArtBox are all defined (InDesign
crops to whichever box the Place dialog last used; undefined boxes throw
"Cannot crop to bleed box").

Consequences: lilypond-mcp now stamps boxes on every cropped PDF and
recommends PDF for layout placement; analog places build/pdf/. The wasm
engine keeps emitting EPS (it cannot run gs) — its consumers convert
host-side when Adobe apps are the destination. EPS remains correct for
Ghostscript-based flows.

## 2026-08-22 — STAGE 4: SUCCESS CRITERION MET. SVG + EPS engraved on wasm.

`wasmtime -W exceptions=y` with the mounts/env from nix/assets +
hlolli's runner recipe (see below) engraved test.ly to:
- `test.svg` (4.2 KB), and
- `test.cropped.eps` — BoundingBox 0 -37 74 1, **identical to the native
  pipeline's**, Emmentaler-20 + C059-Roman embedded, renders clean
  through Ghostscript.

The assets derivation (nix/assets, adapted from hlolli) builds Emmentaler
natively with fontforge/metapost from OUR source tree, stages scm/ + ly/ +
text fonts (URW base35 + DejaVu) + fonts.conf — plus `ps/` (the PostScript
prologs), which the SVG-only original omitted and EPS needs at engrave
time.

Invocation essentials (full recipe in the runner): mount work dir,
assets tree at /lilypond, guile's share/guile/3.0 and ccache; env
LILYPOND_DATADIR=/lilypond, GUILE_LOAD_PATH/=COMPILED_PATH,
FONTCONFIG_FILE=/lilypond/fonts/fonts.conf, HOME/TMPDIR/XDG_CACHE_HOME
into the work dir; `--argv0 /lilypond`.

Known warts, non-blocking:
- EPS run exits nonzero AFTER writing the .eps: the -dcrop pipeline tries
  a PNG preview via Ghostscript, which our no-subprocess stub fails.
  Output is complete; fix later (skip png conversion when spawning is
  unavailable) — candidate patch in scm/backend-library.
- Auto-compile warnings when the datadir mount is read-only: harmless;
  the precompiled-bytecode derivation (hlolli's nix/lilypond/bytecode)
  is the proper fix and also cuts startup time.

Stage 5 remaining: a wrapper script/runner packaging module + assets +
guile mounts, wasm-opt size trimming maybe, then the lilypond-mcp backend.

## 2026-08-22 — STAGE 3 COMPLETE: lilypond.wasm links AND RUNS

`nix build .#lilypond` → 62 MB `lilypond.wasm`, and
`wasmtime -W exceptions=y lilypond.wasm --version` prints
"GNU LilyPond 2.27.3 (running Guile 3.0)" — upstream master of 2026-08-21,
Guile bootstrapping inside wasm. Four rounds:

1. libpng: sjlj flags + `-lsetjmp` (sjlj lowering calls `__wasm_setjmp`
   from wasi-libc's libsetjmp);
2. libpng again: contrib test binaries want tmpfile() → library-only build;
3. lily compile: `libguile.h` not found — guile's .pc needed hlolli's
   surgery (includedir=$dev, -L paths for static private deps ffi/gmp/
   unistring, Cflags with emulated-signal + dep includes);
4. Linked. hlolli's two LilyPond patches applied **clean to 2.27.3**;
   his "svg-only" runtime patch turned out EPS-compatible all along (it
   only stubs subprocess spawning — EPS never spawns; installed as
   patches/0002-wasi-runtime-no-subprocess.patch).

The final link needs `wasm-opt --fpcast-emu --spill-pointers` (GObject
callback casts; boehm-gc needs pointer locals in linear memory) and an
EH-enabled engine (`wasmtime -W exceptions=y`).

Stage 4 remaining: runtime data — the Scheme library (scm/, ly/),
Emmentaler + text fonts from a native LilyPond build, fonts.conf — mounted
via `wasmtime --dir`, then engrave test.ly → SVG + cropped EPS. hlolli's
nix/lilypond/{assets,bytecode} dirs are the reference.

## 2026-08-22 — checkpoint 9 DONE: wasi-guile. STAGE 2 COMPLETE.

`libguile-3.0.a`, members verified `\0asm`. `nix build .#wasi-deps` links
the whole nine-package farm. Seven rounds against the boss:

1. nixpkgs' savannah c117f8e cross patch is already merged in guile 3.0.11
   → filter it from old.patches (and drop the autoreconfHook that existed
   only for it; rerunning autoconf dies on missing pkg.m4).
2. gmp: hlolli's patch + --disable-assembly + alloca on the heap. Clean.
3. libunistring: skip the test helpers (gnulib signal wrapper). BUT a
   space inside a makeFlags element silently becomes extra make goals and
   installs NOTHING — use `makeFlagsArray+=(...)` in preBuild.
4. guile configure: my nativeBuildInputs filter on "wrapper" also removed
   the *pkg-config wrapper* → libffi undetectable. Filter "shell-wrapper".
5. ports.c: POLLPRI doesn't exist in wasi-libc's poll.h → -DPOLLPRI=0.
6. …which, added inside a configureFlags element, hit the SAME
   spaces-in-list trap as (3). CPPFLAGS as an env attr instead.
7. Victory.

**Rule now twice-paid: no spaces inside nix list elements — makeFlags,
configureFlags, any of them.**

Stage 3 is next: cross-configure the patched LilyPond source (SVG backend
only) against this stack. Remember from hlolli: the final linked module
needs `wasm-opt --fpcast-emu` (GObject/Pango callback casts) and an
EH-capable engine (sjlj/exnref).

## 2026-08-22 — checkpoint 8 DONE: wasi-pango (+ harfbuzz, fribidi)

- EH-format unification: every archive in the stack now compiles with the
  same `-mexception-handling -mllvm -wasm-enable-sjlj -mllvm
  -wasm-use-legacy-eh=false` (mixing formats breaks the final link; hlolli's
  harfbuzz notes this). freetype/fontconfig rebuilt to match.
- harfbuzz 12.3.0: hlolli's meson flag list needed pruning (png/raster/
  subset/vector/zlib options no longer exist) and chafa=disabled added.
- pango: nixpkgs sets `env.FONTCONFIG_FILE = makeFontsConf ...` which drags
  a fonts.conf derivation that tries to read our (empty) fontconfig $out —
  and replacing `env` wholesale did NOT remove it; needed explicit
  `FONTCONFIG_FILE = null` at the top level of overrideAttrs.
- The empty-declared-output dance (`for o in $outputs; do mkdir -p ...`)
  is now the standard closing move for every tool-less library build.

Remaining: guile — the boss. hlolli's kit: guile-wasi.patch,
guile-wasm-callbacks.patch, plus gmp-wasi.patch and libunistring-wasi.patch.

## 2026-08-22 — checkpoint 7 DONE: wasi-glib (libglib + libgobject + libgio)

The hardest adaptation yet. hlolli's nine-patch series was written for an
older glib; ours is 2.86.3. What changed:

- his 0001 hunks: `process_spawn_allowed` no longer exists (spawn is
  auto-detected); `subdir()` list moved. Regenerated.
- patches 0002–0009 squashed into one `0002-wasi-support.patch`,
  **generated against nixpkgs-patched source** — nixpkgs' own glib patches
  (split-dev-programs, gdb_script) change gobject/meson.build context, so
  patching against pristine source fails in the sandbox. (Also: gdb_script
  has a malformed second diff header GNU patch <2.8 can't parse locally.)
- 2.86.3-specific fixes: three-way guard in g_on_error_stack_trace (the
  non-unix branch is Windows-only code), g_test_trap_fork guard,
  gobject-query wrapped, and **gspawn-posix.c excluded from wasi sources**
  — g_spawn_* stays unresolved in the archive; the final module must not
  reference it.
- pcre2: library-only build (pcre2grep needs fork/sys/wait.h).
- Beware `.orig`/`.rej` litter when regenerating patches from a scratch
  tree — it ends up inside `git diff` and breaks sandbox patching.

Remaining: pango (needs harfbuzz + fribidi), then guile — the boss.

## 2026-08-22 — checkpoints 4+5+6 DONE: wasi-libffi, wasi-boehmgc, wasi-fontconfig

libffi and boehm-gc: hlolli's patches applied cleanly, built first try
(libffi's stock wasm backend is Emscripten-only; boehm-gc needed WASI in
gcconfig.h plus `--disable-threads --disable-cplusplus`).

fontconfig took adaptation — his derivation targets a different fontconfig:
- his snprintf-configure patch is obsolete in 2.17.1 (dropped upstream);
- his library-only buildPhase references an `fc-const` dir that no longer
  exists; 2.17.1 wants `make -C fc-case`, `-C fc-lang`, then the alias +
  fcobjshash headers in src/, then `libfontconfig.la`;
- the cache-locks patch (fcntl F_* constants) applied with offsets;
- multi-output bookkeeping: `bin`/`out` must exist even when empty, and the
  archive lands in the `lib` output, not `out`.
Lesson: **his patches transfer; his build phases need re-deriving per
version.**

## 2026-08-22 — checkpoints 2+3 DONE: wasi-expat, wasi-freetype

Iteration is minutes now. The recurring WASI pattern is confirmed:
**libraries build; the packages' auxiliary CLI tools break** on POSIX APIs
wasi-libc lacks. Fixes, all in the overlay:

- expat: `--without-tests --without-examples --without-xmlwf` (benchmark
  needs `clock()`).
- brotli: `#define chown(p,o,g) 0` for the CLI plus
  `-D_WASI_EMULATED_PROCESS_CLOCKS` / `-lwasi-emulated-process-clocks` —
  the wasi-libc emulation libraries are the idiomatic fix for clock/signal.
- freetype: built **lean** — no libpng (color-emoji glyphs), no brotli
  (WOFF2), no bzip2 (.pcf.bz2), none needed for SVG engraving. Killed
  `freetype-config` (its postInstall references a *target-platform*
  pkg-config, and makeWrapper's hook drags in a broken target bash).
- **setjmp reached earlier than expected**: FreeType's validators use it,
  not just Guile. wasi-libc gates `<setjmp.h>` on
  `__wasm_exception_handling__`; building with
  `-mexception-handling -mllvm -wasm-enable-sjlj` works. Consequence:
  those objects require an EH-capable engine at runtime (recent wasmtime).
  This is the template for the Guile fight.

## 2026-08-22 — checkpoint 1 DONE: wasi-zlib builds (and the great overlay confession)

`nix build .#wasi-zlib` → `libz.a` whose members start with `\0asm`. Three
fixes, all in the flake overlay:

1. `#include <errno.h>` into gzguts.h (wasi-libc strictness);
2. `NIX_LDFLAGS = ""` — nixpkgs' zlib sets `--undefined-version` whenever
   the linker is lld ≥ 16 (zlib#960 workaround); wasm-ld *is* lld but
   rejects the flag. The failure only hits the example binaries, but that
   fails the build. (A sed on `configure` was the wrong fix — the flag came
   from the derivation env, not configure.)
3. **Scope overlays to the wasi target.** An unscoped `zlib = ...` in the
   overlay also replaced the *native* zlib — native LLVM links zlib, so the
   entire native toolchain rebuilt from source. Nearly all of the ~5h of
   LLVM/clang grinding across both pins was this, self-inflicted, not an
   inherent cross-compilation cost. With the overlay guarded by
   `prev.stdenv.hostPlatform.isWasi`, the same build needed **1 local
   derivation** + 139 MiB of cache downloads.

Also: a transient `nix build` exit-1 after an LLVM pass (cause unknown,
disk fine); resuming was lossless.

## 2026-08-21 — nixpkgs repinned to hlolli's rev; first build abandoned

The `wasi-zlib` build on nixos-unstable (`ffb3c9b`) ran ~2.5h through the
darwin bootstrap (LLVM ×2, clang ×2, full stdenv — none of the cross-target
variants are in any binary cache, on any pin) and a `--dry-run` then revealed
64 derivations still ahead, including a **full rustc bootstrap**: current
nixpkgs' wasi32 stdenv pulls in Rust-based component-model tooling
(wasm-tools, wit-bindgen, wkg). Dry-run against hlolli's pin (`4db2c22`):
414 drvs but zero Rust, 330 MiB substitutable, and it is the dep-world his
guile/gmp/libffi derivations are proven against. Repinned; killed the build.
The abandoned toolchain remains in the local store if we ever return.
Lesson for the tail workflow: **dry-run first, always** — count the world
before building it.

## 2026-08-21 — recon of hlolli/lilypond-wasm

The prior-art repo has already fought most of stage 2: full nix derivations
under `nix/` for guile (+ `guile-wasi.patch`, `guile-wasm-callbacks.patch`),
boehm-gc, gmp, libffi, libunistring (each with a `-wasi.patch`), plus
freetype/fontconfig/glib/pango/harfbuzz/fribidi/pcre2/expat/zlib/libpng —
and only **two** patches against LilyPond itself:
`0001-optional-cairo-and-font-build.patch` and
`0002-wasi-svg-only-runtime.patch`. Strategy implication: before writing any
stage-2 fix from scratch, try adapting his derivation/patch (check licensing
when vendoring). Our project still differs in tailing upstream master via a
flake input rather than a bundled source.

## 2026-08-21 — project start

Upstream pin: `6069e16` (master, 2.27.3 dev, fetched 2026-08-21).

- Stage 1 works: `nix build .#source` applies the (empty) patch series to
  upstream tip; VERSION confirms 2.27.3 / stable 2.26.0.
- Whole stage-2 stack evaluates as `*-static-wasm32-unknown-wasip1` in
  nixpkgs `ffb3c9b` (2026-08-19) on aarch64-darwin — including guile 3.0.11.
- `wasi-zlib` build attempt #1 failed: gz* file layer uses `errno` without
  including `<errno.h>`; wasi-libc doesn't provide it transitively. Fixed
  with a one-line sed in the flake overlay. Attempt #2 spent its first
  10+ minutes building the wasi clang/wasi-libc toolchain from source
  (expected one-time cost); result pending.
