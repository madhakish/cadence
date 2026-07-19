// IndexedDB/program adapter for the pure rotation-first coaching engine.
// Evaluation is read-only. Program mutations cross an explicit user-accepted
// boundary and the caller persists a CoachingDecision audit record.
import * as C from "./core.js";
import { iso } from "./db.js";

export function coachingReport(program, sessions, exMap, checkins = []) {
  const id = program.uuid || program.id;
  const slots = (program.days || []).flatMap((day) => [
    ...(day.lifts || []).map((lift) => {
      const exercise = exMap.get(lift.exerciseName);
      const plan = C.programPlanFor(
        { cycleNumber: program.cycleNumber, baseWeightLb: lift.baseWeightLb, nextPhase: program.currentWeek, incrementLb: 0 },
        program.roundingLb, exercise?.type, exercise?.movementGroup, lift.role, program.focus,
        lift.prescription || "automatic", { ...lift, workingSets: lift.doubleProgressionSets ?? 3 },
      );
      return { id: lift.id, exerciseName: lift.exerciseName, dayIndex: day.order,
        pattern: exercise?.movementPattern || C.movementPattern(lift.exerciseName, exercise?.movementGroup),
        plannedSets: plan.sets, isMain: lift.role === "main", capacityManaged: lift.capacityManaged !== false,
        maximumSets: lift.maximumSets || 6 };
    }),
    ...(day.accessories || []).map((accessory) => {
      const exercise = exMap.get(accessory.exerciseName);
      return { id: accessory.id, exerciseName: accessory.exerciseName, dayIndex: day.order,
        pattern: exercise?.movementPattern || C.movementPattern(accessory.exerciseName, exercise?.movementGroup),
        plannedSets: accessory.sets, isMain: false, capacityManaged: accessory.capacityManaged !== false,
        maximumSets: accessory.maximumSets || 6 };
    }),
  ]);
  const history = sessions.flatMap((session) => {
    const tag = session.programTag;
    if (!tag || (tag.programId !== id && tag.programName !== program.name)
        || tag.cycleNumber == null || tag.week == null || tag.dayIndex == null) return [];
    const sessionDate = Date.parse(session.completedAt || session.date);
    return [{ id: String(session.id), date: session.completedAt || session.date, programID: id,
      cycleNumber: tag.cycleNumber, rotation: tag.week, dayIndex: tag.dayIndex, completed: true,
      hasHardStopCheckIn: checkins.some((checkin) => {
        const elapsed = Date.parse(checkin.date) - sessionDate;
        return elapsed >= 0 && elapsed <= 36 * 60 * 60 * 1_000
          && /flag|pain|swell|off/i.test(checkin.response || "");
      }),
      exercises: (session.exercises || []).map((entry) => {
        const exercise = exMap.get(entry.exerciseName);
        return { slotID: entry.programSlotId || null, exerciseName: entry.exerciseName,
          pattern: exercise?.movementPattern || C.movementPattern(entry.exerciseName, exercise?.movementGroup),
          plannedSets: entry.plannedSets ?? (entry.sets || []).filter((set) => !set.isWarmup).length,
          plannedWeightLb: entry.plannedWeightLb ?? null, plannedReps: entry.plannedReps ?? null,
          roundingLb: C.programLoadStep(program.roundingLb, exercise?.type),
          sets: (entry.sets || []).map((set) => ({ actualWeightLb: set.weightLb, actualReps: set.reps,
            plannedWeightLb: set.plannedWeightLb ?? entry.plannedWeightLb ?? null,
            plannedReps: set.plannedReps ?? entry.plannedReps ?? null, isWarmup: !!set.isWarmup,
            prescriptionBlock: set.prescriptionBlock || (set.isWarmup ? "warmup" : "work"),
            completed: set.status === "completed", stoppedEarly: (set.flags || []).includes("stopped early"),
            hasBodyFlag: !!set.bodyFlagSite, quality: C.setQuality(set.flags) || "ungraded",
            durationSeconds: set.durationSeconds ?? null })) };
      }) }];
  });
  return C.evaluateCoaching({ id, expectedDayIndexes: (program.days || []).map((day) => day.order), slots,
    maximumAddedSetsPerRotation: program.maximumAddedSetsPerRotation ?? 6 }, history, program.reliableHistoryStart);
}

const PREFERRED_EXERCISES = {
  verticalPull: ["Lat Pulldown", "Assisted Pull-up", "Pull-ups"],
  kneeFlexion: ["Seated Leg Curl", "Lying Leg Curl", "Nordic Hamstring Curl"],
  shoulderStability: ["Face Pulls", "Band External Rotation", "Y-T-W Raises"],
  adductor: ["Copenhagen Plank", "Cable Hip Adduction"],
  core: ["Hanging Knee Raise", "Dead Bug", "Plank"],
};

