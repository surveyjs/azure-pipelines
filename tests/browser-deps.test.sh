# Tests of .github/actions/npm-install/browser-deps-start.sh and
# .github/actions/browser-deps-wait/wait.sh with npx and sudo stubbed out.
source tests/lib.sh

TMP="$(mktemp -d)"
mkdir -p "$TMP/bin" "$TMP/ws/a/node_modules/.bin" "$TMP/rt"
printf '#!/bin/sh\n' > "$TMP/ws/a/node_modules/.bin/playwright"
chmod +x "$TMP/ws/a/node_modules/.bin/playwright"
# npx holds while $TMP/hold exists - the builds of a real job - and fails when $TMP/fail does
cat > "$TMP/bin/npx" <<'EOF'
#!/usr/bin/env bash
while [ -f "$STUB_DIR/hold" ]; do sleep 0.1; done
echo "npx $*"
[ ! -f "$STUB_DIR/fail" ] || exit 3
EOF
cat > "$TMP/bin/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo $*"
EOF
chmod +x "$TMP/bin/npx" "$TMP/bin/sudo"
export PATH="$TMP/bin:$PATH" GITHUB_WORKSPACE="$TMP/ws" STUB_DIR="$TMP" NPM_DIRS=a

start() {
  OUT="$(RUNNER_TEMP="$TMP/rt" timeout 10 bash .github/actions/npm-install/browser-deps-start.sh 2>&1)"
  STATUS=$?
}
wait_deps() { # [timeout in seconds] [runner temp]
  OUT="$(RUNNER_TEMP="${2:-$TMP/rt}" BROWSER_DEPS_TIMEOUT="${1:-}" \
    bash .github/actions/browser-deps-wait/wait.sh 2>&1)"
  STATUS=$?
}

touch "$TMP/hold"
start
assert_eq "start returns while the install still runs" 0 "$STATUS"
assert_eq "and no status is written before the install ends" "no" \
  "$([ -e "$TMP/rt/browser-deps/status" ] && echo yes || echo no)"
rm "$TMP/hold"
wait_deps
assert_eq "wait succeeds once the install has succeeded" 0 "$STATUS"
assert_contains "and prints its log" "$OUT" "npx --no-install playwright install-deps chromium"
assert_contains "the font as well" "$OUT" "sudo apt-get install -y --no-install-recommends fonts-ubuntu"

touch "$TMP/fail"
start
wait_deps
assert_eq "a failed install fails the wait with its exit status" 3 "$STATUS"
assert_contains "names the failure" "$OUT" "::error::"
assert_contains "and prints the log" "$OUT" "npx --no-install playwright install-deps chromium"
rm "$TMP/fail"

touch "$TMP/hold"
start
wait_deps 1
assert_fails "an install that outlives the timeout fails the wait" "$STATUS"
assert_contains "and says so" "$OUT" "did not finish in 1s"
rm "$TMP/hold"
wait_deps

touch "$TMP/fail"
start
wait_deps
rm "$TMP/fail"
start
wait_deps
assert_eq "a new start drops the status of the previous install" 0 "$STATUS"

mkdir -p "$TMP/rt2"
wait_deps "" "$TMP/rt2"
assert_fails "wait without a start fails" "$STATUS"
assert_contains "and points at npm-install" "$OUT" "browsers: 'true'"

rm -rf "$TMP"
finish
