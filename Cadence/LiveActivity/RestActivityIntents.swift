import AppIntents

/// Lock Screen / Dynamic Island buttons. `LiveActivityIntent` runs in the app's
/// process (relaunched in the background if needed), so each one operates on the
/// running activity via `RestActivityController` rather than any in-memory timer.

struct PauseRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause rest"
    func perform() async throws -> some IntentResult {
        await RestActivityController.pause()
        return .result()
    }
}

struct ResumeRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Resume rest"
    func perform() async throws -> some IntentResult {
        await RestActivityController.resume()
        return .result()
    }
}

struct AddRestTimeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Add 30 seconds"
    func perform() async throws -> some IntentResult {
        await RestActivityController.addTime(30)
        return .result()
    }
}

struct EndRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End rest"
    func perform() async throws -> some IntentResult {
        await RestActivityController.end()
        return .result()
    }
}
