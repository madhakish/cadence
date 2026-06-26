// Active-session logger — the core daily screen. Set entry, quality flags,
// rest timer, autoregulation, body signals, completion + PR detection.
import * as ui from "../ui.js";
import * as C from "../core.js";
import { BODY_SITES, SET_FLAGS, CATEGORIES, watchNote, COPY } from "../constants.js";
import { Sessions, Exercises, Tracks, Gyms, Milestones, Programs, iso } from "../db.js";

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
function beep() {
  try {
    const ac = new (window.AudioContext || window.webkitAudioContext)();
    const o = ac.createOscillator(), g = ac.createGain();
    o.frequency.value = 880; o.connect(g); g.connect(ac.destination);
    g.gain.setValueAtTime(0.001, ac.currentTime); g.gain.exponentialRampToValueAtTime(0.3, ac.currentTime + 0.02);
    g.gain.exponentialRampToValueAtTime(0.001, ac.currentTime + 0.5);
    o.start(); o.stop(ac.currentTime + 0.5);
  } catch { /* ignore */ }
  if (navigator.vibrate) navigator.vibrate(200);
}

const setWeightLabel = (s) => {
  if (s.weightLb === 0) return "BW";
  return s.enteredUnit === "kg" ? `${C.trim(C.kgFromLb(s.weightLb))} kg` : `${C.trim(s.weightLb)} lb`;
};

