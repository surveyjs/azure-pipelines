# Tests of .github/actions/junit-reporters/karma.junit.conf.js - the Karma config wrapping a
# package's own: it is called with a stand-in Karma config object, next to a stub
# karma-junit-reporter, as `ng test --karma-config` would after the action installed the reporter.
source tests/lib.sh

if ! command -v node >/dev/null 2>&1; then
  echo "  skip  node is not installed"
  exit 0
fi

TMP="$(mktemp -d)"
cp .github/actions/junit-reporters/karma.junit.conf.js "$TMP/"
mkdir -p "$TMP/node_modules/karma-junit-reporter" "$TMP/pkg"
echo 'module.exports = { "reporter:junit": ["type", function junit() {}] };' \
  > "$TMP/node_modules/karma-junit-reporter/index.js"
echo 'module.exports = function (config) { config.set({ basePath: "./", plugins: ["own"], reporters: ["progress", "kjhtml"] }); };' \
  > "$TMP/pkg/karma.conf.js"

OUT="$(cd "$TMP" && KARMA_CONFIG=pkg/karma.conf.js JUNIT_FILE=out/junit.xml node -e '
  const path = require("path");
  const config = { set(options) { Object.assign(this, options); } };
  require("./karma.junit.conf.js")(config);
  console.log([
    config.basePath === path.resolve("pkg"),
    JSON.stringify(config.plugins.map((p) => typeof p === "string" ? p : Object.keys(p)[0])),
    JSON.stringify(config.reporters),
    config.junitReporter.outputFile === path.resolve("out/junit.xml"),
    config.junitReporter.useBrowserName
  ].join(" "));' 2>&1)"

assert_eq "the package config is applied and the JUnit reporter added to its plugins and reporters" \
  'true ["own","reporter:junit"] ["progress","kjhtml","junit"] true false' "$OUT"

rm -rf "$TMP"
finish
