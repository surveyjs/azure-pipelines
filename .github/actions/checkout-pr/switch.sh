#!/usr/bin/env bash
# Usage (env): PR_NUMBER - companion PR number or empty; REPO_DIR - the repository's directory;
# REPO_NAME - its name for the log; GIT_TOKEN - optional PAT for the fetch.
set -euo pipefail

PR="${PR_NUMBER:-}"
if [ -z "$PR" ]; then
  echo "No companion PR for $REPO_NAME - staying on the branch tip"
  exit 0
fi
# The number comes from a PR title: anything but digits must not reach git.
if ! [[ "$PR" =~ ^[0-9]+$ ]]; then
  echo "::error::Companion PR for $REPO_NAME must be a number"
  exit 1
fi

AUTH=""
if [ -n "${GIT_TOKEN:-}" ]; then
  AUTH="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GIT_TOKEN" | base64 -w0)"
fi
# The header reaches git through the environment only - it never lands in .git/config. An empty
# value keeps the fetch anonymous.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0="http.https://github.com/.extraheader" GIT_CONFIG_VALUE_0="$AUTH"

cd "$REPO_DIR"
# pull/N/merge, not /head: the PR already merged into its base, the same shape of ref the workflow
# checks out for its own PR. The branch tip alone misses commits the base got after the PR forked,
# so an API that is already on the base branch reads as missing and the build fails. A missing
# merge ref means the PR conflicts with its base - warn and fall back to the tip rather than fail.
if git fetch --depth=1 origin "pull/$PR/merge"; then
  echo "$REPO_NAME PR $PR merged into its base branch"
else
  echo "::warning::pull/$PR/merge is unavailable - $REPO_NAME PR $PR most likely conflicts with its base branch. Falling back to the PR branch tip: this build does not see commits the base branch got after the PR forked."
  git fetch --depth=1 origin "pull/$PR/head"
fi
git checkout --quiet FETCH_HEAD
echo "$REPO_NAME is at $(git rev-parse HEAD)"
