// IndexedDB/program adapter for the pure rotation-first coaching engine.
// Evaluation is read-only. Program mutations cross an explicit user-accepted
// boundary and the caller persists a CoachingDecision audit record.
import * as C from "./core.js";
import { iso, sessionBelongsToProgram } from "./db.js";

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
        trainingIntent: day.trainingIntent || "general",
        pattern: exercise?.movementPattern || C.movementPattern(lift.exerciseName, exercise?.movementGroup),
        plannedSets: plan.sets, role: lift.role, isMain: lift.role === "main", capacityManaged: lift.capacityManaged !== false,
        maximumSets: lift.maximumSets || C.DEFAULT_MAXIMUM_SETS,
        prescriptionStyle: C.resolvedPrescriptionStyle(
          lift.prescription || "automatic", exercise?.movementGroup, lift.role, program.focus,
        ),
        baseWeightLb: lift.baseWeightLb,
        workingSets: lift.doubleProgressionSets ?? 3,
        workingReps: (lift.currentReps ?? 5) <= 3 ? 3 : 5,
        // A graded peak waits in `pending` until the deload ends. Reading only
        // the settled count would hide a stall for a whole cycle — exactly the
        // cycle worth rotating out of. Native splits pending across columns;
        // web stashes the whole ProgressionResult under `pending`.
        stallCount: lift.pending?.state?.stallCount ?? lift.stallCount ?? 0,
        exerciseIsShelved: C.exerciseIsShelved(exercise) };
    }),
    ...(day.accessories || []).map((accessory) => {
      const exercise = exMap.get(accessory.exerciseName);
      return { id: accessory.id, exerciseName: accessory.exerciseName, dayIndex: day.order,
        trainingIntent: day.trainingIntent || "general",
        pattern: exercise?.movementPattern || C.movementPattern(accessory.exerciseName, exercise?.movementGroup),
        plannedSets: accessory.sets, role: "accessory", isMain: false, capacityManaged: accessory.capacityManaged !== false,
        maximumSets: accessory.maximumSets || C.DEFAULT_MAXIMUM_SETS, stallCount: accessory.stallCount || 0,
        exerciseIsShelved: C.exerciseIsShelved(exercise) };
    }),
  ]);
  const history = sessions.flatMap((session) => {
    const tag = session.programTag;
    if (!tag || !sessionBelongsToProgram(session, program)
        || tag.cycleNumber == null || tag.week == null || tag.dayIndex == null) return [];
    const sessionDate = Date.parse(session.completedAt || session.date);
    return [{ id: String(session.id), date: session.completedAt || session.date, programID: id,
      cycleNumber: tag.cycleNumber, rotation: tag.week, dayIndex: tag.dayIndex, completed: true,
      hasHardStopCheckIn: checkins.some((checkin) => {
        const elapsed = Date.parse(checkin.date) - sessionDate;
        return elapsed >= 0 && elapsed <= C.CHECKIN_ATTRIBUTION_WINDOW_MS
          && C.isHardStopResponse(checkin.response);
      }),
      exercises: (session.exercises || []).map((entry) => {
        const exercise = exMap.get(entry.exerciseName);
        return { slotID: entry.programSlotId || null, programRole: entry.programRole || null, exerciseName: entry.exerciseName,
          pattern: exercise?.movementPattern || C.movementPattern(entry.exerciseName, exercise?.movementGroup),
          plannedSets: entry.plannedSets ?? (entry.sets || []).filter((set) => !set.isWarmup).length,
          plannedWeightLb: entry.plannedWeightLb ?? null, plannedReps: entry.plannedReps ?? null,
          prescriptionStyle: entry.prescriptionStyle || null,
          roundingLb: C.programLoadStep(program.roundingLb, exercise?.type),
          sets: (entry.sets || []).map((set) => ({ actualWeightLb: set.weightLb, actualReps: set.reps,
            plannedWeightLb: set.plannedWeightLb ?? entry.plannedWeightLb ?? null,
            plannedReps: set.plannedReps ?? entry.plannedReps ?? null, isWarmup: !!set.isWarmup,
            prescriptionBlock: C.resolvedPrescriptionBlock(set),
            completed: set.status === "completed", stoppedEarly: (set.flags || []).includes("stopped early"),
            hasBodyFlag: !!set.bodyFlagSite, quality: C.setQuality(set.flags) || "ungraded",
            durationSeconds: set.durationSeconds ?? null })) };
      }) }];
  });
  // What the apply path could actually resolve for each pattern, so the
  // engine never proposes an addPattern that is guaranteed to throw on Apply
  // (a freeWeightsOnly program whose only candidates are machines, forever).
  // Mirrors CoachingService.report and the resolution in
  // applyCoachingRecommendation: preferred names first, then any exercise
  // classified under the pattern.
  const policyExercises = [...exMap.values()].filter((item) => C.exerciseIsAvailableForProgramming(item)
    && C.equipmentPolicyAllows(program.equipmentPolicy, item.type));
  const patternsWithAvailableExercise = [...new Set([
    ...policyExercises.map((item) => item.movementPattern).filter(Boolean),
    ...Object.keys(C.PREFERRED_EXERCISES).filter((pattern) => (C.PREFERRED_EXERCISES[pattern] || [])
      .some((name) => policyExercises.some((item) => item.name === name))),
  ])];
  return C.evaluateCoaching({ id, expectedDayIndexes: (program.days || []).map((day) => day.order), slots,
    maximumAddedSetsPerRotation: program.maximumAddedSetsPerRotation ?? 6,
    patternsWithAvailableExercise }, history, program.reliableHistoryStart);
}

