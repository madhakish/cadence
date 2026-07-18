// CadenceCore, ported to JS. Pure functions, no DOM, no storage.
// This mirrors CadenceCore/Sources/CadenceCore/*.swift exactly; the
// companion test (web/tests/core.test.mjs) re-runs the Swift suite's
// assertions to keep them in lockstep. All weights are pounds (Double).

// ---- Units -----------------------------------------------------------------

export const KG_PER_LB = 0.45359237;            // exact international avoirdupois
export const LB_PER_KG = 1.0 / KG_PER_LB;

export const lbFromKg = (kg) => kg * LB_PER_KG;
export const kgFromLb = (lb) => lb * KG_PER_LB;
export const toLb = (value, unit) => (unit === "lb" ? value : lbFromKg(value));

// Round half away from zero, matching Swift's Double.rounded().
const roundHalfAway = (x) => Math.sign(x) * Math.round(Math.abs(x));

export function roundTo(valueLb, increment) {
  if (!(increment > 0)) return valueLb;
  return roundHalfAway(valueLb / increment) * increment;
}

// Dumbbells are stored per hand. Cap their prescription/progression step at
// 5 lb so a program-wide 10 lb rounding choice cannot become a 20 lb total
// upper-body jump. Mirrors ProgramEngine.loadStep.
export function programLoadStep(programRoundingLb, exerciseType = null) {
  return exerciseType === "dumbbell" ? Math.min(programRoundingLb, 5) : programRoundingLb;
}

// Program wave plan with a per-hand DB ceiling: a 55 lb volume base must not
// jump to 65 lb at Peak. Above-base DB rotations stay within one 5 lb rack
// jump; barbell/machine waves retain the normal percentages.
export function programPlanFor(state, programRoundingLb, exerciseType = null) {
  const plan = planFor(state, programLoadStep(programRoundingLb, exerciseType));
  if (exerciseType !== "dumbbell" || plan.weightLb <= state.baseWeightLb) return plan;
  return { ...plan, weightLb: Math.min(plan.weightLb, state.baseWeightLb + 5) };
}

// Round a target TOTAL to the nearest weight cleanly loadable on `barLb`: the
// per-side load snaps to `stepLb`, so no lonely 2.5 lb change plate (e.g. 150 on
// a 45 bar → 155 = 45+10/side). Never below the bar. For secondary/accessory
// barbell work where a neat weight beats an exact number. Mirrors Weight.barLoadable.
export function barLoadable(targetLb, barLb, stepLb) {
  if (!(stepLb > 0) || !(targetLb > barLb)) return Math.max(targetLb, barLb);
  const perSide = roundTo((targetLb - barLb) / 2.0, stepLb);
  return barLb + 2.0 * perSide;
}

// "232" or "232.4" — drop trailing zeros.
export function trim(value, decimals = 1) {
  const f = Math.pow(10, decimals);
  const rounded = roundHalfAway(value * f) / f;
  if (rounded === Math.round(rounded)) return rounded.toFixed(0);
  let s = rounded.toFixed(decimals);
  while (s.endsWith("0")) s = s.slice(0, -1);
  if (s.endsWith(".")) s = s.slice(0, -1);
  return s;
}

// "232 lb / 105.2 kg"
export const both = (lb) => `${trim(lb)} lb / ${trim(kgFromLb(lb))} kg`;

export function unitFormat(mode, lb) {
  switch (mode) {
    case "kgPrimary": return `${trim(kgFromLb(lb))} kg`;
    case "both": return both(lb);
    case "lbPrimary":
    default: return `${trim(lb)} lb`;
  }
}
export const primaryUnit = (mode) => (mode === "kgPrimary" ? "kg" : "lb");

// ---- Explicit set lifecycle -------------------------------------------------
export const SET_STATUSES = ["planned", "completed", "skipped"];
export const SET_QUALITIES = ["clean", "grindy", "wobble"];
export const resolveSetStatus = (raw, sessionCompleted) => SET_STATUSES.includes(raw) ? raw : (sessionCompleted ? "completed" : "planned");
export const setQuality = (flags = []) => flags.find((flag) => SET_QUALITIES.includes(flag)) || null;
export const normalizedSetFlags = (quality, stoppedEarly = false) => [
  ...(SET_QUALITIES.includes(quality) ? [quality] : []),
  ...(stoppedEarly ? ["stopped early"] : []),
];

// ---- Plates & bars ---------------------------------------------------------

export const plateLb = (p) => toLb(p.value, p.unit);
export const plateId = (p) => `${p.value}-${p.unit}`;
export const plateLabel = (p) => `${trim(p.value, 2)} ${p.unit}`;

