// Wraps the karma.conf.js of a package (KARMA_CONFIG) for `ng test --karma-config`: adds the JUnit
// reporter, which the package does not install, writing to JUNIT_FILE. The packages list their
// plugins, so Karma would not load the reporter by itself; basePath is pinned to the package's
// folder, since Karma resolves a relative one against the folder of this file.
const path = require("path");

module.exports = function (config) {
  const own = path.resolve(process.env.KARMA_CONFIG);
  require(own)(config);
  config.set({
    basePath: path.resolve(path.dirname(own), config.basePath || ""),
    plugins: [...(config.plugins || []), require("karma-junit-reporter")],
    reporters: [...(config.reporters || []), "junit"],
    junitReporter: { outputFile: path.resolve(process.env.JUNIT_FILE), useBrowserName: false }
  });
};
