import XCTest
@testable import CadenceCore

/// Mirrors web/tests/barbell-inspector.test.mjs: the 3D inspector's physical
/// layout, explode fraction, authored cameras, and lathe profiles agree with web.
final class BarbellInspectorTests: XCTestCase {
    private let bar45 = Bar(value: 45, unit: .lb)
    private var counts: [PlateCount] {
        [PlateCount(plate: Plate(value: 45, unit: .lb), count: 2), PlateCount(plate: Plate(value: 10, unit: .lb), count: 1)]
    }
    private func loadout(_ bar: Bar, _ perSide: [PlateCount]) -> Loadout { Loadout(bar: bar, perSide: perSide, collarLb: 5) }

    func testAssembledLayoutIsPhysicalAndMirrored() {
        let layout = BarbellInspector.layout(loadout: loadout(bar45, counts), style: .steel, explode: 0)
        XCTAssertEqual(layout.discs.count, 6)
        XCTAssertEqual(layout.bar.shaftHalfLength, 685)
        XCTAssertEqual(layout.bar.sleeveLength, 415)
        XCTAssertEqual(layout.bar.shaftRadius, 14)
        XCTAssertEqual(layout.bar.sleeveRadius, 25)
        let right = layout.discs.filter { $0.side > 0 }.sorted { $0.index < $1.index }
        XCTAssertEqual(right[0].centerX, layout.bar.shoulderEnd + right[0].thickness / 2, accuracy: 1e-9)
        XCTAssertEqual(right[1].centerX, right[0].centerX + right[0].thickness / 2 + right[1].thickness / 2, accuracy: 1e-9)
        for disc in layout.discs {
            let mirror = layout.discs.first { $0.index == disc.index && $0.side == -disc.side }!
            XCTAssertEqual(mirror.centerX, -disc.centerX, accuracy: 1e-9)
            XCTAssertEqual(mirror.radius, disc.radius)
            XCTAssertEqual(disc.family, "steel")
        }
        XCTAssertEqual(layout.collar.right, right[2].centerX + right[2].thickness / 2, accuracy: 1e-9)
        XCTAssertEqual(layout.collar.length, 50)
        XCTAssertEqual(layout.extent, 685 + 415)
        XCTAssertEqual(BarbellInspector.layout(loadout: loadout(Bar(value: 15, unit: .kg), []), style: .bumper, explode: 0).bar.sleeveLength, 320)
        XCTAssertEqual(BarbellInspector.layout(loadout: loadout(Bar(value: 35, unit: .lb), []), style: .bumper, explode: 0).bar.shaftRadius, 12.5)
    }

    func testExplodeFractionSpreadsPlatesAndCollar() {
        let closed = BarbellInspector.layout(loadout: loadout(bar45, counts), style: .steel, explode: 0)
        let open = BarbellInspector.layout(loadout: loadout(bar45, counts), style: .steel, explode: 1)
        let half = BarbellInspector.layout(loadout: loadout(bar45, counts), style: .steel, explode: 0.5)
        let gap = 2 * closed.maxRadius * 1.3 + 24
        func right(_ layout: BarbellInspector.Layout, _ index: Int) -> BarbellInspector.Disc {
            layout.discs.first { $0.side > 0 && $0.index == index }!
        }
        XCTAssertEqual(right(open, 0).centerX, right(closed, 0).centerX, accuracy: 1e-9)
        XCTAssertEqual(right(open, 2).centerX, right(closed, 2).centerX + 2 * gap, accuracy: 1e-9)
        XCTAssertEqual(right(half, 2).centerX, right(closed, 2).centerX + gap, accuracy: 1e-9)
        XCTAssertEqual(open.collar.right, right(open, 2).centerX + right(open, 2).thickness / 2 + 80, accuracy: 1e-9)
        XCTAssertEqual(half.collar.right, right(half, 2).centerX + right(half, 2).thickness / 2 + 40, accuracy: 1e-9)
        XCTAssertGreaterThan(open.collar.right, closed.collar.right)
        XCTAssertGreaterThanOrEqual(open.extent, closed.extent)
    }

    func testAuthoredCameraEndpoints() {
        XCTAssertEqual(BarbellInspector.Camera.initial(exploded: true), BarbellInspector.Camera(yaw: 50, pitch: 10, zoom: 1))
        XCTAssertEqual(BarbellInspector.Camera.initial(exploded: false), BarbellInspector.Camera(yaw: 8, pitch: 6, zoom: 1))
        let eye = BarbellInspector.Camera.initial(exploded: false).position(distance: 1000)
        XCTAssertEqual((eye.x * eye.x + eye.y * eye.y + eye.z * eye.z).squareRoot(), 1000, accuracy: 1e-9)
        XCTAssertTrue(eye.x < 0 && eye.z > 0 && eye.y > 0)
        XCTAssertEqual(BarbellInspector.Camera(yaw: 90, pitch: 0, zoom: 1).position(distance: 10).x, -10, accuracy: 1e-9)
        XCTAssertEqual(BarbellInspector.Camera(yaw: 0, pitch: 0, zoom: 1).position(distance: 10).z, 10, accuracy: 1e-9)
    }

