#!/usr/bin/env bash
# Port of templates/utils/npm.yml (keep in sync while it lives), minus its /tmp tarball cache -
# hosted runners start clean; sub-project D adds actions/cache.
# Usage (env): NPM_DIRS - directories, one per line, relative to GITHUB_WORKSPACE or absolute;
# NPM_UPDATE - optional "<directory> <package>" lines, `npm update`d after the installs;
# GITHUB_TOKEN - optional PAT.
#
# Some package.json files depend on git URLs (survey-utils, eslint-plugin-surveyjs). npm tries
# https first and, when that fails, silently retries over ssh - where the runner has no key, so
# the log shows only "Permission denied (publickey)" and hides the real error. The extraheader
# authenticates the request (anonymous git to github.com gets rate-limited); rewriting ssh to
# https keeps the real failure visible when it happens. An empty extraheader resets the header
# list, so a fork PR without the secret still works anonymously.
set -e

AUTH=""
if [ -n "${GITHUB_TOKEN:-}" ]; then
  AUTH="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 -w0)"
fi
export GIT_CONFIG_COUNT=3
export GIT_CONFIG_KEY_0="http.https://github.com/.extraheader" GIT_CONFIG_VALUE_0="$AUTH"
export GIT_CONFIG_KEY_1="url.https://github.com/.insteadOf"    GIT_CONFIG_VALUE_1="ssh://git@github.com/"
export GIT_CONFIG_KEY_2="url.https://github.com/.insteadOf"    GIT_CONFIG_VALUE_2="git@github.com:"
# puppeteer 22 sits unused in the root package.json files and would download Chrome every time
export PUPPETEER_SKIP_DOWNLOAD=true

resolve() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *) printf '%s' "$GITHUB_WORKSPACE/$1" ;;
  esac
}

FLAGS=(--no-audit --no-fund --no-update-notifier --no-package-lock)
PIDS=()
DIRS=()
while IFS= read -r DIR; do
  DIR="${DIR%$'\r'}"
  [ -n "$DIR" ] || continue
  DIR="$(resolve "$DIR")"
  (
    if [ ! -f "$DIR/package.json" ]; then
      echo "[$DIR] package.json not found"
      exit 1
    fi
    echo "[$DIR] npm install"
    cd "$DIR" && npm install "${FLAGS[@]}"
  ) &
  PIDS+=($!)
  DIRS+=("$DIR")
done <<< "$NPM_DIRS"

FAILED=0
for i in "${!PIDS[@]}"; do
  if ! wait "${PIDS[$i]}"; then
    echo "FAILED: ${DIRS[$i]}"
    FAILED=1
  fi
done
[ "$FAILED" -eq 0 ] || exit 1

while IFS= read -r LINE; do
  LINE="${LINE%$'\r'}"
  [ -n "$LINE" ] || continue
  DIR="$(resolve "${LINE%% *}")"
  PKG="${LINE#* }"
  echo "[$DIR] npm update $PKG"
  (cd "$DIR" && npm update "$PKG" --no-package-lock --no-audit --no-fund)
done <<< "${NPM_UPDATE:-}"
