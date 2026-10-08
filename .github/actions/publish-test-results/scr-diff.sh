#!/usr/bin/env bash
# Usage (env): RESULTS_JSON - Playwright JSON report; OUT_FILE - the page to write; TITLE - its
# heading; MAX_BYTES - PNG bytes to embed at most (default 50 MB); GITHUB_SERVER_URL,
# GITHUB_REPOSITORY, GITHUB_RUN_ID - the link back to the run.
# Writes one self-contained HTML page with the expected / actual / diff images of every screenshot
# mismatch: the last attempt of a failed test, the last failed attempt of a flaky one. A single file
# with the images inlined is what a non-zipped artifact can show in the browser. The page has no
# script - the view modes switch with CSS only. Sets the count, failed and flaky outputs; with no
# report or no mismatch it writes no page, sets count=0 and passes: the test results decide the job.
set -uo pipefail

MAX_BYTES="${MAX_BYTES:-52428800}"

nothing() {
  printf 'count=0\nfailed=0\nflaky=0\n' >> "$GITHUB_OUTPUT"
  exit 0
}

if [ ! -f "$RESULTS_JSON" ]; then
  echo "No Playwright JSON report at $RESULTS_JSON - no diff page."
  nothing
fi

# One object per mismatched screenshot: {base, name, expected?, actual?, diff?, status, file, line,
# path (describe titles + test title), project, retry, note}. The attachments of one
# toHaveScreenshot are <base>-expected.png, <base>-actual.png and <base>-diff.png; a missing
# baseline has no diff. The note is the line of the matching error that says what differs.
EXTRACT="$(cat <<'JQ'
def clean: gsub("\u001b\\[[0-9;]*m"; "");
def specs($path):
  (.specs[]? | {path: ($path + [.title]), file, line, tests}),
  (.suites[]? as $s | $s | specs($path + [$s.title]));
