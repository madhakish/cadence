import Foundation
import SwiftData
import CadenceCore

/// First-launch seed for non-personal reference data only. Workout history,
/// body metrics, signals, programs, and progression state always start empty.
enum Seeder {

    static func seedIfNeeded(context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<AppSettings>())
        if let settings = existing.first, settings.seededAt != nil { return }

        let settings = existing.first ?? {
            let value = AppSettings()
            context.insert(value)
            return value
        }()

        let existingExercises = try context.fetch(FetchDescriptor<Exercise>())
        let existingNames = Set(existingExercises.map(\.name))
        for exercise in libraryDefinitions() where !existingNames.contains(exercise.name) {
            context.insert(exercise)
        }
        if try context.fetch(FetchDescriptor<Gym>()).isEmpty { seedGym(context: context) }
        settings.seededAt = .now
        do { try context.save() }
        catch { context.rollback(); throw error }
    }

    // MARK: - Exercise library

    /// Generic exercise definitions shared with the web app. Watch sites and
    /// shelving are intentionally unset; those are user-owned health choices.
    static func libraryDefinitions() -> [Exercise] {
        [
            Exercise(name: "Deadlift", category: .main, type: .barbell, movementGroup: "hinge"),
            Exercise(name: "Back Squat", category: .main, type: .barbell, movementGroup: "squat"),
            Exercise(name: "Front Squat", category: .main, type: .barbell, movementGroup: "squat"),
            Exercise(name: "Overhead Squat", category: .main, type: .barbell, movementGroup: "squat"),
            Exercise(name: "Barbell Bench", category: .main, type: .barbell, movementGroup: "press"),
            Exercise(name: "Overhead Press", category: .main, type: .barbell, movementGroup: "press", notes: "Strict barbell press"),
            Exercise(name: "Push Press", category: .main, type: .barbell, movementGroup: "press"),
            Exercise(name: "Push Jerk", category: .main, type: .barbell, movementGroup: "press"),
            Exercise(name: "Split Jerk", category: .main, type: .barbell, movementGroup: "press"),
            Exercise(name: "Incline DB Press", category: .main, type: .dumbbell, movementGroup: "press"),
            Exercise(name: "Flat DB Press", category: .main, type: .dumbbell, movementGroup: "press"),
            Exercise(name: "Seated Upright DB Press", category: .main, type: .dumbbell, movementGroup: "press"),
            Exercise(name: "Overhead DB Press", category: .main, type: .dumbbell, movementGroup: "press"),
            Exercise(name: "Snatch", category: .main, type: .barbell, movementGroup: "olympic"),
            Exercise(name: "Clean & Jerk", category: .main, type: .barbell, movementGroup: "olympic"),
            Exercise(name: "Clean", category: .main, type: .barbell, movementGroup: "olympic"),
            Exercise(name: "Power Clean", category: .main, type: .barbell, movementGroup: "olympic"),
            Exercise(name: "Power Snatch", category: .main, type: .barbell, movementGroup: "olympic"),
            Exercise(name: "Hang Power Clean", category: .accessory, type: .barbell, movementGroup: "olympic", defaultRestSeconds: 180),
            Exercise(name: "Hang Power Snatch", category: .accessory, type: .barbell, movementGroup: "olympic", defaultRestSeconds: 180),
            Exercise(name: "Clean Pull", category: .accessory, type: .barbell, movementGroup: "olympic", defaultRestSeconds: 180),
            Exercise(name: "Snatch Pull", category: .accessory, type: .barbell, movementGroup: "olympic", defaultRestSeconds: 180),
            Exercise(name: "Romanian Deadlift", category: .accessory, type: .barbell, movementGroup: "hinge", defaultRestSeconds: 180),
            Exercise(name: "Snatch-grip Deadlift", category: .accessory, type: .barbell, movementGroup: "hinge", defaultRestSeconds: 180),
            Exercise(name: "Good Morning", category: .accessory, type: .barbell, movementGroup: "hinge", defaultRestSeconds: 120),
            Exercise(name: "Turkish Get-up", category: .accessory, type: .kettlebell, movementGroup: "core", isUnilateral: true),
            Exercise(name: "Single-arm DB Row", category: .accessory, type: .dumbbell, movementGroup: "pull", isUnilateral: true),
            Exercise(name: "Lat Pulldown", category: .accessory, type: .machine, movementGroup: "pull"),
            Exercise(name: "Chest-supported Row", category: .accessory, type: .machine, movementGroup: "pull"),
            Exercise(name: "Ring Row", category: .accessory, type: .bodyweight, movementGroup: "pull", notes: "Face-pull style"),
            Exercise(name: "Band Pull-aparts", category: .accessory, type: .band, movementGroup: "pull", defaultRestSeconds: 60),
            Exercise(name: "Face Pulls", category: .accessory, type: .machine, movementGroup: "pull"),
            Exercise(name: "Y-T-W Raises", category: .accessory, type: .dumbbell, movementGroup: "shoulder", defaultRestSeconds: 60),
            Exercise(name: "Band External Rotation", category: .accessory, type: .band, movementGroup: "shoulder", isUnilateral: true, defaultRestSeconds: 60),
            Exercise(name: "DB Curls", category: .accessory, type: .dumbbell, movementGroup: "arms"),
            Exercise(name: "DB Overhead Triceps Extension", category: .accessory, type: .dumbbell, movementGroup: "arms"),
            Exercise(name: "Walking Lunges", category: .accessory, type: .bodyweight, movementGroup: "squat", isUnilateral: true),
            Exercise(name: "GHD Sit-up", category: .accessory, type: .bodyweight, movementGroup: "core"),
            Exercise(name: "Plank", category: .accessory, type: .timed, movementGroup: "core", defaultRestSeconds: 60),
            Exercise(name: "Side Plank", category: .accessory, type: .timed, movementGroup: "core", isUnilateral: true, defaultRestSeconds: 60),
            Exercise(name: "KB Swing", category: .accessory, type: .kettlebell, movementGroup: "hinge"),
            Exercise(name: "KB Clean", category: .accessory, type: .kettlebell, movementGroup: "olympic", isUnilateral: true),
            Exercise(name: "Dips", category: .accessory, type: .bodyweight, movementGroup: "press"),
            Exercise(name: "Walk", category: .conditioning, type: .conditioning, movementGroup: "conditioning", notes: "Distance / time / incline"),
            Exercise(name: "Run-Walk Intervals", category: .conditioning, type: .conditioning, movementGroup: "conditioning", notes: "Jog min / walk min × rounds"),
            Exercise(name: "Bike", category: .conditioning, type: .conditioning, movementGroup: "conditioning"),
            Exercise(name: "Ruck", category: .conditioning, type: .conditioning, movementGroup: "conditioning"),
        ]
    }

    /// Idempotent library top-up. Existing records remain user-owned; only a
    /// missing movement group is backfilled.
    static func syncLibrary(context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<Exercise>())
        var byName = Dictionary(uniqueKeysWithValues: existing.map { ($0.name, $0) })
        for definition in libraryDefinitions() {
            if let current = byName[definition.name] {
                if current.movementGroup.isEmpty && !definition.movementGroup.isEmpty {
                    current.movementGroup = definition.movementGroup
                }
            } else {
                context.insert(definition)
                byName[definition.name] = definition
            }
        }
        try clearRetiredRestStamps(byName: byName, context: context)
        do { try context.save() }
        catch { context.rollback(); throw error }
    }

    private static func clearRetiredRestStamps(byName: [String: Exercise], context: ModelContext) throws {
        guard let settings = try context.fetch(FetchDescriptor<AppSettings>()).first,
              !settings.restSeedStampsCleared else { return }
        for (name, stamp) in retiredRestStamps {
            if let current = byName[name], current.defaultRestSeconds == stamp {
                current.defaultRestSeconds = 0
            }
        }
        settings.restSeedStampsCleared = true
    }

    static let retiredRestStamps: [String: Int] = [
        "Deadlift": 300, "Back Squat": 300, "Front Squat": 300, "Overhead Squat": 300,
        "Barbell Bench": 300, "Overhead Press": 300, "Push Press": 300, "Push Jerk": 300,
        "Split Jerk": 300, "Incline DB Press": 300, "Flat DB Press": 300,
        "Seated Upright DB Press": 300, "Overhead DB Press": 300,
        "Snatch": 240, "Clean & Jerk": 240, "Clean": 240, "Power Clean": 240, "Power Snatch": 240,
        "Turkish Get-up": 90, "Single-arm DB Row": 90, "Lat Pulldown": 90, "Chest-supported Row": 90,
        "Ring Row": 90, "Face Pulls": 90, "DB Curls": 90, "DB Overhead Triceps Extension": 90,
        "Walking Lunges": 90, "GHD Sit-up": 90, "KB Swing": 90, "KB Clean": 90, "Dips": 90,
        "Back Extension": 90, "Hanging Knee Raise": 90,
    ]

    private static func seedGym(context: ModelContext) {
        context.insert(Gym(name: "Main Gym", isDefault: true, defaultBar: .bar45lb))
    }
}
