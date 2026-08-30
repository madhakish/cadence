# Backup schema reference

Cadence's JSON export is the durable, cross-platform backup contract shared
by the iOS app and web PWA. It is not an IndexedDB or SwiftData dump.

## Versioning

`schemaVersion` is an integer at the bundle root. Current exporters write
version **11**. A missing version means the legacy version-0 shape.

Importers accept their current version and older versions they know how to
migrate. They reject a newer or invalid version before opening a write
transaction. Updating Cadence is the recovery path for a newer backup.

The source-of-truth constants are:

- Native: `BackupContract.currentSchemaVersion` in `CadenceCore`
- Web: `BACKUP_SCHEMA_VERSION` in `web/app/js/db.js`

These values must change together.

## Version 11 stable portable identity

Version 11 (epic #155 Stage 2) adds identity fields; no collection changes
shape and every field is additive:

- **`id`** on each exercise definition: a portable UUID. Exercises that
  existed before v11 carry a **deterministic legacy id** derived from the
  exact name (`StableID.exerciseLegacyID` / `C.exerciseLegacyID`, identical
  byte-for-byte on both clients), so the same store contents produce the
  same ids everywhere; user-created exercises mint a random UUID at
  creation. The name remains the store's unique key — the id is the
  portable reference joins and backups carry.
- **`exerciseId`** on session exercise entries, program lift/accessory
  slots, tracks, and milestones: the portable id of the referenced
  exercise.
- **`templateId`** on programs and **`programTemplateId`** on sessions: the
  methodology (ProgramTemplateData slug) the program was instantiated
  from. Recorded at instantiation only — never inferred for legacy or
  hand-built programs, where it stays null.

Importers accept v0–v10 and synthesize every id with the same deterministic
derivation. A malformed v11 id is repaired the same way rather than
rejected — the established slot-id policy. v11 bundles round-trip ids
verbatim.

## Version 10 training-context intervals and manual bar picks

Version 10 adds one collection and one per-session-exercise marker:

- **`intervals`** is a list of typed calendar spans the lifter declared over
  their timeline: `{ id, kind, startDate, endDate, enteredAsDays, note,
  programId }`. `kind` is `"deload"`, `"rest"`, `"away"`, or
  `"activeRecovery"` — deliberately distinct, never collapsed into one
  "break". Dates are inclusive day-granular ISO strings (`yyyy-MM-dd`); `id`
  is a portable UUID so restore preserves identity; `programId` is optional
  linkage to the program the span interrupts. A day inside a rest, away, or
  active-recovery span is never a missed day; work logged inside an
  active-recovery span is banked history that never feeds program
  progression.
- **`barIdManual`** on a session exercise is emitted **only when `true`**: the
  entry's bar was picked by hand and never follows a mid-session gym switch,
  even when it equals the outgoing gym's default. Absent means stamped.

Both are additive. A version-9-or-older bundle restores with no intervals
(existing declared breaks in the store are left alone — only collections
present in a bundle are replaced) and every bar treated as stamped, exactly
the pre-v10 behavior. Older importers reject a v10 bundle on the version
gate, which is correct: silently dropping a declared break would turn it back
into an apparent lapse after a restore.

## Version 9 programming semantics

Version 9 adds two required strings to every newly written program tree:

- **`program.equipmentPolicy`** is `"any"` or `"freeWeightsOnly"`.
  `freeWeightsOnly` limits automatic selection to barbell, dumbbell,
  kettlebell, bodyweight, and timed (bodyweight-hold) exercises. It does not rewrite manually authored
  slots.
- **`program.days[].trainingIntent`** is `"general"`, `"heavy"`,
  `"volume"`, `"technique"`, or `"explosive"`. Intent is explicit because
  neither a display name nor the first slot can classify a mixed day reliably.

Both fields are additive. A version-8-or-older bundle restores missing values
as the literal legacy behavior: `"any"` for the program and `"general"` for
each day. Importers require and validate both values on version-9 bundles,
rather than silently coercing an unknown policy or intent.

## Version 8 station plates

Version 8 adds one optional per-exercise field, `stationDenomination`, for a
lift whose STATION stocks a single plate denomination — the kg-only deadlift
platform beside lb-stocked squat racks.

- **`stationDenomination`** is `"lb"`, `"kg"`, or `null` on a library
  exercise object, beside `defaultRestSeconds`. Null means the lift solves
  against the gym's full plate inventory, exactly what every lift did before
  stations existed. A set preference filters prescriptions, warmups, and the
  plate hint to that denomination, falling back to that denomination's full
  standard set when the gym stocks none of it.
- The key may be **absent or null** — the web exporter writes an explicit
  `null` for a cleared preference while the native encoder omits nil keys —
  and both mean the same thing. Importers on both clients restore an absent
  or null key as the cleared preference at **every** bundle version, so a
  restore never leaves a station configuration behind that the backup does
  not contain.

The version has to move even though the field is optional and additive: a
version-7 importer parses the bundle happily and silently drops the
preference, putting the lifter's kg deadlift station back on lb math after a
restore. Moving the version makes it fail the gate instead.

No field shapes changed and no field was removed, so a version-7 bundle
restores under version 8 untouched, with every lift on the gym inventory —
including a lift whose local preference was set after the backup was written:
the restore clears it, because the backup describes a world without it.

## Version 7 climbed flights

Version 7 adds one optional per-set field, `flights`, for conditioning a
machine measures in floors rather than ground covered.

- **`flights`** is a non-negative number on a set object, beside
  `distanceMiles` and `durationSeconds`. It is the count climbed; the pace in
  flights per minute is always re-derived from it and the duration, exactly as
  speed is re-derived from distance and duration. There is no stored pace.
- The key is **emitted only when set**, like `inclinePercent` and
  `revertToExerciseName`, so bundles for training that has no flight count
  re-export byte-for-byte identically to their version-6 form.

The version still has to move even though the field is optional and additive:
a version-6 importer parses the bundle happily and silently drops the count,
which is data loss disguised as a clean restore. Moving the version makes it
fail the gate instead, with "this backup is newer than this app".

No field shapes changed and no field was removed, so a version-6 bundle
restores under version 7 untouched, with `flights` absent everywhere.

## Version 6 retires protein logging

Version 6 is the first **lossy** boundary in this contract. Every version
before it added fields; this one removes them.

- **`protein`** — the array of logged servings is gone. A v≤5 bundle still
  imports, but its protein entries are dropped on the way in, because neither
  client has anywhere to put them any more.
- **`settings.proteinTargetGrams`** — gone with the tracker it measured
  against. Ignored where old bundles still carry it.
- **`settings.birthYear`** — new. An integer year, or `0` for "not set". Any
  other value must produce a plausible age (1901-present, at most 120 years),
  and both importers reject a bundle that fails that check rather than
  silently moving the lifter across the older-adult protein threshold.

Only the year is stored, not a date of birth. Age in years is all the protein
guidance needs, and a health app should hold the least personal detail that
answers its question.

### Why the data goes rather than sits

Serving-level logging only works with a real meal-entry surface, which Cadence
will never have. Keeping the store as a place stale rows accumulate would be
worse than removing it, and keeping it in the backup contract would imply a
restore path for a feature that no longer exists.

**Restoring a v≤5 backup will not bring protein history back.** That is the
intended behaviour and the reason this ships as a SemVer major.

## Version 5 effort and AMRAP

Version 5 adds three values to enums the importer validates against
whitelists, which is precisely why the version has to move: an older importer
would otherwise reject a newer backup with a confusing "unknown enum value"
rather than "this backup is newer than this app". Both clients run the version
gate *before* validation so the failure is the honest one.

- **`amrap`** joins `prescriptionBlock`. A prescribed set taken past its rep
  target — 5/3/1's "+" set, which is that method's actual progression engine.
  It is graded work, not a garnish: an AMRAP set counts toward completion and
  is eligible as the cycle's strength sample.
- **`repPR`** joins the milestone `kind` vocabulary. More weight at a rep
  count than ever before at that count, capped at ten reps.
- **`rir1` / `rir2` / `rir3plus`** join set `flags`. Reps left in reserve,
  in three coarse buckets rather than a number, because RIR accuracy averages
  about a rep of error even in experienced lifters.

Reps in reserve is a **separate exclusive group** from set quality. Each group
allows at most one value per set, and the two never exclude each other — a set
can be both `clean` and `rir1`, because how the bar moved and how close to
failure it was are different questions. Importers enforce both rules
independently from version 5 onward.

No field shapes changed and no field was removed, so a version-4 bundle
restores under version 5 untouched.

## Version 4 methodology styles

Version 4 widens the program-lift (and session-exercise) `prescription`
vocabulary with the training-methodology styles: `linearFives`,
`texasVolume`, `texasLight`, `texasIntensity`, `fiveThreeOne`, `maxEffort`,
and `dynamicEffort`. It also adds the `ramp` set kind to `prescriptionBlock` —
prescribed sub-maximal sets before the day's top work (the 5/3/1 65/75%
sets), distinct from post-work `backoff` sets. No field shapes changed.
The version exists so an older importer rejects a backup containing the
new styles cleanly by version instead of failing enum validation
mid-file; version ≤3 backups import unchanged. For `fiveThreeOne` slots
the persisted `baseWeightLb` is the training max, not a working weight.

