import ActivityKit
import Foundation
import UserNotifications

/// Owns the rest Live Activity **and** the paired "Rest over." local
/// notification, so the two never drift. Shared between the app (foreground
/// authority, via `begin`/`apply`/`finish`) and the widget extension's App
/// Intents (background authority, via `pause`/`resume`/`addTime`/`end`, which
/// read the running activity as the source of truth so they work even when the
/// app was relaunched fresh to service a Lock Screen tap).
///
/// The countdown itself needs no updates — the widget renders it from
/// `endDate`. We only push a new `ContentState` when something structural
/// changes (pause, resume, extend, end).
enum RestActivityController {

    /// Matches NotificationService's rest identifier so one owner's schedule
    /// replaces the other's — never two "Rest over." alerts pending at once.
    static let notificationID = "rest-timer"

    static var isSupported: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    private static var current: Activity<RestActivityAttributes>? {
        Activity<RestActivityAttributes>.activities.first
    }

    /// The live state + lift name, if a rest activity is running. Lets the app
    /// reconcile its in-memory timer after the user drove it from the Lock Screen.
    static var snapshot: (state: RestActivityAttributes.ContentState, exerciseName: String)? {
        guard let a = current else { return nil }
        return (a.content.state, a.attributes.exerciseName)
    }

    // MARK: - Foreground authority (called by RestTimer)

    /// Start (or restart) a rest: schedule the notification and, when the OS
    /// allows Live Activities, start the Lock Screen / Dynamic Island activity.
    static func begin(exerciseName: String, total: TimeInterval, endDate: Date) async {
        scheduleNotification(at: endDate, exerciseName: exerciseName)
        guard isSupported else { return }
        await endAllActivities() // one rest at a time
        let state = RestActivityAttributes.ContentState(endDate: endDate, isPaused: false, pausedRemaining: 0, total: total)
        _ = try? Activity.request(
            attributes: RestActivityAttributes(exerciseName: exerciseName),
            content: ActivityContent(state: state, staleDate: endDate.addingTimeInterval(60)),
            pushType: nil
        )
    }

    /// Push an explicit new state (app-side pause/resume/extend) and keep the
    /// notification in step.
    static func apply(_ state: RestActivityAttributes.ContentState, exerciseName: String) async {
        if state.isPaused { cancelNotification() }
        else { scheduleNotification(at: state.endDate, exerciseName: exerciseName) }
        guard let a = current else { return }
        await a.update(ActivityContent(state: state, staleDate: state.isPaused ? nil : state.endDate.addingTimeInterval(60)))
    }

    /// End the rest everywhere.
    static func finish() async {
        cancelNotification()
        await endAllActivities()
    }

    // MARK: - Background authority (called by the Lock Screen App Intents)

    static func pause() async {
        guard let a = current else { return }
        var s = a.content.state
        guard !s.isPaused else { return }
        s.pausedRemaining = max(0, s.endDate.timeIntervalSinceNow)
        s.isPaused = true
        await apply(s, exerciseName: a.attributes.exerciseName)
    }

    static func resume() async {
        guard let a = current else { return }
        var s = a.content.state
        guard s.isPaused else { return }
        s.endDate = Date().addingTimeInterval(max(0, s.pausedRemaining))
        s.isPaused = false
        await apply(s, exerciseName: a.attributes.exerciseName)
    }

    static func addTime(_ seconds: TimeInterval) async {
        guard let a = current else { return }
        var s = a.content.state
        s.total += seconds
        if s.isPaused { s.pausedRemaining = max(0, s.pausedRemaining + seconds) }
        else { s.endDate = s.endDate.addingTimeInterval(seconds) }
        await apply(s, exerciseName: a.attributes.exerciseName)
    }

    static func end() async { await finish() }

    // MARK: - Fire-and-forget wrappers (for the synchronous main-actor RestTimer)

    static func beginDetached(exerciseName: String, total: TimeInterval, endDate: Date) {
        Task { await begin(exerciseName: exerciseName, total: total, endDate: endDate) }
    }

    static func applyDetached(_ state: RestActivityAttributes.ContentState, exerciseName: String) {
        Task { await apply(state, exerciseName: exerciseName) }
    }

    static func finishDetached() {
        Task { await finish() }
    }

    // MARK: - Internals

    private static func endAllActivities() async {
        for a in Activity<RestActivityAttributes>.activities {
            await a.end(nil, dismissalPolicy: .immediate)
        }
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
        content.body = "\(exerciseName) — next set."
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