// Plate colour token (the user's gym scheme). The UI maps the token → a hex.
// kg is IWF: 25 red · 20 blue · 15 yellow · 10 green · 5 white · 2.5 red change plate.
// lb (colour bumpers): 55 red · 45 blue · 35 yellow · 25 green · 10 white ·
// 5 and under (and fractional) black iron.
export function plateColorToken(plate) {
  if (plate.unit === "lb") {
    if (plate.value >= 55) return "red";
    if (plate.value === 45) return "blue";
    if (plate.value === 35) return "yellow";
    if (plate.value === 25) return "green";
    if (plate.value === 10) return "white";
    return "black"; // 5, 2.5, fractional
  }
  if (plate.value >= 25) return "red";
  if (plate.value === 20) return "blue";
  if (plate.value === 15) return "yellow";
  if (plate.value === 10) return "green";
  if (plate.value === 5) return "white";
  if (plate.value === 2.5) return "red"; // IWF change plate
  return "black"; // 1.25 + misc
}

// Relative drawn diameter of a plate (0.4–1.0), by canonical pounds, so the
// barbell graphic looks physically right regardless of unit.
export function plateSizeFactor(plate) {
  const lb = plateLb(plate);
  if (lb >= 44) return 1.0;   // 45/55 lb, 20/25 kg
  if (lb >= 33) return 0.9;   // 35 lb, 15 kg
  if (lb >= 22) return 0.78;  // 25 lb, 10 kg
  if (lb >= 11) return 0.62;  // 10 lb, 5 kg
  if (lb >= 5) return 0.5;    // 5 lb
  return 0.4;                 // 2.5 lb / fractional
}

const mkPlates = (vals, unit) => vals.map((value) => ({ value, unit }));
export const STANDARD_KG = mkPlates([25, 20, 15, 10, 5, 2.5, 1.25], "kg");
export const STANDARD_LB = mkPlates([45, 35, 25, 10, 5, 2.5], "lb");
export const ALL_STANDARD = [...STANDARD_LB, ...STANDARD_KG];

export const BARS = {
  bar45lb: { value: 45, unit: "lb" },
  bar35lb: { value: 35, unit: "lb" },
  bar20kg: { value: 20, unit: "kg" },
  bar15kg: { value: 15, unit: "kg" },
};
export const ALL_BARS = [BARS.bar45lb, BARS.bar35lb, BARS.bar20kg, BARS.bar15kg];
export const barLb = (b) => toLb(b.value, b.unit);
export const barId = (b) => `${b.value}-${b.unit}`;
export const barLabel = (b) => `${trim(b.value)} ${b.unit} bar`;
export const barById = (id) => ALL_BARS.find((b) => barId(b) === id) || BARS.bar45lb;

export const plateCountLb = (pc) => plateLb(pc.plate) * pc.count;
export const plateCountLabel = (pc) =>
  pc.count === 1 ? plateLabel(pc.plate) : `${plateLabel(pc.plate)} ×${pc.count}`;

export function loadoutPerSideLb(perSide) {
  return perSide.reduce((s, pc) => s + plateCountLb(pc), 0);
}
export function loadoutTotalLb(bar, perSide) {
  return barLb(bar) + 2 * loadoutPerSideLb(perSide);
}
export function perSideLabel(perSide) {
  if (!perSide.length) return "bar only";
  return [...perSide]
    .sort((a, b) => plateLb(b.plate) - plateLb(a.plate))
    .map(plateCountLabel)
    .join(" + ");
}

// ---- Plate math ------------------------------------------------------------

export const TOLERANCE_LB = 2.0;