## Version 3 coaching and prescription contract

Version 3 preserves performed work separately from the prescription that
produced it. A session may include `completedAt`; each exercise may include the
strategy `targetWeightLb`, gym-resolved `plannedWeightLb`, duration target,
pre-computed fallback, and prescription style. Every set carries immutable
target/planned weight, reps, duration, and a `prescriptionBlock` (`warmup`,
`primer`, `topSingle`, `work`, `backoff`, or `conditioning`) alongside the
final performed values. Historical version-2 sets migrate with null plan
snapshots instead of having a current program retroactively assigned to them.

Programs include deterministic-coach settings and per-slot progression data:
offset waves, double-progression windows, optional peak singles and primer
singles, fixed drop increments, capacity limits, and conditioning effort/RPE.
Exercise definitions include primary/secondary movement patterns, aliases,
programming tags, and user-owned availability/re-entry criteria. The optional
`coachingDecisions` section records accepted, deferred, dismissed, or
overridden proposals so a deterministic recommendation remains auditable.

Conditioning duration remains separate from lifting set volume. Movement gates
and criteria are user data; no personal health or injury defaults are seeded by
either client.

## Version 2 session contract

Every session carries:

- optional stable `id`, `date`, `notes`, optional historical `gym`, and optional stable `gymId`
- `isCompleted`, preserving both open and banked sessions
- optional `programTag`
- ordered `exercises`, each with its planned prescription, optional stable
  `programSlotId`, optional session-local `barId`, and logged sets

