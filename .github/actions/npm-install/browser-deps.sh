#!/usr/bin/env bash
# Usage (env): NPM_DIRS - as in install.sh. Installs the system libraries Playwright's Chromium
# needs, with the Playwright CLI of the first listed directory that has one, and fonts-ubuntu for
# the screenshot tests.
set -euo pipefail

while IFS= read -r DIR; do
  DIR="${DIR%$'\r'}"
  [ -n "$DIR" ] || continue
  case "$DIR" in /*) ;; *) DIR="$GITHUB_WORKSPACE/$DIR" ;; esac
  if [ -x "$DIR/node_modules/.bin/playwright" ]; then
    cd "$DIR"
    npx --no-install playwright install-deps chromium
    # no apt-get update: install-deps has just run one
    sudo apt-get install -y --no-install-recommends fonts-ubuntu
    exit 0
  fi
done <<< "$NPM_DIRS"
echo "::warning::No Playwright CLI in the listed directories - browser dependencies and fonts-ubuntu were not installed"
