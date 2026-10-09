# Tests of .github/actions/publish-test-results/flaky.sh - the flaky tests of a JUnit report.
# tests/fixtures/junit holds real reports of Playwright 1.60 (paths made relative), written with
# retries: 2 and PLAYWRIGHT_JUNIT_INCLUDE_RETRIES=1 unless named otherwise: a passed and a flaky test
# (flaky.xml, flaky-without-retries.xml), a passed and a failed one (failed.xml).
source tests/lib.sh

TMP="$(mktemp -d)"
FX=tests/fixtures/junit

run() { # <junit file>
  : > "$TMP/output"
  OUT="$(JUNIT_FILE="$1" GITHUB_OUTPUT="$TMP/output" bash .github/actions/publish-test-results/flaky.sh 2>&1)"
  STATUS=$?
  FOUND="$(sed -n 's/^found=//p' "$TMP/output")"
  COUNT="$(sed -n 's/^count=//p' "$TMP/output")"
}

run "$FX/flaky.xml"
assert_eq "a report with a flaky test passes" 0 "$STATUS"
assert_eq "the flaky test is found" true "$FOUND"
assert_eq "and counted" 1 "$COUNT"
assert_contains "and named in the log" "$OUT" "1 flaky test(s) in $FX/flaky.xml"

run "$FX/failed.xml"
assert_eq "a failed test is not flaky - its retries are <rerunFailure>" false "$FOUND"
assert_eq "nothing counted" 0 "$COUNT"

run "$FX/flaky-without-retries.xml"
assert_eq "without PLAYWRIGHT_JUNIT_INCLUDE_RETRIES a flaky test looks passed" false "$FOUND"

# A test flaky over two attempts counts once; another flaky test, with an error, counts too.
awk '{ print } /<\/flakyFailure>/ && !done { print "<flakyFailure message=\"again\" type=\"FAILURE\"></flakyFailure>"; done = 1 }' \
  "$FX/flaky.xml" \
  | sed 's#</testsuite>#<testcase name="other" classname="x"><flakyError message="boom" type="Error"></flakyError></testcase>\n</testsuite>#' \
  > "$TMP/two.xml"
run "$TMP/two.xml"
assert_eq "every flaky test counts once, however many attempts failed" 2 "$COUNT"

run "$TMP/missing.xml"
assert_eq "no report passes" 0 "$STATUS"
assert_eq "with no flaky tests" false "$FOUND"

rm -rf "$TMP"
finish
