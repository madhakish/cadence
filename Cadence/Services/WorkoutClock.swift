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
    private var sessionID: PersistentIdentifier?

    /// Begin (or continue) the stopwatch for a session. Re-entering the same
    /// session keeps the running clock and just refreshes the activity's
    /// context; a different session restarts both. On a cold start with a
    /// session activity still live (app relaunched mid-workout), the clock
    /// adopts the activity's origin instead of resetting to zero.
    func begin(for session: WorkoutSession, currentLift: String, defaultRestSeconds: Int) {
        if sessionID == session.persistentModelID, startDate != nil {
            WorkoutActivityController.updateContextDetached(currentLift: currentLift, defaultRestSeconds: defaultRestSeconds)
            return
        }
        var start = Date()
        if sessionID == nil, let snap = WorkoutActivityController.snapshot, !snap.isAdHoc {
            start = snap.startDate
        }
        startDate = start
        sessionID = session.persistentModelID
        WorkoutActivityController.beginSessionDetached(startDate: start, currentLift: currentLift, defaultRestSeconds: defaultRestSeconds)
    }

    /// The lift being worked (or its smart rest) changed — keep the activity's
    /// elapsed face and quick-rest default honest.
    func updateContext(currentLift: String, defaultRestSeconds: Int) {
        guard startDate != nil else { return }
        WorkoutActivityController.updateContextDetached(currentLift: currentLift, defaultRestSeconds: defaultRestSeconds)
    }

    /// The workout is over (banked) — stop the stopwatch and end the activity.
    func end() {
        startDate = nil
        sessionID = nil
        WorkoutActivityController.endSessionDetached()
    }
}
