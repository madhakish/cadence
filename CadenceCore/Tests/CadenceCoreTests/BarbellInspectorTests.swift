import XCTest
@testable import CadenceCore

/// Mirrors web/tests/barbell-inspector.test.mjs: the 3D inspector's physical
/// layout, explode fraction, orbit camera, and lathe profiles agree with web.
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
        let gap = BarbellInspector.Limits.explodeGap
        func right(_ layout: BarbellInspector.Layout, _ index: Int) -> BarbellInspector.Disc {
            layout.discs.first { $0.side > 0 && $0.index == index }!
        }
        XCTAssertEqual(right(open, 0).centerX, right(closed, 0).centerX + gap, accuracy: 1e-9)
        XCTAssertEqual(right(open, 2).centerX, right(closed, 2).centerX + 3 * gap, accuracy: 1e-9)
        XCTAssertEqual(right(half, 2).centerX, right(closed, 2).centerX + 1.5 * gap, accuracy: 1e-9)
        XCTAssertEqual(open.collar.right, right(open, 2).centerX + right(open, 2).thickness / 2 + gap, accuracy: 1e-9)
        XCTAssertGreaterThan(open.collar.right, closed.collar.right)
        XCTAssertGreaterThanOrEqual(open.extent, closed.extent)
    }

    func testCameraLimitsAndOrbit() {
        XCTAssertEqual(BarbellInspector.Camera.initial(exploded: true), BarbellInspector.Camera(yaw: 35, pitch: 12, zoom: 1))
        XCTAssertEqual(BarbellInspector.Camera.initial(exploded: false), BarbellInspector.Camera(yaw: 8, pitch: 10, zoom: 1))
        let exploded = BarbellInspector.Camera.initial(exploded: true)
        XCTAssertEqual(exploded.orbiting(yaw: 10, pitch: -5), BarbellInspector.Camera(yaw: 45, pitch: 7, zoom: 1))
        XCTAssertEqual(exploded.orbiting(yaw: 0, pitch: 200).pitch, BarbellInspector.Limits.pitchMax)
        XCTAssertEqual(exploded.orbiting(yaw: 0, pitch: -200).pitch, BarbellInspector.Limits.pitchMin)
        XCTAssertEqual(exploded.orbiting(yaw: 170, pitch: 0).yaw, -155)
        XCTAssertEqual(BarbellInspector.Camera.initial(exploded: false).orbiting(yaw: -188, pitch: 0).yaw, 180)
        XCTAssertEqual(exploded.zoomed(by: 100).zoom, BarbellInspector.Limits.zoomMax)
        XCTAssertEqual(exploded.zoomed(by: 0).zoom, BarbellInspector.Limits.zoomMin)
        XCTAssertEqual(exploded.zoomed(by: 1.5).zoom, 1.5, accuracy: 1e-9)
        let eye = BarbellInspector.Camera.initial(exploded: false).position(distance: 1000)
        XCTAssertEqual((eye.x * eye.x + eye.y * eye.y + eye.z * eye.z).squareRoot(), 1000, accuracy: 1e-9)
        XCTAssertTrue(eye.x < 0 && eye.z > 0 && eye.y > 0)
        XCTAssertEqual(BarbellInspector.Camera(yaw: 90, pitch: 0, zoom: 1).position(distance: 10).x, -10, accuracy: 1e-9)
        XCTAssertEqual(BarbellInspector.Camera(yaw: 0, pitch: 0, zoom: 1).position(distance: 10).z, 10, accuracy: 1e-9)
        XCTAssertEqual(BarbellInspector.Camera(yaw: 0, pitch: 0, zoom: 2).position(distance: 10).z, 5, accuracy: 1e-9)
    }

    func testFrameIsTheBarAssembledAndTheNearStackExploded() {
        let closed = BarbellInspector.layout(loadout: loadout(bar45, counts), style: .steel, explode: 0)
        let open = BarbellInspector.layout(loadout: loadout(bar45, counts), style: .steel, explode: 1)
        let closedFrame = BarbellInspector.frame(layout: closed, explode: 0)
        let openFrame = BarbellInspector.frame(layout: open, explode: 1)
        let midFrame = BarbellInspector.frame(layout: BarbellInspector.layout(loadout: loadout(bar45, counts), style: .steel, explode: 0.5), explode: 0.5)
        XCTAssertEqual(closedFrame, BarbellInspector.Frame(target: BarbellInspector.Point3(x: 0, y: 0, z: 0), halfWidth: closed.extent))
        XCTAssertTrue(openFrame.target.x < -closed.bar.shaftHalfLength && openFrame.target.x > -open.extent, "exploded frames the centre of the near stack")
        XCTAssertTrue(openFrame.halfWidth < closed.extent && openFrame.halfWidth > (open.collar.right + open.collar.length - open.bar.shaftHalfLength) / 2)
        XCTAssertTrue(midFrame.target.x < 0 && midFrame.target.x > openFrame.target.x && midFrame.halfWidth > openFrame.halfWidth)
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
