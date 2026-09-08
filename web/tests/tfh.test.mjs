import assert from "node:assert/strict";
import * as C from "../app/js/core.js";

const anchor = { id: "anchor", exerciseId: "exercise", weightLb: 42,
  reps: [3, 3, 3, 3], minReps: 3, maxReps: 5, incrementLb: 5,
  mode: "repsFirst", loadBasis: "perImplement", implementCount: 2, isPerSide: false };
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

assert.equal(typeof C.tfhProject, "function", "TFH must be a production core rule");
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
assert.deepEqual(C.tfhProject(anchor, [exposure(1, 1), exposure(1, 1, [3,3,3,3], {id:"duplicate"})], 1, 2).reps,
  anchor.reps, "ambiguous duplicate exposures never double advance");
const bw = {...anchor, mode:"bodyweight", weightLb:0, incrementLb:0,
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
assert.equal(duplicateRecovery.state,"recover","ambiguous history must not cancel recovery");
assert.ok(duplicateRecovery.reps.length < anchor.reps.length);
console.log("TFH regression tests passed");
