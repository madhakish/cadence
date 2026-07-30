import Foundation
import SwiftData
import CadenceCore

/// Completing a set from the Lock Screen, and describing the one that's next.
///
/// Kept out of the intent so the whole cycle — resolve, complete, arm rest,
/// advance — is one testable thing rather than logic living in an AppIntent's
/// `perform()`. The intent stays three lines.
///
/// Everything here runs on the main actor because SwiftData's `mainContext` is
/// main-actor-bound and a `LiveActivityIntent` can arrive on any executor.
@MainActor
enum LockScreenSetService {

    /// What a Lock Screen tap did, so the intent can say it out loud.
    enum Outcome {
        case completed(nextLabel: String?)
        case nothingToComplete
        case unavailable
    }

    /// Complete the set the lifter is looking at, arm its rest, and advance.
    ///
    /// The activity's `CurrentSet` is treated as a **claim, not an
    /// instruction**. The set actually completed is re-derived from the store
    /// through the same `SetLifecycle.currentSetIndex` the logger highlights
    /// with, and the two must agree. If the app moved on while the Lock Screen
    /// was showing a stale card, the tap is refused rather than silently
    /// crediting a set the lifter never saw — an unexplained completed set is
    /// far worse than a button that did nothing.
    static func completeCurrentSet() async -> Outcome {
        guard let snapshot = WorkoutActivityController.snapshot,
              let sessionID = snapshot.state.sessionID,
              let claim = snapshot.state.currentSet else { return .unavailable }
        // `existing` on purpose: a tap arriving while the app sits in the
        // startup recovery screen must not force open the store the app just
        // failed to open.
        guard let container = PersistenceStack.existing ?? (try? PersistenceStack.container())
        else { return .unavailable }

        let context = container.mainContext
        guard let session = try? context.fetch(FetchDescriptor<WorkoutSession>())
            .first(where: { $0.id == sessionID }) else { return .unavailable }
        guard let entry = session.orderedExercises.first(where: { $0.order == claim.exerciseOrder }),
              let set = entry.currentSet,
              set.order == claim.setOrder else { return .nothingToComplete }

        set.status = .completed
        guard PersistenceErrorCenter.shared.save(context, operation: "Completing a set from the Lock Screen")
        else { return .unavailable }

        // Always, unlike the in-app row, which is gated on `autoStartRest`.
        // One tap has to run the whole cycle: there is no reasonable way to
        // hunt for a second button with the phone locked.
        let restSeconds = snapshot.state.defaultRestSeconds
        if restSeconds > 0 {
            await WorkoutActivityController.startRest(
                RestClock.start(total: Double(restSeconds), now: Date().timeIntervalSince1970),
                exerciseName: entry.exercise?.name ?? snapshot.state.currentLift
            )
        }

        let next = nextSet(in: session)
        await WorkoutActivityController.updateCurrentSet(next)
        return .completed(nextLabel: next?.label)
    }

    /// The session's next set to work, searched across exercises in order —
    /// finishing the last set of one lift rolls onto the first of the next
    /// rather than reporting the session done.
    static func nextSet(in session: WorkoutSession) -> WorkoutActivityAttributes.CurrentSet? {
        for entry in session.orderedExercises {
            guard let set = entry.currentSet,
                  let progress = entry.currentSetProgress else { continue }
            return WorkoutActivityAttributes.CurrentSet(
                exerciseOrder: entry.order,
                setOrder: set.order,
                position: progress.position,
                total: progress.total,
                label: label(for: set, in: entry)
            )
        }
        return nil
    }

    /// Formatted here rather than in the widget: the widget is another process
    /// with no unit preference, and a second formatter is a second chance to
    /// render kilograms as pounds.
    static func label(for set: SetEntry, in entry: SessionExercise) -> String {
        if entry.exercise?.type == .conditioning {
            return CardioFormat.setLabel(
                distanceMiles: set.distanceMiles,
                durationSeconds: set.durationSeconds,
                inclinePercent: set.inclinePercent,
                loadLb: CardioFormat.carriesLoad(exerciseName: entry.exercise?.name ?? "") ? set.weightLb : nil
            )
        }
        if let seconds = set.plannedDurationSeconds ?? set.durationSeconds, seconds > 0, set.weightLb <= 0 {
            return CardioFormat.durationLabel(seconds: seconds)
        }
        let weight = set.enteredUnit == .kg
            ? "\(Weight.trim(Weight.kg(fromLb: set.weightLb))) kg"
            : "\(Weight.trim(set.weightLb)) lb"
        let perSide = set.isPerSide ? "/side" : ""
        guard set.weightLb > 0 else { return "\(set.reps) reps" }
        return "\(weight)\(perSide) × \(set.reps)"
    }
}
