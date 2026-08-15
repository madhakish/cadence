// Port of the CadenceCore XCTest suite. Run: node tests/core.test.mjs
// Keeps the JS math in lockstep with the Swift source of truth.
import * as C from "../app/js/core.js";

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

// The clean stack is loading guidance, not a new prescription: within the
// band the programmed number is what gets stored; only genuinely unreachable
// targets store the achieved load.
eq(C.storedPrescription(90, 89.1), 90, "[INV-LOAD-STORED-NEAT] in-band kg stack keeps the neat 90");
eq(C.storedPrescription(220, s.totalLb), 220, "220 card stays 220 despite the kg stack");
eq(C.storedPrescription(155, 155), 155, "exact load passes through");
eq(C.storedPrescription(90, 85), 85, "[INV-LOAD-STORED-NEAT] unreachable target stores the honest load");
eq(C.storedPrescription(50, 65), 65, "sparse-rack overshoot stays honest");

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
r = C.warmupRamp(245, 45, 5, false);
ok(JSON.stringify(r.map((x) => x.weightLb)) === JSON.stringify([100, 135, 170, 210]), "ramp can omit empty bar");
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
eq(`${rolePlan.sets}x${rolePlan.reps}@${rolePlan.weightLb}`, "3x8@180", "complementary volume avoids a second 5x5");
for (const [phase, expected] of [[1, "3x8@180"], [2, "3x8@190"], [3, "3x6@200"], [4, "1x5@150"]]) {
  const p = C.programPlanFor({ cycleNumber: 1, baseWeightLb: 200, nextPhase: phase, incrementLb: 0 }, 5,
    "barbell", "hinge", "complementary", "strength", "automatic");
  eq(`${p.sets}x${p.reps}@${p.weightLb}`, expected, `complementary phase ${phase} stays volume-oriented`);
  ok(p.reps >= 5 && p.weightLb <= 200, `[INV-COMP-IS-VOLUME] complementary phase ${phase} is 5+ reps at/below base`);
}
let techniquePlan = C.programPlanFor({ cycleNumber: 1, baseWeightLb: 100, nextPhase: 3, incrementLb: 0 }, 5,
  "barbell", "olympic", "main", "strength", "automatic");
eq(`${techniquePlan.sets}x${techniquePlan.reps}@${techniquePlan.weightLb}`, "5x1@115", "Olympic peak is crisp singles");
const techniqueBuild = [1, 2, 3, 4].map((phase) => C.programPlanFor(
  { cycleNumber: 1, baseWeightLb: 100, nextPhase: phase, incrementLb: 0 }, 5,
  "barbell", "olympic", "main", "strength", "automatic"));
eq(techniqueBuild.map((plan) => plan.sets).join(","), "5,5,5,3", "Olympic build keeps five practice sets before recovery");
eq(techniqueBuild.map((plan) => plan.reps).join(","), "3,2,1,2", "Olympic build moves triples to doubles to singles");
eq(techniqueBuild.map((plan) => plan.weightLb).join(","), "100,110,115,90", "Olympic build adds 7.5% of its opening load per step");
eq(C.templateStartFraction("technique"), 0.70, "new Olympic blocks start conservatively at 70% of history");
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
eq(plan.weightLb, 165, "recovery weight"); eq(plan.sets, 2, "recovery sets"); eq(plan.reps, 3, "recovery reps");
eq(C.PHASES[4].name, "Recovery", "phase 4 is presented as recovery, not a fourth training rotation");
eq(C.portablePhaseLabel(4), "R4 Deload 3×5", "the v7 backup wire label remains backward-compatible");
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

// Propagating an edit changes the work about to be done, not the target the
// session is graded against — otherwise the base weight could climb on work
// that was never done.
ok(C.belowPlanWork([205, 205, 205], 225, 3),
  "[INV-BELOW-PLAN-IS-BELOW-PLAN] a lighter session still grades as below plan");
ok(!C.belowPlanWork([225, 225, 225], 225, 3),
  "[INV-BELOW-PLAN-IS-BELOW-PLAN] work at plan is not below plan");
ok(!C.belowPlanWork([225, 225, 225, 185], 225, 3),
  "[INV-BELOW-PLAN-IS-BELOW-PLAN] a back-off set beyond the prescription never fails the grade");
ok(!C.belowPlanWork([223.5, 225, 225], 225, 3),
  "[INV-BELOW-PLAN-IS-BELOW-PLAN] kg-entry noise inside half a rounding step still counts as at plan");

// A rotation must be judged against the program as it stood WHEN IT WAS RUN.
// Programs legitimately gain days — adding a complementary lift, moving from a
// 2-day to a 4-day split — and reading today's day list back over old
// rotations reported finished work as permanently "1/4 days banked".
{
  const mkSession = (cycle, rotation, dayIndex, date) => ({
    id: `s${cycle}-${rotation}-${dayIndex}`, date, programID: "p1", cycleNumber: cycle,
    rotation, dayIndex, completed: true, exercises: [],
  });
  const program = { id: "p1", expectedDayIndexes: [0, 1, 2, 3], slots: [], maximumAddedSetsPerRotation: 6 };
  // Two closed rotations run under a smaller program, then the live one.
  const report = C.evaluateCoaching(program, [
    mkSession(1, 1, 0, "2026-05-09T12:00:00Z"), mkSession(1, 1, 1, "2026-05-12T12:00:00Z"),
    mkSession(1, 2, 0, "2026-05-15T12:00:00Z"), mkSession(1, 2, 1, "2026-05-19T12:00:00Z"),
    mkSession(2, 1, 0, "2026-07-15T12:00:00Z"),
  ]);
  const [first, second, current] = report.rotations;
  ok(first.isComplete && first.judgedAsRun,
    "[INV-ROTATION-JUDGED-AS-RUN] a closed rotation is complete against the days it ran");
  ok(second.isComplete && second.judgedAsRun,
    "[INV-ROTATION-JUDGED-AS-RUN] every closed rotation, not just the first");
  ok(!current.isComplete && !current.judgedAsRun,
    "[INV-ROTATION-JUDGED-AS-RUN] the live rotation is still measured against the current program");
  eq(current.expectedDayIndexes.length, 4,
    "[INV-ROTATION-JUDGED-AS-RUN] the live rotation expects today's full day set");
}

// Schedule advance walks day ORDER values, not array positions. Import
// validates day orders as unique but never as contiguous, so a bundle can
// carry [0, 1, 5]; index-space arithmetic then never recognized the last day
// (the week stopped advancing, the cycle never rolled over) and stranded the
// day past the gap.
const sa = (orders, banked) => {
  const r = C.scheduleAdvance(orders, banked);
  return `${r.nextDayOrder}${r.isLastDay ? "!" : ""}`;
};
eq(sa([0, 1, 2, 3], 0), "1", "contiguous orders step forward");
eq(sa([0, 1, 2, 3], 3), "0!", "the highest order is the last day and wraps");
eq(sa([0, 1, 5], 1), "5", "[INV-SCHEDULE-WALKS-ORDERS] the day past a gap is reachable");
eq(sa([0, 1, 5], 5), "0!", "the highest order is the last day whatever its value");
eq(sa([2, 0, 1], 0), "1", "stored order is not assumed sorted");
eq(sa([0], 0), "0!", "a one-day program banks its only day as the last day");
eq(sa([0, 1], 9), "0!", "a stale tag closes the rotation instead of stranding it");
eq(sa([], 0), "0!", "an empty program does not crash");
// Two DISTINCT days can share one order (a damaged store, or an add that
// collided on days.length). Stepping inside the duplicate pair would advance
// an order to itself and strand the rotation the same way a gap did.
eq(sa([0, 0, 1], 0), "1", "[INV-SCHEDULE-WALKS-ORDERS] duplicate orders never advance a day to itself");
eq(sa([0, 1, 1], 1), "0!", "a duplicated last order is still the last day");
eq(sa([0, 0], 0), "0!", "an all-duplicate program still closes its rotation");

// [INV-RECOVERY-IS-A-BRIDGE] Phase 4 selects structural representatives,
// never day-name substrings, and preserves authored schedule order.
eq(C.recoveryDayOrders([
  { order: 0, mainMovementGroup: "press" }, { order: 1, mainMovementGroup: "squat" },
  { order: 2, mainMovementGroup: "pull" }, { order: 3, mainMovementGroup: "hinge" },
]).join(","), "0,1", "recovery keeps one authored upper and one lower exposure");
eq(C.recoveryDayOrders([
  { order: 9, mainMovementGroup: "squat" }, { order: 2, mainMovementGroup: "hinge" },
  { order: 7, mainMovementGroup: "press" },
]).join(","), "2,7", "lower-first sparse programs retain their authored order");
eq(C.recoveryDayOrders([
  { order: 5, mainMovementGroup: "olympic" }, { order: 0, mainMovementGroup: "squat" },
  { order: 2, mainMovementGroup: null },
]).join(","), "0,2,5", "ambiguous programs retain their complete authored rotation");
eq(C.recoveryDayOrders([]).length, 0, "empty recovery candidates stay empty");

// Recovery completion counts selected exposures actually banked in the
// current cycle. Pointer order cannot make the second-authored day roll early,
// and an old full-rotation day cannot count as part of the shortened bridge.
let recoveryAdvance = C.recoveryScheduleAdvance([0, 1], [0]);
eq(`${recoveryAdvance.nextDayOrder}:${recoveryAdvance.isLastDay}`, "1:false",
  "banking lower points at the remaining upper exposure");
recoveryAdvance = C.recoveryScheduleAdvance([0, 1], [1]);
eq(`${recoveryAdvance.nextDayOrder}:${recoveryAdvance.isLastDay}`, "0:false",
  "either recovery exposure may be banked first");
recoveryAdvance = C.recoveryScheduleAdvance([0, 1], [1, 0, 0]);
eq(recoveryAdvance.isLastDay, true, "both selected exposures complete recovery exactly once");
recoveryAdvance = C.recoveryScheduleAdvance([0, 1], [2]);
eq(`${recoveryAdvance.nextDayOrder}:${recoveryAdvance.isLastDay}`, "0:false",
  "a non-bridge day cannot complete recovery");
eq(C.recoveryScheduleAdvance([], [0]).isLastDay, false, "an empty bridge fails closed");

// The seven-day value expires Recovery; it does not schedule this cycle-based
// program. Any two banked recovery sessions are also a hard cap, even when a
// legacy/manual pointer sent them to non-selected day orders.
const peakMs = Date.UTC(2042, 0, 1, 12);
eq(C.recoveryBridgeCompletionReason(1, 2, false, peakMs, peakMs + C.RECOVERY_WINDOW_MS - 1), null,
  "one recovery session inside the window leaves the bridge open");
eq(C.recoveryBridgeCompletionReason(2, 2, false, peakMs, peakMs + 60_000), "sessionLimit",
  "two recovery sessions close the bridge regardless of day order");
eq(C.recoveryBridgeCompletionReason(1, 2, false, peakMs, peakMs + C.RECOVERY_WINDOW_MS), "windowElapsed",
  "a half-finished bridge expires at exactly seven elapsed days");
eq(C.recoveryBridgeCompletionReason(1, 2, true, null, peakMs), "selectedExposures",
  "a short selected bridge may close normally");
eq(C.recoveryBridgeCompletionReason(1, 2, false, null, peakMs + 2 * C.RECOVERY_WINDOW_MS), null,
  "missing history never invents an expiry anchor");

// Recovery is a fixed window after Peak, not a timer that starts only when the
// first reduced workout is banked. Zero workouts is a valid deload choice.
eq(C.recoveryBridgeCompletionReason(0, 2, false, peakMs, peakMs + C.RECOVERY_WINDOW_MS), "windowElapsed",
  "an unbanked bridge expires at the same seven-day boundary");
eq(C.recoveryBridgeCompletionReason(0, 2, false, peakMs, peakMs + 40 * C.RECOVERY_WINDOW_MS), "windowElapsed",
  "a stale hard-phase anchor cannot leave Recovery open indefinitely");

// The cap is the bridge's OWN length. A program that is not recognizably
// upper/lower keeps its full authored pass, and a constant two silently dropped
// day three onward — losing exactly the work that fallback exists to preserve.
eq(C.recoveryBridgeCompletionReason(2, 4, false, peakMs, peakMs + 60_000), null,
  "a four-day authored bridge is not closed by two sessions");
eq(C.recoveryBridgeCompletionReason(4, 4, false, peakMs, peakMs + 60_000), "sessionLimit",
  "it closes once its own length is banked");
eq(C.recoveryBridgeCompletionReason(2, 1, false, peakMs, peakMs + 60_000), "sessionLimit",
  "and a degenerate one-day bridge still keeps the two-session floor");

// The top scheme must describe work that was actually performed. Reporting the
// group minimum across every top-weight set invented schemes nobody did — and
// those strings are banked as the history baseline.
let ts = C.prTopScheme([{ weightLb: 225, reps: 5 }, { weightLb: 225, reps: 2 }]);
eq(`${ts.sets}×${ts.reps}`, "1×5", "[INV-SCHEME-PERFORMED] a top set plus a fatigue set is one five, not two doubles");
ts = C.prTopScheme([...Array(4).fill({ weightLb: 225, reps: 5 }), { weightLb: 225, reps: 3 }]);
eq(`${ts.sets}×${ts.reps}`, "4×5", "[INV-SCHEME-PERFORMED] four fives and a dropped triple is 4×5, never 5×3");
ts = C.prTopScheme([{ weightLb: 185, reps: 8 }, { weightLb: 185, reps: 6 }]);
eq(`${ts.sets}×${ts.reps}`, "1×8", "an even split takes the harder group");
ts = C.prTopScheme([...Array(5).fill({ weightLb: 175, reps: 5 }), { weightLb: 155, reps: 8 }]);
eq(`${ts.weightLb}:${ts.sets}×${ts.reps}`, "175:5×5", "back-off sets never shape the top scheme");

// Bodyweight/assisted work has no meaningful load to name.
ev = C.prEvaluate({
  exercise: "Push-ups", sessionSets: Array(3).fill({ weightLb: 0, reps: 12, loadBasis: "bodyweight" }),
  historySets: [], historyVolumes: [], historySchemes: [],
});
eq(ev.find((e) => e.kind === "firstScheme")?.label, "First 3×12 push-ups",
  "[INV-NO-LOAD-WITHOUT-RESISTANCE] bodyweight scheme milestone omits a meaningless 0 load");

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
  const weightedPullup = { name: "Weighted Pull-up", category: "Accessory", type: "bodyweight",
    movementGroup: "pull", loadBasis: "externalTotal" };

  eq(C.swapCompatible(backSquat, frontSquat), true, "same tier/pattern/loadability → offered");
  eq(C.swapCompatible(chinups, pullups), true, "bodyweight→bodyweight is fine");
  eq(C.swapCompatible(weightedPullup, pullups), false,
    "weighted and unloaded pull-ups cannot carry the same prescription");
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

