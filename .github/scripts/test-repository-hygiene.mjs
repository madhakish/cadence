import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { validatePullRequest } from './pr-contract.mjs';
import { validateInstructions, commonFiles } from './check-agent-instructions.mjs';

const rootGuide = '# Guide\n[Coordination](AGENT-COORDINATION.md)\n[Doctrine](.agents/torvalds-doctrine.md)\n[Notes](.agents/notes.md)\n';

const validate = (pr) => validatePullRequest(pr).errors;

test('a Conventional Commit title passes with any body, or none', () => {
  for (const title of ['fix(core)!: migrate the store', 'feat(watch): log sets from wrist motion', 'ci: bump ruby/setup-ruby from 1.334.0 to 1.335.0']) {
    assert.deepEqual(validate({ title }), [], title);
    assert.deepEqual(validate({ title, body: 'Free prose.' }), [], title);
  }
});

test('titles semantic-release cannot read fail', () => {
  for (const title of ['misc updates', 'Fix: capitalised type', 'feat:missing space', 'ci: ok\nextra', 'feature: not a type', '', undefined]) {
    assert.equal(validate({ title }).length, 1, String(title));
  }
});

function fixture(changes = {}) {
  const root = mkdtempSync(join(tmpdir(), 'agent-instructions-'));
  const files = Object.fromEntries(commonFiles.map(path => [path, '# Guide\n']));
  Object.assign(files, {
    'AGENTS.md': rootGuide,
    '.github/copilot-instructions.md': '[Guide](../AGENTS.md)\n[Coordination](../AGENT-COORDINATION.md)\n[Doctrine](../.agents/torvalds-doctrine.md)\n',
    'CLAUDE.md': '@AGENTS.md\n@AGENT-COORDINATION.md\n@.agents/notes.md\n',
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

test('loaders must retain all three imports and cannot follow outside symlinks', () => {
  const root = fixture({ 'CLAUDE.md': '@AGENTS.md\n@AGENT-COORDINATION.md\n' });
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
