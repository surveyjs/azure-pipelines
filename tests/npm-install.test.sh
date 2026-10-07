# Tests of .github/actions/npm-install/{install,browser-deps}.sh with npm and npx stubbed out.
source tests/lib.sh

TMP="$(mktemp -d)"
mkdir -p "$TMP/bin" "$TMP/ws/a" "$TMP/ws/b" "$TMP/ws/nopkg"
echo '{}' > "$TMP/ws/a/package.json"
echo '{}' > "$TMP/ws/b/package.json"
cat > "$TMP/bin/npm" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "$(basename "$PWD")" "$*" "${GIT_CONFIG_VALUE_0:-}" "${PUPPETEER_SKIP_DOWNLOAD:-}" >> "$NPM_LOG"
[ ! -f fail-install ] || exit 1
EOF
cat > "$TMP/bin/npx" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s\n' "$(basename "$PWD")" "$*" >> "$NPX_LOG"
EOF
chmod +x "$TMP/bin/npm" "$TMP/bin/npx"
export PATH="$TMP/bin:$PATH" GITHUB_WORKSPACE="$TMP/ws" NPM_LOG="$TMP/npm.log" NPX_LOG="$TMP/npx.log"
INSTALL='install --no-audit --no-fund --no-update-notifier --no-package-lock'

run() { # <directories> [token] [update]
  : > "$NPM_LOG"
  OUT="$(NPM_DIRS="$1" GITHUB_TOKEN="${2:-}" NPM_UPDATE="${3:-}" bash .github/actions/npm-install/install.sh 2>&1)"
  STATUS=$?
  LOG="$(sort "$NPM_LOG")"
}

run $'a\n\nb'
assert_eq "every listed directory installs, blank lines ignored" 0 "$STATUS"
assert_eq "one npm install per directory, Azure flags, puppeteer download off" \
  "$(printf 'a|%s||true\nb|%s||true' "$INSTALL" "$INSTALL")" "$LOG"

run 'a' 'secret-token'
assert_contains "the token becomes a basic extraheader for git" "$LOG" "|AUTHORIZATION: basic eC1hY2Nlc3MtdG9rZW46c2VjcmV0LXRva2Vu|"

run 'a' '' 'a eslint-plugin-surveyjs'
assert_contains "update runs npm update in its directory after the install" "$LOG" \
  "a|update eslint-plugin-surveyjs --no-package-lock --no-audit --no-fund||true"

touch "$TMP/ws/b/fail-install"
run $'a\nb'
assert_eq "a failed install fails the step" 1 "$STATUS"
assert_contains "and names the directory" "$OUT" "FAILED: $TMP/ws/b"
rm "$TMP/ws/b/fail-install"

run 'nopkg'
assert_eq "a directory without package.json fails" 1 "$STATUS"
assert_contains "and says why" "$OUT" "package.json not found"

run "$TMP/ws/a"
assert_eq "absolute paths are taken as they are" "a|$INSTALL||true" "$LOG"

mkdir -p "$TMP/ws/b/node_modules/.bin"
printf '#!/bin/sh\n' > "$TMP/ws/b/node_modules/.bin/playwright"
chmod +x "$TMP/ws/b/node_modules/.bin/playwright"
: > "$NPX_LOG"
OUT="$(NPM_DIRS=$'a\nb' bash .github/actions/npm-install/browser-deps.sh 2>&1)"
assert_eq "install-deps runs with the first Playwright CLI found" "b|--no-install playwright install-deps chromium" "$(cat "$NPX_LOG")"

: > "$NPX_LOG"
OUT="$(NPM_DIRS='a' bash .github/actions/npm-install/browser-deps.sh 2>&1)"
assert_eq "no Playwright CLI - nothing runs" "" "$(cat "$NPX_LOG")"
assert_contains "but it warns" "$OUT" "::warning::No Playwright CLI"

rm -rf "$TMP"
finish
