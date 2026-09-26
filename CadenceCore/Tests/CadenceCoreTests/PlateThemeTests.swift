import XCTest
@testable import CadenceCore

/// Holds the Swift plate theme model to web/tests/fixtures/plate-themes.json,
/// the snapshot generated from web/app/js/plate-theme.js
/// (web/tools/generate-plate-themes-fixture.mjs). Either mirror drifting fails.
final class PlateThemeTests: XCTestCase {
    struct Row: Decodable {
        let plate: String, style: String, diameter: Double, thickness: Double, family: String
        let fill: String, edge: String, ink: String, band: String?
        let finish: String, metal: Double, roughness: Double, photoFamily: String?
        let hub: Double, photoHub: Double, rim: Double
    }
    struct Sets: Decodable { let kg: [String]; let lb: [String] }
    struct Theme: Decodable {
        let id: String, label: String, primaryUnit: String, sets: Sets
        let brand: String, barFinish: String, backdrop: String, hubFinish: String, details: [String]
        let rows: [Row]
    }
    struct LayoutDisc: Decodable {
        let plate: String, side: Int, index: Int, family: String
        let centerX: Double, radius: Double, thickness: Double, theme: String
    }
    struct Layout: Decodable { let theme: String; let style: String; let discs: [LayoutDisc] }
    struct Tint: Decodable { let fill: String; let style: String; let target: Double; let matrix: [Double] }
    struct Fixture: Decodable {
        let themes: [Theme]; let layouts: [Layout]; let tints: [Tint]; let familyLabels: [String: String]
    }

