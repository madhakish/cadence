## What changed and why

<!-- Lead with the behaviour, not the diff. If this fixes a bug, describe what
     the wrong behaviour cost — a fabricated milestone, a stranded schedule, a
     workout that timed itself. That sentence is usually the test name. -->

Closes #

## Release meaning

<!-- semantic-release reads the SQUASH SUBJECT, not the commits. Make sure the
     subject matches the box you tick. -->

- [ ] `fix:` — patch
- [ ] `feat:` — minor
- [ ] `fix!:` / `feat!:` / `BREAKING CHANGE:` — major
- [ ] `docs:` / `test:` / `ci:` / `chore:` / `refactor:` / `style:` — no release

## Parity

- [ ] Shared training logic changed on **both** `CadenceCore` and `web/js/core.js`, with matching test cases
- [ ] Not applicable — this is platform-specific or non-domain code

## Persistence

<!-- Delete this section only if nothing persisted changed. If a SwiftData
     @Model, an IndexedDB record shape, or the backup contract moved, all of it
     applies and none of it can be deferred to a follow-up PR. -->

- [ ] No persisted state changed
- [ ] The previous schema is frozen as an immutable snapshot; no released version identifier was reused
- [ ] Every production migration plan is extended from every shipped checksum
- [ ] `CadenceMigrationTests` opens a **real on-disk store** for each affected old checksum and asserts data, relationships, manual edits, and settings survive
- [ ] `BackupContract.currentSchemaVersion` and `BACKUP_SCHEMA_VERSION` are in lockstep, and `docs/reference/backup-schema.md` is updated
- [ ] The SemVer marker above is `major` if old stores need conversion or an old binary could not open newly written data

## Invariants

- [ ] Behaviour is covered by a rule in `docs/reference/invariants.md`, cited by an `[INV-*]` tag in the tests
- [ ] A new rule was added, on every platform it claims
- [ ] A rule was removed or narrowed — the commit says why the behaviour is no longer required

## Verification

<!-- Paste the counts. "Tests pass" is not evidence. -->

```
cd CadenceCore && swift test
cd web && npm test
```

- [ ] `git diff --check` is clean
- [ ] No real workouts, bodyweight, health data, gym names, membership photos, exports, or credentials in the diff
- [ ] No generated `Cadence.xcodeproj`, build output, or unrelated reformatting
- [ ] User docs updated for changed behaviour or data contracts

## CI

- [ ] Green on the **exact head commit** proposed for merge — including the migration tests, iOS Simulator build, and unsigned device build when app-target code changed

<!-- For release or publishing changes: green PR checks prove nothing. After
     merge, watch the `main` run through a COMPLETED TestFlight job before
     calling it fixed. -->