export async function applyCoachingRecommendation(program, recommendation, exercises, sessions = []) {
  const change = recommendation.change;
  let message = "Program held unchanged.";
  const automaticExercises = exercises.filter((item) => C.exerciseIsAvailableForProgramming(item)
    && C.equipmentPolicyAllows(program.equipmentPolicy, item.type));
  if (change.type === "capacityPlan") {
    const available = automaticExercises;
    const resolved = (change.additions || []).map((adjustment) => {
      if (adjustment.type !== "addPattern") return { adjustment };
      const exercise = (C.PREFERRED_EXERCISES[adjustment.pattern] || [])
        .map((name) => available.find((item) => item.name === name)).find(Boolean)
        || available.find((item) => item.movementPattern === adjustment.pattern);
      // Fallback = lowest ORDER, like native orderedDays.first — array
      // position is authoring history, not schedule position.
      const day = (program.days || []).find((item) => item.order === adjustment.dayIndex)
        || [...(program.days || [])].sort((left, right) => (left.order ?? 0) - (right.order ?? 0))[0];
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
        // Lift slots only accept added sets on the rep-window style — a
        // methodology slot's sets-across shape is part of its published
        // prescription (mirrors the native applier).
        if (!("sets" in slot) && (slot.prescription || "automatic") !== "doubleProgression") continue;
        const key = "sets" in slot ? "sets" : "doubleProgressionSets";
        const old = slot[key] || 1;
        slot[key] = Math.min(slot.maximumSets || C.DEFAULT_MAXIMUM_SETS, old + adjustment.count);
        messages.push(`${adjustment.exerciseName} ${old}→${slot[key]}`);
      } else {
        const { minReps, maxReps } = C.defaultRepRange(adjustment.pattern);
        item.day.accessories.push({ exerciseName: item.exercise.name, order: item.day.accessories.length,
          sets: adjustment.sets, minReps,
          maxReps,
          currentReps: minReps, targetSeconds: item.exercise.type === "timed" ? 30 : 0,
          durationStepSeconds: 5, weightLb: 0, incrementLb: 0, stallCount: 0,
          capacityManaged: true, maximumSets: C.DEFAULT_MAXIMUM_SETS, conditioningEffort: "easy", targetRPE: 0 });
        messages.push(`${item.exercise.name} +${adjustment.sets}`);
      }
    }
    message = messages.length ? `Applied for this rotation: ${messages.join(", ")}.` : "Capacity plan was already satisfied.";
  } else if (change.type === "addSet") {
    const slot = (program.days || []).flatMap((day) => [...(day.accessories || []), ...(day.lifts || [])])
      .find((candidate) => candidate.id === change.slotID);
    if (slot && (("sets" in slot) || (slot.prescription || "automatic") === "doubleProgression")) {
      const key = "sets" in slot ? "sets" : "doubleProgressionSets";
      const old = slot[key] || 1; slot[key] = Math.min(slot.maximumSets || C.DEFAULT_MAXIMUM_SETS, old + change.count);
      message = `${slot.exerciseName}: ${old} → ${slot[key]} sets per rotation.`;
    }
  } else if (change.type === "addPattern") {
    const available = automaticExercises;
    const exercise = (C.PREFERRED_EXERCISES[change.pattern] || []).map((name) => available.find((item) => item.name === name)).find(Boolean)
      || available.find((item) => item.movementPattern === change.pattern);
    // Fallback = lowest ORDER, like native orderedDays.first (see capacityPlan).
    const day = (program.days || []).find((item) => item.order === change.dayIndex)
      || [...(program.days || [])].sort((left, right) => (left.order ?? 0) - (right.order ?? 0))[0];
    if (!exercise || !day) throw new Error(`No available ${C.movementPatternName(change.pattern).toLowerCase()} exercise.`);
    const { minReps, maxReps } = C.defaultRepRange(change.pattern);
    day.accessories.push({ exerciseName: exercise.name, order: day.accessories.length, sets: change.sets,
      minReps, maxReps,
      currentReps: minReps, targetSeconds: exercise.type === "timed" ? 30 : 0,
      durationStepSeconds: 5, weightLb: 0, incrementLb: 0, stallCount: 0,
      capacityManaged: true, maximumSets: C.DEFAULT_MAXIMUM_SETS, conditioningEffort: "easy", targetRPE: 0 });
    message = `Added ${change.sets} sets of ${exercise.name} to ${day.name}.`;
  } else if (change.type === "reduceAccessoryVolume") {
    message = `Scheduled a ${change.percent}% accessory-set cut for the next rotation only.`;
  } else if (change.type === "promoteVerticalPull") {
    const day = (program.days || []).find((item) => (item.order ?? 0) === change.dayIndex);
    if (!day) throw new Error("The program day for this recommendation no longer exists.");
    // The replacement is the template's own choice — pull-ups on a
    // double-progression window that grows into weighted pull-ups — not a
    // swap candidate: crossing the tier is the point. Mirrors CoachingService.
    const pullUps = automaticExercises.find((item) => item.name === "Pull-ups");
    if (!pullUps) throw new Error("Pull-ups is not in the library. Add or unshelve it first.");
    const ids = new Set((change.accessorySlotIDs || []).map(String));
    const retiring = (day.accessories || []).filter((slot) => ids.has(String(slot.id)));
    if (!retiring.length) throw new Error("The vertical-pull accessories this recommendation names no longer exist.");
    const retiredNames = retiring.map((slot) => slot.exerciseName).join(", ");
    // Renumber over the AUTHORED sequence (order field, name tiebreak — the
    // same comparator native orderedAccessories uses), not raw array
    // position: the editor reorders by mutating order fields only, so array
    // order can lag the authored order and stamping by index would silently
    // revert the user's reorder.
    day.accessories = day.accessories.filter((slot) => !ids.has(String(slot.id)))
      .sort((a, b) => (a.order ?? 0) - (b.order ?? 0)
        || String(a.exerciseName).localeCompare(String(b.exerciseName)));
    day.accessories.forEach((slot, index) => { slot.order = index; });
    // Idempotent against a stale offer: if the day gained a pull-up lift
    // since evaluation (hand-edit, another apply), retiring the accessories
    // is still right but a second identical slot is not.
    if ((day.lifts || []).some((slot) => slot.exerciseName === pullUps.name)) {
      message = `Retired ${retiredNames} — ${day.name} already trains ${pullUps.name} at the lift tier.`;
    } else {
      // The same slot shape the template authors: complementary double
      // progression, three sets, born at bodyweight (base 0). max(order)+1,
      // not length: authored orders can be noncontiguous (imports, edits),
      // and the promoted slot must append after the day's last lift.
      day.lifts = [...(day.lifts || []), {
        exerciseName: pullUps.name, role: "complementary",
        order: Math.max(-1, ...(day.lifts || []).map((slot) => slot.order ?? 0)) + 1,
        prescription: "doubleProgression", doubleProgressionSets: 3,
        baseWeightLb: 0, estimatedMaxLb: 0, stallCount: 0, lastIncrementLb: 0,
      }];
      message = `${retiredNames} → ${pullUps.name} as programmed lift work on ${day.name}.`;
    }
  } else if (change.type === "rotateExercise") {
    const current = exercises.find((item) => item.name === change.exerciseName);
    if (!current) throw new Error(`${change.exerciseName} is no longer in the library, so a compatible variation cannot be chosen.`);
    const lift = (program.days || []).flatMap((day) => day.lifts || []).find((slot) => slot.id === change.slotID);
    const accessory = (program.days || []).flatMap((day) => day.accessories || []).find((slot) => slot.id === change.slotID);
    const slot = lift || accessory;
    if (!slot) throw new Error(`The program slot for ${change.exerciseName} no longer exists.`);
    if (slot.exerciseName !== change.exerciseName) {
      throw new Error(`The program slot changed after the ${change.exerciseName} recommendation, so no rotation was applied.`);
    }
    const compatible = automaticExercises.filter((candidate) => C.swapCompatible(
      current,
      { ...candidate, isShelved: C.exerciseIsShelved(candidate) },
    ))
      .sort((a, b) => String(a.name) < String(b.name) ? -1 : String(a.name) > String(b.name) ? 1 : 0);
    const isMaxEffortLift = !!lift && (lift.prescription || "automatic") === "maxEffort";
    let replacement = compatible[0];
    if (isMaxEffortLift) {
      const preferred = C.PREFERRED_MAX_EFFORT_EXERCISES[current.movementPattern] || [];
      const currentIndex = preferred.indexOf(current.name);
      const start = currentIndex >= 0 ? (currentIndex + 1) % preferred.length : 0;
      const rotated = preferred.length
        ? Array.from({ length: preferred.length }, (_, index) => preferred[(start + index) % preferred.length]) : [];
      replacement = rotated.map((name) => compatible.find((candidate) => candidate.name === name)).find(Boolean)
        || compatible[0];
    }
    if (!replacement) throw new Error(`No compatible variation of ${change.exerciseName} is available. Add one to the library, or unshelve an existing one.`);
    if (isMaxEffortLift) {
      // reduce, not Math.max(...spread): spreading every matching set into
      // arguments can overflow the engine's argument limit on a long history.
      const priorBest = sessions.filter((session) => session.isCompleted)
        .flatMap((session) => session.exercises || [])
        .filter((entry) => entry.exerciseName === replacement.name)
        .flatMap((entry) => entry.sets || [])
        .filter((set) => !set.isWarmup && set.status === "completed" && set.reps === 1
          && C.countsAsPrescribedWork(C.resolvedPrescriptionBlock(set))
          && !(set.flags || []).some((flag) => ["stopped early", "grindy", "wobble"].includes(flag))
          && !set.bodyFlagSite && !set.autoregReason)
        .reduce((best, set) => Math.max(best, set.weightLb || 0), 0);
      lift.baseWeightLb = C.maxEffortVariationTarget(
        priorBest, lift.estimatedMaxLb, lift.baseWeightLb, replacement.movementGroup, program.roundingLb,
      );
    }
    slot.exerciseName = replacement.name;
    slot.revertToExerciseName = null;
    slot.stallCount = 0;
    // The stashed grade belongs to the exercise being rotated out. Carrying it
    // over is the exact inheritance the comment above rules out — and the
    // pending base is the old lift's weight, which must not land on the new one.
    // The earned increment belonged to the OLD movement too; carrying it would
    // arm the honest-base repair against evidence the new lift never produced
    // (the evidence lookup also checks the movement name — this keeps the
    // stored state truthful). Mirrors CoachingService.
    if (lift) { delete lift.pending; lift.lastIncrementLb = 0; }
    message = `${change.exerciseName} → ${replacement.name} for this slot.`;
  } else if (change.type === "tryShorterSpacing") {
    const old = program.preferredSessionSpacingDays || 3;
    program.preferredSessionSpacingDays = Math.max(2, change.days);
    message = `Preferred spacing: ${old} → ${program.preferredSessionSpacingDays} days.`;
  } else if (change.type === "useLinearTriples") {
    const lift = (program.days || []).flatMap((day) => day.lifts || [])
      .find((slot) => slot.id === change.slotID);
    if (!lift) throw new Error(`The program slot for ${change.exerciseName} no longer exists.`);
    if (lift.exerciseName !== change.exerciseName
        || (lift.prescription || "automatic") !== "linearFives"
        || lift.capacityManaged === false || (lift.maximumSets || C.DEFAULT_MAXIMUM_SETS) < 5
        || (lift.doubleProgressionSets ?? 3) !== 3 || (lift.currentReps ?? 5) !== 5
        || !Number.isFinite(change.expectedBaseWeightLb)
        || !Number.isFinite(lift.baseWeightLb)
        || Math.abs(lift.baseWeightLb - change.expectedBaseWeightLb) >= 0.01) {
      throw new Error(`The program slot for ${change.exerciseName} changed after this recommendation, so triples were not applied.`);
    }
    lift.doubleProgressionSets = 5;
    lift.currentReps = 3;
    lift.stallCount = 0;
    delete lift.pending;
    message = `${change.exerciseName}: 3×5 → 5×3; session-to-session loading stays in place.`;
  }
  return message;
}

