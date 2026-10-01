// Replay the DEBUG-only native proof export through the production importer.
// Called by visual-proof.yml after the real iPhone capture suite; all data is
// synthetic. Fixed-size screenshots cover the DP-1 matrix on both web widths.
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { chromium, expect } from '@playwright/test';
import { startServer } from '../tests/browser/server.mjs';

const [fixturePath, output, sourceSHA, directory, phase = 'after'] = process.argv.slice(2);
if (!fixturePath || !output || !/^[a-f0-9]{40}$/.test(sourceSHA || '') || !['before', 'after'].includes(phase)) {
  throw new Error('Usage: capture-design-pass.mjs native-fixture.json output-directory source-SHA [web-root] [before|after]');
}
const bundle = JSON.parse(await readFile(fixturePath, 'utf8'));
const server = await startServer(directory ? { directory } : {});
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
    if (phase === 'before') {
      await expect.poll(() => page.evaluate(() => !!navigator.serviceWorker.controller),
        { timeout: 30_000 }).toBe(true);
      await page.reload();
    }
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
      await page.screenshot({ path: join(output, `${phase}-web-${surface}-${width}.png`) });
      const scroll = await page.evaluate(() => ({ windowX: window.scrollX, windowY: window.scrollY,
        overlayY: document.querySelector('#overlays > .overlay:last-child .overlay-body')?.scrollTop ?? null }));
      captures.push({ surface, width, height, file: `${phase}-web-${surface}-${width}.png`, scroll });
    };

    await nav('home'); await shot('today');
    await page.evaluate(async () => (await import('./js/views/activity.js')).openActivityLog());
    await expect(top()).toContainText('Wood Splitting'); await shot('ad-hoc-work'); await closeTop();
    await page.evaluate(async (id) => (await import('./js/views/session.js')).openSession(id), sessionID);
    const squat = phase === 'after' ? page.locator('.exercise-card.emphasized .title-button').first()
      : top().getByRole('button', { name: 'Back Squat — muscles, history, and settings', exact: true }).first();
    await expect(squat).toBeVisible(); await shot('session');
    if (phase === 'after') {
      await top().locator('.barbell-wrap.current-loadout').first()
        .evaluate((el) => el.scrollIntoView({ block: 'start' }));
      await shot('session-plates');
    }
    await squat.click();
    await expect(top()).toContainText('Back Squat'); await shot('exercise-pane');
    if (phase === 'after') {
      await top().locator('summary').filter({ hasText: 'Previous performance & programming' }).click();
      await top().locator('summary').filter({ hasText: 'Muscles & relationship' }).click();
      await shot('exercise-pane-expanded');
      await top().locator('.anatomy-card').scrollIntoViewIfNeeded();
      await shot('exercise-anatomy');
      await top().getByRole('button', { name: 'Quads, primary muscle', exact: true }).click();
      await top().locator('.anatomy-card').scrollIntoViewIfNeeded(); await shot('exercise-anatomy-selected');
    } else {
      await expect(top().locator('svg').first()).toBeVisible(); await shot('exercise-anatomy');
      captures.push({ surface: 'exercise-anatomy-selected', supported: false,
        reason: 'The original revision has a static figure and no muscle-selection control.' });
    }
    await closeTop(); await closeTop();

    await page.evaluate(async () => (await import('./js/views/plates.js')).openPlateCalculator());
    const target = top().locator('input[inputmode="decimal"]').first();
    await target.fill('139'); await shot('plate-calculator');
    if (phase === 'after') {
      await top().locator('.barbell-expand').click();
      await expect(top().locator('.barbell-inspection-surface')).toBeVisible();
      const solid = await top().locator('canvas.barbell-gl').count() > 0;
      await shot('plate-inspection');
      await top().locator('.barbell-explode').click(); await shot('plate-inspection-exploded');
      captures.push({ width, renderer: solid ? 'WebGL solid' : 'sprite SVG fallback' });
      await closeTop();
    }
    await closeTop();

    for (const [scenario, target, unit] of [['lb-exact', '135', 'lb'], ['kg-change', '22.5', 'kg'],
      ['unreachable', '200', 'lb'], ['reverse', null, null]]) {
      await page.evaluate(async (name) => {
        const db = await import('./js/db.js'); const C = await import('./js/core.js');
        const gym = (await db.Gyms.all()).find((g) => g.isDefault);
        gym.defaultBarId = C.barId(name === 'kg-change' ? C.BARS.bar20kg : C.BARS.bar45lb);
        gym.plateToggles = (name === 'lb-exact' ? C.STANDARD_LB : name === 'unreachable'
          ? [{ value: 45, unit: 'lb' }] : C.STANDARD_KG).map((p) => ({ ...p, enabled: true }));
        gym.loadingPolicy = name === 'unreachable' ? 'exact' : 'closest';
        await db.Gyms.save(gym);
      }, scenario);
      await page.evaluate(async () => (await import('./js/views/plates.js')).openPlateCalculator());
      if (scenario === 'reverse') {
        await top().getByRole('button', { name: 'On the bar', exact: true }).click();
        await top().locator('.plate-row').filter({ hasText: '1.25 kg' }).locator('button').nth(1).click();
        await top().locator('.overlay-body').evaluate((el) => el.scrollTo(0, 0));
      } else {
        await top().locator('input[inputmode="decimal"]').first().fill(target);
        await top().getByRole('button', { name: unit, exact: true }).click();
      }
      if (scenario === 'unreachable') await expect(top()).toContainText('No available');
      await shot(`calculator-${scenario}`); await closeTop();
    }

    if (phase === 'after') {
      await page.evaluate(async () => {
        const db = await import('./js/db.js');
        (await import('./js/views/settings.js')).exerciseLibrary(await db.Exercises.all());
      });
      await expect(top().locator('.exercise-browser')).toBeVisible();
    } else {
      await nav('settings'); await page.getByText('Exercise library', { exact: true }).click();
      await expect(top()).toContainText('Back Squat');
    }
    await shot('library');
    if (phase === 'after') {
      const search = top().locator('input[type="search"]');
      const mainCategory = top().locator('.library-group summary').filter({ hasText: 'Main' }).first();
      await mainCategory.click(); await shot('library-category'); await mainCategory.click();
      await search.fill('Back Squat');
      await shot('library-search');
      await top().getByRole('button', { name: 'Add Back Squat to Favorites', exact: true }).first().click();
      await expect(top().getByRole('button', { name: 'Remove Back Squat from Favorites', exact: true }).first()).toBeVisible();
      await top().getByRole('combobox', { name: 'Movement', exact: true }).selectOption('squat');
      await top().getByRole('combobox', { name: 'Equipment', exact: true }).selectOption('barbell');
      await shot('library-composed');
      await top().getByRole('combobox', { name: 'Equipment', exact: true }).selectOption('dumbbell');
      await expect(top()).toContainText('No exercises match'); await shot('library-no-results');
      await top().getByRole('button', { name: 'Clear filters', exact: true }).click();
      await shot('library-favorites');
      if (width === 390) {
        // CSS zoom is a layout stress, not a claim of manual browser/pinch
        // zoom testing. Both edge widths also run with reduced motion.
        await page.emulateMedia({ reducedMotion: 'reduce' });
        for (const edge of [320, 430]) {
          await page.setViewportSize({ width: edge, height: 844 });
          for (const zoom of [1, 2]) {
            await page.evaluate((value) => { document.documentElement.style.zoom = String(value); }, zoom);
            const star = top().getByRole('button', { name: 'Remove Back Squat from Favorites', exact: true }).first();
            await star.scrollIntoViewIfNeeded();
            const bounds = await star.boundingBox();
            if (!bounds || bounds.width < 44 || bounds.height < 44
              || bounds.x < 0 || bounds.x + bounds.width > edge + 1) {
              throw new Error(`Favorite control clipped at ${edge}px / CSS zoom ${zoom}`);
            }
            const file = `after-web-favorites-${edge}-zoom${zoom}.png`;
            await page.screenshot({ path: join(output, file) });
            captures.push({ surface: 'library-favorites', width: edge, height: 844, file,
              cssZoom: zoom, reducedMotion: true, starBounds: bounds });
          }
        }
        await page.evaluate(() => { document.documentElement.style.zoom = ''; });
        await page.setViewportSize({ width, height });
        await page.emulateMedia({ reducedMotion: 'no-preference' });
      }
    }
    await closeTop();
    if (phase === 'after') {
      await page.evaluate(async (id) => (await import('./js/views/session.js')).openSession(id), sessionID);
      await top().getByRole('button', { name: '+ Add exercise', exact: true }).click();
      await expect(page.getByRole('dialog', { name: 'Add exercise', exact: true })
        .getByRole('region', { name: 'Favorites' })).toContainText('Back Squat');
      await shot('session-picker');
      await page.keyboard.press('Escape');
      await expect(page.getByRole('dialog', { name: 'Add exercise', exact: true })).toHaveCount(0);
      await closeTop();
    }
    await nav('settings');
    // Opening the old Library scrolls Settings to its entry near the bottom.
    // Compare the root composition at the top on both revisions.
    await page.evaluate(() => window.scrollTo({ top: 0, left: 0, behavior: 'instant' }));
    await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(0);
    await shot('settings');
    if (phase === 'after') {
      await page.locator('.settings-group summary').filter({ hasText: 'Rest & training behavior' }).click();
    }
    const rest = phase === 'after' ? page.getByRole('button', { name: /^Squat & deadlift mains:/ })
      : page.getByText('Squat & deadlift mains', { exact: true });
    await rest.scrollIntoViewIfNeeded(); await shot('settings-rest');
    if (phase === 'after') {
      await rest.click(); await expect(page.locator('.duration-editor')).toBeVisible(); await shot('duration-picker');
      await page.getByRole('dialog').last().getByRole('button', { name: 'Cancel', exact: true }).click();
    }
    await nav('history'); await page.getByRole('button', { name: 'Log', exact: true }).click();
    await expect(page.locator('#view')).toContainText('Wood Splitting'); await shot('history');
    if (phase === 'after') {
      for (const [theme, label] of [['carbon', 'Foundry'], ['memento', 'Heritage Gold'],
        ['titanium', 'Titanium'], ['slate', 'Slate'], ['system', 'System']]) {
        await nav('settings');
        const appearance = page.locator('.settings-group summary').filter({ hasText: 'Appearance & accessibility' });
        await appearance.click();
        await page.getByRole('button', { name: label, exact: true }).click();
        await expect.poll(() => page.evaluate(() => document.documentElement.dataset.theme)).toBe(theme);
        await appearance.click();
        await page.evaluate(() => window.scrollTo({ top: 0, left: 0, behavior: 'instant' }));
        await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(0);
        await shot(`app-theme-${theme}-settings`);
      }
    }
    if (errors.length) throw new Error(errors.join('\n'));
    await context.close();
  }
  await writeFile(join(output, 'provenance.json'), JSON.stringify({ sourceSHA, phase,
    fixture: 'native-fixture.json exported from the DEBUG-only in-memory VisualProofSeed',
    backupSchemaVersion: bundle.schemaVersion, captures }, null, 2) + '\n');
  console.log(`Captured ${captures.filter((c) => c.file).length} production web surfaces from the native proof fixture`);
} finally { await browser.close(); await server.close(); }
