import { test as base, expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { startServer } from './server.mjs';

const test = base.extend({
  app: async ({ page }, use) => {
    const server = await startServer();
    const errors = [];
    page.on('pageerror', (error) => errors.push(error.message));
    try {
      await page.goto(server.url);
      await expect.poll(() => page.evaluate(() => !!navigator.serviceWorker.controller).catch(() => false)).toBe(true);
      // First installation claims the client and the production app reloads.
      await expect(page.getByRole('button', { name: 'Blank session', exact: true })).toBeVisible();
      await use(server);
      expect(errors, 'No uncaught browser exceptions').toEqual([]);
    } finally { await server.close(); }
  },
});

// Read-only assertions at the real repository boundary. All workout mutations
// in these journeys go through visible controls, never fixture store writes.
const sessions = (page) => page.evaluate(async () => (await import('./js/db.js')).Sessions.all());
const snapshot = async (page) => (await sessions(page))[0];
const sets = async (page) => (await snapshot(page)).exercises[0].sets;

async function startWorkout(page) {
  await page.getByRole('button', { name: 'Blank session', exact: true }).click();
  await page.getByRole('button', { name: '+ Add exercise', exact: true }).click();
  await page.getByRole('searchbox', { name: 'Search exercises' }).fill('Push-ups');
  await page.getByRole('button', { name: 'Push-ups', exact: true }).click();
  await page.getByRole('button', { name: '+ Set', exact: true }).click();
  const initialReps = (await sets(page))[0].reps;
  await page.locator('.setrow').getByRole('button', { name: /BW.*×/ }).click();
  const editor = page.getByRole('dialog', { name: 'Edit set', exact: true });
  await editor.locator('label').filter({ hasText: 'Reps' }).getByRole('button', { name: '+', exact: true }).click();
  await editor.getByRole('button', { name: 'Done', exact: true }).click();
  await expect.poll(async () => (await sets(page))[0].reps).toBe(initialReps + 1);
  await page.getByRole('button', { name: 'Set status: planned', exact: true }).click();
  await expect.poll(async () => (await sets(page))[0].status).toBe('completed');
  await page.getByRole('button', { name: '+ Set', exact: true }).click();
  await expect.poll(async () => (await sets(page)).length).toBe(2);
  await page.getByRole('button', { name: 'Show all sets', exact: true }).click();
  const workout = await snapshot(page);
  expect(workout.isCompleted).toBe(false);
  expect(workout.exercises[0].sets.map((set) => set.status)).toEqual(['completed', 'planned']);
  expect(workout.exercises[0].sets[0].weightLb).toBe(0);
  return workout;
}

async function resume(page) {
  await page.getByRole('button', { name: /Resume workout/ }).click();
  await expect(page.getByRole('region', { name: /Push-ups/ })).toBeVisible();
  await page.getByRole('button', { name: 'Show all sets', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Set status: completed', exact: true })).toHaveCount(1);
  await expect(page.getByRole('button', { name: 'Set status: planned', exact: true })).toHaveCount(1);
}

async function bank(page) {
  await page.getByRole('button', { name: 'Set status: planned', exact: true }).click();
  await page.getByRole('button', { name: 'Bank it.', exact: true }).click();
  await expect.poll(async () => (await snapshot(page)).isCompleted).toBe(true);
  await page.reload();
  await expect(page.getByRole('button', { name: /Resume workout/ })).toHaveCount(0);
  await page.getByRole('button', { name: 'History', exact: true }).click();
  await page.getByRole('button', { name: 'Log', exact: true }).click();
  await expect(page.locator('#view')).toContainText('Push-ups');
}

async function openData(page) {
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.locator('summary').filter({ hasText: 'Data, import, export & backup' }).click();
}

async function downloadBackup(page) {
  await openData(page);
  const downloaded = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Export JSON', exact: true }).click();
  const download = await downloaded;
  expect(download.suggestedFilename()).toBe('cadence-export.json');
  return JSON.parse(await readFile(await download.path(), 'utf8'));
}

async function chooseBackup(page, bundle) {
  await page.getByRole('button', { name: 'Import JSON', exact: true }).click();
  await page.getByLabel('Backup file').setInputFiles({ name: 'synthetic-acceptance.json',
    mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(bundle)) });
}

// Compatibility import fills absent legacy IDs. Assert the precise repair
// against this synthetic catalog; never drop identity from the comparison.
function restoredContent(bundle) {
  const expected = structuredClone(bundle);
  const ids = new Map(expected.exercises.map((exercise) => [exercise.name, exercise.id]));
  for (const session of expected.sessions) for (const exercise of session.exercises) {
    if (exercise.exerciseId == null) exercise.exerciseId = ids.get(exercise.name);
  }
  for (const milestone of expected.milestones) {
    if (milestone.exerciseId == null && milestone.exercise) milestone.exerciseId = ids.get(milestone.exercise);
  }
  return portableContent(expected);
}

function portableContent(bundle) {
  const { exportedAt, ...content } = bundle;
  return content;
}

test('[WEB-WORKOUT-REOPEN] edited work survives reload and a new tab', async ({ page, context, app }) => {
  const before = await startWorkout(page);
  await page.getByRole('button', { name: 'Set status: completed', exact: true }).click();
  await expect.poll(async () => (await sets(page))[0].status).toBe('planned');
  await page.getByRole('button', { name: 'Set status: planned', exact: true }).first().click();
  await expect.poll(async () => (await sets(page))[0].status).toBe('completed');
  await page.reload();
  await resume(page);
  expect(await snapshot(page)).toEqual(before);
  const reopened = await context.newPage();
  await page.close();
  await reopened.goto(app.url);
  await resume(reopened);
  expect(await snapshot(reopened)).toEqual(before);
});

test('[WEB-OFFLINE-RESUME] cached app resumes and banks work without a network', async ({ page, app }) => {
  const before = await startWorkout(page);
  // Cut the actual transport instead of Playwright's WebKit offline emulation
  // (which fails navigation internally). The server sends no HTTP response;
  // a direct Node request proves it is unreachable before trusting the cache.
  app.disconnect();
  await expect(fetch(app.url, { signal: AbortSignal.timeout(3000) })).rejects.toThrow();
  await page.reload();
  expect(await page.evaluate(() => !!navigator.serviceWorker.controller)).toBe(true);
  await resume(page);
  expect(await snapshot(page)).toEqual(before);
  await bank(page);
  const backup = await downloadBackup(page);
  expect(backup.sessions).toHaveLength(1);
  expect(backup.sessions[0].isCompleted).toBe(true);
  expect(backup.sessions[0].exercises[0].sets.map((set) => set.status)).toEqual(['completed', 'completed']);
});

test('[WEB-UPDATE-RESUME] adopting a real worker update preserves the open workout', async ({ page, app }) => {
  const before = await startWorkout(page);
  await page.evaluate(async () => {
    const other = await caches.open('another-project-cache');
    await other.put('sentinel', new Response('keep me'));
  });
  app.deploy();
  await page.evaluate(async () => (await navigator.serviceWorker.getRegistration()).update());
  await expect(page.locator('#update-banner')).toContainText('New version available');
  expect(await snapshot(page)).toEqual(before);
  await page.locator('#update-banner').getByRole('button', { name: 'Refresh', exact: true }).click();
  await resume(page);
  expect(await snapshot(page)).toEqual(before);
  await expect.poll(() => page.evaluate(() => caches.keys())).toEqual(
    expect.arrayContaining(['cadence-app-acceptance-b', 'another-project-cache']));
  expect(await page.evaluate(() => caches.keys())).not.toContain('cadence-app-acceptance-a');
  expect(await page.evaluate(async () => (await (await caches.open('another-project-cache')).match('sentinel')).text())).toBe('keep me');
});

test('[WEB-BACKUP-ROUNDTRIP] exported work restores in a fresh browser context', async ({ page, browser, app }) => {
  await startWorkout(page);
  await bank(page);
  const original = await downloadBackup(page);
  const fresh = await browser.newContext();
  try {
    const restored = await fresh.newPage();
    await restored.goto(app.url);
    await restored.waitForFunction(() => navigator.serviceWorker.controller !== null);
    await expect(restored.getByRole('button', { name: 'Blank session', exact: true })).toBeVisible();
    expect(await sessions(restored)).toEqual([]);
    await openData(restored);
    await chooseBackup(restored, original);
    await restored.getByRole('dialog', { name: 'Restore this backup?', exact: true }).getByRole('button', { name: 'Restore', exact: true }).click();
    await expect.poll(async () => (await sessions(restored)).length).toBe(1);
    await restored.reload();
    const roundtrip = await downloadBackup(restored);
    expect(portableContent(roundtrip)).toEqual(restoredContent(original));
    await chooseBackup(restored, roundtrip);
    await expect(restored.locator('#toast')).toContainText('Nothing to restore');
    await expect(restored.getByRole('dialog', { name: 'Restore this backup?', exact: true })).toHaveCount(0);
  } finally { await fresh.close(); }
});

test('[WEB-RESTORE-CONTENT] same counts with different reps require confirmation', async ({ page, app }) => {
  await startWorkout(page);
  await bank(page);
  const original = await downloadBackup(page);
  const changed = structuredClone(original);
  changed.sessions[0].exercises[0].sets[0].reps += 2;
  await chooseBackup(page, changed);
  const confirmation = page.getByRole('dialog', { name: 'Restore this backup?', exact: true });
  await expect(confirmation).toContainText('Recorded values or settings differ');
  await confirmation.getByRole('button', { name: 'Cancel', exact: true }).click();
  await page.reload();
  expect(portableContent(await downloadBackup(page))).toEqual(portableContent(original));
  await chooseBackup(page, changed);
  await confirmation.getByRole('button', { name: 'Restore', exact: true }).click();
  await expect.poll(async () => (await sets(page))[0].reps).toBe(changed.sessions[0].exercises[0].sets[0].reps);
  await page.reload();
  expect(portableContent(await downloadBackup(page))).toEqual(restoredContent(changed));
});
