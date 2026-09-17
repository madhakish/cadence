import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {ciState} from './wait-for-visual-ci.mjs';
const sha='a'.repeat(40);
const success={id:1,head_sha:sha,event:'pull_request',status:'completed',conclusion:'success'};
assert.equal(ciState([],sha),'pending');
assert.equal(ciState([success],sha),'success');
assert.equal(ciState([{...success,head_sha:'b'.repeat(40)}],sha),'pending');
assert.equal(ciState([{...success,event:'push'}],sha),'pending');
assert.equal(ciState([success,{...success,id:2,status:'in_progress',conclusion:null}],sha),'pending');
for (const conclusion of ['failure','cancelled','skipped','timed_out','neutral']) {
  assert.equal(ciState([success,{...success,id:2,conclusion}],sha),'failed');
}
const workflow=readFileSync('.github/workflows/visual-proof.yml','utf8');
assert.ok(workflow.includes("contains(github.event.pull_request.labels.*.name, 'visual-proof')"));
assert.ok(workflow.includes('github.event.pull_request.head.repo.full_name == github.repository'));
assert.ok(workflow.includes('needs: gate'));
assert.ok(workflow.includes('ref: ${{ needs.gate.outputs.sha }}'));
assert.ok(!workflow.includes('pull_request_target'));
assert.ok(!workflow.includes('write')); // no elevated token on code execution
assert.ok(workflow.includes('persist-credentials: false'));
console.log('Opt-in visual CI gating tests passed');
