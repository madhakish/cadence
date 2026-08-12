// Active-session logger — the core daily screen. Set entry, quality flags,
// rest timer, autoregulation, body signals, completion + PR detection.
import * as ui from "../ui.js";
import * as C from "../core.js";
import { BODY_SITES, CATEGORIES, watchNote, COPY } from "../constants.js";
import { Sessions, Exercises, Tracks, Gyms, Milestones, Programs, Settings, CoachingDecisions, Checkins, iso, runAll } from "../db.js";
import { barbellSVG, dumbbellSVG, prescriptionPlateDetails } from "../barbell.js";
import { effectiveAccessoryPercent, coachingReport } from "../coaching-adapter.js";
import { exerciseDetail } from "./settings.js";

const trackState = (t) => ({ cycleNumber: t.cycleNumber, baseWeightLb: t.baseWeightLb, nextPhase: t.nextPhase, incrementLb: t.incrementLb });
const mkSet = (order, w, r, o = {}) => ({
  order, weightLb: w, reps: r, isWarmup: !!o.warm, isPerSide: !!o.perSide, enteredUnit: o.unit || "lb",
  targetWeightLb: o.targetWeightLb ?? w,
  plannedWeightLb: o.plannedWeightLb ?? w,
  plannedReps: o.plannedReps ?? r,
  plannedDurationSeconds: o.plannedDurationSeconds ?? null,
  prescriptionBlock: o.prescriptionBlock || (o.warm ? "warmup" : "work"),
  loadBasis: C.LOAD_BASES.includes(o.loadBasis) ? o.loadBasis : C.inferredLoadBasis(o.exerciseType),
  implementCount: Math.max(1, o.implementCount || C.inferredImplementCount(o.exerciseType)),
  status: "planned",
  flags: [], bodyFlagSite: null, bodyFlagNote: null, durationSeconds: null, distanceMiles: null,
  flights: null, inclinePercent: null, autoregReason: null,
});
const loadOptions = (exercise) => ({
  loadBasis: C.resolvedLoadBasis(exercise), implementCount: C.resolvedImplementCount(exercise),
  exerciseType: exercise?.type,
});

const availablePlates = (gym, exercise = null) => {
  const rack = !gym || !Array.isArray(gym.plateToggles) || !gym.plateToggles.length
    ? C.ALL_STANDARD
    : gym.plateToggles.filter((toggle) => toggle.enabled)
      .map((toggle) => ({ value: toggle.value, unit: toggle.unit }));
  // The lift's station preference (v8) filters the gym rack to its own
  // denomination — the kg-only deadlift platform beside the lb squat racks.
  return C.stationPlates(exercise?.stationDenomination ?? null, rack);
};

// The theoretical ramp describes useful jumps; the stored ramp must describe
// plates that actually exist. Collapse duplicate/equal-to-working results when
// a sparse rack maps several targets to the same achievable load.
export function achievableWarmups(ramp, workingLb, bar, gym = null, exercise = null) {
  const plates = availablePlates(gym, exercise);
  const collarLb = gym?.collarWeightLb || 0;
  const policy = gym?.loadingPolicy || "closest";
  const seen = new Set();
  const achieved = [];
  for (const warmup of ramp) {
    // A near-miss clean stack (e.g. kg plates on a lb ramp) stays loading
    // guidance — the neat theoretical step is what gets stored.
    const weightLb = C.storedPrescription(
      warmup.weightLb, C.solve(warmup.weightLb, bar, plates, 10, collarLb, policy).totalLb,
      C.barLabelLb(bar),
    );
    const key = weightLb.toFixed(6);
    if (weightLb >= workingLb - 1e-9 || seen.has(key)) continue;
    seen.add(key);
    achieved.push({ ...warmup, weightLb });
  }
  return achieved;
}

export function includesEmptyBarWarmup(exerciseName) {
  const key = String(exerciseName || "").toLowerCase().replace(/[^a-z0-9]/g, "");
  return !["backsquat", "deadlift"].includes(key);
}

async function defaultGymTag() { const g = await Gyms.default(); return { gymId: g?.id || null, gymName: g?.name || null }; }

