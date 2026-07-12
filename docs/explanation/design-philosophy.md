# Design philosophy

Cadence holds an opinion about training. These are the constraints that
keep the app coherent, and the docs make more sense once you know them.

## Adherence dominates outcome

The best program is the one that gets executed. So the plan you see is
simple — four weeks, a handful of lifts, prescriptions you tap to
confirm — and all the complexity lives *inside* the autoregulation,
triggered by data you'd log anyway. There are no periodization knobs to
fiddle; there is a program that reacts to what you actually did.

## Guide, don't interrogate

Every required tap must earn itself. A program day pre-fills weight,
sets, reps, and warmups so a set is one tap to confirm. Cadence asks a
question only when the answer changes a decision (was that set grindy?)
— and wrong auto-detection being worse than manual entry, it prefers to
ask one light question over guessing and corrupting the log.

## The program is the prior

A known plan collapses ambiguity. "Which of 470 exercises is this?"
becomes "which of today's five?" — that's why swaps offer a short,
same-pattern list instead of a search box, and why the Today screen
offers exactly one thing to start.

## Honest grading over encouragement

The engine grades what happened, not what was intended: reps at reduced
weight aren't a clean success; a substituted peak is a skipped peak; two
muddy cycles trigger a deload rather than a third attempt at a lie. The
cost of honesty is occasionally feeling strict; the payoff is that when
the app says *add weight*, you can trust it.

## Local-first, no accounts

Your training data lives on your device and moves only in backup files
you export yourself. This keeps the app fast, private, and free of
infrastructure — with the trade-off that
[backups are your job](../how-to/back-up-and-restore.md). (The roadmap
contemplates an optional sync portal later; local-first stays the
default either way.)

## One brain, two apps

The iOS app and the web app share one deterministic engine (literally
the same logic, mirrored and tested in lockstep), so a decision made on
one platform is the decision the other would have made. Backups are the
interchange; nothing about your program means something different on the
other device.
