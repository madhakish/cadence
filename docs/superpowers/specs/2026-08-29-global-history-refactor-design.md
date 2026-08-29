# Global history refactor — umbrella design

Date: 2026-08-29
Status: approved design, pre-implementation
Baseline: main `7e36047` (v12.0.1, backup schema 10)

## Problem

Athlete strength data is duplicated and drifts. `baseWeightLb` /
`estimatedMaxLb` live on program lifts (`ProgramModels.swift`), on tracked
lifts (`TrackingModels.swift`), and in the web mirror (`web/app/js/db.js`) —
each program instance carries its own stale copy of what the athlete can
lift. Consequences observed in a real 12.0.1 export:

- Archived and current programs hold different copies of the same lift's
  strength values.
- Editing a completed session does not consistently update the canonical
  session or rebuild derived state (a corrected 5×5 deadlift still exported
  as 235×8).
- Switching programming styles would today mean re-entering weights and
  fragmenting history.

Separately, prescriptions emit gym-hostile loads: 1.25 lb plates sneaking
into lower lifts, warmups like 130 lb that nobody loads, and working weights
(260) that require fiddlier plate setups than their neighbors (255/265).

## Design principle (load-bearing)

- **Global history answers:** what has this athlete done, and what are they
  capable of now?
- **Program template answers:** how does this methodology convert that
  capability into today's work?
- **Program instance answers:** where is the athlete inside this block?

Programs prescribe; they never own history or carry a competing copy of
athlete strength. Sessions and sets are canonical; all derived state is
disposable and rebuildable.

## Decisions taken during design review

1. **P0 merges more than the calibrated keepers.** From the Chiron probe
   worktrees: undo-import, isPlateaued, release-notes docs page, PLUS the
   backup named-diff/restore-preview lineage, withCleanup + daysByKind, and
   ad-hoc targets + provenance captions. The morning-run pair (session time
   estimate, movement balance) is not merged and sweeps with the run.
2. **Codex implementation order kept.** Audit → schema → engines →
   switching → session-edit fix → metadata. Recorded trade-off: the
   session-edit export bug stays live until P5.
3. **One batched V11 schema major.** All persisted additions (exercise IDs,
   LiftProfile, session grouping, SetEquipment, warmup-conditioning fields)
   ride a single migration and a single backup-schema bump. Features ship
   incrementally afterward against the already-migrated store.
4. **Architecture + two proof templates.** Linear progression (behavior
   port of the current program; acceptance bar: existing users notice
   nothing) and 5/3/1 (frozen training max; proves snapshot + refresh
   machinery). Further styles are later content, not part of this plan.
5. **Plate-math quantization builds once, inside P3**, as the resolver's
   final stage. No early standalone version.

## Phase map

Each of P2–P7 gets its own spec → plan → implementation cycle.

- **P0 — Chiron harvest** (mechanics, no spec). Six PRs from existing green
  worktrees, in order: (1) withCleanup + TrainingIntervals.daysByKind,
  (2) undo-import, (3) TrendProjection.isPlateaued, (4) five-collection
  named backup diff + restore preview with confirm gate, (5) ad-hoc history
  targets + provenance captions (from the scope-bug-free t1-r2 worktree),
  (6) release-notes docs page with break-kind names corrected to
  Deload/Rest/Away/Active recovery. Then conclude the Chiron run and sweep
  all probe worktrees. Main is clean before refactor work starts.
- **P1 — Audit** (output is a document). Every reader/writer of
  baseWeightLb, estimatedMaxLb, tracked-lift strength, milestones, PRs,
  banked progression, and every session-edit path, both clients. Validates
  the V11 shape against reality; answers whether an e1RM formula already
  exists and where track-level vs program-level strength values disagree.
- **P2 — V11 schema major.** The only SemVer major in the plan. Details
  below.
- **P3 — Engines.** Centralized e1RM, resolveTrainingAnchor,
  ExerciseEstimateRule table, PlateMath quantizer.
- **P4 — Program lifecycle.** Template/instance split, activate/suspend/
  resume, refresh policies, two proof templates. Acceptance tests A–E.
- **P5 — Session editing + rebuildDerivedState().** Synthetic 5×5
  regression, idempotent rebuild, integrity-rebuild triggers. Test F.
- **P6 — Frequency + metadata UX.** Same-day grouping, ruck/stair pre-lift
  warmup flow, belt/strap filters and guidance. Tests H, I, J.
- **P7 — History as filter.** Program comparisons, A-vs-B overlays,
  all-time defaults; full-suite + schema-10 round-trip validation.
  Tests G, K.

## V11 data model

Target shapes; P1's audit finalizes the mapping onto existing models.

- **ExerciseDefinition** — existing `Exercise` model gains stable `id` +
  `aliases` as canonical identity; names become display/search values.
  Sessions and program slots migrate from name-references to
  id-references. The seed catalog maps known names → ids during migration;
  unrecognized names get new definitions, never guesses. Variations remain
  distinct exercises related only through explicit estimation rules — no
  string matching.
