# Start from a pre-programmed style

Cadence ships ready-made program styles so you can start training
without building anything. Templates are starting points, not contracts —
everything in them is editable afterward.

## Create a program from a style

1. Open **Settings → Programs** and tap **+ Add program**.
2. Pick a style:
   - **Strength — Upper/Lower** · 4 days · barbell strength A/B split
   - **Olympic Weightlifting** · 3 days · snatch, clean & jerk, strength base
   - **Metabolic Conditioning** · 3 days · circuits and engine work
   - **Novice Linear — 3×5 / 5×5** · A/B progression every session
   - **Texas Method** · volume, light, and intensity days
   - **5/3/1 — Wendler** · four training-max days
   - **Conjugate — Westside** · weekly max effort plus three-week speed loops
   - (or **Blank program** to build your own)
3. The program appears in your list with all its days, lifts, and
   accessories filled in. Any exercises it needs that aren't in your
   library are added automatically — existing exercises are never
   modified.

Each template is a composition of slot-level prescriptions. You can mix those
styles in the editor or import a standalone program file containing any
combination; choosing a template never changes the engine for your other
programs.

The first program you ever create becomes **Active** automatically;
otherwise the new program is created inactive so it doesn't hijack your
Today screen. Activate it from its editor when you're ready to switch.

## Starting weights fill themselves in

Cadence checks your completed workout history when it creates the program.
Main lifts derive a conservative opening base from your recorded e1RM and the
slot's selected prescription. Accessories reuse the most recent completed
working weight. A methodology-specific percentage, such as 5/3/1 or
Boring-But-Big, wins where the method requires one.

If you have never logged a movement, Cadence supplies a conservative
exercise/equipment default instead of leaving a blank. Those defaults are
reference data, not another profile: they are not body measurements and are
never exported as athlete state. Correct the load when you perform the movement
the first time; the next program you create will use that recorded result.

Review the first session and edit anything that does not fit your equipment or
experience. Very light movements are intentionally very light — Y-T-W raises,
for example, start at 5 lb per dumbbell when no history exists.

## Rotate training blocks without losing your place

Only one program drives Today, but inactive programs keep their own day,
rotation, and progression state. Activate an Oly or conditioning block for a
while, then reactivate an earlier Conjugate program to resume it exactly where
you left it.

Completed exercise history is global to you rather than owned by one program.
If you create a fresh template later, it can reuse relevant work logged in any
earlier block — squat and press history can seed Conjugate, Snatch history can
seed another Oly block, and a recent kettlebell load can seed conditioning.
Creating a new copy gets current history-derived starts; reactivating an
existing copy preserves that program's saved progression.

## What the styles assume

See [Program templates](../reference/templates.md) for the exact
contents of each style. In brief: the two lifting styles run the full
4-week wave with strength-focus progression; Metabolic Conditioning uses
**Maintain** focus — loads hold steady and the circuits progress by
adding reps, which is the progression that makes sense for engine work.

## Related

- [Build a custom program](build-a-custom-program.md) if no style fits
- [Programming defaults](../reference/programming-defaults.md) for the exact
  history/default resolution order
- [Edit a program mid-cycle](edit-a-program-mid-cycle.md) to reshape a
  template after you've started it
