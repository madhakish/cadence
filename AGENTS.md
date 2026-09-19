# Cadence repository guide

This is the canonical guide for the repository. Nested `AGENTS.md` files may
add subtree guidance; user/runtime instructions retain their normal precedence.

## Before work

- Read [AGENT-COORDINATION.md](AGENT-COORDINATION.md). Check the task issue,
  current comments, and overlapping PRs before claiming scope or editing.
- Before implementation or code review, read and enforce the
  [Torvalds doctrine](.agents/torvalds-doctrine.md). Criticize code, not people;
  repository persistence, privacy, parity, and compatibility rules still apply.
- Inspect the worktree and preserve unrelated work. Find the implementation,
  tests, native/web counterpart, and affected persistence/import boundaries.
- Read the applicable complete sections in the table below before touching that
  area. They are binding instructions, not optional background. Do not load the
  entire detailed guide for an unrelated task.

Cadence is a single-user, local-first training logbook with an iOS 17+ app and a
vanilla-JavaScript PWA. There is no backend recovery source. `CadenceCore` owns
Foundation-only deterministic logic; `web/app/js/core.js` mirrors it.

## Rules that always apply

- Never delete/reset/replace a store or tell a user to reinstall as a fix.
  Preserve every shipped schema/checksum and supported backup history.
- Before changing persisted shape or meaning, follow the migration protocol.
  Freeze the shipped shape, add a new version, and upgrade every supported
  history in the same PR. SwiftData changes require production on-disk migration
  tests; fresh stores, in-memory tests, and compilation are insufficient.
- Breaking persistence/backup changes require a SemVer major marker even with
  automatic forward migration. Never defer required migration work.
  Document upgrade/downgrade implications and keep recovery non-destructive.
- Change shared domain behavior on both clients with equivalent tests. Keep
  Apple frameworks out of `CadenceCore`; platform and persistence stay at edges.
- Store weight in canonical pounds as `Double`; convert at input/display only.
  Use performed set values, preserve manual edits, stable IDs, load semantics,
  independent set ordering, and planned/completed/skipped/warmup distinctions.
- Mutate only one side of a SwiftData inverse relationship. Surface save
  failures through recovery paths; do not silently discard training changes.
- Never commit or post real workouts, health/body data, gym/member identifiers,
  backups, credentials, or signing material. Use synthetic fixtures.
- Health permissions default off and remain independently granted. Read access
  is device-local, never restored from a backup; health readings never silently
  overwrite logged values.
- Keep views thin and preserve workout usability, accessibility, Dynamic Type,
  VoiceOver, themes, safe areas, reduced motion, and destructive confirmations.
- Edit `project.yml`; never commit generated `Cadence.xcodeproj`, build output,
  packaged apps, or test-result bundles. Keep changes scoped and conventional.
- semantic-release owns tags and versions. Preserve the fail-fast CI ladder,
  migration coverage, immutable signed-artifact promotion, and secret controls.
- Verify the exact PR head before calling it merge-ready. Publishing fixes
  additionally require the actual post-merge release/TestFlight evidence.

## Required reading by task

Paths inside the detailed guide are relative to the repository root unless
they are Markdown links. For any code change, read working approach, privacy,
hygiene, and definition of done in addition to the relevant domain sections.

| Task | Read before changing it |
| --- | --- |
| Any code change | [Working approach](docs/AGENT-GUIDE.md#working-approach), [privacy](docs/AGENT-GUIDE.md#privacy-and-security), [hygiene](docs/AGENT-GUIDE.md#code-and-repository-hygiene), [done](docs/AGENT-GUIDE.md#definition-of-done) |
| Persisted models, records, imports, backups, schema releases | [Complete migration and versioning protocol](docs/AGENT-GUIDE.md#persistence-migrations-and-semantic-versioning) |
| Training logic, seeds, templates, anatomy, load semantics | [Parity](docs/AGENT-GUIDE.md#cross-platform-domain-parity), [training invariants](docs/AGENT-GUIDE.md#training-data-invariants), [invariant registry](docs/reference/invariants.md) |
| PWA mount, modules, caching, site copy | [Pages layout and app scope](docs/AGENT-GUIDE.md#pages-layout-and-app-scope) |
| UI, widgets, Live Activities, accessibility | [Product/UI rules](docs/AGENT-GUIDE.md#product-and-ui-principles), [training invariants](docs/AGENT-GUIDE.md#training-data-invariants) |
| CI, signing, publishing, releases | [CI/release rules](docs/AGENT-GUIDE.md#ci-and-releases), [build commands](docs/AGENT-GUIDE.md#build-and-test-commands), [TestFlight](docs/TESTFLIGHT.md) |
| New area or uncertain ownership | [Repository map](docs/AGENT-GUIDE.md#repository-map) |
| Changing these instructions | [Loading, budgets, and verification](docs/AGENT-INSTRUCTIONS.md) |

## Validation and handoff

- Core: `cd CadenceCore && swift test`.
- Web: `cd web && npm ci && npm test`.
- On macOS, use the [native commands](docs/AGENT-GUIDE.md#build-and-test-commands).
  CI is the normal authoritative native compiler when Xcode is unavailable.
  Check the unsigned-device/Darwin jobs and migrations when applicable; report
  pending work plainly. PRs do not require the main-only simulator artifact.
- Add meaningful regression coverage for reproduced behavior bugs, synchronize
  mirrored contracts, and update developer/user docs for relevant changes.
- Review `git diff --check`, privacy, generated files, scope, and commit meaning.
  Run checks appropriate to changed behavior; docs-only work needs link,
  instruction-size, and diff checks plus the existing required CI.
- Leave branch/PR/SHA, observed results, remaining work, and claim release in
  the task thread. Opening a PR is a handoff, not proof of green CI or a release.

## Code Review Rules

Prioritize persistence loss, missing migrations, parity regressions, incorrect
performed/load semantics, privacy leaks, and unverified completion claims.
Read the applicable rules above and report concrete evidence and impact.
