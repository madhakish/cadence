import { test, expect } from '@playwright/test';
import { startServer } from './server.mjs';

test('[WEB-PLATE-LABELS] exact denominations survive final layout and inspection', async ({ page }, info) => {
  const server = await startServer();
  try {
    // Isolate the production renderer and stylesheet, without an app/worker
    // reload replacing the fixture during the measurements.
    await page.goto(server.url + 'renderer-fixture');
    await page.setContent('<link rel="stylesheet" href="./styles.css"><main style="margin:24px"></main>');
    await page.evaluate(async () => {
      const C = await import('./js/core.js');
      const B = await import('./js/barbell.js');
      const solve = (target, bar, plates, collars = 0, policy = 'closest') => C.solve(target, bar, plates, 10, collars, policy);
      const fixtures = {
        F1: solve(C.lbFromKg(100), C.BARS.bar20kg, C.STANDARD_KG),
        F2: solve(225, C.BARS.bar45lb, C.STANDARD_LB),
        F3: solve(139, C.BARS.bar45lb, C.STANDARD_KG),
        F4: solve(C.lbFromKg(22.5), C.BARS.bar20kg, C.STANDARD_KG),
        F5: C.enteredPlateSolution(C.BARS.bar45lb, [45, 10, 25, 2.5].map(value => ({ plate: { value, unit: 'lb' }, count: 1 }))),
        F6: solve(200, C.BARS.bar45lb, [{ value: 45, unit: 'lb' }], 0, 'exact'),
        F7: solve(195, C.BARS.bar45lb, C.STANDARD_LB),
        F8: solve(50, C.BARS.bar45lb, C.STANDARD_LB, 5),
      };
      window.renderFixture = (id, inspection = false) => {
        const solution = fixtures[id];
        const style = id === 'F7' ? 'bumper' : 'steel';
        const rendered = B.barbellSVG(solution, 'full', style);
        document.querySelector('main').replaceChildren(
          B.barbellStage(rendered, { onExpand: () => {}, emphasis: inspection ? 'expanded' : 'standard' }),
          B.loadoutSummary(solution.targetLb ?? null, solution, { plateStyle: style }));
        return solution.perSide.flatMap(c => Array(c.count).fill(C.plateLabel(c.plate)));
      };
    });
    for (const width of [390, 1280]) {
      await page.setViewportSize({ width, height: width === 390 ? 844 : 800 });
      for (const id of ['F1', 'F2', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8']) {
        const expected = await page.evaluate(id => window.renderFixture(id), id);
        const labels = page.locator('.barbell-plate-denomination');
        await expect(labels).toHaveText(expected);
        if (id === 'F3') expect(expected).toEqual(['20 kg', '1.25 kg']);
        if (id === 'F5') {
          expect(expected).toEqual(['45 lb', '10 lb', '25 lb', '2.5 lb']);
          await expect(page.locator('.loadout-line strong')).toHaveText('45 lb + 10 lb + 25 lb + 2.5 lb / side');
        }
        expect(await labels.evaluateAll(items => items.every(e => parseFloat(getComputedStyle(e).fontSize) >= 14))).toBe(true);
        // Check the final transform, not the nominal SVG font-size attribute.
        const stamps = await page.locator('.barbell-plate-label').evaluateAll(items => items.map(e => {
          const m = e.getScreenCTM();
          return { visible: getComputedStyle(e).display !== 'none', size: parseFloat(getComputedStyle(e).fontSize) * Math.hypot(m.a, m.b) };
        }));
        expect(stamps.every(s => !s.visible || s.size >= 12 - 1e-6)).toBe(true);
        if (id === 'F3' && width === 390) expect(stamps.every(s => !s.visible)).toBe(true);
        if (id === 'F3' && width === 1280) {
          expect(stamps.every(s => s.visible)).toBe(true);
          await expect(page.locator('.barbell-plate-label')).toHaveText(['1.25 kg', '20 kg', '20 kg', '1.25 kg']);
        }
        await expect(page.locator('.weight-unit')).toHaveText(['lb', 'kg']);
        const measures = await page.locator('.weight-measure').evaluateAll(items => items.map(e => {
          const r = e.getBoundingClientRect();
          return { x: r.x, right: r.right, y: r.y, bottom: r.bottom, fits: e.scrollWidth <= e.clientWidth + 1 };
        }));
        expect(measures.every(m => m.x >= 0 && m.right <= width && m.fits)).toBe(true);
        expect(measures[0].right <= measures[1].x + 1 || measures[0].bottom <= measures[1].y + 1).toBe(true);
        const shot = info.outputPath(`${id}-${width}.png`);
        await page.screenshot({ path: shot, fullPage: true });
        await info.attach(`${id}-${width}`, { path: shot, contentType: 'image/png' });
      }
    }
    // A narrow exploded fallback scrolls at natural scale, so the stamp is
    // readable even though the track itself is still only phone width.
    await page.setViewportSize({ width: 390, height: 900 });
    await page.evaluate(() => { window.WebGL2RenderingContext = undefined; window.renderFixture('F3', true); });
    await page.getByRole('button', { name: /Explode plates/ }).click();
    await expect(page.locator('.barbell-plate-label').first()).toBeVisible();
    expect(await page.locator('.barbell-plate-label').evaluateAll(items => items.every(e => {
      const m = e.getScreenCTM();
      return parseFloat(getComputedStyle(e).fontSize) * Math.hypot(m.a, m.b) >= 12;
    }))).toBe(true);
  } finally { await server.close(); }
});
