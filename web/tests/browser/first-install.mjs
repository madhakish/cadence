import { test, expect } from '@playwright/test';

// A first install precaches the whole app shell (about 220 files, 12.6 MB),
// activates, and claims the open page; the production app answers that
// controllerchange with exactly one reload. Wait for that reload's load event,
// armed before navigating so it cannot be missed, instead of polling page state
// against the 10 s UI-assertion timeout: CI WebKit has run this pipeline past
// 10 s while the page stayed responsive (#360). 25 s still leaves the journey
// 20 s of the 45 s test timeout.
const FIRST_INSTALL_TIMEOUT = 25_000;

export async function openFirstInstall(page, url) {
  await test.step('first install reloads under the worker', async () => {
    let loads = 0;
    try {
      await Promise.all([
        page.waitForEvent('load', { predicate: () => ++loads === 2, timeout: FIRST_INSTALL_TIMEOUT }),
        page.goto(url),
      ]);
    } catch (error) {
      // Say which lifecycle stage never finished, so a failure is diagnosable.
      const worker = await page.evaluate(async () => {
        const registration = await navigator.serviceWorker.getRegistration();
        return { controlled: !!navigator.serviceWorker.controller,
          installing: registration?.installing?.state, waiting: registration?.waiting?.state,
          active: registration?.active?.state };
      }).catch((reason) => String(reason));
      throw new Error(`${error.message}\nWorker after ${loads} load(s): ${JSON.stringify(worker)}`);
    }
    expect(await page.evaluate(() =>
      performance.getEntriesByType('navigation')[0]?.type === 'reload' && !!navigator.serviceWorker.controller,
    ), 'the reloaded document is controlled by the worker').toBe(true);
  });
  await expect(page.getByRole('button', { name: 'Blank session', exact: true })).toBeVisible();
}
