You are stabilizing FLAKY Playwright tests in the SurveyJS "survey-library" repo.
A flaky test fails on some attempts but passes on retry — the build is green, but the
test is unreliable. Make it reliably pass WITHOUT hiding a real product bug.

Your working directory is the repo ROOT. Layout:
  * ./CLAUDE.md           — read this first (architecture & test commands).
  * ./e2e/                — e2e specs (*.spec.ts) and helpers (*.ts). You MAY edit these.
  * ./screenshots/        — visual (vrt) specs (*.spec.ts). You MAY edit these.
  * ./packages/*/src/     — PRODUCT code. NEVER edit.
  * ./**/*-snapshots/*.png — baseline screenshots. NEVER edit or regenerate.
  * ./packages/survey-react-ui/test-results/ — failure evidence (junit, results.json, traces)
    from the reproduce run.
  * The pipeline's Reproduce step has ALREADY reproduced this flake here (the leg only reaches
    you when it did), so packages/survey-react-ui/test-results/ holds FRESH failure evidence from
    that run — start there.
  * The ORIGINAL-run flake evidence (trace + results.json from the run that flaked) — the
    END of this prompt lists the exact absolute file paths (they may sit in per-job
    subfolders). Read those files too with the Read tool for additional context on the real
    failure. If that list is empty, the original artifacts didn't download — rely on
    packages/survey-react-ui/test-results/ from the reproduce run. NOTE: this evidence
    lives OUTSIDE the repo on purpose, so Playwright — which clears test-results/ on every
    run — can't touch it; pass the absolute paths to Read (relative globs won't find it).

To RUN the target test you MUST run Playwright from the framework package so its web server starts.
  The END of this prompt gives the EXACT ready-to-run command for this target ("To RE-RUN this exact
  test…") — use it VERBATIM. It already scopes to the one framework variant (only react is built/served
  here; running the file unscoped fails angular/vue with unrelated errors) and uses --retries=0
  --repeat-each to expose flakiness that the default retries=4 would hide.
  If you ever build the command yourself, note that -g is a JS REGEX matched against the SPACE-joined
  full title — the " › " you see in <title> is a reporter glyph, NOT part of the real title. Replace
  each " › " with ".*" and escape regex metacharacters ( ) [ ] $ . * + ? ^ { } | — e.g.
  -g "react autoNextPage.*check auto next page with keyboard". A literal "›" in -g matches nothing
  ("No tests found"). (Visual tests: --project vrt and screenshots/<file>.spec.ts.)

POLICY (HYBRID) — for each target test classify the root cause:
  * TEST FLAKINESS — timing/races (missing awaits, fixed waitForTimeout, animations),
    brittle selectors, order/focus/hover dependence, unmasked dynamic regions in
    screenshots (carets, scrollbars, timestamps). FIX the test code.
  * REAL PRODUCT BUG — assertion reflecting changed/incorrect product behavior, a
    consistent (non-intermittent) failure, or an error thrown from product code.
    DO NOT change anything; just describe it in your final summary.

WHEN FIXING (test flakiness only): prefer web-first assertions over fixed timeouts,
use stable selectors, disable animations, and for vrt add masks / set viewport / await
stability — do NOT regenerate the baseline image. Re-run the affected test (command above)
until it passes reliably.

HARD CONSTRAINTS (a violation discards ALL your changes downstream):
  * Edit ONLY files under  e2e/**  and  screenshots/**/*.spec.ts.
  * NEVER edit packages/**/src/** (product code).
  * NEVER edit or regenerate baseline snapshots (*-snapshots/**/*.png).
  * NEVER weaken comparison tolerances (threshold / maxDiffPixels / maxDiffPixelRatio)
    and NEVER add test.skip / test.fixme just to make a test pass — that hides bugs.
  * Do NOT git add / commit / push — the pipeline handles version control.

FINAL OUTPUT: a concise summary for a PR body — per target test, flakiness (what you
changed) or suspected product bug (why), plus the list of files you changed.
