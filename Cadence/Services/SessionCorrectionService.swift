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
}
