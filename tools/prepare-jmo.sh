#!/usr/bin/env bash
# Repackage the current macOS ARM .jmo for a target jamovi R version and CPU.
# This only rewrites jamovi's compatibility metadata; it does not rebuild R code.
#
#   bash tools/prepare-jmo.sh 4.6.0 mac arm64
#   bash tools/prepare-jmo.sh 4.6.0 all
#   bash tools/prepare-jmo.sh 4.5.3 linux x64 path/to/jmvplus_0.1.0.jmo
set -euo pipefail

R_VERSION="${1:-}"
OS="${2:-}"
ARCH="${3:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_DIR="$ROOT/jmv-plus"
MODULE=jmvplus
VERSION="$(awk -F': *' '$1 == "Version" { print $2; exit }' "$MODULE_DIR/DESCRIPTION")"

usage() {
  echo "usage: prepare-jmo.sh R_VERSION {mac|linux|windows} {arm64|x64} [source.jmo]" >&2
  echo "       prepare-jmo.sh R_VERSION all [source.jmo]" >&2
}

case "$R_VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) usage; exit 1 ;;
esac

if [ "$OS" = "all" ]; then
  [ -z "$ARCH" ] || { usage; exit 1; }
  SOURCE="${3:-$MODULE_DIR/${MODULE}_${VERSION}.jmo}"
else
  case "$OS" in
    mac|linux|windows) ;;
    *) usage; exit 1 ;;
  esac

  case "$ARCH" in
    arm64|x64) ;;
    *) usage; exit 1 ;;
  esac
  SOURCE="${4:-$MODULE_DIR/${MODULE}_${VERSION}.jmo}"
fi

[ -f "$SOURCE" ] || { echo "error: source artifact not found: $SOURCE" >&2; exit 1; }
command -v unzip >/dev/null || { echo "error: unzip is required" >&2; exit 1; }
command -v zip >/dev/null || { echo "error: zip is required" >&2; exit 1; }

if unzip -l "$SOURCE" | grep -Eq '\.(so|dylib|dll)$'; then
  echo "error: $SOURCE contains native libraries and cannot be repackaged safely" >&2
  exit 1
fi

prepare_target() {
  local target_os="$1" target_arch="$2" target_r out_dir out tmp meta

  target_r="${R_VERSION}-${target_arch}"
  out_dir="$ROOT/dist/R${R_VERSION%.*}/${target_os}/${target_arch}"
  out="$out_dir/${MODULE}_${VERSION}.jmo"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/jmvplus-jmo.XXXXXX")"

  unzip -q "$SOURCE" -d "$tmp"
  for meta in "$tmp/$MODULE/jamovi.yaml" "$tmp/$MODULE/jamovi-full.yaml"; do
    [ -f "$meta" ] || { echo "error: metadata missing from source artifact: $meta" >&2; rm -rf "$tmp"; return 1; }
    perl -0pi -e "s/^rVersion: .*$/rVersion: $target_r/m" "$meta"
    grep -qx "rVersion: $target_r" "$meta" || {
      echo "error: could not set rVersion in $meta" >&2; rm -rf "$tmp"; return 1; }
  done

  mkdir -p "$out_dir"
  rm -f "$out"
  (
    cd "$tmp"
    zip -q -r "$out" "$MODULE"
  )
  rm -rf "$tmp"

  echo ">> wrote $out"
  echo ">> compatibility marker: $target_r"
}

if [ "$OS" = "all" ]; then
  prepare_target mac arm64
  prepare_target mac x64
  prepare_target linux arm64
  prepare_target linux x64
  prepare_target windows x64
else
  prepare_target "$OS" "$ARCH"
fi

echo "!! metadata-only repackaging: test each artifact on its target jamovi build"
