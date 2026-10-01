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
    return { x, y, width, height };
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
    await expect(page.getByRole('button', { name: 'Back Squat', exact: true })).toBeVisible();
  } finally { releaseImages(); await slow.close(); await server.close(); }
});
