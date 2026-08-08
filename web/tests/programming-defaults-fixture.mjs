// Language-neutral snapshot shape shared by the web and Swift test suites.
export async function normalizedProgrammingDefaults() {
  const { PROGRAMMING_DEFAULTS } = await import("../app/js/programming-defaults.js");
  return PROGRAMMING_DEFAULTS.map((entry) => ({
    exerciseName: entry.exerciseName,
    slotCategory: entry.slotCategory,
    exerciseType: entry.exerciseType,
    weightLb: entry.weightLb,
    estimatedMaxLb: entry.estimatedMaxLb,
    incrementLb: entry.incrementLb,
  }));
}
