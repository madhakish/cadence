// Port of the CadenceCore XCTest suite. Run: node tests/core.test.mjs
// Keeps the JS math in lockstep with the Swift source of truth.
import * as C from "../js/core.js";

let pass = 0, fail = 0;
const approx = (a, b, eps = 1e-9) => Math.abs(a - b) <= eps;
function ok(cond, msg) { if (cond) { pass++; } else { fail++; console.error("FAIL:", msg); } }
function eq(a, b, msg) { ok(a === b, `${msg} (got ${a}, want ${b})`); }
function near(a, b, eps, msg) { ok(approx(a, b, eps), `${msg} (got ${a}, want ${b}±${eps})`); }
const kgPerSide = (sol) => sol.perSide.reduce((s, pc) => s + pc.plate.value * pc.count, 0);

// ---- Units ----
near(C.kgFromLb(C.lbFromKg(42.5)), 42.5, 1e-9, "kg/lb round trip");
near(C.lbFromKg(20), 44.0924, 0.001, "20kg→lb");
near(C.kgFromLb(45), 20.4117, 0.001, "45lb→kg");
near(C.toLb(100, "lb"), 100, 1e-9, "toLb lb");
near(C.toLb(100, "kg"), 220.462, 0.001, "toLb kg");
eq(C.trim(232.0), "232", "trim integer");
eq(C.trim(232.39), "232.4", "trim 1dp");
eq(C.trim(2.5, 2), "2.5", "trim 2dp trailing zero");
eq(C.trim(1.25, 2), "1.25", "trim 2dp");
eq(C.both(232), "232 lb / 105.2 kg", "both format");
eq(C.unitFormat("lbPrimary", 232), "232 lb", "lbPrimary");
eq(C.unitFormat("kgPrimary", 232), "105.2 kg", "kgPrimary");
eq(C.unitFormat("both", 232), "232 lb / 105.2 kg", "both mode");
eq(C.primaryUnit("kgPrimary"), "kg", "kg primary input unit");
eq(C.primaryUnit("both"), "lb", "both mode keeps lb input primary");

eq(C.resolveSetStatus(null, false), "planned", "legacy open set stays planned");
eq(C.resolveSetStatus(null, true), "completed", "legacy banked set is completed");
eq(C.resolveSetStatus("skipped", true), "skipped", "explicit skipped status wins");
eq(C.normalizedSetFlags("grindy", true).join(","), "grindy,stopped early", "quality and stopped-early normalize independently");
eq(C.setQuality(["wobble", "stopped early"]), "wobble", "quality resolves from observations");

// ---- Rounding ----
eq(C.roundTo(192.5, 5), 195, "round 192.5");
eq(C.roundTo(246.75, 5), 245, "round 246.75");
eq(C.roundTo(162.75, 5), 165, "round 162.75");

// ---- Bar-loadable rounding (per-side snaps to the step, no lonely 2.5) ----
eq(C.barLoadable(150, 45, 5), 155, "150 on 45 bar → 155 (45+10/side)");
eq(C.barLoadable(155, 45, 5), 155, "155 already bar-loadable");
eq(C.barLoadable(145, 45, 5), 145, "145 already bar-loadable");
eq(C.barLoadable(160, 45, 5), 165, "160 → 165");
eq(C.barLoadable(100, 45, 5), 105, "100 → 105");
eq(C.barLoadable(30, 45, 5), 45, "target below bar → bar weight");

// ---- Plate math ----
let s = C.solve(135, C.BARS.bar45lb, C.STANDARD_LB);
near(s.totalLb, 135, 1e-9, "135 total");
ok(!s.isOffTarget, "135 on target");
eq(s.perSide.length, 1, "135 one denom");
eq(s.perSide[0].plate.value, 45, "135 uses 45");
eq(s.perSide[0].count, 1, "135 one plate");

s = C.solve(225, C.BARS.bar45lb, C.STANDARD_LB);
near(s.totalLb, 225, 1e-9, "225 total");
eq(s.perSide[0].plate.value, 45, "225 uses 45");
eq(s.perSide[0].count, 2, "225 two 45s");

s = C.solve(232, C.BARS.bar45lb, C.STANDARD_KG);
near(s.totalLb, 232.39, 0.01, "232 kg total");
ok(!s.isOffTarget, "232 on target");
near(kgPerSide(s), 42.5, 1e-9, "232 → 42.5kg/side");
near(C.kgFromLb(s.totalLb), 105.41, 0.01, "232 kg readout");

let plates = [{ value: 45, unit: "lb" }, { value: 15, unit: "kg" }];
s = C.solve(200, C.BARS.bar45lb, plates);
near(s.totalLb, 201.14, 0.01, "mixed 200 total");
ok(!s.isOffTarget, "mixed 200 on target");
ok(new Set(s.perSide.map((pc) => pc.plate.unit)).size === 2, "mixed units on a side");

s = C.solve(156, C.BARS.bar45lb, [...C.STANDARD_LB, { value: 25, unit: "kg" }]);
eq(s.perSide.length, 1, "156 one denom");
eq(s.perSide[0].plate.unit, "kg", "156 picks kg 25");
ok(!s.isOffTarget, "156 on target");

s = C.solve(100, C.BARS.bar45lb, [{ value: 45, unit: "lb" }]);
near(s.totalLb, 135, 1e-9, "100→135");
ok(s.isOffTarget, "100 off target");
near(s.deviationLb, 35, 1e-9, "100 dev 35");

s = C.solve(40, C.BARS.bar45lb, C.STANDARD_LB);
ok(s.perSide.length === 0, "40 bar only");
near(s.totalLb, 45, 1e-9, "40→45");
ok(s.isOffTarget, "40 off target");

s = C.solve(137, C.BARS.bar45lb, [{ value: 45, unit: "lb" }]);
near(s.totalLb, 135, 1e-9, "137→135");
ok(!s.isOffTarget, "137 exactly 2lb off, no warn");

s = C.solve(95, C.BARS.bar45lb, C.STANDARD_LB);
eq(s.perSide.length, 1, "95 fewer plates");
eq(s.perSide[0].plate.value, 25, "95 uses one 25");

// Realistic loading: 220 on a 45# bar → 2× 20kg blue per side (~220.5), NOT the
// exact-but-ugly 45+35+5+2.5. Within the 2 lb band, fewest plates + one unit win.
s = C.solve(220, C.BARS.bar45lb, C.ALL_STANDARD);
// Heaviest first, competition style: 25+15 kg per side (~221.4), not 20×2
// and not the exact-but-awful 45+35+5+2.5 lb.
eq(s.perSide.length, 2, "220 two denoms, heaviest first");
eq(s.perSide[0].plate.value, 25, "220 leads with the 25kg");
eq(s.perSide[1].plate.value, 15, "220 fills with the 15kg");
ok(!s.isOffTarget, "220 within tolerance");
eq(new Set(s.perSide.map((pc) => pc.plate.unit)).size, 1, "220 no unit mix");

