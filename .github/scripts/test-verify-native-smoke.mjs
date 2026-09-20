import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { verifyNativeSmoke } from "./verify-native-smoke.mjs";

// Captured from xcresulttool on run 35480646912, job 105997876432.
// Keep the real schema: Xcode 26.6 reports totalTestCount, not testsCount.
const passing = JSON.parse(readFileSync(new URL("./native-smoke-summary.fixture.json", import.meta.url), "utf8"));

test("actual Xcode summary proves all critical interactions executed", () => {
  assert.doesNotThrow(() => verifyNativeSmoke(passing));
});

test("empty, partial, skipped, failed, or unrecognized results fail closed", () => {
  for (const result of [
    {},
    { testsCount: 4, passedTests: 4, failedTests: 0, skippedTests: 0 },
    { ...passing, totalTestCount: 0, passedTests: 0 },
    { ...passing, totalTestCount: 3, passedTests: 3 },
    { ...passing, passedTests: 3, failedTests: 1 },
    { ...passing, passedTests: 3, skippedTests: 1 },
    { ...passing, totalTestCount: 5, passedTests: 5 },
  ]) {
    assert.throws(() => verifyNativeSmoke(result), /must execute and pass/);
  }
});
