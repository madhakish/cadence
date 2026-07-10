// Active-session logger — the core daily screen. Set entry, quality flags,
// rest timer, autoregulation, body signals, completion + PR detection.
import * as ui from "../ui.js";
import * as C from "../core.js";
import { BODY_SITES, SET_FLAGS, CATEGORIES, watchNote, COPY } from "../constants.js";
import { Sessions, Exercises, Tracks, Gyms, Milestones, Programs, Settings, iso, runAll } from "../db.js";
import { barbellSVG } from "../barbell.js";

const trackState = (t) => ({ cycleNumber: t.cycleNumber, baseWeightLb: t.baseWeightLb, nextPhase: t.nextPhase, incrementLb: t.incrementLb });
const mkSet = (order, w, r, o = {}) => ({
  order, weightLb: w, reps: r, isWarmup: !!o.warm, isPerSide: !!o.perSide, enteredUnit: "lb",
  flags: [], bodyFlagSite: null, bodyFlagNote: null, durationSeconds: null, distanceMiles: null, autoregReason: null,
});

async function defaultGymName() { const g = await Gyms.default(); return g ? g.name : null; }

export async function createSessionFromTrack(track) {
  const ex = await Exercises.byName(track.exerciseName);
  const sug = track.mode === "cycle" ? C.planFor(trackState(track)) : C.linearPlan(track.baseWeightLb);
  const sets = [];
  let order = 0;
  if (ex && ex.type === "barbell") {
    for (const w of C.warmupRamp(sug.weightLb)) sets.push(mkSet(order++, w.weightLb, w.reps, { warm: true }));
  }
  for (let i = 0; i < sug.sets; i += 1) sets.push(mkSet(order++, sug.weightLb, sug.reps, { perSide: ex && ex.isUnilateral }));
  const se = { order: 0, exerciseName: track.exerciseName, notes: "", phase: sug.phase || null, plannedWeightLb: sug.weightLb, plannedSets: sug.sets, plannedReps: sug.reps, sets };
  const id = await Sessions.save({ date: iso(new Date()), notes: "", isCompleted: false, gymName: await defaultGymName(), exercises: [se] });
  return id;
}

export async function createBlankSession() {
  return Sessions.save({ date: iso(new Date()), notes: "", isCompleted: false, gymName: await defaultGymName(), exercises: [] });
}

// ---- Rest timer ----
function makeRestTimer(onTick, onDone) {
  let endAt = 0, total = 0, handle = null;
  const stop = () => { if (handle) clearInterval(handle); handle = null; endAt = 0; onTick(); };
  return {
    get running() { return !!handle; },
    get remaining() { return Math.max(0, (endAt - Date.now()) / 1000); },
    get progress() { return total ? 1 - this.remaining / total : 0; },
    start(sec) {
      total = sec; endAt = Date.now() + sec * 1000;
      if (handle) clearInterval(handle);
      handle = setInterval(() => { if (this.remaining <= 0) { stop(); onDone(); } else onTick(); }, 250);
      onTick();
    },
    add(sec) { if (handle) { endAt += sec * 1000; total += sec; onTick(); } },
    stop,
  };
}
// One shared AudioContext — browsers cap concurrent contexts, so creating one
// per rest would silence the chime after ~6 rests in a session.
let _audioCtx = null;
function beep(haptics = true) {
  try {
    // A context torn down by the OS (state "closed") never recovers — rebuild
    // it; "interrupted" (iOS phone call/backgrounding) needs resume() too.
    if (_audioCtx && _audioCtx.state === "closed") _audioCtx = null;
    _audioCtx = _audioCtx || new (window.AudioContext || window.webkitAudioContext)();
    const ac = _audioCtx;
    if (ac.state !== "running") ac.resume().catch(() => {}); // async rejection escapes the try/catch
    const o = ac.createOscillator(), g = ac.createGain();
    o.frequency.value = 880; o.connect(g); g.connect(ac.destination);
    g.gain.setValueAtTime(0.001, ac.currentTime); g.gain.exponentialRampToValueAtTime(0.3, ac.currentTime + 0.02);
    g.gain.exponentialRampToValueAtTime(0.001, ac.currentTime + 0.5);
    o.start(); o.stop(ac.currentTime + 0.5);
  } catch { /* ignore */ }
  if (haptics && navigator.vibrate) navigator.vibrate(200);
}