// Heaviest-first beats fewest-plates: 255 is 45+45+10+5 per side, never 35×3
// (equal weight, fewer plates, but nobody skips the 45s).
s = C.solve(255, C.BARS.bar45lb, C.STANDARD_LB);
eq(s.perSide.map((pc) => `${pc.plate.value}x${pc.count}`).join(" "), "45x2 10x1 5x1", "255 loads the 45s first");
ok(!s.isOffTarget, "255 exact");

// Same principle mid-weight: 195 is 45+25+5, not 25×3.
s = C.solve(195, C.BARS.bar45lb, C.STANDARD_LB);
eq(s.perSide.map((pc) => `${pc.plate.value}x${pc.count}`).join(" "), "45x1 25x1 5x1", "195 loads the 45 first");

// 315 keeps a clean single-unit stack (3× 45), no kg/lb intermixing.
s = C.solve(315, C.BARS.bar45lb, C.ALL_STANDARD);
eq(s.perSide.length, 1, "315 one denom");
eq(s.perSide[0].plate.value, 45, "315 uses 45lb");
eq(s.perSide[0].count, 3, "315 three 45s");

// 405 is exactly 45×4/side: the greedy seed reaches it even though a naive
// search would exhaust its node budget in the 25kg branches and settle for a
// 25kg×2 + 35lb×2 frankenstack.
s = C.solve(405, C.BARS.bar45lb, C.ALL_STANDARD);
eq(s.perSide.length, 1, "405 one denom");
eq(s.perSide[0].plate.value, 45, "405 uses 45lb");
eq(s.perSide[0].count, 4, "405 four 45s");
near(s.deviationLb, 0, 1e-9, "405 exact");
eq(new Set(s.perSide.map((pc) => pc.plate.unit)).size, 1, "405 no unit mix");

let perSide = [
  { plate: { value: 45, unit: "lb" }, count: 1 },
  { plate: { value: 15, unit: "kg" }, count: 1 },
];
near(C.totalOnBar(C.BARS.bar45lb, perSide), 201.14, 0.01, "reverse mixed total");
near(C.kgFromLb(C.totalOnBar(C.BARS.bar45lb, perSide)), 91.23, 0.01, "reverse mixed kg");
near(C.totalOnBar(C.BARS.bar20kg, []), 44.09, 0.01, "reverse bar only 20kg");

s = C.solve(C.lbFromKg(100), C.BARS.bar20kg, C.STANDARD_KG);
near(s.deviationLb, 0, 1e-9, "100kg exact");
near(kgPerSide(s), 40, 1e-9, "100kg→40kg/side");

s = C.solve(140, C.BARS.bar45lb, C.STANDARD_LB, 10, 5);
eq(s.totalLb, 140, "collars count toward achieved weight");
eq(s.collarLb, 5, "collar weight retained");
eq(C.totalOnBar(C.BARS.bar45lb, s.perSide, 5), 140, "reverse mode counts collars");
let directional = C.solve(133, C.BARS.bar45lb, [{ value: 5, unit: "lb" }], 10, 0, "under");
ok(directional.totalLb <= 133 && directional.satisfiesPolicy, "never-over policy");
directional = C.solve(133, C.BARS.bar45lb, [{ value: 5, unit: "lb" }], 10, 0, "over");
ok(directional.totalLb >= 133 && directional.satisfiesPolicy, "never-under policy");
directional = C.solve(50, C.BARS.bar45lb, [{ value: 10, unit: "lb" }], 10, 0, "over");
eq(directional.totalLb, 65, "never-under searches past the unrestricted closest load");
ok(directional.satisfiesPolicy, "distant never-under candidate satisfies policy");
const tieRack = [{ value: 45, unit: "lb" }, { value: 25, unit: "lb" }, { value: 5, unit: "lb" }];
let options = C.prescriptionPlateOptions(200, C.BARS.bar45lb, tieRack, 10, 0, "closest", true);
eq(options.selected.totalLb, 205, "volume prescription tie selects heavier load");
eq(options.below.totalLb, 195, "prescription exposes nearest load below");
eq(options.above.totalLb, 205, "prescription exposes nearest load above");
options = C.prescriptionPlateOptions(200, C.BARS.bar45lb, tieRack, 10, 0, "closest", false);
eq(options.selected.totalLb, 195, "peak prescription tie selects lighter load");
options = C.prescriptionPlateOptions(200, C.BARS.bar45lb, tieRack, 10, 0, "under", true);
eq(options.selected.totalLb, 195, "explicit gym policy overrides phase tie-break");
s = C.solve(133, C.BARS.bar45lb, [{ value: 5, unit: "lb" }], 10, 0, "exact");
eq(s.satisfiesPolicy, false, "impossible exact load warns");
eq(s.totalLb, 135, "impossible exact load returns closest fallback");

// ---- Warmup ramp ----
let r = C.warmupRamp(245);
ok(JSON.stringify(r.map((x) => x.weightLb)) === JSON.stringify([45, 100, 135, 170, 210]), "ramp 245 weights");
ok(JSON.stringify(r.map((x) => x.reps)) === JSON.stringify([10, 5, 3, 2, 1]), "ramp 245 reps");
r = C.warmupRamp(65);
ok(JSON.stringify(r.map((x) => x.weightLb)) === JSON.stringify([45, 55]), "ramp 65");
r = C.warmupRamp(45);
ok(JSON.stringify(r.map((x) => x.weightLb)) === JSON.stringify([45]) && r[0].reps === 10, "ramp 45 bar only");
eq(C.programLoadStep(10, "dumbbell"), 5, "dumbbell program step capped per hand");
eq(C.programLoadStep(2.5, "dumbbell"), 2.5, "fine dumbbell step preserved");
eq(C.programLoadStep(10, "barbell"), 10, "barbell program step preserved");
eq(C.programPlanFor({ cycleNumber: 2, baseWeightLb: 55, nextPhase: 3, incrementLb: 0 }, 5, "dumbbell").weightLb,
  60, "DB Peak stays within one 5 lb rack jump of its volume base");
eq(C.programPlanFor({ cycleNumber: 2, baseWeightLb: 55, nextPhase: 3, incrementLb: 0 }, 5, "barbell").weightLb,
  65, "barbell Peak retains the normal wave percentage");
eq(C.resolvedPrescriptionStyle("automatic", "press", "main", "strength"), "wave", "automatic main strength uses wave");
eq(C.resolvedPrescriptionStyle("automatic", "hinge", "complementary", "strength"), "secondary", "automatic complementary uses lower-fatigue strategy");
eq(C.resolvedPrescriptionStyle("automatic", "press", "main", "hypertrophy"), "hypertrophy", "focus drives hypertrophy prescription");
eq(C.resolvedPrescriptionStyle("automatic", "olympic", "main", "strength"), "technique", "Olympic lift prioritizes technique");
let rolePlan = C.programPlanFor({ cycleNumber: 1, baseWeightLb: 200, nextPhase: 1, incrementLb: 0 }, 5,
  "barbell", "hinge", "complementary", "strength", "automatic");
