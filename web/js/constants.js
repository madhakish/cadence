// App-level vocabulary shared across views (mirrors the Swift enums + Copy).
export const BODY_SITES = ["Left shoulder", "Left hip", "Right knee"];
export const WATCH_NOTES = {
  "Left shoulder": "Old trauma. Watch for 'not there' / weakness on pressing.",
  "Left hip": "Old dislocation. Watch during lunges and squats.",
  "Right knee": "Meniscectomy. Swelling after running = hard stop.",
};
export const watchNote = (s) => WATCH_NOTES[s] || "";

export const CATEGORIES = ["Main", "Accessory", "Conditioning"];
export const EX_TYPES = ["barbell", "dumbbell", "kettlebell", "bodyweight", "band", "machine", "timed", "conditioning"];
export const SET_FLAGS = ["clean", "grindy", "wobble", "stopped early"];

export const COPY = {
  sessionDone: "Bank it.",
  noSwelling: "Clear. Carry on.",
  swelling: "Hard stop on running. Let it settle.",
  emptyHistory: "Nothing logged yet.",
  shelved: "Shelved",
};
