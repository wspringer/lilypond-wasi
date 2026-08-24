#!/usr/bin/env bash
# Push this project's build artifacts to a Cachix binary cache.
#
# What gets pushed: every store path in the *build* closure whose name marks
# it as ours — the wasm32-unknown-wasi cross toolchain, the nine patched
# dependency libraries, the assets, and lilypond.wasm itself. Stock nixpkgs
# paths are skipped: cache.nixos.org already has them.
#
# Nothing here is reproducible from a public cache — pkgsCross.wasi32
# derivations are never built by Hydra, on any nixpkgs pin. Losing them
# means rebuilding the cross-LLVM toolchain from source (hours).
#
# Usage:  ./scripts/push-cache.sh [cache-name]
# Needs:  nix run nixpkgs#cachix -- authtoken <token>   (once)
set -euo pipefail

CACHE="${1:-${CACHIX_CACHE:-lilypond-wasm}}"
cd "$(dirname "$0")/.."

echo "==> building targets"
nix build .#lilypond .#assets --no-link

echo "==> collecting build closure"
paths=$(
  for target in lilypond assets; do
    drv=$(nix path-info --derivation ".#$target")
    nix-store -qR --include-outputs "$drv"
  done | sort -u | grep -E 'wasm32|wasi|lilypond' | grep -v '\.drv$'
)

count=$(echo "$paths" | grep -c . || true)
size=$(echo "$paths" | xargs -n 200 nix path-info -S 2>/dev/null |
  awk '{s+=$2} END {printf "%.2f", s/1073741824}')
echo "    $count paths, ${size} GB"

echo "==> pushing to cachix cache '$CACHE'"
echo "$paths" | nix run nixpkgs#cachix -- push "$CACHE"

echo "==> done. Consumers get these automatically via the flake's nixConfig."
