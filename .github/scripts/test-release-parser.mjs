import { analyzeCommits } from "../release/node_modules/@semantic-release/commit-analyzer/index.js";
import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";

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

const workflow = await readFile(new URL("../workflows/ci.yml", import.meta.url), "utf8");
const releaseJob = workflow.match(/\n  release:\n(?<job>[\s\S]*?)\n  testflight:\n/)?.groups?.job;

assert.ok(releaseJob, "Expected ci.yml to define release before testflight");
assert.match(releaseJob, /if: >-\n\s+always\(\) &&/);
assert.match(releaseJob, /needs\.core-tests\.result == 'success'/);
assert.match(releaseJob, /needs\.web-tests\.result == 'success'/);
assert.match(releaseJob, /needs\.app-build\.result == 'success'/);
assert.match(releaseJob, /github\.ref == 'refs\/heads\/main'/);

console.log(`${cases.length + 6} semantic-release contract assertions passed`);