// One-line audit snapshot of a program's structure, mirroring native
// CoachingService.programDescription — the accepted-decision before/after
// record has to read the same in either client's export.
export function programDescription(program) {
  const byOrder = (a, b) => (a.order ?? 0) - (b.order ?? 0);
  return [...(program.days || [])].sort(byOrder).map((day) => {
    const slots = [...(day.lifts || [])].sort(byOrder).map((lift) => `${lift.exerciseName}:lift`)
      .concat([...(day.accessories || [])].sort(byOrder)
        .map((accessory) => `${accessory.exerciseName}:${accessory.sets}`));
    return `${day.name}[${slots.join(",")}]`;
  }).join(" | ");
}

// `program` is the post-apply plan; `beforeProgram` (accepted decisions only)
// is the pre-apply plan the audit trail diffs against. Deferred decisions
// record no snapshot, like native CoachingService.record.
export function coachingDecision(program, recommendation, action, evidence, beforeProgram = null) {
  const accepted = action === "accepted";
  // Clamp like native: a ≥100% cut must persist the 1% floor, not a 0 that
  // fails the override parse and silently restores full accessory volume.
  const temporary = accepted && recommendation.change.type === "reduceAccessoryVolume"
    ? temporaryAccessoryValue(Math.max(1, 100 - recommendation.change.percent), program.cycleNumber, program.currentWeek)
    : accepted && recommendation.change.type === "useLinearTriples"
      ? `linearTriples:slot:${recommendation.change.slotID}:5x3`
      : null;
  return { id: crypto.randomUUID(), date: iso(new Date()), programId: program.uuid || program.id,
    ruleId: recommendation.ruleID, recommendationId: recommendation.id, action,
    title: recommendation.title, explanation: recommendation.explanation, evidence,
    beforeValue: accepted ? programDescription(beforeProgram || program) : null,
    afterValue: accepted ? (temporary ?? programDescription(program)) : null };
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
