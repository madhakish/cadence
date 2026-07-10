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
eq(s.perSide.length, 1, "220 one denom");
eq(s.perSide[0].plate.value, 20, "220 uses 20kg");
eq(s.perSide[0].plate.unit, "kg", "220 kg bumper");
eq(s.perSide[0].count, 2, "220 two 20kg");
ok(!s.isOffTarget, "220 within tolerance");
eq(new Set(s.perSide.map((pc) => pc.plate.unit)).size, 1, "220 no unit mix");

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

// ---- Warmup ramp ----
let r = C.warmupRamp(245);
ok(JSON.stringify(r.map((x) => x.weightLb)) === JSON.stringify([45, 100, 135, 170, 210]), "ramp 245 weights");
ok(JSON.stringify(r.map((x) => x.reps)) === JSON.stringify([10, 5, 3, 2, 1]), "ramp 245 reps");
r = C.warmupRamp(65);
ok(JSON.stringify(r.map((x) => x.weightLb)) === JSON.stringify([45, 55]), "ramp 65");
r = C.warmupRamp(45);
ok(JSON.stringify(r.map((x) => x.weightLb)) === JSON.stringify([45]) && r[0].reps === 10, "ramp 45 bar only");
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
eq(heaviest?.label, "232×5×3 — heaviest deadlift of the comeback", "Jun7 heaviest label");
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

// clean cycle → tapered increment
let pres = C.advanceCycleLift(liftState(), cleanPerf, "strength", 5);
eq(pres.grade, "success", "advance clean grade");
eq(pres.state.baseWeightLb, 180, "clean cycle adds one plate");
eq(pres.state.stallCount, 0, "clean resets stall");
eq(pres.state.lastIncrementLb, 5, "increment recorded");

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

// ---- rest defaults ----
eq(C.restDefaultSeconds("Main", "Deadlift", 0), 300, "deadlift 5:00");
eq(C.restDefaultSeconds("Main", "Back Squat", 0), 300, "squat 5:00");
eq(C.restDefaultSeconds("Main", "Push Press", 0), 240, "push press 4:00");
eq(C.restDefaultSeconds("Main", "Power Clean", 0), 240, "clean 4:00");
eq(C.restDefaultSeconds("Main", "Incline DB Press", 0), 180, "main upper 3:00");
eq(C.restDefaultSeconds("Main", "Barbell Bench", 0), 180, "bench 3:00");
eq(C.restDefaultSeconds("Accessory", "DB Curls", 0), 90, "accessory 1:30");
eq(C.restDefaultSeconds("Accessory", "Face Pulls", 120), 120, "accessory honors its own override");
eq(C.restDefaultSeconds("Main", "Barbell Bench", 120), 120, "main lift honors its per-exercise override");
eq(C.restDefaultSeconds("Main", "Deadlift", 360), 360, "override beats the main-lift movement default");
eq(C.restDefaultSeconds("Conditioning", "Run-Walk Intervals", 0), 0, "conditioning no rest");
eq(C.restDefaultSeconds("Conditioning", "Sled Push", 120), 120, "conditioning honors an explicit override");

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
