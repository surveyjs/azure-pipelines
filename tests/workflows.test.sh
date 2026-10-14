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

# SCR Update is a job of library.yml: library-react.yml only tests.
assert_eq "library-react.yml has no SCR Update job or input" "" \
  "$(grep -n '^  scr-update:\|^      scr-update:\|inputs\.scr-update' .github/workflows/library-react.yml)"
assert_contains "SCR Update pushes only to a PR branch of this repository" \
  "$(sed -n '/^  scr-update:/,/^  [a-z]/p' .github/workflows/library.yml 2>/dev/null | grep '^    if:')" \
  "github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name == github.repository"

# The run's sidebar is one group, CI, with the leaf jobs in a flat list - the jobs of library.yml
# that call their workflows are left out, only the check name carries them. So every leaf job names
# its area and, in library-* and creator-*, its framework: "Creator · React · E2E (1/2)" in the
# sidebar, check "CI / Creator React / Creator · React · E2E (1/2)".
cap() { printf '%s%s' "$(printf '%s' "${1:0:1}" | tr '[:lower:]' '[:upper:]')" "${1:1}"; }
UNNAMED="$(for F in .github/workflows/{library,creator}-{core,react,angular,vue,js}.yml \
    .github/workflows/{analytics,pdf,theme-adapter-demos}-test.yml; do
  PART="$(basename "$F" .yml)"
  case "$PART" in
    analytics-test) PREFIX=Analytics ;;
    pdf-test) PREFIX=PDF ;;
    theme-adapter-demos-test) PREFIX=Demos ;;
    *)
      FW="${PART#*-}"
      case "$FW" in
        core) FW=Core ;;
        js) FW=JS ;;
        *) FW="$(cap "$FW")" ;;
      esac
      PREFIX="$(cap "${PART%%-*}") · $FW" ;;
  esac
  grep -n '^    name:' "$F" | grep -v "^[0-9]*:    name: \"\{0,1\}$PREFIX · " | sed "s|^|$F:|"
done)"
assert_eq "every leaf job names its area (and framework)" "" "$UNNAMED"

# library.yml calls every test workflow.
for W in library-{core,react,angular,vue,js} creator-{core,react,angular,vue,js} \
    analytics-test pdf-test theme-adapter-demos-test; do
  assert_contains "library.yml calls $W.yml" \
    "$(cat .github/workflows/library.yml 2>/dev/null)" "/.github/workflows/$W.yml@"
done

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

# The whole graph is library.yml, which survey-library's only job, CI, calls: the group workflows
# are gone.
for F in library-test creator-test afterparty library-scr-update; do
  assert_eq "the group workflow $F.yml is gone" "no" \
    "$([ -e ".github/workflows/$F.yml" ] && echo yes || echo no)"
done

# job <id> - the job of library.yml, up to the next one.
job() { sed -n "/^  $1:/,/^  [a-z]/p" .github/workflows/library.yml 2>/dev/null; }
# needs <id> - the needs of a job of library.yml, one a line, sorted; a list in either YAML form.
needs() {
  job "$1" | awk '
    /^    needs:/ { on = 1; sub(/^    needs:[[:space:]]*/, ""); gsub(/[][,]/, " ")
      n = split($0, a, " "); for (i = 1; i <= n; i++) print a[i]; next }
    on && /^      - / { sub(/^      - /, ""); print; next }
    { on = 0 }' | LC_ALL=C sort
}

# result is the single required check, "CI / result". It must report on every run, a failed or
# cancelled one included: a skipped required check counts as passed. It checks every job before it.
assert_contains "library.yml's result job runs the result action" "$(job result)" "/.github/actions/result@"
assert_contains "library.yml's result job runs always()" "$(job result | grep '^    if:')" 'always()'
assert_eq "result needs every job before it" \
  "$(awk '/^jobs:/ { on = 1; next } on && /^  [a-z0-9_-]+:[[:space:]]*$/ { sub(/^  /, ""); sub(/:.*/, ""); print }' \
    .github/workflows/library.yml 2>/dev/null | grep -vxE 'result|fails|test-results' | LC_ALL=C sort)" \
  "$(needs result)"
# The run cards: fails waits for the same jobs - the reports of all the tests - and test-results
# comes last, as it merges the reports into one artifact and deletes them.
assert_contains "library.yml's fails job makes the fails card" "$(job fails)" "card: fails"
assert_contains "library.yml's test-results job makes the all card" "$(job test-results)" "card: all"
for J in fails test-results; do
  assert_contains "library.yml's $J job runs run-report" "$(job "$J")" "/.github/actions/run-report@"
  assert_contains "library.yml's $J job runs unless the run was cancelled" \
    "$(job "$J" | grep '^    if:')" '!cancelled()'
done
assert_eq "fails waits for the jobs result checks" "$(needs result)" "$(needs fails)"
assert_eq "test-results follows fails" "fails" "$(needs test-results)"

# The run cards (run-report) group the reports by title, the shard suffix left out, and order them
# by the product the title starts with; a report goes up as JUnit_<artifact-name>, overwriting one
# of the same name.
assert_eq "every test report title starts with its product" "" \
  "$(grep -hE '^ +title: ' .github/workflows/*.yml | grep -vE '^ +title: (Library|Creator|Analytics|PDF|Theme Adapter Demos) ')"
assert_eq "every test report has an artifact name of its own" "" \
  "$(grep -hE '^ +artifact-name: ' .github/workflows/*.yml | sed -E 's/^ +//' | sort | uniq -d)"

finish
