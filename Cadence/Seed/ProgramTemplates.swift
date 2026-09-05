import Foundation
import SwiftData
import CadenceCore

/// Instantiates a program style from ProgramTemplateData (CadenceCore — the
/// data lives there so the Linux test job can enforce parity with the web
/// copy against the shared fixture). Mirrors web createProgramFromTemplate.
enum ProgramTemplates {

    /// Ensure the template's (non-seeded) exercises exist, then create the
    /// program — active only when it's the first, and under a name no other
    /// program holds: Program.name is a unique attribute, so a fixed name
    /// would silently UPSERT into an existing program, resetting its wave
    /// state and doubling its days.
    @discardableResult
    static func instantiate(_ template: ProgramTemplateData.Template, context: ModelContext) throws -> Program {
        // One fetch for the whole library (the Seeder.syncLibrary idiom). If
        // the fetch itself fails we must NOT insert: Exercise.name is unique,
        // and inserting over an unverifiable library would upsert-overwrite
        // the user's records. Throw so Settings can roll back and surface it.
        let existing = try context.fetch(FetchDescriptor<Exercise>())
        let have = Set(existing.map(\.name))
        for e in template.exercises where !have.contains(e.name) {
            context.insert(Exercise(
                name: e.name,
                category: ExerciseCategory(rawValue: e.category) ?? .accessory,
                type: ExerciseType(rawValue: e.type) ?? .bodyweight,
                movementGroup: e.group,
                isUnilateral: e.isUnilateral,
                defaultRestSeconds: e.rest
            ))
        }

        let existingPrograms = try context.fetch(FetchDescriptor<Program>())
        let existingByName = existing.indexedByName()
        let templateByName = Dictionary(uniqueKeysWithValues: template.exercises.map { ($0.name, $0) })
        let historyNames = Set(template.days.flatMap { day in
            day.lifts.flatMap { [$0.exercise, $0.historyExercise].compactMap { $0 } }
                + day.accessories.map(\.exercise)
        })
        let history = try recordedHistory(for: historyNames, context: context)
        let anchorHistory = try anchorIndex(for: historyNames, context: context)
        let shelved = try shelvedNames(context: context)
        let focus = TrainingFocus(rawValue: template.focus) ?? .strength
        let program = Program(
            name: uniqueProgramName(template.name, existing: existingPrograms.map(\.name)),
            focus: focus,
            roundingLb: template.roundingLb,
            isActive: existingPrograms.isEmpty
        )
        context.insert(program)
        // The methodology origin (schema V11): recorded at instantiation,
        // never inferred later. Hand-built programs stay nil.
        program.templateID = template.id
        for (i, d) in template.days.enumerated() {
            let day = ProgramDay(name: d.name, order: i)
            context.insert(day)   // insert before appending children (Seeder pattern)
            // Mutate one side of each SwiftData relationship only. Setting the
            // inverse and appending as well stores the same model reference
            // more than once, which makes editor rows mirror one another.
            program.days.append(day)
            for (slotOrder, l) in d.lifts.enumerated() {
                let exerciseType = existingByName[l.exercise]?.typeRaw
                    ?? templateByName[l.exercise]?.type ?? ExerciseType.dumbbell.rawValue
                let movementGroup = existingByName[l.exercise]?.movementGroup
                    ?? templateByName[l.exercise]?.group ?? ""
                let fallback = ProgrammingDefaultsData.recommendation(
                    exerciseName: l.exercise, slotCategory: ExerciseCategory.main.rawValue,
                    exerciseType: exerciseType
                )
                var base = fallback.weightLb
                var max = fallback.estimatedMaxLb
                let style = PrescriptionStyle(rawValue: l.prescription) ?? .automatic
                let role = LiftRole(rawValue: l.role) ?? .main
                let resolvedStyle = ProgramEngine.resolvedStyle(
                    style, movementGroup: movementGroup, role: role, focus: focus
                )
                let fraction = l.startFraction > 0 ? l.startFraction : resolvedStyle.templateStartFraction
                // Capability first (epic #155 Stage 3): the lifter's own
                // history for this exact lift, else an explicit related-lift
                // rule, else the movement family, else the catalog. The
                // methodology's own fraction converts capability into the
                // starting load — the resolver never sees a gym or a plate.
                    // No defaultE1RMLb on purpose: a conservative-default
                    // anchor must stay empty here so the caller keeps its own
                    // fallback pair, rather than running the catalog number
                    // back through the methodology's start fraction.
                let anchor = TrainingAnchorResolver.resolve(
                    exerciseName: l.historyExercise ?? l.exercise,
                    movementGroup: movementGroup,
                    history: anchorHistory,
                    shelvedExerciseNames: shelved,
                    allowFamilyEstimate: false
                )
                if fraction > 0, let e1RM = anchor.e1RMLb, e1RM > 0 {
                    base = Swift.max(fallback.weightLb, floorTo(fraction * e1RM, step: template.roundingLb))
                    max = (e1RM).rounded()
                }
                let lift = ProgramLift(exerciseName: l.exercise,
                                       role: role,
                                       order: slotOrder,
                                       baseWeightLb: base, estimatedMaxLb: max)
                lift.prescription = style
                lift.exerciseID = existingByName[l.exercise]?.id
                    ?? StableID.exerciseLegacyID(name: l.exercise)
                if l.sets > 0 { lift.doubleProgressionSets = l.sets }
                context.insert(lift)
                day.lifts.append(lift)
            }
            for (slotOrder, a) in d.accessories.enumerated() {
                let exerciseType = existingByName[a.exercise]?.typeRaw
                    ?? templateByName[a.exercise]?.type ?? ExerciseType.dumbbell.rawValue
                let fallback = ProgrammingDefaultsData.recommendation(
                    exerciseName: a.exercise, slotCategory: ExerciseCategory.accessory.rawValue,
                    exerciseType: exerciseType
                )
                var weight = fallback.weightLb
                if a.startFraction > 0, let e1RM = history.bestE1RM[a.exercise], e1RM > 0 {
                    weight = Swift.max(fallback.weightLb,
                                       floorTo(a.startFraction * e1RM, step: template.roundingLb))
                } else if let recent = history.latestWeight[a.exercise], recent > 0 {
                    weight = recent
                }
                let increment = a.incrementLb > 0 ? a.incrementLb : fallback.incrementLb
                let acc = ProgramAccessory(exerciseName: a.exercise, order: slotOrder, sets: a.sets, minReps: a.minReps,
                                           maxReps: a.maxReps, currentReps: a.minReps,
                                           targetSeconds: a.targetSeconds,
                                           durationStepSeconds: a.durationStepSeconds,
                                           weightLb: weight, incrementLb: increment)
                acc.conditioningEffortRaw = a.conditioningEffort
                acc.targetRPE = a.targetRPE
                acc.exerciseID = existingByName[a.exercise]?.id
                    ?? StableID.exerciseLegacyID(name: a.exercise)
                context.insert(acc)
                day.accessories.append(acc)
            }
        }
        return program
    }

