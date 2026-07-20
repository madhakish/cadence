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
const releaseJob = workflow.match(/\n  release:\n(?<job>[\s\S]*?)\n  # GitHub release binaries/)?.groups?.job;
const releaseAssetsJob = workflow.match(/\n  release-assets:\n(?<job>[\s\S]*?)\n  testflight:\n/)?.groups?.job;
const testflightJob = workflow.match(/\n  testflight:\n(?<job>[\s\S]*?)\n  deploy-web:\n/)?.groups?.job;
const releaseConfig = JSON.parse(
  await readFile(new URL("../../.releaserc.json", import.meta.url), "utf8")
);
const githubPlugin = releaseConfig.plugins.find(([name]) => name === "@semantic-release/github");

assert.ok(releaseJob, "Expected ci.yml to define release before release-assets");
assert.match(releaseJob, /if: >-\n\s+always\(\) &&/);
assert.match(releaseJob, /needs\.core-tests\.result == 'success'/);
assert.match(releaseJob, /needs\.web-tests\.result == 'success'/);
assert.match(releaseJob, /needs\.app-build\.result == 'success'/);
assert.match(releaseJob, /github\.ref == 'refs\/heads\/main'/);
assert.match(releaseJob, /fetch-depth: 0\n\s+fetch-tags: true/);
assert.match(releaseJob, /id: semantic-release-command\n\s+continue-on-error: true/);
assert.match(releaseJob, /id: release-state\n\s+if: always\(\)/);
assert.match(releaseJob, /SEMANTIC_RELEASE_OUTCOME: \$\{\{ steps\.semantic-release-command\.outcome \}\}/);
assert.match(releaseJob, /bash \.github\/scripts\/reconcile-release-state\.sh/);
assert.match(releaseJob, /published: \$\{\{ steps\.release-state\.outputs\.published \}\}/);
assert.equal(
  releaseConfig.plugins.some(([name]) => name === "@semantic-release/exec"),
  false,
  "Release side effects must not run inside semantic-release's critical path"
);
assert.equal(githubPlugin?.[1]?.assets, undefined, "GitHub asset uploads must not gate release creation");
assert.ok(releaseAssetsJob, "Expected a separate GitHub release-assets job");
assert.match(releaseAssetsJob, /if: >-\n\s+always\(\) &&\n\s+!cancelled\(\) &&/);
assert.match(releaseAssetsJob, /needs\.release\.outputs\.published == 'true'/);
assert.match(releaseAssetsJob, /for attempt in 1 2 3 4 5/);
assert.match(releaseAssetsJob, /gh release upload/);
assert.ok(testflightJob, "Expected ci.yml to define testflight before deploy-web");
assert.doesNotMatch(testflightJob, /TESTFLIGHT_ENABLED/);
assert.doesNotMatch(testflightJob, /needs\.release\.result == 'success'/);
assert.match(testflightJob, /if: >-\n\s+always\(\) &&\n\s+!cancelled\(\) &&/);
assert.match(testflightJob, /needs\.release\.outputs\.published == 'true'/);
assert.doesNotMatch(testflightJob, /needs:.*release-assets/);
assert.match(testflightJob, /fetch-depth: 0\n\s+fetch-tags: true/);

console.log(`${cases.length + 26} semantic-release contract assertions passed`);
