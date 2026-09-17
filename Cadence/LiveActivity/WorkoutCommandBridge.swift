import CadenceCore
import Foundation

/// Where a Lock Screen command lands. `LiveActivityIntent` runs in the app's
/// process, so the app installs a handler at launch that reaches its store
/// and its services. This file is also compiled into the widget extension,
/// which installs nothing and never performs — its intents are dispatched to
/// the app. A command with no handler answers honestly instead of doing half
/// the job.
enum WorkoutCommandBridge {
    typealias Handler = @MainActor (WorkoutCommand) async -> String

    @MainActor static var handler: Handler?

    @MainActor
    static func perform(_ command: WorkoutCommand) async -> String {
        guard let handler else { return "Open Cadence to log this set." }
        return await handler(command)
    }
}
