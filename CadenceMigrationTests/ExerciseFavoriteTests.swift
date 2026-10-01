import Foundation
import SwiftData
import XCTest
import CadenceCore

@MainActor
final class ExerciseFavoriteTests: XCTestCase {
    func testV14DiskStoreDefaultsFavoritesAndPreservesIdentityGateAndTheme() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Cadence.store")
        let id = "a0000000-0000-4000-8000-000000000063"
        do {
            let schema = Schema(versionedSchema: CadenceSchemaV14.self)
            let old = try ModelContainer(for: schema,
                configurations: ModelConfiguration("favorites", schema: schema, url: url))
            let lift = CadenceSchemaV14.Exercise(name: "Favorite Migration Lift")
            lift.id = id; lift.isShelved = true; lift.gateStatusRaw = "shelved"
            lift.notes = "Synthetic user-owned note"; lift.defaultRestSeconds = 123
            let gym = CadenceSchemaV14.Gym(name: "Synthetic Rack")
            gym.plateThemeRaw = "ipfCalibrated"; gym.collarWeightLb = 5
            old.mainContext.insert(lift); old.mainContext.insert(gym)
            try old.mainContext.save()
        }
        let schema = Schema(versionedSchema: CadenceSchemaV15.self)
        do {
            let upgraded = try ModelContainer(for: schema, migrationPlan: CadenceV14MigrationPlan.self,
                configurations: ModelConfiguration("favorites", schema: schema, url: url))
            let lift = try XCTUnwrap(try upgraded.mainContext.fetch(FetchDescriptor<Exercise>()).first)
            XCTAssertFalse(lift.isFavorite)
            XCTAssertEqual(lift.id, id); XCTAssertEqual(lift.gateStatus, .shelved)
            XCTAssertEqual(lift.notes, "Synthetic user-owned note"); XCTAssertEqual(lift.defaultRestSeconds, 123)
            let gym = try XCTUnwrap(try upgraded.mainContext.fetch(FetchDescriptor<Gym>()).first)
            XCTAssertEqual(gym.plateThemeRaw, "ipfCalibrated"); XCTAssertEqual(gym.collarWeightLb, 5)
            lift.isFavorite = true; lift.name = "Renamed Favorite Migration Lift"
            try upgraded.mainContext.save()
            try Seeder.syncLibrary(context: upgraded.mainContext)
            XCTAssertTrue(lift.isFavorite, "Seed top-up must preserve this user-owned preference")
            XCTAssertFalse(lift.isAvailableForProgramming, "Starring cannot reopen a shelved lift")
        }
        let reopened = try ModelContainer(for: schema, migrationPlan: CadenceV14MigrationPlan.self,
            configurations: ModelConfiguration("favorites", schema: schema, url: url))
        let lift = try XCTUnwrap(try reopened.mainContext.fetch(FetchDescriptor<Exercise>()).first { $0.id == id })
        XCTAssertTrue(lift.isFavorite); XCTAssertEqual(lift.name, "Renamed Favorite Migration Lift")
    }

    func testFavoritesRoundTripPreviewAndLegacyRestore() throws {
        let schema = Schema(versionedSchema: CadenceSchemaV15.self)
        let source = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let lift = Exercise(name: "Synthetic Favorite", category: .main, type: .barbell,
            movementPattern: .squat, loadBasis: .totalBar, implementCount: 1)
        lift.id = "a0000000-0000-4000-8000-000000000063"; lift.isFavorite = true
        source.mainContext.insert(lift); try source.mainContext.save()
        let data = try ExportService.jsonData(context: source.mainContext)
        let restored = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        _ = try ImportService.load(data, into: restored.mainContext)
        let copy = try XCTUnwrap(try restored.mainContext.fetch(FetchDescriptor<Exercise>()).first)
        XCTAssertTrue(copy.isFavorite); XCTAssertEqual(copy.id, lift.id)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var definitions = try XCTUnwrap(json["exercises"] as? [[String: Any]])
        definitions[0]["isFavorite"] = false; json["exercises"] = definitions
        let changed = try JSONSerialization.data(withJSONObject: json)
        let preview = try XCTUnwrap(ImportService.namedRestorePreview(changed, context: restored.mainContext))
        XCTAssertFalse(preview.isNoOp, "A favorite-only restore must show a changed exercise")
        XCTAssertFalse(try ImportService.matchesCurrentData(changed, context: restored.mainContext))
        _ = try ImportService.load(changed, into: restored.mainContext)
        XCTAssertFalse(copy.isFavorite)

        copy.isFavorite = true; try restored.mainContext.save()
        definitions[0].removeValue(forKey: "isFavorite"); json["exercises"] = definitions
        XCTAssertThrowsError(try ImportService.load(JSONSerialization.data(withJSONObject: json), into: restored.mainContext))
        XCTAssertTrue(copy.isFavorite, "Malformed current backups cannot mutate the library")
        json["schemaVersion"] = 15
        _ = try ImportService.load(JSONSerialization.data(withJSONObject: json), into: restored.mainContext)
        XCTAssertFalse(copy.isFavorite, "Pre-favorites backups restore an unstarred library")
    }

    func testFavoriteSaveFailureRollsBackAndReportsIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Cadence.store")
        let schema = Schema(versionedSchema: CadenceSchemaV15.self)
        do {
            let writable = try ModelContainer(for: schema,
                configurations: ModelConfiguration("favorites", schema: schema, url: url))
            writable.mainContext.insert(Exercise(name: "Read-only Lift", category: .accessory, type: .dumbbell))
            try writable.mainContext.save()
        }
        let readOnly = try ModelContainer(for: schema,
            configurations: ModelConfiguration("favorites", schema: schema, url: url, allowsSave: false))
        let lift = try XCTUnwrap(try readOnly.mainContext.fetch(FetchDescriptor<Exercise>()).first)
        XCTAssertFalse(PersistenceErrorCenter.shared.toggleFavorite(lift, context: readOnly.mainContext))
        XCTAssertFalse(lift.isFavorite)
        XCTAssertTrue(PersistenceErrorCenter.shared.message?.contains("Saving the exercise favorite failed") == true)
        PersistenceErrorCenter.shared.message = nil
    }
}
