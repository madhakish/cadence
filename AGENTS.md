# Cadence repository guide

This file applies to the entire repository. It is the canonical working guide
for coding agents and contributors. A more deeply nested `AGENTS.md` may add or
override instructions for its subtree.

## Project in one minute

Cadence is a private, local-first strength-training logbook with two clients:

- A native iOS 17+ app built with SwiftUI, SwiftData, ActivityKit, WidgetKit,
  App Intents, notifications, and optional write-only HealthKit integration.
- A static web PWA built with vanilla JavaScript and IndexedDB. It has no
  production build step and is deployed through GitHub Pages.

There is no backend or account system. User training data is irreplaceable and
must survive every update. The owner is the primary user, so optimize for a
fast, trustworthy training workflow rather than speculative abstraction.

`CadenceCore` is the pure, deterministic domain layer. Equivalent behavior is
mirrored in `web/js/core.js`; the Swift and JavaScript suites enforce parity.
Platform APIs and persistence remain at the edges.

## Non-negotiable rules

1. Never delete, reset, or silently replace a user's persistent store to make
   a launch or migration problem disappear.
2. Never edit a persistence schema that has shipped. Add a new version and an
   explicit, tested upgrade path.
3. A breaking persisted-schema change is a semantic-versioning breaking
   change, even when the forward migration is automatic. Mark it with `!` or a
   `BREAKING CHANGE:` footer so semantic-release produces a major version.
4. A schema-changing PR is incomplete without an on-disk old-to-new migration
   test using the production schema and migration plan.
5. Put deterministic training math in `CadenceCore`, add Swift tests, mirror it
   in `web/js/core.js`, and add equivalent JavaScript assertions.
6. Store weights canonically in pounds as `Double`. Convert kilograms only at
   input and display boundaries.
7. Never commit personal workouts, body metrics, health signals, gym barcodes,
   membership identifiers, backups, credentials, signing material, or tokens.
8. Generate `Cadence.xcodeproj` from `project.yml`; never edit or commit the
   generated project.

## Repository map

| Path | Responsibility |
| --- | --- |
| `CadenceCore/Sources/CadenceCore/` | Foundation-only domain logic: programs, progression, warmups, rest, units, plates, load semantics, PRs, set lifecycle, backup contract |
| `CadenceCore/Tests/CadenceCoreTests/` | Linux- and Darwin-compatible domain tests and compile-regression fixtures |
| `Cadence/Models/` | Live SwiftData models plus immutable historical schema snapshots |
| `Cadence/Services/` | Import/export, completion, clocks, notifications, HealthKit, and persistence error handling |
| `Cadence/Seed/` | Generic exercise/reference data and program templates; never personal state |
| `Cadence/Views/` | SwiftUI screens and reusable presentation components |
| `Cadence/LiveActivity/` | Shared ActivityKit attributes, controller, and intents compiled into app and widget targets |
| `CadenceWidgets/` | Live Activity and Control Center/widget extension surfaces |
| `CadenceMigrationTests/` | Hostless macOS tests that create and migrate real SwiftData SQLite stores |
| `web/js/` | PWA domain mirror, IndexedDB, application orchestration, and views |
| `web/tests/` | Core parity, runtime smoke tests, and cross-platform fixtures |
| `web/tools/` | Deterministic fixture generators |
| `docs/` | Diátaxis user documentation and data-contract references |
| `project.yml` | XcodeGen source of truth for targets, schemes, settings, entitlements, and Info.plist values |
| `.github/workflows/` | Required CI, Pages deployment, semantic release, and optional TestFlight automation |
| `fastlane/` | Headless signing and TestFlight upload flow |

## Working approach

Before editing:

1. Read the relevant models, service, domain function, tests, and user docs.
2. Check the worktree and preserve unrelated user changes.
3. Identify whether the change affects SwiftData, IndexedDB, the portable
   backup contract, Swift/JavaScript parity, the widget extension, or release
   semantics.
4. For behavior shared by both clients, define the behavior in deterministic
   terms and update both implementations in the same change.

While editing:

- Keep views thin. Compute prescriptions, progression, load semantics, timers,
  classification, and other testable decisions in `CadenceCore`.
- Prefer small, named functions and explicit domain types over view-local
  conditionals and stringly typed rules.
- Preserve stable exercise, program-slot, gym, and session identities. Display
  names are not reliable database keys unless the model explicitly defines
  them that way.
- Mutate exactly one side of a SwiftData inverse relationship. Assigning the
  child inverse and appending the same child to the parent collection can
  persist duplicate references that render as mirrored rows. Startup repair
  may deduplicate existing aliases, but new code must not create them.
- Surface persistence failures through the existing error/recovery paths. Do
  not use `try?` where failure would mean lost training changes.
- Update user documentation when behavior or a data contract changes.

## Persistence, migrations, and semantic versioning

Persistence is a public compatibility contract. Treat an existing user's store
and backup as inputs from a released API version, not as development data that
can be recreated.

### What counts as a schema change

For SwiftData, assume the schema changes when a persisted model changes in any
way, including:

- adding, removing, renaming, or changing the type/default of a property;
- changing optionality, uniqueness, external storage, or transformable data;
- adding or changing a relationship, inverse, ordering expectation, or delete
  rule; or
- changing the set of models registered in the schema.

For the web app, changes to object stores, key paths, indexes, persisted record
shape, required fields, or interpretation of stored values require an IndexedDB
upgrade review. Changes to exported JSON require a backup-schema review too.

### SwiftData release process

The current schema is declared in `Cadence/Models/PersistenceSchema.swift`.
Historical snapshots live in `PersistenceSchemaV*.swift`. V1 and the alternate
schema accidentally written by PR #72 are both supported histories; do not
remove either path.

Before modifying any live `@Model` declaration:

1. Determine the newest schema that has actually shipped from `main`.
2. Freeze its exact model shape and checksum in an immutable versioned schema
   file if it is not already frozen. Once committed in a release, that file is
   append-only history and must never be edited.
3. Introduce a new, monotonically increasing `Schema.Version`. Never reuse a
   version identifier for a different checksum.
4. Add a linear `SchemaMigrationPlan` from every supported shipped checksum to
   the new current schema. SwiftData plans cannot branch inside one plan, so
   retain separate production plans and the `AppBootstrap` fallback when
   historical checksums require separate paths.
5. Use a lightweight migration only when SwiftData can express the conversion
   safely. Use a custom stage when values, relationships, constraints, or
   identities require transformation.
6. Backfill migration-safe literal defaults after the container opens when
   necessary. Backfills must be idempotent, preserve valid existing values,
   repair invalid/duplicate identities, and save errors visibly.
7. Keep the recovery screen non-destructive. A temporary in-memory session is
   an escape hatch, not a replacement for the persistent store.

Never solve a checksum mismatch by mutating an old `VersionedSchema`, pointing
the same version at new models, deleting SQLite files, or instructing the user
to reinstall.

### Required SwiftData migration test

Every SwiftData schema change must extend `CadenceMigrationTests` and CI. The
test must:

1. Create a real on-disk store with each affected released schema/checksum.
2. Insert representative records, including relationships and user-edited
   values relevant to the change.
3. Close that container and open the same URL with the production current
   schema and migration plan used by the app.
4. Assert that records, relationships, adjusted weights/reps, identities,
   settings, and relevant defaults survived correctly.
5. Run any production post-open backfill and assert its invariants and
   idempotence.

An in-memory test, a fresh-store test, model compilation, or a successful app
build does not prove upgrade compatibility. The `CadenceMigrationTests` scheme
must remain in `project.yml` and the macOS CI job.

### IndexedDB upgrades

`web/js/db.js` owns `DB_VERSION` and `onupgradeneeded`.

- Bump `DB_VERSION` for an IndexedDB schema or persisted-shape upgrade.
- Migrate old records during the upgrade transaction; seeding fresh defaults
  is not a migration.
- Make transformations deterministic and safe to run once from every supported
  older version.
- Add fake-indexeddb coverage that creates the prior database version, opens it
  with current code, and verifies user data and indexes.
