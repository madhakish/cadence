import CadenceCore
import Foundation
import SwiftData

/// The one path that changes a set's status — from the logger's control, the
/// hold timer, or a Lock Screen command — and the one place that decides what
/// follows a verdict. Models only: no ActivityKit, no SwiftUI, so the same
/// code runs under the migration test target and inside an intent's
/// background relaunch. The result is on disk before anyone projects it.
@MainActor
enum WorkoutCommandService {
    /// What follows a verdict. Each surface applies it its own way: the logger
    /// moves focus and starts its in-app timer; a Lock Screen command projects
    /// it straight into the Live Activity.
    struct Decision: Equatable {
        /// The exercise that now holds the lifter's attention.
        var focusExerciseIndex: Int?
        /// The lift the next rest is for — pending work only, "" when none.
        var nextExerciseName: String
        /// Seconds of rest to arm, or nil when nothing should start.
        var restSeconds: Int?
        /// The quick-rest default for the focused exercise.
        var defaultRestSeconds: Int
        /// The set the Lock Screen should show now.
        var currentSet: CurrentSetProjection?
    }

    enum Failure: Error, Equatable {
        case sessionNotFound
        case sessionAlreadyBanked
        case setNotFound
        /// The named set is no longer the one to act on: the face was stale.
        case movedOn
        case alreadyResolved
    }

    // MARK: Mutation

    /// Change one set's status and save. Every writer goes through here. A
    /// failed save restores the status, so the shared context never carries
    /// a verdict that was reported as not written.
    static func setStatus(_ status: SetStatus, of set: SetEntry, context: ModelContext) throws {
        let previous = set.status
        set.status = status
        do {
            try context.save()
        } catch {
            set.status = previous
            throw error
        }
    }

