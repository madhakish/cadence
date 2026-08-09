#!/usr/bin/env node

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { planRelease } from "./plan-release.mjs";

const repo = mkdtempSync(join(tmpdir(), "cadence-release-plan-"));
const git = (...args) => execFileSync("git", args, { cwd: repo, encoding: "utf8" }).trim();
let commits = 0;

const commit = (message) => {
  commits += 1;
  writeFileSync(join(repo, "fixture"), `${commits}\n`);
  git("add", "fixture");
  git("commit", "-q", "-m", message);
  return git("rev-parse", "HEAD");
};

try {
  git("init", "-q");
  git("config", "user.name", "Cadence CI");
  git("config", "user.email", "ci@example.invalid");

  let head = commit("feat: initial release");
  let plan = await planRelease({ cwd: repo, sha: head });
  assert.deepEqual(
    { simulator: plan.simulatorBuildRequired, store: plan.storeBuildRequired, source: plan.artifactSource, type: plan.type, version: plan.version },
    { simulator: true, store: true, source: "build", type: "minor", version: "1.0.0" },
    "a feature without an existing tag must plan release artifacts",
  );

  git("tag", "v1.0.0");
  plan = await planRelease({ cwd: repo, sha: head });
  assert.deepEqual(
    { simulator: plan.simulatorBuildRequired, store: plan.storeBuildRequired, source: plan.artifactSource, type: plan.type, version: plan.version },
    { simulator: false, store: false, source: "release", type: "tagged", version: "1.0.0" },
    "a retry at an existing release tag must promote the published artifact without rebuilding",
  );

  head = commit("ci: harden the workflow");
  plan = await planRelease({ cwd: repo, sha: head });
  assert.deepEqual(
    { simulator: plan.simulatorBuildRequired, store: plan.storeBuildRequired, source: plan.artifactSource, version: plan.version },
    { simulator: false, store: false, source: "none", version: "" },
    "a non-release main commit must not build release artifacts",
  );

  plan = await planRelease({ cwd: repo, sha: head, verifySignedArtifact: true });
  assert.deepEqual(
    { simulator: plan.simulatorBuildRequired, store: plan.storeBuildRequired, source: plan.artifactSource, version: plan.version },
    { simulator: false, store: true, source: "verify", version: "1.0.0" },
    "an explicit verification must build only the signed IPA and publish nothing",
  );

  head = commit("fix: repair a regression");
  plan = await planRelease({ cwd: repo, sha: head });
  assert.deepEqual(
    { simulator: plan.simulatorBuildRequired, store: plan.storeBuildRequired, source: plan.artifactSource, type: plan.type, version: plan.version },
    { simulator: true, store: true, source: "build", type: "patch", version: "1.0.1" },
    "a fix since the last release must plan both artifacts",
  );

  head = commit("feat!: advance the persistent format");
  plan = await planRelease({ cwd: repo, sha: head });
  assert.deepEqual(
    { simulator: plan.simulatorBuildRequired, store: plan.storeBuildRequired, source: plan.artifactSource, type: plan.type, version: plan.version },
    { simulator: true, store: true, source: "build", type: "major", version: "2.0.0" },
    "the planner must preserve semantic-release's highest pending bump",
  );
} finally {
  rmSync(repo, { recursive: true, force: true });
}

console.log("Release artifact planner contract tests passed (6 scenarios)");