// Branch-and-bound closest per-side load, loaded the way a human loads: within
// TOLERANCE_LB of the target the fewest plates win, then the fewest distinct
// denominations (matched pairs), then a single unit system (no kg+lb
// frankenstacks), then closeness, then erring under. Outside that band it falls
// back to plain closest-then-fewest. Mixed units still appear when they're the
// only way to get close. Mirrors PlateMath.solve.
// Loaded the way a human actually loads: within the band, a stack that IS the
// heaviest-first greedy fill of its own weight (in its own unit system) beats
// any re-shuffled stack — 105/side is 45+45+10+5, never 35×3. Between greedy
// stacks the fewest plates win (220 → 2×20 kg, not 45+35+5+2.5).
export function solve(targetLb, bar, plates, maxPerPlateSide = 10) {
  const perSideTarget = (targetLb - barLb(bar)) / 2.0;

  // dedup by id, sort heaviest-lb first
  const seen = new Map();
  for (const p of plates) seen.set(plateId(p), p);
  const sorted = [...seen.values()].sort((a, b) => plateLb(b) - plateLb(a));

  const empty = () => makeSolution(bar, [], targetLb);
  if (!(perSideTarget > 1e-9) || sorted.length === 0) return empty();

  const values = sorted.map(plateLb);
  const counts = new Array(sorted.length).fill(0);
  let bestCounts = counts.slice();
  let best = null; // { dev, signed, used, distinct, mixed }
  let nodes = 0;

  const isBetter = (c, b) => {
    if (!b) return true;
    const tol = TOLERANCE_LB + 1e-9;
    const cIn = c.dev <= tol, bIn = b.dev <= tol;
    if (cIn !== bIn) return cIn; // a good-enough load beats an out-of-band one
    if (cIn) { // both good enough → cleanest to load, heaviest plates first
      if (c.canonical !== b.canonical) return c.canonical;
      if (c.used !== b.used) return c.used < b.used;
      if (c.distinct !== b.distinct) return c.distinct < b.distinct;
      if (c.mixed !== b.mixed) return !c.mixed;
      if (Math.abs(c.dev - b.dev) > 1e-9) return c.dev < b.dev;
      return c.signed < b.signed - 1e-9; // equal miss: prefer under target
    }
    // both out of band → closest, then fewest plates, then under
    if (Math.abs(c.dev - b.dev) > 1e-9) return c.dev < b.dev;
    if (c.used !== b.used) return c.used < b.used;
    return c.signed < b.signed - 1e-9;
  };

  // True when the stack IS the heaviest-first greedy fill of its own achieved
  // weight within one unit system — how a human racks plates (max out the
  // 45s, then work down). Mixed stacks are never canonical.
  const isGreedyCanonical = (achieved, mixed, used) => {
    if (used === 0) return true;
    if (mixed) return false;
    const first = sorted.findIndex((_, i) => counts[i] > 0);
    if (first < 0) return true;
    const system = sorted[first].unit;
    let rem = achieved;
    for (let i = 0; i < sorted.length; i += 1) {
      if (sorted[i].unit !== system) continue;
      const c = Math.min(maxPerPlateSide, Math.floor(rem / values[i] + 1e-9));
      if (counts[i] !== c) return false;
      rem -= c * values[i];
    }
    return true;
  };

  // used/distinct/kg/lb are threaded through the recursion so each node is O(1)
  // (no per-node rescan of counts) — solve() runs on every plate-calculator keystroke.
  const consider = (remaining, used, distinct, mixed) => {
    const signed = -remaining * 2.0; // achieved − target (total lb)
    // Canonicality only matters inside the band — skip the walk elsewhere.
    const canonical = Math.abs(signed) <= TOLERANCE_LB + 1e-9
      && isGreedyCanonical(perSideTarget - remaining, mixed, used);
    const c = { dev: Math.abs(signed), signed, used, distinct, mixed, canonical };
    if (isBetter(c, best)) { best = c; bestCounts = counts.slice(); }
  };

  const search = (index, remaining, used, distinct, kg, lb) => {
    nodes += 1;
    if (nodes >= 300000) return;
    consider(remaining, used, distinct, kg > 0 && lb > 0);
    if (index >= values.length || !(remaining > 1e-9)) return;
    const v = values[index];
    const isKg = sorted[index].unit === "kg";
    const maxCount = Math.min(maxPerPlateSide, Math.floor(remaining / v) + 1);
    // Prune overshoots past the good-enough band AND the best deviation so far,
    // so cleaner in-tolerance loads are never pruned away.
    const bound = Math.max(TOLERANCE_LB, best ? best.dev : perSideTarget * 2.0);
    for (let c = maxCount; c >= 0; c -= 1) {
      const next = remaining - c * v;
      if (next < 0 && -next * 2.0 > bound + 1e-9) continue; // overshoot past the band
      counts[index] = c;
      const d = distinct + (c > 0 ? 1 : 0);
      search(index + 1, next, used + c, d, kg + (c > 0 && isKg ? 1 : 0), lb + (c > 0 && !isKg ? 1 : 0));
    }
    counts[index] = 0;
  };

  // Seed best with a clean single-unit greedy fill per unit system. Gives the
  // search a tight bound from the first node AND guarantees we never return a
  // worse-than-simple stack if the 300k-node cap trips on a heavy mixed
  // inventory (e.g. 405 → 45×4, not a kg+lb frankenstack).
  const seedGreedy = (unit) => {
    counts.fill(0);
    let remaining = perSideTarget, used = 0, distinct = 0;
    for (let i = 0; i < sorted.length; i += 1) {
      if (sorted[i].unit !== unit) continue;
      const c = Math.min(maxPerPlateSide, Math.floor(remaining / values[i] + 1e-9));
      if (c > 0) { counts[i] = c; remaining -= c * values[i]; used += c; distinct += 1; }
    }
    if (used > 0) consider(remaining, used, distinct, false);
  };
  seedGreedy("lb");
  seedGreedy("kg");
  counts.fill(0);

  search(0, perSideTarget, 0, 0, 0, 0);

  const perSide = [];
  for (let i = 0; i < sorted.length; i += 1) {
    if (bestCounts[i] > 0) perSide.push({ plate: sorted[i], count: bestCounts[i] });
  }
  return makeSolution(bar, perSide, targetLb);
}

