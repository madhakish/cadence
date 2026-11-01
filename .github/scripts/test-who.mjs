import assert from 'node:assert/strict';
import { test } from 'node:test';
import { age, overlaps, report } from './who.mjs';

const now = Date.parse('2026-11-01T12:00:00Z');
const prs = [
  { number: 7, title: 'feat(watch): rest timer', headRefName: 'feat/rest', isDraft: true, updatedAt: '2026-11-01T11:30:00Z',
    files: [{ path: 'CadenceWatch/RestView.swift' }, { path: 'CadenceCore/Sources/Rest.swift' }] },
  { number: 8, title: 'docs: notes', headRefName: 'docs/notes', isDraft: false, updatedAt: '2026-10-29T12:00:00Z',
    files: [{ path: '.agents/notes.md' }] },
];

test('ages read in minutes, hours, then days', () => {
  assert.equal(age('2026-11-01T11:30:00Z', now), '30m');
  assert.equal(age('2026-10-31T12:00:00Z', now), '24h');
  assert.equal(age('2026-10-29T12:00:00Z', now), '3d');
});

test('overlap lists shared files and ignores the branch\'s own PR', () => {
  const mine = ['CadenceCore/Sources/Rest.swift', '.agents/notes.md', 'README.md'];
  assert.deepEqual(overlaps(mine, prs, 'docs/notes'), [{ number: 7, files: ['CadenceCore/Sources/Rest.swift'] }]);
  assert.deepEqual(overlaps(['README.md'], prs, 'chore/x'), []);
});

test('the report names overlapping PRs and says so when there are none', () => {
  const merged = [{ number: 6, title: 'fix: x', mergedAt: '2026-11-01T10:00:00Z' }];
  const hit = report({ prs, merged, mine: ['CadenceWatch/RestView.swift'], branch: 'feat/other', now });
  assert.match(hit, /#7 draft {2}30m ago {2}feat\/rest/);
  assert.match(hit, /Overlap with feat\/other:\n {2}#7: CadenceWatch\/RestView\.swift/);
  assert.match(hit, /Recently merged:\n {2}#6 {2}2h ago {2}fix: x/);
  const clear = report({ prs: [], merged: [], mine: ['README.md'], branch: 'chore/x', now });
  assert.match(clear, /No open pull requests\./);
  assert.match(clear, /No open PR touches the 1 file\(s\) chore\/x changes\./);
});
