#!/usr/bin/env bash
# Usage (env): NPM_DIRS - as in install.sh; CACHE_FAMILY - the cache family (survey-library, ...);
# NPM_CACHE_WEEK - overrides the ISO week (tests).
# Writes `key` and `restore-keys` of the ~/.npm cache to $GITHUB_OUTPUT.
#
# Key: npm-<family>-<ISO week>-<hash of the listed package.json files>. Every job saves under its
# own key after a miss, so the next job with the same directories hits exactly; a PR that leaves
# the package.json files alone hits its base branch's entry. Cache entries are immutable and,
# without lock files, the dependency versions move on - the week bounds that. A miss falls back
# to the family's newest entry of the same week only: each week starts from an empty cache
# instead of piling up the tarballs nobody uses any more.
set -euo pipefail

[ -n "${CACHE_FAMILY:-}" ] || exit 0
WEEK="${NPM_CACHE_WEEK:-$(date -u +%G-W%V)}"

DIRS=()
while IFS= read -r DIR; do
  DIR="${DIR%$'\r'}"
  [ -n "$DIR" ] && DIRS+=("$DIR")
done <<< "${NPM_DIRS:-}"

# A missing package.json is hashed as such: install.sh reports it right after this step.
HASH="$(
  printf '%s\n' "${DIRS[@]}" | LC_ALL=C sort -u | while IFS= read -r DIR; do
    case "$DIR" in /*) FILE="$DIR/package.json" ;; *) FILE="$GITHUB_WORKSPACE/$DIR/package.json" ;; esac
    if [ -f "$FILE" ]; then SUM="$(sha256sum < "$FILE" | cut -c1-64)"; else SUM=missing; fi
    printf '%s %s\n' "$DIR" "$SUM"
  done | sha256sum | cut -c1-16
)"

# An install that downloads nothing leaves no cache directory, and the save would only warn.
mkdir -p "$HOME/.npm/_cacache"

{
  echo "key=npm-$CACHE_FAMILY-$WEEK-$HASH"
  echo "restore-keys=npm-$CACHE_FAMILY-$WEEK-"
} >> "$GITHUB_OUTPUT"
