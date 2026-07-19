// The normalization both the generator and the smoke assertion share: maps
// PROGRAM_TEMPLATES into the language-neutral fixture shape that Swift's
// ProgramTemplateData structs decode to (see ProgramTemplateDataTests).
export async function normalizedTemplates() {
  const { PROGRAM_TEMPLATES } = await import("../js/templates.js");
  return PROGRAM_TEMPLATES.map((t) => ({
    id: t.id, name: t.name, tagline: t.tagline, focus: t.focus, roundingLb: t.roundingLb,
    exercises: t.exercises.map((e) => ({
      name: e.name, category: e.category, type: e.type, group: e.movementGroup,
      isUnilateral: !!e.isUnilateral, rest: e.defaultRestSeconds,
    })),
    days: t.days.map((d) => ({
      name: d.name,
      lifts: d.lifts.map((l) => ({
        exercise: l.exerciseName, role: l.role,
        baseWeightLb: l.baseWeightLb, estimatedMaxLb: l.estimatedMaxLb,
        prescription: l.prescription || "automatic", sets: l.sets || 0,
        startFraction: l.startFraction || 0,
      })),
      accessories: d.accessories.map((a) => ({
        exercise: a.exerciseName, sets: a.sets, minReps: a.minReps, maxReps: a.maxReps,
        weightLb: a.weightLb, incrementLb: a.incrementLb,
        startFraction: a.startFraction || 0,
      })),
    })),
  }));
}
