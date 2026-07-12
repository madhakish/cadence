import ActivityKit
import CadenceCore
import Foundation
import UserNotifications

/// Owns the workout Live Activity **and** the paired "Rest over." local
/// notification, so the two never drift. Shared between the app (foreground
/// authority, via `WorkoutClock`/`RestTimer`) and the widget extension's App
/// Intents (background authority — `LiveActivityIntent` relaunches the app
/// process, so these statics read the running activity as the source of truth
/// even when the app was killed).
///
/// Neither face needs periodic updates — the widget renders the stopwatch from
/// `startDate` and the countdown from `rest.endEpoch`. We only push a new
/// `ContentState` when something structural changes (lift switch, rest
/// start/pause/resume/extend/skip, session end).
enum WorkoutActivityController {

    /// Matches NotificationService's rest identifier so one owner's schedule
    /// replaces the other's — never two "Rest over." alerts pending at once.
    static let notificationID = "rest-timer"

    static var isSupported: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    private static var current: Activity<WorkoutActivityAttributes>? {
        Activity<WorkoutActivityAttributes>.activities.first
    }

    /// The live activity's full picture, if one is running. Lets the app
    /// reconcile its in-memory clocks after the user drove the timer from the
    /// Lock Screen / Action Button while backgrounded.
    static var snapshot: (startDate: Date, isAdHoc: Bool, state: WorkoutActivityAttributes.ContentState)? {
        guard let a = current else { return nil }
        return (a.attributes.startDate, a.attributes.isAdHoc, a.content.state)
    }

    private static var now: Double { Date().timeIntervalSince1970 }

    // MARK: - Foreground authority (WorkoutClock)

    /// Start (or refresh) the session activity. Same `startDate` as the one
    /// already running → just refresh the context (re-entering the session
    /// screen, or the clock re-adopting after an app relaunch); otherwise tear
    /// down whatever is up and start fresh. A rest running on the torn-down
    /// activity (quick rest armed before the session opened) carries over.
    static func beginSession(startDate: Date, currentLift: String, defaultRestSeconds: Int) async {
        guard isSupported else { return }
        if let a = current, a.attributes.startDate == startDate, !a.attributes.isAdHoc {
            var s = a.content.state
            s.currentLift = currentLift
            s.defaultRestSeconds = defaultRestSeconds
            await a.update(content(for: s))
            return
        }
        let carriedRest = current.flatMap { activeRest($0.content.state.rest) }
        await endAllActivities()
        let state = WorkoutActivityAttributes.ContentState(
            currentLift: currentLift, defaultRestSeconds: defaultRestSeconds, rest: carriedRest
        )
        _ = try? Activity.request(
            attributes: WorkoutActivityAttributes(startDate: startDate, isAdHoc: false),
            content: content(for: state),
            pushType: nil
        )
    }

    /// The lift being worked changed (or its smart rest did) — keep the
    /// elapsed face and the quick-rest default honest.
    static func updateContext(currentLift: String, defaultRestSeconds: Int) async {
        guard let a = current else { return }
        var s = a.content.state
        s.currentLift = currentLift
        s.defaultRestSeconds = defaultRestSeconds
        await a.update(content(for: s))
    }

    /// Arm a rest: schedule the "Rest over." notification and swap the
    /// activity to the rest face. With no activity running (quick rest from
    /// the Action Button / Control Center before any session) an ad-hoc one
    /// is born whose stopwatch starts at the rest's start.
    static func startRest(_ rest: RestClock.State, exerciseName: String) async {
        scheduleNotification(at: Date(timeIntervalSince1970: rest.endEpoch), exerciseName: exerciseName)
        guard isSupported else { return }
        if let a = current {
            var s = a.content.state
            if !exerciseName.isEmpty { s.currentLift = exerciseName }
            s.rest = rest
            await a.update(content(for: s))
        } else {
            let state = WorkoutActivityAttributes.ContentState(
                currentLift: exerciseName, defaultRestSeconds: Int(rest.total), rest: rest
            )
            _ = try? Activity.request(
                attributes: WorkoutActivityAttributes(
                    startDate: Date(timeIntervalSince1970: rest.endEpoch - rest.total), isAdHoc: true
                ),
                content: content(for: state),
                pushType: nil
            )
        }
    }

    /// Push a new rest state (pause/resume/extend) — or `nil` to clear the
    /// rest — and keep the notification in step. Clearing the rest on an
    /// ad-hoc activity ends it outright (a stopwatch with no session behind
    /// it means nothing).
    static func applyRest(_ rest: RestClock.State?, exerciseName: String) async {
        if let rest, !rest.paused {
            scheduleNotification(at: Date(timeIntervalSince1970: rest.endEpoch), exerciseName: exerciseName)
        } else {
            cancelNotification()
        }
        guard let a = current else { return }
        if rest == nil && a.attributes.isAdHoc {
            await endAllActivities()
            return
        }
        var s = a.content.state
        s.rest = rest
        await a.update(content(for: s))
    }

    /// The workout is over (banked or abandoned) — end the activity and any
    /// pending rest alert.
    static func endSession() async {
        cancelNotification()
        await endAllActivities()
    }

    /// Push the workout clock's origin/pause state (pause, resume, reset).
    static func updateStopwatch(origin: Date, pausedAt: Date?) async {
        guard let a = current else { return }
        var s = a.content.state
        s.stopwatchStart = origin
        s.stopwatchPausedAt = pausedAt
        await a.update(content(for: s))
    }

    // MARK: - Background authority (Lock Screen / Action Button / Control Center intents)