- **SessionRecord / SetRecord** — existing session models gain
  `sessionGroupId?`, `sequenceWithinDay?`, `sessionPurpose?` (strength /
  technique / warmupConditioning / conditioning / recovery / mixed),
  `revision` / `lastEditedAt`, per-set `SetEquipment` (belt / straps /
  sleeves / wraps: unknown | false | true — legacy migrates to `unknown`,
  never `false`), and warmup-conditioning fields (modality, load, duration,
  distance, pace, incline, flights, placement: preLift | betweenLifts |
  postLift | standalone).
- **LiftProfile** — new persisted store on both clients (SwiftData model +
  IndexedDB object store), explicitly a disposable projection: carries
  `estimatorVersion` + `sourceSetIds`, rebuilt idempotently from sessions,
  never edited directly. Persisted (not computed-on-demand) for
  phone/widget performance; canonical truth stays with sessions. Holds
  current e1RM, all-time best e1RM, latest completed work set, recent top
  sets, recent exposure date, confidence.
- **Program split** — current program model becomes ProgramTemplate
  (stateless: days, phases, load rules, progression rules, training-max
  policy + refresh policy), ProgramInstance (active/suspended/archived,
  cursor, cycle, phase, rotation state, activation history, overrides),
  ProgramLiftState (per-slot progression state; optional
  trainingMaxSnapshot + snapshot source when template policy requires one —
  derived from a global LiftProfile, never a replacement for it).
  `baseWeightLb` / `estimatedMaxLb` survive only as schema-10 decode
  inputs; nothing reads them post-migration.

## Migration (P2)

- One SwiftData plan extended from every supported checksum, including the
  PR-72 branched history, per the repository migration protocol.
- LiftProfiles seeded by priority: completed session history first;
  existing milestone/history projections as validation only; program
  `estimatedMaxLb` only when no valid session history exists; conservative
  default last. Never the largest stale estimate.
- Gear metadata on old records → `unknown`.
- Program lift references convert from exerciseName to exerciseId.
- Backup: `BackupContract.currentSchemaVersion` and `BACKUP_SCHEMA_VERSION`
  10 → 11 together; schema-10 import kept; newer-than-11 rejected before
  writes; synthetic fixtures regenerated deliberately;
  `docs/reference/backup-schema.md` updated.
- Web: `DB_VERSION` bump with `onupgradeneeded` transforms and
  prior-version open tests.
- Proof: real on-disk stores in `CadenceMigrationTests` for all affected
  checksums; fresh-store tests are insufficient. Marked `feat!:`.
- The P0-merged restore-preview/named-diff UX is the user-facing safety net
  for this release's imports.

## Engines (P3)

All engines are pure functions in `CadenceCore` mirrored 1:1 in
`web/app/js/core.js` with matching test cases in both suites.

- **e1RM** — exactly one versioned implementation; `estimatorVersion`
  stamped into every LiftProfile. Completed work sets only; warmups,
  failed, skipped, incomplete sets excluded; very high-rep estimates get
  reduced confidence; a true single evaluates to its actual weight; current
  and all-time tracked separately; historical e1RM events preserved for
  charts; program-style changes never overwrite completed history.
  Load-basis normalization happens here once (totalBar / perImplement /
  externalTotal / bodyweight / assisted) — dumbbells cannot double-double;
  bodyweight/assisted lifts get their own capacity model; conditioning
  progresses on duration/distance/load with no e1RM.
- **resolveTrainingAnchor(exerciseId, template, instance, context)** —
  resolution order: explicit user override → valid exact-exercise
  LiftProfile → recent exact-exercise work at a compatible rep scheme →
  explicit related-exercise rule → movement-pattern anchor → core-lift
  anchor → conservative default. Returns value, source, confidence,
  sourceExerciseId, sourceSetIds, relation rule id/version, explanation —
  so the UI can show "Estimated from Back Squat" with one-tap correction.
  Anchor families: Back Squat (squat), Deadlift (hinge), Barbell Bench
  (horizontal press, with recorded dumbbell/incline fallback), strict OHP
  (vertical press); Olympic lifts prefer exact history, related-strength
  estimates only as low-confidence fallback. Shelved exercises are never
  silently reactivated; historical strength may inform estimates.
- **ExerciseEstimateRule** — small, explicit, versioned relation table
  (source, target, coefficient, confidence, load-basis pair, min/max
  clamps). Seeded only with rules the proof templates and common
  substitutions need: Front Squat ← Back Squat, RDL ← Deadlift,
  Snatch-Grip DL ← Deadlift, Incline ← Bench, Push Press ← OHP,
  Box Squat ← Back Squat, Weighted Pull-up ← Pull-up. No speculative
  ontology.
- **PlateMath quantizer** — the resolver's final stage
  (anchor → percentage → quantize → prescription). Inventory-aware:
  default 45/25/10/5/2.5 per side, no 1.25s, 45 lb bar; per-gym inventory
  rides the existing Gym model. Warmup rule (aggressive): snap to
  large-plate-friendly loads only (45/25/10 combos — 130 → 135); never
  prescribe a warmup needing 2.5s. Working-set rule: within ±5 lb prefer
  the load with the fewest small plates per side (260 → 265 when
  progressing, → 255 on deload/backoff; direction from progression
  context). Precision escape hatch: near-max singles/doubles keep full
  resolution. Property test: the quantizer never emits a load the
  inventory cannot build.