const setWeightLabel = (s) => {
  if (s.weightLb === 0) return "BW";
  return s.enteredUnit === "kg" ? `${C.trim(C.kgFromLb(s.weightLb))} kg` : `${C.trim(s.weightLb)} lb`;
};

export async function openSession(id) {
  const session = await Sessions.get(id);
  if (!session) { ui.toast("Session not found."); return; }
  const exMap = new Map((await Exercises.all()).map((e) => [e.name, e]));
  const settings = await Settings.get();
  const gym = await Gyms.default();
  const save = () => Sessions.save(session);

  // Per-exercise entry/display unit + bar. Session-local. The bar is chosen
  // independently of the plate unit (most bars are 45 lb whatever you load).
  const unitByEx = {};
  const exUnit = (se) => unitByEx[se.exerciseName] || "lb";
  const barByEx = {};
  const defaultBar = gym ? C.barById(gym.defaultBarId) : C.BARS.bar45lb;
  const barFor = (se) => barByEx[se.exerciseName] || defaultBar;

  // Smart per-exercise rest (category/movement); accessories fall back to the
  // accessory setting, then 90s.
  function restFor(ex) {
    if (!ex) return 90;
    const accFallback = ex.category === "Accessory" ? (settings.accessoryRestSeconds || 0) : 0;
    return C.restDefaultSeconds(ex.category, ex.name, ex.defaultRestSeconds > 0 ? ex.defaultRestSeconds : accFallback);
  }

  const sessionStart = Date.now();            // session stopwatch origin (ephemeral)
  let currentSE = null;                       // the exercise you're actively working
  const currentExercise = () => exMap.get(((currentSE || session.exercises[0]) || {}).exerciseName);

  const rest = makeRestTimer(() => paintBar(), () => onRestDone());
  let restLabel = "";
  let barEls = null;                          // bottom-bar refs, filled after pushScreen
  function armRest(seconds, label) { if (!(seconds > 0)) return; restLabel = label || ""; rest.start(seconds); paintBar(); } // 0/none (conditioning) arms nothing
  function onRestDone() { ui.toast(restLabel ? `Rest over · ${restLabel}.` : "Rest over."); beep(settings.haptics !== false); paintBar(); }

  function paintBar() {
    if (!barEls) return;
    barEls.clock.textContent = `${ui.mmss((Date.now() - sessionStart) / 1000)} session`;
    if (rest.running) {
      barEls.restTime.textContent = ui.mmss(rest.remaining);
      barEls.restTime.style.display = "";
      barEls.restBtn.style.display = "none";
      barEls.addBtn.style.display = "";
      barEls.skipBtn.style.display = "";
      barEls.prog.style.width = `${Math.min(100, rest.progress * 100)}%`;
    } else {
      barEls.restTime.style.display = "none";
      barEls.restBtn.style.display = "";
      barEls.restBtn.textContent = `Rest ${ui.mmss(restFor(currentExercise()))}`;
      barEls.addBtn.style.display = "none";
      barEls.skipBtn.style.display = "none";
      barEls.prog.style.width = "0%";
    }
  }

  function buildBottomBar() {
    const clock = ui.h("span", { class: "clock mono" });
    const restTime = ui.h("span", { class: "rest-time mono", style: { display: "none" } });
    const restBtn = ui.h("button", { class: "btn sm primary", text: "Rest", onClick: () => { const ex = currentExercise(); armRest(restFor(ex), ex ? ex.name : ""); } });
    const addBtn = ui.h("button", { class: "btn sm", style: { display: "none" }, text: "+1:00", onClick: () => { rest.add(60); paintBar(); } });
    const skipBtn = ui.h("button", { class: "btn sm ghost", style: { display: "none" }, text: "Skip", onClick: () => { rest.stop(); paintBar(); } });
    const prog = ui.h("i");
    barEls = { clock, restTime, restBtn, addBtn, skipBtn, prog };
    return ui.h("div", { id: "session-bar" },
      ui.h("div", { class: "session-bar-row" }, clock, ui.h("div", { class: "btn-row", style: { alignItems: "center" } }, restTime, restBtn, addBtn, skipBtn)),
      ui.h("div", { class: "progress" }, prog));
  }

  function renderBody(body) {
    ui.clear(body);
    session.exercises.sort((a, b) => a.order - b.order);
    session.exercises.forEach((se) => body.append(exerciseCard(se, body)));

    body.append(ui.h("button", { class: "btn ghost wide", style: { marginTop: "12px" }, text: "+ Add exercise", onClick: () => pickExercise(body) }));

    const notes = ui.h("textarea", { rows: 2, placeholder: "Session notes", value: session.notes || "" });
    notes.addEventListener("input", () => { session.notes = notes.value; save(); });
    body.append(ui.h("div", { class: "section-title", text: "Session notes" }), notes);

    body.append(ui.h("button", { class: "btn primary wide", style: { marginTop: "16px", minHeight: "52px", fontSize: "18px" }, text: COPY.sessionDone, onClick: () => finish() }));
  }

  function exerciseCard(se, body) {
    const ex = exMap.get(se.exerciseName);
    const head = ui.h("div", { class: "row", style: { borderBottom: "0", paddingBottom: "2px" } },
      ui.h("div", { class: "lead" },
        ui.h("span", { class: "title", text: se.exerciseName }),
        se.phase ? ui.h("span", { class: "sub accent", text: C.phaseLabel(se.phase) }) : null),
      ui.h("div", { class: "btn-row", style: { alignItems: "center", flexWrap: "wrap", justifyContent: "flex-end" } },
        ui.h("div", { style: { width: "100px" } },
          ui.seg([{ value: "lb", label: "lb" }, { value: "kg", label: "kg" }], exUnit(se), (u) => { unitByEx[se.exerciseName] = u; renderBody(body); })),
        ex && ex.type === "barbell" ? barSelect(se, body) : null,
        ui.h("button", { class: "btn sm ghost", text: `⏱ ${ui.mmss(restFor(ex))}`, onClick: () => editRest(se, ex, body) }),
        ex && ex.isShelved ? ui.h("span", { class: "pill hard", text: COPY.shelved }) : null));
    const card = ui.h("div", { class: "card" }, head);

    se.sets.sort((a, b) => a.order - b.order);
    se.sets.forEach((s) => card.append(setRow(se, s, body)));

    card.append(ui.h("div", { class: "btn-row", style: { marginTop: "10px" } },
      ui.h("button", { class: "btn sm", text: "+ Set", onClick: () => { currentSE = se; addSet(se); save(); renderBody(body); } }),
      ui.h("button", { class: "btn sm ghost", text: "Rest", onClick: () => { currentSE = se; armRest(restFor(ex), se.exerciseName); } }),
      ui.h("button", { class: "btn sm ghost warn", text: "↓ Dropping load", onClick: () => dropLoad(se, body) })));

    if (ex && ex.watchSite) card.append(ui.h("div", { class: "sub", style: { marginTop: "8px" }, text: `Watch: ${ex.watchSite.toLowerCase()} — ${watchNote(ex.watchSite)}` }));
    return card;
  }

  function editRest(se, ex, body) {
    if (!ex) { ui.toast("No library entry for this exercise."); return; }
    ui.sheet({
      title: `Rest — ${ex.name}`,
      build: (c) => {
        // Floor: writing 0 clears the override, and this stepper shows the
        // EFFECTIVE rest — so 0 is only offered where clearing lands on 0
        // (conditioning, whose smart default IS none); elsewhere stepping to 0
        // would snap the display up to the movement default.
        const floor = C.restDefaultSeconds(ex.category, ex.name, 0) === 0 ? 0 : 15;
        c.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Rest between sets" }),
          ui.stepper(restFor(ex), { min: floor, max: 600, step: 15, format: ui.mmss, onChange: async (v) => { ex.defaultRestSeconds = v; await Exercises.save(ex); renderBody(body); } })));
        c.append(ui.h("div", { class: "sub", style: { marginTop: "8px" }, text: "Saved on the exercise — applies everywhere it's used." }));
      },
    });
  }

  function barSelect(se, body) {
    const sel = ui.h("select", { class: "bar-select" },
      ...C.ALL_BARS.map((b) => ui.h("option", { value: C.barId(b), text: C.barLabel(b), selected: C.barId(b) === C.barId(barFor(se)) })));
    sel.addEventListener("change", () => { barByEx[se.exerciseName] = C.barById(sel.value); renderBody(body); });
    return sel;
  }

  function setRow(se, s, body) {
    const ex = exMap.get(se.exerciseName);
    const u = exUnit(se);
    const wlabel = s.weightLb === 0 ? "BW" : `${C.trim(u === "kg" ? C.kgFromLb(s.weightLb) : s.weightLb)} ${u}`;
    const wt = ui.h("button", { class: "btn ghost", style: { padding: "4px 8px", minHeight: "40px" }, onClick: () => editSet(se, s, body) },
      ui.h("span", { class: "wt mono" + (s.isWarmup ? " muted" : ""), text: wlabel }),
      ui.h("span", { class: "sub mono", text: ` × ${s.reps}${s.isPerSide ? "/side" : ""}` }));
    const tags = ui.h("span", { class: "sub" });
    if (s.isWarmup) tags.append(ui.h("span", { class: "pill", text: "warmup" }));
    if (s.autoregReason) tags.append(ui.h("span", { class: "pill warn", text: `↓ ${s.autoregReason}` }));
    if (s.bodyFlagSite) tags.append(ui.h("span", { class: "pill hard", text: "⚡︎" }));

    const flag = (name, cls) => ui.h("button", {
      class: "flagbtn" + (s.flags.includes(name) ? ` on-${cls}` : ""),
      text: name === "clean" ? "✓" : name[0].toUpperCase(),
      onClick: () => toggleFlag(se, s, name, body),
    });
    const row = ui.h("div", { class: "setrow" }, wt, tags,
      ui.h("div", { class: "flagbtns" }, flag("clean", "clean"), flag("grindy", "grindy"), flag("wobble", "wobble")));

    // Barbell plate visualization (barbell lifts only).
    if (ex && ex.type === "barbell" && s.weightLb > 0) {
      const { svg, solution } = barbellSVG(s.weightLb, u, barFor(se), gym);
      const wrap = ui.h("div", { class: "barbell-wrap" }, svg);
      if (solution.isOffTarget) {
        const t = u === "kg" ? C.kgFromLb(solution.totalLb) : solution.totalLb;
        wrap.append(ui.h("span", { class: "sub warn", text: `≈ closest ${C.trim(t)} ${u}` }));
      }
      return ui.h("div", {}, row, wrap);
    }
    return row;
  }

  function toggleFlag(se, s, name, body) {
    currentSE = se;
    const had = s.flags.includes(name);
    s.flags = had ? s.flags.filter((f) => f !== name) : [...s.flags, name];
    // Auto-start rest only if the user opted in (manual is the default).
    if (!had && settings.autoStartRest && !rest.running) { armRest(restFor(exMap.get(se.exerciseName)), se.exerciseName); }
    save(); renderBody(body);
  }

  function addSet(se) {
    const last = se.sets[se.sets.length - 1];
    const ex = exMap.get(se.exerciseName);
    const w = last ? last.weightLb : (se.plannedWeightLb ?? 45);
    const r = last ? last.reps : (se.plannedReps ?? 5);
    const set = mkSet(se.sets.length, w, r, { perSide: ex && ex.isUnilateral });
    set.enteredUnit = exUnit(se);
    se.sets.push(set);
  }

  function dropLoad(se, body) {
    ui.actionSheet("Dropping load — why?", C.AUTOREG_REASONS.map((reason) => ({
      label: reason,
      onClick: () => {
        // Shared plan (core parity): unflagged working sets only, each dropped
        // from its own weight — a back-off set is never raised.
        const plan = C.dropLoadPlan(se.sets.map((x) => ({ weightLb: x.weightLb, isWarmup: !!x.isWarmup, isFlagged: !!(x.flags || []).length })));
        if (!plan.length) { ui.toast("All sets already logged — nothing to drop."); return; }
        plan.forEach((p, i) => { const x = se.sets[p.index]; x.weightLb = p.weightLb; x.enteredUnit = "lb"; if (i === 0) x.autoregReason = reason; });
        save(); renderBody(body);
        ui.toast(`Dropped to ${C.trim(Math.max(...plan.map((p) => p.weightLb)))} lb`);
      },
    })));
  }

  function editSet(se, s, body) {
    ui.sheet({
      title: "Edit set",
      build: (c, api) => {
        let unit = exUnit(se);
        const shown = unit === "kg" ? C.kgFromLb(s.weightLb) : s.weightLb;
        const wInput = ui.h("input", { class: "big-num", type: "number", inputmode: "decimal", step: "0.5", value: s.weightLb === 0 ? "" : C.trim(shown, 2) });
        c.append(ui.field("Weight (0 = bodyweight)", wInput));
        c.append(ui.field("Unit", ui.seg([{ value: "lb", label: "lb" }, { value: "kg", label: "kg" }], unit, (u) => { unit = u; })));
        let reps = s.reps;
        c.append(ui.field("Reps", ui.stepper(reps, { min: 0, max: 100, onChange: (v) => { reps = v; } })));
        let warm = s.isWarmup, per = s.isPerSide, site = s.bodyFlagSite;
        c.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Warmup" }), ui.toggle(warm, (v) => { warm = v; })));
        c.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Per side" }), ui.toggle(per, (v) => { per = v; })));
        const noteInput = ui.h("input", { type: "text", placeholder: "What did it feel like?", value: s.bodyFlagNote || "" });
        const siteSel = ui.h("select", {}, ui.h("option", { value: "", text: "None" }), ...BODY_SITES.map((b) => ui.h("option", { value: b, text: b, selected: b === site })));
        siteSel.addEventListener("change", () => { site = siteSel.value || null; });
        c.append(ui.field("Body signal", siteSel), ui.field("Signal note", noteInput));
        c.append(ui.h("button", {
          class: "btn primary wide", style: { marginTop: "10px" }, text: "Done",
          onClick: () => {
            const val = parseFloat(wInput.value) || 0;
            s.weightLb = val === 0 ? 0 : C.toLb(val, unit);
            s.enteredUnit = unit; s.reps = reps; s.isWarmup = warm; s.isPerSide = per;
            s.bodyFlagSite = site; s.bodyFlagNote = site ? (noteInput.value || null) : null;
            unitByEx[se.exerciseName] = unit; // keep the row display in the unit you just used
            api.close(); save(); renderBody(body);
          },
        }));
        c.append(ui.h("button", { class: "btn wide danger", style: { marginTop: "8px" }, text: "Delete set",
          onClick: () => { se.sets = se.sets.filter((x) => x !== s); se.sets.forEach((x, i) => { x.order = i; }); api.close(); save(); renderBody(body); } }));
      },
    });
  }

  async function pickExercise(body) {
    const all = await Exercises.all();
    ui.sheet({
      title: "Add exercise",
      build: (c, api) => {
        for (const cat of CATEGORIES) {
          const inCat = all.filter((e) => e.category === cat).sort((a, b) => a.name.localeCompare(b.name));
          if (!inCat.length) continue;
          c.append(ui.h("div", { class: "section-title", text: cat }));
          for (const e of inCat) {
            c.append(ui.h("button", { class: "btn wide ghost", style: { marginTop: "6px", justifyContent: "space-between" },
              onClick: () => {
                session.exercises.push({ order: session.exercises.length, exerciseName: e.name, notes: "", phase: null, plannedWeightLb: null, plannedSets: null, plannedReps: null, sets: [] });
                api.close(); save(); renderBody(body);
              } },
              ui.h("span", { text: e.name }), e.isShelved ? ui.h("span", { class: "pill hard", text: COPY.shelved }) : ui.h("span")));
          }
        }
      },
    });
  }

  let finishing = false; // double-tap on Bank it would run completion twice (dup milestones, racy advances)
  async function finish() {
    if (finishing) return;
    finishing = true;
    try {
      const summary = await completeSession(session);
      rest.stop();
      showSummary(summary, () => { screen.close(); ui.nav.refresh(); });
    } catch (e) {
      finishing = false; // let the user retry on a failed write
      console.error(e);
      ui.toast("Couldn't bank the session — try again.");
    }
  }

  const screen = ui.pushScreen({ title: ui.fmtDate(session.date), build: (b) => renderBody(b) });
  screen.el.append(buildBottomBar());
  paintBar();
  const barTick = setInterval(() => {
    if (!document.body.contains(screen.el)) { clearInterval(barTick); rest.stop(); return; }
    if (!rest.running) paintBar(); // while resting the rest timer's own tick paints
  }, 500);
}