    static func pauseRest() async {
        guard let a = current, let r = a.content.state.rest, !r.paused else { return }
        await applyRest(RestClock.pause(r, now: now), exerciseName: a.content.state.currentLift)
    }

    static func resumeRest() async {
        guard let a = current, let r = a.content.state.rest, r.paused else { return }
        await applyRest(RestClock.resume(r, now: now), exerciseName: a.content.state.currentLift)
    }

    static func addRestTime(_ seconds: Double) async {
        guard let a = current, let r = a.content.state.rest else { return }
        await applyRest(RestClock.add(r, seconds: seconds), exerciseName: a.content.state.currentLift)
    }

    static func skipRest() async {
        guard let a = current, a.content.state.rest != nil else { return }
        await applyRest(nil, exerciseName: a.content.state.currentLift)
    }

    /// Pause the workout clock from the Lock Screen / Dynamic Island.
    static func pauseWorkout() async {
        guard let a = current, a.content.state.stopwatchPausedAt == nil else { return }
        let origin = a.content.state.stopwatchStart ?? a.attributes.startDate
        await updateStopwatch(origin: origin, pausedAt: Date())
    }

    /// Resume it: the origin shifts forward by the paused span, so elapsed
    /// picks up exactly where it froze.
    static func resumeWorkout() async {
        guard let a = current, let paused = a.content.state.stopwatchPausedAt else { return }
        let origin = a.content.state.stopwatchStart ?? a.attributes.startDate
        await updateStopwatch(origin: origin.addingTimeInterval(Date().timeIntervalSince(paused)), pausedAt: nil)
    }

    /// One-button rest control (Action Button / Control Center): a live rest →
    /// skip it; a workout with no rest → arm the current lift's default; no
    /// workout at all → arm a standalone 3:00. Returns the spoken/shown result.
    static func toggleRest() async -> String {
        if let a = current, activeRest(a.content.state.rest) != nil {
            await skipRest()
            return "Rest skipped."
        }
        let lift = current?.content.state.currentLift ?? ""
        let stored = current?.content.state.defaultRestSeconds ?? 0
        let seconds = stored > 0 ? stored : 180
        await startRest(RestClock.start(total: Double(seconds), now: now), exerciseName: lift)
        let label = mmss(seconds)
        return lift.isEmpty ? "Resting \(label)." : "Resting \(label) — \(lift)."
    }

    // MARK: - Fire-and-forget wrappers (for the synchronous main-actor callers)
    //
    // SERIALIZED: each wrapper chains onto the previous one instead of
    // spawning a free Task. Unordered tasks were the "timer won't stop" bug —
    // tap ✕ (applyRest(nil)) while an earlier update was still in flight and
    // the stale update could land second, resurrecting the rest face on the
    // Lock Screen while the app believed the timer was stopped.

    private static var chain: Task<Void, Never> = Task {}

    private static func enqueue(_ op: @escaping @Sendable () async -> Void) {
        chain = Task { [previous = chain] in
            await previous.value
            await op()
        }
    }

    static func beginSessionDetached(startDate: Date, currentLift: String, defaultRestSeconds: Int) {
        enqueue { await beginSession(startDate: startDate, currentLift: currentLift, defaultRestSeconds: defaultRestSeconds) }
    }

    static func updateContextDetached(currentLift: String, defaultRestSeconds: Int) {
        enqueue { await updateContext(currentLift: currentLift, defaultRestSeconds: defaultRestSeconds) }
    }

    static func startRestDetached(_ rest: RestClock.State, exerciseName: String) {
        enqueue { await startRest(rest, exerciseName: exerciseName) }
    }

    static func applyRestDetached(_ rest: RestClock.State?, exerciseName: String) {
        enqueue { await applyRest(rest, exerciseName: exerciseName) }
    }

    static func updateStopwatchDetached(origin: Date, pausedAt: Date?) {
        enqueue { await updateStopwatch(origin: origin, pausedAt: pausedAt) }
    }

    static func endSessionDetached() {
        enqueue { await endSession() }
    }

    // MARK: - Internals

    /// A rest that still means something: running with time left, or paused
    /// (a paused 0:00 was deliberately frozen). An expired countdown is spent.
    private static func activeRest(_ rest: RestClock.State?) -> RestClock.State? {
        guard let rest else { return nil }
        return (rest.paused || RestClock.remaining(rest, now: now) > 0) ? rest : nil
    }

    /// Rest face goes stale a minute past the countdown (the widget shows
    /// 0:00 until the app next reconciles); the elapsed face never does —
    /// the OS's own Live Activity lifetime cap handles abandonment.
    private static func content(for state: WorkoutActivityAttributes.ContentState) -> ActivityContent<WorkoutActivityAttributes.ContentState> {
        var stale: Date?
        if let rest = state.rest, !rest.paused {
            stale = Date(timeIntervalSince1970: rest.endEpoch + 60)
        }
        return ActivityContent(state: state, staleDate: stale)
    }

    private static func endAllActivities() async {
        for a in Activity<WorkoutActivityAttributes>.activities {
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func mmss(_ seconds: Int) -> String {
        String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }

    /// Mirror of NotificationService.scheduleRestDone (kept in sync so the
    /// widget extension needn't link the app's service layer).
    private static func scheduleNotification(at endDate: Date, exerciseName: String) {
        let seconds = endDate.timeIntervalSinceNow
        cancelNotification()
        // UNTimeIntervalNotificationTrigger requires an interval >= 1s or it
        // throws; under a second the rest is effectively over — skip it.
        guard seconds >= 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest over."
        content.body = exerciseName.isEmpty ? "Next set." : "\(exerciseName) — next set."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        )
    }

    private static func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
    }
}
