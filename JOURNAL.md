# Campaign journal

Newest first. Every entry: upstream rev, what was attempted, outcome.

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