// ---- completion + PR detection ----
export async function completeSession(session) {
  // Idempotence backstop (mirrors SessionCompletion.finish): completing twice
  // would duplicate milestones and double-advance tracks/programs. Claim the
  // flag SYNCHRONOUSLY (before the first await) so interleaved calls can't
  // both pass; reset it on failure so a retry isn't no-opped by this guard.
  if (session.isCompleted) return { lines: [], milestones: [] };
  session.isCompleted = true;
  try {
    return await completeSessionInner(session);
  } catch (e) {
    session.isCompleted = false;
    throw e;
  }
}

async function completeSessionInner(session) {
  const prior = (await Sessions.completed()).filter((s) => new Date(s.date) < new Date(session.date));
  const lines = [], milestones = [], milestoneRecords = [];
  // Keyed, not a list: a session with the same tracked exercise in two
  // sections must advance the SAME in-memory track twice (as native does with
  // its context-cached object) — re-reading the store would advance from the
  // same base twice and commit only the last put.
  const trackByName = new Map();
  for (const se of session.exercises) {
    const working = se.sets.filter((s) => !s.isWarmup).map((s) => ({ weightLb: s.weightLb, reps: s.reps }));
    if (!working.length) continue;

    const historySets = [], historyVolumes = [], historySchemes = new Set();
    for (const ps of prior) {
      for (const pe of ps.exercises) {
        if (pe.exerciseName !== se.exerciseName) continue;
        const w = pe.sets.filter((x) => !x.isWarmup).map((x) => ({ weightLb: x.weightLb, reps: x.reps }));
        if (!w.length) continue;
        historySets.push(...w);
        historyVolumes.push(w.reduce((a, b) => a + b.weightLb * b.reps, 0));
        const top = C.prTopScheme(w); if (top) historySchemes.add(`${top.sets}×${top.reps}`);
      }
    }
    const events = C.prEvaluate({ exercise: se.exerciseName, sessionSets: working, historySets, historyVolumes, historySchemes });
    for (const e of events) { milestoneRecords.push({ date: iso(new Date(session.date)), exerciseName: e.exercise, kind: e.kind, label: e.label }); milestones.push(e); }

    // Program-owned exercises advance via the program, never the standalone track.
    const track = se.programRole ? null : (trackByName.get(se.exerciseName) ?? await Tracks.byName(se.exerciseName));
    if (track) {
      track.lastCompletedAt = iso(new Date());
      if (track.mode === "cycle") {
        const adv = C.advancing(trackState(track), track.nextPhase);
        track.cycleNumber = adv.cycleNumber; track.baseWeightLb = adv.baseWeightLb; track.nextPhase = adv.nextPhase;
      } else { track.baseWeightLb += track.incrementLb; }
      trackByName.set(se.exerciseName, track);
    }
    const top = working.reduce((b, s) => (!b || s.weightLb > b.weightLb ? s : b), null);
    lines.push({ exerciseName: se.exerciseName, topSetLabel: `${C.trim(top.weightLb)}×${top.reps}`, volumeLb: working.reduce((a, s) => a + s.weightLb * s.reps, 0) });
  }

  const prog = session.programTag ? await advanceProgram(session, milestones) : null;
  if (prog) milestoneRecords.push(...prog.noteRecords);

  // One transaction: milestones, track advances, program state, and the
  // completed session commit or roll back TOGETHER — a mid-write failure
  // can't leave progression half-advanced against an unbanked session.
  await runAll(["milestones", "tracks", "programs", "sessions"], "readwrite", (os) => {
    for (const m of milestoneRecords) os("milestones").put(m);
    for (const t of trackByName.values()) os("tracks").put(t);
    if (prog && prog.program) os("programs").put(prog.program);
    os("sessions").put(session);
  });
  return { lines, milestones };
}

