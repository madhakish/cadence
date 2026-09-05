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
  role = "main", focus = "strength", prescriptionStyle = "automatic", configuration = {}, addedVolumeSets = 0) {
  const style = resolvedPrescriptionStyle(prescriptionStyle, movementGroup, role, focus);
  const lower = ["squat", "hinge"].includes(movementGroup);
  const config = { ...configuration,
    loadOffsetLb: configuration.loadOffsetLb > 0 ? configuration.loadOffsetLb : (lower ? 25 : 10),
    peakOffsetLb: configuration.peakOffsetLb > 0 ? configuration.peakOffsetLb : (lower ? 33 : 15),
  };
  const plan = planForStyle(state, programLoadStep(programRoundingLb, exerciseType), style, config, movementGroup,
    addedVolumeSets);
  if (exerciseType !== "dumbbell" || plan.weightLb <= state.baseWeightLb) return plan;
  return { ...plan, weightLb: Math.min(plan.weightLb, state.baseWeightLb + 5) };
}

// ---- Methodology styles (mirrors PrescriptionStyle helpers in Swift) -------

// Styles whose base advances after every banked exposure of the slot instead
// of being graded once per 4-week rotation at the Peak.
// Styles no longer offered when configuring a slot.
//
// offsetWave adds fixed pound offsets on the load and peak rotations instead of
// the wave's multipliers. No shipped template uses it, and its two defaults are
// calibrated to bases 61 lb apart — +25 implies a 250 lb lift (25/0.10) while
// +33 implies a 189 lb one (33/0.175) — so the intra-cycle range it produces
// depends on how heavy you are in a way nobody chose.
//
// Retired rather than deleted. The raw value is persisted in programs, backups
// and program files, so removing it would reject data that restores today. A
// slot already using it keeps working and keeps its offsets; it just cannot be
// newly selected. Mirrored in CadenceCore PrescriptionStyle.
export const RETIRED_PRESCRIPTIONS = ["offsetWave"];

// The styles a picker should offer, keeping whatever the slot already has so a
// retired choice never silently rewrites itself to something else.
export const selectablePrescriptions = (all, current) =>
  all.filter(([value]) => !RETIRED_PRESCRIPTIONS.includes(value) || value === current);

export const advancesPerExposure = (style) =>
  ["doubleProgression", "linearFives", "texasVolume", "texasLight", "texasIntensity", "maxEffort"].includes(style);

// Styles that build their own session shape (sets-across, ramps, singles,
// speed sets) — the generic phase primer and peak-single add-ons never apply.
export const buildsOwnSessionShape = (style) =>
  advancesPerExposure(style) || ["fiveThreeOne", "dynamicEffort"].includes(style);

// Whether the Volume / Load / Peak / Recovery vocabulary actually describes
// what this style prescribes.
//
// The rotation counter advances for every slot — the program is one calendar —
// but the NAMES on it are a claim about the prescription, and for most styles
// that claim is false. linearFives and the Texas days move per exposure and
// never grade at a peak; doubleProgression is a rep window at a held load;
// fiveThreeOne and dynamicEffort grade at the cycle boundary but with shapes
// of their own (5+/3+/1+/recovery is not "Volume/Load/Peak").
//
// Derived from buildsOwnSessionShape rather than listed again: those are
// exactly the styles whose plan comes out of their own branch instead of the
// shared phase-shaped table, so one predicate cannot drift from the other.
// Mirrored 1:1 in CadenceCore PrescriptionStyle.usesCyclePhases.
export const usesCyclePhases = (style) => !buildsOwnSessionShape(style);

// Badge-length name for a slot — what the slot actually does, short enough to
// sit beside the lift name. "automatic" never reaches a badge: slotBadge
// resolves it first. Mirrored 1:1 in CadenceCore PrescriptionStyle.shortName.
export const PRESCRIPTION_SHORT_NAMES = {
  automatic: "Automatic", wave: "Wave", offsetWave: "Wave — offsets",
  secondary: "Secondary volume", hypertrophy: "Hypertrophy", technique: "Technique",
  doubleProgression: "Double progression", linearFives: "Linear",
  texasVolume: "Texas volume", texasLight: "Texas light", texasIntensity: "Texas intensity",
  fiveThreeOne: "5/3/1", maxEffort: "Max effort", dynamicEffort: "Speed work",
};
export const prescriptionShortName = (style) => PRESCRIPTION_SHORT_NAMES[style] || style;

// Starting base weight as a fraction of a known e1RM for history-driven
// program creation; 0 keeps the template's hand-set base.
export const defaultStartFraction = (style) => ({
  linearFives: 0.74, texasVolume: 0.77, texasLight: 0.62, texasIntensity: 0.86,
  fiveThreeOne: 0.90, maxEffort: 0.90, dynamicEffort: 0.50,
}[style] || 0);
// Conservative history-derived starting point used only while constructing a
// new program. Explicit methodology ratios still win.
export const templateStartFraction = (style) => defaultStartFraction(style) || ({
  automatic: 0.65, wave: 0.65, offsetWave: 0.65, secondary: 0.55,
  hypertrophy: 0.50, doubleProgression: 0.50, technique: 0.70,
}[style] || 0);
export function resolvedPrescriptionStyle(requested = "automatic", movementGroup = null,
  role = "main", focus = "strength") {
  if (requested !== "automatic") return requested;
  if (movementGroup === "olympic") return "technique";
  if (focus === "hypertrophy") return "hypertrophy";
  if (role === "complementary" || focus === "maintain") return "secondary";
  return "wave";
}

