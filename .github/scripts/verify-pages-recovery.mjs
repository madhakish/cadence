import { pathToFileURL } from "node:url";

export function selectMainRun(runs, sha) {
  const run = runs.filter((r) => r.head_sha === sha && r.head_branch === "main" && r.event === "push")
    .sort((a, b) => b.run_number - a.run_number)[0];
  if (!run || !Number.isSafeInteger(run.id) || run.id <= 0) {
    throw new Error("No main CI run exists for the requested commit.");
  }
  return run;
}

export function verifyMainValidation(jobs) {
  const gates = jobs.filter((job) => job.name === "App build (macOS)");
  if (gates.length !== 1 || gates[0].status !== "completed" || gates[0].conclusion !== "success") {
    throw new Error("The exact main commit must pass its complete validation aggregate before Pages recovery.");
  }
}

async function main() {
  const { GH_REPO, GH_TOKEN, GITHUB_SHA, GITHUB_REF } = process.env;
  if (!GH_REPO || !GH_TOKEN || !GITHUB_SHA || GITHUB_REF !== "refs/heads/main") {
    throw new Error("Pages recovery requires main and explicit repository, token and commit.");
  }
  const get = async (path) => {
    const response = await fetch("https://api.github.com/repos/" + GH_REPO + "/" + path, {
      headers: { Authorization: "Bearer " + GH_TOKEN, Accept: "application/vnd.github+json" },
      signal: AbortSignal.timeout(30000),
    });
    if (!response.ok) throw new Error("Cannot verify main CI (HTTP " + response.status + ").");
    return response.json();
  };
  const query = new URLSearchParams({ branch: "main", event: "push", head_sha: GITHUB_SHA, per_page: "100" });
  const runs = await get("actions/workflows/ci.yml/runs?" + query);
  const run = selectMainRun(runs.workflow_runs, GITHUB_SHA);
  const result = await get("actions/runs/" + run.id + "/jobs?filter=latest&per_page=100");
  verifyMainValidation(result.jobs);
  console.log("Main validation passed for " + GITHUB_SHA + "; Pages recovery may proceed.");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main();
}
