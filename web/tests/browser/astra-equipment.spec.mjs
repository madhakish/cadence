// Exercise the production worker, the assembled and exploded photography, and mixed-unit readouts.
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

test('[WEB-ASTRA-EQUIPMENT] Astra platform, photographic faces and exact stack survive an offline inspection', async ({ page }, info) => {
  const server = await startServer();
  try {
    await openFirstInstall(page, server.url);
    server.disconnect();
    await page.reload();
    await expect(page.getByRole('button', { name: 'Blank session', exact: true })).toBeVisible();
    await show(page, false);
    const stage = page.locator('.barbell-stage');
    await expect(stage.locator('.barbell-platform')).toHaveAttribute('href', /AstraPhotoStageWalnut\.jpg$/);
    await expect(stage.locator('.barbell-plate-face')).toHaveCount(6);
    await expect(stage.locator('.barbell-plate-face').first()).toHaveAttribute('href', /PhotoFaceGloss\.png$/);
    const decodeScene = async () => {
      expect(await stage.locator('svg.realistic image').evaluateAll(async nodes => {
        const urls = new Set(nodes.map(n => n.getAttribute('href')));
        await Promise.all([...urls].map(async url => {
          const image = new Image(); image.src = url; await image.decode();
          if (!image.naturalWidth || !url.includes('/assets/photo/')) throw Error(url);
        }));
        return urls.size;
      })).toBeGreaterThan(6);
    };
    await decodeScene();
    await stage.screenshot({ path: info.outputPath('astra-inline.png') });
    await show(page, true);
    await expect(stage.locator('canvas')).toHaveCount(0);
    await expect(stage.locator('svg.realistic .barbell-plate-face')).toHaveCount(6);
    await decodeScene();
    await stage.screenshot({ path: info.outputPath('astra-assembled.png') });
    await stage.getByRole('button', { name: /Explode plates/ }).click();
    await expect(stage.locator('svg.realistic')).toHaveAttribute('data-exploded', 'true');
    await expect(stage.locator('svg.realistic .barbell-plate-face')).toHaveCount(3);
    await expect(stage.locator('.barbell-disc-caption')).toHaveText(['20 kg', '1.125 lb', '1.125 lb']);
    await decodeScene();
    await stage.screenshot({ path: info.outputPath('astra-exploded.png') });
    await stage.getByRole('button', { name: /Assemble stack/ }).click();
    await expect(stage.locator('svg.realistic .barbell-plate-face')).toHaveCount(6);
    expect(await page.evaluate(async () => {
      const keys = await (await caches.open((await caches.keys()).find(key => key.startsWith('cadence-app-')))).keys();
      return keys.map(x => x.url).filter(url => url.includes('/assets/plates/')).length;
    })).toBe(0);
  } finally { await server.close(); }
});
