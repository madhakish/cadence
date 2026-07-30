import AppIntents

/// Lock Screen / Dynamic Island buttons + the quick rest control.
/// `LiveActivityIntent` runs in the app's process (relaunched in the
/// background if needed), so each one operates on the running activity via
/// `WorkoutActivityController` rather than any in-memory timer — they work
/// even when the app was relaunched fresh to service a Lock Screen tap.

/// Complete the set on the Lock Screen card, start its rest, and load the next
/// one — the whole between-sets cycle in one tap, with the phone locked.
///
/// Unlike the in-app row this always arms rest: `autoStartRest` defaults off,
/// and a Done button that completed the set and then sat there would miss the
/// point of driving the session without unlocking.
struct CompleteCurrentSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Complete set"
    static var description = IntentDescription("Log the current set as done, start your rest, and move to the next set.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch await LockScreenSetService.completeCurrentSet() {
        case let .completed(nextLabel):
            return .result(dialog: IntentDialog(stringLiteral: nextLabel.map { "Set logged. Up next: \($0)." }
                                                ?? "Set logged. That's the last one."))
        case .nothingToComplete:
            return .result(dialog: "That set has already been logged.")
        case .unavailable:
            return .result(dialog: "Couldn't reach your workout — open Cadence and try again.")
        }
    }
}

struct PauseRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause rest"
    func perform() async throws -> some IntentResult {
        await WorkoutActivityController.pauseRest()
        return .result()
    }
}

struct ResumeRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Resume rest"
    func perform() async throws -> some IntentResult {
        await WorkoutActivityController.resumeRest()
        return .result()
    }
}

struct AddRestTimeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Add 30 seconds"
    func perform() async throws -> some IntentResult {
        await WorkoutActivityController.addRestTime(30)
        return .result()
    }
}

struct EndRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End rest"
    func perform() async throws -> some IntentResult {
        await WorkoutActivityController.skipRest()
        return .result()
    }
}

struct PauseWorkoutIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause workout clock"
    func perform() async throws -> some IntentResult {
        await WorkoutActivityController.pauseWorkout()
        return .result()
    }
}

struct ResumeWorkoutIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Resume workout clock"
    func perform() async throws -> some IntentResult {
        await WorkoutActivityController.resumeWorkout()
        return .result()
    }
}

struct EndWorkoutIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End workout"
    func perform() async throws -> some IntentResult {
        await WorkoutActivityController.endSession()
        return .result()
    }
}

/// The one-button rest control, wired to the Action Button (via App
/// Shortcuts) and the iOS 18 Control Center control: resting → skip;
/// working → arm the current lift's default rest; no workout → arm a
/// standalone 3:00. `LiveActivityIntent` so it can start/update the
/// activity from the background without opening the app.
struct ToggleRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Rest timer"
    static var description = IntentDescription("Start rest for the current lift, or skip the rest that's running.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await WorkoutActivityController.toggleRest()
        return .result(dialog: IntentDialog(stringLiteral: outcome))
    }
}
