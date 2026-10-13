#!/usr/bin/env bash
# Usage (env): DIR - the folder to fill; NAME, TITLE - the artifact name and the report title;
# STATUS - job.status after the tests; JUNIT_FILE - the JUnit report, missing when the tests wrote
# none; DIFF_URL, DIFF_FAILED, DIFF_FLAKY - the screenshot diff page, empty without one;
# GITHUB_RUN_ATTEMPT. Stages the report of the job for the run cards Afterparty makes (run-report):
# DIR/report.xml, a copy of the JUnit report, and DIR/meta.json - name, title, status, attempt and
# diff ({url, failed, flaky}) when the job has a diff page.
set -uo pipefail

mkdir -p "$DIR" || exit 1
if [ -f "$JUNIT_FILE" ]; then
  cp "$JUNIT_FILE" "$DIR/report.xml" || exit 1
fi

jq -n --arg name "$NAME" --arg title "$TITLE" --arg status "$STATUS" \
  --arg attempt "${GITHUB_RUN_ATTEMPT:-1}" --arg url "${DIFF_URL:-}" \
  --arg failed "${DIFF_FAILED:-0}" --arg flaky "${DIFF_FLAKY:-0}" '
  {name: $name, title: $title, status: $status, attempt: ($attempt | tonumber)}
  + (if $url == "" then {}
     else {diff: {url: $url, failed: ($failed | tonumber), flaky: ($flaky | tonumber)}} end)' \
  > "$DIR/meta.json"
