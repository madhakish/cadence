import Foundation
import SwiftData
import XCTest

@MainActor
final class PersistenceMigrationTests: XCTestCase {
    func testPre72V1StoreMigratesWithoutDataLoss() throws {
        try assertMigration(
            createStore: createV1Store,
            migrationPlan: CadencePre72MigrationPlan.self,
            expectsExistingSessionID: false
        )
    }

    func testStoreCreatedBy72BuildAlsoMigratesWithoutDataLoss() throws {
        try assertMigration(
            createStore: createShipped72Store,
            migrationPlan: Cadence72MigrationPlan.self,
            expectsExistingSessionID: true
        )
    }

    func testShippedV3StoreMigratesToV4WithoutDataLoss() throws {
        try assertMigration(
            createStore: createV3Store,
            migrationPlan: CadenceV3MigrationPlan.self,
            expectsExistingSessionID: true
        )
    }

    private func assertMigration<Plan: SchemaMigrationPlan>(
        createStore: (URL) throws -> Void,
        migrationPlan: Plan.Type,
        expectsExistingSessionID: Bool
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Cadence.store")

        try createStore(storeURL)

        let schema = Schema(versionedSchema: CadenceSchemaV4.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: storeURL)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: migrationPlan,
            configurations: configuration
        )
        let context = container.mainContext

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].notes, "V1 training log")
        XCTAssertEqual(sessions[0].orderedExercises.first?.orderedSets.first?.weightLb, 185)
        XCTAssertEqual(sessions[0].orderedExercises.first?.plannedWeightLb, 195,
                       "the planned exercise load survives separately from the adjusted performed set")
        XCTAssertNil(sessions[0].orderedExercises.first?.orderedSets.first?.plannedWeightLb,
                     "V3 history is never assigned a fabricated per-set plan")
        XCTAssertNil(sessions[0].completedAt)
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
        XCTAssertEqual(migratedSet.prescriptionBlock, .work)

        let exercise = try XCTUnwrap(try context.fetch(FetchDescriptor<Exercise>()).first { $0.name == "Back Squat" })
        XCTAssertEqual(exercise.movementPattern, .squat)
        XCTAssertEqual(exercise.gateStatus, .open)
        XCTAssertTrue(exercise.reEntryCriteria.isEmpty)

        let programs = try context.fetch(FetchDescriptor<Program>())
        XCTAssertEqual(programs.first?.name, "Migration Program")
        XCTAssertEqual(programs.first?.coachEnabled, true)
        XCTAssertEqual(programs.first?.maximumAddedSetsPerRotation, 6)
        XCTAssertEqual(programs.first?.orderedDays.first?.orderedLifts.first?.baseWeightLb, 175)
        XCTAssertEqual(programs.first?.orderedDays.first?.orderedAccessories.first?.sets, 3)
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
        entry.plannedWeightLb = 195
        entry.plannedSets = 3
        entry.plannedReps = 5
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
        insertV1Program(context)
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
        entry.plannedWeightLb = 195
        entry.plannedSets = 3
        entry.plannedReps = 5
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
        insertV2Program(context)
        try context.save()
    }

    private func createV3Store(at url: URL) throws {
        let schema = Schema(versionedSchema: CadenceSchemaV3.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext

        let exercise = CadenceSchemaV3.Exercise(
            name: "Back Squat", categoryRaw: "Main", typeRaw: "barbell")
        exercise.movementGroup = "squat"
        let session = CadenceSchemaV3.WorkoutSession(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            notes: "V1 training log", isCompleted: true)
        let entry = CadenceSchemaV3.SessionExercise(order: 0, exercise: exercise)
        entry.plannedWeightLb = 195
        entry.plannedSets = 3
        entry.plannedReps = 5
        let set = CadenceSchemaV3.SetEntry(order: 0, weightLb: 185, reps: 5)
        entry.session = session
        entry.sets = [set]
        set.sessionExercise = entry
        session.exercises = [entry]

        context.insert(exercise)
        context.insert(session)
        context.insert(entry)
        context.insert(set)
        context.insert(CadenceSchemaV3.Gym(name: "Migration Gym"))
        context.insert(CadenceSchemaV3.AppSettings())
        insertV3Program(context)
        try context.save()
    }

    private func insertV1Program(_ context: ModelContext) {
        let program = CadenceSchemaV1.Program(name: "Migration Program")
        let day = CadenceSchemaV1.ProgramDay(name: "Lower", order: 0)
        let lift = CadenceSchemaV1.ProgramLift(exerciseName: "Back Squat")
        lift.baseWeightLb = 175
        let accessory = CadenceSchemaV1.ProgramAccessory(exerciseName: "Seated Leg Curl")
        day.program = program; lift.day = day; accessory.day = day
        day.lifts = [lift]; day.accessories = [accessory]; program.days = [day]
        context.insert(program); context.insert(day); context.insert(lift); context.insert(accessory)
    }

    private func insertV2Program(_ context: ModelContext) {
        let program = CadenceSchemaV2.Program(name: "Migration Program")
        let day = CadenceSchemaV2.ProgramDay(name: "Lower", order: 0)
        let lift = CadenceSchemaV2.ProgramLift(exerciseName: "Back Squat")
        lift.baseWeightLb = 175
        let accessory = CadenceSchemaV2.ProgramAccessory(exerciseName: "Seated Leg Curl")
        day.program = program; lift.day = day; accessory.day = day
        day.lifts = [lift]; day.accessories = [accessory]; program.days = [day]
        context.insert(program); context.insert(day); context.insert(lift); context.insert(accessory)
    }

    private func insertV3Program(_ context: ModelContext) {
        let program = CadenceSchemaV3.Program(name: "Migration Program")
        let day = CadenceSchemaV3.ProgramDay(name: "Lower", order: 0)
        let lift = CadenceSchemaV3.ProgramLift(exerciseName: "Back Squat")
        lift.baseWeightLb = 175
        let accessory = CadenceSchemaV3.ProgramAccessory(exerciseName: "Seated Leg Curl")
        day.program = program; lift.day = day; accessory.day = day
        day.lifts = [lift]; day.accessories = [accessory]; program.days = [day]
        context.insert(program); context.insert(day); context.insert(lift); context.insert(accessory)
    }
}

/// The broken build's store advertised V1 while containing the #72 model
/// checksum. This test-only wrapper reproduces that metadata exactly.
private enum Shipped72Schema: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { CadenceSchemaV2.models }
}
