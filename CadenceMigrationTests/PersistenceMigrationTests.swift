import Foundation
import SwiftData
import XCTest
import CadenceCore

@MainActor
final class PersistenceMigrationTests: XCTestCase {
    func testActualV129AppStoreMigratesWithoutDataLoss() throws {
        try assertActualShippedStore(environmentKey: "CADENCE_V129_STORE_DIR")
    }

    func testActualPR72AppStoreMigratesWithoutDataLoss() throws {
        try assertActualShippedStore(environmentKey: "CADENCE_PR72_STORE_DIR")
    }

    func testStoreSurvivesTheActual72And73FailedUpgradeLineage() throws {
        try assertActualShippedStore(environmentKey: "CADENCE_FAILED_UPGRADES_STORE_DIR")
    }

    func testActualPR73V3StoreMigratesWithoutDataLoss() throws {
        try assertActualShippedStore(environmentKey: "CADENCE_PR73_STORE_DIR")
    }

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

    func testRelationshipAliasRepairRestoresIndependentLowerBDayAndIsIdempotent() throws {
        let schema = Schema(versionedSchema: CadenceSchemaV4.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext
        try Seeder.seedIfNeeded(context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let deadliftExercise = try XCTUnwrap(exercises.first { $0.name == "Deadlift" })
        let squatExercise = try XCTUnwrap(exercises.first { $0.name == "Back Squat" })

        let program = Program(name: "Synthetic Alias Regression")
        let day = ProgramDay(name: "Lower B", order: 0)
        let sharedSlotID = UUID().uuidString
        let deadlift = ProgramLift(id: sharedSlotID, exerciseName: "Deadlift", role: .main,
                                   order: 0, baseWeightLb: 225, estimatedMaxLb: 275)
        let squat = ProgramLift(id: sharedSlotID, exerciseName: "Back Squat", role: .complementary,
                                order: 1, baseWeightLb: 175, estimatedMaxLb: 225)
        let walking = ProgramAccessory(exerciseName: "Walking Lunges", order: 0, sets: 3,
                                       minReps: 8, maxReps: 12, currentReps: 8,
                                       weightLb: 0, incrementLb: 0)
        let swings = ProgramAccessory(exerciseName: "KB Swing", order: 1, sets: 3,
                                      minReps: 8, maxReps: 12, currentReps: 8,
                                      weightLb: 53, incrementLb: 5)
        let sidePlank = ProgramAccessory(exerciseName: "Side Plank", order: 2, sets: 3,
                                        minReps: 1, maxReps: 1, currentReps: 1,
                                        weightLb: 0, incrementLb: 0)
        context.insert(program)
        context.insert(day)
        context.insert(deadlift)
        context.insert(squat)
        context.insert(walking)
        context.insert(swings)
        context.insert(sidePlank)
        program.days = [day, day]
        day.lifts = [deadlift, deadlift, squat]
        day.accessories = [walking, swings, swings, sidePlank]

        let session = WorkoutSession()
        session.programID = program.id
        let deadliftEntry = SessionExercise(order: 0, exercise: deadliftExercise)
        deadliftEntry.programRole = LiftRole.main.rawValue
        deadliftEntry.programSlotID = sharedSlotID
        let squatEntry = SessionExercise(order: 1, exercise: squatExercise)
        squatEntry.programRole = LiftRole.complementary.rawValue
        squatEntry.programSlotID = sharedSlotID
        let work = SetEntry(order: 0, weightLb: 175, reps: 5)
        context.insert(session)
        context.insert(deadliftEntry)
        context.insert(squatEntry)
        context.insert(work)
        session.exercises = [deadliftEntry, deadliftEntry, squatEntry]
        squatEntry.sets = [work, work]
        try context.save()

        try Seeder.syncLibrary(context: context)

        XCTAssertEqual(program.days.count, 1)
        XCTAssertEqual(day.lifts.count, 2)
        XCTAssertEqual(day.orderedLifts.map(\.exerciseName), ["Deadlift", "Back Squat"])
        XCTAssertEqual(day.orderedLifts.map(\.role), [.main, .complementary])
        XCTAssertEqual(day.accessories.count, 3)
        XCTAssertEqual(day.orderedAccessories.map(\.exerciseName), ["Walking Lunges", "KB Swing", "Side Plank"])
        XCTAssertEqual(session.exercises.count, 2)
        XCTAssertEqual(squatEntry.sets.count, 1)
        XCTAssertNotEqual(deadlift.id, squat.id)
        XCTAssertEqual(deadliftEntry.programSlotID, deadlift.id)
        XCTAssertEqual(squatEntry.programSlotID, squat.id)

        let repairedIDs = [deadlift.id, squat.id, walking.id, swings.id, sidePlank.id]
        try Seeder.syncLibrary(context: context)
        XCTAssertEqual(day.lifts.count, 2)
        XCTAssertEqual(day.accessories.count, 3)
        XCTAssertEqual([deadlift.id, squat.id, walking.id, swings.id, sidePlank.id], repairedIDs)
    }

    private func assertActualShippedStore(environmentKey: String) throws {
        guard let sourcePath = ProcessInfo.processInfo.environment[environmentKey] else {
            throw XCTSkip("The end-to-end shipped-store fixture is generated by macOS CI")
        }
        let source = URL(fileURLWithPath: sourcePath, isDirectory: true)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-shipped-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for file in try FileManager.default.contentsOfDirectory(at: source,
                                                                 includingPropertiesForKeys: nil) {
            try FileManager.default.copyItem(at: file,
                                             to: directory.appendingPathComponent(file.lastPathComponent))
        }
        let storeURL = directory.appendingPathComponent("default.store")
        let container = try openUsingProductionStrategies(storeURL: storeURL)
        let context = container.mainContext

        // Assert persisted seed records before running any current seeder. A
        // newly-created empty store must not masquerade as a migration.
        XCTAssertFalse(try context.fetch(FetchDescriptor<Exercise>()).isEmpty)
        XCTAssertFalse(try context.fetch(FetchDescriptor<Gym>()).isEmpty)
        XCTAssertNotNil(try context.fetch(FetchDescriptor<AppSettings>()).first?.seededAt)

        try Seeder.syncLibrary(context: context)
        XCTAssertNotNil(try context.fetch(FetchDescriptor<Exercise>()).first { $0.name == "Back Squat" })
        let gyms = try context.fetch(FetchDescriptor<Gym>())
        XCTAssertFalse(gyms.isEmpty)
        XCTAssertEqual(gyms.first?.plateToggles.count, Plate.allStandard.count)
    }

    private func openUsingProductionStrategies(storeURL: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CadenceSchemaV4.self)
        let configuration = {
            ModelConfiguration("migration", schema: schema, url: storeURL)
        }
        let attempts: [() throws -> ModelContainer] = [
            { try ModelContainer(for: schema, migrationPlan: CadenceV3MigrationPlan.self,
                                 configurations: configuration()) },
            { try ModelContainer(for: schema, migrationPlan: CadencePre72MigrationPlan.self,
                                 configurations: configuration()) },
            { try ModelContainer(for: schema, migrationPlan: Cadence72MigrationPlan.self,
                                 configurations: configuration()) },
            { try ModelContainer(for: schema, migrationPlan: nil,
                                 configurations: configuration()) },
        ]
        var lastError: Error?
        for attempt in attempts {
            do { return try attempt() }
            catch { lastError = error }
        }
        throw lastError ?? CocoaError(.fileReadUnknown)
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
        XCTAssertEqual(gyms.first?.availablePlates.count, Plate.allStandard.count,
                       "a legacy empty inventory resolves to the standard rack before normalization")

        try Seeder.syncLibrary(context: context)

        XCTAssertEqual(gyms.first?.plateToggles.count, Plate.allStandard.count,
                       "library sync materializes the legacy rack for Settings")

        let migrated = try XCTUnwrap(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertNotNil(UUID(uuidString: migrated.id))
        let migratedSet = try XCTUnwrap(migrated.orderedExercises.first?.orderedSets.first)
        XCTAssertEqual(migratedSet.loadBasis, .totalBar)
        XCTAssertEqual(migratedSet.resolvedImplementCount, 1)
        XCTAssertEqual(migratedSet.weightLb, 185)
        XCTAssertEqual(migratedSet.prescriptionBlock, .work)
        let migratedWarmup = try XCTUnwrap(
            migrated.orderedExercises.first?.orderedSets.first(where: \.isWarmup)
        )
        XCTAssertEqual(migratedWarmup.weightLb, 95)
        XCTAssertEqual(migratedWarmup.prescriptionBlock, .warmup,
                       "the V4 literal work default must not relabel historical warm-ups")

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
        let warmup = CadenceSchemaV1.SetEntry(order: 1, weightLb: 95, reps: 5)
        warmup.isWarmup = true
        entry.session = session
        entry.sets = [set, warmup]
        set.sessionExercise = entry
        warmup.sessionExercise = entry
        session.exercises = [entry]

        context.insert(exercise)
        context.insert(session)
        context.insert(entry)
        context.insert(set)
        context.insert(warmup)
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
        let warmup = CadenceSchemaV2.SetEntry(order: 1, weightLb: 95, reps: 5)
        warmup.isWarmup = true
        entry.session = session
        entry.sets = [set, warmup]
        set.sessionExercise = entry
        warmup.sessionExercise = entry
        session.exercises = [entry]

        context.insert(exercise)
        context.insert(session)
        context.insert(entry)
        context.insert(set)
        context.insert(warmup)
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
        let warmup = CadenceSchemaV3.SetEntry(order: 1, weightLb: 95, reps: 5)
        warmup.isWarmup = true
        entry.session = session
        entry.sets = [set, warmup]
        set.sessionExercise = entry
        warmup.sessionExercise = entry
        session.exercises = [entry]

        context.insert(exercise)
        context.insert(session)
        context.insert(entry)
        context.insert(set)
        context.insert(warmup)
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