A program tag carries a stable portable `programId` plus the historical
`programName` label. It also carries cycle, week, day index, and `planNames`,
the immutable snapshot used to decide whether an open session may resume after
a program edit. The comparison is a name **multiset** (composition), not a
sequence: display order is derived role-first, so a pure reorder — or a
snapshot written before role-first ordering existed — never orphans an open
session. Renaming a program therefore cannot detach an open session either.

Every set carries a `status` of `planned`, `completed`, or `skipped`. Only
completed sets contribute to volume, PRs, charts, HealthKit metadata, or
progression. Quality remains optional and mutually exclusive (`clean`,
`grindy`, or `wobble`); `stopped early` is an independent observation.

Newer version-2 exports also snapshot each set's `loadBasis` and
`implementCount`. The basis distinguishes total bar weight, per-implement
weight, total external resistance, assistance, and unloaded bodyweight. This
keeps historical tonnage and PR comparisons stable if an exercise definition
is edited later. Exercise definitions carry the same defaults. Gym records may
carry combined `collarWeightLb` and a `loadingPolicy` (`closest`, `under`,
`over`, or `exact`); both clients fall back to zero-weight collars and closest
loading when those optional keys are absent.

Programs, program lift/accessory slots, and gyms each export their stable ID.
The session exercise's `programSlotId` points at the exact lift or accessory
slot it came from, so duplicate names or reordered exercises cannot advance the
wrong goal. Older version-2 backups may omit these optional slot IDs and fall
back to name-and-role matching. The web keeps its IndexedDB primary key private
and resolves the portable program ID after import.

## Slot identity

Program slot IDs are validated for uniqueness within a program. A bundle that
reuses one across two programs is **repaired on restore**, not rejected: the
first occurrence keeps its id, later ones are re-issued, and the importer
reports how many were repaired.

A duplicate would make banked sessions' `programSlotId` permanently ambiguous,
and nothing downstream can clean it up — the launch-time repair scopes its
duplicate detection to a single program. Repairing rather than refusing is the
deliberate choice for this format: a backup is the recovery path of last resort,
and refusing one over a fixable problem would strand data the app itself may
have written. The program-file contract, being additive and opt-in, refuses
instead — see [program file](program-file.md).

## Compatibility rules

- Version-0 sessions have no `isCompleted`; they are treated as completed
  because the legacy web exporter excluded open sessions.
- Pre-version-2 sets in completed sessions migrate as completed. Sets in open
  sessions migrate conservatively as planned.
- Version-2 sessions, programs, and exercises gain version-3 defaults during
  import. Their logged weights/reps remain performed truth; missing per-set
  prescription snapshots stay null.
- Version-8-and-older programs gain `equipmentPolicy: "any"` and days gain
  `trainingIntent: "general"`; no name parsing or equipment filtering is
  applied retroactively.
- Version-10-and-older bundles carry no exercise/template identity; every
  id is derived deterministically from the recorded names during import, so
  both clients agree on identity for identical content.
- Missing top-level sections leave the corresponding local store untouched.
- Import runs a full preflight before storage is touched. Missing identifiers,
  invalid dates or numbers, unknown enum values, duplicate keys, and impossible
  progression positions reject the complete bundle with a field path.
- Import is transactional. A failed record aborts every mutation in the bundle.
- Program and gym names remain historical labels; stable IDs are the linkage
  keys from version 2 onward.

Both clients also keep three rotating local checkpoints when the app
backgrounds and before a valid import. These are an undo buffer, not part of the
portable schema: browser eviction or deleting the native app removes the
checkpoints along with the primary database.

The broad synthetic fixture at
`web/tests/fixtures/synthetic-backup.json` is generated through the real web
exporter and restored by both clients. Regenerate it with
`web/tools/generate-synthetic-backup.mjs` after an intentional schema change.
The pre-identity bundle is kept frozen at
`web/tests/fixtures/synthetic-backup-v10.json` as the permanent upgrade-path
input: importing it must always derive the deterministic legacy ids.
