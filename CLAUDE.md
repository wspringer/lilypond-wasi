# lilypond-wasi

An attempt to build GNU LilyPond to WebAssembly (WASI), **tailing upstream
master** rather than forking it. If it succeeds, this becomes the embedded
engraving backend for `../lilypond-mcp`, making the server runnable with
zero system dependencies.

Target formats: **SVG and EPS**. EPS is LilyPond-native (the ps backend
writes it directly, fonts embedded — no Ghostscript involved), so it works
on WASI provided font files are visible to the module's filesystem. PDF and
PNG are produced by *spawning Ghostscript* and stay native-only — WASI has
no subprocesses. (hlolli's wasi-svg-only-runtime patch cuts the whole PS
path; we adapt it to keep the PS backend and disable only the gs calls.)

## Architecture: tail, don't fork

- Upstream LilyPond is a **pinned flake input** (`lilypond-src`), never a
  checkout we edit. `nix flake update lilypond-src` advances the pin to the
  tip of upstream master.
- All our changes are a **patch series** in `patches/`, applied by
  `nix build .#source`. See `patches/README.md` for the create/rebase recipe.
  Keep patches small and WASI-motivated; the goal is a series short enough to
  become upstream merge requests.
- Toolchain/dependency fixes that don't touch LilyPond itself live in the
  **overlay** inside `flake.nix` (see the zlib errno fix), not in `patches/`.

### Tailing workflow

1. `nix flake update lilypond-src`
2. `nix build .#source` — failure means the patch series no longer applies;
   regenerate the failing patch (recipe in `patches/README.md`)
3. Rebuild the furthest stage previously reached; fix or record what broke
4. Note the upstream rev and outcome in `JOURNAL.md`

## Build stages

Checkpoints, in order. Do not skip ahead: prove each stage with a build (and
where possible a wasmtime run) before starting the next.

1. **Patched source** — `nix build .#source`. Works.
2. **Dependency stack on WASI** — `nix build .#wasi-<name>` in rough
   difficulty order: zlib → expat → freetype → libffi → boehmgc →
   fontconfig → glib → pango → guile. `.#wasi-deps` aggregates all nine.
   Guile is the expected boss fight (JIT, continuations, and BDW-GC all
   assume things WASI doesn't provide).
3. **LilyPond engine** — cross-configure the patched source against the
   stage-2 stack: SVG + PS/EPS backends, Ghostscript-conversion paths
   (PDF/PNG) disabled.
4. **WASI command module** — a `lilypond.wasm` that under
   `wasmtime --dir . lilypond.wasm test.ly` emits an SVG **and a cropped
   EPS with embedded fonts**. This is the success criterion.
5. **Integration** — optional backend for `../lilypond-mcp`.

## Hard-won facts

- The whole stage-2 stack *evaluates* as `*-static-wasm32-unknown-wasip1`
  packages in nixpkgs — the cross machinery exists; expect per-package
  build fixes, collected in the flake overlay.
- zlib needed `#include <errno.h>` injected into gzguts.h (gz* file layer).
- First toolchain build (wasi clang + wasi-libc) takes a long time; later
  builds reuse it from the nix store.
- Prior art: [hlolli/lilypond-wasm](https://github.com/hlolli/lilypond-wasm)
  (`@hlolli/lilypond-wasm` on npm, alpha) — SVG-only by design, WASI first.
  Its ROADMAP.md is a good map of the minefield: the hard part is the
  Guile/GC/Pango/Fontconfig/FreeType stack, not LilyPond's own SVG code.
  Check it before fighting a stage-2 battle; hlolli may have won it already.

## Binary cache

Everything under `wasm32-unknown-wasi` in the store is **unobtainable from
any public cache** — Hydra never builds `pkgsCross.wasi32`, on any nixpkgs
pin. Losing those paths means rebuilding the cross-LLVM toolchain from
source (hours). 2.14 GB across 108 paths; the rest of the 63 GB build
closure is stock nixpkgs that cache.nixos.org serves.

    ./scripts/push-cache.sh [cache-name]     # after: cachix authtoken <t>

Caches are **per-system**: pushing from this laptop banks aarch64-darwin
artifacts only. `.github/workflows/tail-upstream.yml` runs Linux-only by
design — its job is catching upstream drift (system-independent), not
producing Mac artifacts, because macOS runners bill at 10x on a private
repo.

## Conventions

- Record every session's findings (upstream rev, what built, what broke,
  why) in `JOURNAL.md` — negative results included; they are the map.
- Builds happen through the flake only. No ad-hoc `./configure` runs outside
  `nix build`/`nix develop` — reproducibility is the whole point of tailing.
- The devshell has `wasmtime` and `wasm-tools` for running and inspecting
  modules.
