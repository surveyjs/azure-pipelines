#!/usr/bin/env bash
# Usage (env): RUNNER_TEMP - the runner's temp directory; BROWSER_DEPS_TIMEOUT - seconds to wait,
# 600 when empty.
# Waits for the install npm-install/browser-deps-start.sh runs in the background, prints its log
# and exits with its status. State: $RUNNER_TEMP/browser-deps/{log,status} (see that script).
set -uo pipefail

STATE="$RUNNER_TEMP/browser-deps"
if [ ! -d "$STATE" ]; then
  echo "::error::The Chromium system libraries were never installed - npm-install starts that with browsers: 'true'"
  exit 1
fi

TIMEOUT="${BROWSER_DEPS_TIMEOUT:-600}"
WAITED=0
while [ ! -f "$STATE/status" ] && [ "$WAITED" -lt "$TIMEOUT" ]; do
  sleep 1
  WAITED=$((WAITED + 1))
done

echo "::group::Chromium system libraries and fonts-ubuntu (waited ${WAITED}s)"
cat "$STATE/log"
echo "::endgroup::"

if [ ! -f "$STATE/status" ]; then
  echo "::error::Installing the Chromium system libraries and fonts-ubuntu did not finish in ${TIMEOUT}s"
  exit 1
fi
STATUS="$(cat "$STATE/status")"
if [ "$STATUS" != 0 ]; then
  echo "::error::Installing the Chromium system libraries and fonts-ubuntu failed (exit $STATUS) - the log is above"
  exit "$STATUS"
fi
