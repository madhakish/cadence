import Foundation

/// Shared model for the interactive 3D plate inspector. Mirrored 1:1 in
/// web/app/js/barbell-inspector.js; both clients render this layout with
/// their own real-time renderer (SceneKit / WebGL) and prove parity through
/// web/tests/fixtures/barbell-3d.json.
///
/// Everything is physical millimetres from the bar's centre: x runs along the
/// bar (right side positive), y is up, z is toward the viewer. `BarbellScene`
/// stays the orthographic sprite model for compact rows; this is the solid.
public enum BarbellInspector {
    public enum Limits {
        public static let pitchMin = -20.0, pitchMax = 70.0      // degrees above the bar
        public static let zoomMin = 0.55, zoomMax = 3.0
        public static let explodeGap = 65.0                      // mm between plates at explode = 1
    }
    public static let boreRadius = 25.25                         // 50.5 mm Olympic bore

    public struct BarDimensions: Equatable, Sendable {
        public let shaftHalfLength, sleeveLength, shaftRadius, sleeveRadius: Double
        public let shoulderRadius, shoulderLength, collarLength, collarRadius: Double
        public var shoulderEnd: Double { shaftHalfLength + shoulderLength }

        /// Men's (20 kg / 45 lb) and women's (15 kg / 35 lb) bars: the sleeves
        /// differ, the shaft length is the same.
        static let mens = BarDimensions(shaftHalfLength: 685, sleeveLength: 415, shaftRadius: 14, sleeveRadius: 25,
                                        shoulderRadius: 36, shoulderLength: 20, collarLength: 50, collarRadius: 40)
        static let womens = BarDimensions(shaftHalfLength: 685, sleeveLength: 320, shaftRadius: 12.5, sleeveRadius: 25,
                                          shoulderRadius: 36, shoulderLength: 20, collarLength: 50, collarRadius: 40)
    }

    public struct Disc: Equatable, Sendable {
        public let plate: Plate
        public let side: Int          // −1 left, +1 right
        public let index: Int         // stack position from the shoulder
        public let family: String
        public let centerX, radius, thickness: Double
    }

    public struct Collar: Equatable, Sendable {
        public let left, right, length, radius: Double
    }

    public struct Layout: Equatable, Sendable {
        public let bar: BarDimensions
        public let discs: [Disc]
        public let collar: Collar
        public let extent: Double     // half-length of everything, mm
        public let maxRadius: Double
    }

    public static func isWomensBar(_ bar: Bar) -> Bool {
        bar.unit == .kg ? bar.value == 15 : bar.value == 35
    }

    public static func layout(loadout: Loadout, style: PlateVisualStyle, explode: Double,
                              geometry: [String: PlateGeometry] = [:]) -> Layout {
        let bar = isWomensBar(loadout.bar) ? BarDimensions.womens : BarDimensions.mens
        let plates = loadout.perSide.flatMap { count in Array(repeating: count.plate, count: max(0, count.count)) }
        let gap = explode * Limits.explodeGap
        var discs: [Disc] = []
        var stackEnd = bar.shoulderEnd
        for side in [-1, 1] {
            var cursor = bar.shoulderEnd
            for (index, plate) in plates.enumerated() {
                let shape = geometry[plate.id] ?? PlateGeometry.reference(plate, style: style)
                let centerX = cursor + shape.thickness / 2 + gap * Double(index + 1)
                discs.append(Disc(plate: plate, side: side, index: index,
                                  family: PlateGeometry.family(plate, style: style),
                                  centerX: Double(side) * centerX, radius: shape.diameter / 2, thickness: shape.thickness))
                cursor += shape.thickness
            }
            stackEnd = cursor
        }
        let collarStart = stackEnd + gap * Double(plates.count + 1)
        let collar = Collar(left: -collarStart, right: collarStart, length: bar.collarLength, radius: bar.collarRadius)
        let extent = max(bar.shaftHalfLength + bar.sleeveLength, collarStart + bar.collarLength)
        let maxRadius = discs.reduce(bar.collarRadius) { max($0, $1.radius) }
        return Layout(bar: bar, discs: discs, collar: collar, extent: extent, maxRadius: maxRadius)
    }

    public struct Point3: Equatable, Sendable {
        public let x, y, z: Double
        public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
    }

