# How progression decides

The [progression rules](../reference/progression-rules.md) list *what*
the engine does; this page explains *why*.

## Why grade only the peak?

The volume and load rotations build toward the third, peak rotation. Recovery
then bridges into the next mesocycle with only one lower and one upper
exposure. The peak is the only rotation that tests whether the current loading
actually fits you, so it is the only one that earns a verdict. Grading every
session would make the program twitchy where a wave should react to trends.

## Why is recovery not a fourth rotation?

A full A/B pass preserves normal lifting frequency even after load and sets
fall. That is more training at exactly the point the accumulated-fatigue block
is supposed to end. Cadence therefore keeps the movement patterns familiar
with two reduced exposures, collapses accessories to one set, and freezes every
progression and e1RM side effect. Active work between them—walking, mowing,
splitting wood, or an easy ruck—does not need to be forced into a calendar week
or represented as another lifting day.

That reduction is the point. A 2024 controlled study found that inserting a
week of complete training cessation did not improve hypertrophy and produced
smaller strength gains than continuous training. A 2026 within-subject study
found that reducing set volume by roughly two thirds to three quarters and
cutting frequency preserved hypertrophy and 10RM improvement in untrained men.
Neither study proves one universal deload for an experienced lifter outside
those study populations, but together they support keeping a small amount of
familiar work while cutting the total stress hard. That is what the
two-exposure bridge does.

- [Coleman et al. 2024 — one-week deload](https://pubmed.ncbi.nlm.nih.gov/38274324/)
- [Pancar et al. 2026 — reduced-volume/frequency deload](https://www.nature.com/articles/s41598-026-40612-5)

## Why doesn't Cadence rotate complementary lifts on a timer?

Complement selection belongs to the authored program. Same-session squat and
hinge work with contrasting stress can be perfectly reasonable when technique,
performance, and recovery remain sound. Acute biomechanics studies can show
that a trap bar shifts joint moments or that front and back squats distribute
load differently; they do not establish that every pain-free lifter should
swap movements at an arbitrary bar weight or every four calendar weeks.

Keep a useful complement through the mesocycle so it can actually progress.
Reassess it at rollover when performance stalls, setup friction kills
adherence, or body feedback gives a concrete reason to change it. Cadence does
not diagnose an old injury, infer pain, or manufacture a variation schedule
from age alone.

- [Swinton et al. 2011 — straight versus hex-bar deadlift biomechanics](https://pubmed.ncbi.nlm.nih.gov/21659894/)
- [Gullett et al. 2009 — front versus back squat biomechanics](https://pubmed.ncbi.nlm.nih.gov/19002072/)

## Why a proportional increment, and why no ceiling?

The increment is a fraction of your current base — 2.5% for strength,
1.5% for hypertrophy — floored to a loadable step. A 400 lb squat and a
95 lb press should not both move 5 lb, and this way they don't.

It used to be scaled by *headroom* to a training-max ceiling as well, so
progress would shrink to nothing as you approached 90% (or 78%) of your
estimated 1RM. That is gone, because measuring it showed it never worked:
across every realistic combination of base and estimate it produced one
plate step or nothing, never anything between, and the "nothing" could not
be reached after a clean peak. The reason is circular — the peak set is
1.175 × base, so the estimate derived from it always outruns a ceiling
derived from the same base. A ceiling that moves with the thing it is
meant to bound is not a ceiling.

What actually stops you running into a wall is failure, which the engine
already reads: two consecutive stalls rebuild the base at 90%. That is
how the published systems do it too — Wendler resets the training max,
Rippetoe resets after repeated missed sessions. Estimated 1RM is still
smoothed (70% old / 30% new) so one great or terrible session nudges it
rather than yanking it; it just no longer gates the increment.

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
