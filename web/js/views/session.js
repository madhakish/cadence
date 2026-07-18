// Active-session logger — the core daily screen. Set entry, quality flags,
// rest timer, autoregulation, body signals, completion + PR detection.
import * as ui from "../ui.js";
import * as C from "../core.js";
import { BODY_SITES, CATEGORIES, watchNote, COPY } from "../constants.js";
import { Sessions, Exercises, Tracks, Gyms, Milestones, Programs, Settings, iso, runAll } from "../db.js";
import { barbellSVG, dumbbellSVG } from "../barbell.js";

const trackState = (t) => ({ cycleNumber: t.cycleNumber, baseWeightLb: t.baseWeightLb, nextPhase: t.nextPhase, incrementLb: t.incrementLb });
const mkSet = (order, w, r, o = {}) => ({
  order, weightLb: w, reps: r, isWarmup: !!o.warm, isPerSide: !!o.perSide, enteredUnit: o.unit || "lb",
  status: "planned",
  flags: [], bodyFlagSite: null, bodyFlagNote: null, durationSeconds: null, distanceMiles: null,
  inclinePercent: null, autoregReason: null,
});

async function defaultGymTag() { const g = await Gyms.default(); return { gymId: g?.id || null, gymName: g?.name || null }; }

export async function createSessionFromTrack(track) {
  const [ex, gym, settings] = await Promise.all([Exercises.byName(track.exerciseName), Gyms.default(), Settings.get()]);
  const unit = C.primaryUnit(settings.unitDisplay);
  const barLb = C.barLb(gym ? C.barById(gym.defaultBarId) : C.BARS.bar45lb);
  const sug = track.mode === "cycle" ? C.planFor(trackState(track)) : C.linearPlan(track.baseWeightLb);
  const sets = [];
  let order = 0;
  if (ex && ex.type === "barbell") {
    for (const w of C.warmupRamp(sug.weightLb, barLb, track.roundingLb)) sets.push(mkSet(order++, w.weightLb, w.reps, { warm: true, unit }));
  }
  for (let i = 0; i < sug.sets; i += 1) sets.push(mkSet(order++, sug.weightLb, sug.reps, { perSide: ex && ex.isUnilateral, unit }));
  const se = { order: 0, exerciseName: track.exerciseName, notes: "", phase: sug.phase || null, plannedWeightLb: sug.weightLb, plannedSets: sug.sets, plannedReps: sug.reps, sets };
  const id = await Sessions.save({ date: iso(new Date()), notes: "", isCompleted: false, gymId: gym?.id || null, gymName: gym?.name || null, exercises: [se] });
  return id;
}

export async function createBlankSession() {
  return Sessions.save({ date: iso(new Date()), notes: "", isCompleted: false, ...await defaultGymTag(), exercises: [] });
}