    private struct HistorySnapshot {
        var bestE1RM: [String: Double] = [:]
        var latestWeight: [String: Double] = [:]
    }

    /// Known main-lift capacity plus the most recent completed accessory load.
    /// Only workout history is athlete state; defaults remain pure reference
    /// data. This is now an adapter: it normalizes the store's working sets
    /// into samples and delegates the fold (recency ties, lifetime Epley max)
    /// to the shared `AthleteHistory.index`, which web recordedHistory
    /// mirrors through `athleteHistoryIndex`.
    static func athleteHistory(
        for names: Set<String>, context: ModelContext
    ) throws -> [String: AthleteHistory.LiftHistoryProfile] {
        guard !names.isEmpty else { return [:] }
        let sessions = try context.fetch(
            FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.isCompleted })
        )
        var samples: [AthleteHistory.CompletedSetSample] = []
        for session in sessions {
            let timestampMs = session.effectiveCompletionDate.timeIntervalSince1970 * 1000
            for entry in session.exercises {
                guard let name = entry.exercise?.name, names.contains(name) else { continue }
                for set in entry.workingSets where set.weightLb > 0 && set.reps >= 1 {
                    samples.append(AthleteHistory.CompletedSetSample(
                        exerciseName: name, timestampMs: timestampMs,
                        weightLb: set.weightLb, reps: set.reps
                    ))
                }
            }
        }
        return AthleteHistory.index(samples)
    }

    private static func recordedHistory(for names: Set<String>, context: ModelContext) throws -> HistorySnapshot {
        guard !names.isEmpty else { return HistorySnapshot() }
        let sessions = try context.fetch(
            FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.isCompleted })
        )
        var samples: [AthleteHistory.CompletedSetSample] = []
        for session in sessions {
            let timestampMs = session.effectiveCompletionDate.timeIntervalSince1970 * 1000
            for entry in session.exercises {
                guard let name = entry.exercise?.name, names.contains(name) else { continue }
                for set in entry.workingSets where set.weightLb > 0 && set.reps >= 1 {
                    samples.append(AthleteHistory.CompletedSetSample(
                        exerciseName: name, timestampMs: timestampMs,
                        weightLb: set.weightLb, reps: set.reps
                    ))
                }
            }
        }
        var result = HistorySnapshot()
        for (name, profile) in AthleteHistory.index(samples) {
            if let best = profile.allTimeBestE1RMLb { result.bestE1RM[name] = best }
            if let latest = profile.latestCompletedLoadLb { result.latestWeight[name] = latest }
        }
        return result
    }

    /// The history projection the anchor resolver needs: the requested lifts
    /// PLUS every lift a shipped rule or family anchor could estimate from,
    /// so an unseen variation can resolve from the competition lift that
    /// trains it instead of dropping straight to the catalog default.
    static func anchorIndex(
        for names: Set<String>, context: ModelContext
    ) throws -> [String: AthleteHistory.LiftHistoryProfile] {
        var wanted = names
        for rule in TrainingAnchorResolver.defaultRules where names.contains(rule.targetExerciseName) {
            wanted.insert(rule.sourceExerciseName)
        }
        for anchor in TrainingAnchorResolver.defaultFamilyAnchors.values { wanted.insert(anchor) }
        return try athleteHistory(for: wanted, context: context)
    }

    /// Shelved lifts, by name. A shelved lift's own history still counts, but
    /// it must never seed a NEW slot for something else.
    static func shelvedNames(context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<Exercise>()).filter(\.isShelved).map(\.name))
    }

    /// History-aware defaults for a slot added in the custom program editor.
    /// Template creation uses the same rules above, including its optional
    /// history alias and explicit methodology fraction.
    static func bootstrapLift(
        exercise: Exercise,
        role: LiftRole,
        focus: TrainingFocus,
        roundingLb: Double,
        context: ModelContext
    ) throws -> (baseWeightLb: Double, estimatedMaxLb: Double) {
        let fallback = ProgrammingDefaultsData.recommendation(
            exerciseName: exercise.name, slotCategory: ExerciseCategory.main.rawValue,
            exerciseType: exercise.typeRaw
        )
        // Same capability ladder as template instantiation (epic #155
        // Stage 3): exact history, else an explicit related-lift rule, else
        // the movement family, else the catalog default.
        let anchor = TrainingAnchorResolver.resolve(
            exerciseName: exercise.name,
            movementGroup: exercise.movementGroup,
            history: try anchorIndex(for: [exercise.name], context: context),
            shelvedExerciseNames: try shelvedNames(context: context),
            allowFamilyEstimate: false
        )
        guard let e1RM = anchor.e1RMLb, e1RM > 0 else {
            return (fallback.weightLb, fallback.estimatedMaxLb)
        }
        let style = ProgramEngine.resolvedStyle(
            .automatic, movementGroup: exercise.movementGroup, role: role, focus: focus
        )
        return (Swift.max(fallback.weightLb,
                          floorTo(style.templateStartFraction * e1RM, step: roundingLb)),
                e1RM.rounded())
    }

    static func bootstrapAccessory(
        exercise: Exercise,
        context: ModelContext
    ) throws -> (weightLb: Double, incrementLb: Double) {
        let fallback = ProgrammingDefaultsData.recommendation(
            exerciseName: exercise.name, slotCategory: ExerciseCategory.accessory.rawValue,
            exerciseType: exercise.typeRaw
        )
        let history = try recordedHistory(for: [exercise.name], context: context)
        return (history.latestWeight[exercise.name] ?? fallback.weightLb, fallback.incrementLb)
    }

    /// Round DOWN to the plate step: methodology guidance is to err light when
    /// deriving starting weights from an estimated max.
    private static func floorTo(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step + 1e-9).rounded(.down) * step
    }

    /// First free name in "base", "base 2", "base 3"… — shared by the
    /// template and blank-program paths (both must respect name uniqueness).
    static func uniqueProgramName(_ base: String, existing: [String]) -> String {
        let taken = Set(existing)
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}
