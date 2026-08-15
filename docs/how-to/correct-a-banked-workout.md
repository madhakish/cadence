# Correct a banked workout

Noticed after finishing that a set you performed never got its ✓, or that
a set banked the planned weight instead of what you actually lifted?
Banked history is editable.

Open the workout from **History → Log**, then tap **Edit** (top right on
iOS, in the header on web).

## What you can change

For every lifting set:

- **Status** — tap the status mark to cycle *not performed → completed →
  skipped*. A set you performed but never ticked mid-workout becomes real
  history with one tap.
- **Weight** — retype it in your display unit. Stored canonically in
  pounds like every other entry surface.
- **Reps** — retype the count.
- **Timed holds** (planks and friends) — retype the seconds.

A blank or negative entry keeps the stored value — a correction can never
write garbage into your log. Everything else about the set is deliberately
out of reach: quality flags, warm-up status, body signals, and the
*planned* prescription stay exactly as the workout recorded them, so the
plan-versus-actual comparison stays honest.

Conditioning rows (distance, flights, pace) are not edited here — use the
Apple Health comparison on the session detail, which reconciles against a
measurement instead of a memory.

Tap **Done** (iOS) / **Save** (web) to commit.

## What a correction affects

The corrected history is the record these surfaces read:

- session volume, work-set counts, and duration summaries,
- progression charts and last-time recall lines,
- exports and backups,
- the prior-best comparisons future grading reads (est. 1RM history), and
- the narrow performed-evidence repair that plans barbell volume work
  (`honestBase` reads the last volume exposure's top set).

Three things a correction does **not** do — be honest with yourself about
these:

- It does **not** re-run the progression grading that fired when you
  banked the workout. That grade was computed from the uncorrected sets
  and stashed into the lift's pending state; the rollover applies the
  stash without re-reading history. If the *next prescription's base* is
  wrong, fix the lift's base weight in **Settings → your program → the
  lift** — that is the number planning actually builds from.
- It does not re-scan for personal records, so a milestone is neither
  invented nor revoked by an edit.
- It does not touch the planned prescription snapshot — the
  plan-versus-actual comparison keeps showing what was prescribed.
