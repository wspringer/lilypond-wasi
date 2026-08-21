# Patch series

Patches against the pinned upstream LilyPond tree, applied in lexical order
by `nix build .#source`. Name them `NNNN-short-title.patch` (e.g.
`0001-wasi-no-fork.patch`) so the order is explicit.

To create or rebase a patch:

```sh
nix build .#source            # or start from the raw pin
cp -r result lilypond-work && chmod -R u+w lilypond-work
cd lilypond-work && git init -q && git add -A && git commit -qm base
# ...edit...
git diff > ../patches/NNNN-short-title.patch
```

After `nix flake update lilypond-src`, `nix build .#source` failing means the
series no longer applies to upstream tip — regenerate the failing patch the
same way.

Keep every patch small, WASI-motivated, and annotated with a comment block at
the top saying what it does and why upstream needs it. The goal is a series
short enough to one day become upstream merge requests.