// The effort contract for Cadence's secondary-volume prescription. A fixed
// weight cannot distinguish an easy exposure from useful work, and there is
// no honest universal conversion between different lifts. Explicit
// methodologies keep their own contract. Mirrors ProgramEngine.
export function complementaryEffortCue(role, prescriptionStyle = "automatic",
  movementGroup = null, focus = "strength") {
  if (role !== "complementary"
      || resolvedPrescriptionStyle(prescriptionStyle, movementGroup, role, focus) !== "secondary") return null;
  return "Target 2–3 reps left. Adjust the next set if the load misses that range.";
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

// A program policy constrains automatic substitutions, not the exercise
// library or an athlete's deliberate manual edits. Keep this pure so the
// native and web coaching adapters enforce the same boundary.
export function equipmentPolicyAllows(policy, exerciseType) {
  if (policy !== "freeWeightsOnly") return true;
  // "timed" is a LOGGING type, not equipment: every timed movement in the
  // catalog is a bodyweight isometric (planks, holds). Excluding it made the
  // adductor volume floor permanently unfillable under this policy.
  return ["barbell", "dumbbell", "kettlebell", "bodyweight", "timed"]
    .includes(String(exerciseType ?? "").toLowerCase());
}
export const resolvedLoadBasis = (exercise) => LOAD_BASES.includes(exercise?.loadBasis)
  ? exercise.loadBasis : inferredLoadBasis(exercise?.type);
// Whether a double-progression slot on this exercise has a load step to earn.
// A bodyweight identity carries no external load, so its rep-window top is
// advisory — it climbs past it because reps are the only way it progresses.
// See `repWindow`'s `capped`. Mirrors CadenceCore LoadBasis.supportsLoadableIncrement.
export const supportsLoadableIncrement = (exercise) => resolvedLoadBasis(exercise) !== "bodyweight";

// Whether a slot actually has a load step to earn. BOTH halves are required
// and only one of them was ever checked: a numeric increment is not a load step
// on an identity that carries no external load. Mirrors CadenceCore
// ProgramProgression.hasLoadStep.
export const hasLoadStep = (incrementLb, exercise) =>
  supportsLoadableIncrement(exercise) && incrementLb > 0;

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
// Reps left in reserve, coarse on purpose. A number entry invites false
// precision — RIR accuracy is a trainable skill and averages about a rep of
// error even in experienced lifters, so three buckets carry the signal the
// literature actually supports.
//
// Deliberately a SEPARATE group from SET_QUALITIES. Quality says how the bar
// moved; RIR says how close to failure it was, and those are different
// questions — a set can be clean at 3+ reps in reserve or clean at 1. Each
// group is internally exclusive; the two never exclude each other.
export const SET_RIRS = ["rir1", "rir2", "rir3plus"];
export const SET_RIR_LABELS = { rir1: "1 left", rir2: "2 left", rir3plus: "3+ left" };
export const resolveSetStatus = (raw, sessionCompleted) => SET_STATUSES.includes(raw) ? raw : (sessionCompleted ? "completed" : "planned");
export const setQuality = (flags = []) => flags.find((flag) => SET_QUALITIES.includes(flag)) || null;
export const setRIR = (flags = []) => flags.find((flag) => SET_RIRS.includes(flag)) || null;
// Every writer of a flag list goes through here. That matters: this used to
// rebuild the list from quality and stopped-early alone, so any flag outside
// those two was silently dropped on export — a new flag would appear to work
// and then vanish on restore.
export const normalizedSetFlags = (quality, stoppedEarly = false, rir = null) => [
  ...(SET_QUALITIES.includes(quality) ? [quality] : []),
  ...(SET_RIRS.includes(rir) ? [rir] : []),
  ...(stoppedEarly ? ["stopped early"] : []),
];
// A correction to one banked set's performed record, applied after the session
// was completed: the lifter noticed the log is wrong (a set never marked
// complete, a weight banked at the stale plan). Only the fields the correction
// PROVIDES change, and only when they are sane — a blank or negative entry
// keeps the stored value rather than writing garbage into history. Everything
// else on the set (flags, warmup, load basis, planned values, body signals) is
// deliberately out of reach: editing reps cannot reset weight, and a
// correction cannot rewrite what was prescribed. Mirrors
// SetLifecycle.correctedSetValues.
export function correctedSetValues(set, correction = {}) {
  const corrected = { weightLb: set.weightLb, reps: set.reps,
    durationSeconds: set.durationSeconds ?? null, status: set.status };
  if (Number.isFinite(correction.weightLb) && correction.weightLb >= 0) corrected.weightLb = correction.weightLb;
  if (Number.isInteger(correction.reps) && correction.reps >= 0) corrected.reps = correction.reps;
  if (Number.isInteger(correction.durationSeconds) && correction.durationSeconds >= 0) {
    corrected.durationSeconds = correction.durationSeconds;
  }
  if (SET_STATUSES.includes(correction.status)) corrected.status = correction.status;
  return corrected;
}
// One tap on a correction row's status mark walks the shared status order —
// planned → completed → skipped → planned. Owned here, not in the two view
// layers: the cycle is user-facing documented behavior, and a reorder on one
// client would make the same tap do different things per platform. An unknown
// status starts the cycle from planned. Mirrors
// SetLifecycle.nextCorrectionStatus.
export function nextSetStatus(status) {
  const index = SET_STATUSES.indexOf(status);
  return SET_STATUSES[((index < 0 ? 0 : index) + 1) % SET_STATUSES.length];
}

// Whether a set of this kind counts as the slot's prescribed work — the sets
// that are graded and that supply the cycle's strength sample.
//
// "amrap" has to be in here. Grading filtered on "work" alone, so an AMRAP set
// would have been invisible: not counted toward completion, not eligible as the
// top set, and therefore unable to reach the e1RM sample at all. The whole
// point of the block is that its earned reps are read.
//
// Warm-ups, primers, ramps, top singles and back-offs stay out. They are real
// work but they are not the prescription being graded.
export const PRESCRIBED_WORK_BLOCKS = ["work", "amrap"];
export const countsAsPrescribedWork = (block) => PRESCRIBED_WORK_BLOCKS.includes(block || "work");

// Whether a set of this kind is an instruction the program gave the athlete —
// the question "did they do what was asked", which is what gates advancing the
// schedule. Wider than countsAsPrescribedWork by exactly one kind: conditioning
// is prescribed work the athlete owes, but it is graded in its own minutes
// ledger rather than against a load, so it never joins the lifting counts.
export const PROGRAM_INSTRUCTION_BLOCKS = [...PRESCRIBED_WORK_BLOCKS, "conditioning"];
export const countsAsProgramInstruction = (block) => PROGRAM_INSTRUCTION_BLOCKS.includes(block || "work");
// A set's effective block when the field predates the block model: warmups
// are warmups, everything else is work. Mirrors the native SetEntry
// prescriptionBlock getter's fallback.
export const resolvedPrescriptionBlock = (set) => set.prescriptionBlock || (set.isWarmup ? "warmup" : "work");

// ---- Plates & bars ---------------------------------------------------------

export const plateLb = (p) => toLb(p.value, p.unit);
export const plateId = (p) => `${p.value}-${p.unit}`;
export const plateLabel = (p) => `${trim(p.value, 2)} ${p.unit}`;

// Plate colour token (the user's gym scheme). The UI maps the token → a hex.
// kg is IWF: 25 red · 20 blue · 15 yellow · 10 green · 5 white · 2.5 red change plate.
// lb (colour bumpers): 55 red · 45 blue · 35 yellow · 25 green · 10 white ·
// 5 and under (and fractional) black iron.
export function plateColorToken(plate, style = "bumper") {
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
  if (plate.value === 2.5) return style === "bumper" ? "red" : "black";
  return "black"; // 1.25 + misc
}

// Diameter relative to a 450 mm competition disc. Bumper competition plates
// keep the same diameter; calibrated steel steps down with denomination.
export function plateDiameterFactor(plate, style = "steel") {
  if (style === "bumper") {
    if (plate.unit === "kg") {
      if (plate.value >= 10) return 1.0;
      if (plate.value >= 5) return 0.70;
      if (plate.value >= 2.5) return 0.55;
      return 0.45;
    }
    if (plate.value >= 10) return 1.0;
    if (plate.value >= 5) return 0.55;
    return 0.45;
  }
  const lb = plateLb(plate);
  if (lb >= 44) return 1.0;
  if (lb >= 33) return 0.89;
  if (lb >= 22) return 0.72;
  if (lb >= 11) return 0.51;
  if (lb >= 5) return 0.42;
  return 0.36;
}

export function plateThicknessFactor(plate, style = "steel") {
  const lb = plateLb(plate);
  if (style === "bumper") {
    if (lb >= 50) return 1.0;
    if (lb >= 44) return 0.84;
    if (lb >= 33) return 0.70;
    if (lb >= 22) return 0.56;
    if (lb >= 11) return 0.38;
    if (lb >= 5) return 0.28;
    return 0.22;
  }
  if (lb >= 50) return 0.55;
  if (lb >= 44) return 0.47;
  if (lb >= 33) return 0.40;
  if (lb >= 22) return 0.33;
  if (lb >= 11) return 0.25;
  if (lb >= 5) return 0.19;
  return 0.15;
}

export const plateSizeFactor = (plate) => plateDiameterFactor(plate, "steel");

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
// The lb denomination this bar loads plans under: an lb bar is its own label;
// a kg bar labels under its lb twin (a 20 kg bar IS the 45 in the same sense
// the plates are). Twin equivalence maths against this label, never the raw
// converted mass — 44.09 lb is not a clean lb plan. Mirrors Bar.labelLb.
export const barLabelLb = (b) => b.unit === "lb" ? b.value
  : Number(Object.keys(PLATE_TWIN_KG).find((lb) => PLATE_TWIN_KG[lb] === b.value) ?? barLb(b));

// The plate inventory a lift's STATION actually stocks. A station preference
// filters the gym's inventory to that denomination — the deadlift platform by
// the window has only kg plates, the squat racks only lb — falling back to
// the full standard set of that denomination when the gym stocks none of it
// (a preference is a statement about the station, not about the gym's
// shopping). No preference means the gym inventory, unchanged — exactly what
// every lift did before stations existed. Mirrors PlateMath.stationPlates.
export function stationPlates(preference, gymPlates) {
  if (preference !== "lb" && preference !== "kg") return gymPlates;
  const stocked = gymPlates.filter((p) => p.unit === preference);
  if (stocked.length) return stocked;
  return preference === "kg" ? STANDARD_KG : STANDARD_LB;
}

// The canonical grid label of a PERFORMED load — the number the stack on the
// bar goes by, not the number its mass happens to be. A load already on the
// rounding grid snaps to it exactly (never returns float noise); a kg stack
// labels CONSTRUCTIVELY: decompose each side into kg denominations (greedy,
// heaviest first — the stack a lifter actually builds) and read each plate's
// lb twin label back off the twin table. The label can sit above the raw
// mass (221.4 → 225, 838.7 → 855: 20 kg pairs run light) or BELOW it
// (67.05 → 65: a 5 kg pair masses 22.05 but reads 10 a side) — which is why
// this is a decomposition, not a directional search, and why it carries no
// window constant that a plate-table edit could silently invalidate. The
// same bar-or-bar-twin reading plateEquivalent uses applies, and every
// candidate must survive that same predicate, so labeling and grading can
// never disagree about a stack. Only when no twin label exists does it fall
// back to the next grid step up. Mirrors PlateMath.performedLabel.
export function performedLabel(performedLb, barLb = 45, roundingLb = 5) {
  if (!(performedLb > 0) || !(roundingLb > 0)) return performedLb;
  const nearest = Math.round(performedLb / roundingLb) * roundingLb;
  if (Math.abs(nearest - performedLb) < 1e-6) return nearest;
  const barTwinLb = PLATE_TWIN_KG[barLb] != null ? PLATE_TWIN_KG[barLb] / KG_PER_LB : barLb;
  for (const barMass of [barLb, barTwinLb]) {
    const side = kgSideLabelLb((performedLb - barMass) / 2);
    if (side == null) continue;
    const label = barLb + 2 * side;
    if (plateEquivalent(label, performedLb, barLb)) return label;
  }
  return Math.ceil(performedLb / roundingLb) * roundingLb;
}

// The lb label of one side's kg stack: greedy decomposition of sideMassLb
// into kg denominations by their true masses, summed as their lb twin labels
// — the inverse of kgTwinSideMassLb. Null when the mass is not a clean kg
// stack. The greedy epsilon absorbs the rounding of stored weights; the
// remainder bound is half of plateEquivalent's total band, and the caller
// re-verifies through that predicate anyway. Mirrors PlateMath.kgSideLabelLb.
export function kgSideLabelLb(sideMassLb) {
  if (!Number.isFinite(sideMassLb) || sideMassLb < 0) return null;
  let remaining = sideMassLb;
  let labelLb = 0;
  for (const lbLabel of [45, 35, 25, 10, 5, 2.5]) {
    const mass = PLATE_TWIN_KG[lbLabel] / KG_PER_LB;
    while (remaining >= mass - 0.05) { remaining -= mass; labelLb += lbLabel; }
  }
  return Math.abs(remaining) < 0.075 ? labelLb : null;
}

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

// The kg↔lb denomination twins. Lifters switching racks stop going by exact
// numbers and go by plates — a 20 kg plate stands in for a 45, a 5 kg pair for
// a 10 lb pair — not because the masses match (a 10 kg plate is 22 lb standing
// in for a 25) but because the plates are, for training purposes, the same
// object. Below maximal loads the drift is a rounding error; the plate is the
// currency, the number is its label. Mirrored 1:1 in CadenceCore PlateMath.
export const PLATE_TWIN_KG = { 45: 20, 35: 15, 25: 10, 10: 5, 5: 2.5, 2.5: 1.25 };

// The mass, in lb, of the kg-twin stack for one side loaded to sideLb with
// standard lb denominations — or null when sideLb is not a clean lb stack.
// Decomposition is GREEDY (biggest plates first): that is the stack a lifter
// actually builds, and it pins down which of several equal-total loadings the
// twins are taken from.
export function kgTwinSideMassLb(sideLb) {
  if (!Number.isFinite(sideLb) || sideLb < 0) return null;
  let remaining = sideLb;
  let twinLb = 0;
  for (const plate of [45, 35, 25, 10, 5, 2.5]) {
    while (remaining >= plate - 1e-9) {
      remaining -= plate;
      twinLb += PLATE_TWIN_KG[plate] / KG_PER_LB;
    }
  }
  return Math.abs(remaining) < 1e-6 ? twinLb : null;
}

// Whether performedLb is the plate-for-plate kg twin of the lb-clean targetLb
// — same plates, kg denominations, on the same bar or on the bar's own twin
// (a 45 lb bar and a 20 kg bar are the same object in the same sense the
// plates are). This is what makes a kg-gym session read as AT its lb plan
// instead of a below-plan miss that stalls the cycle.
export function plateEquivalent(targetLb, performedLb, barLb = 45) {
  if (!(targetLb > barLb) || !(performedLb > 0)) return false;
  const twinSide = kgTwinSideMassLb((targetLb - barLb) / 2);
  if (twinSide == null) return false;
  const barTwinLb = PLATE_TWIN_KG[barLb] != null ? PLATE_TWIN_KG[barLb] / KG_PER_LB : barLb;
  return [barLb + 2 * twinSide, barTwinLb + 2 * twinSide]
    .some((candidate) => Math.abs(performedLb - candidate) <= 0.15);
}

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
// ---- Training-anchor resolution (epic #155 Stage 3) ----
// Gym-independent athlete capability. Mirrors CadenceCore
// TrainingAnchorResolver — same rule table, same order, same fixtures.
// The methodology converts an anchor into a prescription; quantizeLoad then
// snaps that to the rack. Strictly downstream of here.
export const ANCHOR_RULES = [
  // Squat family
  { id: "front-squat-from-back-squat", version: 1, source: "Back Squat", target: "Front Squat", coefficient: 0.85, confidence: "estimated" },
  { id: "overhead-squat-from-back-squat", version: 1, source: "Back Squat", target: "Overhead Squat", coefficient: 0.65, confidence: "guessed" },
  { id: "low-box-squat-from-back-squat", version: 1, source: "Back Squat", target: "Low Box Squat", coefficient: 0.90, confidence: "estimated" },
  { id: "paused-box-squat-from-back-squat", version: 1, source: "Back Squat", target: "Paused Box Squat", coefficient: 0.90, confidence: "estimated" },
  { id: "front-box-squat-from-back-squat", version: 1, source: "Back Squat", target: "Front Box Squat", coefficient: 0.80, confidence: "estimated" },
  { id: "speed-box-squat-from-back-squat", version: 1, source: "Back Squat", target: "Speed Box Squat", coefficient: 0.60, confidence: "estimated" },
  // Hinge family
  { id: "rdl-from-deadlift", version: 1, source: "Deadlift", target: "Romanian Deadlift", coefficient: 0.85, confidence: "estimated" },
  { id: "snatch-grip-deadlift-from-deadlift", version: 1, source: "Deadlift", target: "Snatch-grip Deadlift", coefficient: 0.85, confidence: "estimated" },
  { id: "speed-deadlift-from-deadlift", version: 1, source: "Deadlift", target: "Speed Deadlift", coefficient: 0.60, confidence: "estimated" },
  { id: "sumo-deadlift-from-deadlift", version: 1, source: "Deadlift", target: "Sumo Deadlift", coefficient: 0.95, confidence: "estimated" },
  { id: "good-morning-from-deadlift", version: 1, source: "Deadlift", target: "Good Morning", coefficient: 0.50, confidence: "guessed" },
  // Horizontal press family
  { id: "incline-bench-from-bench", version: 1, source: "Barbell Bench", target: "Incline Barbell Bench Press", coefficient: 0.80, confidence: "estimated" },
  { id: "close-grip-bench-from-bench", version: 1, source: "Barbell Bench", target: "Close-Grip Bench Press", coefficient: 0.90, confidence: "estimated" },
  { id: "floor-press-from-bench", version: 1, source: "Barbell Bench", target: "Close-Grip Floor Press", coefficient: 0.85, confidence: "estimated" },
  { id: "speed-bench-from-bench", version: 1, source: "Barbell Bench", target: "Speed Bench Press", coefficient: 0.60, confidence: "estimated" },
  // Vertical press family
  { id: "press-from-bench", version: 1, source: "Barbell Bench", target: "Overhead Press", coefficient: 0.63, confidence: "guessed" },
  { id: "push-press-from-press", version: 1, source: "Overhead Press", target: "Push Press", coefficient: 1.15, confidence: "estimated" },
  // Olympic: exact history first; these are the low-confidence floor.
  { id: "clean-from-front-squat", version: 1, source: "Front Squat", target: "Clean", coefficient: 0.80, confidence: "guessed" },
  { id: "power-clean-from-clean", version: 1, source: "Clean", target: "Power Clean", coefficient: 0.85, confidence: "estimated" },
  { id: "clean-and-jerk-from-clean", version: 1, source: "Clean", target: "Clean & Jerk", coefficient: 0.95, confidence: "estimated" },
  { id: "power-snatch-from-snatch", version: 1, source: "Snatch", target: "Power Snatch", coefficient: 0.85, confidence: "estimated" },
];

export const FAMILY_ANCHORS = { squat: "Back Squat", hinge: "Deadlift", press: "Barbell Bench", pull: "Deadlift" };
// Deliberately pessimistic: a family estimate knows only that two lifts train
// the same pattern, so it starts light and lets the program earn it back.
export const FAMILY_ANCHOR_COEFFICIENT = 0.5;

export function resolveTrainingAnchor(exerciseName, {
  movementGroup = null, history = {}, overrideE1RMLb = null, defaultE1RMLb = null,
  rules = ANCHOR_RULES, familyAnchors = FAMILY_ANCHORS, shelvedExerciseNames = [],
  allowFamilyEstimate = true,
} = {}) {
  const shelved = new Set(shelvedExerciseNames);
  const exact = history[exerciseName];
  if (overrideE1RMLb > 0) {
    return { e1RMLb: overrideE1RMLb, latestWorkLb: exact?.latestCompletedLoadLb ?? null,
      source: "explicitOverride", sourceExerciseName: exerciseName, confidence: "measured",
      ruleId: null, explanation: "Your own setting" };
  }
  if (exact) {
    if (exact.allTimeBestE1RMLb > 0) {
      return { e1RMLb: exact.allTimeBestE1RMLb, latestWorkLb: exact.latestCompletedLoadLb ?? null,
        source: "exactExerciseE1RM", sourceExerciseName: exerciseName, confidence: "measured",
        ruleId: null, explanation: `From your ${exerciseName} history` };
    }
    if (exact.latestCompletedLoadLb > 0) {
      return { e1RMLb: null, latestWorkLb: exact.latestCompletedLoadLb,
        source: "exactExerciseRecentWork", sourceExerciseName: exerciseName, confidence: "measured",
        ruleId: null, explanation: `From your last ${exerciseName}` };
    }
  }
  // A shelved lift's history still informs estimates, but a shelved SOURCE
  // never seeds new work: a program must not quietly reactivate something the
  // lifter benched for a reason.
  const estimateFrom = (name, coefficient, confidence, ruleId, source) => {
    if (shelved.has(name)) return null;
    const profile = history[name];
    if (!(profile?.allTimeBestE1RMLb > 0)) return null;
    return { e1RMLb: profile.allTimeBestE1RMLb * coefficient, latestWorkLb: null, source,
      sourceExerciseName: name, confidence, ruleId, explanation: `Estimated from ${name}` };
  };
  for (const rule of rules) {
    if (rule.target !== exerciseName) continue;
    const estimate = estimateFrom(rule.source, rule.coefficient, rule.confidence, rule.id, "relatedExerciseEstimate");
    if (estimate) return estimate;
  }
  // A family estimate says only "these train the same pattern", which is thin
  // evidence for a lift the athlete has never performed. Callers that SEED a
  // slot pass false and take the conservative catalog default instead: a
  // too-light opening set costs one easy session, a too-heavy one costs a
  // failed rep under a loaded bar.
  const anchorName = allowFamilyEstimate && movementGroup ? familyAnchors[movementGroup] : null;
  if (anchorName && anchorName !== exerciseName) {
    const estimate = estimateFrom(anchorName, FAMILY_ANCHOR_COEFFICIENT, "guessed", null, "movementFamilyEstimate");
    if (estimate) return estimate;
  }
  return { e1RMLb: defaultE1RMLb > 0 ? defaultE1RMLb : null, latestWorkLb: null,
    source: "conservativeDefault", sourceExerciseName: null, confidence: "guessed",
    ruleId: null, explanation: "Conservative starting load" };
}

// ---- Load quantization (epic #155 Stage 3) ----
// A plate below this is a change plate: real to load, annoying to chase, and
// never worth a warmup or a low-percentage working set.
export const FIDDLY_PLATE_LB = 5;

// Working sets move at most one plate step and keep every denomination
// available; warmups are approximate by nature, so they get a wider band and
// large plates only. `bias` is a HARD constraint, not a tiebreak: quantizing
// a progressing lifter DOWN onto the load they just left would stall them.
export const quantizeWorkingSet = (bias) => ({ bandLb: 5, minimumPlateLb: 0, bias });
export const QUANTIZE_WARMUP = { bandLb: 10, minimumPlateLb: 10, bias: "nearest" };

// Snap a theoretical target onto the nearest load a human would actually
// build on this rack: fewest change plates per side, then fewest plates, then
// fewest distinct denominations, then closest to the target. Runs at
// prescription materialization — after the methodology converted capability
// into a number — never inside capability resolution, and the result is never
// written back into program cursor state. Mirrors CadenceCore PlateMath.quantize.
export function quantizeLoad(targetLb, bar, plates, collarLb = 0, options = quantizeWorkingSet("nearest"), maxPerPlateSide = 10) {
  if (!(targetLb > 0)) return targetLb;
  const collar = Math.max(0, collarLb || 0);
  // One unit system only — the bar's. A quantized load is a NUMBER the lifter
  // reads and the app stores, so a kg stack must not turn an lb prescription
  // into 211.14: mixed-unit stacks stay what they always were, loading
  // guidance produced by solve() under the neat target.
  const sameSystem = plates.filter((p) => p.unit === bar.unit);
  const pool = sameSystem.length ? sameSystem : plates;
  const usable = [...new Set(pool.map((p) => plateLb(p)))]
    .filter((lb) => lb >= options.minimumPlateLb - 1e-9)
    .sort((a, b) => b - a);
  const lower = options.bias === "up" ? targetLb : targetLb - options.bandLb;
  const upper = options.bias === "down" ? targetLb : targetLb + options.bandLb;
  const barTotal = barLb(bar) + collar;
  let best = null;
  const consider = (total, fiddly, used, distinct) => {
    if (total < lower - 1e-9 || total > upper + 1e-9) return;
    const deviation = Math.abs(total - targetLb);
    if (!best) { best = { fiddly, used, distinct, deviation, total }; return; }
    if (fiddly !== best.fiddly) { if (fiddly < best.fiddly) best = { fiddly, used, distinct, deviation, total }; return; }
    if (used !== best.used) { if (used < best.used) best = { fiddly, used, distinct, deviation, total }; return; }
    if (distinct !== best.distinct) { if (distinct < best.distinct) best = { fiddly, used, distinct, deviation, total }; return; }
    if (deviation < best.deviation - 1e-9) best = { fiddly, used, distinct, deviation, total };
  };
  consider(barTotal, 0, 0, 0);
  const maxPerSide = (upper - barTotal) / 2;
  const walk = (index, perSide, fiddly, used, distinct) => {
    if (index >= usable.length) return;
    const plate = usable[index];
    walk(index + 1, perSide, fiddly, used, distinct);
    if (!(plate > 1e-9)) return;
    let count = 0;
    let side = perSide;
    while (count < maxPerPlateSide) {
      side += plate;
      count += 1;
      if (side > maxPerSide + 1e-9) return;
      const nextFiddly = fiddly + (plate < FIDDLY_PLATE_LB - 1e-9 ? count : 0);
      consider(barTotal + 2 * side, nextFiddly, used + count, distinct + 1);
      walk(index + 1, side, nextFiddly, used + count, distinct + 1);
    }
  };
  walk(0, 0, 0, 0, 0);
  return best ? best.total : targetLb;
}

export const storedPrescription = (targetLb, achievedLb, barLb = 45) => {
  if (Math.abs(achievedLb - targetLb) <= TOLERANCE_LB + 1e-9) return targetLb;
  // Beyond the absolute band, the denomination twin still stores the canonical
  // number: the flat 2 lb tolerance dies exactly as plates stack (a four-pair
  // side is ~7 lb adrift), which is precisely where the lifter says the drift
  // matters least. The plates are the loading guidance; the number is its label.
  if (plateEquivalent(targetLb, achievedLb, barLb)) return targetLb;
  return achievedLb;
};

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

// ---- Program engine (four-phase mesocycle) ---------------------------------

// phase: 1 volume, 2 load, 3 peak, 4 short recovery bridge
export const PHASES = {
  1: { name: "Volume", sets: 5, reps: 5, multiplier: 1.0 },
  2: { name: "Load", sets: 5, reps: 3, multiplier: 1.10 },
  3: { name: "Peak", sets: 3, reps: 3, multiplier: 1.175 },
  4: { name: "Recovery", sets: 2, reps: 3, multiplier: 0.775 },
};
export const phaseNext = (p) => (p >= 4 ? 1 : p + 1);
export const phaseLabel = (p) => {
  const ph = PHASES[p];
  return `R${p} ${ph.name} ${ph.sets}×${ph.reps}`;
};
// Backup schema 7 stores a display label and recovers only the R-number on
// import. Keep the historical phase-4 wire string byte-stable while the live
// app presents the redesigned recovery bridge.
export const portablePhaseLabel = (p) => p === 4 ? "R4 Deload 3×5" : phaseLabel(p);

// The series key for a charted session that belongs to no program rotation.
export const UNTRACKED_ROTATION = "Untracked";

// Which rotation a charted session belongs to.
//
// The rotation is a fact about the SESSION — the program stamps every
// generated session with the rotation it was built for. Only some entries
// repeat it: main and complementary slots carry a per-entry phase, accessory
// slots never have, and entries logged before per-entry phase capture do not
// either. Reading the entry alone therefore reported real program work as
// "Untracked", and the same session that History's Rotations tab counted under
// "Cycle 2 · R3" vanished into the untracked series on Charts.
//
// The entry still wins where it exists: a slot re-logged into a later session
// keeps the rotation it was actually performed in. The session tag is the
// fallback, and only a session with no program tag at all is untracked.
//
// Mirrored 1:1 in CadenceCore ProgramEngine `ChartRotation.label`.
export function chartRotationLabel(entryPhase, sessionRotation) {
  const rotation = entryPhase ?? sessionRotation;
  if (!PHASES[rotation]) return UNTRACKED_ROTATION;
  return `R${rotation} ${PHASES[rotation].name}`;
}

// Where a lift is heading, fitted from what was actually performed.
//
// The charts stop at today, which is honest but not useful for the question a
// lifter actually asks — "at this rate, where am I in a month?" — so this fits
// a least-squares line through the performed points and extends it forward.
//
// A projection is a claim about the future, and the whole job here is to keep
// that claim narrow: it describes the rate the history already shows, it is not
// a plan and not what the program engine will prescribe (programmed work has
// its own forward view in exposurePreview, which runs the real engine), it
// refuses more often than it answers, it reports how well the line actually
// describes the history, and a downward trend projects downward.
//
// Pure in its samples — no dates, no timezones, no unit assumptions. A linear
// fit commutes with lb→kg scaling, so the projection is the same line either
// way. Mirrored 1:1 in CadenceCore TrendProjection.
export const TREND_MIN_SAMPLES = 4;
export const TREND_MIN_SPAN_DAYS = 21;
export const TREND_STALENESS_LIMIT_DAYS = 35;
export const TREND_STEP_DAYS = 7;
export const TREND_HORIZONS = [
  { value: 0, label: "Off" },
  { value: 30, label: "1 month" },
  { value: 90, label: "3 months" },
];

export function projectTrend(samples, horizonDays, asOfDay) {
  const usable = (samples || []).filter((s) => Number.isFinite(s.day) && Number.isFinite(s.value));
  if (usable.length < TREND_MIN_SAMPLES || !(horizonDays > 0)) return null;

  const days = usable.map((s) => s.day);
  const first = Math.min(...days), last = Math.max(...days);
  if (last - first < TREND_MIN_SPAN_DAYS) return null;
  if (asOfDay - last > TREND_STALENESS_LIMIT_DAYS) return null;

  const n = usable.length;
  const meanDay = days.reduce((a, b) => a + b, 0) / n;
  const meanValue = usable.reduce((a, s) => a + s.value, 0) / n;
  let covariance = 0, dayVariance = 0, valueVariance = 0;
  for (const s of usable) {
    const dx = s.day - meanDay, dy = s.value - meanValue;
    covariance += dx * dy; dayVariance += dx * dx; valueVariance += dy * dy;
  }
  // Every exposure on the same day: no rate can be read from it. The span
  // guard above already rejects this, but the division must not depend on that
  // ordering to stay safe.
  if (!(dayVariance > 0)) return null;

  const slope = covariance / dayVariance;
  const intercept = meanValue - slope * meanDay;
  const fitted = (day) => Math.max(0, intercept + slope * day);

  // R² against the mean. A flat history is perfectly described by a flat line,
  // so zero variance is a perfect fit, not a divide-by-zero.
  let residual = 0;
  for (const s of usable) {
    const error = s.value - (intercept + slope * s.day);
    residual += error * error;
  }
  const fitQuality = valueVariance > 0
    ? Math.max(0, Math.min(1, 1 - residual / valueVariance)) : 1;

  const end = asOfDay + horizonDays;
  if (!(end > last)) return null;
  // Starts at the FITTED value on the last performed day, not the performed
  // one: the gap between the last dot and where the line begins is the fit's
  // error, and hiding it by anchoring to the final point would dress a fluke
  // session up as the new baseline.
  const points = [];
  for (let day = last; day < end; day += TREND_STEP_DAYS) points.push({ day, value: fitted(day) });
  points.push({ day: end, value: fitted(end) });

  return { perWeek: slope * 7, fitQuality, points, horizonValue: fitted(end), horizonDay: end };
}

// One line of plain language for the trend. Deliberately says "at this rate"
// every time — the number is a continuation of the past, and the copy should
// never let it read as a promise about the future.
// Mirrored 1:1 in CadenceCore TrendProjection.summary.
export function trendSummary(perWeek, horizonLabel, horizonValue, unit) {
  // Round the MAGNITUDE, then re-apply the sign. Rounding the signed value
  // splits the two platforms on exact halves — Swift rounds away from zero,
  // JavaScript toward +∞ — so −2.25/week reads as −2.3 on one and −2.2 on the
  // other for the same history.
  const magnitude = Math.round(Math.abs(perWeek) * 10) / 10;
  if (magnitude === 0) return `Holding flat · ${horizonValue} in ${horizonLabel} at this rate`;
  const rate = magnitude === Math.round(magnitude) ? magnitude.toFixed(0) : magnitude.toFixed(1);
  return `${perWeek > 0 ? "+" : "−"}${rate} ${unit}/week · ${horizonValue} in ${horizonLabel} at this rate`;
}

// How much to trust the line, in a word. Thresholds are deliberately harsh: a
// projection the lifter should not lean on must not look like one they should.
// Mirrored 1:1 in CadenceCore TrendProjection.fitDescription.
export function fitDescription(fitQuality) {
  if (fitQuality >= 0.75) return "steady trend";
  if (fitQuality >= 0.4) return "rough trend";
  return "very noisy — treat as a guess";
}

// Whether the line is worth calling flat AND worth trusting as flat.
// trendSummary already rounds the magnitude to one decimal and prints
// "Holding flat" whenever that rounds to zero — even when fitDescription is
// simultaneously saying "very noisy". A slope that rounds to zero because the
// line is genuinely flat and a slope that rounds to zero because the fit
// can't find a direction in the noise read identically today; this tells the
// two apart by requiring the same fitQuality floor fitDescription uses for
// "rough trend" (0.4, inclusive).
// Mirrored 1:1 in CadenceCore TrendProjection.isPlateaued.
export function isPlateaued(perWeek, fitQuality) {
  const magnitude = Math.round(Math.abs(perWeek) * 10) / 10;
  return magnitude === 0 && fitQuality >= 0.4;
}

// Where the program is in its rotation, said without claiming the rotation is a
// weight wave. The program-level indicator is shared by slots that have nothing
// to do with each other's prescriptions, so it can only honestly report
// position. Mirrored 1:1 in CadenceCore ProgramEngine.rotationLabel.
// A missing or non-numeric pointer reads as rotation 1 rather than
// "Rotation NaN of 4" — the Swift mirror takes an Int and cannot express that
// case, so the coercion lives here to keep the two saying the same thing.
export const rotationLabel = (rotation) =>
  `Rotation ${Number.isFinite(rotation) ? Math.min(Math.max(rotation, 1), DELOAD_WEEK) : 1} of ${DELOAD_WEEK}`;

// Relative position for the exercise-detail four-rotation preview. Recovery
// is separate from the next work rotation. Mirrors ProgramEngine.
export function rotationContextLabel(rotation, currentRotation) {
  const current = Number.isFinite(currentRotation)
    ? Math.min(Math.max(currentRotation, 1), DELOAD_WEEK) : 1;
  if (rotation === current) return rotation === DELOAD_WEEK ? "Current recovery" : "Current";
  if (rotation === DELOAD_WEEK) return "Recovery";
  // DELOAD_WEEK - 1 is the last work rotation; the cycle length has exactly
  // one owner, so no literal wrap point here.
  const previous = current === 1 || current === DELOAD_WEEK ? DELOAD_WEEK - 1 : current - 1;
  if (rotation === previous) return "Previous";
  const next = current >= DELOAD_WEEK - 1 ? 1 : current + 1;
  if (rotation === next) return current >= DELOAD_WEEK - 1 ? "Next cycle" : "Next";
  return "Later";
}

// What a slot does, for the badge beside its name: "Main · 5/3/1",
// "Complementary · Secondary volume", "Main · Linear". Resolves "automatic"
// first, so the badge names the style the engine will actually run rather than
// the placeholder left in the picker.
// Mirrored 1:1 in CadenceCore ProgramEngine.slotBadge.
export function slotBadge(role = "main", prescriptionStyle = "automatic",
  movementGroup = null, focus = "strength") {
  const style = resolvedPrescriptionStyle(prescriptionStyle, movementGroup, role, focus);
  return `${role === "main" ? "Main" : "Complementary"} · ${prescriptionShortName(style)}`;
}

// The phase name for a slot, or null where the phase vocabulary does not
// describe what the slot prescribes. This is the whole of the fix: the phase
// label is a per-slot fact, not a program-wide one, and a program mixing a wave
// main lift with a novice linear complementary lift has to be able to say so on
// one screen. Mirrored 1:1 in CadenceCore ProgramEngine.slotPhaseLabel.
export function slotPhaseLabel(rotation, role = "main", prescriptionStyle = "automatic",
  movementGroup = null, focus = "strength") {
  const style = resolvedPrescriptionStyle(prescriptionStyle, movementGroup, role, focus);
  if (!usesCyclePhases(style) || !PHASES[rotation]) return null;
  return `R${rotation} ${PHASES[rotation].name}`;
}

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

// Movement-aware offset defaults for offsetWave. A stored zero means "use the
// default"; an explicit value stays user-owned. Absolute pounds on purpose —
// that is what offsetWave is for, and they are deliberately not proportional.
//
// Previously resolved in sessionPrescription only, so a squat reaching
// planForStyle directly silently got the upper-body 10/15 while the native side
// used 25/33. Values unchanged; only the divergence is fixed.
// Mirrored 1:1 in CadenceCore ProgramEngine.resolvedOffsets.
export function resolvedOffsets(loadOffsetLb, peakOffsetLb, movementGroup) {
  const lower = ["squat", "hinge"].includes(movementGroup);
  return {
    loadOffsetLb: loadOffsetLb > 0 ? loadOffsetLb : (lower ? 25 : 10),
    peakOffsetLb: peakOffsetLb > 0 ? peakOffsetLb : (lower ? 33 : 15),
  };
}

export function planForStyle(state, roundingLb = DEFAULT_ROUNDING_LB, style = "wave", configuration = {}, movementGroup = null,
  addedVolumeSets = 0) {
  const p = state.nextPhase;
  // A held cycle's volume fallback: extra sets land on the VOLUME rotation of
  // the wave-family styles only — load and peak keep their shapes, and
  // complementary styles govern their own volume.
  const extraSets = p === 1 ? Math.max(0, addedVolumeSets) : 0;
  const config = {
    // Zero is the stored sentinel for "use the movement-aware default";
    // resolvedOffsets below supplies it. Defaulting to 10/15 here would read as
    // an explicit user choice and suppress the lower-body upgrade.
    loadOffsetLb: 0, peakOffsetLb: 0, deloadMultiplier: 0.775,
    workingSets: 3, minimumReps: 5, maximumReps: 8, currentReps: 5,
    peakSingleEnabled: false, lastPeakSingleLb: 0, peakSingleIncrementLb: 5,
    phasePrimerEnabled: true, ...configuration,
  };
  Object.assign(config, resolvedOffsets(config.loadOffsetLb, config.peakOffsetLb, movementGroup));
  if (style === "linearFives") {
    // Sets-across at the slot's own base; the base moves per exposure
    // (advanceLinearLift). currentReps is a two-stage switch: ordinary fives,
    // or the explicit 3x5 -> 5x3 coaching transition.
    return {
      weightLb: roundTo(state.baseWeightLb * (p === 4 ? 0.80 : 1.0), roundingLb),
      sets: p === 4 ? 2 : Math.max(1, config.workingSets),
      reps: p === 4 ? 3 : (config.currentReps <= 3 ? 3 : 5),
      phase: p, cycleNumber: state.cycleNumber,
    };
  }
  if (["texasVolume", "texasLight", "texasIntensity"].includes(style)) {
    return {
      weightLb: roundTo(state.baseWeightLb * (p === 4 ? 0.80 : 1.0), roundingLb),
      sets: p === 4 ? 2 : Math.max(1, config.workingSets),
      reps: p === 4 ? 3 : 5, phase: p, cycleNumber: state.cycleNumber,
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
      sets: 2, reps: 3, phase: p, cycleNumber: state.cycleNumber,
    };
    return {
      weightLb: roundTo(state.baseWeightLb, roundingLb),
      sets: 1, reps: 1, phase: p, cycleNumber: state.cycleNumber,
    };
  }
  if (style === "dynamicEffort") {
    // Three-week pendulum wave. Straight-bar squat and pull work runs
    // 50→55→60%; speed bench runs 40→45→50%. The slot base is the first
    // percentage, so press multipliers are slightly wider.
    const scheme = movementGroup === "squat" ? [p === 3 ? 10 : 12, 2]
      : movementGroup === "hinge" ? [6, 1] : [9, 3];
    const multiplier = p === 2 && movementGroup === "press" ? 1.125
      : p === 3 && movementGroup === "press" ? 1.25
        : ({ 1: 1.0, 2: 1.10, 3: 1.20, 4: 1.0 })[p];
    return {
      weightLb: roundTo(state.baseWeightLb * multiplier, roundingLb),
      sets: p === 4 ? Math.max(2, Math.ceil(scheme[0] / 2)) : scheme[0],
      reps: scheme[1], phase: p, cycleNumber: state.cycleNumber,
    };
  }
  if (style === "offsetWave") {
    const weight = ({
      1: state.baseWeightLb,
      2: state.baseWeightLb + config.loadOffsetLb,
      3: state.baseWeightLb + config.peakOffsetLb,
      // Zero is "unset", never "lift nothing" — same rescue as the wave
      // branch below and as ProgramEngine's plan, so both cores agree even
      // for a hand-edited store the validators would refuse to import.
      4: state.baseWeightLb * (config.deloadMultiplier > 0 ? config.deloadMultiplier : 0.775),
    })[p];
    const phase = PHASES[p];
    return { weightLb: roundTo(weight, roundingLb), sets: phase.sets + extraSets, reps: phase.reps, phase: p, cycleNumber: state.cycleNumber };
  }
  if (style === "doubleProgression") {
    // One owner for the window, shared with the advance, so the prescription
    // and the grade can never disagree about it — including on `capped`, which
    // is why the slot's loadability has to reach the prescription and not only
    // the advance.
    const window = repWindow(config.minimumReps, config.maximumReps, config.currentReps,
      config.loadableIncrement !== false);
    return {
      weightLb: roundTo(state.baseWeightLb * (p === 4 ? 0.80 : 1.0), roundingLb),
      sets: p === 4 ? 1 : Math.max(1, config.workingSets),
      reps: p === 4 ? Math.min(5, window.low) : window.current,
      phase: p, cycleNumber: state.cycleNumber,
    };
  }
  const byStyle = {
    wave: {
      1: [5, 5, 1.0], 2: [5, 3, 1.10], 3: [3, 3, 1.175], 4: [2, 3, 0.775],
    },
    // Complementary work is volume after the day's heavy main — never a second
    // miniature of the main wave. Sets stay at 5+ reps and at or below the
    // slot's base (a 5-rep-calibrated weight; 8s sit ~90%).
    secondary: {
      1: [3, 8, 0.90], 2: [3, 8, 0.95], 3: [3, 6, 1.0], 4: [1, 5, 0.75],
    },
    hypertrophy: {
      1: [4, 10, 1.0], 2: [4, 8, 1.025], 3: [3, 8, 1.05], 4: [1, 5, 0.80],
    },
    // Conservative classic-lift build: five sets of triples, doubles, then
    // crisp singles. With the template's 70% history bootstrap this lands at
    // ~70/75/80%; recovery uses easy doubles instead of falling near 48%.
    technique: {
      1: [5, 3, 1.0], 2: [5, 2, 1.075], 3: [5, 1, 1.15], 4: [3, 2, 0.90],
    },
  };
  const table = byStyle[style] || byStyle.wave;
  const [sets, reps, tableMultiplier] = table[p];
  // The wave deload's intensity is the slot's own knob (default 0.775, the
  // historical constant). Volume stays cut either way; a lifter who finds
  // 77.5% unproductively light raises the intensity, not the set count.
  // Keyed on the resolved TABLE, not the style string, so an unknown style
  // falling back to the wave keeps parity with native's `?? .automatic`.
  const multiplier = table === byStyle.wave && p === 4
    ? (config.deloadMultiplier > 0 ? config.deloadMultiplier : tableMultiplier)
    : tableMultiplier;
  return {
    weightLb: roundTo(state.baseWeightLb * multiplier, roundingLb),
    // Keyed on the resolved table for the same reason as the multiplier:
    // only the wave family carries the volume fallback.
    sets: sets + (table === byStyle.wave ? extraSets : 0),
    reps, phase: p, cycleNumber: state.cycleNumber,
  };
}

// The order a day's slots were AUTHORED in, recovered from an imported
// payload. Distinct orders pass through verbatim; when every order ties (a
// hand-written file whose slots all say order: 0, or a backup written before
// slots carried orders) the tie holds no information and the array position
// the author wrote the slots in IS their order. Without this a tie falls to
// the alphabetical display fallback and the alphabet quietly does the
// lifter's programming. Pure mirror of CadenceCore ProgramEngine.
export function authoredSlotOrders(orders) {
  if (orders.length > 1 && orders.every((o) => o === orders[0])) {
    return orders.map((_, i) => i);
  }
  return orders;
}

export function primerWeight(baseWeightLb, phase, style, roundingLb = DEFAULT_ROUNDING_LB, configuration = {}) {
  const config = { loadOffsetLb: 10, ...configuration };
  if (phase === 1 || phase === 4) return null;
  if (phase === 2) return roundTo(baseWeightLb, roundingLb);
  if (style === "offsetWave") return roundTo(baseWeightLb + config.loadOffsetLb, roundingLb);
  return roundTo(baseWeightLb * PHASES[2].multiplier, roundingLb);
}

export function sessionPrescription(state, programRoundingLb, exerciseType = null, movementGroup = null,
  role = "main", focus = "strength", prescriptionStyle = "automatic", configuration = {}, estimatedMaxLb = 0,
  addedVolumeSets = 0) {
  const config = {
    peakSingleEnabled: false, lastPeakSingleLb: 0, peakSingleIncrementLb: 5,
    phasePrimerEnabled: true, ...configuration,
  };
  Object.assign(config, resolvedOffsets(config.loadOffsetLb, config.peakOffsetLb, movementGroup));
  const style = resolvedPrescriptionStyle(prescriptionStyle, movementGroup, role, focus);
  const work = programPlanFor(state, programRoundingLb, exerciseType, movementGroup, role, focus, style, config,
    addedVolumeSets);
  const step = programLoadStep(programRoundingLb, exerciseType);
  const blocks = [];
  if (config.phasePrimerEnabled && !buildsOwnSessionShape(style)) {
    const primer = primerWeight(state.baseWeightLb, state.nextPhase, style, step, config);
    if (primer > 0 && primer < work.weightLb) blocks.push({ kind: "primer", weightLb: primer, sets: 1, reps: 1 });
  }
  if (config.peakSingleEnabled && state.nextPhase === 3
    && style !== "technique" && !buildsOwnSessionShape(style)) {
    // The seed is a training max, so it follows the program's focus rather
    // than a hardcoded 0.90 — a hypertrophy program's ceiling is 0.78.
    const tm = FOCUS[focus]?.tm > 0 ? FOCUS[focus].tm : 0.90;
    const seed = config.lastPeakSingleLb > 0
      ? config.lastPeakSingleLb + config.peakSingleIncrementLb : estimatedMaxLb * tm;
    const target = roundTo(seed, step);
    if (target > work.weightLb) blocks.push({ kind: "topSingle", weightLb: target, sets: 1, reps: 1 });
  }
  if (style === "fiveThreeOne") {
    // The two ramp sets below the "+" set. Real prescribed work, but only the
    // top set gates progression, so they carry the non-graded ramp kind;
    // block order puts them before the top set.
    const ramp = {
      1: [[0.65, 5], [0.75, 5]], 2: [[0.70, 3], [0.80, 3]],
      3: [[0.75, 5], [0.85, 3]], 4: [[0.50, 5]],
    }[state.nextPhase];
    for (const [pct, reps] of ramp) {
      blocks.push({ kind: "ramp", weightLb: roundTo(state.baseWeightLb * pct, step), sets: 1, reps });
    }
  }
  if (style === "maxEffort" && state.nextPhase !== 4) {
    // After ordinary warm-ups, no more than three singles at 90% and above:
    // opener, near-max, then the day's target. Only the final single grades.
    let last = -Infinity;
    for (const pct of [0.90, 0.975]) {
      const target = roundTo(state.baseWeightLb * pct, step);
      if (target > last && target < work.weightLb) {
        blocks.push({ kind: "ramp", weightLb: target, sets: 1, reps: 1 });
        last = target;
      }
    }
  }
  // 5/3/1's top set is the "+" set — the AMRAP is the progression engine, not a
  // garnish, and shipping the percentages without it was the template's one
  // material infidelity to the published method. Wendler's deload week has no
  // "+" set, so it stays ordinary work.
  const isFiveThreeOnePlusSet = style === "fiveThreeOne" && state.nextPhase !== 4;
  blocks.push({ kind: isFiveThreeOnePlusSet ? "amrap" : "work", weightLb: work.weightLb, sets: work.sets, reps: work.reps });
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

// The scheme the athlete ACTUALLY performed at the session's top weight: the
// largest group of top-weight sets sharing one rep count, breaking a tie toward
// the harder (higher-rep) group.
//
// Counting every top-weight set while reporting the group's MINIMUM reps
// describes work nobody did — 225×5 followed by a fatigue set of 225×2 reads as
// "2×2", and 4×5 plus a dropped 3 reads as "5×3" (five triples for four fives
// and a three). Those strings are also banked as history schemes, so a
// fabricated scheme silently becomes the baseline every later session is
// measured against. Mirrored 1:1 in CadenceCore PRDetection.topScheme.
export function prTopScheme(sets) {
  if (!sets.length) return null;
  const top = Math.max(...sets.map((s) => s.weightLb));
  const topSets = sets.filter((s) => Math.abs(s.weightLb - top) < 1e-9);
  if (!topSets.length) return null;
  const byReps = new Map();
  for (const set of topSets) byReps.set(set.reps, (byReps.get(set.reps) || 0) + 1);
  let best = null;
  for (const [reps, count] of byReps) {
    if (!best || count > best.count || (count === best.count && reps > best.reps)) best = { reps, count };
  }
  return { weightLb: top, sets: best.count, reps: best.reps };
}

// Epley degrades past ten reps and "most reps at a weight" stops being a
// strength claim, so rep PRs are only tracked inside that range.
export const REP_PR_REP_CEILING = 10;

// Returns [{ kind, exercise, label }], kind ∈ heaviestSet|firstScheme|volumePR|repPR
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
      // Bodyweight and assisted work carry no meaningful load, so naming one
      // reads as "First 3×10 — 0 push-ups". Reps are the whole story there;
      // only external resistance is quoted.
      const label = supportsLoadPR(basis)
        ? `First ${schemeKey} — ${weightLabel(top.weightLb)} ${exercise.toLowerCase()}`
        : `First ${schemeKey} ${exercise.toLowerCase()}`;
      events.push({ kind: "firstScheme", exercise, label });
    }
  }

  const vol = prVolume(comparableSession);
  const priorVolMax = historyVolumes.length ? Math.max(...historyVolumes) : 0;
  if (supportsLoadPR(basis) && vol > priorVolMax + 1e-9 && historyVolumes.length) {
    const volumeLabel = formatWeight ? formatWeight(vol) : `${trim(vol)} lb`;
    events.push({ kind: "volumePR", exercise, label: `Volume PR — ${volumeLabel} total ${exercise.toLowerCase()}` });
  }

  // Rep PR: more weight at a rep count than ever before at that same rep count.
  // History already rebuilt this exact table to draw a chart, so the record
  // existed — nothing announced it when it happened, which is the whole value
  // of a PR.
  //
  // Capped at REP_PR_REP_CEILING: past that, "most reps at a weight" is a
  // conditioning result rather than a strength one, and the table fills with
  // noise from long back-off sets.
  //
  // One event per exercise per session, chosen by Epley so a genuinely harder
  // set wins over a longer easy one — the same ranking the cycle's strength
  // sample uses.
  const bestByReps = new Map();
  for (const set of comparableHistory) {
    if (!(set.reps >= 1 && set.reps <= REP_PR_REP_CEILING)) continue;
    bestByReps.set(set.reps, Math.max(bestByReps.get(set.reps) ?? 0, set.weightLb));
  }
  const beaten = comparableSession.filter((set) => set.reps >= 1 && set.reps <= REP_PR_REP_CEILING
    // A rep count never trained before is a first, not a rep PR — the
    // firstScheme event already speaks for that.
    && bestByReps.has(set.reps) && set.weightLb > bestByReps.get(set.reps) + 1e-9);
  if (beaten.length) {
    const best = beaten.reduce((a, b) => (epleyE1RM(b.weightLb, b.reps) > epleyE1RM(a.weightLb, a.reps) ? b : a));
    events.push({
      kind: "repPR",
      exercise,
      label: supportsLoadPR(basis)
        ? `Rep PR — ${weightLabel(best.weightLb)} × ${best.reps} ${exercise.toLowerCase()}`
        : `Rep PR — ${best.reps} reps ${exercise.toLowerCase()}`,
    });
  }
  return events;
}

