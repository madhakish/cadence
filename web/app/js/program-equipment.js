import * as C from "./core.js";
import { Exercises, Programs, Sessions, sessionBelongsToProgram } from "./db.js";

// Return a revised plan. Session records and the original object stay intact
// until the caller commits the explicit equipment change.
export function restrictProgramEquipment(program, policy, exercises) {
  const revised = structuredClone(program);
  revised.equipmentPolicy = policy;
  const byName = new Map(exercises.map((exercise) => [exercise.name, exercise]));
  const names = (program.days || []).flatMap((day) => [...(day.lifts || []), ...(day.accessories || [])]).map((slot) => slot.exerciseName);
  const missing = policy === "freeWeightsOnly" ? names.filter((name) => !byName.has(name)) : [];
  if (missing.length) throw new Error(`The exercise library is missing ${[...new Set(missing)].join(", ")}. Restore its definition before changing equipment.`);
  const allowed = (name) => C.equipmentPolicyAllows(policy, byName.get(name)?.type);
  const removed = [];
  for (const day of revised.days || []) {
    for (const kind of ["lifts", "accessories"]) {
      day[kind] = (day[kind] || []).filter((slot) => {
        if (!allowed(slot.exerciseName)) { removed.push(slot.exerciseName); return false; }
        if (slot.revertToExerciseName && !allowed(slot.revertToExerciseName)) delete slot.revertToExerciseName;
        return true;
      });
    }
  }
  if (removed.length && program.tfhPolicy) {
    throw new Error("This changes the TFH layout. Remove the blocked exercises and review TFH setup before applying the equipment restriction.");
  }
  return { program: revised, removed };
}

export function assertProgramEquipmentAllowed(program, exercises) {
  if (program.equipmentPolicy !== "freeWeightsOnly") return;
  const byName = new Map(exercises.map((exercise) => [exercise.name, exercise]));
  const blocked = (program.days || []).flatMap((day) => [...(day.lifts || []), ...(day.accessories || [])])
    .filter((slot) => !C.equipmentPolicyAllows(program.equipmentPolicy, byName.get(slot.exerciseName)?.type))
    .map((slot) => slot.exerciseName);
  if (blocked.length) throw new Error(`Equipment restriction excludes ${[...new Set(blocked)].join(", ")}. Apply the restriction in program settings to remove those slots.`);
}

export async function applyProgramEquipmentPolicy(program, policy) {
  const result = restrictProgramEquipment(program, policy, await Exercises.all());
  if (result.removed.length && (await Sessions.openAll()).some((session) => sessionBelongsToProgram(session, program))) {
    throw new Error("Finish the current workout before removing program exercises. Its recorded sets will be kept.");
  }
  await Programs.save(result.program);
  Object.assign(program, result.program);
  return result.removed;
}
