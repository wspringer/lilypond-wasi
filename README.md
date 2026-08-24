# lilypond-wasi

An attempt to build [GNU LilyPond](https://lilypond.org) to WebAssembly
(WASI), pinned against upstream master and carrying a small patch series —
tailing upstream rather than forking it.

If it succeeds, it becomes the embedded, zero-system-dependency engraving
backend (SVG + EPS) for [lilypond-mcp](../lilypond-mcp).

```sh
nix flake update lilypond-src   # advance the upstream pin
nix build .#source              # upstream + patches — must keep building
nix build .#wasi-deps           # the dependency stack, cross-built to WASI
```

See `CLAUDE.md` for the staged build plan and `JOURNAL.md` for the state of
the campaign.

## Licence

GPL-3.0-or-later — see `LICENSE`. The patch series modifies GNU LilyPond,
and much of `nix/` and `patches/deps/` is adapted from
[hlolli/lilypond-wasm](https://github.com/hlolli/lilypond-wasm)
(GPL-3.0-or-later). Attribution and the per-file provenance are in
`NOTICE.md`.

Prebuilt artifacts are published to `lilypond-wasi.cachix.org`; the flake's
`nixConfig` wires it up (consumers need `--accept-flake-config`).
