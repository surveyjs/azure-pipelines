#!/usr/bin/env bash
# Usage (env): NPM_DIRS - as in install.sh. Installs the system libraries Playwright's Chromium
# needs, with the Playwright CLI of the first listed directory that has one, and fonts-ubuntu for
# the screenshot tests.
#
# The runner image has the libraries; what install-deps downloads is ~22 MB of fonts, which
# azure.archive.ubuntu.com usually serves in seconds but now and then at ~50 kB/s - 7+ minutes.
# So the packages are downloaded first, under a watchdog: past BROWSER_DEPS_DOWNLOAD_TIMEOUT
# seconds (60) the download stops, apt leaves the azure mirror for archive.ubuntu.com (next in
# APT_MIRRORS_FILE, /etc/apt/apt-mirrors.txt) and resumes there for up to
# BROWSER_DEPS_RETRY_TIMEOUT seconds (300). Only --download-only runs under the watchdog: it never
# touches dpkg, so stopping it is safe, and the partial files resume on the next mirror. The
# installs then take the packages from apt's cache.
set -euo pipefail

FIRST="${BROWSER_DEPS_DOWNLOAD_TIMEOUT:-60}"
RETRY="${BROWSER_DEPS_RETRY_TIMEOUT:-300}"
MIRRORS="${APT_MIRRORS_FILE:-/etc/apt/apt-mirrors.txt}"

download() { # <seconds> <packages...>
  local LIMIT="$1"
  shift
  # timeout runs as root: the runner user may not signal apt's root processes
  sudo timeout "$LIMIT" apt-get install --download-only -y --no-install-recommends "$@"
}

while IFS= read -r DIR; do
  DIR="${DIR%$'\r'}"
  [ -n "$DIR" ] || continue
  case "$DIR" in /*) ;; *) DIR="$GITHUB_WORKSPACE/$DIR" ;; esac
  if [ -x "$DIR/node_modules/.bin/playwright" ]; then
    cd "$DIR"
    sudo apt-get update

    # Playwright 1.60+ prints "Missing system dependencies (N):" and one indented package per line
    # (exit status 1), or "All system dependencies are installed."
    DRY="$(npx --no-install playwright install-deps --dry-run chromium 2>&1 || true)"
    mapfile -t PKGS < <(printf '%s\n' "$DRY" | sed -n '/^Missing system dependencies/,$ s/^  \([^ ]\{1,\}\)$/\1/p')
    if [ "${#PKGS[@]}" -eq 0 ] && ! grep -q '^All system dependencies are installed' <<< "$DRY"; then
      echo "::notice::install-deps --dry-run listed no packages - only fonts-ubuntu downloads under the watchdog"
    fi
    PKGS+=(fonts-ubuntu)

    if ! download "$FIRST" "${PKGS[@]}"; then
      if [ -f "$MIRRORS" ] && grep -q 'azure\.archive\.ubuntu\.com' "$MIRRORS"; then
        echo "::warning::The fonts did not download in ${FIRST}s from azure.archive.ubuntu.com - switching to archive.ubuntu.com"
        sudo sed -i '/azure\.archive\.ubuntu\.com/d' "$MIRRORS"
      else
        echo "::warning::The fonts did not download in ${FIRST}s and $MIRRORS lists no azure mirror - retrying on the same mirror"
      fi
      sudo apt-get update
      if ! download "$RETRY" "${PKGS[@]}"; then
        echo "::warning::The fonts did not download in another ${RETRY}s either - install-deps downloads the rest"
      fi
    fi

    npx --no-install playwright install-deps chromium
    sudo apt-get install -y --no-install-recommends fonts-ubuntu
    exit 0
  fi
done <<< "$NPM_DIRS"
echo "::warning::No Playwright CLI in the listed directories - browser dependencies and fonts-ubuntu were not installed"
