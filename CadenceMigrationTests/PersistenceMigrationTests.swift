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

    func testShippedV3StoreMigratesToV12WithoutDataLoss() throws {
        try assertMigration(
            createStore: createV3Store,
            migrationPlan: CadenceV3MigrationPlan.self,
            expectsExistingSessionID: true
        )
    }

    /// An install that skipped the protein retirement and arrives two versions
    /// behind, so its store crosses both stages in one open.
    func testShippedV4StoreMigratesToV12WithoutDataLoss() throws {
        try assertMigration(
            createStore: { try self.createV4Store(at: $0) },
            migrationPlan: CadenceV4MigrationPlan.self,
            expectsExistingSessionID: true
        )
    }

    /// The common case for this upgrade: every install shipped since protein
    /// logging was retired carries the V5 checksum.
    func testShippedV5StoreMigratesToV12WithoutDataLoss() throws {
        try assertMigration(
            createStore: { try self.createV5Store(at: $0) },
            migrationPlan: CadenceV5MigrationPlan.self,
            expectsExistingSessionID: true
        )
    }

    /// The common case for THIS upgrade: every install shipped since
    /// conditioning learned to count flights carries the V6 checksum.
    func testShippedV6StoreMigratesToV12WithoutDataLoss() throws {
        try assertMigration(
            createStore: { try self.createV6Store(at: $0) },
            migrationPlan: CadenceV6MigrationPlan.self,
            expectsExistingSessionID: true
        )
    }

    /// The common case for THIS upgrade: every install shipped since vertical
    /// pulling was promoted carries the V7 checksum.
    func testShippedV7StoreMigratesToV12WithoutDataLoss() throws {
        try assertMigration(
            createStore: { try self.createV7Store(at: $0) },
            migrationPlan: CadenceV7MigrationPlan.self,
            expectsExistingSessionID: true
        )
    }

    /// The common V9 upgrade: policy columns must reproduce V8 behavior on a
    /// real on-disk store, then accept explicit values after migration.
    func testV8StoreGainsLiteralLegacyProgrammingPolicies() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-v8-policy-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Cadence.store")
        try createV8PolicyStore(at: storeURL)

        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: CadenceV8MigrationPlan.self,
                configurations: ModelConfiguration("migration", schema: schema, url: storeURL)
            )
            let program = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<Program>()).first)
            XCTAssertEqual(program.name, "V8 Policy Program")
            XCTAssertEqual(program.equipmentPolicy, .any,
                           "legacy programs keep the unrestricted equipment behavior")
            let day = try XCTUnwrap(program.orderedDays.first)
            XCTAssertEqual(day.trainingIntent, .general,
                           "legacy day names are not reinterpreted as programming intent")

            program.equipmentPolicy = .freeWeightsOnly
            day.trainingIntent = .explosive
            try container.mainContext.save()
        }

        let reopened = try ModelContainer(
            for: schema,
            migrationPlan: CadenceV8MigrationPlan.self,
            configurations: ModelConfiguration("migration", schema: schema, url: storeURL)
        )
        let program = try XCTUnwrap(try reopened.mainContext.fetch(FetchDescriptor<Program>()).first)
        XCTAssertEqual(program.equipmentPolicy, .freeWeightsOnly)
        XCTAssertEqual(program.orderedDays.first?.trainingIntent, .explosive)
    }

    /// The common V10 upgrade: a real on-disk V9 store gains the interval
    /// model and the manual-bar column without a row being touched.

    /// V10 -> V11 (epic #155 Stage 2): the lightweight stage invents no
    /// identity — every new column reads nil — and the production Seeder
    /// repair then derives the deterministic legacy ids, idempotently.
    func testV10StoreGainsPortableIdentityWithoutTouchingAnything() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-v10-identity-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Cadence.store")
        try createV10IdentityStore(at: storeURL)

        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
        let expectedID = StableID.exerciseLegacyID(name: "Legacy Row")
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: CadenceV10MigrationPlan.self,
                configurations: ModelConfiguration("migration", schema: schema, url: storeURL)
            )
            let context = container.mainContext
            let exercise = try XCTUnwrap(
                try context.fetch(FetchDescriptor<Exercise>()).first { $0.name == "Legacy Row" })
            XCTAssertNil(exercise.id, "the lightweight stage must not invent identity")
            let lift = try XCTUnwrap(try context.fetch(FetchDescriptor<ProgramLift>()).first)
            XCTAssertNil(lift.exerciseID)
            XCTAssertEqual(lift.baseWeightLb, 185, "programming values survive")

            try Seeder.syncLibrary(context: context)
            XCTAssertEqual(exercise.id, expectedID,
                           "the repair derives the deterministic legacy id")
            XCTAssertEqual(lift.exerciseID, expectedID)
            XCTAssertEqual(try context.fetch(FetchDescriptor<LiftTrack>()).first?.exerciseID, expectedID)
            XCTAssertEqual(try context.fetch(FetchDescriptor<Milestone>()).first?.exerciseID, expectedID)
            let entry = try XCTUnwrap(try context.fetch(FetchDescriptor<SessionExercise>()).first)
            XCTAssertEqual(entry.exerciseID, expectedID)
            XCTAssertNil(try context.fetch(FetchDescriptor<Program>())
                .first { $0.name == "V10 Identity Program" }?.templateID,
                "a legacy program's template origin stays unknown — never guessed")

            // Idempotence: the repair run again rewrites nothing.
            try Seeder.syncLibrary(context: context)
            XCTAssertFalse(context.hasChanges, "a second repair pass writes nothing")
        }

        let reopened = try ModelContainer(
            for: schema,
            migrationPlan: CadenceV10MigrationPlan.self,
            configurations: ModelConfiguration("migration", schema: schema, url: storeURL)
        )
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<Exercise>())
            .first { $0.name == "Legacy Row" }?.id, expectedID, "derived ids persist")
    }

    /// V11 -> V12 (#166): the lightweight stage adds only the brand-new
    /// `ActivityDetail` model and an optional relationship every existing
    /// session reads as nil. A real on-disk V11 store upgrades without a
    /// row being touched, and the production creator then writes the
    /// canonical activity shape (wood splitting, the first kind) into the
    /// migrated store — one off-program `WorkoutSession` on the same
    /// timeline as the training log [INV-WOOD-WORK-USES-ONE-TIMELINE].
    func testV11StoreGainsActivityDetailWithoutTouchingAnything() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-v11-wood-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Cadence.store")
        try createV11WoodStore(at: storeURL)

        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
        var woodSessionID = ""
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: CadenceV11MigrationPlan.self,
                configurations: ModelConfiguration("migration", schema: schema, url: storeURL)
            )
            let context = container.mainContext
            let migrated = try XCTUnwrap(
                try context.fetch(FetchDescriptor<WorkoutSession>()).first { $0.notes == "V11 training day" })
            XCTAssertNil(migrated.activityDetail, "existing sessions carry no detail")
            XCTAssertTrue(migrated.isCompleted)
            let migratedSet = try XCTUnwrap(migrated.orderedExercises.first?.workingSets.first)
            XCTAssertEqual(migratedSet.weightLb, 225, "manual training values survive")
            XCTAssertEqual(migratedSet.reps, 5)
            XCTAssertEqual(try context.fetch(FetchDescriptor<ActivityDetail>()).count, 0)

            // The production preparation seeds the canonical exercise, and the
            // production creator writes the quick-log shape into the migrated
            // store: off-program, one entry, one completed duration set.
            try Seeder.syncLibrary(context: context)
            let wood = try ActivitySession.create(
                input: .init(
                    kind: .woodSplitting,
                    startDate: migrated.date.addingTimeInterval(6 * 3600),
                    durationSeconds: 7_200, sessionRPE: 8.5, loadLb: 8,
                    notes: "Wet oak",
                    woodSplitting: .init(rounds: 55, splitPieces: 15,
                                         estimatedStrikes: 340, cordVolume: 0.25)
                ),
                context: context
            )
            woodSessionID = wood.id
            try context.save()
            XCTAssertNil(wood.programID, "wood splitting never joins a program")
            XCTAssertEqual(wood.orderedExercises.count, 1, "no aliased entry rows")
            XCTAssertEqual(wood.orderedExercises.first?.orderedSets.count, 1, "no aliased set rows")
            XCTAssertEqual(ActivitySession.workload(for: wood)?.arbitraryUnits, 1_020)
            XCTAssertNil(migrated.activityDetail, "the training session stays untouched")
        }

        let reopened = try ModelContainer(
            for: schema,
            migrationPlan: CadenceV11MigrationPlan.self,
            configurations: ModelConfiguration("migration", schema: schema, url: storeURL)
        )
        let context = reopened.mainContext
        let wood = try XCTUnwrap(
            try context.fetch(FetchDescriptor<WorkoutSession>()).first { $0.id == woodSessionID })
        let detail = try XCTUnwrap(wood.activityDetail, "the typed detail persists on disk")
        XCTAssertEqual(detail.kind, .woodSplitting)
        XCTAssertEqual(detail.sessionRPE, 8.5)
        XCTAssertEqual(detail.rounds, 55)
        XCTAssertEqual(detail.splitPieces, 15)
        XCTAssertEqual(detail.estimatedStrikes, 340)
        XCTAssertEqual(detail.cordVolume, 0.25)
        let set = try XCTUnwrap(wood.orderedExercises.first?.workingSets.first)
        XCTAssertEqual(set.durationSeconds, 7_200, "duration lives only on the canonical set")
        XCTAssertEqual(set.weightLb, 8, "maul weight lives only on the canonical set")
        XCTAssertEqual(wood.orderedExercises.first?.workingVolumeLb, 0,
                       "wood splitting is never lifting volume")
    }

    /// The seed ships the registered activity kinds' canonical exercises by
    /// literal name (the web parity check parses the literals from source);
    /// this pins each literal to the registry constant the creator resolves
    /// against, so a rename in either place fails here instead of throwing
    /// `missingExercise` at every quick log.
    func testSeedCarriesEveryRegisteredActivityExercise() {
        let seeded = Set(Seeder.libraryDefinitions().map(\.name))
        for kind in ActivityKind.allCases {
            XCTAssertTrue(seeded.contains(kind.exerciseName),
                          "the seed is missing \(kind.rawValue)'s canonical exercise \(kind.exerciseName)")
        }
    }

    /// The creator is the write-site guard for every recorded number, not
    /// just RPE: both importers require these non-negative and finite, and a
    /// non-finite Double makes JSONEncoder refuse the export outright. An
    /// app must never bank a row whose own backup it cannot restore.
    func testCreatorRejectsValuesItsOwnBackupWouldRefuse() throws {
        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        try Seeder.seedIfNeeded(context: context)
        func input(
            sessionRPE: Double? = 8, loadLb: Double? = 8,
            wood: ActivitySession.WoodSplittingFacts = .init()
        ) -> ActivitySession.Input {
            .init(kind: .woodSplitting, startDate: .now, durationSeconds: 7_200,
                  sessionRPE: sessionRPE, loadLb: loadLb, notes: "", woodSplitting: wood)
        }
        let rejected: [(String, ActivitySession.Input)] = [
            ("duration", .init(kind: .woodSplitting, startDate: .now, durationSeconds: 0,
                               sessionRPE: 8, loadLb: nil, notes: "", woodSplitting: nil)),
            ("sessionRPE", input(sessionRPE: 11)),
            ("loadLb", input(loadLb: -8)),
            ("rounds", input(wood: .init(rounds: -1))),
            ("splitPieces", input(wood: .init(splitPieces: -1))),
            ("estimatedStrikes", input(wood: .init(estimatedStrikes: -1))),
            ("cordVolume", input(wood: .init(cordVolume: -0.25))),
            ("non-finite cordVolume", input(wood: .init(cordVolume: Double.infinity))),
        ]
        for (label, bad) in rejected {
            XCTAssertThrowsError(try ActivitySession.create(input: bad, context: context),
                                 "an out-of-contract \(label) must never be banked")
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<ActivityDetail>()).count, 0,
                       "a rejected quick log leaves no partial rows behind")
    }

    /// The iPhone quick editor mutates the one canonical activity row rather
    /// than delete/recreate. Identity matters to history ordering and backup
    /// diffs; the entry denomination matters when a kilogram maul is edited.
    func testActivityQuickEditPreservesIdentityAndOffProgramShape() throws {
        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        // Keep this regression fixture deliberately narrow. Seeding the full
        // program graph here leaves V12 ProgramDay/ProgramLift metadata alive
        // long enough to collide with the V11 ProgramActivation fixtures in
        // the same Xcode 26 test process; the editor only needs its canonical
        // activity exercise.
        context.insert(Exercise(
            name: ActivityKind.woodSplitting.exerciseName,
            category: .conditioning,
            type: .conditioning,
            movementGroup: "conditioning",
            notes: "Duration / maul weight"
        ))
        try context.save()
        let original = try ActivitySession.create(
            input: .init(kind: .woodSplitting, startDate: .now,
                         durationSeconds: 3_600, sessionRPE: 7, loadLb: 8,
                         notes: "First pile",
                         woodSplitting: .init(rounds: 20, splitPieces: 30)),
            context: context
        )
        // SwiftData relationship models use temporary persistent identifiers
        // until their first save. Establish permanent IDs before proving that
        // the editor mutates these rows instead of replacing them.
        try context.save()
        let originalID = original.id
        let originalEntryID = try XCTUnwrap(original.orderedExercises.first?.id)
        let originalSetID = try XCTUnwrap(original.orderedExercises.first?.orderedSets.first?.id)

        try ActivitySession.update(
            session: original,
            input: .init(kind: .woodSplitting,
                         startDate: original.date.addingTimeInterval(600),
                         durationSeconds: 7_500, sessionRPE: 9,
                         loadLb: Weight.toLb(4, from: .kg), notes: "Oak rounds",
                         woodSplitting: .init(rounds: 60, cordVolume: 0.4),
                         enteredUnit: .kg),
            context: context
        )
        try context.save()

        XCTAssertEqual(original.id, originalID)
        XCTAssertEqual(original.orderedExercises.first?.id, originalEntryID)
        XCTAssertEqual(original.orderedExercises.first?.orderedSets.first?.id, originalSetID)
        XCTAssertNil(original.programID)
        XCTAssertNil(original.programName)
        XCTAssertNil(original.orderedExercises.first?.programRole)
        XCTAssertEqual(original.orderedExercises.count, 1)
        XCTAssertEqual(original.orderedExercises.first?.orderedSets.count, 1)
        let editedSet = try XCTUnwrap(original.orderedExercises.first?.orderedSets.first)
        XCTAssertEqual(editedSet.enteredUnit, .kg)
        XCTAssertEqual(editedSet.durationSeconds, 7_500)
        XCTAssertEqual(editedSet.weightLb, Weight.toLb(4, from: .kg), accuracy: 0.000_001)
        XCTAssertEqual(original.activityDetail?.rounds, 60)
        XCTAssertNil(original.activityDetail?.splitPieces,
                     "an optional fact cleared by the user stays absent")
        XCTAssertEqual(original.activityDetail?.cordVolume, 0.4)
        XCTAssertEqual(ActivitySession.workload(for: original)?.arbitraryUnits, 1_125)
    }

    /// Editing is deliberately not a repair path. If a damaged import or old
    /// bug left extra rows, a warmup row, or a program relationship on an
    /// activity, mutating only the first set would preserve a contradictory
    /// record. Refuse it and leave every row available for explicit recovery.
    func testActivityQuickEditRejectsNoncanonicalSessionShape() throws {
        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let exercise = Exercise(
            name: ActivityKind.woodSplitting.exerciseName,
            category: .conditioning,
            type: .conditioning,
            movementGroup: "conditioning"
        )
        context.insert(exercise)

        let input = ActivitySession.Input(
            kind: .woodSplitting,
            startDate: .now,
            durationSeconds: 3_600,
            sessionRPE: 8,
            loadLb: 8,
            notes: "Synthetic oak",
            woodSplitting: .init(rounds: 20)
        )

        let extraEntrySession = try ActivitySession.create(input: input, context: context)
        let extraEntry = SessionExercise(order: 1, exercise: exercise)
        context.insert(extraEntry)
        extraEntrySession.exercises.append(extraEntry)
        XCTAssertThrowsError(
            try ActivitySession.update(session: extraEntrySession, input: input, context: context)
        )

        let extraSetSession = try ActivitySession.create(input: input, context: context)
        let extraSet = SetEntry(
            order: 1,
            weightLb: 8,
            reps: 0,
            status: .completed,
            durationSeconds: 60,
            prescriptionBlock: .conditioning
        )
        context.insert(extraSet)
        let extraSetEntry = try XCTUnwrap(extraSetSession.orderedExercises.first)
        extraSetEntry.sets.append(extraSet)
        XCTAssertThrowsError(
            try ActivitySession.update(session: extraSetSession, input: input, context: context)
        )

        let warmupSession = try ActivitySession.create(input: input, context: context)
        let corruptedWarmup = try XCTUnwrap(warmupSession.orderedExercises.first?.orderedSets.first)
        corruptedWarmup.isWarmup = true
        XCTAssertThrowsError(
            try ActivitySession.update(session: warmupSession, input: input, context: context)
        )

        let programmedSession = try ActivitySession.create(input: input, context: context)
        programmedSession.programName = "Not off-program"
        XCTAssertThrowsError(
            try ActivitySession.update(session: programmedSession, input: input, context: context)
        )
    }

    func testV9StoreGainsIntervalsAndManualBarWithoutTouchingAnything() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-v9-interval-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Cadence.store")
        try createV9IntervalStore(at: storeURL)

        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: CadenceV9MigrationPlan.self,
                configurations: ModelConfiguration("migration", schema: schema, url: storeURL)
            )
            let context = container.mainContext
            let program = try XCTUnwrap(try context.fetch(FetchDescriptor<Program>()).first)
            XCTAssertEqual(program.name, "V9 Interval Program")
            XCTAssertEqual(program.equipmentPolicy, .freeWeightsOnly,
                           "an explicit V9 policy survives the upgrade")
            let entry = try XCTUnwrap(try context.fetch(FetchDescriptor<SessionExercise>()).first)
            XCTAssertEqual(entry.barID, "45-lb", "the stamped bar survives")
            XCTAssertFalse(entry.barIDIsManual,
                           "a pre-V10 entry must not read as a manual pick")
            XCTAssertTrue(try context.fetch(FetchDescriptor<TrainingInterval>()).isEmpty,
                          "no interval is invented by the upgrade")

            entry.barIDIsManual = true
            let interval = TrainingInterval(
                kindRaw: "away",
                startDate: IntervalDay.date(from: "2026-07-10")!,
                endDate: IntervalDay.date(from: "2026-07-20")!,
                note: "trip"
            )
            context.insert(interval)
            try context.save()
        }

        let reopened = try ModelContainer(
            for: schema,
            migrationPlan: CadenceV9MigrationPlan.self,
            configurations: ModelConfiguration("migration", schema: schema, url: storeURL)
        )
        let context = reopened.mainContext
        XCTAssertEqual(try context.fetch(FetchDescriptor<SessionExercise>()).first?.barIDIsManual, true)
        let interval = try XCTUnwrap(try context.fetch(FetchDescriptor<TrainingInterval>()).first)
        XCTAssertEqual(interval.kind, .away)
        XCTAssertEqual(IntervalDay.string(from: interval.startDate), "2026-07-10")
        XCTAssertEqual(IntervalDay.string(from: interval.endDate), "2026-07-20")
    }


    /// V11 identity round trip (epic #155 Stage 2): exported ids survive a
    /// restore verbatim, and a v10 bundle stripped of every id derives the
    /// same deterministic legacy ids web derives — cross-client identity for
    /// identical content.
    func testBackupRoundTripsIdentityAndDerivesLegacyIDs() throws {
        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
        let source = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let context = source.mainContext
        let exercise = Exercise(name: "Round Trip Row", category: .main, type: .barbell, movementGroup: "hinge")
        exercise.id = "12345678-1234-4123-a123-123456789abc"   // a user-created random UUID
        context.insert(exercise)
        let session = WorkoutSession(date: .now)
        context.insert(session)
        let entry = SessionExercise(order: 0, exercise: exercise)
        entry.exerciseID = exercise.id
        context.insert(entry)
        session.exercises.append(entry)
        try context.save()

        let backup = try ExportService.jsonData(context: context)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: backup) as? [String: Any])
        let exportedDef = try XCTUnwrap((json["exercises"] as? [[String: Any]])?
            .first { $0["name"] as? String == "Round Trip Row" })
        XCTAssertEqual(exportedDef["id"] as? String, exercise.id, "the portable id rides the bundle")

        // v11 ids restore verbatim.
        let restored = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        try ImportService.load(backup, into: restored.mainContext)
        XCTAssertEqual(try restored.mainContext.fetch(FetchDescriptor<Exercise>())
            .first { $0.name == "Round Trip Row" }?.id, exercise.id)

        // A v10 bundle carries no ids: the importer derives the deterministic
        // legacy id from the name — the exact value web derives.
        var legacyJSON = json
        legacyJSON["schemaVersion"] = 10
        var defs = try XCTUnwrap(legacyJSON["exercises"] as? [[String: Any]])
        for index in defs.indices { defs[index].removeValue(forKey: "id") }
        legacyJSON["exercises"] = defs
        let legacyData = try JSONSerialization.data(withJSONObject: legacyJSON)
        let legacy = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        try ImportService.load(legacyData, into: legacy.mainContext)
        XCTAssertEqual(try legacy.mainContext.fetch(FetchDescriptor<Exercise>())
            .first { $0.name == "Round Trip Row" }?.id,
            StableID.exerciseLegacyID(name: "Round Trip Row"),
            "a v10 def derives the deterministic legacy id")
        XCTAssertEqual(try legacy.mainContext.fetch(FetchDescriptor<SessionExercise>())
            .first?.exerciseID, StableID.exerciseLegacyID(name: "Round Trip Row"),
            "a v10 session entry derives the same id from its name")
    }

    func testNativeBackupRoundTripsIntervalsAndManualBarMarker() throws {
        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
        let source = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let context = source.mainContext
        let interval = TrainingInterval(
            kindRaw: "activeRecovery",
            startDate: IntervalDay.date(from: "2026-06-01")!,
            endDate: IntervalDay.date(from: "2026-06-07")!,
            enteredAsDays: false,
            note: "physio block"
        )
        context.insert(interval)
        let session = WorkoutSession(date: IntervalDay.date(from: "2026-06-03")!)
        let entry = SessionExercise(order: 0, exercise: nil)
        entry.barID = "20-kg"
        entry.barIDIsManual = true
        context.insert(entry)
        session.exercises.append(entry)
        context.insert(session)
        try context.save()

        let backup = try ExportService.jsonData(context: context)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: backup) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 12)
        let exportedInterval = try XCTUnwrap((json["intervals"] as? [[String: Any]])?.first)
        XCTAssertEqual(exportedInterval["kind"] as? String, "activeRecovery")
        XCTAssertEqual(exportedInterval["startDate"] as? String, "2026-06-01")
        XCTAssertEqual(exportedInterval["endDate"] as? String, "2026-06-07")
        XCTAssertEqual(exportedInterval["enteredAsDays"] as? Bool, false)
        let exportedEntry = try XCTUnwrap(
            ((json["sessions"] as? [[String: Any]])?.first?["exercises"] as? [[String: Any]])?.first
        )
        XCTAssertEqual(exportedEntry["barIdManual"] as? Bool, true,
                       "a manual pick rides the bundle")

        let restored = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        try ImportService.load(backup, into: restored.mainContext)
        let roundTripped = try XCTUnwrap(
            try restored.mainContext.fetch(FetchDescriptor<TrainingInterval>()).first
        )
        XCTAssertEqual(roundTripped.kind, .activeRecovery)
        XCTAssertEqual(roundTripped.enteredAsDays, false)
        XCTAssertEqual(roundTripped.note, "physio block")
        XCTAssertEqual(roundTripped.id, interval.id, "interval identity survives restore")
        let restoredEntry = try XCTUnwrap(
            try restored.mainContext.fetch(FetchDescriptor<SessionExercise>()).first
        )
        XCTAssertEqual(restoredEntry.barIDIsManual, true)

        // A v9 bundle carries no intervals key: restoring it must leave the
        // store's existing intervals alone (only collections present in the
        // bundle are replaced) and every bar reads as stamped.
        var legacyJSON = json
        legacyJSON["schemaVersion"] = 9
        legacyJSON.removeValue(forKey: "intervals")
        var legacySessions = try XCTUnwrap(legacyJSON["sessions"] as? [[String: Any]])
        var legacyExercises = try XCTUnwrap(legacySessions[0]["exercises"] as? [[String: Any]])
        legacyExercises[0].removeValue(forKey: "barIdManual")
        legacySessions[0]["exercises"] = legacyExercises
        legacyJSON["sessions"] = legacySessions
        try ImportService.load(
            JSONSerialization.data(withJSONObject: legacyJSON),
            into: restored.mainContext
        )
        XCTAssertEqual(try restored.mainContext.fetch(FetchDescriptor<TrainingInterval>()).count, 1,
                       "a v9 restore leaves declared breaks in place")
        XCTAssertEqual(
            try restored.mainContext.fetch(FetchDescriptor<SessionExercise>()).first?.barIDIsManual,
            false,
            "a v9 entry reads as stamped"
        )
    }

    /// v12 (#166): every recorded activity fact — the kind included —
    /// survives export and restore, duration and implement load stay on the
    /// canonical set, and a v11 bundle restores with no detail invented
    /// anywhere [INV-WOOD-WORK-ROUND-TRIPS].
    func testNativeBackupRoundTripsActivityDetail() throws {
        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
        let source = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let context = source.mainContext
        try Seeder.seedIfNeeded(context: context)
        _ = try ActivitySession.create(
            input: .init(
                kind: .woodSplitting,
                startDate: IntervalDay.date(from: "2026-06-03")!,
                durationSeconds: 7_200, sessionRPE: 8.5, loadLb: 8,
                notes: "Wet oak",
                woodSplitting: .init(rounds: 55, splitPieces: nil,
                                     estimatedStrikes: nil, cordVolume: 0.25)
            ),
            context: context
        )
        try context.save()

        let backup = try ExportService.jsonData(context: context)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: backup) as? [String: Any])
        let exportedSession = try XCTUnwrap(
            (json["sessions"] as? [[String: Any]])?.first { $0["activity"] != nil })
        let exportedWood = try XCTUnwrap(exportedSession["activity"] as? [String: Any])
        XCTAssertEqual(exportedWood["kind"] as? String, "woodSplitting")
        XCTAssertEqual(exportedWood["sessionRPE"] as? Double, 8.5)
        XCTAssertEqual(exportedWood["rounds"] as? Int, 55)
        XCTAssertEqual(exportedWood["cordVolume"] as? Double, 0.25)
        XCTAssertNil(exportedWood["splitPieces"], "absent facts stay absent")
        let exportedSet = try XCTUnwrap(
            ((exportedSession["exercises"] as? [[String: Any]])?.first?["sets"] as? [[String: Any]])?.first)
        XCTAssertEqual(exportedSet["durationSeconds"] as? Int, 7_200,
                       "duration is only on the canonical set")
        XCTAssertEqual(exportedSet["weightLb"] as? Double, 8)

        let restored = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        try ImportService.load(backup, into: restored.mainContext)
        let roundTripped = try XCTUnwrap(
            try restored.mainContext.fetch(FetchDescriptor<WorkoutSession>())
                .first { $0.activityDetail != nil })
        let detail = try XCTUnwrap(roundTripped.activityDetail)
        XCTAssertEqual(detail.kind, .woodSplitting)
        XCTAssertEqual(detail.sessionRPE, 8.5)
        XCTAssertEqual(detail.rounds, 55)
        XCTAssertNil(detail.splitPieces)
        XCTAssertNil(detail.estimatedStrikes)
        XCTAssertEqual(detail.cordVolume, 0.25)
        XCTAssertEqual(ActivitySession.workload(for: roundTripped)?.arbitraryUnits, 1_020)

        // A v11 bundle carries no activity key anywhere: the restore must
        // not invent a detail for any session.
        var legacyJSON = json
        legacyJSON["schemaVersion"] = 11
        var legacySessions = try XCTUnwrap(legacyJSON["sessions"] as? [[String: Any]])
        for index in legacySessions.indices { legacySessions[index].removeValue(forKey: "activity") }
        legacyJSON["sessions"] = legacySessions
        let legacy = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        try ImportService.load(
            JSONSerialization.data(withJSONObject: legacyJSON),
            into: legacy.mainContext
        )
        XCTAssertEqual(try legacy.mainContext.fetch(FetchDescriptor<ActivityDetail>()).count, 0,
                       "a v11 restore invents no activity detail")

        // Native validation mirrors web validateBackup: an unregistered
        // kind or an out-of-contract RPE rejects the bundle before any
        // write, so both clients refuse the same file.
        let mutations: [(String, Any)] = [("kind", "hiking"), ("sessionRPE", 15)]
        for (key, value) in mutations {
            var badJSON = json
            var badSessions = try XCTUnwrap(badJSON["sessions"] as? [[String: Any]])
            for index in badSessions.indices where badSessions[index]["activity"] != nil {
                var activity = try XCTUnwrap(badSessions[index]["activity"] as? [String: Any])
                activity[key] = value
                badSessions[index]["activity"] = activity
            }
            badJSON["sessions"] = badSessions
            let rejected = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
            XCTAssertThrowsError(try ImportService.load(
                JSONSerialization.data(withJSONObject: badJSON),
                into: rejected.mainContext
            ), "a malformed activity object must reject before writes, as web does")
        }
    }

    func testNativeBackupRoundTripsProgrammingPoliciesAndDefaultsLegacyBundles() throws {
        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
        let source = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let program = Program(name: "Policy Round Trip", focus: .strength)
        program.equipmentPolicy = .freeWeightsOnly
        let day = ProgramDay(name: "Heavy Lower", order: 0)
        day.trainingIntent = .heavy
        program.days.append(day)
        source.mainContext.insert(program)
        source.mainContext.insert(day)
        try source.mainContext.save()

        let backup = try ExportService.jsonData(context: source.mainContext)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: backup) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 12)
        let exportedProgram = try XCTUnwrap((json["programs"] as? [[String: Any]])?.first)
        XCTAssertEqual(exportedProgram["equipmentPolicy"] as? String, "freeWeightsOnly")
        let exportedDay = try XCTUnwrap((exportedProgram["days"] as? [[String: Any]])?.first)
        XCTAssertEqual(exportedDay["trainingIntent"] as? String, "heavy")

        let restored = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        try ImportService.load(backup, into: restored.mainContext)
        let roundTripped = try XCTUnwrap(try restored.mainContext.fetch(FetchDescriptor<Program>()).first)
        XCTAssertEqual(roundTripped.equipmentPolicy, .freeWeightsOnly)
        XCTAssertEqual(roundTripped.orderedDays.first?.trainingIntent, .heavy)

        var legacyJSON = json
        legacyJSON["schemaVersion"] = 8
        var legacyPrograms = try XCTUnwrap(legacyJSON["programs"] as? [[String: Any]])
        legacyPrograms[0].removeValue(forKey: "equipmentPolicy")
        var legacyDays = try XCTUnwrap(legacyPrograms[0]["days"] as? [[String: Any]])
        legacyDays[0].removeValue(forKey: "trainingIntent")
        legacyPrograms[0]["days"] = legacyDays
        legacyJSON["programs"] = legacyPrograms

        let legacyRestored = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        try ImportService.load(
            JSONSerialization.data(withJSONObject: legacyJSON),
            into: legacyRestored.mainContext
        )
        let legacy = try XCTUnwrap(try legacyRestored.mainContext.fetch(FetchDescriptor<Program>()).first)
        XCTAssertEqual(legacy.equipmentPolicy, .any)
        XCTAssertEqual(legacy.orderedDays.first?.trainingIntent, .general)
    }

    func testNativeStandaloneProgramRoundTripsProgrammingPolicies() throws {
        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
        let source = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let program = Program(name: "Standalone Policy", focus: .strength)
        program.equipmentPolicy = .freeWeightsOnly
        let day = ProgramDay(name: "Speed Lower", order: 0)
        day.trainingIntent = .explosive
        let lift = ProgramLift(
            exerciseName: "Back Squat",
            role: .main,
            baseWeightLb: 135,
            estimatedMaxLb: 185
        )
        day.lifts.append(lift)
        program.days.append(day)
        source.mainContext.insert(program)
        source.mainContext.insert(day)
        source.mainContext.insert(lift)
        try source.mainContext.save()

        let data = try ProgramExportService.jsonData(for: program)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["programSchemaVersion"] as? Int, 2)
        let payload = try XCTUnwrap(json["program"] as? [String: Any])
        XCTAssertEqual(payload["equipmentPolicy"] as? String, "freeWeightsOnly")

        let restored = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        restored.mainContext.insert(Exercise(name: "Back Squat", category: .main, type: .barbell))
        try restored.mainContext.save()
        try ProgramImportService.load(data, into: restored.mainContext)

        let imported = try XCTUnwrap(try restored.mainContext.fetch(FetchDescriptor<Program>()).first)
        XCTAssertEqual(imported.equipmentPolicy, .freeWeightsOnly)
        XCTAssertEqual(imported.orderedDays.first?.trainingIntent, .explosive)
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

        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
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

        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
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
        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
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
        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
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

        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
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

        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
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
        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
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
        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
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
        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
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
        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
        let configuration = {
            ModelConfiguration("migration", schema: schema, url: storeURL)
        }
        let attempts: [() throws -> ModelContainer] = [
            { try ModelContainer(for: schema, migrationPlan: CadenceV10MigrationPlan.self,
                                 configurations: configuration()) },
            { try ModelContainer(for: schema, migrationPlan: CadenceV9MigrationPlan.self,
                                 configurations: configuration()) },
            { try ModelContainer(for: schema, migrationPlan: CadenceV8MigrationPlan.self,
                                 configurations: configuration()) },
            { try ModelContainer(for: schema, migrationPlan: CadenceV7MigrationPlan.self,
                                 configurations: configuration()) },
            { try ModelContainer(for: schema, migrationPlan: CadenceV6MigrationPlan.self,
                                 configurations: configuration()) },
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

        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
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
        XCTAssertEqual(programs.first?.equipmentPolicy, .any)
        XCTAssertEqual(programs.first?.orderedDays.first?.trainingIntent, .general)
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


    private func createV10IdentityStore(at url: URL) throws {
        let schema = Schema(versionedSchema: CadenceSchemaV10.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext

        let exercise = CadenceSchemaV10.Exercise(name: "Legacy Row", categoryRaw: "Main", typeRaw: "barbell")
        let program = CadenceSchemaV10.Program(name: "V10 Identity Program")
        let day = CadenceSchemaV10.ProgramDay(name: "Pull", order: 0)
        let lift = CadenceSchemaV10.ProgramLift(exerciseName: "Legacy Row")
        lift.baseWeightLb = 185
        let session = CadenceSchemaV10.WorkoutSession(date: .now)
        session.isCompleted = true
        let entry = CadenceSchemaV10.SessionExercise(order: 0)
        let track = CadenceSchemaV10.LiftTrack(exerciseName: "Legacy Row")
        let milestone = CadenceSchemaV10.Milestone(kindRaw: "heaviestSet", label: "185 lb x 5")
        milestone.exerciseName = "Legacy Row"
        // One side only — same rule the other fixtures state.
        day.program = program; lift.day = day
        entry.session = session; entry.exercise = exercise
        context.insert(exercise); context.insert(program); context.insert(day); context.insert(lift)
        context.insert(session); context.insert(entry); context.insert(track); context.insert(milestone)
        try context.save()
    }

    private func createV11WoodStore(at url: URL) throws {
        let schema = Schema(versionedSchema: CadenceSchemaV11.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext

        let exercise = CadenceSchemaV11.Exercise(name: "Back Squat", categoryRaw: "Main", typeRaw: "barbell")
        exercise.id = StableID.exerciseLegacyID(name: "Back Squat")
        let session = CadenceSchemaV11.WorkoutSession(date: .now)
        session.notes = "V11 training day"
        session.isCompleted = true
        let entry = CadenceSchemaV11.SessionExercise(order: 0)
        entry.exerciseID = exercise.id
        let set = CadenceSchemaV11.SetEntry(order: 0)
        set.weightLb = 225
        set.reps = 5
        set.statusRaw = "completed"
        // One side only — same rule the other fixtures state.
        entry.exercise = exercise
        entry.session = session
        set.sessionExercise = entry
        context.insert(exercise); context.insert(session); context.insert(entry); context.insert(set)
        try context.save()
    }

    private func createV9IntervalStore(at url: URL) throws {
        let schema = Schema(versionedSchema: CadenceSchemaV9.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext

        let program = CadenceSchemaV9.Program(name: "V9 Interval Program")
        program.equipmentPolicyRaw = "freeWeightsOnly"
        let day = CadenceSchemaV9.ProgramDay(name: "Heavy Lower", order: 0)
        day.trainingIntentRaw = "heavy"
        day.program = program
        let session = CadenceSchemaV9.WorkoutSession(date: .now)
        let entry = CadenceSchemaV9.SessionExercise(order: 0)
        entry.barID = "45-lb"
        entry.session = session
        context.insert(program)
        context.insert(day)
        context.insert(session)
        context.insert(entry)
        try context.save()
    }

    private func createV8PolicyStore(at url: URL) throws {
        let schema = Schema(versionedSchema: CadenceSchemaV8.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext

        let program = CadenceSchemaV8.Program(name: "V8 Policy Program")
        let day = CadenceSchemaV8.ProgramDay(name: "Speed Lower", order: 4)
        day.program = program
        context.insert(program)
        context.insert(day)
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