// ---- Adaptive program progression --------------------------------------------
// Cross-cycle progression that is performance-gated, adds a proportional
// increment on a clean cycle, and auto-deloads on repeated stalls. Pure & deterministic — consumes
// a performance SUMMARY (never a session), no clock/random. Mirrors
// CadenceCore/Sources/CadenceCore/ProgramProgression.swift exactly.

export const QUALITY_FLAG_TOLERANCE = 1;   // ≤1 grindy/wobble set still SUCCESS
export const STALL_LIMIT = 2;              // 2 consecutive non-success → auto deload
export const DELOAD_REBUILD_FRACTION = 0.90;

// Persisted phase value for the recovery bridge. 1–3 are complete progression
// rotations; phase 4 is not another full pass through the program.
export const DELOAD_WEEK = 4;
// Recovery remains cycle-based. These elapsed days only expire a bridge that
// would otherwise sit open indefinitely; they do not schedule rotations.
export const RECOVERY_SESSION_LIMIT = 2;
export const RECOVERY_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

// Whether a persisted workout-stopwatch record may be adopted after a
// relaunch. One rule shared by the native UserDefaults record and the web
// localStorage record. A RUNNING record goes stale after a day (adopting
// last week's origin would paint days of elapsed time onto a reopened
// session); a PAUSED record is frozen evidence — elapsed is fixed at
// (pausedAt − start) — and stays adoptable, needing only internal
// consistency. Future-dated fields (clock skew, bad bytes) never fabricate
// a stopwatch. Mirrors CadenceCore StopwatchRecovery.
export const STOPWATCH_RECORD_WINDOW_MS = 24 * 60 * 60 * 1000;
export function stopwatchRecordUsable(startMs, pausedAtMs, nowMs) {
  if (!Number.isFinite(startMs) || startMs > nowMs) return false;
  if (pausedAtMs != null) {
    return Number.isFinite(pausedAtMs) && pausedAtMs >= startMs && pausedAtMs <= nowMs;
  }
  return nowMs - startMs < STOPWATCH_RECORD_WINDOW_MS;
}
// Complete rotations that must be banked since the last recovery bridge before
// another early one is allowed. Without a floor a run of red rotations turns
// recovery into the schedule, which is the opposite of what it is for.
//
// Counted in ROTATIONS, not sessions. A session floor silently scales with the
// split: eight sessions is two rotations of a four-day program but four
// rotations of a two-day one, and is simply unreachable inside a cycle for any
// rotation of three days or fewer — which disabled the feature outright on half
// the shipped templates.
export const MINIMUM_ROTATIONS_BETWEEN_DELOADS = 2;

// The rotation whose top work decides the cycle's progression.
export const GRADED_WEEK = 3;

// An e1RM observation from a rotation that is NOT the graded one.
//
// The graded rotation is a test, so it moves the estimate in either direction.
// Every other rotation prescribes deliberately submaximal work — a light set is
// not evidence the max fell, it is evidence the program asked for less. So only
// a sample that BEATS the standing estimate says anything, and it still smooths
// rather than jumping.
//
// This is what lets a capped AMRAP on the load rotation feed the engine. It
// also matters for the training-max ceiling: an estimate derived from the peak
// set is a fixed multiple of the base it is meant to bound, and therefore never
// binds. A load-rotation sample is earned reps at a weight the peak did not
// set, which is the independent anchor it has lacked.
export function observedMax(prior, sample) {
  return sample > prior ? smoothE1RM(prior, sample) : prior;
}

// Whether to cut this cycle short and go straight to recovery.
//
// Persistent red, not a single red: one bad rotation is noise, and the
// single-red answer (a temporary accessory-set cut) is already cheaper and
// reversible. Rotations 1 and 2 only — from rotation 3 the schedule advances
// into recovery by itself, so there is nothing to skip.
export function shouldDeloadEarly(currentWeek, readiness, previousReadiness, rotationsSinceLastDeload) {
  if (!(currentWeek >= 1 && currentWeek < DELOAD_WEEK - 1)) return false;
  if (readiness !== "red" || previousReadiness !== "red") return false;
  return rotationsSinceLastDeload >= MINIMUM_ROTATIONS_BETWEEN_DELOADS;
}