export async function createSessionFromTrack(track) {
  const [ex, gym, settings] = await Promise.all([Exercises.byName(track.exerciseName), Gyms.default(), Settings.get()]);
  const unit = C.primaryUnit(settings.unitDisplay);
  const bar = gym ? C.barById(gym.defaultBarId) : C.BARS.bar45lb;
  const barLb = C.barLb(bar);
  const sug = track.mode === "cycle" ? C.planFor(trackState(track)) : C.linearPlan(track.baseWeightLb);
  const workingLb = ex?.type === "barbell" && gym
    ? neatProgramWeight(sug.weightLb, ex, true, barLb, track.roundingLb, gym, sug.phase)
    : sug.weightLb;
  const sets = [];
  let order = 0;
  if (ex && ex.type === "barbell") {
    const ramp = achievableWarmups(
      C.warmupRamp(workingLb, barLb, track.roundingLb, includesEmptyBarWarmup(ex.name)),
      workingLb, bar, gym, ex,
    );
    for (const w of ramp) sets.push(mkSet(order++, w.weightLb, w.reps, { warm: true, unit, ...loadOptions(ex) }));
  }
  if (ex && ex.type === "dumbbell") {
    for (const w of C.dumbbellWarmupRamp(workingLb, C.programLoadStep(track.roundingLb, ex.type))) {
      sets.push(mkSet(order++, w.weightLb, w.reps, { warm: true, unit, perSide: !!ex.isUnilateral, ...loadOptions(ex) }));
    }
  }
  for (let i = 0; i < sug.sets; i += 1) sets.push(mkSet(order++, workingLb, sug.reps, {
    targetWeightLb: sug.weightLb, plannedWeightLb: workingLb, plannedReps: sug.reps,
    perSide: ex && ex.isUnilateral, unit, ...loadOptions(ex),
  }));
  const se = { order: 0, exerciseName: track.exerciseName, notes: "", phase: sug.phase || null,
    targetWeightLb: sug.weightLb, plannedWeightLb: workingLb, plannedSets: sug.sets, plannedReps: sug.reps, sets };
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
  const sessionProgram = session.programTag
    ? await Programs.byStableId(session.programTag.programId)
      || (await Programs.all()).find((candidate) => candidate.name === session.programTag.programName)
    : null;
  const sessionDayName = session.programTag
    ? sessionProgram?.days?.find((day) => day.order === session.programTag.dayIndex)?.name
    : null;
  const workoutName = sessionDayName || session.programTag?.programName || "Workout";
  const save = () => Sessions.save(session);

  // Program recall is slot-scoped. Same-name main/complementary work on other
  // days and slotless extra work are different exposures.
  function lastTimeLine(current) {
    const tag = session.programTag;
    const matchingEntry = (past) => {
      if (!current.programRole) return (past.exercises || []).find((candidate) =>
        candidate.exerciseName === current.exerciseName && !candidate.programRole);
      const pastTag = past.programTag;
      if (!tag || !pastTag) return null;
      const programIds = new Set([tag.programId, sessionProgram?.uuid, sessionProgram?.id]
        .filter((value) => value != null));
      const sameProgram = programIds.has(pastTag.programId)
        || (pastTag.programId == null && tag.programName === pastTag.programName);
      if (!sameProgram || tag.dayIndex !== pastTag.dayIndex) return null;
      return programmedEntry(past, current);
    };
    const dayName = tag ? sessionProgram?.days?.find((day) => day.order === tag.dayIndex)?.name : null;
    const prefix = ["Last", current.programRole, dayName].filter(Boolean).join(" ");
    for (const p of priorSessions) {
      const entry = matchingEntry(p);
      const recalledSets = entry && current.programRole
        ? (entry.sets || []).filter((set) => !set.isWarmup
          && C.countsAsProgramInstruction(set.prescriptionBlock))
          .slice(0, entry.plannedSets ?? entry.sets.length)
          .filter((set) => set.status === "completed")
        : (entry?.sets || []).filter((set) => !set.isWarmup && set.status === "completed");
      const top = recalledSets.reduce((best, set) => (!best || set.weightLb > best.weightLb ? set : best), null);
      if (!top) continue;
      const w = top.weightLb === 0 ? "BW" : ui.fmtWeight(top.weightLb);
      return `${prefix}: ${w}×${top.reps} · ${ui.fmtDate(p.date)} (${agoLabel(p.date)})`;
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
  const synchronizeWarmups = (se, bar, overrideWorkingLb = null) => {
    const ex = exMap.get(se.exerciseName);
    const working = (se.sets || []).filter((set) => !set.isWarmup).sort((a, b) => a.order - b.order);
    const workingLb = overrideWorkingLb ?? se.plannedWeightLb ?? working[0]?.weightLb;
    if (!ex || !(workingLb > 0)) return;
    const fullRamp = ex.type === "barbell"
      ? achievableWarmups(
        C.warmupRamp(workingLb, C.barLb(bar), 5, includesEmptyBarWarmup(ex.name)),
        workingLb, bar, gymState.value, ex,
      )
      : (ex.type === "dumbbell" && se.programRole === "main" ? C.dumbbellWarmupRamp(workingLb, 5) : null);
    if (!fullRamp) return;
    const existing = (se.sets || []).filter((set) => set.isWarmup).sort((a, b) => a.order - b.order);
    // A programmed entry was built under a resolved warmup policy — full ramp,
    // two bridging sets for a complementary lift, or none — possibly refined
    // by the user's own row edits. Resync refreshes the warmup WEIGHTS for the
    // new bar/gym/working weight without changing how many warmups the plan
    // owns (the tail keeps the steps nearest the working weight); it must
    // never re-inflate a deliberately short or empty ramp. Manually added
    // exercises still grow a full ramp as before.
    const desired = se.programRole != null
      ? fullRamp.slice(Math.max(0, fullRamp.length - existing.length))
      : fullRamp;
    const warmups = desired.map((target, index) => {
      const set = existing[index] || mkSet(index, target.weightLb, target.reps, { warm: true, unit: exUnit(se), ...loadOptions(ex) });
      set.weightLb = target.weightLb; set.reps = target.reps; set.isWarmup = true;
      if (set.plannedWeightLb == null) set.plannedWeightLb = target.weightLb;
      if (set.plannedReps == null) set.plannedReps = target.reps;
      set.prescriptionBlock = "warmup";
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

  // Session stopwatch origin (ephemeral). NULL until the workout is started:
  // opening the logger to read the plan is not the same act as training, and a
  // clock that starts itself on open reports elapsed time nobody trained.
  let sessionStart = null;
  function startWorkout() { sessionStart = Date.now(); paintBar(); }
  function resetToNotStarted() { sessionStart = null; rest.stop(); paintBar(); }
  let currentSE = null;                       // the exercise you're actively working
  // Exercise AND role must come from the same session entry — pairing
  // exercises[0] with currentSE's (null) role resolved the first lift's rest
  // without its program role (mirrors native currentOrFirst).
  const currentEntry = () => currentSE
    || session.exercises.find((entry) => (entry.sets || []).some((set) => !set.isWarmup && set.status === "planned"))
    || session.exercises[0] || null;
  const currentExercise = () => exMap.get((currentEntry() || {}).exerciseName);
  const expandedEntries = new Set();

  const rest = makeRestTimer(() => paintBar(), () => onRestDone());
  let restLabel = "";
  let barEls = null;                          // bottom-bar refs, filled after pushScreen
  function armRest(seconds, label) { if (!(seconds > 0)) return; restLabel = label || ""; rest.start(seconds); paintBar(); } // 0/none (conditioning) arms nothing
  function onRestDone() { ui.toast(restLabel ? `Rest over · ${restLabel}.` : "Rest over."); beep(settings.haptics !== false); paintBar(); }

  function paintBar() {
    if (!barEls) return;
    barEls.clock.textContent = sessionStart == null
      ? "not started" : `${ui.mmss((Date.now() - sessionStart) / 1000)} session`;
    barEls.startBtn.style.display = sessionStart == null ? "" : "none";
    barEls.resetBtn.style.display = sessionStart == null ? "none" : "";
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
    const startBtn = ui.h("button", { class: "btn sm primary", text: "Start workout",
      "aria-label": "Start the workout clock for this session", onClick: () => startWorkout() });
    // The undo for starting by accident: back to not started, plan and any
    // logged work intact.
    const resetBtn = ui.h("button", { class: "btn sm ghost", style: { display: "none" }, text: "Reset",
      "aria-label": "Reset this session to not started", onClick: () => resetToNotStarted() });
    const prog = ui.h("i");
    barEls = { clock, restTime, restBtn, subBtn, addBtn, skipBtn, prog, startBtn, resetBtn };
    return ui.h("div", { id: "session-bar" },
      ui.h("div", { class: "session-bar-row" }, clock, ui.h("div", { class: "btn-row", style: { alignItems: "center" } }, startBtn, resetBtn, restTime, restBtn, subBtn, addBtn, skipBtn)),
      ui.h("div", { class: "progress" }, prog));
  }

  function renderBody(body) {
    ui.clear(body);
    session.exercises.sort((a, b) => a.order - b.order);
    const current = currentEntry();
    const exerciseNumber = current ? session.exercises.indexOf(current) + 1 : 0;
    const workSets = session.exercises.flatMap((entry) => (entry.sets || []).filter((set) => !set.isWarmup));
    // Position, not achievement: a skipped set is resolved and moves the
    // workout forward, so the ordinal must count it or skipping every set
    // would read "1 of N" forever. Mirrors the native progress card.
    const resolvedWork = workSets.filter((set) => set.status === "completed" || set.status === "skipped").length;
    body.append(ui.h("div", { class: "card session-progress" },
      ui.h("div", { class: "title mono", text: `Exercise ${exerciseNumber} of ${session.exercises.length} · ${workSets.length === 0 ? 0 : Math.min(resolvedWork + 1, workSets.length)} of ${workSets.length} work sets` }),
      ui.h("div", { class: "sub", text: ui.fmtDate(session.date) })));
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
    session.exercises.forEach((se) => body.append(exerciseCard(se, body)));

    body.append(ui.h("button", { class: "btn ghost wide", style: { marginTop: "12px" }, text: "+ Add exercise", onClick: () => pickExercise(body) }));

    const notes = ui.h("textarea", { rows: 2, placeholder: "Session notes", value: session.notes || "" });
    notes.addEventListener("input", () => { session.notes = notes.value; save(); });
    body.append(ui.h("div", { class: "section-title", text: "Session notes" }), notes);

    body.append(ui.h("button", { class: "btn primary wide", style: { marginTop: "16px", minHeight: "52px", fontSize: "18px" }, text: COPY.sessionDone, onClick: () => finish() }));
    body.append(ui.h("button", { class: "btn ghost danger wide", style: { marginTop: "8px" },
      text: "Discard this session", "aria-label": "Discard this session without banking it",
      onClick: () => discard() }));
  }

  function exerciseCard(se, body) {
    const ex = exMap.get(se.exerciseName);
    const phaseLabel = ui.sessionPhaseLabel(se, ex);
    const head = ui.h("div", { class: "row", style: { borderBottom: "0", paddingBottom: "2px" } },
      ui.h("div", { class: "lead" },
        // The name is the door to the lift itself — muscles figure, history,
        // settings — mid-workout, same as the program editor and library. A
        // real button, not a click-handled span: keyboard focus and
        // Enter/Space work, and the house 44px target applies. The detail
        // screen live-edits this exercise (rest, load basis, shelving), so
        // Back repaints the logger — otherwise the card keeps showing the
        // pre-edit prescription state.
        ex
          ? ui.h("button", { class: "title title-button", text: se.exerciseName,
            "aria-label": `${se.exerciseName} — muscles, history, and settings`,
            onClick: () => exerciseDetail(ex, { onClose: () => renderBody(body) }) })
          : ui.h("span", { class: "title", text: se.exerciseName }),
        phaseLabel ? ui.h("span", { class: "sub accent", text: phaseLabel }) : null),
      ui.h("div", { class: "btn-row", style: { alignItems: "center", flexWrap: "wrap", justifyContent: "flex-end" } },
        ui.h("div", { style: { width: "100px" } },
          ui.seg([{ value: "lb", label: "lb" }, { value: "kg", label: "kg" }], exUnit(se), (u) => { unitByEx[se.exerciseName] = u; renderBody(body); })),
        ex && ex.type === "barbell" ? barSelect(se, body) : null,
        ui.h("button", { class: "btn sm ghost", text: `⏱ ${ui.mmss(restFor(ex, se.programRole))}`, onClick: () => editRest(se, ex, body) }),
        ex && ex.isShelved ? ui.h("span", { class: "pill hard", text: COPY.shelved }) : null));
    const card = ui.h("div", { class: "card" }, head);
    const last = lastTimeLine(se);
    if (last) card.append(ui.h("div", { class: "sub", style: { margin: "0 0 6px" }, text: last }));

    se.sets.sort((a, b) => a.order - b.order);
    const showAll = expandedEntries.has(se);
    const currentSet = se.sets.find((set) => !set.isWarmup && set.status === "planned");
    se.sets.forEach((s, index) => {
      const prior = se.sets[index - 1];
      const loadChange = !!prior && (Math.abs((prior.weightLb || 0) - (s.weightLb || 0)) > 0.001
        || prior.loadBasis !== s.loadBasis || (prior.implementCount || 1) !== (s.implementCount || 1));
      card.append(setRow(se, s, body, {
        compact: !showAll && s !== currentSet,
        showLoadout: showAll || s === currentSet || loadChange,
      }));
    });

    if (se.sets.length > 1) card.append(ui.h("button", { class: "btn sm ghost wide",
      text: showAll ? "Focus current set" : "Show all sets", onClick: () => {
        if (showAll) expandedEntries.delete(se); else expandedEntries.add(se);
        renderBody(body);
      } }));

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

  function setRow(se, s, body, { compact = false, showLoadout = true } = {}) {
    const ex = exMap.get(se.exerciseName);
    const u = setUnit(se, s);
    // Steady-state cardio (type conditioning: Walk/Bike/Ruck…) logs
    // distance/time/incline, not weight×reps — keyed on the exercise TYPE so
    // rep-based conditioning (burpees, type bodyweight) keeps the lifting row.
    const isCardio = ex && ex.type === "conditioning";
    const isTimed = ex && ex.type === "timed";
    const wt = isCardio
      ? ui.h("button", { class: "btn ghost", style: { padding: "4px 8px", minHeight: "40px" }, onClick: () => editCardioSet(se, s, body) },
          ui.h("span", { class: "wt mono", text: C.cardioSetLabel(s.distanceMiles, s.durationSeconds, s.inclinePercent, s.weightLb, s.flights) }),
          ui.h("span", { class: "sub", text: cardioHint(se.exerciseName, s) }))
      : isTimed
        ? ui.h("button", { class: "btn ghost", style: { padding: "4px 8px", minHeight: "40px" }, onClick: () => editTimedSet(se, s, body) },
          ui.h("span", { class: "wt mono", text: C.cardioDurationLabel(s.durationSeconds || 0) }),
          ui.h("span", { class: "sub", text: " hold time" }))
        : ui.h("button", { class: "btn ghost", style: { padding: "4px 8px", minHeight: "40px" }, onClick: () => editSet(se, s, body) },
          ui.h("span", { class: "wt mono" + (s.isWarmup ? " muted" : ""), text: s.weightLb === 0 ? "BW" : `${C.trim(u === "kg" ? C.kgFromLb(s.weightLb) : s.weightLb)} ${u}${C.loadBasisSuffix(s.loadBasis)}` }),
          ui.h("span", { class: "sub mono", text: ` × ${s.reps}${s.isPerSide ? "/side" : ""}` }));
    const tags = ui.h("span", { class: "sub" });
    if (s.isWarmup) tags.append(ui.h("span", { class: "pill", text: "warmup" }));
    // The prescribed reps are a FLOOR on an AMRAP set. Without saying so,
    // 5/3/1's week 3 reads as a plain single and the "+" — the whole
    // progression engine — never happens.
    if (!s.isWarmup && s.prescriptionBlock === "amrap") {
      tags.append(ui.h("span", {
        class: "pill accent",
        text: `AMRAP ${s.plannedReps ?? s.reps}+`,
        title: "Take this set past the target and stop when a rep turns grindy.",
      }));
    }
    if (s.autoregReason) tags.append(ui.h("span", { class: "pill warn", text: `↓ ${s.autoregReason}` }));
    if (s.bodyFlagSite) tags.append(ui.h("span", { class: "pill hard", text: "⚡︎" }));
    if (!isCardio && !isTimed && Number.isFinite(s.plannedWeightLb) && Number.isFinite(s.plannedReps)
        && (Math.abs(s.plannedWeightLb - s.weightLb) > 0.001 || s.plannedReps !== s.reps)) {
      tags.append(ui.h("span", { class: "pill", text: `planned ${ui.fmtWeight(s.plannedWeightLb)}×${s.plannedReps}` }));
    }

    const statusButton = ui.h("button", {
      class: `flagbtn${s.status === "completed" ? " on-clean" : ""}`,
      text: s.status === "completed" ? "✓" : (s.status === "skipped" ? "−" : "○"),
      "aria-label": `Set status: ${s.status}`,
      title: "Tap to complete or undo; hold for more set options",
      onClick: () => {
        currentSE = se;
        const newlyCompleted = s.status !== "completed";
        s.status = newlyCompleted ? "completed" : "planned";
        if (newlyCompleted && settings.autoStartRest && !rest.running) armRest(restFor(exMap.get(se.exerciseName), se.programRole), se.exerciseName);
        save(); renderBody(body);
      },
      onContextMenu: (event) => { event.preventDefault(); chooseStatus(se, s, body); },
    });
    const quality = C.setQuality(s.flags);
    const qualityButton = ui.h("button", {
      class: `flagbtn${quality ? ` on-${quality}` : ""}`,
      text: quality === "clean" ? "✓" : (quality ? quality[0].toUpperCase() : "Q"),
      "aria-label": `Set quality: ${quality || "not graded"}`,
      onClick: () => chooseQuality(s, body),
    });
    // Reps in reserve, beside quality rather than folded into it: quality says
    // how the bar moved, RIR says how close to failure it was. A set can be
    // clean at 3+ in reserve or clean at 1, and those mean different things.
    const rir = C.setRIR(s.flags);
    const rirButton = ui.h("button", {
      class: `flagbtn${rir ? " on-rir" : ""}`,
      text: rir ? rir.replace("rir", "").replace("3plus", "3+") : "R",
      "aria-label": `Reps in reserve: ${rir ? C.SET_RIR_LABELS[rir] : "not graded"}`,
      onClick: () => chooseRIR(s, body),
    });
    // The set you're ON — the first WORKING set with no verdict yet — gets
    // the accent rail; warmups sit quiet (and often go unflagged, so they
    // must not hold the rail hostage).
    const isCurrent = se.sets.find((x) => !x.isWarmup && x.status === "planned") === s;
    const row = ui.h("div", { class: "setrow" + (s.isWarmup ? " warm" : "")
      + (isCurrent ? " current current-set-card" : "") + (compact ? " compact" : "") }, wt, tags,
      ui.h("div", { class: "flagbtns" }, statusButton,
        (isCardio || isTimed) ? null : qualityButton,
        // Duration and conditioning work has no rep count, so reps-in-reserve
        // is meaningless there — same exclusion the quality button uses.
        (isCardio || isTimed) ? null : rirButton));

    // Loadout visualization — plates for barbell lifts, the rack number for
    // dumbbell lifts. Mirrors native.
    if (showLoadout && ex && ex.type === "barbell" && s.weightLb > 0) {
      const { svg, solution } = barbellSVG(s.weightLb, u, barFor(se), gymState.value, null,
        ex?.stationDenomination ?? null, "compact", ex?.movementGroup === "olympic" ? "bumper" : "steel");
      const wrap = ui.h("div", { class: "barbell-wrap" }, svg);
      if (solution.isOffTarget) {
        const t = u === "kg" ? C.kgFromLb(solution.totalLb) : solution.totalLb;
        wrap.append(ui.h("span", { class: "sub warn", text: `≈ closest ${C.trim(t)} ${u}` }));
      }
      for (const detail of prescriptionPlateDetails(
        s.targetWeightLb ?? se.targetWeightLb, s.weightLb, u, barFor(se), gymState.value,
        ex?.stationDenomination ?? null,
      )) {
        wrap.append(ui.h("span", { class: `sub plate-detail${detail.kind === "target" ? " warn" : ""}`, text: detail.text }));
      }
      return ui.h("div", {}, row, wrap);
    }
    if (showLoadout && ex && ex.type === "dumbbell" && s.weightLb > 0) {
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
        s.flags = C.normalizedSetFlags(quality, (s.flags || []).includes("stopped early"), C.setRIR(s.flags));
        save(); renderBody(body);
      },
    })));
  }

  function chooseRIR(s, body) {
    ui.actionSheet("Reps in reserve", [null, ...C.SET_RIRS].map((value) => ({
      label: value ? C.SET_RIR_LABELS[value] : "Not graded",
      onClick: () => {
        s.flags = C.normalizedSetFlags(C.setQuality(s.flags), (s.flags || []).includes("stopped early"), value);
        save(); renderBody(body);
      },
    })));
  }

  function addSet(se) {
    const last = se.sets[se.sets.length - 1];
    const ex = exMap.get(se.exerciseName);
    const durationBased = ex && (ex.type === "timed" || ex.type === "conditioning");
    // [INV-RUCK-CARRIES-ITS-LOAD] Duration-based work is unloaded EXCEPT a
    // loaded carry, which is born wearing its pack and carries that weight to
    // the next leg. Defaulting on first edit cannot work: a conditioning set is
    // created with a planned duration, so afterwards it is indistinguishable
    // from one the lifter deliberately set to zero.
    const carryLb = ex && ex.type === "conditioning" && C.cardioCarriesLoad(se.exerciseName)
      ? (last ? last.weightLb : (C.cardioDefaultLoadLb(se.exerciseName) ?? 0))
      : 0;
    const w = durationBased ? carryLb : (last ? last.weightLb : (se.plannedWeightLb ?? 45));
    const r = durationBased ? 1 : (last ? last.reps : (se.plannedReps ?? 5));
    const inheritedLoad = last && C.LOAD_BASES.includes(last.loadBasis)
      ? { loadBasis: last.loadBasis, implementCount: last.implementCount }
      : loadOptions(ex);
    const durationSeconds = last?.durationSeconds ?? se.plannedDurationSeconds ?? 30;
    const set = mkSet(se.sets.length, w, r, {
      perSide: ex && ex.isUnilateral, ...inheritedLoad,
      targetWeightLb: durationBased ? 0 : (last?.targetWeightLb ?? se.targetWeightLb ?? w),
      plannedWeightLb: w, plannedReps: r,
      plannedDurationSeconds: durationBased ? durationSeconds : null,
      prescriptionBlock: ex?.type === "conditioning" ? "conditioning" : "work",
    });
    set.enteredUnit = exUnit(se);
    if (ex && ex.type === "conditioning" && last) {
      // Repeat intervals: carry the last round's cardio prescription forward.
      set.distanceMiles = last.distanceMiles ?? null;
      set.flights = last.flights ?? null;
      set.durationSeconds = last.durationSeconds ?? null;
      set.inclinePercent = last.inclinePercent ?? null;
    }
    if (durationBased) set.durationSeconds = durationSeconds;
    se.sets.push(set);
    syncSetPlan(se);
  }

  function syncSetPlan(se) {
    se.sets.forEach((set, index) => { set.order = index; });
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
        // The configured drop derives from the MAIN work set — ramp/backoff
        // blocks at lighter loads must not anchor it. With no planned work
        // set left, fixedDrop stays null and the generic percentage drop in
        // dropLoadPlan takes over.
        const first = se.sets.find((x) => !x.isWarmup && x.status === "planned"
          && C.countsAsPrescribedWork(x.prescriptionBlock));
        const fixedDrop = first && se.fallbackWeightLb != null ? Math.max(0, first.weightLb - se.fallbackWeightLb) : null;
        const ex = exMap.get(se.exerciseName);
        const step = C.programLoadStep(5, ex?.type);
        const bar = barFor(se);
        const plan = C.dropLoadPlan(
          se.sets.map((x) => ({ weightLb: x.weightLb, isWarmup: !!x.isWarmup, isFlagged: x.status !== "planned" })),
          step, ex?.type === "barbell" ? C.barLb(bar) : 0, fixedDrop,
        );
        if (!plan.length) { ui.toast("All sets already logged — nothing to drop."); return; }
        plan.forEach((p) => {
          const x = se.sets[p.index];
          x.weightLb = ex?.type === "barbell" && gymState.value
            ? C.solve(p.weightLb, bar, availablePlates(gymState.value, ex), 10,
              gymState.value.collarWeightLb || 0, "under").totalLb : p.weightLb;
          x.autoregReason = reason;
        });
        save(); renderBody(body);
        ui.toast(`Dropped to ${ui.fmtWeight(Math.max(...plan.map((p) => se.sets[p.index].weightLb)))}`);
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
        let applyWeightToRemaining = false;
        let applyRepsToRemaining = !s.isWarmup && s.status === "planned";
        c.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Warmup" }), ui.toggle(warm, (v) => { warm = v; })));
        c.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Per side" }), ui.toggle(per, (v) => { per = v; })));
        c.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Stopped early" }), ui.toggle(stopped, (v) => { stopped = v; })));
        if (!s.isWarmup && se.sets.some((candidate) => candidate !== s && !candidate.isWarmup && candidate.status === "planned")) {
          c.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Apply reps to remaining planned sets" }),
            ui.toggle(applyRepsToRemaining, (v) => { applyRepsToRemaining = v; })));
          c.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Apply weight to remaining planned sets" }),
            ui.toggle(applyWeightToRemaining, (v) => { applyWeightToRemaining = v; })));
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
            const planned = s.plannedWeightLb ?? se.plannedWeightLb;
            if (planned > 0 && weightLb > 0 && Math.abs(weightLb - planned) > 6
                && !window.confirm(`This differs from the planned load by ${C.trim(Math.abs(weightLb - planned))} lb. Confirm the plates and use it?`)) return;
            s.weightLb = weightLb; s.enteredUnit = unit; s.reps = reps;
            const remaining = se.sets.filter((set) => set !== s && !set.isWarmup && set.status === "planned");
            if (applyWeightToRemaining && !warm) for (const target of remaining) { target.weightLb = weightLb; target.enteredUnit = unit; }
            if (applyRepsToRemaining && !warm) for (const target of remaining) target.reps = reps;
            s.isWarmup = warm; s.isPerSide = per;
            s.flags = C.normalizedSetFlags(C.setQuality(s.flags), stopped, C.setRIR(s.flags));
            s.bodyFlagSite = site; s.bodyFlagNote = site ? (noteInput.value || null) : null;
            syncSetPlan(se);
            if (applyWeightToRemaining && !warm) synchronizeWarmups(se, barFor(se), weightLb);
            unitByEx[se.exerciseName] = unit; // keep the row display in the unit you just used
            api.close(); save(); renderBody(body);
          },
        }));
        c.append(ui.h("button", { class: "btn wide danger", style: { marginTop: "8px" }, text: "Delete set",
          onClick: () => { removeSet(se, s); api.close(); save(); renderBody(body); } }));
      },
    });
  }

  // Cardio (type conditioning) sets: distance / time / speed / incline, or
  // flights / time / pace for a climber. Names the fields the sheet will
  // actually show, so the row never advertises one the sheet withholds.
  function cardioHint(exerciseName, s) {
    return ` ${C.cardioFields(exerciseName, s.flights, s.distanceMiles, s.inclinePercent).label}`;
  }

  // [INV-CARDIO-SOLVES-THE-THIRD] Distance and speed are two views of one
  // relationship, so both are editable and whichever one the lifter is NOT
  // typing into is the one that recomputes. Time is never overwritten — it is
  // the one value a treadmill, a watch, and a ruck plan all agree on.
  // Only distance + duration are stored; speed is always re-derivable.
  //
  // [INV-STAIRS-COUNT-FLIGHTS] A climber gets the same pair of fields against
  // a different yardstick — flights and pace instead of distance and speed.
  // Which block a movement gets is a property of the movement, except that a
  // set already holding the other measure keeps its block so history logged
  // before flights existed stays editable rather than becoming unreachable.
  // Mirrors the native CardioSetSheet.
  function editCardioSet(se, s, body) {
    ui.sheet({
      title: `Log conditioning — ${se.exerciseName}`,
      build: (c, api) => {
        // Captured ONCE, here, from the values as they are when the sheet
        // opens. The rule reads what is being edited, so re-deriving it later
        // would let a field delete itself mid-edit: clearing a legacy climb's
        // distance would take the distance and speed rows with it and leave no
        // way to retype the number that had just been cleared.
        const fields = C.cardioFields(se.exerciseName, s.flights, s.distanceMiles, s.inclinePercent);
        const showFlights = fields.flights;
        const showDistance = fields.distance;
        const minInput = ui.h("input", { type: "number", inputmode: "numeric", min: "0", placeholder: "0", value: s.durationSeconds > 0 ? String(Math.floor(s.durationSeconds / 60)) : "" });
        const secInput = ui.h("input", { type: "number", inputmode: "numeric", min: "0", max: "59", placeholder: "0", value: s.durationSeconds > 0 ? String(s.durationSeconds % 60) : "" });
        const readSecs = () => (parseInt(minInput.value, 10) || 0) * 60 + (parseInt(secInput.value, 10) || 0);
        const recomputers = [];

        const distInput = ui.h("input", { class: "big-num", type: "number", inputmode: "decimal", step: "0.05", min: "0", placeholder: "0", value: s.distanceMiles > 0 ? C.trim(s.distanceMiles, 2) : "" });
        const startSpeed = C.cardioSpeedMph(s.distanceMiles, s.durationSeconds);
        const speedInput = ui.h("input", { type: "number", inputmode: "decimal", step: "0.1", min: "0", placeholder: "0", value: startSpeed !== null ? C.trim(startSpeed) : "" });
        // Which of distance/speed is currently computed from the other two.
        // Distance is what gets stored, so it starts as the entered value.
        let derived = "speed";
        // The distance input displays a 2-decimal value, but a pace entered
        // for a short interval needs more than that to survive a round trip.
        // Keep what was actually computed and store THAT, not the display text.
        let computedMiles = null;
        const distNote = ui.h("span", { class: "sub" });
        const speedNote = ui.h("span", { class: "sub" });
        const recomputeDistance = () => {
          const secs = readSecs();
          if (derived === "distance") {
            const miles = C.cardioDistanceMiles(parseFloat(speedInput.value) || 0, secs);
            // With no time there is nothing to solve against; leave whatever
            // distance is already in the field rather than blanking it.
            if (miles !== null) {
              computedMiles = miles;
              distInput.value = C.trim(miles, 2);
            }
          } else {
            computedMiles = null;
            const mph = C.cardioSpeedMph(parseFloat(distInput.value) || 0, secs);
            speedInput.value = mph !== null ? C.trim(mph) : "";
          }
          distNote.textContent = derived === "distance" ? "calculated" : "";
          speedNote.textContent = derived === "speed" ? "calculated" : "";
        };

        const flightInput = ui.h("input", { class: "big-num", type: "number", inputmode: "decimal", step: "1", min: "0", placeholder: "0", value: s.flights > 0 ? C.trim(s.flights, 1) : "" });
        const startPace = C.cardioFlightPace(s.flights, s.durationSeconds);
        const paceInput = ui.h("input", { type: "number", inputmode: "decimal", step: "0.1", min: "0", placeholder: "0", value: startPace !== null ? C.trim(startPace) : "" });
        let flightDerived = "pace";
        let computedFlights = null;
        const flightNote = ui.h("span", { class: "sub" });
        const paceNote = ui.h("span", { class: "sub" });
        const recomputeFlights = () => {
          const secs = readSecs();
          if (flightDerived === "flights") {
            const solved = C.cardioFlights(parseFloat(paceInput.value) || 0, secs);
            if (solved !== null) {
              computedFlights = solved;
              flightInput.value = C.trim(solved, 1);
            }
          } else {
            computedFlights = null;
            const pace = C.cardioFlightPace(parseFloat(flightInput.value) || 0, secs);
            paceInput.value = pace !== null ? C.trim(pace) : "";
          }
          flightNote.textContent = flightDerived === "flights" ? "calculated" : "";
          paceNote.textContent = flightDerived === "pace" ? "calculated" : "";
        };

        if (showFlights) {
          flightInput.addEventListener("input", () => { flightDerived = "pace"; recomputeFlights(); });
          paceInput.addEventListener("input", () => { flightDerived = "flights"; recomputeFlights(); });
          recomputers.push(recomputeFlights);
          c.append(ui.h("div", { class: "row" },
            ui.h("span", {}, ui.h("span", { text: "Flights " }), flightNote), flightInput));
        }
        if (showDistance) {
          distInput.addEventListener("input", () => { derived = "speed"; recomputeDistance(); });
          speedInput.addEventListener("input", () => { derived = "distance"; recomputeDistance(); });
          recomputers.push(recomputeDistance);
          c.append(ui.h("div", { class: "row" },
            ui.h("span", {}, ui.h("span", { text: "Distance (mi) " }), distNote), distInput));
        }
        c.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Time" }),
          ui.h("div", { style: { display: "flex", gap: "6px", alignItems: "center" } },
            minInput, ui.h("span", { class: "sub", text: "min" }), secInput, ui.h("span", { class: "sub", text: "sec" }))));
        if (showDistance) {
          c.append(ui.h("div", { class: "row" },
            ui.h("span", {}, ui.h("span", { text: "Speed (mph) " }), speedNote), speedInput));
        }
        if (showFlights) {
          c.append(ui.h("div", { class: "row" },
            ui.h("span", {}, ui.h("span", { text: "Pace (fl/min) " }), paceNote), paceInput));
        }
        // A climber's grade is the machine, not a setting, so it gets no
        // incline row unless a legacy set already carries one.
        let incline = s.inclinePercent > 0 ? s.inclinePercent : 0;
        if (fields.incline) {
          c.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Incline" }),
            ui.stepper(incline, { min: 0, max: 30, step: 0.5, format: (v) => (v > 0 ? `${C.trim(v)}%` : "—"), onChange: (v) => { incline = v; } })));
        }
        // A ruck is a walk with a pack on — the pack weight is the training
        // variable, so loaded carries keep a load where plain cardio zeroes it.
        // The load is established when the set is created, so the sheet only
        // ever edits what is already there — it never re-defaults.
        const carries = fields.load;
        let carryLb = carries ? (s.weightLb || 0) : 0;
        if (carries) {
          c.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Load" }),
            ui.stepper(carryLb, {
              min: 0, max: 200, step: C.CARDIO_LOAD_INCREMENT_LB,
              format: (v) => (v > 0 ? `${C.trim(v)} lb` : "—"),
              onChange: (v) => { carryLb = v; },
            })));
        }
        [minInput, secInput].forEach((el) => el.addEventListener("input", () => recomputers.forEach((f) => f())));
        recomputers.forEach((f) => f());
        c.append(ui.h("button", {
          class: "btn primary wide", style: { marginTop: "10px" }, text: "Done",
          onClick: () => {
            const secs = readSecs();
            // A derived value is stored at full precision; a typed one is taken
            // from the field as entered.
            const miles = derived === "distance" && computedMiles !== null
              ? computedMiles
              : (parseFloat(distInput.value) || 0);
            const flights = flightDerived === "flights" && computedFlights !== null
              ? computedFlights
              : (parseFloat(flightInput.value) || 0);
            // A hidden block never writes: a climber cannot silently acquire a
            // distance, and a walk cannot acquire a flight count.
            if (showDistance) s.distanceMiles = miles > 0 ? miles : null;
            if (showFlights) s.flights = flights > 0 ? flights : null;
            s.durationSeconds = secs > 0 ? secs : null;
            s.inclinePercent = incline > 0 ? incline : null;
            // Unloaded cardio carries no load; a ruck or a sled does.
            s.weightLb = carries ? carryLb : 0;
            s.reps = Math.max(1, s.reps || 1);
            api.close(); save(); renderBody(body);
          },
        }));
        c.append(ui.h("button", { class: "btn wide danger", style: { marginTop: "8px" }, text: "Delete set",
          onClick: () => { removeSet(se, s); api.close(); save(); renderBody(body); } }));
      },
    });
  }

  function editTimedSet(se, s, body) {
    ui.sheet({
      title: `Log timed set — ${se.exerciseName}`,
      build: (c, api) => {
        let seconds = s.durationSeconds || 30;
        c.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Hold time" }),
          ui.stepper(seconds, { min: 5, max: 1800, step: 5, format: C.cardioDurationLabel, onChange: (v) => { seconds = v; } })));
        c.append(ui.h("button", { class: "btn primary wide", style: { marginTop: "10px" }, text: "Done", onClick: () => {
          s.durationSeconds = seconds; s.weightLb = 0; s.reps = 1;
          api.close(); save(); renderBody(body);
        } }));
        c.append(ui.h("button", { class: "btn wide danger", style: { marginTop: "8px" }, text: "Delete set",
          onClick: () => { removeSet(se, s); api.close(); save(); renderBody(body); } }));
      },
    });
  }

  async function pickExercise(body) {
    const all = await Exercises.all();
    // exMap is snapshotted at openSession; this sheet reads fresh, so an
    // exercise created since (another tab) would otherwise join the session
    // with an inert title and generic accessory rest. Fold the fresh reads
    // in so the card renders the exercise it actually added.
    for (const e of all) exMap.set(e.name, e);
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

  // The way OUT of a session you never want to keep. Banking it is not the
  // answer for a session started by mistake, and closing the screen just
  // leaves it open — so without this the only discard was back on Today.
  function discard() {
    const performed = session.exercises.flatMap((se) => se.sets || [])
      .filter((set) => !set.isWarmup && set.status === "completed").length;
    ui.actionSheet(
      performed === 0
        ? "Discard this session? Nothing has been logged."
        : `Discard this session and lose ${performed} logged set${performed === 1 ? "" : "s"}?`,
      [
        { label: "Discard session", role: "destructive", onClick: async () => {
          await Sessions.del(session.id);
          rest.stop();
          screen.close();
          ui.nav.refresh();
        } },
        { label: "Keep session", role: "cancel", onClick: () => {} },
      ],
    );
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

  const screen = ui.pushScreen({ title: workoutName, build: (b) => renderBody(b) });
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
  session.completedAt = iso(new Date());
  try {
    return await completeSessionInner(session);
  } catch (e) {
    session.isCompleted = false;
    session.completedAt = null;
    throw e;
  }
}

async function completeSessionInner(session) {
  const prior = (await Sessions.completed()).filter((s) => new Date(s.date) < new Date(session.date));
  const exerciseByName = new Map((await Exercises.all()).map((exercise) => [exercise.name, exercise]));
  const lines = [], milestones = [], milestoneRecords = [];
  // Keyed by lift: one banked exposure can advance a standalone track at most
  // once, even when the same exercise appears in multiple sections.
  const trackByName = new Map();
  for (const se of session.exercises) {
    const completedSets = se.sets.filter((s) => !s.isWarmup && s.status === "completed");
    const definition = exerciseByName.get(se.exerciseName);
    const sample = (set) => ({
      weightLb: set.weightLb, reps: set.reps, isPerSide: !!set.isPerSide,
      loadBasis: C.LOAD_BASES.includes(set.loadBasis) ? set.loadBasis : C.resolvedLoadBasis(definition),
      implementCount: set.implementCount || C.resolvedImplementCount(definition),
    });
    const working = completedSets.map(sample);
    if (!working.length) continue;
    const exerciseType = definition?.type;
    if (exerciseType === "timed") {
      const durations = completedSets.map((set) => set.durationSeconds || 0).filter(Boolean);
      if (durations.length) lines.push({ exerciseName: se.exerciseName,
        topSetLabel: `${durations.length} × ${C.cardioDurationLabel(Math.max(...durations))}`, volumeLb: 0 });
      continue;
    }
    if (exerciseType === "conditioning") continue;

    const historySets = [], historyVolumes = [], historySchemes = new Set();
    for (const ps of prior) {
      for (const pe of ps.exercises) {
        if (pe.exerciseName !== se.exerciseName) continue;
        const w = pe.sets.filter((x) => !x.isWarmup && x.status === "completed").map(sample)
          .filter((set) => set.loadBasis === working[0].loadBasis);
        if (!w.length) continue;
        historySets.push(...w);
        historyVolumes.push(C.prVolume(w));
        const top = C.prTopScheme(w); if (top) historySchemes.add(`${top.sets}×${top.reps}`);
      }
    }
    const events = C.prEvaluate({ exercise: se.exerciseName, sessionSets: working, historySets, historyVolumes, historySchemes, formatWeight: ui.fmtWeight });
    for (const e of events) { milestoneRecords.push({ date: iso(new Date(session.date)), exerciseName: e.exercise, kind: e.kind, label: e.label }); milestones.push(e); }

    const top = working.reduce((b, s) => (!b || s.weightLb > b.weightLb ? s : b), null);
    const topLabel = top.loadBasis === "bodyweight" ? `${top.reps} reps`
      : `${ui.fmtWeight(top.weightLb)}${C.loadBasisSuffix(top.loadBasis)} × ${top.reps}`;
    lines.push({ exerciseName: se.exerciseName, topSetLabel: topLabel, volumeLb: C.prVolume(working) });
  }

  const heldStandaloneTracks = [];
  const standaloneByName = new Map();
  for (const se of session.exercises) {
    const definition = exerciseByName.get(se.exerciseName);
    if (se.programRole || definition?.type === "timed" || definition?.type === "conditioning") continue;
    if (!standaloneByName.has(se.exerciseName)) standaloneByName.set(se.exerciseName, []);
    standaloneByName.get(se.exerciseName).push(se);
  }
  for (const [exerciseName, entries] of standaloneByName) {
    const track = await Tracks.byName(exerciseName);
    if (!track) continue;
    const performed = entries.filter((se) => se.sets.some((set) => !set.isWarmup
      && set.status === "completed" && C.countsAsPrescribedWork(set.prescriptionBlock)));
    if (!performed.length) continue;
    const advance = performed.length === entries.length
      && C.earnsStandaloneTrackAdvance(performed.map((se) => cyclePerf(se, track.roundingLb)));
    track.lastCompletedAt = iso(new Date());
    if (advance) {
      if (track.mode === "cycle") {
        const adv = C.advancing(trackState(track), track.nextPhase);
        track.cycleNumber = adv.cycleNumber; track.baseWeightLb = adv.baseWeightLb; track.nextPhase = adv.nextPhase;
      } else { track.baseWeightLb += track.incrementLb; }
    } else heldStandaloneTracks.push(exerciseName);
    trackByName.set(exerciseName, track);
  }

  const hasCompletedProgramInstruction = session.exercises.some((se) => {
    if (!se.programSlotId && !se.programRole) return false;
    const candidates = (se.sets || []).filter((set) => !set.isWarmup
      && C.countsAsProgramInstruction(set.prescriptionBlock));
    return candidates.slice(0, se.plannedSets ?? candidates.length)
      .some((set) => set.status === "completed");
  });
  const prog = session.programTag && hasCompletedProgramInstruction
    ? await advanceProgram(session, milestones) : null;
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
  const workingSets = session.exercises.flatMap((exercise) => exercise.sets.filter((set) => !set.isWarmup));
  const completedSets = workingSets.filter((set) => set.status === "completed");
  const incompleteSets = workingSets.filter((set) => set.status !== "completed");
  const adjusted = completedSets.some((set) => set.autoregReason || (set.flags || []).some((flag) => ["stopped early", "grindy", "wobble"].includes(flag)));
  const coachingNotes = [];
  if (incompleteSets.length) coachingNotes.push(`Modified session — ${completedSets.length} sets completed; unfinished or skipped sets were not credited as performed.`);
  else if (adjusted) coachingNotes.push("Completed with adjustments — progression was graded from the work actually logged.");
  else if (completedSets.length) coachingNotes.push("Completed as planned — progression advanced from the banked work.");
  if (heldStandaloneTracks.length) coachingNotes.push(`Held progression for ${heldStandaloneTracks.sort().join(", ")} — actual work was saved, but the original prescription was not fully met.`);
  if (prog?.program) {
    const nextDay = prog.program.days.find((day) => day.order === prog.program.nextDayIndex) || prog.program.days[0];
    // A day is not in a phase — its slots are, and they can disagree. Naming one
    // phase for the whole day claims a wave over slots that may be linear, 5/3/1
    // or speed work. Mirrored in SessionCompletion.swift.
    if (nextDay) coachingNotes.push(`Next: ${nextDay.name} · ${C.rotationLabel(prog.program.currentWeek)}.`);
  }
  return { lines, milestones, coachingNotes };
}

// ---- Performance summaries (built from logged sets, consumed by the core) ----
function prescribedWork(se) {
  const candidates = (se.sets || []).filter((set) => !set.isWarmup
    && C.countsAsPrescribedWork(set.prescriptionBlock));
  return candidates.slice(0, se.plannedSets ?? candidates.length)
    .filter((set) => set.status === "completed");
}

function programmedEntry(session, slot) {
  // Program definitions expose `id`; live session rows expose
  // `programSlotId` plus their own persistence `id`.
  const slotID = slot.programSlotId || slot.id;
  const role = slot.programRole || slot.role;
  const exact = (session.exercises || []).find((entry) =>
    entry.programSlotId === slotID && entry.programRole === role);
  if (exact) return exact;
  const lineage = (session.exercises || []).filter((entry) =>
    entry.programRole === role && entry.exerciseName === slot.exerciseName);
  return lineage.length === 1 ? lineage[0] : null;
}

function completedProgramInstructionsMatch(session, day) {
  const completed = (session.exercises || []).filter((entry) => {
    if (!entry.programSlotId && !entry.programRole) return false;
    const candidates = (entry.sets || []).filter((set) => !set.isWarmup
      && C.countsAsProgramInstruction(set.prescriptionBlock));
    return candidates.slice(0, entry.plannedSets ?? candidates.length)
      .some((set) => set.status === "completed");
  });
  if (!completed.length) return false;
  return completed.every((entry) => {
    if (["main", "complementary"].includes(entry.programRole)) {
      if (entry.programSlotId) return (day.lifts || []).some((lift) =>
        lift.id === entry.programSlotId && lift.role === entry.programRole);
      return (day.lifts || []).filter((lift) =>
        lift.exerciseName === entry.exerciseName && lift.role === entry.programRole).length === 1;
    }
    if (entry.programRole === "accessory") {
      if (entry.programSlotId) return (day.accessories || []).some((slot) => slot.id === entry.programSlotId);
      return (day.accessories || []).filter((slot) => slot.exerciseName === entry.exerciseName).length === 1;
    }
    return false;
  });
}

// Twin equivalence is a barbell concept — only total-bar work may read its
// number as a bar-and-plates stack; everything else grades on the numbers
// alone (null). The label bar rides along so a 35-class bar twins against its
// own denomination family. Mirrors SessionCompletion.twinBarLb; native
// resolves a legacy set's basis through its linked exercise, web sets have
// carried the basis since creation (older records grade strictly).
function twinBarLb(se, work) {
  if (work[0]?.loadBasis !== "totalBar") return null;
  return C.barLabelLb(se.barId ? C.barById(se.barId) : C.BARS.bar45lb);
}

// The best e1RM logged for the exercise before the session being banked, and
// whether it is a STANDING best — old enough (35 days) to be a prior ceiling
// rather than the frontier of a rising log. This is what progressionRegime
// bands against: a logged drawdown reads rebuild, a standing ceiling being
// closed back in on reads fine, and a fresh log with no such evidence stays
// standard. Mirrors SessionCompletion.priorBestE1RM.
function priorBestE1RM(completedSessions, exerciseName, anchorMs) {
  let best = 0;
  let bestMs = -Infinity;
  for (const candidate of completedSessions) {
    // PRIOR means prior: a session banked out of order must not let later
    // work retroactively pick this cycle's regime. An unparseable date fails
    // the comparison and is skipped rather than poisoning the standing test.
    const stamp = Date.parse(candidate.completedAt || candidate.date);
    if (!(stamp <= anchorMs)) continue;
    for (const entry of candidate.exercises || []) {
      if (entry.exerciseName !== exerciseName) continue;
      for (const set of entry.sets || []) {
        if (set.isWarmup || set.status !== "completed" || !(set.weightLb > 0) || !(set.reps >= 1)) continue;
        // Same rep ceiling as strengthSampleIndex: Epley drifts high past
        // ten reps, and a long back-off set must not become an inflated
        // lifetime ceiling that misgrades every later cycle.
        if (set.reps > C.E1RM_SAMPLE_REP_CEILING) continue;
        const sample = C.epleyE1RM(set.weightLb, set.reps);
        if (sample > best) { best = sample; bestMs = stamp; }
      }
    }
  }
  return { maxLb: best, standing: best > 0 && anchorMs - bestMs >= C.STANDING_BEST_DAYS * 86400000 };
}

function cyclePerf(se, roundingLb) {
  const w = prescribedWork(se);
  const presReps = se.plannedReps ?? (w.length ? Math.max(...w.map((s) => s.reps)) : 0); // ?? not ||: mirrors Swift's nil-coalescing
  // The cycle's strength sample, not simply the heaviest set — see core
  // strengthSampleIndex. Heaviest-first discarded the extra reps of an AMRAP
  // taken at the top weight.
  const topIndex = C.strengthSampleIndex(w.map((s) => s.weightLb), w.map((s) => s.reps));
  const top = topIndex == null ? null : w[topIndex];
  return {
    prescribedSets: se.plannedSets ?? w.length, prescribedReps: presReps,
    completedSets: w.filter((s) => s.reps >= presReps).length,
    anyStoppedEarly: w.some((s) => (s.flags || []).includes("stopped early")),
    anyDroppedLoad: w.some((s) => !!s.autoregReason),
    anyBelowPlanLoad: C.belowPlanWork(w.map((s) => s.weightLb), se.plannedWeightLb, se.plannedSets ?? w.length, roundingLb,
      twinBarLb(se, w)),
    grindyOrWobbleSets: w.filter((s) => (s.flags || []).some((f) => f === "grindy" || f === "wobble")).length,
    topSetWeightLb: top ? top.weightLb : 0, topSetReps: top ? top.reps : 0,
    // The strength sample's own plan, so the advance can ride a performed
    // overshoot. Per-set plan first; the entry plan is the fallback.
    plannedTopWeightLb: top ? (top.plannedWeightLb ?? se.plannedWeightLb ?? 0) : 0,
  };
}
function accPerf(se, roundingLb = 5) {
  const w = prescribedWork(se);
  return {
    completedSets: w.length,
    minRepsAchieved: w.length ? Math.min(...w.map((s) => s.reps)) : 0,
    anyStoppedEarly: w.some((s) => (s.flags || []).includes("stopped early")),
    performedAtPlannedLoad: w.every((s) => !C.belowPlanLoad(
      s.weightLb, s.plannedWeightLb ?? se.plannedWeightLb, roundingLb, twinBarLb(se, w))),
    grindyOrWobbleSets: w.filter((s) => (s.flags || []).some((f) => f === "grindy" || f === "wobble")).length,
    bodyFlagSets: w.filter((s) => !!s.bodyFlagSite).length,
  };
}

// ---- Program day/week/cycle advancement on bank ----
// Mutates the program in memory and returns { program, noteRecords } for the
// caller's single completion transaction — no writes of its own.
// Complete rotations banked for this program since its most recent deload
// rotation. A program that has never deloaded returns every rotation it has
// run, which is exactly right — it has accumulated all of them.
//
// Rotations, not sessions: a session count means something different on every
// split, and the floor it feeds has to mean the same thing on all of them.
function rotationsSinceLastDeload(completed, program) {
  const id = program.uuid || program.id;
  const mine = completed
    .filter((s) => s.programTag && (s.programTag.programId === id || s.programTag.programName === program.name))
    .sort((a, b) => Date.parse(a.completedAt || a.date) - Date.parse(b.completedAt || b.date));
  let lastDeload = -1;
  mine.forEach((s, index) => { if (s.programTag.week === C.DELOAD_WEEK) lastDeload = index; });
  return new Set(mine.slice(lastDeload + 1).map((s) => `${s.programTag.cycleNumber}-${s.programTag.week}`)).size;
}

// Readiness-triggered deload. The schedule normally walks 1 -> 2 -> 3 -> 4; a
// second consecutive red rotation means this cycle is not worth finishing, so
// it goes straight to the deload instead. Mirrors the native advanceProgram.
//
// The session that just closed this rotation is NOT in the store yet — the
// whole completion commits in one transaction after this runs — so it is
// passed in by hand. Judging without it would read the rotation before last.
async function earlyDeloadDecision(program, session, exerciseByName) {
  // Structural guard first: building the coaching report is not free, and from
  // rotation 3 the schedule advances into the deload by itself.
  if (!(program.currentWeek >= 1 && program.currentWeek < C.DELOAD_WEEK - 1)) return null;
  const [stored, checkins] = await Promise.all([Sessions.completed(), Checkins.all()]);
  const completed = [...stored.filter((s) => String(s.id) !== String(session.id)), session];
  const report = coachingReport(program, completed, exerciseByName, checkins);
  // Verified rotations only — an as-run rotation is complete by construction,
  // so trusting one would launder an unknown into a deload.
  const verified = report.rotations.filter((rotation) => rotation.isComplete && !rotation.judgedAsRun);
  const decided = C.shouldDeloadEarly(
    program.currentWeek,
    verified.at(-1)?.readiness ?? "unknown",
    verified.at(-2)?.readiness ?? "unknown",
    rotationsSinceLastDeload(completed, program),
  );
  return decided ? { week: program.currentWeek } : null;
}

function rollOverRecovery(program, exerciseByName, note) {
  const allDayOrders = [...new Set(program.days.map((candidate) => candidate.order ?? 0))]
    .sort((a, b) => a - b);
  for (const d of program.days) {
    for (const lift of d.lifts || []) {
      if (C.advancesPerExposure(lift.prescription)) {
        // Per-exposure slots already advanced while training. A stale pending
        // grade left by a later style edit must never apply at rollover.
        delete lift.pending;
      } else if (lift.pending) {
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
      } else if (!C.buildsOwnSessionShape(lift.prescription || "automatic")) {
        // Wave-family slots: no banked Peak is a stall toward the rebuild.
        lift.stallCount = (lift.stallCount || 0) + 1; lift.lastIncrementLb = 0;
        if (lift.stallCount >= C.STALL_LIMIT) {
          const old = lift.baseWeightLb;
          const loadStep = C.programLoadStep(program.roundingLb, exerciseByName.get(lift.exerciseName)?.type);
          lift.baseWeightLb = C.roundTo(old * C.DELOAD_REBUILD_FRACTION, loadStep);
          lift.stallCount = 0;
          note(`${lift.exerciseName}: skipped peak — deloaded ${ui.fmtWeight(old)}→${ui.fmtWeight(lift.baseWeightLb)}.`, lift.exerciseName);
        }
      } else {
        lift.lastIncrementLb = 0;
      }
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
  program.nextDayIndex = allDayOrders[0] ?? 0;
}

function recoveryBridgeState(program, completed, exerciseByName, nowMs) {
  const stableID = program.uuid || program.id;
  const cycleSessions = completed.filter((candidate) => candidate.programTag
    && (candidate.programTag.programId === stableID
      || (candidate.programTag.programId == null
        && candidate.programTag.programName === program.name))
    && candidate.programTag.cycleNumber === program.cycleNumber);
  const recoverySessions = cycleSessions.filter((candidate) =>
    candidate.programTag.week === C.DELOAD_WEEK);
  const recoveryDayOrders = C.recoveryDayOrders(program.days.map((candidate) => {
    const mainName = (candidate.lifts || []).find((lift) => lift.role === "main")?.exerciseName;
    return { order: candidate.order ?? 0, mainMovementGroup: exerciseByName.get(mainName)?.movementGroup };
  }));
  const selectedComplete = C.recoveryScheduleAdvance(
    recoveryDayOrders, recoverySessions.map((candidate) => candidate.programTag.dayIndex),
  ).isLastDay;
  const hardPhase = cycleSessions.filter((candidate) =>
    candidate.programTag.week > 0 && candidate.programTag.week < C.DELOAD_WEEK);
  const peak = hardPhase.filter((candidate) => candidate.programTag.week === C.GRADED_WEEK);
  // The window is anchored to the last hard phase. A reduced exposure does not
  // start a fresh seven-day window and silently stretch recovery past the
  // program's bound.
  const anchors = peak.length ? peak : hardPhase;
  const anchorMs = anchors.length
    ? Math.max(...anchors.map((candidate) => Date.parse(candidate.completedAt || candidate.date)))
    : null;
  return {
    reason: C.recoveryBridgeCompletionReason(
      recoverySessions.length, recoveryDayOrders.length, selectedComplete, anchorMs, nowMs,
    ),
    recoverySessions,
    recoveryDayOrders,
  };
}

// Close stale/already-satisfied Recovery before Today or Start can prescribe
// another reduced workout. The seven-day threshold only expires the bridge;
// ordinary progression remains driven by completed cycles.
export async function reconcileRecoveryBridge(program, completed = null, now = new Date()) {
  if (!program || program.currentWeek !== C.DELOAD_WEEK) return null;
  // Never advance the program out from under a workout in progress. The open
  // session was built against this rotation; rolling the cycle while it is on
  // screen makes banking it fail the stale-tag guard and land as orphaned
  // history, and on this client it also let createSessionFromProgramDay open a
  // SECOND session while the first stayed open. Reconciliation is not urgent —
  // it runs on the next render once the session is banked or discarded.
  //
  // Scoped to THIS PROGRAM'S sessions, deliberately. Blocking on any open
  // session at all would let one lingering blank session — which Today
  // explicitly supports keeping around — suppress the session cap and the
  // expiry window indefinitely, and Start would go on minting stale recovery
  // prescriptions. That is the indefinite-light-work path this whole mechanism
  // exists to close. Mirrors SessionCompletion.reconcileRecoveryBridge.
  const stableID = program.uuid || program.id;
  const openForThisProgram = (await Sessions.openAll()).some((candidate) => candidate.programTag
    && (candidate.programTag.programId === stableID
      || (candidate.programTag.programId == null
        && candidate.programTag.programName === program.name)));
  if (openForThisProgram) return null;
  const [history, exercises] = await Promise.all([
    completed || Sessions.completed(), Exercises.all(),
  ]);
  const exerciseByName = new Map(exercises.map((exercise) => [exercise.name, exercise]));
  const { reason, recoverySessions } = recoveryBridgeState(program, history, exerciseByName, now.getTime());
  if (!reason) return null;

  const nextCycle = program.cycleNumber + 1;
  const banked = recoverySessions.length;
  const message = reason === "sessionLimit"
    ? `Recovery complete — ${banked} recovery session${banked === 1 ? "" : "s"} banked. Cycle ${nextCycle} starts at Volume.`
    : reason === "windowElapsed"
      ? `Recovery complete — the seven-day recovery window elapsed. Cycle ${nextCycle} starts at Volume.`
      : `Recovery complete — planned recovery exposures banked. Cycle ${nextCycle} starts at Volume.`;
  const noteRecords = [];
  const note = (label, exerciseName) => noteRecords.push({
    date: iso(now), exerciseName: exerciseName || null, kind: "programNote", label,
  });
  rollOverRecovery(program, exerciseByName, note);
  note(`${program.name}: ${message}`, null);
  await runAll(["milestones", "programs"], "readwrite", (os) => {
    for (const record of noteRecords) os("milestones").put(record);
    os("programs").put(program);
  });
  return { program, reason, message };
}

async function advanceProgram(session, milestones) {
  const tag = session.programTag;
  const program = await Programs.byStableId(tag.programId)
    || (await Programs.all()).find((candidate) => candidate.name === tag.programName);
  if (!program) return null;
  const exerciseByName = new Map((await Exercises.all()).map((exercise) => [exercise.name, exercise]));
  const day = program.days.find((d) => d.order === tag.dayIndex);
  if (!day) return null;
  const allDayOrders = [...new Set(program.days.map((candidate) => candidate.order ?? 0))]
    .sort((a, b) => a - b);
  const recoveryDayOrders = C.recoveryDayOrders(program.days.map((candidate) => {
    const mainName = (candidate.lifts || []).find((lift) => lift.role === "main")?.exerciseName;
    return { order: candidate.order ?? 0, mainMovementGroup: exerciseByName.get(mainName)?.movementGroup };
  }));
  const isRecovery = tag.week === C.DELOAD_WEEK;
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
  if (!completedProgramInstructionsMatch(session, day)) {
    note(`${program.name}: banked work from an older version of day ${tag.dayIndex + 1} — kept as history, current schedule unchanged.`, null);
    return { program: null, noteRecords: flushNotes() };
  }

  // Accessories: double progression, evaluated every bank.
  for (const acc of (day.accessories || []).filter(() => !isRecovery)) {
    const se = programmedEntry(session, { ...acc, role: "accessory" });
    if (!se) continue;
    const completed = prescribedWork(se);
    if (!completed.length) continue;
    const exerciseType = exerciseByName.get(acc.exerciseName)?.type;
    if (exerciseType === "conditioning") continue;
    // A temporary red-readiness cut deliberately holds accessory progression.
    if ((se.plannedSets ?? acc.sets) < acc.sets) continue;
    if (exerciseType === "timed") {
      if (completed.length >= acc.sets
        && completed.every((set) => (set.durationSeconds || 0) >= (acc.targetSeconds || 30))
        && !completed.some((set) => (set.flags || []).includes("stopped early"))) {
        acc.targetSeconds = (acc.targetSeconds || 30) + (acc.durationStepSeconds ?? 5);
      }
    } else {
      const loadStep = C.programLoadStep(program.roundingLb, exerciseByName.get(acc.exerciseName)?.type);
      Object.assign(acc, C.advanceAccessory(acc, accPerf(se, loadStep)));
    }
  }
  // Lift slots can opt into rep-window progression instead of phase grading.
  for (const lift of (day.lifts || []).filter((candidate) =>
    candidate.prescription === "doubleProgression" && !isRecovery)) {
    const se = programmedEntry(session, lift);
    if (!se) continue;
    if (!prescribedWork(se).length) continue;
    const liftExercise = exerciseByName.get(lift.exerciseName);
    const loadStep = C.programLoadStep(program.roundingLb, liftExercise?.type);
    // A bodyweight-basis slot progresses by reps alone — its identity carries
    // no external load, so a numeric increment would store weight that
    // history, tonnage, and PR detection all ignore. Adding a belt is
    // switching to the weighted identity (Weighted Pull-up), not
    // incrementing this one. Mirrors SessionCompletion.
    const increment = liftExercise && C.resolvedLoadBasis(liftExercise) === "bodyweight" ? 0 : loadStep;
    const state = {
      sets: lift.doubleProgressionSets || 3, minReps: lift.minimumReps || 5,
      maxReps: lift.maximumReps || 8, currentReps: lift.currentReps || lift.minimumReps || 5,
      weightLb: lift.baseWeightLb, incrementLb: increment, stallCount: lift.stallCount || 0,
    };
    const next = C.advanceAccessory(state, accPerf(se, loadStep));
    lift.baseWeightLb = next.weightLb; lift.currentReps = next.currentReps;
    lift.stallCount = next.stallCount; lift.lastIncrementLb = next.weightLb - state.weightLb;
  }
  // Methodology slots that move per exposure: novice fives and Texas use their
  // linear rule; max effort sets the next target from the completed top single.
  // A day that repeats the same lift+style is still ONE exposure — only the
  // first slot advances
  // (twin sync carries the rest), so duplicates can never double-progress.
  const advancedExposureSlots = new Set();
  for (const lift of (day.lifts || []).filter((candidate) =>
    C.advancesPerExposure(candidate.prescription)
      && candidate.prescription !== "doubleProgression" && !isRecovery)) {
    const exposureKey = `${lift.exerciseName}|${lift.prescription}`;
    if (advancedExposureSlots.has(exposureKey)) continue;
    const se = programmedEntry(session, lift);
    if (!se || !prescribedWork(se).length) continue;
    advancedExposureSlots.add(exposureKey);
    const exercise = exerciseByName.get(lift.exerciseName);
    const loadStep = C.programLoadStep(program.roundingLb, exercise?.type);
    const priorBase = lift.baseWeightLb;
    const priorMax = lift.estimatedMaxLb;
    const perf = cyclePerf(se, loadStep);
    const adv = lift.prescription === "maxEffort"
      ? C.advanceProgramLift(lift, perf, program.focus, lift.prescription,
        exercise?.movementGroup, loadStep)
      : C.advanceLinearLift(lift, perf,
        C.linearRule(lift.prescription, exercise?.movementGroup), loadStep);
    lift.baseWeightLb = adv.state.baseWeightLb; lift.estimatedMaxLb = adv.state.estimatedMaxLb;
    lift.stallCount = adv.state.stallCount; lift.lastIncrementLb = adv.state.lastIncrementLb;
    // Non-success outcomes surface their explanation — a silent hold would
    // read as a broken app, and a deload must always say why.
    if (adv.grade !== "success" && adv.note) note(`${lift.exerciseName}: ${adv.note}`, lift.exerciseName);
    // Repeated slots of the same lift and style (novice squat on Day A and
    // Day B, Texas A/B day pairs) share ONE progression: mirror the advanced
    // state into every twin so "weight every session" holds across
    // alternating days instead of each slot advancing every other exposure.
    // Only twins still in lockstep (same base before this advance) are
    // synchronized — a deliberately diverged or manually edited twin keeps
    // its own base — and a hand-edited estimated 1RM on a twin survives the
    // sync the same way; edits must never disappear.
    for (const twinDay of program.days) {
      for (const twin of twinDay.lifts || []) {
        if (twin === lift || twin.exerciseName !== lift.exerciseName
          || twin.prescription !== lift.prescription
          || Math.abs(twin.baseWeightLb - priorBase) >= 0.001) continue;
        if (Math.abs((twin.estimatedMaxLb || 0) - priorMax) < 0.001) twin.estimatedMaxLb = lift.estimatedMaxLb;
        twin.baseWeightLb = lift.baseWeightLb;
        twin.stallCount = lift.stallCount; twin.lastIncrementLb = lift.lastIncrementLb;
      }
    }
  }
  for (const lift of (day.lifts || []).filter((candidate) => candidate.peakSingleEnabled && !isRecovery)) {
    const se = programmedEntry(session, lift);
    const single = se?.sets.find((set) => set.status === "completed" && set.prescriptionBlock === "topSingle"
      && set.reps >= 1 && !set.autoregReason && !set.bodyFlagSite
      && !(set.flags || []).some((flag) => flag === "grindy" || flag === "wobble"));
    if (single) lift.lastPeakSingleLb = Math.max(lift.lastPeakSingleLb || 0, single.weightLb);
  }
  // Outside the graded rotation the cycle does not advance, but the work still
  // happened, and a set taken past its prescription is the best estimate
  // available. Observation only: it can raise the estimate, never lower it,
  // because a submaximal prescription is not evidence of a smaller max. This is
  // what a capped AMRAP on the load rotation feeds.
  if (tag.week !== C.GRADED_WEEK && !isRecovery) {
    for (const lift of (day.lifts || []).filter((candidate) => !C.advancesPerExposure(candidate.prescription))) {
      const se = programmedEntry(session, lift);
      if (!se || !prescribedWork(se).length) continue;
      const loadStep = C.programLoadStep(program.roundingLb, exerciseByName.get(se.exerciseName)?.type);
      const perf = cyclePerf(se, loadStep);
      if (!(perf.topSetWeightLb > 0 && perf.topSetReps >= 1)) continue;
      lift.estimatedMaxLb = C.observedMax(
        lift.estimatedMaxLb, C.epleyE1RM(perf.topSetWeightLb, perf.topSetReps),
      );
    }
  }

  // Cycle lifts: grade at the week-3 Peak, stash pending; apply at rollover.
  // Headroom to the lifter's own logged prior best stages the increment; the
  // added-set governance decides whether a held cycle may fall back to
  // volume. Mirrors SessionCompletion's graded-week block.
  if (tag.week === C.GRADED_WEEK) {
    const volumeFallback = (program.maximumAddedSetsPerRotation ?? 6) > 0;
    const history = (await Sessions.completed())
      .filter((candidate) => String(candidate.id) !== String(session.id));
    const anchorMs = Date.parse(session.completedAt || session.date);
    for (const lift of (day.lifts || []).filter((candidate) => !C.advancesPerExposure(candidate.prescription))) {
      const se = programmedEntry(session, lift);
      if (se && prescribedWork(se).length) {
        const loadStep = C.programLoadStep(program.roundingLb, exerciseByName.get(se.exerciseName)?.type);
        const prior = priorBestE1RM(history, lift.exerciseName, anchorMs);
        // The advance rides the cycle's performed volume work so the base
        // resyncs to what was actually lifted (a kg rack lands the volume
        // rotation off the stored label in either direction). Evidence is
        // THIS cycle's own volume exposure, labeled under the bar that
        // session actually used — never the peak session's. Total-bar work
        // only — the ride reasons about the number as a bar-and-plates
        // stack, which machines and dumbbells must never get. Mirrors
        // SessionCompletion.
        const rideEvidence = twinBarLb(se, prescribedWork(se)) == null ? null
          : lastVolumeEvidence(lift, program, history, { inCycle: tag.cycleNumber });
        lift.pending = C.advanceProgramLift(lift, cyclePerf(se, loadStep), program.focus,
          lift.prescription || "automatic", exerciseByName.get(se.exerciseName)?.movementGroup, loadStep,
          // The headroom axis is a barbell rule — rebuild jumps are +10 lb
          // PLATE classes, which dumbbell and machine steps must never
          // inherit.
          C.progressionRegime(lift.estimatedMaxLb, prior.maxLb, prior.standing,
            C.resolvedLoadBasis(exerciseByName.get(se.exerciseName) || {}) === "totalBar" ? lift.baseWeightLb : 0), volumeFallback,
          rideEvidence == null ? 0
            : C.performedLabel(rideEvidence.performedLb, rideEvidence.barLabelLb, loadStep));
      }
    }
  }

  // Walk day ORDER values, not array positions (see core scheduleAdvance).
  // Recovery is set-based: count selected exposures actually banked in this
  // cycle. That handles either order, manual selection, and an old phase-4
  // pointer left on a day omitted by the shortened bridge.
  let advance;
  let recoveryCompletionReason = null;
  if (isRecovery) {
    const completedRecovery = (await Sessions.completed())
      .filter((candidate) => candidate.programTag
        && (candidate.programTag.programId === (program.uuid || program.id)
          || (candidate.programTag.programId == null
            && candidate.programTag.programName === program.name))
        && candidate.programTag.cycleNumber === program.cycleNumber
        && candidate.programTag.week === C.DELOAD_WEEK);
    if (!completedRecovery.some((candidate) => String(candidate.id) === String(session.id))) {
      completedRecovery.push(session); // current session is staged, not stored yet
    }
    const completedOrders = completedRecovery.map((candidate) => candidate.programTag.dayIndex);
    advance = C.recoveryScheduleAdvance(recoveryDayOrders, completedOrders);
    recoveryCompletionReason = C.recoveryBridgeCompletionReason(
      completedRecovery.length, recoveryDayOrders.length, advance.isLastDay, null,
      Date.parse(session.completedAt || session.date),
    );
  } else {
    advance = C.scheduleAdvance(allDayOrders, tag.dayIndex);
  }
  const lastDay = advance.isLastDay || recoveryCompletionReason !== null;
  program.nextDayIndex = advance.nextDayOrder;
  if (lastDay) {
    if (program.currentWeek < C.DELOAD_WEEK) {
      const early = await earlyDeloadDecision(program, session, exerciseByName);
      if (early) {
        // Write the hold through the same `pending` a real peak grade uses, so
        // rollover applies it on its existing path and never reaches the
        // skipped-peak stall branch. A slot that already carries a grade keeps
        // it — this only speaks for cycles whose peak never ran.
        for (const d of program.days) {
          for (const lift of d.lifts || []) {
            if (C.advancesPerExposure(lift.prescription) || lift.pending) continue;
            lift.pending = C.recoveryDeloadHold(lift, early.week);
          }
        }
        program.currentWeek = C.DELOAD_WEEK;
        program.nextDayIndex = recoveryDayOrders[0] ?? allDayOrders[0] ?? 0;
        note(`${program.name}: two red rotations in a row — going straight to the recovery bridge. Main-lift bases hold.`, null);
      } else {
        program.currentWeek += 1;
        if (program.currentWeek === C.DELOAD_WEEK) {
          program.nextDayIndex = recoveryDayOrders[0] ?? allDayOrders[0] ?? 0;
        }
      }
    } else {
      rollOverRecovery(program, exerciseByName, note);
    }
  }
  return { program, noteRecords: flushNotes() };
}

// ---- Build a session from a program day ----
// Secondary/accessory barbell work snaps to a neat bar-loadable weight (no
// lonely 2.5); main lifts keep their fine progression, and non-barbell work is
// left alone. Shared by session creation AND the Home preview so the "Start"
// card and the stored prescription never disagree.
export function neatProgramWeight(weightLb, exercise, isMain, barLb, stepLb, gym = null, phase = null) {
  if (!exercise || exercise.type !== "barbell" || !(weightLb > 0)) return weightLb;
  const target = !isMain ? C.barLoadable(weightLb, barLb, stepLb) : weightLb;
  if (!gym) return target;
  const bar = C.barById(gym.defaultBarId);
  // A near-miss clean stack (e.g. kg plates on a lb prescription) stays
  // loading guidance — the neat programmed number is what gets stored.
  return C.storedPrescription(target, C.prescriptionPlateOptions(target, bar, availablePlates(gym, exercise), 10,
    gym.collarWeightLb || 0, gym.loadingPolicy || "closest", phase === 1).selected.totalLb,
  C.barLabelLb(bar));
}

// The most recent completed base-training exposure for this slot: the volume
// rotation for wave slots (other rotations prescribe multiples of the base,
// so their weights are not comparable), any exposure for per-exposure styles
// (their plan is the base every session). For wave slots the caller scopes
// the CYCLE: planning reads evidence from before the cycle being planned
// (beforeCycle) so a cycle's own possibly-repaired exposure can never feed
// the repair that produced it, while the graded advance reads exactly the
// graded cycle's own volume work (inCycle). Entry matching goes through
// programmedEntry (slot ID + role, lineage fallback) plus a same-movement
// check, so a coaching rotation's renamed slot never inherits the old
// exercise's evidence; at-plan selection goes through prescribedWork
// (planned-set window, completed, non-warmup), so user-added bonus rows
// never grade a cycle — they surface separately as bonusLb, the
// planning-only catch-up signal. Returns the heaviest qualifying working
// weight and the BAR IT WAS LIFTED UNDER — the label the twin math must use,
// not whatever bar today's gym defaults to. Null means no evidence. Mirrors
// ProgramSession.lastVolumeEvidence.
export function lastVolumeEvidence(lift, program, sessions, { beforeCycle = null, inCycle = null } = {}) {
  const id = program.uuid || program.id;
  const mine = sessions
    .filter((s) => s.isCompleted && s.programTag
      && (s.programTag.programId === id
        || (s.programTag.programId == null && s.programTag.programName === program.name)))
    .sort((a, b) => Date.parse(b.completedAt || b.date) - Date.parse(a.completedAt || a.date));
  for (const session of mine) {
    if (!C.advancesPerExposure(lift.prescription)) {
      if (session.programTag.week !== 1) continue;
      if (beforeCycle != null && (session.programTag.cycleNumber ?? 0) >= beforeCycle) continue;
      if (inCycle != null && session.programTag.cycleNumber !== inCycle) continue;
    }
    const entry = programmedEntry(session, lift);
    if (!entry || entry.exerciseName !== lift.exerciseName) continue;
    const top = Math.max(0, ...prescribedWork(entry).map((set) => set.weightLb || 0));
    if (top > 0) {
      // The heaviest completed working set BEYOND the planned-set window —
      // work the lifter added on purpose. Grading never sees it; planning
      // treats it as an explicit catch-up signal (honestBase). A bonus row is
      // capability evidence only if at least one rep actually happened — a
      // failed heavy attempt marked completed proves the opposite.
      const candidates = (entry.sets || []).filter((set) => !set.isWarmup
        && C.countsAsPrescribedWork(set.prescriptionBlock));
      const bonus = Math.max(0, ...candidates.slice(entry.plannedSets ?? candidates.length)
        .filter((set) => set.status === "completed" && set.reps >= 1)
        .map((set) => set.weightLb || 0));
      return { performedLb: top, bonusLb: bonus,
        barLabelLb: C.barLabelLb(entry.barId ? C.barById(entry.barId) : C.BARS.bar45lb) };
    }
  }
  return null;
}

// The base every planning surface builds the cycle state from: the stored
// base, repaired by honestBase when the log proves the last earned advance
// moved the label but not the plates (a kg rack solves 215 and 225 to the
// identical 2×20 kg stack). Total-bar work only — the repair reasons about
// the number as a bar-and-plates stack, which is exactly the reading machines
// and dumbbells must never get. Shared by the session builder, the resume
// comparison, and every preview surface so the card, the preview, and the
// stored prescription agree by construction. Mirrors ProgramSession.planningBase.
export function planningBase(lift, exercise, program, sessions) {
  if (!exercise || C.resolvedLoadBasis(exercise) !== "totalBar") return lift.baseWeightLb;
  const evidence = lastVolumeEvidence(lift, program, sessions, {
    beforeCycle: C.advancesPerExposure(lift.prescription) ? null : program.cycleNumber,
  });
  if (!evidence) return lift.baseWeightLb;
  // The catch-up a bonus set can arm is the increment this lift's regime
  // currently earns — derived from slot state alone (the base-to-own-max
  // headroom axis), so every surface computes it identically without a
  // history scan. Mirrors ProgramSession.planningBase.
  const regime = C.progressionRegime(lift.estimatedMaxLb || 0, 0, false, lift.baseWeightLb);
  const catchUp = C.stagedIncrement(lift.baseWeightLb, program.focus, regime, program.roundingLb);
  // Catch-up is a CYCLE-slot mechanism: the wave's rollover advance rides the
  // raised plan, so plan and persisted base reconverge. A per-exposure
  // style's own rule (+5/session, Texas pairs) is its methodology contract —
  // overriding it here would prescribe a load its advance never persists,
  // drifting plan from base every session.
  const bonus = C.advancesPerExposure(lift.prescription) ? 0 : evidence.bonusLb;
  return C.honestBase(lift.baseWeightLb, lift.lastIncrementLb ?? 0,
    evidence.performedLb, program.roundingLb, evidence.barLabelLb,
    bonus, catchUp);
}

// The volume-fallback sets this lift carries, with the rotation-wide
// added-set budget allocated deterministically: stalled peak-graded slots in
// program order (day order, then slot order) receive one set each until
// maximumAddedSetsPerRotation is spent. Slots whose resolved style ignores
// the fallback still hold a rank — that spends budget conservatively rather
// than ever exceeding it. Shared by the session builder and every preview
// surface so the card and the stored prescription agree. Mirrors
// ProgramSession.volumeFallbackSets.
export function volumeFallbackSets(lift, program) {
  const stalled = [...(program.days || [])]
    .sort((a, b) => (a.order ?? 0) - (b.order ?? 0))
    .flatMap((day) => orderedProgramSlots(day.lifts || [])
      .filter((slot) => (slot.stallCount ?? 0) > 0 && !C.advancesPerExposure(slot.prescription)));
  const rank = stalled.findIndex((slot) => slot.id === lift.id);
  if (rank < 0) return 0;
  return C.volumeIncrementSets(lift.stallCount ?? 0, rank, program.maximumAddedSetsPerRotation ?? 6);
}

function orderedProgramSlots(slots = [], roleAwareLegacy = false) {
  const allLegacy = slots.length > 1 && slots.every((slot) => (slot.order ?? 0) === (slots[0].order ?? 0));
  return [...slots].sort((a, b) => {
    if (allLegacy && roleAwareLegacy) {
      const role = (a.role === "main" ? 0 : 1) - (b.role === "main" ? 0 : 1);
      if (role) return role;
    }
    return (a.order ?? 0) - (b.order ?? 0) || a.exerciseName.localeCompare(b.exerciseName);
  });
}

function sessionTargetsMatch(session, program, day, exMap, allSessions) {
  return orderedProgramSlots(day.lifts, true).every((lift) => {
    const exercise = exMap.get(lift.exerciseName);
    // The same honest base the builder plans from — an open session built
    // from the stale label must not resume once the repair raises the plan.
    const expected = C.programPlanFor(
      { cycleNumber: program.cycleNumber,
        baseWeightLb: planningBase(lift, exercise, program, allSessions),
        nextPhase: program.currentWeek, incrementLb: 0 },
      program.roundingLb, exercise?.type, exercise?.movementGroup,
      lift.role, program.focus, lift.prescription || "automatic",
      { ...lift, workingSets: lift.doubleProgressionSets ?? 3 },
    ).weightLb;
    if ((session.exercises || []).some((candidate) =>
      candidate.programSlotId === lift.id && candidate.programRole !== lift.role)) return false;
    const entry = programmedEntry(session, lift);
    // Session-local removals are deliberate and must remain resumable. Compare
    // only slots still present in the open snapshot.
    if (!entry) return true;
    const target = entry?.targetWeightLb ?? entry?.plannedWeightLb;
    return Number.isFinite(target) && Math.abs(target - expected) < 0.01;
  });
}

export async function createSessionFromProgramDay(program, day) {
  const recovery = await reconcileRecoveryBridge(program);
  if (recovery) {
    program = recovery.program;
    day = program.days.find((candidate) => candidate.order === program.nextDayIndex)
      || program.days[0];
    ui.toast(recovery.message);
  }
  // Resume, don't duplicate — but only a session for THIS day at the current
  // position whose BUILT-FROM plan still matches the current plan (issue 17).
  // A name/program-only match resurrected stale snapshots after a day was
  // edited; canResume compares the snapshot (not live exercises) so a
  // session-local remove/swap is preserved while a program edit builds fresh.
  const sortedLifts = orderedProgramSlots(day.lifts, true);
  const sortedAccessories = orderedProgramSlots(day.accessories);
  const dayNames = [...sortedLifts.map((l) => l.exerciseName), ...sortedAccessories.map((a) => a.exerciseName)];
  const stableProgramID = program.uuid || program.id;
  const [allSessions, allExercises, gym, settings, coachingDecisions] = await Promise.all([
    Sessions.all(), Exercises.all(), Gyms.default(), Settings.get(), CoachingDecisions.all(),
  ]);
  const exMap = new Map(allExercises.map((e) => [e.name, e]));
  // The bar resolves before the resume check: the honest base (planningBase)
  // labels performed stacks against the bar the session loads.
  const bar = gym ? C.barById(gym.defaultBarId) : C.BARS.bar45lb;
  const barLb = C.barLb(bar);
  const openForDay = allSessions.find((s) => !s.isCompleted && s.programTag
    && (s.programTag.programId === stableProgramID || (s.programTag.programId == null && s.programTag.programName === program.name))
    && C.canResumeSession(s.programTag.cycleNumber, s.programTag.week, s.programTag.dayIndex,
      program.cycleNumber, program.currentWeek, day.order,
      s.programTag.planNames || [], dayNames)
    && sessionTargetsMatch(s, program, day, exMap, allSessions));
  if (openForDay) return openForDay.id;
  const unit = C.primaryUnit(settings.unitDisplay);
  const neat = (weightLb, ex, isMain, phase = null) =>
    neatProgramWeight(weightLb, ex, isMain, barLb, program.roundingLb, gym, phase);
  const accessoryPercent = effectiveAccessoryPercent(program, coachingDecisions);
  const exercises = [];
  let order = 0;
  const lifts = sortedLifts;
  const preparedMovementGroups = new Set();
  for (const [liftIndex, lift] of lifts.entries()) {
    const ex = exMap.get(lift.exerciseName);
    const loadStep = C.programLoadStep(program.roundingLb, ex?.type);
    const configuration = { ...lift, workingSets: lift.doubleProgressionSets ?? 3 };
    const prescription = C.sessionPrescription(
      { cycleNumber: program.cycleNumber,
        baseWeightLb: planningBase(lift, ex, program, allSessions),
        nextPhase: program.currentWeek, incrementLb: 0 },
      program.roundingLb, ex?.type, ex?.movementGroup, lift.role, program.focus, lift.prescription || "automatic",
      configuration, lift.estimatedMaxLb || 0,
      // A held cycle moves the needle with volume: the stall the grade
      // recorded adds one set to this volume rotation, with the rotation-wide
      // budget allocated across stalled slots. Pure state, so the Home card
      // computes the identical count.
      volumeFallbackSets(lift, program),
    );
    const plan = prescription.mainWork;
    // Methodology slots prescribe exact loads (a +5/session contract, TM
    // percentages, speed waves) — snap them like main lifts, never through
    // the complementary per-side rounding that would distort the increments.
    const exactLoad = lift.role === "main" || C.buildsOwnSessionShape(lift.prescription || "automatic");
    const weightLb = neat(plan.weightLb, ex, exactLoad, program.currentWeek);
    const blockLoads = prescription.blocks.map((block) => neat(block.weightLb, ex, exactLoad, program.currentWeek));
    const sets = [];
    let so = 0;
    // A complementary lift that FOLLOWS other work finds the lifter already
    // warm, so two bridging sets are enough. A complementary slot ordered
    // first in the day still ramps fully — nothing has warmed the lifter
    // yet. An explicit per-slot policy always wins.
    const warmupPolicy = (lift.warmupPolicy || "automatic") === "automatic"
      ? ((lift.role === "complementary" && liftIndex > 0) || preparedMovementGroups.has(ex?.movementGroup) ? "short" : "full")
      : lift.warmupPolicy;
    const topPreparationLoad = blockLoads.length ? Math.max(...blockLoads) : weightLb;
    if (ex && ex.type === "barbell" && warmupPolicy !== "none") {
      const ramp = achievableWarmups(
        C.warmupRamp(topPreparationLoad, barLb, program.roundingLb,
          includesEmptyBarWarmup(ex.name)),
        topPreparationLoad, bar, gym, ex,
      );
      for (const wu of warmupPolicy === "short" ? ramp.slice(-2) : ramp) sets.push(mkSet(so++, wu.weightLb, wu.reps, { warm: true, unit, prescriptionBlock: "warmup", ...loadOptions(ex) }));
    }
    if (ex && ex.type === "dumbbell" && warmupPolicy !== "none") {
      const ramp = C.dumbbellWarmupRamp(topPreparationLoad, loadStep);
      for (const wu of warmupPolicy === "short" ? ramp.slice(-2) : ramp) sets.push(mkSet(so++, wu.weightLb, wu.reps, { warm: true, unit, prescriptionBlock: "warmup", perSide: ex.isUnilateral, ...loadOptions(ex) }));
    }
    prescription.blocks.forEach((block, blockIndex) => {
      const achieved = blockLoads[blockIndex];
      const isPrimer = block.kind === "primer";
      const last = sets.at(-1);
      if (isPrimer && last?.weightLb === achieved) return;
      for (let i = 0; i < block.sets; i += 1) sets.push(mkSet(so++, achieved, block.reps, {
        warm: isPrimer, perSide: ex && ex.isUnilateral, unit,
        targetWeightLb: block.weightLb, plannedWeightLb: achieved, plannedReps: block.reps,
        prescriptionBlock: block.kind, ...loadOptions(ex),
      }));
    });
    const automaticDrop = ["squat", "hinge"].includes(ex?.movementGroup) ? 10 : 5;
    const dropIncrement = lift.dropIncrementLb > 0 ? lift.dropIncrementLb : automaticDrop;
    const rawFallback = C.droppedLoad(weightLb, loadStep, ex?.type === "barbell" ? barLb : 0, dropIncrement);
    const fallbackWeightLb = ex?.type === "barbell" && gym
      ? C.storedPrescription(rawFallback,
        C.solve(rawFallback, bar, availablePlates(gym, ex), 10, gym.collarWeightLb || 0, "under").totalLb,
        C.barLabelLb(bar))
      : rawFallback;
    exercises.push({ order: order++, exerciseName: lift.exerciseName, notes: "", phase: program.currentWeek,
      targetWeightLb: plan.weightLb, plannedWeightLb: weightLb, plannedSets: plan.sets, plannedReps: plan.reps,
      fallbackWeightLb, prescriptionStyle: lift.prescription || "automatic",
      programRole: lift.role, programSlotId: lift.id, sets });
    if (ex?.movementGroup) preparedMovementGroups.add(ex.movementGroup);
  }
  for (const acc of sortedAccessories) {
    const ex = exMap.get(acc.exerciseName);
    const weightLb = neat(acc.weightLb, ex, false);
    const isTimed = ex?.type === "timed" || ex?.type === "conditioning";
    const ordinarySets = acc.capacityManaged === false
      ? acc.sets : Math.max(1, Math.round(acc.sets * accessoryPercent / 100));
    // Recovery retains movement familiarity but not a full accessory session.
    // Banking this exposure cannot advance the slot's rep/load target.
    const effectiveSets = program.currentWeek === C.DELOAD_WEEK ? 1 : ordinarySets;
    const sets = [];
    for (let i = 0; i < effectiveSets; i += 1) {
      const set = mkSet(i, isTimed ? 0 : weightLb, isTimed ? 1 : acc.currentReps, {
        perSide: ex && ex.isUnilateral, unit,
        targetWeightLb: isTimed ? 0 : acc.weightLb, plannedWeightLb: isTimed ? 0 : weightLb,
        plannedReps: isTimed ? 1 : acc.currentReps,
        plannedDurationSeconds: isTimed ? (acc.targetSeconds || 30) : null,
        prescriptionBlock: ex?.type === "conditioning" ? "conditioning" : "work",
        ...loadOptions(ex),
      });
      if (isTimed) set.durationSeconds = acc.targetSeconds || 30;
      sets.push(set);
    }
    exercises.push({ order: order++, exerciseName: acc.exerciseName, notes: "", phase: null,
      targetWeightLb: isTimed ? 0 : acc.weightLb, plannedWeightLb: isTimed ? 0 : weightLb,
      plannedSets: effectiveSets, plannedReps: isTimed ? 1 : acc.currentReps,
      plannedDurationSeconds: isTimed ? (acc.targetSeconds || 30) : null,
      programRole: "accessory", programSlotId: acc.id, sets });
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
            ui.h("span", { class: "sub mono", text: l.volumeLb > 0 ? `Top ${l.topSetLabel} · Volume ${ui.fmtWeight(l.volumeLb)}` : l.topSetLabel }))));
      }
      if (summary.coachingNotes?.length) {
        c.append(ui.h("div", { class: "section-title", text: "Coach" }));
        for (const note of summary.coachingNotes) c.append(ui.h("div", { class: "row" }, ui.h("span", { text: note })));
      }
      if (summary.milestones.length) {
        c.append(ui.h("div", { class: "section-title", text: "Milestones" }));
        for (const m of summary.milestones) c.append(ui.h("div", { class: "row" }, ui.h("span", { class: "accent", text: `⚑ ${m.label}` })));
      }
      c.append(ui.h("button", { class: "btn primary wide", style: { marginTop: "12px" }, text: "Done", onClick: () => { api.close(); onDone(); } }));
    },
  });
}
