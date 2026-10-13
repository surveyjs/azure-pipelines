# Tests of .github/actions/run-report/collect.sh - the suites of the Fails and Test Results cards -
# on reports staged by .github/actions/publish-test-results/stage-report.sh. tests/fixtures/junit
# holds real reports of Playwright 1.60 with PLAYWRIGHT_JUNIT_INCLUDE_RETRIES=1: a passed and a
# flaky test (flaky.xml), a passed and a failed one (failed.xml).
source tests/lib.sh

TMP="$(mktemp -d)"
FX=tests/fixtures/junit
printf '<testsuites><testsuite name="s" tests="1"><testcase name="ok" classname="s"></testcase></testsuite></testsuites>\n' \
  > "$TMP/passed.xml"

# stage <root> <name> <title> <status> <report or ""> [diff url] [failed] [flaky] - an artifact as a
# download of several leaves it: <root>/JUnit_<name>/<name>/
stage() {
  DIR="$1/JUnit_$2/$2" NAME="$2" TITLE="$3" STATUS="$4" JUNIT_FILE="${5:-$TMP/none.xml}" \
    DIFF_URL="${6:-}" DIFF_FAILED="${7:-}" DIFF_FLAKY="${8:-}" GITHUB_RUN_ATTEMPT="${ATTEMPT:-1}" \
    bash .github/actions/publish-test-results/stage-report.sh
}

collect() { # <card> <new> <old>
  rm -rf "$TMP/out" && : > "$TMP/output" && : > "$TMP/summary"
  LOG="$(NEW="$2" OLD="$3" CARD="$1" OUT="$TMP/out" GITHUB_OUTPUT="$TMP/output" \
    GITHUB_STEP_SUMMARY="$TMP/summary" GITHUB_RUN_ATTEMPT="${ATTEMPT:-1}" \
    bash .github/actions/run-report/collect.sh 2>&1)"
  STATUS=$?
  NAMES="$(sed -n '/^names<</,/^EOF_RUN_REPORT/p' "$TMP/output" | sed '1d;$d')"
  PATHS="$(sed -n '/^paths<</,/^EOF_RUN_REPORT/p' "$TMP/output" | sed '1d;$d')"
  FOUND="$(sed -n 's/^found=//p' "$TMP/output")"
  MERGED="$(sed -n 's/^merged=//p' "$TMP/output")"
  SUMMARY="$(cat "$TMP/summary")"
}

N="$TMP/new"
stage "$N" Creator_Angular_E2E_1 "Creator Angular E2E Tests (1/3)" success "$TMP/passed.xml"
stage "$N" Creator_Angular_E2E_2 "Creator Angular E2E Tests (2/3)" failure "$FX/failed.xml"
stage "$N" Creator_Angular_E2E_3 "Creator Angular E2E Tests (3/3)" success "$FX/flaky.xml"
stage "$N" Library_React_SCR "Library React SCR Tests" success "$FX/flaky.xml" "https://x/diff/1" 0 2
stage "$N" Library_React_E2E "Library React E2E Tests" success "$TMP/passed.xml"
stage "$N" Library_Core_Unit "Library Core Unit Tests" success "$TMP/passed.xml"
stage "$N" Analytics_E2E "Analytics E2E Tests" failure "$TMP/passed.xml"
stage "$N" PDF_Test "PDF Tests" failure ""
stage "$N" ThemeAdapterDemos_SCR_shadcn_1 "Theme Adapter Demos SCR shadcn (1/2)" success "$TMP/passed.xml"

collect all "$N" "$TMP/old"
assert_eq "the all card passes" 0 "$STATUS"
assert_eq "every suite with a report, products in order, the shards of one suite together" \
  "$(printf '%s\n' "Library Core Unit Tests" "Library React E2E Tests" "Library React SCR Tests" \
    "Creator Angular E2E Tests" "Analytics E2E Tests" "Theme Adapter Demos SCR shadcn")" "$NAMES"
