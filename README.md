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
