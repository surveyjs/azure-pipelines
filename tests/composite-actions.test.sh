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

finish
