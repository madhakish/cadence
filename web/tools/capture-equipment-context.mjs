// Compare actual pre-art/current applications using the same synthetic export.
// No asset suppression, mocked UI, production store or athlete data.
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
import { chromium, expect } from '@playwright/test';
import { startServer } from '../tests/browser/server.mjs';

const [fixture, output, sourceSHA, directory, phase] = process.argv.slice(2);
if (!fixture || !output || !/^[a-f0-9]{40}$/.test(sourceSHA || '') || !['before', 'after'].includes(phase)) {
  throw new Error('Usage: capture-equipment-context.mjs fixture.json output source-SHA web-root before|after');
}
const bytes = await readFile(fixture);
const bundle = JSON.parse(bytes);
const server = await startServer({ directory });
const browser = await chromium.launch();
const captures = [];
try {
  await mkdir(output, { recursive: true });
  for (const width of [390, 1280]) {
    const height = width === 390 ? 844 : 800;
    const context = await browser.newContext({ viewport: { width, height }, serviceWorkers: 'allow' });
    const page = await context.newPage();
    const errors = []; page.on('pageerror', (error) => errors.push(error.message));
    await page.goto(server.url);
    await expect.poll(() => page.evaluate(() => !!navigator.serviceWorker.controller
      && performance.getEntriesByType('navigation')[0]?.type === 'reload').catch(() => false),
    { timeout: 30_000 }).toBe(true);
    await page.evaluate(async (data) => {
      const db = await import('./js/db.js'); const ui = await import('./js/ui.js');
      db.validateBackup(data); await db.importBundle(data);
      ui.prefs.unitDisplay = data.settings.unitDisplay; ui.applyTheme(data.settings.theme);
      (await import('./js/views/settings.js')).exerciseLibrary(await db.Exercises.all());
    }, bundle);
    const top = () => page.locator('#overlays > .overlay').last();
    const close = async () => top().getByRole('button', { name: '‹ Back', exact: true }).click();
    const shot = async (surface) => {
      await page.evaluate(async () => {
        await Promise.all(document.getAnimations().map((animation) => animation.finished));
        await Promise.all([...document.querySelectorAll('.equipment-context')].map((image) => image.decode()));
      });
      const file = `${phase}-equipment-${surface}-${width}.png`;
      await page.screenshot({ path: join(output, file) });
      captures.push({ surface, width, height, file, imageCount: await page.locator('.equipment-context').count() });
    };
    await expect(top().locator('.library-group > summary')).toHaveCount(3);
    await top().locator('.library-group > summary').last().scrollIntoViewIfNeeded();
    await expect.poll(() => top().locator('.library-group > summary').evaluateAll((rows) => rows.every((row) => {
      const r = row.getBoundingClientRect(); return r.top >= 64 && r.bottom <= innerHeight;
    }))).toBe(true);
    await expect(top().locator('.equipment-context')).toHaveCount(phase === 'after' ? 3 : 0);
    await shot('categories'); await close();

    await page.evaluate(async () => {
      const db = await import('./js/db.js');
      const { id, ...template } = (await db.Exercises.all()).find((e) => e.category === 'Accessory');
      const exercise = { ...template, name: 'Synthetic unlogged accessory', favorite: false };
      await db.Exercises.save(exercise);
      (await import('./js/views/settings.js')).exerciseDetail(await db.Exercises.byName(exercise.name));
    });
    await top().locator('summary').filter({ hasText: 'Previous performance & programming' }).click();
    const empty = top().locator('.set-history-row').filter({ hasText: 'No sessions yet.' });
    await expect(empty).toBeVisible(); await empty.scrollIntoViewIfNeeded();
    await expect(top().locator('.equipment-context')).toHaveCount(phase === 'after' ? 1 : 0);
    await shot('exercise-empty'); await close();

    await page.evaluate(async () => {
      const db = await import('./js/db.js');
      for (const program of await db.Programs.all()) await db.Programs.del(program.id);
      await (await import('./js/ui.js')).nav.go('program');
    });
    const emptyProgram = page.locator('#view .empty');
    await expect(emptyProgram).toContainText('Start blank, use a template, or import a Cadence program file.');
    if (phase === 'after') await expect(emptyProgram.locator('h2')).toHaveText('No program');
    else await expect(emptyProgram.locator('h2')).toHaveCount(0);
    await expect(page.locator('#view .equipment-context')).toHaveCount(phase === 'after' ? 1 : 0);
    await shot('program-empty');
    expect(errors).toEqual([]);
    await context.close();
  }
  await writeFile(join(output, 'provenance.json'), JSON.stringify({ sourceSHA, phase,
    fixtureSHA256: createHash('sha256').update(bytes).digest('hex'),
    fixture: 'Unchanged c3200 DEBUG in-memory export. Private browser origins only.',
    stateChanges: ['Create the same synthetic unlogged accessory via Exercises.save',
      'Remove all programs via Programs.del in the disposable browser database'], captures,
  }, null, 2) + '\n');
} finally { await browser.close(); await server.close(); }