export async function openSession(id) {
  const session = await Sessions.get(id);
  if (!session) { ui.toast("Session not found."); return; }
  const exMap = new Map((await Exercises.all()).map((e) => [e.name, e]));
  const save = () => Sessions.save(session);

  const rest = makeRestTimer(() => paintRest(), () => { ui.toast("Rest over."); beep(); paintRest(); });
  let restEl = null;
  function paintRest() {
    if (!restEl) return;
    if (!rest.running) { restEl.style.display = "none"; return; }
    restEl.style.display = "";
    restEl.querySelector(".big-time").textContent = ui.mmss(rest.remaining);
    restEl.querySelector(".progress > i").style.width = `${Math.min(100, rest.progress * 100)}%`;
  }
  function armRest(seconds) { rest.start(seconds || 90); }

  function renderBody(body) {
    ui.clear(body);
    restEl = ui.h("div", { class: "rest-bar", style: { display: "none" } },
      ui.h("div", { style: { display: "flex", alignItems: "center", justifyContent: "space-between" } },
        ui.h("span", { class: "big-time mono", text: "0:00" }),
        ui.h("div", { class: "btn-row" },
          ui.h("button", { class: "btn sm", text: "+30s", onClick: () => rest.add(30) }),
          ui.h("button", { class: "btn sm ghost", text: "Skip", onClick: () => rest.stop() }))),
      ui.h("div", { class: "progress" }, ui.h("i")));
    body.append(restEl);
    paintRest();

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
      ex && ex.isShelved ? ui.h("span", { class: "pill hard", text: COPY.shelved }) : null);
    const card = ui.h("div", { class: "card" }, head);

    se.sets.sort((a, b) => a.order - b.order);
    se.sets.forEach((s) => card.append(setRow(se, s, body)));

    card.append(ui.h("div", { class: "btn-row", style: { marginTop: "10px" } },
      ui.h("button", { class: "btn sm", text: "+ Set", onClick: () => { addSet(se); save(); renderBody(body); } }),
      ui.h("button", { class: "btn sm ghost warn", text: "↓ Dropping load", onClick: () => dropLoad(se, body) })));

    if (ex && ex.watchSite) card.append(ui.h("div", { class: "sub", style: { marginTop: "8px" }, text: `Watch: ${ex.watchSite.toLowerCase()} — ${watchNote(ex.watchSite)}` }));
    return card;
  }

  function setRow(se, s, body) {
    const wt = ui.h("button", { class: "btn ghost", style: { padding: "4px 8px", minHeight: "40px" }, onClick: () => editSet(se, s, body) },
      ui.h("span", { class: "wt mono" + (s.isWarmup ? " muted" : ""), text: setWeightLabel(s) }),
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
    return ui.h("div", { class: "setrow" }, wt, tags,
      ui.h("div", { class: "flagbtns" }, flag("clean", "clean"), flag("grindy", "grindy"), flag("wobble", "wobble")));
  }

  function toggleFlag(se, s, name, body) {
    const had = s.flags.includes(name);
    s.flags = had ? s.flags.filter((f) => f !== name) : [...s.flags, name];
    if (!had && !rest.running) { const ex = exMap.get(se.exerciseName); armRest(ex ? ex.defaultRestSeconds : 90); }
    save(); renderBody(body);
  }

  function addSet(se) {
    const last = se.sets[se.sets.length - 1];
    const ex = exMap.get(se.exerciseName);
    const w = last ? last.weightLb : (se.plannedWeightLb ?? 45);
    const r = last ? last.reps : (se.plannedReps ?? 5);
    se.sets.push(mkSet(se.sets.length, w, r, { perSide: ex && ex.isUnilateral }));
  }

  function dropLoad(se, body) {
    ui.actionSheet("Dropping load — why?", C.AUTOREG_REASONS.map((reason) => ({
      label: reason,
      onClick: () => {
        const working = se.sets.filter((x) => !x.isWarmup);
        const topW = working.reduce((m, x) => Math.max(m, x.weightLb), 0);
        const dropped = C.droppedLoad(topW);
        working.filter((x) => Math.abs(x.weightLb - topW) < 1e-9).forEach((x) => { x.weightLb = dropped; x.enteredUnit = "lb"; x.autoregReason = reason; });
        save(); renderBody(body);
        ui.toast(`Dropped to ${C.trim(dropped)} lb`);
      },
    })));
  }

  function editSet(se, s, body) {
    ui.sheet({
      title: "Edit set",
      build: (c, api) => {
        let unit = s.enteredUnit;
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

  async function finish() {
    const summary = await completeSession(session);
    rest.stop();
    showSummary(summary, () => { screen.close(); ui.nav.refresh(); });
  }

  const screen = ui.pushScreen({ title: ui.fmtDate(session.date), build: (b) => renderBody(b) });
}

// ---- completion + PR detection ----
export async function completeSession(session) {
  const prior = (await Sessions.completed()).filter((s) => new Date(s.date) < new Date(session.date));
  const lines = [], milestones = [];
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
    for (const e of events) { await Milestones.add({ date: iso(new Date(session.date)), exerciseName: e.exercise, kind: e.kind, label: e.label }); milestones.push(e); }

    // Program-owned exercises advance via the program, never the standalone track.
    const track = se.programRole ? null : await Tracks.byName(se.exerciseName);
    if (track) {
      track.lastCompletedAt = iso(new Date());
      if (track.mode === "cycle") {
        const adv = C.advancing(trackState(track), track.nextPhase);
        track.cycleNumber = adv.cycleNumber; track.baseWeightLb = adv.baseWeightLb; track.nextPhase = adv.nextPhase;
      } else { track.baseWeightLb += track.incrementLb; }
      await Tracks.save(track);
    }
    const top = working.reduce((b, s) => (!b || s.weightLb > b.weightLb ? s : b), null);
    lines.push({ exerciseName: se.exerciseName, topSetLabel: `${C.trim(top.weightLb)}×${top.reps}`, volumeLb: working.reduce((a, s) => a + s.weightLb * s.reps, 0) });
  }

  if (session.programTag) await advanceProgram(session, milestones);

  session.isCompleted = true;
  await Sessions.save(session);
  return { lines, milestones };
}

// ---- Performance summaries (built from logged sets, consumed by the core) ----
function cyclePerf(se) {
  const w = se.sets.filter((s) => !s.isWarmup);
  const presReps = se.plannedReps || (w.length ? Math.max(...w.map((s) => s.reps)) : 0);
  const top = w.reduce((b, s) => (!b || s.weightLb > b.weightLb ? s : b), null);
  return {
    prescribedSets: se.plannedSets || w.length, prescribedReps: presReps,
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
async function advanceProgram(session, milestones) {
  const tag = session.programTag;
  const program = await Programs.get(tag.programId);
  if (!program) return;
  const day = program.days.find((d) => d.order === tag.dayIndex);
  if (!day) return;
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
  await Programs.save(program);
  // Persist program notes as milestones so the explanation shows in History.
  for (const m of milestones) {
    if (m.kind === "programNote" && m._persist) { await Milestones.add({ date: iso(new Date(session.date)), exerciseName: m._persist.exerciseName, kind: "programNote", label: m._persist.label }); delete m._persist; }
  }
}

// ---- Build a session from a program day ----
export async function createSessionFromProgramDay(program, day) {
  const exMap = new Map((await Exercises.all()).map((e) => [e.name, e]));
  const exercises = [];
  let order = 0;
  const lifts = [...(day.lifts || [])].sort((a, b) => (a.role === "main" ? 0 : 1) - (b.role === "main" ? 0 : 1));
  for (const lift of lifts) {
    const plan = C.planFor({ cycleNumber: program.cycleNumber, baseWeightLb: lift.baseWeightLb, nextPhase: program.currentWeek, incrementLb: 0 }, program.roundingLb);
    const ex = exMap.get(lift.exerciseName);
    const sets = [];
    let so = 0;
    if (ex && ex.type === "barbell") for (const wu of C.warmupRamp(plan.weightLb)) sets.push(mkSet(so++, wu.weightLb, wu.reps, { warm: true }));
    for (let i = 0; i < plan.sets; i += 1) sets.push(mkSet(so++, plan.weightLb, plan.reps, { perSide: ex && ex.isUnilateral }));
    exercises.push({ order: order++, exerciseName: lift.exerciseName, notes: "", phase: program.currentWeek, plannedWeightLb: plan.weightLb, plannedSets: plan.sets, plannedReps: plan.reps, programRole: lift.role, sets });
  }
  for (const acc of day.accessories || []) {
    const ex = exMap.get(acc.exerciseName);
    const sets = [];
    for (let i = 0; i < acc.sets; i += 1) sets.push(mkSet(i, acc.weightLb, acc.currentReps, { perSide: ex && ex.isUnilateral }));
    exercises.push({ order: order++, exerciseName: acc.exerciseName, notes: "", phase: null, plannedWeightLb: acc.weightLb, plannedSets: acc.sets, plannedReps: acc.currentReps, programRole: "accessory", sets });
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
