# Precompiled Guile bytecode for the engine's Scheme modules.
#
# Without this, every engrave pays Guile's startup tax: ~66 LilyPond
# modules compiled from source on read-only mounts where the result cannot
# even be cached (measured ~4.7 s for a trivial score). Here the engine
# runs once under wasmtime with a *writable* datadir, and the .go files it
# produces are harvested into a mountable cache.
#
# Adapted from hlolli/lilypond-wasm's bytecode derivation
# (GPL-3.0-or-later). Bytecode is version-coupled to both LilyPond and
# Guile, hence one of these per variant.
{
  lib,
  runCommand,
  wasmtime,
  # per-variant:
  lilypond,
  assets,
  # the wasi guile these were built against:
  guile,
}:

assert lib.assertMsg (lilypond.version == assets.version)
  "bytecode: engine and assets must be the same variant/version";

runCommand "lilypond-wasi-bytecode-${lilypond.version}"
{
  nativeBuildInputs = [ wasmtime ];
  meta = {
    description = "Precompiled LilyPond Scheme modules for the WASI engine";
    license = lib.licenses.gpl3Plus;
  };
} ''
  set -euo pipefail

  # Writable copy of the datadir: Guile drops auto-compiled files below it
  # (a fixed guest path, so no Nix store path ends up inside the bytecode).
  data="$PWD/lilypond"
  cp -R --preserve=timestamps ${assets}/share/lilypond "$data"
  chmod -R u+w "$data"

  mkdir -p work/home work/tmp work/cache/fontconfig work/lily-lib
  cp ${./compile-all.ly} work/compile-all.ly

  run_engrave() {
    # host-side timeout only: wasmtime's own epoch timers slow this workload
    timeout 300s wasmtime run \
      -W exceptions=y -C cache=n \
      --dir "$PWD/work::/work" \
      --dir "$data::/lilypond" \
      --dir ${guile}/share/guile/3.0::/guile \
      --dir ${guile}/lib/guile/3.0/ccache::/guile-ccache \
      --env FONTCONFIG_FILE=/lilypond/fonts/fonts.conf \
      --env GUILE_AUTO_COMPILE=1 \
      --env GUILE_LOAD_PATH=/guile \
      --env GUILE_LOAD_COMPILED_PATH=/guile-ccache \
      --env GUILE_SYSTEM_PATH=/guile \
      --env GUILE_SYSTEM_COMPILED_PATH=/guile-ccache \
      --env HOME=/work/home \
      --env LILYPOND_DATADIR=/lilypond \
      --env LILYPOND_LIBDIR=/work/lily-lib \
      --env TMPDIR=/work/tmp \
      --env XDG_CACHE_HOME=/work/cache \
      --argv0 /lilypond \
      ${lilypond}/bin/lilypond.wasm \
      "$@"
  }

  # SVG pass — must succeed and produce output. The driver's use-modules
  # also pulls the PS/EPS modules through the compiler.
  run_engrave --formats=svg -o /work/compile-all /work/compile-all.ly
  test -s work/compile-all.svg

  # EPS pass — catches modules the PS path loads lazily at engrave time.
  # KNOWN WART (see JOURNAL.md): this run exits nonzero AFTER writing its
  # output, because -dcrop tries a Ghostscript PNG conversion that the
  # no-subprocess runtime refuses. Tolerate the exit code, insist on the
  # artifact.
  run_engrave -dbackend=ps -dcrop --formats=eps -o /work/compile-eps /work/compile-all.ly || true
  test -s work/compile-eps.cropped.eps

  # Cairo pass — PDF and PNG straight from the engine, no subprocesses.
  run_engrave -dbackend=cairo -dcrop --formats=pdf,png -o /work/compile-cairo /work/compile-all.ly
  test -s work/compile-cairo.cropped.pdf

  generated="$data/guile-bytecode"
  test -d "$generated"

  mkdir -p "$out/ccache/lily"
  find "$generated" -type f -name '*.scm.go' | LC_ALL=C sort | while IFS= read -r compiled; do
    module="$(basename "$compiled" .scm.go)"
    source="${assets}/share/lilypond/scm/lily/$module.scm"
    dest="$out/ccache/lily/$module.go"

    if [ ! -f "$source" ]; then
      echo "compiled file has no source in the assets: $compiled" >&2
      exit 1
    fi
    if [ -e "$dest" ]; then
      echo "module name collision: $module" >&2
      exit 1
    fi

    cp "$compiled" "$dest"
    # Guile only accepts bytecode at least as new as its source. Nix
    # normalizes store mtimes and Guile treats equal mtimes as fresh.
    touch -r "$source" "$dest"
    chmod 0444 "$dest"
  done

  # A partial cache silently reintroduces the startup tax; startup + both
  # backends load ~66 modules today. Floor, not exact count, so upstream
  # can add modules without an edit here — but can never ship half a cache.
  count="$(find "$out/ccache/lily" -maxdepth 1 -type f -name '*.go' | wc -l)"
  if [ "$count" -lt 66 ]; then
    echo "expected at least 66 compiled modules, got $count" >&2
    exit 1
  fi

  for required in lily backend-library font-encodings \
    framework-svg output-svg framework-ps output-ps framework-cairo page paper-system; do
    if [ ! -f "$out/ccache/lily/$required.go" ]; then
      echo "required module missing from bytecode cache: $required" >&2
      exit 1
    fi
  done

  echo "cached $count modules"
''
