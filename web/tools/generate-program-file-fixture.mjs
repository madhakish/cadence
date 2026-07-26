// Regenerates web/tests/fixtures/program-file.json — the shared program-file
// fixture asserted from BOTH suites: the node program-file test checks
// web/app/js/program-file.js still produces it, and Swift's
// ProgramFileContractTests decodes it and re-encodes it byte-for-byte. Either
// mirror drifting fails its own CI job.
//
// Written through the real exporter, so the fixture cannot claim a shape the
// production writer does not emit. Everything in it is obviously synthetic:
// fictional program and day names, round numbers, and fixed UUIDs — no real
// training data belongs in the repository.
//
// Run: node tools/generate-program-file-fixture.mjs
import { writeFileSync } from "node:fs";
import { exportProgramFile } from "../app/js/program-file.js";

// Fixed ids so regeneration is deterministic. Deliberately patterned rather
// than random-looking, to read as fixture data at a glance.
const ID = (n) => `f1000000-0000-4000-8000-00000000000${n}`;

// The fixture carries state AND identity: that is the widest shape the
// contract allows, so validating it exercises every optional field.
const program = {
  uuid: "f0000000-0000-4000-8000-000000000000",
  name: "Fixture Upper/Lower",
  focus: "strength",
  roundingLb: 5,
  coachEnabled: true,
  preferredSessionSpacingDays: 3,
  maximumAddedSetsPerRotation: 6,
  cycleNumber: 3,
  currentWeek: 2,
  // A day ORDER, not an array position — and it has to name a day this
  // program actually has. The days below are orders 0 and 2, so 1 would be a
  // pointer to nothing.
  nextDayIndex: 2,
  days: [
    {
      name: "Fixture Lower",
      order: 0,
      lifts: [
        {
          id: ID(1), exerciseName: "Back Squat", role: "main", order: 0,
          prescription: "automatic", warmupPolicy: "automatic",
          loadOffsetLb: 0, peakOffsetLb: 0, deloadMultiplier: 0.775,
          doubleProgressionSets: 3, minimumReps: 5, maximumReps: 8, currentReps: 5,
          peakSingleEnabled: false, peakSingleIncrementLb: 5, phasePrimerEnabled: true,
          dropIncrementLb: 0, capacityManaged: true, maximumSets: 6,
          baseWeightLb: 185, estimatedMaxLb: 225,
          stallCount: 0, lastIncrementLb: 5, lastPeakSingleLb: 0,
          // A stashed week-3 grade: the field most easily lost in a round trip.
          pending: {
            state: { baseWeightLb: 190, estimatedMaxLb: 230, stallCount: 0, lastIncrementLb: 5 },
            note: "Clean peak — add 5 lb next cycle.",
          },
        },
        {
          // Explicit offsets, as a per-hand dumbbell slot needs: the
          // movement-group defaults are tuned for barbell work.
          id: ID(2), exerciseName: "Bulgarian Split Squat", role: "complementary", order: 1,
          prescription: "automatic", warmupPolicy: "short",
          loadOffsetLb: 5, peakOffsetLb: 5, deloadMultiplier: 0.775,
          doubleProgressionSets: 3, minimumReps: 5, maximumReps: 8, currentReps: 5,
          peakSingleEnabled: false, peakSingleIncrementLb: 5, phasePrimerEnabled: true,
          dropIncrementLb: 0, capacityManaged: true, maximumSets: 6,
          baseWeightLb: 25, estimatedMaxLb: 50,
          stallCount: 1, lastIncrementLb: 0, lastPeakSingleLb: 0,
        },
      ],
      accessories: [
        {
          // Timed accessory: progresses by duration, so a zero increment is
          // correct here and must not read as a missing step.
          id: ID(3), exerciseName: "Copenhagen Plank", order: 0,
          sets: 3, minReps: 8, maxReps: 12, currentReps: 8,
          targetSeconds: 20, durationStepSeconds: 5,
          capacityManaged: true, maximumSets: 6,
          conditioningEffort: "easy", targetRPE: 0, weightLb: 0, incrementLb: 0,
          stallCount: 0,
        },
      ],
    },
    {
      // A deliberate gap: day order is the identity banked sessions refer to,
      // so a non-contiguous order must survive export and import verbatim.
      name: "Fixture Upper",
      order: 2,
      lifts: [
        {
          id: ID(4), exerciseName: "Overhead Press", role: "main", order: 0,
          prescription: "fiveThreeOne", warmupPolicy: "full",
          loadOffsetLb: 10, peakOffsetLb: 15, deloadMultiplier: 0.8,
          doubleProgressionSets: 5, minimumReps: 3, maximumReps: 5, currentReps: 5,
          peakSingleEnabled: true, peakSingleIncrementLb: 2.5, phasePrimerEnabled: false,
          dropIncrementLb: 5, capacityManaged: false, maximumSets: 8,
          baseWeightLb: 95, estimatedMaxLb: 115,
          stallCount: 0, lastIncrementLb: 5, lastPeakSingleLb: 135,
          // Cycle-scoped swap marker: losing it turns a temporary swap into a
          // permanent rename.
          revertToExerciseName: "Push Press",
        },
      ],
      accessories: [
        {
          // Fractional increment: a 5 lb step on a 10 lb load would be a 50%
          // jump, so the model must carry a non-integer step.
          id: ID(5), exerciseName: "Y-T-W Raises", order: 0,
          sets: 3, minReps: 8, maxReps: 12, currentReps: 10,
          targetSeconds: 30, durationStepSeconds: 5,
          capacityManaged: true, maximumSets: 6,
          conditioningEffort: "easy", targetRPE: 7, weightLb: 10, incrementLb: 2.5,
          stallCount: 2,
        },
      ],
    },
  ],
};

const file = exportProgramFile(program, { includeState: true, includeIdentity: true });

// Recursive key sort, matching the exporter and Swift's `.sortedKeys`.
const stable = (value) => {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((k) => [k, stable(value[k])]));
  }
  return value;
};

const out = new URL("../tests/fixtures/program-file.json", import.meta.url);
writeFileSync(out, `${JSON.stringify(stable(file), null, 2)}\n`);
console.log(`wrote ${out.pathname}`);
