// The main-health gate against canned responses of the workflow-runs API.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { exemption, fetchMainRuns, gate, judge, latestMainRun } from './main-health-gate.mjs';

const fixture = JSON.parse(readFileSync(new URL('./main-health-runs.fixture.json', import.meta.url), 'utf8'));
const runs = fixture.workflow_runs;
const withConclusion = (id, conclusion) => runs.map((r) => (r.id === id ? { ...r, conclusion } : r));
const feature = { releaseType: 'minor', labels: [], paths: ['Cadence/Views/HomeView.swift'] };

test('the newest judged main run decides; cancelled and skipped runs say nothing', () => {
  assert.equal(latestMainRun(runs).id, 9003);
  assert.equal(latestMainRun([...runs].reverse()).id, 9003, 'response order must not matter');
  assert.equal(latestMainRun(withConclusion(9003, 'success')).id, 9003);
  assert.equal(latestMainRun(runs.filter((r) => ['cancelled', 'skipped'].includes(r.conclusion))), null);
  // Defence in depth over the API's own filters.
  const stray = [{ ...runs[1], id: 1, event: 'pull_request', created_at: '2026-11-01T00:00:00Z' },
    { ...runs[1], id: 2, head_branch: 'feature', created_at: '2026-11-01T00:00:00Z' },
    { ...runs[1], id: 3, status: 'in_progress', conclusion: null, created_at: '2026-11-01T00:00:00Z' }];
  assert.equal(latestMainRun([...stray, ...withConclusion(9003, 'success')]).id, 9003);
});

test('a red main blocks; a green or unknown main does not', () => {
  const red = judge(latestMainRun(runs));
  assert.equal(red.blocked, true);
  assert.match(red.message, /CI run #403 for 3333333 .*runs\/9003\) concluded failure/);
  assert.match(red.message, /label it release-fix/);
  for (const conclusion of ['timed_out', 'startup_failure']) {
    assert.equal(judge(latestMainRun(withConclusion(9003, conclusion))).blocked, true, conclusion);
  }
  assert.equal(judge(latestMainRun(withConclusion(9003, 'success'))).blocked, false);
  assert.equal(judge(null).blocked, false);
});

test('only release-producing PRs outside the release path, without release-fix, are held', () => {
  assert.equal(exemption(feature), null);
  assert.match(exemption({ ...feature, releaseType: null }), /does not produce a release/);
  assert.match(exemption({ ...feature, labels: ['area:ci', 'release-fix'] }), /labelled release-fix/);
  for (const path of ['.github/workflows/ci.yml', '.github/scripts/plan-release.mjs', 'fastlane/Fastfile', 'Gemfile', 'Gemfile.lock', 'project.yml']) {
    assert.match(exemption({ ...feature, paths: [...feature.paths, path] }), /changes the release path/, path);
  }
  for (const path of ['docs/project.yml', 'web/Gemfile', 'Cadence/fastlane/notes.md', 'docs/.github/x']) {
    assert.equal(exemption({ ...feature, paths: [path] }), null, path);
  }
});

test('the gate reads main only when the PR is not exempt', async () => {
  let reads = 0;
  const loadRuns = async () => { reads += 1; return runs; };
  const releaseType = async (title) => (title.startsWith('feat') ? 'minor' : null);
  const pr = (title, labels = []) => ({ title, labels: labels.map((name) => ({ name })) });

  assert.equal((await gate({ pullRequest: pr('feat: x'), paths: feature.paths, releaseType, loadRuns })).blocked, true);
  assert.equal(reads, 1);
  for (const [pullRequest, paths] of [[pr('ci: x'), feature.paths], [pr('feat: x', ['release-fix']), feature.paths],
    [pr('feat: x'), ['fastlane/Fastfile']]]) {
    assert.equal((await gate({ pullRequest, paths, releaseType, loadRuns })).blocked, false, pullRequest.title);
  }
  assert.equal(reads, 1, 'an exempt PR must not depend on the runs API');
});

test('main runs come from the push runs of ci.yml on main, and API failures fail loudly', async () => {
  const got = await fetchMainRuns({ repository: 'example/cadence', token: 't', request: async (url, options) => {
    assert.equal(url, 'https://api.github.com/repos/example/cadence/actions/workflows/ci.yml/runs' +
      '?branch=main&event=push&status=completed&exclude_pull_requests=true&per_page=30');
    assert.equal(options.headers.Authorization, 'Bearer t');
    return { ok: true, json: async () => fixture };
  } });
  assert.equal(got.length, 4);
  await assert.rejects(fetchMainRuns({ repository: 'example/cadence', token: 't', request: async () => ({ ok: false, status: 403 }) }), /HTTP 403/);
});
