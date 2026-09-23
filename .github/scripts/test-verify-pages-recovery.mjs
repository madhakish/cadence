import { test } from "node:test";
import assert from "node:assert/strict";
import { selectMainRun, verifyMainValidation } from "./verify-pages-recovery.mjs";

const run = { id: 1, run_number: 1, event: "push", head_sha: "abc", head_branch: "main" };
const gate = { name: "App build (macOS)", status: "completed", conclusion: "success" };

test("recovery requires the exact main push and its newest run", () => {
  assert.equal(selectMainRun([run, { ...run, id: 2, run_number: 2 }], "abc").id, 2);
  for (const other of [
    [], [{ ...run, event: "pull_request" }], [{ ...run, head_sha: "def" }],
    [{ ...run, head_branch: "feature" }],
  ]) assert.throws(() => selectMainRun(other, "abc"));
});

test("missing, skipped, failed, pending or ambiguous validation cannot deploy", () => {
  for (const jobs of [
    [], [gate, gate], [{ ...gate, conclusion: "failure" }],
    [{ ...gate, conclusion: "skipped" }], [{ ...gate, status: "in_progress" }],
  ]) assert.throws(() => verifyMainValidation(jobs));
});

test("a Pages publishing failure can be recovered after validation passed", () => {
  assert.equal(selectMainRun([{ ...run, conclusion: "failure" }], "abc").id, 1);
  assert.doesNotThrow(() => verifyMainValidation([
    gate, { name: "Deploy site + web app (Pages)", status: "completed", conclusion: "failure" },
  ]));
});
