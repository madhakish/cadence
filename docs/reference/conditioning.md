# Conditioning

Walking, running, rucking, cycling, sleds, and erg work. Conditioning is
logged differently from lifting: there is no weight × reps, and the fields
that matter are distance, time, speed, incline, and — for a loaded carry —
the weight you are carrying.

## Distance, time, and speed are one thing

`distance = speed × time`. Any two of the three give you the third, so the
logger accepts whichever two you actually know and fills in the rest.

That matters because different kinds of conditioning hand you different
pairs:

| You did | You know | Cadence fills in |
| --- | --- | --- |
| Treadmill at 3.5 mph for 30:00 | speed + time | **1.75 mi** |
| GPS run, 3 mi in 27:00 | distance + time | **6.7 mph** |
| Ruck plan: 4 mi at 3.5 mph | distance + speed | **1:08:34** |

In the logger, **distance and speed are both editable**. Whichever one you
are not typing into is the one that recalculates, and it is marked
*calculated* so you can see which is which.

**Time is never overwritten.** It is the one value a treadmill readout, a
watch, and a training plan all agree on. Changing the time holds whichever
side you last set:

- You entered a **pace** → a longer walk means **more distance**, same pace.
- You entered a **distance** → a longer walk means a **slower pace**, same
  distance.

### What gets saved

Only **distance** and **duration**. Speed is always recalculated from those
two, so there is no third number stored that can drift out of agreement
with them. Your backup and your history carry the same two values they
always have — nothing about this changed the file format.

Distance is rounded to two decimals, which is the granularity treadmills and
watches report.

## Loaded carries

A ruck is a walk with a pack on, and the pack weight is the training
variable — progressing it is the entire point. So **rucks, sled pushes, and
sled pulls keep a load** where plain cardio has none.

- A ruck starts at a **20 lb** pack.
- Load adjusts in **10 lb** steps, not the 2.5 lb steps a barbell wants.
- The carried weight leads the set label: `20 lb · 3 mi · 45:00 · 4 mph`.

The 20 lb default only applies when nothing has been logged yet. Once you
set a load — including changing it to something else — that value is yours
and never gets overwritten.

Sleds carry load but have no default: what a sled weighs depends on the
implement and the surface, and guessing would be worse than asking.

Unloaded conditioning — walking, running, cycling, ergs — records no weight
at all.

## Comparing against Apple Health

*(iOS only. The web app has no access to Health.)*

Cadence can show what Health recorded for a session beside what you logged.
This is **off by default** and is a **separate permission** from writing
workouts to Health — granting one does not grant the other.

Turn it on in **Settings → HealthKit → Compare conditioning with Health**.

Once enabled, opening a completed session in History shows a Health row:

```
Health recorded 2.41 mi · you logged 2.00 mi     [ Use Health's 2.41 mi ]
```

### It reports, it never merges

Nothing is ever rewritten on your behalf. The comparison names **both**
numbers and leaves the decision to you, because both instruments are honest
and neither is always right:

- A watch left on the charger would otherwise silently erase a ruck.
- A GPS track through a parking garage or under tree cover would silently
  inflate one.
- A treadmill belt measures a walk more accurately than a wrist does.
- A wrist measures a trail run more accurately than your estimate does.

Your log stays the record, and it is the only thing a backup can restore.

Tapping **Use Health's …** rewrites only that session's conditioning
distance. If the session has several conditioning sets, the new total is
spread across them in proportion to what they already held, so a two-leg
walk keeps its shape instead of collapsing into the first set.

### When nothing appears

The Health row stays hidden — deliberately — when:

- The comparison setting is off.
- The session was never completed. A session needs both a start and an end
  to define a window to look up.
- Health has nothing for that window. An unworn watch is not a finding, and
  showing "you logged too much" would be wrong.
- Both sources agree within tolerance, and there is nothing to decide.

### How a Health workout is matched to a session

By **majority overlap with the session's time window**: a Health workout
counts if at least half of it falls inside the session.

Individual sets carry no timestamp — only the session does — so the
comparison is against the session's **total** conditioning distance.
Claiming to match a specific set would be precision the data does not have.

Majority overlap is what makes both edge cases behave:

- The walk you started in the car park before opening the app **counts** —
  most of it happened during the session.
- The bike commute that ended as you walked in **does not** — most of it
  happened before.

### Tolerance

Two honest instruments never agree exactly, so small differences are
reported as agreement rather than as a discrepancy:

- **0.05 mi**, or
- **2% of the larger distance**, whichever is bigger.

The proportional part matters on long efforts: 2% of a ten-mile ruck is a
fifth of a mile, and that is still two instruments agreeing. A flat
threshold would flag every long session and train you to ignore the row.

### What is read, and what is not

Only **walking/running distance** and **cycling distance**, and only for a
session you have already logged. Cadence does not read heart rate, sleep,
weight, or anything else from Health, and it never reads continuously or in
the background.

The permission is device-local and is deliberately **not** stored in your
backup — restoring onto a new phone will not grant Health access that phone
never gave.

## Related

- [Behavioural invariants](invariants.md) — `INV-CARDIO-SOLVES-THE-THIRD`,
  `INV-RUCK-CARRIES-ITS-LOAD`, and `INV-HEALTH-IS-A-SECOND-OPINION`
- [Run a training day](../how-to/run-a-training-day.md)
- [Back up and restore your data](../how-to/back-up-and-restore.md)
