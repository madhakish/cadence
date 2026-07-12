# Program model reference

A **Program** owns training **Days**; each day owns **Lifts**
(wave-progressed) and **Accessories** (rep-range-progressed). Exactly one
program is active at a time; program-owned exercises are excluded from
the standalone "Next up" tracks.

## Program

| Field | Meaning |
|---|---|
| `name` | Display name |
| `focus` | `strength` / `hypertrophy` / `maintain` — see table below |
| `cycleNumber` | Which 4-week cycle you're on (increments at rollover) |
| `currentWeek` | 1 volume · 2 load · 3 peak · 4 rest (deload) |
| `nextDayIndex` | The day the Today screen offers next |
| `roundingLb` | Plate granularity; all prescriptions snap to it |
| `isActive` | Drives the Today screen |

### Focus

| Focus | Training-max ceiling | Per-cycle increment |
|---|---|---|
| strength | 90% of est. 1RM | 2.5% of base × headroom |
| hypertrophy | 78% of est. 1RM | 1.5% of base × headroom |
| maintain | — | never increments |

## Lift (per day)

| Field | Meaning |
|---|---|
| `role` | `main` (one per day, anchors it, rests longest) or `complementary` |
| `baseWeightLb` | Rotation-1 (volume week) working weight; the wave derives the other weeks |
| `estimatedMaxLb` | Smoothed Epley e1RM; seeds the ceiling, re-estimated from every banked peak |
| `stallCount` | Consecutive non-clean cycles; 2 triggers an automatic −10% deload |
| `lastIncrementLb` | What the last rollover added |
| `pending…` | Week-3 grade stashed until rollover |
| `revertToExerciseName` | Set by a cycle-scoped swap; the slot reverts to this name at rollover |

## Accessory (per day)

| Field | Meaning |
|---|---|
| `sets` | Working sets |
| `minReps` / `maxReps` | The rep range to earn |
| `currentReps` | Today's target reps |
| `weightLb` | Current load |
| `incrementLb` | Load added when the range is earned; **0 = bodyweight** (climbs reps indefinitely, `maxReps` advisory) |
| `revertToExerciseName` | As for lifts |

## Sessions generated from a day

Starting a program day pre-fills one session exercise per lift and
accessory, tagged with the program, cycle, week, day, and role. Barbell
lifts get a warmup ramp; complementary/accessory barbell work snaps to a
neat bar-loadable weight. The tag is what completion validates before
advancing anything — see
[Progression rules](progression-rules.md#stale-sessions).
