import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

export function verifyNativeSmoke(summary) {
  const expected = 4;
  if (summary.totalTestCount !== expected || summary.passedTests !== expected ||
      summary.failedTests !== 0 || summary.skippedTests !== 0) {
    throw new Error("All four native interaction tests must execute and pass with zero skips.");
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  verifyNativeSmoke(JSON.parse(readFileSync(process.argv[2], "utf8")));
  console.log("All four native interaction tests executed and passed.");
}
