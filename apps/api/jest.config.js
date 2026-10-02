module.exports = {
  // Each e2e spec boots its own mongodb-memory-server; two workers keeps a
  // laptop responsive. The commit gate runs related tests --runInBand.
  maxWorkers: 2,
  moduleFileExtensions: ["js", "json", "ts"],
  rootDir: "src",
  testRegex: ".*\\.spec\\.ts$",
  transform: {
    "^.+\\.(t|j)s$": "ts-jest",
  },
  collectCoverageFrom: ["**/*.(t|j)s"],
  coverageDirectory: "../coverage",
  testEnvironment: "node",
};