function makeSolution(bar, perSide, targetLb) {
  const sortedPerSide = [...perSide].sort((a, b) => plateLb(b.plate) - plateLb(a.plate));
  const totalLb = loadoutTotalLb(bar, sortedPerSide);
  const deviationLb = totalLb - targetLb;
  return {
    bar,
    perSide: sortedPerSide,
    targetLb,
    totalLb,
    deviationLb,
    isOffTarget: Math.abs(deviationLb) > TOLERANCE_LB,
  };
}

// Reverse mode: what's on the bar → total.
export const totalOnBar = (bar, perSide) => loadoutTotalLb(bar, perSide);

// ---- Warmup ramp -----------------------------------------------------------

const RAMP_STEPS = [
  { percent: 0.40, reps: 5 },
  { percent: 0.55, reps: 3 },
  { percent: 0.70, reps: 2 },
  { percent: 0.85, reps: 1 },
];

export function warmupRamp(workingLb, barLb = 45, roundingLb = 5) {
  const sets = [{ weightLb: barLb, reps: 10 }];
  for (const step of RAMP_STEPS) {
    const w = roundTo(workingLb * step.percent, roundingLb);
    if (w > barLb + 1e-9 && w < workingLb - 1e-9) sets.push({ weightLb: w, reps: step.reps });
  }
  return sets.map((s) => ({ ...s, label: `${trim(s.weightLb)} × ${s.reps}` }));
}


// Short per-hand ramp for a main dumbbell lift: no empty-bar opener, no
// duplicate rack weights, and never the working weight itself.
export function dumbbellWarmupRamp(workingLb, roundingLb = 5) {
  if (!(workingLb > 0)) return [];
  const seen = new Set();
  return [[0.40, 10], [0.60, 5], [0.80, 2]].flatMap(([percent, reps]) => {
    const weightLb = Math.max(roundingLb, roundTo(workingLb * percent, roundingLb));
    if (weightLb >= workingLb - 1e-9 || seen.has(weightLb)) return [];
    seen.add(weightLb);
    return [{ weightLb, reps }];
  });
}

// ---- Program engine (4-week cycle) -----------------------------------------

// phase: 1 volume, 2 load, 3 peak, 4 deload
export const PHASES = {
  1: { name: "Volume", sets: 5, reps: 5, multiplier: 1.0 },
  2: { name: "Load", sets: 5, reps: 3, multiplier: 1.10 },
  3: { name: "Peak", sets: 3, reps: 3, multiplier: 1.175 },
  4: { name: "Deload", sets: 3, reps: 5, multiplier: 0.775 },
};
export const phaseNext = (p) => (p >= 4 ? 1 : p + 1);
export const phaseLabel = (p) => {
  const ph = PHASES[p];
  return `R${p} ${ph.name} ${ph.sets}×${ph.reps}`;
};

export const DEFAULT_ROUNDING_LB = 5.0;

// state: { cycleNumber, baseWeightLb, nextPhase, incrementLb }
export function planFor(state, roundingLb = DEFAULT_ROUNDING_LB) {
  const p = state.nextPhase;
  const ph = PHASES[p];
  return {
    weightLb: roundTo(state.baseWeightLb * ph.multiplier, roundingLb),
    sets: ph.sets,
    reps: ph.reps,
    phase: p,
    cycleNumber: state.cycleNumber,
  };
}

export function advancing(state, afterCompleting) {
  const next = { ...state };
  if (afterCompleting === 4) {
    next.cycleNumber += 1;
    next.baseWeightLb += state.incrementLb;
    next.nextPhase = 1;
  } else {
    next.nextPhase = phaseNext(afterCompleting);
  }
  return next;
}

// One tap "dropping load": cut remaining sets ~7%, round, never below bar.
export function droppedLoad(currentLb, roundingLb = DEFAULT_ROUNDING_LB, barLb = 45) {
  const dropped = roundTo(currentLb * 0.93, roundingLb);
  const result = dropped >= currentLb ? currentLb - roundingLb : dropped;
  return Math.max(result, barLb);
}