// The lifter's priority order: the needle moves every cycle — weight when a
// clean jump is earnable, volume when it is not. Headroom to the LOGGED prior
// best stages the increment; a held cycle falls back to a volume set instead
// of a bare hold. Mirrors ProgramProgressionTests/ProgramEngineTests.
{
  // [INV-NEEDLE-ALWAYS-MOVES] regime bands off logged evidence only.
  eq(C.progressionRegime(300, 0, true), "standard", "no logged evidence grades standard");
  eq(C.progressionRegime(300, 400, false), "rebuild", "a logged drawdown reads rebuild regardless of the best's age");
  eq(C.progressionRegime(395, 400, true), "fine", "closing on a standing ceiling reads fine");
  eq(C.progressionRegime(395, 400, false), "standard",
    "[INV-NEEDLE-ALWAYS-MOVES] a fresh log rising through its own best never reads fine");
  eq(C.progressionRegime(370, 400, true), "standard", "inside the normal band nothing changes");
  // [INV-NEEDLE-ALWAYS-MOVES] the second axis: a base far below the lifter's
  // OWN estimated max is a rebuild even when a young log's rising prior best
  // never shows a drawdown. Mirrors CadenceCore — same numbers.
  eq(C.progressionRegime(278.3, 270, false, 226), "rebuild",
    "a 226 base under a 278 estimated max (81%) is a rebuild in progress");
  eq(C.progressionRegime(278.3, 270, false, 240), "standard",
    "past 85% of own capability the headroom axis stands down");
  eq(C.progressionRegime(400, 400, true, 395), "fine",
    "the fine band is untouched — a base near the ceiling can never read as headroom");

  // [INV-NEEDLE-ALWAYS-MOVES] staged increments.
  eq(C.stagedIncrement(175, "strength", "standard", 5), 5, "standard is focusIncrement untouched");
  eq(C.stagedIncrement(175, "strength", "rebuild", 5), 10,
    "rebuild rounds the 5 lb step up to the clean 10 lb class — no change plates");
  eq(C.stagedIncrement(175, "strength", "fine", 5), 2.5,
    "fine halves the step down to change-plate granularity");
  eq(C.stagedIncrement(221, "strength", "rebuild", 10), 10, "an increment already in the clean class is untouched");
  eq(C.stagedIncrement(221, "strength", "fine", 10), 5, "fine at 10-rounding is a 5 lb pair");
  eq(C.stagedIncrement(300, "maintain", "rebuild", 5), 0, "maintain stays zero in every regime");

  // [INV-NEEDLE-ALWAYS-MOVES] the volume fallback derives from pure state,
  // with the rotation-wide budget allocated by stalled rank.
  eq(C.volumeIncrementSets(1, 0, 6), 1, "a held cycle adds one volume set");
  eq(C.volumeIncrementSets(0, 0, 6), 0, "no stall, no extra volume");
  eq(C.volumeIncrementSets(1, 0, 0), 0, "the added-set governance can turn the fallback off entirely");
  eq(C.volumeIncrementSets(1, 0, 1), 1, "the first stalled slot spends the budget");
  eq(C.volumeIncrementSets(1, 1, 1), 0, "the second stalled slot finds it spent — four stalls under a cap of one add one set, not four");
  eq(C.volumeIncrementSets(1, 3, 6), 1, "a roomy budget covers every stalled slot");
  eq(C.volumeIncrementSets(1, -1, 6), 0, "a slot outside the stalled ranking carries nothing");

  // [INV-NEEDLE-ALWAYS-MOVES] a held cycle moves the needle with volume.
  const heldResult = C.advanceCycleLift(liftState(), { ...cleanPerf, grindyOrWobbleSets: 3 }, "strength", 5,
    "rebuild", true);
  eq(heldResult.state.stallCount, 1, "the stall still counts");
  eq(heldResult.state.baseWeightLb, 175, "the weight holds; the volume moves");
  ok(/adds a set/.test(heldResult.note || ""), "the note tells the lifter how the cycle still moves");
  const secondMiss = C.advanceCycleLift(heldResult.state, { ...cleanPerf, completedSets: 1 }, "strength", 5,
    "rebuild", true);
  eq(secondMiss.state.baseWeightLb, 160, "the stall→deload ladder is intact underneath (175→160)");
  eq(secondMiss.state.stallCount, 0, "deload consumes the counter");
  const cleanRebuild = C.advanceCycleLift(liftState(), cleanPerf, "strength", 5, "rebuild", true);
  eq(cleanRebuild.state.baseWeightLb, 185, "a clean rebuild grade jumps the clean class: 175 + 10");

  // [INV-NEEDLE-ALWAYS-MOVES] the fallback lands on the VOLUME rotation only.
  const volState = { cycleNumber: 1, baseWeightLb: 210, nextPhase: 1, incrementLb: 0 };
  eq(C.planForStyle(volState, 5, "wave", {}, null, 1).sets, 6, "5×5 becomes 6×5 at the same load");
  eq(C.planForStyle(volState, 5, "wave", {}, null, 0).sets, 5, "a clean grade returns the shape with the jump");
  eq(C.planForStyle(volState, 5, "offsetWave", {}, null, 1).sets, 6, "offset wave carries the fallback too");
  eq(C.planForStyle(volState, 5, "secondary", {}, null, 1).sets, 3, "complementary styles govern their own volume");
  eq(C.planForStyle({ ...volState, nextPhase: 2 }, 5, "wave", {}, null, 1).sets, 5, "load keeps its shape");
  eq(C.planForStyle({ ...volState, nextPhase: 3 }, 5, "wave", {}, null, 1).sets, 3, "peak keeps its precision");
  eq(C.sessionPrescription(volState, 5, "barbell", "hinge", "main", "strength", "automatic", {}, 0, 1).mainWork.sets, 6,
    "the whole pipeline threads it — the stored prescription matches the card");
}

// The increment is a fraction of base floored to a loadable step, and nothing
// else. The old headroom-to-ceiling taper is gone: it produced only 0 or one
// step across every realistic load, and its cliff was unreachable on the
// success path because a clean peak raises the estimate faster than the base.
eq(C.focusIncrement(150, "strength", 5), 5, "a light base still earns one loadable step");
eq(C.focusIncrement(200, "strength", 5), 5, "a base near the OLD ceiling keeps progressing");
eq(C.focusIncrement(210, "strength", 5), 5, "and so does one past it — the cap no longer exists");
eq(C.focusIncrement(400, "strength", 5), 10, "a heavy base earns the full 2.5% once it clears a step");
eq(C.focusIncrement(400, "hypertrophy", 5), 5, "hypertrophy's 1.5% is a smaller step at the same base");
eq(C.focusIncrement(0, "strength", 5), 0, "an unset base earns nothing");

// The property that made the old taper dead arithmetic: never anything between
// zero and one step. The replacement is allowed to exceed a step; what it must
// never do is return a weight nobody can load.
{
  const offStep = [];
  for (let base = 45; base <= 700; base += 5) {
    for (const focus of ["strength", "hypertrophy"]) {
      const inc = C.focusIncrement(base, focus, 5);
      if (inc % 5 !== 0) offStep.push(`${focus}@${base}=${inc}`);
    }
  }
  eq(offStep.length, 0, `every increment lands on a loadable step (${offStep.slice(0, 3)})`);
}

// offsetWave is retired from the pickers but NOT deleted: its raw value is
// persisted in programs, backups and program files, so a slot already on it has
// to keep working and keep appearing in its own picker.
{
  const all = [["automatic", "A"], ["wave", "W"], ["offsetWave", "O"], ["secondary", "S"]];
  const offered = (current) => C.selectablePrescriptions(all, current).map(([v]) => v);
  ok(!offered("wave").includes("offsetWave"), "a new slot is never offered the retired style");
  ok(offered("offsetWave").includes("offsetWave"),
    "a slot already on it still sees it, so opening the picker cannot silently rewrite the slot");
  eq(offered("wave").length, all.length - 1, "and nothing else is hidden");
  // Still a real style everywhere that is not a picker.
  ok(C.planForStyle({ cycleNumber: 1, baseWeightLb: 200, nextPhase: 3, incrementLb: 0 }, 5, "offsetWave",
    { loadOffsetLb: 25, peakOffsetLb: 33 }).weightLb > 200, "a retired style still prescribes");
}

// Ten clean cycles at a base that used to freeze: it must keep moving now.
{
  let state = { baseWeightLb: 200, estimatedMaxLb: 226, stallCount: 0, lastIncrementLb: 0 };
  const perf = { prescribedSets: 3, prescribedReps: 3, completedSets: 3, anyStoppedEarly: false,
    anyDroppedLoad: false, anyBelowPlanLoad: false, grindyOrWobbleSets: 0, topSetWeightLb: 235, topSetReps: 3 };
  for (let i = 0; i < 10; i++) state = C.advanceCycleLift(state, perf, "strength", 5).state;
  ok(state.baseWeightLb >= 250, `ten clean cycles keep adding weight (got ${state.baseWeightLb})`);
}

// maintain never increments
pres = C.advanceCycleLift(liftState(), cleanPerf, "maintain", 5);
eq(pres.state.baseWeightLb, 175, "maintain holds weight on success");
eq(pres.state.stallCount, 0, "maintain success resets stall");

// offsetWave's movement-aware defaults live in one place now. They used to be
// resolved in sessionPrescription only, so a squat reaching planForStyle
// directly got the upper-body 10/15 while the native side used 25/33.
{
  const lower = C.resolvedOffsets(0, 0, "squat");
  ok(lower.loadOffsetLb === 25 && lower.peakOffsetLb === 33, "lower-body offsets default to 25/33");
  const hinge = C.resolvedOffsets(0, 0, "hinge");
  ok(hinge.loadOffsetLb === 25 && hinge.peakOffsetLb === 33, "hinge counts as lower body");
  const upper = C.resolvedOffsets(0, 0, "press");
  ok(upper.loadOffsetLb === 10 && upper.peakOffsetLb === 15, "everything else defaults to 10/15");
  const unknown = C.resolvedOffsets(0, 0, null);
  ok(unknown.loadOffsetLb === 10 && unknown.peakOffsetLb === 15, "an unknown group is treated as upper body");
  const explicit = C.resolvedOffsets(40, 60, "squat");
  ok(explicit.loadOffsetLb === 40 && explicit.peakOffsetLb === 60, "an explicit offset stays user-owned");
  const partial = C.resolvedOffsets(40, 0, "squat");
  ok(partial.loadOffsetLb === 40 && partial.peakOffsetLb === 33, "each offset defaults independently");
  // The bug: planForStyle must now agree with sessionPrescription for a squat.
  const viaStyle = C.planForStyle({ baseWeightLb: 200, nextPhase: 3, cycleNumber: 1 }, 5, "offsetWave", {}, "squat");
  ok(viaStyle.weightLb === 235, `planForStyle applies the lower-body peak offset (got ${viaStyle.weightLb})`);
}

// ---- authored slot order (ProgramEngineTests.swift) ----
// [INV-TIED-ORDER-IS-AUTHORED] Every order tied → the tie carries no
// information; the array position the author wrote the slots in is their
// order. Without this the display fallback hands the day to the alphabet.
eq(C.authoredSlotOrders([0, 0, 0]).join(","), "0,1,2", "an all-tied day takes authored array order");
eq(C.authoredSlotOrders([7, 7]).join(","), "0,1", "any shared value is the same degenerate case");
eq(C.authoredSlotOrders([2, 0, 1]).join(","), "2,0,1", "distinct orders are the author's numbers");
eq(C.authoredSlotOrders([0, 0, 2]).join(","), "0,0,2", "a partial tie is a real authored ordering, kept verbatim");
eq(C.authoredSlotOrders([5]).join(","), "5", "a single slot has nothing to disambiguate");
eq(C.authoredSlotOrders([]).length, 0, "empty in, empty out");

// ---- deload intensity knob (ProgramEngineTests.swift) ----
// [INV-DELOAD-IS-THE-SLOTS-KNOB]
{
  const deload = (config) => C.programPlanFor(
    { baseWeightLb: 200, nextPhase: 4, cycleNumber: 1 }, 5, "barbell", "press", "main", "strength", "wave", config);
  eq(deload({}).weightLb, 155, "default stays the historical 0.775 — nobody's deload moves uninvited");
  eq(deload({ deloadMultiplier: 0.85 }).weightLb, 170,
    "a slot that finds 77.5% unproductively light raises intensity, not volume");
  eq(`${deload({ deloadMultiplier: 0.85 }).sets}x${deload({ deloadMultiplier: 0.85 }).reps}`, "2x3",
    "the volume cut is not negotiable through this knob");
  const peak = C.programPlanFor(
    { baseWeightLb: 200, nextPhase: 3, cycleNumber: 1 }, 5, "barbell", "press", "main", "strength", "wave",
    { deloadMultiplier: 0.85 });
  eq(peak.weightLb, 235, "only the deload listens; working rotations keep the wave shape");
  const secondary = C.programPlanFor(
    { baseWeightLb: 200, nextPhase: 4, cycleNumber: 1 }, 5, "barbell", "press", "complementary", "strength", "automatic",
    { deloadMultiplier: 0.85 });
  eq(secondary.weightLb, 150, "a complementary slot resolves secondary and keeps its own fixed 0.75 deload");
  // Zero is "unset", never "lift nothing" — no importer admits a 0, but a
  // hand-edited store must not plan an empty bar, and both branches must
  // agree with the native engine's identical guard.
  eq(deload({ deloadMultiplier: 0 }).weightLb, 155, "a zero multiplier falls back to the table's 0.775 on wave");
  const offsetZero = C.programPlanFor(
    { baseWeightLb: 200, nextPhase: 4, cycleNumber: 1 }, 5, "barbell", "press", "main", "strength", "offsetWave",
    { loadOffsetLb: 10, peakOffsetLb: 25, deloadMultiplier: 0 });
  eq(offsetZero.weightLb, 155, "a zero multiplier falls back to 0.775 on offsetWave too");
  // The knob must survive the whole session builder, not just the plan table:
  // sessionPrescription is what actually puts the bar weight in front of the
  // lifter on a rest week.
  const sessionDeload = C.sessionPrescription(
    { baseWeightLb: 200, nextPhase: 4, cycleNumber: 1 }, 5, "barbell", "press", "main", "strength", "automatic",
    { deloadMultiplier: 0.85, phasePrimerEnabled: false });
  const workBlock = sessionDeload.blocks.find((b) => b.kind === "work");
  eq(workBlock.weightLb, 170, "the session builder hands the slot's knob to the bar");
  eq(`${workBlock.sets}x${workBlock.reps}`, "2x3", "and keeps the fixed recovery volume");
}

// A peak single's seed is a training max, so it follows the program's focus.
{
  const state = { baseWeightLb: 100, nextPhase: 3, cycleNumber: 1 };
  const cfg = { peakSingleEnabled: true, lastPeakSingleLb: 0, phasePrimerEnabled: false };
  const strength = C.sessionPrescription(state, 5, "barbell", "press", "main", "strength", "wave", cfg, 200);
  const hyper = C.sessionPrescription(state, 5, "barbell", "press", "main", "hypertrophy", "wave", cfg, 200);
  const single = (p) => p.blocks.find((b) => b.kind === "topSingle")?.weightLb;
  ok(single(strength) === 180, `strength seeds the single at 0.90 of e1RM (got ${single(strength)})`);
  ok(single(hyper) === 155, `hypertrophy seeds it at its own 0.78 ceiling (got ${single(hyper)})`);
}

// Protein guidance is derived, advisory, and silent without a bodyweight.
ok(C.proteinDailyTargetGrams(201) === 145, `201 lb at 1.6 g/kg rounds to 145 g (got ${C.proteinDailyTargetGrams(201)})`);
ok(C.proteinPerMealGrams(201) === 35, `201 lb at 0.4 g/kg per meal rounds to 35 g (got ${C.proteinPerMealGrams(201)})`);
ok(C.proteinDailyTargetGrams(null) === null, "no bodyweight, no suggestion");
ok(C.proteinDailyTargetGrams(0) === null, "a zero bodyweight is not a bodyweight");
ok(C.proteinSummary(null) === null, "no bodyweight, no guidance line");
ok(/145 g\/day/.test(C.proteinSummary(201)), "the guidance line names the daily figure");
ok(/35 g per meal/.test(C.proteinSummary(201)), "and the per-meal figure");
// A heavier lifter gets a proportionally larger target — the old flat 100 g
// literal was the same for a 130 lb and a 250 lb lifter.
ok(C.proteinDailyTargetGrams(250) > C.proteinDailyTargetGrams(130), "the target scales with bodyweight");

// Age changes the per-meal threshold and nothing else. The daily figure is
// already the resistance-training one, so training type does not scale it.
ok(C.proteinPerMealGrams(201, 40) === 25, "under 65 uses the 0.25 g/kg per-meal threshold");
ok(C.proteinPerMealGrams(201, 70) === 35, "65+ uses the higher 0.4 g/kg threshold");
ok(C.proteinPerMealGrams(201, 65) === 35, "65 is the threshold, not one past it");
ok(C.proteinDailyTargetGrams(201) === 145, "the daily figure does not move with age");
// An unknown age takes the higher per-dose threshold: eating to it costs a
// younger lifter nothing, under-dosing an older one is the failure that matters.
ok(C.proteinMealGramsPerKg(null) === C.PROTEIN_MEAL_G_PER_KG_OLDER, "unknown age is conservative");
ok(C.proteinPerMealGrams(201, null) === 35, "and yields the older-adult figure");
ok(C.proteinPerMealRationale(null) === null, "nothing to explain when there is no age");
ok(/0\.4 g\/kg/.test(C.proteinPerMealRationale(70)), "the rationale names the older threshold");
ok(/0\.25 g\/kg/.test(C.proteinPerMealRationale(40)), "and the younger one");
// Age is never guessed from a nonsense birth year.
ok(C.ageFromBirthYear(1980, 2026) === 46, "a plausible birth year gives an age");
ok(C.ageFromBirthYear(0, 2026) === null, "unset is not a birth year");
ok(C.ageFromBirthYear(1899, 2026) === null, "before 1900 is not plausible");
ok(C.ageFromBirthYear(2030, 2026) === null, "not yet born");
ok(C.ageFromBirthYear(1901, 2026) === null, "past a plausible lifespan");
ok(C.ageFromBirthYear(2026, 2026) === 0, "born this year is age zero, not unknown");

// Session spacing is advisory and only speaks when it has something to say.
ok(C.sessionSpacingShortfall(1, 3) === 2, "one day into a three-day preference is two short");
ok(C.sessionSpacingShortfall(0, 3) === 3, "training the same day is the full shortfall");
ok(C.sessionSpacingShortfall(3, 3) === null, "meeting the preference says nothing");
ok(C.sessionSpacingShortfall(9, 3) === null, "being well past it says nothing");
ok(C.sessionSpacingShortfall(null, 3) === null, "no prior session says nothing");
ok(C.sessionSpacingShortfall(1, 0) === null, "no preference recorded says nothing");
ok(C.sessionSpacingShortfall(-1, 3) === null, "a negative gap is nonsense, not a warning");

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
// A LOADED accessory with a zero increment falls into the same branch: it
// climbs reps past its own maximum and the weight never moves. That is a
// misconfiguration, not a choice, so the program editor flags it.
let broken = { sets: 3, minReps: 8, maxReps: 12, currentReps: 12, weightLb: 75, incrementLb: 0, stallCount: 0 };
let brokenAdvance = C.advanceAccessory(broken, { completedSets: 3, minRepsAchieved: 12, anyStoppedEarly: false });
ok(brokenAdvance.weightLb === 75 && brokenAdvance.currentReps === 13,
  "a loaded accessory with no increment never adds load and climbs reps instead");
