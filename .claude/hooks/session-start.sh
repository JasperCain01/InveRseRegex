#!/bin/bash
# SessionStart hook: provision the R toolchain so tests, roxygen and R CMD check
# work in Claude Code on the web sessions.
#
# Context: this project is a base-R-only package, but its dev/test workflow
# needs R plus a few packages. CRAN is blocked through the web sandbox proxy,
# so we install everything from Ubuntu's apt repositories as r-cran-* packages
# rather than via install.packages()/pak.
#
# The script is idempotent (safe to re-run) and only does work in the remote
# web environment; locally it exits immediately.
set -euo pipefail

# Only run in Claude Code on the web; a no-op elsewhere.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive

# apt package list: R itself plus the dev/test packages we rely on.
PKGS="r-base-core r-cran-testthat r-cran-roxygen2 r-cran-devtools r-cran-stringr"

# Fast path: if Rscript and testthat are already present (cached container),
# there is nothing to do.
if command -v Rscript >/dev/null 2>&1 \
   && Rscript -e 'quit(status = as.integer(!requireNamespace("testthat", quietly = TRUE)))' >/dev/null 2>&1; then
  echo "R toolchain already present; skipping install."
  exit 0
fi

echo "Installing R toolchain via apt (CRAN is blocked in the web sandbox)..."
apt-get update -qq
# shellcheck disable=SC2086
apt-get install -y -qq $PKGS

echo "R toolchain ready:"
Rscript -e 'cat(R.version.string, "\n")'
