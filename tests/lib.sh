# Assertion helpers for tests/*.test.sh. Sourced from the repository root (tests/run.sh cd's
# there). Every test file calls `finish` last: it exits non-zero when an assertion failed.

FAILURES=0

pass() { printf '  ok    %s\n' "$1"; }

fail() {
  printf '  FAIL  %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

# assert_eq <name> <expected> <actual>
assert_eq() {
  if [ "$2" = "$3" ]; then
    pass "$1"
  else
    fail "$1"
    printf '        expected: %s\n        actual:   %s\n' "$2" "$3"
  fi
}

# assert_contains <name> <haystack> <needle>
assert_contains() {
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1"; printf '        missing: %s\n        in:      %s\n' "$3" "$2" ;;
  esac
}

# assert_not_contains <name> <haystack> <needle>
assert_not_contains() {
  case "$2" in
    *"$3"*) fail "$1"; printf '        unexpected: %s\n' "$3" ;;
    *) pass "$1" ;;
  esac
}

# assert_fails <name> <exit status>
assert_fails() {
  if [ "$2" -ne 0 ]; then
    pass "$1"
  else
    fail "$1"
    printf '        expected a non-zero exit status\n'
  fi
}

finish() {
  if [ "$FAILURES" -eq 0 ]; then exit 0; fi
  printf '%s assertion(s) failed\n' "$FAILURES"
  exit 1
}
