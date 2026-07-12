import Foundation
import Observation
import SwiftData

/// The session stopwatch. Lives at the root (not the session screen), so the
/// elapsed clock survives leaving and re-entering the logger — and, via the
/// workout Live Activity, backgrounding and app relaunch too. One clock, one
/// active workout (n=1).
@Observable
final class WorkoutClock {
    private(set) var startDate: Date?
    /// Set while the stopwatch is paused; elapsed freezes at (pausedAt − start).
    private(set) var pausedAt: Date?
    private var sessionID: PersistentIdentifier?

    var isRunning: Bool { startDate != nil }
    var isPaused: Bool { pausedAt != nil }

    /// Begin (or continue) the stopwatch for a session. Re-entering the same
    /// session keeps the running clock and just refreshes the activity's
    /// context; a different session restarts both. On a cold start with a
    /// session activity still live (app relaunched mid-workout), the clock
    /// adopts the activity's origin — including a pause in effect — instead
    /// of resetting to zero.
    func begin(for session: WorkoutSession, currentLift: String, defaultRestSeconds: Int) {
        if sessionID == session.persistentModelID, startDate != nil {
            WorkoutActivityController.updateContextDetached(currentLift: currentLift, defaultRestSeconds: defaultRestSeconds)
            return
        }
        var start = Date()
        var paused: Date?
        if sessionID == nil, let snap = WorkoutActivityController.snapshot, !snap.isAdHoc {
            start = snap.state.stopwatchStart ?? snap.startDate
            paused = snap.state.stopwatchPausedAt
        }
        startDate = start
        pausedAt = paused
        sessionID = session.persistentModelID
        WorkoutActivityController.beginSessionDetached(startDate: start, currentLift: currentLift, defaultRestSeconds: defaultRestSeconds)
        // A shifted origin or live pause re-applies after the (queued) begin.
        if paused != nil {
            WorkoutActivityController.updateStopwatchDetached(origin: start, pausedAt: paused)
        }
    }

    /// Freeze the elapsed clock (rest timers are unaffected).
    func pause() {
        guard let start = startDate, pausedAt == nil else { return }
        pausedAt = Date()
        WorkoutActivityController.updateStopwatchDetached(origin: start, pausedAt: pausedAt)
    }

    /// Unfreeze: the origin shifts forward by the paused span, so elapsed
    /// picks up exactly where it stopped.
    func resume() {
        guard let start = startDate, let paused = pausedAt else { return }
        startDate = start.addingTimeInterval(Date().timeIntervalSince(paused))
        pausedAt = nil
        WorkoutActivityController.updateStopwatchDetached(origin: startDate ?? Date(), pausedAt: nil)
    }

    /// Restart the elapsed clock at 0:00 (the session and its rest timer keep
    /// going — this is just the stopwatch).
    func reset() {
        guard startDate != nil else { return }
        startDate = Date()
        pausedAt = nil
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
        WorkoutActivityController.endSessionDetached()
    }
}