ok(C.accessoryCannotProgressLoad("dumbbell", "perImplement", 75, 0), "per-hand dumbbell slot with no increment is flagged");
ok(C.accessoryCannotProgressLoad("machine", "externalTotal", 120, 0), "machine slot with no increment is flagged");
ok(!C.accessoryCannotProgressLoad("timed", "externalTotal", 25, 0), "a timed slot progresses by duration, not load");
// A weighted pull-up is TYPED bodyweight but hangs real plates from a belt.
// Keying loadability on type alone silently exempted it, so a belt slot with a
// zero increment never progressed and never warned. Mirrors CadenceCore.
ok(C.accessoryCannotProgressLoad("bodyweight", "externalTotal", 25, 0),
  "a belt-loaded bodyweight slot with no increment is flagged");
ok(!C.accessoryCannotProgressLoad("bodyweight", "bodyweight", 0, 0),
  "an unloaded bodyweight slot has no load to step");
ok(!C.accessoryCannotProgressLoad("conditioning", "externalTotal", 20, 0),
  "a loaded carry progresses by distance or duration, not by a load increment");
ok(!C.accessoryCannotProgressLoad("conditioning", "externalTotal", 25, 0), "conditioning is not load-progressed");
ok(!C.accessoryCannotProgressLoad("bodyweight", "bodyweight", 0, 0), "bodyweight work has no load to add");
ok(!C.accessoryCannotProgressLoad("barbell", "bodyweight", 45, 0), "an explicit bodyweight basis wins over the equipment label");
ok(!C.accessoryCannotProgressLoad("dumbbell", "perImplement", 10, 2.5), "a fractional increment is a real increment");
ok(!C.accessoryCannotProgressLoad("DUMBBELL", "perImplement", 40, 5), "the type test is case-insensitive");
// An unloaded slot is not a misconfiguration: 0/0 is how "no external load" is
// spelled, and it is what every newly added accessory starts at.
ok(!C.accessoryCannotProgressLoad("dumbbell", "perImplement", 0, 0), "an unconfigured accessory is not flagged");
ok(!C.accessoryCannotProgressLoad("band", "externalTotal", 0, 0), "a band with no numeric load is not flagged");
// Fractional increments must survive: 5 lb on a 10 lb load is a 50% jump.
let fractional = C.advanceAccessory(
  { sets: 3, minReps: 8, maxReps: 12, currentReps: 12, weightLb: 10, incrementLb: 2.5, stallCount: 0 },
  { completedSets: 3, minRepsAchieved: 12, anyStoppedEarly: false });
ok(fractional.weightLb === 12.5 && fractional.currentReps === 8, "a 2.5 lb accessory increment is added unrounded");

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
eq(C.plateColorToken({ value: 2.5, unit: "kg" }, "steel"), "black", "2.5 kg calibrated steel is not an IWF red change plate");
eq(C.plateDiameterFactor({ value: 20, unit: "kg" }, "bumper"), 1, "20 kg bumper uses the 450 mm diameter");
eq(C.plateDiameterFactor({ value: 10, unit: "kg" }, "bumper"), 1, "10 kg bumper uses the 450 mm diameter");
ok(C.plateDiameterFactor({ value: 20, unit: "kg" }, "steel") > C.plateDiameterFactor({ value: 10, unit: "kg" }, "steel"),
  "calibrated steel diameter steps down by denomination");
ok(C.plateThicknessFactor({ value: 20, unit: "kg" }, "bumper") > C.plateThicknessFactor({ value: 20, unit: "kg" }, "steel"),
  "rubber bumpers consume more sleeve than calibrated steel");

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
// [INV-CARDIO-SOLVES-THE-THIRD] the treadmill case: pace and time are what the
// lifter sets, so the distance has to fall out rather than be worked out on the belt.
eq(C.cardioDistanceMiles(3.5, 1800), 1.75, "distance from speed + time");
eq(C.cardioDistanceMiles(4, 1350), 1.5, "distance from speed + time");
eq(C.cardioDistanceMiles(3.7, 1020), 1.0483, "stored finer than a treadmill displays; the label trims it");
// A one-minute interval at two decimals put 3.0 and 3.1 mph on the same 0.05 mi.
ok(C.cardioDistanceMiles(3.0, 60) !== C.cardioDistanceMiles(3.1, 60),
  "[INV-CARDIO-SOLVES-THE-THIRD] a 0.1 mph step survives a one-minute interval");
eq(C.cardioSpeedMph(C.cardioDistanceMiles(3.1, 60), 60), 3.1, "and reads back as the pace that was set");
eq(C.cardioDistanceMiles(null, 1800), null, "no speed → no distance");
eq(C.cardioDistanceMiles(3.5, null), null, "no time → no distance");
eq(C.cardioDistanceMiles(0, 0), null, "zeros → no distance");
eq(C.cardioDurationSeconds(1.75, 3.5), 1800, "time from distance + speed");
eq(C.cardioDurationSeconds(1.5, 4), 1350, "time from distance + speed");
eq(C.cardioDurationSeconds(null, 3.5), null, "no distance → no time");
eq(C.cardioDurationSeconds(2, null), null, "no speed → no time");
eq(C.cardioDurationSeconds(0, 0), null, "zeros → no time");
// [INV-CARDIO-SOLVES-THE-THIRD] only distance and duration persist, so a
// distance computed from speed must read back as that same speed.
for (const mph of [2.5, 3.0, 3.1, 3.5, 4.0, 5.5, 6.0, 7.5]) {
  for (const minutes of [1, 2, 5, 10, 15, 20, 30, 45, 60]) {
    const secs = minutes * 60;
    const miles = C.cardioDistanceMiles(mph, secs);
    ok(Math.abs(C.cardioSpeedMph(miles, secs) - mph) <= 0.001,
      `[INV-CARDIO-SOLVES-THE-THIRD] ${mph} mph for ${minutes}m reads back as that pace`);
    ok(Math.abs(C.cardioDurationSeconds(miles, mph) - secs) <= 30,
      `[INV-CARDIO-SOLVES-THE-THIRD] ${mph} mph over ${miles} mi reads back as that time`);
  }
}
// ---- health reconciliation (HealthComparisonTests.swift) ----
// [INV-HEALTH-IS-A-SECOND-OPINION] Health reports, it never overwrites.
{
  const min = (m) => new Date((1_780_000_000 + m * 60) * 1000);
  const agree = C.healthCompare(3.0, 3.04);
  eq(agree.kind, "agree", "two honest instruments never match exactly");
  ok(!agree.isDiscrepancy, "[INV-HEALTH-IS-A-SECOND-OPINION] a hundredth of a mile is not a discrepancy");
  eq(agree.adoptableMiles, null, "nothing to adopt when they agree");
  eq(C.healthCompare(10.0, 10.18).kind, "agree", "long efforts get proportional slack");
  eq(C.healthCompare(10.0, 10.6).kind, "healthHigher", "past the band it is a real disagreement");

  const higher = C.healthCompare(2.0, 2.4);
  eq(higher.kind, "healthHigher", "Health recorded further");
  eq(higher.adoptableMiles, 2.4, "adopting means taking Health's number");
  eq(C.healthCompare(3.0, 2.4).kind, "loggedHigher", "the log claims further");
  eq(C.healthCompare(3.0, 2.4).adoptableMiles, 2.4, "adopting still means taking Health's number");

  eq(C.healthCompare(null, 2.0).kind, "onlyHealth", "Health has work the log missed");
  eq(C.healthCompare(2.0, null).kind, "onlyLogged", "an unworn watch");
  eq(C.healthCompare(null, null).kind, "neither", "nothing either side");
  eq(C.healthCompare(0, 0).kind, "neither", "zeros are absence");
  ok(!C.healthCompare(5.0, null).isDiscrepancy,
    "[INV-HEALTH-IS-A-SECOND-OPINION] an unworn watch never reads as 'you logged too much'");
  eq(C.healthCompare(5.0, null).adoptableMiles, null, "there is nothing in Health to adopt");

  eq(C.healthOverlapSeconds(min(0), min(60), min(30), min(90)), 1800, "overlap in seconds");
  eq(C.healthOverlapSeconds(min(0), min(30), min(30), min(60)), 0, "touching is not overlapping");
  eq(C.healthOverlapSeconds(min(0), min(10), min(50), min(60)), 0, "disjoint");
  ok(C.healthSampleBelongsToSession(min(-5), min(45), min(0), min(60)),
    "the walk started in the car park still belongs to the session");
  ok(!C.healthSampleBelongsToSession(min(-40), min(5), min(0), min(60)),
    "the bike commute that ended as the session began does not");
  ok(!C.healthSampleBelongsToSession(min(10), min(10), min(0), min(60)),
    "a zero-length sample belongs to nothing");

  eq(C.healthComparisonLabel(C.healthCompare(3, 3)), "Health agrees: 3 mi", "agreement label");
  eq(C.healthComparisonLabel(higher), "Health recorded 2.4 mi · you logged 2 mi", "disagreement names both sides");
  eq(C.healthComparisonLabel(C.healthCompare(2, null)), "Nothing in Health for this session", "one-sided label");
  eq(C.healthComparisonLabel(C.healthCompare(null, null)), "No conditioning distance", "empty label");

  // [INV-HEALTH-IS-A-SECOND-OPINION] A read never counts Cadence's own writes.
  // Once Cadence writes distance, bodyweight and body fat into Health, every
  // read would otherwise find them and "confirm" the log against itself.
  const app = "com.example.cadence";
  ok(!C.healthSourceIsForeign(app, app),
    "[INV-HEALTH-IS-A-SECOND-OPINION] our own write is not a second opinion");
  ok(!C.healthSourceIsForeign("COM.EXAMPLE.CADENCE", app), "bundle ids are not case sensitive");
  ok(C.healthSourceIsForeign("com.apple.health", app), "another app is a real second opinion");
  ok(C.healthSourceIsForeign("com.example.cadence.watch", app),
    "a different bundle is a different source, prefix or not");
  ok(C.healthSourceIsForeign(null, app), "unattributable counts as foreign");
  ok(C.healthSourceIsForeign("  ", app), "blank counts as foreign");
  ok(C.healthSourceIsForeign(app, null),
    "[INV-HEALTH-IS-A-SECOND-OPINION] not knowing who we are cannot mean owning everything");

  const morning = min(0);
  const yesterday = new Date(morning.getTime() - 30 * 3600 * 1000);
  ok(C.healthIsSameWeighIn(197.2, morning, 197.2, morning), "the same weigh-in");
  ok(C.healthIsSameWeighIn(197.2, morning, 197.3, morning), "a kilogram round-trip is the same weigh-in");
  ok(!C.healthIsSameWeighIn(197.2, morning, 198.6, morning),
    "a genuinely different weight the same day stays offerable");
  ok(!C.healthIsSameWeighIn(197.2, yesterday, 197.2, morning),
    "yesterday's weight is not a duplicate of today's");

  const stage = (name, from, to) => ({ stage: name, start: min(from), end: min(to) });
  eq(C.healthAsleepSeconds([
    stage("inBed", 0, 30), stage("asleepCore", 30, 210), stage("asleepDeep", 210, 270),
    stage("awake", 270, 290), stage("asleepREM", 290, 380), stage("inBed", 380, 395),
  ]), 10800 + 3600 + 5400, "sleep is asleep stages only");
  eq(C.healthAsleepSeconds([]), 0, "no stages is no sleep");
  eq(C.healthAsleepSeconds([stage("inBed", 0, 480)]), 0,
    "a night on the mattress with no staging is not eight hours of sleep");
  eq(C.healthAsleepSeconds([stage("asleepCore", 60, 60)]), 0, "a zero-length stage is no sleep");
  eq(C.healthAsleepSeconds([stage("asleepCore", 60, 30)]), 0, "an inverted interval is not negative sleep");

  // [INV-HEALTH-IS-A-SECOND-OPINION] The anti-echo filter excludes Cadence,
  // not third parties, so several foreign sources can stage the same night.
  // Summing a watch and a sleep app would report sixteen hours for eight.
  eq(C.healthAsleepSeconds([
    stage("asleepCore", 0, 240), stage("asleepREM", 240, 480), stage("asleepUnspecified", 10, 470),
  ]), 480 * 60, "two instruments on one night is one night");
  eq(C.healthAsleepSeconds([stage("asleepCore", 0, 120), stage("asleepCore", 300, 360)]), 180 * 60,
    "genuinely disjoint sleep still adds — a nap is not an overlap");
  eq(C.healthAsleepSeconds([stage("asleepCore", 0, 240), stage("asleepCore", 200, 300)]), 300 * 60,
    "a longer-running source extends the union, never doubles it");
}

eq(C.cardioDurationLabel(1350), "22:30", "m:ss");
eq(C.cardioDurationLabel(65), "1:05", "single-digit minutes");
eq(C.cardioDurationLabel(5400), "1:30:00", "hour-plus gets h:mm:ss");
eq(C.cardioDurationLabel(0), "0:00", "zero");
// [INV-RUCK-CARRIES-ITS-LOAD] a ruck is a walk with a pack on; the pack is the point.
ok(C.cardioCarriesLoad("Ruck"), "[INV-RUCK-CARRIES-ITS-LOAD] a ruck carries load");
ok(C.cardioCarriesLoad("Sled Push"), "a sled carries load");
ok(!C.cardioCarriesLoad("Walk"), "a walk carries nothing");
ok(!C.cardioCarriesLoad("Bike"), "a bike carries nothing");
eq(C.cardioDefaultLoadLb("Ruck"), 20, "[INV-RUCK-CARRIES-ITS-LOAD] a ruck starts at a 20 lb pack");
eq(C.cardioDefaultLoadLb("Sled Push"), null, "sleds vary too much to have an honest default");
eq(C.cardioDefaultLoadLb("Walk"), null, "unloaded work has no default load");
eq(C.CARDIO_LOAD_INCREMENT_LB, 10, "[INV-RUCK-CARRIES-ITS-LOAD] packs move in 10 lb steps");
eq(C.cardioSetLabel(3, 2700, null, 20), "20 lb · 3 mi · 45:00 · 4 mph",
  "[INV-RUCK-CARRIES-ITS-LOAD] the pack weight leads the label");
eq(C.cardioSetLabel(3, 2700, null, 0), "3 mi · 45:00 · 4 mph", "unloaded work shows no load");
eq(C.cardioSetLabel(3, 2700, null), "3 mi · 45:00 · 4 mph", "the load argument is optional");
eq(C.cardioSetLabel(1.5, 1350, null), "1.5 mi · 22:30 · 4 mph", "full label");
eq(C.cardioSetLabel(3, 2700, 12), "3 mi · 45:00 · 4 mph · 12%", "fictional full-field fixture");
eq(C.cardioSetLabel(null, 1800, null), "30:00", "time only");
eq(C.cardioSetLabel(2, null, null), "2 mi", "distance only");
eq(C.cardioSetLabel(0.25, null, null), "0.25 mi", "quarter-mile keeps two decimals");
eq(C.cardioSetLabel(null, null, null), "—", "nothing logged yet");

// [INV-STAIRS-COUNT-FLIGHTS] a stair climber's belt goes nowhere; the console
// counts floors, so flights + time are logged and the pace is derived.
ok(C.cardioClimbsFlights("Stair Climber"), "[INV-STAIRS-COUNT-FLIGHTS] a stair climber counts flights");
ok(!C.cardioClimbsFlights("Walk"), "a walk covers ground");
ok(!C.cardioClimbsFlights("Elliptical"), "an elliptical is not a climber");
ok(!C.cardioClimbsFlights("Ruck"), "a ruck covers ground");
eq(C.cardioFlightPace(160, 1200), 8.0, "pace from flights + time");
eq(C.cardioFlightPace(55, 900), 3.7, "rounded to one decimal");
eq(C.cardioFlightPace(null, 1200), null, "no flights → no pace");
eq(C.cardioFlightPace(160, null), null, "no time → no pace");
eq(C.cardioFlightPace(0, 0), null, "zeros → no pace");
eq(C.cardioFlights(8, 1200), 160, "flights from pace + time");
eq(C.cardioFlights(7.5, 900), 112.5, "flights from pace + time");
// Whole flights would put 8.0 and 8.3 floors-per-minute on the same count over
// a short interval, exactly as two decimals of a mile collapsed 3.0 and 3.1 mph.
ok(C.cardioFlights(8.0, 30) !== C.cardioFlights(8.3, 30),
  "a 0.1 fl/min step must survive a thirty-second interval");