assert_eq "a glob per suite" "$TMP/out/04/*.xml" "$(sed -n 4p <<< "$PATHS")"
assert_eq "the suite folder holds all its shards" "Creator_Angular_E2E_1.xml Creator_Angular_E2E_2.xml Creator_Angular_E2E_3.xml" \
  "$(cd "$TMP/out/04" && echo *)"
assert_eq "every report of this attempt is found" 9 "$FOUND"
assert_eq "the merged artifact of the first attempt" "Test Results" "$MERGED"
assert_eq "the all card writes no text of its own" "" "$SUMMARY"

collect fails "$N" "$TMP/old"
assert_eq "the fails card passes" 0 "$STATUS"
assert_eq "only the suites with a failed or flaky test" \
  "$(printf '%s\n' "Library React SCR Tests" "Creator Angular E2E Tests")" "$NAMES"
assert_eq "a failing suite comes whole, every shard" 3 "$(ls "$TMP/out/02" | wc -l | tr -d ' ')"
assert_contains "the diff pages are linked" "$SUMMARY" \
  "- [Library React SCR Tests](https://x/diff/1) — 0 screenshot mismatch(es) in failed tests, 2 in flaky tests"
assert_contains "a job that failed without a report is named" "$SUMMARY" \
  "- **PDF Tests** — no test report: the job failed before its tests finished"
assert_contains "and one that failed with a clean report" "$SUMMARY" \
  "- **Analytics E2E Tests** — the job failed, but its report has no failed test: see the job log"
assert_not_contains "a failed job with a failed test is in the tables only" "$SUMMARY" "Creator Angular E2E Tests (2/3)"
assert_contains "the tables get a heading after the lists" "$SUMMARY" "### Failed and flaky tests"

# A re-run: earlier attempts left their reports merged, a single artifact right in the path and
# several in a folder each; the re-run jobs left theirs in this attempt.
O="$TMP/old1"
stage "$O" Creator_Angular_E2E_2 "Creator Angular E2E Tests (2/3)" failure "$FX/failed.xml"
stage "$O" Library_React_E2E "Library React E2E Tests" success "$TMP/passed.xml"
mv "$O/JUnit_Creator_Angular_E2E_2/Creator_Angular_E2E_2" "$O/" && mv "$O/JUnit_Library_React_E2E/Library_React_E2E" "$O/"
rm -r "$O"/JUnit_*
ATTEMPT=2 stage "$TMP/new2" Creator_Angular_E2E_2 "Creator Angular E2E Tests (2/3)" success "$TMP/passed.xml"
ATTEMPT=2 collect fails "$TMP/new2" "$O"
assert_eq "the latest attempt of a report wins" "" "$NAMES"
assert_eq "nothing to say" "" "$SUMMARY"
assert_eq "the merged artifact of a later attempt has a name of its own" "Test Results (attempt 2)" "$MERGED"
ATTEMPT=2 collect all "$TMP/new2" "$O"
assert_eq "the reports of earlier attempts still count" \
  "$(printf '%s\n' "Library React E2E Tests" "Creator Angular E2E Tests")" "$NAMES"
assert_eq "only those of this attempt are merged" 1 "$FOUND"

mkdir -p "$TMP/old2/Test Results" "$TMP/old2/Test Results (attempt 2)"
stage "$TMP/o1" PDF_Test "PDF Tests" failure "$FX/failed.xml"
ATTEMPT=2 stage "$TMP/o2" PDF_Test "PDF Tests" success "$TMP/passed.xml"
mv "$TMP/o1/JUnit_PDF_Test/PDF_Test" "$TMP/old2/Test Results/"
mv "$TMP/o2/JUnit_PDF_Test/PDF_Test" "$TMP/old2/Test Results (attempt 2)/"
ATTEMPT=3 collect fails "$TMP/none" "$TMP/old2"
assert_eq "among merged artifacts too" "" "$NAMES"

collect fails "$TMP/none" "$TMP/none"
assert_eq "no reports pass" 0 "$STATUS"
assert_eq "with no suites" "" "$NAMES$PATHS"
assert_eq "no text" "" "$SUMMARY"
assert_eq "and nothing to merge" 0 "$FOUND"

rm -rf "$TMP"
finish
