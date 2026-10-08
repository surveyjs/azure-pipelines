# Tests of .github/actions/publish-test-results/scr-diff.sh - the screenshot diff page built from a
# Playwright JSON report. tests/fixtures/playwright is a real report of Playwright 1.60 (paths made
# relative): a test with two soft mismatches that failed both attempts, a test without a baseline,
# a flaky test and a passed one.
source tests/lib.sh

TMP="$(mktemp -d)"
cp -r tests/fixtures/playwright "$TMP/fx"

run() { # <results.json> [max bytes]
  rm -f "$TMP/page.html"
  : > "$TMP/output"
  OUT="$(RESULTS_JSON="$1" OUT_FILE="$TMP/page.html" TITLE="React SCR Tests" MAX_BYTES="${2:-}" \
    GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=surveyjs/survey-library GITHUB_RUN_ID=123 \
    GITHUB_OUTPUT="$TMP/output" bash .github/actions/publish-test-results/scr-diff.sh 2>&1)"
  STATUS=$?
  COUNT="$(sed -n 's/^count=//p' "$TMP/output")"
  FAILED="$(sed -n 's/^failed=//p' "$TMP/output")"
  FLAKY="$(sed -n 's/^flaky=//p' "$TMP/output")"
  PAGE="$(cat "$TMP/page.html" 2>/dev/null)"
}

run "$TMP/fx/results.json"
assert_eq "a report with mismatches passes" 0 "$STATUS"
assert_eq "every mismatched screenshot is counted, soft ones separately" 4 "$COUNT"
assert_eq "three of them in failed tests" 3 "$FAILED"
assert_eq "one in a flaky test" 1 "$FLAKY"
assert_contains "the page has the title" "$PAGE" "<h1>React SCR Tests</h1>"
assert_contains "and links the run" "$PAGE" 'href="https://github.com/surveyjs/survey-library/actions/runs/123"'
assert_contains "the images are embedded" "$PAGE" "data:image/png;base64,$(base64 -w0 "$TMP/fx/screenshots/panel-first.png")"
assert_eq "expected, actual and diff of each mismatch; no diff without a baseline" 11 "$(grep -o '<img ' <<< "$PAGE" | wc -l | tr -d ' ')"
assert_contains "the test path is escaped" "$PAGE" "Panel › title &lt;b&gt; › two soft mismatches &lt;script&gt;x&lt;/script&gt;"
assert_not_contains "no raw markup from test titles" "$PAGE" "<script>"
assert_contains "the project is shown" "$PAGE" "[vrt]"
assert_contains "a failed test shows its last attempt" "$PAGE" "retry #1"
assert_contains "the pixel difference is shown" "$PAGE" "384 pixels (ratio 1.00 of all image pixels) are different."
assert_contains "a missing baseline is explained" "$PAGE" '<p class="note">A snapshot doesn'
assert_not_contains "a passed test is not on the page" "$PAGE" "stable"
assert_contains "flaky tests are collapsed" "$(sed -n '/<details/,$p' "$TMP/page.html")" "panel-flaky"
assert_not_contains "and only them" "$(sed -n '/<details/,$p' "$TMP/page.html")" "panel-first"
assert_not_contains "the page needs no script" "$PAGE" "<script"

run "$TMP/fx/results.json" 150
assert_eq "over the size limit the page still lists every mismatch" 4 "$COUNT"
assert_eq "but embeds only the images that fit" 1 "$(grep -o 'data:image/png' <<< "$PAGE" | wc -l | tr -d ' ')"
assert_contains "and says where the rest is" "$PAGE" "not embedded"

# On the runners Playwright writes absolute attachment paths. MSYS2_ARG_CONV_EXCL: on Windows the
# shell would hand a native jq C:/... for /tmp/..., which is not what the runners see.
MSYS2_ARG_CONV_EXCL='*' jq --arg d "$TMP/fx/" \
  'walk(if type == "object" and has("path") then .path = $d + .path else . end)' \
  < "$TMP/fx/results.json" > "$TMP/absolute.json"
run "$TMP/absolute.json"
assert_eq "absolute attachment paths are read as they are" 11 "$(grep -o 'data:image/png' <<< "$PAGE" | wc -l | tr -d ' ')"

rm "$TMP/fx/screenshots/panel-flaky.png"
run "$TMP/fx/results.json"
assert_contains "a missing image file is named, not fatal" "$PAGE" "not found: panel-flaky-expected.png"
assert_eq "and the step still passes" 0 "$STATUS"

run "$TMP/none.json"
assert_eq "no report (an a11y run with --reporter dot) passes" 0 "$STATUS"
assert_eq "with nothing to publish" 0 "$COUNT"
assert_eq "and no page" "" "$PAGE"

printf 'not json' > "$TMP/garbage.json"
run "$TMP/garbage.json"
assert_eq "an unreadable report does not fail the step" 0 "$STATUS"
assert_eq "it publishes nothing" 0 "$COUNT"
assert_contains "but warns" "$OUT" "::warning::"

jq 'walk(if type == "object" and has("specs") then .specs |= map(select(.title == "stable")) else . end)' \
  "$TMP/fx/results.json" > "$TMP/green.json"
run "$TMP/green.json"
assert_eq "a green report has nothing to publish" 0 "$COUNT"
assert_eq "and no page" "" "$PAGE"

rm -rf "$TMP"
finish