    private func fixture() throws -> Fixture {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("web/tests/fixtures/plate-themes.json"))
        return try JSONDecoder().decode(Fixture.self, from: data)
    }

    private func plate(_ id: String) -> Plate {
        let parts = id.split(separator: "-")
        return Plate(value: Double(parts[0])!, unit: WeightUnit(rawValue: String(parts[1]))!)
    }

    func testEveryThemeMatchesWebFixture() throws {
        let themes = try fixture().themes
        XCTAssertEqual(themes.map(\.id), PlateThemeID.allCases.map(\.rawValue))
        for expected in themes {
            let id = try XCTUnwrap(PlateThemeID(rawValue: expected.id))
            let theme = PlateTheme.description(id)
            XCTAssertEqual(id.label, expected.label)
            XCTAssertEqual(id.primaryUnit.rawValue, expected.primaryUnit)
            XCTAssertEqual(PlateTheme.set(for: .kg, theme: id).map(\.id), expected.sets.kg, expected.id)
            XCTAssertEqual(PlateTheme.set(for: .lb, theme: id).map(\.id), expected.sets.lb, expected.id)
            XCTAssertEqual(theme.brand, expected.brand)
            XCTAssertEqual(theme.barFinish.rawValue, expected.barFinish)
            XCTAssertEqual(PlatePalette.hex(theme.backdrop), expected.backdrop)
            XCTAssertEqual(theme.hubFinish.rawValue, expected.hubFinish)
            XCTAssertEqual(theme.details, expected.details)
            XCTAssertFalse(expected.rows.isEmpty)
            for row in expected.rows {
                let p = plate(row.plate)
                let style: PlateVisualStyle = row.style == "bumper" ? .bumper : .steel
                let context = "\(expected.id) \(row.plate) \(row.style)"
                let geometry = PlateTheme.geometry(p, theme: id, style: style)
                XCTAssertEqual(geometry.diameter, row.diameter, context)
                XCTAssertEqual(geometry.thickness, row.thickness, context)
                XCTAssertEqual(PlateTheme.family(p, theme: id, style: style), row.family, context)
                let colour = PlateTheme.colour(p, theme: id, style: style)
                XCTAssertEqual(PlatePalette.hex(colour.fill), row.fill, context)
                XCTAssertEqual(PlatePalette.hex(colour.edge), row.edge, context)
                XCTAssertEqual(PlatePalette.hex(colour.ink), row.ink, context)
                XCTAssertEqual(PlateTheme.band(p, theme: id).map(PlatePalette.hex), row.band, context)
                let material = PlateTheme.material(p, theme: id, style: style)
                XCTAssertEqual(material.finish.rawValue, row.finish, context)
                XCTAssertEqual(material.metal, row.metal, context)
                XCTAssertEqual(material.roughness, row.roughness, context)
                XCTAssertEqual(material.photoFamily?.rawValue.lowercased(), row.photoFamily, context)
                let ratios = PlateTheme.ratios(p, theme: id, style: style)
                XCTAssertEqual(ratios.hub, row.hub, context)
                XCTAssertEqual(ratios.photoHub, row.photoHub, context)
                XCTAssertEqual(ratios.rim, row.rim, context)
                if id != .custom {
                    // Named themes ignore the legacy style.
                    XCTAssertEqual(PlateTheme.geometry(p, theme: id, style: .bumper), geometry, context)
                    XCTAssertEqual(PlateTheme.colour(p, theme: id, style: .steel), colour, context)
                }
            }
        }
    }

    /// custom and the default parameter reproduce today's style-driven look.
    func testCustomIsLegacy() throws {
        let ids = Set(try fixture().themes.flatMap { $0.sets.kg + $0.sets.lb })
        for id in ids {
            let p = plate(id)
            for style in [PlateVisualStyle.bumper, .steel] {
                XCTAssertEqual(PlateTheme.geometry(p, theme: .custom, style: style), PlateGeometry.reference(p, style: style))
                XCTAssertEqual(PlateTheme.family(p, theme: .custom, style: style), PlateGeometry.family(p, style: style))
                XCTAssertEqual(PlateTheme.colour(p, theme: .custom, style: style),
                               PlatePalette.colour(for: p.colorToken(for: style)))
            }
            XCTAssertEqual(PlateTheme.geometry(p), PlateGeometry.reference(p, style: .steel))
            XCTAssertEqual(PlateTheme.colour(p), PlatePalette.colour(for: p.colorToken))
        }
        XCTAssertEqual(PlateTheme.set(for: .kg), Plate.standardKg)
        XCTAssertEqual(PlateTheme.set(for: .lb), Plate.standardLb)
    }

    func testFederationColourRules() {
        let kg = { (v: Double) in Plate(value: v, unit: .kg) }
        XCTAssertEqual(PlateTheme.colour(kg(25), theme: .iwfCompetition).fill, 0xC6302C)
        XCTAssertEqual(PlateTheme.colour(kg(2), theme: .iwfCompetition).fill, 0x234FAE, "IWF change plates follow")
        XCTAssertEqual(PlateTheme.colour(kg(2.5), theme: .ipfCalibrated).fill, 0x1E1F22, "IPF 2.5 kg is black")
        XCTAssertEqual(PlateTheme.material(kg(1.25), theme: .ipfCalibrated).finish, .machined, "IPF 1.25 kg is chrome")
        let lb = PlateTheme.set(for: .lb, theme: .lbBlackIron)
        let colours = lb.map { PlateTheme.colour($0, theme: .lbBlackIron) }
        XCTAssertTrue(colours.allSatisfy { $0 == colours[0] }, "iron is monochrome")
    }

    /// The shared layouts take the theme: the inspector layout matches the
    /// web snapshot per theme, and the default is today's layout.
    func testLayoutsFollowTheme() throws {
        let loadout = Loadout(bar: .bar20kg, perSide: [25, 20, 10, 5, 2.5, 1.25]
            .map { PlateCount(plate: Plate(value: $0, unit: .kg), count: 1) }, preservesOrder: true)
        for expected in try fixture().layouts {
            let id = try XCTUnwrap(PlateThemeID(rawValue: expected.theme))
            let discs = BarbellInspector.layout(loadout: loadout, style: .steel, explode: 0, theme: id).discs
            XCTAssertEqual(discs.map(\.plate.id), expected.discs.map(\.plate))
            for (disc, row) in zip(discs, expected.discs) {
                let context = "\(expected.theme) \(row.plate) \(row.side)"
                XCTAssertEqual(disc.side, row.side, context)
                XCTAssertEqual(disc.index, row.index, context)
                XCTAssertEqual(disc.family, row.family, context)
                XCTAssertEqual(disc.centerX, row.centerX, accuracy: 1e-9, context)
                XCTAssertEqual(disc.radius, row.radius, context)
                XCTAssertEqual(disc.thickness, row.thickness, context)
                XCTAssertEqual(disc.theme.rawValue, row.theme, context)
            }
        }
        XCTAssertEqual(BarbellInspector.layout(loadout: loadout, style: .bumper, explode: 0.5, theme: .custom),
                       BarbellInspector.layout(loadout: loadout, style: .bumper, explode: 0.5))
        let scene = BarbellScene(loadout: loadout, style: .steel, exploded: false, theme: .ipfCalibrated)
        XCTAssertTrue(scene.discs.allSatisfy { $0.theme == .ipfCalibrated })
        XCTAssertEqual(scene.discs.first { $0.plate.value == 5 }?.radius, 228 * 0.18)
        let legacy = BarbellScene(loadout: loadout, style: .bumper, exploded: true)
        let custom = BarbellScene(loadout: loadout, style: .bumper, exploded: true, theme: .custom)
        XCTAssertEqual(legacy.width, custom.width)
        XCTAssertEqual(legacy.discs.map(\.radius), custom.discs.map(\.radius))
    }

    func testFillTintAndFamilyLabelsMatchWeb() throws {
        let fixture = try fixture()
        XCTAssertEqual(fixture.tints.count, 4)
        for tint in fixture.tints {
            let fill = try XCTUnwrap(UInt32(tint.fill.dropFirst(), radix: 16))
            let style: PlateVisualStyle = tint.style == "bumper" ? .bumper : .steel
            XCTAssertEqual(PlateFaceTint.target(forFill: fill), tint.target, tint.fill)
            let matrix = PlateFaceTint(fill: fill, style: style).matrix
            XCTAssertEqual(matrix.count, 20)
            for (value, mirror) in zip(matrix, tint.matrix) { XCTAssertEqual(value, mirror, accuracy: 1e-12, tint.fill) }
        }
        for (family, label) in fixture.familyLabels {
            XCTAssertEqual(PlateGeometry.familyLabel(family), label, family)
        }
        // Token tints are the fill tints at the pigment's own target.
        for (token, colour) in PlatePalette.colours {
            for style in [PlateVisualStyle.bumper, .steel] {
                XCTAssertEqual(PlateFaceTint(token: token, style: style).matrix,
                               PlateFaceTint(fill: colour.fill, style: style, target: PlateFaceTint.target(for: token)).matrix)
            }
        }
    }
}