// ---- Performance summaries (built from logged sets, consumed by the core) ----
function cyclePerf(se) {
  const w = se.sets.filter((s) => !s.isWarmup);
  const presReps = se.plannedReps ?? (w.length ? Math.max(...w.map((s) => s.reps)) : 0); // ?? not ||: mirrors Swift's nil-coalescing
  const top = w.reduce((b, s) => (!b || s.weightLb > b.weightLb ? s : b), null);
  return {
    prescribedSets: se.plannedSets ?? w.length, prescribedReps: presReps,
    completedSets: w.filter((s) => s.reps >= presReps).length,
    anyStoppedEarly: w.some((s) => (s.flags || []).includes("stopped early")),
    anyDroppedLoad: w.some((s) => !!s.autoregReason),
    grindyOrWobbleSets: w.filter((s) => (s.flags || []).some((f) => f === "grindy" || f === "wobble")).length,
    topSetWeightLb: top ? top.weightLb : 0, topSetReps: top ? top.reps : 0,
  };
}
function accPerf(se) {
  const w = se.sets.filter((s) => !s.isWarmup);
  return {
    completedSets: w.length,
    minRepsAchieved: w.length ? Math.min(...w.map((s) => s.reps)) : 0,
    anyStoppedEarly: w.some((s) => (s.flags || []).includes("stopped early")),
  };
}