// The state a cycle-graded slot carries out of a cycle the program cut short
// for recovery. The lifter did not miss a peak — the peak never ran — so the
// base holds and no stall accrues. It is written into the same `pending` a real
// peak grade uses, so rollover applies it through its existing path and never
// reaches the skipped-peak stall branch.
export function recoveryDeloadHold(lift, week) {
  return {
    state: {
      baseWeightLb: lift.baseWeightLb,
      estimatedMaxLb: lift.estimatedMaxLb,
      stallCount: lift.stallCount || 0,
      lastIncrementLb: 0,
    },
    grade: "hold",
    note: `Recovery bridge — output stayed red, so the cycle stopped after rotation ${week} and went straight to recovery. The base holds.`,
  };
}

// focus → { tm: training-max as fraction of e1RM, inc: increment fraction of base }
export const FOCUS = {
  strength: { tm: 0.90, inc: 0.025 },
  hypertrophy: { tm: 0.78, inc: 0.015 },
  maintain: { tm: 0.0, inc: 0.0 },
};
export const focusParams = (focus) => FOCUS[focus] || FOCUS.strength;

// Deterministic UUID-shaped identifiers (epic #155 Stage 2) — the exact
// algorithm db.js has minted program-slot ids with since V4, promoted to the
// shared core so CadenceCore's StableID can mirror it byte-for-byte (shared
// vectors in core.test.mjs / StableIDTests). FNV-1a 32 over the seed, then
// 32 xorshift rounds emitting one hex nibble each, assembled v4-shaped.
export const stableID = (seed) => {
  let state = 0x811c9dc5;
  for (const ch of seed) { state ^= ch.charCodeAt(0); state = Math.imul(state, 0x01000193); }
  let hex = "";
  for (let i = 0; i < 32; i += 1) { state ^= state << 13; state ^= state >>> 17; state ^= state << 5; hex += ((state >>> 0) & 15).toString(16); }
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4${hex.slice(13, 16)}-a${hex.slice(17, 20)}-${hex.slice(20)}`;
};

// The legacy-ID namespace for exercises: seed/migration/import derive a
// pre-v11 exercise's portable id from its exact name, so the same store
// contents produce the same ids on every client. Mirrors
// StableID.exerciseLegacyID.
export const exerciseLegacyID = (name) => stableID(`exercise:${name}`);

export const epleyE1RM = (weightLb, reps) => (reps >= 1 ? weightLb * (1 + reps / 30.0) : weightLb);

// The shared athlete-history fold (epic #155 Stage 1): one projection from
// completed performed work to per-lift strength facts, consumed by template
// seeding on both clients. Pure and order-independent; callers normalize
// their own store's sets into samples (completed, non-warmup, positive load,
// at least one rep) because those filters live with each client's data layer.
// latestCompletedLoadLb is recency-first (same-moment ties take the heavier
// load, "what did they lift last"); allTimeBestE1RMLb is the lifetime Epley
// max with no rep ceiling ("capacity for seeding a brand-new slot") — the
// anchored rep-capped priorBestE1RM, slot-scoped recall, basis-partitioned PR
// baselines, and chart series deliberately keep their own scans.
// Mirrors CadenceCore AthleteHistory.index.
export function athleteHistoryIndex(samples) {
  const result = {};
  for (const sample of samples || []) {
    const profile = result[sample.exerciseName]
      || (result[sample.exerciseName] = {
        latestCompletedLoadLb: null, latestExposureMs: null, allTimeBestE1RMLb: null,
      });
    if (profile.latestExposureMs == null || sample.timestampMs > profile.latestExposureMs) {
      profile.latestExposureMs = sample.timestampMs;
      profile.latestCompletedLoadLb = sample.weightLb;
    } else if (sample.timestampMs === profile.latestExposureMs) {
      profile.latestCompletedLoadLb = Math.max(profile.latestCompletedLoadLb || 0, sample.weightLb);
    }
    const e1RM = epleyE1RM(sample.weightLb, sample.reps);
    if (e1RM > (profile.allTimeBestE1RMLb || 0)) profile.allTimeBestE1RMLb = e1RM;
  }
  return result;
}

// Epley is accurate at roughly 2-10 reps and drifts high above that, so a long
// back-off set is not allowed to masquerade as a strength sample.
export const E1RM_SAMPLE_REP_CEILING = 10;

// Which performed set is the cycle's strength sample.
//
// Heaviest-first is the intuitive answer and it is wrong: it makes an
// as-many-reps-as-possible set at the top weight invisible, because the first
// set at that weight wins the tie and the extra reps are discarded. A lifter
// who takes the last set to 8 instead of the prescribed 3 has produced the
// single best estimate of the cycle, and the engine has been throwing it away.
//
// Ranking by Epley fixes that and cannot be fooled by back-off volume —
// 135x10 estimates 180 lb and loses to 215x3's 236.5 — as long as reps stay
// inside the formula's accurate range, which is what the ceiling is for. When
// every set is a long one there is nothing better available, so the whole pool
// is ranked anyway rather than reporting no sample at all.
export function strengthSampleIndex(weightsLb, reps) {
  const count = Math.min(weightsLb.length, reps.length);
  if (count < 1) return null;
  const indexes = Array.from({ length: count }, (_, i) => i);
  const short = indexes.filter((i) => reps[i] <= E1RM_SAMPLE_REP_CEILING);
  const pool = short.length ? short : indexes;
  return pool.reduce((best, i) => (epleyE1RM(weightsLb[i], reps[i]) > epleyE1RM(weightsLb[best], reps[best]) ? i : best));
}
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
export function belowPlanLoad(actualLb, plannedLb, roundingLb = DEFAULT_ROUNDING_LB, barLb = 45) {
  if (plannedLb == null || plannedLb <= 0) return false;
  if (!(actualLb < plannedLb - roundingLb / 2)) return false;
  // A stack that is the plate-for-plate kg twin of the plan IS the plan —
  // heavier bars drift further under their lb label (each 20 kg pair is
  // 1.8 lb light), and grading that drift as a miss stalled cycles for work
  // the lifter performed exactly as loaded. The equivalence is a barbell
  // concept: it invents a bar-and-plates reading of the number, so only
  // total-bar work may claim it. Machines and dumbbells grade on the
  // numbers alone (barLb: null).
  if (barLb == null) return true;
  return !plateEquivalent(plannedLb, actualLb, barLb);
}

// Aggregate for a whole lift: the prescription is met when at least
// prescribedSets working sets are at the planned load. Extra sets beyond the
// prescription are bonus volume — a lighter back-off set after completing the
// planned work must not fail the cycle. Fewer at-plan sets than prescribed
// (whole lift performed light, or one prescribed set cut down) is below plan.
export function belowPlanWork(weightsLb, plannedLb, prescribedSets, roundingLb = DEFAULT_ROUNDING_LB, barLb = 45) {
  if (plannedLb == null || plannedLb <= 0) return false;
  const atPlan = weightsLb.filter((w) => !belowPlanLoad(w, plannedLb, roundingLb, barLb)).length;
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
// cycle/week/day tag AND the plan it was BUILT from still has the SAME
// COMPOSITION as the day's current plan. Snapshot-vs-current, not the live
// exercises — so a session-local remove/swap is preserved (resumed), while a
// PROGRAM edit (swap/add/remove) diverges the built-from plan → build fresh.
// Composition, not sequence: display order is now derived role-first, so a
// pure position move — and, critically, a pre-role-first snapshot written by
// an older version — must not orphan an in-flight session with logged sets.
// The sorted comparison is ordinal (code units), matching Swift's String `<`.
// Empty sessionPlanNames (pre-snapshot session) never resumes. Mirrors
// CadenceCore canResumeSession.
export function canResumeSession(tagCycle, tagWeek, tagDayIndex, cycleNumber, currentWeek, dayIndex, sessionPlanNames, dayPlanNames) {
  if (tagCycle !== cycleNumber || tagWeek !== currentWeek || tagDayIndex !== dayIndex) return false;
  if (!sessionPlanNames.length || sessionPlanNames.length !== dayPlanNames.length) return false;
  // NFC-normalize before comparing: Swift String equality is Unicode-
  // canonical, so an NFD-entered name must resume on both clients, not just
  // iOS.
  const session = sessionPlanNames.map((name) => String(name).normalize()).sort();
  const day = dayPlanNames.map((name) => String(name).normalize()).sort();
  return session.every((name, index) => name === day[index]);
}

// ---- Swap rules (issue 20) ----------------------------------------------
// A candidate is offered only when it trains the same movement pattern
// (non-empty matching group), sits in the same programming tier
// (Main/Accessory/Conditioning), matches the current lift's loadability,
// isn't the same exercise, and isn't shelved. `current`/`candidate` are
// exercise records. Loadability follows the resolved load basis, not equipment
// type: a weighted pull-up is bodyweight-typed but still carries external load.
// ---- Program slot ordering (one spelling) ----------------------------------
// Main work always precedes complementary work; authored order is preserved
// inside each role. Ties break on exerciseName with ORDINAL comparison
// (Swift's tuple `<`), not locale collation. Accessory-only callers have no
// main roles, so this is also their authored order. Mirrors native
// ProgramDay.orderedLifts / orderedAccessories.
export function orderedProgramSlots(slots = []) {
  const byName = (a, b) => (a.exerciseName < b.exerciseName ? -1 : a.exerciseName > b.exerciseName ? 1 : 0);
  return [...slots].sort((a, b) => {
    const role = (a.role === "main" ? 0 : 1) - (b.role === "main" ? 0 : 1);
    if (role) return role;
    return (a.order ?? 0) - (b.order ?? 0) || byName(a, b);
  });
}

// ---- Exercise gate (one spelling) ------------------------------------------
// The tri-state gate is authoritative; the legacy `isShelved` boolean decides
// only for records written before the gate existed, and a stale "open" next
// to isShelved=true reads as shelved. Mirrors the native Exercise.gateStatus
// getter — six ad-hoc spellings of this rule disagreed on exactly those
// legacy/stale combinations.
export function exerciseGateStatus(exercise) {
  if (!exercise) return "open";
  const raw = ["open", "watch", "shelved", "re-entry"].includes(exercise.gateStatus)
    ? exercise.gateStatus : "open";
  return raw === "open" && exercise.isShelved ? "shelved" : raw;
}
export function exerciseIsShelved(exercise) { return exerciseGateStatus(exercise) === "shelved"; }
// Shelved is the only gate state the coach must not prescribe into; watch and
// re-entry remain programmable (re-entry EXISTS to be programmed carefully).
export function exerciseIsAvailableForProgramming(exercise) { return !exerciseIsShelved(exercise); }

export function swapCompatible(current, candidate) {
  return !!current.movementGroup
    && candidate.movementGroup === current.movementGroup
    && candidate.name !== current.name
    && !candidate.isShelved
    && candidate.category === current.category
    && supportsLoadPR(resolvedLoadBasis(candidate)) === supportsLoadPR(resolvedLoadBasis(current));
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

// Where the schedule goes after banking the day with `bankedDayOrder`.
//
// Day `order` values ADDRESS the rotation — nextDayIndex holds an order, not a
// position — but they are not guaranteed to be the contiguous 0..n-1 that
// index-space arithmetic ((index + 1) % count) assumes. Import validates day
// orders as unique and never as contiguous. A gap made the last day
// unrecognizable: the week stopped advancing, the cycle never rolled over,
// every stashed Peak grade sat unapplied, and any day past the gap became
// unreachable. Walking the sorted orders is correct for both the tidy and the
// damaged case.
//
// Duplicate orders are collapsed first: two DISTINCT days can share one order
// (a damaged store, or an add that collided on days.length), and stepping
// within a duplicate pair would advance an order to itself and strand the
// schedule exactly like the gap this function exists to fix.
//
// An unknown bankedDayOrder (a stale tag, a deleted day) reports the last day
// so a rotation can still close, and points at the first day.
// Mirrored 1:1 in CadenceCore ProgramProgression.scheduleAdvance.
export function scheduleAdvance(dayOrders, bankedDayOrder) {
  const sorted = [...new Set(dayOrders)].sort((a, b) => a - b);
  const position = sorted.indexOf(bankedDayOrder);
  if (position < 0) return { nextDayOrder: sorted.length ? sorted[0] : 0, isLastDay: true };
  return { nextDayOrder: sorted[(position + 1) % sorted.length], isLastDay: position === sorted.length - 1 };
}

// Recovery completion is set-based, not pointer-based. The bridge can be
// banked in either order, and an in-flight phase-4 program may still point at
// an old full-rotation day omitted by the shortened bridge. Only selected
// exposures actually banked in this cycle count toward completion.
// Mirrored 1:1 in CadenceCore ProgramProgression.recoveryScheduleAdvance.
export function recoveryScheduleAdvance(dayOrders, completedDayOrders) {
  const selected = [...new Set(dayOrders)].sort((a, b) => a - b);
  if (!selected.length) return { nextDayOrder: 0, isLastDay: false };
  const completed = new Set(completedDayOrders);
  const next = selected.find((order) => !completed.has(order));
  return next === undefined
    ? { nextDayOrder: selected[0], isLastDay: true }
    : { nextDayOrder: next, isLastDay: false };
}

// Why a bounded recovery bridge is ready to hand off to the next cycle.
// `lastHardPhaseCompletionMs` is normally the final Peak completion; callers
// may supply the preceding rotation completion when recovery started early.
// Mirrored 1:1 in CadenceCore ProgramProgression.
export function recoveryBridgeCompletionReason(
  completedRecoverySessions,
  selectedExposureCount,
  selectedExposuresComplete,
  lastHardPhaseCompletionMs,
  nowMs,
) {
  if (selectedExposuresComplete) return "selectedExposures";
  // The cap is the BRIDGE'S OWN LENGTH, not a constant two. A program that is
  // not recognizably upper/lower keeps its full authored pass — that fallback
  // is deliberate, and capping it at two silently dropped day three onward for
  // full-body, Olympic and conditioning programs, which is the work-losing
  // behaviour the fallback exists to prevent.
  const cap = Math.max(RECOVERY_SESSION_LIMIT, selectedExposureCount || 0);
  if (completedRecoverySessions >= cap) return "sessionLimit";
  // Recovery is a bounded bridge from the last hard phase, not a new calendar
  // window that starts when reduced work is banked. Otherwise a first recovery
  // exposure on day six silently extends the bridge to day thirteen, and an
  // untouched recovery pointer can prescribe reduced work forever.
  if (Number.isFinite(lastHardPhaseCompletionMs)
      && nowMs - lastHardPhaseCompletionMs >= RECOVERY_WINDOW_MS) return "windowElapsed";
  return null;
}

// Select one authored lower and one authored upper exposure for the phase-4
// recovery bridge. Only the MAIN lift's movement group is supplied by callers,
// so accessories cannot reclassify a day. Unrecognizable programs keep their
// complete authored order: Olympic, full-body, conditioning-only, and damaged
// programs must not silently lose days because the engine guessed.
// Mirrored 1:1 in CadenceCore ProgramProgression.recoveryDayOrders.
export function recoveryDayOrders(candidates) {
  const sorted = [...candidates].sort((a, b) => a.order - b.order);
  const allOrders = [...new Set(sorted.map((candidate) => candidate.order))].sort((a, b) => a - b);
  const group = (candidate) => String(candidate.mainMovementGroup || "").toLowerCase();
  const lower = sorted.find((candidate) => ["squat", "hinge"].includes(group(candidate)));
  const upper = sorted.find((candidate) => ["press", "pull"].includes(group(candidate)));
  if (!lower || !upper || lower.order === upper.order) return allOrders;
  const selected = new Set([lower.order, upper.order]);
  return allOrders.filter((order) => selected.has(order));
}

// Increment = fraction of base, floored at plate granularity.
//
// This used to scale by headroom to a training-max ceiling
// (estimatedMax x tmFraction) and clamp to 0 at the cap. Both were removed,
// because measurement showed the taper never tapered and the ceiling could not
// bind:
//
// - Across 10,560 realistic (base, e1RM) pairs the function returned exactly
//   two values, 0 or roundingLb, and nothing in between. base x 0.025 x
//   headroom is a fraction of a pound at every realistic load, so it floored to
//   zero and the "guarantee a loadable bump" rescue put it straight back to a
//   full plate step. The headroom term's only observable effect was a cliff at
//   headroom <= 0.02.
// - That cliff was unreachable on the path that matters. A clean peak feeds
//   smoothedMax with 1.175 x base, which outruns a 0.90 x e1RM ceiling by
//   construction — traced over seven clean cycles, headroom RISES (0.047 ->
//   0.070) as the base climbs. A ceiling derived from the base cannot bound
//   the base.
//
// Base drift is bounded by performance instead, which is what the published
// systems do: STALL_LIMIT consecutive non-success cycles rebuild at
// DELOAD_REBUILD_FRACTION. tmFraction stays — it seeds peak singles and places
// a new program's base.
//
// Mirrored 1:1 in CadenceCore ProgramProgression.focusIncrement.
export function focusIncrement(baseWeightLb, focus, roundingLb = DEFAULT_ROUNDING_LB) {
  const fraction = focusParams(focus).inc;
  if (!(fraction > 0) || !(baseWeightLb > 0) || !(roundingLb > 0)) return 0;
  const stepped = Math.floor((baseWeightLb * fraction) / roundingLb) * roundingLb;
  // A clean cycle always earns at least one loadable step; anything less is not
  // a prescription anyone can put on a bar.
  return Math.max(roundingLb, stepped);
}

// Where the lifter stands relative to their own logged capability. The regime
// selects increment size and the failure fallback; the priority order it
// encodes is the lifter's: the needle moves every cycle, with weight when a
// clean jump is earnable and volume when it is not.
// Rebuild below 90% of the prior best; fine within 2.5% of it.
export const REBUILD_HEADROOM_BAND = 0.90;
export const FINE_HEADROOM_BAND = 0.975;
// A base at or below this fraction of the lifter's OWN current estimated max
// reads rebuild regardless of history bookkeeping. The drawdown test compares
// against the log's prior best — but a young log's prior best moves up with
// every cycle, so the rebuilding lifter that band exists for (real prior
// numbers predate the app) never trips it. The base-to-capability ratio is
// visible in the log right now: a 226 base under a 278 estimated max (81%) is
// a rebuild in progress, and +5 change-plate crumbs are noise at that
// distance from the ceiling. Mirrors ProgramProgression.rebuildBaseHeadroom.
export const REBUILD_BASE_HEADROOM = 0.85;
// A prior best only counts as a CEILING once it has stood this long. A fresh
// log rises through its own all-time best every cycle — without this guard
// the rebuilding lifter the regime exists for would read as at-max and be
// handed change-plate increments, the exact opposite of intent.
export const STANDING_BEST_DAYS = 35;

// Headroom to prior capability, banded: "rebuild" | "standard" | "fine".
// priorBestMaxLb is the best e1RM in the LOG (callers scan history); zero
// means no evidence and grades standard. Mirrors ProgramProgression.
export function progressionRegime(estimatedMaxLb, priorBestMaxLb, standingBest, baseWeightLb = 0) {
  // Base-to-own-capability headroom first — the fine band cannot also hold
  // there (fine means the base is closing on the ceiling).
  if (baseWeightLb > 0 && estimatedMaxLb > 0
    && baseWeightLb <= estimatedMaxLb * REBUILD_BASE_HEADROOM) return "rebuild";
  if (!(estimatedMaxLb > 0) || !(priorBestMaxLb > 0)) return "standard";
  if (estimatedMaxLb < priorBestMaxLb * REBUILD_HEADROOM_BAND) return "rebuild";
  if (standingBest && estimatedMaxLb >= priorBestMaxLb * FINE_HEADROOM_BAND) return "fine";
  return "standard";
}

// The focus increment staged by regime. Rebuild rounds UP to the clean 10 lb
// class — a 5 lb bump needs 2.5 lb change plates, which are noise while
// rebuilding; fine halves the step down to change-plate granularity, which is
// where they become the correct tool. Standard is focusIncrement untouched.
// A maintain focus stays 0 in every regime. Mirrors ProgramProgression.
export function stagedIncrement(baseWeightLb, focus, regime, roundingLb = DEFAULT_ROUNDING_LB) {
  const inc = focusIncrement(baseWeightLb, focus, roundingLb);
  if (!(inc > 0)) return 0;
  if (regime === "rebuild") return Math.ceil(inc / 10) * 10;
  if (regime === "fine") {
    // Half the program's own loadable step — the same half-grid the grading
    // tolerance already treats as met. At 5 lb rounding the banked halves
    // surface every second cycle; a program whose rack really has change
    // plates says so with 2.5 lb rounding, and the fine step follows it down.
    const half = roundingLb / 2;
    return Math.max(half, Math.round((inc / 2) / half) * half);
  }
  return inc;
}

// Target for a newly selected max-effort variation. Returning variations use
// their own completed single plus the normal upper/lower increment. The
// numeric-only model cannot derive one exercise's max from another, so an
// unseen variation gets an 80% calibration ceiling, not a fabricated 90%
// target. The old variation's TARGET is never inherited when any estimate
// exists; the last-resort fallbackBaseLb (no prior single AND a zero
// estimate — a hand-authored slot that never bootstrapped) IS the outgoing
// slot's base: with no evidence of any kind, holding the bar where the
// athlete was already working is the least-wrong seed, and the pre-rotation
// behavior for exactly this case. Mirrors ProgramProgression.
export function maxEffortVariationTarget(priorBestSingleLb, estimatedMaxLb, fallbackBaseLb,
  movementGroup = null, roundingLb = DEFAULT_ROUNDING_LB) {
  const increment = ["squat", "hinge"].includes(movementGroup) ? 10 : 5;
  const seed = priorBestSingleLb > 0 ? priorBestSingleLb + increment
    : estimatedMaxLb > 0 ? estimatedMaxLb * 0.80 : fallbackBaseLb;
  return Math.max(0, roundTo(seed, roundingLb));
}

// Extra sets the next VOLUME rotation carries after a held cycle, so the
// needle still moves when the weight cannot. Derived from persisted state
// alone — the Home card and the created session agree by construction, and a
// later clean grade resets the stall and returns the volume with the weight
// jump. maximumAddedSetsPerRotation is the ROTATION-WIDE budget, not a
// per-slot switch: callers rank this slot among the program's stalled
// peak-graded slots in stable program order (day order, then slot order) and
// the first `maximum` ranks receive one set each — four stalled lifts under
// a budget of one add one set, not four. Zero budget means no added work,
// ever. Mirrors ProgramProgression.volumeIncrementSets.
export function volumeIncrementSets(stallCount, stalledRank, maximumAddedSetsPerRotation) {
  return stallCount > 0 && stalledRank >= 0 && stalledRank < maximumAddedSetsPerRotation ? 1 : 0;
}

// state: { baseWeightLb, estimatedMaxLb, stallCount, role, lastIncrementLb }
// returns { state, grade, note }
// The base a cycle is honestly planned from: the stored base, repaired upward
// when the log proves the last earned advance failed to clear what was
// actually lifted. The trap is an advance computed in LABEL space: 215 + 10 =
// 225, but in a kg rack both numbers solve to the identical 2×20 kg stack —
// the label moved and the plates did not. The honest base is the canonical
// label of the last performed volume exposure plus the increment that advance
// earned: label(221.4) + 10 = 235, whose kg twin stack (232.4) is finally a
// heavier bar. Guards: only a machine-earned advance (lastIncrementLb > 0) is
// repaired — holds, deloads, and hand-set bases are their own truth; the RAW
// performed weight must clear the pre-advance base (base − lastIncrement)
// past the half-step grading tolerance (raw before labeling, so the label
// cannot manufacture the very margin it is tested for — a clean lifter's
// pre-advance exposure IS the pre-advance base) AND sit within one increment
// above the stored base (further out is a hand-set base or off-program heavy
// work, both left alone); capped at one increment above the stored base and
// floored at it — the floor is LOAD-BEARING, since performedLabel can sit
// below the raw mass (small kg plates outweigh their labels). Evidence must
// come from a cycle BEFORE the one being planned — callers scope it; the
// current cycle's own exposure must never feed the repair that produced its
// plan. Mirrors ProgramProgression.honestBase.
// bonusPerformedLb is the heaviest completed working set the lifter ADDED
// past the prescription (zero when none). Bonus work is deliberately
// history-only for grading — it can never pass or fail a cycle — but as
// planning evidence it is the opposite of ambient noise: a heavier set the
// lifter chose to pull is as explicit a signal as a hand edit, so it arms one
// staged increment of catch-up (catchUpIncrementLb, the increment the lift's
// regime currently earns; the last earned increment is the fallback) even
// when the at-plan work sat at the pre-advance base. Clamped to one step per
// cycle: the base chases demonstrated capability, it never teleports to one
// good day.
export function honestBase(baseWeightLb, lastIncrementLb, lastVolumePerformedLb,
  roundingLb = DEFAULT_ROUNDING_LB, barLb = 45, bonusPerformedLb = 0, catchUpIncrementLb = 0) {
  if (!(baseWeightLb > 0) || !(lastIncrementLb > 0)) return baseWeightLb;
  let repaired = baseWeightLb;
  if (lastVolumePerformedLb > 0
    && lastVolumePerformedLb > baseWeightLb - lastIncrementLb + roundingLb / 2
    && lastVolumePerformedLb <= baseWeightLb + lastIncrementLb + roundingLb / 2) {
    const label = performedLabel(lastVolumePerformedLb, barLb, roundingLb);
    repaired = Math.max(baseWeightLb, Math.min(label + lastIncrementLb, baseWeightLb + lastIncrementLb));
  }
  if (bonusPerformedLb > baseWeightLb + roundingLb / 2) {
    const step = catchUpIncrementLb > 0 ? catchUpIncrementLb : lastIncrementLb;
    const label = performedLabel(bonusPerformedLb, barLb, roundingLb);
    repaired = Math.max(repaired, Math.min(label + step, baseWeightLb + step));
  }
  return repaired;
}

export function advanceCycleLift(state, perf, focus, roundingLb = DEFAULT_ROUNDING_LB,
  regime = "standard", volumeFallback = false, performedVolumeLb = 0) {
  const grade = gradeCycle(perf);
  const estimatedMaxLb = smoothedMax(state, perf);
  const next = { ...state, estimatedMaxLb };
  let note = null;

  if (grade === "success") {
    next.stallCount = 0;
    const inc = stagedIncrement(state.baseWeightLb, focus, regime, roundingLb);
    // Progression rides performed values, not the stale programmed base. The
    // grade fires at the Peak, whose top set is base-× by design — so the
    // performed weight cannot feed the base directly; its OVERSHOOT ratio over
    // its own plan can. A lifter whose rack lands them a stack above plan
    // every session (kg plates on lb prescriptions) trains ahead of the base,
    // and advancing the stale number handed them back a fraction of the
    // increment. Guards: only ABOVE plan, only past the same half-step
    // tolerance the grade itself uses, never downward. plannedTopWeightLb 0
    // (legacy callers) keeps the old behavior exactly.
    let advancedFrom = state.baseWeightLb;
    if (perf.plannedTopWeightLb > 0
        && perf.topSetWeightLb - perf.plannedTopWeightLb >= roundingLb / 2) {
      advancedFrom = Math.max(state.baseWeightLb,
        state.baseWeightLb * (perf.topSetWeightLb / perf.plannedTopWeightLb));
    }
    // The volume rotation is where the lifter actually trains the base, and a
    // rack can land it off the stored label in either denomination. Advancing
    // from its canonical performed label (callers pass it through
    // performedLabel) resyncs a base the prescription-time honestBase repair
    // has been carrying, so stall and deload math stop operating on a stale
    // number. Never downward: lighter volume work already failed the grade.
    if (performedVolumeLb > advancedFrom + roundingLb / 2) {
      advancedFrom = performedVolumeLb;
    }
    next.baseWeightLb = advancedFrom + inc;
    next.lastIncrementLb = inc;
    note = advancedFrom > state.baseWeightLb
      ? `Clean peak, performed above plan — base rides the ${trim(advancedFrom - state.baseWeightLb)} lb overshoot, then +${trim(inc)} lb.`
      : inc > 0 ? `Clean peak — add ${trim(inc)} lb next cycle.` : "Maintaining — holding weight.";
  } else {
    next.stallCount = state.stallCount + 1;
    next.lastIncrementLb = 0;
    // Holding means "repeat the weight the cycle actually ran", and the
    // volume rotation is where that weight lives. A cycle carried by the
    // honest-base repair banked its volume work above the stored label;
    // without this resync, zeroing lastIncrementLb would disarm the repair
    // while the stale base persists, and the next cycle would re-prescribe
    // the very plates the repair existed to move past. Only upward, only
    // from completed volume work (lighter volume never clears the guard),
    // and the deload math below then operates on the real number.
    if (performedVolumeLb > next.baseWeightLb + roundingLb / 2) {
      next.baseWeightLb = performedVolumeLb;
    }
    if (next.stallCount >= STALL_LIMIT) {
      const old = next.baseWeightLb;
      next.baseWeightLb = roundTo(old * DELOAD_REBUILD_FRACTION, roundingLb);
      next.stallCount = 0;
      note = `Two cycles without a clean peak — deloaded ${trim(old)}→${trim(next.baseWeightLb)} lb to rebuild.`;
    } else if (volumeFallback) {
      // The needle still moves: a held weight adds a volume set next rotation
      // (volumeIncrementSets derives it from this stall), so the cycle
      // progresses by volume when it cannot progress by load.
      const held = grade === "fail" ? "Missed peak work" : "Grindy peak";
      note = `${held} — holding the weight; the next volume rotation adds a set so the cycle still moves.`;
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
// proportional rule. Mirrors ProgramProgression.advanceProgramLift.
export function advanceProgramLift(state, perf, focus, style, movementGroup = null, roundingLb = DEFAULT_ROUNDING_LB,
  regime = "standard", volumeFallback = false, performedVolumeLb = 0) {
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
    const next = { ...state };
    let note = null;
    if (grade === "success") {
      const made = Math.max(state.baseWeightLb, perf.topSetWeightLb);
      next.stallCount = 0;
      next.baseWeightLb = roundTo(made + increment, roundingLb);
      next.lastIncrementLb = next.baseWeightLb - state.baseWeightLb;
      // Keep the reference-lift estimate stable. Feeding this special
      // exercise's single into it would leak one variation's max into the next.
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
  return advanceCycleLift(state, perf, focus, roundingLb, regime, volumeFallback, performedVolumeLb);
}

// Whether an accessory slot is CARRYING load it can never add to.
//
// advanceAccessory uses `incrementLb > 0` as its entire test for "is this slot
// weighted?". That is correct for bodyweight and timed work, which progress by
// reps or duration and have no load to add. But a slot holding a real working
// weight with a zero increment falls into the same branch: it climbs reps
// forever, past its own maxReps, and the weight never moves.
//
// `weightLb > 0` is what makes this a misconfiguration rather than a choice. A
// zero weight with a zero increment is the documented way to say "no external
// load" — it is the default every newly added accessory starts at, and the
// editor labels the field "Load step (0 = bodyweight)".
//
// Timed and conditioning work is excluded for the same reason in reverse: a
// plank progresses by durationStepSeconds, so a zero increment there is right
// even when the slot carries a weight vest.
//
// Mirrored 1:1 in CadenceCore ProgramProgression.accessoryCannotProgressLoad.
export function accessoryCannotProgressLoad(exerciseType, loadBasis, weightLb, incrementLb) {
  // An explicit external basis outranks the equipment type, but ONLY for
  // bodyweight: a weighted pull-up is typed bodyweight while hanging real
  // plates from a belt, and the type guard alone silently exempted it from this
  // warning. Timed and conditioning stay unloadable whatever they carry.
  const type = String(exerciseType ?? "").toLowerCase();
  const unloadable = type === "timed" || type === "conditioning"
    || (type === "bodyweight" && !supportsLoadPR(loadBasis));
  if (unloadable) return false;
  if (loadBasis === "bodyweight") return false;
  return weightLb > 0 && !(incrementLb > 0);
}

// Whether the next session is landing sooner than the program's preferred
// spacing, and by how much.
//
// preferredSessionSpacingDays was previously write-only: a stepper set it, the
// coach's shorter-spacing trial wrote it, and nothing ever read it back. A
// preference the app collects and then ignores is worse than not asking. This
// is advisory only — it never blocks a session, because the lifter's calendar
// beats the app's opinion.
//
// Returns null when there is nothing useful to say.
// Bodyweight- and age-derived protein guidance. Advisory, and deliberately
// outside the programming engine — nothing here feeds progression or readiness.
// Since schema V5 there is no tracker and no stored target: this is a figure to
// aim at, not a number to tick off.
//
// 1.6 g/kg/day is the plateau Morton et al. (2018) found for RT-induced
// fat-free mass gains. That meta-analysis pooled resistance-training trials, so
// the training modality is already inside the number — there is no per-session
// multiplier, because scaling a daily intake by one day's workout is not
// something the evidence supports.
//
// Age is where the answer genuinely changes: Moore et al. (2015) put the
// per-meal plateau near 0.24 g/kg for younger adults and near 0.40 g/kg for
// older ones, the higher figure PROT-AGE (Bauer 2013) recommends, because
// muscle responds less to a given dose with age.
// Mirrored 1:1 in CadenceCore ProteinGuidance.
export const PROTEIN_DAILY_G_PER_KG = 1.6;
export const PROTEIN_MEAL_G_PER_KG_YOUNGER = 0.25;
export const PROTEIN_MEAL_G_PER_KG_OLDER = 0.4;
export const PROTEIN_OLDER_ADULT_AGE = 65;
export const PROTEIN_MEALS_PER_DAY = 4;

// Age in whole years, or null when there is no usable birth year. Never
// guessed — a default age would silently apply the wrong per-meal threshold.
export function ageFromBirthYear(birthYear, currentYear) {
  if (!(birthYear > 1900) || !(currentYear >= birthYear)) return null;
  const years = currentYear - birthYear;
  return years <= 120 ? years : null;
}

// Without an age this is the older-adult figure — the conservative direction,
// since the higher per-dose threshold costs a younger lifter nothing while
// under-dosing an older one is the failure that matters.
export function proteinMealGramsPerKg(age) {
  if (age == null) return PROTEIN_MEAL_G_PER_KG_OLDER;
  return age >= PROTEIN_OLDER_ADULT_AGE ? PROTEIN_MEAL_G_PER_KG_OLDER : PROTEIN_MEAL_G_PER_KG_YOUNGER;
}

const proteinGrams = (bodyweightLb, perKg) => {
  if (!(bodyweightLb > 0)) return null;
  return Math.round(kgFromLb(bodyweightLb) * perKg / 5) * 5;
};
export const proteinDailyTargetGrams = (bodyweightLb) => proteinGrams(bodyweightLb, PROTEIN_DAILY_G_PER_KG);
export const proteinPerMealGrams = (bodyweightLb, age = null) =>
  proteinGrams(bodyweightLb, proteinMealGramsPerKg(age));

// One line of guidance, or null when there is no bodyweight logged — the app
// never invents one.
export function proteinSummary(bodyweightLb, age = null) {
  const daily = proteinDailyTargetGrams(bodyweightLb);
  const meal = proteinPerMealGrams(bodyweightLb, age);
  if (daily == null || meal == null) return null;
  return `${daily} g/day at ${PROTEIN_DAILY_G_PER_KG} g/kg, about ${meal} g per meal across ${PROTEIN_MEALS_PER_DAY}.`;
}

// Why the per-meal figure is what it is, or null without an age to explain it.
export function proteinPerMealRationale(age) {
  if (age == null) return null;
  return age >= PROTEIN_OLDER_ADULT_AGE
    ? `Per-meal figure uses the higher ${PROTEIN_MEAL_G_PER_KG_OLDER} g/kg threshold for adults `
      + `${PROTEIN_OLDER_ADULT_AGE}+; muscle responds less to a given dose with age.`
    : `Per-meal figure uses ${PROTEIN_MEAL_G_PER_KG_YOUNGER} g/kg, rising to `
      + `${PROTEIN_MEAL_G_PER_KG_OLDER} g/kg from ${PROTEIN_OLDER_ADULT_AGE}.`;
}

// Mirrored 1:1 in CadenceCore ProgramProgression.sessionSpacingShortfall.
export function sessionSpacingShortfall(daysSinceLastSession, preferredDays) {
  if (!(preferredDays > 0)) return null;
  if (!Number.isInteger(daysSinceLastSession) || daysSinceLastSession < 0) return null;
  const shortfall = preferredDays - daysSinceLastSession;
  return shortfall > 0 ? shortfall : null;
}

// ---- Training-context intervals (one spelling) ------------------------------
// A typed calendar span the lifter declares over their timeline. The kinds
// are deliberately distinct — they differ in whether load was applied,
// whether the body was recovering, and what the engine should do afterwards
// (INV-INTERVAL-KINDS-STAY-DISTINCT). Nothing collapses them into a single
// "break". Callers pass inclusive day-bounded epoch milliseconds
// (start-of-day / end-of-day) so time zones resolve at the edge and the
// shared logic stays pure number comparison. Mirrors CadenceCore
// TrainingIntervals.
export const TRAINING_INTERVAL_KINDS = ["deload", "rest", "away", "activeRecovery"];
export const TRAINING_INTERVAL_KIND_LABELS = {
  deload: "Deload", rest: "Rest", away: "Away", activeRecovery: "Active recovery",
};
// The kinds that excuse an absence: a day inside one is never a missed day,
// never breaks a streak, and never reads as a lapse
// (INV-INTERVAL-IS-NOT-A-GAP). Deload deliberately does NOT excuse absence —
// deload days still expect sessions.
export const ABSENCE_EXCUSING_INTERVAL_KINDS = ["rest", "away", "activeRecovery"];

const intervalEndMs = (interval) => Math.max(interval.startMs, interval.endMs);

export function intervalContains(interval, timeMs) {
  return timeMs >= interval.startMs && timeMs <= intervalEndMs(interval);
}

export function insideInterval(timeMs, intervals = [], kinds = null) {
  return intervals.some((interval) => (kinds == null || kinds.includes(interval.kind))
    && intervalContains(interval, timeMs));
}

// Whether the gap between two trained moments is excused: some
// absence-excusing interval overlaps the open time between them. The spacing
// advisory and the shorter-spacing trial must not read a declared break as a
// training-frequency signal.
export function intervalGapExcused(fromMs, toMs, intervals = []) {
  if (!(toMs > fromMs)) return false;
  return intervals.some((interval) => ABSENCE_EXCUSING_INTERVAL_KINDS.includes(interval.kind)
    && interval.startMs <= toMs && intervalEndMs(interval) >= fromMs);
}

// Work logged inside an active-recovery interval is real, banked history —
// and explicitly off-program (INV-RECOVERY-WORK-IS-OFF-PROGRAM).
export function isOffProgramTime(timeMs, intervals = []) {
  return insideInterval(timeMs, intervals, ["activeRecovery"]);
}

// The away interval most recently ended before now, when it ended within the
// window and no session has been banked since it ended — the moment to
// suggest re-entry rather than straight continuation.
export function recentReturnFromAway(nowMs, lastSessionMs, intervals = [], windowMs = 7 * 86_400_000) {
  return intervals
    .filter((interval) => interval.kind === "away"
      && intervalEndMs(interval) < nowMs && nowMs - intervalEndMs(interval) <= windowMs
      && (lastSessionMs == null || lastSessionMs <= intervalEndMs(interval)))
    .reduce((latest, interval) => (!latest || intervalEndMs(interval) > intervalEndMs(latest) ? interval : latest), null);
}

// Total calendar days per kind within [sinceMs, untilMs], mirroring the
// merge-not-sum discipline asleepSeconds uses for overlapping sleep stages:
// two same-kind intervals covering the same day count that day once, not
// twice. Different kinds never merge into each other
// (INV-INTERVAL-KINDS-STAY-DISTINCT). Intervals extending outside the window
// are clamped to its edges first. Mirrors CadenceCore TrainingIntervals.daysByKind.
export function intervalDaysByKind(intervals = [], sinceMs, untilMs) {
  const result = Object.fromEntries(TRAINING_INTERVAL_KINDS.map((kind) => [kind, 0]));
  if (!(untilMs > sinceMs)) return result;

  for (const kind of TRAINING_INTERVAL_KINDS) {
    const clamped = intervals
      .filter((interval) => interval.kind === kind)
      .map((interval) => [Math.max(interval.startMs, sinceMs), Math.min(intervalEndMs(interval), untilMs)])
      .filter(([start, end]) => start <= end)
      .sort((a, b) => a[0] - b[0]);
    if (!clamped.length) continue;

    let totalMs = 0;
    let [runStart, runEnd] = clamped[0];
    for (const [start, end] of clamped.slice(1)) {
      if (start > runEnd) {
        totalMs += runEnd - runStart + 1;
        runStart = start;
        runEnd = end;
      } else if (end > runEnd) {
        runEnd = end;
      }
    }
    totalMs += runEnd - runStart + 1;
    result[kind] = Math.round(totalMs / 86_400_000);
  }
  return result;
}

// Accessory double progression. state: { sets, minReps, maxReps, currentReps,
// weightLb, incrementLb, stallCount }; perf: { completedSets, minRepsAchieved, anyStoppedEarly }
// The rep window a double-progression slot actually runs on, and the target
// inside it.
//
// The stored endpoints are two independent numbers that the editors let the
// lifter move past each other, so `minReps > maxReps` is a reachable state —
// the program editor already warns about it. Reading those endpoints literally
// is what made it destructive: with a window of 8–5 and a target of 5,
// `currentReps >= maxReps` is immediately true, so a slot prescribed at 3×5
// banked one clean exposure and came back at 3×8 with the load stepped as well
// — the whole point of double progression is that reps and load never move in
// the same exposure.
//
// The endpoints are therefore read as an UNORDERED pair: crossed steppers are
// the same window with its ends swapped, which preserves the runway the lifter
// configured. Collapsing `max` up to `min` instead would keep the window
// degenerate, and a degenerate window has no rep runway at all — every clean
// exposure would add load, which is the behaviour being fixed. The target is
// then clamped into that window, so what gets prescribed and what gets graded
// are the same number by construction.
//
// Stored endpoints are deliberately NOT rewritten: the crossed pair is the
// lifter's to correct, and the editor warning is what tells them.
//
// `capped` is what a slot WITHOUT a loadable increment turns off. Its window
// top is advisory — with no weight to add, the only way to progress is more
// reps, so it climbs past the top and the target must not be pulled back down
// to it. It is still floored at the bottom.
// Mirrored 1:1 in CadenceCore ProgramProgression.repWindow.
export function repWindow(minReps, maxReps, currentReps, capped = true) {
  const lo = Number.isFinite(minReps) ? minReps : 1;
  const hi = Number.isFinite(maxReps) ? maxReps : lo;
  const current = Number.isFinite(currentReps) ? currentReps : lo;
  const low = Math.max(1, Math.min(lo, hi));
  const high = Math.max(low, Math.max(lo, hi));
  const floored = Math.max(current, low);
  return { low, high, current: capped ? Math.min(floored, high) : floored };
}

// Accessory double progression. Two guarantees hold for EVERY input, including
// a slot whose stored window is incoherent:
//   - the rep target rises only at a held load; and
//   - the load rises only with the rep target held or dropped.
// They rest entirely on `repWindow` returning `low <= current <= high` (`high`
// only when capped): every branch below reads the clamped window rather than
// the stored fields, so no stored combination can put the target outside the
// range the branches assume. The reported failure (a slot prescribed at 3×5 @
// 80 returning 3×8 @ 85 in one exposure) came from reading the stored fields
// directly. Both suites sweep the whole input space rather than trusting this
// argument.
export function advanceAccessory(state, perf) {
  const next = { ...state };
  const weighted = state.incrementLb > 0;
  const window = repWindow(state.minReps, state.maxReps, state.currentReps, weighted);
  next.currentReps = window.current;
  const hitAll = perf.completedSets >= state.sets && perf.minRepsAchieved >= window.current
    && !perf.anyStoppedEarly && perf.performedAtPlannedLoad !== false
    && (perf.grindyOrWobbleSets || 0) <= 1 && (perf.bodyFlagSets || 0) === 0;
  if (!hitAll) {
    next.stallCount = state.stallCount + 1;
  } else if (weighted && window.current >= window.high) {
    next.weightLb = state.weightLb + state.incrementLb; // earned the rep range → add load, reset reps
    // The reset lands on the window BOTTOM, and this is the line that used to
    // raise reps while adding load: with the stored endpoints crossed,
    // `state.minReps` was above the target that had just been performed. It is
    // safe now for one reason and it is worth naming — `repWindow` guarantees
    // `low <= current`, so the reset can only hold or lower the target, never
    // raise it. Anything that weakens that clamp reopens the bug here.
    next.currentReps = window.low;
    next.stallCount = 0;
  } else {
    // weighted: climb to the cap. bodyweight/timed (no loadable increment): keep
    // climbing reps — the window top is advisory, since there's no weight to add.
    next.currentReps = weighted ? Math.min(window.current + 1, window.high) : window.current + 1;
    next.stallCount = 0;
  }
  return next;
}

// A history-aware first-set target for an off-program (ad-hoc/accessory)
// exercise, replacing the generic catalog default whenever the lifter has
// already performed this exact exercise+load-basis pairing.
//
// Repeats the prior top-of-session weight/reps by default. Adds one
// `incrementLb` step ONLY when the prior top-weight sets were both clean AND
// left reps in reserve (rir2/rir3plus) — the one state that actually shows
// headroom. Grindy, wobbly, rir1, or unflagged exposures hold flat: history
// without a legible "there was more in the tank" signal must not be read as
// one.
//
// Bodyweight and assisted work follow the same suppression PRDetection
// already applies to load PRs (`supportsLoadPR`): there is no honest
// external-load bump to offer, so weight is always repeated and only the rep
// count carries the suggestion.
//
// Returns null when there is no prior exposure, so the caller's existing
// generic-catalog fallback still applies. Mirrors CadenceCore
// `ProgramProgression.suggestedAdHocFirstSetTarget` 1:1.
export function suggestedAdHocFirstSetTarget(exposure, incrementLb = 5) {
  if (!exposure) return null;
  if (!supportsLoadPR(exposure.loadBasis)) {
    return { weightLb: exposure.weightLb, reps: exposure.reps };
  }
  const roomInReserve = exposure.quality === "clean"
    && (exposure.rir === "rir2" || exposure.rir === "rir3plus");
  const weightLb = roomInReserve ? exposure.weightLb + incrementLb : exposure.weightLb;
  return { weightLb, reps: exposure.reps };
}

// A short "where did this number come from" disclosure for a history-based
// ad-hoc first-set suggestion — the suggestion itself
// (`suggestedAdHocFirstSetTarget`) is otherwise silent about its origin.
// Reuses the app's existing relative-time wording (`agoLabel` in
// views/session.js) rather than inventing a second "how long ago" vocabulary
// the lifter would have to learn. Mirrors CadenceCore
// `ProgramProgression.historyProvenanceLabel` 1:1.
export function historyProvenanceLabel(exposureDate, asOfDate) {
  const days = Math.max(0, Math.floor((new Date(asOfDate) - new Date(exposureDate)) / 86400000));
  let when;
  if (days === 0) when = "today";
  else if (days === 1) when = "yesterday";
  else if (days < 14) when = `${days}d ago`;
  else if (days < 70) when = `${Math.floor(days / 7)}w ago`;
  else when = `${Math.floor(days / 30)}mo ago`;
  return `from your last exposure, ${when}`;
}

// The next `count` exposures a slot will actually produce.
//
// The point of the deterministic engine is that its output can be audited, and
// a wall of steppers is not an audit. A lifter setting a 190 lb base cannot see
// that it yields a 225 lb peak triple while 188 yields 220 — the difference
// between a +10 and a +5 jump, decided entirely by which side of a rounding
// boundary the multiplication lands on. This turns that into something a human
// reads at a glance.
//
// It runs the SHIPPED engine forward rather than describing it: every
// prescription comes from sessionPrescription, and every step between exposures
// comes from the same advanceAccessory / advanceLinearLift / advanceProgramLift
// calls the banking layer makes. A parallel implementation would be able to
// disagree with the app, which would make the preview worse than nothing.
//
// The walk assumes each exposure is banked exactly as prescribed — a clean
// success. That is the honest reading of "what will this produce": misses are
// the lifter's to discover, and a preview that guessed at them would be
// fiction. Reset and stall state still show, because the slot's CURRENT
// stallCount is carried in and the engine's own notes come back on each entry.
//
// Costs no persisted state. Mirrored 1:1 in CadenceCore
// ProgramEngine.exposurePreview.
export function exposurePreview({
  count = 4, baseWeightLb, estimatedMaxLb = 0, stallCount = 0, cycleNumber = 1, rotation = 1,
  programRoundingLb = DEFAULT_ROUNDING_LB, exerciseType = null, movementGroup = null,
  role = "main", focus = "strength", prescriptionStyle = "automatic", configuration = {},
  pendingState = null, schedule = null,
} = {}) {
  if (!(count > 0) || !(baseWeightLb >= 0)) return [];
  const style = resolvedPrescriptionStyle(prescriptionStyle, movementGroup, role, focus);
  const step = programLoadStep(programRoundingLb, exerciseType);
  // Coerce rather than spread-with-defaults: a slot record written before the
  // rep-window fields existed (and every freshly added lift) carries them as
  // `undefined`, and an explicit undefined WINS an object spread. That would
  // reach advanceAccessory as NaN and preview a rep window of nothing.
  // `repWindow` then owns the reading — including crossed endpoints, which
  // would otherwise let the preview show a rep jump and a load step landing
  // together. Same clamps the native side applies, so both platforms read a
  // malformed slot identically.
  const config = { ...configuration };
  const num = (value, fallback) => (Number.isFinite(value) ? value : fallback);
  config.workingSets = Math.max(1, num(config.workingSets, 3));
  const configuredWindow = repWindow(
    num(config.minimumReps, 5), num(config.maximumReps, 8),
    num(config.currentReps, num(config.minimumReps, 5)),
    config.loadableIncrement !== false,
  );
  config.minimumReps = configuredWindow.low;
  config.maximumReps = configuredWindow.high;
  config.currentReps = style === "linearFives"
    ? (num(config.currentReps, 5) <= 3 ? 3 : 5)
    : configuredWindow.current;
  let state = { baseWeightLb, estimatedMaxLb, stallCount, role, lastIncrementLb: 0 };
  let cycle = Math.max(1, cycleNumber);
  let phase = PHASES[rotation] ? rotation : 1;
  // Graded styles stash the new base at the Peak and apply it at the rollover,
  // so the recovery rotation still runs off the old base. Mirrors
  // pendingBaseWeightLb in the banking layer exactly.
  //
  // Seeded from the slot's ALREADY-BANKED grade when there is one. Open the
  // editor during recovery after a peak has been banked and the slot is
  // carrying an earned new base that the next cycle will use; starting from
  // null previewed that cycle off the old base and quietly understated every
  // number the lifter was about to see.
  let pending = pendingState;
  const entries = [];
  // A clean exposure of a plan: every prescribed set made at the prescribed
  // load, no quality flags, no autoreg drop.
  const cleanPerformance = (plan) => ({
    prescribedSets: plan.sets, prescribedReps: plan.reps, completedSets: plan.sets,
    anyStoppedEarly: false, anyDroppedLoad: false, anyBelowPlanLoad: false,
    grindyOrWobbleSets: 0, topSetWeightLb: plan.weightLb, topSetReps: plan.reps,
      plannedTopWeightLb: plan.weightLb,
  });

  // A direct core caller may omit schedule context. Treat that as a one-day
  // program; app surfaces supply the real day pointer and recovery selection.
  const previewSchedule = schedule || {
    targetDayOrder: 0, nextDayOrder: 0, allDayOrders: [0],
    recoveryDayOrders: [0], synchronizedDayOrders: [0],
  };
  const uniqueSorted = (values) => [...new Set(values || [])].sort((a, b) => a - b);
  const allOrders = uniqueSorted(previewSchedule.allDayOrders);
  const recoveryOrders = uniqueSorted(previewSchedule.recoveryDayOrders);
  if (!allOrders.includes(previewSchedule.targetDayOrder)) return [];
  const synchronizedOrders = new Set([
    ...(previewSchedule.synchronizedDayOrders || []), previewSchedule.targetDayOrder,
  ]);
  const activeOrders = () => (phase === DELOAD_WEEK && recoveryOrders.length ? recoveryOrders : allOrders);
  let orders = activeOrders();
  let orderIndex = Math.max(0, orders.indexOf(previewSchedule.nextDayOrder));
  const maxSteps = count * Math.max(1, allOrders.length + recoveryOrders.length) + allOrders.length + 8;
  let steps = 0;

  while (entries.length < count && orders.length && steps < maxSteps) {
    steps += 1;
    const dayOrder = orders[orderIndex];
    const isTarget = dayOrder === previewSchedule.targetDayOrder;
    const isSynchronizedDay = synchronizedOrders.has(dayOrder);
    const cycleState = {
      cycleNumber: cycle, baseWeightLb: state.baseWeightLb,
      nextPhase: phase, incrementLb: state.lastIncrementLb,
    };
    const prescription = sessionPrescription(
      cycleState, programRoundingLb, exerciseType, movementGroup,
      role, focus, style, config, state.estimatedMaxLb,
    );
    const work = prescription.mainWork;
    let note = null;

    if (isTarget && style === "doubleProgression") {
      // Rep window first, load second — and never on the recovery rotation,
      // which is non-progressive by contract.
      if (phase !== DELOAD_WEEK) {
        // The increment is the SLOT'S, not the program's step. A bodyweight
        // identity has no load to add, and handing this walk a non-zero step
        // made the preview disagree with the banking layer it exists to mirror:
        // it announced "add 5 lb and drop back to 5 reps" and showed the base
        // climbing 0 → 5 → 10 for a slot that only ever earns reps.
        const increment = config.loadableIncrement !== false ? step : 0;
        // `config` was normalized on the way in, so the window is already
        // coherent here — re-clamping would drift from the Swift mirror.
        const prior = {
          sets: config.workingSets, minReps: config.minimumReps,
          maxReps: config.maximumReps, currentReps: config.currentReps,
          weightLb: state.baseWeightLb, incrementLb: increment, stallCount: state.stallCount,
        };
        const next = advanceAccessory(prior, {
          completedSets: work.sets, minRepsAchieved: work.reps, anyStoppedEarly: false,
          performedAtPlannedLoad: true, grindyOrWobbleSets: 0, bodyFlagSets: 0,
        });
        note = next.weightLb > prior.weightLb
          ? `Top of the window earned — add ${trim(increment)} lb and drop back to ${next.currentReps} reps.`
          : `Earned the reps — ${next.currentReps} next time at the same load.`;
        state.lastIncrementLb = next.weightLb - prior.weightLb;
        state.baseWeightLb = next.weightLb;
        state.stallCount = next.stallCount;
        config.currentReps = next.currentReps;
      }
    } else if (advancesPerExposure(style) && style !== "doubleProgression" && isSynchronizedDay) {
      if (phase !== DELOAD_WEEK) {
        const result = style === "maxEffort"
          ? advanceProgramLift(state, cleanPerformance(work), focus, style, movementGroup, step)
          : advanceLinearLift(state, cleanPerformance(work), linearRule(style, movementGroup), step);
        state = result.state;
        if (isTarget) note = result.note;
      } else if (isTarget) {
        note = "Recovery rotation — the base holds, then the exposure cadence resumes.";
      }
    } else if (isTarget && phase === GRADED_WEEK) {
      const result = advanceProgramLift(state, cleanPerformance(work), focus, style, movementGroup, step);
      // The grade is banked now; the base lands at the rollover.
      pending = result.state;
      note = result.note;
    }

    if (isTarget) {
      entries.push({
        exposureNumber: entries.length + 1,
        cycleNumber: cycle,
        rotation: phase,
        phaseName: slotPhaseLabel(phase, role, style, movementGroup, focus),
        isRecovery: phase === DELOAD_WEEK,
        baseWeightLb: cycleState.baseWeightLb,
        prescription,
        advanceNote: note,
      });
    }

    orderIndex += 1;
    if (orderIndex >= orders.length) {
      if (phase === DELOAD_WEEK) {
        cycle += 1;
        // Mirror rollOverRecovery exactly, all three branches. Per-exposure
        // slots discard stale pending grades; graded slots apply a banked
        // grade; a peak-less wave accrues the real stall/rebuild.
        if (advancesPerExposure(style)) {
          pending = null;
        } else if (pending) {
          state = pending;
          pending = null;
        } else if (usesCyclePhases(style)) {
          state.stallCount = (state.stallCount || 0) + 1;
          state.lastIncrementLb = 0;
          if (state.stallCount >= STALL_LIMIT) {
            state.baseWeightLb = roundTo(state.baseWeightLb * DELOAD_REBUILD_FRACTION, step);
            state.stallCount = 0;
          }
        }
        phase = 1;
      } else {
        phase += 1;
      }
      orders = activeOrders();
      orderIndex = 0;
    }
  }
  return entries;
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

// How long after a session a hard-stop check-in still attributes to it, and
// what counts as a hard-stop response. One catalog for readiness attribution
// and the Body screen on both clients — a vocabulary word added to one copy
// and not another flips rotation readiness per platform. Mirrors
// CoachingEngine.checkInAttributionWindow / isHardStopResponse.
export const CHECKIN_ATTRIBUTION_WINDOW_MS = 36 * 60 * 60 * 1000;
export function isHardStopResponse(response) {
  const lowered = String(response || "").toLowerCase();
  return ["flag", "pain", "swell", "off"].some((word) => lowered.includes(word));
}

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

// Distance, duration, and speed are one relationship seen from three sides:
// distance = speed × time. Any two give the third, so the logger can accept
// whichever two the lifter actually knows. Only distance and duration are
// persisted — speed is always recoverable from them, so there is no third
// field to store, disagree with itself, or migrate. Flights repeat that
// relationship against a yardstick that is not ground covered, and are
// persisted the same way: the count and the duration, never the pace.

// Miles per hour from distance + duration, rounded to one decimal; null when
// either half is missing/zero (no speed without both).
export function cardioSpeedMph(distanceMiles, durationSeconds) {
  if (!(distanceMiles > 0) || !(durationSeconds > 0)) return null;
  return Math.round((distanceMiles / (durationSeconds / 3600)) * 10) / 10;
}

// Miles from speed + duration — the treadmill case, where the lifter sets a
// pace and a time and never sees a distance until the belt stops.
//
// Kept to four decimals rather than the two a treadmill displays: at two, a
// one-minute interval cannot tell 3.0 mph from 3.1 (both land on 0.05 mi), so
// a logged pace would read back as a different one. Display trims; storage does not.
export function cardioDistanceMiles(speedMph, durationSeconds) {
  if (!(speedMph > 0) || !(durationSeconds > 0)) return null;
  return Math.round(speedMph * (durationSeconds / 3600) * 10000) / 10000;
}

// Seconds from distance + speed — "four miles at 3.5 mph" as a plan.
export function cardioDurationSeconds(distanceMiles, speedMph) {
  if (!(distanceMiles > 0) || !(speedMph > 0)) return null;
  return Math.round((distanceMiles / speedMph) * 3600);
}

// ---- Climbed flights -------------------------------------------------------
// Conditioning measured in flights climbed, not ground covered. A stair
// climber's belt goes nowhere, so miles and miles-per-hour describe it with a
// unit it does not have: the console counts floors, and the training variable
// is how many and how fast.
//
// flights = pace × time, the same solve-the-third rule as distance, with pace
// in flights per minute rather than miles per hour. Minutes, because a
// climber's console reads in floors per minute and an hourly rate on a
// twenty-minute effort is a number nobody checks against the machine.
export const FLIGHT_CLIMBERS = new Set(["Stair Climber"]);

export const cardioClimbsFlights = (exerciseName) => FLIGHT_CLIMBERS.has(exerciseName);

// Flights per minute from flights + duration, rounded to one decimal; null
// when either half is missing/zero (no pace without both).
export function cardioFlightPace(flights, durationSeconds) {
  if (!(flights > 0) || !(durationSeconds > 0)) return null;
  return Math.round((flights / (durationSeconds / 60)) * 10) / 10;
}

// Flights from pace + duration — "twenty minutes at eight floors a minute".
//
// Four decimals for the same reason distance is: a pace set on a short
// interval has to read back as the pace that was set, and rounding to whole
// flights would collapse neighbouring paces onto one count.
export function cardioFlights(pacePerMinute, durationSeconds) {
  if (!(pacePerMinute > 0) || !(durationSeconds > 0)) return null;
  return Math.round(pacePerMinute * (durationSeconds / 60) * 10000) / 10000;
}

// Seconds from flights + pace — "sixty floors at eight a minute" as a plan.
export function cardioFlightDurationSeconds(flights, pacePerMinute) {
  if (!(flights > 0) || !(pacePerMinute > 0)) return null;
  return Math.round((flights / pacePerMinute) * 60);
}

// "170 flights", "1 flight". Trimmed to one decimal: a count entered by hand
// is whole, but one solved from a pace over a short interval is not, and
// rounding it away would contradict the pace shown beside it.
export function cardioFlightsLabel(flights) {
  const text = trim(flights, 1);
  return `${text} ${text === "1" ? "flight" : "flights"}`;
}

// Which fields a conditioning set is edited with. Pure mirror of
// CadenceCore/CardioFormat.swift (`CardioFields`, `fields`).
//
// Decided by the movement AND by what the set already holds: a climb logged in
// miles before flights existed keeps its distance block, because a field that
// disappears takes the only way to correct the value with it.
//
// One source for the editor's rows, its section header, and the row's
// affordance line, so a row can never advertise a field the editor withholds.
export function cardioFields(exerciseName, flights, distanceMiles, inclinePercent) {
  const climbs = cardioClimbsFlights(exerciseName);
  const f = {
    load: cardioCarriesLoad(exerciseName),
    flights: climbs || flights > 0,
    distance: !climbs || distanceMiles > 0,
    // A climber's grade is the machine, not a setting — unless a legacy set
    // already carries one.
    incline: !climbs || inclinePercent > 0,
  };
  const names = [];
  if (f.load) names.push("load");
  if (f.flights) names.push("flights");
  if (f.distance) names.push("distance");
  names.push("time");
  if (f.distance) names.push("speed");
  if (f.flights) names.push("pace");
  if (f.incline) names.push("incline");
  f.names = names;
  f.label = names.join(" · ");
  f.headerLabel = names.length
    ? [names[0][0].toUpperCase() + names[0].slice(1), ...names.slice(1)].join(" · ")
    : "";
  return f;
}

// Conditioning that carries external load. A ruck is a walk with a pack on,
// and the pack weight is the training variable — progressing it is the whole
// point. Zeroing the load the way unloaded cardio does makes a 60 lb ruck
// indistinguishable from a stroll.
export const LOADED_CARRIES = new Set(["Ruck", "Sled Push", "Sled Pull"]);

export const cardioCarriesLoad = (exerciseName) => LOADED_CARRIES.has(exerciseName);

// Where a loaded carry starts when nothing has been logged yet. A 20 lb pack
// is the conventional entry point. Sleds vary far too much by surface and
// implement to have an honest default.
export const cardioDefaultLoadLb = (exerciseName) => (exerciseName === "Ruck" ? 20 : null);

// Loaded carries move in plates and full pack increments, not barbell steps.
export const CARDIO_LOAD_INCREMENT_LB = 10;

// Format a duration as minutes and seconds, including hours when needed.
export function cardioDurationLabel(seconds) {
  const s = Math.max(0, seconds);
  const two = (n) => String(n).padStart(2, "0");
  if (s >= 3600) return `${Math.floor(s / 3600)}:${two(Math.floor((s % 3600) / 60))}:${two(s % 60)}`;
  return `${Math.floor(s / 60)}:${two(s % 60)}`;
}

// Build one compact line from whichever cardio fields were logged.
// Missing halves simply drop out; nothing logged → "—".
// `loadLb` is the carried weight for a ruck or sled — omitted entirely for
// unloaded work, which has none.
//
// Driven by what the set actually holds rather than by the exercise, so a
// stair-climber set logged in miles before flights existed still renders the
// distance it was recorded with instead of reading empty.
export function cardioSetLabel(distanceMiles, durationSeconds, inclinePercent, loadLb = null, flights = null) {
  const parts = [];
  if (loadLb > 0) parts.push(`${trim(loadLb)} lb`);
  if (flights > 0) parts.push(cardioFlightsLabel(flights));
  if (distanceMiles > 0) parts.push(`${trim(distanceMiles, 2)} mi`);
  if (durationSeconds > 0) parts.push(cardioDurationLabel(durationSeconds));
  const mph = cardioSpeedMph(distanceMiles, durationSeconds);
  if (mph !== null) parts.push(`${trim(mph)} mph`);
  const pace = cardioFlightPace(flights, durationSeconds);
  if (pace !== null) parts.push(`${trim(pace)} fl/min`);
  if (inclinePercent > 0) parts.push(`${trim(inclinePercent)}%`);
  return parts.length ? parts.join(" · ") : "—";
}

// ---- Health reconciliation -------------------------------------------------
// Pure mirror of CadenceCore/HealthComparison.swift.
//
// Health is a second opinion, never an authority. A watch measures a ruck more
// honestly than a lifter estimating afterwards; a treadmill belt measures a
// walk more honestly than a wrist. Neither wins by default, so this layer
// reports the disagreement and leaves the decision to the person who did the
// work. Nothing here mutates a log.
//
// A set carries no timestamp, only the session does, so comparison is at the
// session's conditioning total.

// Distances closer than this are the same distance; long efforts get
// proportional slack.
export const HEALTH_TOLERANCE_MILES = 0.05;
export const HEALTH_TOLERANCE_FRACTION = 0.02;

// Seconds two half-open ranges share. Zero when they merely touch.
// Accepts Date or epoch-millisecond numbers.
export function healthOverlapSeconds(aStart, aEnd, bStart, bEnd) {
  const ms = (v) => (v instanceof Date ? v.getTime() : v);
  const start = Math.max(ms(aStart), ms(bStart));
  const end = Math.min(ms(aEnd), ms(bEnd));
  return end > start ? Math.round((end - start) / 1000) : 0;
}

// Whether a Health workout belongs to a session, by majority overlap.
// Containment would drop the walk started in the car park before the app was
// opened; any-overlap would claim the bike commute that ended as it began.
export function healthSampleBelongsToSession(sampleStart, sampleEnd, sessionStart, sessionEnd) {
  const ms = (v) => (v instanceof Date ? v.getTime() : v);
  const sampleSeconds = (ms(sampleEnd) - ms(sampleStart)) / 1000;
  if (!(sampleSeconds > 0)) return false;
  return healthOverlapSeconds(sampleStart, sampleEnd, sessionStart, sessionEnd) >= sampleSeconds / 2;
}

// Compare any two measurements of the same thing. Zero and null are both
// absence — "Health has nothing to say" is never "Health says zero". Pass
// toleranceFraction 0 where a flat band is the honest one (a weigh-in does not
// get looser as the lifter gets heavier).
export function healthVerdictKind(logged, health, toleranceAbsolute, toleranceFraction = 0) {
  const l = logged > 0 ? logged : null;
  const h = health > 0 ? health : null;
  if (l === null && h === null) return "neither";
  if (l === null) return "onlyHealth";
  if (h === null) return "onlyLogged";
  const allowed = Math.max(toleranceAbsolute, Math.max(l, h) * toleranceFraction);
  if (Math.abs(h - l) <= allowed + 1e-9) return "agree";
  return h > l ? "healthHigher" : "loggedHigher";
}

// Compare a logged conditioning distance against Health's for one session.
// Returns { kind, loggedMiles, healthMiles, isDiscrepancy, adoptableMiles }.
export function healthCompare(loggedMiles, healthMiles) {
  const logged = loggedMiles > 0 ? loggedMiles : null;
  const health = healthMiles > 0 ? healthMiles : null;
  const kind = healthVerdictKind(logged, health, HEALTH_TOLERANCE_MILES, HEALTH_TOLERANCE_FRACTION);
  return {
    kind,
    loggedMiles: logged,
    healthMiles: health,
    isDiscrepancy: kind === "healthHigher" || kind === "loggedHigher" || kind === "onlyHealth",
    adoptableMiles: kind === "onlyLogged" || kind === "agree" || kind === "neither" ? null : health,
  };
}

// One line stating what each source says. Never phrased as a correction.
export function healthComparisonLabel(verdict) {
  const l = () => trim(verdict.loggedMiles, 2);
  const h = () => trim(verdict.healthMiles, 2);
  switch (verdict.kind) {
    case "agree": return `Health agrees: ${l()} mi`;
    case "healthHigher": return `Health recorded ${h()} mi · you logged ${l()} mi`;
    case "loggedHigher": return `You logged ${l()} mi · Health recorded ${h()} mi`;
    case "onlyHealth": return `Health recorded ${h()} mi that isn't logged`;
    case "onlyLogged": return "Nothing in Health for this session";
    default: return "No conditioning distance";
  }
}

