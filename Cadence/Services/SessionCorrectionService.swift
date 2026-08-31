import CadenceCore
import Foundation
import SwiftData

/// The banked-correction boundary (epic #155 Stage 0): applies buffered set
/// corrections through the shared `SetLifecycle` rule, writing only fields
/// that actually changed so an untouched field can never dirty the record.
/// Mirrors web `db.js` `Sessions.applyCorrections`.
///
/// Deliberately does NOT re-run bank-time grading, milestones, or program
/// advancement — that reconciliation is epic #155 Stage 6. Charts, exports,
/// recalls, and prior-best evidence read the canonical sets and follow the
/// correction on their own.
enum SessionCorrectionService {
    /// What a correction actually reconciled. `rebuiltMilestones` is the
    /// deterministic part; the program's banked grade is deliberately NOT
    /// replayed (no recorded baseline exists for it), and callers surface that
    /// rather than implying the cursor followed the correction.
    struct Outcome: Equatable {
        let rebuiltMilestones: Int
        let programStateReplayed: Bool
    }

    static func apply(_ corrections: [(set: SetEntry, correction: SetLifecycle.SetCorrection)]) {
        for (set, correction) in corrections {
            let corrected = SetLifecycle.correctedSetValues(
                weightLb: set.weightLb, reps: set.reps,
                durationSeconds: set.durationSeconds, status: set.status,
                correction: correction
            )
            if set.weightLb != corrected.weightLb { set.weightLb = corrected.weightLb }
            if set.reps != corrected.reps { set.reps = corrected.reps }
            if set.durationSeconds != corrected.durationSeconds { set.durationSeconds = corrected.durationSeconds }
            if set.status != corrected.status { set.status = corrected.status }
        }
    }

    /// Apply corrections, then regenerate every derived record that can be
    /// rebuilt deterministically from the corrected canonical sessions —
    /// today, the PR milestones of the lifts the correction touched
    /// (epic #155 Stage 6). Program progression state is not replayed: the
    /// grade that fired at bank time was computed against a cursor this store
    /// never recorded, so rebuilding it would be a guess dressed as history.
    @discardableResult
    static func applyAndRebuild(
        _ corrections: [(set: SetEntry, correction: SetLifecycle.SetCorrection)],
        in session: WorkoutSession,
        context: ModelContext,
        intervals: [TrainingIntervalSnapshot] = [],
        formatWeight: (Double) -> String = { String(format: "%g lb", $0) }
    ) throws -> Outcome {
        let corrected = Set(corrections.map { ObjectIdentifier($0.set) })
        var affected: Set<String> = []
        for entry in session.exercises where entry.sets.contains(where: { corrected.contains(ObjectIdentifier($0)) }) {
            if let name = entry.exercise?.name { affected.insert(name) }
        }
        apply(corrections)
        let rebuilt = try MilestoneProjection.rebuild(
            exerciseNames: affected, context: context,
            intervals: intervals, formatWeight: formatWeight
        )
        return Outcome(rebuiltMilestones: rebuilt, programStateReplayed: false)
    }
}
