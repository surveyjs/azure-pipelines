# Tests of .github/actions/options/parse.sh: the tags of the PR title and of the commit message.
source tests/lib.sh

TMP="$(mktemp -d)"
run() { # <title> <commit message> [pr number, default 42] [PR head repository, default this one]
  printf '%s' "$1" > "$TMP/title.txt"
  printf '%s' "$2" > "$TMP/commit.txt"
  : > "$TMP/output"
  : > "$TMP/summary"
  OUT="$(PR_NUMBER="${3-42}" HEAD_REPOSITORY="${4-surveyjs/survey-library}" \
    PR_TITLE_FILE="$TMP/title.txt" COMMIT_MESSAGE_FILE="$TMP/commit.txt" \
    GITHUB_REPOSITORY=surveyjs/survey-library GITHUB_OUTPUT="$TMP/output" GITHUB_STEP_SUMMARY="$TMP/summary" \
    bash .github/actions/options/parse.sh 2>&1)"
  STATUS=$?
  PR_TAGS="$(sed -n 's/^pr_tags=//p' "$TMP/output")"
  COMMIT_TAGS="$(sed -n 's/^commit_tags=//p' "$TMP/output")"
  SCR_UPDATE="$(sed -n 's/^scr_update=//p' "$TMP/output")"
  SUMMARY="$(cat "$TMP/summary")"
}

run 'Add the new question type [creator: 1234] [adapters: 56]' 'Add the new question type'
assert_eq "title tags become a JSON object" '{"CREATOR":"1234","ADAPTERS":"56"}' "$PR_TAGS"
assert_eq "no commit tags" '{}' "$COMMIT_TAGS"
assert_eq "scr_update is empty without the tag" '' "$SCR_UPDATE"
assert_eq "valid tags pass" 0 "$STATUS"
assert_contains "the summary links the companion PR" "$SUMMARY" '[surveyjs/survey-creator#1234](https://github.com/surveyjs/survey-creator/pull/1234)'

run 'Fix [Creator : 12 ] and [backport: V2]' 'msg'
assert_eq "names are trimmed and upper-cased, non-PR tags stay text" '{"CREATOR":"12","BACKPORT":"V2"}' "$PR_TAGS"

run 'Fix [WIP] [my-tag: 1] [creator: ]' 'msg'
assert_eq "bare, invalid-name and empty-value title tags are skipped" '{}' "$PR_TAGS"
assert_eq "no summary without tags" '' "$SUMMARY"

run 'Update screenshots' $'Update screenshots\n\n[scr_update]'
assert_eq "a bare commit tag is true" '{"SCR_UPDATE":"true"}' "$COMMIT_TAGS"
assert_eq "scr_update comes from the commit message" 'true' "$SCR_UPDATE"
assert_eq "[scr_update] on a PR from this repository passes" 0 "$STATUS"

# [scr_update] skips every test job, and the SCR Update job cannot push to a fork: without this
# check a fork PR would get a green result having run nothing.
run 'Update screenshots' $'Update screenshots\n\n[scr_update]' 42 someone/survey-library
assert_eq "[scr_update] on a PR from a fork fails the step" 1 "$STATUS"
assert_contains "and says why" "$OUT" '::error::[scr_update] only works on pull requests from surveyjs/survey-library'

run 'Fix' 'msg' 42 someone/survey-library
assert_eq "a fork PR without [scr_update] passes" 0 "$STATUS"

run 'Fix [creator: abc]' 'msg'
assert_eq "a non-numeric companion PR fails the step" 1 "$STATUS"
assert_contains "and names the tag" "$OUT" '::error::The [CREATOR: ...] tag in the PR title must be a pull request number'

run 'Fix' $'msg\n::error::injected\n::set-output name=scr_update::true'
assert_eq "workflow commands in the commit message do not set outputs" '' "$SCR_UPDATE"
TOKEN="$(printf '%s\n' "$OUT" | sed -n 's/^::stop-commands::\(.*\)$/\1/p' | tail -n1)"
STOP_AT="$(printf '%s\n' "$OUT" | grep -n "^::stop-commands::$TOKEN\$" | cut -d: -f1)"
INJECTED_AT="$(printf '%s\n' "$OUT" | grep -n '^::error::injected$' | cut -d: -f1)"
RESUME_AT="$(printf '%s\n' "$OUT" | grep -n "^::$TOKEN::\$" | cut -d: -f1)"
[ -n "$TOKEN" ] && [ "${STOP_AT:-0}" -lt "${INJECTED_AT:-0}" ] && [ "${INJECTED_AT:-0}" -lt "${RESUME_AT:-0}" ]
assert_eq "the commit message is printed between stop-commands and resume" 0 "$?"

run '' '' ''
assert_eq "outside a PR the tags are {}" '{}' "$PR_TAGS"
assert_eq "outside a PR scr_update is empty" '' "$SCR_UPDATE"
assert_eq "outside a PR it passes" 0 "$STATUS"

rm -rf "$TMP"
finish
