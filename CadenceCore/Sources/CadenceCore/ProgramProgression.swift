import Foundation

/// Cross-cycle, performance-gated progression for program lifts. It adds a
/// proportional increment on a clean cycle and auto-deloads on repeated stalls,
/// so weight is never added blindly. Pure & deterministic — consumes a performance
/// SUMMARY (never a session), no clock/random. Mirrored 1:1 in web/app/js/core.js.

public enum CycleGrade: String, Codable, Sendable { case success, hold, fail }

public enum TrainingFocus: String, Codable, Sendable {
    case strength, hypertrophy, maintain

    /// Training-max ceiling as a fraction of estimated 1RM.
    public var tmFraction: Double {
        switch self {
        case .strength: return 0.90
        case .hypertrophy: return 0.78
        case .maintain: return 0.0
        }
    }

    /// Per-cycle increment as a fraction of the current base weight.
    public var incrementFraction: Double {
        switch self {
        case .strength: return 0.025
        case .hypertrophy: return 0.015
        case .maintain: return 0.0
        }
    }
}

public enum LiftRole: String, Codable, Sendable { case main, complementary }

/// What the core consumes about a lift's KEY work (the Peak / week-3 top sets).
/// Built by the data layer from logged sets; never holds a session or a clock.
public struct CycleLiftPerformance: Hashable, Sendable {
    public var prescribedSets: Int
    public var prescribedReps: Int
    public var completedSets: Int          // sets that met or beat target reps
    public var anyStoppedEarly: Bool
    public var anyDroppedLoad: Bool        // a working set carried an autoreg reason
    public var anyBelowPlanLoad: Bool      // a working set measured below plan (see belowPlanLoad)
    public var grindyOrWobbleSets: Int
    public var topSetWeightLb: Double
    public var topSetReps: Int
    /// What the strength sample was PLANNED at, so the advance can see how far
    /// above plan it was actually performed. 0 = unknown (legacy callers), and
    /// the overshoot path stays off.
    public var plannedTopWeightLb: Double

    public init(prescribedSets: Int, prescribedReps: Int, completedSets: Int, anyStoppedEarly: Bool,
                anyDroppedLoad: Bool, anyBelowPlanLoad: Bool = false, grindyOrWobbleSets: Int,
                topSetWeightLb: Double, topSetReps: Int, plannedTopWeightLb: Double = 0) {
        self.prescribedSets = prescribedSets
        self.prescribedReps = prescribedReps
        self.completedSets = completedSets
        self.anyStoppedEarly = anyStoppedEarly
        self.anyDroppedLoad = anyDroppedLoad
        self.anyBelowPlanLoad = anyBelowPlanLoad
        self.grindyOrWobbleSets = grindyOrWobbleSets
        self.topSetWeightLb = topSetWeightLb
        self.topSetReps = topSetReps
        self.plannedTopWeightLb = plannedTopWeightLb
    }
}

/// Per-lift progression state owned by a program (main/complementary lift).
public struct ProgramLiftState: Codable, Hashable, Sendable {
    public var baseWeightLb: Double        // week-1 volume weight (drives planFor)
    public var estimatedMaxLb: Double      // smoothed Epley e1RM
    public var stallCount: Int             // consecutive non-success cycles
    public var role: LiftRole
    public var lastIncrementLb: Double

    public init(baseWeightLb: Double, estimatedMaxLb: Double, stallCount: Int = 0,
                role: LiftRole = .main, lastIncrementLb: Double = 0) {
        self.baseWeightLb = baseWeightLb
        self.estimatedMaxLb = estimatedMaxLb
        self.stallCount = stallCount
        self.role = role
        self.lastIncrementLb = lastIncrementLb
    }
}

public struct ProgressionResult: Sendable {
    public let state: ProgramLiftState
    public let grade: CycleGrade
    public let note: String?
}

/// The minimum information needed to choose representative recovery
/// exposures from an authored program day. `order` is the persisted schedule
/// address; only the MAIN lift's movement group participates, so an accessory
/// cannot accidentally turn an upper day into a lower day (or vice versa).
public struct RecoveryDayCandidate: Hashable, Sendable {
    public let order: Int
    public let mainMovementGroup: String?

    public init(order: Int, mainMovementGroup: String?) {
        self.order = order
        self.mainMovementGroup = mainMovementGroup
    }
}

/// Why a bounded recovery bridge is ready to hand off to the next cycle.
/// The elapsed-time case is only an expiry guard; it does not make a
/// cycle-based program advance by calendar weeks.
public enum RecoveryBridgeCompletionReason: String, Hashable, Sendable {
    case selectedExposures
    case sessionLimit
    case windowElapsed
}

/// Accessory double-progression state (rep range → weight).
public struct AccessoryState: Codable, Hashable, Sendable {
    public var sets: Int
    public var minReps: Int
    public var maxReps: Int
    public var currentReps: Int
    public var weightLb: Double
    public var incrementLb: Double
    public var stallCount: Int

