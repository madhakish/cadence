// Conservative, nonpersonal bootstrap loads for program construction.
// This is reference data, not athlete state: it is never persisted, exported,
// or mixed with body measurements. Completed workout history replaces it.
const rec = (slotCategory, exerciseType, weightLb, estimatedMaxLb, incrementLb,
  exerciseName = null) => ({ exerciseName, slotCategory, exerciseType, weightLb, estimatedMaxLb, incrementLb });

export const PROGRAMMING_DEFAULTS = [
  rec("Main", "barbell", 65, 95, 5, "Deadlift"),
  rec("Main", "barbell", 35, 55, 5, "Snatch"),
  rec("Main", "barbell", 35, 55, 5, "Overhead Squat"),
  rec("Main", "barbell", 45, 65, 5, "Clean & Jerk"),
  rec("Main", "dumbbell", 10, 20, 5, "Incline DB Press"),

  rec("Accessory", "dumbbell", 5, 8, 2.5, "Y-T-W Raises"),
  rec("Accessory", "dumbbell", 5, 8, 2.5, "Rear Delt Fly"),
  rec("Accessory", "dumbbell", 5, 10, 2.5, "DB Overhead Triceps Extension"),
  rec("Accessory", "kettlebell", 15, 25, 5, "KB Swing"),
  rec("Accessory", "kettlebell", 15, 25, 5, "Goblet Squat"),
  rec("Accessory", "barbell", 20, 30, 5, "Skull Crusher"),
  rec("Accessory", "barbell", 45, 65, 5, "Barbell Row"),
  rec("Accessory", "barbell", 45, 65, 5, "Snatch Pull"),
  rec("Accessory", "barbell", 45, 65, 5, "Clean Pull"),
  rec("Accessory", "barbell", 45, 65, 5, "Overhead Press"),
  rec("Accessory", "barbell", 45, 65, 5, "Barbell Bench"),
  rec("Accessory", "barbell", 45, 65, 5, "Back Squat"),
  rec("Accessory", "barbell", 65, 95, 5, "Deadlift"),
  rec("Accessory", "machine", 10, 20, 5, "Face Pulls"),
  rec("Accessory", "machine", 10, 20, 5, "Triceps Pushdown"),
  rec("Accessory", "machine", 20, 35, 5, "Lat Pulldown"),
  rec("Accessory", "machine", 20, 35, 5, "Lying Leg Curl"),

  rec("Main", "barbell", 45, 65, 5),
  rec("Main", "dumbbell", 10, 20, 5),
  rec("Main", "kettlebell", 15, 25, 5),
  rec("Main", "machine", 20, 35, 5),
  rec("Main", "bodyweight", 0, 0, 0),
  rec("Main", "band", 0, 0, 0),
  rec("Main", "timed", 0, 0, 0),
  rec("Main", "conditioning", 0, 0, 0),
  rec("Accessory", "barbell", 20, 30, 5),
  rec("Accessory", "dumbbell", 5, 10, 2.5),
  rec("Accessory", "kettlebell", 10, 20, 5),
  rec("Accessory", "machine", 10, 20, 5),
  rec("Accessory", "bodyweight", 0, 0, 0),
  rec("Accessory", "band", 0, 0, 0),
  rec("Accessory", "timed", 0, 0, 0),
  rec("Accessory", "conditioning", 0, 0, 0),
  rec("Conditioning", "conditioning", 0, 0, 0),
];

export function recommendation(exerciseName, slotCategory, exerciseType) {
  return PROGRAMMING_DEFAULTS.find((entry) => entry.exerciseName === exerciseName
    && entry.slotCategory === slotCategory && entry.exerciseType === exerciseType)
    || PROGRAMMING_DEFAULTS.find((entry) => entry.exerciseName == null
      && entry.slotCategory === slotCategory && entry.exerciseType === exerciseType)
    || PROGRAMMING_DEFAULTS.find((entry) => entry.exerciseName == null
      && entry.slotCategory === slotCategory
      && entry.exerciseType === (slotCategory === "Conditioning" ? "conditioning" : "dumbbell"))
    || rec(slotCategory, exerciseType, 5, 10, 2.5);
}
