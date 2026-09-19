import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { validatePullRequest, checkTask } from './pr-contract.mjs';
import { validateInstructions, commonFiles } from './check-agent-instructions.mjs';

const rootGuide = '# Guide\n[Coordination](AGENT-COORDINATION.md)\n[Doctrine](.agents/torvalds-doctrine.md)\n';

const pr = { title: 'ci: validate instructions', body: 'Task: #12\nScope: Enforce instruction budgets.\nVerification: Node regression cases passed.', user: { login: 'maintainer', type: 'User' } };
const validate = (change) => validatePullRequest({ ...pr, ...change }, 'owner/repo');

test('canonical task references and a reasoned maintenance exemption', () => {
  for (const value of ['#12', 'owner/repo#12', 'https://github.com/owner/repo/issues/12']) {
    assert.deepEqual(validate({ body: pr.body.replace('#12', value) }), { errors: [], task: { repository: 'owner/repo', number: 12 } });
  }
  assert.deepEqual(validate({ body: pr.body.replace('#12', 'none — weekly dependency maintenance') }), { errors: [], task: null });
});

test('missing, duplicate, placeholder and example-only fields fail', () => {
  for (const body of ['', pr.body + '\nTask: #13', pr.body.replace('#12', '<issue>'), pr.body.replace('#12', 'none — <reason>'), `<!-- ${pr.body} -->`, '```text\n' + pr.body + '\n```', pr.body.replace('Node regression cases passed.', 'pending')]) {
    assert.ok(validate({ body }).errors.length, body);
  }
});

test('unterminated fences, longer closers and shorter non-closers hide metadata', () => {
  for (const fence of ['```', '~~~~']) {
    const longer = fence + fence[0];
    const examples = [fence + 'text\n' + pr.body, fence + 'text\n' + pr.body + '\n' + longer,
      longer + '\n' + fence + '\n' + pr.body + '\n' + longer];
    for (const body of examples) assert.ok(validate({ body }).errors.length, body);
    assert.deepEqual(validate({ body: fence + 'text\nTask: fake\n' + longer + '\n' + pr.body }).errors, []);
  }
  assert.ok(validate({ body: '<!--\n' + pr.body }).errors.length);
});

test('Conventional Commit titles and authenticated Dependabot identity', () => {
  assert.equal(validate({ title: 'fix(core)!: migrate the store' }).errors.length, 0);
  assert.ok(validate({ title: 'misc updates' }).errors.length);
  assert.ok(validate({ title: 'ci: ok\nextra' }).errors.length);
  assert.equal(validate({ body: 'Bumps a dependency.', user: { login: 'dependabot[bot]', type: 'Bot' } }).errors.length, 0);
  assert.ok(validate({ body: '', user: { login: 'dependabot[bot]', type: 'User' } }).errors.length);
});

test('comment markers in fence info do not hide following metadata', () => {
  for (const fence of ['```', '~~~']) {
    const body = `${fence}html <!-- example\n<div>example</div>\n${fence}\n${pr.body}`;
    assert.deepEqual(validate({ body }).errors, []);
  }
});

test('issue validation rejects PR references and inaccessible tasks', async () => {
  const task = { repository: 'owner/repo', number: 12 };
  await checkTask(task, 'test-token', async (url) => {
    assert.equal(url, 'https://api.github.com/repos/owner/repo/issues/12');
    return { ok: true, json: async () => ({ number: 12 }) };
  });
  await assert.rejects(checkTask(task, 'test-token', async () => ({ ok: true, json: async () => ({ pull_request: {} }) })), /pull request/);
  await assert.rejects(checkTask(task, 'test-token', async () => ({ ok: false, status: 404 })), /HTTP 404/);
});

function fixture(changes = {}) {
  const root = mkdtempSync(join(tmpdir(), 'agent-instructions-'));
  const files = Object.fromEntries(commonFiles.map(path => [path, '# Guide\n']));
  Object.assign(files, {
    'AGENTS.md': rootGuide,
    '.github/copilot-instructions.md': '[Guide](../AGENTS.md)\n[Coordination](../AGENT-COORDINATION.md)\n[Doctrine](../.agents/torvalds-doctrine.md)\n',
    'CLAUDE.md': '@AGENTS.md\n@AGENT-COORDINATION.md\n',
    'docs/AGENT-INSTRUCTIONS.md': '# Maintenance\n', 'docs/REPOSITORY-HYGIENE.md': '# Hygiene\n',
  }, changes);
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), text);
  }
  return root;
}

test('valid links, duplicate heading anchors and literal code examples', () => {
  const root = fixture({ 'AGENTS.md': rootGuide + '# Guide\n[second](#guide-1)\n```text\n@missing.md\n[example](absent.md)\n```\n' });
  try { assert.deepEqual(validateInstructions(root).errors, []); }
  finally { rmSync(root, { recursive: true }); }
});

test('instruction limits count both bytes and lines', () => {
  for (const text of ['x\n'.repeat(201), '界'.repeat(2800)]) {
    const root = fixture({ 'AGENTS.md': text });
    try { assert.ok(validateInstructions(root).errors.some(e => e.includes('exceeds 200'))); }
    finally { rmSync(root, { recursive: true }); }
  }
  const root = fixture({ '.agents/torvalds-doctrine.md': 'x'.repeat(20480) });
  try { assert.ok(validateInstructions(root).errors.some(e => e.includes('Common instructions'))); }
  finally { rmSync(root, { recursive: true }); }
});

test('missing files, missing anchors, traversal and cycles fail', () => {
  const cases = [
    ['[broken](absent.md)', /missing or outside repository: absent\.md/],
    ['[broken](CLAUDE.md#absent)', /missing anchor CLAUDE\.md#absent/],
    ['[escape](../../outside)', /missing or outside repository: \.\.\/\.\.\/outside/],
    ['@CLAUDE.md\n', /Import cycle at/],
  ];
  for (const [text, expected] of cases) {
    const root = fixture({ 'AGENTS.md': rootGuide + text });
    try { assert.ok(validateInstructions(root).errors.some(error => expected.test(error)), text); }
    finally { rmSync(root, { recursive: true }); }
  }
});

test('loaders must retain both imports and cannot follow outside symlinks', () => {
  const root = fixture({ 'CLAUDE.md': '@AGENTS.md\n' });
  const outside = mkdtempSync(join(tmpdir(), 'outside-instructions-'));
  try {
    assert.ok(validateInstructions(root).errors.some(e => e.includes('must import')));
    writeFileSync(join(outside, 'secret.md'), 'private');
    symlinkSync(join(outside, 'secret.md'), join(root, 'linked.md'));
    writeFileSync(join(root, 'AGENTS.md'), '[link](linked.md)');
    assert.ok(validateInstructions(root).errors.some(e => e.includes('outside repository')));
  } finally { rmSync(root, { recursive: true }); rmSync(outside, { recursive: true }); }
});

test('new automatic imports cannot evade the aggregate budget', () => {
  const root = fixture({ 'AGENTS.md': rootGuide + '@extra.md\n', 'extra.md': 'x'.repeat(20480) });
  try { assert.ok(validateInstructions(root).errors.some(e => e.includes('Common instructions'))); }
  finally { rmSync(root, { recursive: true }); }
});

test('Codex and Copilot entry points must keep their required references', () => {
  for (const path of ['AGENTS.md', '.github/copilot-instructions.md']) {
    const root = fixture({ [path]: '# Guide\n' });
    try { assert.ok(validateInstructions(root).errors.some(e => e.includes('must link'))); }
    finally { rmSync(root, { recursive: true }); }
  }
});