eq(`${rolePlan.sets}x${rolePlan.reps}@${rolePlan.weightLb}`, "3x5@200", "complementary volume avoids a second 5x5");
let techniquePlan = C.programPlanFor({ cycleNumber: 1, baseWeightLb: 100, nextPhase: 3, incrementLb: 0 }, 5,
  "barbell", "olympic", "main", "strength", "automatic");
eq(`${techniquePlan.sets}x${techniquePlan.reps}@${techniquePlan.weightLb}`, "6x1@110", "Olympic peak is crisp singles");
const offsetConfig = { loadOffsetLb: 25, peakOffsetLb: 33, deloadMultiplier: 0.80 };
eq([1, 2, 3, 4].map((phase) => C.planForStyle(
  { cycleNumber: 2, baseWeightLb: 221, nextPhase: phase }, 5, "offsetWave", offsetConfig).weightLb).join(","),
"220,245,255,175", "offset wave derives every phase from the volume base");
const multiBlock = C.sessionPrescription(
  { cycleNumber: 2, baseWeightLb: 221, nextPhase: 3 }, 5, "barbell", "hinge", "main", "strength", "offsetWave",
  { ...offsetConfig, peakSingleEnabled: true, lastPeakSingleLb: 270, peakSingleIncrementLb: 5, phasePrimerEnabled: true }, 300);
eq(multiBlock.blocks.map((block) => block.kind).join(","), "primer,topSingle,work", "peak prescription separates primer, single, and work");
eq(multiBlock.blocks.map((block) => block.weightLb).join(","), "245,275,255", "peak block weights derive correctly");
const dbDouble = C.programPlanFor(
  { cycleNumber: 1, baseWeightLb: 55, nextPhase: 2 }, 5, "dumbbell", "press", "main", "strength", "doubleProgression",
  { workingSets: 5, minimumReps: 5, maximumReps: 8, currentReps: 5 });
eq(`${dbDouble.sets}x${dbDouble.reps}@${dbDouble.weightLb}`, "5x5@55", "DB double progression holds load and uses current reps");
r = C.dumbbellWarmupRamp(60);
ok(JSON.stringify(r.map((x) => x.weightLb)) === JSON.stringify([25, 35, 50]), "dumbbell ramp weights");
ok(JSON.stringify(r.map((x) => x.reps)) === JSON.stringify([10, 5, 2]), "dumbbell ramp reps");
for (let w = 50; w <= 500; w += 7.5) {
  for (const set of C.warmupRamp(w).slice(1)) ok(set.weightLb < w, `ramp ${w} below working`);
}

// ---- Program engine ----
let plan = C.planFor({ cycleNumber: 1, baseWeightLb: 210, nextPhase: 3, incrementLb: 10 });
eq(plan.weightLb, 245, "DL peak weight"); eq(plan.sets, 3, "DL peak sets");
eq(plan.reps, 3, "DL peak reps"); eq(plan.phase, 3, "DL peak phase");
plan = C.planFor({ cycleNumber: 1, baseWeightLb: 175, nextPhase: 2, incrementLb: 10 });
eq(plan.weightLb, 195, "SQ load weight"); eq(plan.sets, 5, "SQ load sets"); eq(plan.reps, 3, "SQ load reps");
plan = C.planFor({ cycleNumber: 1, baseWeightLb: 210, nextPhase: 1, incrementLb: 10 });
eq(plan.weightLb, 210, "volume = base"); eq(plan.sets, 5, "vol sets"); eq(plan.reps, 5, "vol reps");
plan = C.planFor({ cycleNumber: 1, baseWeightLb: 210, nextPhase: 4, incrementLb: 10 });
eq(plan.weightLb, 165, "deload weight"); eq(plan.sets, 3, "deload sets"); eq(plan.reps, 5, "deload reps");
ok(plan.weightLb / 210 >= 0.75 && plan.weightLb / 210 <= 0.80, "deload band");

let st = { cycleNumber: 1, baseWeightLb: 210, nextPhase: 1, incrementLb: 10 };
st = C.advancing(st, 1); eq(st.nextPhase, 2, "advance vol→load");
st = C.advancing(st, 2); eq(st.nextPhase, 3, "advance load→peak");
st = C.advancing(st, 3); eq(st.nextPhase, 4, "advance peak→deload");
eq(st.baseWeightLb, 210, "no mid-cycle base change"); eq(st.cycleNumber, 1, "no mid-cycle number change");
let lower = C.advancing({ cycleNumber: 1, baseWeightLb: 210, nextPhase: 4, incrementLb: 10 }, 4);
eq(lower.cycleNumber, 2, "rollover cycle"); eq(lower.baseWeightLb, 220, "rollover +10"); eq(lower.nextPhase, 1, "rollover→volume");
let upper = C.advancing({ cycleNumber: 1, baseWeightLb: 95, nextPhase: 4, incrementLb: 5 }, 4);
eq(upper.baseWeightLb, 100, "upper rollover +5");

eq(C.droppedLoad(232), 215, "drop 232");
eq(C.droppedLoad(100), 95, "drop 100");
eq(C.droppedLoad(50), 45, "drop never below bar");
eq(C.droppedLoad(45), 45, "drop at bar");
eq(C.droppedLoad(205, 5, 45, 10), 195, "configured lower-body drop step");
eq(C.droppedLoad(140, 5, 45, 5), 135, "configured upper-body drop step");
ok(C.droppedLoad(65) < 65 && C.droppedLoad(65) >= 45, "drop always drops above bar");
{
  // mirrors ProgramEngineTests.testDropLoadPlan…: unflagged working sets only,
  // each dropped from its OWN weight (back-offs never raised toward the top's drop)
  const plan = C.dropLoadPlan([
    { weightLb: 45, isWarmup: true, isFlagged: false },
    { weightLb: 300, isWarmup: false, isFlagged: false },
    { weightLb: 240, isWarmup: false, isFlagged: false },
    { weightLb: 240, isWarmup: false, isFlagged: true },
  ]);
  eq(plan.map((p) => p.index).join(","), "1,2", "plan targets unflagged working sets");
  eq(plan[0].weightLb, 280, "top set 300 drops to 280");
  eq(plan[1].weightLb, 225, "back-off 240 drops to 225, not raised to 280");
  eq(C.dropLoadPlan([{ weightLb: 225, isWarmup: false, isFlagged: true }]).length, 0, "all performed → empty plan");
}

// ---- PR detection ----
eq(C.inferredLoadBasis("barbell"), "totalBar", "barbell load basis inference");
eq(C.inferredLoadBasis("dumbbell"), "perImplement", "dumbbell load basis inference");
eq(C.loadVolume({ weightLb: 60, reps: 5, loadBasis: "perImplement", implementCount: 2 }), 600, "pair of dumbbells counts both implements");
eq(C.loadVolume({ weightLb: 60, reps: 5, isPerSide: true, loadBasis: "perImplement", implementCount: 1 }), 600, "unilateral reps count both sides");
eq(C.loadVolume({ weightLb: 40, reps: 8, loadBasis: "assisted", implementCount: 1 }), null, "assistance has no tonnage");