- **rebuildDerivedState() (ships P5)** — one entry point plus scoped
  variant `(affectedExerciseIds, fromDate)`; idempotent; triggered after
  session edit, backup import, schema migration, and estimator-version
  change. Rebuilds: exercise history, current/all-time e1RM, PRs,
  milestones, volume, rep-scheme records, banked/completion counts,
  rotation completion, cycle advancement, progression state, stall
  detection, readiness, recommendations, charts, export data. Stale
  coaching decisions are marked superseded in an audit log, never
  re-applied.

## Program lifecycle (P4)

- `activateProgram(templateId, mode)` / `suspendProgram(instanceId)` /
  `resumeProgram(instanceId)`.
- Modes: `resumeExistingInstance` (cursor, rotation, cycle, phase, and
  progression state preserved; loads refresh per template policy; no
  weight prompts; no history reset), `startNewBlock` (new instance from
  template, every lift seeded from LiftProfiles or fallback estimates,
  previous instance preserved as filterable history), `createNewInstance`
  (parallel instance of the same style, same global history).
- `TrainingMaxRefreshPolicy`: eachSession | eachRotation | eachCycle |
  onActivation | manual — template-defined, not user-facing configuration.
- Switching must never: delete/rename sessions, rewrite historical program
  tags, reset PRs/charts/bodyweight history, duplicate exercises, copy
  stale e1RMs from archived programs, or prompt for known weights.
- Completed sessions keep their original program context. All-time history
  is the default view; program is a filter, not a storage boundary.
  Required comparisons: all programs, one program, A vs B, same lift
  across styles (P7).

## Frequency, warmups, gear (P6)

- No Monday–Sunday assumption: training days, rotations, cycles,
  mesocycles, recovery intervals; calendar weeks are presentation
  metadata. `preferredSessionSpacingDays` stays guidance and must not
  block consecutive days, variable rest, multiple sessions per date,
  AM/PM splits, technique micro-sessions, or separated conditioning.
- Distinguish distribution frequency vs practice frequency vs dose
  frequency; readiness/coaching use actual performance trends, not
  "sessions < 24 h apart" alone.
- Ruck / stair-climber pre-lift warmups modeled explicitly as warmup
  conditioning (~0.5 mi / ~10 min / ~3.2 mph / ~20 lb / ~2% grade, or
  ~20 flights): tracked with modality, load, duration, distance, pace,
  incline, flights, placement, optional effort rating; never classified as
  a failed strength prescription; never an automatic readiness penalty; no
  automatic intensity escalation just because it is repeatable. Progression
  recommendations distinguish warmup purpose from dedicated conditioning.
- Belt/straps: set-level metadata, never separate exercises. Unified
  history with belted/beltless and strapped/unstrapped filters. Guidance by
  relative intensity and effort (beltless easy warmups; optional ~70–80%
  e1RM; increasingly useful 80%+ / RPE 8+; beltless backoffs for bracing
  practice) — recommendations, not enforcement; no bodyweight-ratio
  gates. Templates may declare a gear policy (beltless / optional /
  recommended / competitionSpecific).

## Testing strategy

- Acceptance tests A–K from the brief map onto phases: A–E, G → P4;
  F → P5; H–J → P6; K → P2 + P7.
- Written as mirrored CadenceCore + core.js unit tests; where they cross
  persistence, real on-disk CadenceMigrationTests stores and
  fake-indexeddb smoke tests.
- Pure engines get property-style coverage (quantizer inventory
  invariant; resolver order totality; rebuild idempotence).
- Synthetic fixtures only: a schema-10 fixture for K, the 5×5 edit fixture
  for F (one incorrect final set corrected to 5×5; verify canonical
  session, e1RM, volume, milestone, banked-once progression,
  recommendations, chart, and export all agree; rebuild idempotent). No
  personal exports committed, ever.

## Release train

- P0: individual `feat:` / `fix:` / `docs:` PRs, each CI-green and
  squash-merged with release-meaningful titles.
- P2: the one `feat!:` major, migration notes in the PR body; post-merge
  main run watched through TestFlight per doctrine.
- P3–P7: minors against the migrated store.
- Every phase: Linux parse gate → macOS jobs → migration scheme when
  persistence is touched, on the exact head commit; both mirrored suites
  green.

## Non-negotiable rules (carried from the brief)

Sessions and sets are canonical. Derived state must be rebuildable.
Exercise identity must be stable. Athlete strength is global. Programs
prescribe; they do not own history. Program-specific progression state is
allowed; program-specific duplicate strength facts are not. Existing users
never re-enter known weights. Switching programs never resets progress.
Completed historical prescriptions remain historical facts. No personal
training export in the repository. No drive-by refactor. No name-based
special-case pile. No broad abstraction hierarchy where structs and
deterministic functions solve it.
