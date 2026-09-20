import { test } from "node:test";
import assert from "node:assert/strict";
import { verifyNativeSmoke } from "./verify-native-smoke.mjs";

const passing = { testsCount: 4, passedTests: 4, failedTests: 0, skippedTests: 0 };

test("all critical interactions executed successfully", () => {
  assert.doesNotThrow(() => verifyNativeSmoke(passing));
});

test("empty, partial, skipped, failed, or unrecognized results fail closed", () => {
  for (const result of [
    {},
    { totalTestCount: 4, passedTests: 4, failedTests: 0, skippedTests: 0 },
    { testsCount: 0, passedTests: 0, failedTests: 0, skippedTests: 0 },
    { ...passing, testsCount: 3, passedTests: 3 },
    { ...passing, passedTests: 3, failedTests: 1 },
    { ...passing, passedTests: 3, skippedTests: 1 },
    { ...passing, testsCount: 5, passedTests: 5 },
  ]) {
    assert.throws(() => verifyNativeSmoke(result), /must execute and pass/);
  }
});