    public init(sets: Int, minReps: Int, maxReps: Int, currentReps: Int,
                weightLb: Double, incrementLb: Double, stallCount: Int = 0) {
        self.sets = sets
        self.minReps = minReps
        self.maxReps = maxReps
        self.currentReps = currentReps
        self.weightLb = weightLb
        self.incrementLb = incrementLb
        self.stallCount = stallCount
    }
}

public struct AccessoryPerformance: Hashable, Sendable {
    public var completedSets: Int
    public var minRepsAchieved: Int        // lowest rep count across the working sets
    public var anyStoppedEarly: Bool
    public var performedAtPlannedLoad: Bool
    public var grindyOrWobbleSets: Int
    public var bodyFlagSets: Int

    public init(completedSets: Int, minRepsAchieved: Int, anyStoppedEarly: Bool,
                performedAtPlannedLoad: Bool = true, grindyOrWobbleSets: Int = 0,
                bodyFlagSets: Int = 0) {
        self.completedSets = completedSets
        self.minRepsAchieved = minRepsAchieved
        self.anyStoppedEarly = anyStoppedEarly
        self.performedAtPlannedLoad = performedAtPlannedLoad
        self.grindyOrWobbleSets = grindyOrWobbleSets
        self.bodyFlagSets = bodyFlagSets
    }
}

public enum ProgramProgression {
    public static let qualityFlagTolerance = 1     // ≤1 grindy/wobble set still SUCCESS
    public static let stallLimit = 2               // 2 consecutive non-success → auto deload
    public static let deloadRebuildFraction = 0.90

    /// Persisted phase value for the recovery bridge. 1–3 are full volume,
    /// load, and peak rotations; phase 4 is not another complete rotation.
    public static let deloadWeek = 4
    /// Recovery is deliberately smaller than a full authored rotation.
    public static let recoverySessionLimit = 2
    /// Maximum elapsed time after the last hard-phase completion during which
    /// Cadence may prescribe another recovery workout.
    public static let recoveryWindow: TimeInterval = 7 * 24 * 60 * 60
    /// Complete rotations that must be banked since the last recovery bridge
    /// before another early one is allowed. Without a floor a run of red
    /// rotations turns recovery into the schedule, which is the
    /// opposite of what it is for.
    ///
    /// Counted in ROTATIONS, not sessions. A session floor silently scales with
    /// the split: eight sessions is two rotations of a four-day program but
    /// four rotations of a two-day one, and is simply unreachable inside a
    /// cycle for any rotation of three days or fewer — which disabled the
    /// feature outright on half the shipped templates.
    public static let minimumRotationsBetweenDeloads = 2

    /// Whether to cut this cycle short and go straight to recovery.
    ///
    /// Persistent red, not a single red: one bad rotation is noise, and the
    /// single-red answer (a temporary accessory-set cut) is already cheaper and
    /// reversible. Rotations 1 and 2 only — from rotation 3 the schedule
    /// advances into recovery by itself, so there is nothing to skip.
    public static func shouldDeloadEarly(
        currentWeek: Int,
        readiness: ReadinessState,
        previousReadiness: ReadinessState,
        rotationsSinceLastDeload: Int
    ) -> Bool {
        guard currentWeek >= 1, currentWeek < deloadWeek - 1 else { return false }
        guard readiness == .red, previousReadiness == .red else { return false }
        return rotationsSinceLastDeload >= minimumRotationsBetweenDeloads
    }

    /// The rotation whose top work decides the cycle's progression.
    public static let gradedWeek = 3

    /// An e1RM observation from a rotation that is NOT the graded one.
    ///
    /// The graded rotation is a test, so it moves the estimate in either
    /// direction. Every other rotation prescribes deliberately submaximal work
    /// — a light set is not evidence the max fell, it is evidence the program
    /// asked for less. So only a sample that BEATS the standing estimate says
    /// anything, and it still smooths rather than jumping.
    ///
    /// This is what lets a capped AMRAP on the load rotation feed the engine.
    /// It also matters for the training-max ceiling: an estimate derived from
    /// the peak set is a fixed multiple of the base it is meant to bound, and
    /// therefore never binds. A load-rotation sample is earned reps at a weight
    /// the peak did not set, which is the independent anchor it has lacked.
    public static func observedMax(prior: Double, sample: Double) -> Double {
        guard sample > prior else { return prior }
        return smoothE1RM(prior: prior, sample: sample)
    }

    /// The state a cycle-graded slot carries out of a cycle the program cut
    /// short for recovery.
    ///
    /// The lifter did not miss a peak — the peak never ran — so the base holds
    /// and no stall accrues. It is written into the same pending group a real
    /// peak grade uses, so the rollover applies it through its existing path
    /// and never reaches the skipped-peak stall branch.
    public static func recoveryDeloadHold(
        _ state: ProgramLiftState, atWeek week: Int
    ) -> ProgressionResult {
        var next = state
        next.lastIncrementLb = 0
        return ProgressionResult(
            state: next,
            grade: .hold,
            note: "Recovery bridge — output stayed red, so the cycle stopped after rotation \(week) and went straight to recovery. The base holds."
        )
    }

