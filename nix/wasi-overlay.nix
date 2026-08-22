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
  let
    # One exception format for every archive in the stack: setjmp/longjmp
    # lowered via wasm EH (sjlj), modern exnref encoding, and the target
    # feature enabled so wasi-libc's <setjmp.h> gate opens. Mixing formats
    # across static archives breaks the final link.
    sjljFlags = "-mexception-handling -mllvm -wasm-enable-sjlj -mllvm -wasm-use-legacy-eh=false";
    allPlatforms = old: (old.meta or { }) // {
      platforms = lib.platforms.all;
      badPlatforms = [ ];
    };
  in
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
        NIX_CFLAGS_COMPILE = sjljFlags;
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
        CFLAGS = (old.env.CFLAGS or "") + " -O2 -DFC_NO_MT " + sjljFlags;
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
      meta = allPlatforms old;
    });

    # FriBidi, static and tool-less (hlolli's recipe).
    fribidi = prev.fribidi.overrideAttrs (old: {
      mesonFlags = (old.mesonFlags or [ ]) ++ [
        "-Dbin=false"
        "-Ddefault_library=static"
        "-Ddocs=false"
        "-Dtests=false"
      ];
      postInstall = (old.postInstall or "") + ''
        for o in $outputs; do mkdir -p ''${!o}; done
      '';
      doCheck = false;
      doInstallCheck = false;
      meta = allPlatforms old;
    });

    # HarfBuzz against our lean FreeType only — no cairo/icu/graphite/glib.
    # Includes FreeType headers, hence the shared sjlj/EH flags.
    harfbuzz =
      (prev.harfbuzz.override {
        freetype = final.freetype;
        withCoreText = false;
        withGraphite2 = false;
        withIcu = false;
        withIntrospection = false;
      }).overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ../patches/deps/harfbuzz/0001-wasi-single-thread-and-stdio.patch
        ];
        buildInputs = [ final.freetype ];
        propagatedBuildInputs = [ final.freetype ];
        env = (old.env or { }) // {
          NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "")
            + " -DHB_NO_MT -DHB_NO_MMAP " + sjljFlags;
        };
        mesonFlags = [
          "-Dbenchmark=disabled"
          "-Dcairo=disabled"
          "-Dchafa=disabled"
          "-Dcoretext=disabled"
          "-Ddefault_library=static"
          "-Ddirectwrite=disabled"
          "-Ddocs=disabled"
          "-Dfontations=disabled"
          "-Dfreetype=enabled"
          "-Dgdi=disabled"
          "-Dglib=disabled"
          "-Dgobject=disabled"
          "-Dgraphite=disabled"
          "-Dgraphite2=disabled"
          "-Dharfrust=disabled"
          "-Dicu=disabled"
          "-Dintrospection=disabled"
          "-Dkbts=disabled"
          "-Dtests=disabled"
          "-Dutilities=disabled"
          "-Dwasm=disabled"
          "-Dwith_libstdcxx=false"
        ];
        postInstall = (old.postInstall or "") + ''
          # satisfy declared outputs (devdoc) the doc-less build never fills
          for o in $outputs; do mkdir -p ''${!o}; done
        '';
        doCheck = false;
        doInstallCheck = false;
        meta = allPlatforms old;
      });

    # Pango (hlolli's three patches: skip target tools, synchronous
    # fontconfig, stdio locks). Cairo-less; LilyPond's SVG backend does its
    # own drawing and needs pango only for text shaping/metrics.
    pango =
      (prev.pango.override {
        withIntrospection = false;
        x11Support = false;
      }).overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ../patches/deps/pango/0001-wasi-skip-target-tools.patch
          ../patches/deps/pango/0002-wasi-synchronous-fontconfig.patch
          ../patches/deps/pango/0003-wasi-stdio-locks.patch
        ];
        buildInputs = with final; [ fontconfig freetype fribidi glib harfbuzz ];
        propagatedBuildInputs = with final; [ fontconfig freetype fribidi glib harfbuzz ];
        # nixpkgs points FONTCONFIG_FILE at a native test font set; keep
        # that closure out of a cross build that runs no target programs.
        env = builtins.removeAttrs (old.env or { }) [ "FONTCONFIG_FILE" ] // {
          NIX_CFLAGS_COMPILE = sjljFlags;
        };
        FONTCONFIG_FILE = null;
        mesonFlags = [
          "-Dbuild-examples=false"
          "-Dbuild-testsuite=false"
          "-Dcairo=disabled"
          "-Ddefault_library=static"
          "-Ddocumentation=false"
          "-Dfontconfig=enabled"
          "-Dfreetype=enabled"
          "-Dintrospection=disabled"
          "-Dlibthai=disabled"
          "-Dman-pages=false"
          "-Dsysprof=disabled"
          "-Dxft=disabled"
        ];
        postInstall = (old.postInstall or "") + ''
          # tools skipped on WASI; satisfy the declared outputs
          for o in $outputs; do mkdir -p ''${!o}; done
        '';
        doCheck = false;
        doInstallCheck = false;
        meta = allPlatforms old;
      });

    # Never built for wasi (filtered out of guile's inputs below), but they
    # must at least *evaluate* for guile's argument set to resolve.
    readline = prev.readline.overrideAttrs (old: { meta = allPlatforms old; });
    ncurses = prev.ncurses.overrideAttrs (old: { meta = allPlatforms old; });

    # GMP without assembly, and scratch space on the heap instead of
    # alloca — nested arithmetic can exhaust wasm's fixed stack.
    gmp = prev.gmp.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ../patches/deps/gmp-wasi.patch ];
      configureFlags = (old.configureFlags or [ ]) ++ [
        "--disable-assembly"
        "--enable-alloca=malloc-reentrant"
      ];
      doCheck = false;
      meta = allPlatforms old;
    });

    libunistring = prev.libunistring.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ../patches/deps/libunistring-wasi.patch ];
      # the test helpers' gnulib signal wrapper cannot work on WASI;
      # build/install only the library (and docs). NB: must go through
      # makeFlagsArray — a space inside a makeFlags element gets split
      # into bogus make goals and the install lands empty.
      preBuild = ''
        makeFlagsArray+=("SUBDIRS=doc gnulib-local lib")
      '';
      doCheck = false;
      meta = allPlatforms old;
    });

    # Guile — the boss. hlolli's two patches: guile-wasi (platform support,
    # no fork/exec/jit) and guile-wasm-callbacks (typed trampolines — wasm
    # checks indirect-call signatures exactly). Static, single-threaded,
    # no networking, no posix process API, no loadable modules.
    guile = (prev.guile.override {
      inherit (final) boehmgc gmp libffi libunistring;
    }).overrideAttrs (old: {
      CFLAGS = "-O2 " + sjljFlags;
      LIBS = "-lwasi-emulated-signal -lsetjmp";
      patches =
        # nixpkgs adds a cross-compilation fix (savannah c117f8e) "until the
        # next release" — guile 3.0.11 has it merged, so it double-applies.
        builtins.filter (p: !(lib.hasInfix "c117f8edc471" (baseNameOf (toString p))))
          (old.patches or [ ])
        ++ [
          ../patches/deps/guile/guile-wasi.patch
          ../patches/deps/guile/guile-wasm-callbacks.patch
        ];
      # A static Guile needs no terminal editor or loadable modules;
      # readline/libtool would drag ncurses and libltdl into the closure.
      buildInputs =
        builtins.filter (p: !(builtins.elem (lib.getName p) [ "libtool" "readline" ]))
          (old.buildInputs or [ ]);
      propagatedBuildInputs =
        builtins.filter (p: !(builtins.elem (lib.getName p) [ "libtool" "readline" ]))
          (old.propagatedBuildInputs or [ ]);
      nativeBuildInputs =
        # drop the shell-wrapper hook (target-bash dragger) and the
        # autoreconfHook (only existed for the c117f8e cross patch; rerun
        # trips on a missing pkg.m4) — but NOT the cc/pkg-config wrappers!
        builtins.filter
          (p: !(lib.hasInfix "shell-wrapper" (p.name or "") || lib.hasInfix "autoreconf" (p.name or "")))
          (old.nativeBuildInputs or [ ]);
      configureFlags =
        builtins.filter (f: !(lib.hasPrefix "--with-libreadline-prefix=" f))
          (old.configureFlags or [ ])
        ++ [
          "--disable-jit"
          "--disable-lto"
          "--disable-networking"
          "--disable-nls"
          "--disable-posix"
          "--with-modules=no"
          "--with-threads=null"
          "--without-libreadline-prefix"
          # wasi-libc's UTC-only mktime is sound; gnulib cannot run its
          # probe while cross-compiling and would pick a larger fallback.
          "gl_cv_func_working_mktime=yes"
        ];
      # WASI has no async signals; the emulation layer keeps Guile's
      # in-process signal/raise API working synchronously. And its poll.h
      # knows no priority events — POLLPRI=0 is a no-op bit. (As an env
      # var, not a configureFlags element: those must not contain spaces.)
      CPPFLAGS = "-D_WASI_EMULATED_SIGNAL -DPOLLPRI=0";
      # The target cannot run Guile's installed helper programs; keep the
      # static library, headers, and Scheme files for later links.
      postInstall = ''
        test -f "$out/lib/libguile-3.0.a"
        rm -rf "$out/bin"
        find "$out/lib" -type f \( -name '*.so' -o -name '*.so.*' -o -name '*.dylib' \) -delete
        for o in $outputs; do mkdir -p ''${!o}; done
      '';
      doCheck = false;
      doInstallCheck = false;
      meta = allPlatforms old;
    });
  }