eq(C.cardioFlights(null, 1200), null, "no pace → no flights");
eq(C.cardioFlights(8, null), null, "no time → no flights");
eq(C.cardioFlights(0, 0), null, "zeros → no flights");
eq(C.cardioFlightDurationSeconds(160, 8), 1200, "time from flights + pace");
eq(C.cardioFlightDurationSeconds(60, 7.5), 480, "time from flights + pace");
eq(C.cardioFlightDurationSeconds(null, 8), null, "no flights → no time");
eq(C.cardioFlightDurationSeconds(160, null), null, "no pace → no time");
eq(C.cardioFlightDurationSeconds(0, 0), null, "zeros → no time");
// Only the count and the duration are stored, so a count solved from a pace has
// to read back as the pace that was set on the machine.
for (const pace of [4.0, 6.0, 7.5, 8.0, 8.3, 10.0, 12.5, 15.0]) {
  for (const minutes of [1, 2, 5, 10, 15, 20, 30, 45, 60]) {
    const secs = minutes * 60;
    const flights = C.cardioFlights(pace, secs);
    ok(Math.abs(C.cardioFlightPace(flights, secs) - pace) <= 0.001,
      `${pace} fl/min for ${minutes}m reads back as the same pace`);
    ok(Math.abs(C.cardioFlightDurationSeconds(flights, pace) - secs) <= 30,
      `${pace} fl/min over ${flights} flights reads back as the same time`);
  }
}
eq(C.cardioFlightsLabel(170), "170 flights", "whole counts stay whole");
eq(C.cardioFlightsLabel(1), "1 flight", "one flight is singular");
eq(C.cardioFlightsLabel(8.46), "8.5 flights", "a solved count keeps the decimal its pace implies");
eq(C.cardioSetLabel(null, 1200, null, null, 160), "160 flights · 20:00 · 8 fl/min",
  "[INV-STAIRS-COUNT-FLIGHTS] flights lead, and the pace is derived exactly like mph");
eq(C.cardioSetLabel(null, null, null, null, 160), "160 flights",
  "no time → no pace, the same way distance alone shows no mph");
eq(C.cardioSetLabel(1.5, 1350, null), "1.5 mi · 22:30 · 4 mph",
  "legacy conditioning is untouched by the flights argument");
// The editor's rows, its header, and the row's affordance line all read from
// one rule, so a row can never advertise a field the editor withholds.
eq(C.cardioFields("Stair Climber", 160, null, null).names.join(","), "flights,time,pace",
  "[INV-STAIRS-COUNT-FLIGHTS] a climber gets flights and a pace, and no incline");
eq(C.cardioFields("Stair Climber", 160, null, null).label, "flights · time · pace", "affordance line");
eq(C.cardioFields("Stair Climber", 160, null, null).headerLabel, "Flights · time · pace", "section header");
eq(C.cardioFields("Walk", null, 3, null).names.join(","), "distance,time,speed,incline",
  "a walk covers ground; it has no flight count");
eq(C.cardioFields("Ruck", null, 3, null).names.join(","), "load,distance,time,speed,incline",
  "the list names every row the editor shows, load and incline included");
// A climb logged before flights existed keeps the block it was recorded with —
// a field that disappears takes the only way to fix the value with it.
eq(C.cardioFields("Stair Climber", null, 0.75, 6).names.join(","),
  "flights,distance,time,speed,pace,incline",
  "[INV-STAIRS-COUNT-FLIGHTS] a pre-flights climb keeps its distance and incline editable");
eq(C.cardioFields("Stair Climber", null, null, null).names.join(","), "flights,time,pace",
  "an empty climb grows no distance block just because nothing is logged yet");

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
      { id: "squat", exerciseName: "Back Squat", dayIndex: 0, pattern: "squat", plannedSets: 3, role: "main", isMain: true },
      { id: "press-a", exerciseName: "Overhead Press", dayIndex: 1, pattern: "verticalPress", plannedSets: 3, role: "main", isMain: true },
      { id: "deadlift", exerciseName: "Deadlift", dayIndex: 2, pattern: "hipHinge", plannedSets: 3, role: "main", isMain: true },
      { id: "press-b", exerciseName: "Incline DB Press", dayIndex: 3, pattern: "horizontalPress", plannedSets: 3, role: "main", isMain: true },
      { id: "row", exerciseName: "Chest-supported Row", dayIndex: 3, pattern: "horizontalPull", plannedSets: 6, role: "accessory", maximumSets: 6 },
      { id: "bike", exerciseName: "Bike", dayIndex: 1, pattern: "easyAerobic", plannedSets: 1, role: "accessory" },
    ],
  };
  const coachingSession = (rotation, dayIndex, dayOffset, weight = 100, actual = weight) => {
    const names = ["Back Squat", "Overhead Press", "Deadlift", "Incline DB Press"];
    const patterns = ["squat", "verticalPress", "hipHinge", "horizontalPress"];
    const slotIDs = ["squat", "press-a", "deadlift", "press-b"];
    return {
      id: `1-${rotation}-${dayIndex}`, date: new Date(1_700_000_000_000 + dayOffset * 86_400_000).toISOString(),
      programID: "program", cycleNumber: 1, rotation, dayIndex, completed: true,
      exercises: [{
        slotID: slotIDs[dayIndex], programRole: "main",
        exerciseName: names[dayIndex], pattern: patterns[dayIndex],
        plannedSets: 3, plannedWeightLb: weight, plannedReps: 5,
        sets: Array.from({ length: 3 }, () => ({ actualWeightLb: actual, actualReps: 5, plannedWeightLb: weight, plannedReps: 5, completed: true })),
      }],
    };
  };

  let report = C.evaluateCoaching(coachingProgram, [coachingSession(1, 0, 0)]);
  eq(report.currentReadiness, "unknown", "first incomplete rotation is unknown without a baseline");
  eq(report.recommendations.length, 0, "incomplete rotation never adds volume");

  const partialComparable = Array.from({ length: 4 }, (_, dayIndex) =>
    coachingSession(1, dayIndex, dayIndex * 3));
  partialComparable.push(coachingSession(2, 0, 12, 105));
  partialComparable.push(coachingSession(2, 1, 15, 105));
  report = C.evaluateCoaching(coachingProgram, partialComparable);
  eq(report.currentReadiness, "green", "incomplete rotation reports provisional readiness after a baseline");
  ok(!report.rotations.at(-1).isComplete, "provisional readiness does not complete the rotation");
  ok(report.rotations.at(-1).reasons[0].includes("2/4 days banked"), "partial readiness explains rotation progress");
  eq(report.recommendations.length, 0, "provisional readiness never adds volume");

  const conditioningSessions = Array.from({ length: 4 }, (_, dayIndex) => coachingSession(1, dayIndex, dayIndex * 3));
  conditioningSessions[1].exercises.push({
    slotID: "bike", programRole: "accessory",
    exerciseName: "Bike", pattern: "easyAerobic", plannedSets: 1,
    sets: [{ actualWeightLb: 0, actualReps: 0, durationSeconds: 1_200, completed: true }],
  });
  conditioningSessions[0].exercises[0].sets.push({
    actualWeightLb: 120, actualReps: 1, plannedWeightLb: 120, plannedReps: 1,
    prescriptionBlock: "topSingle", completed: true,
  });
  conditioningSessions[0].exercises[0].sets.push({
    actualWeightLb: 500, actualReps: 20, plannedWeightLb: 500, plannedReps: 20,
    completed: true,
  });
  conditioningSessions[0].exercises.push({
    exerciseName: "Back Squat", pattern: "squat", plannedSets: 1,
    sets: [{ actualWeightLb: 500, actualReps: 20, completed: true }],
  });
  report = C.evaluateCoaching(coachingProgram, conditioningSessions);
  eq(report.rotations[0].plannedWorkingSets, 12, "conditioning does not inflate planned lifting sets");
  eq(report.rotations[0].completedWorkingSets, 12, "conditioning does not inflate completed lifting sets");
  eq(report.rotations[0].conditioningMinutes, 20, "conditioning remains in its minute ledger");
  eq(report.rotations[0].patternSets.squat, 3,
    "top singles, added sets, and slotless exercises are not program distribution");

  const sameLiftProgram = {
    id: "program", expectedDayIndexes: [0, 1], slots: [
      { id: "lower-b-main", exerciseName: "Back Squat", dayIndex: 0, pattern: "squat", plannedSets: 3, role: "main", isMain: true },
      { id: "lower-a-complementary", exerciseName: "Back Squat", dayIndex: 1, pattern: "squat", plannedSets: 3, role: "complementary" },
    ],
  };
  const squatExposure = (rotation, dayIndex, slotID, role, weight) => ({
    id: `${rotation}-${dayIndex}`, date: new Date(1_700_000_000_000 + (rotation * 10 + dayIndex) * 86_400_000).toISOString(),
    programID: "program", cycleNumber: 1, rotation, dayIndex, completed: true,
    exercises: [{ slotID, programRole: role, exerciseName: "Back Squat", pattern: "squat",
      plannedSets: 3, plannedWeightLb: weight, plannedReps: 3,
      sets: Array.from({ length: 3 }, () => ({ actualWeightLb: weight, actualReps: 3,
        plannedWeightLb: weight, plannedReps: 3, completed: true })) }],
  });
  report = C.evaluateCoaching(sameLiftProgram, [
    squatExposure(1, 0, "lower-b-main", "main", 225),
    squatExposure(1, 1, "lower-a-complementary", "complementary", 175),
    squatExposure(2, 0, "lower-b-main", "main", 225),
    squatExposure(2, 1, "lower-a-complementary", "complementary", 140),
  ]);
  eq(report.currentReadiness, "yellow", "same-name main and complementary output is compared by slot");

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

  sessions = [];
  for (let dayIndex = 0; dayIndex < 4; dayIndex++) sessions.push(coachingSession(1, dayIndex, dayIndex * 3, 100));
  for (let dayIndex = 0; dayIndex < 4; dayIndex++) sessions.push(coachingSession(2, dayIndex, 12 + dayIndex * 3, 90));
  for (let dayIndex = 0; dayIndex < 4; dayIndex++) sessions.push(coachingSession(3, dayIndex, 24 + dayIndex * 3, 81));
  report = C.evaluateCoaching(coachingProgram, sessions);
  eq(report.currentReadiness, "red", "a second consecutive red rotation stays red");
  eq(report.recommendations[0].ruleID, `readiness.red.persistent.recovery-rotation.v${C.COACHING_RULE_VERSION}`,
    "a red that survives the 25% cut escalates to a recovery rotation");
  eq(report.recommendations[0].change.percent, 50, "the recovery rotation halves accessory volume");
  ok(!report.recommendations.some((r) => r.change.percent === 25),
    "the escalation replaces the single-red rule rather than stacking with it");

  sessions = Array.from({ length: 4 }, (_, dayIndex) => coachingSession(1, dayIndex, dayIndex * 3));
  sessions[2].hasHardStopCheckIn = true;
  report = C.evaluateCoaching(coachingProgram, sessions);
  eq(report.currentReadiness, "red", "hard-stop recovery check-in makes a complete rotation red");
  ok(report.rotations[0].reasons.some((reason) => reason.includes("check-in")), "hard-stop check-in is explained");

  // ---- Rotation suggestions: shelved and stuck slots ----
  const withSlot = (id, patch) => ({
    ...coachingProgram,
    slots: coachingProgram.slots.map((slot) => (slot.id === id ? { ...slot, ...patch } : slot)),
  });
  const greenSessions = [];
  for (let rotation = 1; rotation <= 3; rotation++) {
    for (let dayIndex = 0; dayIndex < 4; dayIndex++) {
      greenSessions.push(coachingSession(rotation, dayIndex, ((rotation - 1) * 4 + dayIndex) * 3, 100 + (rotation - 1) * 5));
    }
  }
  const rotationOf = (rep) => rep.change.type === "rotateExercise";

  report = C.evaluateCoaching(withSlot("squat", { exerciseIsShelved: true }), greenSessions);
  let suggestion = report.recommendations.find(rotationOf);
  ok(!!suggestion, "a slot prescribing a shelved exercise is surfaced");
  eq(suggestion.ruleID, `program.slot.rotate.shelved.v${C.COACHING_RULE_VERSION}`, "shelved slots get their own rule");
  eq(suggestion.change.slotID, "squat", "the suggestion names the slot, not the exercise library");
  ok(suggestion.id.endsWith("-squat"), "one suggestion per slot, so two stuck slots do not collide on one id");

  // A stall is a program-hygiene signal, not a capacity one: it must surface
  // even when readiness has already claimed the headline.
  report = C.evaluateCoaching(withSlot("squat", { stallCount: 1 }), greenSessions);
  suggestion = report.recommendations.find(rotationOf);
  ok(!!suggestion, "one non-success cycle on a lift slot proposes a rotation");
  eq(suggestion.ruleID, `program.slot.rotate.stalled.v${C.COACHING_RULE_VERSION}`, "stalled slots get their own rule");

  sessions = [];
  for (let dayIndex = 0; dayIndex < 4; dayIndex++) sessions.push(coachingSession(1, dayIndex, dayIndex * 3, 100));
  for (let dayIndex = 0; dayIndex < 4; dayIndex++) sessions.push(coachingSession(2, dayIndex, 12 + dayIndex * 3, 90));
  report = C.evaluateCoaching(withSlot("squat", { stallCount: 1 }), sessions);
  eq(report.recommendations[0].change.type, "reduceAccessoryVolume", "readiness still leads the list");
  ok(report.recommendations.some(rotationOf), "a red rotation does not suppress the stall suggestion");

  // Accessory counters are unbounded and nothing ever resolves them, so a
  // single missed rep target must not read as a plateau.
  report = C.evaluateCoaching(withSlot("row", { stallCount: 1 }), greenSessions);
  ok(!report.recommendations.some(rotationOf), "one missed accessory exposure is not a plateau");
  report = C.evaluateCoaching(withSlot("row", { stallCount: 3 }), greenSessions);
  ok(report.recommendations.some(rotationOf), "three stuck accessory exposures propose a rotation");

  report = C.evaluateCoaching(withSlot("bike", { stallCount: 5, exerciseIsShelved: true }), greenSessions);
  ok(!report.recommendations.some(rotationOf), "conditioning slots are never rotated by this rule");

  // A rebuilt upper linear slot may change one dial: 3x5 -> 5x3. A miss
  // without the engine's 10% rebuild is not enough, and lower-body schedule
  // changes are deliberately outside this rule.
  const linearSessions = structuredClone(greenSessions);
  for (const session of linearSessions.filter((candidate) => candidate.dayIndex === 1)) {
    const press = session.exercises[0];
    press.prescriptionStyle = "linearFives";
    press.plannedWeightLb = 100;
    press.sets = press.sets.map((set) => ({
      ...set, actualWeightLb: 100, actualReps: 4, plannedWeightLb: 100, plannedReps: 5,
    }));
  }
  report = C.evaluateCoaching(withSlot("press-a", {
    prescriptionStyle: "linearFives", baseWeightLb: 90, workingSets: 3, workingReps: 5,
  }), linearSessions);
  let stage = report.recommendations.find((candidate) => candidate.change.type === "useLinearTriples");
  ok(stage?.change.slotID === "press-a", "a rebuilt upper linear slot proposes triples for that slot only");
  eq(stage.change.expectedBaseWeightLb, 90, "the stage change records the base it evaluated");
  eq(stage.ruleID, "program.slot.linear-triples.v1", "the adaptive stage has an independent rule version");
  ok(stage.explanation.includes("100 to 90 lb"), "the strategy transition explains the observed rebuild");

  report = C.evaluateCoaching(withSlot("press-a", {
    prescriptionStyle: "linearFives", baseWeightLb: 100, workingSets: 3, workingReps: 5,
  }), linearSessions);
  ok(!report.recommendations.some((candidate) => candidate.change.type === "useLinearTriples"),
    "three misses without the load rebuild do not trigger a stage change");

  report = C.evaluateCoaching(withSlot("press-a", {
    prescriptionStyle: "linearFives", baseWeightLb: 90, workingSets: 3, workingReps: 5,
    capacityManaged: false,
  }), linearSessions);
  ok(!report.recommendations.some((candidate) => candidate.change.type === "useLinearTriples"),
    "a slot that disallows coached sets cannot propose five sets");

  report = C.evaluateCoaching(withSlot("press-a", {
    prescriptionStyle: "linearFives", baseWeightLb: 90, workingSets: 3, workingReps: 5,
    maximumSets: 4,
  }), linearSessions);
  ok(!report.recommendations.some((candidate) => candidate.change.type === "useLinearTriples"),
    "a four-set slot cap cannot propose five sets");

  const oneMissSessions = structuredClone(greenSessions);
  const oneMiss = [...oneMissSessions].reverse().find((session) => session.dayIndex === 1).exercises[0];
  oneMiss.prescriptionStyle = "linearFives";
  oneMiss.plannedWeightLb = 100;
  oneMiss.sets[0] = { ...oneMiss.sets[0], actualReps: 4, plannedWeightLb: 100, plannedReps: 5 };
  report = C.evaluateCoaching(withSlot("press-a", {
    prescriptionStyle: "linearFives", baseWeightLb: 90, workingSets: 3, workingReps: 5,
  }), oneMissSessions);
  ok(!report.recommendations.some((candidate) => candidate.change.type === "useLinearTriples"),
    "a manual base reduction after one miss cannot masquerade as the three-miss reset");

  const recoveredSessions = structuredClone(linearSessions);
  const latestSuccess = coachingSession(4, 1, 48, 100);
  latestSuccess.exercises[0].prescriptionStyle = "linearFives";
  recoveredSessions.push(latestSuccess);
  report = C.evaluateCoaching(withSlot("press-a", {
    prescriptionStyle: "linearFives", baseWeightLb: 90, workingSets: 3, workingReps: 5,
  }), recoveredSessions);
  ok(!report.recommendations.some((candidate) => candidate.change.type === "useLinearTriples"),
    "a newer success makes an older three-miss run stale");

  const fiveByFiveSessions = structuredClone(linearSessions);
  for (const session of fiveByFiveSessions.filter((candidate) => candidate.dayIndex === 1)) {
    const press = session.exercises[0];
    press.plannedSets = 5;
    press.sets = Array.from({ length: 5 }, () => ({
      actualWeightLb: 100, actualReps: 4, plannedWeightLb: 100, plannedReps: 5,
    }));
  }
  report = C.evaluateCoaching(withSlot("press-a", {
    prescriptionStyle: "linearFives", baseWeightLb: 90, workingSets: 3, workingReps: 5,
  }), fiveByFiveSessions);
  ok(!report.recommendations.some((candidate) => candidate.change.type === "useLinearTriples"),
    "failed 5x5 history cannot masquerade as a failed 3x5 prescription");

  const lowerSessions = structuredClone(greenSessions);
  for (const session of lowerSessions.filter((candidate) => candidate.dayIndex === 0)) {
    const squat = session.exercises[0];
    squat.prescriptionStyle = "linearFives";
    squat.plannedWeightLb = 100;
    squat.sets = squat.sets.map((set) => ({
      ...set, actualWeightLb: 100, actualReps: 4, plannedWeightLb: 100, plannedReps: 5,
    }));
  }
  report = C.evaluateCoaching(withSlot("squat", {
    prescriptionStyle: "linearFives", baseWeightLb: 90, workingSets: 3, workingReps: 5,
  }), lowerSessions);
  ok(!report.recommendations.some((candidate) => candidate.change.type === "useLinearTriples"),
    "squat and pull transitions wait for authored light-day and frequency semantics");
}