    public static func epleyE1RM(weightLb: Double, reps: Int) -> Double {
        reps >= 1 ? weightLb * (1 + Double(reps) / 30.0) : weightLb
    }

    /// Epley is accurate at roughly 2–10 reps and drifts high above that, so a
    /// long back-off set is not allowed to masquerade as a strength sample.
    public static let e1RMSampleRepCeiling = 10

    /// Which performed set is the cycle's strength sample.
    ///
    /// Heaviest-first is the intuitive answer and it is wrong: it makes an
    /// as-many-reps-as-possible set at the top weight invisible, because the
    /// first set at that weight wins the tie and the extra reps are discarded.
    /// A lifter who takes the last set to 8 instead of the prescribed 3 has
    /// produced the single best estimate of the cycle, and the engine has been
    /// throwing it away.
    ///
    /// Ranking by Epley fixes that and cannot be fooled by back-off volume —
    /// 135×10 estimates 180 lb and loses to 215×3's 236.5 — as long as reps
    /// stay inside the formula's accurate range, which is what the ceiling is
    /// for. When every set is a long one there is nothing better available, so
    /// the whole pool is ranked anyway rather than reporting no sample at all.
    public static func strengthSampleIndex(weightsLb: [Double], reps: [Int]) -> Int? {
        let count = Swift.min(weightsLb.count, reps.count)
        guard count > 0 else { return nil }
        let indexes = Array(0..<count)
        let short = indexes.filter { reps[$0] <= e1RMSampleRepCeiling }
        let pool = short.isEmpty ? indexes : short
        return pool.max {
            epleyE1RM(weightLb: weightsLb[$0], reps: reps[$0])
                < epleyE1RM(weightLb: weightsLb[$1], reps: reps[$1])
        }
    }

    public static func smoothE1RM(prior: Double, sample: Double) -> Double {
        prior <= 0 ? sample : 0.7 * prior + 0.3 * sample
    }

    public static func gradeCycle(_ perf: CycleLiftPerformance) -> CycleGrade {
        if perf.completedSets < perf.prescribedSets || perf.anyStoppedEarly || perf.anyDroppedLoad
            || perf.anyBelowPlanLoad { return .fail }
        if perf.grindyOrWobbleSets > qualityFlagTolerance { return .hold }
        return .success
    }

    /// A standalone lift track advances once per banked exposure only when
    /// every occurrence of that lift met its original prescription. This keeps
    /// session-local rep/load edits as performed history without letting a
    /// lighter or incomplete workout silently raise the next goal. Multiple
    /// occurrences are one lift exposure, not multiple progression events.
    public static func earnsStandaloneTrackAdvance(_ performances: [CycleLiftPerformance]) -> Bool {
        !performances.isEmpty && performances.allSatisfy { gradeCycle($0) == .success }
    }

    /// Whether a working set's actual load fell below its prescription. Reps at
    /// a reduced weight must not grade as a clean success — that would reset the
    /// stall counter and bump the base weight off work that wasn't done. The
    /// tolerance is HALF a plate-rounding step: within it counts as met (float
    /// noise, kg-entry conversions), a full step down is a genuine drop. Applies
    /// to manual edits and autoreg drops alike; heavier than planned is always
    /// fine; no prescription (nil/zero plan) means nothing to compare against.
    public static func belowPlanLoad(
        actualLb: Double, plannedLb: Double?,
        roundingLb: Double = ProgramEngine.defaultRoundingLb
    ) -> Bool {
        guard let planned = plannedLb, planned > 0 else { return false }
        return actualLb < planned - roundingLb / 2
    }

    /// Aggregate for a whole lift: the prescription is met when at least
    /// `prescribedSets` working sets are at the planned load. Extra sets beyond
    /// the prescription are bonus volume — a lighter back-off set after
    /// completing the planned work must not fail the cycle. Fewer at-plan sets
    /// than prescribed (whole lift performed light, or one prescribed set cut
    /// down) is below plan.
    public static func belowPlanWork(
        weightsLb: [Double], plannedLb: Double?, prescribedSets: Int,
        roundingLb: Double = ProgramEngine.defaultRoundingLb
    ) -> Bool {
        guard let planned = plannedLb, planned > 0 else { return false }
        let atPlan = weightsLb.filter { !belowPlanLoad(actualLb: $0, plannedLb: planned, roundingLb: roundingLb) }.count
        return atPlan < prescribedSets
    }

    /// A banked session may only advance the program if its tag (captured at
    /// creation) still matches the program's live position — otherwise it's a
    /// duplicate or stale session and must be kept as history without moving
    /// the schedule a second time (issue 17: banking two copies of a week's
    /// final day skipped a whole week).
    public static func sessionTagCurrent(
        tagCycle: Int, tagWeek: Int, tagDayIndex: Int,
        cycleNumber: Int, currentWeek: Int, nextDayIndex: Int
    ) -> Bool {
        tagCycle == cycleNumber && tagWeek == currentWeek && tagDayIndex == nextDayIndex
    }

