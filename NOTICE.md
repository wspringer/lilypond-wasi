# Licensing and attribution

This project is licensed **GPL-3.0-or-later** (see `LICENSE`), and not by
choice of convenience — it is what the contents require:

- `patches/*.patch` modify GNU LilyPond, which is GPL-3.0-or-later. Patches
  to a GPL work are derivative works of it.
- `patches/deps/**` and much of `nix/**` are taken or adapted from
  [hlolli/lilypond-wasm](https://github.com/hlolli/lilypond-wasm) by
  Hlöðver Sigurðsson, also GPL-3.0-or-later.

## Vendored from hlolli/lilypond-wasm

Copyright (C) 2026 Hlöðver Sigurðsson, GPL-3.0-or-later. Used and adapted
here with the version drift noted in `JOURNAL.md`:

| File | Adaptation |
|---|---|
| `patches/0001-optional-cairo-and-font-build.patch` | verbatim; applies clean to 2.27.3 |
| `patches/0002-wasi-runtime-no-subprocess.patch` | verbatim; renamed (it stubs subprocess spawning, not the PS/EPS path) |
| `patches/deps/libffi-wasi.patch` | verbatim |
| `patches/deps/boehm-gc-wasi.patch` | verbatim |
| `patches/deps/gmp-wasi.patch` | verbatim |
| `patches/deps/libunistring-wasi.patch` | verbatim |
| `patches/deps/fontconfig-0001-wasi-cache-locks.patch` | verbatim (applies with offsets) |
| `patches/deps/harfbuzz/*`, `patches/deps/pango/*` | verbatim |
| `patches/deps/glib/*` | **re-derived** for glib 2.86.3 against nixpkgs-patched source |
| `nix/wasi-overlay.nix` | derivation logic adapted from his per-package `nix/*` files |
| `nix/lilypond.nix`, `nix/assets/` | adapted from his `nix/lilypond/{default.nix,assets/}` |

His project targets **SVG only** and bundles a pinned LilyPond source. This
one keeps the PS/EPS path alive and tracks upstream master as a flake input
— see `CLAUDE.md`.

## Third-party runtime data

`nix/assets` stages fonts that carry their own terms: Emmentaler (built from
LilyPond source, GPL-3.0-or-later with font exception), URW base35
(AGPL-3.0 / free), and DejaVu (Bitstream Vera derivative, permissive).
