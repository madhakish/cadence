import Foundation
import Observation
import CadenceCore

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

    /// The single reader of the durable record: decodes once, and drops a
    /// record no session could ever adopt — corrupt bytes, or one failing
    /// the shared usability rule (stale running origin, future-dated
    /// fields; a paused record is frozen evidence and does not go stale —
    /// StopwatchRecovery owns that decision, tested on both cores) — so
    /// dead bytes are not re-decoded on every open. A record that is merely
    /// another session's stays put.
    private static func loadRecord() -> PersistedClock? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: persistenceKey) else { return nil }
        guard let record = try? JSONDecoder().decode(PersistedClock.self, from: data),
              StopwatchRecovery.recordUsable(start: record.start, pausedAt: record.pausedAt, now: Date()) else {
            defaults.removeObject(forKey: persistenceKey)
            return nil
        }
        return record
    }

    private static func restore(for sessionID: String) -> PersistedClock? {
        guard let record = loadRecord(), record.sessionID == sessionID else { return nil }
        return record
    }

    /// The recovery precedence, in one place: a live (non-ad-hoc) activity
    /// for this session wins — it carries a pause in effect and any shifted
    /// origin — and the durable record is the fallback when no activity
    /// survived the relaunch.
    private static func recoveredState(for sessionID: String) -> (start: Date, pausedAt: Date?)? {
        if let snap = WorkoutActivityController.snapshot, !snap.isAdHoc,
           snap.state.sessionID == sessionID {
            return (snap.state.stopwatchStart ?? snap.startDate, snap.state.stopwatchPausedAt)
        }
        if let record = restore(for: sessionID) {
            return (record.start, record.pausedAt)
        }
        return nil
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
        guard loadRecord()?.sessionID == sessionID else { return }
        UserDefaults.standard.removeObject(forKey: Self.persistenceKey)
    }

    /// A destructive action (discard, bank) is done with a session: end the
    /// clock if that session owns it; otherwise drop only that session's
    /// leftovers — its durable record AND any orphaned Live Activity it left
    /// behind (begin() adopts the snapshot BEFORE the record, so an orphaned
    /// activity would resurrect a discarded stopwatch even with the record
    /// cleared). Never touches another workout's clock, record, or activity,
    /// and never an ad-hoc quick rest.
    func release(sessionID: String) {
        if isTracking(sessionID: sessionID) {
            end()
            return
        }
        Self.clearPersisted(for: sessionID)
        if let snap = WorkoutActivityController.snapshot, !snap.isAdHoc,
           snap.state.sessionID == sessionID {
            WorkoutActivityController.endSessionDetached()
        }
    }

    /// Begin (or continue) the stopwatch for a session. Re-entering the same
    /// session keeps the running clock and just refreshes the activity's
    /// context; a different session restarts both. On a cold start
    /// (app relaunched mid-workout), the clock adopts the recovered origin —
    /// including a pause in effect — instead of resetting to zero.
    func begin(for session: WorkoutSession, currentLift: String, defaultRestSeconds: Int) {
        if sessionID == session.id, startDate != nil {
            WorkoutActivityController.updateContextDetached(currentLift: currentLift, defaultRestSeconds: defaultRestSeconds)
            return
        }
        var start = Date()
        var paused: Date?
        if sessionID == nil, let recovered = Self.recoveredState(for: session.id) {
            start = recovered.start
            paused = recovered.pausedAt
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
    /// start (live activity or durable record — recoveredState owns the
    /// precedence). Never starts a fresh stopwatch.
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
        if sessionID == nil, Self.recoveredState(for: session.id) != nil {
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
    /// controls) — stop the stopwatch and end the activity. Only callers that
    /// know this clock is theirs should call this directly; a destructive
    /// action on a *session* goes through release(sessionID:), which scopes
    /// the teardown to that session.
    func end() {
        startDate = nil
        pausedAt = nil
        sessionID = nil
        persist()
        WorkoutActivityController.endSessionDetached()
    }
}
