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
export function programPlanFor(state, programRoundingLb, exerciseType = null, movementGroup = null,
  role = "main", focus = "strength", prescriptionStyle = "automatic", configuration = {}) {
  const style = resolvedPrescriptionStyle(prescriptionStyle, movementGroup, role, focus);
  const lower = ["squat", "hinge"].includes(movementGroup);
  const config = { ...configuration,
    loadOffsetLb: configuration.loadOffsetLb > 0 ? configuration.loadOffsetLb : (lower ? 25 : 10),
    peakOffsetLb: configuration.peakOffsetLb > 0 ? configuration.peakOffsetLb : (lower ? 33 : 15),
  };
  const plan = planForStyle(state, programLoadStep(programRoundingLb, exerciseType), style, config, movementGroup);
  if (exerciseType !== "dumbbell" || plan.weightLb <= state.baseWeightLb) return plan;
  return { ...plan, weightLb: Math.min(plan.weightLb, state.baseWeightLb + 5) };
}

// ---- Methodology styles (mirrors PrescriptionStyle helpers in Swift) -------

// Styles whose base advances after every banked exposure of the slot instead
// of being graded once per 4-week rotation at the Peak.
export const advancesPerExposure = (style) =>
  ["doubleProgression", "linearFives", "texasVolume", "texasLight", "texasIntensity"].includes(style);

// Styles that build their own session shape (sets-across, ramps, singles,
// speed sets) — the generic phase primer and peak-single add-ons never apply.
export const buildsOwnSessionShape = (style) =>
  advancesPerExposure(style) || ["fiveThreeOne", "maxEffort", "dynamicEffort"].includes(style);

