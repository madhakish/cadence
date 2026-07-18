// App-level vocabulary shared across views (mirrors the Swift enums + Copy).
export const BODY_SITES = ["Shoulder", "Hip", "Knee"];
export const WATCH_NOTES = {
  Shoulder: "Track comfort and range of motion during upper-body work.",
  Hip: "Track comfort and range of motion during lower-body work.",
  Knee: "Track comfort during squatting, lunging, and running.",
};
export const watchNote = (s) => WATCH_NOTES[s] || "";
export const normalizeBodySite = (value) => {
  if (BODY_SITES.includes(value)) return value;
  const normalized = String(value || "").trim().toLowerCase();
  return BODY_SITES.find((candidate) => normalized.endsWith(candidate.toLowerCase())) || null;
};

export const CATEGORIES = ["Main", "Accessory", "Conditioning"];
export const EX_TYPES = ["barbell", "dumbbell", "kettlebell", "bodyweight", "band", "machine", "timed", "conditioning"];
export const SET_FLAGS = ["clean", "grindy", "wobble", "stopped early"];

export const COPY = {
  sessionDone: "Bank it.",
  noSwelling: "All clear.",
  swelling: "Pause and reassess before continuing.",
  emptyHistory: "Nothing logged yet.",
  shelved: "Shelved",
};
