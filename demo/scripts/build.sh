#!/usr/bin/env bash
# Assemble the static demo site into demo/_site/.
#
# The site needs three things:
#   1. the hand-written page (demo/site/*),
#   2. the webR runtime (copied from the pinned npm package, so the site is
#      self-hosted and does not depend on a third-party CDN), and
#   3. InveRseRegex itself, as an installed binary package tarball.
#
# On 3: InveRseRegex is pure R (no compiled code), so a binary built by native R
# with `R CMD INSTALL --build` contains only serialised R objects and loads in
# webR unchanged -- no WebAssembly toolchain is needed. If the package ever
# gains C/C++ code this shortcut stops working and the build must move to the
# r-wasm `rwasm` tooling.
#
# Run from anywhere; requires R and `npm install` having been run in demo/.
set -euo pipefail

DEMO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$DEMO/.." && pwd)"
OUT="$DEMO/_site"
WEBR="$DEMO/node_modules/webr/dist"

if [ ! -d "$WEBR" ]; then
  echo "webR not found at $WEBR -- run 'npm install' in demo/ first." >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT/pkg" "$OUT/webr"

# 1. The page itself.
cp -R "$DEMO/site/." "$OUT/"

# 2. The webR runtime: only the files the browser actually loads.
cp "$WEBR/webr.js" "$WEBR/webr-worker.js" "$WEBR/R.js" "$WEBR/R.wasm" \
   "$WEBR/libRblas.so" "$WEBR/libRlapack.so" "$OUT/webr/"
cp -R "$WEBR/vfs" "$OUT/webr/"

# 3. The package, built from the working tree.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
(
  cd "$TMP"
  R CMD build --no-manual --no-build-vignettes "$ROOT" > build.log 2>&1 \
    || { cat build.log >&2; exit 1; }
  mkdir lib
  R CMD INSTALL --build -l lib InveRseRegex_*.tar.gz > install.log 2>&1 \
    || { cat install.log >&2; exit 1; }
)
BIN="$(ls "$TMP"/InveRseRegex_*_R_*.tar.gz)"
cp "$BIN" "$OUT/pkg/InveRseRegex.tar.gz"

# A small manifest the page shows in its footer.
VERSION="$(sed -n 's/^Version: *//p' "$ROOT/DESCRIPTION")"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
WEBR_VERSION="$(node -p "require('$DEMO/node_modules/webr/package.json').version")"
printf '{"package_version":"%s","commit":"%s","webr_version":"%s"}\n' \
  "$VERSION" "$COMMIT" "$WEBR_VERSION" > "$OUT/build-info.json"

echo "Built demo site in $OUT ($(du -sh "$OUT" | cut -f1))"
