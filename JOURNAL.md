# Campaign journal

Newest first. Every entry: upstream rev, what was attempted, outcome.

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
