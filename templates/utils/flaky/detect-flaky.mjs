#!/usr/bin/env node
// Parse the Playwright JSON report for tests the runner marked status === "flaky"
// (failed an attempt, passed on retry — the build stays green) and print them.
//
// Invoked by templates/utils/flaky/detect.yml. Pure stdlib, no deps. Never throws to
// the caller: any problem prints a note and exits 0, so detection stays non-blocking
// (the YAML step is condition: always() / continueOnError: true).
//
// Usage:  node detect-flaky.mjs <project> [resultsPath]
//   <project>      Playwright project to filter on ("e2e" / "vrt"); "" = all projects.
//   [resultsPath]  report path, relative to cwd. Default: test-results/results.json.

import { readFileSync } from "node:fs";

const project = process.argv[2] ?? process.env.PROJECT ?? "";
const resultsPath = process.argv[3] ?? "test-results/results.json";

let data;
try {
  data = JSON.parse(readFileSync(resultsPath, "utf8"));
} catch (e) {
  console.error(`Could not parse ${resultsPath}: ${e.message}`);
  process.exit(0);
}

// Keep only the "<e2e|screenshots>/….spec.ts" tail of a spec file path.
const norm = (f) => {
  const m = (f || "").match(/(?:e2e|screenshots)\/.*\.spec\.ts$/);
  return m ? m[0] : null;
};

const flaky = new Set();
(function walk(suite) {
  for (const spec of suite.specs || []) {
    for (const t of spec.tests || []) {
      if (t.status !== "flaky") continue;
      if (project && t.projectName !== project) continue;
      const file = norm(spec.file || suite.file);
      if (!file) continue;
      const title = (spec.title || "").replace(/;/g, " ").replace(/::/g, ": ").trim();
      flaky.add(`${file}::${title}::${t.projectName}`);
    }
  }
  for (const child of suite.suites || []) walk(child);
})(data);

if (flaky.size === 0) {
  console.log(`No flaky tests detected for project '${project}'.`);
  process.exit(0);
}
console.log(`Detected ${flaky.size} flaky test(s) to fix for project '${project}':`);
for (const f of flaky) console.log(`  ${f}`);
