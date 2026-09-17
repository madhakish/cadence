import XCTest
@testable import CadenceCore

final class BarbellSceneTests: XCTestCase {
    func testPhotographicTintMatchesWeb() throws {
        struct Tint: Decodable { let token: String; let gains: [Double] }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("web/tests/fixtures/plate-tints.json"))
        for expected in try JSONDecoder().decode([Tint].self, from: data) {
            let actual = PlateFaceTint(token: expected.token)
            for (value, gain) in zip([actual.red, actual.green, actual.blue], expected.gains) {
                XCTAssertEqual(value, gain, accuracy: 1e-8)
            }
        }
    }
    func testInspectionPreservesDimensionsOrderAndMirrors() {
        let loadout = Loadout(bar: .bar45lb, perSide: [45, 10, 25, 2.5].map {
            PlateCount(plate: Plate(value: $0, unit: .lb), count: 1)
        }, collarLb: 5, preservesOrder: true)
        let assembled = BarbellScene(loadout: loadout, style: .bumper, exploded: false)
        let exploded = BarbellScene(loadout: loadout, style: .bumper, exploded: true)
        XCTAssertEqual(exploded.discs.filter { $0.side == 1 }.map { $0.plate.value }, [45, 10, 25, 2.5])
        XCTAssertEqual(exploded.discs.map(\.radius), assembled.discs.map(\.radius))
        XCTAssertGreaterThan(exploded.width, assembled.width)
        for (left, right) in zip(exploded.discs, exploded.discs.dropFirst()) {
            XCTAssertGreaterThanOrEqual(right.x - right.faceRadius - right.depth / 2
                - (left.x + left.faceRadius + left.depth / 2), 22 - 1e-8)
        }
        for disc in exploded.discs {
            let mirror = exploded.discs.first { $0.side == -disc.side && $0.index == disc.index }!
            XCTAssertEqual(mirror.x, -disc.x)
            XCTAssertEqual(mirror.radius, disc.radius)
            XCTAssertLessThan(abs(disc.x) + disc.faceRadius + disc.depth, exploded.width / 2)
        }
    }

    func testPlateFamilyNamesTheSummaryCell() {
        XCTAssertEqual(PlateGeometry.family(Plate(value: 5, unit: .kg), style: .bumper), "bumper",
                       "a full-size 5 kg training bumper is a bumper")
        XCTAssertEqual(PlateGeometry.family(Plate(value: 5, unit: .kg), style: .steel), "steel")
        XCTAssertEqual(PlateGeometry.family(Plate(value: 2.5, unit: .kg), style: .bumper), "change")
        XCTAssertEqual(PlateGeometry.family(Plate(value: 45, unit: .lb), style: .steel), "steel")
        XCTAssertEqual(PlateGeometry.family(Plate(value: 5, unit: .lb), style: .bumper), "change")
        XCTAssertEqual(PlateGeometry.familyLabel("bumper"), "Bumpers")
        XCTAssertEqual(PlateGeometry.familyLabel("change"), "Change")
    }

    func testFiveKilogramBumperDoesNotBecomeAChangePlate() {
        let plate = Plate(value: 5, unit: .kg)
        XCTAssertEqual(PlateGeometry.reference(plate, style: .bumper).diameter, 450)
        XCTAssertEqual(PlateGeometry.reference(plate, style: .steel).diameter, 230)
        let loadout = Loadout(bar: .bar20kg, perSide: [PlateCount(plate: plate, count: 1)])
        for exploded in [false, true] {
            let scene = BarbellScene(loadout: loadout, style: .bumper, exploded: exploded,
                geometry: [plate.id: PlateGeometry(diameter: 230, thickness: 20)])
            XCTAssertEqual(scene.discs[0].radius, 230 * 0.18)
        }
    }

    func testSceneMatchesWebFixture() throws {
        struct Fixture: Decodable {
            struct Expected: Decodable {
                struct Disc: Decodable { let x, y, radius, faceRadius, depth: Double; let side, index: Int }
                let width, height, shoulder, end, collar, axisX, axisY, faceScale: Double
                let discs: [Disc]
            }
            let loadout: Loadout
            let style: String
            let exploded: Bool
            let scene: Expected
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("web/tests/fixtures/barbell-scene.json"))
        for fixture in try JSONDecoder().decode([Fixture].self, from: data) {
            let scene = BarbellScene(loadout: fixture.loadout,
                style: fixture.style == "bumper" ? .bumper : .steel, exploded: fixture.exploded)
            XCTAssertEqual(scene.width, fixture.scene.width, accuracy: 1e-8)
            XCTAssertEqual(scene.height, fixture.scene.height, accuracy: 1e-8)
            XCTAssertEqual(scene.discs.count, fixture.scene.discs.count)
            for (disc, expected) in zip(scene.discs, fixture.scene.discs) {
                XCTAssertEqual(disc.x, expected.x, accuracy: 1e-8)
                XCTAssertEqual(disc.y, expected.y, accuracy: 1e-8)
                XCTAssertEqual(disc.radius, expected.radius, accuracy: 1e-8)
                XCTAssertEqual(disc.faceRadius, expected.faceRadius, accuracy: 1e-8)
                XCTAssertEqual(disc.depth, expected.depth, accuracy: 1e-8)
                XCTAssertEqual(disc.side, expected.side)
                XCTAssertEqual(disc.index, expected.index)
            }
        }
    }
}