// ---- Methodology styles: 5/3/1, max/dynamic effort, linear fives, Texas ----
{
  // 5/3/1 wave: base IS the training max; top set per week off the published %.
  const tm = (phase) => ({ cycleNumber: 1, baseWeightLb: 300, nextPhase: phase, incrementLb: 0 });
  let p = C.planForStyle(tm(1), 5, "fiveThreeOne");
  eq(`${p.weightLb}/${p.sets}x${p.reps}`, "255/1x5", "531 week 1 top set 85%×5+");
  p = C.planForStyle(tm(2), 5, "fiveThreeOne");
  eq(`${p.weightLb}/${p.sets}x${p.reps}`, "270/1x3", "531 week 2 top set 90%×3+");
  p = C.planForStyle(tm(3), 5, "fiveThreeOne");
  eq(`${p.weightLb}/${p.sets}x${p.reps}`, "285/1x1", "531 week 3 top set 95%×1+");
  p = C.planForStyle(tm(4), 5, "fiveThreeOne");
  eq(`${p.weightLb}/${p.sets}x${p.reps}`, "180/1x5", "531 deload 60%×5");

  // The top set is the "+" set — the AMRAP is 5/3/1's progression engine, and
  // shipping the percentages without it was the template's one real infidelity.
  const pres531 = C.sessionPrescription(tm(3), 5, "barbell", "squat", "main", "strength", "fiveThreeOne");
  eq(pres531.blocks.map((b) => b.kind).join(","), "ramp,ramp,amrap", "531 ramp precedes the + set");
  // The recovery bridge has no "+" set and trims the ramp to one set.
  const deload531 = C.sessionPrescription(tm(4), 5, "barbell", "squat", "main", "strength", "fiveThreeOne");
  eq(deload531.blocks.map((b) => b.kind).join(","), "ramp,work", "the 531 recovery bridge carries no + set and one ramp");
  // An AMRAP set is graded work. Filtering to "work" alone made it invisible:
  // uncounted for completion, ineligible as the top set, unable to reach the
  // e1RM sample — the entire point of the block.
  ok(C.countsAsPrescribedWork("amrap") && C.countsAsPrescribedWork("work"),
    "amrap and work are both prescribed work");
  ok(!["warmup", "primer", "ramp", "topSingle", "backoff"].some(C.countsAsPrescribedWork),
    "preparation and back-off work are not the prescription being graded");
  eq(pres531.blocks.map((b) => b.weightLb).join(","), "225,255,285", "531 week-3 ramp 75/85/95%");
  eq(pres531.blocks.map((b) => b.reps).join(","), "5,3,1", "531 week-3 reps 5/3/1");

  // Max effort: no more than three 90%+ singles; recovery trades them away.
  const me = C.sessionPrescription({ cycleNumber: 1, baseWeightLb: 315, nextPhase: 1, incrementLb: 0 },
    5, "barbell", "squat", "main", "strength", "maxEffort");
  eq(me.mainWork.weightLb, 315, "ME top single at the slot target");
  eq(me.blocks.map((b) => b.kind).join(","), "ramp,ramp,work", "ME opener, near-max and target");
  eq(me.blocks.map((b) => b.weightLb).join(","), "285,305,315", "ME carries three distinct heavy singles");
  const meDeload = C.planForStyle({ cycleNumber: 1, baseWeightLb: 315, nextPhase: 4, incrementLb: 0 }, 5, "maxEffort");
  eq(`${meDeload.weightLb}/${meDeload.sets}x${meDeload.reps}`, "220/2x3", "ME recovery is two moderate triples");

  // Dynamic effort: movement-pattern schemes and the 3-week wave.
  let de = C.planForStyle({ cycleNumber: 1, baseWeightLb: 150, nextPhase: 2, incrementLb: 0 }, 5, "dynamicEffort", {}, "squat");
  eq(`${de.weightLb}/${de.sets}x${de.reps}`, "165/12x2", "DE squat week 2 is 12 doubles at 55%");
  de = C.planForStyle({ cycleNumber: 1, baseWeightLb: 185, nextPhase: 1, incrementLb: 0 }, 5, "dynamicEffort", {}, "hinge");
  eq(`${de.sets}x${de.reps}`, "6x1", "DE speed pulls are singles");
  de = C.planForStyle({ cycleNumber: 1, baseWeightLb: 100, nextPhase: 3, incrementLb: 0 }, 5, "dynamicEffort", {}, "press");
  eq(`${de.weightLb}/${de.sets}x${de.reps}`, "125/9x3", "DE bench wave reaches 50% from a 40% base");

  // Linear fives ignore the three progression waves; recovery is the
  // intentional override and cannot advance the slot when banked.
  for (const phase of [1, 2, 3]) {
    const lp = C.planForStyle({ cycleNumber: 1, baseWeightLb: 205, nextPhase: phase, incrementLb: 0 }, 5, "linearFives", { workingSets: 3 });
    eq(`${lp.weightLb}/${lp.sets}x${lp.reps}`, "205/3x5", `linearFives constant at phase ${phase}`);
  }
  const triples = C.planForStyle(
    { cycleNumber: 1, baseWeightLb: 205, nextPhase: 2, incrementLb: 0 },
    5, "linearFives", { workingSets: 5, currentReps: 3 });
  eq(`${triples.weightLb}/${triples.sets}x${triples.reps}`, "205/5x3",
    "adaptive upper linear stage changes only 3x5 to 5x3");
  const triplesPreview = C.exposurePreview({
    count: 1, baseWeightLb: 205, prescriptionStyle: "linearFives",
    configuration: { workingSets: 5, currentReps: 3 },
  });
  eq(`${triplesPreview[0].prescription.mainWork.sets}x${triplesPreview[0].prescription.mainWork.reps}`,
    "5x3", "the editor preview preserves the triples stage");
  const recoveryLinear = C.planForStyle(
    { cycleNumber: 1, baseWeightLb: 205, nextPhase: 4, incrementLb: 0 }, 5, "linearFives", { workingSets: 3 });
  eq(`${recoveryLinear.weightLb}/${recoveryLinear.sets}x${recoveryLinear.reps}`, "165/2x3",
    "linear fives yield to the recovery prescription");

  // Style helpers.
  ok(C.advancesPerExposure("texasVolume") && C.advancesPerExposure("linearFives")
    && C.advancesPerExposure("maxEffort"), "exposure styles advance on their own cadence");
  ok(!C.advancesPerExposure("fiveThreeOne") && !C.advancesPerExposure("wave"), "wave styles grade at the Peak");
  ok(C.buildsOwnSessionShape("dynamicEffort") && !C.buildsOwnSessionShape("wave"), "own-shape styles skip primers");
  eq(C.defaultStartFraction("fiveThreeOne"), 0.90, "531 TM = 90% of e1RM");
  eq(C.defaultStartFraction("dynamicEffort"), 0.50, "speed work at 50%");
  eq(C.defaultStartFraction("wave"), 0, "classic wave has no methodology-mandated ratio");
  eq(C.templateStartFraction("wave"), 0.65, "template wave gets conservative history runway");
  eq(C.templateStartFraction("secondary"), 0.55, "template secondary work starts below wave work");
  eq(C.templateStartFraction("fiveThreeOne"), 0.90, "explicit methodology ratio wins in template setup");

  const mePreview = C.exposurePreview({
    count: 4, baseWeightLb: 315, estimatedMaxLb: 330, programRoundingLb: 5,
    exerciseType: "barbell", movementGroup: "press", prescriptionStyle: "maxEffort",
  });
  eq(mePreview.map((entry) => entry.baseWeightLb).join(","), "315,320,325,330",
    "ME advances after every exposure, independent of the DE wave");
  ok(mePreview.every((entry) => entry.phaseName == null), "ME never borrows wave phase names");
  const dePreview = C.exposurePreview({
    count: 4, baseWeightLb: 100, estimatedMaxLb: 250, programRoundingLb: 5,
    exerciseType: "barbell", movementGroup: "press", prescriptionStyle: "dynamicEffort",
  });
  eq(dePreview.map((entry) => entry.prescription.mainWork.weightLb).join(","), "100,115,125,100",
    "DE keeps its own 40/45/50 wave and reset");

  // Per-exposure linear progression: +10 lower per session, SS 3-miss deload.
  const rule = C.linearRule("linearFives", "squat");
  eq(`${rule.incrementLb}/${rule.stallLimit}/${rule.deloadFraction}`, "10/3/0.9", "novice lower rule");
  eq(C.linearRule("texasVolume", "press").incrementLb, 5, "texas upper +5 per completion");
  eq(C.linearRule("texasVolume", "squat").incrementLb, 5, "texas lower also +5 — twin A/B slots are synced");
  eq(C.linearRule("texasIntensity", "hinge").stallLimit, 2, "texas resets after 2 misses");
  const fives = { prescribedSets: 3, prescribedReps: 5, completedSets: 3, anyStoppedEarly: false, anyDroppedLoad: false, anyBelowPlanLoad: false, grindyOrWobbleSets: 0, topSetWeightLb: 205, topSetReps: 5 };
  const lin = { baseWeightLb: 205, estimatedMaxLb: 280, stallCount: 0, role: "main", lastIncrementLb: 0 };
  const up = C.advanceLinearLift(lin, fives, rule, 5);
  eq(up.state.baseWeightLb, 215, "novice squat +10 after a clean session");
  eq(up.state.stallCount, 0, "clean session clears stalls");
  const miss = { ...fives, completedSets: 2, topSetReps: 4 };
  const held = C.advanceLinearLift(lin, miss, rule, 5);
  eq(held.state.baseWeightLb, 205, "missed session holds the weight");
  eq(held.state.stallCount, 1, "missed session counts a stall");
  const third = C.advanceLinearLift({ ...lin, stallCount: 2 }, miss, rule, 5);
  eq(third.state.baseWeightLb, 185, "third consecutive miss deloads 10%");
  eq(third.state.stallCount, 0, "deload restarts the count");
  const grindy = { ...fives, grindyOrWobbleSets: 2 };
  const heldGrind = C.advanceLinearLift({ ...lin, stallCount: 2 }, grindy, rule, 5);
  eq(heldGrind.state.baseWeightLb, 205, "grindy-but-complete session holds the weight");
  eq(heldGrind.state.stallCount, 0, "a completed session breaks the consecutive-miss chain");
  const skipped = { ...miss, completedSets: 0, topSetWeightLb: 0, topSetReps: 0 };
  const heldSkip = C.advanceLinearLift(lin, skipped, rule, 5);
  eq(heldSkip.state.estimatedMaxLb, 280, "a fully missed top set never smooths the e1RM toward zero");

  // Cycle-graded methodology increments.
  const cleanTop = { prescribedSets: 1, prescribedReps: 1, completedSets: 1, anyStoppedEarly: false, anyDroppedLoad: false, anyBelowPlanLoad: false, grindyOrWobbleSets: 0, topSetWeightLb: 285, topSetReps: 3 };
  const tmState = { baseWeightLb: 300, estimatedMaxLb: 330, stallCount: 0, role: "main", lastIncrementLb: 0 };
  const tmUp = C.advanceProgramLift(tmState, cleanTop, "strength", "fiveThreeOne", "squat", 5);
  eq(tmUp.state.baseWeightLb, 310, "531 lower TM +10 per clean cycle");
  const missedTop = { ...cleanTop, completedSets: 0, anyStoppedEarly: true, topSetReps: 0 };
  const tmReset = C.advanceProgramLift(tmState, missedTop, "strength", "fiveThreeOne", "squat", 5);
  eq(tmReset.state.baseWeightLb, 270, "531 missed minimum resets TM three cycles back");
  eq(tmReset.state.estimatedMaxLb, 330, "531 reset never smooths the e1RM off a missed set");
  const droppedButMade = { ...cleanTop, anyDroppedLoad: true };
  const tmHeld = C.advanceProgramLift(tmState, droppedButMade, "strength", "fiveThreeOne", "squat", 5);
  eq(tmHeld.state.baseWeightLb, 300, "531 autoreg drop that made the reps holds the TM — no reset");
  eq(tmHeld.grade, "fail", "the compromised cycle still fails the grade");
  const tmSecond = C.advanceProgramLift({ ...tmState, stallCount: 1 }, droppedButMade, "strength", "fiveThreeOne", "squat", 5);
  eq(tmSecond.state.baseWeightLb, 270, "two compromised cycles self-correct the TM three cycles back");
  eq(tmSecond.state.stallCount, 0, "the compromised-cycle counter is consumed by the reset");
  const meMiss2 = C.advanceProgramLift({ ...tmState, baseWeightLb: 315 }, missedTop, "strength", "maxEffort", "press", 5);
  eq(meMiss2.state.stallCount, 0, "ME misses never accrue a counter another style could trip over");
  const madeSingle = { ...cleanTop, prescribedReps: 1, topSetWeightLb: 325, topSetReps: 1 };
  const meUp = C.advanceProgramLift({ ...tmState, baseWeightLb: 315 }, madeSingle, "strength", "maxEffort", "press", 5);
  eq(meUp.state.baseWeightLb, 330, "ME anchors a heavier made single before adding the next step");
  eq(meUp.state.estimatedMaxLb, 330, "a single is not inflated through a rep-max formula");
  const meMiss = C.advanceProgramLift({ ...tmState, baseWeightLb: 315 }, missedTop, "strength", "maxEffort", "press", 5);
  eq(meMiss.state.baseWeightLb, 315, "ME missed single holds — rotate instead");
  const deHold = C.advanceProgramLift({ ...tmState, baseWeightLb: 150 }, cleanTop, "strength", "dynamicEffort", "squat", 5);
  eq(deHold.state.baseWeightLb, 150, "DE base holds across cycles");
  eq(deHold.state.estimatedMaxLb, 330, "DE never smooths e1RM off speed doubles");
  const classic = C.advanceProgramLift(tmState, cleanTop, "strength", "wave", "squat", 5);
  ok(classic.state.baseWeightLb >= 300, "non-methodology styles keep the tapered rule");
}

// ---- The cycle's strength sample ----
{
  const at = (w, r) => C.strengthSampleIndex(w, r);
  // The whole point: an AMRAP taken at the top weight must win. Heaviest-first
  // gave the tie to the FIRST set at that weight and threw the extra reps away.
  eq(at([225, 225, 225], [3, 3, 8]), 2, "extra reps at the top weight are the cycle's best estimate");
  eq(at([225, 225], [3, 3]), 0, "with nothing to separate them the first top set stands");
  // ...and back-off volume must not win, which is why Epley beats raw reps.
  eq(at([215, 135], [3, 10]), 0, "a 135x10 back-off does not outrank a 215x3");
  eq(at([225, 185], [3, 10]), 0, "a heavy triple outranks a long back-off set");
  // Epley drifts high past ~10 reps, so a very long set is not a strength sample
  // while a usable one exists.
  eq(at([185, 95], [5, 25]), 0, "a 25-rep set is not allowed to masquerade as a max");
  eq(at([95, 95], [20, 25]), 1, "when every set is a long one, rank them anyway rather than reporting none");
  eq(at([], []), null, "no performed work is no sample");
  eq(C.epleyE1RM(215, 3).toFixed(1), "236.5", "the 215x3 that actually happened estimates 236.5");
}

