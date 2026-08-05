#!/usr/bin/env bash
# Build dist/ artifacts for a jamovi/R version and publish a GitHub release
# with the per-platform .jmo files attached. Run this whenever jamovi bumps
# its bundled R version and jmvplus needs a matching release.
#
#   bash tools/release.sh 4.6.0
#
# Requires jmvplus/jmvplus_0.1.0.jmo to already exist (build it first with
# tools/install.sh desktop).
set -euo pipefail

R_VERSION="${1:-}"

usage() { echo "usage: release.sh R_VERSION" >&2; }

case "$R_VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) usage; exit 1 ;;
esac

command -v gh >/dev/null || { echo "error: gh CLI is required" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_DIR="$ROOT/jmvplus"
MODULE=jmvplus
VERSION="$(awk -F': *' '$1 == "Version" { print $2; exit }' "$MODULE_DIR/DESCRIPTION")"
R_MINOR="${R_VERSION%.*}"
REPO="$(cd "$ROOT" && gh repo view --json nameWithOwner -q .nameWithOwner)"

echo ">> building dist/R${R_MINOR} for R $R_VERSION"
bash "$ROOT/tools/prepare-jmo.sh" "$R_VERSION" all

TAG="v${VERSION}-R${R_VERSION}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

for os_dir in "$ROOT/dist/R${R_MINOR}"/*/; do
  os="$(basename "$os_dir")"
  for arch_dir in "$os_dir"*/; do
    arch="$(basename "$arch_dir")"
    jmo="$arch_dir${MODULE}_${VERSION}.jmo"
    [ -f "$jmo" ] || { echo "error: missing $jmo" >&2; exit 1; }
    cp "$jmo" "$STAGE/${MODULE}_${VERSION}_${os}_${arch}.jmo"
  done
done

echo ">> creating release $TAG on $REPO"
gh release create "$TAG" \
  --repo "$REPO" \
  --title "$MODULE $VERSION (jamovi / R $R_VERSION)" \
  --notes "$MODULE $VERSION built for jamovi releases bundling R $R_VERSION. Download the .jmo matching your OS, then in jamovi: Modules -> jamovi library -> Sideload." \
  "$STAGE"/*.jmo

echo ">> done: https://github.com/$REPO/releases/tag/$TAG"