// ---- Program day/week/cycle advancement on bank ----
// Mutates the program in memory and returns { program, noteRecords } for the
// caller's single completion transaction — no writes of its own.
async function advanceProgram(session, milestones) {
  const tag = session.programTag;
  const program = await Programs.get(tag.programId);
  if (!program) return null;
  const day = program.days.find((d) => d.order === tag.dayIndex);
  if (!day) return null;
  const note = (label, name) => milestones.push({ kind: "programNote", exercise: name, label, _persist: { exerciseName: name, label } });

  // Accessories: double progression, evaluated every bank.
  for (const acc of day.accessories || []) {
    const se = session.exercises.find((e) => e.programRole === "accessory" && e.exerciseName === acc.exerciseName);
    if (se) Object.assign(acc, C.advanceAccessory(acc, accPerf(se)));
  }
  // Cycle lifts: grade at the week-3 Peak, stash pending; apply at rollover.
  if (tag.week === 3) {
    for (const lift of day.lifts || []) {
      const se = session.exercises.find((e) => e.exerciseName === lift.exerciseName && e.programRole === lift.role);
      if (se) lift.pending = C.advanceCycleLift(lift, cyclePerf(se), program.focus, program.roundingLb);
    }
  }

  const lastDay = tag.dayIndex === program.days.length - 1;
  program.nextDayIndex = (tag.dayIndex + 1) % program.days.length;
  if (lastDay) {
    if (program.currentWeek < 4) {
      program.currentWeek += 1;
    } else {
      // Rollover: apply each lift's pending (or treat a skipped peak as a stall).
      for (const d of program.days) {
        for (const lift of d.lifts || []) {
          if (lift.pending) {
            const p = lift.pending.state;
            lift.baseWeightLb = p.baseWeightLb; lift.estimatedMaxLb = p.estimatedMaxLb;
            lift.stallCount = p.stallCount; lift.lastIncrementLb = p.lastIncrementLb;
            if (lift.pending.note) note(`${lift.exerciseName}: ${lift.pending.note}`, lift.exerciseName);
            delete lift.pending;
          } else {
            lift.stallCount = (lift.stallCount || 0) + 1; lift.lastIncrementLb = 0;
            if (lift.stallCount >= C.STALL_LIMIT) {
              const old = lift.baseWeightLb;
              lift.baseWeightLb = C.roundTo(old * C.DELOAD_REBUILD_FRACTION, program.roundingLb);
              lift.stallCount = 0;
              note(`${lift.exerciseName}: skipped peak — deloaded ${C.trim(old)}→${C.trim(lift.baseWeightLb)} lb.`, lift.exerciseName);
            }
          }
        }
      }
      program.cycleNumber += 1;
      program.currentWeek = 1;
    }
  }
  // Program notes become milestones so the explanation shows in History; the
  // caller persists them with the rest of the completion transaction.
  const noteRecords = [];
  for (const m of milestones) {
    if (m.kind === "programNote" && m._persist) { noteRecords.push({ date: iso(new Date(session.date)), exerciseName: m._persist.exerciseName, kind: "programNote", label: m._persist.label }); delete m._persist; }
  }
  return { program, noteRecords };
}