    /// Whether an OPEN session may be resumed when the user (re)starts a
    /// program day, rather than building a fresh one. It must be tagged for
    /// the SAME cycle/week/day AND the plan it was BUILT from must still equal
    /// the day's CURRENT plan.
    ///
    /// The comparison is snapshot-vs-current-plan, NOT the session's live
    /// exercises: a session-local remove or a "just this session" swap changes
    /// the live exercises but not the built-from plan, so that customized
    /// session is still resumed (its edits preserved). Only a PROGRAM edit
    /// (swap/add/remove in the editor) or a position move diverges the
    /// built-from plan from the current one → build fresh, never resurface the
    /// stale content. `sessionPlanNames` empty (a pre-snapshot session) never
    /// resumes.
    public static func canResumeSession(
        tagCycle: Int, tagWeek: Int, tagDayIndex: Int,
        cycleNumber: Int, currentWeek: Int, dayIndex: Int,
        sessionPlanNames: [String], dayPlanNames: [String]
    ) -> Bool {
        tagCycle == cycleNumber && tagWeek == currentWeek && tagDayIndex == dayIndex
            && !sessionPlanNames.isEmpty && sessionPlanNames == dayPlanNames
    }

    /// Where the schedule goes after banking the day with `bankedDayOrder`.
    ///
    /// Day `order` values ADDRESS the rotation — `nextDayIndex` holds an order,
    /// not a position — but they are not guaranteed to be the contiguous
    /// 0..n-1 that index-space arithmetic (`(index + 1) % count`) assumes.
    /// Import validates day orders as unique and never as contiguous, and the
    /// native `days` relationship can still carry aliases in shipped stores. A
    /// gap made the last day unrecognizable: the week stopped advancing, the
    /// cycle never rolled over, every stashed Peak grade sat unapplied, and any
    /// day past the gap became unreachable. Walking the sorted orders is
    /// correct for both the tidy and the damaged case.
    ///
    /// Duplicate orders are collapsed first: two DISTINCT days can share one
    /// order (a damaged store, or an add that collided on `days.count`), and
    /// stepping within a duplicate pair would advance an order to itself and
    /// strand the schedule exactly like the gap this function exists to fix.
    ///
    /// An unknown `bankedDayOrder` (a stale tag, a deleted day) reports the
    /// last day so a rotation can still close, and points at the first day.
    /// Mirrored 1:1 in web/app/js/core.js `scheduleAdvance`.
    public static func scheduleAdvance(
        dayOrders: [Int], bankedDayOrder: Int
    ) -> (nextDayOrder: Int, isLastDay: Bool) {
        let sorted = Array(Set(dayOrders)).sorted()
        guard let position = sorted.firstIndex(of: bankedDayOrder) else {
            return (sorted.first ?? 0, true)
        }
        return (sorted[(position + 1) % sorted.count], position == sorted.count - 1)
    }

    /// Recovery completion is set-based, not pointer-based. The bridge may be
    /// banked in either order, and a program upgraded while already in phase 4
    /// may point at a day omitted by the shortened bridge. Count the selected
    /// exposures actually banked in this cycle, then choose the first missing
    /// authored order. Unknown/non-bridge days never count by themselves.
    /// Mirrored 1:1 in web/app/js/core.js `recoveryScheduleAdvance`.
    public static func recoveryScheduleAdvance(
        dayOrders: [Int], completedDayOrders: [Int]
    ) -> (nextDayOrder: Int, isLastDay: Bool) {
        let selected = Array(Set(dayOrders)).sorted()
        guard !selected.isEmpty else { return (0, false) }
        let completed = Set(completedDayOrders)
        if let next = selected.first(where: { !completed.contains($0) }) {
            return (next, false)
        }
        return (selected[0], true)
    }

    /// Decide whether recovery has done its job.
    ///
    /// Selected representative exposures still close a short bridge normally.
    /// Independently, two banked recovery sessions are a hard cap even when
    /// an old/manual pointer sent those sessions to non-selected day orders.
    /// Finally, the bridge expires after seven elapsed days from the last Peak
    /// (or other hard-phase anchor supplied by the persistence edge), so a
    /// stale Recovery pointer can never prescribe reduced work indefinitely.
    /// Mirrored 1:1 in web/app/js/core.js `recoveryBridgeCompletionReason`.
    public static func recoveryBridgeCompletionReason(
        completedRecoverySessions: Int,
        selectedExposureCount: Int,
        selectedExposuresComplete: Bool,
        lastHardPhaseCompletion: Date?,
        asOf now: Date
    ) -> RecoveryBridgeCompletionReason? {
        if selectedExposuresComplete { return .selectedExposures }
        // The cap is the BRIDGE'S OWN LENGTH, not a constant two. A program
        // that is not recognizably upper/lower keeps its full authored pass —
        // that fallback is deliberate, and capping it at two silently dropped
        // day three onward for full-body, Olympic and conditioning programs,
        // which is the work-losing behaviour the fallback exists to prevent.
        let cap = Swift.max(recoverySessionLimit, selectedExposureCount)
        if completedRecoverySessions >= cap { return .sessionLimit }
        // Recovery is a bounded bridge from the last hard phase, not a new
        // calendar window that starts when reduced work is banked. Otherwise a
        // first recovery exposure on day six silently extends the bridge to day
        // thirteen, and an untouched recovery pointer can prescribe reduced
        // work forever. Manual positioning remains available, but it does not
        // override the stale-bridge guard implicitly.
        guard let anchor = lastHardPhaseCompletion,
              now.timeIntervalSince(anchor) >= recoveryWindow else { return nil }
        return .windowElapsed
    }

