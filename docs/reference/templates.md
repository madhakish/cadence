# Program templates reference

<!-- Structure MUST MATCH web/app/js/templates.js ≡ CadenceCore
     ProgramTemplateData.swift, fixture-locked to program-templates.json.
     The weights below are resolved no-history values from the separately
     parity-locked programming-defaults catalog. -->

What each pre-programmed style contains. Cadence uses completed history when it
exists; the values below show the conservative **no-history** bootstrap.
Weights are in lb; dumbbell loads are per implement; accessories are shown as
sets × rep-range (+load step where loaded). See [Programming defaults](programming-defaults.md).

## Strength — Upper/Lower

4 days · focus **strength** · rounding 5 lb

The upper days alternate the two presses — A has the overhead emphasis,
B the incline — and each day's accessories support that day's press.
Every day carries core work.

| Day | Main | Complementary | Accessories |
|---|---|---|---|
| Upper A | Overhead Press (45 / e1RM 65) | Incline DB Press (10/20) | DB Overhead Triceps Extension 3×8–12 @5 (+5) · Y-T-W Raises 3×10–15 @5 (+2.5) · GHD Sit-up 3×8–15 |
| Lower A | Back Squat (45/65) | Romanian Deadlift (45/65) | Walking Lunges 3×10–20 · Hanging Knee Raise 3×8–15 |
| Upper B | Incline DB Press (10/20) | Overhead Press (45/65) | Dips 3×5–12 · Band Pull-aparts 3×15–25 · Hanging Knee Raise 3×8–15 |
| Lower B | Deadlift (65/95) | Front Squat (45/65) | Back Extension 3×10–15 · GHD Sit-up 3×8–15 |

## Olympic Weightlifting

3 days · focus **strength** · rounding 5 lb

| Day | Main | Complementary | Accessories |
|---|---|---|---|
| Snatch Day | Snatch (35/55) | Overhead Squat (35/55) | Snatch Pull 3×3–5 @45 (+10) · Hanging Knee Raise 3×8–15 |
| Clean & Jerk Day | Clean & Jerk (45/65) | Front Squat (45/65) | Clean Pull 3×3–5 @45 (+10) · Pull-ups 3×5–10 |
| Strength Day | Back Squat (45/65) | Overhead Press (45/65) | Back Extension 3×10–15 · Hanging Knee Raise 3×8–15 |

## Metabolic Conditioning

3 days · focus **maintain** (loads hold; circuits progress by reps)

| Day | Circuit |
|---|---|
| Engine A | KB Swing 5×10–20 @15 · Burpees 4×8–15 · Mountain Climbers 4×20–40 |
| Engine B | Push-ups 4×10–25 · Ring Row 4×8–15 · Sit-ups 4×15–30 |
| Engine C | Box Jumps 4×8–15 · Goblet Squat 4×10–20 @15 · Walking Lunges 4×12–24 |

## Methodology templates

Five templates automate published programs — see
[Training methodologies](training-methodologies.md) for the full rules,
percentages, and progression each one runs:

| Template | Days | Structure |
|---|---|---|
| Novice Linear — 3×5 | A/B ×3/wk | Squat 3×5 every day · press/bench alternate 3×5 · deadlift 1×5 |
| Novice Linear — 5×5 | A/B ×3/wk | Squat 5×5 · bench+row / press+deadlift split |
| Texas Method | 6 (two weeks) | Volume 5×5 · light day · intensity 1×5 PR; presses alternate weekly |
| 5/3/1 — Wendler | 4 | One main lift per day off a 90% training max, plus Boring-But-Big 5×10 |
| Conjugate — Westside | 4 | Weekly special-exercise max effort ×2 · independent 3-week speed loops ×2 · repetition work + sled GPP |

### Conjugate — Westside

| Day | Main work | Assistance |
|---|---|---|
| Mon — Max Effort Lower | Low Box Squat · 3 heavy singles · rotate weekly | Nordic curl 4×6–10 · back extension 4×10–15 · hanging knee raise 4×10–15 |
| Wed — Max Effort Upper | Floor Press · 3 heavy singles · rotate weekly | Skull crusher 4×8–12 · barbell row 4×8–12 · face pulls 3×12–15 |
| Fri — Dynamic Effort Lower | Speed Box Squat 12/12/10×2 @50/55/60% · Speed Deadlift 6×1 @50/55/60% | Nordic curl · back extension · hanging knee raise · Sled Pull 4×60 sec easy |
| Sun — Dynamic Effort Upper | Speed Bench 9×3 @40/45/50% | Triceps pushdown · lat pulldown · rear-delt fly |

See the reviewed [implementation and source map](conjugate-method.md), including
the weekly variation pools and the boundaries of the straight-bar prescription.

## Behavior on creation

- Library exercises the template needs are created if missing (with
  movement groups, so [swaps](swap-rules.md) work); existing exercises
  are never modified.
- The program is created **inactive** unless it's your first.
- Main slots derive their opening weights from your best recorded e1RM and the
  resolved prescription's conservative fraction, rounded down to the plate
  step. Special conjugate exercises may deliberately name their competition
  lift as the history source.
- Accessories reuse the most recent completed working weight. Explicit
  methodology fractions (such as Boring-But-Big) take precedence.
- With no usable history, the shared exercise/equipment catalog supplies a
  conservative nonblank load for loaded work. Bodyweight, bands, timed work,
  and conditioning remain at zero because pounds are not their progression.
- Everything — days, lifts, weights, ranges — is editable afterward like
  any custom program.
