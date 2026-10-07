#!/usr/bin/env bash
# Usage (env): NEEDS - toJSON(needs) of the calling job.
# Fails when a needed job ended as failure or cancelled. A job skipped by its own condition
# (scr_update, options on a push) is fine. A failed options job is not: it skips every test job,
# and without this check the run would go green having tested nothing.
set -uo pipefail

if ! printf '%s' "$NEEDS" | jq -e 'type == "object"' >/dev/null 2>&1; then
  echo "::error::NEEDS is not a JSON object"
  exit 1
fi

printf '%s' "$NEEDS" | jq -r 'to_entries[] | "\(.key): \(.value.result)"'

BAD="$(printf '%s' "$NEEDS" | jq -r 'to_entries[] | select(.value.result == "failure" or .value.result == "cancelled") | "\(.key)=\(.value.result)"')"
if [ -n "$BAD" ]; then
  while IFS= read -r L; do echo "::error::$L"; done <<< "$BAD"
  exit 1
fi
echo "All jobs succeeded or were skipped by their own conditions."
