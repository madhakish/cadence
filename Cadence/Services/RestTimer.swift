import CadenceCore
import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Countdown between sets. Manual by default — armed from the Rest buttons or
/// the bottom bar; only auto-armed after a set when the auto-start setting is
/// on. All state math is `RestClock` (CadenceCore, mirrored on web); this
/// class just ticks the display and delegates the "Rest over." notification
/// and the workout Live Activity's rest face to `WorkoutActivityController`,
/// so the phone can sit face-down on the chalk bucket and still be driven
/// from the Lock Screen; buzzes on finish when haptics are enabled.
@Observable
final class RestTimer {
    private(set) var remaining: TimeInterval = 0
    private(set) var isRunning = false
    private(set) var exerciseName = ""
    /// Mirrors the haptics setting; the session view keeps it in sync.
    var hapticsEnabled = true
    private var clock: RestClock.State?
    private var timer: Timer?

    var isPaused: Bool { clock?.paused ?? false }
    var total: TimeInterval { clock?.total ?? 0 }

    var progress: Double {
        guard let clock else { return 0 }
        return RestClock.fractionRemaining(clock, now: now)
    }

    var display: String { mmss(Int(remaining.rounded())) }

    private var now: Double { Date().timeIntervalSince1970 }

    func start(seconds: Int, exerciseName: String) {
        // Guard BEFORE clearing: arming a zero-rest movement (conditioning) must
        // not kill a countdown already running (mirrors web armRest).
        guard seconds > 0 else { return }
        // Clear only LOCAL state — do NOT clear the activity's rest here. That
        // runs in its own task and could land after startRest's, tearing down
        // the rest we're about to start. startRest replaces the rest state and
        // reschedules the notification in-order, so it owns the swap.
        stopLocalOnly()
        self.exerciseName = exerciseName
        let state = RestClock.start(total: TimeInterval(seconds), now: now)
        clock = state
        remaining = RestClock.remaining(state, now: now)
        isRunning = true
        WorkoutActivityController.startRestDetached(state, exerciseName: exerciseName)
        startTicking()
    }

    /// Skip the rest. The workout activity reverts to its elapsed face (the
    /// session itself keeps going — `WorkoutClock.end` is what ends it).
    func stop() {
        stopLocalOnly()
        WorkoutActivityController.applyRestDetached(nil, exerciseName: exerciseName)
    }

    func add(seconds: Int) {
        guard isRunning, let state = clock else { return }
        apply(RestClock.add(state, seconds: TimeInterval(seconds)))
    }

    func pause() {
        guard isRunning, let state = clock, !state.paused else { return }
        invalidate()
        apply(RestClock.pause(state, now: now))
    }

    func resume() {
        guard isRunning, let state = clock, state.paused else { return }
        apply(RestClock.resume(state, now: now))
        startTicking()
    }

    /// Adopt the Live Activity's rest state after the user may have driven the
    /// timer from the Lock Screen / Action Button while the app was
    /// backgrounded. Call on foreground.
    func reconcileFromActivity() {
        // No Live Activities on this device/setting → the in-app timer and its
        // notification are the whole story; never clear them from here.
        guard WorkoutActivityController.isSupported else { return }
        guard let snap = WorkoutActivityController.snapshot else {
            if isRunning { stopLocalOnly() } // the whole workout ended elsewhere
            return
        }
        guard let rest = snap.state.rest else {
            if isRunning { stopLocalOnly() } // rest skipped from the Lock Screen
            return
        }
        exerciseName = snap.state.currentLift
        clock = rest
        remaining = RestClock.remaining(rest, now: now)
        isRunning = true
        if rest.paused {
            invalidate()
        } else if remaining <= 0 {
            stopLocalOnly() // expired while backgrounded (the notification already fired)
        } else {
            startTicking()
        }
    }

    // MARK: - Internals

    /// Commit a new clock state locally and push it to the activity +
    /// notification in one step, so the two views of the rest never drift.
    private func apply(_ state: RestClock.State) {
        clock = state
        remaining = RestClock.remaining(state, now: now)
        WorkoutActivityController.applyRestDetached(state, exerciseName: exerciseName)
    }

    private func startTicking() {
        invalidate()
        tick()
        // 0.5s halves the observation churn vs 0.25s — nothing rendered needs
        // sub-second resolution, and the clock's end keeps the countdown accurate.
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func invalidate() {
        timer?.invalidate()
        timer = nil
    }

    /// Clear local state without touching the activity/notification (they were
    /// already handled elsewhere).
    private func stopLocalOnly() {
        invalidate()
        isRunning = false
        remaining = 0
        clock = nil
    }

    private func tick() {
        guard let state = clock, !state.paused else { return }
        remaining = RestClock.remaining(state, now: now)
        if remaining <= 0 {
            invalidate()
            isRunning = false
            clock = nil
            // Swap the activity back to its elapsed face (ends an ad-hoc one).
            WorkoutActivityController.applyRestDetached(nil, exerciseName: exerciseName)
            if hapticsEnabled {
                #if canImport(UIKit)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
            }
        }
    }
}
