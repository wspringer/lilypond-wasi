# Shared by every check: one way to run the engine, and the assertions
# that decide whether its output is any good. Sourced by the runCommand
# scripts in default.nix, which export LILYPOND, ASSETS, BYTECODE, GUILE
# and LILYPOND_VERSION first.

set -euo pipefail

mkdir -p work/home work/tmp work/cache/fontconfig work/lily-lib

# Copy a case into the guest-visible work dir, with \version "@version@"
# filled in from the variant being tested.
stage() {
  sed "s/@version@/$LILYPOND_VERSION/g" "$1" > "work/$(basename "$1")"
}

# engrave <log> <lilypond args...> — runs the engine, logs to <log>, and
# returns the engine's exit code. The mount layout is the runtime contract
# release consumers use; keep it in step with release.yml's usage notes.
engrave() {
  local log="$1"
  shift
  local status=0
  # host-side timeout only: wasmtime's own epoch timers slow this workload
  timeout 300s wasmtime run \
    -W exceptions=y -C cache=n \
    --dir "$PWD/work::/work" \
    --dir "$ASSETS/share/lilypond::/lilypond" \
    --dir "$GUILE/share/guile/3.0::/guile" \
    --dir "$GUILE/lib/guile/3.0/ccache::/guile-ccache" \
    --dir "$BYTECODE/ccache::/lily-ccache" \
    --env FONTCONFIG_FILE=/lilypond/fonts/fonts.conf \
    --env GUILE_LOAD_PATH=/guile \
    --env GUILE_LOAD_COMPILED_PATH=/guile-ccache:/lily-ccache \
    --env GUILE_SYSTEM_PATH=/guile \
    --env GUILE_SYSTEM_COMPILED_PATH=/guile-ccache \
    --env HOME=/work/home \
    --env LILYPOND_DATADIR=/lilypond \
    --env LILYPOND_LIBDIR=/work/lily-lib \
    --env TMPDIR=/work/tmp \
    --env XDG_CACHE_HOME=/work/cache \
    --argv0 /lilypond \
    "$LILYPOND/bin/lilypond.wasm" \
    "$@" > "$log" 2>&1 || status=$?
  cat "$log"
  # LilyPond itself exits 0 or 1. Anything else is the runtime: a wasm
  # trap, an out-of-bounds access, the timeout. Never acceptable.
  if [ "$status" -gt 1 ] || grep -qiE 'wasm (trap|backtrace)' "$log"; then
    fail "engine crashed (exit $status) instead of reporting through LilyPond"
  fi
  return "$status"
}

fail() {
  echo "CHECK FAILED: $*" >&2
  exit 1
}

# A clean engrave: exit 0, LilyPond reports success, and not one warning
# or error on the way — font fallbacks and Scheme hiccups show up here.
assert_clean() {
  local log="$1"
  grep -q 'Success: compilation successfully completed' "$log" \
    || fail "$log: no success line"
  if grep -E '(warning|error):' "$log"; then
    fail "$log: warnings or errors during a clean engrave"
  fi
}

# The EPS path exits 1 by design (see JOURNAL.md): after writing the EPS,
# -dcrop tries a Ghostscript PNG conversion the no-subprocess runtime
# refuses. So: everything before that step must be clean, and the step
# must actually be the one that failed.
assert_clean_until_png() {
  local log="$1"
  grep -q '^Converting to PNG' "$log" \
    || fail "$log: failed before reaching the Ghostscript step"
  if sed '/^Converting to PNG/,$d' "$log" | grep -E '(warning|error):'; then
    fail "$log: warnings or errors before the Ghostscript step"
  fi
  grep -q 'cannot run child process on WASI: gs' "$log" \
    || fail "$log: exited nonzero for a reason other than the known gs wart"
}

assert_svg() {
  local svg="$1"
  test -s "$svg" || fail "$svg: missing or empty"
  xmllint --noout "$svg" || fail "$svg: not well-formed XML"
  # Music glyphs (noteheads, clefs) are drawn as outline paths.
  grep -q '<path' "$svg" || fail "$svg: no glyph outlines"
}

# assert_svg_text <svg> <string> — the string must appear as rendered text.
assert_svg_text() {
  grep -qF -- "$2" "$1" || fail "$1: expected text '$2' not rendered"
}

# assert_eps <eps> <font...> — a cropped EPS embedding exactly the named
# fonts. Exactly, because fontconfig substitutes a missing family silently
# (no warning anywhere): the only trace of a fallback is an unexpected
# font in the embedded set.
assert_eps() {
  local eps="$1"
  shift
  test -s "$eps" || fail "$eps: missing or empty"
  head -n 1 "$eps" | grep -q '^%!PS-Adobe-.* EPSF-' || fail "$eps: not an EPS header"

  local bbox llx lly urx ury
  bbox=$(grep -a -m 1 '^%%BoundingBox:' "$eps") || fail "$eps: no BoundingBox"
  read -r _ llx lly urx ury <<< "$bbox"
  local w=$((urx - llx)) h=$((ury - lly))
  # Cropped means non-empty and smaller than an A4 page (595x842 pt).
  { [ "$w" -gt 0 ] && [ "$h" -gt 0 ]; } || fail "$eps: empty BoundingBox ($bbox)"
  { [ "$w" -lt 595 ] && [ "$h" -lt 842 ]; } || fail "$eps: not cropped ($bbox)"

  local expected supplied embedded
  expected=$(printf '%s\n' "$@" | LC_ALL=C sort)
  supplied=$(sed -n 's/^%%DocumentSuppliedResources: font //p' "$eps" | tr -d '\r' | LC_ALL=C sort)
  # Supplied AND embedded: each needs the font program itself too.
  embedded=$(sed -n 's/^%%BeginFont: //p' "$eps" | tr -d '\r' | LC_ALL=C sort)
  [ "$supplied" = "$expected" ] \
    || fail "$eps: supplied fonts [$(echo $supplied)], expected [$(echo $expected)]"
  [ "$embedded" = "$expected" ] \
    || fail "$eps: embedded fonts [$(echo $embedded)], expected [$(echo $expected)]"
}
