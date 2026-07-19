# Claude Code instructions for Cadence

Read `AGENTS.md` before making changes. It is the canonical repository guide
and applies to Claude as well as other coding agents. This file provides the
Claude-specific startup checklist and repeats the safety contracts that must
never depend on context or memory.

## Repository summary

Cadence is a single-user, local-first strength-training logbook delivered as:

- a native iOS 17+ SwiftUI/SwiftData app with a widget/Live Activity extension;
- a vanilla-JavaScript PWA backed by IndexedDB; and
- a Foundation-only Swift package, `CadenceCore`, containing deterministic
  training logic mirrored by `web/js/core.js`.

There is no server-side source of truth. The user's on-device store and portable
backup are the source of truth, so persistence compatibility has higher priority
than implementation convenience.

## Start every task this way

1. Read `AGENTS.md` and any relevant user documentation in `docs/`.
2. Inspect `git status` and preserve unrelated user work.
3. Locate the production implementation, its mirrored native/web counterpart,
   existing tests, persistence models, and import/export boundaries.
4. Classify the change before editing:
   - pure domain behavior;
   - native UI/platform integration;
   - web UI/runtime behavior;
   - SwiftData or IndexedDB persistence;
   - backup schema;
   - privacy/permissions; or
   - release/CI infrastructure.
5. If persisted state changes, stop normal implementation flow and follow the
   migration protocol below first.

## Absolute rules

- Never delete/reset a store, tell the user to reinstall, or silently start a
  replacement store as a persistence fix.
- Never mutate an already released SwiftData `VersionedSchema` or reuse its
  version identifier for a new checksum.
- Never ship a schema change without an upgrade path and real on-disk migration
  test.
- Treat a breaking persisted-schema change as a SemVer major change. Use
  `fix!:`/`feat!:` or a `BREAKING CHANGE:` footer in the merge/squash commit.
- Never defer a required migration to another PR.
- Never commit real workouts, body/health data, gym tags, membership details,
  exports, credentials, or signing material.
- Never edit or commit the generated `Cadence.xcodeproj`; edit `project.yml`.
- Never put Apple-framework code into `CadenceCore`.
- Never change shared domain behavior on only one client.

## Architecture and ownership

| Concern | Source of truth |
| --- | --- |
| Training math and deterministic state transitions | `CadenceCore/Sources/CadenceCore/` |
| Swift domain regression tests | `CadenceCore/Tests/CadenceCoreTests/` |
| JavaScript domain mirror | `web/js/core.js` and `web/tests/core.test.mjs` |
| Native persistence | `Cadence/Models/`, `Cadence/Services/`, `Cadence/Seed/Seeder.swift` |
| SwiftData compatibility | `PersistenceSchema*.swift`, `AppBootstrap`, `CadenceMigrationTests/` |
| Web persistence | `web/js/db.js` and fake-indexeddb smoke coverage |
| Portable backup contract | `BackupContract.swift`, `web/js/db.js`, import/export services, backup docs/fixtures |
| Native UI | `Cadence/Views/` |
| Live Activity and controls | `Cadence/LiveActivity/` and `CadenceWidgets/` |
| Generic reference data | `Cadence/Seed/`, template/anatomy mirrored fixtures |
| Build configuration | `project.yml` |
| Release and distribution | `.github/workflows/`, `.releaserc.json`, `fastlane/` |

Keep views and persistence adapters thin. New testable logic belongs in
`CadenceCore`; implement the equivalent function in `web/js/core.js` and give
both suites matching cases.

## Persistence and migration protocol

### SwiftData

Treat every released schema/checksum as immutable API history. The repository
currently preserves both the pre-PR-72 V1 schema and the alternate schema that
PR #72 wrote while still advertising V1. Both histories must keep upgrading.

Before changing a live `@Model` property, relationship, constraint, default,
attribute, or registered model:

1. Identify the latest schema shipped on `main`.
2. Freeze its exact declarations/checksum in an immutable
   `PersistenceSchemaV<N>.swift` snapshot if needed.
3. Create a new current schema with a monotonically increasing
   `Schema.Version`; never alter the prior snapshot.
4. Extend every production migration plan from every supported shipped
   checksum. Keep separate linear plans and `AppBootstrap` fallback paths where
   SwiftData cannot represent branched history in one plan.
5. Choose lightweight migration only when it preserves data and relationships.
   Use a custom migration for renames, conversions, constraint changes, or
   identity repair that cannot be represented safely.
6. Make post-open backfills idempotent. Preserve valid values; repair missing,
   malformed, or duplicate IDs; propagate save errors.
