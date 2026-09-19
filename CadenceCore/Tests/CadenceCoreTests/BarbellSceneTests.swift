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

    /// DP-3's renderer fixtures F1–F8, mirrored from web/tests/plate-renderer.test.mjs:
    /// the scene carries every entered plate mirrored once, names each with
    /// its exact denomination, keeps entered order, and keeps steel and
    /// bumper geometry distinct.
    func testRendererFixturesMirrorWeb() {
        func solve(_ lb: Double, _ bar: Bar, _ plates: [Plate], collar: Double = 0,
                   policy: LoadingPolicy = .closest) -> PlateSolution {
            PlateMath.solveLoad(weightLb: lb, bar: bar, plates: plates, collarLb: collar, policy: policy)
        }
        let entered = Loadout(bar: .bar45lb, perSide: [45, 10, 25, 2.5].map {
            PlateCount(plate: Plate(value: $0, unit: .lb), count: 1)
        }, preservesOrder: true)
        let fixtures: [(String, Loadout, PlateVisualStyle)] = [
            ("F1", solve(Weight.lb(fromKg: 100), .bar20kg, Plate.standardKg).loadout, .steel),
            ("F2", solve(225, .bar45lb, Plate.standardLb).loadout, .steel),
            ("F3", solve(139, .bar45lb, Plate.standardKg).loadout, .steel),
            ("F4", solve(Weight.lb(fromKg: 22.5), .bar20kg, Plate.standardKg).loadout, .steel),
            ("F5", entered, .steel),
            ("F6", solve(200, .bar45lb, [Plate(value: 45, unit: .lb)], policy: .exact).loadout, .steel),
            ("F7", solve(195, .bar45lb, Plate.standardLb).loadout, .bumper),
            ("F8", solve(50, .bar45lb, Plate.standardLb, collar: 5).loadout, .steel),
        ]
        for (name, loadout, style) in fixtures {
            let scene = BarbellScene(loadout: loadout, style: style, exploded: false)
            let entered = loadout.perSide.reduce(0) { $0 + max(0, $1.count) }
            XCTAssertEqual(scene.discs.count, entered * 2, "\(name): every entered plate is mirrored exactly once")
            for disc in scene.discs {
                XCTAssertFalse(disc.plate.label.isEmpty, "\(name): every plate carries its denomination")
                XCTAssertTrue(disc.accessibilityLabel.contains(disc.plate.label),
                              "\(name): the spoken name carries the exact denomination")
            }
        }
        let f4 = fixtures[3].1.perSide.flatMap { Array(repeating: $0.plate, count: $0.count) }
        XCTAssertTrue(f4.contains { $0.label == "1.25 kg" }, "F4: a 1.25 kg plate remains 1.25 kg")
        let f5 = BarbellScene(loadout: entered, style: .steel, exploded: false)
        XCTAssertEqual(f5.discs.filter { $0.side == 1 }.sorted { $0.index < $1.index }.map { $0.plate.value },
                       [45, 10, 25, 2.5], "F5: reverse mode preserves entered collar-to-sleeve order")
        let f7 = fixtures[6].1
        // Mirrors the web check: the first two plates (45 + 25) differ in
        // calibrated steel and share one competition diameter as bumpers; the
        // 5 lb change plate is legitimately smaller in both families.
        let steelRadii = BarbellScene(loadout: f7, style: .steel, exploded: false).discs
            .filter { $0.side == 1 }.sorted { $0.index < $1.index }.map(\.radius)
        let bumperRadii = BarbellScene(loadout: f7, style: .bumper, exploded: false).discs
            .filter { $0.side == 1 }.sorted { $0.index < $1.index }.map(\.radius)
        XCTAssertNotEqual(steelRadii[0], steelRadii[1], "F7: calibrated steel steps down with denomination")
        XCTAssertEqual(bumperRadii[0], bumperRadii[1], "F7: bumpers keep one competition diameter")
        XCTAssertGreaterThan(fixtures[7].1.collarLb, 0, "F8: configured collars are part of the loadout")
        XCTAssertEqual(BarbellScene.Disc(plate: Plate(value: 20, unit: .kg), side: -1, index: 0,
                                         x: 0, y: 0, radius: 1, faceRadius: 1, depth: 1).accessibilityLabel,
                       "20 kg plate, 1 from inside, left side", "one spoken name on both clients")
    }

    func testPlatePaletteIsTheOneColourTable() {
        XCTAssertEqual(PlatePalette.colour(for: "yellow").ink, 0x24262A)
        XCTAssertEqual(PlatePalette.colour(for: "red").ink, 0xFFFFFF)
        XCTAssertEqual(PlatePalette.hex(PlatePalette.colour(for: "blue").fill), "#2f6fed")
        XCTAssertEqual(PlatePalette.colour(for: "chartreuse"), PlatePalette.fallback)
        XCTAssertEqual(PlateFaceTint(token: "black").red, 1, "black iron is the untinted texture")
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
