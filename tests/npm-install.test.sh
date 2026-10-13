# Tests of .github/actions/npm-install/{install,browser-deps}.sh with npm, npx and sudo stubbed out.
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
# install-deps --dry-run lists the missing packages the way Playwright 1.60-1.62 does, unless
# $TMP/dry-all (everything installed) or $TMP/dry-odd (an output it does not recognize) exists
cat > "$TMP/bin/npx" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s\n' "$(basename "$PWD")" "$*" >> "$NPX_LOG"
case "$*" in
  *--dry-run*)
    if [ -f "$STUB_DIR/dry-all" ]; then echo "All system dependencies are installed."; exit 0; fi
    if [ -f "$STUB_DIR/dry-odd" ]; then echo "sudo -- sh -c \"apt-get install fonts-a\""; exit 0; fi
    printf 'Missing system dependencies (2):\n  fonts-a\n  libfreetype6\n'
    exit 1 ;;
esac
EOF
# The same log as npx, to keep the order. sed really runs (on the scratch mirror list); a
# --download-only times out (124) while $TMP/slow holds a count above zero, one per call.
cat > "$TMP/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo|%s\n' "$*" >> "$NPX_LOG"
[ "$1" != sed ] || exec "$@"
case "$*" in
  *--download-only*)
    N="$(cat "$STUB_DIR/slow" 2>/dev/null || echo 0)"
    if [ "$N" -gt 0 ]; then echo $((N - 1)) > "$STUB_DIR/slow"; exit 124; fi ;;
esac
EOF
chmod +x "$TMP/bin/npm" "$TMP/bin/npx" "$TMP/bin/sudo"
export PATH="$TMP/bin:$PATH" GITHUB_WORKSPACE="$TMP/ws" NPM_LOG="$TMP/npm.log" NPX_LOG="$TMP/npx.log" \
  STUB_DIR="$TMP" APT_MIRRORS_FILE="$TMP/apt-mirrors.txt"
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
# The runner's apt takes its mirrors from this list, azure first (/etc/apt/apt-mirrors.txt).
MIRRORS="$(printf 'http://azure.archive.ubuntu.com/ubuntu/\tpriority:1\nhttps://archive.ubuntu.com/ubuntu/\tpriority:2\nhttps://security.ubuntu.com/ubuntu/\tpriority:3')"
deps() { # [slow downloads]
  : > "$NPX_LOG"
  printf '%s\n' "$MIRRORS" > "$APT_MIRRORS_FILE"
  echo "${1:-0}" > "$TMP/slow"
  OUT="$(NPM_DIRS=$'a\nb' bash .github/actions/npm-install/browser-deps.sh 2>&1)"
  STATUS=$?
  LOG="$(grep -v '^sudo|sed ' "$NPX_LOG")"
}
DOWNLOAD='apt-get install --download-only -y --no-install-recommends'
FONTS='sudo|apt-get install -y --no-install-recommends fonts-ubuntu'

deps
assert_eq "the missing packages and fonts-ubuntu download under a 60 s watchdog, then install-deps and the font install from them" \
  "$(printf '%s\n' 'sudo|apt-get update' 'b|--no-install playwright install-deps --dry-run chromium' \
    "sudo|timeout 60 $DOWNLOAD fonts-a libfreetype6 fonts-ubuntu" \
    'b|--no-install playwright install-deps chromium' "$FONTS")" "$LOG"
assert_eq "a fast mirror stays" "$MIRRORS" "$(cat "$APT_MIRRORS_FILE")"

deps 1
assert_eq "a download over the watchdog leaves the azure mirror and downloads again for up to 300 s" \
  "$(printf '%s\n' 'sudo|apt-get update' 'b|--no-install playwright install-deps --dry-run chromium' \
    "sudo|timeout 60 $DOWNLOAD fonts-a libfreetype6 fonts-ubuntu" 'sudo|apt-get update' \
    "sudo|timeout 300 $DOWNLOAD fonts-a libfreetype6 fonts-ubuntu" \
    'b|--no-install playwright install-deps chromium' "$FONTS")" "$LOG"
assert_eq "archive.ubuntu.com heads the mirror list then" \
  "$(printf '%s\n' "$MIRRORS" | sed 1d)" "$(cat "$APT_MIRRORS_FILE")"
assert_contains "and the switch is a warning" "$OUT" "::warning::"
assert_eq "the install succeeds" 0 "$STATUS"

