import Foundation

/// Whether a persisted workout-stopwatch record may be adopted after a
/// relaunch. One rule, shared by the native UserDefaults record and the web
/// localStorage record (mirrored in `web/app/js/core.js`), so the two
/// clients can never drift on what "stale" means.
///
/// A RUNNING record goes stale after a day — the same sanity bound the
/// history duration label applies — because adopting last week's origin
/// would paint days of elapsed time onto a reopened session. A PAUSED
/// record is different: its elapsed time is frozen at (pausedAt − start)
/// and stays exactly right no matter how much wall-clock time passes, so a
/// workout paused before a force-quit is still adoptable days later; it
/// needs only internal consistency. Future-dated fields (clock skew, bad
/// bytes) are unusable in every case — they would fabricate a stopwatch.
public enum StopwatchRecovery {
    /// How long a RUNNING record stays adoptable.
    public static let recordWindow: TimeInterval = 24 * 60 * 60

    public static func recordUsable(start: Date, pausedAt: Date?, now: Date) -> Bool {
        guard start <= now else { return false }
        if let pausedAt {
            return pausedAt >= start && pausedAt <= now
        }
        return now.timeIntervalSince(start) < recordWindow
    }
}
