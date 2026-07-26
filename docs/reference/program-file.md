# Program file reference

A program file is a single training program as a standalone JSON document —
its days, lift slots, accessory slots, and the progression configuration that
drives them. It exists so a program can be authored or edited outside Cadence
and brought back in without touching session history.

It is **not** a backup. The [backup schema](backup-schema.md) is the
cross-platform recovery format and carries everything; a program file carries
one program and nothing else.

## What it is not

A program file never contains:

`sessions` · `bodyweight` · `protein` · `milestones` · `checkIns` ·
`coachingDecisions` · `gyms` · `settings` · `tracks` · the exercise library ·
gate status or re-entry criteria.

Importing one never reads or writes those domains either. It adds a program.

## Versioning

The root carries two fields that identify it:

```json
{ "kind": "cadence.program", "programSchemaVersion": 1, "program": { … } }
```

`kind` keeps the two importers from accepting each other's files. A backup
handed to the program importer is refused by discriminator, and vice versa,
before anything is read.

`programSchemaVersion` is an integer and versions **independently of the
backup's `schemaVersion`**. A change to the program format does not move the
backup version, and a change to the backup format does not move this one.
Current writers emit version **1**.

Importers accept their current version and older versions they know. They
reject a newer or invalid version before opening a write. Updating Cadence is
the recovery path for a newer file.

The source-of-truth constants are:

- Native: `ProgramFileContract.currentSchemaVersion` in `CadenceCore`
- Web: `PROGRAM_SCHEMA_VERSION` in `web/app/js/program-file.js`

These values must change together.

## Version 1

Version 1 is the plan shape, plus two optional groups.

**The plan** — always present. Program name, focus, rounding, coaching
preferences, and the ordered days. Each day carries its lifts and accessories
with their full progression configuration: role, prescription style, warm-up
policy, load and peak offsets, deload multiplier, rep windows, set counts,
base weight, and estimated max.

**Runtime state** — optional, off by default. `stallCount`, `lastIncrementLb`,
`lastPeakSingleLb`, the stashed week-3 `pending` peak grade, the cycle-scoped
`revertToExerciseName` swap marker, and the program's wave position
(`cycleNumber`, `currentWeek`, `nextDayIndex`).

**Identity** — optional, off by default. The program's `id` and each slot's
`id`.

## Plan or snapshot

Export is **plan-only by default**. A program shared with another lifter has
no business carrying the author's stall counters or a mid-cycle peak grade;
those describe one person's position in one cycle and are misleading anywhere
else.

Export **with state** when the intent is to hand-edit a file and bring it back
to the same device. That is the mode that round-trips losslessly.

Wave position is all-or-nothing. A file carrying `cycleNumber` but not
`currentWeek` is rejected rather than guessed at, because a half-carried
position is the difference between a deload and a peak week. `nextDayIndex`
must name one of the program's day orders — a pointer to a day that isn't
there would fall back to the first day and silently lose the position.

A lift's progression counters (`stallCount`, `lastIncrementLb`,
`lastPeakSingleLb`) are likewise a group: all three or none. `pending` and
`revertToExerciseName` are independent, since both are genuinely absent most of
the time.

A plan-only file imports at cycle 1, week 1, with cleared counters.

## Identity and update-in-place

By default an import **creates** a program with fresh UUIDs. Slot ids are what
banked sessions point at through `programSlotId`, so adopting the ids in a
file is an explicit choice, not a default.

Import **preserving identity** when the file came from this device and should
update the program it came from. If a program with that id is present it is
updated in place, keeping its slot ids and therefore its coaching history and
"last time" recall. Without the flag, the same file makes an independent copy.

Two slots sharing an id is rejected. A duplicate would make progression
advance the wrong lift.

## Determinism

On a given client, the same program exports to byte-identical output every
time:

- keys are sorted (native `JSONEncoder .sortedKeys`, web recursive key sort);
- optional fields are omitted rather than written as null; and
- no timestamp appears anywhere in the payload.

`export → import → export` produces an identical file.

Across clients the two agree on every key, value, and ordering, but not on
interior whitespace: Foundation's pretty-printer writes `"key" : value` where
`JSON.stringify` writes `"key": value`. Whitespace is not part of the contract.
A file written by either client is read identically by the other.

## Exercise resolution

Slots reference exercises by name. On import each name is resolved against the
library by canonical name first, then by alias. A resolved alias is rewritten
to the canonical name.

This includes `revertToExerciseName`, the cycle-scoped swap marker. Rollover
writes that name straight onto the slot, so an unresolvable marker would leave
the slot bound to no exercise definition weeks after the import appeared to
succeed.

**An unresolved name fails the import**, naming the exercise, and nothing is
written. Cadence does not create a stub for it: `loadBasis` and
`movementPattern` decide how a slot progresses and how its volume counts, so a
guessed definition produces confidently wrong prescriptions. A failed import
is recoverable; a wrong stub is not obvious until the numbers are already off.

Add the exercise to your library, or rename the slot to a name or alias you
already have, and import again.

## Gated exercises

Gate status and re-entry criteria are personal rehab state attached to your
library, not properties of a program, so they are never exported and never
applied on import.

A program that references an exercise gated shut in the target library still
imports. The report names it, and the slot will not be programmed until the
exercise is reopened.

## What an import can change

One program record. Nothing else.

- It never overwrites an existing program. A colliding name becomes
  "Name 2" — `Program.name` is unique on the native side, so a fixed name
  would silently upsert into an in-progress program.
- It never takes the active flag from a program you are mid-cycle on. An
  imported program is inactive unless it is the only one.
- It reports what it did — created or updated, with day and slot counts, and
  any warnings — rather than succeeding silently.
- A file that fails validation, or names an exercise that cannot be resolved,
  changes nothing at all.

Day `order` values are preserved verbatim, gaps included. A day's order is the
identity every banked session's `programTag.dayIndex` refers to; renumbering
would misattribute already-logged work.

## Where to find it

- Export: the program editor, next to "Duplicate program".
- Import: the "Add program" menu, as "From a file…".

## Testing

`web/tests/fixtures/program-file.json` is the shared fixture. The node
program-file suite asserts the JavaScript exporter still produces it
byte-for-byte, and Swift's `ProgramFileContractTests` decodes the same file and
re-encodes it byte-for-byte. Either mirror drifting fails its own CI job.

Regenerate it with `web/tools/generate-program-file-fixture.mjs` after an
intentional format change.
