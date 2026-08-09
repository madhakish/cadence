import Foundation
import Observation

/// The session stopwatch. Lives at the root (not the session screen), so the
/// elapsed clock survives leaving and re-entering the logger — and, via the
/// workout Live Activity, backgrounding and app relaunch too. One clock, one
/// active workout (n=1).
@Observable
final class WorkoutClock {
    private(set) var startDate: Date?
    /// Set while the stopwatch is paused; elapsed freezes at (pausedAt − start).
    private(set) var pausedAt: Date?
    private var sessionID: String?

    var isRunning: Bool { startDate != nil }
    var isPaused: Bool { pausedAt != nil }

    /// Durable stopwatch state, written on every transition. The Live
    /// Activity snapshot is the preferred cold-start recovery (it carries a
    /// pause in effect and any shifted origin), but an activity is not a
    /// database: the lifter can dismiss it from the lock screen, the system
    /// expires it, or Live Activities are simply off — and a force-quit
    /// relaunch then restarted the workout timer at 0:00 mid-session. This
    /// record is the fallback that survives all of those.
    private struct PersistedClock: Codable {
        var sessionID: String
        var start: Date
        var pausedAt: Date?
    }
    private static let persistenceKey = "workoutClockState"
    /// A stale record must not resurrect a week-old stopwatch onto a
    /// reopened session — the same one-day sanity bound the history
    /// duration label applies.
    private static let persistenceWindow: TimeInterval = 24 * 60 * 60

