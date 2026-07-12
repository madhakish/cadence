import XCTest
@testable import CadenceCore

/// Parity + sanity for the anatomy data. The Swift copy must equal
/// web/tests/fixtures/anatomy.json (the same fixture the node smoke suite
/// holds web/js/anatomy.js to), so either mirror drifting fails its own CI
/// job. Regenerate with web/tools/generate-anatomy-fixture.mjs.
final class AnatomyDataTests: XCTestCase {

    private struct Fixture: Codable {
        let names: [String: String]
        let body: [[[Double]]]
        let regions: [AnatomyData.Region]
        let map: [String: AnatomyData.Profile]
        let groupDefaults: [String: AnatomyData.Profile]
    }

    private func fixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // → CadenceCoreTests/
            .deletingLastPathComponent()   // → Tests/
            .deletingLastPathComponent()   // → CadenceCore/
            .deletingLastPathComponent()   // → repo root
            .appendingPathComponent("web/tests/fixtures/anatomy.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func testAnatomyMatchesSharedFixture() throws {
        let fx = try fixture()
        XCTAssertEqual(AnatomyData.muscleNames, fx.names)
        XCTAssertEqual(AnatomyData.body, fx.body)
        XCTAssertEqual(AnatomyData.regions, fx.regions)
        XCTAssertEqual(AnatomyData.map, fx.map)
        XCTAssertEqual(AnatomyData.groupDefaults, fx.groupDefaults)
    }

    func testEveryProfileReferencesRealRegions() {
        let regionIds = Set(AnatomyData.regions.map(\.id))
        XCTAssertEqual(regionIds, Set(AnatomyData.muscleNames.keys), "every region has a display name and vice versa")
        for (exercise, p) in AnatomyData.map {
            for id in p.primary + p.secondary {
                XCTAssertTrue(regionIds.contains(id), "\(exercise) references unknown region \(id)")
            }
            XCTAssertFalse(p.primary.isEmpty, "\(exercise) has at least one primary mover")
            XCTAssertTrue(Set(p.primary).isDisjoint(with: Set(p.secondary)), "\(exercise): a muscle is primary or supporting, not both")
        }
        for (group, p) in AnatomyData.groupDefaults {
            for id in p.primary + p.secondary {
                XCTAssertTrue(regionIds.contains(id), "group \(group) references unknown region \(id)")
            }
        }
    }

    func testLookupFallsBackByGroup() {
        XCTAssertEqual(AnatomyData.muscleProfile(name: "Back Squat", movementGroup: "squat")?.primary.first, "quads")
        XCTAssertEqual(AnatomyData.muscleProfile(name: "Custom Novelty Press", movementGroup: "press")?.primary,
                       ["delts", "chest", "triceps"], "unknown exercise falls back to its movement group")
        XCTAssertNil(AnatomyData.muscleProfile(name: "Mystery", movementGroup: ""), "no name, no group → no figure")
        XCTAssertEqual(AnatomyData.blurb(AnatomyData.Profile(primary: ["delts"], secondary: ["traps"])),
                       "Primary: Shoulders · Supporting: Traps")
    }
}
