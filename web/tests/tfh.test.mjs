import assert from "node:assert/strict";
import * as C from "../app/js/core.js";

const anchor = { id: "anchor", exerciseId: "exercise", weightLb: 42,
  reps: [3, 3, 3, 3], minReps: 3, maxReps: 5, incrementLb: 5,
  loadBasis: "perImplement", implementCount: 2, isPerSide: false, benchmarkEnabled: true };
const exposure = (cycle, rotation, reps = anchor.reps, extra = {}) => ({
  id: `${cycle}-${rotation}`, cycle, rotation, dayIndex: 0, date: cycle * 100 + rotation,
  anchorId: anchor.id, exerciseId: anchor.exerciseId,
  sets: reps.map((actualReps, i) => ({ weightLb: anchor.weightLb, reps: actualReps, plannedReps: anchor.reps[i],
    plannedWeightLb: anchor.weightLb, status: "completed", loadBasis: anchor.loadBasis,
    implementCount: 2, isPerSide: false, quality: "clean", rir: null,
    benchmark: rotation === 3 && i === reps.length - 1,
    stopReason: "technicalLimit", restSeconds: 180 })),
  context: "same preceding work", ...extra,
});

assert.equal(typeof C.tfhProject, "function", "TFH must expose a pure core policy");
const empty = C.tfhProject(anchor, [], 1, 1);
assert.deepEqual(empty.reps, anchor.reps, "new method preserves authored performed shape");
const next = C.tfhProject(anchor, [exposure(1, 1)], 1, 2);
assert.equal(next.weightLb, 42, "one successful exposure must not force a coarse load jump");
assert.equal(next.reps.reduce((a, b) => a + b), 13, "earn one total rep, not one per set");
assert.deepEqual(C.tfhProject(anchor, [exposure(1, 1, [2, 2, 2, 2])], 1, 2).reps,
  anchor.reps, "a miss holds instead of adding fatigue");
assert.equal(C.tfhProject(anchor, [exposure(1, 1)], 1, 4).benchmark, false);
assert.ok(C.tfhProject(anchor, [], 1, 4).reps.length < anchor.reps.length);
assert.deepEqual(C.tfhProject(anchor, [exposure(1, 4)], 2, 1).reps, anchor.reps,
  "recovery is never progression evidence");
assert.equal(C.tfhProject(anchor, [exposure(1, 1), exposure(1, 1, [3,3,3,3], {id:"duplicate"})], 1, 2),
  null, "ambiguous duplicate exposures require review, not a reset to starting targets");
const bw = {...anchor, weightLb:0, incrementLb:0,
  loadBasis:"bodyweight", implementCount:1, reps:[6,6], minReps:4, maxReps:6};
assert.deepEqual(C.tfhProject(bw, [], 1, 1).reps, [6,6]);
assert.equal(C.tfhProject(bw, [], 1, 1).weightLb, 0);

const history = [1,2,3].flatMap(c => [1,2,3].map(r => exposure(c,r)));
assert.equal(C.tfhPlateau({...anchor,intent:"maintain"},history,[1,2,3],4).state,"notAssessing",
  "intentional maintenance cannot become a plateau");
assert.deepEqual(C.tfhProject({...anchor,intent:"maintain"},history,4,1).reps,anchor.reps,
  "maintenance does not silently increase workload");
assert.equal(C.tfhPlateau(anchor, history, [1,2], 3).state, "learning",
  "two flat cycles require a prior completed baseline, not just two test sets");
assert.equal(C.tfhPlateau(anchor, history, [1,2,3], 4).state, "possiblePlateau");
assert.equal(C.tfhPlateau(anchor, history.map(e => e.cycle===3 && e.rotation===3
  ? {...e,sets:e.sets.map((s,i)=>i===3?{...s,reps:s.reps+1}:s)}:e), [1,2,3], 4).state, "progressing",
  "a clean benchmark rep is positive evidence at unchanged weight");
assert.equal(C.tfhPlateau(anchor, history.map(e=>({...e,sets:e.sets.map(s=>({...s,stopReason:null}))})),
  [1,2,3], 4).state, "learning", "missing benchmark evidence is not a plateau");
assert.equal(C.tfhPlateau(anchor, history.map(e=>({...e,context:`different-${e.cycle}`})),
  [1,2,3], 4).state, "learning", "different preceding workload invalidates the comparison");
assert.equal(C.tfhPlateau(anchor, history.map(e=>({...e,sets:e.sets.map(s=>({...s,stopReason:"repCap"}))})),
  [1,2,3], 4).state, "learning", "capped tests measure a lower bound, not capacity");
