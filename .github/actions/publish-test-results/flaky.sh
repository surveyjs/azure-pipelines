#!/usr/bin/env bash
# Usage (env): JUNIT_FILE - the JUnit report. Sets the found (true / false) and count outputs: the
# tests of the report that failed an attempt and passed a retry. Playwright (1.59+) writes those
# attempts as <flakyFailure> / <flakyError> only with PLAYWRIGHT_JUNIT_INCLUDE_RETRIES=1, which the
# test workflows set; without it a flaky test looks passed. No report - no flaky tests.
set -uo pipefail

COUNT=0
if [ -f "$JUNIT_FILE" ]; then
  # One per <testcase> with a flaky attempt, however many retries it took.
  COUNT="$(awk '/<testcase[ >]/ { flaky = 0 } /<flaky(Failure|Error)[ \/>]/ && !flaky { flaky = 1; n++ }
    END { print n + 0 }' "$JUNIT_FILE")"
fi

if [ "$COUNT" -gt 0 ]; then
  echo "$COUNT flaky test(s) in $JUNIT_FILE"
  printf 'found=true\ncount=%s\n' "$COUNT" >> "$GITHUB_OUTPUT"
else
  printf 'found=false\ncount=0\n' >> "$GITHUB_OUTPUT"
fi
