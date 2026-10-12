# Static checks of the workflows in .github/workflows. actionlint treats
# `uses: surveyjs/azure-pipelines/...@ref` as a remote reference and does not follow it, while
# GitHub rejects the whole run at start when such a reference points at a missing file.
# EXTRA_WORKFLOWS - space-separated workflow files of other repositories (survey-library's caller
# workflow) whose references are checked too.
source tests/lib.sh

MISSING=""
while IFS= read -r REF; do
  P="${REF#surveyjs/azure-pipelines/}"
  P="${P%@*}"
  case "$P" in
    .github/workflows/*) [ -f "$P" ] || MISSING="$MISSING $REF" ;;
    .github/actions/*) [ -f "$P/action.yml" ] || MISSING="$MISSING $REF" ;;
    *) MISSING="$MISSING $REF" ;;
  esac
done < <(grep -ho 'surveyjs/azure-pipelines/\.github/[^ ]*@[A-Za-z0-9._-]*' \
  .github/workflows/*.yml .github/actions/*/action.yml ${EXTRA_WORKFLOWS:-} | sort -u)
assert_eq "every internal uses: points at an existing workflow or action" "" "$MISSING"

# actionlint matches the `with:` of a call against the callee's workflow_call inputs only for local
# calls. Rewrite the internal references to ./.github/workflows/... in a scratch repository and lint
# there: a misspelled or missing input also makes GitHub reject the whole run at start.
if command -v actionlint >/dev/null 2>&1; then
  LINT_DIR="$(mktemp -d)"
  git init -q "$LINT_DIR"
  mkdir -p "$LINT_DIR/.github/workflows"
  cp .github/workflows/*.yml "$LINT_DIR/.github/workflows/"
  for F in ${EXTRA_WORKFLOWS:-}; do cp "$F" "$LINT_DIR/.github/workflows/extra-$(basename "$F")"; done
  sed -i -E 's#surveyjs/azure-pipelines/(\.github/workflows/[^@ ]+)@[A-Za-z0-9._-]+#./\1#' \
    "$LINT_DIR"/.github/workflows/*.yml
  LINT="$(cd "$LINT_DIR" && actionlint -no-color 2>&1)"
  assert_eq "every internal call passes only the inputs its workflow declares" "" "$LINT"
  rm -rf "$LINT_DIR"
else
  printf '  skip  actionlint is not installed - inputs of internal calls are not checked\n'
fi

# SCR Update is a group of its own (library-scr-update.yml): library-react.yml only tests.
assert_eq "library-react.yml has no SCR Update job or input" "" \
  "$(grep -n '^  scr-update:\|^      scr-update:\|inputs\.scr-update' .github/workflows/library-react.yml)"
GUARD="$(grep -c "if: github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name == github.repository" \
  .github/workflows/library-scr-update.yml 2>/dev/null)"
assert_eq "SCR Update pushes only to a PR branch of this repository" 1 "${GUARD:-0}"

# Job names carry no area prefix: the group in the run's sidebar already names the area, so the
# check reads "Library / React / Markup", not "Library / React / Library React · Markup".
PREFIXED="$(grep -n '^    name: .*·' .github/workflows/*.yml)"
assert_eq "no job name repeats its area" "" "$PREFIXED"

# The Library and Creator groups call every workflow of their area.
for AREA in library creator; do
  for PART in core react angular vue js; do
    assert_contains "$AREA-test.yml calls $AREA-$PART.yml" \
      "$(cat ".github/workflows/$AREA-test.yml" 2>/dev/null)" "/.github/workflows/$AREA-$PART.yml@"
  done
done
# creator-core has no screenshot job, the other four take the switch.
BLOCKING="$(grep -c 'scr-blocking: ${{ inputs.scr-blocking }}' .github/workflows/creator-test.yml 2>/dev/null)"
assert_eq "creator-test.yml passes scr-blocking to the four screenshot workflows" 4 "${BLOCKING:-0}"

# Afterparty carries the single required check. The orchestrator is gone: the graph lives in
# survey-library's caller workflow, where its top-level jobs become the run's groups.
assert_contains "afterparty.yml runs the result action" \
  "$(cat .github/workflows/afterparty.yml 2>/dev/null)" "/.github/actions/result@"
assert_eq "the orchestrator library.yml is gone" "no" \
  "$([ -e .github/workflows/library.yml ] && echo yes || echo no)"
# result must report on every run, a failed or cancelled one included, whatever GitHub's implicit
# success() counts across the workflow_call boundary: a skipped required check counts as passed.
assert_contains "Afterparty's result job runs always()" \
  "$(sed -n '/^  result:/,/^  [a-z]/p' .github/workflows/afterparty.yml 2>/dev/null)" 'if: ${{ always() }}'

finish
