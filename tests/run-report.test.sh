# Tests of .github/actions/run-report/collect.sh - the suites of the two parts of the test card, the
# failed and flaky tests and every suite - on reports staged by
# .github/actions/publish-test-results/stage-report.sh. tests/fixtures/junit holds real reports of
# Playwright 1.60 with PLAYWRIGHT_JUNIT_INCLUDE_RETRIES=1: a passed and a flaky test (flaky.xml), a
# passed and a failed one (failed.xml).
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

collect() { # <part> <new> <old>
  rm -rf "$TMP/out" && : > "$TMP/output" && : > "$TMP/summary"
  LOG="$(NEW="$2" OLD="$3" PART="$1" OUT="$TMP/out" GITHUB_OUTPUT="$TMP/output" \
    GITHUB_STEP_SUMMARY="$TMP/summary" GITHUB_RUN_ATTEMPT="${ATTEMPT:-1}" \
    bash .github/actions/run-report/collect.sh 2>&1)"
  STATUS=$?
  NAMES="$(sed -n '/^names<</,/^EOF_RUN_REPORT/p' "$TMP/output" | sed '1d;$d')"
  PATHS="$(sed -n '/^paths<</,/^EOF_RUN_REPORT/p' "$TMP/output" | sed '1d;$d')"
  FOUND="$(sed -n 's/^found=//p' "$TMP/output")"
  FAILED="$(sed -n 's/^failed=//p' "$TMP/output")"
  FLAKY="$(sed -n 's/^flaky=//p' "$TMP/output")"
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
assert_eq "the all part passes" 0 "$STATUS"
assert_eq "every suite with a report, products in order, the shards of one suite together" \
  "$(printf '%s\n' "Library Core Unit Tests" "Library React E2E Tests" "Library React SCR Tests" \
    "Creator Angular E2E Tests" "Analytics E2E Tests" "Theme Adapter Demos SCR shadcn")" "$NAMES"
assert_eq "a glob per suite" "$TMP/out/04/*.xml" "$(sed -n 4p <<< "$PATHS")"
assert_eq "the suite folder holds all its shards" \
  "Creator_Angular_E2E_1.passed.xml Creator_Angular_E2E_2.failed.xml Creator_Angular_E2E_3.flaky.xml" \
  "$(cd "$TMP/out/04" && echo *)"
assert_eq "every report of this attempt is found" 9 "$FOUND"
assert_eq "the merged artifact of the first attempt" "Test Results" "$MERGED"
assert_eq "the all part writes only its heading, the table is action-junit-report's" "### All suites" "$SUMMARY"

collect fails "$N" "$TMP/old"
assert_eq "the fails part passes" 0 "$STATUS"
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
assert_contains "the part opens with the failed and flaky tests of each suite, the shards summed" "$SUMMARY" \
  "$(printf '%s\n' "### Failed and flaky tests" "" "| Suite | Failed | Flaky |" "| --- | ---: | ---: |" \
    "| Library React SCR Tests | 0 | 1 |" "| Creator Angular E2E Tests | 1 | 1 |")"
assert_eq "the table comes first, the diff links after it" "### Failed and flaky tests" "$(head -1 "$TMP/summary")"
assert_eq "the failed tests of the part are counted" 1 "$FAILED"
assert_eq "and the flaky ones" 2 "$FLAKY"

# A report on one line, the way some reporters write it: a test counts once, retries or not.
printf '%s' '<testsuites><testsuite name="s" tests="3"><testcase name="a"><failure message="x"/><rerunFailure message="x"/></testcase><testcase name="b"><flakyFailure message="y"/><flakyError message="y"/></testcase><testcase name="c"><error message="z"/></testcase></testsuite></testsuites>' \
  > "$TMP/oneline.xml"
stage "$TMP/new3" PDF_Test "PDF Tests" failure "$TMP/oneline.xml"
collect fails "$TMP/new3" "$TMP/none"
assert_contains "the tags are counted wherever they are" "$SUMMARY" "| PDF Tests | 2 | 1 |"

# A test script of a few runs, a JUnit file each: junit-file is a glob.
mkdir -p "$TMP/runs" && cp "$FX/failed.xml" "$FX/flaky.xml" "$TMP/runs/"
stage "$TMP/new4" Analytics_Unit "Analytics Unit Tests" failure "$TMP/runs/*.xml"
assert_eq "every file of the glob is staged" "failed.xml flaky.xml meta.json" \
  "$(cd "$TMP/new4/JUnit_Analytics_Unit/Analytics_Unit" && echo *)"
collect fails "$TMP/new4" "$TMP/none"
assert_contains "and counted" "$SUMMARY" "| Analytics Unit Tests | 1 | 1 |"
assert_eq "and laid out for the part" "Analytics_Unit.failed.xml Analytics_Unit.flaky.xml" "$(cd "$TMP/out/01" && echo *)"

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
collect all "$TMP/none" "$TMP/none"
assert_eq "no heading of the all part either - a run of SCR Update" "" "$SUMMARY"

# details.sh: the failed and flaky tests out of the outputs of action-junit-report
details() { # <detailed_summary> <flaky_summary> <flaky>
  : > "$TMP/summary"
  DETAILED="$1" FLAKY_TABLE="$2" FLAKY="$3" GITHUB_STEP_SUMMARY="$TMP/summary" \
    bash .github/actions/run-report/details.sh
  STATUS=$?
  SUMMARY="$(cat "$TMP/summary")"
}
FAILED_BLOCKS='<p><strong>Failed tests</strong></p>
<details><summary>❌ <strong>PDF Tests</strong> › a</summary><br><pre>x</pre></details>'
FLAKY_ROWS='<table><tr><th>Test</th><th>Retries</th></tr><tr><td>b</td><td>1</td></tr></table>'
details "<table></table>$FAILED_BLOCKS" "$FLAKY_ROWS" 1
assert_eq "details pass" 0 "$STATUS"
assert_eq "the failed tests with their logs, then the flaky ones, without the empty details table" \
  "$(printf '%s\n\n%s\n%s' "$FAILED_BLOCKS" "<p><strong>Flaky tests</strong></p>" "$FLAKY_ROWS")" "$SUMMARY"
details "<table></table>" '<table><tr><th>Test</th><th>Retries</th></tr></table>' 0
assert_eq "without failed and flaky tests nothing is written" "" "$SUMMARY"
details "" "$FLAKY_ROWS" 1
assert_eq "flaky tests alone" "$(printf '%s\n%s' "<p><strong>Flaky tests</strong></p>" "$FLAKY_ROWS")" "$SUMMARY"

rm -rf "$TMP"
finish