// Which sets a mid-session "dropping load" tap rewrites, and to what. Only
// not-yet-performed sets (unflagged working sets) are touched — a flagged set
// is history — and each is dropped from ITS OWN weight, so a lighter back-off
// set is never raised toward the top set's drop. Mirrors
// ProgramEngine.dropLoadPlan.
export function dropLoadPlan(sets, roundingLb = DEFAULT_ROUNDING_LB, barLb = 45) {
  const out = [];
  sets.forEach((s, index) => {
    if (s.isWarmup || s.isFlagged) return;
    out.push({ index, weightLb: droppedLoad(s.weightLb, roundingLb, barLb) });
  });
  return out;
}

export const AUTOREG_REASONS = ["bar speed", "wobble", "joint signal", "heat", "fatigue"];

// plan: { weightLb, sets, reps, phase? }
export function sessionPlanLabel(plan) {
  const base = `${trim(plan.weightLb)} × ${plan.sets}×${plan.reps}`;
  if (plan.phase) return `${base} — R${plan.phase} ${PHASES[plan.phase].name}`;
  return base;
}

// linear-mode suggestion helper
export const linearPlan = (baseWeightLb) => ({ weightLb: baseWeightLb, sets: 3, reps: 5, phase: null });

// ---- PR detection ----------------------------------------------------------

// sets: [{ weightLb, reps }]
export const prVolume = (sets) => sets.reduce((s, x) => s + x.weightLb * x.reps, 0);

export function prTopScheme(sets) {
  if (!sets.length) return null;
  const top = Math.max(...sets.map((s) => s.weightLb));
  const topSets = sets.filter((s) => Math.abs(s.weightLb - top) < 1e-9);
  if (!topSets.length) return null;
  const reps = Math.min(...topSets.map((s) => s.reps));
  return { weightLb: top, sets: topSets.length, reps };
}

// Returns [{ kind, exercise, label }], kind ∈ heaviestSet|firstScheme|volumePR
export function prEvaluate({ exercise, sessionSets, historySets, historyVolumes, historySchemes, formatWeight = null }) {
  if (!sessionSets.length) return [];
  const events = [];
  const weightLabel = formatWeight || trim;
  const priorMax = historySets.length ? Math.max(...historySets.map((s) => s.weightLb)) : 0;
  const top = prTopScheme(sessionSets);
  const schemes = historySchemes instanceof Set ? historySchemes : new Set(historySchemes);

  if (top) {
    if (top.weightLb > priorMax + 1e-9) {
      const scheme = top.sets > 1
        ? `${weightLabel(top.weightLb)}×${top.sets}×${top.reps}`
        : `${weightLabel(top.weightLb)}×${top.reps}`;
      events.push({ kind: "heaviestSet", exercise, label: `${scheme} — heaviest ${exercise.toLowerCase()} logged` });
    }
    const schemeKey = `${top.sets}×${top.reps}`;
    if (!schemes.has(schemeKey)) {
      events.push({ kind: "firstScheme", exercise, label: `First ${schemeKey} — ${weightLabel(top.weightLb)} ${exercise.toLowerCase()}` });
    }
  }

  const vol = prVolume(sessionSets);
  const priorVolMax = historyVolumes.length ? Math.max(...historyVolumes) : 0;
  if (vol > priorVolMax + 1e-9 && historyVolumes.length) {
    const volumeLabel = formatWeight ? formatWeight(vol) : `${trim(vol)} lb`;
    events.push({ kind: "volumePR", exercise, label: `Volume PR — ${volumeLabel} total ${exercise.toLowerCase()}` });
  }
  return events;
}

// ---- Adaptive program progression --------------------------------------------
// Cross-cycle progression that is performance-gated, tapers toward an estimated
// ceiling, and auto-deloads on repeated stalls. Pure & deterministic — consumes
// a performance SUMMARY (never a session), no clock/random. Mirrors
// CadenceCore/Sources/CadenceCore/ProgramProgression.swift exactly.

export const QUALITY_FLAG_TOLERANCE = 1;   // ≤1 grindy/wobble set still SUCCESS
export const STALL_LIMIT = 2;              // 2 consecutive non-success → auto deload
export const DELOAD_REBUILD_FRACTION = 0.90;

// focus → { tm: training-max as fraction of e1RM, inc: increment fraction of base }
export const FOCUS = {
  strength: { tm: 0.90, inc: 0.025 },
  hypertrophy: { tm: 0.78, inc: 0.015 },
  maintain: { tm: 0.0, inc: 0.0 },
};
export const focusParams = (focus) => FOCUS[focus] || FOCUS.strength;

export const epleyE1RM = (weightLb, reps) => (reps >= 1 ? weightLb * (1 + reps / 30.0) : weightLb);
export const smoothE1RM = (prior, sample) => (prior <= 0 ? sample : 0.7 * prior + 0.3 * sample);

