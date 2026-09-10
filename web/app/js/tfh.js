import * as C from "./core.js";

const stableID = p => p.uuid || p.id;
const fail = reason => { throw new Error(`TFH: ${reason}`); };
export function tfhPractice(slot,exercise,rotation) {
  const weight = slot.weightLb ?? slot.baseWeightLb ?? 0, sets = slot.sets ?? 1, seconds = slot.targetSeconds;
  if (!Number.isInteger(seconds) || seconds <= 0 || !Number.isInteger(sets) || sets <= 0
      || !Number.isFinite(weight) || weight < 0) fail(`${exercise.name} needs an authored duration and load.`);
  const weightLb = exercise.type === "conditioning" && C.cardioCarriesLoad(exercise.name)
    ? (weight > 0 ? weight : (C.cardioDefaultLoadLb(exercise.name) ?? 0)) : weight;
  return {weightLb,sets:rotation === 4 ? 1 : sets,seconds:rotation === 4 ? Math.max(1,Math.floor(seconds/2)) : seconds};
}
export function tfhCohort(program, sessions) {
  return sessions.filter(s => s.isCompleted && s.programTag?.programId === stableID(program)
    && s.tfhPolicyId === program.tfhPolicy.id && s.tfhExcludedFromProgression !== true
    && (s.exercises || []).some(e => {
      if (!e.programSlotId) return false;
      const instructions = [...(e.sets || [])].sort((a,b)=>a.order-b.order)
        .filter(x => !x.isWarmup && C.countsAsProgramInstruction(x.prescriptionBlock));
      return instructions.slice(0,e.plannedSets ?? instructions.length).some(x=>x.status === "completed");
    }));
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
      sets: (e.sets || []).filter(s => !s.isWarmup && C.countsAsPrescribedWork(s.prescriptionBlock))
        .sort((a,b) => a.order-b.order).slice(0,e.plannedSets ?? e.sets.length).map(s => ({
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
  const prior = program.tfhPolicy;
  if (prior && !C.tfhValidPolicy(prior)) fail("The stored TFH policy is invalid.");
  const mine = sessions.filter(s => s.isCompleted && s.programTag?.programId === stableID(program) && s.tfhExcludedFromProgression !== true)
    .sort((a,b) => Date.parse(b.completedAt || b.date)-Date.parse(a.completedAt || a.date));
  const anchors = {};
  for (const d of program.days || []) for (const slot of [...(d.lifts || []), ...(d.accessories || [])]) {
    const ex = exercises.find(e => e.name === slot.exerciseName);
    if (!ex?.id) fail(`${slot.exerciseName} needs a stable exercise identity.`);
    if (["timed","conditioning"].includes(ex.type)) {
      if ((d.lifts || []).includes(slot))
        fail(`Move ${slot.exerciseName} to an accessory slot and set its duration before enabling TFH.`);
      continue;
    }
    const previous = mine.map(s => s.exercises.find(e => e.programSlotId === slot.id && e.exerciseId === ex.id)).find(Boolean);
    const candidates = [...(previous?.sets || [])].sort((a,b)=>a.order-b.order)
      .filter(s=>!s.isWarmup && C.countsAsPrescribedWork(s.prescriptionBlock));
    const work = candidates.slice(0,previous?.plannedSets ?? candidates.length).filter(s=>s.status === "completed");
    const basis = C.resolvedLoadBasis(ex);
    const uniform = work.length && work.every(s => Math.abs(s.weightLb-work[0].weightLb)<0.001
      && C.resolvedLoadBasis(s) === basis && C.resolvedImplementCount(s) === C.resolvedImplementCount(ex)
      && !!s.isPerSide === !!ex.isUnilateral);
    const authored = prior?.anchors[slot.id];
    if (authored?.exerciseId === ex.id && authored.loadBasis === basis
        && authored.implementCount === C.resolvedImplementCount(ex) && authored.isPerSide === !!ex.isUnilateral) {
      anchors[slot.id] = {...structuredClone(authored),id:crypto.randomUUID(),
        weightLb:uniform ? (basis === "bodyweight" ? 0 : work[0].weightLb) : authored.weightLb};
      continue;
    }
    const min = Math.max(1,slot.minimumReps ?? slot.minReps ?? 5);
    const max = Math.max(min,slot.maximumReps ?? slot.maxReps ?? 8);
    const reps = Math.min(max,Math.max(min,slot.currentReps ?? min));
    anchors[slot.id] = {id:crypto.randomUUID(),exerciseId:ex.id,
      weightLb:basis === "bodyweight" ? 0 : (uniform ? work[0].weightLb : (slot.baseWeightLb ?? slot.weightLb ?? 0)),
      reps:Array(Math.min(10,Math.max(1,slot.doubleProgressionSets ?? slot.sets ?? 3))).fill(reps),
      minReps:min,maxReps:max,incrementLb:ex.type === "dumbbell" ? 5 : (slot.incrementLb ?? program.roundingLb),
      loadBasis:basis,implementCount:C.resolvedImplementCount(ex),isPerSide:!!ex.isUnilateral,
      intent:ex.movementGroup === "olympic" ? "practice" : "develop",benchmarkEnabled:false};
  }
  const dayOrders = (program.days || []).map(d=>d.order).sort((a,b)=>a-b);
  const layout = Object.fromEntries((program.days || []).flatMap(d=>[...(d.lifts || []),...(d.accessories || [])].map(s=>[s.id,`${d.order}:${s.role || "accessory"}:${s.order}`])));
  const previousRecovery = (prior?.recoveryDayOrders || []).filter(d=>dayOrders.includes(d));
  return {version:1,id:crypto.randomUUID(),startCycle:Math.max(program.cycleNumber,1+Math.max(0,...mine.map(s=>s.programTag.cycleNumber || 0))),
    dayOrders,recoveryDayOrders:previousRecovery.length >= 2 ? previousRecovery : dayOrders.slice(0,2),anchors,layout};
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