    /// Select one authored lower and one authored upper exposure for the
    /// phase-4 recovery bridge.
    ///
    /// This is deliberately movement-driven rather than name-driven: "Day A"
    /// and localized/custom day names are valid, while the main lift already
    /// carries the structural signal we need. The first authored representative
    /// of each half is retained and their original schedule order is preserved.
    ///
    /// Programs that are not recognizably upper/lower fall back to their full
    /// authored order. That preserves existing behavior for Olympic, full-body,
    /// conditioning-only, damaged, and otherwise ambiguous programs instead of
    /// silently dropping work based on a guess.
    /// Mirrored 1:1 in web/app/js/core.js `recoveryDayOrders`.
    public static func recoveryDayOrders(_ candidates: [RecoveryDayCandidate]) -> [Int] {
        let sorted = candidates.sorted { $0.order < $1.order }
        let allOrders = Array(Set(sorted.map(\.order))).sorted()
        let group: (RecoveryDayCandidate) -> String = {
            $0.mainMovementGroup?.lowercased() ?? ""
        }
        guard let lower = sorted.first(where: { ["squat", "hinge"].contains(group($0)) }),
              let upper = sorted.first(where: { ["press", "pull"].contains(group($0)) }),
              lower.order != upper.order else {
            return allOrders
        }
        let selected = Set([lower.order, upper.order])
        return allOrders.filter { selected.contains($0) }
    }

    /// Increment = fraction of base, floored at plate granularity.
    ///
    /// This used to scale by headroom to a training-max ceiling
    /// (`estimatedMax × tmFraction`) and clamp to 0 at the cap. Both were
    /// removed, because measurement showed the taper never tapered and the
    /// ceiling could not bind:
    ///
    /// - Across 10,560 realistic (base, e1RM) pairs the function returned
    ///   exactly two values, 0 or `roundingLb`, and nothing in between.
    ///   `base × 0.025 × headroom` is a fraction of a pound at every realistic
    ///   load, so it floored to zero and the "guarantee a loadable bump" rescue
    ///   put it straight back to a full plate step. The headroom term's only
    ///   observable effect was a cliff at `headroom ≤ 0.02`.
    /// - That cliff was unreachable on the path that matters. A clean peak
    ///   feeds `smoothedMax` with `1.175 × base`, which outruns a `0.90 × e1RM`
    ///   ceiling by construction — traced over seven clean cycles, headroom
    ///   RISES (0.047 → 0.070) as the base climbs. A ceiling derived from the
    ///   base cannot bound the base.
    ///
    /// Base drift is bounded by performance instead, which is what the
    /// published systems do: `stallLimit` consecutive non-success cycles
    /// rebuild at `deloadRebuildFraction`. `TrainingFocus.tmFraction` stays —
    /// `ProgramEngine` seeds peak singles from it and `defaultStartFraction`
    /// uses it to place a new program's base.
    ///
    /// Mirrored 1:1 in web/app/js/core.js `focusIncrement`.
    public static func focusIncrement(
        baseWeightLb: Double, focus: TrainingFocus,
        roundingLb: Double = ProgramEngine.defaultRoundingLb
    ) -> Double {
        guard focus.incrementFraction > 0, baseWeightLb > 0, roundingLb > 0 else { return 0 }
        let raw = baseWeightLb * focus.incrementFraction
        let stepped = (raw / roundingLb).rounded(.down) * roundingLb
        // A clean cycle always earns at least one loadable step; anything less
        // is not a prescription anyone can put on a bar.
        return Swift.max(roundingLb, stepped)
    }

