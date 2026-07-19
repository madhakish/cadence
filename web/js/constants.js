// App-level vocabulary shared across views (mirrors the Swift enums + Copy).
export const BODY_SITES = ["Shoulder", "Hip", "Knee", "Back", "Elbow", "Wrist", "Ankle", "Groin", "Neck"];
export const WATCH_NOTES = {
  Shoulder: "Track comfort and range of motion during upper-body work.",
  Hip: "Track comfort and range of motion during lower-body work.",
  Knee: "Track comfort during squatting, lunging, and running.",
  Back: "Track comfort and tolerance during loaded trunk and hinge work.",
  Elbow: "Track comfort during pressing, pulling, and arm work.",
  Wrist: "Track comfort in loaded grip and rack positions.",
  Ankle: "Track comfort and range during lower-body and conditioning work.",
  Groin: "Track comfort during wide-stance, unilateral, and adductor work.",
  Neck: "Track comfort and position during loaded work.",
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