// ---- Build a session from a program day ----
// Secondary/accessory barbell work snaps to a neat bar-loadable weight (no
// lonely 2.5); main lifts keep their fine progression, and non-barbell work is
// left alone. Shared by session creation AND the Home preview so the "Start"
// card and the stored prescription never disagree.
export function neatProgramWeight(weightLb, exercise, isMain, barLb, stepLb) {
  return (!isMain && exercise && exercise.type === "barbell") ? C.barLoadable(weightLb, barLb, stepLb) : weightLb;
}

export async function createSessionFromProgramDay(program, day) {
  const exMap = new Map((await Exercises.all()).map((e) => [e.name, e]));
  const gym = await Gyms.default();
  const barLb = C.barLb(gym ? C.barById(gym.defaultBarId) : C.BARS.bar45lb);
  const neat = (weightLb, ex, isMain) => neatProgramWeight(weightLb, ex, isMain, barLb, program.roundingLb);
  const exercises = [];
  let order = 0;
  const lifts = [...(day.lifts || [])].sort((a, b) => (a.role === "main" ? 0 : 1) - (b.role === "main" ? 0 : 1));
  for (const lift of lifts) {
    const plan = C.planFor({ cycleNumber: program.cycleNumber, baseWeightLb: lift.baseWeightLb, nextPhase: program.currentWeek, incrementLb: 0 }, program.roundingLb);
    const ex = exMap.get(lift.exerciseName);
    const weightLb = neat(plan.weightLb, ex, lift.role === "main");
    const sets = [];
    let so = 0;
    if (ex && ex.type === "barbell") for (const wu of C.warmupRamp(weightLb, barLb, program.roundingLb)) sets.push(mkSet(so++, wu.weightLb, wu.reps, { warm: true }));
    for (let i = 0; i < plan.sets; i += 1) sets.push(mkSet(so++, weightLb, plan.reps, { perSide: ex && ex.isUnilateral }));
    exercises.push({ order: order++, exerciseName: lift.exerciseName, notes: "", phase: program.currentWeek, plannedWeightLb: weightLb, plannedSets: plan.sets, plannedReps: plan.reps, programRole: lift.role, sets });
  }
  for (const acc of day.accessories || []) {
    const ex = exMap.get(acc.exerciseName);
    const weightLb = neat(acc.weightLb, ex, false);
    const sets = [];
    for (let i = 0; i < acc.sets; i += 1) sets.push(mkSet(i, weightLb, acc.currentReps, { perSide: ex && ex.isUnilateral }));
    exercises.push({ order: order++, exerciseName: acc.exerciseName, notes: "", phase: null, plannedWeightLb: weightLb, plannedSets: acc.sets, plannedReps: acc.currentReps, programRole: "accessory", sets });
  }
  const id = await Sessions.save({
    date: iso(new Date()), notes: "", isCompleted: false, gymName: await defaultGymName(),
    programTag: { programId: program.id, cycleNumber: program.cycleNumber, week: program.currentWeek, dayIndex: day.order },
    exercises,
  });
  return id;
}

function showSummary(summary, onDone) {
  ui.sheet({
    title: COPY.sessionDone,
    build: (c, api) => {
      c.append(ui.h("div", { class: "section-title", text: "Session" }));
      if (!summary.lines.length) c.append(ui.h("div", { class: "muted", text: "No working sets logged." }));
      for (const l of summary.lines) {
        c.append(ui.h("div", { class: "row" },
          ui.h("div", { class: "lead" }, ui.h("span", { class: "title", text: l.exerciseName }),
            ui.h("span", { class: "sub mono", text: `Top ${l.topSetLabel} · Volume ${C.trim(l.volumeLb)} lb` }))));
      }
      if (summary.milestones.length) {
        c.append(ui.h("div", { class: "section-title", text: "Milestones" }));
        for (const m of summary.milestones) c.append(ui.h("div", { class: "row" }, ui.h("span", { class: "accent", text: `⚑ ${m.label}` })));
      }
      c.append(ui.h("button", { class: "btn primary wide", style: { marginTop: "12px" }, text: "Done", onClick: () => { api.close(); onDone(); } }));
    },
  });
}
