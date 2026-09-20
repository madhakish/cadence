// Headless-Chromium captures of the web app's core surfaces at the two
// design-pass viewports (390×844 phone, 1280×800 desktop). Runs inside the
// zenika/alpine-chrome:with-puppeteer image so no browser is needed on the
// host; the app is served from this checkout by a tiny static server and the
// state is a fictional fixture built through the app's own modules — never a
// real backup.
//
// The image keeps puppeteer under /usr/src/app, so the script is copied
// beside it before it runs (ESM resolution walks up from the script's own
// directory):
//
//   podman run --rm --user 0 -v "$PWD/web":/web:ro -v "$OUT":/out \
//     --entrypoint sh docker.io/zenika/alpine-chrome:with-puppeteer -c \
//     'cp /web/tools/capture-web-proof.mjs /usr/src/app/ && node /usr/src/app/capture-web-proof.mjs /out /web'
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import puppeteer from "puppeteer";

const OUT = process.argv[2] || "/out";
const ROOT = path.resolve(process.argv[3] || path.join(path.dirname(new URL(import.meta.url).pathname), ".."));
const PORT = 8123;
const TYPES = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css",
  ".png": "image/png", ".svg": "image/svg+xml", ".json": "application/json", ".webmanifest": "application/manifest+json",
  ".woff2": "font/woff2", ".wav": "audio/wav" };
const VIEWPORTS = [
  { name: "390", width: 390, height: 844, deviceScaleFactor: 2, isMobile: true, hasTouch: true },
  { name: "1280", width: 1280, height: 800, deviceScaleFactor: 1 },
];

// Serve <checkout>/web at /cadence/ so the app sees the same mount point it
// ships under (/cadence/app/).
const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://localhost");
  let file = url.pathname.replace(/^\/cadence\/?/, "");
  if (file === "" || file.endsWith("/")) file += "index.html";
  const full = path.join(ROOT, file);
  if (!full.startsWith(ROOT) || !fs.existsSync(full) || fs.statSync(full).isDirectory()) {
    res.writeHead(404); res.end(); return;
  }
  res.writeHead(200, { "content-type": TYPES[path.extname(full)] || "application/octet-stream", "cache-control": "no-store" });
  fs.createReadStream(full).pipe(res);
});
await new Promise((resolve) => server.listen(PORT, "127.0.0.1", resolve));

const settle = (ms = 450) => new Promise((resolve) => setTimeout(resolve, ms));

// Fictional fixture state: a program on its first lower day, opened as a
// session with the warmups and first work set already done, so the focused
// lift reads "working set 2 of 3" like the native proof seed.
async function seed() {
  const db = await import("/cadence/app/js/db.js");
  const session = await import("/cadence/app/js/views/session.js");
  const cyc = (exerciseName, role, baseWeightLb, estimatedMaxLb) =>
    ({ exerciseName, role, baseWeightLb, estimatedMaxLb, stallCount: 0, lastIncrementLb: 0 });
  const acc = (exerciseName, weightLb, incrementLb = 5) =>
    ({ exerciseName, sets: 3, minReps: 8, maxReps: 12, currentReps: 8, weightLb, incrementLb, stallCount: 0 });
  await db.Programs.save({
    name: "Foundry Hypertrophy", focus: "strength", cycleNumber: 1, currentWeek: 1,
    nextDayIndex: 0, roundingLb: 5, isActive: true,
    days: [{ name: "Lower Forge", order: 0,
      lifts: [cyc("Back Squat", "main", 185, 225), cyc("Romanian Deadlift", "complementary", 155, 205)],
      accessories: [acc("Plank", 0, 0)] }],
  });
  const program = await db.Programs.active();
  const day = [...program.days].sort((a, b) => a.order - b.order)[0];
  const id = await session.createSessionFromProgramDay(program, day);
  const workout = await db.Sessions.get(id);
  const squat = workout.exercises[0];
  let workDone = 0;
  for (const set of squat.sets) {
    if (set.isWarmup) set.status = "completed";
    else if (workDone === 0) { set.status = "completed"; workDone += 1; }
  }
  await db.Sessions.save(workout);
  return id;
}