7. Extend `CadenceMigrationTests` to create representative real SQLite stores
   for all affected old checksums, open them with the production current plan,
   and assert data, relationships, manual training edits, settings, and
   invariants survive.
8. Keep the recovery path non-destructive and document upgrade/downgrade
   implications.

Fresh-store or in-memory tests are insufficient. A successful compile is
insufficient. CI's hostless macOS migration scheme is the required proof.

### IndexedDB

Review `web/js/db.js` whenever persisted record shape or interpretation changes.
Bump `DB_VERSION` when required, transform older data inside
`onupgradeneeded`, and test opening a prior database version with current code.
Do not mistake fresh seeding for migration coverage.

### Backups

The backup is cross-platform recovery, not an internal implementation detail.
Keep native `BackupContract.currentSchemaVersion` and web
`BACKUP_SCHEMA_VERSION` synchronized. Accept and migrate documented older
versions, reject unsupported newer versions before writes, update native and
web import/export together, regenerate synthetic fixtures deliberately, and
update `docs/reference/backup-schema.md`.

### Semantic versioning

`semantic-release` reads commits on `main`:

- `fix:` means patch.
- `feat:` means minor.
- `fix!:`/`feat!:` or `BREAKING CHANGE:` means major.
- docs/test/ci/chore/refactor/style commits do not release.

A persisted format that requires conversion for old stores, prevents an old
binary from opening newly written data, removes/renames data, changes types or
relationships, or changes backup compatibility is breaking. Mark the release
as major even if the new app performs the forward migration automatically. The
same PR must include the upgrade path, tests, recovery notes, and contract docs.

Never create release tags or hand-edit versions; semantic-release owns them.

## Domain invariants to protect

- Store all weights in canonical pounds. Convert only at entry/display.
- History, goals, progression, volume, and PRs use performed values, not stale
  programmed values. Preserve manual weight/repetition adjustments.
- Editing reps cannot reset weight; editing weight cannot reset other set state.
- Sets are independently addable/removable and deterministically ordered.
- Update only one side of a SwiftData inverse relationship; never both assign
  the child inverse and append that child to the parent collection. Collection
  aliases produce mirrored editor rows and destructive deletes.
- Planned/completed/skipped and warmup/working states stay distinct.
- Load basis and implement count are explicit; do not guess from an exercise
  name after semantics have been persisted.
- Program progression is pure, deterministic, and based on completed summaries.
- Seed data is generic and canonical across native, web, templates, search, and
  swap rules.
- The gym membership tag is a launch-level, trivially accessible workflow.

## Product expectations

Cadence is used mid-workout. Prefer predictable defaults, minimal taps, large
targets, one-handed reachability, and edits that never disappear. Ask a small
question only when a wrong inference would corrupt the log. Make planned versus
actual work obvious without exposing internal state-machine complexity.

Check accessibility, Dynamic Type, VoiceOver labels, safe areas, themes,
reduced motion, and destructive-action confirmation for UI changes. Native and
web should share information architecture while using platform-appropriate UI.

## Validation commands

```bash
cd CadenceCore && swift test
```

```bash
cd web && npm ci && npm test
```

On a Mac:

```bash
xcodegen generate
xcodebuild test -project Cadence.xcodeproj -scheme CadenceMigrationTests -destination 'platform=macOS'
xcodebuild build -project Cadence.xcodeproj -scheme Cadence -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

This workspace usually lacks Xcode. When app-target code changes, GitHub Actions
is the compiler: wait for the exact PR head to pass migration tests, the iOS
Simulator build, and the unsigned-device build before calling the work done.

The macOS toolchain in Actions is a first-class, long-established part of this
repository — a complete CI/CD pipeline through semantic-release, fastlane, and
TestFlight/App Store Connect. Treat "CI validates the Swift side" as the normal
workflow, not a caveat or a limitation to apologize for: state that the head
commit's Darwin jobs are pending and watch them, nothing more.

## Finish every task this way

1. Review the diff for accidental personal data, secrets, generated files, and
   unrelated formatting.
2. Run the relevant core/web tests and `git diff --check`.
3. Confirm mirrored contracts and fixtures are synchronized.
4. Confirm schema/backup changes have versioning, upgrade tests, documentation,
   and the correct SemVer major marker.
5. Update user docs for changed behavior or data contracts.
6. Use an intentional Conventional Commit and ensure the PR's final
   merge/squash title carries the same release meaning.
7. Verify all required CI jobs on the exact head commit.

The complete definition of done, privacy rules, CI topology, and repository map
remain in `AGENTS.md`; when the files differ, follow the stricter rule.