    public static func advanceCycleLift(
        _ state: ProgramLiftState, perf: CycleLiftPerformance, focus: TrainingFocus,
        roundingLb: Double = ProgramEngine.defaultRoundingLb
    ) -> ProgressionResult {
        let grade = gradeCycle(perf)
        let estimatedMaxLb = smoothedMax(state, perf: perf)
        var next = state
        next.estimatedMaxLb = estimatedMaxLb
        var note: String?

        if grade == .success {
            next.stallCount = 0
            let inc = focusIncrement(baseWeightLb: state.baseWeightLb, focus: focus, roundingLb: roundingLb)
            // Progression rides performed values, not the stale programmed
            // base. The grade fires at the Peak, whose top set is base-× by
            // design — so the performed weight cannot feed the base directly;
            // its OVERSHOOT ratio over its own plan can. A lifter whose rack
            // lands them a stack above plan every session (kg plates on lb
            // prescriptions) trains ahead of the base, and advancing the
            // stale number handed them back a fraction of the increment.
            //
            // Guards: only ABOVE plan (below already fails the grade; equal is
            // ratio 1), only past the same half-step tolerance the grade
            // itself uses (float noise and near-misses are not a training
            // signal), and never downward.
            var advancedFrom = state.baseWeightLb
            if perf.plannedTopWeightLb > 0,
               perf.topSetWeightLb - perf.plannedTopWeightLb >= roundingLb / 2 {
                advancedFrom = Swift.max(
                    state.baseWeightLb,
                    state.baseWeightLb * (perf.topSetWeightLb / perf.plannedTopWeightLb)
                )
            }
            next.baseWeightLb = advancedFrom + inc
            next.lastIncrementLb = inc
            if advancedFrom > state.baseWeightLb {
                note = "Clean peak, performed above plan — base rides the \(Weight.trim(advancedFrom - state.baseWeightLb)) lb overshoot, then +\(Weight.trim(inc)) lb."
            } else if inc > 0 {
                note = "Clean peak — add \(Weight.trim(inc)) lb next cycle."
            } else {
                note = "Maintaining — holding weight."
            }
        } else {
            next.stallCount = state.stallCount + 1
            next.lastIncrementLb = 0
            if next.stallCount >= stallLimit {
                let old = next.baseWeightLb
                next.baseWeightLb = Weight.round(old * deloadRebuildFraction, to: roundingLb)
                next.stallCount = 0
                note = "Two cycles without a clean peak — deloaded \(Weight.trim(old))→\(Weight.trim(next.baseWeightLb)) lb to rebuild."
            } else {
                note = grade == .fail ? "Missed peak work — holding weight, retry the cycle."
                                      : "Grindy peak — holding weight, retry the cycle."
            }
        }
        return ProgressionResult(state: next, grade: grade, note: note)
    }

    /// Per-exposure linear rule for the methodology styles that add weight
    /// every time the slot's work is completed as prescribed.
    ///
    /// - Novice linear fives: +10 lb per exposure for squat/hinge patterns,
    ///   +5 lb for everything else; three consecutive misses deload 10%
    ///   (Starting Strength's reset). Repeated slots of the same lift are
    ///   synchronized by the banking layer, so "weight every session" holds
    ///   across alternating A/B days.
    /// - Texas day slots: +5 lb per completion for every lift — with the A/B
    ///   twin slots synchronized, that is the published +5 lb/week (and +5
    ///   per appearance for the weekly-alternating presses); two misses
    ///   reset 5%.
    public struct LinearRule: Hashable, Sendable {
        public let incrementLb: Double
        public let stallLimit: Int
        public let deloadFraction: Double

        public init(incrementLb: Double, stallLimit: Int, deloadFraction: Double) {
            self.incrementLb = incrementLb
            self.stallLimit = stallLimit
            self.deloadFraction = deloadFraction
        }
    }

    public static func linearRule(for style: PrescriptionStyle, movementGroup: String?) -> LinearRule {
        let lower = movementGroup == "squat" || movementGroup == "hinge"
        switch style {
        case .linearFives:
            return LinearRule(incrementLb: lower ? 10 : 5, stallLimit: 3, deloadFraction: 0.90)
        default:
            return LinearRule(incrementLb: 5, stallLimit: 2, deloadFraction: 0.95)
        }
    }

    /// Advance a per-exposure linear slot after a banked session. Success adds
    /// the rule's fixed increment; misses hold, and `stallLimit` consecutive
    /// misses deload by the rule's fraction and restart the count. The e1RM
    /// smooths from the top set (fives are honest samples).
    /// A performed top set that actually happened. A skipped or fully-missed
    /// top set reports weight/reps 0; smoothing that into the e1RM would crush
    /// the estimate by 30% per occurrence, so only real samples smooth.
    static func smoothedMax(_ state: ProgramLiftState, perf: CycleLiftPerformance) -> Double {
        guard perf.topSetWeightLb > 0, perf.topSetReps >= 1 else { return state.estimatedMaxLb }
        let sample = epleyE1RM(weightLb: perf.topSetWeightLb, reps: perf.topSetReps)
        return smoothE1RM(prior: state.estimatedMaxLb, sample: sample)
    }

