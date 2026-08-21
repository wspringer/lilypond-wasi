{
  description = "lilypond-wasm — WASI/WebAssembly build of GNU LilyPond, tailing upstream master";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

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
            # which wasi-libc does not forgive.
            zlib = prev.zlib.overrideAttrs (old: {
              postPatch = (old.postPatch or "") + ''
                sed -i '1i #include <errno.h>' gzguts.h
              '';
            });
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
