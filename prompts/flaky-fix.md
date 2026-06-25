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
  * The ORIGINAL-run flake evidence (trace + results.json from the run that flaked) —
    its absolute directory path is given at the END of this prompt. Inspect it FIRST (an
    intermittent flake may not reproduce locally, so this is often the only evidence of
    the real failure). NOTE: it lives OUTSIDE the repo on purpose, so Playwright — which
    clears test-results/ on every run — can't touch it.

To RUN a test you MUST run Playwright from the framework package so its web server starts:
    cd packages/survey-react-ui && npx playwright test e2e/<file>.spec.ts --project e2e -g "<title>" --retries=0 --repeat-each=5
  (visual tests: --project vrt and screenshots/<file>.spec.ts). The path is a substring filter.
  ALWAYS pass -g "<title>" with the target's <title> (3rd field is the <project>): each spec file is
  parametrized across frameworks (angular/react/vue/...), but only react is built/served here — running
  the file unscoped fails the other frameworks with unrelated errors. Scope to the one target variant.
  --retries=0 --repeat-each exposes flakiness that the default retries=4 would hide.

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
