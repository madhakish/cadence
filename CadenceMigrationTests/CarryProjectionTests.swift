import CadenceCore
import Foundation
import SwiftData
import XCTest

@MainActor
final class CarryProjectionTests: XCTestCase {
    func testMixedRepHistoryNeverSuppressesDistanceVolumeRecord() throws {
        let schema = Schema(versionedSchema: CadenceSchemaV15.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let exercise = Exercise(name: "Farmer Carry", category: .accessory, type: .dumbbell,
                                loadBasis: .perImplement, implementCount: 2)
        context.insert(exercise)
        let pastDate = Date(timeIntervalSince1970: 1_700_000_000)
        func addSession(date: Date, distances: [Double?], loads: [Double], reps: [Int]) {
            let workout = WorkoutSession(date: date)
            context.insert(workout)
            workout.isCompleted = true
            let entry = SessionExercise(order: 0, exercise: exercise)
            context.insert(entry)
            workout.exercises = [entry]
            entry.sets = distances.indices.map { index in
                let set = SetEntry(order: index, weightLb: loads[index], reps: reps[index],
                                   distanceMiles: distances[index].map { CardioFormat.miles(fromYards: $0) },
                                   loadBasis: .perImplement, implementCount: 2)
                context.insert(set)
                set.status = .completed
                return set
            }
        }
        addSession(date: pastDate, distances: [nil, 40], loads: [600, 50], reps: [100, 1])
        addSession(date: pastDate.addingTimeInterval(86400), distances: [60], loads: [50], reps: [1])
        try context.save()
        let history = try MilestoneProjection.priorHistory(for: exercise.name, basis: .perImplement,
            before: pastDate.addingTimeInterval(86400), context: context, distanceCarries: true)
        XCTAssertEqual(history.volumes, [4000])
        XCTAssertEqual(history.sets.count, 1)
        _ = try MilestoneProjection.rebuild(exerciseNames: [exercise.name], context: context,
                                            formatWeight: { Weight.trim($0) })
        let records = try context.fetch(FetchDescriptor<Milestone>()).filter { $0.date > pastDate }
        XCTAssertEqual(records.map(\.kindRaw), [PREvent.Kind.volumePR.rawValue])
        XCTAssertTrue(records.first?.label.contains("6000") ?? false)
    }

    func testExplicitProfileInventoryKeepsOtherDenominationsDisabled() {
        let gym = Gym(name: "Synthetic gym")
        gym.plateTheme = .iwfCompetition
        gym.plateToggles = [PlateToggle(plate: Plate(value: 45, unit: .lb))]
        gym.applyPlateProfileInventory()
        XCTAssertEqual(Set(gym.availablePlates.map(\.id)), Set(PlateTheme.set(for: .kg, theme: .iwfCompetition).map(\.id)))
        XCTAssertFalse(gym.plateToggles.first { $0.plate == Plate(value: 45, unit: .lb) }?.enabled ?? true)
    }
}
