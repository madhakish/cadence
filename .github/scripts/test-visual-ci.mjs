import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {FAST_SUITES, latestRun, fastSuiteState} from './wait-for-visual-ci.mjs';
const sha='a'.repeat(40);
const run={id:1,head_sha:sha,event:'pull_request',status:'in_progress',conclusion:null};
const done=(name,conclusion='success')=>({name,status:'completed',conclusion});
const running=(name)=>({name,status:'in_progress',conclusion:null});
const [core,web]=FAST_SUITES;
// Only the latest pull_request attempt for the exact head counts.
assert.equal(latestRun([],sha),null);
assert.equal(latestRun([run],sha),run);
assert.equal(latestRun([{...run,head_sha:'b'.repeat(40)}],sha),null);
assert.equal(latestRun([{...run,event:'push'}],sha),null);
assert.equal(latestRun([run,{...run,id:2}],sha).id,2);
// The capture starts once the fast Linux suites pass, not after the macOS ladder.
assert.equal(fastSuiteState(null,[]),'pending');
assert.equal(fastSuiteState(run,[]),'pending');
assert.equal(fastSuiteState(run,[done(core),running(web)]),'pending');
assert.equal(fastSuiteState(run,[done(core),done(web),running('Unsigned device build')]),'success');
assert.equal(fastSuiteState({...run,status:'completed',conclusion:'failure'},[done(core),done(web),done('Unsigned device build','failure')]),'success');
for (const conclusion of ['failure','cancelled','skipped','timed_out','neutral']) {
  assert.equal(fastSuiteState(run,[done(core),done(web,conclusion)]),'failed');
}
// A run that ended without those suites (preflight failure, superseded) never will.
assert.equal(fastSuiteState({...run,status:'completed',conclusion:'cancelled'},[done('Preflight + classify')]),'failed');
const ci=readFileSync('.github/workflows/ci.yml','utf8');
for (const name of FAST_SUITES) assert.ok(ci.includes(`name: ${name}`), `${name} is a CI job name`);
const workflow=readFileSync('.github/workflows/visual-proof.yml','utf8');
assert.ok(workflow.includes("contains(github.event.pull_request.labels.*.name, 'visual-proof')"));
assert.ok(workflow.includes('github.event.pull_request.head.repo.full_name == github.repository'));
assert.ok(workflow.includes('needs: gate'));
assert.ok(workflow.includes('ref: ${{ needs.gate.outputs.sha }}'));
assert.ok(workflow.includes('path: build/visual-proof') && workflow.includes('restore-keys:'), 'the simulator build is cached between captures');
assert.ok(!workflow.includes('pull_request_target'));
assert.ok(!workflow.includes('write')); // no elevated token on code execution
assert.ok(workflow.includes('persist-credentials: false'));
console.log('Opt-in visual CI gating tests passed');