deps 2
assert_eq "a slow second mirror still installs - install-deps downloads the rest itself" \
  "$(printf '%s\n' 'b|--no-install playwright install-deps chromium' "$FONTS")" "$(printf '%s\n' "$LOG" | tail -n 2)"
assert_eq "with a second warning" 2 "$(printf '%s\n' "$OUT" | grep -c '::warning::')"
assert_eq "and success" 0 "$STATUS"

rm "$APT_MIRRORS_FILE"
: > "$NPX_LOG"; echo 1 > "$TMP/slow"
OUT="$(NPM_DIRS=$'a\nb' bash .github/actions/npm-install/browser-deps.sh 2>&1)"
assert_contains "no mirror list to switch - the download is retried on the same mirror" "$(cat "$NPX_LOG")" \
  "sudo|timeout 300 $DOWNLOAD"
assert_contains "and the warning says so" "$OUT" "same mirror"

touch "$TMP/dry-all"
deps
assert_contains "nothing missing - only fonts-ubuntu downloads ahead" "$LOG" "sudo|timeout 60 $DOWNLOAD fonts-ubuntu"
assert_not_contains "silently" "$OUT" "::notice::"
rm "$TMP/dry-all"

touch "$TMP/dry-odd"
deps
assert_contains "an unrecognized dry run - only fonts-ubuntu downloads ahead" "$LOG" "sudo|timeout 60 $DOWNLOAD fonts-ubuntu"
assert_contains "with a notice" "$OUT" "::notice::"
rm "$TMP/dry-odd"

: > "$NPX_LOG"
OUT="$(NPM_DIRS='a' bash .github/actions/npm-install/browser-deps.sh 2>&1)"
assert_eq "no Playwright CLI - nothing runs" "" "$(cat "$NPX_LOG")"
assert_contains "but it warns" "$OUT" "::warning::No Playwright CLI"

key() { # <directories> [family] [node version]
  : > "$TMP/out"
  GITHUB_OUTPUT="$TMP/out" NPM_DIRS="$1" CACHE_FAMILY="${2-fam}" NODE_VERSION="${3:-24}" \
    bash .github/actions/npm-install/cache-key.sh
  STATUS=$?
  KEY="$(sed -n 's/^key=//p' "$TMP/out")"
  PATHS="$(sed -n '/^paths<<EOF$/,/^EOF$/{/^paths<<EOF$/d;/^EOF$/d;p}' "$TMP/out")"
}

key $'a\nb'
assert_eq "cache-key succeeds" 0 "$STATUS"
assert_contains "the key is npm-<family>-node<version>-<hash>" "$KEY" "npm-fam-node24-"
assert_eq "and the hash has 16 hex digits" 16 "$(printf '%s' "${KEY#npm-fam-node24-}" | tr -dc '0-9a-f' | wc -c | tr -d ' ')"
assert_eq "the entry holds every directory's node_modules and Playwright's browsers" \
  "$(printf 'a/node_modules\nb/node_modules\n~/.cache/ms-playwright')" "$PATHS"
assert_not_contains "no restore-keys: a miss installs from scratch, as in Azure" "$(cat "$TMP/out")" "restore-keys"
AB="$KEY"

key $'b\r\n\na'
assert_eq "order, blank lines and CRs change neither the key" "$AB" "$KEY"
assert_eq "nor the paths" "$(printf 'a/node_modules\nb/node_modules\n~/.cache/ms-playwright')" "$PATHS"

key 'a'
assert_not_contains "a different set of directories changes the key" "$KEY" "$AB"

echo '{"dependencies":{}}' > "$TMP/ws/b/package.json"
key $'a\nb'
assert_not_contains "an edited package.json changes the key" "$KEY" "$AB"
echo '{}' > "$TMP/ws/b/package.json"

key $'a\nb' fam 22
assert_contains "another Node.js version changes the key" "$KEY" "npm-fam-node22-"

key $'.\n/abs/dir/'
assert_eq "the workspace root and absolute directories map to their node_modules" \
  "$(printf 'node_modules\n/abs/dir/node_modules\n~/.cache/ms-playwright')" "$PATHS"

key $'a\nnopkg'
assert_eq "a missing package.json does not fail the key (install.sh reports it)" 0 "$STATUS"

key 'a' ''
assert_eq "no family - no outputs" "" "$(cat "$TMP/out")"

rm -rf "$TMP"
finish
