# Backup schema reference

Cadence's JSON export is the durable, cross-platform backup contract shared
by the iOS app and web PWA. It is not an IndexedDB or SwiftData dump.

## Versioning

`schemaVersion` is an integer at the bundle root. Current exporters write
version **4**. A missing version means the legacy version-0 shape.

Importers accept their current version and older versions they know how to
migrate. They reject a newer or invalid version before opening a write
transaction. Updating Cadence is the recovery path for a newer backup.

The source-of-truth constants are:

- Native: `BackupContract.currentSchemaVersion` in `CadenceCore`
- Web: `BACKUP_SCHEMA_VERSION` in `web/js/db.js`

These values must change together.

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
a program edit. Renaming a program therefore cannot detach an open session.

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

## Compatibility rules

- Version-0 sessions have no `isCompleted`; they are treated as completed
  because the legacy web exporter excluded open sessions.
- Pre-version-2 sets in completed sessions migrate as completed. Sets in open
  sessions migrate conservatively as planned.
- Version-2 sessions, programs, and exercises gain version-3 defaults during
  import. Their logged weights/reps remain performed truth; missing per-set
  prescription snapshots stay null.
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
