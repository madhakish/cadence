import Foundation
import Observation
import CadenceCore

/// The session stopwatch. Lives at the root (not the session screen), so the
/// elapsed clock survives leaving and re-entering the logger — and, via the
/// workout Live Activity, backgrounding and app relaunch too. One clock, one
/// active workout (n=1).
@Observable
final class WorkoutClock {
    /// Display origin only: resume/reset may shift it. Health uses the
    /// immutable start and pause history in the durable record instead.
    private(set) var startDate: Date?
    /// Set while the stopwatch is paused; elapsed freezes at (pausedAt − start).
    private(set) var pausedAt: Date?
    private var sessionID: String?

    var isRunning: Bool { startDate != nil }
    var isPaused: Bool { pausedAt != nil }

    /// The durable record is shared with Lock Screen controls. New records
    /// carry real workout timing independently of the display origin; legacy
    /// records still restore their stopwatch but cannot reconstruct that past.
    private static func recoveredState(for sessionID: String) -> WorkoutClockRecord? {
        let record = WorkoutClockPersistence.load().flatMap { $0.sessionID == sessionID ? $0 : nil }
        if record?.healthTiming != nil { return record }
        if let snap = WorkoutActivityController.snapshot, !snap.isAdHoc,
           snap.state.sessionID == sessionID {
            return WorkoutClockRecord(sessionID: sessionID,
                                      start: snap.state.stopwatchStart ?? snap.startDate,
                                      pausedAt: snap.state.stopwatchPausedAt)
        }
        return record
    }

    private func adopt(_ record: WorkoutClockRecord) {
        startDate = record.start
        pausedAt = record.pausedAt
        sessionID = record.sessionID
    }

    /// Reconcile controls used from the Lock Screen before another foreground
    /// action or export. The durable record also survives activity dismissal.
    func synchronize() {
        guard let sessionID else { return }
        guard let record = WorkoutClockPersistence.load(), record.sessionID == sessionID else {
            startDate = nil
            pausedAt = nil
            self.sessionID = nil
            return
        }
        adopt(record)
    }

    func healthTiming(for candidate: String) -> HealthWorkoutTiming? {
        guard isTracking(sessionID: candidate) else { return nil }
        synchronize()
        guard let record = WorkoutClockPersistence.load(), record.sessionID == candidate else { return nil }
        return record.healthTiming
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
        WorkoutClockPersistence.clear(for: sessionID)
    }

    /// A destructive action (discard, bank) is done with a session: end the
    /// clock if that session owns it; otherwise drop only that session's
    /// leftovers — its durable record AND any orphaned Live Activity it left
    /// behind (a legacy activity can recover its stopwatch even with the
    /// record cleared). Never touches another workout's clock, record, or activity,
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
    func begin(for session: WorkoutSession, currentLift: String, defaultRestSeconds: Int,
               currentSet: CurrentSetProjection? = nil) {
        synchronize()
        if sessionID == session.id, startDate != nil {
            WorkoutActivityController.updateContextDetached(currentLift: currentLift, defaultRestSeconds: defaultRestSeconds,
                                                            currentSet: currentSet)
            return
        }
        let now = Date()
        let record = sessionID == nil ? Self.recoveredState(for: session.id) : nil
        let state = record ?? WorkoutClockRecord(sessionID: session.id, start: now,
                                                  healthTiming: HealthWorkoutTiming(start: now))
        adopt(state)
        WorkoutClockPersistence.save(state)
        WorkoutActivityController.beginSessionDetached(sessionID: session.id, startDate: state.start,
                                                        currentLift: currentLift, defaultRestSeconds: defaultRestSeconds,
                                                        currentSet: currentSet)
        if state.pausedAt != nil {
            WorkoutActivityController.updateStopwatchDetached(origin: state.start, pausedAt: state.pausedAt)
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
    func resumeIfTracking(for session: WorkoutSession, currentLift: String, defaultRestSeconds: Int,
                          currentSet: CurrentSetProjection? = nil) -> Bool {
        synchronize()
        if sessionID == session.id, startDate != nil {
            WorkoutActivityController.updateContextDetached(currentLift: currentLift, defaultRestSeconds: defaultRestSeconds,
                                                            currentSet: currentSet)
            return true
        }
        if sessionID == nil, Self.recoveredState(for: session.id) != nil {
            begin(for: session, currentLift: currentLift, defaultRestSeconds: defaultRestSeconds, currentSet: currentSet)
            return true
        }
        return false
    }

    /// Freeze the elapsed clock (rest timers are unaffected).
    func pause() { transition { $0.pause(at: Date()) } }

    /// Shift only the display origin; keep the actual workout start intact.
    func resume() { transition { $0.resume(at: Date()) } }

    /// Reset only the elapsed display, preserving measured workout history.
    func reset() { transition { $0.reset(at: Date()) } }

    private func transition(_ change: (inout WorkoutClockRecord) -> Void) {
        guard let sessionID,
              let record = WorkoutClockPersistence.update(for: sessionID, change) else { return }
        adopt(record)
        WorkoutActivityController.updateStopwatchDetached(origin: record.start, pausedAt: record.pausedAt)
    }

    /// The lift being worked (or its smart rest) changed — keep the activity's
    /// elapsed face and quick-rest default honest.
    func updateContext(currentLift: String, defaultRestSeconds: Int, currentSet: CurrentSetProjection? = nil) {
        guard startDate != nil else { return }
        WorkoutActivityController.updateContextDetached(currentLift: currentLift, defaultRestSeconds: defaultRestSeconds,
                                                        currentSet: currentSet)
    }

    /// The workout is over (banked, or ended deliberately from the clock
    /// controls) — stop the stopwatch and end the activity. Only callers that
    /// know this clock is theirs should call this directly; a destructive
    /// action on a *session* goes through release(sessionID:), which scopes
    /// the teardown to that session.
    func end() {
        if let sessionID { WorkoutClockPersistence.clear(for: sessionID) }
        startDate = nil
        pausedAt = nil
        sessionID = nil
        WorkoutActivityController.endSessionDetached()
    }
}
