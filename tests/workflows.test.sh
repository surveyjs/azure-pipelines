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

# The run's sidebar shows only the group (Library, Creator) and the leaf job's name - not the
# React / Angular / ... level between them, which only the check name carries. So every leaf job of
# library-* and creator-* names its framework: "React · E2E (1/2)" in the sidebar, check
# "Creator / React / React · E2E (1/2)".
UNNAMED="$(for F in .github/workflows/{library,creator}-{core,react,angular,vue,js}.yml; do
  PART="$(basename "$F" .yml)"; PART="${PART#*-}"
  case "$PART" in
    core) FW=Core ;;
    js) FW=JS ;;
    *) FW="$(printf '%s' "${PART:0:1}" | tr '[:lower:]' '[:upper:]')${PART:1}" ;;
  esac
  grep -n '^    name:' "$F" | grep -v "^[0-9]*:    name: \"\{0,1\}$FW · " | sed "s|^|$F:|"
done)"
assert_eq "every leaf job of library-* and creator-* names its framework" "" "$UNNAMED"

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

# The long suites run in Playwright / Vitest shards, one job per shard. A shard job must not cancel
# its sibling on failure, must name its shard in the check, and must upload under a name of its own:
# publish-test-results overwrites an artifact of the same name.
SHARDS="$(awk '
  function flush() {
    if (job != "" && body ~ /--shard=/) {
      print "sharded " job
      if (body !~ /fail-fast: false/) print "issue " job ": no fail-fast: false"
      if (name !~ /matrix\.shard/) print "issue " job ": the name does not show matrix.shard"
      n = split(body, lines, "\n")
      for (i = 1; i <= n; i++)
        if (lines[i] ~ /artifact-name:/ && lines[i] !~ /matrix\.shard/) print "issue " job ": " lines[i]
      # A literal count must agree everywhere: --shard=k/2 next to [1, 2, 3] never runs a third of
      # the tests (or fails with shard 3/2). Jobs that take the count from matrix.shards agree by
      # construction.
      if (body !~ /matrix\.shards/) {
        listed = 0
        if (match(body, /shard: \[[0-9, ]*\]/)) { list = substr(body, RSTART, RLENGTH); listed = gsub(/[0-9]+/, "", list) }
        flag = match(body, /--shard=[$][{][{] matrix[.]shard [}][}][/][0-9]+/) ? substr(body, RSTART, RLENGTH) : ""
        sub(/.*\//, "", flag)
        named = match(name, /\/[0-9]+\)/) ? substr(name, RSTART + 1, RLENGTH - 2) : ""
        if (listed != flag || listed != named)
          print "issue " job ": " listed " shards in the matrix, /" flag " in --shard, /" named " in the name"
      }
    }
    job = ""; body = ""; name = ""
  }
  FNR == 1 { flush(); injobs = 0; file = FILENAME; sub(/.*\//, "", file) }
  /^jobs:/ { injobs = 1; next }
  injobs && /^  [a-z0-9_-]+:[[:space:]]*$/ { flush(); job = file ":" substr($1, 1, length($1) - 1); next }
  job != "" && /^    name:/ { name = $0 }
  job != "" { body = body "\n" $0 }
  END { flush() }
' .github/workflows/*.yml)"
assert_eq "the long suites are sharded" \
  "$(printf 'sharded %s\n' creator-angular.yml:e2e creator-angular.yml:scr creator-core.yml:unit \
    creator-js.yml:e2e creator-js.yml:scr creator-react.yml:e2e creator-react.yml:scr \
    creator-vue.yml:e2e creator-vue.yml:scr theme-adapter-demos-test.yml:scr)" \
  "$(printf '%s\n' "$SHARDS" | grep '^sharded ' | LC_ALL=C sort)"
assert_eq "every shard job keeps its sibling, names its shard and uploads under its own name" "" \
  "$(printf '%s\n' "$SHARDS" | grep '^issue ')"
# vitest run already runs the presets project; npm run test:presets ran it a second time.
assert_eq "creator-core runs the presets once, inside npm run test" "" \
  "$(grep -n 'test:presets' .github/workflows/creator-core.yml)"

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
