# Release notes: August 2026

This page summarizes features added in August 2026. Each section names what
changed, why it matters to your training, and points to the full reference
where that feature is documented. Both the iOS app and the web app receive
every feature.

## Backup restore preview with per-item diff

Before a backup restore commits, both apps now show exactly which exercises,
lift tracks, gyms, sessions, and programs would change — each named item
marked new, changed, or removed (unchanged items stay out of the way). The
preview is read-only until you explicitly tap **Restore**; if the backup
matches your current data, the app says so and skips the restore entirely.

**Why it matters.** Restores replace data wholesale. The preview catches
surprises — an old backup imported by mistake, or the wrong file entirely —
before anything is written.

**Full detail:** [Back up and restore your data](../how-to/back-up-and-restore.md)

## One-tap revert after an import

Right after a successful JSON import, the completion message offers
**Revert to checkpoint from before this import** alongside **Keep it**.
Cadence already writes a local checkpoint before every import; this surfaces
that recovery at the exact moment you would want it, using the same restore
path as the general "Restore latest checkpoint" control in Settings.

**Why it matters.** If you realize immediately that the import was a mistake,
the undo is one tap — no hunting for the local-recovery section.

**Full detail:** [Back up and restore your data](../how-to/back-up-and-restore.md)

## Off-program first-set targets from your own history

Add an exercise mid-session that isn't in your program, and its first set now
starts from your most recent completed top set of that lift at the same load
semantics — not from a generic default. The suggested set carries a short
caption saying where the number came from (your last exposure), so a
suggestion never reads as a prescription. With no matching history, the
conservative catalog default still applies, and barbell movements are never
suggested below the bar you actually have loaded.

**Why it matters.** Accessories and ad-hoc lifts fill the same role from
session to session. Starting from your own recent performance saves a trip to
the history chart, and the caption keeps you the judge of the number.

**Full detail:** [Run a training day](../how-to/run-a-training-day.md)

## Plateau flag on progression charts

The progression chart's trend caption now appends a **Plateaued** label — but
only when both things are true: the weekly rate rounds to exactly flat, and
the trend fit is reliable enough to act on (fit quality 0.4 or higher, the
same floor the caption's own fit description uses). A flat-looking number on
a noisy fit stays unflagged: that's noise, not a plateau.

**Why it matters.** Stalls are where programming decisions live. The flag
tells you when flat is real — time to hold, deload, or change methods — and
stays quiet when the data can't support the call.

**Full detail:** [History charts reference](history-charts.md)

## Declared-breaks time accounting

The Training section now summarizes the calendar days spent in each break
kind — Deload, Rest, Away, and Active recovery — over the window you're
viewing. Overlapping breaks of the same kind count each day once, not twice;
different kinds are tallied separately, so a day inside both a deload span
and an away span counts toward both.

**Why it matters.** Your training year has structure. Seeing break time by
kind at a glance shows how much of the year went to loading versus
recovering, and whether that balance matches your plan.

**Full detail:** [Declare a training break](../how-to/declare-a-training-break.md)

## Under the hood: test fixture isolation

The web test suite gained a shared fixture-cleanup helper so suites no longer
leak state between test blocks. No user-facing behavior changes.
