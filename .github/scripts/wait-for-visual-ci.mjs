import {pathToFileURL} from 'node:url';

// The latest CI attempt for this exact PR head is the only usable evidence.
export function ciState(runs, sha) {
  const run = runs.filter(r => r.head_sha === sha && r.event === 'pull_request')
    .sort((a,b) => b.id-a.id)[0];
  if (!run || run.status !== 'completed') return 'pending';
  return run.conclusion === 'success' ? 'success' : 'failed';
}

async function main() {
  const {GH_REPO, HEAD_SHA, GH_TOKEN} = process.env;
  if (!/^[a-zA-Z0-9_.-]+\/[a-zA-Z0-9_.-]+$/.test(GH_REPO || '') || !/^[a-f0-9]{40}$/.test(HEAD_SHA || '') || !GH_TOKEN) {
    throw new Error('Repository, exact head SHA and read-only Actions token are required');
  }
  for (let attempt=0; attempt<45; attempt++) {
    const response = await fetch(`https://api.github.com/repos/${GH_REPO}/actions/workflows/ci.yml/runs?event=pull_request&head_sha=${HEAD_SHA}&per_page=30`, {
      headers:{Authorization:`Bearer ${GH_TOKEN}`, Accept:'application/vnd.github+json'},
      signal:AbortSignal.timeout(20000),
    });
    if (!response.ok) throw new Error(`Reading CI failed: HTTP ${response.status}`);
    const state = ciState((await response.json()).workflow_runs || [], HEAD_SHA);
    if (state === 'success') { console.log(`CI passed for ${HEAD_SHA}`); return; }
    if (state === 'failed') throw new Error('Latest CI attempt failed; no simulator will start');
    console.log('Waiting for the exact PR head to pass CI');
    await new Promise(resolve=>setTimeout(resolve,20000));
  }
  throw new Error('Timed out waiting for CI; no simulator will start');
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