// ---- Readiness-triggered deload ----
{
  const far = C.MINIMUM_ROTATIONS_BETWEEN_DELOADS;
  ok(C.shouldDeloadEarly(2, "red", "red", far), "two red rotations cut the cycle short");
  ok(C.shouldDeloadEarly(1, "red", "red", far), "rotation 1 can deload early once the floor is clear");
  // The floor is in rotations so it means the same thing on a 2-day split as on
  // a 6-day one. A session floor of 8 was unreachable inside a cycle below 4 days.
  eq(far, 2, "two complete rotations, whatever the split");

  ok(!C.shouldDeloadEarly(2, "red", "yellow", far), "one red rotation is noise, not a deload");
  ok(!C.shouldDeloadEarly(2, "red", "unknown", far), "a first-ever red has nothing to persist against");
  ok(!C.shouldDeloadEarly(2, "yellow", "red", far), "a recovered rotation finishes the cycle");

  // From rotation 3 the schedule walks into the deload by itself, and rotation
  // 4 IS the deload — jumping either would be a no-op that still writes holds.
  ok(!C.shouldDeloadEarly(3, "red", "red", far), "rotation 3 already advances into the deload");
  ok(!C.shouldDeloadEarly(C.DELOAD_WEEK, "red", "red", far), "the deload rotation cannot deload again");

  // The floor is what stops a run of red rotations turning the recovery deload
  // into the schedule.
  ok(!C.shouldDeloadEarly(2, "red", "red", far - 1), "a deload too soon after the last one is blocked");
  ok(C.shouldDeloadEarly(2, "red", "red", far + 10), "an old deload never blocks a new one");

  // e1RM observation outside the graded rotation: a capped AMRAP on the load
  // week must be able to raise the estimate, and a deload week must never
  // lower it.
  eq(C.observedMax(221.45, 236.5), C.smoothE1RM(221.45, 236.5), "a better sample smooths the estimate up");
  ok(C.observedMax(221.45, 236.5) > 221.45, "and it actually moves");
  eq(C.observedMax(221.45, 169), 221.45, "a deload set is not evidence the max fell");
  eq(C.observedMax(221.45, 221.45), 221.45, "an equal sample is no new information");
  eq(C.GRADED_WEEK, 3, "the graded rotation is the peak");

  // The hold is what keeps the skipped peak from reading as a missed peak.
  const stuck = { baseWeightLb: 225, estimatedMaxLb: 290, stallCount: 1, lastIncrementLb: 10 };
  const held = C.recoveryDeloadHold(stuck, 2);
  eq(held.grade, "hold", "a cycle the program cut short is a hold, not a fail");
  eq(held.state.baseWeightLb, 225, "the base holds — the lifter did not miss a peak, the peak never ran");
  eq(held.state.stallCount, 1, "no stall accrues for work that was never prescribed");
  eq(held.state.lastIncrementLb, 0, "the increment record stops advertising a bump that did not happen");
  ok(held.note.includes("rotation 2"), "the note says which rotation was cut short");
}

// ---- Style-aware labels (#105) ---------------------------------------------
// The rotation counter is shared by every slot; the phase NAMES are a claim
// about one slot's prescription. Rendering "Peak" against a linear slot asserts
// something about the engine that is false.
{
  ok(C.usesCyclePhases("wave") && C.usesCyclePhases("secondary") && C.usesCyclePhases("hypertrophy"),
    "the wave family and its volume cousins really do run V/L/P/D");
  ok(C.usesCyclePhases("technique"), "technique is phase-shaped too — it comes out of the shared table");
  for (const style of ["linearFives", "texasVolume", "texasLight", "texasIntensity",
    "doubleProgression", "fiveThreeOne", "maxEffort", "dynamicEffort"]) {
    ok(!C.usesCyclePhases(style), `[INV-PHASE-NAME-IS-PER-SLOT] ${style} does not use the phase vocabulary`);
    eq(C.slotPhaseLabel(3, "main", style), null,
      `[INV-PHASE-NAME-IS-PER-SLOT] ${style} gets no phase label at rotation 3`);
  }

  eq(C.slotPhaseLabel(3, "main", "wave"), "R3 Peak", "a wave slot still says which phase it is in");
  eq(C.slotPhaseLabel(4, "complementary", "automatic"), "R4 Recovery",
    "automatic resolves to secondary on a complementary slot, which is phase-shaped");
  eq(C.slotPhaseLabel(9, "main", "wave"), null, "an out-of-range rotation labels nothing");

  eq(C.slotBadge("main", "fiveThreeOne"), "Main · 5/3/1", "5/3/1 badge");
  eq(C.slotBadge("main", "linearFives"), "Main · Linear", "linear badge");
  eq(C.slotBadge("complementary", "automatic"), "Complementary · Secondary volume",
    "automatic names the style the engine will actually run, not the placeholder");
  eq(C.slotBadge("main", "automatic", "olympic"), "Main · Technique", "olympic auto-resolves to technique");
  eq(C.slotBadge("main", "automatic"), "Main · Wave", "a main strength slot resolves to the wave");

  eq(C.rotationLabel(2), "Rotation 2 of 4",
    "[INV-PHASE-NAME-IS-PER-SLOT] the program-level indicator is style-neutral");
  eq(C.rotationLabel(0), "Rotation 1 of 4", "rotation clamps low");
  eq(C.rotationLabel(7), "Rotation 4 of 4", "rotation clamps high");
  eq(C.rotationLabel(undefined), "Rotation 1 of 4", "a missing pointer never reads as NaN");
}

// ---- Exposure preview (#106) -----------------------------------------------
{
  // A wave slot walks V/L/P/R off one base, then rolls with the clean-peak bump.
  const wave = C.exposurePreview({ baseWeightLb: 190, estimatedMaxLb: 250, prescriptionStyle: "wave",
    movementGroup: "squat", programRoundingLb: 5, exerciseType: "barbell" });
  eq(wave.length, 4, "four exposures by default");
  eq(wave.map((e) => e.rotation).join(","), "1,2,3,4", "the wave walks the rotation in order");
  eq(wave.map((e) => e.prescription.mainWork.weightLb).join(","), "190,210,225,145",
    "[INV-PREVIEW-RUNS-THE-REAL-ENGINE] the preview reports the engine's own rounded loads");
  eq(wave[2].phaseName, "R3 Peak", "a wave exposure carries its phase name");
  ok(wave.every((e) => e.baseWeightLb === 190), "the base holds for a whole cycle, recovery included");
  ok((wave[2].advanceNote || "").includes("Clean peak"), "the peak exposure explains next cycle's bump");

  // The rounding boundary the issue calls out: two pounds of base apart, and
  // the peak triple lands a whole plate step apart. This is exactly the class
  // of defect the preview exists to make visible without a parameter sweep.
  const at188 = C.exposurePreview({ baseWeightLb: 188, prescriptionStyle: "wave", programRoundingLb: 5 });
  eq(at188[2].prescription.mainWork.weightLb, 220, "a 188 lb base peaks at 220");
  eq(wave[2].prescription.mainWork.weightLb, 225, "a 190 lb base peaks at 225 — one plate step for two pounds");

  // A per-exposure slot previews EXPOSURES: the base moves every session and no
  // phase name is ever attached, but the recovery rotation still holds.
  const linear = C.exposurePreview({ count: 5, baseWeightLb: 205, prescriptionStyle: "linearFives",
    movementGroup: "squat", programRoundingLb: 5, configuration: { workingSets: 3 } });
  eq(linear.map((e) => e.prescription.mainWork.weightLb).join(","), "205,215,225,190,235",
    "linear fives add 10 per exposure, cut to 80% for the recovery rotation, then resume from the held base");
  eq(linear.map((e) => e.baseWeightLb).join(","), "205,215,225,235,235",
    "the base advances per exposure and holds across recovery");
  ok(linear.every((e) => e.phaseName === null), "no phase name is rendered against a linear slot");
  ok(linear[3].isRecovery, "the recovery rotation is still flagged — it changes the prescription");

  // 5/3/1 previews its own shape: ramps plus a graded "+" set, never V/L/P.
  const wendler = C.exposurePreview({ count: 5, baseWeightLb: 200, prescriptionStyle: "fiveThreeOne",
    movementGroup: "press", programRoundingLb: 5 });
  eq(wendler.map((e) => e.prescription.mainWork.reps).join(","), "5,3,1,5,5", "5+/3+/1+/deload then round again");
  ok(wendler.every((e) => e.phaseName === null), "5/3/1 is never labelled Volume/Load/Peak");
  eq(wendler[0].prescription.blocks.filter((b) => b.kind === "ramp").length, 2, "the ramp sets are previewed");
  eq(wendler[0].prescription.blocks.at(-1).kind, "amrap", "weeks 1–3 top out on the + set");
  eq(wendler[3].prescription.blocks.at(-1).kind, "work", "the deload has no + set");
  eq(wendler[4].baseWeightLb, 205, "a clean cycle adds +5 to an upper-body training max at the rollover");
  eq(wendler[3].baseWeightLb, 200,
    "[INV-PREVIEW-RUNS-THE-REAL-ENGINE] and not before — recovery still runs off the old training max");

  // Double progression climbs the rep window before it touches the load.
  const dp = C.exposurePreview({ count: 4, baseWeightLb: 60, prescriptionStyle: "doubleProgression",
    exerciseType: "dumbbell", programRoundingLb: 10,
    configuration: { workingSets: 3, minimumReps: 6, maximumReps: 8, currentReps: 7 } });
  eq(dp.map((e) => `${e.prescription.mainWork.weightLb}x${e.prescription.mainWork.reps}`).join(","),
    "60x7,60x8,65x6,50x5", "reps climb to the cap, then load steps and reps drop back");
  ok(dp.every((e) => e.phaseName === null), "double progression is a rep window, not a phase");

  // A freshly added slot carries no rep-window keys at all. An explicit
  // `undefined` wins an object spread, so defaulting by spread would have
  // reached the engine as NaN and previewed a window of nothing.
  const bare = C.exposurePreview({ count: 2, baseWeightLb: 100, prescriptionStyle: "doubleProgression",
    programRoundingLb: 5, configuration: { workingSets: undefined, minimumReps: undefined,
      maximumReps: undefined, currentReps: undefined } });
  ok(bare.every((e) => Number.isFinite(e.prescription.mainWork.weightLb)
    && Number.isFinite(e.prescription.mainWork.reps) && e.prescription.mainWork.reps > 0),
    "a slot with no rep-window fields still previews real numbers");
  eq(bare[0].prescription.mainWork.reps, 5, "and falls back to the documented 5-rep default");

  // Day B is next, so its synchronized squat advances before Day A appears.
  // Day A was already banked in R2; its actual next exposure is R3.
  const twinned = C.exposurePreview({ count: 3, baseWeightLb: 205, rotation: 2,
    prescriptionStyle: "linearFives", movementGroup: "squat", programRoundingLb: 5,
    configuration: { workingSets: 3 }, schedule: {
      targetDayOrder: 0, nextDayOrder: 1, allDayOrders: [0, 1],
      recoveryDayOrders: [0], synchronizedDayOrders: [0, 1],
    } });
  eq(twinned.map((e) => e.rotation).join(","), "3,4,1",
    "the day pointer determines the slot's next actual rotation");
  eq(twinned.map((e) => e.baseWeightLb).join(","), "215,235,235",
    "the earlier twin moves the first load and Recovery holds it");

  const omittedRecovery = C.exposurePreview({ count: 2, baseWeightLb: 200, rotation: 4,
    prescriptionStyle: "wave", schedule: {
      targetDayOrder: 1, nextDayOrder: 0, allDayOrders: [0, 1],
      recoveryDayOrders: [0], synchronizedDayOrders: [1],
    } });
  eq(omittedRecovery.map((e) => e.rotation).join(","), "1,2",
    "a day omitted from the bridge has no fictional Recovery exposure");

  // A peak banked this cycle already carries an earned base. Recovery still
  // runs off the OLD one — the pending grade lands at the rollover, not before.
  const banked = C.exposurePreview({ count: 2, baseWeightLb: 200, rotation: 4, prescriptionStyle: "wave",
    programRoundingLb: 5,
    pendingState: { baseWeightLb: 210, estimatedMaxLb: 260, stallCount: 0, role: "main", lastIncrementLb: 10 } });
  eq(banked[0].baseWeightLb, 200, "recovery previews off the base the session will actually use");
  eq(banked[1].baseWeightLb, 210, "and the next cycle picks up the grade already banked at the peak");
  eq(C.exposurePreview({ count: 2, baseWeightLb: 200, rotation: 4, prescriptionStyle: "wave", programRoundingLb: 5 })[1]
    .baseWeightLb, 200, "with nothing banked the base simply holds");

  // The rollover mirrors rollOverRecovery's THREE branches, not just "apply the
  // pending". A per-exposure slot already advanced while training, so a stale
  // grade left by a later style edit is deleted rather than applied.
  const staleOnLinear = C.exposurePreview({ count: 5, baseWeightLb: 205, prescriptionStyle: "linearFives",
    movementGroup: "squat", programRoundingLb: 5, configuration: { workingSets: 3 },
    pendingState: { baseWeightLb: 150, estimatedMaxLb: 200, stallCount: 0, role: "main", lastIncrementLb: 0 } });
  eq(staleOnLinear.map((e) => e.prescription.mainWork.weightLb).join(","), "205,215,225,190,235",
    "a linear slot never drops to a phantom graded base at the rollover");

  // And a wave slot that reaches the rollover with no banked peak accrues a
  // stall toward the rebuild — the preview must show the drop that is coming.
  const skippedPeak = C.exposurePreview({ count: 3, baseWeightLb: 200, rotation: 4, stallCount: 1,
    prescriptionStyle: "wave", programRoundingLb: 5 });
  eq(skippedPeak.map((e) => e.baseWeightLb).join(","), "200,180,180",
    "a second peak-less cycle rebuilds at 90%, and the preview says so");
  eq(C.exposurePreview({ count: 3, baseWeightLb: 200, rotation: 4, stallCount: 0,
    prescriptionStyle: "wave", programRoundingLb: 5 }).map((e) => e.baseWeightLb).join(","), "200,200,200",
    "the first peak-less cycle only accrues the stall");

  // Contract edges.
  eq(C.exposurePreview({ baseWeightLb: 100, count: 0 }).length, 0, "a zero count previews nothing");
  eq(C.exposurePreview({ count: 2, baseWeightLb: 200, rotation: 3, prescriptionStyle: "wave" })
    .map((e) => e.rotation).join(","), "3,4", "the preview starts from the slot's current rotation");
}

// The rotation a charted session belongs to. Mirrors CadenceCore
// ChartRotation.label — same cases, same strings.
{
  // The per-entry phase wins where a slot carries one.
  eq(C.chartRotationLabel(2, 3), "R2 Load",
    "[INV-CHART-ROTATION-FROM-SESSION] a slot's own phase names its rotation");
  // Accessory slots and entries logged before per-entry phase capture carry
  // none, so the session's own rotation tag has to answer — this is the whole
  // bug: real program work charted as "Untracked".
  eq(C.chartRotationLabel(null, 3), "R3 Peak",
    "[INV-CHART-ROTATION-FROM-SESSION] an untagged entry inherits its session's rotation");
  eq(C.chartRotationLabel(undefined, 1), "R1 Volume",
    "[INV-CHART-ROTATION-FROM-SESSION] a missing entry phase is not an absent rotation");
  eq(C.chartRotationLabel(null, 4), "R4 Recovery",
    "[INV-CHART-ROTATION-FROM-SESSION] rotation 4 is Recovery");
  // Only a session with no program tag at all is genuinely untracked.
  eq(C.chartRotationLabel(null, null), "Untracked",
    "[INV-CHART-ROTATION-FROM-SESSION] a session outside a program is untracked");
  eq(C.chartRotationLabel(null, undefined), "Untracked",
    "[INV-CHART-ROTATION-FROM-SESSION] an absent tag is untracked");
  // A tag outside the rotation vocabulary is not invented into one.
  eq(C.chartRotationLabel(null, 0), "Untracked",
    "[INV-CHART-ROTATION-FROM-SESSION] rotation 0 is not a rotation");
  eq(C.chartRotationLabel(null, 9), "Untracked",
    "[INV-CHART-ROTATION-FROM-SESSION] a rotation beyond the cycle is not invented");

  // Every label the split view can produce must have a palette entry, or a
  // rotation silently loses its colour (R4 did, through the Deload rename).
  const { ROTATION_COLORS } = await import("../app/js/charts.js");
  const produced = [1, 2, 3, 4].map((r) => C.chartRotationLabel(null, r)).concat(C.UNTRACKED_ROTATION);
  const uncoloured = produced.filter((label) => !ROTATION_COLORS[label]);
  eq(uncoloured.join(",") || "none", "none",
    "[INV-CHART-ROTATION-FROM-SESSION] every rotation label has a chart colour");
}

