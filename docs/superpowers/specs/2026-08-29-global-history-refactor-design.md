# Global history refactor — umbrella design

Date: 2026-08-29
Status: approved design, pre-implementation
Baseline: main `7e36047` (v12.0.1, backup schema 10, web DB_VERSION 7)
Epic: #155 — program-independent lift history, training anchors, and
lossless program switching. Where this document and #155 differ on code
shapes, #155 wins: it was written against the inspected seams.

## Problem

Athlete strength data is duplicated and drifts. `estimatedMaxLb` is copied
into every program slot (`ProgramModels.swift`) and treated as if each
program owns the athlete's capability; archived and current copies of the
same lift disagree in real 12.0.1 exports. `baseWeightLb` is different: it
is legitimate program-local cursor state (linear working load, Texas slot
load, wave base, 5/3/1 anchor) and must survive suspension/resume — it is
NOT deleted by this refactor.

Further confirmed debt (#155):

- Exercise identity is a display name; joins are stringly typed
  (`indexedByName()`, `exerciseName` on program slots, name-keyed web
  store).
- History projection is computed independently in at least four places
  (`ProgramTemplates.recordedHistory`, chart e1RM, prior-best grading,
  recall lines, plus web mirrors).
- `SessionDetailView.commitCorrections` intentionally does not re-run
  progression grading or PR detection. Per code inspection it DOES write
  the canonical `SetEntry` fields that `ExportService.buildBundle`
  serializes, so exports of corrected sets are expected correct; the
  stale-state risk is confined to separately persisted progression,
  milestone, and cursor state. The 235×8-after-correction anomaly seen in
  a real export is therefore a finding to reproduce in Stage 0, not an
  assumed baseline failure.

Separately (user requirement, not in #155): prescriptions emit gym-hostile
loads — 1.25 lb plates sneaking into lower lifts, 130 lb warmups, working
weights like 260 that load worse than 255/265. A `PlateMath` policy
already exists in CadenceCore (mirrored in core.js) and is applied
per-prescription via `ProgramSession.achievableWeight` /
`achievableWarmups`; the defect is policy (all standard denominations
enabled by default, no small-plate avoidance, no warmup snapping), not a
missing engine.

## Design principle (load-bearing)

Programs prescribe. Sessions prove. The history projection is rebuildable
and never becomes another persistent competing truth.

- Global history answers: what has this athlete done; what can they do now?
- Program template answers: how does this methodology convert capability
  into today's work?
- Program (the existing model — already the instance) answers: where is
  the athlete inside this block?

## Canonical model (#155, verbatim intent)

```text
Completed sessions + performed sets   — canonical athlete history
AthleteHistoryIndex                   — disposable in-memory projection
ProgramTemplateData                   — stateless methodology
Program                               — one resumable user-specific block
ProgramLift / ProgramAccessory        — methodology-local cursor state
```

Explicitly rejected for the first implementation: a persisted LiftProfile.
Start pure; cache in memory only if profiling proves the scan matters;
persisting later requires measured justification and a derived-state
version.

## Decisions taken during design review

1. **P0 merges more than the calibrated keepers.** From the Chiron probe
   worktrees: undo-import, isPlateaued, release-notes docs page, PLUS the
   backup named-diff/restore-preview lineage, withCleanup + daysByKind,
   and ad-hoc targets + provenance captions. The morning-run pair
   (session time estimate, movement balance) is not merged and sweeps
   with the run.
2. **Characterize before architecting.** Stage 0's synthetic regression
   identifies exactly which persisted projections go stale before any
   journal/reducer design (supersedes the earlier "edit fix at step 6 /
   audit-only first" framing — Stage 0 IS the audit, executable).
3. **Narrow V11 major** (supersedes the earlier "one batched V11"
   decision, per #155): stable exercise identity + template origin only.
   Session purpose/grouping, warmup-conditioning role, and belt/strap
   metadata are later, separate schema work with their own bumps.
4. **No new program hierarchy.** `Program` is already the instance;
   `templateID` groups instances by style. No ProgramTemplate/Instance/
   LiftState rename churn.
5. **Proof-of-machinery scope for styles.** The switcher and resolver are
   proven against the existing template set — linear-style progression
   (current behavior, byte-for-byte gate) plus one frozen-training-max
   methodology — before any new styles are authored.
6. **Plate-math quantization lives at prescription materialization,
   never in capability resolution** (PR #156 review, blocking). The
   resolver's output is gym-independent athlete capability; quantization
   extends the existing `PlateMath` policy at the
   `ProgramSession.achievableWeight`/`achievableWarmups` call sites,
   after methodology conversion. Quantized loads are never written back
   into `baseWeightLb` or any global state — cursor rounding uses the
   program's existing `roundingLb` policy. No early standalone version.

## Phase map

P0–P2 need no persisted-schema change. Each of P1–P8 gets its own
spec → plan → implementation cycle; PR titles follow #155's sequence.

- **P0 — Chiron harvest** (mechanics, no spec). Six PRs from existing
  green worktrees, in order: (1) withCleanup +
  TrainingIntervals.daysByKind, (2) undo-import, (3)
  TrendProjection.isPlateaued, (4) five-collection named backup diff +
  restore preview with confirm gate, (5) ad-hoc history targets +
  provenance captions (scope-bug-free t1-r2 worktree), (6) release-notes
  docs page with break-kind names corrected. Then conclude the Chiron run
  and sweep all probe worktrees. P0 is NOT a dependency of the refactor:
  P1/P2 may start in parallel; the harvest merges first only where
  convenient, never as an architectural gate.
- **P1 — Stage 0: characterize banked correction.**
  `test/fix: characterize banked-session correction projections`.
  Extract `SessionCorrectionService` (native) + web mirror so the view
  buffers text and delegates; build the synthetic programmed 5×5 deadlift
  fixture (bank four sets, correct the fifth) and assert independently:
  stored session, export, volume/work-set summary, chart e1RM points,
  rotation/banked-day accounting, milestone/PR state, program
  cursor/pending grade — each correct or demonstrably stale — and
  idempotence. Gate: no journal design until this inventory exists.
- **P2 — Stage 1: centralize the history projection.**
  `refactor: centralize athlete history and e1RM projection`.
  `AthleteHistory.swift` in CadenceCore + core.js mirror:
  `CompletedSetSample` → `LiftHistoryProfile` (latest completed load,
  latest exposure, all-time/recent best e1RM, provenance, exposure
  count). Preserve current behavior exactly: completed non-warmup sets
  only, canonical pounds, the existing Epley formula, exact
  load-semantics handling, no e1RM without external resistance,
  lifetime-best seeding where templates already use it. Replace duplicate
  readers incrementally (template creation → custom bootstrap → chart
  samples → prior-best lookups where semantics match; do not unify
  readers answering different questions). Gate: program creation is
  byte-for-byte equivalent on synthetic history.
- **P3 — Stage 2: stable identity, V11 schema major.**
  `feat!: add stable exercise identity and backup schema v11`.
  One compatibility-complete breaking PR: native CadenceSchemaV11 (freeze
  the shipped V10 snapshot first), backup schema 11 both clients, web
  DB_VERSION 8. Optional `id`/`exerciseID`/`templateID` fields per #155's
  model list; idempotent post-open repair assigns every legacy row a
  portable ID; one deterministic legacy-ID function in CadenceCore
  mirrored in JS so a v10 backup imports to identical IDs on both
  clients. Web keeps the name key, adds a unique `byId` index, backfills
  in the upgrade transaction. Resolution invariant everywhere: ID present
  → resolve by ID or fail closed; ID absent → legacy name fallback;
  foreign ID → never bind by coincidental name. Importers accept v0–v10
  and synthesize IDs; v11 round-trips without identity loss. Gates: real
  V10 SQLite migration test, fake-indexeddb V7→V8 test, v10 fixture
  imports both clients, native→web→native v11 round trip, double-run
  migration produces no changes. The P0-merged restore-preview/named-diff
  UX is the user-facing safety net for this release.
- **P4 — Stage 3: training-anchor resolver (+ plate math).**
  `feat: resolve new program anchors from global history`.
  `TrainingAnchorResolver.swift` + mirror, consuming AthleteHistoryIndex
  only (no independent scans). Order: explicit override → exact-exercise
  completed history → exact latest successful load (styles that need a
  load, e.g. double progression) → explicit related-lift rule → explicit
  movement-family/core-lift rule → existing `ProgrammingDefaultsData`.
  Returns e1RM/latest work + source + sourceExerciseID + confidence +
  explanation; UI may say "estimated from Deadlift", never presents an
  estimate as measured. Related-lift rules: small versioned data table
  (front/box squat ← Back Squat; RDL/snatch-grip/speed ← Deadlift; speed/
  close-grip/floor press ← horizontal anchors; jerk/overhead ← exact
  C&J or strict press; Olympic variants exact-first, low-confidence
  strength fallback), coefficients in data with tests, no substring
  matching. Methodology conversion per style; resume never auto-refreshes
  a suspended program.

  **Load quantization (separate layer, same phase).** The pipeline keeps
  capability and equipment strictly apart:

  ```text
  AthleteHistoryIndex
      ↓
  TrainingAnchorResolver     — gym-independent capability + provenance
      ↓
  methodology conversion     — training max / working cursor / percentages
      ↓
  LoadQuantizer / PlateMath  — gym + bar + denomination policy
      ↓
  session prescription
  ```

  The same history resolves to the same anchor regardless of selected
  gym; quantized loads are never persisted into `baseWeightLb` or any
  cursor (cursor rounding stays on the program's existing `roundingLb`).
  Implementation extends the EXISTING `PlateMath`/`Plates` policy in
  CadenceCore (+ core.js mirror) at the per-prescription call sites
  `ProgramSession.achievableWeight` and `achievableWarmups` — which
  already run for every generated session, so progressed loads and
  warmups both get the new policy, and warmups are distinguishable from
  near-max singles at that boundary. Policy changes: default denomination
  policy excludes 1.25s; warmups snap to large-plate-friendly loads only
  (130 → 135, never a 2.5); working sets within ±5 lb prefer fewest
  small plates per side (260 → 265 progressing, → 255 backing off);
  near-max singles/doubles keep full resolution. `Gym.plateToggles`
  records denomination availability, not counts, so the property test
  proves loads are constructible under the enabled-denomination model
  (unlimited pairs of enabled plates), not physical-rack availability;
  per-plate quantities are a possible later extension. Gate: parity
  tests for exact / related / family / default / bodyweight /
  per-implement dumbbell / shelved paths, plus the quantizer property
  test above.
- **P5 — Stage 4: explicit program switching.**
  `feat: add resumable program switcher and new-block flow`.
  `ProgramActivationService` + web mirror replaces direct `isActive`
  mutation in Settings. Three actions: resume existing (cursor untouched),
  start new block of this style, switch to another style (both
  instantiate from current global history via the resolver — no weight
  prompts). Rules: exactly one active program; inactive programs retain
  cycle/rotation/day/slot cursors/stalls/pending; open sessions stay
  attached to their creating program, never silently retagged; switching
  fails visibly rather than orphaning; activation only after successful
  persistence. UI: prominent switcher from Today/Home with anchor preview
  showing measured/estimated/default source; Settings stays the deep
  editor. Gate: A→B→A preserves A's exact cursor and all sessions.
- **P6 — Stage 5: history filters and comparison.**
  `feat: filter and compare all-time history by program style`.
  ProgressionChartsView + web: all programs (default) / one instance /
  one style across blocks / compare two. Uses session `programID` +
  `programTemplateID` snapshots, legacy name fallback for legacy rows
  only. Rotations view gets an explicit program selector — changing the
  active program never rewrites the matrix being read. Gate: one Back
  Squat history across three methodologies renders as one all-time
  series and isolates correctly.
- **P7 — Stage 6: banked-correction reconciliation.**
  `fix!: reconcile banked corrections with persisted progression state` —
  only if P1 proves a schema/journal is necessary. Always rebuild
  immediately: summaries, chart points, recall, exports, PR/milestone
  projection (regenerated deterministically, never appended), computed
  reports. Progression state: extract `SessionCompletion.advanceProgram`
  into a pure reducer first, then the smallest proven persistence
  boundary — current-cycle regrade, or a typed per-session checkpoint
  journal from a known baseline. New programs store a replay baseline;
  legacy programs get an explicit migration checkpoint; the UI never
  claims a legacy cursor was rebuilt when it was not. Gate: correct +
  rebuild twice → identical state, no duplicate advancement.
- **P8 — later, separate schema work** (own bumps, not part of V11):
  optional session purpose/group metadata (strength / technique /
  warmup-conditioning / conditioning / recovery — multiple sessions per
  date already work); an explicit warmup-conditioning role so a routine
  pre-lift 10-minute ruck or 20 flights is never a fatigue penalty or a
  failed prescription (track existing duration/distance/load/incline/
  flights; no second movement identity; no auto-escalation because it is
  repeatable); set-level `beltUsed`/`strapsUsed` with legacy nil =
  unknown, never false ("Belted Deadlift" is not a new exercise); belt
  guidance by relative intensity/effort (optional ~70–80% e1RM,
  increasingly useful 80%+/RPE 8+, beltless backoffs for bracing), as
  recommendations with an optional template gear policy — no
  bodyweight-ratio gates.

## File map, invariants, PR sequence

Owned by #155 (file map for shared core / native / web / tests / docs;
the seven INV-* invariants; the eight-PR sequence). This document does
not duplicate them; treat #155 as the source of truth for those lists.
The quantizer work modifies the existing `PlateMath.swift`/`Plates.swift`
(+ core.js mirror) and the `ProgramSession` call sites; its docs land with
`docs/reference/progression-rules.md`.

## Testing strategy

- Every stage gate above is the acceptance bar; stages ship only with
  their gate tests green on both suites.
- Pure engines (projection, resolver, quantizer, progression reducer) get
  mirrored CadenceCore + core.js cases and property-style coverage
  (quantizer inventory invariant, resolver order totality, rebuild
  idempotence).
- Persistence gates use real on-disk stores in CadenceMigrationTests and
  fake-indexeddb upgrade tests — fresh-store tests are insufficient.
- Synthetic fixtures only; no personal export is ever committed.

## Release train

- P0: individual `feat:`/`fix:`/`docs:` PRs, each CI-green,
  squash-merged with release-meaningful titles.
- P1–P2: `test:`/`fix:`/`refactor:` — no schema change, no major.
- P3: the one `feat!:` major of the epic's core; migration notes in the
  PR body; post-merge main run watched through TestFlight per doctrine.
- P4–P6: minors. P7: `fix!:` only if P1's inventory demands persisted
  change. P8: separate bumps when scheduled.
- Every phase: Linux parse gate → macOS jobs → migration scheme when
  persistence is touched, on the exact head commit; both mirrored suites
  green.
