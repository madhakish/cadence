// Exercise the production worker, both inspection renderers, and mixed-unit readouts.
import { test, expect } from '@playwright/test';
import { openFirstInstall } from './first-install.mjs';
import { startServer } from './server.mjs';

async function show(page, inspected) {
  await page.evaluate(async inspected => {
    const C = await import('./js/core.js');
    const B = await import('./js/barbell.js');
    const load = C.enteredPlateSolution(C.BARS.bar45lb, [
      { plate: { value: 20, unit: 'kg' }, count: 1 }, { plate: { value: 1.125, unit: 'lb' }, count: 2 },
    ], 5);
    const opts = { plateTheme: 'ipfCalibratedGloss', plateStyle: 'steel' };
    const previous = document.querySelector('.barbell-stage');
    previous?.dispose?.();
    const stage = B.barbellStage(B.barbellSVG(load, 'full', 'steel', opts), { emphasis: inspected ? 'expanded' : 'standard' });
    document.querySelector('main').replaceChildren(stage, B.loadoutSummary(null, load, opts));
  }, inspected);
}

test('Astra platform, photographic faces and exact stack survive an offline inspection', async ({ page, browserName }, info) => {
  const server = await startServer();
  try {
    await openFirstInstall(page, server.url);
    server.disconnect();
    await page.reload();
    await show(page, false);
    await expect(page.locator('.barbell-platform')).toHaveAttribute('href', /platform-walnut.webp$/);
    await expect(page.locator('.barbell-plate-face')).toHaveCount(6);
    await expect(page.locator('.barbell-plate-face').first()).toHaveAttribute('href', /gloss.png$/);
    await page.locator('.barbell-stage').screenshot({ path: info.outputPath('astra-inline.png') });
    const hasGL = await page.evaluate(() => Boolean(document.createElement('canvas').getContext('webgl2')));
    await show(page, true);
    const stage = page.locator('.barbell-stage');
    if (hasGL) {
      await expect(stage.locator('canvas')).toBeVisible();
      await expect.poll(() => page.evaluate(() => performance.getEntriesByType('resource').some(e => e.name.endsWith('chrome-roughness.png')))).toBe(true);
      await stage.screenshot({ path: info.outputPath('astra-live-assembled.png') });
      await stage.getByRole('button', { name: /Explode plates/ }).click();
      await expect(stage.locator('.barbell-disc-caption').first()).toBeVisible();
      await expect(stage.locator('.barbell-disc-caption')).toHaveText(['20 kg', '1.125 lb', '1.125 lb']);
      await stage.screenshot({ path: info.outputPath('astra-live-exploded.png') });
      await page.evaluate(() => document.querySelector('.barbell-gl').getContext('webgl2').getExtension('WEBGL_lose_context').loseContext());
      await expect(stage.locator('svg.realistic')).toBeVisible();
      await expect(stage.locator('svg.realistic')).toHaveAttribute('data-exploded', 'true');
    } else {
      test.info().annotations.push({type: 'renderer', description: browserName + ' exposes SVG only'});
      await stage.getByRole('button', { name: /Explode plates/ }).click();
    }
    await expect(stage.locator('.barbell-disc-caption')).toHaveText(['20 kg', '1.125 lb', '1.125 lb']);
    await stage.screenshot({ path: info.outputPath('astra-svg-exploded.png') });
    expect(await page.evaluate(async () => {
      const keys = await (await caches.open((await caches.keys()).find(key => key.startsWith('cadence-app-')))).keys();
      return keys.map(x => x.url).filter(url => url.includes('/assets/plates/')).length;
    })).toBe(0);
  } finally { await server.close(); }
});
