# Tests of .github/actions/result/check.sh - the single required status check.
source tests/lib.sh

run() {
  OUT="$(NEEDS="$1" bash .github/actions/result/check.sh 2>&1)"
  STATUS=$?
}

run '{"lint":{"result":"success"},"options":{"result":"skipped"},"library-core":{"result":"success"}}'
assert_eq "success and skipped pass" 0 "$STATUS"
assert_contains "every job's result is printed" "$OUT" "options: skipped"

run '{"lint":{"result":"success"},"library-core":{"result":"failure"}}'
assert_eq "a failed job fails the check" 1 "$STATUS"
assert_contains "the failed job is named" "$OUT" "::error::library-core=failure"

run '{"options":{"result":"failure"},"library-core":{"result":"skipped"},"creator-core":{"result":"skipped"}}'
assert_eq "a failed options job fails the check although the tests were skipped" 1 "$STATUS"

run '{"creator-react":{"result":"cancelled"}}'
assert_eq "a cancelled job fails the check" 1 "$STATUS"

run '{}'
assert_eq "no needs pass" 0 "$STATUS"

run 'not json'
assert_eq "garbage fails instead of passing" 1 "$STATUS"

# [scr_update]: the test jobs are skipped by their own condition, SCR Update ran.
run '{"lint":{"result":"success"},"options":{"result":"success"},"scr-update":{"result":"success"},"library-core":{"result":"skipped"},"library-react":{"result":"skipped"},"creator-core":{"result":"skipped"},"creator-react":{"result":"skipped"},"analytics":{"result":"skipped"},"pdf":{"result":"skipped"},"theme-adapter-demos":{"result":"skipped"}}'
assert_eq "[scr_update]: skipped test jobs pass" 0 "$STATUS"

run '{"lint":{"result":"success"},"options":{"result":"success"},"scr-update":{"result":"skipped"},"library-react":{"result":"success"},"creator-react":{"result":"failure"}}'
assert_eq "a failed test workflow fails the check" 1 "$STATUS"
assert_contains "the failed test workflow is named" "$OUT" "::error::creator-react=failure"

finish
