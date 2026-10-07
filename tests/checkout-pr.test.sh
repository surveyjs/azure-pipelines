# Tests of .github/actions/checkout-pr/switch.sh against a local remote with GitHub-style
# refs/pull/N/{head,merge} refs.
source tests/lib.sh

TMP="$(mktemp -d)"
GIT=(git -c user.email=test@example.com -c user.name=test -c init.defaultBranch=main)
"${GIT[@]}" init -q --bare "$TMP/remote.git"
"${GIT[@]}" init -q "$TMP/src"
(
  cd "$TMP/src" || exit 1
  "${GIT[@]}" commit -q --allow-empty -m base
  "${GIT[@]}" push -q "$TMP/remote.git" main
  "${GIT[@]}" switch -q -c feature
  "${GIT[@]}" commit -q --allow-empty -m "pr head"
  "${GIT[@]}" switch -q main
  "${GIT[@]}" merge -q --no-ff -m "pr merge" feature
  # PR 1 has both refs; PR 2 conflicts with its base, so GitHub keeps no merge ref for it.
  "${GIT[@]}" push -q "$TMP/remote.git" feature:refs/pull/1/head main:refs/pull/1/merge feature:refs/pull/2/head
)
HEAD_SHA="$(git -C "$TMP/src" rev-parse feature)"
MERGE_SHA="$(git -C "$TMP/src" rev-parse main)"

fresh() {
  rm -rf "$TMP/work"
  git clone -q --depth 1 "file://$TMP/remote.git" "$TMP/work" 2>/dev/null
  BASE_SHA="$(git -C "$TMP/work" rev-parse HEAD)"
}
run() {
  OUT="$(PR_NUMBER="$1" REPO_DIR="$TMP/work" REPO_NAME=survey-creator GIT_TOKEN="" \
    bash .github/actions/checkout-pr/switch.sh 2>&1)"
  STATUS=$?
  NOW="$(git -C "$TMP/work" rev-parse HEAD)"
}

fresh; run 1
assert_eq "a PR with a merge ref is checked out at pull/N/merge" "$MERGE_SHA" "$NOW"
assert_contains "and the log says so" "$OUT" "survey-creator PR 1 merged into its base branch"

fresh; run 2
assert_eq "without a merge ref it falls back to pull/N/head" "$HEAD_SHA" "$NOW"
assert_contains "with a warning" "$OUT" "::warning::pull/2/merge is unavailable - survey-creator PR 2"
assert_eq "the fallback is not an error" 0 "$STATUS"

fresh; run ''
assert_eq "no PR leaves the branch tip" "$BASE_SHA" "$NOW"
assert_eq "no PR is not an error" 0 "$STATUS"

fresh; run '1; touch pwned'
assert_eq "a non-numeric PR is rejected" 1 "$STATUS"
assert_eq "before git runs" "$BASE_SHA" "$NOW"
assert_contains "with an error" "$OUT" "::error::Companion PR for survey-creator must be a number"

fresh; run 3
assert_fails "a PR without any ref fails the step" "$STATUS"

rm -rf "$TMP"
finish