    func testBothFramesFocusOnTheNearSleeve() {
        let closed = BarbellInspector.layout(loadout: loadout(bar45, counts), style: .steel, explode: 0)
        let open = BarbellInspector.layout(loadout: loadout(bar45, counts), style: .steel, explode: 1)
        let closedFrame = BarbellInspector.frame(layout: closed, explode: 0)
        let openFrame = BarbellInspector.frame(layout: open, explode: 1)
        let midFrame = BarbellInspector.frame(layout: BarbellInspector.layout(loadout: loadout(bar45, counts), style: .steel, explode: 0.5), explode: 0.5)
        XCTAssertLessThan(closedFrame.target.x, -closed.bar.shaftHalfLength)
        XCTAssertLessThan(closedFrame.halfWidth, closed.extent * 0.6)
        XCTAssertGreaterThan(closedFrame.target.x + closedFrame.halfWidth, -closed.bar.shaftHalfLength + 200, "assembled includes visible shaft")
        XCTAssertTrue(openFrame.target.x < -closed.bar.shaftHalfLength && openFrame.target.x > -open.extent)
        XCTAssertLessThan(openFrame.target.x - openFrame.halfWidth, open.collar.left - open.collar.length)
        XCTAssertTrue(midFrame.target.x < closedFrame.target.x && midFrame.target.x > openFrame.target.x)
        let empty = BarbellInspector.layout(loadout: loadout(Bar(value: 15, unit: .kg), []), style: .bumper, explode: 0)
        let emptyFrame = BarbellInspector.frame(layout: empty, explode: 0)
        XCTAssertLessThanOrEqual(emptyFrame.target.x - emptyFrame.halfWidth, -empty.bar.shaftHalfLength - empty.bar.sleeveLength)
        XCTAssertEqual(BarbellInspector.layout(loadout: loadout(bar45, counts), style: .steel, explode: -1), closed)
        XCTAssertEqual(BarbellInspector.layout(loadout: loadout(bar45, counts), style: .steel, explode: 2), open)
    }

    func testSparseStacksFrameActualPlatesWithoutAnInvisibleCollar() {
        for count in [1, 2] {
            let sparse = Loadout(bar: bar45, perSide: [PlateCount(plate: Plate(value: 45, unit: .lb), count: count)], collarLb: 0)
            let shut = BarbellInspector.layout(loadout: sparse, style: .steel, explode: 0)
            let spread = BarbellInspector.layout(loadout: sparse, style: .steel, explode: 1)
            let closedView = BarbellInspector.frame(layout: shut, explode: 0)
            let openView = BarbellInspector.frame(layout: spread, explode: 1)
            let discs = spread.discs.filter { $0.side < 0 }
            XCTAssertEqual(discs[0].centerX, shut.discs[0].centerX, accuracy: 1e-9)
            let last = discs.last!
            XCTAssertEqual(spread.collar.left, last.centerX - last.thickness / 2, accuracy: 1e-9, "absent collar reserves no additional gap")
            XCTAssertEqual(spread.collar.length, 0)
            XCTAssertEqual(spread.collar.radius, 0)
            let openYaw = BarbellInspector.Camera.initial(exploded: true).yaw * Double.pi / 180
            let closedYaw = BarbellInspector.Camera.initial(exploded: false).yaw * Double.pi / 180
            XCTAssertLessThan(openView.halfWidth * cos(openYaw), closedView.halfWidth * cos(closedYaw), "sparse inspection has a tighter projected frame")
            if count == 1 { XCTAssertLessThan(openView.halfWidth, closedView.halfWidth * 0.5) }
        }
        let empty = BarbellInspector.layout(loadout: Loadout(bar: Bar(value: 15, unit: .kg), perSide: [], collarLb: 0), style: .bumper, explode: 1)
        XCTAssertEqual(empty.collar.left, -empty.bar.shoulderEnd)
        let frame = BarbellInspector.frame(layout: empty, explode: 1)
        XCTAssertLessThanOrEqual(frame.target.x - frame.halfWidth, -empty.bar.shaftHalfLength - empty.bar.sleeveLength)
    }

