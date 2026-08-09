#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { appendFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { analyzeCommits } from "../release/node_modules/@semantic-release/commit-analyzer/index.js";
import semver from "../release/node_modules/semver/index.js";

const RELEASE_CWD = fileURLToPath(new URL("../release/", import.meta.url));
const SEMVER_TAG = /^v\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/;
const logger = { log() {}, error() {} };

const git = (cwd, args) =>
  execFileSync("git", args, { cwd, encoding: "utf8" }).trim();

const lines = (value) => value.split("\n").filter(Boolean);

export async function planRelease({ cwd, sha, verifySignedArtifact = false }) {
  const tagAtHead = lines(git(cwd, ["tag", "--points-at", sha, "--list", "v[0-9]*"]))
    .find((tag) => SEMVER_TAG.test(tag));
  const lastTag = lines(git(cwd, [
    "tag",
    "--merged",
    sha,
    "--list",
    "v[0-9]*",
    "--sort=-version:refname",
  ])).find((tag) => SEMVER_TAG.test(tag));
  const range = lastTag ? `${lastTag}..${sha}` : sha;
  const commits = lines(git(cwd, ["rev-list", "--reverse", range])).map((hash) => ({
    hash,
    message: git(cwd, ["show", "-s", "--format=%B", hash]),
  }));
  const type = await analyzeCommits(
    { preset: "conventionalcommits" },
    { cwd: RELEASE_CWD, commits, logger },
  );

  if (verifySignedArtifact) {
    const version = tagAtHead?.slice(1) ??
      (type && lastTag ? semver.inc(lastTag.slice(1), type) : null) ??
      lastTag?.slice(1) ??
      "1.0.0";
    return {
      simulatorBuildRequired: false,
      storeBuildRequired: true,
      artifactSource: "verify",
      type: type ?? "none",
      version,
      reason: "explicit-signed-artifact-verification",
    };
  }

  if (tagAtHead) {
    return {
      simulatorBuildRequired: false,
      storeBuildRequired: false,
      artifactSource: "release",
      type: "tagged",
      version: tagAtHead.slice(1),
      reason: `reuse-${tagAtHead}`,
    };
  }

  if (!type) {
    return {
      simulatorBuildRequired: false,
      storeBuildRequired: false,
      artifactSource: "none",
      type: "none",
      version: "",
      reason: "no-release-producing-commits",
    };
  }

  const version = lastTag ? semver.inc(lastTag.slice(1), type) : "1.0.0";
  if (!version) throw new Error(`Cannot apply a ${type} bump to ${lastTag}`);
  return {
    simulatorBuildRequired: true,
    storeBuildRequired: true,
    artifactSource: "build",
    type,
    version,
    reason: `pending-${type}-release`,
  };
}

function writePlan(plan, outputPath) {
  appendFileSync(
    outputPath,
    `simulator-build-required=${plan.simulatorBuildRequired}\n` +
      `store-build-required=${plan.storeBuildRequired}\n` +
      `artifact-source=${plan.artifactSource}\n` +
      `type=${plan.type}\nversion=${plan.version}\nreason=${plan.reason}\n`,
  );
}

async function main() {
  const outputPath = process.env.GITHUB_OUTPUT;
  if (!outputPath) throw new Error("GITHUB_OUTPUT is required");

  let plan;
  if (process.env.RELEASE_CANDIDATE !== "true") {
    plan = {
      simulatorBuildRequired: false,
      storeBuildRequired: false,
      artifactSource: "none",
      type: "none",
      version: "",
      reason: "not-main",
    };
  } else {
    const sha = process.env.GITHUB_SHA;
    if (!sha) throw new Error("GITHUB_SHA is required for a release candidate");
    plan = await planRelease({
      cwd: process.cwd(),
      sha,
      verifySignedArtifact: process.env.VERIFY_SIGNED_ARTIFACT === "true",
    });
  }

  writePlan(plan, outputPath);
  console.log(
    `release artifact: source=${plan.artifactSource} version=${plan.version || "none"} (${plan.reason})`,
  );
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