const dlHistory = [
  { weightLb: 221, reps: 3 }, { weightLb: 221, reps: 3 },
  ...Array(3).fill({ weightLb: 210, reps: 5 }),
  ...Array(3).fill({ weightLb: 221, reps: 2 }),
  ...Array(5).fill({ weightLb: 210, reps: 5 }),
];
const dlVolumes = [221 * 3, 221 * 3, 210 * 3 * 5 + 221 * 3 * 2, 210 * 5 * 5];

let ev = C.prEvaluate({
  exercise: "Deadlift",
  sessionSets: Array(5).fill({ weightLb: 232, reps: 3 }),
  historySets: dlHistory, historyVolumes: dlVolumes, historySchemes: ["1×3", "3×2", "5×5"],
});
let heaviest = ev.find((e) => e.kind === "heaviestSet");
ok(heaviest, "Jun7 heaviest exists");
eq(heaviest?.label, "232×5×3 — heaviest deadlift logged", "heaviest label");
ok(ev.some((e) => e.kind === "firstScheme"), "Jun7 first scheme");
ok(!ev.some((e) => e.kind === "volumePR"), "Jun7 not volume PR");

ev = C.prEvaluate({
  exercise: "Deadlift",
  sessionSets: [{ weightLb: 200, reps: 5 }],
  historySets: dlHistory, historyVolumes: dlVolumes, historySchemes: ["1×3", "3×2", "5×5", "1×5"],
});
ok(ev.length === 0, "nothing new → no events");

ev = C.prEvaluate({
  exercise: "Deadlift",
  sessionSets: Array(5).fill({ weightLb: 210, reps: 5 }),
  historySets: [{ weightLb: 221, reps: 3 }], historyVolumes: [663], historySchemes: ["1×3"],
});
ok(ev.some((e) => e.kind === "volumePR"), "volume PR detected");
ok(!ev.some((e) => e.kind === "heaviestSet"), "no heaviest when lighter");

ev = C.prEvaluate({
  exercise: "Back Squat",
  sessionSets: Array(5).fill({ weightLb: 175, reps: 5 }),
  historySets: [], historyVolumes: [], historySchemes: [],
});
ok(ev.some((e) => e.kind === "heaviestSet"), "first session heaviest");
ok(ev.some((e) => e.kind === "firstScheme"), "first session scheme");
ok(!ev.some((e) => e.kind === "volumePR"), "first session not volume PR");

ev = C.prEvaluate({
  exercise: "Deadlift", sessionSets: [{ weightLb: 220.462, reps: 1 }],
  historySets: [], historyVolumes: [], historySchemes: [],
  formatWeight: (lb) => `${C.trim(C.kgFromLb(lb))} kg`,
});
ok(ev.every((e) => e.label.includes("100 kg")), "PR labels honor the presentation-unit formatter");

let top = C.prTopScheme([...Array(5).fill({ weightLb: 175, reps: 5 }), { weightLb: 155, reps: 8 }]);
eq(top.weightLb, 175, "top weight group"); eq(top.sets, 5, "top sets"); eq(top.reps, 5, "top reps");

// ---- Adaptive program progression ----
const cleanPerf = { prescribedSets: 3, prescribedReps: 3, completedSets: 3, anyStoppedEarly: false, anyDroppedLoad: false, grindyOrWobbleSets: 0, topSetWeightLb: 206, topSetReps: 3 };
const liftState = () => ({ baseWeightLb: 175, estimatedMaxLb: 226, stallCount: 0, role: "main", lastIncrementLb: 0 });

// e1RM math
eq(C.epleyE1RM(225, 5), 262.5, "epley 225x5");
eq(C.smoothE1RM(0, 262.5), 262.5, "e1rm cold start");
eq(C.smoothE1RM(200, 300), 230, "e1rm smoothing 0.7/0.3");

// grading
eq(C.gradeCycle(cleanPerf), "success", "clean → success");
eq(C.gradeCycle({ ...cleanPerf, grindyOrWobbleSets: 1 }), "success", "1 grindy still success (boundary)");
eq(C.gradeCycle({ ...cleanPerf, grindyOrWobbleSets: 2 }), "hold", "2 grindy → hold");
eq(C.gradeCycle({ ...cleanPerf, completedSets: 2 }), "fail", "missed set → fail");
eq(C.gradeCycle({ ...cleanPerf, anyStoppedEarly: true }), "fail", "stopped early → fail");
eq(C.gradeCycle({ ...cleanPerf, anyDroppedLoad: true }), "fail", "dropped load → fail");
eq(C.gradeCycle({ ...cleanPerf, anyBelowPlanLoad: true }), "fail", "below-plan load → fail");
eq(C.earnsStandaloneTrackAdvance([cleanPerf]), true, "clean standalone exposure advances");
eq(C.earnsStandaloneTrackAdvance([cleanPerf, cleanPerf]), true, "duplicate clean sections are one successful exposure");
eq(C.earnsStandaloneTrackAdvance([cleanPerf, { ...cleanPerf, anyBelowPlanLoad: true }]), false, "adjusted occurrence holds standalone exposure");
eq(C.earnsStandaloneTrackAdvance([]), false, "no performed work never advances standalone track");

// belowPlanLoad: met within half a rounding step; a full step down is a drop (issue 18)
eq(C.belowPlanLoad(175, 175, 5), false, "at plan → met");
eq(C.belowPlanLoad(180, 175, 5), false, "heavier than plan is fine");
eq(C.belowPlanLoad(172.5, 175, 5), false, "half a step under is still met (boundary)");
eq(C.belowPlanLoad(172.4, 175, 5), true, "past half a step is a drop");
eq(C.belowPlanLoad(170, 175, 5), true, "a full plate step down is a drop");
eq(C.belowPlanLoad(100, null, 5), false, "no prescription → nothing to compare");
eq(C.belowPlanLoad(100, 0, 5), false, "zero plan → nothing to compare");

// belowPlanWork: the prescription is met by prescribedSets at-plan sets; extras are bonus
eq(C.belowPlanWork([175, 175, 175], 175, 3, 5), false, "all prescribed sets at plan → met");
eq(C.belowPlanWork([175, 175, 175, 155], 175, 3, 5), false, "lighter back-off after the planned work is bonus volume");
eq(C.belowPlanWork([100, 100, 100], 175, 3, 5), true, "whole lift performed light → below plan");
eq(C.belowPlanWork([175, 175, 155], 175, 3, 5), true, "one prescribed set cut down → below plan");
eq(C.belowPlanWork([100, 100, 100], null, 3, 5), false, "no prescription → nothing to compare");

