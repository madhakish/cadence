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

    /// The set the Lock Screen's Done button will complete.
    ///
    /// Identity is (exercise order, set order) rather than a model id, because
    /// `SetEntry` has none — order is stable for the activity's whole life,
    /// which is one session. The intent re-derives the current set from the
    /// store anyway and refuses if it disagrees with this, so a stale activity
    /// can never complete a set the lifter could not see.
    ///
    /// `label` is formatted by the app, not the widget. The widget runs in its
    /// own process with no access to the unit preference, and a second
    /// formatter is a second chance to render kilograms as pounds.
    struct CurrentSet: Codable, Hashable {
        var exerciseOrder: Int
        var setOrder: Int
        /// 1-based, counting the set being worked. Warmups excluded.
        var position: Int
        var total: Int
        /// "185 lb × 5", "0:30", "1.5 mi" — whatever this set actually is.
        var label: String
    }

    struct ContentState: Codable, Hashable {
        /// Stable workout identifier used by taps to reopen the exact logger.
        /// nil for an ad-hoc rest started outside a session.
        var sessionID: String? = nil
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
        /// The set Done completes. nil when there is nothing left to work, or
        /// for an ad-hoc rest with no session behind it — either way the Lock
        /// Screen shows no Done button rather than one that does nothing.
        var currentSet: CurrentSet? = nil
    }

    /// Session stopwatch origin. Fixed for the activity's life.
    var startDate: Date
    /// True when the activity was born from a quick rest with no workout
    /// running (Action Button before the session screen opened) — it ends
    /// when its rest ends instead of reverting to a meaningless stopwatch.
    var isAdHoc: Bool
}
