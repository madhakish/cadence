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

    func testShippedV3StoreMigratesToV8WithoutDataLoss() throws {
        try assertMigration(
            createStore: createV3Store,
            migrationPlan: CadenceV3MigrationPlan.self,
            expectsExistingSessionID: true
        )
    }

    /// An install that skipped the protein retirement and arrives two versions
    /// behind, so its store crosses both stages in one open.
    func testShippedV4StoreMigratesToV8WithoutDataLoss() throws {
        try assertMigration(
            createStore: { try self.createV4Store(at: $0) },
            migrationPlan: CadenceV4MigrationPlan.self,
            expectsExistingSessionID: true
        )
    }

    /// The common case for this upgrade: every install shipped since protein
    /// logging was retired carries the V5 checksum.
    func testShippedV5StoreMigratesToV8WithoutDataLoss() throws {
        try assertMigration(
            createStore: { try self.createV5Store(at: $0) },
            migrationPlan: CadenceV5MigrationPlan.self,
            expectsExistingSessionID: true
        )
    }

    /// The common case for THIS upgrade: every install shipped since
    /// conditioning learned to count flights carries the V6 checksum.
    func testShippedV6StoreMigratesToV8WithoutDataLoss() throws {
        try assertMigration(
            createStore: { try self.createV6Store(at: $0) },
            migrationPlan: CadenceV6MigrationPlan.self,
            expectsExistingSessionID: true
        )
    }

    /// The common case for THIS upgrade: every install shipped since vertical
    /// pulling was promoted carries the V7 checksum.
    func testShippedV7StoreMigratesToV8WithoutDataLoss() throws {
        try assertMigration(
            createStore: { try self.createV7Store(at: $0) },
            migrationPlan: CadenceV7MigrationPlan.self,
            expectsExistingSessionID: true
        )
    }

    /// The whole point of V8: the station column arrives as nil — "use the gym
    /// inventory", exactly what every lift did before stations existed — the
    /// one-shot stamps survive the hop, and a preference set after the upgrade
    /// persists across reopens.
    func testV7StoreGainsTheStationColumnWithoutTouchingAnything() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Cadence.store")
        try createV7Store(at: storeURL)

        let schema = Schema(versionedSchema: CadenceSchemaV8.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: storeURL)
        do {
            let container = try ModelContainer(for: schema, migrationPlan: CadenceV7MigrationPlan.self,
                                               configurations: configuration)
            let context = container.mainContext
            let squat = try XCTUnwrap(
                try context.fetch(FetchDescriptor<Exercise>()).first { $0.name == "Back Squat" }
            )
            XCTAssertNil(squat.stationDenomination,
                         "a migrated exercise has no station preference — the gym inventory rule holds")
            XCTAssertEqual(try context.fetch(FetchDescriptor<AppSettings>()).first?.verticalPullMainsPromoted,
                           true, "the V7 one-shot stamp survives the V8 hop")
            // The lifter declares the deadlift station's kg plates once…
            let deadlift = try XCTUnwrap(
                try context.fetch(FetchDescriptor<Exercise>()).first { $0.name == "Deadlift" }
            )
            deadlift.stationDenomination = .kg
            try context.save()
        }
        // …and it is still there when the store reopens.
        let reopened = try ModelContainer(
            for: schema, migrationPlan: CadenceV7MigrationPlan.self,
            configurations: ModelConfiguration("migration", schema: schema, url: storeURL)
        )
        let deadlift = try XCTUnwrap(
            try reopened.mainContext.fetch(FetchDescriptor<Exercise>()).first { $0.name == "Deadlift" }
        )
        XCTAssertEqual(deadlift.stationDenomination, .kg,
                       "the station preference is persisted state, not a runtime guess")
    }

    /// The whole point of V7: a store seeded while pull-ups were accessories
    /// must come out the other side with them charted as main lifts, without
    /// the repair touching anything the lifter decided for themselves.
    func testV6StorePromotesSeededPullUpsAndLeavesDeliberateCategoriesAlone() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Cadence.store")
        try createV6Store(at: storeURL)

        let schema = Schema(versionedSchema: CadenceSchemaV8.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, migrationPlan: CadenceV6MigrationPlan.self,
                                           configurations: configuration)
        let context = container.mainContext

        // The upgraded store has not been repaired yet — the new column reads
        // false, which is exactly "this install still needs the promotion".
        let settingsBefore = try context.fetch(FetchDescriptor<AppSettings>())
        XCTAssertEqual(settingsBefore.first?.verticalPullMainsPromoted, false,
                       "a migrated store starts unrepaired")

        try Seeder.syncLibrary(context: context)

        let byName = { (name: String) throws -> Exercise? in
            try context.fetch(FetchDescriptor<Exercise>()).first { $0.name == name }
        }
        XCTAssertEqual(try byName("Pull-ups")?.category, .main,
                       "a seeded accessory pull-up is promoted to a main lift")
        XCTAssertEqual(try byName("Chin-ups")?.category, .conditioning,
                       "a category the lifter set themselves is never overwritten — delete the guard and this fails")
        XCTAssertEqual(try byName("Assisted Pull-up")?.category, .accessory,
                       "assistance is a regression toward a pull-up and stays an accessory")
        // syncLibrary inserts any definition the store is missing, so the
        // weighted entries arrive on an existing install with no extra step.
        XCTAssertEqual(try byName("Weighted Pull-up")?.category, .main)
        XCTAssertEqual(try byName("Weighted Pull-up")?.loadBasis, .externalTotal,
                       "belt weight is real resistance and must earn load PRs")
        XCTAssertEqual(try byName("Pull-ups")?.loadBasis, .bodyweight,
                       "an unloaded pull-up never fakes a 0 lb PR")

        // The lifter disagrees, and says so. The repair must not argue.
        try byName("Pull-ups")?.categoryRaw = ExerciseCategory.accessory.rawValue
        try context.save()
        try Seeder.syncLibrary(context: context)
        XCTAssertEqual(try byName("Pull-ups")?.category, .accessory,
                       "the promotion is one-shot — a category set back deliberately is never overwritten")

        // And it stays idempotent: no duplicate rows across repeated opens.
        try Seeder.syncLibrary(context: context)
        let pullUps = try context.fetch(FetchDescriptor<Exercise>()).filter { $0.name == "Pull-ups" }
        XCTAssertEqual(pullUps.count, 1, "repair never duplicates a library row")
    }

    /// The V6 fixture itself must be a valid V6 graph. A helper from another
    /// schema version can compile at the call site but cannot be persisted by
    /// this container, which would make every downstream current-schema assertion theater.
    func testV6FixtureContainsItsProgramGraphBeforeMigration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-v6-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Cadence.store")
        try createV6Store(at: storeURL)

        let schema = Schema(versionedSchema: CadenceSchemaV6.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let program = try XCTUnwrap(
            try container.mainContext.fetch(FetchDescriptor<CadenceSchemaV6.Program>()).first
        )
        XCTAssertEqual(program.name, "Migration Program")
        XCTAssertEqual(program.days.count, 1)
        XCTAssertEqual(program.days.first?.lifts.first?.exerciseName, "Back Squat")
        XCTAssertEqual(program.days.first?.accessories.first?.exerciseName, "Seated Leg Curl")
    }

    /// Native and web backups must agree on every one-shot library stamp. If
    /// native omits this one, restoring its own post-migration backup promotes
    /// a pull-up the lifter deliberately moved back to Accessory.
    func testNativeBackupRoundTripKeepsVerticalPullPromotionStamp() throws {
        let schema = Schema(versionedSchema: CadenceSchemaV8.self)
        let source = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let sourceSettings = AppSettings()
        sourceSettings.verticalPullMainsPromoted = true
        source.mainContext.insert(sourceSettings)
        try source.mainContext.save()

        let backup = try ExportService.jsonData(context: source.mainContext)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: backup) as? [String: Any])
        let exportedSettings = try XCTUnwrap(json["settings"] as? [String: Any])
        XCTAssertEqual(exportedSettings["verticalPullMainsPromoted"] as? Bool, true,
                       "native export carries the one-shot marker")

        let restored = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let restoredSettings = AppSettings()
        restoredSettings.verticalPullMainsPromoted = false
        restored.mainContext.insert(restoredSettings)
        try restored.mainContext.save()
        try ImportService.load(backup, into: restored.mainContext)

        let roundTripped = try XCTUnwrap(
            try restored.mainContext.fetch(FetchDescriptor<AppSettings>()).first
        )
        XCTAssertTrue(roundTripped.verticalPullMainsPromoted,
                      "restoring a native backup does not re-arm the promotion")
    }

    /// A restore must not leave a station configuration behind that the
    /// backup does not contain: a pre-v8 bundle never carries the key, and a
    /// v8 bundle omits it when cleared (the native encoder drops nil keys) —
    /// both restore as "gym inventory", matching web's wholesale-record
    /// replacement.
    func testRestoreClearsAStationPreferenceTheBackupDoesNotContain() throws {
        let schema = Schema(versionedSchema: CadenceSchemaV8.self)
        let source = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        source.mainContext.insert(Exercise(name: "Deadlift", category: .main, type: .barbell))
        source.mainContext.insert(AppSettings())
        try source.mainContext.save()
        var bundle = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try ExportService.jsonData(context: source.mainContext)
            ) as? [String: Any]
        )
        bundle["schemaVersion"] = 7   // the bundle predates stations entirely
        let preStation = try JSONSerialization.data(withJSONObject: bundle)

        let restored = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let local = Exercise(name: "Deadlift", category: .main, type: .barbell)
        local.stationDenomination = .kg   // declared AFTER the backup was written
        restored.mainContext.insert(local)
        restored.mainContext.insert(AppSettings())
        try restored.mainContext.save()
        try ImportService.load(preStation, into: restored.mainContext)

        let deadlift = try XCTUnwrap(
            try restored.mainContext.fetch(FetchDescriptor<Exercise>()).first { $0.name == "Deadlift" }
        )
        XCTAssertNil(deadlift.stationDenomination,
                     "a restore never resurrects a station configuration the backup does not contain")
    }

    /// V5 removes `ProteinEntry` and `proteinTargetGrams`. That is deliberate
    /// and destructive, so the thing worth proving is the blast radius: the
    /// dropped entity takes nothing else with it, and the store still opens.
    func testV5DropsProteinWithoutTakingTheRestOfTheStoreWithIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Cadence.store")

        try createV4Store(at: storeURL, proteinEntries: 12)

        let schema = Schema(versionedSchema: CadenceSchemaV8.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: storeURL)
        let container = try ModelContainer(
            for: schema, migrationPlan: CadenceV4MigrationPlan.self, configurations: configuration
        )
        let context = container.mainContext

        // The neighbours in the same file and the same store.
        let weights = try context.fetch(FetchDescriptor<BodyweightEntry>())
        XCTAssertEqual(weights.count, 2, "bodyweight entries were collateral damage")
        XCTAssertEqual(weights.map(\.weightLb).sorted(), [199, 201])
        XCTAssertEqual(weights.first { $0.weightLb == 201 }?.bodyFatPercent, 18,
                       "body fat did not survive alongside the weigh-in")
        XCTAssertEqual(try context.fetch(FetchDescriptor<CheckIn>()).count, 1,
                       "check-ins share TrackingModels.swift with the deleted entity")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Milestone>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)

        // The settings row loses one field and gains another; everything else
        // it holds must be untouched.
        let settings = try XCTUnwrap(try context.fetch(FetchDescriptor<AppSettings>()).first)
        XCTAssertEqual(settings.birthYear, 0, "an upgraded row takes the not-set default")
        XCTAssertEqual(settings.accessoryRestSeconds, 75, "an unrelated setting moved")
        XCTAssertEqual(settings.themeNameRaw, "slate")
        XCTAssertTrue(settings.healthKitEnabled)

        // And the store keeps working after the upgrade: a birth year set now
        // survives a reopen, which is what makes the new field real rather than
        // merely declared.
        settings.birthYear = 1958
        try context.save()
        XCTAssertEqual(ProteinGuidance.age(birthYear: 1958, inYear: 2026), 68)
        XCTAssertEqual(ProteinGuidance.mealGramsPerKg(age: 68), ProteinGuidance.mealGramsPerKgOlder)
    }

    /// [INV-STAIRS-COUNT-FLIGHTS] The V5 store predates flights entirely, so
    /// every conditioning set in it was logged the only way V5 offered —
    /// distance and time. Adding the column must leave those numbers exactly
    /// where they were and must not invent a count for them.
    func testV5ConditioningKeepsItsDistanceAndGainsAnEmptyFlightCount() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Cadence.store")

        try createV5Store(at: storeURL)

        let schema = Schema(versionedSchema: CadenceSchemaV8.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: storeURL)
        let container = try ModelContainer(
            for: schema, migrationPlan: CadenceV5MigrationPlan.self, configurations: configuration
        )
        let context = container.mainContext

        let session = try XCTUnwrap(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
        let climb = try XCTUnwrap(
            session.orderedExercises.first { $0.exercise?.name == "Stair Climber" }?.orderedSets.first)
        XCTAssertEqual(climb.distanceMiles, 0.75, "a V5 stair-climber set keeps the distance it was logged with")
        XCTAssertEqual(climb.durationSeconds, 1200)
        XCTAssertNil(climb.flights, "migration adds the column; it does not fabricate a count")
        XCTAssertEqual(
            CardioFormat.setLabel(distanceMiles: climb.distanceMiles,
                                  durationSeconds: climb.durationSeconds,
                                  inclinePercent: climb.inclinePercent,
                                  loadLb: climb.weightLb,
                                  flights: climb.flights),
            "0.75 mi · 20:00 · 2.3 mph",
            "history written before flights still renders what it holds")

        // And the new column accepts a count on the very same row, so the
        // upgraded store can log the next climb the way the machine reads.
        climb.flights = 160
        climb.distanceMiles = nil
        try context.save()

        // Re-read through a SECOND container on the same file. Fetching again
        // from the context that wrote it returns the same registered object and
        // would pass whether or not the column ever reached disk, which is the
        // only thing this half of the test is for.
        let reopenedContainer = try ModelContainer(
            for: schema, migrationPlan: CadenceV5MigrationPlan.self,
            configurations: ModelConfiguration("migration", schema: schema, url: storeURL)
        )
        let saved = try XCTUnwrap(
            try reopenedContainer.mainContext
                .fetch(FetchDescriptor<WorkoutSession>()).first?
                .orderedExercises.first { $0.exercise?.name == "Stair Climber" }?
                .orderedSets.first)
        XCTAssertEqual(saved.flights, 160, "the new column did not survive a reopen")
        XCTAssertNil(saved.distanceMiles, "clearing the legacy distance did not persist")
        XCTAssertEqual(CardioFormat.flightPace(flights: saved.flights,
                                               durationSeconds: saved.durationSeconds), 8.0)
    }

    func testRelationshipAliasRepairRestoresIndependentLowerBDayAndIsIdempotent() throws {
        let schema = Schema(versionedSchema: CadenceSchemaV8.self)
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

    func testRelationshipAliasRepairDoesNotGuessBetweenIdenticalCollidingSlots() throws {
        let schema = Schema(versionedSchema: CadenceSchemaV8.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext
        try Seeder.seedIfNeeded(context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let deadliftExercise = try XCTUnwrap(exercises.first { $0.name == "Deadlift" })
        let sharedSlotID = UUID().uuidString
        let program = Program(name: "Synthetic Ambiguous Slot Regression")
        let day = ProgramDay(name: "Lower B", order: 0)
        let first = ProgramLift(id: sharedSlotID, exerciseName: "Deadlift", role: .main,
                                order: 0, baseWeightLb: 225, estimatedMaxLb: 275)
        let second = ProgramLift(id: sharedSlotID, exerciseName: "Deadlift", role: .main,
                                 order: 1, baseWeightLb: 225, estimatedMaxLb: 275)
        let session = WorkoutSession()
        session.programID = program.id
        let entry = SessionExercise(order: 0, exercise: deadliftExercise)
        entry.programRole = LiftRole.main.rawValue
        entry.programSlotID = sharedSlotID

        context.insert(program)
        context.insert(day)
        context.insert(first)
        context.insert(second)
        context.insert(session)
        context.insert(entry)
        program.days = [day]
        day.lifts = [first, second]
        session.exercises = [entry]
        try context.save()

        try Seeder.syncLibrary(context: context)

        XCTAssertEqual(first.id, sharedSlotID)
        XCTAssertNotEqual(second.id, sharedSlotID)
        XCTAssertEqual(entry.programSlotID, sharedSlotID,
                       "Ambiguous history must remain bound to the unchanged slot")
    }

    func testMirroredLowerBMatrixRestoresRolesFromItsTaggedProgramDay() throws {
        let schema = Schema(versionedSchema: CadenceSchemaV8.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext
        try Seeder.seedIfNeeded(context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let deadliftExercise = try XCTUnwrap(exercises.first { $0.name == "Deadlift" })
        let squatExercise = try XCTUnwrap(exercises.first { $0.name == "Back Squat" })
        let program = Program(name: "Synthetic Four Day Matrix", cycleNumber: 2,
                              currentWeek: 3, nextDayIndex: 2, isActive: false)
        let lowerA = ProgramDay(name: "Lower A", order: 0)
        let lowerB = ProgramDay(name: "Lower B", order: 2)
        let lowerASquat = ProgramLift(exerciseName: "Back Squat", role: .main,
                                      baseWeightLb: 160, estimatedMaxLb: 220)
        let lowerADeadlift = ProgramLift(exerciseName: "Deadlift", role: .complementary,
                                         baseWeightLb: 130, estimatedMaxLb: 250)
        let lowerBSquat = ProgramLift(exerciseName: "Back Squat", role: .main,
                                      baseWeightLb: 115, estimatedMaxLb: 210)
        let lowerBDeadlift = ProgramLift(exerciseName: "Deadlift", role: .complementary,
                                         baseWeightLb: 195, estimatedMaxLb: 260)
        context.insert(program)
        context.insert(lowerA)
        context.insert(lowerB)
        context.insert(lowerASquat)
        context.insert(lowerADeadlift)
        context.insert(lowerBSquat)
        context.insert(lowerBDeadlift)
        program.days = [lowerA, lowerB]
        lowerA.lifts = [lowerASquat, lowerADeadlift]
        lowerB.lifts = [lowerBSquat, lowerBDeadlift]

        let priorLowerB = WorkoutSession(date: Date(timeIntervalSince1970: 2_000_000_000))
        priorLowerB.isCompleted = true
        priorLowerB.completedAt = priorLowerB.date
        priorLowerB.programID = program.id
        priorLowerB.programName = program.name
        priorLowerB.programCycleNumber = 2
        priorLowerB.programWeek = 1
        priorLowerB.programDayIndex = 2
        let deadliftEntry = SessionExercise(order: 0, exercise: deadliftExercise)
        deadliftEntry.programRole = LiftRole.main.rawValue
        let squatEntry = SessionExercise(order: 1, exercise: squatExercise)
        squatEntry.programRole = LiftRole.complementary.rawValue
        context.insert(priorLowerB)
        context.insert(deadliftEntry)
        context.insert(squatEntry)
        priorLowerB.exercises = [deadliftEntry, squatEntry]
        try context.save()

        let slotIDs = [lowerBSquat.id, lowerBDeadlift.id]
        try Seeder.syncLibrary(context: context)

        XCTAssertEqual(lowerB.orderedLifts.map(\.exerciseName), ["Deadlift", "Back Squat"])
        XCTAssertEqual(lowerB.orderedLifts.map(\.role), [.main, .complementary])
        XCTAssertEqual(lowerBDeadlift.baseWeightLb, 195)
        XCTAssertEqual(lowerBSquat.baseWeightLb, 115)
        XCTAssertEqual([lowerBSquat.id, lowerBDeadlift.id], slotIDs)

        try Seeder.syncLibrary(context: context)
        XCTAssertEqual(lowerB.orderedLifts.map(\.exerciseName), ["Deadlift", "Back Squat"])
        XCTAssertEqual(lowerB.orderedLifts.map(\.role), [.main, .complementary])
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
        let schema = Schema(versionedSchema: CadenceSchemaV8.self)
        let configuration = {
            ModelConfiguration("migration", schema: schema, url: storeURL)
        }
        let attempts: [() throws -> ModelContainer] = [
            { try ModelContainer(for: schema, migrationPlan: CadenceV5MigrationPlan.self,
                                 configurations: configuration()) },
            { try ModelContainer(for: schema, migrationPlan: CadenceV4MigrationPlan.self,
                                 configurations: configuration()) },
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

        let schema = Schema(versionedSchema: CadenceSchemaV8.self)
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
        // One side only — see the note in createV4Store. This fixture carried
        // the same aliasing before V4 froze; it proved less than it claimed.
        entry.session = session
        set.sessionExercise = entry
        warmup.sessionExercise = entry

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

    /// A store at the frozen V4 checksum, carrying the two things V5 removes
    /// plus enough neighbouring data to notice if the removal overreaches.
    private func createV4Store(at url: URL, proteinEntries: Int = 3) throws {
        let schema = Schema(versionedSchema: CadenceSchemaV4.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext

        let exercise = CadenceSchemaV4.Exercise(
            name: "Back Squat", categoryRaw: "Main", typeRaw: "barbell")
        exercise.movementGroup = "squat"
        let session = CadenceSchemaV4.WorkoutSession(
            date: Date(timeIntervalSince1970: 1_700_000_000))
        session.notes = "V1 training log"
        session.isCompleted = true
        let entry = CadenceSchemaV4.SessionExercise(order: 0)
        entry.exercise = exercise
        entry.plannedWeightLb = 195
        entry.plannedSets = 3
        entry.plannedReps = 5
        let set = CadenceSchemaV4.SetEntry(order: 0)
        set.weightLb = 185
        set.reps = 5
        let warmup = CadenceSchemaV4.SetEntry(order: 1)
        warmup.weightLb = 95
        warmup.reps = 5
        warmup.isWarmup = true
        warmup.prescriptionBlockRaw = "warmup"
        // One side only. Assigning the child inverse AND appending to the
        // parent collection persists duplicate references, and a fixture built
        // that way would let this test pass on self-corrupted data rather than
        // prove ordinary V4 relationships survive the upgrade.
        entry.session = session
        set.sessionExercise = entry
        warmup.sessionExercise = entry

        context.insert(exercise)
        context.insert(session)
        context.insert(entry)
        context.insert(set)
        context.insert(warmup)
        context.insert(CadenceSchemaV4.Gym(name: "Migration Gym"))

        // The data V5 destroys, and the data sitting next to it that must not be.
        for index in 0..<proteinEntries {
            context.insert(CadenceSchemaV4.ProteinEntry(
                date: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 3600),
                grams: 40, label: "Retired entry \(index)"))
        }
        let heavier = CadenceSchemaV4.BodyweightEntry(
            date: Date(timeIntervalSince1970: 1_700_000_000), weightLb: 201)
        heavier.bodyFatPercent = 18
        context.insert(heavier)
        context.insert(CadenceSchemaV4.BodyweightEntry(
            date: Date(timeIntervalSince1970: 1_700_600_000), weightLb: 199))
        context.insert(CadenceSchemaV4.CheckIn(
            siteRaw: "Knee", response: "All clear"))
        context.insert(CadenceSchemaV4.Milestone(
            kindRaw: "weight", label: "Fixture PR"))

        let settings = CadenceSchemaV4.AppSettings()
        settings.proteinTargetGrams = 145
        settings.accessoryRestSeconds = 75
        settings.themeNameRaw = "slate"
        settings.healthKitEnabled = true
        context.insert(settings)

        insertV4Program(context)
        try context.save()
    }

    private func insertV4Program(_ context: ModelContext) {
        let program = CadenceSchemaV4.Program(name: "Migration Program")
        let day = CadenceSchemaV4.ProgramDay(name: "Lower", order: 0)
        let lift = CadenceSchemaV4.ProgramLift(exerciseName: "Back Squat")
        lift.baseWeightLb = 175
        let accessory = CadenceSchemaV4.ProgramAccessory(exerciseName: "Seated Leg Curl")
        // One side only — same rule the session fixture states; see createV4Store.
        day.program = program; lift.day = day; accessory.day = day
        context.insert(program); context.insert(day); context.insert(lift); context.insert(accessory)
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

    /// The last shape shipped before flights existed. It carries a conditioning
    /// set alongside the barbell work, because that set is the one the new
    /// column has to leave alone.
    private func createV5Store(at url: URL) throws {
        let schema = Schema(versionedSchema: CadenceSchemaV5.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext

        let exercise = CadenceSchemaV5.Exercise(
            name: "Back Squat", categoryRaw: "Main", typeRaw: "barbell")
        exercise.movementGroup = "squat"
        let session = CadenceSchemaV5.WorkoutSession(
            date: Date(timeIntervalSince1970: 1_700_000_000))
        session.notes = "V1 training log"
        session.isCompleted = true
        let entry = CadenceSchemaV5.SessionExercise(order: 0)
        entry.exercise = exercise
        entry.plannedWeightLb = 195
        entry.plannedSets = 3
        entry.plannedReps = 5
        let set = CadenceSchemaV5.SetEntry(order: 0)
        set.weightLb = 185
        set.reps = 5
        let warmup = CadenceSchemaV5.SetEntry(order: 1)
        warmup.weightLb = 95
        warmup.reps = 5
        warmup.isWarmup = true
        warmup.prescriptionBlockRaw = "warmup"
        // One side only — see createV4Store. A fixture built with both sides of
        // the inverse assigned would let this pass on self-corrupted data.
        entry.session = session
        set.sessionExercise = entry
        warmup.sessionExercise = entry

        let climber = CadenceSchemaV5.Exercise(
            name: "Stair Climber", categoryRaw: "Conditioning", typeRaw: "conditioning")
        climber.movementGroup = "conditioning"
        let climbEntry = CadenceSchemaV5.SessionExercise(order: 1)
        climbEntry.exercise = climber
        let climbSet = CadenceSchemaV5.SetEntry(order: 0)
        climbSet.reps = 1
        climbSet.distanceMiles = 0.75
        climbSet.durationSeconds = 1200
        climbEntry.session = session
        climbSet.sessionExercise = climbEntry

        context.insert(exercise)
        context.insert(session)
        context.insert(entry)
        context.insert(set)
        context.insert(warmup)
        context.insert(climber)
        context.insert(climbEntry)
        context.insert(climbSet)
        context.insert(CadenceSchemaV5.Gym(name: "Migration Gym"))
        context.insert(CadenceSchemaV5.AppSettings())
        insertV5Program(context)
        try context.save()
    }

    /// The last shape shipped before vertical pulling became primary work.
    /// Pull-ups is seeded ACCESSORY — the exact state the V7 repair has to
    /// find and promote — and Chin-ups carries a category the lifter set
    /// themselves, which the repair must leave exactly where it is.
    private func createV6Store(at url: URL) throws {
        let schema = Schema(versionedSchema: CadenceSchemaV6.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext

        let exercise = CadenceSchemaV6.Exercise(
            name: "Back Squat", categoryRaw: "Main", typeRaw: "barbell")
        exercise.movementGroup = "squat"
        let session = CadenceSchemaV6.WorkoutSession(
            date: Date(timeIntervalSince1970: 1_700_000_000))
        session.notes = "V1 training log"
        session.isCompleted = true
        let entry = CadenceSchemaV6.SessionExercise(order: 0)
        entry.exercise = exercise
        entry.plannedWeightLb = 195
        entry.plannedSets = 3
        entry.plannedReps = 5
        let set = CadenceSchemaV6.SetEntry(order: 0)
        set.weightLb = 185
        set.reps = 5
        let warmup = CadenceSchemaV6.SetEntry(order: 1)
        warmup.weightLb = 95
        warmup.reps = 5
        warmup.isWarmup = true
        warmup.prescriptionBlockRaw = "warmup"
        // One side only — see createV4Store. A fixture built with both sides of
        // the inverse assigned would let this pass on self-corrupted data.
        entry.session = session
        set.sessionExercise = entry
        warmup.sessionExercise = entry

        let pullUps = CadenceSchemaV6.Exercise(
            name: "Pull-ups", categoryRaw: "Accessory", typeRaw: "bodyweight")
        pullUps.movementGroup = "pull"
        // Deliberately NOT Accessory: the lifter has re-categorized this row,
        // and the repair must not argue. Main would be indistinguishable from
        // a promotion, so the fixture uses the one value that tells the guard
        // apart from its absence.
        let chinUps = CadenceSchemaV6.Exercise(
            name: "Chin-ups", categoryRaw: "Conditioning", typeRaw: "bodyweight")
        chinUps.movementGroup = "pull"
        let assisted = CadenceSchemaV6.Exercise(
            name: "Assisted Pull-up", categoryRaw: "Accessory", typeRaw: "machine")
        assisted.movementGroup = "pull"

        let climber = CadenceSchemaV6.Exercise(
            name: "Stair Climber", categoryRaw: "Conditioning", typeRaw: "conditioning")
        climber.movementGroup = "conditioning"
        let climbEntry = CadenceSchemaV6.SessionExercise(order: 1)
        climbEntry.exercise = climber
        let climbSet = CadenceSchemaV6.SetEntry(order: 0)
        climbSet.reps = 1
        climbSet.distanceMiles = 0.75
        climbSet.durationSeconds = 1200
        climbEntry.session = session
        climbSet.sessionExercise = climbEntry

        context.insert(exercise)
        context.insert(session)
        context.insert(entry)
        context.insert(set)
        context.insert(warmup)
        context.insert(climber)
        context.insert(climbEntry)
        context.insert(climbSet)
        context.insert(pullUps)
        context.insert(chinUps)
        context.insert(assisted)
        context.insert(CadenceSchemaV6.Gym(name: "Migration Gym"))
        context.insert(CadenceSchemaV6.AppSettings())
        insertV6Program(context)
        try context.save()
    }

    private func insertV5Program(_ context: ModelContext) {
        let program = CadenceSchemaV5.Program(name: "Migration Program")
        let day = CadenceSchemaV5.ProgramDay(name: "Lower", order: 0)
        let lift = CadenceSchemaV5.ProgramLift(exerciseName: "Back Squat")
        lift.baseWeightLb = 175
        let accessory = CadenceSchemaV5.ProgramAccessory(exerciseName: "Seated Leg Curl")
        // One side only — same rule the session fixture above states: a store
        // built with both sides of the inverse assigned would let migration
        // pass on self-corrupted relationship rows production never writes.
        day.program = program; lift.day = day; accessory.day = day
        context.insert(program); context.insert(day); context.insert(lift); context.insert(accessory)
    }

    private func insertV6Program(_ context: ModelContext) {
        let program = CadenceSchemaV6.Program(name: "Migration Program")
        let day = CadenceSchemaV6.ProgramDay(name: "Lower", order: 0)
        let lift = CadenceSchemaV6.ProgramLift(exerciseName: "Back Squat")
        lift.baseWeightLb = 175
        let accessory = CadenceSchemaV6.ProgramAccessory(exerciseName: "Seated Leg Curl")
        // One side only — same rule the session fixture above states: a store
        // built with both sides of the inverse assigned would let migration
        // pass on self-corrupted relationship rows production never writes.
        day.program = program; lift.day = day; accessory.day = day
        context.insert(program); context.insert(day); context.insert(lift); context.insert(accessory)
    }

    /// A representative store carrying the V7 checksum: the training log the
    /// V6 fixture writes, plus the promotion stamp V7 introduced (set, as a
    /// repaired install would have it) and a Deadlift row for the V8 station
    /// test to claim.
    private func createV7Store(at url: URL) throws {
        let schema = Schema(versionedSchema: CadenceSchemaV7.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext

        let exercise = CadenceSchemaV7.Exercise(
            name: "Back Squat", categoryRaw: "Main", typeRaw: "barbell")
        exercise.movementGroup = "squat"
        let deadlift = CadenceSchemaV7.Exercise(
            name: "Deadlift", categoryRaw: "Main", typeRaw: "barbell")
        deadlift.movementGroup = "hinge"
        let session = CadenceSchemaV7.WorkoutSession(
            date: Date(timeIntervalSince1970: 1_700_000_000))
        session.notes = "V1 training log"
        session.isCompleted = true
        let entry = CadenceSchemaV7.SessionExercise(order: 0)
        entry.exercise = exercise
        entry.plannedWeightLb = 195
        entry.plannedSets = 3
        entry.plannedReps = 5
        let set = CadenceSchemaV7.SetEntry(order: 0)
        set.weightLb = 185
        set.reps = 5
        let warmup = CadenceSchemaV7.SetEntry(order: 1)
        warmup.weightLb = 95
        warmup.reps = 5
        warmup.isWarmup = true
        warmup.prescriptionBlockRaw = "warmup"
        // One side only — see createV4Store. A fixture built with both sides of
        // the inverse assigned would let this pass on self-corrupted data.
        entry.session = session
        set.sessionExercise = entry
        warmup.sessionExercise = entry

        let climber = CadenceSchemaV7.Exercise(
            name: "Stair Climber", categoryRaw: "Conditioning", typeRaw: "conditioning")
        climber.movementGroup = "conditioning"
        let climbEntry = CadenceSchemaV7.SessionExercise(order: 1)
        climbEntry.exercise = climber
        let climbSet = CadenceSchemaV7.SetEntry(order: 0)
        climbSet.reps = 1
        climbSet.distanceMiles = 0.75
        climbSet.durationSeconds = 1200
        climbEntry.session = session
        climbSet.sessionExercise = climbEntry

        let settings = CadenceSchemaV7.AppSettings()
        settings.verticalPullMainsPromoted = true

        context.insert(exercise)
        context.insert(deadlift)
        context.insert(session)
        context.insert(entry)
        context.insert(set)
        context.insert(warmup)
        context.insert(climber)
        context.insert(climbEntry)
        context.insert(climbSet)
        context.insert(CadenceSchemaV7.Gym(name: "Migration Gym"))
        context.insert(settings)
        insertV7Program(context)
        try context.save()
    }

    private func insertV7Program(_ context: ModelContext) {
        let program = CadenceSchemaV7.Program(name: "Migration Program")
        let day = CadenceSchemaV7.ProgramDay(name: "Lower", order: 0)
        let lift = CadenceSchemaV7.ProgramLift(exerciseName: "Back Squat")
        lift.baseWeightLb = 175
        let accessory = CadenceSchemaV7.ProgramAccessory(exerciseName: "Seated Leg Curl")
        // One side only — same rule the session fixture above states: a store
        // built with both sides of the inverse assigned would let migration
        // pass on self-corrupted relationship rows production never writes.
        day.program = program; lift.day = day; accessory.day = day
        context.insert(program); context.insert(day); context.insert(lift); context.insert(accessory)
    }
}

/// The broken build's store advertised V1 while containing the #72 model
/// checksum. This test-only wrapper reproduces that metadata exactly.
private enum Shipped72Schema: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { CadenceSchemaV2.models }
}
