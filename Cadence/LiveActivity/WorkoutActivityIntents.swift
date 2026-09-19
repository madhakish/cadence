import AppIntents
import CadenceCore

/// Lock Screen / Dynamic Island buttons + the quick rest control.
/// `LiveActivityIntent` runs in the app's process (relaunched in the
/// background if needed), so each one operates on the running activity via
/// `WorkoutActivityController` rather than any in-memory timer — they work
/// even when the app was relaunched fresh to service a Lock Screen tap.

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

/// Complete the set the Lock Screen face names. The set is identified
/// structurally and re-derived when the command runs, so a stale face never
/// completes the following set — it says the workout moved on instead.
struct CompleteSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Complete set"
    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Exercise") var exerciseIndex: Int
    @Parameter(title: "Set") var setIndex: Int
    @Parameter(title: "Layout") var layout: String

    init() {}
    init(sessionID: String, exerciseIndex: Int, setIndex: Int, layout: String) {
        self.sessionID = sessionID
        self.exerciseIndex = exerciseIndex
        self.setIndex = setIndex
        self.layout = layout
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await WorkoutCommandBridge.perform(
            .completeSet(sessionID: sessionID, exerciseIndex: exerciseIndex, setIndex: setIndex, layout: layout))
        return .result(dialog: IntentDialog(stringLiteral: outcome))
    }
}

/// Skip the set the face names, with the same structural identity and
/// stale-face refusal as completing it.
struct SkipSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip set"
    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Exercise") var exerciseIndex: Int
    @Parameter(title: "Set") var setIndex: Int
    @Parameter(title: "Layout") var layout: String

    init() {}
    init(sessionID: String, exerciseIndex: Int, setIndex: Int, layout: String) {
        self.sessionID = sessionID
        self.exerciseIndex = exerciseIndex
        self.setIndex = setIndex
        self.layout = layout
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await WorkoutCommandBridge.perform(
            .skipSet(sessionID: sessionID, exerciseIndex: exerciseIndex, setIndex: setIndex, layout: layout))
        return .result(dialog: IntentDialog(stringLiteral: outcome))
    }
}

/// Return the set the face names to planned — the one-tap undo the logger
/// also offers. Same identity rules; never touches a different set.
struct UndoSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Undo set"
    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Exercise") var exerciseIndex: Int
    @Parameter(title: "Set") var setIndex: Int
    @Parameter(title: "Layout") var layout: String

    init() {}
    init(sessionID: String, exerciseIndex: Int, setIndex: Int, layout: String) {
        self.sessionID = sessionID
        self.exerciseIndex = exerciseIndex
        self.setIndex = setIndex
        self.layout = layout
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await WorkoutCommandBridge.perform(
            .undoSet(sessionID: sessionID, exerciseIndex: exerciseIndex, setIndex: setIndex, layout: layout))
        return .result(dialog: IntentDialog(stringLiteral: outcome))
    }
}