// swapCompatible: swap-candidate filtering (issue 20) — mirrors SwapRulesTests.swift
{
  const backSquat = { name: "Back Squat", category: "Main", type: "barbell", movementGroup: "squat" };
  const frontSquat = { name: "Front Squat", category: "Main", type: "barbell", movementGroup: "squat" };
  const walkingLunges = { name: "Walking Lunges", category: "Accessory", type: "bodyweight", movementGroup: "squat" };
  const dbPress = { name: "Incline DB Press", category: "Main", type: "dumbbell", movementGroup: "press" };
  const machinePress = { name: "Machine Press", category: "Main", type: "machine", movementGroup: "press" };
  const bwPress = { name: "Pike Push-up", category: "Main", type: "bodyweight", movementGroup: "press" };
  const benchShelved = { name: "Barbell Bench", category: "Main", type: "barbell", movementGroup: "press", isShelved: true };
  const dips = { name: "Dips", category: "Accessory", type: "bodyweight", movementGroup: "press" };
  const chinups = { name: "Chin-ups", category: "Accessory", type: "bodyweight", movementGroup: "pull" };
  const pullups = { name: "Pull-ups", category: "Accessory", type: "bodyweight", movementGroup: "pull" };

  eq(C.swapCompatible(backSquat, frontSquat), true, "same tier/pattern/loadability → offered");
  eq(C.swapCompatible(chinups, pullups), true, "bodyweight→bodyweight is fine");
  eq(C.swapCompatible(walkingLunges, backSquat), false, "accessory can't jump to a main competition lift");
  eq(C.swapCompatible(dbPress, dips), false, "loaded press can't swap to an unloadable accessory");
  eq(C.swapCompatible(dbPress, bwPress), false, "loadability mismatch alone filters (same tier/group)");
  eq(C.swapCompatible(dbPress, machinePress), true, "equipment change within loadable types is fine");
  eq(C.swapCompatible(dbPress, benchShelved), false, "shelved is never offered");
  eq(C.swapCompatible(backSquat, dbPress), false, "different movement pattern");
  eq(C.swapCompatible(backSquat, backSquat), false, "never itself");
  eq(C.swapCompatible({ ...backSquat, movementGroup: "" }, frontSquat), false, "ungrouped lift offers no swaps");
}

// completionCommit: save-or-rollback boundary for banking (issue 19) —
// mirrors CompletionPersistenceTests.swift (same cases, same expectations)
{
  let saves = 0, rollbacks = 0, sideEffects = 0;
  C.completionCommit(() => { saves += 1; }, () => { rollbacks += 1; });
  eq(saves, 1, "committed once");
  eq(rollbacks, 0, "no rollback on success");

  let threw = null;
  try {
    C.completionCommit(() => { throw new Error("store down"); }, () => { rollbacks += 1; });
    sideEffects += 1; // everything after commit — the web analog of HealthKit/notifications
  } catch (e) { threw = e; }
  ok(threw && /store down/.test(threw.message), "the underlying failure propagates to the caller");
  eq(rollbacks, 1, "a failed save rolls back exactly once");
  eq(sideEffects, 0, "side effects after commit never run on failure");

  // Retryable: after a rolled-back failure, the same commit succeeds cleanly.
  let healthy = false;
  const attempt = () => C.completionCommit(() => { if (!healthy) throw new Error("store down"); }, () => { rollbacks += 1; });
  try { attempt(); } catch { /* expected */ }
  healthy = true;
  attempt();
  eq(rollbacks, 2, "only the failed attempts rolled back");

  // A rollback that itself throws must not mask the save failure.
  let masked = null;
  try {
    C.completionCommit(() => { throw new Error("store down"); }, () => { throw new Error("rollback exploded"); });
  } catch (e) { masked = e; }
  ok(masked && /store down/.test(masked.message), "the save failure propagates even when rollback throws");
}

// sessionTagCurrent: a session may advance the program only from its live position (issue 17)
eq(C.sessionTagCurrent(2, 1, 3, 2, 1, 3), true, "tag at the live position → current");
eq(C.sessionTagCurrent(1, 1, 3, 2, 1, 3), false, "stale cycle → not current");
eq(C.sessionTagCurrent(2, 1, 3, 2, 2, 3), false, "stale week → not current");
eq(C.sessionTagCurrent(2, 1, 3, 2, 1, 0), false, "stale day → not current");

// canResumeSession: compares the plan the session was BUILT from (snapshot)
// against the day's current plan — NOT the live exercises.
{
  const plan = ["Overhead Press", "Incline DB Press", "Dips"];
  eq(C.canResumeSession(2, 1, 3, 2, 1, 3, plan, plan), true, "same position + unchanged plan → resume");
  // Session-local edits (remove/swap) change live exercises, NOT the built-from
  // snapshot — so the customized open session still resumes (Codex case).
  eq(C.canResumeSession(2, 1, 3, 2, 1, 3, plan, plan), true, "session-local edit still resumes (snapshot unchanged)");
  // The reported bug: the PROGRAM day was edited, so the snapshot the session
  // was built from no longer equals the current plan → build fresh.
  eq(C.canResumeSession(2, 1, 3, 2, 1, 3, ["Overhead Press", "Chest-supported Row", "Dips"], plan), false, "program-edited plan → build fresh");
  eq(C.canResumeSession(2, 1, 2, 2, 1, 3, plan, plan), false, "different day → build fresh");
  eq(C.canResumeSession(1, 1, 3, 2, 1, 3, plan, plan), false, "stale cycle → build fresh");
  eq(C.canResumeSession(2, 2, 3, 2, 1, 3, plan, plan), false, "stale week → build fresh");
  eq(C.canResumeSession(2, 1, 3, 2, 1, 3, [], plan), false, "pre-snapshot session (no plan names) → build fresh");
}

// RestClock.add shrinks as well as extends, flooring at 0 (subtract control)
{
  const s = C.restClockStart(120, 1000);
  eq(C.restClockRemaining(C.restClockAdd(s, -60), 1000), 60, "−60 shrinks the rest");
  eq(C.restClockRemaining(C.restClockAdd(s, -300), 1000), 0, "over-subtract floors at 0");
}

// issue 18 repro: 3×3 prescribed at 175 (e1RM 300) but performed at 100 must
// not grade success, reset the stall, or raise the base weight.
const belowPlanPerf = { ...cleanPerf, anyBelowPlanLoad: true, topSetWeightLb: 100 };
const rBelow = C.advanceCycleLift({ baseWeightLb: 175, estimatedMaxLb: 300, stallCount: 0, role: "main", lastIncrementLb: 0 }, belowPlanPerf, "strength", 5);
eq(rBelow.grade, "fail", "below-plan cycle fails");
eq(rBelow.state.baseWeightLb, 175, "no bump off work that wasn't done");
eq(rBelow.state.stallCount, 1, "below-plan counts as a stall, not a reset");
eq(rBelow.state.lastIncrementLb, 0, "no increment recorded");

// clean cycle → tapered increment
let pres = C.advanceCycleLift(liftState(), cleanPerf, "strength", 5);
eq(pres.grade, "success", "advance clean grade");
eq(pres.state.baseWeightLb, 180, "clean cycle adds one plate");
eq(pres.state.stallCount, 0, "clean resets stall");
eq(pres.state.lastIncrementLb, 5, "increment recorded");
eq(pres.note, "Clean peak — add 5 lb next cycle.", "clean result explains next-cycle change");

