// Runtime smoke test under jsdom + fake-indexeddb: seeds, renders every view,
// and drives a real session-completion flow (PR detection + track advance) and
// an export/import round trip. Run: node tests/smoke.test.mjs
import "fake-indexeddb/auto";
import { JSDOM } from "jsdom";

const dom = new JSDOM(`<!doctype html><html><body>
  <header id="topbar"><h1 id="screen-title"></h1><div id="topbar-actions"></div></header>
  <main id="view"></main><button id="fab"></button><nav id="tabbar"></nav>
  <div id="overlays"></div><div id="toast"></div></body></html>`);
global.window = dom.window;
global.document = dom.window.document;
global.FileReader = dom.window.FileReader;
global.Node = dom.window.Node;

let pass = 0, fail = 0;
const ok = (c, m) => { if (c) pass++; else { fail++; console.error("FAIL:", m); } };
const tick = () => new Promise((r) => setTimeout(r, 60));
const host = () => document.getElementById("view");

const db = await import("../js/db.js");
const home = await import("../js/views/home.js");
const history = await import("../js/views/history.js");
const body = await import("../js/views/body.js");
const signals = await import("../js/views/signals.js");
const settings = await import("../js/views/settings.js");
const session = await import("../js/views/session.js");
const plates = await import("../js/views/plates.js");

// ---- seed ----
await db.ensureSeeded();
ok((await db.Exercises.all()).length === 30, "seeded 30 exercises");
ok((await db.Sessions.completed()).length === 10, "seeded 10 sessions");
ok((await db.Tracks.all()).length === 3, "seeded 3 tracks");
await db.ensureSeeded(); // idempotent
ok((await db.Sessions.completed()).length === 10, "re-seed is a no-op");

// ---- render every tab without throwing ----
for (const [name, view] of [["home", home], ["history", history], ["body", body], ["signals", signals], ["settings", settings]]) {
  try { await view.render(host()); ok(host().childElementCount > 0, `${name} rendered`); }
  catch (e) { ok(false, `${name} threw: ${e.message}`); }
}

// exercise history charts mode (lineChart path)
await history.render(host());
const chartsBtn = [...host().querySelectorAll(".seg button")].find((b) => b.textContent === "Charts");
chartsBtn.click(); await tick();
ok(host().querySelector("svg.chart") || host().querySelector(".empty"), "history charts mode renders");

// plate calculator overlay
await plates.openPlateCalculator(); await tick();
ok(document.querySelector("#overlays .overlay"), "plate calculator opened");
document.querySelector("#overlays .overlay .overlay-head button").click(); // close
await tick();

// ---- full session flow: start Deadlift (peak 245×3×3), complete, expect PR + advance ----
const dl = (await db.Tracks.all()).find((t) => t.exerciseName === "Deadlift");
const id = await session.createSessionFromTrack(dl);
const created = await db.Sessions.get(id);
const work = created.exercises[0].sets.filter((s) => !s.isWarmup);
const warm = created.exercises[0].sets.filter((s) => s.isWarmup);
ok(warm.length === 5 && warm[0].weightLb === 45, "deadlift got a warmup ramp");
ok(work.length === 3 && work.every((s) => s.weightLb === 245 && s.reps === 3), "3 working sets at 245×3");

await session.openSession(id); await tick();
const bank = [...document.querySelectorAll("#overlays .overlay button")].find((b) => b.textContent === "Bank it.");
ok(!!bank, "Bank it. button present");
bank.click(); await tick();

const completed = (await db.Sessions.completed()).length;
ok(completed === 11, `session banked (now ${completed} completed)`);
const dlAfter = await db.Tracks.byName("Deadlift");
ok(dlAfter.nextPhase === 4, `deadlift advanced peak→deload (nextPhase=${dlAfter.nextPhase})`);
const ms = await db.Milestones.all();
ok(ms.some((m) => m.exerciseName === "Deadlift" && m.kind === "heaviestSet" && m.label.includes("245")), "245 heaviest-set milestone logged");

// ---- export / import round trip ----
const json = await db.exportJSON();
const parsed = JSON.parse(json);
ok(parsed.sessions.length === 11 && Array.isArray(parsed.milestones), "export bundle shape");
const csv = await db.exportCSV();
ok(csv.split("\n")[0].startsWith("date,exercise,set_index"), "csv header");
await db.importBundle(parsed);
ok((await db.Sessions.completed()).length === 11, "import round trip preserves sessions");

// ---- protein add reflects in today's total ----
await db.Protein.add({ date: new Date().toISOString(), grams: 45, label: "Shake" });
ok((await db.Protein.todayTotal()) >= 45, "protein logged for today");

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
