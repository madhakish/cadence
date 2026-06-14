// Offline app shell. Cache-first for same-origin GET; network falls back to
// cache so the app opens with no signal (gym basements). Bump CACHE on release.
const CACHE = "comeback-v1";
const ASSETS = [
  "./", "index.html", "styles.css", "manifest.webmanifest",
  "js/app.js", "js/core.js", "js/db.js", "js/seed.js", "js/ui.js", "js/charts.js",
  "js/views/home.js", "js/views/history.js", "js/views/body.js",
  "js/views/signals.js", "js/views/settings.js", "js/views/session.js", "js/views/plates.js",
  "icons/icon-192.png", "icons/icon-512.png", "icons/apple-touch-icon.png",
];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
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