// Starting base weight as a fraction of a known e1RM for history-driven
// program creation; 0 keeps the template's hand-set base.
export const defaultStartFraction = (style) => ({
  linearFives: 0.74, texasVolume: 0.77, texasLight: 0.62, texasIntensity: 0.86,
  fiveThreeOne: 0.90, maxEffort: 0.90, dynamicEffort: 0.50,
}[style] || 0);
export function resolvedPrescriptionStyle(requested = "automatic", movementGroup = null,
  role = "main", focus = "strength") {
  if (requested !== "automatic") return requested;
  if (movementGroup === "olympic") return "technique";
  if (focus === "hypertrophy") return "hypertrophy";
  if (role === "complementary" || focus === "maintain") return "secondary";
  return "wave";
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

// ---- Load semantics --------------------------------------------------------
// Equipment describes what is used; load basis describes what the entered
// number means. Sets snapshot both basis and implement count so later library
// edits cannot rewrite historical tonnage or PR meaning.
export const LOAD_BASES = ["totalBar", "perImplement", "externalTotal", "assisted", "bodyweight"];
export const loadBasisLabel = (basis) => ({
  totalBar: "Total bar weight", perImplement: "Per implement", externalTotal: "External total",
  assisted: "Assistance", bodyweight: "Bodyweight",
}[basis] || "External total");
export const loadBasisSuffix = (basis) => basis === "perImplement" ? " each" : (basis === "assisted" ? " assistance" : "");
export const inferredLoadBasis = (exerciseType) => {
  if (exerciseType === "barbell") return "totalBar";
  if (exerciseType === "dumbbell" || exerciseType === "kettlebell") return "perImplement";
  if (exerciseType === "bodyweight") return "bodyweight";
  return "externalTotal";
};
export const inferredImplementCount = (exerciseType) => exerciseType === "dumbbell" ? 2 : 1;
export const resolvedLoadBasis = (exercise) => LOAD_BASES.includes(exercise?.loadBasis)
  ? exercise.loadBasis : inferredLoadBasis(exercise?.type);
export const resolvedImplementCount = (exercise) => resolvedLoadBasis(exercise) === "perImplement"
  ? Math.max(1, Number.isInteger(exercise?.implementCount) && exercise.implementCount > 0
    ? exercise.implementCount : inferredImplementCount(exercise?.type)) : 1;
export const supportsLoadPR = (basis) => ["totalBar", "perImplement", "externalTotal"].includes(basis);
export function loadVolume(set) {
  const basis = LOAD_BASES.includes(set.loadBasis) ? set.loadBasis : "externalTotal";
  if (!supportsLoadPR(basis) || !(set.weightLb >= 0) || !(set.reps > 0)) return null;
  const implementMultiplier = basis === "perImplement" ? Math.max(1, set.implementCount || 1) : 1;
  return set.weightLb * set.reps * implementMultiplier * (set.isPerSide ? 2 : 1);
}

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
export function loadoutTotalLb(bar, perSide, collarLb = 0) {
  return barLb(bar) + Math.max(0, collarLb) + 2 * loadoutPerSideLb(perSide);
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
export const LOADING_POLICIES = ["closest", "under", "over", "exact"];
export const loadingPolicyLabel = (policy) => ({
  closest: "Closest", under: "Never over", over: "Never under", exact: "Exact / competition",
}[policy] || "Closest");

const policyAllows = (deviationLb, policy) => {
  if (policy === "under") return deviationLb <= 1e-9;
  if (policy === "over") return deviationLb >= -1e-9;
  if (policy === "exact") return Math.abs(deviationLb) <= 0.01;
  return true;
};

export function solve(targetLb, bar, plates, maxPerPlateSide = 10, collarLb = 0, policy = "closest") {
  collarLb = Math.max(0, collarLb);
  policy = LOADING_POLICIES.includes(policy) ? policy : "closest";
  const perSideTarget = (targetLb - barLb(bar) - collarLb) / 2.0;

  // dedup by id, sort heaviest-lb first
  const seen = new Map();
  for (const p of plates) seen.set(plateId(p), p);
  const sorted = [...seen.values()].sort((a, b) => plateLb(b) - plateLb(a));

  const empty = () => makeSolution(bar, [], targetLb, collarLb, policy,
    policyAllows(loadoutTotalLb(bar, [], collarLb) - targetLb, policy));
  if (!(perSideTarget > 1e-9) || sorted.length === 0) return empty();

  const values = sorted.map(plateLb);
  const counts = new Array(sorted.length).fill(0);
  let bestCounts = counts.slice();
  let best = null; // { dev, signed, used, distinct, mixed }
  let policyBestCounts = counts.slice();
  let policyBest = null;
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
    if (policyAllows(signed, policy) && isBetter(c, policyBest)) {
      policyBest = c; policyBestCounts = counts.slice();
    }
  };

  const search = (index, remaining, used, distinct, kg, lb) => {
    nodes += 1;
    if (nodes >= 300000) return;
    consider(remaining, used, distinct, kg > 0 && lb > 0);
    if (index >= values.length || !(remaining > 1e-9)) return;
    const v = values[index];
    const isKg = sorted[index].unit === "kg";
    const maxCount = Math.min(maxPerPlateSide, Math.floor(remaining / v) + 1);
    // A never-under search cannot use the unrestricted closest result as its
    // initial overshoot bound: the nearest valid load may be much farther away
    // (50 target, 45 bar, 10s -> 65).
    const directionalBound = policy === "over" ? (policyBest ? policyBest.dev : Infinity) : 0;
    const bound = Math.max(TOLERANCE_LB, best ? best.dev : perSideTarget * 2.0, directionalBound);
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

  const selectedCounts = policyBest ? policyBestCounts : bestCounts;
  const perSide = [];
  for (let i = 0; i < sorted.length; i += 1) {
    if (selectedCounts[i] > 0) perSide.push({ plate: sorted[i], count: selectedCounts[i] });
  }
  return makeSolution(bar, perSide, targetLb, collarLb, policy, !!policyBest);
}

// What a session stores for a solved rack load. Inside the good-enough band
// the clean stack is loading GUIDANCE, not a new prescription — the programmed
// number stays on the card (90, not the 89.1 lb a 10 kg pair happens to
// weigh), and the barbell hint explains the actual plates. Only a genuinely
// unreachable target stores the achieved load, so the log stays honest on
// sparse racks. Mirrored 1:1 in CadenceCore PlateMath.storedPrescription.
export const storedPrescription = (targetLb, achievedLb) =>
  (Math.abs(achievedLb - targetLb) <= TOLERANCE_LB + 1e-9 ? targetLb : achievedLb);

// Resolve a programmed target against the active rack and retain the nearest
// achievable load on each side for the UI. Explicit gym policy wins; closest
// ties can be phase-aware (volume over, peak/other under).
export function prescriptionPlateOptions(targetLb, bar, plates, maxPerPlateSide = 10,
  collarLb = 0, policy = "closest", preferOverOnTie = false) {
  const underCandidate = solve(targetLb, bar, plates, maxPerPlateSide, collarLb, "under");
  const overCandidate = solve(targetLb, bar, plates, maxPerPlateSide, collarLb, "over");
  const below = underCandidate.satisfiesPolicy ? underCandidate : null;
  const above = overCandidate.satisfiesPolicy ? overCandidate : null;
  let selected;
  if (policy !== "closest") {
    selected = solve(targetLb, bar, plates, maxPerPlateSide, collarLb, policy);
  } else if (below && above) {
    const underMiss = Math.abs(below.deviationLb), overMiss = Math.abs(above.deviationLb);
    selected = Math.abs(underMiss - overMiss) <= 1e-9
      ? (preferOverOnTie ? above : below)
      : (underMiss < overMiss ? below : above);
  } else {
    selected = below || above || solve(targetLb, bar, plates, maxPerPlateSide, collarLb, "closest");
  }
  return { targetLb, selected, below, above };
}

function makeSolution(bar, perSide, targetLb, collarLb = 0, policy = "closest", satisfiesPolicy = true) {
  const sortedPerSide = [...perSide].sort((a, b) => plateLb(b.plate) - plateLb(a.plate));
  const totalLb = loadoutTotalLb(bar, sortedPerSide, collarLb);
  const deviationLb = totalLb - targetLb;
  return {
    bar,
    collarLb,
    perSide: sortedPerSide,
    targetLb,
    policy,
    satisfiesPolicy,
    totalLb,
    deviationLb,
    isOffTarget: Math.abs(deviationLb) > TOLERANCE_LB,
  };
}

// Reverse mode: what's on the bar → total.
export const totalOnBar = (bar, perSide, collarLb = 0) => loadoutTotalLb(bar, perSide, collarLb);

// ---- Warmup ramp -----------------------------------------------------------

const RAMP_STEPS = [
  { percent: 0.40, reps: 5 },
  { percent: 0.55, reps: 3 },
  { percent: 0.70, reps: 2 },
  { percent: 0.85, reps: 1 },
];

export function warmupRamp(workingLb, barLb = 45, roundingLb = 5, includeEmptyBar = true) {
  const sets = includeEmptyBar ? [{ weightLb: barLb, reps: 10 }] : [];
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

export function planForStyle(state, roundingLb = DEFAULT_ROUNDING_LB, style = "wave", configuration = {}, movementGroup = null) {
  const p = state.nextPhase;
  const config = {
    loadOffsetLb: 10, peakOffsetLb: 15, deloadMultiplier: 0.775,
    workingSets: 3, minimumReps: 5, maximumReps: 8, currentReps: 5,
    peakSingleEnabled: false, lastPeakSingleLb: 0, peakSingleIncrementLb: 5,
    phasePrimerEnabled: true, ...configuration,
  };
  if (["linearFives", "texasVolume", "texasLight", "texasIntensity"].includes(style)) {
    // Sets-across at the slot's own base; the base moves per exposure
    // (advanceLinearLift), so the 4-week phase never shapes the weight.
    return {
      weightLb: roundTo(state.baseWeightLb, roundingLb),
      sets: Math.max(1, config.workingSets), reps: 5, phase: p, cycleNumber: state.cycleNumber,
    };
  }
  if (style === "fiveThreeOne") {
    // baseWeightLb is the TRAINING MAX. The plan is the graded top ("+") set;
    // the two ramp sets are emitted by sessionPrescription.
    const top = { 1: [0.85, 5], 2: [0.90, 3], 3: [0.95, 1], 4: [0.60, 5] }[p];
    return {
      weightLb: roundTo(state.baseWeightLb * top[0], roundingLb),
      sets: 1, reps: top[1], phase: p, cycleNumber: state.cycleNumber,
    };
  }
  if (style === "maxEffort") {
    // Work up to a top single at the slot's current target; the deload
    // rotation trades the single for moderate triples.
    if (p === 4) return {
      weightLb: roundTo(state.baseWeightLb * 0.70, roundingLb),
      sets: 3, reps: 3, phase: p, cycleNumber: state.cycleNumber,
    };
    return {
      weightLb: roundTo(state.baseWeightLb, roundingLb),
      sets: 1, reps: 1, phase: p, cycleNumber: state.cycleNumber,
    };
  }
  if (style === "dynamicEffort") {
    // Speed work: base ≈ 50% of the slot's max, waved up over the two middle
    // rotations, back to the wave floor on deload. Squat pattern takes speed
    // doubles, hinge takes speed pulls, presses take triples.
    const scheme = movementGroup === "squat" ? [10, 2] : movementGroup === "hinge" ? [6, 1] : [9, 3];
    const multiplier = { 1: 1.0, 2: 1.10, 3: 1.20, 4: 1.0 }[p];
    return {
      weightLb: roundTo(state.baseWeightLb * multiplier, roundingLb),
      sets: scheme[0], reps: scheme[1], phase: p, cycleNumber: state.cycleNumber,
    };
  }
  if (style === "offsetWave") {
    const weight = ({
      1: state.baseWeightLb,
      2: state.baseWeightLb + config.loadOffsetLb,
      3: state.baseWeightLb + config.peakOffsetLb,
      4: state.baseWeightLb * config.deloadMultiplier,
    })[p];
    const phase = PHASES[p];
    return { weightLb: roundTo(weight, roundingLb), sets: phase.sets, reps: phase.reps, phase: p, cycleNumber: state.cycleNumber };
  }
  if (style === "doubleProgression") return {
    weightLb: roundTo(state.baseWeightLb, roundingLb),
    sets: Math.max(1, config.workingSets),
    reps: Math.min(Math.max(config.currentReps, config.minimumReps), config.maximumReps),
    phase: p, cycleNumber: state.cycleNumber,
  };
  const byStyle = {
    wave: {
      1: [5, 5, 1.0], 2: [5, 3, 1.10], 3: [3, 3, 1.175], 4: [3, 5, 0.775],
    },
    // Complementary work is volume after the day's heavy main — never a second
    // miniature of the main wave. Sets stay at 5+ reps and at or below the
    // slot's base (a 5-rep-calibrated weight; 8s sit ~90%).
    secondary: {
      1: [3, 8, 0.90], 2: [3, 8, 0.95], 3: [3, 6, 1.0], 4: [2, 8, 0.75],
    },
    hypertrophy: {
      1: [4, 10, 1.0], 2: [4, 8, 1.025], 3: [3, 8, 1.05], 4: [2, 10, 0.85],
    },
    technique: {
      1: [5, 3, 1.0], 2: [6, 2, 1.05], 3: [6, 1, 1.10], 4: [3, 2, 0.80],
    },
  };
  const [sets, reps, multiplier] = (byStyle[style] || byStyle.wave)[p];
  return {
    weightLb: roundTo(state.baseWeightLb * multiplier, roundingLb),
    sets, reps, phase: p, cycleNumber: state.cycleNumber,
  };
}

export function primerWeight(baseWeightLb, phase, style, roundingLb = DEFAULT_ROUNDING_LB, configuration = {}) {
  const config = { loadOffsetLb: 10, ...configuration };
  if (phase === 1 || phase === 4) return null;
  if (phase === 2) return roundTo(baseWeightLb, roundingLb);
  if (style === "offsetWave") return roundTo(baseWeightLb + config.loadOffsetLb, roundingLb);
  return roundTo(baseWeightLb * PHASES[2].multiplier, roundingLb);
}

export function sessionPrescription(state, programRoundingLb, exerciseType = null, movementGroup = null,
  role = "main", focus = "strength", prescriptionStyle = "automatic", configuration = {}, estimatedMaxLb = 0) {
  const config = {
    peakSingleEnabled: false, lastPeakSingleLb: 0, peakSingleIncrementLb: 5,
    phasePrimerEnabled: true, ...configuration,
  };
  const lower = ["squat", "hinge"].includes(movementGroup);
  if (!(config.loadOffsetLb > 0)) config.loadOffsetLb = lower ? 25 : 10;
  if (!(config.peakOffsetLb > 0)) config.peakOffsetLb = lower ? 33 : 15;
  const style = resolvedPrescriptionStyle(prescriptionStyle, movementGroup, role, focus);
  const work = programPlanFor(state, programRoundingLb, exerciseType, movementGroup, role, focus, style, config);
  const step = programLoadStep(programRoundingLb, exerciseType);
  const blocks = [];
  if (config.phasePrimerEnabled && !buildsOwnSessionShape(style)) {
    const primer = primerWeight(state.baseWeightLb, state.nextPhase, style, step, config);
    if (primer > 0 && primer < work.weightLb) blocks.push({ kind: "primer", weightLb: primer, sets: 1, reps: 1 });
  }
  if (config.peakSingleEnabled && state.nextPhase === 3
    && style !== "technique" && !buildsOwnSessionShape(style)) {
    const seed = config.lastPeakSingleLb > 0
      ? config.lastPeakSingleLb + config.peakSingleIncrementLb : estimatedMaxLb * 0.90;
    const target = roundTo(seed, step);
    if (target > work.weightLb) blocks.push({ kind: "topSingle", weightLb: target, sets: 1, reps: 1 });
  }
  if (style === "fiveThreeOne") {
    // The two ramp sets below the "+" set. Real prescribed work, but only the
    // top set gates progression, so they carry the non-graded ramp kind;
    // block order puts them before the top set.
    const ramp = {
      1: [[0.65, 5], [0.75, 5]], 2: [[0.70, 3], [0.80, 3]],
      3: [[0.75, 5], [0.85, 3]], 4: [[0.40, 5], [0.50, 5]],
    }[state.nextPhase];
    for (const [pct, reps] of ramp) {
      blocks.push({ kind: "ramp", weightLb: roundTo(state.baseWeightLb * pct, step), sets: 1, reps });
    }
  }
  blocks.push({ kind: "work", weightLb: work.weightLb, sets: work.sets, reps: work.reps });
  if (style === "maxEffort" && state.nextPhase !== 4) {
    blocks.push({ kind: "backoff", weightLb: roundTo(state.baseWeightLb * 0.80, step), sets: 3, reps: 3 });
  }
  return { mainWork: work, blocks };
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
export function droppedLoad(currentLb, roundingLb = DEFAULT_ROUNDING_LB, barLb = 45, dropIncrementLb = null) {
  const dropped = dropIncrementLb > 0 ? currentLb - dropIncrementLb : roundTo(currentLb * 0.93, roundingLb);
  const result = dropped >= currentLb ? currentLb - roundingLb : dropped;
  return Math.max(result, barLb);
}

// Which sets a mid-session "dropping load" tap rewrites, and to what. Only
// not-yet-performed sets (unflagged working sets) are touched — a flagged set
// is history — and each is dropped from ITS OWN weight, so a lighter back-off
// set is never raised toward the top set's drop. Mirrors
// ProgramEngine.dropLoadPlan.
export function dropLoadPlan(sets, roundingLb = DEFAULT_ROUNDING_LB, barLb = 45, dropIncrementLb = null) {
  const out = [];
  sets.forEach((s, index) => {
    if (s.isWarmup || s.isFlagged) return;
    out.push({ index, weightLb: droppedLoad(s.weightLb, roundingLb, barLb, dropIncrementLb) });
  });
  return out;
}

export const AUTOREG_REASONS = ["bar speed", "wobble", "joint signal", "heat", "fatigue", "not there"];

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
export const prVolume = (sets) => sets.reduce((sum, set) => sum + (loadVolume(set) ?? 0), 0);

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
  const basis = LOAD_BASES.includes(sessionSets[0].loadBasis) ? sessionSets[0].loadBasis : "totalBar";
  const comparableSession = sessionSets.filter((set) => (set.loadBasis || basis) === basis);
  const comparableHistory = historySets.filter((set) => (set.loadBasis || basis) === basis);
  const priorMax = comparableHistory.length ? Math.max(...comparableHistory.map((s) => s.weightLb)) : 0;
  const top = prTopScheme(comparableSession);
  const schemes = historySchemes instanceof Set ? historySchemes : new Set(historySchemes);

  if (top) {
    if (supportsLoadPR(basis) && top.weightLb > priorMax + 1e-9) {
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

  const vol = prVolume(comparableSession);
  const priorVolMax = historyVolumes.length ? Math.max(...historyVolumes) : 0;
  if (supportsLoadPR(basis) && vol > priorVolMax + 1e-9 && historyVolumes.length) {
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

// One banked standalone exposure advances only when every occurrence met its
// immutable prescription. Duplicate sections are one exposure, not two bumps.
export function earnsStandaloneTrackAdvance(performances) {
  return performances.length > 0 && performances.every((perf) => gradeCycle(perf) === "success");
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
  const estimatedMaxLb = smoothedMax(state, perf);
  const next = { ...state, estimatedMaxLb };
  let note = null;

  if (grade === "success") {
    next.stallCount = 0;
    const inc = taperedIncrement(state.baseWeightLb, estimatedMaxLb, focus, roundingLb);
    next.baseWeightLb = state.baseWeightLb + inc;
    next.lastIncrementLb = inc;
    note = inc > 0 ? `Clean peak — add ${trim(inc)} lb next cycle.`
      : (focusParams(focus).inc <= 0 ? "Maintaining — holding weight." : "At training-max ceiling — holding weight.");
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

// Per-exposure linear rule for methodology styles that add weight every time
// the slot completes as prescribed. Mirrors ProgramProgression.linearRule.
export function linearRule(style, movementGroup = null) {
  const lower = ["squat", "hinge"].includes(movementGroup);
  if (style === "linearFives") return { incrementLb: lower ? 10 : 5, stallLimit: 3, deloadFraction: 0.90 };
  // Texas day slots: flat +5 per completion — twin A/B slots are synchronized
  // by the banking layer, which lands on the published +5 lb/week per lift.
  return { incrementLb: 5, stallLimit: 2, deloadFraction: 0.95 };
}

// A performed top set that actually happened. A skipped or fully-missed top
// set reports weight/reps 0; smoothing that into the e1RM would crush the
// estimate by 30% per occurrence, so only real samples smooth. Mirrors
// ProgramProgression.smoothedMax.
const smoothedMax = (state, perf) => (perf.topSetWeightLb > 0 && perf.topSetReps >= 1
  ? smoothE1RM(state.estimatedMaxLb, epleyE1RM(perf.topSetWeightLb, perf.topSetReps))
  : state.estimatedMaxLb);

// Advance a per-exposure linear slot after a banked session. Mirrors
// ProgramProgression.advanceLinearLift.
export function advanceLinearLift(state, perf, rule, roundingLb = DEFAULT_ROUNDING_LB) {
  const grade = gradeCycle(perf);
  const next = { ...state, estimatedMaxLb: smoothedMax(state, perf) };
  let note = null;

  if (grade === "success") {
    next.stallCount = 0;
    next.baseWeightLb = state.baseWeightLb + rule.incrementLb;
    next.lastIncrementLb = rule.incrementLb;
    note = `Completed as prescribed — add ${trim(rule.incrementLb)} lb next time.`;
  } else if (grade === "hold") {
    // Grindy but every rep was made. The published novice rule is to grind
    // and keep adding; the conservative middle is to hold the weight WITHOUT
    // accruing a miss — and a completed session breaks the consecutive-miss
    // chain, so the deload note stays truthful.
    next.stallCount = 0;
    next.lastIncrementLb = 0;
    note = "Grindy session — holding weight; misses were not counted.";
  } else {
    next.stallCount = state.stallCount + 1;
    next.lastIncrementLb = 0;
    if (next.stallCount >= rule.stallLimit) {
      const old = state.baseWeightLb;
      next.baseWeightLb = roundTo(old * rule.deloadFraction, roundingLb);
      next.stallCount = 0;
      note = `Missed ${rule.stallLimit} in a row — deloaded ${trim(old)}→${trim(next.baseWeightLb)} lb to rebuild.`;
    } else {
      note = "Prescription not fully met — holding weight, try it again.";
    }
  }
  return { state: next, grade, note };
}

// Style-aware cycle progression at the Peak grade / rollover. Methodology
// styles use their published fixed increments; everything else keeps the
// tapered headroom rule. Mirrors ProgramProgression.advanceProgramLift.
export function advanceProgramLift(state, perf, focus, style, movementGroup = null, roundingLb = DEFAULT_ROUNDING_LB) {
  const lower = ["squat", "hinge"].includes(movementGroup);
  const increment = lower ? 10 : 5;
  if (style === "fiveThreeOne") {
    const grade = gradeCycle(perf);
    const next = { ...state, estimatedMaxLb: smoothedMax(state, perf) };
    let note = null;
    if (grade === "success") {
      next.stallCount = 0;
      next.baseWeightLb = state.baseWeightLb + increment;
      next.lastIncrementLb = increment;
      note = `Hit the top set — training max +${trim(increment)} lb next cycle.`;
    } else if (grade === "fail" && perf.completedSets < perf.prescribedSets) {
      // Wendler's reset applies only to genuinely missing the "+" set's
      // minimum reps. A fail from an autoreg drop or a light manual edit
      // made the reps at reduced load — that holds.
      const old = state.baseWeightLb;
      next.baseWeightLb = Math.max(roundingLb, roundTo(old - 3 * increment, roundingLb));
      next.stallCount = 0;
      next.lastIncrementLb = 0;
      note = `Missed the minimum reps — training max reset ${trim(old)}→${trim(next.baseWeightLb)} lb (three cycles back).`;
    } else {
      next.stallCount = state.stallCount + 1;
      next.lastIncrementLb = 0;
      if (grade === "fail" && next.stallCount >= STALL_LIMIT) {
        // Repeated compromised "+" sets mean the TM is set too high even
        // though the reps are technically appearing — apply the same
        // three-cycles-back correction and consume the counter.
        const old = state.baseWeightLb;
        next.baseWeightLb = Math.max(roundingLb, roundTo(old - 3 * increment, roundingLb));
        next.stallCount = 0;
        note = `Two compromised cycles — training max reset ${trim(old)}→${trim(next.baseWeightLb)} lb (three cycles back).`;
      } else {
        note = grade === "fail"
          ? "Top set compromised — holding the training max this cycle."
          : "Grindy top set — holding the training max this cycle.";
      }
    }
    return { state: next, grade, note };
  }
  if (style === "maxEffort") {
    const grade = gradeCycle(perf);
    const next = { ...state, estimatedMaxLb: smoothedMax(state, perf) };
    let note = null;
    if (grade === "success") {
      next.stallCount = 0;
      next.baseWeightLb = state.baseWeightLb + increment;
      next.lastIncrementLb = increment;
      note = `Made the top single — next target +${trim(increment)} lb. Rotate the variation to keep it moving.`;
    } else {
      // Rotation, not accumulation, is this methodology's stall answer — no
      // counter accrues (a stale count would detonate a spurious deload if
      // the slot is later switched to a wave style).
      next.lastIncrementLb = 0;
      note = "Missed the single — holding the target. Swap the variation rather than grinding the same lift.";
    }
    return { state: next, grade, note };
  }
  if (style === "dynamicEffort") {
    // Speed doubles are not an e1RM sample; leave the estimate alone.
    return {
      state: { ...state, lastIncrementLb: 0 }, grade: gradeCycle(perf),
      note: "Speed work holds — raise this slot when the max-effort lift moves.",
    };
  }
  return advanceCycleLift(state, perf, focus, roundingLb);
}

// Accessory double progression. state: { sets, minReps, maxReps, currentReps,
// weightLb, incrementLb, stallCount }; perf: { completedSets, minRepsAchieved, anyStoppedEarly }
export function advanceAccessory(state, perf) {
  const next = { ...state };
  const hitAll = perf.completedSets >= state.sets && perf.minRepsAchieved >= state.currentReps
    && !perf.anyStoppedEarly && perf.performedAtPlannedLoad !== false
    && (perf.grindyOrWobbleSets || 0) <= 1 && (perf.bodyFlagSets || 0) === 0;
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

// ---- Rotation-first coaching ----------------------------------------------
// Pure deterministic mirror of CadenceCore/CoachingEngine.swift. Persistence
// adapters pass immutable planned/performed snapshots; this layer never edits
// a program or treats a calendar week as a rotation boundary.

export const MOVEMENT_PATTERNS = [
  "horizontalPress", "verticalPress", "horizontalPull", "verticalPull", "squat",
  "hipHinge", "kneeFlexion", "hipExtension", "unilateralKnee", "olympicPower",
  "shoulderStability", "arms", "core", "adductor", "calves", "carry",
  "easyAerobic", "intervals", "mixedConditioning", "unknown",
];

export const movementPatternName = (pattern) => ({
  horizontalPress: "Horizontal press", verticalPress: "Vertical press",
  horizontalPull: "Horizontal pull", verticalPull: "Vertical pull", squat: "Squat",
  hipHinge: "Hip hinge", kneeFlexion: "Hamstring isolation", hipExtension: "Hip extension",
  unilateralKnee: "Unilateral lower", olympicPower: "Olympic power",
  shoulderStability: "Rear delt / cuff", arms: "Arms", core: "Core",
  adductor: "Adductor / groin", calves: "Calves", carry: "Carry",
  easyAerobic: "Easy aerobic", intervals: "Intervals", mixedConditioning: "Mixed conditioning",
  unknown: "Unclassified",
}[pattern] || "Unclassified");

export const isConditioningPattern = (pattern) =>
  ["easyAerobic", "intervals", "mixedConditioning"].includes(pattern);

const PATTERN_NAMES = {
  verticalPress: new Set(["Overhead Press", "Push Press", "Push Jerk", "Split Jerk", "Overhead DB Press", "Seated Upright DB Press", "Arnold Press", "Landmine Press", "KB Press"]),
  verticalPull: new Set(["Lat Pulldown", "Straight-arm Pulldown", "Pull-ups", "Chin-ups", "Assisted Pull-up"]),
  horizontalPull: new Set(["Single-arm DB Row", "Chest-supported Row", "Ring Row", "Barbell Row", "Pendlay Row", "T-Bar Row", "Seated Cable Row", "One-arm Cable Row", "Bent-over DB Row", "Incline Bench DB Row", "KB Row", "Banded Row"]),
  kneeFlexion: new Set(["Seated Leg Curl", "Lying Leg Curl", "Nordic Hamstring Curl"]),
  hipExtension: new Set(["Back Extension", "Glute Bridge", "Barbell Hip Thrust", "Cable Pull-through"]),
  unilateralKnee: new Set(["Walking Lunges", "Bulgarian Split Squat", "Reverse Lunge", "Forward Lunge", "Step-up"]),
  shoulderStability: new Set(["Band Pull-aparts", "Face Pulls", "Y-T-W Raises", "Band External Rotation", "Rear Delt Fly", "Reverse Pec Deck"]),
  easyAerobic: new Set(["Walk", "Bike", "Ruck", "Elliptical", "Stair Climber", "Swimming", "Row Erg", "Ski Erg"]),
  intervals: new Set(["Run-Walk Intervals", "Jump Rope", "Sled Push", "Sled Pull", "Battle Ropes"]),
};

export function movementPattern(exerciseName, movementGroup, explicitPattern = null) {
  if (explicitPattern && MOVEMENT_PATTERNS.includes(explicitPattern) && explicitPattern !== "unknown") return explicitPattern;
  for (const [pattern, names] of Object.entries(PATTERN_NAMES)) if (names.has(exerciseName)) return pattern;
  if (/copenhagen/i.test(exerciseName)) return "adductor";
  return ({
    press: "horizontalPress", pull: "horizontalPull", squat: "squat", hinge: "hipHinge",
    olympic: "olympicPower", shoulder: "shoulderStability", arms: "arms", core: "core",
    calves: "calves", carry: "carry", conditioning: "mixedConditioning",
  })[movementGroup] || "unknown";
}

export const COACHING_RULE_VERSION = 1;
export const GREEN_COMPLETION_FLOOR = 0.90;
export const RED_COMPLETION_FLOOR = 0.80;
export const GREEN_AT_PLAN_FLOOR = 0.90;
export const YELLOW_PERFORMANCE_DROP = -0.02;
export const RED_PERFORMANCE_DROP = -0.05;

const epoch = (date) => typeof date === "number" ? date : Date.parse(date);
const atPlan = (set) => {
  const repsMet = (set.actualReps ?? 0) >= (set.plannedReps ?? set.actualReps ?? 0);
  return repsMet && (!(set.plannedWeightLb > 0) || (set.actualWeightLb ?? 0) >= set.plannedWeightLb - 0.01);
};
const performanceBySlot = (sessions) => {
  const result = {};
  for (const exercise of sessions.flatMap((session) => session.exercises || [])) {
    if (!exercise.slotID || isConditioningPattern(exercise.pattern)) continue;
    const best = Math.max(0, ...(exercise.sets || [])
      .filter((set) => !set.isWarmup && (set.prescriptionBlock || "work") === "work"
        && set.completed !== false && set.actualReps > 0)
      .map((set) => epleyE1RM(set.actualWeightLb, set.actualReps)));
    if (best > 0) result[exercise.slotID] = Math.max(result[exercise.slotID] || 0, best);
  }
  return result;
};

function programmedCoachingSession(session, slots) {
  return {
    ...session,
    exercises: (session.exercises || []).flatMap((exercise) => {
      let slot = exercise.slotID
        ? slots.find((candidate) => candidate.id === exercise.slotID && candidate.dayIndex === session.dayIndex)
        : null;
      if (!slot && exercise.programRole) {
        const legacy = slots.filter((candidate) => candidate.dayIndex === session.dayIndex
          && candidate.exerciseName === exercise.exerciseName && candidate.role === exercise.programRole);
        if (legacy.length === 1) [slot] = legacy;
      }
      if (!slot) return [];

      let remainingWork = Math.max(0, exercise.plannedSets || 0);
      const sets = (exercise.sets || []).filter((set) => {
        const block = set.prescriptionBlock || (set.isWarmup ? "warmup" : "work");
        if (!["work", "conditioning"].includes(block)) return true;
        if (remainingWork <= 0) return false;
        remainingWork -= 1;
        return true;
      });
      return [{ ...exercise, slotID: slot.id, programRole: slot.role, pattern: slot.pattern, sets }];
    }),
  };
}

function assessCoachingRotation(key, sessions, expectedDayIndexes, priorPerformance, priorReadiness) {
  const completedDayIndexes = [...new Set(sessions.map((session) => session.dayIndex))];
  const complete = expectedDayIndexes.every((day) => completedDayIndexes.includes(day));
  const exercises = sessions.flatMap((session) => session.exercises || []);
  const allSets = exercises.flatMap((exercise) => exercise.sets || []);
  // Conditioning is reported in minutes, not lifting sets, and therefore
  // cannot raise or lower lifting prescription completion/readiness.
  const liftingExercises = exercises.filter((exercise) => !isConditioningPattern(exercise.pattern));
  const working = liftingExercises.flatMap((exercise) => exercise.sets || []).filter((set) =>
    !set.isWarmup && (set.prescriptionBlock || "work") === "work");
  const completedWorking = working.filter((set) => set.completed !== false);
  const plannedWorkingSets = liftingExercises.reduce((sum, exercise) =>
    sum + Math.max(0, exercise.plannedSets || 0), 0);
  const atPlanWorkingSets = completedWorking.filter(atPlan).length;
  const patternSets = {};
  for (const exercise of exercises) patternSets[exercise.pattern] = (patternSets[exercise.pattern] || 0)
    + (exercise.sets || []).filter((set) => !set.isWarmup
      && (set.prescriptionBlock || "work") === "work" && set.completed !== false).length;
  const conditioningSeconds = exercises.filter((exercise) => isConditioningPattern(exercise.pattern))
    .flatMap((exercise) => exercise.sets || []).filter((set) => set.completed !== false)
    .reduce((sum, set) => sum + (set.durationSeconds || 0), 0);
  const bodyFlags = allSets.filter((set) => !!set.hasBodyFlag).length;
  const stoppedWithBody = allSets.some((set) => set.stoppedEarly && set.hasBodyFlag);
  const hardStopCheckIn = sessions.some((session) => !!session.hasHardStopCheckIn);
  const warmupQualityFlags = allSets.filter((set) => set.isWarmup && ["grindy", "wobble"].includes(set.quality)).length;
  const workingQualityFlags = completedWorking.filter((set) => ["grindy", "wobble"].includes(set.quality)).length;
  const currentPerformance = performanceBySlot(sessions);
  const deltas = Object.entries(currentPerformance).flatMap(([slotID, value]) => priorPerformance[slotID] > 0
    ? [(value - priorPerformance[slotID]) / priorPerformance[slotID]] : []);
  const meaningfulDrops = deltas.filter((delta) => delta <= RED_PERFORMANCE_DROP).length;
  const performanceDelta = deltas.length ? deltas.reduce((sum, value) => sum + value, 0) / deltas.length : null;
  const completionRate = plannedWorkingSets > 0 ? completedWorking.length / plannedWorkingSets : 0;
  const atPlanRate = plannedWorkingSets > 0 ? atPlanWorkingSets / plannedWorkingSets : 0;
  const reasons = [];
  let readiness;
  if (hardStopCheckIn || stoppedWithBody || completionRate < RED_COMPLETION_FLOOR || meaningfulDrops >= 2
      || (priorReadiness === "red" && (completionRate < GREEN_COMPLETION_FLOOR || bodyFlags > 0))) {
    readiness = "red";
    if (hardStopCheckIn) reasons.push("A post-session body check-in reported a hard-stop signal.");
    if (stoppedWithBody) reasons.push("A body signal stopped work early.");
    if (completionRate < RED_COMPLETION_FLOOR) reasons.push(`Only ${Math.round(completionRate * 100)}% of prescribed working sets were completed.`);
    if (meaningfulDrops >= 2) reasons.push(`Performance fell at least 5% on ${meaningfulDrops} repeated lifts.`);
  } else if (completionRate < GREEN_COMPLETION_FLOOR || atPlanRate < GREEN_AT_PLAN_FLOOR
      || bodyFlags > 0 || warmupQualityFlags > 0
      || workingQualityFlags > Math.max(1, Math.floor(completedWorking.length / 4))
      || (performanceDelta ?? 0) < YELLOW_PERFORMANCE_DROP) {
    readiness = "yellow";
    if (completionRate < GREEN_COMPLETION_FLOOR) reasons.push(`Prescription completion was ${Math.round(completionRate * 100)}%.`);
    if (atPlanRate < GREEN_AT_PLAN_FLOOR) reasons.push("Some completed work was below its planned load or reps.");
    if (bodyFlags > 0) reasons.push(`${bodyFlags} body signal${bodyFlags === 1 ? "" : "s"} logged.`);
    if (warmupQualityFlags > 0) reasons.push("Warm-up quality was flagged.");
    if (workingQualityFlags > Math.max(1, Math.floor(completedWorking.length / 4))) reasons.push("More than a quarter of working sets were grindy or wobbly.");
    if (performanceDelta !== null && performanceDelta < YELLOW_PERFORMANCE_DROP) reasons.push(`Repeated-lift output fell ${Math.round(Math.abs(performanceDelta * 100))}% on average.`);
  } else if (!Object.keys(priorPerformance).length) {
    readiness = "unknown";
    reasons.push("First complete reliable rotation establishes the comparison baseline.");
  } else {
    readiness = "green";
    reasons.push("At least 90% of prescribed work was completed at plan without a body stop.");
    if (performanceDelta !== null) reasons.push(`Repeated-lift output changed ${performanceDelta >= 0 ? "+" : ""}${Math.round(performanceDelta * 100)}%.`);
  }
  if (!complete) {
    const progress = `Rotation is still in progress (${completedDayIndexes.length}/${expectedDayIndexes.length} days banked).`;
    if (readiness === "green") reasons[0] = `${progress} Completed programmed slots are tracking at plan.`;
    else if (readiness === "unknown") reasons.unshift(progress);
    else reasons.push(progress);
  }
  return {
    key, startedAt: Math.min(...sessions.map((session) => epoch(session.date))),
    completedAt: complete ? Math.max(...sessions.map((session) => epoch(session.date))) : null,
    completedDayIndexes, expectedDayIndexes, isComplete: complete, plannedWorkingSets,
    completedWorkingSets: completedWorking.length, atPlanWorkingSets,
    conditioningMinutes: conditioningSeconds / 60, patternSets, readiness, reasons,
    performanceDelta, completionRate,
  };
}

const preferredCoachingDay = (pattern, slots) => {
  if (["kneeFlexion", "hipExtension"].includes(pattern)) {
    const squat = slots.find((slot) => slot.isMain && slot.pattern === "squat");
    if (squat) return squat.dayIndex;
  }
  if (["verticalPull", "shoulderStability"].includes(pattern)) {
    const upper = slots.find((slot) => slot.isMain && ["horizontalPress", "verticalPress"].includes(slot.pattern));
    if (upper) return upper.dayIndex;
  }
  return slots.length ? Math.min(...slots.map((slot) => slot.dayIndex)) : 0;
};

const shorterSpacingTrial = (sessions) => {
  const ordered = [...sessions].sort((a, b) => epoch(a.date) - epoch(b.date));
  if (ordered.length < 4) return null;
  const intervals = ordered.slice(1).map((session, index) =>
    Math.floor((epoch(session.date) - epoch(ordered[index].date)) / 86_400_000)).filter((days) => days > 0).sort((a, b) => a - b);
  if (intervals.length < 3) return null;
  const median = intervals[Math.floor(intervals.length / 2)];
  return median >= 4 ? Math.max(2, median - 1) : null;
};

function coachingRecommendations(program, latest, greenRotationStreak, sessions) {
  if (!latest) return [];
  const evidenceKey = `c${latest.key.cycleNumber}-r${latest.key.rotation}`;
  if (latest.readiness === "red") return [{
    id: `readiness.red.reduce-accessories.v${COACHING_RULE_VERSION}:${evidenceKey}`,
    ruleID: `readiness.red.reduce-accessories.v${COACHING_RULE_VERSION}`, priority: 100,
    title: "Run one lower-volume rotation",
    explanation: "Repeated output markers are red. Hold main-lift loading and cut accessory sets about 25% for one rotation.",
    change: { type: "reduceAccessoryVolume", percent: 25 },
  }];
  if (latest.readiness === "yellow") return [{
    id: `readiness.yellow.hold.v${COACHING_RULE_VERSION}:${evidenceKey}`,
    ruleID: `readiness.yellow.hold.v${COACHING_RULE_VERSION}`, priority: 80,
    title: "Hold the current prescription", explanation: latest.reasons[0] || "Another exposure is needed before adding work.",
    change: { type: "hold" },
  }];
  if (greenRotationStreak < 2) return [];
  const budgets = [["verticalPull", 3], ["kneeFlexion", 3], ["shoulderStability", 2], ["adductor", 2], ["core", 4]];
  const planned = {};
  for (const slot of program.slots || []) planned[slot.pattern] = (planned[slot.pattern] || 0) + slot.plannedSets;
  const capacity = Math.max(0, program.maximumAddedSetsPerRotation ?? 6);
  let changes = 0;
  const result = [];
  const capacityAdjustments = [];
  const capacityEvidence = [];
  for (const [pattern, target] of budgets) {
    const current = planned[pattern] || 0;
    if (current >= target || changes >= capacity) continue;
    const amount = Math.min(target - current, capacity - changes);
    const slot = (program.slots || []).find((candidate) => candidate.pattern === pattern
      && candidate.capacityManaged !== false && !candidate.isMain
      && candidate.plannedSets < (candidate.maximumSets || 6));
    if (slot) {
      const add = Math.min(amount, (slot.maximumSets || 6) - slot.plannedSets);
      if (add <= 0) continue;
      capacityAdjustments.push({ type: "addSet", slotID: slot.id, exerciseName: slot.exerciseName, count: add });
      capacityEvidence.push(`${movementPatternName(pattern)} ${current}/${target} → +${add}`);
      changes += add;
    } else {
      const dayIndex = preferredCoachingDay(pattern, program.slots || []);
      capacityAdjustments.push({ type: "addPattern", pattern, dayIndex, sets: amount });
      capacityEvidence.push(`${movementPatternName(pattern)} ${current}/${target} → +${amount}`);
      changes += amount;
    }
  }
  if (capacityAdjustments.length) result.push({
    id: `capacity.rotation-plan.v${COACHING_RULE_VERSION}:${evidenceKey}`,
    ruleID: `capacity.rotation-plan.v${COACHING_RULE_VERSION}`, priority: 40,
    title: `Add ${changes} targeted set${changes === 1 ? "" : "s"}`,
    explanation: `Two rotations were green. ${capacityEvidence.join("; ")}.`,
    change: { type: "capacityPlan", additions: capacityAdjustments },
  });
  const shorter = shorterSpacingTrial(sessions);
  if (shorter !== null) result.push({
    id: `cadence.shorter-trial.v${COACHING_RULE_VERSION}:${evidenceKey}`,
    ruleID: `cadence.shorter-trial.v${COACHING_RULE_VERSION}`, priority: 20,
    title: "A shorter recovery trial is supported",
    explanation: `Recent exposures stayed green at the observed spacing. Try the next session after ${shorter} days once, then reassess output.`,
    change: { type: "tryShorterSpacing", days: shorter },
  });
  return result.sort((a, b) => b.priority - a.priority || b.id.localeCompare(a.id));
}

export function evaluateCoaching(program, sessions, reliableHistoryStart = null) {
  const reliable = reliableHistoryStart == null ? -Infinity : epoch(reliableHistoryStart);
  const relevant = sessions.filter((session) => session.completed !== false
    && session.programID === program.id && epoch(session.date) >= reliable)
    .map((session) => programmedCoachingSession(session, program.slots || []));
  const groups = new Map();
  for (const session of relevant) {
    const id = `${session.programID}:${session.cycleNumber}:${session.rotation}`;
    if (!groups.has(id)) groups.set(id, { key: { programID: session.programID, cycleNumber: session.cycleNumber, rotation: session.rotation }, sessions: [] });
    groups.get(id).sessions.push(session);
  }
  const ordered = [...groups.values()].sort((a, b) =>
    Math.min(...a.sessions.map((session) => epoch(session.date))) - Math.min(...b.sessions.map((session) => epoch(session.date))));
  const rotations = [];
  let priorPerformance = {}, priorReadiness = "unknown";
  for (const group of ordered) {
    const assessment = assessCoachingRotation(group.key, group.sessions, [...program.expectedDayIndexes], priorPerformance, priorReadiness);
    rotations.push(assessment);
    if (assessment.isComplete) {
      priorPerformance = performanceBySlot(group.sessions);
      priorReadiness = assessment.readiness;
    }
  }
  const completed = rotations.filter((rotation) => rotation.isComplete);
  // In-progress rotations can report provisional readiness after a complete
  // baseline; recommendations and green streaks still require completion.
  const currentReadiness = rotations.at(-1)?.readiness || "unknown";
  let greenRotationStreak = 0;
  for (const rotation of [...completed].reverse()) {
    if (rotation.readiness !== "green") break;
    greenRotationStreak += 1;
  }
  return {
    rotations, currentReadiness, greenRotationStreak,
    recommendations: coachingRecommendations(program, completed.at(-1), greenRotationStreak, relevant),
  };
}
