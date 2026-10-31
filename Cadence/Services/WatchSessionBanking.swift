import CadenceCore
import Foundation
import SwiftData

/// Banking for sessions shared with the watch (design #339, section 5). Kept
/// apart from `WatchSessionSync` because `SessionCompletion` reaches HealthKit,
/// which the hostless migration suite does not link.
@MainActor
enum WatchSessionBanking {
    /// Bank a watch-synced session once the end barrier holds: `sessionEnded`
    /// arrived and every operation it lists has been processed. A session
    /// waiting for the owner (duplicate, stale plan, recovered) never banks
    /// here. Returns nil when it is not time yet.
    @discardableResult
    static func bankIfReady(_ session: WorkoutSession, context: ModelContext) throws -> SessionSummary? {
        guard !session.isCompleted, session.syncReviewReasonRaw == nil,
              let replica = try WatchSessionSync.endpoint(of: session)?.replica,
              replica.isReadyToBank else { return nil }
        let view = replica.view()
        guard let end = view.ended else { return nil }
        try WatchSessionSync.project(view, onto: session, phone: try WatchSessionSync.phoneContext(of: replica),
                                     context: context)
        // Set before banking so bank-time export sees who owns the workout.
        session.watchHealthOutcome = end.health
        let timing = WatchSessionSync.healthTiming(startedAt: session.date, view: view)
        return try SessionCompletion.finish(session, context: context, healthTiming: timing, endedAt: end.endedAt)
    }

    /// Why a watch session is waiting for the owner, in plain words.
    static func reviewExplanation(_ reason: String?) -> String? {
        switch reason {
        case "duplicate": return "You started this program day on both devices. Keep this one, or discard it and keep the other."
        case "stalePlan": return "This was started from a plan built on an earlier day. Confirm it was the right day before it's saved."
        case "recovered": return "These sets came back from your watch after a restore. Check them before they're saved."
        case nil: return nil
        default: return "This session needs a look before it's saved."
        }
    }

    /// The owner chose to keep a session that was waiting for review: clear the
    /// flag and bank it if the watch has already ended it.
    @discardableResult
    static func keep(_ session: WorkoutSession, context: ModelContext) throws -> SessionSummary? {
        session.syncReviewReasonRaw = nil
        try context.save()
        return try bankIfReady(session, context: context)
    }
}