- Coordinate service-worker cache changes when deployed assets or startup
  assumptions change.

### Portable backup contract

The JSON backup is the cross-platform recovery and interchange format.

- Keep `CadenceCore/BackupContract.currentSchemaVersion` and
  `web/js/db.js` `BACKUP_SCHEMA_VERSION` equal.
- Importers must continue to accept every documented older version and reject
  unsupported newer versions before destructive writes.
- A backup-schema change requires native and web import/export updates,
  `BackupContractTests`, web validation/smoke tests, regenerated synthetic
  fixtures, and `docs/reference/backup-schema.md` updates.
- Restore must be transactional or validation-first. Never partially replace
  good data with an invalid bundle.

### Semantic-release contract

Commits on `main` drive releases:

| Commit | Release |
| --- | --- |
| `fix:` | patch |
| `feat:` | minor |
| `fix!:` / `feat!:` or `BREAKING CHANGE:` | major |
| `docs:`, `test:`, `ci:`, `chore:`, `refactor:`, `style:` | no release |

If persisted data written by the new release cannot be opened by the previous
release, or an old store cannot be opened without conversion, the change is
breaking and must use a major-release marker. The same PR must contain the
upgrade path, migration tests, compatibility/recovery notes, and any backup
contract updates. Do not defer migration work to a follow-up.

Do not manually create version tags/releases or hand-bump release versions.
semantic-release owns them. Avoid `#word` tokens in commit subjects because the
release-note generator can misread them as issue references.

## Cross-platform domain parity

The following pairs are lockstep contracts:

- `CadenceCore` domain math ↔ `web/js/core.js`
- `ProgramTemplateData.swift` ↔ `web/js/templates.js` ↔
  `web/tests/fixtures/program-templates.json`
- `AnatomyData.swift` ↔ `web/js/anatomy.js` ↔
  `web/tests/fixtures/anatomy.json`
- `BackupContract.currentSchemaVersion` ↔ `BACKUP_SCHEMA_VERSION`
- Native seed names ↔ template exercise names and web seed names

When one side changes, update the other implementation and equivalent tests in
the same PR. Regenerate fixtures only after reviewing the semantic diff; do not
update snapshots merely to silence a failure.

`CadenceCore` must remain Foundation-only and Linux-testable. Do not import
SwiftUI, SwiftData, UIKit, ActivityKit, HealthKit, or other Apple-only frameworks
into it. Guard genuinely Darwin-only tests with `#if canImport(Darwin)`.

## Training-data invariants

- Planned prescriptions and performed work are different. History, goals,
  progression, summaries, and PR detection must use the final performed set
  values, including in-session weight/repetition edits.
- Editing reps must not overwrite an adjusted weight, and editing weight must
  not silently reset other set state.
- Users can add and remove individual sets. Preserve deterministic ordering and
  do not conflate removing a set with removing an exercise.
- Program days, lifts, accessories, session exercises, and sets must contain
  each persistent model reference once. Two visible editor rows must always be
  two independently editable models with distinct stable slot identities.
- Set lifecycle is explicit: planned, completed, and skipped are not
  interchangeable. Warmups do not count as working sets unless a rule says so.
- Load semantics are explicit (`totalBar`, per implement/per hand, bodyweight,
  assisted, duration/distance). Do not infer historical meaning from a display
  label when persisted semantics exist.
- Main dumbbell work progresses in practical per-hand increments and receives
  warmups according to the production warmup policy.
- Program progression is pure and deterministic. It consumes completed
  performance summaries and preserves manual in-session adjustments.
- Exercise definitions are generic reference data. Keep canonical names,
  categories, movement groups, equipment/load basis, unilateral state, and
  aliases coherent across seed data, templates, search, and swap rules.

## Product and UI principles

- Gym arrival is a primary use case. The membership tag must be trivially and
  prominently accessible at launch, through its shortcut/control surfaces, and
  without navigating a settings hierarchy.
- Optimize for minimal interaction during training: prefill predictable values,
  preserve edits, use large targets, and keep primary actions reachable with
  one hand.
- Guide rather than interrogate. Ask only when an incorrect inference would
  corrupt the log.
