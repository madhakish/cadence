import { test, expect } from '@playwright/test';
import { startServer } from './server.mjs';

test('[WEB-EXERCISE-FAVORITES] saved shortcuts survive reopen and select through the shared picker', async ({ page }, info) => {
  const server = await startServer();
  const errors = []; page.on('pageerror', (e) => errors.push(e.message));
  try {
    await page.goto(server.url);
    await expect.poll(() => page.evaluate(() => !!navigator.serviceWorker.controller
      && performance.getEntriesByType('navigation')[0]?.type === 'reload').catch(() => false)).toBe(true);
    const openLibrary = async () => {
      await page.getByRole('button', { name: 'Settings', exact: true }).click();
      await page.locator('summary').filter({ hasText: 'Programming & library' }).click();
      await page.getByText('Exercise library', { exact: true }).click();
      await expect(page.getByRole('searchbox', { name: 'Search exercises' })).toBeVisible();
    };
    await openLibrary();
    const browser = page.locator('.exercise-browser');
    const favorites = browser.getByRole('region', { name: 'Favorites' });
    await expect(favorites).toContainText('Star a lift');
    await browser.getByRole('searchbox').fill('Back Squat');
    const star = browser.getByRole('button', { name: 'Add Back Squat to Favorites', exact: true });
    await star.focus(); await star.press('Enter');
    await expect(favorites).toContainText('Back Squat');
    await expect(browser.getByRole('button', { name: 'Remove Back Squat from Favorites', exact: true }).last()).toBeFocused();
    await browser.getByRole('combobox', { name: 'Movement', exact: true }).selectOption('squat');
    await browser.getByRole('combobox', { name: 'Equipment', exact: true }).selectOption('barbell');
    await expect(favorites).toContainText('Back Squat');
    for (const width of [390, 1280]) {
      await page.setViewportSize({ width, height: width === 390 ? 844 : 800 });
      const path = info.outputPath(`favorites-filtered-${width}.png`);
      await page.screenshot({ path }); await info.attach(`favorites-${width}`, { path, contentType: 'image/png' });
    }
    await browser.getByRole('combobox', { name: 'Equipment', exact: true }).selectOption('dumbbell');
    await expect(browser).toContainText('No exercises match');
    await browser.getByRole('button', { name: 'Clear filters', exact: true }).click();
    await expect(favorites).toContainText('Back Squat');
    await page.reload(); await openLibrary();
    await expect(favorites).toContainText('Back Squat');
    await page.getByRole('button', { name: '‹ Back', exact: true }).click();
    await page.getByRole('button', { name: 'Today', exact: true }).click();
    await page.getByRole('button', { name: 'Blank session', exact: true }).click();
    await page.getByRole('button', { name: '+ Add exercise', exact: true }).click();
    const picker = page.locator('.exercise-browser');
    await expect(picker.getByRole('region', { name: 'Favorites' })).toContainText('Back Squat');
    await picker.getByRole('button', { name: 'Back Squat', exact: true }).click();
    await expect(picker).toHaveCount(0);
    await expect.poll(() => page.evaluate(async () => {
      const db = await import('./js/db.js');
      return (await db.Sessions.all())[0]?.exercises[0]?.exerciseName;
    })).toBe('Back Squat');
    expect(errors).toEqual([]);
  } finally { await server.close(); }
});
