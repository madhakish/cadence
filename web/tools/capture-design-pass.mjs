// Replay the DEBUG-only native proof export through the production importer.
// Called by visual-proof.yml after the real iPhone capture suite; all data is
// synthetic. Fixed-size screenshots cover the DP-1 matrix on both web widths.
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { chromium, expect } from '@playwright/test';
import { startServer } from '../tests/browser/server.mjs';

const [fixturePath, output, sourceSHA] = process.argv.slice(2);
if (!fixturePath || !output || !/^[a-f0-9]{40}$/.test(sourceSHA || '')) {
  throw new Error('Usage: capture-design-pass.mjs native-fixture.json output-directory source-SHA');
}
const bundle = JSON.parse(await readFile(fixturePath, 'utf8'));
const server = await startServer();
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader',
  '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
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
    const sessionID = await page.evaluate(async (data) => {
      const db = await import('./js/db.js');
      const ui = await import('./js/ui.js');
      db.validateBackup(data); await db.importBundle(data);
      ui.prefs.unitDisplay = data.settings.unitDisplay;
      ui.applyTheme(data.settings.theme);
      return (await db.Sessions.all()).find((s) => !s.isCompleted && s.programTag)?.id;
    }, bundle);
    if (sessionID == null) throw new Error('The native fixture has no open program session');
    const nav = (tab) => page.evaluate(async (name) => (await import('./js/ui.js')).nav.go(name), tab);
    const top = () => page.locator('#overlays > .overlay').last();
    const closeTop = async () => { await top().getByRole('button', { name: '‹ Back', exact: true }).click(); };
    const shot = async (surface) => {
      // Local artwork loads asynchronously into fixed geometry. Wait for its
      // decode/redraw before retaining pixels; this never changes app state.
      await page.waitForTimeout(600);
      await page.screenshot({ path: join(output, `web-${surface}-${width}.png`) });
      captures.push({ surface, width, height, file: `web-${surface}-${width}.png` });
    };

    await nav('home'); await shot('today');
    await page.evaluate(async () => (await import('./js/views/activity.js')).openActivityLog());
    await expect(top()).toContainText('Wood Splitting'); await shot('ad-hoc-work'); await closeTop();
    await page.evaluate(async (id) => (await import('./js/views/session.js')).openSession(id), sessionID);
    await expect(page.locator('.current-set-hero')).toBeVisible(); await shot('session');
    await page.locator('.exercise-card.emphasized .title-button').first().click();
    await expect(top().locator('.exercise-info-hero')).toBeVisible(); await shot('exercise-pane');
    await top().locator('summary').filter({ hasText: 'Muscles & relationship' }).click();
    await expect(top().locator('.anatomy-card')).toBeVisible();
    await top().locator('.anatomy-card').scrollIntoViewIfNeeded();
    await shot('exercise-anatomy'); await closeTop(); await closeTop();

    await page.evaluate(async () => (await import('./js/views/plates.js')).openPlateCalculator());
    const target = top().locator('input[inputmode="decimal"]').first();
    await target.fill('139'); await shot('plate-calculator');
    await top().locator('.barbell-expand').click();
    await expect(top().locator('.barbell-inspection-surface')).toBeVisible();
    const solid = await top().locator('canvas.barbell-gl').count() > 0;
    await shot('plate-inspection');
    await top().locator('.barbell-explode').click(); await shot('plate-inspection-exploded');
    captures.push({ width, renderer: solid ? 'WebGL solid' : 'sprite SVG fallback' });
    await closeTop(); await closeTop();

    await page.evaluate(async () => {
      const db = await import('./js/db.js');
      (await import('./js/views/settings.js')).exerciseLibrary(await db.Exercises.all());
    });
    await expect(top().locator('.exercise-browser')).toBeVisible(); await shot('library'); await closeTop();
    await nav('settings'); await shot('settings');
    await nav('history'); await page.getByRole('button', { name: 'Log', exact: true }).click();
    await expect(page.locator('#view')).toContainText('Wood Splitting'); await shot('history');
    if (errors.length) throw new Error(errors.join('\n'));
    await context.close();
  }
  await writeFile(join(output, 'provenance.json'), JSON.stringify({ sourceSHA,
    fixture: 'native-fixture.json exported from the DEBUG-only in-memory VisualProofSeed',
    backupSchemaVersion: bundle.schemaVersion, captures }, null, 2) + '\n');
  console.log(`Captured ${captures.filter((c) => c.file).length} production web surfaces from the native proof fixture`);
} finally { await browser.close(); await server.close(); }