// perf: { prescribedSets, prescribedReps, completedSets, anyStoppedEarly,
//         anyDroppedLoad, anyBelowPlanLoad, grindyOrWobbleSets, topSetWeightLb, topSetReps }
export function gradeCycle(perf) {
  if (perf.completedSets < perf.prescribedSets || perf.anyStoppedEarly || perf.anyDroppedLoad
      || perf.anyBelowPlanLoad) return "fail";
  if (perf.grindyOrWobbleSets > QUALITY_FLAG_TOLERANCE) return "hold";
  return "success";
}

// Whether a working set's actual load fell below its prescription. Reps at a
// reduced weight must not grade as a clean success — that would reset the stall
// counter and bump the base weight off work that wasn't done. The tolerance is
// HALF a plate-rounding step: within it counts as met (float noise, kg-entry
// conversions), a full step down is a genuine drop. Applies to manual edits and
// autoreg drops alike; heavier than planned is always fine; no prescription
// (null/zero plan) means nothing to compare against.
export function belowPlanLoad(actualLb, plannedLb, roundingLb = DEFAULT_ROUNDING_LB) {
  if (plannedLb == null || plannedLb <= 0) return false;
  return actualLb < plannedLb - roundingLb / 2;
}

// Aggregate for a whole lift: the prescription is met when at least
// prescribedSets working sets are at the planned load. Extra sets beyond the
// prescription are bonus volume — a lighter back-off set after completing the
// planned work must not fail the cycle. Fewer at-plan sets than prescribed
// (whole lift performed light, or one prescribed set cut down) is below plan.
export function belowPlanWork(weightsLb, plannedLb, prescribedSets, roundingLb = DEFAULT_ROUNDING_LB) {
  if (plannedLb == null || plannedLb <= 0) return false;
  const atPlan = weightsLb.filter((w) => !belowPlanLoad(w, plannedLb, roundingLb)).length;
  return atPlan < prescribedSets;
}

// A banked session may only advance the program if its tag (captured at
// creation) still matches the program's live position — otherwise it's a
// duplicate or stale session and must be kept as history without moving the
// schedule a second time (issue 17: banking two copies of a week's final day
// skipped a whole week).
export function sessionTagCurrent(tagCycle, tagWeek, tagDayIndex, cycleNumber, currentWeek, nextDayIndex) {
  return tagCycle === cycleNumber && tagWeek === currentWeek && tagDayIndex === nextDayIndex;
}

// Whether an OPEN session may be resumed on (re)Start vs built fresh: same
// cycle/week/day tag AND the plan it was BUILT from still equals the day's
// CURRENT plan. Snapshot-vs-current, not the live exercises — so a session-
// local remove/swap is preserved (resumed), while a PROGRAM edit or position
// move diverges the built-from plan → build fresh. Empty sessionPlanNames
// (pre-snapshot session) never resumes. Mirrors CadenceCore canResumeSession.
export function canResumeSession(tagCycle, tagWeek, tagDayIndex, cycleNumber, currentWeek, dayIndex, sessionPlanNames, dayPlanNames) {
  return tagCycle === cycleNumber && tagWeek === currentWeek && tagDayIndex === dayIndex
    && sessionPlanNames.length > 0 && sessionPlanNames.length === dayPlanNames.length
    && sessionPlanNames.every((n, i) => n === dayPlanNames[i]);
}

// ---- Swap rules (issue 20) ----------------------------------------------
// Mirrors CadenceCore's SwapRules. Exercise types that can't carry a weight
// prescription — a loaded slot must never be offered an unloadable substitute
// (Incline DB Press → Dips) or vice versa.
export const UNLOADABLE_TYPES = new Set(["bodyweight", "timed", "conditioning"]);

// A candidate is offered only when it trains the same movement pattern
// (non-empty matching group), sits in the same programming tier
// (Main/Accessory/Conditioning), matches the current lift's loadability,
// isn't the same exercise, and isn't shelved. `current`/`candidate` are
// exercise records: { name, category, type, movementGroup, isShelved }.
export function swapCompatible(current, candidate) {
  return !!current.movementGroup
    && candidate.movementGroup === current.movementGroup
    && candidate.name !== current.name
    && !candidate.isShelved
    && candidate.category === current.category
    && UNLOADABLE_TYPES.has(candidate.type) === UNLOADABLE_TYPES.has(current.type);
}

// The transactional boundary for banking a session (issue 19), mirroring
// CadenceCore's CompletionPersistence.commit: save the staged completion batch
// or roll it back and rethrow, so side effects only ever run after a durable
// commit. The web app gets this atomicity natively from its single IndexedDB
// completion transaction; the mirror exists for the native app and parity.
export function completionCommit(save, rollback) {
  try {
    save();
  } catch (e) {
    // The save failure is the truth the caller needs; a rollback that also
    // throws must not mask it. (The Swift mirror gets this for free — its
    // rollback closure is typed non-throwing.)
    try { rollback(); } catch { /* keep the save failure */ }
    throw e;
  }
}

