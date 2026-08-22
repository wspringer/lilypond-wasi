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
          # wasm32-unknown-wasi, static. Target-scoped fixes for the
          # dependency stack live in nix/wasi-overlay.nix.
          wasi = pkgs.pkgsCross.wasi32.extend
            (import ./nix/wasi-overlay.nix { lib = nixpkgs.lib; });
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

          # Stage 2 — the dependency stack cross-built to WASI. Each attr is
          # an individually buildable checkpoint; wasi-deps aggregates them.
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
