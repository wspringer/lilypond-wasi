# LilyPond cross-compiled to wasm32-wasi, adapted from hlolli/lilypond-wasm's
# derivation (GPL-3.0-or-later) for our upstream-tailing source and SVG+EPS
# scope. Emits a single statically linked lilypond.wasm.
{
  boehmgc,
  buildPackages,
  cairo,
  expat,
  fontconfig,
  freetype,
  fribidi,
  glib,
  gmp,
  guile,
  harfbuzz,
  lib,
  libffi,
  libpng,
  libunistring,
  pango,
  pcre2,
  src,
  stdenv,
  version,
  zlib,
}:

stdenv.mkDerivation {
  pname = "lilypond-wasi";
  inherit version;

  inherit src;
  # the source tree already carries the ./patches series via .#source

  strictDeps = true;

  nativeBuildInputs = [
    buildPackages.autoconf
    buildPackages.binaryen
    buildPackages.bison
    buildPackages.flex
    buildPackages.gettext
    buildPackages.perl
    buildPackages.pkg-config
    buildPackages.python3
  ];

  buildInputs = [
    boehmgc
    cairo
    expat
    fontconfig
    freetype
    fribidi
    glib
    gmp
    guile
    harfbuzz
    libffi
    libpng
    libunistring
    pango
    pcre2
    zlib
  ];

  configureFlags = [
    "--disable-documentation"
    "--disable-fonts"
    "--disable-gs-api"
    "--with-extractpdfmark=no"
    "--with-flexlexer-dir=${buildPackages.flex}/include"
  ];

  env = {
    NIX_CFLAGS_COMPILE = "-O2 -D_WASI_EMULATED_PROCESS_CLOCKS"
      + " -mexception-handling -mllvm -wasm-enable-sjlj -mllvm -wasm-use-legacy-eh=false";
    # Full Scheme startup needs more than wasm-ld's small default stack.
    NIX_LDFLAGS = "-z,stack-size=8388608";
  };

  LIBS = "-lwasi-emulated-process-clocks -lwasi-emulated-signal -lsetjmp";

  preConfigure = ''
    ./autogen.sh --noconfigure

    # LilyPond's configure checks do not ask pkg-config for private static
    # dependencies. Supply those flags here because every target library is
    # static.
    export BDWGC_CFLAGS="$("$PKG_CONFIG" --cflags bdw-gc)"
    export BDWGC_LIBS="$("$PKG_CONFIG" --static --libs bdw-gc)"
    export CAIRO_CFLAGS="$("$PKG_CONFIG" --cflags cairo)"
    export CAIRO_LIBS="$("$PKG_CONFIG" --static --libs cairo)"
    export FONTCONFIG_CFLAGS="$("$PKG_CONFIG" --cflags fontconfig)"
    export FONTCONFIG_LIBS="$("$PKG_CONFIG" --static --libs fontconfig)"
    export FREETYPE2_CFLAGS="$("$PKG_CONFIG" --cflags freetype2)"
    export FREETYPE2_LIBS="$("$PKG_CONFIG" --static --libs freetype2)"
    export GLIB_CFLAGS="$("$PKG_CONFIG" --cflags glib-2.0)"
    export GLIB_LIBS="$("$PKG_CONFIG" --static --libs glib-2.0)"
    export GOBJECT_CFLAGS="$("$PKG_CONFIG" --cflags gobject-2.0)"
    export GOBJECT_LIBS="$("$PKG_CONFIG" --static --libs gobject-2.0)"
    export GUILE_CFLAGS="$("$PKG_CONFIG" --cflags guile-3.0)"
    export GUILE_LIBS="$("$PKG_CONFIG" --static --libs guile-3.0)"
    export LIBPNG_CFLAGS="$("$PKG_CONFIG" --cflags libpng)"
    export LIBPNG_LIBS="$("$PKG_CONFIG" --static --libs libpng)"
    export PANGO_FT2_CFLAGS="$("$PKG_CONFIG" --cflags pangoft2)"
    export PANGO_FT2_LIBS="$("$PKG_CONFIG" --static --libs pangoft2)"
    export ZLIB_CFLAGS="$("$PKG_CONFIG" --cflags zlib)"
    export ZLIB_LIBS="$("$PKG_CONFIG" --static --libs zlib)"
  '';

  enableParallelBuilding = true;

  buildPhase = ''
    runHook preBuild

    # LilyPond treats an inherited "out" variable as an output-directory
    # suffix. Keep Nix's store output out of the make environment.
    env -u out make -C lily default

    # --fpcast-emu: GObject/Pango cast callbacks between C signatures and
    # wasm checks indirect-call types exactly.
    # --spill-pointers: keep pointer locals visible in linear memory for
    # boehm-gc's conservative scan.
    # --strip-debug -Os: 59 MB -> 13 MB (3.6 MB gzipped), engraved output
    # verified byte-identical (JOURNAL.md 2026-08-22).
    wasm-opt --fpcast-emu --spill-pointers --strip-debug -Os \
      --enable-exception-handling --enable-bulk-memory \
      --enable-nontrapping-float-to-int --enable-sign-ext \
      --enable-multivalue --enable-reference-types \
      lily/out/lilypond \
      -o lilypond.wasm

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    cp lilypond.wasm "$out/bin/lilypond.wasm"
    test -s "$out/bin/lilypond.wasm"
    runHook postInstall
  '';

  dontStrip = true;
  doCheck = false;
  doInstallCheck = false;

  meta = {
    description = "LilyPond (SVG + EPS) linked statically for wasm32-wasi";
    homepage = "https://lilypond.org/";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.all;
  };
}
