#!/usr/bin/env bash
# Runs every tests/*.test.sh from the repository root. Needs bash, git and jq
# (Windows: `winget install --id jqlang.jq -e`; the GitHub runners have all three).
cd "$(dirname "$0")/.." || exit 2
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git is required"; exit 2; }

# Windows builds of jq write CRLF, while the scripts run on Linux runners, where jq writes LF.
# Binary mode makes the local runs see what the runners see.
if [ "$(jq -rn '"x"' | od -An -c | tr -d ' \n')" = 'x\r\n' ]; then
  jq() { command jq -b "$@"; }
  export -f jq
fi

STATUS=0
for T in tests/*.test.sh; do
  echo "== $T"
  bash "$T" || STATUS=1
done
exit "$STATUS"
