// Retirement worker for the app's OLD scope.
//
// Until the product site landed, the PWA was served from the Pages root and
// registered a service worker here, at `/cadence/sw.js`, with scope
// `/cadence/`. The app now lives at `/cadence/app/` and registers
// `/cadence/app/sw.js` instead. Anyone who added the old app to their home
// screen still has the root registration, and its cache-first handler would
// keep serving them a stale app shell — or, once the cache refreshed, the
// marketing page as their app.
//
// So this file must keep existing, and must do exactly one thing: stand down.
// Browsers re-fetch a registered worker's script (bypassing the HTTP cache) on
// navigation and at least daily, so an old install picks this up on its next
// launch with signal, drops its caches, unregisters, and gets sent to the new
// URL. `web/index.html` also redirects standalone launches to `./app/` as a
// second, JS-side safety net.
//
// Do not turn this back into a caching worker, and do not delete it while any
// install might still be pointing at it: deleting it leaves the old worker in
// place forever, because there is nothing left to update it with.
self.addEventListener("install", () => self.skipWaiting());

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    // Drop everything the old app shell cached, then stop controlling clients.
    const keys = await caches.keys();
    await Promise.all(keys.map((key) => caches.delete(key)));
    await self.registration.unregister();

    // Send any window still sitting on the old scope to the app's new home.
    // Scope-relative so this works on Pages, on a custom domain, and locally.
    const scope = new URL(self.registration.scope);
    const target = new URL("app/", scope).href;
    const clients = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const client of clients) {
      const url = new URL(client.url);
      // Only the old app entry point. A window reading the site's other pages
      // is a browser tab that never wanted the app.
      const atOldRoot = url.pathname === scope.pathname ||
        url.pathname === `${scope.pathname}index.html`;
      if (atOldRoot && "navigate" in client) {
        try { await client.navigate(target); } catch (e) { /* the reload picks it up */ }
      }
    }
  })());
});

// No fetch handler on purpose: with none registered, the browser goes straight
// to the network and this worker cannot serve a stale response on its way out.