// [INV-HEALTH-IS-A-SECOND-OPINION] Whether a Health sample came from somewhere
// other than Cadence itself.
//
// Load-bearing, and invisible when wrong. Cadence writes workouts, bodyweight
// and body fat into Health; without this every read would find those writes and
// "confirm" the log against a mirror of itself. A cross-check that always
// agrees is worse than no cross-check, because it looks like corroboration.
//
// An unattributable sample counts as foreign: discounting a sample we cannot
// prove is ours would silently drop a real second opinion, and the other
// choice fails visibly the first time it offers the lifter their own number.
export function healthSourceIsForeign(bundleIdentifier, appBundleIdentifier) {
  const app = (appBundleIdentifier || "").trim();
  if (!app) return true;
  const source = (bundleIdentifier || "").trim();
  if (!source) return true;
  return source.toLowerCase() !== app.toLowerCase();
}

// Two weigh-ins closer than this are the same weigh-in. A scale reports to a
// tenth of a pound and Health round-trips through kilograms, so exact equality
// would offer an "import" of a weight the lifter just typed.
export const HEALTH_WEIGH_IN_TOLERANCE_LB = 0.2;

// Whether a Health weigh-in is one Cadence already has: same calendar day and
// same number. A genuine second weigh-in later the same day is a different
// weight and stays offerable; yesterday's is a different day, not a duplicate.
export function healthIsSameWeighIn(loggedLb, loggedDate, healthLb, healthDate) {
  const a = loggedDate instanceof Date ? loggedDate : new Date(loggedDate);
  const b = healthDate instanceof Date ? healthDate : new Date(healthDate);
  if (a.getFullYear() !== b.getFullYear() || a.getMonth() !== b.getMonth()
      || a.getDate() !== b.getDate()) return false;
  return Math.abs(loggedLb - healthLb) <= HEALTH_WEIGH_IN_TOLERANCE_LB + 1e-9;
}

