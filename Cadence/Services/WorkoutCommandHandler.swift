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
        // Same definition as the in-app timer and the controller's own rest
        // face: a paused rest is still the rest in progress.
        let restRunning = WorkoutActivityController.snapshot?.state.rest
            .map { $0.paused || RestClock.remaining($0, now: now) > 0 } ?? false
        do {
            let result = try WorkoutCommandService.perform(command, settings: settings,
                                                           restRunning: restRunning, context: context)
            // The detached wrappers join the controller's serialized chain, so
            // a scenePhase republish racing this tap lands in order.
            WorkoutActivityController.updateContextDetached(
                currentLift: result.decision.nextExerciseName,
                defaultRestSeconds: result.decision.defaultRestSeconds,
                currentSet: result.decision.currentSet
            )
            if let seconds = result.decision.restSeconds {
                WorkoutActivityController.startRestDetached(
                    RestClock.start(total: TimeInterval(seconds), now: now),
                    exerciseName: result.decision.nextExerciseName
                )
            }
            return result.message
        } catch let failure as WorkoutCommandService.Failure {
            // A Live Activity button renders no dialog, so a refusal must show
            // as a corrected face: re-project the saved state (or end the
            // activity for a banked session) before answering.
            reproject(after: failure, sessionID: command.sessionID, settings: settings, context: context)
            return WorkoutCommandService.message(for: failure)
        } catch {
            // Same discipline as the in-app path (PersistenceErrorCenter):
            // nothing reported as unsaved may linger in the shared context.
            context.rollback()
            return "Couldn't save that set. Open Cadence."
        }
    }

    private static func reproject(after failure: WorkoutCommandService.Failure, sessionID: String,
                                  settings: AppSettings?, context: ModelContext) {
        if failure == .sessionAlreadyBanked {
            WorkoutActivityController.endSessionDetached()
            return
        }
        let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })
        guard let session = try? context.fetch(descriptor).first else { return }
        let projection = WorkoutCommandService.projection(for: session, focus: nil)
        let entry = projection.map { session.orderedExercises[$0.exerciseIndex] }
        WorkoutActivityController.updateContextDetached(
            currentLift: projection?.exerciseName ?? "",
            defaultRestSeconds: smartRestSeconds(for: entry?.exercise, role: entry?.programRole, settings: settings),
            currentSet: projection
        )
    }
}

private extension WorkoutCommand {
    var sessionID: String {
        switch self {
        case let .completeSet(id, _, _, _), let .skipSet(id, _, _, _), let .undoSet(id, _, _, _): return id
        }
    }
}
