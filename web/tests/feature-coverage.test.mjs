import { test } from 'node:test';
import assert from 'node:assert/strict';
import { manifest, verifyFeatureCoverage } from '../tools/verify-feature-coverage.mjs';

function report() {
  const specs = Object.keys(manifest.requirements).map((id) => ({ title: `[${id}] behavioral journey`,
    tests: manifest.projects.map((projectName) => ({ projectName, expectedStatus: 'passed',
      status: 'expected', results: [{ status: 'passed' }] })) }));
  return { errors: [], stats: { expected: specs.length * manifest.projects.length,
    unexpected: 0, flaky: 0, skipped: 0 }, suites: [{ suites: [{ specs }] }] };
}

test('every registered requirement executes on both browser engines', () => {
  assert.equal(verifyFeatureCoverage(report()).length, 10);
});

for (const [name, corrupt] of Object.entries({
  empty: (r) => { r.suites = []; },
  omittedRequirement: (r) => { r.suites[0].suites[0].specs.pop(); },
  omittedBrowser: (r) => { r.suites[0].suites[0].specs[0].tests.pop(); },
  unknownRequirement: (r) => { r.suites[0].suites[0].specs[0].title = '[WEB-NOT-REGISTERED]'; },
  duplicate: (r) => { r.suites[0].suites[0].specs.push(r.suites[0].suites[0].specs[0]); },
  skipped: (r) => { r.suites[0].suites[0].specs[0].tests[0].results[0].status = 'skipped'; },
  expectedFailure: (r) => { r.suites[0].suites[0].specs[0].tests[0].expectedStatus = 'failed'; },
  failure: (r) => { r.suites[0].suites[0].specs[0].tests[0].status = 'unexpected'; },
  missingResult: (r) => { r.suites[0].suites[0].specs[0].tests[0].results = []; },
  retry: (r) => { r.suites[0].suites[0].specs[0].tests[0].results.unshift({ status: 'failed' }); },
  interrupted: (r) => { r.errors.push({ message: 'Worker interrupted' }); },
  aggregateSkip: (r) => { r.stats.skipped = 1; },
})) {
  test(`acceptance fails closed on ${name}`, () => {
    const input = report(); corrupt(input);
    assert.throws(() => verifyFeatureCoverage(input));
  });
}