// The HKCategoryValueSleepAnalysis stages that count as sleep. `inBed` is time
// on the mattress, not time asleep, and `awake` is explicitly not sleep;
// counting either would inflate a night by hours.
export const HEALTH_ASLEEP_STAGES = [
  "asleepUnspecified", "asleepCore", "asleepDeep", "asleepREM",
];

// Total time actually asleep, from stage samples of { stage, start, end }.
//
// Overlapping intervals are MERGED, not added. A watch and a sleep app both
// staging the same night is ordinary, and the anti-echo filter does not help —
// it excludes Cadence, not third parties. Summing durations would report ten
// hours of sleep to someone who slept five, a number wrong enough to discredit
// every other figure on the screen.
export function healthAsleepSeconds(stages) {
  const ms = (v) => (v instanceof Date ? v.getTime() : new Date(v).getTime());
  const intervals = (stages || [])
    .filter((s) => HEALTH_ASLEEP_STAGES.includes(s.stage) && ms(s.end) > ms(s.start))
    .map((s) => [ms(s.start), ms(s.end)])
    .sort((a, b) => a[0] - b[0]);
  if (!intervals.length) return 0;

  let total = 0;
  let [runStart, runEnd] = intervals[0];
  for (const [start, end] of intervals.slice(1)) {
    if (start > runEnd) {
      total += runEnd - runStart;
      runStart = start;
      runEnd = end;
    } else if (end > runEnd) {
      runEnd = end;
    }
  }
  total += runEnd - runStart;
  return Math.round(total / 1000);
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

// One matcher for the library, program pickers, and active logger. Exercise
// availability is deliberately filtered by each caller: a gate is not search.
const normalizedExerciseSearchText = (value) => String(value ?? "")
  .normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();

export function exerciseMatchesSearch(exercise, query) {
  const term = normalizedExerciseSearchText(query).trim();
  if (!term) return true;
  return [exercise?.name, exercise?.movementGroup,
    movementPatternName(exercise?.movementPattern), exercise?.type,
    ...(exercise?.aliases || []), ...(exercise?.strategyTags || [])]
    .some((value) => normalizedExerciseSearchText(value).includes(term));
}

export const isConditioningPattern = (pattern) =>
  ["easyAerobic", "intervals", "mixedConditioning"].includes(pattern);

// Display names for the program-policy enums — one spelling for every picker
// and pill. Mirrors DayTrainingIntent.name / EquipmentPolicy.name in
// CadenceCore/ProgramPolicy.swift.
export const DAY_TRAINING_INTENT_LABELS = {
  general: "General", heavy: "Heavy", volume: "Volume",
  technique: "Technique", explosive: "Explosive",
};
export const EQUIPMENT_POLICY_LABELS = {
  any: "Any equipment", freeWeightsOnly: "Free weights + bodyweight",
};

const PATTERN_NAMES = {
  verticalPress: new Set(["Overhead Press", "Push Press", "Push Jerk", "Split Jerk", "Overhead DB Press", "Seated Upright DB Press", "Arnold Press", "Landmine Press", "KB Press"]),
  verticalPull: new Set(["Lat Pulldown", "Straight-arm Pulldown", "Pull-ups", "Chin-ups", "Assisted Pull-up",
    "Weighted Pull-up", "Weighted Chin-up"]),
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

// v2: a second consecutive red rotation escalates to a deeper cut.
export const COACHING_RULE_VERSION = 2;
// The set ceiling a slot falls to when it has never been given one. Mirrors
// CoachingEngine.defaultMaximumSets — capacity planning on both clients must
// agree on how much a defaulted slot can absorb.
export const DEFAULT_MAXIMUM_SETS = 6;
// Preference-ordered exercise names for filling a missing movement pattern —
// the coach's opinion, not the athlete's data. One catalog, mirrors
// CoachingEngine.preferredExerciseNames: a name added to one client's copy
// made the same accepted recommendation add different exercises.
export const PREFERRED_EXERCISES = {
  verticalPull: ["Lat Pulldown", "Assisted Pull-up", "Pull-ups", "Chin-ups",
    "Weighted Pull-up", "Weighted Chin-up"],
  kneeFlexion: ["Seated Leg Curl", "Lying Leg Curl", "Nordic Hamstring Curl"],
  shoulderStability: ["Face Pulls", "Band External Rotation", "Y-T-W Raises"],
  adductor: ["Copenhagen Plank", "Cable Hip Adduction"],
  core: ["Hanging Knee Raise", "Dead Bug", "Plank"],
};
// Seeded special-exercise rotations for max-effort slots. Compatible custom
// variations remain the fallback. Mirrors CoachingEngine.
export const PREFERRED_MAX_EFFORT_EXERCISES = {
  squat: ["Low Box Squat", "Front Box Squat", "Paused Box Squat"],
  horizontalPress: ["Floor Press", "Close-Grip Floor Press"],
};
// The rep window a coach-added accessory slot opens with, by pattern.
// Mirrors CoachingEngine.defaultRepRange(for:).
export const defaultRepRange = (pattern) => ["adductor", "core"].includes(pattern)
  ? { minReps: 8, maxReps: 12 } : { minReps: 6, maxReps: 10 };
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
      .filter((set) => !set.isWarmup && countsAsPrescribedWork(set.prescriptionBlock)
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
        const block = resolvedPrescriptionBlock(set);
        if (!countsAsProgramInstruction(block)) return true;
        if (remainingWork <= 0) return false;
        remainingWork -= 1;
        return true;
      });
      return [{ ...exercise, slotID: slot.id, programRole: slot.role, pattern: slot.pattern, sets }];
    }),
  };
}

