# Apple Health

*(iOS only. The web app has no access to Health.)*

Cadence exchanges data with Apple Health in two directions. They are
**separate permissions**, both **off by default**, and granting one does not
grant the other. Settings also offers a **separate, off-by-default Steps read
opt-in** for timed ruck summaries. Turn these on under **Settings → Rest & training behavior → Profile & Health**.

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

### Timing and save status

Banking a timed session preserves its actual start, including across pauses,
resumes and app relaunches. Paused intervals do not count toward Health workout
duration. Banking while paused ends the Health interval at the pause; resetting
the on-screen stopwatch resets only that display, not the workout's history.
Lock Screen controls and the app use the same device-local timing record.

The bank summary reports whether the Health save succeeded, is still running,
needs write permission, or could not be confirmed. Your Cadence session is
saved first and remains safe if Health fails. A session without reliable timing
for its logged day is kept in Cadence and the summary explains why it was not
exported. This includes restored stopwatch records from versions that stored
only an adjusted display origin: their elapsed display survives the upgrade,
but the original workout start cannot be recovered honestly.

The version-2 stopwatch record keeps its three frozen version-1 fields and
adds optional export history. Version-1 records upgrade without inventing that
history; older app versions can still read new records. No SwiftData store or backup format changes. The timing history stays
on this device and is not restored as a Health permission or health record.

This is a one-shot export. There is no durable retry queue, historical sync,
or correction reconciliation yet. If the app exits while saving, or a save
cannot be confirmed, check Health before adding the workout manually. Quick
activity logging continues to use the explicit start and duration you enter;
the new save-status display applies to the timed-session bank summary.

The implementation uses Apple's [pause/resume workout events](https://developer.apple.com/documentation/healthkit/hkworkoutevent)
and checks the builder's [elapsed time](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder/elapsedtime(at:)),
which excludes paused intervals, before finishing the workout.

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
| Measured steps (separate opt-in) | Timed ruck bank summary | Health statistics for the captured ruck window; display only |
| Conditioning distance | History → session detail | Compared against the session's logged distance |
| Workout energy | History → session detail | Shown for the session window |
| Bodyweight and body fat | Body | Offered as a weigh-in to log, on an explicit tap |
| HRV, resting heart rate, sleep | Body | Displayed only |

### Measured steps after a ruck

Enable **Read measured ruck steps** in Settings or the bank summary. This asks
only for step-read access, independently of workout writes and the existing
Health comparison. A completed permission prompt does not prove access was
granted: Health keeps read-denial status private.

The summary uses HealthKit's cumulative statistics across sources, not a raw
sum of phone and watch samples. It queries Health records overlapping the
actual captured start/end window. The displayed window includes interior
pauses and may include samples straddling a boundary; it is **not an exact
active-only step count**. Banking while paused ends the window at that pause.
Cadence never converts miles to steps and never writes step samples.

Only sessions whose completed working exercises are all conditioning exercises
named **Ruck** qualify (case and surrounding whitespace are ignored). Mixed
sessions and exercises with other names are deferred rather than claiming all
session steps belong to a ruck. Missing reliable timing is
explained; a backdated or legacy session does not get a guessed window.

The session saves before any step lookup and Done remains available. No data,
zero, denied access and delayed sensor sync do not become measured zeros. Use
**Refresh steps** while the summary is open to retry a read. Turning the
separate toggle off removes the reading. The quantity is transient: no history,
backup, export, log, analytics or server receives it. Closing the summary ends
this display; persistent history and retry queues are outside this slice.

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

Revoking a permission in the iOS Health app stops further access to that type.
Turning off a Cadence read toggle hides its display. Data already written to Health stays there and is managed in
Health, not in Cadence. The read opt-ins are stored on the device and are
deliberately **not** included in a backup — restoring on a new phone would
otherwise imply a Health grant that phone never gave.
