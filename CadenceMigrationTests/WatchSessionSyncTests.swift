import CadenceCore
import Foundation
import SwiftData
import XCTest

/// Phone side of watch sync (#335): snapshots, watch-started sessions and
/// merged views written back onto real SwiftData rows.
@MainActor
final class WatchSessionSyncTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var nextID = 0

    private func opID() -> String {
        nextID += 1
        return "op-\(nextID)"
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CadenceSchemaV16.self)
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        // As at app launch: seeding, then the library sync that gives every
        // exercise its portable ID.
        try Seeder.seedIfNeeded(context: container.mainContext)
        try Seeder.syncLibrary(context: container.mainContext)
        return container
    }

    private func lifts(_ context: ModelContext) throws -> (Exercise, Exercise) {
        let all = try context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)]))
            .filter { $0.id != nil && $0.type == .barbell }
        return (try XCTUnwrap(all.first), try XCTUnwrap(all.dropFirst().first))
    }

    /// A planned program session with planning detail the watch never sees.
    private func plannedSession(_ context: ModelContext) throws -> WorkoutSession {
        let (bench, row) = try lifts(context)
        let session = WorkoutSession(date: t0, notes: "Synthetic day", gymID: "gym-1", gymName: "Synthetic Gym")
        session.programID = "program-1"; session.programName = "Synthetic Program"
        session.programCycleNumber = 2; session.programWeek = 3; session.programDayIndex = 1
        session.programPlanNames = [bench.name, row.name]
        context.insert(session)
        for (order, lift) in [bench, row].enumerated() {
            let entry = SessionExercise(order: order, exercise: lift)
            entry.exerciseID = lift.id
            entry.programSlotID = "slot-\(order)"; entry.programRole = order == 0 ? "main" : "accessory"
            entry.plannedWeightLb = 185; entry.plannedSets = 3; entry.plannedReps = 5
            entry.prescriptionStyleRaw = "topSetBackoff"; entry.phaseRaw = 2; entry.barID = "bar-45"
            context.insert(entry)
            entry.session = session
            for setOrder in 0..<3 {
                let set = SetEntry(order: setOrder, weightLb: 185, reps: 5, isWarmup: setOrder == 0,
                                   loadBasis: .totalBar, implementCount: 1, targetWeightLb: 190,
                                   plannedWeightLb: 185, plannedReps: 5)
                context.insert(set)
                set.sessionExercise = entry
            }
        }
        try context.save()
        return session
    }

    /// The watch starts `snapshot`; the phone joins and builds its SwiftData copy.
    private func startOnWatch(_ snapshot: SyncSessionSnapshot, phoneContext context: ModelContext)
        throws -> (watch: SyncEndpoint, phone: SyncEndpoint, session: WorkoutSession) {
        var watch = SyncEndpoint(device: .watch)
        var phone = SyncEndpoint(device: .phone)
        let start = watch.start(sessionID: "c0000000-0000-4000-8000-000000000335", snapshot: snapshot,
                                operationID: opID(), now: t0)!
        XCTAssertEqual(phone.receive(start), .applied)
        let session = try WatchSessionSync.materialize(phone.replica!, startedAt: start.timestamp, context: context)
        try context.save()
        return (watch, phone, session)
    }

    private func layout(_ session: WorkoutSession) -> [String] {
        session.orderedExercises.map { entry in
            "\(entry.exercise?.name ?? "?"):" + entry.orderedSets.map { "\($0.reps)x\(Int($0.weightLb))\($0.status == .completed ? "✓" : "")" }
                .joined(separator: ",")
        }
    }

    // [INV-WATCH-SYNC-IDENTITY]
    func testAWatchStartedSessionKeepsEveryIDAndThePhonesPlan() throws {
        let source = try makeContainer()
        let original = try plannedSession(source.mainContext)
        let snapshot = try WatchSessionSync.snapshot(of: original, title: "Day B", builtAt: t0)
        XCTAssertEqual(snapshot.position, SyncProgramPosition(programID: "program-1", cycle: 2, week: 3, dayIndex: 1))

        let phoneStore = try makeContainer()
        let (_, _, session) = try startOnWatch(snapshot, phoneContext: phoneStore.mainContext)
        XCTAssertEqual(session.id, "c0000000-0000-4000-8000-000000000335")
        XCTAssertEqual(session.programID, "program-1"); XCTAssertEqual(session.programWeek, 3)
        XCTAssertEqual(session.programPlanNames, original.programPlanNames)
        XCTAssertEqual(session.gymName, "Synthetic Gym"); XCTAssertEqual(session.notes, "Synthetic day")
        let pairs = zip(original.orderedExercises, session.orderedExercises)
        XCTAssertEqual(session.orderedExercises.count, 2)
        for (before, after) in pairs {
            XCTAssertEqual(after.syncID, before.syncID)
            XCTAssertEqual(after.exerciseID, before.exerciseID)
            XCTAssertEqual(after.exercise?.name, before.exercise?.name)
            XCTAssertEqual(after.programSlotID, before.programSlotID); XCTAssertEqual(after.programRole, before.programRole)
            XCTAssertEqual(after.prescriptionStyleRaw, "topSetBackoff"); XCTAssertEqual(after.phaseRaw, 2)
            XCTAssertEqual(after.plannedWeightLb, 185); XCTAssertEqual(after.barID, "bar-45")
            XCTAssertEqual(after.orderedSets.map(\.syncID), before.orderedSets.map(\.syncID))
            XCTAssertEqual(after.orderedSets.map(\.isWarmup), before.orderedSets.map(\.isWarmup))
            XCTAssertEqual(after.orderedSets.map(\.targetWeightLb), before.orderedSets.map(\.targetWeightLb))
            XCTAssertEqual(after.orderedSets.map(\.loadBasisRaw), before.orderedSets.map(\.loadBasisRaw))
            XCTAssertEqual(after.orderedSets.map(\.implementCount), before.orderedSets.map(\.implementCount))
        }
    }

    // [INV-WATCH-SYNC-PERFORMED-WORK]
    func testWatchWorkReachesTheRowsAndProjectionIsIdempotent() throws {
        let source = try makeContainer()
        let snapshot = try WatchSessionSync.snapshot(of: try plannedSession(source.mainContext), title: "Day B", builtAt: t0)
        let store = try makeContainer()
        let context = store.mainContext
        var (watch, phone, session) = try startOnWatch(snapshot, phoneContext: context)
        let bench = snapshot.exercises[0]
        let row = snapshot.exercises[1]
        // Apart: the watch logs bench and adds a fourth set; the phone drops a row set.
        for set in bench.sets {
            _ = watch.issue(.setPerformed(setID: set.id, patch: SyncSetPatch(status: .completed, reps: 5,
                weightLb: 185, performedAs: bench.catalog.exerciseID)), operationID: opID(), now: t0)
        }
        let extra = SyncPlannedSet(id: "d0000000-0000-4000-8000-000000000004", reps: 3, weightLb: 195)
        _ = watch.issue(.setAdded(exerciseID: bench.id, after: bench.sets[2].id, set: extra), operationID: opID(), now: t0)
        _ = watch.issue(.setPerformed(setID: extra.id, patch: SyncSetPatch(status: .completed, reps: 3,
            performedAs: bench.catalog.exerciseID)), operationID: opID(), now: t0)
        let removed = row.sets[2].id
        _ = phone.issue(.setRemoved(setID: removed, sawStatus: phone.replica!.statusStamp(ofSet: removed)!),
                        operationID: opID(), now: t0)
        for op in watch.outbox { phone.receive(op) }

        try WatchSessionSync.project(phone.replica!.view(), onto: session,
                                     phone: try WatchSessionSync.phoneContext(of: phone.replica!), context: context)
        try WatchSessionSync.store(phone, in: session)
        try context.save()
        let benchName = session.orderedExercises[0].exercise?.name ?? "?"
        let rowName = session.orderedExercises[1].exercise?.name ?? "?"
        XCTAssertEqual(layout(session), ["\(benchName):5x185✓,5x185✓,5x185✓,3x195✓", "\(rowName):5x185,5x185"])
        XCTAssertNil(try context.fetch(FetchDescriptor<SetEntry>()).first { $0.syncID == removed })
        XCTAssertEqual(session.orderedExercises[0].orderedSets.last?.syncID, extra.id)
        XCTAssertEqual(session.orderedExercises[0].orderedSets.last?.loadBasisRaw, LoadBasis.totalBar.rawValue)

        try WatchSessionSync.project(phone.replica!.view(), onto: session,
                                     phone: try WatchSessionSync.phoneContext(of: phone.replica!), context: context)
        XCTAssertFalse(context.hasChanges, "projecting the same view twice changes nothing")
        XCTAssertEqual(try WatchSessionSync.endpoint(of: session), phone)
    }

    // [INV-WATCH-SYNC-PERFORMED-WORK]
    func testWorkPerformedBeforeAnUnseenSwapStaysWithItsMovement() throws {
        let source = try makeContainer()
        let snapshot = try WatchSessionSync.snapshot(of: try plannedSession(source.mainContext), title: "Day B", builtAt: t0)
        let store = try makeContainer()
        let context = store.mainContext
        var (watch, phone, session) = try startOnWatch(snapshot, phoneContext: context)
        let row = snapshot.exercises[1]
        let other = try XCTUnwrap(try context.fetch(FetchDescriptor<Exercise>()).first {
            $0.id != nil && $0.id != row.catalog.exerciseID && $0.id != snapshot.exercises[0].catalog.exerciseID
        })
        _ = watch.issue(.setPerformed(setID: row.sets[1].id, patch: SyncSetPatch(status: .completed, reps: 8,
            weightLb: 135, performedAs: row.catalog.exerciseID)), operationID: opID(), now: t0)
        let saw = phone.replica!.newestStatusStamp(inExercise: row.id)!
        _ = phone.issue(.exerciseReplaced(exerciseID: row.id, catalog: SyncCatalogExercise(
            exerciseID: other.id!, name: other.name)), operationID: opID(), now: t0)
        for set in row.sets {
            _ = phone.issue(.setRemoved(setID: set.id, sawStatus: saw), operationID: opID(), now: t0)
        }
        for op in watch.outbox { phone.receive(op) }
        let view = phone.replica!.view()
        try WatchSessionSync.project(view, onto: session, phone: try WatchSessionSync.phoneContext(of: phone.replica!),
                                     context: context)
        try context.save()

        XCTAssertEqual(session.orderedExercises.count, 3)
        let reinstated = session.orderedExercises[1]
        XCTAssertEqual(reinstated.exerciseID, row.catalog.exerciseID, "the row set is never recorded as another lift")
        XCTAssertEqual(reinstated.orderedSets.map(\.syncID), [row.sets[1].id])
        XCTAssertNotNil(UUID(uuidString: reinstated.syncID), "a derived entry still gets a valid sync ID")
        XCTAssertEqual(session.orderedExercises[2].exerciseID, other.id)
        XCTAssertTrue(session.orderedExercises[2].orderedSets.isEmpty)
        try Seeder.ensureSyncIDs(context: context)
        try WatchSessionSync.project(view, onto: session, phone: try WatchSessionSync.phoneContext(of: phone.replica!),
                                     context: context)
        XCTAssertFalse(context.hasChanges, "the backfill keeps the derived entry's ID, so projection finds it again")
    }

    // [INV-WATCH-SYNC-PERFORMED-WORK]
    func testPhoneEditsBecomeOperationsInsteadOfBeingOverwritten() throws {
        let source = try makeContainer()
        let snapshot = try WatchSessionSync.snapshot(of: try plannedSession(source.mainContext), title: "Day B", builtAt: t0)
        let store = try makeContainer()
        let context = store.mainContext
        var (watch, phone, session) = try startOnWatch(snapshot, phoneContext: context)
        // The phone's logger edits rows directly: completes a set with a heavier
        // load, flags it, adds a set, deletes another and moves the row first.
        let bench = session.orderedExercises[0]
        let row = session.orderedExercises[1]
        let first = bench.orderedSets[1]
        first.status = .completed; first.weightLb = 195; first.flagsRaw = ["grindy"]
        let added = SetEntry(order: 3, weightLb: 155, reps: 8)
        context.insert(added); added.sessionExercise = bench
        let deleted = row.orderedSets[2].syncID
        context.delete(row.orderedSets[2])
        row.order = -1
        try context.save()
        // Meanwhile the watch completes a different set.
        _ = watch.issue(.setPerformed(setID: snapshot.exercises[1].sets[0].id, patch: SyncSetPatch(
            status: .completed, reps: 8, weightLb: 135, performedAs: snapshot.exercises[1].catalog.exerciseID)),
                        operationID: opID(), now: t0)

        let phoneOps = WatchSessionSync.captureLocalEdits(of: session, into: &phone, now: t0, makeID: opID)
        XCTAssertFalse(phoneOps.isEmpty)
        for op in watch.outbox { phone.receive(op) }
        for op in phoneOps { watch.receive(op) }
        try WatchSessionSync.project(phone.replica!.view(), onto: session,
                                     phone: try WatchSessionSync.phoneContext(of: phone.replica!), context: context)
        try context.save()

        XCTAssertEqual(phone.replica!.view().exercises, watch.replica!.view().exercises, "both devices agree")
        XCTAssertEqual(session.orderedExercises.map(\.syncID), [row.syncID, bench.syncID], "the phone's reorder survives")
        let kept = try XCTUnwrap(bench.orderedSets.first { $0.syncID == first.syncID })
        XCTAssertEqual(kept.status, .completed); XCTAssertEqual(kept.weightLb, 195); XCTAssertEqual(kept.flagsRaw, ["grindy"])
        XCTAssertTrue(bench.orderedSets.contains { $0.syncID == added.syncID && $0.reps == 8 })
        XCTAssertNil(try context.fetch(FetchDescriptor<SetEntry>()).first { $0.syncID == deleted })
        XCTAssertEqual(row.orderedSets.first?.status, .completed, "the watch's work arrives too")
        XCTAssertTrue(WatchSessionSync.captureLocalEdits(of: session, into: &phone, now: t0, makeID: opID).isEmpty,
                      "rows that match the merge produce no operations")
    }

    func testLateWatchSetsReachABankedSessionThroughTheCorrectionPath() throws {
        let source = try makeContainer()
        let snapshot = try WatchSessionSync.snapshot(of: try plannedSession(source.mainContext), title: "Day B", builtAt: t0)
        let store = try makeContainer()
        let context = store.mainContext
        var (watch, phone, session) = try startOnWatch(snapshot, phoneContext: context)
        // The phone banked without the watch; the watch's sets arrive afterwards.
        session.isCompleted = true
        try context.save()
        let bench = snapshot.exercises[0]
        _ = watch.issue(.setPerformed(setID: bench.sets[1].id, patch: SyncSetPatch(status: .completed, reps: 6,
            weightLb: 190, performedAs: bench.catalog.exerciseID)), operationID: opID(), now: t0)
        _ = watch.issue(.setFlags(setID: bench.sets[1].id, flags: ["clean"]), operationID: opID(), now: t0)
        for op in watch.outbox { phone.receive(op) }

        let late = WatchSessionSync.lateCorrections(view: phone.replica!.view(), session: session)
        XCTAssertEqual(late.corrections.count, 1)
        XCTAssertEqual(late.pending, [bench.sets[1].id], "a tag is structural, not a value correction")
        try SessionCorrectionService.applyAndRebuild(late.corrections, in: session, context: context)
        let set = try XCTUnwrap(session.orderedExercises[0].orderedSets.first { $0.syncID == bench.sets[1].id })
        XCTAssertEqual(set.status, .completed); XCTAssertEqual(set.reps, 6); XCTAssertEqual(set.weightLb, 190)
        XCTAssertTrue(WatchSessionSync.lateCorrections(view: phone.replica!.view(), session: session).corrections.isEmpty)

        // The structural remainder: the tag, and a set the watch added late.
        let extra = SyncPlannedSet(id: "e0000000-0000-4000-8000-000000000009", reps: 3, weightLb: 200)
        _ = watch.issue(.setAdded(exerciseID: bench.id, after: bench.sets[2].id, set: extra), operationID: opID(), now: t0)
        _ = watch.issue(.setPerformed(setID: extra.id, patch: SyncSetPatch(status: .completed, reps: 3,
            performedAs: bench.catalog.exerciseID)), operationID: opID(), now: t0)
        for op in watch.outbox { phone.receive(op) }
        let remainder = WatchSessionSync.lateCorrections(view: phone.replica!.view(), session: session)
        try SessionCorrectionService.applyAndRebuild(remainder.corrections, in: session, context: context)
        try SessionCorrectionService.applyWatchStructure(phone.replica!.view(), pendingSetIDs: remainder.pending,
            phone: try WatchSessionSync.phoneContext(of: phone.replica!), to: session, context: context)
        try context.save()
        XCTAssertEqual(set.flagsRaw, ["clean"])
        let added = try XCTUnwrap(session.orderedExercises[0].orderedSets.last)
        XCTAssertEqual(added.syncID, extra.id); XCTAssertEqual(added.status, .completed); XCTAssertEqual(added.weightLb, 200)
        let after = WatchSessionSync.lateCorrections(view: phone.replica!.view(), session: session)
        XCTAssertTrue(after.corrections.isEmpty && after.pending.isEmpty, "nothing late is left unapplied")
    }

    func testAPlannedSnapshotInsertsNothing() throws {
        let store = try makeContainer()
        let context = store.mainContext
        let (lift, _) = try lifts(context)
        let program = Program(name: "Synthetic Program", focus: .strength, isActive: true)
        context.insert(program)
        let day = ProgramDay(name: "Day A", order: 0)
        context.insert(day)
        program.days.append(day)
        let slot = ProgramLift(exerciseName: lift.name, role: .main, order: 0, baseWeightLb: 135, estimatedMaxLb: 200)
        context.insert(slot)
        day.lifts.append(slot)
        try context.save()

        let snapshot = try WatchSessionSync.plannedSnapshot(program: program, day: day, container: store, builtAt: t0)
        XCTAssertEqual(snapshot.title, "Day A")
        XCTAssertFalse(snapshot.exercises.isEmpty)
        XCTAssertEqual(snapshot.exercises[0].catalog.name, lift.name)
        XCTAssertTrue(snapshot.exercises.allSatisfy { UUID(uuidString: $0.id) != nil })
        XCTAssertNotNil(snapshot.phoneContext)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty, "building ahead never inserts a session")
        XCTAssertFalse(context.hasChanges)
    }

    func testWatchHealthOutcomeRoundTrips() {
        let session = WorkoutSession()
        XCTAssertNil(session.watchHealthOutcome)
        session.watchHealthOutcome = .saved(workoutID: "hk-1")
        XCTAssertEqual(session.watchHealthOutcomeRaw, "saved"); XCTAssertEqual(session.watchHealthWorkoutID, "hk-1")
        XCTAssertEqual(session.watchHealthOutcome, .saved(workoutID: "hk-1"))
        session.watchHealthOutcome = .unknown
        XCTAssertEqual(session.watchHealthOutcome, .unknown); XCTAssertNil(session.watchHealthWorkoutID)
        session.watchHealthOutcome = nil
        XCTAssertNil(session.watchHealthOutcomeRaw)
    }
}
