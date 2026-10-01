# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: equipment-context.spec.mjs >> [WEB-EQUIPMENT-CONTEXT] category artwork reserves geometry during decode and works offline
- Location: tests/browser/equipment-context.spec.mjs:22:1

# Error details

```
Error: expect(received).toBe(expected) // Object.is equality

Expected: true
Received: false
```

# Test source

```ts
  1  | import { test, expect } from '@playwright/test';
  2  | import { startServer } from './server.mjs';
  3  |
  4  | const openLibrary = async (page) => {
  5  |   await page.getByRole('button', { name: 'Settings', exact: true }).click();
  6  |   await page.locator('summary').filter({ hasText: 'Programming & library' }).click();
  7  |   await page.getByText('Exercise library', { exact: true }).click();
  8  |   await expect(page.getByRole('searchbox', { name: 'Search exercises' })).toBeVisible();
  9  | };
  10 | const geometry = (page) => page.locator('.library-group > summary').evaluateAll((rows) =>
  11 |   rows.map((row) => {
  12 |     const { x, y, width, height } = row.getBoundingClientRect();
  13 |     // Ignore subpixel floating-point representation, not visible movement.
  14 |     const pixel = (value) => Math.round(value * 1000) / 1000;
  15 |     return { x: pixel(x), y: pixel(y), width: pixel(width), height: pixel(height) };
  16 |   }));
  17 | const decoded = (page) => page.locator('.library-group .equipment-context').evaluateAll(async (images) => {
  18 |   await Promise.all(images.map((image) => image.decode()));
  19 |   return images.map((image) => ({ width: image.naturalWidth, height: image.naturalHeight, alt: image.alt }));
  20 | });
  21 |
  22 | test('[WEB-EQUIPMENT-CONTEXT] category artwork reserves geometry during decode and works offline', async ({ page, browser }) => {
  23 |   const server = await startServer();
  24 |   const slow = await browser.newContext({ serviceWorkers: 'block', viewport: { width: 375, height: 812 } });
  25 |   let releaseImages;
  26 |   const imagesReady = new Promise((resolve) => { releaseImages = resolve; });
  27 |   try {
  28 |     const delayed = await slow.newPage();
  29 |     await delayed.goto(server.url);
  30 |     await delayed.route('**/assets/equipment-context/*.png', async (route) => {
  31 |       await imagesReady; await route.continue();
  32 |     });
  33 |     await openLibrary(delayed);
  34 |     await expect(delayed.locator('.library-group .equipment-context')).toHaveCount(3);
  35 |     // Measure decode independently of the actual sheet's entrance transition.
  36 |     // Requests remain blocked while its authored navigation animation finishes.
  37 |     await delayed.locator('#overlays > .overlay').last().evaluate(async (overlay) => {
  38 |       await Promise.all(overlay.getAnimations({ subtree: true }).map((animation) => animation.finished));
  39 |     });
  40 |     const before = await geometry(delayed);
  41 |     expect(await delayed.locator('.equipment-context').evaluateAll((images) => images.every((image) => !image.complete))).toBe(true);
  42 |     releaseImages();
  43 |     expect(await decoded(delayed)).toEqual(Array.from({ length: 3 }, () => ({ width: 768, height: 512, alt: '' })));
  44 |     expect(await geometry(delayed)).toEqual(before);
  45 |     await delayed.emulateMedia({ reducedMotion: 'reduce' });
  46 |     for (const width of [320, 430, 1280]) {
  47 |       await delayed.setViewportSize({ width, height: 844 });
  48 |       for (const zoom of [1, 2]) {
  49 |         await delayed.evaluate((value) => { document.documentElement.style.zoom = String(value); }, zoom);
  50 |         const rows = delayed.locator('.library-group > summary');
> 51 |         expect(await rows.evaluateAll((items) => items.every((row) => row.scrollWidth <= row.clientWidth + 1))).toBe(true);
     |                                                                                                                 ^ Error: expect(received).toBe(expected) // Object.is equality
  52 |         await expect(delayed.getByRole('searchbox', { name: 'Search exercises' })).toBeVisible();
  53 |       }
  54 |     }
  55 |
  56 |     // The normal worker must fetch these assets before any category is opened.
  57 |     await page.goto(server.url);
  58 |     await expect.poll(() => page.evaluate(() => !!navigator.serviceWorker.controller
  59 |       && performance.getEntriesByType('navigation')[0]?.type === 'reload').catch(() => false)).toBe(true);
  60 |     server.disconnect();
  61 |     await page.reload();
  62 |     await openLibrary(page);
  63 |     expect(await decoded(page)).toEqual(Array.from({ length: 3 }, () => ({ width: 768, height: 512, alt: '' })));
  64 |     await page.getByRole('searchbox', { name: 'Search exercises' }).fill('Back Squat');
  65 |     const lift = page.locator('.library-open').filter({ has: page.getByText('Back Squat', { exact: true }) });
  66 |     await expect(lift).toBeVisible(); await lift.click();
  67 |     const detail = page.getByRole('dialog', { name: 'Back Squat', exact: true });
  68 |     await expect(detail).toBeVisible();
  69 |     await expect(detail.locator('.exercise-info-hero h2')).toHaveText('Back Squat');
  70 |   } finally { releaseImages(); await slow.close(); await server.close(); }
  71 | });
  72 |
```
