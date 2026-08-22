{
  description = "lilypond-wasm — WASI/WebAssembly build of GNU LilyPond, tailing upstream master";

  inputs = {
    # Pinned to the same rev as hlolli/lilypond-wasm (see JOURNAL.md
    # 2026-08-21): its wasi32 stdenv predates the Rust component-model
    # tooling (rustc bootstrap!) that current nixpkgs drags into every
    # cross build, and it is the dep-world hlolli's guile/gmp/libffi
    # derivations were proven against. Deliberately not tracking a channel.
    nixpkgs.url = "github:NixOS/nixpkgs/4db2c220f32fd162658ed1b7bb2f46a82996ddbe";

    # Upstream GNU LilyPond, pinned but advanceable:
    #   nix flake update lilypond-src
    # moves the pin to the tip of master. Our patches live in ./patches and
    # are applied on top; the upstream tree itself is never modified.
    lilypond-src = {
      url = "gitlab:lilypond/lilypond";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, lilypond-src }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      patchesOf = dir:
        map (name: dir + "/${name}")
          (builtins.filter (nixpkgs.lib.hasSuffix ".patch")
            (builtins.attrNames (builtins.readDir dir)));
    in
    {
      packages = forAllSystems (pkgs:
        let
          # wasm32-unknown-wasip1, static. The whole LilyPond dependency
          # stack evaluates for this target in current nixpkgs; the overlay
          # collects the fixes needed to make it actually build.
          wasi = pkgs.pkgsCross.wasi32.extend (final: prev: {
            # zlib's gz* file layer uses errno without including <errno.h>,
            # which wasi-libc does not forgive; and its configure probes for
            # --undefined-version, a GNU-ld flag wasm-ld rejects when the
            # example binaries link.
            # IMPORTANT: overlays apply to every stage of the cross package
            # set, so this must be scoped to the wasi target — patching the
            # native zlib too changes its hash and cascades into rebuilding
            # the entire native toolchain (LLVM links zlib). See JOURNAL.md.
            zlib =
              if prev.stdenv.hostPlatform.isWasi then
                prev.zlib.overrideAttrs (old: {
                  postPatch = (old.postPatch or "") + ''
                    sed -i '1i #include <errno.h>' gzguts.h
                  '';
                  # nixpkgs sets NIX_LDFLAGS = "--undefined-version" whenever
                  # the linker is lld >= 16 (zlib issue #960 workaround), but
                  # wasm-ld — also lld — rejects that flag.
                  env = (old.env or { }) // { NIX_LDFLAGS = ""; };
                })
              else
                prev.zlib;

            # A pattern to expect everywhere: libraries cross-compile fine,
            # but packages' auxiliary command-line tools trip over POSIX APIs
            # WASI lacks (clock, chown, ...). Disable or defang the tools.
            expat =
              if prev.stdenv.hostPlatform.isWasi then
                prev.expat.overrideAttrs (old: {
                  # the benchmark tool needs clock(); skip tools entirely
                  configureFlags = (old.configureFlags or [ ]) ++ [
                    "--without-tests"
                    "--without-examples"
                    "--without-xmlwf"
                  ];
                })
              else
                prev.expat;

            brotli =
              if prev.stdenv.hostPlatform.isWasi then
                prev.brotli.overrideAttrs (old: {
                  # the brotli CLI calls chown() (absent from wasi-libc) and
                  # clock() (needs the emulation library)
                  postPatch = (old.postPatch or "") + ''
                    sed -i '1i #define chown(p,o,g) 0' c/tools/brotli.c
                  '';
                  env = (old.env or { }) // {
                    NIX_CFLAGS_COMPILE = "-D_WASI_EMULATED_PROCESS_CLOCKS";
                    NIX_LDFLAGS = "-lwasi-emulated-process-clocks";
                  };
                })
              else
                prev.brotli;

            # libpng needs setjmp/longjmp — wasm's exception-handling
            # proposal, a battle we only intend to fight once, for Guile.
            # FreeType uses libpng solely for color-emoji (SBIX/CBDT) glyphs
            # and brotli solely for WOFF2 — an SVG music engraver needs
            # neither, so build FreeType lean instead.
            freetype =
              if prev.stdenv.hostPlatform.isWasi then
                prev.freetype.overrideAttrs (old: {
                  buildInputs = [ ];
                  propagatedBuildInputs = [ final.zlib ];
                  configureFlags =
                    # freetype-config would drag a *target* pkg-config and
                    # bash into the closure (see postInstall upstream);
                    # nothing needs the script.
                    builtins.filter (f: f != "--enable-freetype-config") (old.configureFlags or [ ])
                    ++ [
                      "--with-png=no"
                      "--with-brotli=no"
                      "--with-harfbuzz=no"
                      "--with-bzip2=no"
                    ];
                  postInstall = "";
                  # makeWrapper's shell-wrapper hook exists only to wrap
                  # freetype-config, and drags a (broken) target-platform
                  # bash into the closure.
                  nativeBuildInputs =
                    builtins.filter (d: !(nixpkgs.lib.hasInfix "wrapper" (d.name or "")))
                      (old.nativeBuildInputs or [ ]);
                  # FreeType's validators use setjmp, which wasm only has via
                  # the exception-handling proposal. NOTE: objects built this
                  # way need an EH-capable engine (recent wasmtime) at runtime.
                  # Guile will need the same treatment — this is the pattern.
                  env = (old.env or { }) // {
                    NIX_CFLAGS_COMPILE = "-mexception-handling -mllvm -wasm-enable-sjlj";
                  };
                })
              else
                prev.freetype;
          });
          shortRev = builtins.substring 0 7 (lilypond-src.rev or "dirty");
        in
        rec {
          # Upstream master with the ./patches series applied — the tree every
          # later stage consumes. If this builds after `nix flake update
          # lilypond-src`, the patch series still applies to upstream tip.
          source = pkgs.applyPatches {
            name = "lilypond-src-patched-${shortRev}";
            src = lilypond-src;
            patches = patchesOf ./patches;
          };

          # Stage 1 — the dependency stack cross-built to WASI. Each attr is
          # an individually buildable checkpoint; wasi-deps aggregates them.
          # Rough order of difficulty: zlib → expat → freetype → libffi →
          # boehmgc → fontconfig → glib → pango → guile.
          wasi-zlib = wasi.zlib;
          wasi-expat = wasi.expat;
          wasi-freetype = wasi.freetype;
          wasi-libffi = wasi.libffi;
          wasi-boehmgc = wasi.boehmgc;
          wasi-fontconfig = wasi.fontconfig;
          wasi-glib = wasi.glib;
          wasi-pango = wasi.pango;
          wasi-guile = wasi.guile;

          wasi-deps = pkgs.linkFarm "lilypond-wasi-deps" [
            { name = "zlib"; path = wasi-zlib; }
            { name = "expat"; path = wasi-expat; }
            { name = "freetype"; path = wasi-freetype; }
            { name = "libffi"; path = wasi-libffi; }
            { name = "boehmgc"; path = wasi-boehmgc; }
            { name = "fontconfig"; path = wasi-fontconfig; }
            { name = "glib"; path = wasi-glib; }
            { name = "pango"; path = wasi-pango; }
            { name = "guile"; path = wasi-guile; }
          ];

          default = source;
        });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            wasmtime # run/verify WASI modules
            wasm-tools # inspect them
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);
    };
}
