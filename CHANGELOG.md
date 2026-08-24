# Changelog

Recipe changes — the patch series, the WASI overlay, and the build — are
recorded here by Knope from conventional commits. Upstream LilyPond changes
are not: those are visible in `flake.lock` history and in the per-variant
release tags (`dev/<lilypond>-p<recipe>`, `stable/<lilypond>-p<recipe>`).

## 0.1.2 (2026-08-24)

### Features

- self-sufficient releases — Guile ccache tarball + runtime manifest

## 0.1.1 (2026-08-24)

### Features

- precompiled Guile bytecode per variant — startup 4.7s -> 0.9s

## 0.1.0

Initial recipe: two-patch series against upstream LilyPond (optional
cairo/font build; no-subprocess WASI runtime), the wasm32-unknown-wasi
dependency stack (zlib through guile), a 12.9 MB engine for each of the
stable and development lines, and native-built runtime assets.