    private func persist() {
        let defaults = UserDefaults.standard
        guard let sessionID, let startDate else {
            defaults.removeObject(forKey: Self.persistenceKey)
            return
        }
        let record = PersistedClock(sessionID: sessionID, start: startDate, pausedAt: pausedAt)
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: Self.persistenceKey)
        }
    }

    private static func restore(for sessionID: String) -> PersistedClock? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: persistenceKey) else { return nil }
        guard let record = try? JSONDecoder().decode(PersistedClock.self, from: data) else {
            // Corrupt bytes can never become a clock — drop them instead of
            // re-decoding the same garbage on every open.
            defaults.removeObject(forKey: persistenceKey)
            return nil
        }
        // A future-dated origin (clock skew, bad bytes) is as unusable as a
        // stale one: it would restore a "running" stopwatch with negative
        // elapsed time. Only a start within the last day counts.
        let age = Date().timeIntervalSince(record.start)
        guard record.sessionID == sessionID, age >= 0, age < persistenceWindow else { return nil }
        return record
    }

    /// True only for the open session that owns the root-scoped stopwatch and
    /// Live Activity. Used by destructive session actions so another workout's
    /// clock is never stopped accidentally.
    func isTracking(sessionID candidate: String) -> Bool {
        sessionID == candidate && startDate != nil
    }

    /// Drop the durable record for a session being discarded before the clock
    /// re-adopted it (force-quit, then discard from Today). Without this the
    /// record outlives the session — and a restored backup reuses session IDs,
    /// so reopening within the day would resurrect a discarded stopwatch.
    /// Leaves any other session's record alone.
    static func clearPersisted(for sessionID: String) {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: persistenceKey),
              let record = try? JSONDecoder().decode(PersistedClock.self, from: data),
              record.sessionID == sessionID else { return }
        defaults.removeObject(forKey: persistenceKey)
    }

    /// Begin (or continue) the stopwatch for a session. Re-entering the same
    /// session keeps the running clock and just refreshes the activity's
    /// context; a different session restarts both. On a cold start with a
    /// session activity still live (app relaunched mid-workout), the clock
    /// adopts the activity's origin — including a pause in effect — instead
    /// of resetting to zero.
    func begin(for session: WorkoutSession, currentLift: String, defaultRestSeconds: Int) {
        if sessionID == session.id, startDate != nil {
            WorkoutActivityController.updateContextDetached(currentLift: currentLift, defaultRestSeconds: defaultRestSeconds)
            return
        }
        var start = Date()
        var paused: Date?
        if sessionID == nil, let snap = WorkoutActivityController.snapshot, !snap.isAdHoc,
           snap.state.sessionID == session.id {
            start = snap.state.stopwatchStart ?? snap.startDate
            paused = snap.state.stopwatchPausedAt
        } else if sessionID == nil, let record = Self.restore(for: session.id) {
            // No live activity to adopt (dismissed, expired, or disabled) —
            // the durable record keeps the elapsed clock honest across a
            // relaunch instead of restarting the workout at 0:00.
            start = record.start
            paused = record.pausedAt
        }
        startDate = start
        pausedAt = paused
        sessionID = session.id
        persist()
        WorkoutActivityController.beginSessionDetached(sessionID: session.id, startDate: start,
                                                        currentLift: currentLift, defaultRestSeconds: defaultRestSeconds)
        // A shifted origin or live pause re-applies after the (queued) begin.
        if paused != nil {
            WorkoutActivityController.updateStopwatchDetached(origin: start, pausedAt: paused)
        }
    }

    /// Re-entering a session that is ALREADY being timed: refresh the Live
    /// Activity context, or re-adopt a clock still running from before a cold
    /// start. Never starts a fresh stopwatch.
    ///
    /// Opening a session is not the same act as starting one — a lifter
    /// reviewing what is coming, or reopening a logger to read the plan, has
    /// not begun training, and a clock that started itself on appear reported
    /// elapsed time nobody trained and could not be undone without discarding
    /// the session.
    @discardableResult
    func resumeIfTracking(for session: WorkoutSession, currentLift: String, defaultRestSeconds: Int) -> Bool {
        if sessionID == session.id, startDate != nil {
            WorkoutActivityController.updateContextDetached(currentLift: currentLift, defaultRestSeconds: defaultRestSeconds)
            return true
        }
        // Cold start with this session's activity still live: adopt it rather
        // than stranding a workout that is genuinely still running.
        if sessionID == nil, let snap = WorkoutActivityController.snapshot, !snap.isAdHoc,
           snap.state.sessionID == session.id {
            begin(for: session, currentLift: currentLift, defaultRestSeconds: defaultRestSeconds)
            return true
        }
        // No activity survived the relaunch, but the durable record says this
        // session's stopwatch was running — resume it (begin() reads the same
        // record for the origin and any pause in effect).
        if sessionID == nil, Self.restore(for: session.id) != nil {
            begin(for: session, currentLift: currentLift, defaultRestSeconds: defaultRestSeconds)
            return true
        }
        return false
    }

    /// Freeze the elapsed clock (rest timers are unaffected).
    func pause() {
        guard let start = startDate, pausedAt == nil else { return }
        pausedAt = Date()
        persist()
        WorkoutActivityController.updateStopwatchDetached(origin: start, pausedAt: pausedAt)
    }

    /// Unfreeze: the origin shifts forward by the paused span, so elapsed
    /// picks up exactly where it stopped.
    func resume() {
        guard let start = startDate, let paused = pausedAt else { return }
        startDate = start.addingTimeInterval(Date().timeIntervalSince(paused))
        pausedAt = nil
        persist()
        WorkoutActivityController.updateStopwatchDetached(origin: startDate ?? Date(), pausedAt: nil)
    }

    /// Restart the elapsed clock at 0:00 (the session and its rest timer keep
    /// going — this is just the stopwatch).
    func reset() {
        guard startDate != nil else { return }
        startDate = Date()
        pausedAt = nil
        persist()
        WorkoutActivityController.updateStopwatchDetached(origin: startDate ?? Date(), pausedAt: nil)
    }

    /// The lift being worked (or its smart rest) changed — keep the activity's
    /// elapsed face and quick-rest default honest.
    func updateContext(currentLift: String, defaultRestSeconds: Int) {
        guard startDate != nil else { return }
        WorkoutActivityController.updateContextDetached(currentLift: currentLift, defaultRestSeconds: defaultRestSeconds)
    }

    /// The workout is over (banked, or ended deliberately from the clock
    /// controls) — stop the stopwatch and end the activity.
    func end() {
        startDate = nil
        pausedAt = nil
        sessionID = nil
        persist()
        WorkoutActivityController.endSessionDetached()
    }
}
