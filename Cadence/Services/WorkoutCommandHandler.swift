import CadenceCore
import Foundation
import SwiftData

/// The app's end of WorkoutCommandBridge: reach the store the views observe,
/// run the one command service, and only then project the saved result into
/// the Live Activity — a face never shows a state that was not written.
@MainActor
enum WorkoutCommandHandler {
    static func install() {
        WorkoutCommandBridge.handler = { command in await handle(command) }
    }

    static func handle(_ command: WorkoutCommand) async -> String {
        guard let container = AppBootstrap.forCommands().container else {
            return "Open Cadence to log this set."
        }
        let context = container.mainContext
        let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first
        let now = Date().timeIntervalSince1970
        let restRunning = WorkoutActivityController.snapshot?.state.rest
            .map { !$0.paused && RestClock.remaining($0, now: now) > 0 } ?? false
        do {
            let result = try WorkoutCommandService.perform(command, settings: settings,
                                                           restRunning: restRunning, context: context)
            await WorkoutActivityController.updateContext(
                currentLift: result.decision.nextExerciseName,
                defaultRestSeconds: result.decision.defaultRestSeconds,
                currentSet: result.decision.currentSet
            )
            if let seconds = result.decision.restSeconds {
                await WorkoutActivityController.startRest(
                    RestClock.start(total: TimeInterval(seconds), now: now),
                    exerciseName: result.decision.nextExerciseName
                )
            }
            return result.message
        } catch let failure as WorkoutCommandService.Failure {
            return WorkoutCommandService.message(for: failure)
        } catch {
            return "Couldn't save that set. Open Cadence."
        }
    }
}
