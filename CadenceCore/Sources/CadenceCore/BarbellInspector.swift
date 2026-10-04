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
        /// The plate theme the disc was laid out in.
        public var theme: PlateThemeID = .custom
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
                              geometry: [String: PlateGeometry] = [:], theme: PlateThemeID = .custom) -> Layout {
        let bar = isWomensBar(loadout.bar) ? BarDimensions.womens : BarDimensions.mens
        let plates = loadout.perSide.flatMap { count in Array(repeating: count.plate, count: max(0, count.count)) }
        let shapes = plates.map { geometry[$0.id] ?? PlateTheme.geometry($0, theme: theme, style: style) }
        let maxRadius = shapes.reduce(bar.collarRadius) { max($0, $1.diameter / 2) }
        // At 50° yaw, a face projects radius*sin(yaw) along the stack. The gap
        // exceeds diameter*tan(50°), with air between even the largest faces.
        let fraction = min(1, max(0, explode))
        let gap = fraction * (2 * maxRadius * 1.3 + 24)
        var discs: [Disc] = []
        var stackEnd = bar.shoulderEnd
        for side in [-1, 1] {
            var cursor = bar.shoulderEnd
            for (index, plate) in plates.enumerated() {
                let shape = shapes[index]
                let centerX = cursor + shape.thickness / 2 + gap * Double(index)
                discs.append(Disc(plate: plate, side: side, index: index,
                                  family: PlateTheme.family(plate, theme: theme, style: style),
                                  centerX: Double(side) * centerX, radius: shape.diameter / 2, thickness: shape.thickness, theme: theme))
                cursor += shape.thickness
            }
            stackEnd = cursor
        }
        let hasCollar = loadout.collarLb > 0
        let collarStart = stackEnd + gap * Double(max(0, plates.count - 1)) + (hasCollar && !plates.isEmpty ? min(gap, 80 * fraction) : 0)
        let collar = Collar(left: -collarStart, right: collarStart, length: hasCollar ? bar.collarLength : 0, radius: hasCollar ? bar.collarRadius : 0)
        let extent = max(bar.shaftHalfLength + bar.sleeveLength, collarStart + collar.length)
        return Layout(bar: bar, discs: discs, collar: collar, extent: extent, maxRadius: maxRadius)
    }

    public struct Point3: Equatable, Sendable {
        public let x, y, z: Double
        public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
    }

    /// Yaw is the angle between the bar axis and the screen plane (0 =
    /// side-on, 90 = looking down the bar from the −x end). Pitch is elevation
    /// above the bar. Both authored views frame the near sleeve; the exploded
    /// view swings to 50° so every separated plate face reads clearly.
    public struct Camera: Equatable, Sendable {
        public var yaw, pitch, zoom: Double

        public init(yaw: Double, pitch: Double, zoom: Double) {
            self.yaw = yaw; self.pitch = pitch; self.zoom = zoom
        }

        public static func initial(exploded: Bool) -> Camera {
            exploded ? Camera(yaw: 50, pitch: 10, zoom: 1) : Camera(yaw: 8, pitch: 6, zoom: 1)
        }

        /// Eye position relative to the frame target for a base distance.
        public func position(distance: Double) -> Point3 {
            let d = distance / zoom
            let yawR = yaw * .pi / 180, pitchR = pitch * .pi / 180
            return Point3(x: -d * cos(pitchR) * sin(yawR), y: d * sin(pitchR), z: d * cos(pitchR) * cos(yawR))
        }
    }

    /// Assembled includes sleeve and shaft; inspection frames the actual plates
    /// and any visible collar. Empty bars keep their full sleeve.
    public struct Frame: Equatable, Sendable {
        public let target: Point3
        public let halfWidth: Double
    }

    public static func frame(layout: Layout, explode: Double) -> Frame {
        let t = min(1, max(0, explode))
        let stackOuter = layout.collar.left - layout.collar.length
        let sleeveOuter = min(-layout.bar.shaftHalfLength - layout.bar.sleeveLength, stackOuter)
        let outer = sleeveOuter * (1 - t) + (layout.discs.isEmpty ? sleeveOuter : stackOuter) * t
        let inner = -layout.bar.shaftHalfLength + 260 * (1 - t) + 20 * t
        return Frame(target: Point3(x: (outer + inner) / 2, y: 0, z: 0), halfWidth: (inner - outer) / 2 + layout.maxRadius * 0.6)
    }

    /// Keep every exploded denomination readable; large stacks scroll without
    /// changing the camera. Assembled stays within the viewport.
    public static func minimumWidth(layout: Layout, viewportWidth: Double, exploded: Bool) -> Double {
        exploded ? max(viewportWidth, Double(layout.discs.filter { $0.side < 0 }.count) * 112 + 32) : viewportWidth
    }

    public struct ProfilePoint: Equatable, Sendable {
        public let radius, axial: Double
        public init(radius: Double, axial: Double) { self.radius = radius; self.axial = axial }
    }

    /// Lathe profiles: closed outlines as (radius, axial) millimetre pairs from
    /// the bore on the −x face, over the rim, back to the bore on the +x face.
    /// The renderers revolve them around the bar axis. The first and last two
    /// edges form the chrome hub; the remaining edges belong to the coating.
    public static func plateProfile(family: String, diameter: Double, thickness: Double) -> [ProfilePoint] {
        let r = diameter / 2, ht = thickness / 2
        let half: [(Double, Double)]
        switch family {
        case "bumper":
            let hub = max(boreRadius + 8, 0.47 * r), proud = 1.0
            let recess = min(4, 0.1 * thickness), bevel = min(3, 0.15 * thickness)
            half = [(boreRadius, -(ht + proud)), (hub, -(ht + proud)), (hub, -(ht - recess)),
                    (0.86 * r, -(ht - recess)), (0.91 * r, -ht), (r - bevel, -ht), (r, -(ht - bevel))]
        case "steel":
            let hub = max(boreRadius + 8, 0.2 * r), proud = 0.8
            let dish = min(2.4, 0.12 * thickness), bevel = min(1.2, 0.15 * thickness)
            half = [(boreRadius, -(ht + proud)), (hub, -(ht + proud)), (hub, -(ht - dish)),
                    (0.82 * r, -(ht - dish)), (0.89 * r, -ht), (r - bevel, -ht), (r, -(ht - bevel))]
        case "ipf":
            // Calibrated disc: thin painted face recessed inside a raised outer lip.
            let hub = max(boreRadius + 8, 0.2 * r), proud = 0.8
            let lip = min(2.2, 0.12 * thickness), lipW = 0.06 * r
            half = [(boreRadius, -(ht + proud)), (hub, -(ht + proud)), (hub, -(ht - lip)),
                    (r - lipW - 4, -(ht - lip)), (r - lipW, -ht), (r - 1, -ht), (r, -(ht - 1))]
        case "iron":
            // Cast iron: raised centre boss and a raised rim lip around a sunken face.
            let boss = max(boreRadius + 10, 0.24 * r), proud = 1.2
            let lip = min(3, 0.14 * thickness), lipW = 0.09 * r
            half = [(boreRadius, -(ht + proud)), (boss, -(ht + proud)), (boss + 3, -(ht - lip)),
                    (r - lipW - 3, -(ht - lip)), (r - lipW, -ht), (r - 1.5, -ht), (r, -(ht - 1.5))]
        case "machined":
            // Turned steel: flat face with one shallow machined step.
            let hub = max(boreRadius + 8, 0.22 * r), proud = 0.8, step = min(1.5, 0.08 * thickness)
            half = [(boreRadius, -(ht + proud)), (hub, -(ht + proud)), (hub, -(ht - step)),
                    (0.6 * r, -(ht - step)), (0.62 * r, -ht), (r - 1, -ht), (r, -(ht - 1))]
        default:
            let hub = max(boreRadius + 8, 0.25 * r), proud = 0.7, bevel = min(1.5, 0.15 * thickness)
            half = [(boreRadius, -(ht + proud)), (hub, -(ht + proud)), (hub, -ht), (r - bevel, -ht), (r, -(ht - bevel))]
        }
        let front = half.map { ProfilePoint(radius: $0.0, axial: $0.1) }
        return front + front.reversed().map { ProfilePoint(radius: $0.radius, axial: -$0.axial) }
    }
}
