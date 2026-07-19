import { analyzeCommits } from "../release/node_modules/@semantic-release/commit-analyzer/index.js";

const logger = { log() {} };
const cases = [
  ["fix: ordinary correction", "patch"],
  ["feat: ordinary feature", "minor"],
  ["fix!: persisted schema compatibility", "major"],
  ["feat!: persisted schema compatibility", "major"],
  ["fix: compatibility\n\nBREAKING CHANGE: store format advanced", "major"],
];

for (const [message, expected] of cases) {
  const actual = await analyzeCommits(
    { preset: "conventionalcommits" },
    { cwd: new URL("../release", import.meta.url).pathname, commits: [{ message, hash: "fixture" }], logger }
  );
  if (actual !== expected) {
    throw new Error(`Expected ${JSON.stringify(message)} to produce ${expected}; got ${actual}`);
  }
}

console.log(`${cases.length} semantic-release contract assertions passed`);