// Where a lift is heading, fitted from what was performed. Mirrors CadenceCore
// TrendProjectionTests — same samples, same numbers.
{
  const S = (pairs) => pairs.map(([day, value]) => ({ day, value }));
  const climb = S([[0, 200], [7, 205], [14, 210], [21, 215], [28, 220]]);
  const near = (a, b, msg) => ok(Math.abs(a - b) < 0.0001, `${msg} (got ${a})`);

  // A history that climbed 5 lb a week projects 5 lb a week. The line is the
  // rate the lifter already walked, not a target anyone set.
  const up = C.projectTrend(climb, 30, 28);
  near(up.perWeek, 5, "[INV-PROJECTION-IS-THE-PERFORMED-RATE] the projection is the performed rate");
  near(up.fitQuality, 1, "[INV-PROJECTION-DECLARES-ITS-FIT] a clean climb fits perfectly");
  near(up.horizonDay, 58, "[INV-PROJECTION-IS-THE-PERFORMED-RATE] the horizon lands past today");
  near(up.horizonValue, 241.4285714, "[INV-PROJECTION-IS-THE-PERFORMED-RATE] the horizon value follows the fit");
  // Weekly steps from the last performed session, ending exactly on the
  // horizon so the line reaches the date the caption names.
  eq(up.points.map((p) => p.day).join(","), "28,35,42,49,56,58",
    "[INV-PROJECTION-IS-THE-PERFORMED-RATE] weekly steps ending on the horizon");
  near(up.points[0].value, 220, "[INV-PROJECTION-DECLARES-ITS-FIT] the line starts at the fitted value");
  near(up.points.at(-1).value, up.horizonValue, "[INV-PROJECTION-IS-THE-PERFORMED-RATE] the last point is the horizon");

  // Bad news is data.
  const down = C.projectTrend(S([[0, 220], [7, 215], [14, 210], [21, 205], [28, 200]]), 30, 28);
  near(down.perWeek, -5, "[INV-PROJECTION-IS-THE-PERFORMED-RATE] a decline projects downward");
  near(down.horizonValue, 178.5714286, "[INV-PROJECTION-IS-THE-PERFORMED-RATE] the decline continues");

  // ...but never through the floor.
  const floor = C.projectTrend(S([[0, 100], [7, 75], [14, 50], [21, 25]]), 90, 21);
  near(floor.perWeek, -25, "[INV-PROJECTION-IS-THE-PERFORMED-RATE] a steep slide keeps its rate");
  near(floor.horizonValue, 0, "[INV-PROJECTION-IS-THE-PERFORMED-RATE] no projection below zero");
  ok(floor.points.every((p) => p.value >= 0),
    "[INV-PROJECTION-IS-THE-PERFORMED-RATE] no projected point below zero");

  // Refusals.
  eq(C.projectTrend(S([[0, 200], [14, 210], [28, 220]]), 30, 28), null,
    "[INV-PROJECTION-REFUSES-THIN-HISTORY] three exposures is an anecdote");
  eq(C.projectTrend(S([[0, 200], [3, 205], [7, 210], [10, 215]]), 30, 10), null,
    "[INV-PROJECTION-REFUSES-THIN-HISTORY] four sessions in ten days say nothing about a month out");
  eq(C.projectTrend(climb, 30, 70), null,
    "[INV-PROJECTION-REFUSES-THIN-HISTORY] a lift untouched for six weeks is not extended");
  ok(C.projectTrend(climb, 30, 63) !== null,
    "[INV-PROJECTION-REFUSES-THIN-HISTORY] one day inside the staleness limit still projects");
  eq(C.projectTrend(climb, 0, 28), null,
    "[INV-PROJECTION-REFUSES-THIN-HISTORY] the off horizon projects nothing");

  // A line drawn through noise still has a slope. Reporting how badly it fits
  // is what stops that slope from reading as a finding.
  const noisy = C.projectTrend(S([[0, 200], [7, 300], [14, 200], [21, 300]]), 30, 21);
  near(noisy.perWeek, 20, "[INV-PROJECTION-DECLARES-ITS-FIT] noise still has a slope");
  near(noisy.fitQuality, 0.2, "[INV-PROJECTION-DECLARES-ITS-FIT] and the fit says how little it means");
  eq(C.fitDescription(noisy.fitQuality), "very noisy — treat as a guess",
    "[INV-PROJECTION-DECLARES-ITS-FIT] a poor fit says so in words");

  const flat = C.projectTrend(S([[0, 200], [7, 200], [14, 200], [21, 200]]), 30, 21);
  near(flat.perWeek, 0, "[INV-PROJECTION-DECLARES-ITS-FIT] a flat history has no rate");
  near(flat.fitQuality, 1, "[INV-PROJECTION-DECLARES-ITS-FIT] a flat line describes it perfectly");
  near(flat.horizonValue, 200, "[INV-PROJECTION-DECLARES-ITS-FIT] and projects flat");

  eq(C.fitDescription(1), "steady trend", "[INV-PROJECTION-DECLARES-ITS-FIT] fit band: steady");
  eq(C.fitDescription(0.75), "steady trend", "[INV-PROJECTION-DECLARES-ITS-FIT] fit band edge: steady");
  eq(C.fitDescription(0.74), "rough trend", "[INV-PROJECTION-DECLARES-ITS-FIT] fit band: rough");
  eq(C.fitDescription(0.4), "rough trend", "[INV-PROJECTION-DECLARES-ITS-FIT] fit band edge: rough");
  eq(C.fitDescription(0.39), "very noisy — treat as a guess", "[INV-PROJECTION-DECLARES-ITS-FIT] fit band: noisy");

  // The chart converts to the display unit before projecting. A linear fit
  // commutes with that scaling, so kg and lb describe the same line.
  const kg = C.projectTrend(climb.map((s) => ({ day: s.day, value: C.kgFromLb(s.value) })), 30, 28);
  near(kg.perWeek, C.kgFromLb(up.perWeek), "[INV-PROJECTION-IS-THE-PERFORMED-RATE] the rate scales with the unit");
  near(kg.horizonValue, C.kgFromLb(up.horizonValue), "[INV-PROJECTION-IS-THE-PERFORMED-RATE] so does the horizon");
  near(kg.fitQuality, up.fitQuality, "[INV-PROJECTION-DECLARES-ITS-FIT] the fit is unit-free");

  // Copy always says "at this rate".
  eq(C.trendSummary(5, "1 month", "241 lb", "lb"), "+5 lb/week · 241 lb in 1 month at this rate",
    "[INV-PROJECTION-IS-THE-PERFORMED-RATE] the summary hedges the number");
  eq(C.trendSummary(-2.25, "3 months", "180 lb", "lb"), "−2.3 lb/week · 180 lb in 3 months at this rate",
    "[INV-PROJECTION-IS-THE-PERFORMED-RATE] a falling rate reads as falling");
  eq(C.trendSummary(0, "1 month", "200 lb", "lb"), "Holding flat · 200 lb in 1 month at this rate",
    "[INV-PROJECTION-IS-THE-PERFORMED-RATE] flat says flat");
  eq(C.trendSummary(0.04, "1 month", "200 lb", "lb"), "Holding flat · 200 lb in 1 month at this rate",
    "[INV-PROJECTION-IS-THE-PERFORMED-RATE] a rate that rounds away is flat, not a vanishing +0");

  eq(C.TREND_HORIZONS.map((h) => h.value).join(","), "0,30,90", "the horizons are off, one month, three");
  eq(C.TREND_HORIZONS.map((h) => h.label).join(","), "Off,1 month,3 months", "and say so in words");
}

// The grade fires at the Peak, whose top set is base-multiplied by design — so
// the performed weight cannot feed the base directly. Its overshoot RATIO over
// its own plan can. Mirrors CadenceCore ProgramProgressionTests — same
// numbers, same tolerances.
{
  const near = (a, b, msg) => ok(Math.abs(a - b) < 0.0001, `${msg} (got ${a}, want ${b})`);
  const inc = C.focusIncrement(200, "strength", 5);
  const state = { baseWeightLb: 200, estimatedMaxLb: 260, stallCount: 0, role: "main", lastIncrementLb: 0 };
  const perf = (top, planned) => ({
    prescribedSets: 3, prescribedReps: 3, completedSets: 3, anyStoppedEarly: false,
    anyDroppedLoad: false, anyBelowPlanLoad: false, grindyOrWobbleSets: 0,
    topSetWeightLb: top, topSetReps: 3, plannedTopWeightLb: planned ?? 0,
  });

  const rode = C.advanceCycleLift(state, perf(245, 235), "strength", 5);
  near(rode.state.baseWeightLb, 200 * (245 / 235) + inc,
    "[INV-PROGRESSION-RIDES-PERFORMED] ten pounds over plan rides into the base");
  ok(/above plan/.test(rode.note), "[INV-PROGRESSION-RIDES-PERFORMED] and the note says so");

  near(C.advanceCycleLift(state, perf(237.4, 235), "strength", 5).state.baseWeightLb, 200 + inc,
    "[INV-PROGRESSION-RIDES-PERFORMED] a sub-half-step overshoot is rack noise, not signal");
  near(C.advanceCycleLift(state, perf(237.5, 235), "strength", 5).state.baseWeightLb,
    200 * (237.5 / 235) + inc,
    "[INV-PROGRESSION-RIDES-PERFORMED] exactly the half step fires");
  near(C.advanceCycleLift(state, perf(245, null), "strength", 5).state.baseWeightLb, 200 + inc,
    "[INV-PROGRESSION-RIDES-PERFORMED] a performance with no recorded plan keeps the old advance exactly");
  // Below plan cannot reach this path at all — it fails the grade first — so
  // the ratio can never move the base downward.
  const below = C.advanceCycleLift(state,
    { ...perf(228, 235), anyBelowPlanLoad: true }, "strength", 5);
  ok(below.grade === "fail" && below.state.baseWeightLb === 200,
    "[INV-PROGRESSION-RIDES-PERFORMED] under plan fails the grade and holds — never advances downward");
}

// An earned advance must buy plates, not just a bigger label: in a kg rack,
// 215 and 225 both solve to the identical 2×20 kg stack, so the stored base
// can trail what the bar actually carried. performedLabel names the stack;
// honestBase repairs the plan; the graded advance rides the volume exposure
// to resync the base. Mirrors CadenceCore PlateMathTests /
// ProgramProgressionTests — same numbers, same tolerances.
{
  const near = (a, b, msg) => ok(Math.abs(a - b) < 0.0001, `${msg} (got ${a}, want ${b})`);

  eq(C.performedLabel(221.37), 225, "[INV-ADVANCE-BUYS-PLATES] 2×20 kg a side on a 45 bar goes by 225");
  eq(C.performedLabel(232.39), 235, "[INV-ADVANCE-BUYS-PLATES] 20+20+2.5 kg a side goes by 235");
  eq(C.performedLabel(226.87), 230, "[INV-ADVANCE-BUYS-PLATES] 20+20+1.25 kg a side goes by 230");
  eq(C.performedLabel(397.74), 405,
    "[INV-ADVANCE-BUYS-PLATES] four 20 kg pairs drift past one grid step and still find their 405 label");
  eq(C.performedLabel(838.66), 855,
    "[INV-ADVANCE-BUYS-PLATES] nine 20 kg pairs drift three grid steps up and still find their label");
  eq(C.performedLabel(67.05), 65,
    "[INV-ADVANCE-BUYS-PLATES] a 5 kg pair outweighs its 10-a-side label — the true label sits BELOW the raw mass");
  eq(C.performedLabel(225), 225, "[INV-ADVANCE-BUYS-PLATES] a grid-clean load is its own label");
  eq(C.performedLabel(223), 225, "[INV-ADVANCE-BUYS-PLATES] no twin label → the next grid step up, never understating");
  eq(C.performedLabel(0), 0, "no load, no label");

  eq(C.honestBase(225, 10, 221.37, 5, 45), 235,
    "[INV-ADVANCE-BUYS-PLATES] label(221.4) + 10 = 235 — the kg twin stack 232.4 is finally a heavier bar");
  eq(C.honestBase(225, 10, 225, 5, 45), 235,
    "[INV-ADVANCE-BUYS-PLATES] a canonically-stored volume exposure repairs identically");
  eq(C.honestBase(225, 10, 215, 5, 45), 225,
    "[INV-ADVANCE-BUYS-PLATES] a clean lb lifter's performed weight IS the pre-advance base — untouched");
  eq(C.honestBase(225, 10, 235, 5, 45), 235,
    "[INV-ADVANCE-BUYS-PLATES] once the bumped exposure is banked, the cap holds the plan steady");
  eq(C.honestBase(225, 0, 221.37, 5, 45), 225,
    "[INV-ADVANCE-BUYS-PLATES] no earned increment (hold, deload, or a hand-set base) — no repair");
  eq(C.honestBase(105, 5, 101.9, 5, 45), 105,
    "[INV-ADVANCE-BUYS-PLATES] raw compare: 101.9 does not clear 102.5, and its 105 ceiling must not pretend it does");
  eq(C.honestBase(300, 10, 221.37, 5, 45), 300,
    "[INV-ADVANCE-BUYS-PLATES] never downward — a base above the log stands");
  eq(C.honestBase(200, 10, 221.37, 5, 45), 200,
    "[INV-ADVANCE-BUYS-PLATES] evidence more than one increment above the base is a hand-set base or off-program work — left alone");

  // Bonus work the lifter ADDED past the prescription arms one staged
  // increment of catch-up — the base chases demonstrated capability, one
  // step per cycle, and grading still never sees the bonus rows. Mirrors
  // CadenceCore — same numbers (base 226, 220×5 at plan + 245×3 bonus,
  // rebuild step 10 → plan from 236; the card rounds to 235).
  eq(C.honestBase(226, 5, 220, 5, 45, 245, 10), 236,
    "[INV-ADVANCE-BUYS-PLATES] 245×3 added past a 220×5 prescription lifts the plan one rebuild step above the base");
  eq(C.honestBase(226, 5, 220, 5, 45, 227, 10), 226,
    "[INV-ADVANCE-BUYS-PLATES] a bonus set inside the half-step band is noise, not a signal");
  eq(C.honestBase(226, 5, 220, 5, 45, 245, 0), 231,
    "[INV-ADVANCE-BUYS-PLATES] without a staged step the last earned increment bounds the catch-up");
  eq(C.honestBase(226, 0, 220, 5, 45, 245, 10), 226,
    "[INV-ADVANCE-BUYS-PLATES] a hand-set base is never repaired, bonus work or not");
  eq(C.honestBase(225, 10, 221.37, 5, 45, 245, 10), 235,
    "[INV-ADVANCE-BUYS-PLATES] the stale-label repair and the bonus catch-up agree on the same honest plan");

  const state = { baseWeightLb: 225, estimatedMaxLb: 280, stallCount: 0, role: "main", lastIncrementLb: 0 };
  const clean = {
    prescribedSets: 3, prescribedReps: 3, completedSets: 3, anyStoppedEarly: false,
    anyDroppedLoad: false, anyBelowPlanLoad: false, grindyOrWobbleSets: 0,
    topSetWeightLb: 264, topSetReps: 3, plannedTopWeightLb: 264,
  };
  const inc = C.stagedIncrement(225, "strength", "rebuild", 5);
  near(C.advanceCycleLift(state, clean, "strength", 5, "rebuild", false, 235).state.baseWeightLb,
    235 + inc, "[INV-ADVANCE-BUYS-PLATES] the base advances from the volume rotation actually lifted");
  near(C.advanceCycleLift(state, clean, "strength", 5, "rebuild", false, 225).state.baseWeightLb,
    225 + inc, "[INV-ADVANCE-BUYS-PLATES] a volume label equal to the base changes nothing");
  const held = C.advanceCycleLift(state, { ...clean, anyBelowPlanLoad: true },
    "strength", 5, "rebuild", false, 235);
  ok(held.grade === "fail" && held.state.baseWeightLb === 235
    && held.state.lastIncrementLb === 0 && held.state.stallCount === 1,
    "[INV-ADVANCE-BUYS-PLATES] a failed grade holds the increment, but the base still resyncs to the volume the cycle actually ran");
  ok(C.advanceCycleLift(state, { ...clean, anyBelowPlanLoad: true },
    "strength", 5, "rebuild", false, 220).state.baseWeightLb === 225,
    "[INV-ADVANCE-BUYS-PLATES] lighter volume evidence never drags a held base down");
}