    /// Yaw is the angle between the bar axis and the screen plane (0 =
    /// side-on, 90 = looking down the bar from the −x end). Pitch is elevation
    /// above the bar. Assembled is the straight-ahead view of the whole bar;
    /// exploded swings to 35° and frames the near stack so plates and numerals
    /// read clearly (see `frame(layout:explode:)`).
    public struct Camera: Equatable, Sendable {
        public var yaw, pitch, zoom: Double

        public init(yaw: Double, pitch: Double, zoom: Double) {
            self.yaw = yaw; self.pitch = pitch; self.zoom = zoom
        }

        public static func initial(exploded: Bool) -> Camera {
            exploded ? Camera(yaw: 35, pitch: 12, zoom: 1) : Camera(yaw: 8, pitch: 10, zoom: 1)
        }

        public func orbiting(yaw dYaw: Double, pitch dPitch: Double) -> Camera {
            Camera(yaw: Self.wrapDegrees(yaw + dYaw),
                   pitch: min(Limits.pitchMax, max(Limits.pitchMin, pitch + dPitch)), zoom: zoom)
        }

        public func zoomed(by factor: Double) -> Camera {
            Camera(yaw: yaw, pitch: pitch, zoom: min(Limits.zoomMax, max(Limits.zoomMin, zoom * factor)))
        }

        /// Eye position relative to the orbit target for a base distance.
        public func position(distance: Double) -> Point3 {
            let d = distance / zoom
            let yawR = yaw * .pi / 180, pitchR = pitch * .pi / 180
            return Point3(x: -d * cos(pitchR) * sin(yawR), y: d * sin(pitchR), z: d * cos(pitchR) * cos(yawR))
        }

        /// Wrap into (−180, 180], matching the web modulo arithmetic.
        static func wrapDegrees(_ degrees: Double) -> Double {
            let shifted = degrees + 180
            let modulo = shifted - 360 * (shifted / 360).rounded(.down)
            let wrapped = modulo - 180
            return wrapped == -180 ? 180 : wrapped
        }
    }

    /// What the camera frames at zoom 1: the whole bar when assembled; the
    /// near (−x) stack from the sleeve start to the lock collar when exploded,
    /// blended by the explode fraction so the cut is one continuous move.
    public struct Frame: Equatable, Sendable {
        public let target: Point3
        public let halfWidth: Double
    }

    public static func frame(layout: Layout, explode: Double) -> Frame {
        let t = min(1, max(0, explode))
        let outer = layout.collar.left - layout.collar.length, inner = -layout.bar.shaftHalfLength
        let stackCenter = (outer + inner) / 2, stackHalf = (inner - outer) / 2 + layout.maxRadius * 0.6
        return Frame(target: Point3(x: stackCenter * t + 0, y: 0, z: 0), halfWidth: layout.extent * (1 - t) + stackHalf * t)
    }

    public struct ProfilePoint: Equatable, Sendable {
        public let radius, axial: Double
        public init(radius: Double, axial: Double) { self.radius = radius; self.axial = axial }
    }

    /// Lathe profiles: closed outlines as (radius, axial) millimetre pairs from
    /// the bore on the −x face, over the rim, back to the bore on the +x face.
    /// The renderers revolve them around the bar axis.
    public static func plateProfile(family: String, diameter: Double, thickness: Double) -> [ProfilePoint] {
        let r = diameter / 2, ht = thickness / 2
        let half: [(Double, Double)]
        switch family {
        case "bumper":
            let hub = 0.235 * r, proud = 1.5, recess = 0.14 * thickness, rim = 0.9 * r
            half = [(boreRadius, -(ht + proud)), (hub, -(ht + proud)), (hub, -(ht - recess)), (rim, -(ht - recess)), (rim, -ht), (r, -ht)]
        case "steel":
            let hub = 0.2 * r, proud = 1.5, dish = 0.18 * thickness, lip = 0.86 * r
            half = [(boreRadius, -(ht + proud)), (hub, -(ht + proud)), (hub, -(ht - dish)), (lip, -ht), (r, -ht)]
        default:
            let hub = max(boreRadius + 8, 0.25 * r), proud = 1.0
            half = [(boreRadius, -(ht + proud)), (hub, -(ht + proud)), (hub, -ht), (r, -ht)]
        }
        let front = half.map { ProfilePoint(radius: $0.0, axial: $0.1) }
        return front + front.reversed().map { ProfilePoint(radius: $0.radius, axial: -$0.axial) }
    }
}
