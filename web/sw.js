// Offline app shell. Cache-first for same-origin GET; network falls back to
// cache so the app opens with no signal (gym basements).
//
// CACHE includes a build token that the Pages deploy stamps with the commit
// SHA (see .github/workflows/pages.yml). That makes THIS file change on every
// release, which is what causes the browser to install the new worker, refresh
// the cached assets, and drop the old cache — i.e. how updates actually reach
// an installed phone.
const CACHE = "comeback-__BUILD__";
const ASSETS = [
  "./", "index.html", "styles.css", "manifest.webmanifest",
  "js/app.js", "js/core.js", "js/db.js", "js/seed.js", "js/ui.js", "js/charts.js", "js/constants.js",
  "js/views/home.js", "js/views/history.js", "js/views/body.js",
  "js/views/signals.js", "js/views/settings.js", "js/views/session.js", "js/views/plates.js",
  "icons/icon-192.png", "icons/icon-512.png", "icons/apple-touch-icon.png",
];

self.addEventListener("install", (e) => {
  // Don't skipWaiting automatically — the new worker waits so the app can offer
  // a "refresh to update" prompt. It still activates on the next cold launch
  // once the old clients are gone.
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// The app posts this when the user taps "Refresh" on the update prompt.
self.addEventListener("message", (e) => {
  if (e.data && e.data.type === "SKIP_WAITING") self.skipWaiting();
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET" || new URL(req.url).origin !== self.location.origin) return;
  e.respondWith(
    caches.match(req).then((hit) => hit || fetch(req).then((res) => {
      const copy = res.clone();
      caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
      return res;
    }).catch(() => caches.match("index.html")))
  );
});