// grindy → HOLD
pres = C.advanceCycleLift(liftState(), { ...cleanPerf, grindyOrWobbleSets: 3 }, "strength", 5);
eq(pres.grade, "hold", "grindy → hold grade");
eq(pres.state.baseWeightLb, 175, "hold keeps weight");
eq(pres.state.stallCount, 1, "hold increments stall");

// two stalls → auto deload −10%
let st1 = C.advanceCycleLift(liftState(), { ...cleanPerf, grindyOrWobbleSets: 3 }, "strength", 5).state; // stall 1
let st2 = C.advanceCycleLift(st1, { ...cleanPerf, completedSets: 1 }, "strength", 5);                     // stall 2 → deload
eq(st2.state.baseWeightLb, 160, "two stalls → −10% deload (175→160)");
eq(st2.state.stallCount, 0, "deload resets stall");
ok(/deloaded/.test(st2.note || ""), "deload note present");

// taper: far below ceiling bumps, near/over ceiling does not
eq(C.taperedIncrement(150, 226, "strength", 5), 5, "far below ceiling → +5");
eq(C.taperedIncrement(200, 226, "strength", 5), 0, "near ceiling → 0 (tapered out)");
eq(C.taperedIncrement(210, 226, "strength", 5), 0, "over ceiling → 0");

// maintain never increments
pres = C.advanceCycleLift(liftState(), cleanPerf, "maintain", 5);
eq(pres.state.baseWeightLb, 175, "maintain holds weight on success");
eq(pres.state.stallCount, 0, "maintain success resets stall");

// accessory double progression
let acc = { sets: 3, minReps: 8, maxReps: 12, currentReps: 12, weightLb: 50, incrementLb: 5, stallCount: 0 };
let ac = C.advanceAccessory(acc, { completedSets: 3, minRepsAchieved: 12, anyStoppedEarly: false });
ok(ac.weightLb === 55 && ac.currentReps === 8, "accessory at max reps → +weight, reset reps");
ac = C.advanceAccessory({ ...acc, currentReps: 10 }, { completedSets: 3, minRepsAchieved: 10, anyStoppedEarly: false });
ok(ac.weightLb === 50 && ac.currentReps === 11, "accessory below max → +1 rep, hold weight");
ac = C.advanceAccessory({ ...acc, currentReps: 10 }, { completedSets: 2, minRepsAchieved: 10, anyStoppedEarly: false });
ok(ac.weightLb === 50 && ac.currentReps === 10 && ac.stallCount === 1, "accessory miss → hold + stall");
ac = C.advanceAccessory({ ...acc, currentReps: 10 }, { completedSets: 3, minRepsAchieved: 10, anyStoppedEarly: false, performedAtPlannedLoad: false });
ok(ac.weightLb === 50 && ac.currentReps === 10 && ac.stallCount === 1, "adjusted-lower accessory work never earns progression");
ac = C.advanceAccessory({ ...acc, currentReps: 10 }, { completedSets: 3, minRepsAchieved: 10, anyStoppedEarly: false, grindyOrWobbleSets: 2 });
ok(ac.weightLb === 50 && ac.currentReps === 10 && ac.stallCount === 1, "poor-quality accessory work holds progression");
// bodyweight/timed accessory (0 increment) climbs reps past max — no reset, no weight added
let bw = { sets: 3, minReps: 8, maxReps: 12, currentReps: 12, weightLb: 0, incrementLb: 0, stallCount: 0 };
let bwa = C.advanceAccessory(bw, { completedSets: 3, minRepsAchieved: 12, anyStoppedEarly: false });
ok(bwa.weightLb === 0 && bwa.currentReps === 13 && bwa.stallCount === 0, "bodyweight accessory climbs past max, no reset");

// ---- plate colours (gym scheme) ----
eq(C.plateColorToken({ value: 55, unit: "lb" }), "red", "55 lb red");
eq(C.plateColorToken({ value: 45, unit: "lb" }), "blue", "45 lb blue");
eq(C.plateColorToken({ value: 35, unit: "lb" }), "yellow", "35 lb yellow");
eq(C.plateColorToken({ value: 25, unit: "lb" }), "green", "25 lb green");
eq(C.plateColorToken({ value: 10, unit: "lb" }), "white", "10 lb white");
eq(C.plateColorToken({ value: 5, unit: "lb" }), "black", "5 lb black");
eq(C.plateColorToken({ value: 2.5, unit: "lb" }), "black", "2.5 lb black");
eq(C.plateColorToken({ value: 25, unit: "kg" }), "red", "25 kg red");
eq(C.plateColorToken({ value: 20, unit: "kg" }), "blue", "20 kg blue");
eq(C.plateColorToken({ value: 15, unit: "kg" }), "yellow", "15 kg yellow (IWF)");
eq(C.plateColorToken({ value: 10, unit: "kg" }), "green", "10 kg green (IWF)");
eq(C.plateColorToken({ value: 5, unit: "kg" }), "white", "5 kg white (IWF)");
eq(C.plateColorToken({ value: 2.5, unit: "kg" }), "red", "2.5 kg red change plate");
ok(C.plateSizeFactor({ value: 45, unit: "lb" }) > C.plateSizeFactor({ value: 10, unit: "lb" }), "bigger plate draws taller");

// ---- bar list + id parity (mirrors PlateMathTests.testBarListMatchesWeb) ----
eq(C.ALL_BARS.map(C.barId).join(","), "45-lb,35-lb,20-kg,15-kg", "bar list matches Swift Bar.all");
ok(Math.abs(C.barLb(C.BARS.bar15kg) - 33.069) < 0.001, "15 kg bar in lb");
eq(C.barById("15-kg"), C.BARS.bar15kg, "barById resolves the 15 kg bar");
eq(C.barById("nonsense"), C.BARS.bar45lb, "unknown id falls back to 45 lb bar");
eq(C.plateId({ value: 45, unit: "lb" }), "45-lb", "plate id format");
eq(C.plateId({ value: 1.25, unit: "kg" }), "1.25-kg", "fractional plate id format");

