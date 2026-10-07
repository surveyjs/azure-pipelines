#!/usr/bin/env bash
# Usage (env): GH_TOKEN, PR_NUMBER, HEAD_SHA, GITHUB_API_URL, GITHUB_REPOSITORY, RUNNER_TEMP.
# Fetches the PR title - fresh, so "Re-run all jobs" sees an edited title - and the message of the
# PR's head commit into $RUNNER_TEMP/options/. Both are attacker-controlled text on fork PRs: they
# travel through files, never through ${{ }}. A failed API call is fatal on purpose: the tags
# select the companion PRs, and losing them silently tests the target branch with a green build.
set -uo pipefail

DIR="$RUNNER_TEMP/options"
mkdir -p "$DIR"
: > "$DIR/title.txt"
: > "$DIR/commit.txt"
if [ -z "${PR_NUMBER:-}" ]; then
  echo "Not a pull request - no PR title to parse"
  exit 0
fi

api() {
  curl -sS -f --max-time 30 \
    -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
    "$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/$1"
}
if ! PR_JSON="$(api "pulls/$PR_NUMBER")"; then
  echo "::error::Could not fetch PR #$PR_NUMBER from the GitHub API (see the curl error above). Companion PR tags are unknown, so the test jobs would silently run against the target branch."
  exit 1
fi
if ! COMMIT_JSON="$(api "commits/$HEAD_SHA")"; then
  echo "::error::Could not fetch the PR's head commit from the GitHub API (see the curl error above)."
  exit 1
fi
printf '%s' "$PR_JSON" | jq -r '.title // ""' > "$DIR/title.txt"
printf '%s' "$COMMIT_JSON" | jq -r '.commit.message // ""' > "$DIR/commit.txt"