- Make planned versus actual state visually clear without requiring the user to
  manage implementation details.
- Accessibility, Dynamic Type, safe areas, light/dark themes, reduced motion,
  VoiceOver labels, and destructive-action confirmation are part of done.
- Keep native and web information architecture conceptually aligned while using
  platform-appropriate controls.

## Privacy and security

- Seed only generic exercises, equipment defaults, and optional program-style
  templates. No real user values or exported backups belong in fixtures.
- Synthetic fixtures must be obviously artificial and deterministic.
- HealthKit remains optional and write-only unless an explicitly scoped change
  updates permissions, privacy text, documentation, and tests.
- Never log full backups, membership barcodes, body/health records, or secrets.
- Keep GitHub Actions permissions least-privilege and pin third-party actions to
  immutable commit SHAs.
- Signing keys, `.p8` files, match credentials, Apple IDs, PATs, and passwords
  belong only in the documented secret stores.

## Build and test commands

Core tests, from any supported Swift toolchain:

```bash
cd CadenceCore
swift test
```

Web parity and smoke tests:

```bash
cd web
npm ci
npm test
```

Native project and builds, on macOS with the required Xcode:

```bash
brew install xcodegen
xcodegen generate
xcodebuild test -project Cadence.xcodeproj -scheme CadenceMigrationTests -destination 'platform=macOS'
xcodebuild build -project Cadence.xcodeproj -scheme Cadence -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

This Linux workspace cannot compile the app target; GitHub Actions is the
authoritative compiler for SwiftUI/SwiftData changes. Do not claim native
validation until the macOS migration test, simulator build, and unsigned-device
build have completed successfully.

## CI and releases

Pull requests always run Linux CadenceCore tests, web parity/runtime tests, and
the stable `App build (macOS)` aggregate check. Native validation is
change-aware behind that aggregate:

- current iOS Simulator and unsigned-device builds run in parallel for native,
  shared-core, project, or CI-workflow changes;
- docs/web-only changes do not consume macOS runners; and
- the real shipped-store migration suite runs for persistence-affecting paths
  only. Its generic historical stores are cached by immutable shipped lineage,
  but a cache miss must regenerate them from the actually shipped apps.

Never broaden the migration skip list to make schema CI faster. If a model,
Seeder, migration test, project definition, or shipped-store generator can
affect compatibility, `.github/scripts/classify-ci-paths.sh` must classify it
as a migration change and its classifier tests must be updated.

Green pushes to `main` run semantic-release and package release artifacts. A
signed TestFlight upload runs only when semantic-release publishes a new tag;
`workflow_dispatch` with `force_testflight=true` is the explicit recovery path
for re-uploading the latest tag. Web deploys reuse the CI web-test result;
`pages.yml` is manual recovery only. See `docs/TESTFLIGHT.md`; do not weaken
signing, migration, or secret controls to make CI convenient.

## Code and repository hygiene

- Follow existing Swift and JavaScript style. Do not reformat unrelated code.
- Add a regression test for every reproduced bug at the lowest deterministic
  layer that can express it.
- Capture recurring Swift compiler hazards in
  `CompileRegressionTests.swift` when CadenceCore can represent them.
- Preserve the user's dirty worktree and unrelated changes.
- Do not commit generated `Cadence.xcodeproj`, `.build/`, `DerivedData/`, test
  result bundles, packaged apps, secrets, or personal exports.
- Update `README.md` for developer-facing setup/feature changes and `docs/` for
  user-facing or data-contract behavior.
- Use Conventional Commits intentionally. The final merge/squash subject must
  carry the correct semantic-release meaning.

## Definition of done

A change is done only when:

- behavior matches the training and product invariants above;
- native and web implementations remain in parity where applicable;
- regression tests cover the change and all relevant suites pass;
- every persisted-schema change has a version, upgrade path, real-store test,
  and correct major semantic-version marker;
- backup compatibility and documentation are updated when needed;
- no personal data or secret was introduced;
- generated artifacts are absent from the diff; and
- CI is green for the exact commit proposed for merge.