function assessCoachingRotation(key, sessions, expectedDayIndexes, priorPerformance, priorReadiness, judgedAsRun = false) {
  const completedDayIndexes = [...new Set(sessions.map((session) => session.dayIndex))];
  const complete = expectedDayIndexes.every((day) => completedDayIndexes.includes(day));
  const exercises = sessions.flatMap((session) => session.exercises || []);
  const allSets = exercises.flatMap((exercise) => exercise.sets || []);
  // Conditioning is reported in minutes, not lifting sets, and therefore
  // cannot raise or lower lifting prescription completion/readiness.
  const liftingExercises = exercises.filter((exercise) => !isConditioningPattern(exercise.pattern));
  const working = liftingExercises.flatMap((exercise) => exercise.sets || []).filter((set) =>
    !set.isWarmup && countsAsPrescribedWork(set.prescriptionBlock));
  const completedWorking = working.filter((set) => set.completed !== false);
  const plannedWorkingSets = liftingExercises.reduce((sum, exercise) =>
    sum + Math.max(0, exercise.plannedSets || 0), 0);
  const atPlanWorkingSets = completedWorking.filter(atPlan).length;
  const patternSets = {};
  for (const exercise of exercises) patternSets[exercise.pattern] = (patternSets[exercise.pattern] || 0)
    + (exercise.sets || []).filter((set) => !set.isWarmup
      && countsAsPrescribedWork(set.prescriptionBlock) && set.completed !== false).length;
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
  if (judgedAsRun) {
    // First, because both clients surface only the leading reason.
    reasons.unshift(`Closed rotation — reported as run (${completedDayIndexes.length} day${completedDayIndexes.length === 1 ? "" : "s"}); the program's shape at the time is not recoverable.`);
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
    completedDayIndexes, expectedDayIndexes, isComplete: complete, judgedAsRun, plannedWorkingSets,
    completedWorkingSets: completedWorking.length, atPlanWorkingSets,
    conditioningMinutes: conditioningSeconds / 60, patternSets, readiness, reasons,
    performanceDelta, completionRate,
  };
}

// Technique and explosive days own quality, not fatigue accumulation.
// Explicit intent is the proof; legacy `general` days retain the old capacity
// behavior exactly. Mirrors CoachingEngine.supportsAddedCapacity.
const supportsAddedCapacity = (slot) => !["technique", "explosive"].includes(slot.trainingIntent || "general");

const preferredCoachingDay = (pattern, slots) => {
  const eligible = slots.filter(supportsAddedCapacity);
  if (["kneeFlexion", "hipExtension"].includes(pattern)) {
    const squat = eligible.find((slot) => slot.isMain && slot.pattern === "squat");
    if (squat) return squat.dayIndex;
  }
  if (["verticalPull", "shoulderStability"].includes(pattern)) {
    const upper = eligible.find((slot) => slot.isMain && ["horizontalPress", "verticalPress"].includes(slot.pattern));
    if (upper) return upper.dayIndex;
  }
  return eligible.length ? Math.min(...eligible.map((slot) => slot.dayIndex)) : null;
};

const shorterSpacingTrial = (sessions, declaredBreaks = []) => {
  const ordered = [...sessions].sort((a, b) => epoch(a.date) - epoch(b.date));
  if (ordered.length < 4) return null;
  // A gap the lifter declared (rest/away/active recovery overlapping the open
  // time) is not a frequency observation — including it would read a vacation
  // as the athlete's chosen spacing (INV-INTERVAL-IS-NOT-A-GAP). Mirrors
  // CoachingEngine.shorterSpacingTrial.
  const intervals = ordered.slice(1)
    .map((session, index) => [epoch(ordered[index].date), epoch(session.date)])
    .filter(([fromMs, toMs]) => !intervalGapExcused(fromMs, toMs, declaredBreaks))
    .map(([fromMs, toMs]) => Math.floor((toMs - fromMs) / 86_400_000))
    .filter((days) => days > 0).sort((a, b) => a - b);
  if (intervals.length < 3) return null;
  const median = intervals[Math.floor(intervals.length / 2)];
  return median >= 4 ? Math.max(2, median - 1) : null;
};

// A lift slot's counter resets the moment the base is rebuilt, so any non-zero
// value means the weight is being retried. Accessory counters are unbounded and
// nothing ever resolves them, so they need a real plateau.
export const LIFT_STALL_ROTATION_THRESHOLD = 1;
export const ACCESSORY_STALL_ROTATION_THRESHOLD = 3;

// Slots the program should stop prescribing as they stand: the exercise has
// been shelved, or the slot is stuck retrying a weight it is not making. Both
// are suggestions — the engine names the slot, the client resolves a compatible
// variation, and the athlete decides.
function rotationSuggestions(program, sessions, evidenceKey) {
  const result = [];
  // Ordinal (code-unit) tiebreak, NOT localeCompare: Swift's String `<` is
  // ordinal, and the slot walk order feeds recommendation ids that must match
  // across clients regardless of the browser's locale/collation.
  const ordered = [...(program.slots || [])].sort((a, b) => a.dayIndex - b.dayIndex
    || (String(a.id) < String(b.id) ? -1 : String(a.id) > String(b.id) ? 1 : 0));
  // Only the max-effort branch reads history; most programs have no such slot
  // and must not pay a full-history copy+sort per report (mirrors native).
  const newest = ordered.some((slot) => slot.prescriptionStyle === "maxEffort")
    ? [...sessions].sort((a, b) => epoch(b.date) - epoch(a.date)) : [];
  for (const slot of ordered) {
    if (isConditioningPattern(slot.pattern)) continue;
    if (slot.exerciseIsShelved) {
      result.push({
        id: `program.slot.rotate.shelved.v${COACHING_RULE_VERSION}:${evidenceKey}-${slot.id}`,
        ruleID: `program.slot.rotate.shelved.v${COACHING_RULE_VERSION}`, priority: 70,
        title: `${slot.exerciseName} is shelved but still programmed`,
        explanation: `This slot still prescribes ${slot.exerciseName}, which you have shelved. Rotate it to a compatible variation of the same movement, or reopen the exercise.`,
        change: { type: "rotateExercise", slotID: slot.id, exerciseName: slot.exerciseName },
      });
      continue;
    }
    // rotationCandidateAvailable === false suppresses the weekly rotation:
    // same principle as the capacity availability gate — a recommendation the
    // apply path cannot resolve must not nag forever. null/undefined (legacy
    // snapshot) keeps the old behavior.
    if (slot.prescriptionStyle === "maxEffort" && slot.rotationCandidateAvailable !== false) {
      // First qualifying session wins — stop there instead of materializing
      // every match across years of history (mirrors native lazy .first).
      let latest = null;
      for (const session of newest) {
        if (session.rotation === DELOAD_WEEK) continue;
        const exercise = (session.exercises || []).find((candidate) => candidate.slotID === slot.id);
        // Only work PERFORMED under a max-effort prescription counts as an
        // exposure: a peak single logged while the slot ran another style (or
        // before it became maxEffort) must not rotate the slot away. The
        // entry's stamped style is the session-time truth. Only the entry
        // matters from here — the recommendation id is session-free.
        const completedSingle = exercise?.prescriptionStyle === "maxEffort"
          && (exercise.sets || []).some((set) => !set.isWarmup
            && set.completed !== false && set.actualReps === 1
            && countsAsPrescribedWork(set.prescriptionBlock));
        if (completedSingle) { latest = exercise; break; }
      }
      if (latest?.exerciseName === slot.exerciseName) {
        result.push({
          // The id carries only portable components (cycle/rotation evidence
          // key + slot id) — NEVER the session id, which is an IndexedDB
          // autoincrement locally but a UUID natively and after any backup
          // restore, so embedding it resurfaces dismissed recommendations.
          id: `program.slot.rotate.max-effort-weekly.v${COACHING_RULE_VERSION}:${evidenceKey}-${slot.id}`,
          ruleID: `program.slot.rotate.max-effort-weekly.v${COACHING_RULE_VERSION}`, priority: 65,
          title: `Rotate ${slot.exerciseName}`,
          explanation: `The latest completed max-effort single used ${slot.exerciseName}. Rotate to another special exercise before the next max-effort day so the effort stays specific without repeatedly testing the same lift.`,
          change: { type: "rotateExercise", slotID: slot.id, exerciseName: slot.exerciseName },
        });
        continue;
      }
    }
    const threshold = slot.role === "accessory" ? ACCESSORY_STALL_ROTATION_THRESHOLD : LIFT_STALL_ROTATION_THRESHOLD;
    const stalls = Math.max(0, slot.stallCount || 0);
    if (stalls < threshold) continue;
    result.push({
      id: `program.slot.rotate.stalled.v${COACHING_RULE_VERSION}:${evidenceKey}-${slot.id}`,
      ruleID: `program.slot.rotate.stalled.v${COACHING_RULE_VERSION}`, priority: 60,
      title: `${slot.exerciseName} is stuck`,
      explanation: `${slot.exerciseName} has ${stalls} exposure${stalls === 1 ? "" : "s"} on record without meeting its prescription, so it is being retried rather than added to. Rotating to a compatible variation of the same movement is the usual answer before the weight gets cut.`,
      change: { type: "rotateExercise", slotID: slot.id, exerciseName: slot.exerciseName },
    });
  }
  return result;
}

