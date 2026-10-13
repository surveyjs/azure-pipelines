#!/usr/bin/env bash
# Usage (env): DETAILED, FLAKY_TABLE - the detailed_summary and flaky_summary outputs of
# action-junit-report; FLAKY - the flaky tests collect.sh counted; GITHUB_STEP_SUMMARY. Ends the
# fails card with the failed tests and the flaky ones. The action writes no summary there - its
# totals table is not what that card is about - so only these parts of it go in: DETAILED is the
# details table, empty with the failed tests shown as blocks with their logs, and those blocks;
# FLAKY_TABLE is a header alone without a flaky test.
set -uo pipefail

DETAILED="${DETAILED#<table></table>}"
{
  [ -z "$DETAILED" ] || printf '%s\n\n' "$DETAILED"
  [ "${FLAKY:-0}" = 0 ] || printf '<p><strong>Flaky tests</strong></p>\n%s\n\n' "$FLAKY_TABLE"
} >> "$GITHUB_STEP_SUMMARY"
