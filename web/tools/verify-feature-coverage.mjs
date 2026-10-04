import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const manifest = JSON.parse(readFileSync(new URL('../tests/browser/requirements.json', import.meta.url), 'utf8'));

export function verifyFeatureCoverage(report) {
  const expected = new Set(manifest.projects.flatMap((project) =>
    Object.keys(manifest.requirements).map((id) => `${project}/${id}`)));
  if (!expected.size || !Array.isArray(report?.suites) || !Array.isArray(report.errors)
      || report.errors.length || report.stats?.unexpected !== 0 || report.stats?.flaky !== 0
      || report.stats?.skipped !== 0 || report.stats?.expected !== expected.size) {
    throw new Error('Browser acceptance report is missing, incomplete, failed or skipped');
  }
  const seen = new Set();
  function visit(suite) {
    for (const spec of suite.specs || []) {
      const id = /^\[(WEB-[A-Z-]+)\]/.exec(spec.title)?.[1];
      for (const result of spec.tests || []) {
        const key = `${result.projectName}/${id}`;
        if (!expected.has(key) || seen.has(key) || result.expectedStatus !== 'passed'
            || result.status !== 'expected' || result.results?.length !== 1
            || result.results[0].status !== 'passed') {
          throw new Error(`Missing, duplicated, retried, skipped or failed requirement: ${key}`);
        }
        seen.add(key);
      }
    }
    for (const child of suite.suites || []) visit(child);
  }
  for (const suite of report.suites) visit(suite);
  const missing = [...expected].filter((key) => !seen.has(key));
  if (missing.length) throw new Error(`Unexecuted requirements: ${missing.join(', ')}`);
  return [...seen].sort();
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const report = JSON.parse(readFileSync(process.argv[2] || 'test-results/browser-results.json', 'utf8'));
  const executed = verifyFeatureCoverage(report);
  console.log(`Browser acceptance: ${executed.length} required executions passed; no skips or retries.`);
  for (const key of executed) console.log(`PASS ${key}`);
}
