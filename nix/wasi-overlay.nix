# WASI-target fixes for the LilyPond dependency stack.
#
# Applied via pkgsCross.wasi32.extend. Overlays apply to EVERY stage of a
# cross package set, so the whole overlay is guarded on the wasi target —
# touching native packages changes their hashes and cascades into rebuilding
# the native toolchain from source (see JOURNAL.md 2026-08-22, the great
# overlay confession).
#
# Recurring WASI patterns:
# - libraries build; packages' auxiliary CLI tools break on POSIX APIs
#   wasi-libc lacks (clock, chown, signals, file locks) → disable the tools
#   or link wasi-libc's emulation libraries (-lwasi-emulated-*);
# - setjmp/longjmp needs the wasm exception-handling proposal:
#   `-mexception-handling -mllvm -wasm-enable-sjlj`, and an EH-capable
#   engine at runtime;
# - several patches adopted from hlolli/lilypond-wasm (GPL-3.0-or-later),
#   which pins the same nixpkgs rev — see patches/deps/.
{ lib }: final: prev:

if !prev.stdenv.hostPlatform.isWasi then
  { }
else
  {
    zlib = prev.zlib.overrideAttrs (old: {
      # gz* file layer uses errno without including <errno.h>
      postPatch = (old.postPatch or "") + ''
        sed -i '1i #include <errno.h>' gzguts.h
      '';
      # nixpkgs sets NIX_LDFLAGS = "--undefined-version" whenever the linker
      # is lld >= 16 (zlib#960 workaround); wasm-ld rejects the flag.
      env = (old.env or { }) // { NIX_LDFLAGS = ""; };
    });

    expat = prev.expat.overrideAttrs (old: {
      # the benchmark tool needs clock(); skip tools entirely
      configureFlags = (old.configureFlags or [ ]) ++ [
        "--without-tests"
        "--without-examples"
        "--without-xmlwf"
      ];
    });

    brotli = prev.brotli.overrideAttrs (old: {
      # the brotli CLI calls chown() (absent from wasi-libc) and clock()
      postPatch = (old.postPatch or "") + ''
        sed -i '1i #define chown(p,o,g) 0' c/tools/brotli.c
      '';
      env = (old.env or { }) // {
        NIX_CFLAGS_COMPILE = "-D_WASI_EMULATED_PROCESS_CLOCKS";
        NIX_LDFLAGS = "-lwasi-emulated-process-clocks";
      };
    });

    # Lean FreeType: no libpng (color-emoji glyphs), no brotli (WOFF2), no
    # bzip2 (.pcf.bz2) — an SVG music engraver needs none of them, and
    # libpng would drag setjmp in through a second door.
    freetype = prev.freetype.overrideAttrs (old: {
      buildInputs = [ ];
      propagatedBuildInputs = [ final.zlib ];
      configureFlags =
        # freetype-config would drag a *target* pkg-config and bash into
        # the closure (upstream postInstall); nothing needs the script.
        builtins.filter (f: f != "--enable-freetype-config") (old.configureFlags or [ ])
        ++ [
          "--with-png=no"
          "--with-brotli=no"
          "--with-harfbuzz=no"
          "--with-bzip2=no"
        ];
      postInstall = "";
      nativeBuildInputs =
        builtins.filter (d: !(lib.hasInfix "wrapper" (d.name or "")))
          (old.nativeBuildInputs or [ ]);
      # FreeType's validators use setjmp
      env = (old.env or { }) // {
        NIX_CFLAGS_COMPILE = "-mexception-handling -mllvm -wasm-enable-sjlj";
      };
    });

    # libffi's wasm backend targets Emscripten; hlolli's patch makes it
    # speak WASI: typed scalar calls for 0-4 args, other CIFs rejected.
    libffi = prev.libffi.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ../patches/deps/libffi-wasi.patch ];
      configureFlags = (old.configureFlags or [ ]) ++ [ "--disable-multi-os-directory" ];
      doCheck = false;
    });

    # boehm-gc knows no WASI; hlolli's patch teaches gcconfig.h the platform
    # (single-threaded, no signals, no incremental collection).
    boehmgc = prev.boehmgc.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ../patches/deps/boehm-gc-wasi.patch ];
      configureFlags = (old.configureFlags or [ ]) ++ [
        "--disable-cplusplus"
        "--disable-threads"
      ];
      doCheck = false;
    });

    # Fontconfig: WASI has no file locking (fcntl F_* constants) — patched
    # out of the cache code — and the fc-* CLI tools need process APIs, so
    # only the static library and its generated tables are built.
    # (Build phases re-derived for 2.17.1; hlolli's targeted an older tree.)
    fontconfig = prev.fontconfig.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ../patches/deps/fontconfig-0001-wasi-cache-locks.patch
      ];
      env = (old.env or { }) // {
        CFLAGS = (old.env.CFLAGS or "")
          + " -O2 -DFC_NO_MT -mexception-handling -mllvm -wasm-enable-sjlj";
        ac_cv_va_copy = "C99";
        fc_cv_c99_vsnprintf = "yes";
      };
      configureFlags = (old.configureFlags or [ ]) ++ [
        "--disable-cache-build"
        "--disable-docs"
        "--disable-iconv"
        "--disable-nls"
        "--with-add-fonts=no"
        "--with-arch=wasm32"
        "--with-cache-dir=/tmp/fontconfig-cache"
        "--with-default-fonts=/fonts"
      ];
      buildPhase = ''
        runHook preBuild
        make -C fc-case
        make -C fc-lang
        make -C src fcalias.h fcaliastail.h fcftalias.h fcftaliastail.h fcobjshash.h
        make -C src libfontconfig.la
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        make -C src install-libLTLIBRARIES
        make -C fontconfig install-fontconfigincludeHEADERS
        make install-pkgconfigDATA
        # no CLI tools on WASI; satisfy the declared outputs
        mkdir -p $out $bin
        runHook postInstall
      '';
      postInstall = ''
        test -f "''${lib:-$out}/lib/libfontconfig.a"
      '';
      doCheck = false;
    });

    # pcre2, library-only (from hlolli's recipe): pcre2grep needs fork and
    # sys/wait.h; the test tools need process clocks and rlimits.
    pcre2 = prev.pcre2.overrideAttrs (old: {
      configureFlags = (old.configureFlags or [ ]) ++ [
        "--disable-pcre2-16"
        "--disable-pcre2-32"
        "--disable-jit"
        "--disable-pcre2grep-jit"
        "--disable-pcre2grep-callout-fork"
        "--disable-pcre2grep-libz"
        "--disable-pcre2grep-libbz2"
        "--disable-pcre2test-libedit"
        "--disable-pcre2test-libreadline"
      ];
      buildPhase = ''
        runHook preBuild
        make libpcre2-8.la libpcre2-posix.la
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        make \
          install-libLTLIBRARIES \
          install-pkgconfigDATA \
          install-includeHEADERS \
          install-nodist_includeHEADERS
        # satisfy declared outputs the library-only build never fills
        for o in $outputs; do mkdir -p ''${!o}; done
        runHook postInstall
      '';
      doCheck = false;
    });

    # GLib, via hlolli's nine-patch series (same glib version — his nixpkgs
    # pin is ours). Static, minimal: no gio modules, no introspection, no
    # tools. NOTE from upstream work: GObject/Pango cast callbacks between C
    # signatures; the FINAL linked wasm module needs wasm-opt --fpcast-emu.
    glib = prev.glib.overrideAttrs (old: {
      outputs = [ "out" "dev" ];
      patches = (old.patches or [ ]) ++ [
        ../patches/deps/glib/0001-wasi-minimal-build.patch
        ../patches/deps/glib/0002-wasi-support.patch
      ];
      buildInputs = [ final.libffi final.pcre2 ];
      propagatedBuildInputs = [ final.libffi final.pcre2 ];
      env = (old.env or { }) // {
        NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "")
          + " -D_WASI_EMULATED_GETPID -D_WASI_EMULATED_SIGNAL";
      };
      mesonFlags = [
        "-Dbsymbolic_functions=false"
        "-Ddefault_library=static"
        "-Ddocumentation=false"
        "-Ddtrace=disabled"
        "-Dglib_debug=disabled"
        "-Dinstalled_tests=false"
        "-Dintrospection=disabled"
        "-Dlibelf=disabled"
        "-Dlibmount=disabled"
        "-Dman-pages=disabled"
        "-Dnls=disabled"
        "-Dselinux=disabled"
        "-Dsysprof=disabled"
        "-Dsystemtap=disabled"
        "-Dtests=false"
        "-Dxattr=false"
      ];
      postPatch = (old.postPatch or "") + ''
        patchShebangs tools/gen-visibility-macros.py
      '';
      # The host package's setup hook manages GSettings schemas; this WASI
      # subset does not build GSettings.
      setupHook = null;
      postConfigure = ''
        patchShebangs gobject/glib-genmarshal gobject/glib-mkenums
      '';
      postInstall = ''
        rm -rf "$out/bin" "$out/share"
        rm -f "$out"/lib/*-gdb.py
        substituteInPlace "$out/lib/pkgconfig/glib-2.0.pc" \
          --replace-fail \
            "-lglib-2.0 -lm" \
            "-lglib-2.0 -lm -lwasi-emulated-getpid -lwasi-emulated-signal" \
          --replace-fail \
            "Cflags: " \
            "Cflags: -D_WASI_EMULATED_GETPID -D_WASI_EMULATED_SIGNAL "
        sed -i \
          -e '/^devbindir=/d' \
          -e '/^glib_genmarshal=/d' \
          -e '/^gobject_query=/d' \
          -e '/^glib_mkenums=/d' \
          -e '/^glib_valgrind_suppressions=/d' \
          "$out/lib/pkgconfig/glib-2.0.pc"
        test -f "$out/lib/libglib-2.0.a"
        test -f "$out/lib/libgobject-2.0.a"
        test -f "$out/lib/libgio-2.0.a"
      '';
      doCheck = false;
      doInstallCheck = false;
      # upstream meta says wasi is unsupported; the patch series disagrees
      meta = (old.meta or { }) // {
        platforms = lib.platforms.all;
        badPlatforms = [ ];
      };
    });
  }
