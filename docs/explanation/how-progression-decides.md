# How progression decides

The [progression rules](../reference/progression-rules.md) list *what*
the engine does; this page explains *why*.

## Why grade only the peak?

Weeks 1–2 build toward week 3; week 4 is recovery. The peak is the only
week that tests whether the current loading actually fits you, so it's
the only week that earns a verdict. Grading every session would make the
program twitchy — reacting to a bad Tuesday — where a wave should react
to trends.

## Why tapered increments instead of fixed jumps?

Fixed +5/cycle works until it doesn't, and then it fails abruptly. The
increment here is a fraction of your base scaled by *headroom* — how far
your working weight sits below a ceiling (90% or 78% of estimated 1RM,
by focus). Far from the ceiling you get meaningful jumps; near it,
progress shrinks to a plate, then to zero, instead of driving you into a
wall. Estimated 1RM itself is smoothed (70% old / 30% new) so one great
or terrible peak nudges the ceiling rather than yanking it.

## Why do stalls deload automatically?

One muddy cycle can be noise — sleep, stress, a bad week. Two in a row
is signal. At that point the honest move is to rebuild: −10%, reset, run
the wave back up. Automating it removes the negotiation lifters lose
with themselves, and the History note keeps the decision inspectable.

## Why is below-plan work a fail rather than a scaled grade?

The engine could try to pro-rate credit for 3×3 at a lighter weight, but
partial credit compounds into base weights that drift from reality. A
binary rule — the prescription was met or it wasn't (within half a plate
step for measurement noise) — keeps the base trustworthy, and the stall
path already handles "close but not there" humanely. Extra volume beyond
the prescription is always free.

## Why do accessories progress differently?

Wave loading suits low-rep barbell work. Accessories chase a different
adaptation: earn the top of a rep range across all sets, then add the
smallest load step and start again — classic double progression, graded
every session because there's no peak to wait for. Bodyweight work has
no load step to add, so it climbs reps indefinitely.

## What happens when I adjust a standalone lift?

The original sets, reps, and achievable load remain an immutable prescription
snapshot. The values you edit and complete are the performed record. Cadence
saves those actual values to History, then advances the standalone lift only
when every prescribed occurrence met its original reps and load. A lighter,
shorter, stopped, or incomplete exposure holds the next goal without erasing
the work. If the same tracked lift appears twice in one session, both sections
form one exposure and can advance the track at most once.

## Why won't a duplicate session advance things twice?

Progression state is a ledger, and a ledger must not double-post. Every
session carries the program position it was created from; if the program
has moved on by the time it's banked (a duplicate, or a session left
open across a repositioning), it becomes history — the training still
counts in your log — without moving the schedule. The same thinking
makes banking atomic: either everything commits (history, milestones,
progression) or nothing does, so a storage hiccup can't leave the ledger
half-written.