    func testExplodedFacesDoNotOverlapAndLabelsKeepTheirWidth() {
        let custom = [Plate(value: 45, unit: .lb).id: PlateGeometry(diameter: 600, thickness: 30)]
        let geometries: [[String: PlateGeometry]] = [[:], custom]
        for geometry in geometries {
            let layout = BarbellInspector.layout(loadout: loadout(bar45, counts), style: .bumper, explode: 1, geometry: geometry)
            let discs = layout.discs.filter { $0.side < 0 }
            let yaw = BarbellInspector.Camera.initial(exploded: true).yaw * Double.pi / 180
            for index in 1..<discs.count {
                let separation = abs(discs[index].centerX - discs[index - 1].centerX) * cos(yaw)
                let faces = (discs[index].radius + discs[index - 1].radius) * sin(yaw)
                XCTAssertGreaterThan(separation, faces + 10, "exploded faces have visible air between them")
            }
        }
        let layout = BarbellInspector.layout(loadout: loadout(bar45, counts), style: .steel, explode: 1)
        XCTAssertEqual(BarbellInspector.minimumWidth(layout: layout, viewportWidth: 390, exploded: false), 390)
        XCTAssertEqual(BarbellInspector.minimumWidth(layout: layout, viewportWidth: 390, exploded: true), 390)
        XCTAssertEqual(BarbellInspector.minimumWidth(layout: layout, viewportWidth: 354, exploded: true), 368)
        XCTAssertEqual(BarbellInspector.minimumWidth(layout: layout, viewportWidth: 1280, exploded: true), 1280)
        let empty = BarbellInspector.layout(loadout: loadout(bar45, []), style: .steel, explode: 1)
        XCTAssertEqual(BarbellInspector.minimumWidth(layout: empty, viewportWidth: 320, exploded: true), 320)
        let heavy = BarbellInspector.layout(loadout: loadout(bar45, [PlateCount(plate: Plate(value: 20, unit: .kg), count: 8)]), style: .bumper, explode: 1)
        XCTAssertEqual(BarbellInspector.minimumWidth(layout: heavy, viewportWidth: 390, exploded: true), 928)
    }

    func testProfilesAreClosedSymmetricAndInsideThePlate() {
        for (family, diameter, thickness) in [("bumper", 450.0, 60.0), ("steel", 450.0, 27.0), ("change", 160.0, 16.0)] {
            let profile = BarbellInspector.plateProfile(family: family, diameter: diameter, thickness: thickness)
            XCTAssertGreaterThanOrEqual(profile.count, 6, family)
            XCTAssertTrue(profile.allSatisfy { $0.radius >= 25.25 - 1e-9 && $0.radius <= diameter / 2 + 1e-9 && abs($0.axial) <= thickness / 2 + 3 + 1e-9 }, family)
            XCTAssertTrue(profile.contains { abs($0.radius - diameter / 2) < 1e-9 }, family)
            XCTAssertEqual(profile.first?.radius, 25.25, family)
            XCTAssertEqual(profile.last?.radius, 25.25, family)
            let mirrored = profile.map { BarbellInspector.ProfilePoint(radius: $0.radius, axial: -$0.axial) }.reversed()
            XCTAssertEqual(profile, Array(mirrored), "\(family) profile is symmetric about the centre plane")
        }
        XCTAssertTrue(BarbellInspector.plateProfile(family: "bumper", diameter: 450, thickness: 60)
            .contains { $0.radius > 25.25 && $0.radius < 225 && abs($0.axial) < 30 - 1 }, "bumper faces are recessed inside the rim")
        let bumper = BarbellInspector.plateProfile(family: "bumper", diameter: 450, thickness: 60)
        XCTAssertGreaterThan(bumper[1].radius, 100, "competition bumper has a broad chrome hub")
        XCTAssertTrue(bumper[2].axial >= -30 && bumper[2].axial <= -26, "bumper face is shallowly recessed")
        for family in ["bumper", "steel", "change"] {
            let profile = BarbellInspector.plateProfile(family: family, diameter: 450, thickness: 30)
            XCTAssertTrue(profile.contains { $0.radius == 225 && abs($0.axial) < 15 }, "outer edge is chamfered")
            XCTAssertEqual(profile[1].radius, profile[2].radius, "chrome has exactly a face and a hub wall")
        }
        XCTAssertTrue(BarbellInspector.plateProfile(family: "steel", diameter: 450, thickness: 27)
            .contains { $0.radius < 0.3 * 225 && $0.axial > -13.5 }, "steel faces dish toward the hub")
    }