// The kg↔lb denomination twins: the plate is the currency, the number is its
// label. Mirrors CadenceCore PlateMathTests/ProgramProgressionTests — same
// stacks, same masses.
{
  // The greedy decomposition names the stack a lifter actually builds.
  ok(Math.abs(C.kgTwinSideMassLb(90) - 2 * 20 / C.KG_PER_LB) < 1e-6,
    "[INV-PLATES-ARE-THE-CURRENCY] 90/side is two 45s, twinned to two 20 kg");
  ok(C.kgTwinSideMassLb(91) === null,
    "[INV-PLATES-ARE-THE-CURRENCY] a non-stack side has no twin");
  ok(C.kgTwinSideMassLb(Infinity) === null,
    "[INV-PLATES-ARE-THE-CURRENCY] a non-finite side refuses instead of looping the greedy solver");
  ok(C.kgTwinSideMassLb(NaN) === null,
    "[INV-PLATES-ARE-THE-CURRENCY] NaN has no twin");
  ok(C.plateEquivalent(Infinity, 221.37) === false,
    "[INV-PLATES-ARE-THE-CURRENCY] a non-finite target cannot claim equivalence");

  // The motivating session: a 225 plan loaded as 2×20 kg per side on a 45 bar.
  ok(C.plateEquivalent(225, 221.37),
    "[INV-PLATES-ARE-THE-CURRENCY] the kg stack IS the 225 plan");
  // The same plates on the bar's own twin (20 kg bar) also count.
  ok(C.plateEquivalent(225, 20 / C.KG_PER_LB + 4 * (20 / C.KG_PER_LB)),
    "[INV-PLATES-ARE-THE-CURRENCY] a 20 kg bar twins the 45 the same way the plates do");
  // 221.4 against a 215 plan is an OVERSHOOT, not a twin — that case belongs
  // to the performed-overshoot advance, not to equivalence.
  ok(!C.plateEquivalent(215, 221.37),
    "[INV-PLATES-ARE-THE-CURRENCY] an overshoot is not an equivalence");
  // The flat 2 lb band dies as plates stack; the twin does not. Four pairs a
  // side is ~7.3 lb adrift and still the same plates.
  const heavyTwin = 45 + 8 * (20 / C.KG_PER_LB);
  ok(C.plateEquivalent(405, heavyTwin),
    "[INV-PLATES-ARE-THE-CURRENCY] a four-pair side twins despite ~7 lb of drift");

  // Grading: the twin stack is AT plan — this is the stall trap, closed.
  ok(!C.belowPlanLoad(221.37, 225, 5),
    "[INV-PLATES-ARE-THE-CURRENCY] the twin stack does not grade below plan");
  ok(!C.belowPlanWork([221.37, 221.37, 221.37], 225, 3, 5),
    "[INV-PLATES-ARE-THE-CURRENCY] a twin session keeps its prescribed-set count");
  ok(C.belowPlanLoad(210.3, 225, 5),
    "[INV-PLATES-ARE-THE-CURRENCY] a genuinely lighter stack still grades below plan");

  // Storing: the canonical number stays on the card past the absolute band.
  eq(C.storedPrescription(405, heavyTwin), 405,
    "[INV-PLATES-ARE-THE-CURRENCY] the twin stores the programmed number, not the drift");
  eq(C.storedPrescription(405, 380), 380,
    "[INV-PLATES-ARE-THE-CURRENCY] a non-twin unreachable target still stores what the rack can do");
  eq(C.storedPrescription(220, 221.37), 220,
    "[INV-LOAD-STORED-NEAT] the absolute band is untouched underneath");

  // The bar's denomination label, not its converted mass, is what the twin
  // maths against — and threading it is what lets a 35-class plan twin at all.
  eq(C.barLabelLb(C.BARS.bar35lb), 35,
    "[INV-PLATES-ARE-THE-CURRENCY] an lb bar is its own label");
  eq(C.barLabelLb(C.BARS.bar20kg), 45,
    "[INV-PLATES-ARE-THE-CURRENCY] a 20 kg bar labels under the 45");
  eq(C.barLabelLb(C.BARS.bar15kg), 35,
    "[INV-PLATES-ARE-THE-CURRENCY] a 15 kg bar labels under the 35");
  const thirtyFiveTwin = 35 + 8 * (20 / C.KG_PER_LB);
  eq(C.storedPrescription(395, thirtyFiveTwin, 35), 395,
    "[INV-PLATES-ARE-THE-CURRENCY] a 35-bar plan twins when its own bar is threaded through");
  eq(C.storedPrescription(395, thirtyFiveTwin), thirtyFiveTwin,
    "[INV-PLATES-ARE-THE-CURRENCY] without the bar the decomposition is wrong and the achieved load stays");

  // Equivalence is a barbell concept: 100 kg happens to match a fake
  // "20 kg bar + 2×20 kg plates" reading of a 225 plan. On a real bar that
  // IS the plan; a machine or dumbbell has no bar to read.
  const hundredKg = 100 / C.KG_PER_LB;
  ok(!C.belowPlanLoad(hundredKg, 225, 5, 45),
    "[INV-PLATES-ARE-THE-CURRENCY] on the bar, 100 kg is the 225 plan on the bar's own kg twin");
  ok(C.belowPlanLoad(hundredKg, 225, 5, null),
    "[INV-PLATES-ARE-THE-CURRENCY] off the bar, no plate reading exists and the miss stands");
  ok(C.belowPlanWork([hundredKg, hundredKg, hundredKg], 225, 3, 5, null),
    "[INV-PLATES-ARE-THE-CURRENCY] a non-barbell lift graded light stays below plan");
}

// A station preference filters the gym inventory to its own denomination,
// falling back to that denomination's full standard set when the gym stocks
// none of it; no preference is the gym inventory unchanged. Mirrors
// PlateMathTests.testStationPlates.
{
  const mixed = C.ALL_STANDARD;
  ok(C.stationPlates(null, mixed) === mixed,
    "[INV-STATION-OWNS-ITS-PLATES] no preference is the gym inventory, exactly as before stations existed");
  ok(JSON.stringify(C.stationPlates("kg", mixed)) === JSON.stringify(mixed.filter((p) => p.unit === "kg")),
    "[INV-STATION-OWNS-ITS-PLATES] the kg station sees only the gym's kg plates");
  ok(JSON.stringify(C.stationPlates("lb", mixed)) === JSON.stringify(mixed.filter((p) => p.unit === "lb")),
    "[INV-STATION-OWNS-ITS-PLATES] the lb station sees only the gym's lb plates");
  ok(C.stationPlates("kg", C.STANDARD_LB) === C.STANDARD_KG,
    "[INV-STATION-OWNS-ITS-PLATES] a kg station in an lb-stocked gym is a statement about the station");
  // The motivating rack: the kg deadlift station prescribes the twin stack
  // natively, and the twin math stores the canonical number.
  const solved = C.solve(235, C.BARS.bar45lb, C.stationPlates("kg", C.ALL_STANDARD), 10);
  ok(solved.perSide.every((pc) => pc.plate.unit === "kg"),
    "[INV-STATION-OWNS-ITS-PLATES] every prescribed plate is a kg plate");
}

// ---- Stopwatch record adoption (mirrors StopwatchRecoveryTests) ----
{
  const now = 1_700_000_000_000;
  const MIN = 60 * 1000, HOUR = 60 * MIN;
  ok(C.stopwatchRecordUsable(now - 40 * MIN, null, now),
    "[INV-CLOCK-SURVIVES-RELAUNCH] a running record within a day is adoptable");
  ok(C.stopwatchRecordUsable(now - 23.9 * HOUR, null, now),
    "[INV-CLOCK-SURVIVES-RELAUNCH] a running record just inside the window is adoptable");
  ok(!C.stopwatchRecordUsable(now - 24 * HOUR, null, now),
    "[INV-CLOCK-SURVIVES-RELAUNCH] a running record at the window is stale");
  ok(!C.stopwatchRecordUsable(now - 7 * 24 * HOUR, null, now),
    "[INV-CLOCK-SURVIVES-RELAUNCH] last week's running record is stale");
  ok(!C.stopwatchRecordUsable(now + HOUR, null, now),
    "[INV-CLOCK-SURVIVES-RELAUNCH] a future-dated origin never fabricates a stopwatch");
  ok(!C.stopwatchRecordUsable(NaN, null, now),
    "[INV-CLOCK-SURVIVES-RELAUNCH] a non-numeric origin is unusable");
  // Paused records are frozen evidence: elapsed is fixed at pausedAt − start,
  // so wall-clock age does not stale them — only inconsistency does.
  const threeDaysAgo = now - 3 * 24 * HOUR;
  ok(C.stopwatchRecordUsable(threeDaysAgo, threeDaysAgo + 30 * MIN, now),
    "[INV-CLOCK-SURVIVES-RELAUNCH] a paused record outlives the running window");
  ok(!C.stopwatchRecordUsable(threeDaysAgo, threeDaysAgo - 5 * MIN, now),
    "[INV-CLOCK-SURVIVES-RELAUNCH] a pause before the start is corrupt");
  ok(!C.stopwatchRecordUsable(threeDaysAgo, now + 5 * MIN, now),
    "[INV-CLOCK-SURVIVES-RELAUNCH] a future-dated pause is corrupt");
}

// ---- Hard-stop check-in attribution (mirrors CoachingEngineTests) ----
// One vocabulary and one window on both clients — a word added to one copy
// and not the other flips rotation readiness per platform.
{
  ok(C.CHECKIN_ATTRIBUTION_WINDOW_MS === 36 * 60 * 60 * 1000,
    "the check-in attribution window is 36 hours");
  for (const response of ["flagged the knee", "PAIN in the elbow", "swelling", "took the day off"]) {
    ok(C.isHardStopResponse(response), `"${response}" is a hard stop`);
  }
  for (const response of ["felt great", "a bit tired", ""]) {
    ok(!C.isHardStopResponse(response), `"${response}" is not a hard stop`);
  }
}

// ---- Shared coaching catalogs and defaults (mirrors CoachingEngineTests) ----
{
  ok(C.DEFAULT_MAXIMUM_SETS === 6, "the defaulted slot ceiling is 6 sets on both clients");
  ok(JSON.stringify(C.defaultRepRange("adductor")) === JSON.stringify({ minReps: 8, maxReps: 12 })
    && JSON.stringify(C.defaultRepRange("core")) === JSON.stringify({ minReps: 8, maxReps: 12 })
    && JSON.stringify(C.defaultRepRange("verticalPull")) === JSON.stringify({ minReps: 6, maxReps: 10 }),
    "coach-added slots open 8–12 for adductor/core and 6–10 elsewhere");
  ok(C.PREFERRED_EXERCISES.verticalPull[0] === "Lat Pulldown"
    && C.PREFERRED_EXERCISES.core.includes("Plank"),
    "the preferred-exercise catalog is the shared one");
}

// ---- Exercise gate: one spelling (mirrors native Exercise.gateStatus) ----
{
  ok(C.exerciseGateStatus({ gateStatus: "shelved" }) === "shelved", "an explicit shelved gate reads shelved");
  ok(C.exerciseGateStatus({ gateStatus: "re-entry", isShelved: true }) === "re-entry",
    "a tri-state gate outranks the legacy boolean");
  ok(C.exerciseGateStatus({ gateStatus: "open", isShelved: true }) === "shelved",
    "a stale open next to isShelved reads shelved, like native");
  ok(C.exerciseGateStatus({ isShelved: true }) === "shelved"
    && C.exerciseGateStatus({}) === "open" && C.exerciseGateStatus(null) === "open",
    "gate-less legacy records fall back to the boolean");
  ok(C.exerciseIsAvailableForProgramming({ gateStatus: "re-entry", isShelved: true })
    && !C.exerciseIsAvailableForProgramming({ isShelved: true }),
    "re-entry stays programmable; shelved never is");
}

// ---- Program slot ordering: one spelling ----
{
  const authored = [
    { exerciseName: "B Lift", role: "complementary", order: 2 },
    { exerciseName: "A Lift", role: "main", order: 5 },
  ];
  ok(C.orderedProgramSlots(authored).map((s) => s.exerciseName).join(",") === "B Lift,A Lift",
    "authored orders win over roles and names");
  const legacy = [
    { exerciseName: "Z Complement", role: "complementary", order: 0 },
    { exerciseName: "A Main", role: "main", order: 0 },
  ];
  ok(C.orderedProgramSlots(legacy, true)[0].exerciseName === "A Main",
    "legacy all-equal orders keep main-first when the caller asks");
  ok(C.orderedProgramSlots(legacy)[0].exerciseName === "A Main",
    "without role awareness, equal orders tie-break on ordinal name");
}

// ---- Vertical-pull tier promotion (mirrors CoachingEngineTests) ----
{
  const slot = (id, name, day, pattern, role, shelved = false) => ({
    id, exerciseName: name, dayIndex: day, pattern, plannedSets: 3, role,
    isMain: role === "main", exerciseIsShelved: shelved,
  });
  const offered = C.verticalPullPromotions({ slots: [
    slot("press", "Overhead Press", 0, "verticalPress", "main"),
    slot("pulldown", "Lat Pulldown", 0, "verticalPull", "accessory"),
    slot("curls", "DB Curls", 0, "arms", "accessory"),
  ] });
  ok(offered.length === 1 && offered[0].change.type === "promoteVerticalPull"
    && offered[0].change.dayIndex === 0
    && offered[0].change.accessorySlotIDs.join() === "pulldown"
    && offered[0].change.accessoryNames.join() === "Lat Pulldown",
    "a day pulling only through a machine accessory earns the promotion offer");
  ok(offered[0].id === "program.day.vertical-pull-tier.v1:day0:pulldown",
    "the promotion id is rotation-independent so one dismissal holds for good");
  ok(C.verticalPullPromotions({ slots: [
    slot("press", "Incline DB Press", 0, "horizontalPress", "main"),
    slot("pullups", "Pull-ups", 0, "verticalPull", "accessory"),
  ] }).length === 1, "a pull-up accessory is the same below-the-tier shape");
  ok(C.verticalPullPromotions({ slots: [
    slot("press", "Overhead Press", 0, "verticalPress", "main"),
    slot("pullups", "Pull-ups", 0, "verticalPull", "complementary"),
    slot("pulldown", "Lat Pulldown", 0, "verticalPull", "accessory"),
  ] }).length === 0, "a day already pulling at the lift tier needs nothing");
  ok(C.verticalPullPromotions({ slots: [
    slot("press", "Overhead Press", 0, "verticalPress", "main"),
    slot("pulldown", "Lat Pulldown", 0, "verticalPull", "accessory", true),
  ] }).length === 0, "a shelved pull accessory is not a choice to promote");
  ok(C.verticalPullPromotions({ slots: [
    slot("pulldown", "Lat Pulldown", 0, "verticalPull", "accessory"),
  ] }).length === 0, "a day with no lift work is not a day to reshape");
  // The snapshot arrives in day-record order; the id must not depend on it,
  // or a reorder would re-emit a dismissed offer.
  const forward = C.verticalPullPromotions({ slots: [
    slot("a-pull", "Straight-arm Pulldown", 0, "verticalPull", "accessory"),
    slot("press", "Overhead Press", 0, "verticalPress", "main"),
    slot("z-pull", "Lat Pulldown", 0, "verticalPull", "accessory"),
  ] });
  const reversed = C.verticalPullPromotions({ slots: [
    slot("z-pull", "Lat Pulldown", 0, "verticalPull", "accessory"),
    slot("press", "Overhead Press", 0, "verticalPress", "main"),
    slot("a-pull", "Straight-arm Pulldown", 0, "verticalPull", "accessory"),
  ] });
  ok(forward[0].id === reversed[0].id
    && forward[0].id === "program.day.vertical-pull-tier.v1:day0:a-pull,z-pull",
    "the offer id is stable under slot reordering");
}

// ---- Banked-set corrections (mirrors SetLifecycleTests) ----
{
  const banked = { weightLb: 195, reps: 5, durationSeconds: null, status: "completed" };
  const reweighed = C.correctedSetValues(banked, { weightLb: 205 });
  ok(reweighed.weightLb === 205 && reweighed.reps === 5 && reweighed.status === "completed",
    "[INV-BANKED-SETS-CORRECTABLE] editing weight cannot reset reps or status");
  const ticked = C.correctedSetValues({ ...banked, status: "planned" }, { status: "completed" });
  ok(ticked.status === "completed" && ticked.weightLb === 195,
    "[INV-BANKED-SETS-CORRECTABLE] the missed ✓ becomes real history without touching the weight");
  const garbage = C.correctedSetValues({ ...banked, durationSeconds: 30 },
    { weightLb: -5, reps: -1, durationSeconds: -10, status: "imaginary" });
  ok(garbage.weightLb === 195 && garbage.reps === 5 && garbage.durationSeconds === 30
    && garbage.status === "completed",
    "[INV-BANKED-SETS-CORRECTABLE] negative, non-numeric, or unknown corrections keep the stored values");
  const nan = C.correctedSetValues(banked, { weightLb: NaN, reps: 2.5 });
  ok(nan.weightLb === 195 && nan.reps === 5,
    "[INV-BANKED-SETS-CORRECTABLE] NaN weights and fractional reps keep the stored values");
  const untouched = C.correctedSetValues({ ...banked, durationSeconds: 45 }, {});
  ok(untouched.weightLb === 195 && untouched.reps === 5 && untouched.durationSeconds === 45
    && untouched.status === "completed",
    "[INV-BANKED-SETS-CORRECTABLE] an empty correction changes nothing");
  // The status cycle is shared domain behavior — one tap must walk the same
  // documented order on both clients (mirrors SetLifecycleTests).
  ok(C.nextSetStatus("planned") === "completed"
    && C.nextSetStatus("completed") === "skipped"
    && C.nextSetStatus("skipped") === "planned",
    "[INV-BANKED-SETS-CORRECTABLE] the status cycle is planned → completed → skipped → planned");
  ok(C.nextSetStatus("imaginary") === "completed",
    "an unknown status starts the cycle from planned, like Swift");
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