// Increment = fraction of base × headroom-to-ceiling, floored at plate granularity,
// 0 at/over the focus-dependent training-max ceiling.
export function taperedIncrement(baseWeightLb, estimatedMaxLb, focus, roundingLb = DEFAULT_ROUNDING_LB) {
  const fp = focusParams(focus);
  if (fp.inc <= 0) return 0; // maintain never increments
  const ceiling = estimatedMaxLb * fp.tm;
  if (ceiling <= 0 || baseWeightLb >= ceiling) return 0;
  const headroom = Math.max(0, Math.min(1, (ceiling - baseWeightLb) / ceiling));
  const raw = baseWeightLb * fp.inc * headroom;
  let inc = Math.floor(raw / roundingLb) * roundingLb;
  if (inc < roundingLb && headroom > 0.02) inc = roundingLb; // guarantee a loadable bump unless basically at ceiling
  if (baseWeightLb + inc > ceiling) inc = Math.max(0, Math.floor((ceiling - baseWeightLb) / roundingLb) * roundingLb);
  return inc;
}

// state: { baseWeightLb, estimatedMaxLb, stallCount, role, lastIncrementLb }
// returns { state, grade, note }
export function advanceCycleLift(state, perf, focus, roundingLb = DEFAULT_ROUNDING_LB) {
  const grade = gradeCycle(perf);
  const sample = epleyE1RM(perf.topSetWeightLb, perf.topSetReps);
  const estimatedMaxLb = smoothE1RM(state.estimatedMaxLb, sample);
  const next = { ...state, estimatedMaxLb };
  let note = null;

  if (grade === "success") {
    next.stallCount = 0;
    const inc = taperedIncrement(state.baseWeightLb, estimatedMaxLb, focus, roundingLb);
    next.baseWeightLb = state.baseWeightLb + inc;
    next.lastIncrementLb = inc;
    if (inc === 0) note = focusParams(focus).inc <= 0 ? "Maintaining — holding weight." : "At training-max ceiling — holding weight.";
  } else {
    next.stallCount = state.stallCount + 1;
    next.lastIncrementLb = 0;
    if (next.stallCount >= STALL_LIMIT) {
      const old = next.baseWeightLb;
      next.baseWeightLb = roundTo(old * DELOAD_REBUILD_FRACTION, roundingLb);
      next.stallCount = 0;
      note = `Two cycles without a clean peak — deloaded ${trim(old)}→${trim(next.baseWeightLb)} lb to rebuild.`;
    } else {
      note = grade === "fail" ? "Missed peak work — holding weight, retry the cycle."
                              : "Grindy peak — holding weight, retry the cycle.";
    }
  }
  return { state: next, grade, note };
}

// Accessory double progression. state: { sets, minReps, maxReps, currentReps,
// weightLb, incrementLb, stallCount }; perf: { completedSets, minRepsAchieved, anyStoppedEarly }
export function advanceAccessory(state, perf) {
  const next = { ...state };
  const hitAll = perf.completedSets >= state.sets && perf.minRepsAchieved >= state.currentReps && !perf.anyStoppedEarly;
  const weighted = state.incrementLb > 0;
  if (!hitAll) {
    next.stallCount = state.stallCount + 1;
  } else if (weighted && state.currentReps >= state.maxReps) {
    next.weightLb = state.weightLb + state.incrementLb; // earned the rep range → add load, reset reps
    next.currentReps = state.minReps;
    next.stallCount = 0;
  } else {
    // weighted: climb to the cap. bodyweight/timed (no loadable increment): keep
    // climbing reps — maxReps is advisory, since there's no weight to add.
    next.currentReps = weighted ? Math.min(state.currentReps + 1, state.maxReps) : state.currentReps + 1;
    next.stallCount = 0;
  }
  return next;
}

// ---- Rest defaults ---------------------------------------------------------
// Five user-tunable rest buckets (seconds) — the SMART DEFAULTS an exercise
// falls to when it has no explicit rest of its own. Mirrors CadenceCore
// RestConfig.standard.
export const REST_DEFAULTS = {
  mainCompoundSeconds: 300, // main squat & hinge lifts
  olympicSeconds: 240,      // main olympic lifts
  mainUpperSeconds: 180,    // other main lifts (presses etc.)
  secondarySeconds: 180,    // complementary program lifts
  accessorySeconds: 90,     // accessories
};

