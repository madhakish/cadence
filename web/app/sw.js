// Offline app shell. Cache-first for same-origin GET; network falls back to
// cache so the app opens with no signal (gym basements).
//
// CACHE includes a build token that the Pages deploy stamps with the commit
// SHA (see .github/workflows/pages.yml). That makes THIS file change on every
// release, which is what causes the browser to install the new worker, refresh
// the cached assets, and drop the old cache — i.e. how updates actually reach
// an installed phone.
// Cache Storage is keyed by ORIGIN, not by scope: every project published under
// this github.io account shares one namespace. So this worker owns exactly the
// `cadence-app-` prefix and never deletes a key outside it. The legacy
// `cadence-<build>` shells from when the app was served at the Pages root belong
// to web/sw.js, which retires them.
const CACHE_PREFIX = "cadence-app-";
const CACHE = `${CACHE_PREFIX}__BUILD__`;
const ownedByThisWorker = (key) => key.startsWith(CACHE_PREFIX);
const ASSETS = [
  "js/equipment-context.js",
  "assets/equipment-context/accessory.png",
  "assets/equipment-context/conditioning.png",
  "./", "index.html", "styles.css", "manifest.webmanifest",
  "js/app.js", "js/core.js", "js/db.js", "js/seed.js", "js/templates.js", "js/programming-defaults.js", "js/program-file.js", "js/program-equipment.js", "js/anatomy.js", "js/ui.js", "js/charts.js", "js/constants.js", "js/barbell.js", "js/barbell-scene.js", "js/plate-theme.js", "js/barbell-inspector.js", "js/barbell-gl.js", "js/coaching-adapter.js", "js/workout-clock.js", "js/gym-tag.js", "js/hold-timer.js",
  "js/views/home.js", "js/views/program.js", "js/views/history.js", "js/views/activity.js", "js/views/body.js",
  "js/views/signals.js", "js/views/settings.js", "js/views/session.js", "js/views/plates.js",
  "js/tfh.js", "js/views/tfh.js",
  "js/plate-art.js",
  "assets/astra/main-context.jpg",
  "assets/astra/dumbbell.png",
  "assets/astra/room.jpg",
  "assets/astra/room-band.webp",
  "assets/astra/sleeve.png",
  "assets/astra/chrome-roughness.png",
  "assets/astra/hub.png",
  "assets/astra/rubber.png",
  "assets/astra/black-rubber.png",
  "assets/astra/powder.png",
  "assets/astra/gloss.png",
  "assets/astra/cast-iron.png",
  "assets/astra/machined.png",
  "assets/astra/hammertone.png",
  "assets/astra/platform-oak.webp",
  "assets/astra/platform-walnut.webp",
  "assets/astra/platform-white-oak.webp",
  "assets/astra/platform-maple.webp",
  "assets/astra/bumper-10lb.png",
  "assets/astra/bumper-25lb.png",
  "assets/astra/bumper-35lb.png",
  "assets/astra/bumper-45lb.png",
  "assets/astra/bumper-55lb.png",
  "assets/vitruvian-front.jpeg", "assets/vitruvian-back.jpeg",
  "assets/vitruvian-front-traps.svg", "assets/vitruvian-front-delts.svg", "assets/vitruvian-front-chest.svg",
  "assets/vitruvian-front-biceps.svg", "assets/vitruvian-front-forearms.svg", "assets/vitruvian-front-obliques.svg",
  "assets/vitruvian-front-abs.svg", "assets/vitruvian-front-quads.svg", "assets/vitruvian-front-adductors.svg",
  "assets/vitruvian-back-traps.svg", "assets/vitruvian-back-delts.svg", "assets/vitruvian-back-lats.svg",
  "assets/vitruvian-back-triceps.svg", "assets/vitruvian-back-lowerback.svg", "assets/vitruvian-back-forearms.svg",
  "assets/vitruvian-back-glutes.svg", "assets/vitruvian-back-hamstrings.svg", "assets/vitruvian-back-calves.svg",
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
    caches.keys()
      .then((keys) => Promise.all(keys
        .filter((k) => ownedByThisWorker(k) && k !== CACHE)
        .map((k) => caches.delete(k))))
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
  // Read only this worker's own cache: a bare caches.match searches every cache
  // on the shared github.io origin, so another project could otherwise plant an
  // entry this app would serve. [INV-WEB-CACHE-OWNERSHIP]
  const own = caches.open(CACHE);
  e.respondWith(
    own.then((c) => c.match(req)).then((hit) => hit || fetch(req).then((res) => {
      // Cache only successful same-origin responses, never a 404 or an error page.
      if (res.ok && res.type === "basic") {
        const copy = res.clone();
        own.then((c) => c.put(req, copy)).catch(() => {});
      }
      return res;
    }).catch(() => own.then((c) => c.match("index.html"))))
  );
});
