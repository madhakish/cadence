# Contributing

Cadence is a single-maintainer project, and the source is **published for
reference, not for redistribution** — see [LICENSE](LICENSE). That shapes what
is useful to send:

| | |
|---|---|
| **Bug reports** | Very welcome. [Open an issue](https://github.com/madhakish/cadence/issues/new/choose). |
| **Feature ideas** | Welcome. Say what you were trying to train, not just what button you wanted. |
| **Security reports** | Please use [private reporting](https://github.com/madhakish/cadence/security/advisories/new), not a public issue. See [SECURITY.md](SECURITY.md). |
| **Pull requests** | Not accepted from outside the project. The license grants no right to publish derivative works, so there is no path to merge outside code without a separate written agreement. Please open an issue instead — a good report is worth more here than a patch. |

If you were about to send a patch: sorry, and thank you. Describe the fix in an
issue and it will get built with attribution.

---

The rest of this file is the working contract for anyone — the maintainer, or a
coding agent acting on their behalf — making changes **inside** the repository.

## Read these first

[`AGENTS.md`](AGENTS.md) is the canonical repository guide: the repository map,
the migration protocol, the parity contract, and the definition of done.
[`CLAUDE.md`](CLAUDE.md) is the startup checklist and repeats the safety rules
that must never depend on memory. Where the two differ, **follow the stricter
rule**.

## What this app is

A local-first strength-training logbook with no server. The user's on-device
store and their portable backup **are** the source of truth. There is no
migration you can run later from a backend, and no support channel that can
recover a store you broke. Persistence compatibility therefore outranks
implementation convenience, every time.

It is also used mid-workout, one-handed, between sets, by someone who is tired.
Predictable defaults and edits that never disappear beat clever inference.

## Three shapes of change

**Shared training logic** lives in `CadenceCore/Sources/CadenceCore/` and is
mirrored 1:1 by `web/js/core.js`. Never change one side alone. Add matching
cases to `CadenceCore/Tests/CadenceCoreTests/` and `web/tests/core.test.mjs`.
`CadenceCore` is Foundation-only — no Apple frameworks.

**Platform code** is `Cadence/` (SwiftUI) and `web/js/views/` (vanilla JS).
Keep views and persistence adapters thin; new testable logic belongs in core.
Never edit the generated `Cadence.xcodeproj` — edit `project.yml`.

**Persisted state** — a SwiftData `@Model`, an IndexedDB record shape, or the
backup contract — stops normal implementation flow. Go read the migration
protocol in `AGENTS.md` before writing anything, and see below.

## If you touch persistence

The short version of a long protocol:

- Never mutate a released `VersionedSchema` or reuse its version identifier.
  Freeze it as a snapshot and add a new one.
- Extend **every** migration plan from **every** shipped checksum. The
  repository deliberately carries more than one history.
- Prove it with a real on-disk store in `CadenceMigrationTests`. A fresh-store
  test, an in-memory test, and a successful compile all prove nothing here.
- Never delete or reset a store, and never tell a user to reinstall, as a fix.
- Keep `BackupContract.currentSchemaVersion` and `BACKUP_SCHEMA_VERSION` in
  lockstep, and update `docs/reference/backup-schema.md`.
- Mark it a **breaking** change (`fix!:`/`feat!:` or a `BREAKING CHANGE:`
  footer) if old stores need conversion or an old binary could not open newly
  written data — even when the new app migrates automatically.

Never defer a required migration to a follow-up PR.

## Behavioural invariants

[`docs/reference/invariants.md`](docs/reference/invariants.md) is a readable
specification of rules that must not silently change. Each one exists because
the opposite behaviour shipped and cost something real.

It is machine-checked. Tag an assertion with the rule ID and
`.github/scripts/check-invariants.mjs` will verify that every rule is asserted
on every platform it claims:

```js
ok(scheme === "1×5", "[INV-SCHEME-PERFORMED] a top set plus a fatigue set is one five");
```

Fixing a bug that the registry does not yet describe is a good moment to add a
rule. Deleting one is a deliberate act — say in the commit why the behaviour is
no longer required.

## Privacy

Never commit real workouts, bodyweight or health data, gym names, membership
photos or barcodes, exports, credentials, or signing material. Seed and fixture
data is generic by construction. If you need a realistic dataset to reason
about, keep it outside the repository.

This applies to issues too: **do not paste a real backup file into a bug
report.** See the reporting template for how to redact one.

## Validation

```bash
cd CadenceCore && swift test
cd web && npm ci && npm test     # parity + IndexedDB + smoke + invariant gate
```

On a Mac:

```bash
xcodegen generate
xcodebuild test -project Cadence.xcodeproj -scheme CadenceMigrationTests -destination 'platform=macOS'
xcodebuild build -project Cadence.xcodeproj -scheme Cadence -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

Without a Mac, GitHub Actions is the compiler. Wait for the exact head commit
to pass the migration tests, the Simulator build, and the unsigned device build
before calling app-target work done.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/), read by
semantic-release on `main`:

- `fix:` → patch, `feat:` → minor
- `fix!:` / `feat!:` / `BREAKING CHANGE:` → major
- `docs:` / `test:` / `ci:` / `chore:` / `refactor:` / `style:` → no release

The **squash subject** is what semantic-release reads, so it must carry the
correct meaning for the whole PR. Never create release tags or hand-edit
versions — semantic-release owns them.

## Done

A change is done when behaviour matches the invariants, native and web stay in
parity, regression tests cover it, any persisted-schema change has a version
and a real-store test and the right SemVer marker, docs are updated, no
personal data or generated artifact is in the diff, and CI is green on the
exact commit proposed for merge.

For release or publishing changes, green PR checks prove nothing. Watch the
post-merge `main` run through a completed TestFlight job.