// Smart per-exercise rest, resolved in a fixed precedence order:
//   1. the exercise's own rest (exerciseDefaultRest > 0) wins everywhere —
//      the deliberate exception (set via ⏱ in the logger or the library);
//   2. conditioning never rests;
//   3. the exercise's role in today's program (complementary → secondary
//      bucket, accessory → accessory bucket);
//   4. otherwise the movement decides, keyed on movementGroup (the same
//      data-driven grouping that powers swaps — never name matching):
//      main squat/hinge → mainCompound, main olympic → olympic, any other
//      main → mainUpper, everything else → accessory.
// Pure; mirrored 1:1 in CadenceCore/RestDefaults.swift.
export function restDefaultSeconds(category, movementGroup, role = null, config = REST_DEFAULTS, exerciseDefaultRest = 0) {
  if (exerciseDefaultRest > 0) return exerciseDefaultRest; // per-exercise rest wins everywhere
  if (category === "Conditioning" || movementGroup === "conditioning") return 0;
  if (role === "complementary") return config.secondarySeconds;
  if (role === "accessory") return config.accessorySeconds;
  if (category === "Main") {
    if (movementGroup === "squat" || movementGroup === "hinge") return config.mainCompoundSeconds;
    if (movementGroup === "olympic") return config.olympicSeconds;
    return config.mainUpperSeconds;
  }
  return config.accessorySeconds;
}

// ---- Rest clock ------------------------------------------------------------
// Pure state math for the between-sets rest countdown — one implementation of
// pause/resume/extend shared by the logger's timer here and (mirrored 1:1)
// CadenceCore/RestClock.swift, which also drives the native Live Activity.
// Deterministic: every transition takes `now` (epoch SECONDS) explicitly.
// State: { endEpoch, paused, pausedRemaining, total }.
export function restClockStart(total, now) {
  const t = Math.max(0, total);
  return { endEpoch: now + t, paused: false, pausedRemaining: 0, total: t };
}
// Idempotent: pausing a paused clock changes nothing (a second tap must not
// re-freeze a stale remaining).
export function restClockPause(s, now) {
  if (s.paused) return s;
  return { ...s, paused: true, pausedRemaining: Math.max(0, s.endEpoch - now) };
}
// Idempotent: resuming a running clock changes nothing.
export function restClockResume(s, now) {
  if (!s.paused) return s;
  return { ...s, paused: false, endEpoch: now + Math.max(0, s.pausedRemaining) };
}
// Extend (or shrink, negative): the frozen remaining moves while paused, the
// end moves while running. Both floor at 0.
export function restClockAdd(s, seconds) {
  const total = Math.max(0, s.total + seconds);
  if (s.paused) return { ...s, total, pausedRemaining: Math.max(0, s.pausedRemaining + seconds) };
  return { ...s, total, endEpoch: s.endEpoch + seconds };
}
export function restClockRemaining(s, now) {
  return s.paused ? s.pausedRemaining : Math.max(0, s.endEpoch - now);
}
// 1 at the start of the rest, 0 when it's over (the progress-ring source).
export function restClockFractionRemaining(s, now) {
  return s.total > 0 ? Math.min(1, Math.max(0, restClockRemaining(s, now) / s.total)) : 0;
}

// ---- Cardio set formatting -------------------------------------------------
// Conditioning sets log distance/time/incline, not weight×reps. These build
// the shared label the logger and history rows render. Pure; mirrored 1:1 in
// CadenceCore/CardioFormat.swift.

// Miles per hour from distance + duration, rounded to one decimal; null when
// either half is missing/zero (no speed without both).
export function cardioSpeedMph(distanceMiles, durationSeconds) {
  if (!(distanceMiles > 0) || !(durationSeconds > 0)) return null;
  return Math.round((distanceMiles / (durationSeconds / 3600)) * 10) / 10;
}

// Format a duration as minutes and seconds, including hours when needed.
export function cardioDurationLabel(seconds) {
  const s = Math.max(0, seconds);
  const two = (n) => String(n).padStart(2, "0");
  if (s >= 3600) return `${Math.floor(s / 3600)}:${two(Math.floor((s % 3600) / 60))}:${two(s % 60)}`;
  return `${Math.floor(s / 60)}:${two(s % 60)}`;
}

// Build one compact line from whichever cardio fields were logged.
// Missing halves simply drop out; nothing logged → "—".
export function cardioSetLabel(distanceMiles, durationSeconds, inclinePercent) {
  const parts = [];
  if (distanceMiles > 0) parts.push(`${trim(distanceMiles, 2)} mi`);
  if (durationSeconds > 0) parts.push(cardioDurationLabel(durationSeconds));
  const mph = cardioSpeedMph(distanceMiles, durationSeconds);
  if (mph !== null) parts.push(`${trim(mph)} mph`);
  if (inclinePercent > 0) parts.push(`${trim(inclinePercent)}%`);
  return parts.length ? parts.join(" · ") : "—";
}