    func testModelMatchesWebFixture() throws {
        struct Fixture: Decodable {
            struct Solution: Decodable { let bar: Bar; let perSide: [PlateCount] }
            struct Disc: Decodable { let side, index: Int; let family: String; let centerX, radius, thickness: Double }
            struct Collar: Decodable { let left, right, length, radius: Double }
            struct BarDims: Decodable { let shaftHalfLength, sleeveLength, shaftRadius, sleeveRadius, shoulderRadius, shoulderLength, collarLength, collarRadius, shoulderEnd: Double }
            struct Layout: Decodable { let bar: BarDims; let discs: [Disc]; let collar: Collar; let extent, maxRadius: Double }
            struct Profile: Decodable { let family: String; let diameter, thickness: Double; let points: [[Double]] }
            struct CameraCase: Decodable {
                struct Cam: Decodable { let yaw, pitch, zoom: Double }
                struct Pos: Decodable { let x, y, z: Double }
                let camera: Cam; let distance: Double; let position: Pos
            }
            struct FrameCase: Decodable {
                struct Frame: Decodable { struct Target: Decodable { let x, y, z: Double }; let target: Target; let halfWidth: Double }
                let explode: Double; let frame: Frame
            }
            let solution: Solution; let style: String; let explode: Double
            let layout: Layout; let profiles: [Profile]; let cameras: [CameraCase]; let frames: [FrameCase]
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("web/tests/fixtures/barbell-3d.json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        let layout = BarbellInspector.layout(loadout: Loadout(bar: fixture.solution.bar, perSide: fixture.solution.perSide, collarLb: 0),
                                             style: fixture.style == "bumper" ? .bumper : .steel, explode: fixture.explode)
        XCTAssertEqual(layout.discs.count, fixture.layout.discs.count)
        for (disc, expected) in zip(layout.discs, fixture.layout.discs) {
            XCTAssertEqual(disc.side, expected.side); XCTAssertEqual(disc.index, expected.index)
            XCTAssertEqual(disc.family, expected.family)
            XCTAssertEqual(disc.centerX, expected.centerX, accuracy: 1e-8)
            XCTAssertEqual(disc.radius, expected.radius, accuracy: 1e-8)
            XCTAssertEqual(disc.thickness, expected.thickness, accuracy: 1e-8)
        }
        for (actual, expected) in [(layout.bar.shaftHalfLength, fixture.layout.bar.shaftHalfLength), (layout.bar.sleeveLength, fixture.layout.bar.sleeveLength),
                                   (layout.bar.shaftRadius, fixture.layout.bar.shaftRadius), (layout.bar.sleeveRadius, fixture.layout.bar.sleeveRadius),
                                   (layout.bar.shoulderRadius, fixture.layout.bar.shoulderRadius), (layout.bar.shoulderLength, fixture.layout.bar.shoulderLength),
                                   (layout.bar.collarLength, fixture.layout.bar.collarLength), (layout.bar.collarRadius, fixture.layout.bar.collarRadius),
                                   (layout.bar.shoulderEnd, fixture.layout.bar.shoulderEnd), (layout.collar.left, fixture.layout.collar.left),
                                   (layout.collar.right, fixture.layout.collar.right), (layout.collar.length, fixture.layout.collar.length),
                                   (layout.collar.radius, fixture.layout.collar.radius), (layout.extent, fixture.layout.extent), (layout.maxRadius, fixture.layout.maxRadius)] {
            XCTAssertEqual(actual, expected, accuracy: 1e-8)
        }
        for profile in fixture.profiles {
            let points = BarbellInspector.plateProfile(family: profile.family, diameter: profile.diameter, thickness: profile.thickness)
            XCTAssertEqual(points.count, profile.points.count, profile.family)
            for (point, expected) in zip(points, profile.points) {
                XCTAssertEqual(point.radius, expected[0], accuracy: 1e-8)
                XCTAssertEqual(point.axial, expected[1], accuracy: 1e-8)
            }
        }
        for c in fixture.cameras {
            let position = BarbellInspector.Camera(yaw: c.camera.yaw, pitch: c.camera.pitch, zoom: c.camera.zoom).position(distance: c.distance)
            XCTAssertEqual(position.x, c.position.x, accuracy: 1e-8)
            XCTAssertEqual(position.y, c.position.y, accuracy: 1e-8)
            XCTAssertEqual(position.z, c.position.z, accuracy: 1e-8)
        }
        let style: PlateVisualStyle = fixture.style == "bumper" ? .bumper : .steel
        for f in fixture.frames {
            let frameLayout = BarbellInspector.layout(loadout: Loadout(bar: fixture.solution.bar, perSide: fixture.solution.perSide, collarLb: 0), style: style, explode: f.explode)
            let frame = BarbellInspector.frame(layout: frameLayout, explode: f.explode)
            XCTAssertEqual(frame.target.x, f.frame.target.x, accuracy: 1e-8)
            XCTAssertEqual(frame.halfWidth, f.frame.halfWidth, accuracy: 1e-8)
        }
    }
}