    /// Bind a face to the ordered persisted entries and sets, not just their
    /// labels and warmup/work pattern. Equal-shaped replacements must differ.
    static func layout(of session: WorkoutSession) -> String {
        let entries = session.orderedExercises
        let identities = entries.map { entry in
            [entry.persistentModelID] + entry.orderedSets.map(\.persistentModelID)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // An unavailable identity must never authorize a command. Persisted
        // identifiers encode across contexts/relaunches; debug strings don't.
        guard let encoded = try? encoder.encode(identities) else { return "" }
        let description = entries.map { entry in
            "\(entry.exercise?.name ?? "?")#\(entry.orderedSets.map { $0.isWarmup ? "w" : "s" }.joined())"
        }.joined(separator: ";")
        return "ids-v1:" + SetLifecycle.layoutFingerprint(encoded.base64EncodedString() + ";" + description)
    }

    // MARK: Decision

    /// What follows a verdict on `set`: where focus goes (undo returns it to
    /// the set's own exercise; a resolution advances through authored order
    /// to the next exercise with planned work), which lift the next rest is
    /// for, and whether to arm one — the shared `SetLifecycle` rules.
    static func decision(after previous: SetStatus, status: SetStatus, set: SetEntry, entry: SessionExercise,
                         session: WorkoutSession, settings: AppSettings?, restRunning: Bool) -> Decision {
        let ordered = session.orderedExercises
        let resolvedIndex = ordered.firstIndex { $0.persistentModelID == entry.persistentModelID } ?? -1
        let statuses = ordered.map { $0.orderedSets.map(\.status) }
        let focusIndex: Int?
        if status == .planned {
            focusIndex = resolvedIndex >= 0 ? resolvedIndex : nil
        } else {
            focusIndex = SetLifecycle.focusAfterResolving(statuses, resolvedIndex: resolvedIndex)
        }
        let focus = focusIndex.map { ordered[$0] }
        let nextIndex = SetLifecycle.nextPendingExerciseIndex(statuses, after: focusIndex ?? resolvedIndex)
        let nextName = nextIndex.map { ordered[$0].exercise?.name ?? "" } ?? ""
        let restSeconds = SetLifecycle.restAfterCompleting(
            previous: previous, status: status, isWarmup: set.isWarmup,
            restSeconds: smartRestSeconds(for: entry.exercise, role: entry.programRole, settings: settings),
            autoStart: settings?.autoStartRest == true, restRunning: restRunning
        )
        return Decision(
            focusExerciseIndex: focusIndex,
            nextExerciseName: nextName,
            restSeconds: restSeconds,
            defaultRestSeconds: smartRestSeconds(for: focus?.exercise, role: focus?.programRole, settings: settings),
            currentSet: projection(for: session, focus: focus)
        )
    }

    /// The set the Lock Screen shows: the first unresolved set, warmups
    /// included, of the focused exercise — the same rule the logger draws.
    /// With no explicit focus, the first exercise that still has planned work.
    static func projection(for session: WorkoutSession, focus: SessionExercise?) -> CurrentSetProjection? {
        let ordered = session.orderedExercises
        guard let entry = focus ?? ordered.first(where: { $0.orderedSets.contains { $0.status == .planned } }),
              let exerciseIndex = ordered.firstIndex(where: { $0.persistentModelID == entry.persistentModelID })
        else { return nil }
        let sets = entry.orderedSets
        let states = sets.map { SetLifecycle.PresentationState(isWarmup: $0.isWarmup, status: $0.status) }
        guard let setIndex = SetLifecycle.currentPresentationIndex(states) else { return nil }
        let set = sets[setIndex]
        let group = sets.filter { $0.isWarmup == set.isWarmup }
        let ordinal = (group.firstIndex { $0.persistentModelID == set.persistentModelID } ?? 0) + 1
        let type = entry.exercise?.type
        let timed = type == .timed || type == .conditioning
        return CurrentSetProjection(
            exerciseIndex: exerciseIndex, setIndex: setIndex, ordinal: ordinal, total: group.count,
            isWarmup: set.isWarmup, reps: set.reps, loadLb: set.weightLb,
            exerciseName: entry.exercise?.name ?? "",
            durationSeconds: timed ? set.durationSeconds : nil,
            layout: layout(of: session)
        )
    }

    // MARK: Lock Screen commands

    /// Locate the set the face named, refuse a stale face, change the status,
    /// save, and decide what follows. Returns the decision and the sentence
    /// the Lock Screen speaks back.
    static func perform(_ command: WorkoutCommand, settings: AppSettings?, restRunning: Bool,
                        context: ModelContext) throws -> (decision: Decision, message: String) {
        let sessionID: String
        let exerciseIndex: Int
        let setIndex: Int
        let layout: String
        let status: SetStatus
        switch command {
        case let .completeSet(s, e, i, l): (sessionID, exerciseIndex, setIndex, layout, status) = (s, e, i, l, .completed)
        case let .skipSet(s, e, i, l): (sessionID, exerciseIndex, setIndex, layout, status) = (s, e, i, l, .skipped)
        case let .undoSet(s, e, i, l): (sessionID, exerciseIndex, setIndex, layout, status) = (s, e, i, l, .planned)
        }
        let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })
        guard let session = try context.fetch(descriptor).first else { throw Failure.sessionNotFound }
        guard !session.isCompleted else { throw Failure.sessionAlreadyBanked }
        // Indices are array offsets; a face built before the session was
        // reordered or edited must not land on whatever now occupies them.
        guard !layout.isEmpty, layout == Self.layout(of: session) else { throw Failure.movedOn }
        let ordered = session.orderedExercises
        guard ordered.indices.contains(exerciseIndex) else { throw Failure.setNotFound }
        let entry = ordered[exerciseIndex]
        let sets = entry.orderedSets
        guard sets.indices.contains(setIndex) else { throw Failure.setNotFound }
        let set = sets[setIndex]
        let previous = set.status
        switch status {
        case .completed, .skipped:
            guard previous == .planned else { throw Failure.alreadyResolved }
            // Only the entry's first unresolved set may be resolved from a
            // face: a stale face must never resolve the following set.
            let states = sets.map { SetLifecycle.PresentationState(isWarmup: $0.isWarmup, status: $0.status) }
            guard SetLifecycle.currentPresentationIndex(states) == setIndex else { throw Failure.movedOn }
        case .planned:
            guard previous != .planned else { throw Failure.alreadyResolved }
        }
        try setStatus(status, of: set, context: context)
        let decision = decision(after: previous, status: status, set: set, entry: entry,
                                session: session, settings: settings, restRunning: restRunning)
        let name = entry.exercise?.name ?? "Set"
        let message: String
        switch status {
        case .completed:
            if let seconds = decision.restSeconds {
                message = "\(name) logged. Rest \(seconds / 60):\(String(format: "%02d", seconds % 60))."
            } else {
                message = "\(name) logged."
            }
        case .skipped: message = "\(name) set skipped."
        case .planned: message = "\(name) set back to planned."
        }
        return (decision, message)
    }

    /// The sentence a refused command speaks back. Never pretends.
    static func message(for failure: Failure) -> String {
        switch failure {
        case .sessionNotFound: return "Open Cadence to log this set."
        case .sessionAlreadyBanked: return "That workout is already banked."
        case .setNotFound: return "That set is no longer in the workout."
        case .movedOn: return "The workout moved on. Open Cadence to log."
        case .alreadyResolved: return "Already logged."
        }
    }
}

/// Smart per-exercise rest via the shared CadenceCore precedence (per-exercise
/// rest → program role → movementGroup bucket); no exercise → accessory bucket.
func smartRestSeconds(for exercise: Exercise?, role: String? = nil, settings: AppSettings?) -> Int {
    let config = settings?.restConfig ?? .standard
    guard let ex = exercise else { return config.accessorySeconds }
    return RestDefaults.seconds(category: ex.categoryRaw, movementGroup: ex.movementGroup, role: role,
                                config: config,
                                exerciseDefaultRest: ex.defaultRestSeconds)
}