// ---- rest defaults (override → conditioning → role → movementGroup) ----
// Movement buckets key on movementGroup (the swap-pool grouping) — never on
// exercise-name matching. Mirrors RestDefaultsTests.swift.
eq(C.restDefaultSeconds("Main", "hinge"), 300, "main hinge 5:00");
eq(C.restDefaultSeconds("Main", "squat"), 300, "main squat 5:00");
eq(C.restDefaultSeconds("Main", "olympic"), 240, "main olympic 4:00");
eq(C.restDefaultSeconds("Main", "press"), 180, "presses are mainUpper — Push Press is group press, not olympic");
eq(C.restDefaultSeconds("Main", ""), 180, "ungrouped custom main falls to mainUpper");
eq(C.restDefaultSeconds("Accessory", "arms"), 90, "accessory 1:30");
eq(C.restDefaultSeconds("Accessory", "olympic"), 90, "non-main olympic work is still accessory-bucketed");
eq(C.restDefaultSeconds("Accessory", "pull", null, C.REST_DEFAULTS, 120), 120, "accessory honors its own rest");
eq(C.restDefaultSeconds("Main", "press", null, C.REST_DEFAULTS, 120), 120, "main lift honors its per-exercise rest");
eq(C.restDefaultSeconds("Main", "hinge", null, C.REST_DEFAULTS, 360), 360, "per-exercise rest beats the movement default");
eq(C.restDefaultSeconds("Conditioning", "conditioning"), 0, "conditioning no rest");
eq(C.restDefaultSeconds("Accessory", "conditioning"), 0, "conditioning movement never rests regardless of category");
eq(C.restDefaultSeconds("Conditioning", "conditioning", null, C.REST_DEFAULTS, 120), 120, "conditioning honors an explicit rest");
// Secondary/complementary lifts rest at the secondary bucket regardless of movement.
eq(C.restDefaultSeconds("Main", "hinge", "complementary"), 180, "complementary deadlift → secondary 3:00, not 5:00");
eq(C.restDefaultSeconds("Main", "squat", "complementary"), 180, "complementary squat → secondary 3:00");
eq(C.restDefaultSeconds("Main", "hinge", "main"), 300, "main role keeps the movement default");
eq(C.restDefaultSeconds("Accessory", "arms", "accessory"), 90, "accessory role → accessory bucket");
eq(C.restDefaultSeconds("Accessory", "pull", "accessory", C.REST_DEFAULTS, 180), 180, "a deliberate per-exercise rest beats the role bucket");
// Configurable buckets override the defaults both directions.
const rc = { mainCompoundSeconds: 210, olympicSeconds: 200, mainUpperSeconds: 150, secondarySeconds: 120, accessorySeconds: 60 };
eq(C.restDefaultSeconds("Main", "hinge", "main", rc), 210, "configurable main compound");
eq(C.restDefaultSeconds("Main", "press", "main", rc), 150, "configurable main upper");
eq(C.restDefaultSeconds("Main", "hinge", "complementary", rc), 120, "configurable secondary");
eq(C.restDefaultSeconds("Accessory", "arms", null, rc), 60, "configurable accessory");

// ---- cardio set formatting (CardioFormatTests.swift) ----
eq(C.cardioSpeedMph(1.5, 1350), 4.0, "speed from distance + time");
eq(C.cardioSpeedMph(5, 5400), 3.3, "rounded to one decimal");
eq(C.cardioSpeedMph(null, 1800), null, "no distance → no speed");
eq(C.cardioSpeedMph(2, null), null, "no time → no speed");
eq(C.cardioSpeedMph(0, 0), null, "zeros → no speed");
eq(C.cardioDurationLabel(1350), "22:30", "m:ss");
eq(C.cardioDurationLabel(65), "1:05", "single-digit minutes");
eq(C.cardioDurationLabel(5400), "1:30:00", "hour-plus gets h:mm:ss");
eq(C.cardioDurationLabel(0), "0:00", "zero");
eq(C.cardioSetLabel(1.5, 1350, null), "1.5 mi · 22:30 · 4 mph", "full label");
eq(C.cardioSetLabel(3, 2700, 12), "3 mi · 45:00 · 4 mph · 12%", "fictional full-field fixture");
eq(C.cardioSetLabel(null, 1800, null), "30:00", "time only");
eq(C.cardioSetLabel(2, null, null), "2 mi", "distance only");
eq(C.cardioSetLabel(0.25, null, null), "0.25 mi", "quarter-mile keeps two decimals");
eq(C.cardioSetLabel(null, null, null), "—", "nothing logged yet");

// ---- RestClock parity (RestClockTests.swift) ----
{
  // start counts down from total
  let s = C.restClockStart(180, 1000);
  eq(s.endEpoch, 1180, "restClock start endEpoch");
  eq(s.paused, false, "restClock starts running");
  eq(C.restClockRemaining(s, 1000), 180, "full remaining at start");
  eq(C.restClockRemaining(s, 1005), 175, "remaining ticks down");
  eq(C.restClockRemaining(s, 1300), 0, "remaining floors at 0 after the end");

  // negative total clamps
  const neg = C.restClockStart(-5, 1000);
  eq(neg.total, 0, "negative total clamps to 0");
  eq(C.restClockRemaining(neg, 1000), 0, "clamped start has nothing left");

  // pause freezes remaining
  s = C.restClockStart(180, 1000);
  s = C.restClockPause(s, 1060);
  eq(s.paused, true, "pause pauses");
  eq(s.pausedRemaining, 120, "pause freezes remaining");
  eq(C.restClockRemaining(s, 2000), 120, "paused remaining ignores the clock");
  ok(C.restClockPause(s, 2000) === s, "second pause must not re-freeze a stale remaining");

  // resume restarts from the frozen remaining
  s = C.restClockResume(s, 2000);
  eq(s.paused, false, "resume resumes");
  eq(s.endEpoch, 2120, "resume recomputes the end");
  eq(C.restClockRemaining(s, 2060), 60, "resumed countdown ticks");
  ok(C.restClockResume(s, 2100) === s, "resume is idempotent");

  // add while running moves the end
  s = C.restClockStart(60, 0);
  s = C.restClockAdd(s, 30);
  eq(s.endEpoch, 90, "add moves the end");
  eq(s.total, 90, "add grows the total");
  eq(C.restClockRemaining(s, 10), 80, "remaining reflects the extension");

  // add while paused moves the frozen remaining
  s = C.restClockStart(60, 0);
  s = C.restClockPause(s, 45); // 15 left
  s = C.restClockAdd(s, 30);
  eq(s.pausedRemaining, 45, "paused add moves the frozen remaining");
  eq(s.total, 90, "paused add grows the total");
  eq(C.restClockRemaining(s, 500), 45, "paused extension holds");

  // negative add floors at zero
  s = C.restClockStart(60, 0);
  s = C.restClockPause(s, 55); // 5 left
  s = C.restClockAdd(s, -30);
  eq(s.pausedRemaining, 0, "negative add floors remaining at 0");
  eq(s.total, 30, "negative add shrinks the total");

  // fraction remaining
  s = C.restClockStart(100, 0);
  eq(C.restClockFractionRemaining(s, 0), 1, "fraction 1 at start");
  eq(C.restClockFractionRemaining(s, 75), 0.25, "fraction 0.25 at 75s");
  eq(C.restClockFractionRemaining(s, 100), 0, "fraction 0 at the end");
  eq(C.restClockFractionRemaining(s, 500), 0, "fraction 0 after the end");
  eq(C.restClockFractionRemaining(C.restClockStart(0, 0), 0), 0, "zero-length rest has no progress");

  // pause/resume round trip preserves the total rest delivered
  s = C.restClockStart(180, 0);
  s = C.restClockPause(s, 30);   // 150 left, frozen
  s = C.restClockResume(s, 100); // runs 100->250
  s = C.restClockPause(s, 200);  // 50 left
  s = C.restClockResume(s, 300); // runs 300->350
  eq(s.endEpoch, 350, "interruptions still deliver the full rest");
  eq(C.restClockRemaining(s, 300), 50, "post-round-trip remaining");
  eq(s.total, 180, "total untouched by pause/resume");
}

