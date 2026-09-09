import Foundation
import SwiftData
import XCTest
import CadenceCore

@MainActor
final class TFHIntegrationTests: XCTestCase {
    private func container() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CadenceSchemaV13.self)
        return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    private func fixture(_ context: ModelContext) throws -> Program {
        let ex = Exercise(name: "TFH Fixture Press", category: .main, type: .dumbbell,
                          loadBasis: .perImplement, implementCount: 2)
        ex.id = UUID().uuidString; context.insert(ex)
        let p = Program(name: "TFH fixture"); context.insert(p)
        for i in 0..<2 {
            let d = ProgramDay(name: "Day \(i)", order: i); context.insert(d); p.days.append(d)
            let l = ProgramLift(exerciseName: ex.name, role: .main, baseWeightLb: 60, estimatedMaxLb: 0)
            l.exerciseID = ex.id; l.minimumReps = 3; l.maximumReps = 5; l.currentReps = 3
            context.insert(l); d.lifts.append(l)
        }
        try context.save()
        let draft = try TFHProgramService.draft(p, exercises: [ex], sessions: [])
        try TFHProgramService.activate(draft, program: p, exercises: [ex], context: context)
        return p
    }

    private func bank(_ session: WorkoutSession, program: Program, context: ModelContext) throws {
        for set in session.exercises.flatMap(\.orderedSets) { set.status = .completed; set.quality = .clean }
        session.tfhContext = "same setup and preceding work"
        session.isCompleted = true; session.completedAt = session.date
        try TFHProgramService.complete(session, program: program, context: context)
        try context.save()
    }

    func testProductionBuilderCompletionCorrectionAndRecovery() throws {
        let c = try container(), context = c.mainContext
        let p = try fixture(context), slot = try XCTUnwrap(p.day(order: 0)?.lifts.first)
        let first = try ProgramSession.make(program: p, day: p.orderedDays[0], context: context)
        XCTAssertTrue(try ProgramSession.make(program: p, day: p.orderedDays[0], context: context) === first)
        let entry = try XCTUnwrap(first.orderedExercises.first)
        XCTAssertEqual(entry.exerciseID, slot.exerciseID)
        XCTAssertEqual(entry.plannedWorkingSets.map(\.reps), [3,3,3])
        XCTAssertTrue(entry.plannedWorkingSets.allSatisfy { $0.loadBasis == .perImplement && $0.resolvedImplementCount == 2 })
        try bank(first, program: p, context: context)
        XCTAssertEqual(p.nextDayIndex, 1)
        let history = try context.fetch(FetchDescriptor<WorkoutSession>())
        var next = try XCTUnwrap(TFHProgramService.prescription(p, slotID: slot.id, sessions: history, rotation: 2))
        XCTAssertEqual(next.1.weightLb, 60); XCTAssertEqual(next.1.reps, [4,3,3])
        let last = try XCTUnwrap(entry.plannedWorkingSets.last)
        SessionCorrectionService.apply([(set: last, correction: SetLifecycle.SetCorrection(reps: 2))])
        try context.save()
        next = try XCTUnwrap(TFHProgramService.prescription(p, slotID: slot.id, sessions: history, rotation: 2))
        XCTAssertEqual(next.1.reps, [3,3,3], "corrected canonical evidence replaces the old success without a stall replay")
        SessionCorrectionService.apply([(set: last, correction: SetLifecycle.SetCorrection(reps: 3))])
        while p.currentWeek != 4 {
            let s = try ProgramSession.make(program: p, day: p.nextDay!, context: context)
            try bank(s, program: p, context: context)
        }
        for _ in 0..<2 {
            let s = try ProgramSession.make(program: p, day: p.nextDay!, context: context)
            XCTAssertEqual(s.orderedExercises.first?.plannedWorkingSets.count, 2)
            XCTAssertTrue(s.exercises.flatMap(\.orderedSets).allSatisfy { $0.tfhBenchmarkData == nil })
            try bank(s, program: p, context: context)
        }
        XCTAssertEqual(p.cycleNumber, 2); XCTAssertEqual(p.currentWeek, 1)
        let backup = try ExportService.jsonData(context: context)
        let destination = try container()
        _ = try ImportService.load(backup, into: destination.mainContext)
        let restored = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<Program>()).first)
        XCTAssertEqual(try TFHProgramService.policy(restored), try TFHProgramService.policy(p))
        let restoredHistory = try destination.mainContext.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(restoredHistory.count, 8)
        XCTAssertEqual(try TFHProgramService.position(restored, policy: TFHProgramService.policy(restored)!, sessions: restoredHistory).completedCycles, [1])
    }

    func testMigrationFromShippedV12KeepsHistoryAndAddsOnlyOptionalTFHState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Cadence.store")
        try writeV12Store(url)
        let schema = Schema(versionedSchema: CadenceSchemaV13.self)
        var storedPolicy: TFHProgramPolicy?
        do {
            let c = try ModelContainer(for: schema, migrationPlan: CadenceV12MigrationPlan.self,
                configurations: ModelConfiguration("migration", schema: schema, url: url))
            let ctx = c.mainContext
            let old = try XCTUnwrap(ctx.fetch(FetchDescriptor<WorkoutSession>()).first)
            XCTAssertNil(old.tfhPolicyID); XCTAssertNil(old.tfhContext); XCTAssertNil(old.tfhExcludedFromProgression)
            XCTAssertEqual(old.orderedExercises.first?.workingSets.first?.weightLb, 55)
            XCTAssertEqual(old.orderedExercises.first?.workingSets.first?.plannedWeightLb, 60)
            XCTAssertNil(old.orderedExercises.first?.tfhAnchorData)
            let p = try XCTUnwrap(ctx.fetch(FetchDescriptor<Program>()).first)
            XCTAssertNil(p.tfhPolicyData)
            let exs = try ctx.fetch(FetchDescriptor<Exercise>())
            let draft = try TFHProgramService.draft(p, exercises: exs, sessions: [old])
            try TFHProgramService.activate(draft, program: p, exercises: exs, context: ctx)
            storedPolicy = try TFHProgramService.policy(p)
            let s = try ProgramSession.make(program: p, day: p.nextDay!, context: ctx)
            let set = try XCTUnwrap(s.orderedExercises.first?.plannedWorkingSets.last)
            set.prescriptionBlockRaw = "amrap"
            set.tfhBenchmarkData = try TFHProgramService.encode(TFHBenchmarkResult(stopReason: .technicalLimit, restSeconds: 180))
            try bank(s, program: p, context: ctx)
        }
        let reopened = try ModelContainer(for: schema, migrationPlan: CadenceV12MigrationPlan.self,
            configurations: ModelConfiguration("migration", schema: schema, url: url))
        let p = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Program>()).first)
        XCTAssertEqual(try TFHProgramService.policy(p), storedPolicy)
        let sessions = try reopened.mainContext.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 2)
        let saved = try XCTUnwrap(sessions.first { $0.tfhPolicyID != nil })
        let set = try XCTUnwrap(saved.orderedExercises.first?.plannedWorkingSets.last)
        XCTAssertEqual(try TFHProgramService.decode(TFHBenchmarkResult.self, set.tfhBenchmarkData)?.restSeconds, 180)
    }

    private func writeV12Store(_ url: URL) throws {
        let schema = Schema(versionedSchema: CadenceSchemaV12.self)
        let c = try ModelContainer(for: schema, configurations: ModelConfiguration("migration", schema: schema, url: url))
        let ctx = c.mainContext
        let ex = CadenceSchemaV12.Exercise(name: "TFH V12 Press", categoryRaw: "Main")
        ex.id = UUID().uuidString; ex.loadBasisRaw = "perImplement"; ex.implementCount = 2; ctx.insert(ex)
        let p = CadenceSchemaV12.Program(name: "V12 fixture"); ctx.insert(p)
        for i in 0..<2 {
            let day = CadenceSchemaV12.ProgramDay(name: "Day \(i)", order: i); ctx.insert(day); p.days.append(day)
            let l = CadenceSchemaV12.ProgramLift(exerciseName: ex.name)
            l.exerciseID = ex.id; l.baseWeightLb = 60; ctx.insert(l); day.lifts.append(l)
        }
        let s = CadenceSchemaV12.WorkoutSession(); s.isCompleted = true; s.completedAt = s.date
        ctx.insert(s)
        let e = CadenceSchemaV12.SessionExercise(); e.exerciseID = ex.id; e.exercise = ex
        ctx.insert(e); s.exercises.append(e)
        let set = CadenceSchemaV12.SetEntry(); set.weightLb = 55; set.reps = 5
        set.plannedWeightLb = 60; set.plannedReps = 5; set.statusRaw = "completed"
        ctx.insert(set); e.sets.append(set)
        try ctx.save()
    }
}
