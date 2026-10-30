# Tests of .github/actions/branch-or-default/resolve.sh against a local remote: a branch or tag the
# remote has is kept, a missing one resolves to empty (the default branch), a broken remote fails.
source tests/lib.sh

TMP="$(mktemp -d)"
GIT=(git -c user.email=test@example.com -c user.name=test -c init.defaultBranch=main)
"${GIT[@]}" init -q --bare "$TMP/remote.git"
"${GIT[@]}" init -q "$TMP/src"
(
  cd "$TMP/src" || exit 1
  "${GIT[@]}" commit -q --allow-empty -m base
  "${GIT[@]}" tag v1
  "${GIT[@]}" push -q "$TMP/remote.git" main main:feature/x v1
)

run() {
  : > "$TMP/output"
  OUT="$(REPO_URL="${2:-file://$TMP/remote.git}" REF="$1" REPO_NAME=survey-creator GIT_TOKEN="" \
    GITHUB_OUTPUT="$TMP/output" bash .github/actions/branch-or-default/resolve.sh 2>&1)"
  STATUS=$?
  RESOLVED="$(sed -n 's/^ref=//p' "$TMP/output")"
}

run feature/x
assert_eq "a branch the remote has is kept" "feature/x" "$RESOLVED"
assert_not_contains "without a notice" "$OUT" "::notice::"
assert_eq "and without an error" 0 "$STATUS"

run v1
assert_eq "a tag the remote has is kept" "v1" "$RESOLVED"

run test/perf-nightly
assert_eq "a missing branch resolves to the default branch" "" "$RESOLVED"
assert_contains "with a notice" "$OUT" "::notice::survey-creator has no branch test/perf-nightly - building its default branch"
assert_eq "a missing branch is not an error" 0 "$STATUS"

run ''
assert_eq "no ref stays empty" "" "$RESOLVED"
assert_eq "no ref is not an error" 0 "$STATUS"

run main "file://$TMP/missing.git"
assert_fails "an unreachable remote fails the step" "$STATUS"
assert_not_contains "instead of falling back" "$OUT" "::notice::"

rm -rf "$TMP"
finish
