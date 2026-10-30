#!/usr/bin/env bash
# Usage (env): REPO_URL - the repository's clone URL; REF - the branch or tag to check out, or empty;
# REPO_NAME - its name for the log; GIT_TOKEN - optional PAT for the lookup. Writes `ref` to
# $GITHUB_OUTPUT: REF when the repository has it, empty (= its default branch) when it does not.
set -euo pipefail

if [ -z "${REF:-}" ]; then
  echo "ref=" >> "$GITHUB_OUTPUT"
  exit 0
fi

AUTH=""
if [ -n "${GIT_TOKEN:-}" ]; then
  AUTH="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GIT_TOKEN" | base64 -w0)"
fi
# The header reaches git through the environment only, as in checkout-pr/switch.sh.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0="http.https://github.com/.extraheader" GIT_CONFIG_VALUE_0="$AUTH"

# A PR into a branch only survey-library has (a stacked PR, a test branch) names that branch for
# every companion repository. Exit code 2 is "no such ref"; anything else (network, auth) fails the
# step rather than quietly building another branch.
STATUS=0
git ls-remote --exit-code "$REPO_URL" "refs/heads/$REF" "refs/tags/$REF" > /dev/null || STATUS=$?
case "$STATUS" in
  0) echo "ref=$REF" >> "$GITHUB_OUTPUT" ;;
  2)
    echo "::notice::$REPO_NAME has no branch $REF - building its default branch"
    echo "ref=" >> "$GITHUB_OUTPUT"
    ;;
  *) exit "$STATUS" ;;
esac
