#!/usr/bin/env bash
# Usage (env): NEW - the JUnit_<artifact-name> artifacts of this attempt; OLD - the Test Results*
# artifacts earlier attempts merged theirs into; CARD - fails or all; OUT - the folder to lay the
# reports out in; GITHUB_RUN_ATTEMPT, GITHUB_OUTPUT, GITHUB_STEP_SUMMARY.
# A report is a folder <artifact-name>/ with meta.json and, when the tests wrote one, report.xml
# (publish-test-results/stage-report.sh). download-artifact puts a single artifact right into its
# path and several into a folder each, so the reports are looked up at any depth. A job re-run in
# this attempt left its report in NEW, the others are in OLD: the latest attempt of a name wins.
# A suite is the reports of one title without the shard suffix " (n/m)"; the suites go Library,
# Creator, Analytics, PDF, Theme Adapter Demos, by title within a product. The card's suites are
# laid out as OUT/<NN>/<name>.xml, and the outputs paths and names list them a line each - the
# report_paths and check_name of action-junit-report. The fails card holds the suites with a failed
# or flaky test; it starts with the links to the screenshot diff pages and the jobs that failed
# without a failed test in their report. Also sets found - the reports in NEW, which the merge
# takes - and merged, the name of the merged artifact.
set -uo pipefail

SEP=$'\x1f'
TMP="$(mktemp -d)"

# <name> <attempt> <0 - NEW, 1 - OLD> <meta.json>
for SRC in 0 1; do
  if [ "$SRC" = 0 ]; then ROOT="$NEW"; else ROOT="$OLD"; fi
  [ -d "$ROOT" ] || continue
  find "$ROOT" -name meta.json -type f | while IFS= read -r F; do
    printf '%s%s%s%s%s\n' "$(jq -r '[.name, (.attempt // 1 | tostring)] | join("\u001f")' "$F")" \
      "$SEP" "$SRC" "$SEP" "$F"
  done
done > "$TMP/metas"

FOUND="$(awk -F "$SEP" '$3 == 0' "$TMP/metas" | wc -l | tr -d ' ')"

# The latest attempt of every name: <rank> <suite> <title> <name> <dir> <has report> <failed> <flaky>
# <status> <diff url> <diff failed> <diff flaky>
LC_ALL=C sort -t "$SEP" -k1,1 -k2,2nr -k3,3n "$TMP/metas" | awk -F "$SEP" '!seen[$1]++ { print $4 }' |
  while IFS= read -r F; do
    D="${F%/meta.json}"
    IFS="$SEP" read -r NAME TITLE STATUS URL DIFF_FAILED DIFF_FLAKY < <(jq -r '[.name, .title, .status,
      (.diff.url // ""), (.diff.failed // 0 | tostring), (.diff.flaky // 0 | tostring)] | join("\u001f")' "$F")
    SUITE="$(sed -E 's/ \([0-9]+\/[0-9]+\)$//' <<< "$TITLE")"
    case "$SUITE" in
      "Library "*) RANK=1 ;;
      "Creator "*) RANK=2 ;;
      "Analytics "*) RANK=3 ;;
      "PDF "*) RANK=4 ;;
      "Theme Adapter Demos "*) RANK=5 ;;
      *) RANK=9 ;;
    esac
    HAS=0 FAILED=0 FLAKY=0
    if [ -f "$D/report.xml" ]; then
      HAS=1
      grep -Eq '<(failure|error)[ />]' "$D/report.xml" && FAILED=1
      grep -Eq '<(flakyFailure|flakyError)[ />]' "$D/report.xml" && FLAKY=1
    fi
    printf '%s\n' "$RANK$SEP$SUITE$SEP$TITLE$SEP$NAME$SEP$D$SEP$HAS$SEP$FAILED$SEP$FLAKY$SEP$STATUS$SEP$URL$SEP$DIFF_FAILED$SEP$DIFF_FLAKY"
  done | LC_ALL=C sort -t "$SEP" -k1,1n -k2,2 -k3,3 > "$TMP/reports"

# The card's suites: every suite with a report, or for fails every suite with a failed or flaky test
if [ "$CARD" = fails ]; then
  awk -F "$SEP" '$7 == 1 || $8 == 1 { print $2 }' "$TMP/reports"
else
  awk -F "$SEP" '$6 == 1 { print $2 }' "$TMP/reports"
fi | awk '!seen[$0]++' > "$TMP/suites"

PATHS=""
NAMES=""
N=0
while IFS= read -r SUITE; do
  N=$((N + 1))
  DIR="$OUT/$(printf '%02d' "$N")"
  mkdir -p "$DIR"
  while IFS="$SEP" read -r _ S _ NAME D HAS _; do
    [ "$S" = "$SUITE" ] && [ "$HAS" = 1 ] && cp "$D/report.xml" "$DIR/$NAME.xml"
  done < "$TMP/reports"
  PATHS="$PATHS$DIR/*.xml"$'\n'
  NAMES="$NAMES$SUITE"$'\n'
done < "$TMP/suites"

if [ "$CARD" = fails ]; then
  DIFFS="$(awk -F "$SEP" '$10 != "" {
      text = $11 " screenshot mismatch(es) in failed tests"
      if ($12 != 0) text = text ", " $12 " in flaky tests"
      print "- [" $3 "](" $10 ") — " text
    }' "$TMP/reports")"
  JOBS="$(awk -F "$SEP" '$9 == "failure" && $6 == 0 { print "- **" $3 "** — no test report: the job failed before its tests finished" }
      $9 == "failure" && $6 == 1 && $7 == 0 { print "- **" $3 "** — the job failed, but its report has no failed test: see the job log" }' \
    "$TMP/reports")"
  {
    [ -z "$DIFFS" ] || printf '### Screenshot diffs\n\n%s\n\n' "$DIFFS"
    [ -z "$JOBS" ] || printf '### Failed jobs without a failed test\n\n%s\n\n' "$JOBS"
    [ "$N" = 0 ] || [ -z "$DIFFS$JOBS" ] || printf '### Failed and flaky tests\n\n'
  } >> "$GITHUB_STEP_SUMMARY"
fi

MERGED="Test Results"
[ "${GITHUB_RUN_ATTEMPT:-1}" = 1 ] || MERGED="$MERGED (attempt $GITHUB_RUN_ATTEMPT)"

echo "$N suite(s) for the $CARD card, $FOUND report(s) of this attempt."
{
  printf 'paths<<EOF_RUN_REPORT\n%sEOF_RUN_REPORT\n' "$PATHS"
  printf 'names<<EOF_RUN_REPORT\n%sEOF_RUN_REPORT\n' "$NAMES"
  printf 'found=%s\nmerged=%s\n' "$FOUND" "$MERGED"
} >> "$GITHUB_OUTPUT"
rm -rf "$TMP"
