# Build a custom program

Use this guide when you already know your split and want to encode it.
If you're new to Cadence's program model, the
[first-program tutorial](../tutorials/first-program.md) walks the same
ground with more explanation.

## Create the shell

**Settings → Programs → + Add program → Blank program**, then open it:

| Setting | What it does |
|---|---|
| Name | Display only |
| Focus | Strength / Hypertrophy / Maintain — sets increment size and the training-max ceiling ([details](../reference/progression-rules.md)) |
| Rounding | Plate granularity; every prescription snaps to it (default 5 lb) |
| Active | The active program drives the Today screen; exactly one program is active at a time |
| Rotation | Your position in the 4-week wave — set it if you're migrating mid-cycle |

## Add days

**+ Add day** for each training day, in rotation order. Name them
whatever you like ("Upper A", "Snatch Day"). Days rotate in order and
the wave advances one week each time the **last** day is banked.

## Add lifts (wave-progressed work)

Per day, **+ Add lift** and set:

- **Role** — **Main** (one per day: the anchor, longest rest) or
  **Comp.** Both are graded at the peak and progressed at rollover.
- **Rotation-1 base** — the week-1 volume weight. The wave derives every
  other week from it.
- **Est. 1RM** — seeds the training-max ceiling; re-estimated from every
  banked peak.

A lift can appear on multiple days; each slot progresses independently.

## Add accessories (rep-range work)

Per day, **+ Add accessory** and set sets, min–max rep range, weight,
and **Load step**. Accessories use double progression: earn the top of
the rep range on all sets → add the load step and reset to min reps.
**Load step 0 marks bodyweight work** — it climbs reps indefinitely
instead of adding load.

## Sanity checklist before day one

- Exactly one **Main** lift per day.
- Rotation-1 bases honest (comfortable 3×5 today, not aspirational).
- Bodyweight accessories have load step 0.
- The program is **Active** and Rotation shows week 1 unless you're
  intentionally mid-cycle.
- New movement you might need alternates for? Give the exercise a
  **movement group** in the library so [swaps](swap-an-exercise.md)
  are offered.