def note($msgs; $name):
  ([$msgs[] | select(contains("Snapshot: " + $name))] + [$msgs[] | select(contains($name))] | first // "")
  | [splits("\n") | select(test("pixels \\(ratio|Expected an image|snapshot doesn't exist"))] | first // ""
  | sub("^\\s*(Error: )?"; "");
[ .suites[]? | specs([]) as $spec | $spec.tests[]
  | select(.status == "unexpected" or .status == "flaky") as $test
  | (if .status == "flaky" then [.results[] | select(.status != "passed" and .status != "skipped")] | last
     else .results | last end) as $r
  | select($r != null)
  | [$r.errors[]?.message // empty | clean] as $msgs
  | reduce ($r.attachments[]? | select(.contentType == "image/png") | .path as $p
            | .name | capture("^(?<base>.+)-(?<kind>expected|actual|diff)\\.png$") | .path = $p) as $a
      ([]; if any(.[]; .base == $a.base)
           then map(if .base == $a.base then .[$a.kind] = $a.path else . end)
           else . + [{base: $a.base, ($a.kind): $a.path}] end)
  | .[]
  | . + {status: $test.status, file: $spec.file, line: $spec.line, path: $spec.path,
         project: ($test.projectName // ""), retry: $r.retry, name: (.base + ".png")}
  | .note = note($msgs; .name)
]
JQ
)"

if ! SHOTS="$(jq -c "$EXTRACT" "$RESULTS_JSON" 2>&1)"; then
  echo "::warning::Could not read the Playwright JSON report $RESULTS_JSON - no diff page: $SHOTS"
  nothing
fi
COUNT="$(jq -r 'length' <<< "$SHOTS")"
FAILED="$(jq -r 'map(select(.status == "unexpected")) | length' <<< "$SHOTS")"
FLAKY="$(jq -r 'map(select(.status == "flaky")) | length' <<< "$SHOTS")"
if [ "$COUNT" = 0 ]; then
  echo "No screenshot mismatches in $RESULTS_JSON - no diff page."
  nothing
fi

RUN_URL=""
if [ -n "${GITHUB_RUN_ID:-}" ]; then
  RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/$GITHUB_RUN_ID"
fi

# Body lines: "H <html>" is written as it is, "I <escaped attachment name><TAB><path>" becomes an
# embedded image. Every text from the report goes through @html.
RENDER="$(cat <<'JQ'
def h: tostring | @html;
def fig($cls; $caption; $kind):
  if .[$kind] then
    "H <figure class=\"\($cls)\"><figcaption>\($caption)</figcaption>\(if $cls == "a" then "<div class=\"clip\">" else "" end)",
    "I \(.base + "-" + $kind + ".png" | h)\t\(.[$kind])",
    "H \(if $cls == "a" then "</div>" else "" end)</figure>"
  else empty end;
def heading:
  "\(.file | sub("^(\\.\\./)+"; "") | h):\(.line) › \(.path | map(h) | join(" › "))"
  + (if .project != "" then " <span class=\"tag\">[\(.project | h)]</span>" else "" end)
  + (if .retry > 0 then " <span class=\"tag\">retry #\(.retry)</span>" else "" end);
def shot($i):
  "H <section class=\"shot\" id=\"s\($i)\">",
  "H <h2>\(heading)</h2>",
  "H <h3>\(.name | h)</h3>",
  (if .note != "" then "H <p class=\"note\">\(.note | h)</p>" else empty end),
  (if .expected and .actual and .diff then
    "H <input type=\"radio\" name=\"m\($i)\" id=\"m\($i)s\" class=\"side\" checked><label for=\"m\($i)s\">Side by side</label>",
    "H <input type=\"radio\" name=\"m\($i)\" id=\"m\($i)d\" class=\"only-diff\"><label for=\"m\($i)d\">Diff</label>",
    "H <input type=\"radio\" name=\"m\($i)\" id=\"m\($i)o\" class=\"slide\"><label for=\"m\($i)o\">Slider</label>"
  else empty end),
  "H <div class=\"view\">",
  fig("e"; "Expected"; "expected"), fig("a"; "Actual"; "actual"), fig("d"; "Diff"; "diff"),
  "H </div>",
  "H </section>";
def plural($n; $word): "\($n) \($word)\(if $n == 1 then "" else "es" end)";
to_entries as $all
| [$all[] | select(.value.status == "unexpected")] as $failed
| [$all[] | select(.value.status == "flaky")] as $flaky
| "H <header>",
  "H <h1>\($title | h)</h1>",
  "H <p>\(plural($failed | length; "screenshot mismatch")) in failed tests"
    + (if ($flaky | length) > 0 then ", \($flaky | length) in flaky tests" else "" end)
    + (if $run != "" then " · <a href=\"\($run | h)\">workflow run</a>" else "" end) + "</p>",
  "H </header>",
  (if ($failed | length) > 0 then
    "H <nav><ol>",
    ($failed[] | "H <li><a href=\"#s\(.key)\">\(.value.path | map(h) | join(" › ")) — \(.value.name | h)</a></li>"),
    "H </ol></nav>"
  else empty end),
  ($failed[] | .key as $i | .value | shot($i)),
  (if ($flaky | length) > 0 then
    "H <details>",
    "H <summary>Flaky tests - passed on a retry (\($flaky | length))</summary>",
    ($flaky[] | .key as $i | .value | shot($i)),
    "H </details>"
  else empty end)
JQ
)"

BASE_DIR="$(dirname "$RESULTS_JSON")"
EMBEDDED=0
image() { # <escaped attachment name> <path>
  local NAME="$1" FILE="$2" SIZE
  case "$FILE" in /*) ;; *) FILE="$BASE_DIR/$FILE" ;; esac
  if [ ! -f "$FILE" ]; then
    printf '<p class="skip">not found: %s</p>\n' "$NAME"
    return
  fi
  SIZE="$(wc -c < "$FILE" | tr -d ' ')"
  if [ $((EMBEDDED + SIZE)) -gt "$MAX_BYTES" ]; then
    printf '<p class="skip">%s: not embedded - the page reached its size limit; see the Playwright report artifact</p>\n' "$NAME"
    return
  fi
  EMBEDDED=$((EMBEDDED + SIZE))
  printf '<img alt="%s" src="data:image/png;base64,' "$NAME"
  base64 -w0 "$FILE"
  printf '">\n'
}

mkdir -p "$(dirname "$OUT_FILE")"
{
  printf '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
  printf '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
  printf '<title>%s - screenshot diffs</title>\n' "$(jq -rn --arg t "$TITLE" '$t | @html')"
  cat <<'CSS'
<style>
:root { color-scheme: light dark; --bg: #fff; --fg: #1f2328; --muted: #59636e; --line: #d1d9e0;
  --card: #f6f8fa; --accent: #0969da; --bad: #cf222e; }
@media (prefers-color-scheme: dark) {
  :root { --bg: #0d1117; --fg: #e6edf3; --muted: #9198a1; --line: #3d444d; --card: #151b23;
    --accent: #4493f8; --bad: #f85149; }
}
body { margin: 0; padding: 16px 24px 48px; background: var(--bg); color: var(--fg);
  font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; }
a { color: var(--accent); }
h1 { font-size: 20px; margin: 0 0 4px; }
header p { margin: 0 0 16px; color: var(--muted); }
nav ol { margin: 0 0 24px; padding-left: 24px; }
details > summary { cursor: pointer; font-weight: 600; margin: 24px 0 12px; }
.shot { border: 1px solid var(--line); border-radius: 6px; padding: 12px 16px; margin: 0 0 16px; background: var(--card); }
.shot h2 { font-size: 14px; margin: 0; overflow-wrap: anywhere; }
.shot h3 { font: 13px/1.5 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; margin: 2px 0 8px; }
.tag, .note { color: var(--muted); font-weight: 400; }
.note { margin: 0 0 8px; }
.skip { margin: 0; color: var(--bad); }
input[type=radio] { position: absolute; opacity: 0; pointer-events: none; }
label { display: inline-block; padding: 2px 10px; margin: 0 4px 8px 0; border: 1px solid var(--line);
  border-radius: 6px; cursor: pointer; user-select: none; }
input:checked + label { background: var(--accent); border-color: var(--accent); color: #fff; }
input:focus-visible + label { outline: 2px solid var(--accent); outline-offset: 2px; }
.view { display: flex; gap: 12px; align-items: flex-start; overflow-x: auto; }
figure { margin: 0; flex: 1 1 0; min-width: 0; }
figcaption { font-size: 12px; color: var(--muted); margin-bottom: 4px; }
img { display: block; max-width: 100%; height: auto; border: 1px solid var(--line);
  background: repeating-conic-gradient(#8883 0 25%, transparent 0 50%) 0 0 / 16px 16px; }
.only-diff:checked ~ .view .e, .only-diff:checked ~ .view .a { display: none; }
.slide:checked ~ .view { display: grid; grid-template-columns: max-content; }
.slide:checked ~ .view .d { display: none; }
.slide:checked ~ .view figure { grid-area: 1 / 1; min-width: max-content; }
.slide:checked ~ .view .a figcaption { visibility: hidden; }
.slide:checked ~ .view .e figcaption::after { content: " on the right, actual on the left - drag the corner of the split"; }
.slide:checked ~ .view .clip { resize: horizontal; overflow: hidden; width: 50%; min-width: 8px; max-width: 100%;
  border-right: 2px solid var(--accent); }
.slide:checked ~ .view img { max-width: none; }
</style>
CSS
  printf '</head>\n<body>\n'
  while IFS= read -r L; do
    case "$L" in
      "I "*) L="${L#I }"; image "${L%%$'\t'*}" "${L#*$'\t'}" ;;
      *) printf '%s\n' "${L#H }" ;;
    esac
  done < <(jq -r --arg title "$TITLE" --arg run "$RUN_URL" "$RENDER" <<< "$SHOTS")
  printf '</body>\n</html>\n'
} > "$OUT_FILE"

printf 'count=%s\nfailed=%s\nflaky=%s\n' "$COUNT" "$FAILED" "$FLAKY" >> "$GITHUB_OUTPUT"
echo "Screenshot diff page: $OUT_FILE - $FAILED mismatch(es) in failed tests, $FLAKY in flaky tests, $EMBEDDED bytes of images embedded."
