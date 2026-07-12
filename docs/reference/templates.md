# Program templates reference

<!-- MUST MATCH web/js/templates.js ≡ CadenceCore ProgramTemplateData.swift,
     which are fixture-locked to web/tests/fixtures/program-templates.json.
     Edit templates → regenerate the fixture → update these tables. -->

What each pre-programmed style contains. All baselines are deliberately
light — set your own rotation-1 bases and est. 1RMs before day one
([how](../how-to/start-from-a-style.md)). Weights in lb; accessories
shown as sets × rep-range (+load step where loaded).

## Strength — Upper/Lower

4 days · focus **strength** · rounding 5 lb

| Day | Main | Complementary | Accessories |
|---|---|---|---|
| Upper A | Overhead Press (65 / e1RM 95) | Incline DB Press (50/80) | Chin-ups 3×5–10 · Single-arm DB Row 3×8–12 @40 (+5) |
| Lower A | Back Squat (135/205) | Romanian Deadlift (95/165) | Walking Lunges 3×10–20 · Hanging Knee Raise 3×8–15 |
| Upper B | Push Press (75/115) | Incline DB Press (50/80) | Push-ups 3×10–25 · Single-arm DB Row 3×8–12 @40 (+5) |
| Lower B | Deadlift (155/245) | Front Squat (95/155) | Back Extension 3×10–15 · Hanging Knee Raise 3×8–15 |

## Olympic Weightlifting

3 days · focus **strength** · rounding 5 lb

| Day | Main | Complementary | Accessories |
|---|---|---|---|
| Snatch Day | Snatch (65/115) | Overhead Squat (65/115) | Snatch Pull 3×3–5 @95 (+10) · Hanging Knee Raise 3×8–15 |
| Clean & Jerk Day | Clean & Jerk (85/145) | Front Squat (115/185) | Clean Pull 3×3–5 @115 (+10) · Pull-ups 3×5–10 |
| Strength Day | Back Squat (135/225) | Overhead Press (65/105) | Back Extension 3×10–15 · Hanging Knee Raise 3×8–15 |

## Metabolic Conditioning

3 days · focus **maintain** (loads hold; circuits progress by reps)

| Day | Circuit |
|---|---|
| Engine A | KB Swing 5×10–20 @35 · Burpees 4×8–15 · Mountain Climbers 4×20–40 |
| Engine B | Push-ups 4×10–25 · Ring Row 4×8–15 · Sit-ups 4×15–30 |
| Engine C | Box Jumps 4×8–15 · Goblet Squat 4×10–20 @35 · Walking Lunges 4×12–24 |

## Behavior on creation

- Library exercises the template needs are created if missing (with
  movement groups, so [swaps](swap-rules.md) work); existing exercises
  are never modified.
- The program is created **inactive** unless it's your first.
- Everything — days, lifts, weights, ranges — is editable afterward like
  any custom program.
