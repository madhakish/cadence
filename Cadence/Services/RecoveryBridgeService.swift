import Foundation
import SwiftData
import CadenceCore

/// The legacy recovery bridge's persistence edge: which recovery exposures
/// this cycle banked, the manual Next-day choices that reconciliation keeps,
/// and closing a stale or satisfied bridge. Models-only, so the hostless
/// CadenceMigrationTests target exercises it on real SwiftData rows.
/// Moved verbatim from SessionCompletion; decisions live in CadenceCore.
enum RecoveryBridgeService {

    struct RecoveryBridgeReconciliation {
        let reason: RecoveryBridgeCompletionReason? // nil when only the next-day pointer was repaired
        let message: String
    }

    /// Fetch only the newest completed sessions for one phase of this cycle.
    /// Stable-ID and legacy-name matching use separate descriptors so Swift's
    /// predicate macro never has to type-check the combined fallback. The
    /// legacy query runs only when stable rows have not filled the requested
    /// limit, so the total number of returned rows remains bounded by `limit`.
    private static func recentCompletedSessions(
        for program: Program,
        phase: Int,
        limit: Int,
        context: ModelContext
    ) throws -> [WorkoutSession] {
        let stableProgramID = program.id
        let legacyProgramName = program.name
        let cycleNumber = program.cycleNumber
        guard limit > 0 else { return [] }

        let identifiedPredicate = #Predicate<WorkoutSession> { session in
            session.isCompleted
                && session.programID == stableProgramID
                && session.programCycleNumber == cycleNumber
                && session.programWeek == phase
        }
        let newestFirst = [SortDescriptor<WorkoutSession>(\.date, order: .reverse)]
        var identifiedDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: identifiedPredicate,
            sortBy: newestFirst
        )
        identifiedDescriptor.fetchLimit = limit
        let identified = try context.fetch(identifiedDescriptor)
        guard identified.count < limit else { return identified }

        let legacyPredicate = #Predicate<WorkoutSession> { session in
            session.isCompleted
                && session.programID == nil
                && session.programName == legacyProgramName
                && session.programCycleNumber == cycleNumber
                && session.programWeek == phase
        }
        var legacyDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: legacyPredicate,
            sortBy: newestFirst
        )
        legacyDescriptor.fetchLimit = limit - identified.count
        let legacy = try context.fetch(legacyDescriptor)
        return (identified + legacy)
            .sorted { $0.date > $1.date }
    }

    /// Enough rows to reach the bridge's own cap. That is two for a normal
    /// upper/lower bridge, but a program keeping its full authored pass has a
    /// longer one, and fetching only two would report it complete early.
    static func recentRecoverySessions(
        for program: Program, selectedExposureCount: Int, context: ModelContext
    ) throws -> [WorkoutSession] {
        try recentCompletedSessions(
            for: program,
            phase: ProgramProgression.deloadWeek,
            limit: Swift.max(ProgramProgression.recoverySessionLimit, selectedExposureCount),
            context: context
        )
    }

    private static func lastHardPhaseCompletion(
        for program: Program, context: ModelContext
    ) throws -> Date? {
        let peakPhase = ProgramProgression.gradedWeek
        let volumePhase = 1
        let loadPhase = 2

        let peak = try recentCompletedSessions(
            for: program,
            phase: peakPhase,
            limit: 1,
            context: context
        ).first
        if let peak { return peak.effectiveCompletionDate }

        // Early recovery deliberately skips Peak. In that case the most
        // recent Volume/Load completion is the expiry anchor.
        let volume = try recentCompletedSessions(
            for: program,
            phase: volumePhase,
            limit: 1,
            context: context
        ).first
        let load = try recentCompletedSessions(
            for: program,
            phase: loadPhase,
            limit: 1,
            context: context
        ).first
        let preceding = [volume, load].compactMap { $0 }.max {
            $0.effectiveCompletionDate < $1.effectiveCompletionDate
        }
        return preceding.map(\.effectiveCompletionDate)
    }

    private static func selectedRecoveryDayOrders(
        for program: Program, exerciseByName: [String: Exercise]
    ) -> [Int] {
        ProgramProgression.recoveryDayOrders(
            program.orderedDays.map { programDay in
                let mainName = programDay.orderedLifts.first(where: { $0.role == .main })?.exerciseName
                return RecoveryDayCandidate(
                    order: programDay.order,
                    mainMovementGroup: mainName.flatMap { exerciseByName[$0]?.movementGroup }
                )
            }
        )
    }

    /// Days the manual "Next day" picker may offer; `nil` means every day.
    /// During a legacy recovery bridge it is the unbanked recovery days, which
    /// are exactly the pointers reconciliation keeps. An empty remainder means
    /// the bridge is complete and rolls over on the next reconcile, so the
    /// picker is unrestricted. Mirrors web session.js `manualNextDayOrders`.
    static func manualNextDayOrders(program: Program, context: ModelContext) throws -> [Int]? {
        guard program.tfhPolicyData == nil, program.currentWeek == ProgramProgression.deloadWeek else { return nil }
        let exerciseByName = try context.fetch(FetchDescriptor<Exercise>()).indexedByName()
        let recoveryOrders = selectedRecoveryDayOrders(for: program, exerciseByName: exerciseByName)
        let recoverySessions = try recentRecoverySessions(
            for: program, selectedExposureCount: recoveryOrders.count, context: context
        )
        let remaining = ProgramProgression.recoveryRemainingDayOrders(
            dayOrders: recoveryOrders, completedDayOrders: recoverySessions.compactMap(\.programDayIndex)
        )
        return remaining.isEmpty ? nil : remaining
    }

    /// Close a stale or already-satisfied recovery bridge before Today or
    /// Start can prescribe another reduced workout. The seven-day threshold is
    /// an expiry guard only; normal program advancement remains cycle-based.
    @discardableResult
    static func reconcileRecoveryBridge(
        program: Program, context: ModelContext, asOf now: Date = .now
    ) throws -> RecoveryBridgeReconciliation? {
        if program.tfhPolicyData != nil {
            _ = try TFHProgramService.synchronize(program, sessions: context.fetch(FetchDescriptor<WorkoutSession>()))
            try context.save()
            return nil
        }
        guard program.currentWeek == ProgramProgression.deloadWeek else { return nil }

        // Never advance the program out from under a workout in progress. The
        // open session was built against this rotation; rolling the cycle while
        // it is on screen makes banking it fail the stale-tag guard and land as
        // orphaned history. Reconciliation is not urgent — it runs on the next
        // render once the session is banked or discarded.
        //
        // Scoped to THIS PROGRAM'S sessions, deliberately. Blocking on any open
        // session at all would let one lingering blank session — which Today
        // explicitly supports keeping around — suppress the session cap and the
        // expiry window indefinitely, and Start would go on minting stale
        // recovery prescriptions. That is the indefinite-light-work path this
        // whole mechanism exists to close.
        //
        // Stable-ID and legacy-name matching use separate descriptors for the
        // same reason `recentCompletedSessions` does: the predicate macro never
        // has to type-check the combined optional fallback.
        let stableProgramID = program.id
        let legacyProgramName = program.name
        var openByID = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { session in
                !session.isCompleted && session.programID == stableProgramID
            }
        )
        openByID.fetchLimit = 1
        guard try context.fetch(openByID).isEmpty else { return nil }

        var openByName = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { session in
                !session.isCompleted && session.programID == nil
                    && session.programName == legacyProgramName
            }
        )
        openByName.fetchLimit = 1
        guard try context.fetch(openByName).isEmpty else { return nil }

        let exerciseByName = try context.fetch(FetchDescriptor<Exercise>()).indexedByName()
        let recoveryOrders = selectedRecoveryDayOrders(for: program, exerciseByName: exerciseByName)
        let recoverySessions = try recentRecoverySessions(
            for: program, selectedExposureCount: recoveryOrders.count, context: context
        )
        let selectedComplete = ProgramProgression.recoveryScheduleAdvance(
            dayOrders: recoveryOrders,
            completedDayOrders: recoverySessions.compactMap(\.programDayIndex)
        ).isLastDay
        var reason = ProgramProgression.recoveryBridgeCompletionReason(
            completedRecoverySessions: recoverySessions.count,
            selectedExposureCount: recoveryOrders.count,
            selectedExposuresComplete: selectedComplete,
            lastHardPhaseCompletion: nil,
            asOf: now
        )
        if reason == nil {
            reason = ProgramProgression.recoveryBridgeCompletionReason(
                completedRecoverySessions: recoverySessions.count,
                selectedExposureCount: recoveryOrders.count,
                selectedExposuresComplete: selectedComplete,
                lastHardPhaseCompletion: try lastHardPhaseCompletion(for: program, context: context),
                asOf: now
            )
        }
        guard let reason else {
            let next = ProgramProgression.recoveryResumeDayOrder(
                dayOrders: recoveryOrders,
                completedDayOrders: recoverySessions.compactMap(\.programDayIndex),
                currentDayOrder: program.nextDayIndex
            )
            guard next != program.nextDayIndex else { return nil }
            program.nextDayIndex = next
            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
            return RecoveryBridgeReconciliation(
                reason: nil, message: "Recovery continues — next light session: \(program.day(order: next)?.name ?? "program day")."
            )
        }

        let nextCycle = program.cycleNumber + 1
        let banked = recoverySessions.count
        let message: String
        switch reason {
        case .selectedExposures:
            message = "Recovery complete — planned recovery exposures banked. Cycle \(nextCycle) starts at Volume."
        case .sessionLimit:
            message = "Recovery complete — \(banked) recovery session\(banked == 1 ? "" : "s") banked. Cycle \(nextCycle) starts at Volume."
        case .windowElapsed:
            message = "Recovery complete — the seven-day recovery window elapsed. Cycle \(nextCycle) starts at Volume."
        }

        let unitDisplay = try context.fetch(FetchDescriptor<AppSettings>()).unitDisplay
        var events: [PREvent] = []
        rollOverRecovery(
            program: program,
            allDayOrders: program.orderedDays.map(\.order),
            exerciseTypeByName: exerciseByName.mapValues(\.typeRaw),
            context: context,
            unitDisplay: unitDisplay,
            date: now,
            events: &events
        )
        context.insert(Milestone(
            date: now, exerciseName: nil, kind: .programNote,
            label: "\(program.name): \(message)"
        ))
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return RecoveryBridgeReconciliation(reason: reason, message: message)
    }

    static func rollOverRecovery(
        program: Program,
        allDayOrders: [Int],
        exerciseTypeByName: [String: String],
        context: ModelContext,
        unitDisplay: UnitDisplay,
        date: Date,
        events: inout [PREvent]
    ) {
        for d in program.days {
            for lift in d.lifts {
                if lift.prescription.advancesPerExposure {
                    // Per-exposure slots (rep windows, novice fives, Texas
                    // days) advance after every banked session and do not
                    // participate in Peak grading or skipped-Peak stalls.
                    // Clear any stale pending left by a style edit after a
                    // grade — it must never apply months later.
                    lift.pendingBaseWeightLb = nil
                    lift.pendingEstimatedMaxLb = nil
                    lift.pendingStallCount = nil
                    lift.pendingLastIncrementLb = nil
                    lift.pendingNote = nil
                } else if let pendingBase = lift.pendingBaseWeightLb {
                    let oldBase = lift.baseWeightLb
                    lift.baseWeightLb = pendingBase
                    lift.estimatedMaxLb = lift.pendingEstimatedMaxLb ?? lift.estimatedMaxLb
                    lift.stallCount = lift.pendingStallCount ?? lift.stallCount
                    lift.lastIncrementLb = lift.pendingLastIncrementLb ?? 0
                    if let note = lift.pendingNote {
                        let presented = note.hasPrefix("Two cycles without a clean peak")
                            ? "Two cycles without a clean peak — deloaded \(unitDisplay.format(lb: oldBase))→\(unitDisplay.format(lb: pendingBase)) to rebuild."
                            : note
                        let label = "\(lift.exerciseName): \(presented)"
                        context.insert(Milestone(date: date, exerciseName: lift.exerciseName, kind: .programNote, label: label))
                        events.append(PREvent(kind: .programNote, exercise: lift.exerciseName, label: label))
                    }
                    lift.pendingBaseWeightLb = nil
                    lift.pendingEstimatedMaxLb = nil
                    lift.pendingStallCount = nil
                    lift.pendingLastIncrementLb = nil
                    lift.pendingNote = nil
                } else if !lift.prescription.buildsOwnSessionShape {
                    // Wave-family slots: a peak never banked is a stall toward
                    // the 10% rebuild. The methodology cycle styles (5/3/1,
                    // max/dynamic effort) define their own miss rules and
                    // simply hold when the graded week was skipped — a
                    // skipped week is not missed reps.
                    lift.stallCount += 1
                    lift.lastIncrementLb = 0
                    if lift.stallCount >= ProgramProgression.stallLimit {
                        let old = lift.baseWeightLb
                        let loadStep = ProgramEngine.loadStep(programRoundingLb: program.roundingLb,
                                                              exerciseType: exerciseTypeByName[lift.exerciseName])
                        lift.baseWeightLb = Weight.round(old * ProgramProgression.deloadRebuildFraction, to: loadStep)
                        lift.stallCount = 0
                        let label = "\(lift.exerciseName): skipped peak — deloaded \(unitDisplay.format(lb: old))→\(unitDisplay.format(lb: lift.baseWeightLb))."
                        context.insert(Milestone(date: date, exerciseName: lift.exerciseName, kind: .programNote, label: label))
                        events.append(PREvent(kind: .programNote, exercise: lift.exerciseName, label: label))
                    }
                } else {
                    // Methodology cycle styles hold on a skipped graded week,
                    // but the increment record must not keep advertising a
                    // bump that never happened this cycle.
                    lift.lastIncrementLb = 0
                }
                // A cycle-scoped swap ends with the cycle (mirrors web).
                if let original = lift.revertToExerciseName, program.equipmentPolicy.allows(exerciseType: exerciseTypeByName[original] ?? "") {
                    let label = "\(original): cycle swap over — slot reverts from \(lift.exerciseName) for the new cycle."
                    lift.exerciseName = original
                    context.insert(Milestone(date: date, exerciseName: original, kind: .programNote, label: label))
                    events.append(PREvent(kind: .programNote, exercise: original, label: label))
                }
                lift.revertToExerciseName = nil
            }
            for acc in d.accessories {
                if let original = acc.revertToExerciseName, program.equipmentPolicy.allows(exerciseType: exerciseTypeByName[original] ?? "") {
                    let label = "\(original): cycle swap over — slot reverts from \(acc.exerciseName) for the new cycle."
                    acc.exerciseName = original
                    context.insert(Milestone(date: date, exerciseName: original, kind: .programNote, label: label))
                    events.append(PREvent(kind: .programNote, exercise: original, label: label))
                }
                acc.revertToExerciseName = nil
            }
        }
        program.cycleNumber += 1
        program.currentWeek = 1
        program.nextDayIndex = allDayOrders.first ?? 0
    }
}