// ---- Rotation-first coaching parity (CoachingEngineTests.swift) ----
{
  eq(C.movementPattern("Barbell Row", "pull"), "horizontalPull", "rows classify horizontally");
  eq(C.movementPattern("Lat Pulldown", "pull"), "verticalPull", "pulldowns classify vertically");
  eq(C.movementPattern("Seated Leg Curl", "hinge"), "kneeFlexion", "leg curls classify as knee flexion");
  eq(C.movementPattern("Back Extension", "hinge"), "hipExtension", "back extensions classify as hip extension");
  eq(C.movementPattern("Overhead Press", "press"), "verticalPress", "OHP classifies vertically");

  const coachingProgram = {
    id: "program", expectedDayIndexes: [0, 1, 2, 3],
    slots: [
      { id: "squat", exerciseName: "Back Squat", dayIndex: 0, pattern: "squat", plannedSets: 3, isMain: true },
      { id: "press-a", exerciseName: "Overhead Press", dayIndex: 1, pattern: "verticalPress", plannedSets: 3, isMain: true },
      { id: "deadlift", exerciseName: "Deadlift", dayIndex: 2, pattern: "hipHinge", plannedSets: 3, isMain: true },
      { id: "press-b", exerciseName: "Incline DB Press", dayIndex: 3, pattern: "horizontalPress", plannedSets: 3, isMain: true },
      { id: "row", exerciseName: "Chest-supported Row", dayIndex: 3, pattern: "horizontalPull", plannedSets: 6, maximumSets: 6 },
    ],
  };
  const coachingSession = (rotation, dayIndex, dayOffset, weight = 100, actual = weight) => {
    const names = ["Back Squat", "Overhead Press", "Deadlift", "Incline DB Press"];
    const patterns = ["squat", "verticalPress", "hipHinge", "horizontalPress"];
    return {
      id: `1-${rotation}-${dayIndex}`, date: new Date(1_700_000_000_000 + dayOffset * 86_400_000).toISOString(),
      programID: "program", cycleNumber: 1, rotation, dayIndex, completed: true,
      exercises: [{
        slotID: `slot-${dayIndex}`, exerciseName: names[dayIndex], pattern: patterns[dayIndex],
        plannedSets: 3, plannedWeightLb: weight, plannedReps: 5,
        sets: Array.from({ length: 3 }, () => ({ actualWeightLb: actual, actualReps: 5, plannedWeightLb: weight, plannedReps: 5, completed: true })),
      }],
    };
  };

  let report = C.evaluateCoaching(coachingProgram, [coachingSession(1, 0, 0)]);
  eq(report.currentReadiness, "unknown", "incomplete rotation is unknown");
  eq(report.recommendations.length, 0, "incomplete rotation never adds volume");

  const conditioningSessions = Array.from({ length: 4 }, (_, dayIndex) => coachingSession(1, dayIndex, dayIndex * 3));
  conditioningSessions[1].exercises.push({
    exerciseName: "Bike", pattern: "easyAerobic", plannedSets: 1,
    sets: [{ actualWeightLb: 0, actualReps: 0, durationSeconds: 1_200, completed: true }],
  });
  conditioningSessions[0].exercises[0].sets.push({
    actualWeightLb: 120, actualReps: 1, plannedWeightLb: 120, plannedReps: 1,
    prescriptionBlock: "topSingle", completed: true,
  });
  report = C.evaluateCoaching(coachingProgram, conditioningSessions);
  eq(report.rotations[0].plannedWorkingSets, 12, "conditioning does not inflate planned lifting sets");
  eq(report.rotations[0].completedWorkingSets, 12, "conditioning does not inflate completed lifting sets");
  eq(report.rotations[0].conditioningMinutes, 20, "conditioning remains in its minute ledger");
  eq(report.rotations[0].patternSets.squat, 3, "top single is performance evidence, not a budget work set");

  let sessions = [];
  for (let rotation = 1; rotation <= 3; rotation++) {
    for (let dayIndex = 0; dayIndex < 4; dayIndex++) {
      sessions.push(coachingSession(rotation, dayIndex, ((rotation - 1) * 4 + dayIndex) * 3, 100 + (rotation - 1) * 5));
    }
  }
  report = C.evaluateCoaching(coachingProgram, sessions);
  eq(report.currentReadiness, "green", "two comparable rotations end green");
  eq(report.greenRotationStreak, 2, "first rotation is the baseline");
  const capacityPlan = report.recommendations.find((r) => r.change.type === "capacityPlan");
  ok(!!capacityPlan, "capacity additions are bundled into one audited action");
  const adds = capacityPlan.change.additions;
  eq(adds.reduce((sum, addition) => sum + (addition.sets || addition.count), 0), 6, "capacity change capped at six targeted sets");
  ok(adds.some((r) => r.pattern === "verticalPull"), "vertical pull gap is proposed");
  const hamstrings = adds.find((r) => r.pattern === "kneeFlexion");
  ok(!!hamstrings, "hamstring isolation gap is proposed");
  eq(hamstrings.dayIndex, 0, "hamstrings slot onto the squat-led day");

  sessions = [];
  for (let dayIndex = 0; dayIndex < 4; dayIndex++) sessions.push(coachingSession(1, dayIndex, dayIndex * 3));
  for (let dayIndex = 0; dayIndex < 4; dayIndex++) sessions.push(coachingSession(2, dayIndex, 12 + dayIndex * 3, 105, dayIndex === 0 ? 90 : 105));
  report = C.evaluateCoaching(coachingProgram, sessions);
  eq(report.currentReadiness, "yellow", "adjusted-lower work makes rotation yellow");
  eq(report.recommendations[0].change.type, "hold", "yellow holds prescription");

  sessions = [];
  for (let dayIndex = 0; dayIndex < 4; dayIndex++) sessions.push(coachingSession(1, dayIndex, dayIndex * 3, 100));
  for (let dayIndex = 0; dayIndex < 4; dayIndex++) sessions.push(coachingSession(2, dayIndex, 12 + dayIndex * 3, 90));
  report = C.evaluateCoaching(coachingProgram, sessions);
  eq(report.currentReadiness, "red", "large repeated performance drops are red");
  eq(report.recommendations[0].change.type, "reduceAccessoryVolume", "red proposes reduced accessories");

  sessions = Array.from({ length: 4 }, (_, dayIndex) => coachingSession(1, dayIndex, dayIndex * 3));
  sessions[2].hasHardStopCheckIn = true;
  report = C.evaluateCoaching(coachingProgram, sessions);
  eq(report.currentReadiness, "red", "hard-stop recovery check-in makes a complete rotation red");
  ok(report.rotations[0].reasons.some((reason) => reason.includes("check-in")), "hard-stop check-in is explained");
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
