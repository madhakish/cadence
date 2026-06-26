// ComebackCore, ported to JS. Pure functions, no DOM, no storage.
// This mirrors ComebackCore/Sources/ComebackCore/*.swift exactly; the
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

// ---- Plates & bars ---------------------------------------------------------

export const plateLb = (p) => toLb(p.value, p.unit);
export const plateId = (p) => `${p.value}-${p.unit}`;
export const plateLabel = (p) => `${trim(p.value, 2)} ${p.unit}`;

const mkPlates = (vals, unit) => vals.map((value) => ({ value, unit }));
export const STANDARD_KG = mkPlates([25, 20, 15, 10, 5, 2.5, 1.25], "kg");
export const STANDARD_LB = mkPlates([45, 35, 25, 10, 5, 2.5], "lb");
export const ALL_STANDARD = [...STANDARD_LB, ...STANDARD_KG];

export const BARS = {
  bar45lb: { value: 45, unit: "lb" },
  bar35lb: { value: 35, unit: "lb" },
  bar20kg: { value: 20, unit: "kg" },
};
export const ALL_BARS = [BARS.bar45lb, BARS.bar35lb, BARS.bar20kg];
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

// Branch-and-bound closest per-side load. Ties prefer fewer plates, then
// erring under the target. Mirrors PlateMath.solve.
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
  let bestDev = perSideTarget * 2.0;
  let bestSigned = -perSideTarget * 2.0;
  let bestPlates = 0;
  let nodes = 0;

  const consider = (remaining, used) => {
    const signed = -remaining * 2.0; // achieved − target
    const dev = Math.abs(signed);
    let better;
    if (dev < bestDev - 1e-9) better = true;
    else if (Math.abs(dev - bestDev) <= 1e-9) {
      if (used < bestPlates) better = true;
      else if (used === bestPlates && signed < bestSigned - 1e-9) better = true;
      else better = false;
    } else better = false;
    if (better) {
      bestDev = dev; bestSigned = signed; bestPlates = used;
      bestCounts = counts.slice();
    }
  };

  const search = (index, remaining, used) => {
    nodes += 1;
    if (nodes >= 300000) return;
    consider(remaining, used);
    if (index >= values.length || !(remaining > 1e-9)) return;
    const v = values[index];
    const maxCount = Math.min(maxPerPlateSide, Math.floor(remaining / v) + 1);
    for (let c = maxCount; c >= 0; c -= 1) {
      const next = remaining - c * v;
      if (next < 0 && -next * 2.0 > bestDev + 1e-9) continue; // overshoot worse
      counts[index] = c;
      search(index + 1, next, used + c);
    }
    counts[index] = 0;
  };

  search(0, perSideTarget, 0);

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
  return `Wk${p} ${ph.name} ${ph.sets}×${ph.reps}`;
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

export const AUTOREG_REASONS = ["bar speed", "wobble", "joint signal", "heat", "fatigue"];

// plan: { weightLb, sets, reps, phase? }
export function sessionPlanLabel(plan) {
  const base = `${trim(plan.weightLb)} × ${plan.sets}×${plan.reps}`;
  if (plan.phase) return `${base} — Wk${plan.phase} ${PHASES[plan.phase].name}`;
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
export function prEvaluate({ exercise, sessionSets, historySets, historyVolumes, historySchemes }) {
  if (!sessionSets.length) return [];
  const events = [];
  const priorMax = historySets.length ? Math.max(...historySets.map((s) => s.weightLb)) : 0;
  const top = prTopScheme(sessionSets);
  const schemes = historySchemes instanceof Set ? historySchemes : new Set(historySchemes);

  if (top) {
    if (top.weightLb > priorMax + 1e-9) {
      const scheme = top.sets > 1
        ? `${trim(top.weightLb)}×${top.sets}×${top.reps}`
        : `${trim(top.weightLb)}×${top.reps}`;
      events.push({ kind: "heaviestSet", exercise, label: `${scheme} — heaviest ${exercise.toLowerCase()} of the comeback` });
    }
    const schemeKey = `${top.sets}×${top.reps}`;
    if (!schemes.has(schemeKey)) {
      events.push({ kind: "firstScheme", exercise, label: `First ${schemeKey} — ${trim(top.weightLb)} ${exercise.toLowerCase()}` });
    }
  }

  const vol = prVolume(sessionSets);
  const priorVolMax = historyVolumes.length ? Math.max(...historyVolumes) : 0;
  if (vol > priorVolMax + 1e-9 && historyVolumes.length) {
    events.push({ kind: "volumePR", exercise, label: `Volume PR — ${trim(vol)} lb total ${exercise.toLowerCase()}` });
  }
  return events;
}

// ---- Adaptive program progression --------------------------------------------
// Cross-cycle progression that is performance-gated, tapers toward an estimated
// ceiling, and auto-deloads on repeated stalls. Pure & deterministic — consumes
// a performance SUMMARY (never a session), no clock/random. Mirrors
// ComebackCore/Sources/ComebackCore/ProgramProgression.swift exactly.

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
//         anyDroppedLoad, grindyOrWobbleSets, topSetWeightLb, topSetReps }
export function gradeCycle(perf) {
  if (perf.completedSets < perf.prescribedSets || perf.anyStoppedEarly || perf.anyDroppedLoad) return "fail";
  if (perf.grindyOrWobbleSets > QUALITY_FLAG_TOLERANCE) return "hold";
  return "success";
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
  if (hitAll && state.currentReps >= state.maxReps) {
    next.weightLb = state.weightLb + state.incrementLb;
    next.currentReps = state.minReps;
    next.stallCount = 0;
  } else if (hitAll) {
    next.currentReps = Math.min(state.currentReps + 1, state.maxReps);
    next.stallCount = 0;
  } else {
    next.stallCount = state.stallCount + 1;
  }
  return next;
}
