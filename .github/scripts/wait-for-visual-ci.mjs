import {pathToFileURL} from 'node:url';

// The fast Linux suites of the latest CI attempt for this exact PR head are
// the evidence a capture needs: the macOS device build is the merge gate, not
// a prerequisite for pointing a simulator at the same commit. Starting here
// instead of after the whole ladder takes several minutes off every capture.
export const FAST_SUITES = ['CadenceCore tests (Linux)', 'Web tests (parity + smoke)'];

// The latest pull_request attempt for the exact head is the only usable run.
export function latestRun(runs, sha) {
  return runs.filter(r => r.head_sha === sha && r.event === 'pull_request')
    .sort((a,b) => b.id-a.id)[0] || null;
}

// 'success' once every fast suite has passed; 'failed' as soon as one of them
// fails, or when the run has already ended without producing them (cancelled,
// preflight failure); otherwise 'pending'.
export function fastSuiteState(run, jobs) {
  if (!run) return 'pending';
  const byName = new Map((jobs || []).map(j => [j.name, j]));
  const suites = FAST_SUITES.map(name => byName.get(name));
  if (suites.some(j => j && j.status === 'completed' && j.conclusion !== 'success')) return 'failed';
  if (suites.every(j => j && j.status === 'completed' && j.conclusion === 'success')) return 'success';
  if (run.status === 'completed') return 'failed';
  return 'pending';
}

async function main() {
  const {GH_REPO, HEAD_SHA, GH_TOKEN} = process.env;
  if (!/^[a-zA-Z0-9_.-]+\/[a-zA-Z0-9_.-]+$/.test(GH_REPO || '') || !/^[a-f0-9]{40}$/.test(HEAD_SHA || '') || !GH_TOKEN) {
    throw new Error('Repository, exact head SHA and read-only Actions token are required');
  }
  const headers = {Authorization:`Bearer ${GH_TOKEN}`, Accept:'application/vnd.github+json'};
  const read = async (url) => {
    const response = await fetch(url, {headers, signal:AbortSignal.timeout(20000)});
    if (!response.ok) throw new Error(`Reading CI failed: HTTP ${response.status}`);
    return response.json();
  };
  for (let attempt=0; attempt<45; attempt++) {
    const runs = await read(`https://api.github.com/repos/${GH_REPO}/actions/workflows/ci.yml/runs?event=pull_request&head_sha=${HEAD_SHA}&per_page=30`);
    const run = latestRun(runs.workflow_runs || [], HEAD_SHA);
    const jobs = run ? (await read(`https://api.github.com/repos/${GH_REPO}/actions/runs/${run.id}/jobs?per_page=100`)).jobs : [];
    const state = fastSuiteState(run, jobs);
    if (state === 'success') { console.log(`Fast suites passed for ${HEAD_SHA}`); return; }
    if (state === 'failed') throw new Error('Latest CI attempt failed its fast suites; no simulator will start');
    console.log('Waiting for the exact PR head to pass the fast suites');
    await new Promise(resolve=>setTimeout(resolve,20000));
  }
  throw new Error('Timed out waiting for CI; no simulator will start');
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
