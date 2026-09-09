import * as C from "./core.js";

const stableID = p => p.uuid || p.id;
const fail = reason => { throw new Error(`TFH: ${reason}`); };
export function tfhCohort(program, sessions) {
  return sessions.filter(s => s.isCompleted && s.programTag?.programId === stableID(program)
    && s.tfhPolicyId === program.tfhPolicy.id && s.tfhExcludedFromProgression !== true
    && (s.exercises || []).some(e => e.programSlotId
      && (e.sets || []).some(x => !x.isWarmup && x.status === "completed")));
}
export function tfhCurrentPosition(program, sessions) {
  C.tfhValidateProgram(program);
  if (!program.tfhPolicy) return null;
  const completions = tfhCohort(program,sessions).map(s => {
    C.tfhValidateSession(s);
    if(s.programTag.cycleNumber < program.tfhPolicy.startCycle) fail("A completed session predates its TFH cohort.");
    return {cycle:s.programTag.cycleNumber,rotation:s.programTag.week,dayOrder:s.programTag.dayIndex};
  });
  const next = C.tfhPosition(program.tfhPolicy, completions);
  if (!next) fail("Completed session positions are incomplete or ambiguous. Review duplicate history.");
  return next;
}
export function tfhSynchronize(program, sessions) {
  const next = tfhCurrentPosition(program,sessions);
  if (!next) return null;
  program.cycleNumber = next.cycle; program.currentWeek = next.rotation; program.nextDayIndex = next.dayOrder;
  return next;
}
export function tfhExposures(program,sessions) {
  return tfhCohort(program,sessions).flatMap(session => {
    C.tfhValidateSession(session);
    return (session.exercises || []).filter(e => e.tfhAnchor).map(e => ({
      id: `${session.uuid || session.id}:${e.programSlotId || e.tfhAnchor.id}`,
      anchorId: e.tfhAnchor.id, exerciseId: e.exerciseId,
      cycle: session.programTag.cycleNumber, rotation: session.programTag.week,
      context: session.tfhContext || null,
      sets: (e.sets || []).filter(s => !s.isWarmup).sort((a,b) => a.order-b.order).map(s => ({
        weightLb: s.weightLb, reps: s.reps, plannedWeightLb: s.plannedWeightLb, plannedReps: s.plannedReps,
        status: s.status, loadBasis: s.loadBasis, implementCount: s.implementCount, isPerSide: !!s.isPerSide,
        quality: C.setQuality(s.flags), stoppedEarly: (s.flags || []).includes("stopped early"),
        hasBodyFlag: !!s.bodyFlagSite, benchmark: s.tfhBenchmark != null,
        stopReason: s.tfhBenchmark?.stopReason || null, restSeconds: s.tfhBenchmark?.restSeconds ?? null,
      })),
    }));
  });
}
export function tfhPrescription(program,slotID,sessions,rotation = null) {
  const next = tfhCurrentPosition(program,sessions);
  const anchor = program.tfhPolicy?.anchors[slotID];
  if (!anchor) return null;
  const plan = C.tfhProject(anchor, tfhExposures(program,sessions), next.cycle, rotation ?? next.rotation);
  if (!plan) fail("The recorded targets cannot be compared. Review this slot's history or start a new cohort.");
  return {anchor,plan};
}
export function tfhDraft(program,exercises,sessions) {
  const mine = sessions.filter(s => s.isCompleted && s.programTag?.programId === stableID(program))
    .sort((a,b) => Date.parse(b.completedAt || b.date)-Date.parse(a.completedAt || a.date));
  const anchors = {};
  for (const d of program.days || []) for (const slot of [...(d.lifts || []), ...(d.accessories || [])]) {
    const ex = exercises.find(e => e.name === slot.exerciseName);
    if (!ex?.id) fail(`${slot.exerciseName} needs a stable exercise identity.`);
    if (["timed","conditioning"].includes(ex.type)) continue;
    const previous = mine.map(s => s.exercises.find(e => e.programSlotId === slot.id && e.exerciseId === ex.id)).find(Boolean);
    const work = (previous?.sets || []).filter(s => !s.isWarmup && s.status === "completed");
    const uniform = work.length && work.every(s => Math.abs(s.weightLb-work[0].weightLb)<0.001);
    const min = Math.max(1,slot.minimumReps ?? slot.minReps ?? 5);
    const max = Math.max(min,slot.maximumReps ?? slot.maxReps ?? 8);
    const reps = Math.min(max,Math.max(min,slot.currentReps ?? min));
    const basis = C.resolvedLoadBasis(ex);
    anchors[slot.id] = {id:crypto.randomUUID(),exerciseId:ex.id,
      weightLb:basis === "bodyweight" ? 0 : (uniform ? work[0].weightLb : (slot.baseWeightLb ?? slot.weightLb ?? 0)),
      reps:Array(Math.min(10,Math.max(1,slot.doubleProgressionSets ?? slot.sets ?? 3))).fill(reps),
      minReps:min,maxReps:max,incrementLb:ex.type === "dumbbell" ? 5 : (slot.incrementLb ?? program.roundingLb),
      loadBasis:basis,implementCount:C.resolvedImplementCount(ex),isPerSide:!!ex.isUnilateral,
      intent:ex.movementGroup === "olympic" ? "practice" : "develop",benchmarkEnabled:false};
  }
  const dayOrders = (program.days || []).map(d=>d.order).sort((a,b)=>a-b);
  const layout = Object.fromEntries((program.days || []).flatMap(d=>[...(d.lifts || []),...(d.accessories || [])].map(s=>[s.id,`${d.order}:${s.role || "accessory"}:${s.order}`])));
  return {version:1,id:crypto.randomUUID(),startCycle:Math.max(program.cycleNumber,1+Math.max(0,...mine.map(s=>s.programTag.cycleNumber || 0))),
    dayOrders,recoveryDayOrders:dayOrders.slice(0,2),anchors,layout};
}
export function tfhCoachingReport(program,sessions) {
  let recommendations;
  try {
    const next = tfhCurrentPosition(program,sessions), history = tfhExposures(program,sessions);
    const names = new Map(program.days.flatMap(d=>[...(d.lifts || []),...(d.accessories || [])]).map(s=>[s.id,s.exerciseName]));
    recommendations = Object.entries(program.tfhPolicy.anchors).sort(([a],[b])=>a.localeCompare(b)).map(([id,anchor])=>{
      const a = C.tfhPlateau(anchor,history,next.completedCycles,next.cycle);
      return {id:`tfh:${program.tfhPolicy.id}:${id}:${next.cycle}`,ruleID:`tfh.${a.state}`,priority:30,
        title:`${names.get(id) || "Exercise"} · ${a.state === "possiblePlateau" ? "review capacity" : a.state}`,
        explanation:a.reason,change:{type:"hold"}};
    });
  } catch (e) { recommendations = [{id:"tfh:review",ruleID:"tfh.review",priority:1,title:"Review TFH history",explanation:e.message,change:{type:"hold"}}]; }
  return {rotations:[],currentReadiness:"unknown",greenRotationStreak:0,recommendations};
}