assert.equal(C.tfhProject(anchor, [exposure(3,1)], 2,1).weightLb, 42,
  "future sessions cannot affect earlier prescriptions");
const progressed = exposure(2,1,[4,4,4,4]);
progressed.sets = progressed.sets.map(s=>({...s,weightLb:47,plannedWeightLb:47,plannedReps:4,quality:"grindy"}));
assert.equal(C.tfhProject(anchor,[progressed],2,2).weightLb,47,
  "a difficult session retains its current prescription instead of resetting to the original anchor");
assert.deepEqual(C.tfhProject(anchor,[progressed],2,2).reps,[4,4,4,4]);
const duplicateRecovery = C.tfhProject(anchor,[exposure(1,1),exposure(1,1)],1,4);
assert.equal(duplicateRecovery,null,"ambiguous history cannot justify guessing a recovery load");
const adjustedTargets = exposure(2,1);
adjustedTargets.sets[0].plannedReps = 2;
assert.equal(C.tfhProject(anchor,[adjustedTargets],2,2),null,
  "manually adjusted targets outside the authored range must never be clamped upward");

const loadAnchor = {...anchor, weightLb:101, reps:[5,5,5,5]};
const topExposure = (cycle, clean = true) => {
  const e = exposure(cycle,1,[5,5,5,5]);
  e.sets = e.sets.map(s=>({...s, weightLb:101, plannedWeightLb:101, plannedReps:5,
    quality:clean?"clean":"grindy"}));
  return e;
};
assert.equal(C.tfhProject(loadAnchor,[topExposure(1),topExposure(2)],3,1).weightLb,106);
assert.equal(C.tfhProject(loadAnchor,[topExposure(1),topExposure(2),topExposure(3,false),topExposure(4)],5,1).weightLb,101,
  "old successes cannot bypass a recent difficult matching phase");
assert.equal(C.tfhProject(loadAnchor,[topExposure(1),topExposure(3)],4,1).weightLb,101,
  "a missing intervening cycle cannot earn a load step");
const difficultRecent = exposure(2,2);
difficultRecent.sets[0].quality = "grindy";
const afterDifficult = C.tfhProject(anchor,[exposure(1,3),difficultRecent],2,3);
assert.deepEqual(afterDifficult.reps,anchor.reps,"an older successful phase cannot override the latest difficult work");
assert.equal(afterDifficult.benchmark,false,"difficult recent work does not earn a capacity test");
assert.equal(C.tfhProject({...anchor,benchmarkEnabled:undefined},[],1,3).benchmark,false,
  "technical benchmarks require explicit selection");
assert.equal(C.tfhProject({...anchor,intent:"practice"},history,4,3).benchmark,false);
assert.deepEqual(C.tfhProject({...anchor,intent:"practice"},history,4,3).reps,anchor.reps);
const roseThenFell = history.map(e=>e.cycle===2?{...e,sets:e.sets.map(s=>({...s,reps:s.reps+1}))}:e);
assert.equal(C.tfhPlateau(anchor,roseThenFell,[1,2,3],4).state,"review",
  "earlier gains cannot hide a subsequent decline");
assert.equal(C.tfhPlateau(anchor,history,[1,2,3],7).state,"learning","old flat evidence is not a current plateau");
const alteredBW = {...bw, benchmarkEnabled:true};
const bwHistory = history.map(e=>({...e,sets:e.sets.slice(0,2).map(s=>({...s,
  weightLb:12,plannedWeightLb:12,loadBasis:"bodyweight",implementCount:1,reps:6,plannedReps:6}))}));
assert.equal(C.tfhPlateau(alteredBW,bwHistory,[1,2,3],4).state,"learning",
  "a bodyweight record with external mass needs identity/load-basis repair");
const adjusted = exposure(1,2);
adjusted.sets = adjusted.sets.map(s=>({...s,weightLb:32}));
const repeated = exposure(1,3);
repeated.sets = repeated.sets.map(s=>({...s,weightLb:32,plannedWeightLb:32}));
const afterAdjustment = [exposure(1,1),adjusted,repeated];
assert.equal(C.tfhProject(anchor,afterAdjustment,2,1).weightLb,32,"old matching phases cannot undo a repeated load reduction");
afterAdjustment.push({...repeated,id:"2-1",cycle:2,rotation:1});
assert.equal(C.tfhProject(anchor,afterAdjustment,2,2).weightLb,32,"the old adjusted phase cannot resurrect its old target either");
console.log("TFH regression tests passed");