// ---- Rest timer ----
// Display/interval shell over the shared RestClock state math (core.js,
// mirrored 1:1 in CadenceCore/RestClock.swift — the same transitions drive
// the native timer and its Live Activity). `progress` is the ELAPSED
// fraction, what the bar fill wants.
function makeRestTimer(onTick, onDone) {
  let clock = null, handle = null;
  const nowS = () => Date.now() / 1000;
  const stop = () => { if (handle) clearInterval(handle); handle = null; clock = null; onTick(); };
  return {
    get running() { return !!handle; },
    get remaining() { return clock ? C.restClockRemaining(clock, nowS()) : 0; },
    get progress() { return clock ? 1 - C.restClockFractionRemaining(clock, nowS()) : 0; },
    start(sec) {
      clock = C.restClockStart(sec, nowS());
      if (handle) clearInterval(handle);
      handle = setInterval(() => { if (this.remaining <= 0) { stop(); onDone(); } else onTick(); }, 250);
      onTick();
    },
    add(sec) { if (handle && clock) { clock = C.restClockAdd(clock, sec); onTick(); } },
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

const topSetOf = (e) => (e.sets || []).filter((x) => !x.isWarmup && x.status === "completed")
  .reduce((b, x) => (!b || x.weightLb > b.weightLb ? x : b), null);

// Compact "how long ago" for the last-session recall line.
function agoLabel(date) {
  const days = Math.max(0, Math.floor((Date.now() - new Date(date)) / 86400000));
  if (days === 0) return "today";
  if (days === 1) return "yesterday";
  if (days < 14) return `${days}d ago`;
  if (days < 70) return `${Math.floor(days / 7)}w ago`;
  return `${Math.floor(days / 30)}mo ago`;
}

export async function openSession(id) {
  const session = await Sessions.get(id);
  if (!session) { ui.toast("Session not found."); return; }
  const exMap = new Map((await Exercises.all()).map((e) => [e.name, e]));
  const settings = await Settings.get();
  const gymOptions = await Gyms.all();
  const gymState = { value: await Gyms.resolve(session.gymId, session.gymName) };
  const priorSessions = (await Sessions.completed())
    .filter((s) => s.id !== session.id)
    .sort((a, b) => new Date(b.date) - new Date(a.date)); // newest first, sorted once
  const save = () => Sessions.save(session);

  // Compact previous-performance context searched across ALL history (not
  // just this program), so a lift you
  // swapped away from months ago still tells you where you left off.
  // Mirrors the native ActiveSessionView.lastTime.
  function lastTimeLine(name) {
    for (const p of priorSessions) {
      const entries = (p.exercises || []).filter((e) => e.exerciseName === name);
      const tops = entries.map((e) => topSetOf(e)).filter(Boolean);
      if (!tops.length) continue;
      const top = tops.reduce((b, t) => (t.weightLb > b.weightLb ? t : b));
      const w = top.weightLb === 0 ? "BW" : ui.fmtWeight(top.weightLb);
      return `Last: ${w}×${top.reps} · ${ui.fmtDate(p.date)} (${agoLabel(p.date)})`;
    }
    return null;
  }

  // Per-exercise entry/display unit + bar. Session-local. The bar is chosen
  // independently of the plate unit (most bars are 45 lb whatever you load).
  const unitByEx = {};
  const exUnit = (se) => unitByEx[se.exerciseName]
    || (se.sets || []).find((set) => set.enteredUnit)?.enteredUnit
    || C.primaryUnit(settings.unitDisplay);
  const setUnit = (se, set) => unitByEx[se.exerciseName] || set.enteredUnit || exUnit(se);
  const barFor = (se) => (se.barId ? C.barById(se.barId) : null)
    || (gymState.value ? C.barById(gymState.value.defaultBarId) : C.BARS.bar45lb);
  const synchronizeWarmups = (se, bar) => {
    const ex = exMap.get(se.exerciseName);
    const working = (se.sets || []).filter((set) => !set.isWarmup).sort((a, b) => a.order - b.order);
    const workingLb = se.plannedWeightLb ?? working[0]?.weightLb;
    if (!ex || !(workingLb > 0)) return;
    const desired = ex.type === "barbell"
      ? C.warmupRamp(workingLb, C.barLb(bar), 5)
      : (ex.type === "dumbbell" && se.programRole === "main" ? C.dumbbellWarmupRamp(workingLb, 5) : null);
    if (!desired) return;
    const existing = (se.sets || []).filter((set) => set.isWarmup).sort((a, b) => a.order - b.order);
    const warmups = desired.map((target, index) => {
      const set = existing[index] || mkSet(index, target.weightLb, target.reps, { warm: true, unit: exUnit(se) });
      set.weightLb = target.weightLb; set.reps = target.reps; set.isWarmup = true;
      return set;
    });
    se.sets = [...warmups, ...working];
    se.sets.forEach((set, index) => { set.order = index; });
  };

  // The five configurable rest buckets — Settings.get() normalizes the shape,
  // so `settings.rest` is always complete here.
  const restCfg = settings.rest;
  // Smart rest via the shared precedence: per-exercise rest → program role →
  // movementGroup bucket. No exercise record → accessory bucket.
  function restFor(ex, role = null) {
    if (!ex) return restCfg.accessorySeconds;
    return C.restDefaultSeconds(ex.category, ex.movementGroup, role, restCfg, ex.defaultRestSeconds > 0 ? ex.defaultRestSeconds : 0);
  }

  const sessionStart = Date.now();            // session stopwatch origin (ephemeral)
  let currentSE = null;                       // the exercise you're actively working
  // Exercise AND role must come from the same session entry — pairing
  // exercises[0] with currentSE's (null) role resolved the first lift's rest
  // without its program role (mirrors native currentOrFirst).
  const currentEntry = () => currentSE || session.exercises[0] || null;
  const currentExercise = () => exMap.get((currentEntry() || {}).exerciseName);

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
      barEls.subBtn.style.display = "";
      barEls.addBtn.style.display = "";
      barEls.skipBtn.style.display = "";
      barEls.prog.style.width = `${Math.min(100, rest.progress * 100)}%`;
    } else {
      barEls.restTime.style.display = "none";
      barEls.restBtn.style.display = "";
      barEls.restBtn.textContent = `Rest ${ui.mmss(restFor(currentExercise(), currentEntry()?.programRole))}`;
      barEls.subBtn.style.display = "none";
      barEls.addBtn.style.display = "none";
      barEls.skipBtn.style.display = "none";
      barEls.prog.style.width = "0%";
    }
  }

  function buildBottomBar() {
    const clock = ui.h("span", { class: "clock mono" });
    const restTime = ui.h("span", { class: "rest-time mono", style: { display: "none" } });
    const restBtn = ui.h("button", { class: "btn sm primary", text: "Rest", onClick: () => { const ex = currentExercise(); armRest(restFor(ex, currentEntry()?.programRole), ex ? ex.name : ""); } });
    const subBtn = ui.h("button", { class: "btn sm", style: { display: "none" }, text: "−1:00", onClick: () => { rest.add(-60); paintBar(); } });
    const addBtn = ui.h("button", { class: "btn sm", style: { display: "none" }, text: "+1:00", onClick: () => { rest.add(60); paintBar(); } });
    const skipBtn = ui.h("button", { class: "btn sm ghost", style: { display: "none" }, text: "Skip", onClick: () => { rest.stop(); paintBar(); } });
    const prog = ui.h("i");
    barEls = { clock, restTime, restBtn, subBtn, addBtn, skipBtn, prog };
    return ui.h("div", { id: "session-bar" },
      ui.h("div", { class: "session-bar-row" }, clock, ui.h("div", { class: "btn-row", style: { alignItems: "center" } }, restTime, restBtn, subBtn, addBtn, skipBtn)),
      ui.h("div", { class: "progress" }, prog));
  }

  function renderBody(body) {
    ui.clear(body);
    if (gymOptions.length) {
      const gymSelect = ui.h("select", {}, ...gymOptions.map((g) => ui.h("option", { value: g.id, text: g.name, selected: g.id === gymState.value?.id })));
      gymSelect.addEventListener("change", () => {
        gymState.value = gymOptions.find((g) => g.id === gymSelect.value) || gymState.value;
        session.gymId = gymState.value?.id || null; session.gymName = gymState.value?.name || null;
        for (const se of session.exercises) if (!se.barId) synchronizeWarmups(se, C.barById(gymState.value.defaultBarId));
        save(); renderBody(body);
      });
      body.append(ui.field("Training at", gymSelect));
    }
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
        ui.h("button", { class: "btn sm ghost", text: `⏱ ${ui.mmss(restFor(ex, se.programRole))}`, onClick: () => editRest(se, ex, body) }),
        ex && ex.isShelved ? ui.h("span", { class: "pill hard", text: COPY.shelved }) : null));
    const card = ui.h("div", { class: "card" }, head);
    const last = lastTimeLine(se.exerciseName);
    if (last) card.append(ui.h("div", { class: "sub", style: { margin: "0 0 6px" }, text: last }));

    se.sets.sort((a, b) => a.order - b.order);
    se.sets.forEach((s) => card.append(setRow(se, s, body)));

    card.append(ui.h("div", { class: "btn-row", style: { marginTop: "10px" } },
      ui.h("button", { class: "btn sm", text: "+ Set", onClick: () => { currentSE = se; addSet(se); save(); renderBody(body); } }),
      ui.h("button", { class: "btn sm", text: "− Set", disabled: !(se.sets || []).length, onClick: () => {
        currentSE = se;
        const ordered = [...(se.sets || [])].sort((a, b) => a.order - b.order);
        const target = [...ordered].reverse().find((set) => !set.isWarmup) || ordered.at(-1);
        if (target) removeSet(se, target);
        save(); renderBody(body);
      } }),
      ui.h("button", { class: "btn sm ghost", text: "Rest", onClick: () => { currentSE = se; armRest(restFor(ex, se.programRole), se.exerciseName); } }),
      ui.h("button", { class: "btn sm ghost warn", text: "↓ Dropping load", onClick: () => dropLoad(se, body) }),
      // Remove the exercise from THIS session (program slot untouched).
      ui.h("button", { class: "btn sm ghost danger", text: "✕ Remove", onClick: () => {
        session.exercises = session.exercises.filter((x) => x !== se);
        if (currentSE === se) currentSE = null;
        save(); renderBody(body);
      } })));

    if (ex && ex.watchSite) card.append(ui.h("div", { class: "sub", style: { marginTop: "8px" }, text: `Watch: ${ex.watchSite.toLowerCase()} — ${watchNote(ex.watchSite)}` }));
    return card;
  }

  function editRest(se, ex, body) {
    if (!ex) { ui.toast("No library entry for this exercise."); return; }
    ui.sheet({
      title: `Rest — ${ex.name}`,
      build: (c) => {
        const render = () => {
          ui.clear(c);
          // Floor: the stepper shows the EFFECTIVE rest, so it can't offer 0
          // ("Default") without the display snapping to the bucket value —
          // except where the bucket itself is 0 (conditioning). Clearing an
          // override back to bucket-driven is the explicit Reset below.
          const floor = C.restDefaultSeconds(ex.category, ex.movementGroup, se.programRole, restCfg, 0) === 0 ? 0 : 15;
          c.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Rest between sets" }),
            ui.stepper(restFor(ex, se.programRole), { min: floor, max: 600, step: 15, format: ui.mmss, onChange: async (v) => { ex.defaultRestSeconds = v; await Exercises.save(ex); renderBody(body); render(); } })));
          if (ex.defaultRestSeconds > 0) {
            c.append(ui.h("button", { class: "btn ghost wide", style: { marginTop: "8px" }, text: "Reset to default", onClick: async () => {
              ex.defaultRestSeconds = 0; await Exercises.save(ex); renderBody(body); render();
            } }));
          }
          c.append(ui.h("div", { class: "sub", style: { marginTop: "8px" }, text: "Saved on the exercise — applies everywhere it's used. Default = the rest buckets in Settings." }));
        };
        render();
      },
    });
  }

  function barSelect(se, body) {
    const sel = ui.h("select", { class: "bar-select" },
      ...C.ALL_BARS.map((b) => ui.h("option", { value: C.barId(b), text: C.barLabel(b), selected: C.barId(b) === C.barId(barFor(se)) })));
    sel.addEventListener("change", () => {
      se.barId = sel.value;
      synchronizeWarmups(se, C.barById(sel.value));
      save(); renderBody(body);
    });
    return sel;
  }

  function setRow(se, s, body) {
    const ex = exMap.get(se.exerciseName);
    const u = setUnit(se, s);
    // Steady-state cardio (type conditioning: Walk/Bike/Ruck…) logs
    // distance/time/incline, not weight×reps — keyed on the exercise TYPE so
    // rep-based conditioning (burpees, type bodyweight) keeps the lifting row.
    const isCardio = ex && ex.type === "conditioning";
    const wt = isCardio
      ? ui.h("button", { class: "btn ghost", style: { padding: "4px 8px", minHeight: "40px" }, onClick: () => editCardioSet(se, s, body) },
          ui.h("span", { class: "wt mono", text: C.cardioSetLabel(s.distanceMiles, s.durationSeconds, s.inclinePercent) }),
          ui.h("span", { class: "sub", text: " distance · time · incline" }))
      : ui.h("button", { class: "btn ghost", style: { padding: "4px 8px", minHeight: "40px" }, onClick: () => editSet(se, s, body) },
          ui.h("span", { class: "wt mono" + (s.isWarmup ? " muted" : ""), text: s.weightLb === 0 ? "BW" : `${C.trim(u === "kg" ? C.kgFromLb(s.weightLb) : s.weightLb)} ${u}` }),
          ui.h("span", { class: "sub mono", text: ` × ${s.reps}${s.isPerSide ? "/side" : ""}` }));
    const tags = ui.h("span", { class: "sub" });
    if (s.isWarmup) tags.append(ui.h("span", { class: "pill", text: "warmup" }));
    if (s.autoregReason) tags.append(ui.h("span", { class: "pill warn", text: `↓ ${s.autoregReason}` }));
    if (s.bodyFlagSite) tags.append(ui.h("span", { class: "pill hard", text: "⚡︎" }));

    const statusButton = ui.h("button", {
      class: `flagbtn${s.status === "completed" ? " on-clean" : ""}`,
      text: s.status === "completed" ? "✓" : (s.status === "skipped" ? "−" : "○"),
      "aria-label": `Set status: ${s.status}`,
      onClick: () => chooseStatus(se, s, body),
    });
    const quality = C.setQuality(s.flags);
    const qualityButton = ui.h("button", {
      class: `flagbtn${quality ? ` on-${quality}` : ""}`,
      text: quality === "clean" ? "✓" : (quality ? quality[0].toUpperCase() : "Q"),
      "aria-label": `Set quality: ${quality || "not graded"}`,
      onClick: () => chooseQuality(s, body),
    });
    // The set you're ON — the first WORKING set with no verdict yet — gets
    // the accent rail; warmups sit quiet (and often go unflagged, so they
    // must not hold the rail hostage).
    const isCurrent = se.sets.find((x) => !x.isWarmup && x.status === "planned") === s;
    const row = ui.h("div", { class: "setrow" + (s.isWarmup ? " warm" : "") + (isCurrent ? " current" : "") }, wt, tags,
      ui.h("div", { class: "flagbtns" }, statusButton, isCardio ? null : qualityButton));

    // Loadout visualization — plates for barbell lifts, the rack number for
    // dumbbell lifts. Mirrors native.
    if (ex && ex.type === "barbell" && s.weightLb > 0) {
      const { svg, solution } = barbellSVG(s.weightLb, u, barFor(se), gymState.value);
      const wrap = ui.h("div", { class: "barbell-wrap" }, svg);
      if (solution.isOffTarget) {
        const t = u === "kg" ? C.kgFromLb(solution.totalLb) : solution.totalLb;
        wrap.append(ui.h("span", { class: "sub warn", text: `≈ closest ${C.trim(t)} ${u}` }));
      }
      return ui.h("div", {}, row, wrap);
    }
    if (ex && ex.type === "dumbbell" && s.weightLb > 0) {
      return ui.h("div", {}, row, ui.h("div", { class: "barbell-wrap" },
        dumbbellSVG(s.weightLb, u), ui.h("span", { class: "sub", text: u })));
    }
    return row;
  }

  function chooseStatus(se, s, body) {
    currentSE = se;
    ui.actionSheet("Set status", ["planned", "completed", "skipped"].map((status) => ({
      label: status[0].toUpperCase() + status.slice(1),
      onClick: () => {
        const newlyCompleted = status === "completed" && s.status !== "completed";
        s.status = status;
        if (newlyCompleted && settings.autoStartRest && !rest.running) armRest(restFor(exMap.get(se.exerciseName), se.programRole), se.exerciseName);
        save(); renderBody(body);
      },
    })));
  }

  function chooseQuality(s, body) {
    ui.actionSheet("Set quality", [null, "clean", "grindy", "wobble"].map((quality) => ({
      label: quality ? quality[0].toUpperCase() + quality.slice(1) : "Not graded",
      onClick: () => {
        s.flags = C.normalizedSetFlags(quality, (s.flags || []).includes("stopped early"));
        save(); renderBody(body);
      },
    })));
  }

  function addSet(se) {
    const last = se.sets[se.sets.length - 1];
    const ex = exMap.get(se.exerciseName);
    const w = last ? last.weightLb : (se.plannedWeightLb ?? 45);
    const r = last ? last.reps : (se.plannedReps ?? 5);
    const set = mkSet(se.sets.length, w, r, { perSide: ex && ex.isUnilateral });
    set.enteredUnit = exUnit(se);
    if (ex && ex.type === "conditioning" && last) {
      // Repeat intervals: carry the last round's cardio prescription forward.
      set.distanceMiles = last.distanceMiles ?? null;
      set.durationSeconds = last.durationSeconds ?? null;
      set.inclinePercent = last.inclinePercent ?? null;
    }
    se.sets.push(set);
    syncSetPlan(se);
  }

  function syncSetPlan(se) {
    se.sets.forEach((set, index) => { set.order = index; });
    se.plannedSets = se.sets.filter((set) => !set.isWarmup).length;
  }

  function removeSet(se, set) {
    se.sets = se.sets.filter((candidate) => candidate !== set);
    syncSetPlan(se);
  }

  function dropLoad(se, body) {
    ui.actionSheet("Dropping load — why?", C.AUTOREG_REASONS.map((reason) => ({
      label: reason,
      onClick: () => {
        // Shared plan (core parity): unflagged working sets only, each dropped
        // from its own weight — a back-off set is never raised.
        const plan = C.dropLoadPlan(se.sets.map((x) => ({ weightLb: x.weightLb, isWarmup: !!x.isWarmup, isFlagged: x.status !== "planned" })));
        if (!plan.length) { ui.toast("All sets already logged — nothing to drop."); return; }
        plan.forEach((p, i) => { const x = se.sets[p.index]; x.weightLb = p.weightLb; if (i === 0) x.autoregReason = reason; });
        save(); renderBody(body);
        ui.toast(`Dropped to ${ui.fmtWeight(Math.max(...plan.map((p) => p.weightLb)))}`);
      },
    })));
  }

  function editSet(se, s, body) {
    ui.sheet({
      title: "Edit set",
      build: (c, api) => {
        let unit = setUnit(se, s);
        const shown = unit === "kg" ? C.kgFromLb(s.weightLb) : s.weightLb;
        const wInput = ui.h("input", { class: "big-num", type: "number", inputmode: "decimal", step: "0.5", value: s.weightLb === 0 ? "" : C.trim(shown, 2) });
        c.append(ui.field("Weight (0 = bodyweight)", wInput));
        c.append(ui.field("Unit", ui.seg([{ value: "lb", label: "lb" }, { value: "kg", label: "kg" }], unit, (u) => { unit = u; })));
        let reps = s.reps;
        c.append(ui.field("Reps", ui.stepper(reps, { min: 0, max: 100, onChange: (v) => { reps = v; } })));
        let warm = s.isWarmup, per = s.isPerSide, site = s.bodyFlagSite;
        let stopped = (s.flags || []).includes("stopped early");
        let applyToRemaining = !s.isWarmup && s.status === "planned";
        c.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Warmup" }), ui.toggle(warm, (v) => { warm = v; })));
        c.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Per side" }), ui.toggle(per, (v) => { per = v; })));
        c.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Stopped early" }), ui.toggle(stopped, (v) => { stopped = v; })));
        if (!s.isWarmup && se.sets.some((candidate) => candidate !== s && !candidate.isWarmup && candidate.status === "planned")) {
          c.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Apply weight and reps to remaining planned sets" }),
            ui.toggle(applyToRemaining, (v) => { applyToRemaining = v; })));
        }
        const noteInput = ui.h("input", { type: "text", placeholder: "What did it feel like?", value: s.bodyFlagNote || "" });
        const siteSel = ui.h("select", {}, ui.h("option", { value: "", text: "None" }), ...BODY_SITES.map((b) => ui.h("option", { value: b, text: b, selected: b === site })));
        siteSel.addEventListener("change", () => { site = siteSel.value || null; });
        c.append(ui.field("Body signal", siteSel), ui.field("Signal note", noteInput));
        c.append(ui.h("button", {
          class: "btn primary wide", style: { marginTop: "10px" }, text: "Done",
          onClick: () => {
            const val = parseFloat(wInput.value) || 0;
            const weightLb = val === 0 ? 0 : C.toLb(val, unit);
            const targets = applyToRemaining && !warm
              ? se.sets.filter((set) => !set.isWarmup && (set === s || set.status === "planned"))
              : [s];
            for (const target of targets) { target.weightLb = weightLb; target.enteredUnit = unit; target.reps = reps; }
            s.isWarmup = warm; s.isPerSide = per;
            s.flags = C.normalizedSetFlags(C.setQuality(s.flags), stopped);
            s.bodyFlagSite = site; s.bodyFlagNote = site ? (noteInput.value || null) : null;
            syncSetPlan(se);
            if (applyToRemaining && !warm) {
              se.plannedWeightLb = weightLb;
              se.plannedReps = reps;
              synchronizeWarmups(se, barFor(se));
            }
            unitByEx[se.exerciseName] = unit; // keep the row display in the unit you just used
            api.close(); save(); renderBody(body);
          },
        }));
        c.append(ui.h("button", { class: "btn wide danger", style: { marginTop: "8px" }, text: "Delete set",
          onClick: () => { removeSet(se, s); api.close(); save(); renderBody(body); } }));
      },
    });
  }

  // Cardio (type conditioning) sets: distance / time / incline, speed derived.
  // Mirrors the native CardioSetSheet.
  function editCardioSet(se, s, body) {
    ui.sheet({
      title: `Log conditioning — ${se.exerciseName}`,
      build: (c, api) => {
        const distInput = ui.h("input", { class: "big-num", type: "number", inputmode: "decimal", step: "0.05", min: "0", placeholder: "0", value: s.distanceMiles > 0 ? C.trim(s.distanceMiles, 2) : "" });
        const minInput = ui.h("input", { type: "number", inputmode: "numeric", min: "0", placeholder: "0", value: s.durationSeconds > 0 ? String(Math.floor(s.durationSeconds / 60)) : "" });
        const secInput = ui.h("input", { type: "number", inputmode: "numeric", min: "0", max: "59", placeholder: "0", value: s.durationSeconds > 0 ? String(s.durationSeconds % 60) : "" });
        let incline = s.inclinePercent > 0 ? s.inclinePercent : 0;
        const speedLine = ui.h("div", { class: "sub", style: { margin: "6px 4px" } });
        const readSecs = () => (parseInt(minInput.value, 10) || 0) * 60 + (parseInt(secInput.value, 10) || 0);
        const paintSpeed = () => {
          const mph = C.cardioSpeedMph(parseFloat(distInput.value) || 0, readSecs());
          speedLine.textContent = mph !== null ? `Speed: ${C.trim(mph)} mph` : "";
        };
        [distInput, minInput, secInput].forEach((el) => el.addEventListener("input", paintSpeed));
        c.append(ui.field("Distance (mi)", distInput));
        c.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Time" }),
          ui.h("div", { style: { display: "flex", gap: "6px", alignItems: "center" } },
            minInput, ui.h("span", { class: "sub", text: "min" }), secInput, ui.h("span", { class: "sub", text: "sec" }))));
        c.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Incline" }),
          ui.stepper(incline, { min: 0, max: 30, step: 0.5, format: (v) => (v > 0 ? `${C.trim(v)}%` : "—"), onChange: (v) => { incline = v; } })));
        c.append(speedLine);
        paintSpeed();
        c.append(ui.h("button", {
          class: "btn primary wide", style: { marginTop: "10px" }, text: "Done",
          onClick: () => {
            const miles = parseFloat(distInput.value) || 0;
            const secs = readSecs();
            s.distanceMiles = miles > 0 ? miles : null;
            s.durationSeconds = secs > 0 ? secs : null;
            s.inclinePercent = incline > 0 ? incline : null;
            s.weightLb = 0; s.reps = Math.max(1, s.reps || 1); // cardio carries no load
            api.close(); save(); renderBody(body);
          },
        }));
        c.append(ui.h("button", { class: "btn wide danger", style: { marginTop: "8px" }, text: "Delete set",
          onClick: () => { removeSet(se, s); api.close(); save(); renderBody(body); } }));
      },
    });
  }

  async function pickExercise(body) {
    const all = await Exercises.all();
    ui.sheet({
      title: "Add exercise",
      build: (c, api) => {
        const search = ui.h("input", { type: "search", placeholder: "Exercise or movement" });
        const results = ui.h("div");
        const paint = () => {
          ui.clear(results);
          const term = search.value.trim().toLowerCase();
          const visible = term ? all.filter((exercise) => [exercise.name, exercise.movementGroup].some((value) => String(value || "").toLowerCase().includes(term))) : all;
          for (const cat of CATEGORIES) {
            const inCat = visible.filter((e) => e.category === cat).sort((a, b) => a.name.localeCompare(b.name));
            if (!inCat.length) continue;
            results.append(ui.h("div", { class: "section-title", text: cat }));
            for (const e of inCat) {
              results.append(ui.h("button", { class: "btn wide ghost", style: { marginTop: "6px", justifyContent: "space-between" },
                onClick: () => {
                  session.exercises.push({ order: session.exercises.length, exerciseName: e.name, notes: "", phase: null, plannedWeightLb: null, plannedSets: null, plannedReps: null, sets: [] });
                  api.close(); save(); renderBody(body);
                } },
                ui.h("span", { text: e.name }), e.isShelved ? ui.h("span", { class: "pill hard", text: COPY.shelved }) : ui.h("span")));
            }
          }
        };
        search.addEventListener("input", paint);
        c.append(search, results);
        paint();
      },
    });
  }

  let finishing = false; // double-tap on Bank it would run completion twice (dup milestones, racy advances)
  async function finish() {
    if (finishing) return;
    const working = session.exercises.flatMap((se) => se.sets || []).filter((set) => !set.isWarmup);
    const completed = working.filter((set) => set.status === "completed").length;
    const unfinished = working.filter((set) => set.status === "planned").length;
    if (unfinished) {
      ui.actionSheet(`Bank completed work? ${completed} completed; ${unfinished} planned set${unfinished === 1 ? " is" : "s are"} unfinished.`, [
        { label: "Bank completed work", onClick: () => bankNow() },
        { label: "Keep logging", role: "cancel", onClick: () => {} },
      ]);
      return;
    }
    await bankNow();
  }
  async function bankNow() {
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
    const working = se.sets.filter((s) => !s.isWarmup && s.status === "completed").map((s) => ({ weightLb: s.weightLb, reps: s.reps }));
    if (!working.length) continue;

    const historySets = [], historyVolumes = [], historySchemes = new Set();
    for (const ps of prior) {
      for (const pe of ps.exercises) {
        if (pe.exerciseName !== se.exerciseName) continue;
        const w = pe.sets.filter((x) => !x.isWarmup && x.status === "completed").map((x) => ({ weightLb: x.weightLb, reps: x.reps }));
        if (!w.length) continue;
        historySets.push(...w);
        historyVolumes.push(w.reduce((a, b) => a + b.weightLb * b.reps, 0));
        const top = C.prTopScheme(w); if (top) historySchemes.add(`${top.sets}×${top.reps}`);
      }
    }
    const events = C.prEvaluate({ exercise: se.exerciseName, sessionSets: working, historySets, historyVolumes, historySchemes, formatWeight: ui.fmtWeight });
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
    lines.push({ exerciseName: se.exerciseName, topSetLabel: `${ui.fmtWeight(top.weightLb)} × ${top.reps}`, volumeLb: working.reduce((a, s) => a + s.weightLb * s.reps, 0) });
  }

  const hasCompletedWork = session.exercises.some((se) => se.sets.some((set) => !set.isWarmup && set.status === "completed"));
  const prog = session.programTag && hasCompletedWork ? await advanceProgram(session, milestones) : null;
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
function cyclePerf(se, roundingLb) {
  const w = se.sets.filter((s) => !s.isWarmup && s.status === "completed");
  const presReps = se.plannedReps ?? (w.length ? Math.max(...w.map((s) => s.reps)) : 0); // ?? not ||: mirrors Swift's nil-coalescing
  const top = w.reduce((b, s) => (!b || s.weightLb > b.weightLb ? s : b), null);
  return {
    prescribedSets: se.plannedSets ?? w.length, prescribedReps: presReps,
    completedSets: w.filter((s) => s.reps >= presReps).length,
    anyStoppedEarly: w.some((s) => (s.flags || []).includes("stopped early")),
    anyDroppedLoad: w.some((s) => !!s.autoregReason),
    anyBelowPlanLoad: C.belowPlanWork(w.map((s) => s.weightLb), se.plannedWeightLb, se.plannedSets ?? w.length, roundingLb),
    grindyOrWobbleSets: w.filter((s) => (s.flags || []).some((f) => f === "grindy" || f === "wobble")).length,
    topSetWeightLb: top ? top.weightLb : 0, topSetReps: top ? top.reps : 0,
  };
}
function accPerf(se) {
  const w = se.sets.filter((s) => !s.isWarmup && s.status === "completed");
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
  const program = await Programs.byStableId(tag.programId)
    || (await Programs.all()).find((candidate) => candidate.name === tag.programName);
  if (!program) return null;
  const exerciseByName = new Map((await Exercises.all()).map((exercise) => [exercise.name, exercise]));
  const day = program.days.find((d) => d.order === tag.dayIndex);
  if (!day) return null;
  const note = (label, name) => milestones.push({ kind: "programNote", exercise: name, label, _persist: { exerciseName: name, label } });
  // Program notes become milestones so the explanation shows in History; the
  // caller persists them with the rest of the completion transaction.
  const flushNotes = () => {
    const noteRecords = [];
    for (const m of milestones) {
      if (m.kind === "programNote" && m._persist) { noteRecords.push({ date: iso(new Date(session.date)), exerciseName: m._persist.exerciseName, kind: "programNote", label: m._persist.label }); delete m._persist; }
    }
    return noteRecords;
  };

  // Duplicate/stale guard: the tag captured at creation must still match the
  // program's live position, or this bank must not move the schedule again.
  if (!C.sessionTagCurrent(tag.cycleNumber, tag.week, tag.dayIndex, program.cycleNumber, program.currentWeek, program.nextDayIndex)) {
    note(`${program.name}: banked a session from cycle ${tag.cycleNumber} week ${tag.week} day ${tag.dayIndex + 1}, but the program has moved on — kept as history, schedule not advanced twice.`, null);
    return { program: null, noteRecords: flushNotes() };
  }

  // Accessories: double progression, evaluated every bank.
  for (const acc of day.accessories || []) {
    const se = session.exercises.find((e) => e.programSlotId === acc.id
      || (!e.programSlotId && e.programRole === "accessory" && e.exerciseName === acc.exerciseName));
    if (se && se.sets.some((set) => !set.isWarmup && set.status === "completed")) Object.assign(acc, C.advanceAccessory(acc, accPerf(se)));
  }
  // Cycle lifts: grade at the week-3 Peak, stash pending; apply at rollover.
  if (tag.week === 3) {
    for (const lift of day.lifts || []) {
      const se = session.exercises.find((e) => e.programSlotId === lift.id
        || (!e.programSlotId && e.exerciseName === lift.exerciseName && e.programRole === lift.role));
      if (se && se.sets.some((set) => !set.isWarmup && set.status === "completed")) {
        const loadStep = C.programLoadStep(program.roundingLb, exerciseByName.get(se.exerciseName)?.type);
        lift.pending = C.advanceCycleLift(lift, cyclePerf(se, loadStep), program.focus, loadStep);
      }
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
            const oldBase = lift.baseWeightLb;
            lift.baseWeightLb = p.baseWeightLb; lift.estimatedMaxLb = p.estimatedMaxLb;
            lift.stallCount = p.stallCount; lift.lastIncrementLb = p.lastIncrementLb;
            if (lift.pending.note) {
              const presented = lift.pending.note.startsWith("Two cycles without a clean peak")
                ? `Two cycles without a clean peak — deloaded ${ui.fmtWeight(oldBase)}→${ui.fmtWeight(p.baseWeightLb)} to rebuild.`
                : lift.pending.note;
              note(`${lift.exerciseName}: ${presented}`, lift.exerciseName);
            }
            delete lift.pending;
          } else {
            lift.stallCount = (lift.stallCount || 0) + 1; lift.lastIncrementLb = 0;
            if (lift.stallCount >= C.STALL_LIMIT) {
              const old = lift.baseWeightLb;
              const loadStep = C.programLoadStep(program.roundingLb, exerciseByName.get(lift.exerciseName)?.type);
              lift.baseWeightLb = C.roundTo(old * C.DELOAD_REBUILD_FRACTION, loadStep);
              lift.stallCount = 0;
              note(`${lift.exerciseName}: skipped peak — deloaded ${ui.fmtWeight(old)}→${ui.fmtWeight(lift.baseWeightLb)}.`, lift.exerciseName);
            }
          }
          // A cycle-scoped swap ends with the cycle (mirrors native; the swap
          // gesture is native-only, but this state can arrive via backup).
          if (lift.revertToExerciseName) {
            const original = lift.revertToExerciseName;
            note(`${original}: cycle swap over — slot reverts from ${lift.exerciseName} for the new cycle.`, original);
            lift.exerciseName = original;
            delete lift.revertToExerciseName;
          }
        }
        for (const acc of d.accessories || []) {
          if (acc.revertToExerciseName) {
            const original = acc.revertToExerciseName;
            note(`${original}: cycle swap over — slot reverts from ${acc.exerciseName} for the new cycle.`, original);
            acc.exerciseName = original;
            delete acc.revertToExerciseName;
          }
        }
      }
      program.cycleNumber += 1;
      program.currentWeek = 1;
    }
  }
  return { program, noteRecords: flushNotes() };
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
  // Resume, don't duplicate — but only a session for THIS day at the current
  // position whose BUILT-FROM plan still matches the current plan (issue 17).
  // A name/program-only match resurrected stale snapshots after a day was
  // edited; canResume compares the snapshot (not live exercises) so a
  // session-local remove/swap is preserved while a program edit builds fresh.
  const sortedLifts = [...day.lifts].sort((a, b) => (a.role === "main" ? 0 : 1) - (b.role === "main" ? 0 : 1));
  const dayNames = [...sortedLifts.map((l) => l.exerciseName), ...(day.accessories || []).map((a) => a.exerciseName)];
  const stableProgramID = program.uuid || program.id;
  const openForDay = (await Sessions.all()).find((s) => !s.isCompleted && s.programTag
    && (s.programTag.programId === stableProgramID || (s.programTag.programId == null && s.programTag.programName === program.name))
    && C.canResumeSession(s.programTag.cycleNumber, s.programTag.week, s.programTag.dayIndex,
      program.cycleNumber, program.currentWeek, day.order,
      s.programTag.planNames || [], dayNames));
  if (openForDay) return openForDay.id;
  const [allExercises, gym, settings] = await Promise.all([Exercises.all(), Gyms.default(), Settings.get()]);
  const exMap = new Map(allExercises.map((e) => [e.name, e]));
  const unit = C.primaryUnit(settings.unitDisplay);
  const barLb = C.barLb(gym ? C.barById(gym.defaultBarId) : C.BARS.bar45lb);
  const neat = (weightLb, ex, isMain) => neatProgramWeight(weightLb, ex, isMain, barLb, program.roundingLb);
  const exercises = [];
  let order = 0;
  const lifts = [...(day.lifts || [])].sort((a, b) => (a.role === "main" ? 0 : 1) - (b.role === "main" ? 0 : 1));
  for (const lift of lifts) {
    const ex = exMap.get(lift.exerciseName);
    const loadStep = C.programLoadStep(program.roundingLb, ex?.type);
    const plan = C.programPlanFor({ cycleNumber: program.cycleNumber, baseWeightLb: lift.baseWeightLb, nextPhase: program.currentWeek, incrementLb: 0 }, program.roundingLb, ex?.type);
    const weightLb = neat(plan.weightLb, ex, lift.role === "main");
    const sets = [];
    let so = 0;
    if (ex && ex.type === "barbell") for (const wu of C.warmupRamp(weightLb, barLb, program.roundingLb)) sets.push(mkSet(so++, wu.weightLb, wu.reps, { warm: true, unit }));
    if (ex && ex.type === "dumbbell" && lift.role === "main") for (const wu of C.dumbbellWarmupRamp(weightLb, loadStep)) sets.push(mkSet(so++, wu.weightLb, wu.reps, { warm: true, unit, perSide: ex.isUnilateral }));
    for (let i = 0; i < plan.sets; i += 1) sets.push(mkSet(so++, weightLb, plan.reps, { perSide: ex && ex.isUnilateral, unit }));
    exercises.push({ order: order++, exerciseName: lift.exerciseName, notes: "", phase: program.currentWeek, plannedWeightLb: weightLb, plannedSets: plan.sets, plannedReps: plan.reps, programRole: lift.role, programSlotId: lift.id, sets });
  }
  for (const acc of day.accessories || []) {
    const ex = exMap.get(acc.exerciseName);
    const weightLb = neat(acc.weightLb, ex, false);
    const sets = [];
    for (let i = 0; i < acc.sets; i += 1) sets.push(mkSet(i, weightLb, acc.currentReps, { perSide: ex && ex.isUnilateral, unit }));
    exercises.push({ order: order++, exerciseName: acc.exerciseName, notes: "", phase: null, plannedWeightLb: weightLb, plannedSets: acc.sets, plannedReps: acc.currentReps, programRole: "accessory", programSlotId: acc.id, sets });
  }
  const id = await Sessions.save({
    date: iso(new Date()), notes: "", isCompleted: false, ...await defaultGymTag(),
    programTag: { programId: stableProgramID, programName: program.name, cycleNumber: program.cycleNumber, week: program.currentWeek, dayIndex: day.order, planNames: dayNames },
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
            ui.h("span", { class: "sub mono", text: `Top ${l.topSetLabel} · Volume ${ui.fmtWeight(l.volumeLb)}` }))));
      }
      if (summary.milestones.length) {
        c.append(ui.h("div", { class: "section-title", text: "Milestones" }));
        for (const m of summary.milestones) c.append(ui.h("div", { class: "row" }, ui.h("span", { class: "accent", text: `⚑ ${m.label}` })));
      }
      c.append(ui.h("button", { class: "btn primary wide", style: { marginTop: "12px" }, text: "Done", onClick: () => { api.close(); onDone(); } }));
    },
  });
}
