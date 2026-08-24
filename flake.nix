{
  description = "lilypond-wasi — WASI/WebAssembly build of GNU LilyPond, tailing upstream master";

  # Nothing the overlay patches or reflags is obtainable from a public
  # cache; the stock wasi cross toolchain does come from cache.nixos.org.
  # Consumers need --accept-flake-config for these to take effect.
  nixConfig = {
    extra-substituters = [ "https://lilypond-wasi.cachix.org" ];
    extra-trusted-public-keys = [
      "lilypond-wasi.cachix.org-1:glhfmPO7w9C/uWcv6fpS5LI878nEegtKU7Si0frHVBs="
    ];
  };

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
    #
    # LilyPond uses even minors for stable and odd for development, so
    # master is the 2.27 development series that becomes 2.28. The stable
    # 2.26 line is maintained in parallel and tracked as a second input —
    # the same two-patch series applies clean to both (verified 2026-08-24),
    # and the WASI dependency stack is shared, so the second variant costs
    # only its own engine and assets.
    lilypond-src = {
      url = "gitlab:lilypond/lilypond";
      flake = false;
    };

    lilypond-stable-src = {
      url = "gitlab:lilypond/lilypond/stable%2F2.26";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, lilypond-src, lilypond-stable-src }:
    let
      inherit (nixpkgs) lib;
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      patchesOf = dir:
        map (name: dir + "/${name}")
          (builtins.filter (lib.hasSuffix ".patch")
            (builtins.attrNames (builtins.readDir dir)));

      # Read the version out of upstream's own VERSION file rather than
      # hardcoding it — a literal string silently lies the moment the pin
      # advances. Produces e.g. "2.27.3+g6069e16": what LilyPond is inside,
      # plus the exact revision it came from.
      upstreamVersion = src:
        let
          lines = lib.splitString "\n" (builtins.readFile "${src}/VERSION");
          field = key:
            let hit = builtins.filter (l: lib.hasPrefix "${key}=" l) lines;
            in if hit == [ ] then "0" else lib.removePrefix "${key}=" (builtins.head hit);
        in
        "${field "MAJOR_VERSION"}.${field "MINOR_VERSION"}.${field "PATCH_LEVEL"}";

      artifactVersion = src:
        "${upstreamVersion src}+g${builtins.substring 0 7 (src.rev or "dirty")}";
    in
    {
      packages = forAllSystems (pkgs:
        let
          # wasm32-unknown-wasi, static. Target-scoped fixes for the
          # dependency stack live in nix/wasi-overlay.nix. Shared by every
          # LilyPond variant — none of it depends on the LilyPond version.
          wasi = pkgs.pkgsCross.wasi32.extend (import ./nix/wasi-overlay.nix { inherit lib; });

          # One LilyPond generation: patched source, engine, runtime data.
          mkVariant = src:
            let
              version = artifactVersion src;
              source = pkgs.applyPatches {
                name = "lilypond-src-patched-${builtins.substring 0 7 (src.rev or "dirty")}";
                inherit src;
                patches = patchesOf ./patches;
              };
              lilypond = wasi.callPackage ./nix/lilypond.nix { src = source; inherit version; };
              assets = pkgs.callPackage ./nix/assets { src = source; inherit version; };
            in
            # The engine loads the Scheme library out of the asset tree.
            # Mixing generations would fail in confusing ways at run time.
            assert lilypond.version == assets.version;
            { inherit source lilypond assets version; };

          dev = mkVariant lilypond-src;
          stable = mkVariant lilypond-stable-src;
        in
        {
          # Development series (master) — the tailing target.
          source = dev.source;
          lilypond = dev.lilypond;
          assets = dev.assets;

          # Stable series (stable/2.26) — matches what nixpkgs ships and
          # what analog's native pipeline engraves with.
          source-stable = stable.source;
          lilypond-stable = stable.lilypond;
          assets-stable = stable.assets;

          # Stage 2 — the WASI dependency stack, shared by both variants.
          wasi-zlib = wasi.zlib;
          wasi-expat = wasi.expat;
          wasi-freetype = wasi.freetype;
          wasi-libffi = wasi.libffi;
          wasi-boehmgc = wasi.boehmgc;
          wasi-fontconfig = wasi.fontconfig;
          wasi-glib = wasi.glib;
          wasi-fribidi = wasi.fribidi;
          wasi-harfbuzz = wasi.harfbuzz;
          wasi-gmp = wasi.gmp;
          wasi-libunistring = wasi.libunistring;
          wasi-pango = wasi.pango;
          wasi-guile = wasi.guile;

          wasi-deps = pkgs.linkFarm "lilypond-wasi-deps" [
            { name = "zlib"; path = wasi.zlib; }
            { name = "expat"; path = wasi.expat; }
            { name = "freetype"; path = wasi.freetype; }
            { name = "libffi"; path = wasi.libffi; }
            { name = "boehmgc"; path = wasi.boehmgc; }
            { name = "fontconfig"; path = wasi.fontconfig; }
            { name = "glib"; path = wasi.glib; }
            { name = "pango"; path = wasi.pango; }
            { name = "guile"; path = wasi.guile; }
          ];

          default = dev.lilypond;
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