    public static func advanceLinearLift(
        _ state: ProgramLiftState, perf: CycleLiftPerformance, rule: LinearRule,
        roundingLb: Double = ProgramEngine.defaultRoundingLb
    ) -> ProgressionResult {
        let grade = gradeCycle(perf)
        var next = state
        next.estimatedMaxLb = smoothedMax(state, perf: perf)
        var note: String?

        switch grade {
        case .success:
            next.stallCount = 0
            next.baseWeightLb = state.baseWeightLb + rule.incrementLb
            next.lastIncrementLb = rule.incrementLb
            note = "Completed as prescribed — add \(Weight.trim(rule.incrementLb)) lb next time."
        case .hold:
            // Grindy but every rep was made. The published novice rule is to
            // grind and keep adding; the conservative middle is to hold the
            // weight WITHOUT accruing a miss — and a completed session breaks
            // the consecutive-miss chain, so the deload note stays truthful.
            next.stallCount = 0
            next.lastIncrementLb = 0
            note = "Grindy session — holding weight; misses were not counted."
        case .fail:
            next.stallCount = state.stallCount + 1
            next.lastIncrementLb = 0
            if next.stallCount >= rule.stallLimit {
                let old = state.baseWeightLb
                next.baseWeightLb = Weight.round(old * rule.deloadFraction, to: roundingLb)
                next.stallCount = 0
                note = "Missed \(rule.stallLimit) in a row — deloaded \(Weight.trim(old))→\(Weight.trim(next.baseWeightLb)) lb to rebuild."
            } else {
                note = "Prescription not fully met — holding weight, try it again."
            }
        }
        return ProgressionResult(state: next, grade: grade, note: note)
    }

    /// Style-aware cycle progression, applied at the Peak grade / rollover for
    /// slots that are NOT per-exposure. Methodology styles use their published
    /// fixed increments; every other style keeps the proportional rule.
    ///
    /// - 5/3/1: +5 lb upper / +10 lb lower to the training max per clean
    ///   cycle; missing the "+" set's minimum resets the TM three cycles back
    ///   (Wendler's "five steps forward, three steps back").
    /// - Max effort: +5/+10 to the target after a made single; a miss holds —
    ///   Westside answers stalls by rotating the variation (the swap gesture),
    ///   never by auto-raising a missed target.
    /// - Dynamic effort: speed weight follows the slot's max; the base holds
    ///   and the wave supplies intra-cycle progression.
    public static func advanceProgramLift(
        _ state: ProgramLiftState, perf: CycleLiftPerformance, focus: TrainingFocus,
        style: PrescriptionStyle, movementGroup: String?,
        roundingLb: Double = ProgramEngine.defaultRoundingLb
    ) -> ProgressionResult {
        let lower = movementGroup == "squat" || movementGroup == "hinge"
        let increment = lower ? 10.0 : 5.0
        switch style {
        case .fiveThreeOne:
            let grade = gradeCycle(perf)
            var next = state
            next.estimatedMaxLb = smoothedMax(state, perf: perf)
            var note: String?
            if grade == .success {
                next.stallCount = 0
                next.baseWeightLb = state.baseWeightLb + increment
                next.lastIncrementLb = increment
                note = "Hit the top set — training max +\(Weight.trim(increment)) lb next cycle."
            } else if grade == .fail, perf.completedSets < perf.prescribedSets {
                // Wendler's reset applies only to genuinely missing the "+"
                // set's minimum reps. A fail from an autoreg drop or a light
                // manual edit made the reps at reduced load — that holds.
                let old = state.baseWeightLb
                next.baseWeightLb = Swift.max(roundingLb, Weight.round(old - 3 * increment, to: roundingLb))
                next.stallCount = 0
                next.lastIncrementLb = 0
                note = "Missed the minimum reps — training max reset \(Weight.trim(old))→\(Weight.trim(next.baseWeightLb)) lb (three cycles back)."
            } else {
                next.stallCount = state.stallCount + 1
                next.lastIncrementLb = 0
                if grade == .fail, next.stallCount >= stallLimit {
                    // Repeated compromised "+" sets mean the TM is set too
                    // high even though the reps are technically appearing —
                    // apply the same three-cycles-back correction and consume
                    // the counter.
                    let old = state.baseWeightLb
                    next.baseWeightLb = Swift.max(roundingLb, Weight.round(old - 3 * increment, to: roundingLb))
                    next.stallCount = 0
                    note = "Two compromised cycles — training max reset \(Weight.trim(old))→\(Weight.trim(next.baseWeightLb)) lb (three cycles back)."
                } else {
                    note = grade == .fail
                        ? "Top set compromised — holding the training max this cycle."
                        : "Grindy top set — holding the training max this cycle."
                }
            }
            return ProgressionResult(state: next, grade: grade, note: note)
        case .maxEffort:
            let grade = gradeCycle(perf)
            var next = state
            next.estimatedMaxLb = smoothedMax(state, perf: perf)
            var note: String?
            if grade == .success {
                next.stallCount = 0
                next.baseWeightLb = state.baseWeightLb + increment
                next.lastIncrementLb = increment
                note = "Made the top single — next target +\(Weight.trim(increment)) lb. Rotate the variation to keep it moving."
            } else {
                // Rotation, not accumulation, is this methodology's stall
                // answer — no counter accrues (a stale count would detonate a
                // spurious deload if the slot is later switched to a wave style).
                next.lastIncrementLb = 0
                note = "Missed the single — holding the target. Swap the variation rather than grinding the same lift."
            }
            return ProgressionResult(state: next, grade: grade, note: note)
        case .dynamicEffort:
            // Speed doubles are not an e1RM sample; leave the estimate alone.
            var next = state
            next.lastIncrementLb = 0
            return ProgressionResult(
                state: next, grade: gradeCycle(perf),
                note: "Speed work holds — raise this slot when the max-effort lift moves."
            )
        default:
            return advanceCycleLift(state, perf: perf, focus: focus, roundingLb: roundingLb)
        }
    }

