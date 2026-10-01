import { test, expect } from '@playwright/test';
import { startServer } from './server.mjs';

const openLibrary = async (page) => {
  await page.getByRole('button', { name: 'Settings', exact: true }).click();
  await page.locator('summary').filter({ hasText: 'Programming & library' }).click();
  await page.getByText('Exercise library', { exact: true }).click();
  await expect(page.getByRole('searchbox', { name: 'Search exercises' })).toBeVisible();
};
const geometry = (page) => page.locator('.library-group > summary').evaluateAll((rows) =>
  rows.map((row) => {
    const { x, y, width, height } = row.getBoundingClientRect();
    // Ignore subpixel floating-point representation, not visible movement.
    const pixel = (value) => Math.round(value * 1000) / 1000;
    return { x: pixel(x), y: pixel(y), width: pixel(width), height: pixel(height) };
  }));
const decoded = (page) => page.locator('.library-group .equipment-context').evaluateAll(async (images) => {
  await Promise.all(images.map((image) => image.decode()));
  return images.map((image) => ({ width: image.naturalWidth, height: image.naturalHeight, alt: image.alt }));
});

test('[WEB-EQUIPMENT-CONTEXT] category artwork reserves geometry during decode and works offline', async ({ page, browser }) => {
  const server = await startServer();
  const slow = await browser.newContext({ serviceWorkers: 'block', viewport: { width: 375, height: 812 } });
  let releaseImages;
  const imagesReady = new Promise((resolve) => { releaseImages = resolve; });
  try {
    const delayed = await slow.newPage();
    await delayed.goto(server.url);
    await delayed.route('**/assets/equipment-context/*.png', async (route) => {
      await imagesReady; await route.continue();
    });
    await openLibrary(delayed);
    await expect(delayed.locator('.library-group .equipment-context')).toHaveCount(3);
    // Measure decode independently of the actual sheet's entrance transition.
    // Requests remain blocked while its authored navigation animation finishes.
    await delayed.locator('#overlays > .overlay').last().evaluate(async (overlay) => {
      await Promise.all(overlay.getAnimations({ subtree: true }).map((animation) => animation.finished));
    });
    const before = await geometry(delayed);
    expect(await delayed.locator('.equipment-context').evaluateAll((images) => images.every((image) => !image.complete))).toBe(true);
    releaseImages();
    expect(await decoded(delayed)).toEqual(Array.from({ length: 3 }, () => ({ width: 768, height: 512, alt: '' })));
    expect(await geometry(delayed)).toEqual(before);
    await delayed.emulateMedia({ reducedMotion: 'reduce' });
    for (const width of [320, 430, 1280]) {
      await delayed.setViewportSize({ width, height: 844 });
      for (const zoom of [1, 2]) {
        await delayed.evaluate((value) => { document.documentElement.style.zoom = String(value); }, zoom);
        const rows = delayed.locator('.library-group > summary');
        expect(await rows.evaluateAll((items) => items.every((row) => row.scrollWidth <= row.clientWidth + 1))).toBe(true);
        await expect(delayed.getByRole('searchbox', { name: 'Search exercises' })).toBeVisible();
      }
    }

    // The normal worker must fetch these assets before any category is opened.
    await page.goto(server.url);
    await expect.poll(() => page.evaluate(() => !!navigator.serviceWorker.controller
      && performance.getEntriesByType('navigation')[0]?.type === 'reload').catch(() => false)).toBe(true);
    server.disconnect();
    await page.reload();
    await openLibrary(page);
    expect(await decoded(page)).toEqual(Array.from({ length: 3 }, () => ({ width: 768, height: 512, alt: '' })));
    await page.getByRole('searchbox', { name: 'Search exercises' }).fill('Back Squat');
    const lift = page.locator('.library-open').filter({ has: page.getByText('Back Squat', { exact: true }) });
    await expect(lift).toBeVisible(); await lift.click();
    const detail = page.getByRole('dialog', { name: 'Back Squat', exact: true });
    await expect(detail).toBeVisible();
    await expect(detail.locator('.exercise-info-hero h2')).toHaveText('Back Squat');
  } finally { releaseImages(); await slow.close(); await server.close(); }
});
