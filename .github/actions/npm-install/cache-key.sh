#!/usr/bin/env bash
# Usage (env): NPM_DIRS - as in install.sh; CACHE_FAMILY - the cache family (survey-library, ...);
# NODE_VERSION - the Node.js version the action sets up.
# Writes `key` and `paths` of the node_modules cache to $GITHUB_OUTPUT.
#
# Like the /tmp tarballs of templates/utils/npm.yml: the installed trees themselves, restored
# before `npm install`, which then finds everything in place ("up to date" in seconds). Caching
# ~/.npm instead saved the downloads only - building the trees without lock files still took
# most of a minute. Playwright's browsers go into the same entry: the root postinstall
# (`playwright install chromium`) downloads them otherwise.
#
# Key: npm-<family>-node<version>-<hash of the listed package.json files>; one entry per set of
# directories. As in Azure, no week and no restore-keys: the trees stay as they are until a
# package.json of the set changes, and then install from scratch. A fallback to an older tree
# would freeze it for good - `npm install` keeps the versions it finds - and actions/cache does
# not restore an entry saved with another list of paths anyway.
set -euo pipefail

[ -n "${CACHE_FAMILY:-}" ] || exit 0

DIRS=()
while IFS= read -r DIR; do
  DIR="${DIR%$'\r'}"
  [ -n "$DIR" ] && DIRS+=("$DIR")
done <<< "${NPM_DIRS:-}"
mapfile -t DIRS < <(printf '%s\n' "${DIRS[@]}" | LC_ALL=C sort -u | sed '/^$/d')

# A missing package.json is hashed as such: install.sh reports it right after this step.
HASH="$(
  for DIR in "${DIRS[@]}"; do
    case "$DIR" in /*) FILE="$DIR/package.json" ;; *) FILE="$GITHUB_WORKSPACE/$DIR/package.json" ;; esac
    if [ -f "$FILE" ]; then SUM="$(sha256sum < "$FILE" | cut -c1-64)"; else SUM=missing; fi
    printf '%s %s\n' "$DIR" "$SUM"
  done | sha256sum | cut -c1-16
)"

{
  echo "key=npm-$CACHE_FAMILY-node${NODE_VERSION:-}-$HASH"
  echo 'paths<<EOF'
  for DIR in "${DIRS[@]}"; do
    case "$DIR" in .) echo node_modules ;; *) echo "${DIR%/}/node_modules" ;; esac
  done
  echo '~/.cache/ms-playwright'
  echo EOF
} >> "$GITHUB_OUTPUT"
