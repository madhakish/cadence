import assert from "node:assert/strict";
import { draftNudge, fixCommits, MARKER, REGISTRY } from "./invariant-nudge.mjs";

const fix = { sha: "abc1234def", message: "fix: keep the rest timer from restarting on undo\n\nUndoing a verdict restarted a running countdown.\n\nRefs #12" };
const feat = { sha: "0000000aaa", message: "feat: add a thing" };
const breaking = { sha: "beefbeef00", message: "fix!: advance the store schema\n\nBREAKING CHANGE: old stores migrate." };

// Only Conventional Commit fixes count; the subject and first prose paragraph feed the draft.
assert.deepEqual(fixCommits([feat]), []);
assert.deepEqual(fixCommits([fix]), [{ sha: "abc1234def", subject: "keep the rest timer from restarting on undo", breaking: false, rationale: "Undoing a verdict restarted a running countdown." }]);
assert.equal(fixCommits([breaking])[0].breaking, true);
assert.equal(fixCommits([breaking])[0].rationale, "");

// No fix commits: nothing to say.
assert.equal(draftNudge({ commits: [feat], files: ["web/app/js/ui.js"] }).comment, null);

// Fix commits with the registry touched: a short "nothing to do" that replaces an earlier nudge.
const touched = draftNudge({ commits: [fix, feat], files: [REGISTRY, "web/app/js/ui.js"] });
assert.ok(touched.registryTouched);
assert.ok(touched.comment.startsWith(MARKER));
assert.match(touched.comment, /1 fix commit and updates/);

// Fix commits without the registry: the nudge lists them and drafts an entry per fix.
const nudged = draftNudge({ commits: [fix, breaking, feat], files: ["Cadence/Views/RootView.swift"] });
assert.ok(nudged.comment.startsWith(MARKER));
assert.match(nudged.comment, /2 fix commits and does not touch/);
assert.match(nudged.comment, /- `abc1234` keep the rest timer from restarting on undo/);
assert.match(nudged.comment, /### INV-KEEP-REST-TIMER-RESTARTING/);
assert.match(nudged.comment, /Keep the rest timer from restarting on undo\. Undoing a verdict restarted a running countdown\./);
assert.match(nudged.comment, /never blocks a merge/);
assert.ok(!nudged.comment.includes("Refs #12"), "footers never leak into the draft");

console.log("invariant nudge: 11 assertions passed");
