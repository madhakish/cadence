import { analyzeCommits } from "../release/node_modules/@semantic-release/commit-analyzer/index.js";
import { generateNotes } from "../release/node_modules/@semantic-release/release-notes-generator/index.js";
import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";

const logger = { log() {}, error() {} };
const cwd = new URL("../release", import.meta.url).pathname;
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
    { cwd, commits: [{ message, hash: "fixture" }], logger }
  );
  if (actual !== expected) {
    throw new Error(`Expected ${JSON.stringify(message)} to produce ${expected}; got ${actual}`);
  }
}

// The version bump and the release notes come from two different plugins
// reading the same preset. Asserting only the bump let v2.0.0 through v3.2.0
// ship with a correct version and a body containing nothing but the compare
// header: the preset advertised writer options under a key the bundled
// conventional-changelog-writer does not read, so every commit group rendered
// empty and no job failed. Notes are a release artefact — assert the content.
const notes = async (message, hash = "fixture") =>
  generateNotes(
    { preset: "conventionalcommits" },
    {
      cwd,
      options: { repositoryUrl: "https://github.com/madhakish/cadence" },
      lastRelease: { version: "1.0.0", gitTag: "v1.0.0" },
      nextRelease: { version: "1.1.0", gitTag: "v1.1.0", type: "minor" },
      commits: [{ message, hash }],
      logger,
    }
  );

const featureNotes = await notes("feat(anatomy): give every exercise a profile", "abcdef1234");
assert.match(featureNotes, /### Features/, "a feat commit must render a Features section");
assert.match(
  featureNotes,
  /give every exercise a profile/,
  "the release body must contain the commit subject, not just the compare header"
);
assert.match(featureNotes, /\*\*anatomy:\*\*/, "a scoped commit must render its scope");
assert.match(featureNotes, /abcdef1/, "each entry must link back to its commit");

const fixNotes = await notes("fix: keep extra work out of the main line");
assert.match(fixNotes, /### Bug Fixes/, "a fix commit must render a Bug Fixes section");

const breakingNotes = await notes("feat!: advance the persisted store format");
assert.match(
  breakingNotes,
  /BREAKING CHANGE/i,
  "a breaking change must be called out in the body, not only in the version"
);

// A body of only the compare header is the exact shape of the silent failure.
for (const [label, body] of [
  ["feature", featureNotes],
  ["fix", fixNotes],
  ["breaking", breakingNotes],
]) {
  assert.ok(
    body.trim().split("\n").filter(Boolean).length > 1,
    `${label} notes collapsed to a bare header — the preset and the writer disagree on writerOpts`
  );
}

const workflow = await readFile(new URL("../workflows/ci.yml", import.meta.url), "utf8");
const workflowConcurrency = workflow.match(/\nconcurrency:\n(?<block>[\s\S]*?)\n\n# Default every job/)?.groups?.block;
const releaseJob = workflow.match(/\n  release:\n(?<job>[\s\S]*?)\n  # GitHub release binaries/)?.groups?.job;
const releaseAssetsJob = workflow.match(/\n  release-assets:\n(?<job>[\s\S]*?)\n  testflight:\n/)?.groups?.job;
const testflightJob = workflow.match(/\n  testflight:\n(?<job>[\s\S]*?)\n  deploy-web:\n/)?.groups?.job;
const releaseConfig = JSON.parse(
  await readFile(new URL("../../.releaserc.json", import.meta.url), "utf8")
);
const githubPlugin = releaseConfig.plugins.find(([name]) => name === "@semantic-release/github");

assert.ok(workflowConcurrency, "Expected ci.yml to define workflow concurrency");
assert.match(workflowConcurrency, /'cadence-production-release'/);
assert.match(workflowConcurrency, /format\('ci-pr-\{0\}-\{1\}'/);
assert.match(workflowConcurrency, /queue: max/);
assert.doesNotMatch(workflowConcurrency, /cancel-in-progress/);
assert.ok(releaseJob, "Expected ci.yml to define release before release-assets");
assert.match(releaseJob, /concurrency:\n\s+group: semantic-release\n\s+queue: max/);
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
assert.match(releaseAssetsJob, /GH_REPO: \$\{\{ github\.repository \}\}/);
assert.match(releaseAssetsJob, /gh release upload/);
assert.ok(testflightJob, "Expected ci.yml to define testflight before deploy-web");
assert.doesNotMatch(testflightJob, /TESTFLIGHT_ENABLED/);
assert.doesNotMatch(testflightJob, /needs\.release\.result == 'success'/);
assert.match(testflightJob, /if: >-\n\s+always\(\) &&\n\s+!cancelled\(\) &&/);
assert.match(testflightJob, /needs\.release\.outputs\.published == 'true'/);
assert.doesNotMatch(testflightJob, /needs:.*release-assets/);
assert.match(testflightJob, /fetch-depth: 0\n\s+fetch-tags: true/);

console.log(`${cases.length + 43} semantic-release contract assertions passed`);