// The vertical pull belongs at the lift tier (issue #126): current templates
// train pull-ups as programmed double-progression work that earns load at the
// top of its rep window — never as an accessory buried under the press, and
// never only as a machine stack. A program instantiated before that change
// still carries the old shape, and no migration rewrites an authored program,
// so the coach offers the upgrade instead: one recommendation per day whose
// ONLY vertical pull is accessory work. The evidence key is
// rotation-independent — a structural fact, not a per-rotation reading — so
// one dismissal silences it for good, and applying removes the condition.
// Mirrored 1:1 in CoachingEngine.verticalPullPromotions.
export function verticalPullPromotions(program) {
  const result = [];
  const byDay = new Map();
  for (const slot of program.slots || []) {
    if (!byDay.has(slot.dayIndex)) byDay.set(slot.dayIndex, []);
    byDay.get(slot.dayIndex).push(slot);
  }
  for (const dayIndex of [...byDay.keys()].sort((a, b) => a - b)) {
    const slots = byDay.get(dayIndex);
    const lifts = slots.filter((slot) => slot.role !== "accessory");
    if (!lifts.length || lifts.some((slot) => slot.pattern === "verticalPull")) continue;
    // Sorted by slot id: the snapshot is built in day-record order, and the
    // recommendation id derives from these ids — reordering the same slots
    // must not re-emit a dismissed offer.
    const pulls = slots.filter((slot) =>
      slot.role === "accessory" && slot.pattern === "verticalPull" && !slot.exerciseIsShelved)
      .sort((a, b) => String(a.id).localeCompare(String(b.id)));
    if (!pulls.length) continue;
    const names = pulls.map((slot) => slot.exerciseName);
    const key = `day${dayIndex}:${pulls.map((slot) => slot.id).join(",")}`;
    result.push({
      id: `program.day.vertical-pull-tier.v1:${key}`,
      ruleID: "program.day.vertical-pull-tier.v1", priority: 55,
      title: "Train the pull as lift work",
      explanation: `This day's only vertical pull is accessory work (${names.join(", ")}). Pulling is main work: retire the accessory and train pull-ups as a programmed lift on a rep window that earns load at the top — the same shape new programs start with.`,
      change: { type: "promoteVerticalPull", dayIndex, accessorySlotIDs: pulls.map((slot) => slot.id), accessoryNames: names },
    });
  }
  return result;
}

// First adaptive stage inside Progressive Barbell Strength. A single miss is
// noise: linear progression already retries three misses and rebuilds the base
// by 10%. Once that rebuild is visible, an upper press may keep the same
// per-exposure loading cadence while changing only 3x5 -> 5x3. Squat and pull
// transitions need light-day/frequency semantics and are intentionally not
// guessed here. Mirrored in CoachingEngine.linearStageSuggestions.
function linearStageSuggestions(program, sessions, evidenceKey) {
  const upperPresses = new Set(["horizontalPress", "verticalPress"]);
  const orderedSessions = [...sessions].sort((a, b) => epoch(b.date) - epoch(a.date));
  return (program.slots || []).flatMap((slot) => {
    if (slot.prescriptionStyle !== "linearFives" || !upperPresses.has(slot.pattern)
        || slot.capacityManaged === false || (slot.maximumSets || DEFAULT_MAXIMUM_SETS) < 5
        || slot.workingSets !== 3 || slot.workingReps !== 5
        || !(slot.baseWeightLb > 0)) return [];
    const slotHistory = orderedSessions.flatMap((session) => {
      const exercise = (session.exercises || []).find((candidate) =>
        candidate.slotID === slot.id);
      return exercise ? [{ sessionID: session.id, exercise }] : [];
    });
    const exposures = [];
    for (const entry of slotHistory) {
      if (entry.exercise.prescriptionStyle !== "linearFives") break;
      const { exercise } = entry;
      const prescribed = (exercise.sets || []).filter((set) =>
        !set.isWarmup && countsAsPrescribedWork(set.prescriptionBlock));
      const plannedWeight = exercise.plannedWeightLb
        ?? Math.max(0, ...prescribed.map((set) => set.plannedWeightLb || 0));
      const plannedSets = exercise.plannedSets || 0;
      const setRepTargets = [...new Set(prescribed
        .map((set) => set.plannedReps).filter(Number.isFinite))];
      const plannedReps = exercise.plannedReps
        ?? (setRepTargets.length === 1 ? setRepTargets[0] : null);
      // Unknown/legacy plan data breaks the proof. Do not discard it and join
      // two failure runs that were never observed as consecutive.
      if (!(plannedWeight > 0) || plannedSets !== 3 || plannedReps !== 5) break;
      const metSets = prescribed.filter((set) => set.completed !== false && atPlan(set)).length;
      exposures.push({ sessionID: entry.sessionID, plannedWeight, missed: metSets < plannedSets });
    }
    const missesNeeded = linearRule("linearFives", null).stallLimit;
    if (exposures.length < missesNeeded) return [];
    const attempts = exposures.slice(0, missesNeeded);
    const weights = attempts.map((attempt) => attempt.plannedWeight);
    const lightest = Math.min(...weights), plannedWeight = Math.max(...weights);
    if (!attempts.every((attempt) => attempt.missed)
        || plannedWeight - lightest >= 0.01
        || slot.baseWeightLb > plannedWeight * 0.925) return [];
    return [{
      // Portable components only (cycle/rotation evidence key + slot id) —
      // NEVER a session id, which is an IndexedDB autoincrement here but a
      // UUID natively and is rewritten by any backup restore, resurfacing
      // dismissed recommendations. Staleness is already guarded by the
      // change's expectedBaseWeightLb. Mirrors CoachingEngine.
      id: `program.slot.linear-triples.v1:${evidenceKey}-${slot.id}`,
      ruleID: "program.slot.linear-triples.v1", priority: 65,
      title: `Move ${slot.exerciseName} to triples`,
      explanation: `${slot.exerciseName}'s linear base was rebuilt from ${trim(plannedWeight)} to ${trim(slot.baseWeightLb)} lb after the last prescription was not met. Keep session-to-session loading, but change this slot from 3x5 to 5x3 so only rep structure changes.`,
      change: {
        type: "useLinearTriples", slotID: slot.id, exerciseName: slot.exerciseName,
        expectedBaseWeightLb: slot.baseWeightLb,
      },
    }];
  });
}

function coachingRecommendations(program, latest, previousReadiness, greenRotationStreak, sessions, intervals = []) {
  if (!latest) return [];
  const evidenceKey = `c${latest.key.cycleNumber}-r${latest.key.rotation}`;
  // Rotation suggestions are program hygiene, not capacity: a slot pointing at
  // a shelved exercise or stuck retrying the same weight is wrong at every
  // readiness level, so these are offered alongside the readiness verdict
  // rather than gated behind a green streak. They sort below every readiness
  // rule, so the light stays the headline.
  const programChanges = [
    ...rotationSuggestions(program, sessions, evidenceKey),
    ...linearStageSuggestions(program, sessions, evidenceKey),
    ...verticalPullPromotions(program),
  ];
  // Ordinal tiebreak (see rotationSuggestions): the surfaced-first ordering
  // must be locale-independent and identical to Swift's.
  const byPriority = (a, b) => b.priority - a.priority || (b.id < a.id ? -1 : b.id > a.id ? 1 : 0);
  const decided = (recommendation) => [recommendation, ...programChanges].sort(byPriority);
  // A second consecutive red rotation escalates: one bad rotation is noise,
  // two in a row is a trend, and the 25% cut has already been tried without
  // restoring output. Cuts volume while KEEPING frequency (Rogerson 2024) —
  // the rotation still runs, it just carries less work.
  //
  // Deliberately does NOT jump the program to its scheduled deload week:
  // skipping the peak would mark every wave-family slot as a missed peak and
  // start them toward a 10% rebuild, punishing a lifter twice. It leaves
  // main-lift LOAD alone for the same reason — a cycle is graded on the peak
  // work actually performed and no session records "this was a planned
  // deload", so lighter mains would read back as a failed peak. Cutting
  // accessory SETS is invisible to double progression, which grades reps at a
  // held weight.
  if (latest.readiness === "red" && previousReadiness === "red") return decided({
    id: `readiness.red.persistent.recovery-rotation.v${COACHING_RULE_VERSION}:${evidenceKey}`,
    ruleID: `readiness.red.persistent.recovery-rotation.v${COACHING_RULE_VERSION}`, priority: 110,
    title: "Run a recovery rotation",
    explanation: "Two rotations in a row are red and the lighter rotation did not restore output. Hold main-lift loading and cut accessory sets about 50% for one rotation, keeping every session.",
    change: { type: "reduceAccessoryVolume", percent: 50 },
  });
  if (latest.readiness === "red") return decided({
    id: `readiness.red.reduce-accessories.v${COACHING_RULE_VERSION}:${evidenceKey}`,
    ruleID: `readiness.red.reduce-accessories.v${COACHING_RULE_VERSION}`, priority: 100,
    title: "Run one lower-volume rotation",
    explanation: "Repeated output markers are red. Hold main-lift loading and cut accessory sets about 25% for one rotation.",
    change: { type: "reduceAccessoryVolume", percent: 25 },
  });
  if (latest.readiness === "yellow") return decided({
    id: `readiness.yellow.hold.v${COACHING_RULE_VERSION}:${evidenceKey}`,
    ruleID: `readiness.yellow.hold.v${COACHING_RULE_VERSION}`, priority: 80,
    title: "Hold the current prescription", explanation: latest.reasons[0] || "Another exposure is needed before adding work.",
    change: { type: "hold" },
  });
  if (greenRotationStreak < 2) return [...programChanges].sort(byPriority);
  const budgets = [["verticalPull", 3], ["kneeFlexion", 3], ["shoulderStability", 2], ["adductor", 2], ["core", 4]];
  const planned = {};
  for (const slot of program.slots || []) planned[slot.pattern] = (planned[slot.pattern] || 0) + slot.plannedSets;
  const capacity = Math.max(0, program.maximumAddedSetsPerRotation ?? 6);
  let changes = 0;
  const result = [...programChanges];
  const capacityAdjustments = [];
  const capacityEvidence = [];
  const blockedEvidence = [];
  for (const [pattern, target] of budgets) {
    const current = planned[pattern] || 0;
    // capacity 0 is the athlete's opt-out of automatic capacity management —
    // no additions AND no blocked notices.
    if (current >= target || capacity <= 0) continue;
    const slot = (program.slots || []).find((candidate) => candidate.pattern === pattern
      && candidate.capacityManaged !== false && !candidate.isMain
      && supportsAddedCapacity(candidate)
      && candidate.plannedSets < (candidate.maximumSets || DEFAULT_MAXIMUM_SETS));
    let dayIndex = null;
    if (!slot) {
      // A PERMANENTLY blocked floor is reported even when this rotation's
      // budget is already spent — that is the whole point of the notice; a
      // merely-unbudgeted fillable floor just waits for the next rotation.
      if (program.patternsWithAvailableExercise
          && !program.patternsWithAvailableExercise.includes(pattern)) {
        blockedEvidence.push(`${movementPatternName(pattern)} ${current}/${target} — no compatible exercise available`);
        continue;
      }
      dayIndex = preferredCoachingDay(pattern, program.slots || []);
      if (dayIndex === null) {
        blockedEvidence.push(`${movementPatternName(pattern)} ${current}/${target} — no eligible day (technique/explosive)`);
        continue;
      }
    }
    if (changes >= capacity) continue;
    const amount = Math.min(target - current, capacity - changes);
    if (slot) {
      const add = Math.min(amount, (slot.maximumSets || DEFAULT_MAXIMUM_SETS) - slot.plannedSets);
      if (add <= 0) continue;
      capacityAdjustments.push({ type: "addSet", slotID: slot.id, exerciseName: slot.exerciseName, count: add });
      capacityEvidence.push(`${movementPatternName(pattern)} ${current}/${target} → +${add}`);
      changes += add;
    } else {
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
  if (blockedEvidence.length) result.push({
    id: `capacity.rotation-plan.blocked.v${COACHING_RULE_VERSION}:${evidenceKey}`,
    ruleID: `capacity.rotation-plan.blocked.v${COACHING_RULE_VERSION}`, priority: 39,
    title: "Volume floors need attention",
    explanation: `Two rotations were green, but some movement floors cannot be raised automatically: ${blockedEvidence.join("; ")}.`,
    change: { type: "hold" },
  });
  const shorter = shorterSpacingTrial(sessions, intervals);
  if (shorter !== null) result.push({
    id: `cadence.shorter-trial.v${COACHING_RULE_VERSION}:${evidenceKey}`,
    ruleID: `cadence.shorter-trial.v${COACHING_RULE_VERSION}`, priority: 20,
    title: "A shorter recovery trial is supported",
    explanation: `Recent exposures stayed green at the observed spacing. Try the next session after ${shorter} days once, then reassess output.`,
    change: { type: "tryShorterSpacing", days: shorter },
  });
  return result.sort(byPriority);
}

export function evaluateCoaching(program, sessions, reliableHistoryStart = null, intervals = []) {
  const reliable = reliableHistoryStart == null ? -Infinity : epoch(reliableHistoryStart);
  // A session banked inside an active-recovery span is off-program work
  // (INV-RECOVERY-WORK-IS-OFF-PROGRAM): completion already refused to advance
  // the schedule for it, so letting it complete a rotation or seed a
  // readiness baseline here would grade the program on work the program
  // never prescribed. Mirrors CoachingEngine.evaluate.
  const relevant = sessions.filter((session) => session.completed !== false
    && session.programID === program.id && epoch(session.date) >= reliable
    && !isOffProgramTime(epoch(session.date), intervals))
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
    // A rotation must be judged against the program as it stood WHEN IT WAS
    // RUN, not as it stands today. Programs legitimately gain and lose days, and
    // reading today's day list back over old rotations made every one of them
    // permanently "in progress" for work that was actually finished. Only the
    // CURRENT rotation is measured against the live program; a rotation the
    // schedule has moved past ran the days it ran.
    const isCurrent = group === ordered[ordered.length - 1];
    // A closed rotation that DID meet today's day set is genuinely complete and
    // behaves normally. Only one that falls short is reported as-run — its
    // shortfall may be a program that has since changed shape, which is
    // unknowable from here, so it is shown as history but never trusted as a
    // verified baseline.
    const ran = [...new Set(group.sessions.map((s) => s.dayIndex))];
    const shortfall = !program.expectedDayIndexes.every((d) => ran.includes(d));
    const asRun = !isCurrent && shortfall;
    const assessment = assessCoachingRotation(group.key, group.sessions,
      asRun ? ran : [...program.expectedDayIndexes], priorPerformance, priorReadiness, asRun);
    rotations.push(assessment);
    // Only a rotation VERIFIED complete against a known day set may seed the
    // next comparison. An as-run rotation is complete by construction.
    if (assessment.isComplete && !assessment.judgedAsRun) {
      priorPerformance = performanceBySlot(group.sessions);
      priorReadiness = assessment.readiness;
    }
  }
  // Streaks and capacity plans require verified rotations only.
  const completed = rotations.filter((rotation) => rotation.isComplete && !rotation.judgedAsRun);
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
    // The rotation before the latest verified one, so a red that persists can
    // escalate past a red that is one bad week.
    recommendations: coachingRecommendations(program, completed.at(-1),
      completed.at(-2)?.readiness ?? "unknown", greenRotationStreak, relevant, intervals),
  };
}

// ---- Restore preview: per-item named diff ----
// Mirrors CadenceCore's BackupContract.NamedEntity family. `id` is the store
// identity (a gym/session/program's own id; an exercise/track's own name,
// since neither has a separate id), `name` is what the user reads, and
// `signature` is a caller-built fingerprint of the remaining fields —
// callers own how that's derived per collection so this stays a generic
// id/name/signature diff.

// Classifies each incoming entity against the current store's matching id:
// an id absent from the current store is new; a matching id whose name and
// signature both match is unchanged; anything else — a rename or any other
// field edit — is changed.
//
// `includeRemoved` decides whether a current id the bundle omits is reported
// as `removed`. Every collection's restore write clears the store and
// re-inserts only the bundle's records, so an omitted id is genuinely
// dropped — pass `false` only for a collection whose write instead upserts
// by id/name and never deletes.
export function namedRestoreDiff(current, incoming, includeRemoved = true) {
  const byID = new Map(current.map((entity) => [entity.id, entity]));
  const matchedIDs = new Set();
  const result = incoming.map((entity) => {
    matchedIDs.add(entity.id);
    const existing = byID.get(entity.id);
    if (!existing) return { name: entity.name, id: entity.id, status: "new" };
    const unchanged = existing.name === entity.name && existing.signature === entity.signature;
    return { name: entity.name, id: entity.id, status: unchanged ? "unchanged" : "changed" };
  });
  if (!includeRemoved) return result;
  for (const entity of current) {
    if (!matchedIDs.has(entity.id)) result.push({ name: entity.name, id: entity.id, status: "removed" });
  }
  return result;
}

// Per-collection named restore diff for the five collections a restore
// preview names individually: exercises, lift tracks, gyms, sessions, and
// programs.
export function namedRestorePreview({
  currentExercises, incomingExercises, currentTracks, incomingTracks, currentGyms, incomingGyms,
  currentSessions, incomingSessions, currentPrograms, incomingPrograms,
  includeRemovedExercises = true,
}) {
  return {
    exercises: namedRestoreDiff(currentExercises, incomingExercises, includeRemovedExercises),
    tracks: namedRestoreDiff(currentTracks, incomingTracks),
    gyms: namedRestoreDiff(currentGyms, incomingGyms),
    sessions: namedRestoreDiff(currentSessions, incomingSessions),
    programs: namedRestoreDiff(currentPrograms, incomingPrograms),
  };
}

// True only when every classified item across all five collections is
// unchanged — the signal a restore UI uses to skip its destructive confirm
// gate entirely.
export function isNamedRestoreNoOp(preview) {
  return [preview.exercises, preview.tracks, preview.gyms, preview.sessions, preview.programs]
    .every((collection) => collection.every((item) => item.status === "unchanged"));
}

// The registered ad-hoc activity kinds (#166) — real physical work logged as
// one completed, off-program conditioning session on the same timeline as
// training. Wood splitting is the first; a future kind (mountain biking,
// hiking, climbing, portaging, …) is added here deliberately, with its own
// typed facts, seeded exercise, and a backup-contract version bump — never
// inferred from an exercise name. Mirrors native `ActivityKind`.
export const ACTIVITY_EXERCISE_NAMES = { woodSplitting: "Wood Splitting" };
// Derived, never hand-maintained: one registry, so the validator whitelist
// and the name resolver cannot drift apart.
export const ACTIVITY_KINDS = Object.keys(ACTIVITY_EXERCISE_NAMES);
// Only a REGISTERED kind resolves a name — the same whitelist the backup
// validator uses. A bare `ACTIVITY_EXERCISE_NAMES[kind]` would also answer for
// inherited Object keys ("constructor", "toString"), handing a caller a
// function where native's enum can only ever return a real name.
export const activityExerciseName = (kind) =>
  (ACTIVITY_KINDS.includes(kind) ? ACTIVITY_EXERCISE_NAMES[kind] : null);
// The recorded session-RPE contract, one spelling for the validator and the
// workload math. Mirrors native `ActivityWorkload.sessionRPERange`.
export const ACTIVITY_SESSION_RPE = { min: 1, max: 10 };

// Session-RPE workload for ad-hoc activity sessions (#166): duration minutes
// × session RPE, in arbitrary units. Relative session load, never barbell
// tonnage (INV-WOOD-WORK-IS-NOT-LIFTING-VOLUME). RPE follows the recorded
// contract, 1.0–10.0 inclusive; a missing or out-of-contract input yields
// null, not an estimate. Mirrors native `ActivityWorkload`.
export function activityWorkload(durationSeconds, sessionRPE) {
  if (!Number.isFinite(durationSeconds) || durationSeconds <= 0) return null;
  if (!Number.isFinite(sessionRPE)
    || sessionRPE < ACTIVITY_SESSION_RPE.min || sessionRPE > ACTIVITY_SESSION_RPE.max) return null;
  const durationMinutes = durationSeconds / 60;
  return { durationMinutes, sessionRPE, arbitraryUnits: durationMinutes * sessionRPE };
}
