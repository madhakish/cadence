# Apple Health

*(iOS only. The web app has no access to Health.)*

Cadence exchanges data with Apple Health in two directions. They are
**separate permissions**, both **off by default**, and granting one does not
grant the other. Turn either on in **Settings → HealthKit**.

## What Cadence writes

With the write half enabled, finishing a session mirrors it to Health as a
workout carrying its start, end, activity type, and the conditioning distance
you logged. Logging a bodyweight writes that weight, plus body fat percentage
when you entered one.

Distance is worked out **per exercise**, not from the session as a whole. A
lifting day that finishes with a walk is a mixed session, and asking what type
of distance a *mixed* session covered has no good answer — so the walk's miles
are filed as foot distance and a bike cooldown's as cycling distance, even in
the same workout. Rowing and swimming carry duration only; Cadence does not log
the units Health wants for those.

### What Health cannot hold

Health has no schema for sets, reps, or load. `traditionalStrengthTraining`
plus a duration is the entire vocabulary Apple provides for lifting, which is
why every lifting app shows a duration in Health and nothing more. Your Cadence
log stays the only complete record of a session, and the only one a backup
restores.

Cadence also does **not** write an energy or calorie estimate. It has no heart
rate to work from, and a fabricated figure in a store other apps trust is worse
than silence.

## What Cadence reads

| | Where it appears | What it does |
|---|---|---|
| Conditioning distance | History → session detail | Compared against the session's logged distance |
| Workout energy | History → session detail | Shown for the session window |
| Bodyweight and body fat | Body | Offered as a weigh-in to log, on an explicit tap |
| HRV, resting heart rate, sleep | Body | Displayed only |

### Reading suggests; it never merges

Nothing Health says is written into your log on its own. A weigh-in Health has
that Cadence does not is offered with both the number and its date, and
becomes an entry only when you tap to log it. A conditioning distance that
disagrees names **both** figures and leaves the choice to you. See
[Conditioning](conditioning.md) for how that comparison is matched and toleranced.

Absence is never a finding. If Health has nothing for a window, or the read
permission was denied, Cadence shows nothing rather than a zero — an unworn
watch is not evidence that you did not train.

### Cadence never compares against itself

Every read excludes the records Cadence itself wrote. Without that, the app
would read back its own mirrored workouts and weigh-ins, agree with the log
perfectly every time, and present that as confirmation.

A sample whose source cannot be identified is treated as somebody else's: it is
better to show a second opinion that might be your own than to silently discard
a real one.

## Recovery signals do not drive your program

HRV, resting heart rate, and sleep are shown on the Body screen and go no
further. They do not feed readiness, deloads, or prescription.

This is deliberate. Cadence grades progression from work actually performed —
whether you completed the sets, at what quality, with how many reps in
reserve — and for a self-coached lifter those output markers are a more
defensible signal than an overnight heart-rate reading. The recovery figures
are context for your own judgement, not an input to the engine.

Sleep is counted from the sleep **stages** Health recorded, not from time in
bed; a night on the mattress with no staging reports nothing rather than eight
hours. Where several apps staged the same night — a watch and a sleep tracker,
say — their intervals are **merged, not added**. Excluding Cadence's own writes
does not reduce Health to a single source, and summing two instruments would
report ten hours to someone who slept five.

## Turning it off

Revoking either permission in the iOS Health app stops the corresponding half
immediately. Data already written to Health stays there and is managed in
Health, not in Cadence. The read opt-in is stored on the device and is
deliberately **not** included in a backup — restoring on a new phone would
otherwise imply a Health grant that phone never gave.
