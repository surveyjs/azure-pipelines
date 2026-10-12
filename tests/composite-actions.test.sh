# Static checks of the composite actions' action.yml files. actionlint does not look into composite
# actions, and the runner validates every action manifest before the job's first step - one bad
# expression fails the whole job ("Failed to load .../action.yml").
source tests/lib.sh

# The runner evaluates ${{ }} even inside `description:` text, where no function is available:
# `${{ !cancelled() }}` in a description failed every job with "Unrecognized function: 'cancelled'".
# Expressions belong under `runs:` and in `outputs.<id>.value` only.
OUTSIDE="$(awk 'FNR == 1 { section = "" } /^[a-z]+:/ { section = $1 }
  /\$\{\{/ && section != "runs:" && $0 !~ /^    value:/ { print FILENAME ":" FNR ": " $0 }' .github/actions/*/action.yml)"
assert_eq "no expression outside runs: and outputs values" "" "$OUTSIDE"

# Steps that must run after a failed step use always(): the caller's `if: ${{ !cancelled() }}`
# decides whether the action runs at all, so cancelled() is never needed inside one.
IN_RUNS="$(awk 'FNR == 1 { section = "" } /^[a-z]+:/ { section = $1 }
  section == "runs:" && /cancelled\(/ { print FILENAME ":" FNR ": " $0 }' .github/actions/*/action.yml)"
assert_eq "no composite step uses cancelled()" "" "$IN_RUNS"

# npm-install only starts the browser install (in the background): an action that asks it for
# browsers must wait for them after it, or the tests race apt.
NO_WAIT=""
for F in .github/actions/*/action.yml; do
  INSTALL="$(grep -n 'actions/npm-install@' "$F" | head -1 | cut -d: -f1)"
  [ -n "$INSTALL" ] && grep -q '^        browsers:' "$F" || continue
  WAIT="$(grep -n 'actions/browser-deps-wait@' "$F" | tail -1 | cut -d: -f1)"
  [ -n "$WAIT" ] && [ "$WAIT" -gt "$INSTALL" ] || NO_WAIT="$NO_WAIT $F"
done
assert_eq "every action that installs browsers waits for them" "" "$NO_WAIT"

finish