    /// Whether an accessory slot is CARRYING load it can never add to.
    ///
    /// `advanceAccessory` uses `incrementLb > 0` as its entire test for "is
    /// this slot weighted?". That is correct for bodyweight and timed work,
    /// which progress by reps or duration and have no load to add. But a slot
    /// holding a real working weight with a zero increment falls into the same
    /// branch: it climbs reps forever, past its own `maxReps`, and the weight
    /// never moves no matter how well the sets go.
    ///
    /// `weightLb > 0` is what makes this a misconfiguration rather than a
    /// choice. A zero weight with a zero increment is the documented way to say
    /// "no external load" — it is the default every newly added accessory
    /// starts at, and the web editor labels the field "Load step
    /// (0 = bodyweight)". Flagging that would fire on every slot the moment it
    /// was created, before the lifter had configured anything.
    ///
    /// Timed and conditioning work is excluded for the same reason in reverse:
    /// a plank progresses by `durationStepSeconds`, so a zero increment there
    /// is correct even when the slot carries a weight vest.
    ///
    /// Mirrored 1:1 in web/app/js/core.js `accessoryCannotProgressLoad`.
    public static func accessoryCannotProgressLoad(
        exerciseType: String?, loadBasis: LoadBasis, weightLb: Double, incrementLb: Double
    ) -> Bool {
        // Reps- and duration-progressed work has no load to step.
        //
        // An explicit external basis outranks the equipment type, but ONLY for
        // bodyweight: a weighted pull-up is typed bodyweight while hanging real
        // plates from a belt, and the type guard alone silently exempted it
        // from this warning, so a belt slot with a zero increment would never
        // progress and never say so. Timed and conditioning stay unloadable
        // whatever they carry — a weight-vest plank still progresses by
        // duration, which is what the zero increment there means.
        let type = exerciseType?.lowercased() ?? ""
        let unloadable = type == "timed" || type == "conditioning"
            || (type == "bodyweight" && !loadBasis.supportsLoadPR)
        guard !unloadable else { return false }
        guard loadBasis != .bodyweight else { return false }
        return weightLb > 0 && incrementLb <= 0
    }

    /// Whether the next session is landing sooner than the program's preferred
    /// spacing, and by how much.
    ///
    /// `preferredSessionSpacingDays` was previously write-only: a stepper set
    /// it, the coach's shorter-spacing trial wrote it, and nothing ever read it
    /// back. A preference the app collects and then ignores is worse than not
    /// asking. This is advisory only — it never blocks a session, because the
    /// lifter's calendar beats the app's opinion.
    ///
    /// Returns nil when there is nothing useful to say: no prior session, no
    /// preference recorded, or the gap is already met.
    /// Mirrored 1:1 in web/app/js/core.js `sessionSpacingShortfall`.
    public static func sessionSpacingShortfall(daysSinceLastSession: Int?, preferredDays: Int) -> Int? {
        guard preferredDays > 0, let elapsed = daysSinceLastSession, elapsed >= 0 else { return nil }
        let shortfall = preferredDays - elapsed
        return shortfall > 0 ? shortfall : nil
    }

    /// Accessory double progression: earn the top of the rep range across all
    /// sets, then add the smallest increment and reset reps. Never adds weight
    /// that wasn't earned.
    public static func advanceAccessory(_ state: AccessoryState, perf: AccessoryPerformance) -> AccessoryState {
        var next = state
        let hitAll = perf.completedSets >= state.sets && perf.minRepsAchieved >= state.currentReps
            && !perf.anyStoppedEarly && perf.performedAtPlannedLoad
            && perf.grindyOrWobbleSets <= qualityFlagTolerance && perf.bodyFlagSets == 0
        let weighted = state.incrementLb > 0
        if !hitAll {
            next.stallCount = state.stallCount + 1
        } else if weighted && state.currentReps >= state.maxReps {
            next.weightLb = state.weightLb + state.incrementLb   // earned the rep range → add load, reset reps
            next.currentReps = state.minReps
            next.stallCount = 0
        } else {
            // weighted: climb to the cap. bodyweight/timed (no loadable increment):
            // keep climbing reps — maxReps is advisory, since there's no weight to add.
            next.currentReps = weighted ? Swift.min(state.currentReps + 1, state.maxReps) : state.currentReps + 1
            next.stallCount = 0
        }
        return next
    }
}
