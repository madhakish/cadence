import Foundation
import SwiftData
import XCTest

@MainActor
final class PersistenceMigrationTests: XCTestCase {
    func testPre72V1StoreMigratesWithoutDataLoss() throws {
        try assertMigration(createStore: createV1Store, expectsExistingSessionID: false)
    }

    func testStoreCreatedBy72BuildAlsoMigratesWithoutDataLoss() throws {
        try assertMigration(createStore: createShipped72Store, expectsExistingSessionID: true)
    }

    private func assertMigration(createStore: (URL) throws -> Void,
                                 expectsExistingSessionID: Bool) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Cadence.store")

        try createStore(storeURL)

        let schema = Schema(versionedSchema: CadenceSchemaV3.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: storeURL)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: CadenceMigrationPlan.self,
            configurations: configuration
        )
        let context = container.mainContext

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].notes, "V1 training log")
        XCTAssertEqual(sessions[0].orderedExercises.first?.orderedSets.first?.weightLb, 185)
        if expectsExistingSessionID {
            XCTAssertNotNil(UUID(uuidString: sessions[0].id))
        } else {
            XCTAssertEqual(sessions[0].id, "", "pre-#72 rows receive the lightweight literal default first")
        }

        let gyms = try context.fetch(FetchDescriptor<Gym>())
        XCTAssertEqual(gyms.first?.name, "Migration Gym")
        XCTAssertEqual(gyms.first?.collarWeightLb, 0)
        XCTAssertEqual(gyms.first?.loadingPolicy, .closest)

        try Seeder.syncLibrary(context: context)

        let migrated = try XCTUnwrap(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertNotNil(UUID(uuidString: migrated.id))
        let migratedSet = try XCTUnwrap(migrated.orderedExercises.first?.orderedSets.first)
        XCTAssertEqual(migratedSet.loadBasis, .totalBar)
        XCTAssertEqual(migratedSet.resolvedImplementCount, 1)
        XCTAssertEqual(migratedSet.weightLb, 185)
    }

    private func createV1Store(at url: URL) throws {
        let schema = Schema(versionedSchema: CadenceSchemaV1.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext

        let exercise = CadenceSchemaV1.Exercise(
            name: "Back Squat", categoryRaw: "Main", typeRaw: "barbell")
        exercise.movementGroup = "squat"
        let session = CadenceSchemaV1.WorkoutSession(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            notes: "V1 training log", isCompleted: true)
        let entry = CadenceSchemaV1.SessionExercise(order: 0, exercise: exercise)
        let set = CadenceSchemaV1.SetEntry(order: 0, weightLb: 185, reps: 5)
        entry.session = session
        entry.sets = [set]
        set.sessionExercise = entry
        session.exercises = [entry]

        context.insert(exercise)
        context.insert(session)
        context.insert(entry)
        context.insert(set)
        context.insert(CadenceSchemaV1.Gym(name: "Migration Gym"))
        context.insert(CadenceSchemaV1.AppSettings())
        try context.save()
    }

    private func createShipped72Store(at url: URL) throws {
        // PR #72 accidentally kept versionIdentifier 1.0.0 while changing the
        // model checksum. Recreate that exact label + model combination.
        let schema = Schema(versionedSchema: Shipped72Schema.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext

        let exercise = CadenceSchemaV2.Exercise(
            name: "Back Squat", categoryRaw: "Main", typeRaw: "barbell")
        exercise.movementGroup = "squat"
        let session = CadenceSchemaV2.WorkoutSession(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            notes: "V1 training log", isCompleted: true)
        let entry = CadenceSchemaV2.SessionExercise(order: 0, exercise: exercise)
        let set = CadenceSchemaV2.SetEntry(order: 0, weightLb: 185, reps: 5)
        entry.session = session
        entry.sets = [set]
        set.sessionExercise = entry
        session.exercises = [entry]

        context.insert(exercise)
        context.insert(session)
        context.insert(entry)
        context.insert(set)
        context.insert(CadenceSchemaV2.Gym(name: "Migration Gym"))
        context.insert(CadenceSchemaV2.AppSettings())
        try context.save()
    }
}

/// The broken build's store advertised V1 while containing the #72 model
/// checksum. This test-only wrapper reproduces that metadata exactly.
private enum Shipped72Schema: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { CadenceSchemaV2.models }
}
