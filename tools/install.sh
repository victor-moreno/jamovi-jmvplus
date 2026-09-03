#!/usr/bin/env bash
# Build and install jmvplus into jamovi desktop and/or a running jamovi Docker
# container.
#
#   bash install.sh              both targets, whichever are available
#   bash install.sh desktop
#   bash install.sh docker [container]     (default container: jamovi)
#
# The desktop target uses whichever R `Rscript` resolves to (respecting
# ~/.Rprofile, which appends jamovi.app's bundled module library) rather than
# a custom R_LIBS_USER under ~/R/.Rlib-arm|.Rlib-x64 -- R here is managed by
# rig, not that path. Pick the active R version with `rig default <version>`
# before running this if needed; it must match the R version jamovi.app
# itself bundles, or jmvcore segfaults on load.
set -euo pipefail

TARGET="${1:-both}"
CONTAINER="${2:-jamovi}"

HERE="$(cd "$(dirname "$0")/../jmvplus" && pwd)"
MODULE=jmvplus
VERSION="$(awk -F': *' '$1 == "Version" { print $2; exit }' "$HERE/DESCRIPTION")"
ARTIFACT="$HERE/${MODULE}_${VERSION}.jmo"

# ── desktop ──────────────────────────────────────────────────────────────────
install_desktop() {
  local APP APP_R LOG
  APP=/Applications/jamovi.app
  APP_R="$APP/Contents/Frameworks/R.framework/Versions/Current/Resources/bin/R"
  [ -x "$APP_R" ] || { echo "error: no R inside $APP" >&2; return 1; }

  echo ">> desktop: building jmvplus with $(Rscript -e 'cat(R.version.string)')"
  cd "$HERE"

  LOG="$(mktemp)"
  Rscript -e 'jmvtools::install()' 2>&1 | tee "$LOG" | grep -vE '^\s*$' || true

  # jmvtools::install() can report errors on stdout while exiting successfully.
  # It can also claim installation succeeded after a SingletonLock failure.
  [ -f "$ARTIFACT" ] || {
    echo "error: jmvtools did not produce $ARTIFACT" >&2
    rm -f "$LOG"; return 1
  }
  if grep -q 'SingletonLock' "$LOG"; then
    echo
    echo "!! jamovi.app could not be driven (SingletonLock denied)."
    echo "!! The .jmo was still built. Install it by hand:"
    echo "!!   jamovi -> Modules -> Install from file -> $ARTIFACT"
    rm -f "$LOG"
    return 0
  fi
  if ! grep -q 'Module installed successfully' "$LOG"; then
    echo "error: jmvtools::install() did not install the module (see above)" >&2
    rm -f "$LOG"; return 1
  fi
  rm -f "$LOG"

  local MODDIR="$HOME/Library/Application Support/jamovi/modules/$MODULE"
  if [ -d "$MODDIR" ]; then
    echo ">> desktop: installed at $MODDIR"
  else
    echo "!! desktop: install reported success but $MODDIR does not exist."
    echo "!! Install $ARTIFACT by hand (Modules -> Install from file)."
    return 1
  fi
}

# ── docker ───────────────────────────────────────────────────────────────────
install_docker() {
  if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER"; then
    echo "!! docker: container '$CONTAINER' is not running — skipping"
    return 0
  fi

  if ! docker exec "$CONTAINER" sh -c 'command -v jmc >/dev/null 2>&1'; then
    echo "!! docker: jmc is not in the container." >&2
    echo "!! Install the jamovi compiler in the image before using this target." >&2
    return 1
  fi

  echo ">> docker: copying source into $CONTAINER"
  # --no-mac-metadata/--no-xattrs: AppleDouble ._ files otherwise land in the
  # container and jmc tries to compile them.
  tar --no-mac-metadata --no-xattrs -C "$HERE" -cf - DESCRIPTION NAMESPACE R jamovi \
    | docker exec -i "$CONTAINER" sh -c \
        'rm -rf /tmp/jmvplus-src && mkdir -p /tmp/jmvplus-src && tar -C /tmp/jmvplus-src -xf -'

  echo ">> docker: jmc --install"
  docker exec -i "$CONTAINER" bash -s <<'INCONTAINER'
set -euo pipefail
source /usr/lib/jamovi/bin/env.conf 2>/dev/null || true
RHOME="${R_HOME:-$(R RHOME 2>/dev/null || true)}"
[ -n "$RHOME" ] || { echo "   error: no R in the container" >&2; exit 1; }
RLIBS=/usr/lib/jamovi/modules/base/R

jmc --install /tmp/jmvplus-src \
    --to /usr/lib/jamovi/modules \
    --rhome "$RHOME" \
    --rlibs "$RLIBS" \
    --patch-version --skip-deps

[ -f /usr/lib/jamovi/modules/jmvplus/jamovi.yaml ] || {
  echo "   error: jmc did not install jmvplus" >&2; exit 1; }
INCONTAINER

  echo ">> docker: restarting $CONTAINER to load the module"
  docker restart "$CONTAINER" >/dev/null
  echo ">> docker: testing coefficient of variation"
  docker exec -i "$CONTAINER" bash -s <<'INCONTAINER'
set -euo pipefail
Rscript --vanilla -e '
    .libPaths(c(
        "/usr/lib/jamovi/modules/jmv/R",
        "/usr/lib/jamovi/modules/base/R",
        "/usr/lib/jamovi/modules/jmvplus/R",
        .libPaths()
    ))
    library(jmv)
    library(jmvplus)

    data <- data.frame(x = c(10, 20, 30))
    analysis <- jmv::descriptivesClass$new(
        options = jmv::descriptivesOptions$new(vars = "x", desc = "rows"),
        data = data
    )
    analysis$addAddon(jmvplus::descriptivesClass$new(
        options = jmvplus::descriptivesOptions$new()
    ))
    analysis$run()

    cv <- analysis$results$descriptivesT$asDF$cv[1]
    stopifnot(isTRUE(all.equal(cv, 50)))
    noSd <- jmv::descriptivesClass$new(
        options = jmv::descriptivesOptions$new(vars = "x", desc = "rows", sd = FALSE),
        data = data
    )
    noSd$addAddon(jmvplus::descriptivesClass$new(
        options = jmvplus::descriptivesOptions$new()
    ))
    noSd$run()
    stopifnot(! "cv" %in% names(noSd$results$descriptivesT$asDF))
    cat(sprintf("   CV smoke test passed: %.0f%%\n", cv))
'
INCONTAINER
  echo ">> docker: installed jmvplus; open Descriptives to verify CV (%) is reported"
}

case "$TARGET" in
  desktop) install_desktop ;;
  docker)  install_docker ;;
  both)    install_desktop || true; echo; install_docker || true ;;
  *)       echo "usage: install.sh [desktop|docker|both] [container]" >&2; exit 1 ;;
esac
