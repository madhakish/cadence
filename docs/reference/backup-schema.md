# Backup schema reference

Cadence's JSON export is the durable, cross-platform backup contract shared
by the iOS app and web PWA. It is not an IndexedDB or SwiftData dump.

## Versioning

`schemaVersion` is an integer at the bundle root. Current exporters write
version **1**. A missing version means the legacy version-0 shape.

Importers accept their current version and older versions they know how to
migrate. They reject a newer or invalid version before opening a write
transaction. Updating Cadence is the recovery path for a newer backup.

The source-of-truth constants are:

- Native: `BackupContract.currentSchemaVersion` in `CadenceCore`
- Web: `BACKUP_SCHEMA_VERSION` in `web/js/db.js`

These values must change together.

## Version 1 session contract

Every session carries:

- `date`, `notes`, and optional `gym`
- `isCompleted`, preserving both open and banked sessions
- optional `programTag`
- ordered `exercises`, each with its planned prescription and logged sets

A program tag uses the program's unique name across the backup boundary. Local
SwiftData or IndexedDB identifiers are deliberately excluded. The tag also
carries cycle, week, day index, and `planNames`, the immutable snapshot used to
decide whether an open session may resume after a program edit.

On web import, `programName` is resolved back to the destination database's
local program ID. Legacy web tags containing `programId` remain accepted.

## Compatibility rules

- Version-0 sessions have no `isCompleted`; they are treated as completed
  because the legacy web exporter excluded open sessions.
- Missing top-level sections leave the corresponding local store untouched.
- Import runs a full preflight before storage is touched. Missing identifiers,
  invalid dates or numbers, unknown enum values, duplicate keys, and impossible
  progression positions reject the complete bundle with a field path.
- Import is transactional. A failed record aborts every mutation in the bundle.
- Program names are unique and act as the cross-platform linkage key until a
  future schema introduces stable portable IDs.

Both clients also keep three rotating local checkpoints when the app
backgrounds and before a valid import. These are an undo buffer, not part of the
portable schema: browser eviction or deleting the native app removes the
checkpoints along with the primary database.

The broad synthetic fixture at
`web/tests/fixtures/synthetic-backup.json` is generated through the real web
exporter and restored by both clients. Regenerate it with
`web/tools/generate-synthetic-backup.mjs` after an intentional schema change.
