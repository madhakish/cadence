import Foundation
import SwiftData
import CadenceCore

/// Builds the canonical ad-hoc activity session shape (#166): one completed,
/// off-program `WorkoutSession` holding the kind's canonical conditioning
/// entry with one completed duration set, plus the typed `ActivityDetail`.
/// Wood splitting is the first registered kind. Duration and implement load
/// live only on the set — the detail record never duplicates them
/// (INV-WOOD-WORK-DOES-NOT-GUESS keeps every optional user-entered).
enum ActivitySession {

    /// Wood-splitting facts (kind `woodSplitting`). A future kind carries
    /// its own typed facts struct rather than widening this one.
    struct WoodSplittingFacts {
        var rounds: Int?
        var splitPieces: Int?
        var estimatedStrikes: Int?
        var cordVolume: Double?
    }

    struct Input {
        var kind: ActivityKind
        var startDate: Date
        var durationSeconds: Int
        var sessionRPE: Double?
        /// Weight of the implement carried through the work (the splitting
        /// maul), recorded on the canonical set when supplied.
        var loadLb: Double?
        var notes: String
        var woodSplitting: WoodSplittingFacts?
        /// The implement field's entry denomination. `loadLb` remains the
        /// canonical stored value; this only restores the keyboard/display
        /// choice when a banked activity is edited.
        var enteredUnit: WeightUnit = .lb
    }

    enum Error: LocalizedError {
        case invalidDuration
        case invalidSessionRPE
        case invalidValue(String)
        case missingExercise(String)
        case invalidSessionShape

        var errorDescription: String? {
            switch self {
            case .invalidDuration: return "Duration must be greater than zero."
            case .invalidSessionRPE: return "Session RPE must be between 1 and 10."
            case .invalidValue(let label): return "\(label) must be a real number, zero or more."
            case .missingExercise(let name):
                return "The exercise library is missing \(name). Sync or restore the library, then try again."
            case .invalidSessionShape:
                return "This activity record is incomplete and can't be edited safely."
            }
        }
    }

    /// Every recorded number the importers require non-negative and finite.
    /// Nil stays nil — absence is preserved, never repaired to a zero
    /// (INV-WOOD-WORK-DOES-NOT-GUESS).
    private static func requireNonNegative(_ value: Double?, _ label: String) throws {
        guard let value else { return }
        guard value.isFinite, value >= 0 else { throw Error.invalidValue(label) }
    }

    private static func requireNonNegative(_ value: Int?, _ label: String) throws {
        guard let value else { return }
        guard value >= 0 else { throw Error.invalidValue(label) }
    }

