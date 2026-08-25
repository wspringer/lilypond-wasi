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

Automated. `.github/workflows/update-upstream.yml` runs Mondays 06:00 UTC,
one job per variant:

1. `nix flake update <input>` — advance the pin to that branch's tip
2. `nix build .#source…` — **does the patch series still apply?**
3. `nix build .#<engine>` — does it still build?
4. Open a PR with the before/after revisions and those results

A PR appears only when the checks pass; if a patch stops applying, the
workflow goes red instead and the failing hunk is in the log. Adoption
stays deliberate — you merge. One PR per variant, so a break in the
development series never blocks a stable-series update.

Note: PRs opened with `GITHUB_TOKEN` do not trigger other workflows, which
is why verification happens *inside* the update job rather than relying on
`build.yml` to run on the PR. Set a `GH_PAT` secret to get CI on these PRs
too.

Doing it by hand is the same three commands:

    nix flake update lilypond-src
    nix build .#lilypond
    git commit flake.lock

When a patch no longer applies, regenerate it (recipe in
`patches/README.md`) and record what upstream changed in `JOURNAL.md`.

## Variants and versioning

Two LilyPond generations are tracked, sharing one patch series and one WASI
dependency stack:

| Output | Branch | Version |
|---|---|---|
| `.#lilypond`, `.#assets` | `master` (dev, becomes 2.28) | 2.27.x |
| `.#lilypond-stable`, `.#assets-stable` | `stable/2.26` | 2.26.x |

LilyPond uses even minors for stable, odd for development. The stable line
matches what nixpkgs ships and what analog's native pipeline engraves with;
master is the tailing target and the branch patches would be upstreamed to.
Both patches applied clean to both generations (verified 2026-08-24) — if
that ever stops being true, split into `patches/` and `patches-stable/`.

**Never hardcode a version.** It is read from upstream's own `VERSION` file
and suffixed with the pinned revision — `2.27.3+g6069e16` — so it cannot
drift from what was actually built. A flake-level assert requires
`lilypond.version == assets.version`: the engine loads its Scheme library
out of the asset tree, and mixing generations fails confusingly at run time.

## Releasing

Two independent things trigger a release — **upstream moving** or **our own
recipe changing** (patches, overlay, build flags) — so no single number can
describe one. The tag carries both axes, and there is one release stream per
variant:

    stable/2.26.1-p0.1.0     LilyPond 2.26.1, stable line, recipe 0.1.0
    dev/2.27.4-p0.1.0        LilyPond 2.27.4, development line, same recipe

Consequences worth understanding:

- **One variant per release.** If master moves and stable does not, only a
  `dev/*` release is cut. A combined release would republish a byte-identical
  stable artifact under a new name, implying a change that did not happen.
- **`dev/*` publishes as a pre-release**, so GitHub's "Latest" is always the
  stable line — matching what LilyPond means by its two series.
- **The recipe version lives in `./recipe-version`** and is asserted against
  the tag; so is the upstream version, against what the pin actually builds.
  A tag cannot misdescribe its contents — the release fails first.
- The workflow **engraves a score under wasmtime before publishing**. A
  module that cannot engrave never becomes a release.

The recipe version is managed by **Knope** (`knope.toml`): change files
in `.changeset/` describing our patches/overlay/build keep a
bot-maintained release PR up to date; merging it bumps `recipe-version`
and `CHANGELOG.md`. Knope never touches the per-variant release tags —
it cannot know LilyPond versions.

Releases are cut mechanically by `tag-releases.yml`: whenever `flake.lock`
or `recipe-version` changes on main, it derives `<variant>/<lilypond>-p<recipe>`
per variant and dispatches release.yml for any tag that does not exist yet.
Merging an upstream PR or the knope release PR *is* the release decision —
no manual tagging. (Change-file discipline matters here: a PR without a
change file does not bump the recipe, so it does not re-release anything —
which is exactly right for journal entries, workflow tuning, and the
automated upstream pin bumps.)


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

Of the wasm32-unknown-wasi build closure (77 output paths):

- **9 come from cache.nixos.org** — the stock cross toolchain (wasilibc,
  clang-wrapper, compiler-rt, libcxx, the binutils/pkg-config wrappers).
  Hydra *does* build these. Correction to an earlier claim in this file:
  they were never at risk.
- **68 exist only in our cache** — everything the overlay patches or
  reflags, plus the engine and assets. Those are the ones worth pushing.

    ./scripts/push-cache.sh [cache-name]     # after: cachix authtoken <t>

Cachix skips anything already on cache.nixos.org, so the push naturally
uploads only the 68.

Consumers must pass `--accept-flake-config` (or add the substituter to
their own nix.conf) for the flake's `nixConfig` to take effect; Nix
ignores untrusted flake settings by default.

    ./scripts/push-cache.sh [cache-name]     # after: cachix authtoken <t>


Caches are **per-system**: pushing from this laptop banks aarch64-darwin
artifacts only. `.github/workflows/tail-upstream.yml` runs Linux-only by
design — its job is catching upstream drift (system-independent), not
producing Mac artifacts, because macOS runners bill at 10x on a private
repo.

## Conventions

- **Change files carry recipe-release semantics.** Any PR that changes
  what gets built (patches, overlay, build flags, artifact contents) must
  include a change file — `knope document-change`, or by hand in
  `.changeset/<slug>.md`:

  ```markdown
  ---
  default: patch
  ---

  #### One-line summary for the changelog
  ```

  Change files survive squash merges structurally (they are files in the
  PR), allow several changelog entries per PR, and Knope consumes them at
  release. Bump types, in recipe terms:
  - `patch` — a correction to the recipe. Re-releases **both** variants.
  - `minor` — new recipe capability (a new format, a new package in the
    stack). Re-releases both variants.
  - `major` — consumers must adapt (artifact naming, runtime contract,
    mount layout).
- **No change file means no recipe bump and no release** — correct for
  journal entries, workflow tuning, documentation. Deliberately also
  correct for the automated upstream PRs: pin bumps are releases of the
  *upstream* axis, not the recipe — never add a change file to one.
- **Conventional commit subjects stay** (`fix:`, `feat:`, `chore:`, …) as
  hygiene: squash merges use the PR title as the commit subject, and a
  readable history matters. They just no longer decide versions.
- Record every session's findings (upstream rev, what built, what broke,
  why) in `JOURNAL.md` — negative results included; they are the map.
- Builds happen through the flake only. No ad-hoc `./configure` runs outside
  `nix build`/`nix develop` — reproducibility is the whole point of tailing.
- The devshell has `wasmtime` and `wasm-tools` for running and inspecting
  modules.
