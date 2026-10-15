#!/usr/bin/env bash
# Usage (env): DIR - the folder to fill; NAME, TITLE - the artifact name and the report title;
# STATUS - job.status after the tests; JUNIT_FILE - the JUnit report, or a glob for several (a test
# script of a few runs writes a report each), none when the tests wrote none; DIFF_URL,
# DIFF_FAILED, DIFF_FLAKY - the screenshot diff page, empty without one; GITHUB_RUN_ATTEMPT.
# Stages the report of the job for the test card library.yml makes (run-report): a copy of every
# JUnit file in DIR, and DIR/meta.json - name, title, status, attempt and diff ({url, failed,
# flaky}) when the job has a diff page.
set -uo pipefail

mkdir -p "$DIR" || exit 1
while IFS= read -r F; do
  [ ! -f "$F" ] || cp "$F" "$DIR/" || exit 1
done < <(compgen -G "$JUNIT_FILE")

jq -n --arg name "$NAME" --arg title "$TITLE" --arg status "$STATUS" \
  --arg attempt "${GITHUB_RUN_ATTEMPT:-1}" --arg url "${DIFF_URL:-}" \
  --arg failed "${DIFF_FAILED:-0}" --arg flaky "${DIFF_FLAKY:-0}" '
  {name: $name, title: $title, status: $status, attempt: ($attempt | tonumber)}
  + (if $url == "" then {}
     else {diff: {url: $url, failed: ($failed | tonumber), flaky: ($flaky | tonumber)}} end)' \
  > "$DIR/meta.json"
