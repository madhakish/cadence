#!/usr/bin/env node
// Main-health merge gate. On 2026-10-31 main's release path was red for seven
// hours while feature PRs kept merging, each one another release candidate
// queued behind the broken path. While the newest push run of ci.yml on main
// is red, a pull request whose title would release fails here, and the
// `App build (macOS)` aggregate fails with it. Fixes stay mergeable: titles
// that release nothing, PRs that change the release path itself, and PRs
// labelled release-fix.
//
//   node main-health-gate.mjs <changed-paths-file>
//   GITHUB_EVENT_PATH, GITHUB_REPOSITORY, GH_TOKEN (actions: read)
//
// The event's labels and title are the ones the run started with; a re-run
// reuses them, so a newly added label needs a push or a reopen. Main's state
// is read live, so a re-run after main recovers passes.
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export const RELEASE_FIX_LABEL = 'release-fix';
// Workflows and CI scripts, signing, and the Xcode project.
const RELEASE_PATH = /^(?:\.github\/|fastlane\/|Gemfile[^/]*$|project\.yml$)/;
// Conclusions that judge main. Cancelled, skipped and neutral runs do not.
const RED = new Set(['failure', 'timed_out', 'startup_failure']);
const judges = (run) => run.conclusion === 'success' || RED.has(run.conclusion);

// Why this PR may merge whatever main's state, or null when main decides.
export function exemption({ releaseType, labels, paths }) {
  if (!releaseType) return 'its title does not produce a release';
  if (labels.includes(RELEASE_FIX_LABEL)) return `it is labelled ${RELEASE_FIX_LABEL}`;
  const path = paths.find((p) => RELEASE_PATH.test(p));
  return path ? `it changes the release path (${path})` : null;
}

// The newest completed push run on main with a verdict.
export function latestMainRun(runs) {
  return runs
    .filter((r) => r.event === 'push' && r.head_branch === 'main' && r.status === 'completed' && judges(r))
    .sort((a, b) => b.created_at.localeCompare(a.created_at))[0] ?? null;
}

export function judge(run) {
  if (!run) return { blocked: false, message: 'no completed main run to judge; not blocking' };
  const which = `CI run #${run.run_number} for ${run.head_sha.slice(0, 7)} (${run.html_url})`;
  if (!RED.has(run.conclusion)) return { blocked: false, message: `main is green: ${which}` };
  return {
    blocked: true,
    message: `main's release path is red: ${which} concluded ${run.conclusion}. ` +
      'Release-producing PRs wait until main is green again; fix main first. ' +
      `If this PR is that fix, label it ${RELEASE_FIX_LABEL} and push or reopen it. ` +
      'Once main is green, re-run this job.',
  };
}

export async function gate({ pullRequest, paths, releaseType, loadRuns }) {
  const exempt = exemption({
    releaseType: await releaseType(pullRequest.title),
    labels: (pullRequest.labels ?? []).map((l) => l.name),
    paths,
  });
  if (exempt) return { blocked: false, message: `not applicable: ${exempt}` };
  return judge(latestMainRun(await loadRuns()));
}

export async function fetchMainRuns({ repository, token, api = 'https://api.github.com', request = fetch }) {
  const url = `${api}/repos/${repository}/actions/workflows/ci.yml/runs` +
    '?branch=main&event=push&status=completed&exclude_pull_requests=true&per_page=30';
  const response = await request(url, {
    headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' },
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error(`cannot read main's CI runs (HTTP ${response.status}); re-run this job`);
  return (await response.json()).workflow_runs ?? [];
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  if (!event.pull_request) throw new Error('the main-health gate runs on pull_request events only');
  // The pinned release toolchain (.github/release, npm ci) provides the analyzer.
  const { releaseType } = await import('./plan-release.mjs');
  const result = await gate({
    pullRequest: event.pull_request,
    paths: readFileSync(process.argv[2], 'utf8').split('\n').filter(Boolean),
    releaseType: (title) => releaseType([{ hash: 'pull-request-title', message: title }]),
    loadRuns: () => fetchMainRuns({
      repository: process.env.GITHUB_REPOSITORY,
      token: process.env.GH_TOKEN,
      api: process.env.GITHUB_API_URL,
    }),
  });
  console.log(result.blocked ? `::error::${result.message}` : `Main-health gate: ${result.message}`);
  if (result.blocked) process.exitCode = 1;
}
