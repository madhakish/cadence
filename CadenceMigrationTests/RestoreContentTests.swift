import Foundation
import SwiftData
import XCTest
import CadenceCore

@MainActor
final class RestoreContentTests: XCTestCase {
    func testWeightOnlyRepairReachesRestoreWithoutChangingIdentity() throws {
        let schema = Schema(versionedSchema: CadenceSchemaV13.self)
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = container.mainContext
        let exercise = Exercise(name: "Synthetic Restore Lift", category: .main, type: .barbell)
        context.insert(exercise)
        let session = WorkoutSession(date: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(session)
        session.isCompleted = true; session.completedAt = session.date
        let entry = SessionExercise(order: 0, exercise: exercise)
        context.insert(entry); session.exercises.append(entry)
        let set = SetEntry(order: 0, weightLb: 100, reps: 5, status: .completed)
        context.insert(set); entry.sets.append(set)
        try context.save()
        let id = session.id
        let original = try ExportService.jsonData(context: context)
        XCTAssertTrue(try ImportService.matchesCurrentData(original, context: context))

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var sessions = try XCTUnwrap(json["sessions"] as? [[String: Any]])
        var entries = try XCTUnwrap(sessions[0]["exercises"] as? [[String: Any]])
        var sets = try XCTUnwrap(entries[0]["sets"] as? [[String: Any]])
        sets[0]["weightLb"] = 95.0
        entries[0]["sets"] = sets; sessions[0]["exercises"] = entries; json["sessions"] = sessions
        let repaired = try JSONSerialization.data(withJSONObject: json)
        let shallow = try XCTUnwrap(ImportService.namedRestorePreview(repaired, context: context))
        XCTAssertTrue(shallow.isNoOp, "The reproduction preserves the shallow preview's names and counts")
        XCTAssertFalse(try ImportService.matchesCurrentData(repaired, context: context))
        XCTAssertEqual(set.weightLb, 100, "Preflight must not mutate stored data")

        try ImportService.load(repaired, into: context)
        let restored = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].id, id)
        XCTAssertEqual(restored[0].orderedExercises[0].orderedSets[0].weightLb, 95)
        XCTAssertTrue(try ImportService.matchesCurrentData(ExportService.jsonData(context: context), context: context))

        json["schemaVersion"] = BackupContract.currentSchemaVersion + 1
        XCTAssertThrowsError(try ImportService.matchesCurrentData(JSONSerialization.data(withJSONObject: json), context: context))
    }
}
