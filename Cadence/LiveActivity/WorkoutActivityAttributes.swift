import ActivityKit
import CadenceCore
import Foundation

/// The contract shared between the app and the widget extension for the ONE
/// workout Live Activity (Lock Screen + Dynamic Island). Two faces, one
/// activity: a session stopwatch (elapsed count-up + the lift you're working)
/// that swaps to the rest countdown + controls while a rest is running, then
/// swaps back. The stopwatch derives from `startDate` and the countdown from
/// `rest` (a pure `RestClock.State`), so both tick via `Text(timerInterval:)`
/// with the phone asleep and the app suspended — no background execution,
/// no push.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The lift being worked (elapsed face) or rested (rest face).
        var currentLift: String
        /// What a quick rest (Action Button / Control Center) should arm for
        /// the current lift — kept fresh by the app so the intent needs no
        /// database access.
        var defaultRestSeconds: Int
        /// The running rest, if any. `nil` → elapsed face.
        var rest: RestClock.State?
        /// Stopwatch origin override: resume/reset shift the clock's start,
        /// but `attributes.startDate` is immutable — so the live origin rides
        /// in state. nil → `attributes.startDate` (activity as born).
        var stopwatchStart: Date? = nil
        /// Set while the workout clock is paused; the widget freezes the
        /// elapsed face at (pausedAt − origin).
        var stopwatchPausedAt: Date? = nil
    }

    /// Session stopwatch origin. Fixed for the activity's life.
    var startDate: Date
    /// True when the activity was born from a quick rest with no workout
    /// running (Action Button before the session screen opened) — it ends
    /// when its rest ends instead of reverting to a meaningless stopwatch.
    var isAdHoc: Bool
}