const browser = await puppeteer.launch({
  executablePath: "/usr/bin/chromium-browser",
  // Software WebGL2 (SwiftShader through ANGLE) so the 3D inspector renders
  // in the GPU-less container instead of falling back to the sprite SVG.
  args: ["--no-sandbox", "--disable-dev-shm-usage", "--font-render-hinting=none",
    "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
});
try {
  fs.mkdirSync(OUT, { recursive: true });
  for (const viewport of VIEWPORTS) {
    // Each viewport gets its own browser context (and so its own IndexedDB),
    // so the second capture set never inherits the first one's session.
    const context = await browser.createBrowserContext();
    const page = await context.newPage();
    page.on("pageerror", (error) => console.error(`[${viewport.name}] page error:`, error.message));
    await page.setViewport(viewport);
    await page.goto(`http://127.0.0.1:${PORT}/cadence/app/`, { waitUntil: "networkidle0" });
    await page.waitForSelector("#tabbar .tab");
    const sessionID = await page.evaluate(seed);
    const shot = async (name) => {
      await settle();
      await page.screenshot({ path: path.join(OUT, `web-${name}-${viewport.name}.png`), fullPage: false });
      console.log(`captured web-${name}-${viewport.name}.png`);
    };
    const nav = (tab) => page.evaluate(async (t) => { const ui = await import("/cadence/app/js/ui.js"); await ui.nav.go(t); }, tab);
    const closeTop = () => page.evaluate(() => document.querySelector("#overlays .overlay:last-child .overlay-head button")?.click());

    await nav("home"); await shot("today");
    await page.evaluate(async (id) => { const s = await import("/cadence/app/js/views/session.js"); await s.openSession(id); }, sessionID);
    await page.waitForSelector(".current-set-hero"); await shot("session");
    await page.evaluate(() => document.querySelector(".exercise-card.emphasized .title-button")?.click());
    await page.waitForSelector("#overlays .overlay:nth-child(2)"); await shot("exercise-pane");
    await closeTop(); await settle(200);
    await closeTop(); await settle(200);

    await page.evaluate(async () => { const p = await import("/cadence/app/js/views/plates.js"); await p.openPlateCalculator(); });
    await page.waitForSelector("#overlays .overlay");
    await page.evaluate(() => {
      const overlay = document.querySelector("#overlays .overlay:last-child");
      const input = overlay.querySelector('input[inputmode="decimal"], input[type="number"]');
      if (input) { input.value = "139"; input.dispatchEvent(new window.Event("input", { bubbles: true })); }
    });
    await shot("plate-calculator");
    await page.evaluate(() => document.querySelector("#overlays .overlay:last-child .barbell-expand")?.click());
    await settle(600);
    // Say which renderer the proof shows; a missing WebGL context must not
    // pass silently as a screenshot of the fallback.
    const solid = await page.evaluate(() => Boolean(document.querySelector("#overlays .overlay:last-child .barbell-stage.solid canvas.barbell-gl")));
    console.log(`[${viewport.name}] plate-inspection renderer: ${solid ? "WebGL solid" : "sprite SVG fallback"}`);
    await shot("plate-inspection");
    if (solid) {
      // Orbit by drag, switch the backdrop, and reset, like the iPhone capture.
      const box = await (await page.$("#overlays .overlay:last-child canvas.barbell-gl")).boundingBox();
      await page.mouse.move(box.x + box.width * 0.6, box.y + box.height / 2);
      await page.mouse.down();
      await page.mouse.move(box.x + box.width * 0.3, box.y + box.height * 0.35, { steps: 12 });
      await page.mouse.up();
      await settle(300);
      await shot("plate-inspection-orbit");
      await page.evaluate(() => document.querySelector("#overlays .overlay:last-child .barbell-backdrop button[data-backdrop='paper']")?.click());
      await settle(300);
      await shot("plate-inspection-paper");
      await page.evaluate(() => {
        document.querySelector("#overlays .overlay:last-child .barbell-backdrop button[data-backdrop='studio']")?.click();
        document.querySelector("#overlays .overlay:last-child .barbell-reset-view")?.click();
      });
      await settle(300);
    }
    await closeTop(); await settle(200); await closeTop(); await settle(200);

    await page.evaluate(async () => {
      const db = await import("/cadence/app/js/db.js");
      const settings = await import("/cadence/app/js/views/settings.js");
      settings.exerciseLibrary(await db.Exercises.all());
    });
    await page.waitForSelector("#overlays .overlay"); await shot("library");
    await closeTop(); await settle(200);

    await nav("settings"); await shot("settings");
    await nav("history"); await shot("history");
    await page.close();
    await context.close();
  }
} finally {
  await browser.close();
  server.close();
}