    private static func validatedExercise(input: Input, context: ModelContext) throws -> Exercise {
        guard input.durationSeconds > 0 else { throw Error.invalidDuration }
        // The write site is the guard: the recorded contract is 1.0–10.0,
        // and an out-of-contract RPE would persist as a "valid" row whose
        // workload can never derive and whose export web refuses to restore.
        if let rpe = input.sessionRPE, !ActivityWorkload.sessionRPERange.contains(rpe) {
            throw Error.invalidSessionRPE
        }
        // Kind-specific facts attach only for their own kind, so a stray
        // field can never masquerade as another activity's data.
        let wood = input.kind == .woodSplitting ? input.woodSplitting : nil
        // The same reasoning as the RPE guard, for every remaining recorded
        // number: both importers require these non-negative and finite, so an
        // unguarded write banks a row whose own backup neither client will
        // restore — and a non-finite Double makes JSONEncoder refuse the
        // export outright, leaving the user with no backup at all.
        try requireNonNegative(input.loadLb, "Implement weight")
        try requireNonNegative(wood?.rounds, "Rounds")
        try requireNonNegative(wood?.splitPieces, "Split pieces")
        try requireNonNegative(wood?.estimatedStrikes, "Estimated strikes")
        try requireNonNegative(wood?.cordVolume, "Cords split")
        let exerciseName = input.kind.exerciseName
        var lookup = FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == exerciseName })
        lookup.fetchLimit = 1
        guard let exercise = try context.fetch(lookup).first else {
            throw Error.missingExercise(exerciseName)
        }
        return exercise
    }

    static func create(input: Input, context: ModelContext) throws -> WorkoutSession {
        let exercise = try validatedExercise(input: input, context: context)
        let wood = input.kind == .woodSplitting ? input.woodSplitting : nil

        // Banked already complete: quick logging never opens the set-by-set
        // logger, and it must never advance program state, so no program
        // fields are stamped (INV-WOOD-WORK-USES-ONE-TIMELINE).
        let session = WorkoutSession(date: input.startDate, notes: input.notes)
        session.isCompleted = true
        session.completedAt = input.startDate.addingTimeInterval(TimeInterval(input.durationSeconds))
        context.insert(session)

        // Insert-then-append, touching only the parent collection of each
        // inverse pair — mirrors ProgramSession; assigning the child inverse
        // as well can persist aliased rows (see normalizeRelationshipAliases).
        let entry = SessionExercise(order: 0, exercise: exercise)
        entry.exerciseID = exercise.id
        context.insert(entry)
        session.exercises.append(entry)

        // An unrecorded implement weight banks 0, the same "unloaded"
        // encoding every other conditioning set in the app uses (a run, a
        // row, a walk): `SetEntry.weightLb` is non-optional, so absence is
        // not representable there and 0 is the canonical reading, not an
        // invented fact. The kind's OPTIONAL typed facts live on
        // ActivityDetail, where nil round-trips as nil.
        let set = SetEntry(
            order: 0,
            weightLb: input.loadLb ?? 0,
            reps: 0,
            status: .completed,
            enteredUnit: input.enteredUnit,
            durationSeconds: input.durationSeconds,
            loadBasis: exercise.loadBasis,
            implementCount: exercise.resolvedImplementCount,
            prescriptionBlock: .conditioning
        )
        context.insert(set)
        entry.sets.append(set)

        let detail = ActivityDetail(
            kindRaw: input.kind.rawValue,
            sessionRPE: input.sessionRPE,
            rounds: wood?.rounds,
            splitPieces: wood?.splitPieces,
            estimatedStrikes: wood?.estimatedStrikes,
            cordVolume: wood?.cordVolume
        )
        context.insert(detail)
        session.activityDetail = detail
        return session
    }

    /// Edits the same canonical row the quick logger created. This is not a
    /// second workout path: it keeps the existing session identity and its
    /// off-program shape, changing only the user-entered activity facts.
    static func update(session: WorkoutSession, input: Input, context: ModelContext) throws {
        let exercise = try validatedExercise(input: input, context: context)
        let wood = input.kind == .woodSplitting ? input.woodSplitting : nil
        guard let detail = session.activityDetail,
              let entry = session.orderedExercises.first,
              let set = entry.orderedSets.first
        else { throw Error.invalidSessionShape }

        session.date = input.startDate
        session.completedAt = input.startDate.addingTimeInterval(TimeInterval(input.durationSeconds))
        session.notes = input.notes
        session.isCompleted = true

        entry.exercise = exercise
        entry.exerciseID = exercise.id
        set.weightLb = input.loadLb ?? 0
        set.enteredUnit = input.enteredUnit
        set.durationSeconds = input.durationSeconds
        set.status = .completed
        set.reps = 0
        set.loadBasis = exercise.loadBasis
        set.implementCount = exercise.resolvedImplementCount
        set.prescriptionBlock = .conditioning

        detail.kindRaw = input.kind.rawValue
        detail.sessionRPE = input.sessionRPE
        detail.rounds = wood?.rounds
        detail.splitPieces = wood?.splitPieces
        detail.estimatedStrikes = wood?.estimatedStrikes
        detail.cordVolume = wood?.cordVolume
    }

    /// Session-RPE workload (arbitrary units), derivable only when the
    /// kind's entry holds completed duration work and an RPE was recorded.
    /// The entry is matched by the stable exercise id first — it survives a
    /// library rename and a bundle restored without an exercises collection
    /// — with the live name as the fallback; every completed duration set
    /// it holds counts, because sets stay independently addable. Mirrors
    /// web `C.activityWorkload` for the math.
    static func workload(for session: WorkoutSession) -> ActivityWorkload? {
        guard let detail = session.activityDetail, let kind = detail.kind else { return nil }
        let kindID = StableID.exerciseLegacyID(name: kind.exerciseName)
        let entry = session.orderedExercises.first {
            $0.exerciseID == kindID || $0.exercise?.name == kind.exerciseName
        }
        let seconds = entry?.workingSets.compactMap(\.durationSeconds).reduce(0, +)
        return ActivityWorkload(durationSeconds: seconds, sessionRPE: detail.sessionRPE)
    }
}
