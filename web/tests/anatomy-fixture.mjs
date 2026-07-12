// The normalization both the generator and the smoke assertion share: maps
// the anatomy data into the language-neutral fixture shape that Swift's
// AnatomyData decodes to (see AnatomyDataTests).
export async function normalizedAnatomy() {
  const A = await import("../js/anatomy.js");
  return {
    names: A.MUSCLE_NAMES,
    body: A.ANATOMY_BODY,
    regions: A.ANATOMY_REGIONS,
    map: A.MUSCLE_MAP,
    groupDefaults: A.MUSCLE_GROUP_DEFAULTS,
  };
}
