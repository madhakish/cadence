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
// Cache Storage is keyed by ORIGIN, not by scope. `caches.keys()` therefore
// returns every cache on github.io/<account> — including the relocated app's and
// any other project published under the same account. So this worker deletes
// only the legacy root shells it is retiring: `cadence-<build>`, explicitly
// excluding the `cadence-app-` prefix that web/app/sw.js owns.
//
// The exclusion is not theoretical. `/cadence/app/` sits inside this worker's
// `/cadence/` scope, so the first visit to the relocated app is itself a
// navigation that can trigger this worker's update check — activating it after
// the app worker has already populated its cache. Deleting indiscriminately
// there would wipe the new offline shell on the way out.
const LEGACY_PREFIX = "cadence-";
const APP_PREFIX = "cadence-app-";
const isRetiredShell = (key) => key.startsWith(LEGACY_PREFIX) && !key.startsWith(APP_PREFIX);

self.addEventListener("install", () => self.skipWaiting());

// This worker deliberately does NOT redirect anyone. An earlier version walked
// `clients.matchAll()` and called `client.navigate("app/")` to move stranded
// windows itself. Two problems, in order of importance:
//
//  1. It could not be shown to work. In a browser test it never fired — with or
//     without `includeUncontrolled` — because `navigate()` requires the window
//     to be controlled by *this* worker, and an activating replacement worker's
//     relationship to the previous worker's clients is subtle enough that the
//     behaviour was unverifiable rather than merely fiddly.
//  2. `Client` exposes no display mode, so it could not tell an installed launch
//     from an ordinary browser tab. Anyone who had ever opened the old web app
//     in a tab got yanked off the product site into the logbook.
//
// So the hand-off lives in `web/index.html` instead, as a `display-mode:
// standalone` check: plainly verifiable, and it redirects only real installs.
// The cost is that an install launching the old URL sees its cached old shell
// for that one session and lands in the app from the next launch, once the fresh
// index.html is served. That is a strictly better failure mode than a redirect
// that fires on the wrong windows and cannot be demonstrated to fire on the
// right ones.
self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(isRetiredShell).map((key) => caches.delete(key)));
    await self.registration.unregister();
  })());
});

// No fetch handler on purpose: with none registered, the browser goes straight
// to the network and this worker cannot serve a stale response on its way out.