export async function applyCoachingRecommendation(program, recommendation, exercises) {
  const change = recommendation.change;
  let message = "Program held unchanged.";
  if (change.type === "capacityPlan") {
    const available = exercises.filter((exercise) => !exercise.isShelved && exercise.gateStatus !== "shelved");
    const resolved = (change.additions || []).map((adjustment) => {
      if (adjustment.type !== "addPattern") return { adjustment };
      const exercise = (PREFERRED_EXERCISES[adjustment.pattern] || [])
        .map((name) => available.find((item) => item.name === name)).find(Boolean)
        || available.find((item) => item.movementPattern === adjustment.pattern);
      const day = (program.days || []).find((item) => item.order === adjustment.dayIndex) || program.days?.[0];
      if (!exercise || !day) throw new Error(`No available ${C.movementPatternName(adjustment.pattern).toLowerCase()} exercise.`);
      return { adjustment, exercise, day };
    });
    const messages = [];
    for (const item of resolved) {
      const adjustment = item.adjustment;
      if (adjustment.type === "addSet") {
        const slot = (program.days || []).flatMap((day) => [...(day.accessories || []), ...(day.lifts || [])])
          .find((candidate) => candidate.id === adjustment.slotID);
        if (!slot) continue;
        const key = "sets" in slot ? "sets" : "doubleProgressionSets";
        const old = slot[key] || 1;
        slot[key] = Math.min(slot.maximumSets || 6, old + adjustment.count);
        messages.push(`${adjustment.exerciseName} ${old}→${slot[key]}`);
      } else {
        const minReps = ["adductor", "core"].includes(adjustment.pattern) ? 8 : 6;
        item.day.accessories.push({ exerciseName: item.exercise.name, order: item.day.accessories.length,
          sets: adjustment.sets, minReps,
          maxReps: ["adductor", "core"].includes(adjustment.pattern) ? 12 : 10,
          currentReps: minReps, targetSeconds: item.exercise.type === "timed" ? 30 : 0,
          durationStepSeconds: 5, weightLb: 0, incrementLb: 0, stallCount: 0,
          capacityManaged: true, maximumSets: 6, conditioningEffort: "easy", targetRPE: 0 });
        messages.push(`${item.exercise.name} +${adjustment.sets}`);
      }
    }
    message = messages.length ? `Applied for this rotation: ${messages.join(", ")}.` : "Capacity plan was already satisfied.";
  } else if (change.type === "addSet") {
    const slot = (program.days || []).flatMap((day) => [...(day.accessories || []), ...(day.lifts || [])])
      .find((candidate) => candidate.id === change.slotID);
    if (slot) {
      const key = "sets" in slot ? "sets" : "doubleProgressionSets";
      const old = slot[key] || 1; slot[key] = Math.min(slot.maximumSets || 6, old + change.count);
      message = `${slot.exerciseName}: ${old} → ${slot[key]} sets per rotation.`;
    }
  } else if (change.type === "addPattern") {
    const available = exercises.filter((exercise) => !exercise.isShelved && exercise.gateStatus !== "shelved");
    const exercise = (PREFERRED_EXERCISES[change.pattern] || []).map((name) => available.find((item) => item.name === name)).find(Boolean)
      || available.find((item) => item.movementPattern === change.pattern);
    const day = (program.days || []).find((item) => item.order === change.dayIndex) || program.days?.[0];
    if (!exercise || !day) throw new Error(`No available ${C.movementPatternName(change.pattern).toLowerCase()} exercise.`);
    const minReps = ["adductor", "core"].includes(change.pattern) ? 8 : 6;
    day.accessories.push({ exerciseName: exercise.name, order: day.accessories.length, sets: change.sets,
      minReps, maxReps: ["adductor", "core"].includes(change.pattern) ? 12 : 10,
      currentReps: minReps, targetSeconds: exercise.type === "timed" ? 30 : 0,
      durationStepSeconds: 5, weightLb: 0, incrementLb: 0, stallCount: 0,
      capacityManaged: true, maximumSets: 6, conditioningEffort: "easy", targetRPE: 0 });
    message = `Added ${change.sets} sets of ${exercise.name} to ${day.name}.`;
  } else if (change.type === "reduceAccessoryVolume") {
    message = `Scheduled a ${change.percent}% accessory-set cut for the next rotation only.`;
  } else if (change.type === "tryShorterSpacing") {
    const old = program.preferredSessionSpacingDays || 3;
    program.preferredSessionSpacingDays = Math.max(2, change.days);
    message = `Preferred spacing: ${old} → ${program.preferredSessionSpacingDays} days.`;
  }
  return message;
}

export function coachingDecision(program, recommendation, action, evidence) {
  const temporary = action === "accepted" && recommendation.change.type === "reduceAccessoryVolume"
    ? temporaryAccessoryValue(100 - recommendation.change.percent, program.cycleNumber, program.currentWeek)
    : null;
  return { id: crypto.randomUUID(), date: iso(new Date()), programId: program.uuid || program.id,
    ruleId: recommendation.ruleID, recommendationId: recommendation.id, action,
    title: recommendation.title, explanation: recommendation.explanation, evidence,
    beforeValue: null, afterValue: temporary };
}

export function temporaryAccessoryValue(percent, cycleNumber, rotation) {
  return `temporaryAccessoryPercent:${percent}:cycle:${cycleNumber}:rotation:${rotation}`;
}

export function temporaryAccessoryOverride(value) {
  const match = /^temporaryAccessoryPercent:(\d+):cycle:(\d+):rotation:(\d+)$/.exec(value || "");
  if (!match) return null;
  const percent = Number(match[1]);
  return percent >= 1 && percent <= 100
    ? { percent, cycleNumber: Number(match[2]), rotation: Number(match[3]) }
    : null;
}

export function effectiveAccessoryPercent(program, decisions) {
  const programId = program.uuid || program.id;
  const ordered = [...(decisions || [])].sort((a, b) => Date.parse(b.date) - Date.parse(a.date));
  for (const decision of ordered) {
    if ((decision.programId || decision.programID) !== programId || decision.action !== "accepted") continue;
    const override = temporaryAccessoryOverride(decision.afterValue);
    if (override?.cycleNumber === program.cycleNumber && override.rotation === program.currentWeek) {
      return override.percent;
    }
  }
  return 100;
}
