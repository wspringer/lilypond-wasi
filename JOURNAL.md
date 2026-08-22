# Campaign journal

Newest first. Every entry: upstream rev, what was attempted, outcome.

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
