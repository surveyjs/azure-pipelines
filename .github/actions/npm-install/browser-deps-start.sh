#!/usr/bin/env bash
# Usage (env): NPM_DIRS - as in browser-deps.sh; RUNNER_TEMP - the runner's temp directory.
# Starts browser-deps.sh in the background and returns: apt runs while the job builds, and the
# browser-deps-wait action waits for it before the tests - ~40 s off every browser job. The runner
# leaves a step's background processes alone until the job ends.
#
# State, shared with browser-deps-wait/wait.sh: $RUNNER_TEMP/browser-deps/log - the output;
# $RUNNER_TEMP/browser-deps/status - the exit status, written (atomically) once it has finished.
set -euo pipefail

STATE="$RUNNER_TEMP/browser-deps"
rm -rf "$STATE"
mkdir -p "$STATE"

# Every stream redirected: a background process holding the step's stdout would keep it open.
nohup bash -c 'bash "$1"; echo $? > "$2/status.tmp"; mv "$2/status.tmp" "$2/status"' \
  _ "$(dirname "$0")/browser-deps.sh" "$STATE" > "$STATE/log" 2>&1 < /dev/null &
echo "Installing in the background (pid $!); browser-deps-wait waits for it before the tests"
