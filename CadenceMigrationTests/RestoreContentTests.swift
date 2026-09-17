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
        // Explicit current-format values avoid legacy inference sentinels
        // producing unrelated exercise-definition changes in the preview.
        let exercise = Exercise(name: "Synthetic Restore Lift", category: .main, type: .barbell,
            movementPattern: .squat, loadBasis: .totalBar, implementCount: 1)
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

        _ = try ImportService.load(repaired, into: context)
        let restored = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].id, id)
        XCTAssertEqual(restored[0].orderedExercises[0].orderedSets[0].weightLb, 95)
        XCTAssertTrue(try ImportService.matchesCurrentData(ExportService.jsonData(context: context), context: context))

        json["schemaVersion"] = BackupContract.currentSchemaVersion + 1
        XCTAssertThrowsError(try ImportService.matchesCurrentData(JSONSerialization.data(withJSONObject: json), context: context))
        let metadataOnly = Data(#"{"schemaVersion":14,"appVersion":"test"}"#.utf8)
        XCTAssertThrowsError(try ImportService.matchesCurrentData(metadataOnly, context: context))
        XCTAssertThrowsError(try ImportService.load(metadataOnly, into: context))

        let intervalOnly = Data(#"{"schemaVersion":14,"intervals":[{"id":"a0000000-0000-4000-8000-000000000002","kind":"rest","startDate":"2025-01-02","endDate":"2025-01-03","enteredAsDays":true,"note":"Synthetic break"}]}"#.utf8)
        XCTAssertFalse(try ImportService.matchesCurrentData(intervalOnly, context: context))
        _ = try ImportService.load(intervalOnly, into: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
        let after = try XCTUnwrap(JSONSerialization.jsonObject(with: ExportService.jsonData(context: context)) as? [String: Any])
        XCTAssertEqual((after["intervals"] as? [[String: Any]])?.count, 1)
        XCTAssertTrue(try ImportService.matchesCurrentData(Data(#"{"schemaVersion":14,"coachingDecisions":[]}"#.utf8), context: context))
    }
}
