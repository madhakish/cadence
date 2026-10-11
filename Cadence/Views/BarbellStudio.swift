import CadenceCore
import Metal
import SceneKit
import SwiftUI
import UIKit

/// The one physically lit barbell scene behind every native bar view: the
/// session row, the current-set stage, the calculator and the inspector.
/// A real Olympic bar on a real platform (oak centre branded with the
/// Vitruvian artwork, stall-mat drop zones), lit by the gym environment baked
/// from the approved Cycles look-dev (docs/design-pass/lookdev). Geometry is
/// physical millimetres from `BarbellInspector.layout`: x along the bar (right
/// positive), y up, z toward the viewer.
enum StudioShot: String, Hashable, Sendable {
    /// Straight ahead at bar height: the session row.
    case row
    /// Three-quarter view of the whole bar: stage, calculator, inspector.
    case hero
    /// Plates slid out along the near sleeve so every face reads.
    case blowup
}

final class BarbellStudio {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let loadout: Loadout
    let layout: BarbellInspector.Layout
    /// Near-sleeve plates in stack order, for captions and explode motion.
    private(set) var nearDiscs: [(disc: BarbellInspector.Disc, node: SCNNode)] = []
    private var farDiscs: [(disc: BarbellInspector.Disc, node: SCNNode)] = []
    private var collarNodes: [(side: Int, node: SCNNode)] = []
    private let style: PlateVisualStyle
    private let theme: PlateThemeID
    /// Height of the platform surface below the bar axis (mm).
    let floorDrop: Double

    static let blowupGap = 170.0

    init(loadout: Loadout, style: PlateVisualStyle, theme: PlateThemeID) {
        self.loadout = loadout
        self.style = style
        self.theme = theme
        layout = BarbellInspector.layout(loadout: loadout, style: style, explode: 0, theme: theme)
        floorDrop = layout.maxRadius
        build()
    }

    // MARK: Framing

    /// Places the camera for a shot at a viewport aspect (width / height).
    func frame(_ shot: StudioShot, aspect: Double) {
        let camera = cameraNode.camera!
        camera.projectionDirection = .horizontal
        let eye: SCNVector3, target: SCNVector3, fov: Double, fStop: Double
        switch shot {
        case .row:
            // Lifter's eye at bar height, straight on; the bar fills the width.
            let halfWidth = layout.extent + 70
            let distance = 3100.0
            fov = 2 * atan(halfWidth / distance) * 180 / .pi
            eye = SCNVector3(-120, 25, Float(distance))
            target = SCNVector3(0, Float(-0.12 * floorDrop), 0)
            fStop = 8
        case .hero:
            let reach = max(1, layout.extent / 1120)
            eye = SCNVector3(Float(-2000 * reach), 330, Float(2250 * reach))
            target = SCNVector3(Float(-200 * reach), Float(-0.27 * floorDrop), 0)
            fov = aspect >= 1.5 ? 43.6 : 52
            fStop = 5.6
        case .blowup:
            let near = nearDiscs.map(\.node.position.x)
            let outer = Double(near.min() ?? Float(-layout.bar.shoulderEnd)) - layout.maxRadius * 0.4
            let inner = -layout.bar.shoulderEnd + 60
            let mid = (outer + inner) / 2
            let span = max(700, inner - outer)
            let scale = span / 1000
            eye = SCNVector3(Float(mid - 530 * scale), Float(300 * max(0.8, scale)), Float(1700 * scale))
            target = SCNVector3(Float(mid), Float(-0.2 * floorDrop), 0)
            fov = aspect >= 1.2 ? 48.5 : 58
            fStop = 7.1
        }
        camera.fieldOfView = CGFloat(fov)
        cameraNode.position = eye
        cameraNode.look(at: target)
        let dx = Double(eye.x - target.x), dy = Double(eye.y - target.y), dz = Double(eye.z - target.z)
        camera.focusDistance = CGFloat((dx * dx + dy * dy + dz * dz).squareRoot())
        camera.fStop = CGFloat(fStop)
    }

    /// 0 assembled ... 1 exploded. Only the near sleeve's stack slides; the
    /// far side stays loaded so the bar still reads as one object.
    func explode(_ t: Double) {
        let t = min(1, max(0, t))
        for (disc, node) in nearDiscs {
            node.position.x = Float(disc.centerX - t * Self.blowupGap * Double(disc.index))
        }
        for (side, node) in collarNodes where side < 0 {
            node.opacity = CGFloat(1 - t)
        }
    }

    // MARK: Build

    private func build() {
        let bar = layout.bar
        let oxide = PlateTheme.description(theme).barFinish == .blackOxide
        let root = scene.rootNode

        // Shaft: polished sections, diamond knurl zones with chalk, marks at
        // 810/910 mm, a centre knurl.
        let zones: [(Double, Double, Bool)] = Self.shaftZones(half: bar.shaftHalfLength)
        for (a, b, knurled) in zones where b > a {
            let mat = knurled ? (oxide ? StudioMaterials.oxideKnurl : StudioMaterials.knurl)
                              : (oxide ? StudioMaterials.oxideShaft : StudioMaterials.shaft)
            let node = SCNNode(geometry: StudioLathe.geometry(
                [.init(bar.shaftRadius, a), .init(bar.shaftRadius, b)], segments: 64, materials: [mat]))
            root.addChildNode(node)
        }
        for s in [-1.0, 1.0] {
            root.addChildNode(Self.shoulder(bar: bar, side: s))
            root.addChildNode(Self.sleeve(bar: bar, side: s))
        }

        for disc in layout.discs {
            let node = StudioPlates.node(for: disc, style: style, theme: theme)
            node.position = SCNVector3(Float(disc.centerX), 0, 0)
            root.addChildNode(node)
            if disc.side < 0 { nearDiscs.append((disc, node)) } else { farDiscs.append((disc, node)) }
        }
        nearDiscs.sort { $0.disc.index < $1.disc.index }

        if loadout.collarLb > 0 {
            for side in [-1, 1] {
                let x = side < 0 ? layout.collar.left - layout.collar.length / 2 : layout.collar.right + layout.collar.length / 2
                let node = Self.collar(length: layout.collar.length, radius: layout.collar.radius, bore: bar.sleeveRadius)
                node.position = SCNVector3(Float(x), 0, 0)
                root.addChildNode(node)
                collarNodes.append((side, node))
            }
        }

        StudioPlatform.add(to: root, floorY: -floorDrop)
        StudioLighting.apply(to: scene, floorY: -floorDrop)

        let camera = SCNCamera()
        camera.zNear = 40
        camera.zFar = 40000
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = StudioLighting.exposure
        camera.averageGray = 0.18
        camera.whitePoint = 1.0
        camera.minimumExposure = -10
        camera.maximumExposure = 10
        camera.bloomIntensity = 0.18
        camera.bloomThreshold = 1.1
        camera.bloomBlurRadius = 6
        camera.screenSpaceAmbientOcclusionIntensity = 1.1
        camera.screenSpaceAmbientOcclusionRadius = 40
        camera.screenSpaceAmbientOcclusionNormalThreshold = 0.3
        camera.screenSpaceAmbientOcclusionDepthThreshold = 0.2
        camera.vignettingIntensity = 0.35
        camera.vignettingPower = 0.6
        camera.wantsDepthOfField = true
        camera.focalBlurSampleCount = 12
        camera.apertureBladeCount = 7
        cameraNode.camera = camera
        root.addChildNode(cameraNode)
        frame(.hero, aspect: 16.0 / 9.0)
    }

    /// (from, to, knurled) along the shaft, left to right.
    static func shaftZones(half: Double) -> [(Double, Double, Bool)] {
        let mark = 2.5
        // Right-half boundaries; mirrored for the left.
        let right: [(Double, Double, Bool)] = [
            (0, 60, true), (60, 210, false), (210, 405 - mark, true), (405 - mark, 405 + mark, false),
            (405 + mark, 455 - mark, true), (455 - mark, 455 + mark, false), (455 + mark, half - 45, true),
            (half - 45, half, false),
        ]
        var out: [(Double, Double, Bool)] = []
        for (a, b, k) in right.reversed() { out.append((-b, -a, k)) }
        out.append(contentsOf: right)
        return out
    }

    private static func shoulder(bar: BarbellInspector.BarDimensions, side: Double) -> SCNNode {
        let x0 = bar.shaftHalfLength, x1 = bar.shoulderEnd, r = bar.shoulderRadius
        let p: [StudioLathe.P] = [
            .init(bar.shaftRadius, x0 - 0.5), .init(r - 3.5, x0), .init(r, x0 + 3), .init(r, x1 - 5),
            .init(r - 4, x1 - 2.5), .init(r - 4, x1), .init(bar.sleeveRadius + 0.2, x1),
        ]
        let node = SCNNode(geometry: StudioLathe.geometry(StudioLathe.mirrored(p, side), segments: 96,
                                                          materials: [StudioMaterials.chrome]))
        let bush = StudioLathe.geometry(StudioLathe.mirrored([.init(r - 4.2, x1 - 2.4), .init(r - 4.2, x1 - 0.2)], side),
                                        segments: 96, materials: [StudioMaterials.bronze])
        node.addChildNode(SCNNode(geometry: bush))
        return node
    }

    private static func sleeve(bar: BarbellInspector.BarDimensions, side: Double) -> SCNNode {
        let sr = bar.sleeveRadius, x1 = bar.shoulderEnd, e = bar.shoulderEnd + bar.sleeveLength
        let g1 = e - 40, g2 = e - 55
        let p: [StudioLathe.P] = [
            .init(sr * 0.98, x1), .init(sr, x1 + 0.5), .init(sr, g2), .init(sr - 0.8, g2 + 1), .init(sr - 0.8, g2 + 2.5),
            .init(sr, g2 + 3.5), .init(sr, g1), .init(sr - 0.8, g1 + 1), .init(sr - 0.8, g1 + 2.5), .init(sr, g1 + 3.5),
            .init(sr, e - 2.5), .init(sr - 2.5, e), .init(17, e), .init(16, e - 3), .init(0, e - 3),
        ]
        let node = SCNNode(geometry: StudioLathe.geometry(StudioLathe.mirrored(p, side), segments: 128,
                                                          materials: [StudioMaterials.sleeve]))
        let cap: [StudioLathe.P] = [.init(10.5, e - 2.9), .init(10.5, e - 1.6), .init(0, e - 1.4)]
        node.addChildNode(SCNNode(geometry: StudioLathe.geometry(StudioLathe.mirrored(cap, side), segments: 48,
                                                                 materials: [StudioMaterials.darkSteel])))
        return node
    }

    /// Spring-lock collar: chrome body, knurled grip ring, black release lever.
    private static func collar(length: Double, radius: Double, bore: Double) -> SCNNode {
        let h = length / 2
        let p: [StudioLathe.P] = [
            .init(bore + 0.4, -h), .init(radius - 4, -h), .init(radius, -h + 4), .init(radius, -h + 20), .init(radius - 3, -h + 22),
            .init(radius - 3, h - 16), .init(radius, h - 14), .init(radius, h - 4), .init(radius - 4, h), .init(bore + 0.4, h),
        ]
        let node = SCNNode(geometry: StudioLathe.geometry(p, segments: 96, materials: [StudioMaterials.chrome]))
        let grip = StudioLathe.geometry([.init(radius - 2.8, -h + 22), .init(radius - 1.5, -h + 23), .init(radius - 1.5, h - 17),
                                         .init(radius - 2.8, h - 16)], segments: 96, materials: [StudioMaterials.knurledRing])
        node.addChildNode(SCNNode(geometry: grip))
        let lever = SCNBox(width: 28, height: 34, length: 12, chamferRadius: 3)
        lever.firstMaterial = StudioMaterials.lever
        let leverNode = SCNNode(geometry: lever)
        leverNode.position = SCNVector3(0, Float(radius + 15), 0)
        leverNode.eulerAngles.z = 0.35
        node.addChildNode(leverNode)
        return node
    }
}

// MARK: - Lathe

/// Revolves a (radius, axial) profile around the bar (x) axis. Each profile
/// edge owns its ring pair, so creases stay crisp while the circumference
/// shades smoothly. `m` on the first point of an edge picks its material.
/// u runs around the circumference, v along the profile. Profiles wind from
/// the −x side outward and back along +x; `mirrored` flips x and reverses the
/// winding so normals stay outward.
enum StudioLathe {
    struct P {
        let r: Double, x: Double, m: Int
        init(_ r: Double, _ x: Double, _ m: Int = 0) { self.r = r; self.x = x; self.m = m }
    }

    static func geometry(_ profile: [P], segments: Int, materials: [SCNMaterial]) -> SCNGeometry {
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], uvs: [CGPoint] = []
        var indices = Array(repeating: [Int32](), count: max(1, materials.count))
        let total = zip(profile, profile.dropFirst()).reduce(0.0) { $0 + hypot($1.1.r - $1.0.r, $1.1.x - $1.0.x) }
        var travelled = 0.0
        for (a, b) in zip(profile, profile.dropFirst()) {
            let dr = b.r - a.r, dx = b.x - a.x
            let length = hypot(dr, dx)
            guard length > 0 else { continue }
            // Outward normal for a profile wound from the −x face, over the
            // rim, back along the +x face; mirrored profiles are reversed.
            let nr = dx / length, nx = -dr / length
            let base = Int32(vertices.count)
            for (point, v) in [(a, travelled / total), (b, (travelled + length) / total)] {
                for j in 0...segments {
                    let t = Double(j) / Double(segments) * 2 * .pi
                    let c = cos(t), s = sin(t)
                    vertices.append(SCNVector3(Float(point.x), Float(point.r * c), Float(point.r * s)))
                    normals.append(SCNVector3(Float(nx), Float(nr * c), Float(nr * s)))
                    uvs.append(CGPoint(x: Double(j) / Double(segments), y: v))
                }
            }
            let ring = Int32(segments + 1)
            let slot = min(max(0, a.m), indices.count - 1)
            for j in 0..<Int32(segments) {
                let i0 = base + j, i1 = i0 + 1, i2 = base + ring + j, i3 = i2 + 1
                indices[slot] += [i0, i2, i1, i1, i2, i3]
            }
            travelled += length
        }
        let elements = indices.map { SCNGeometryElement(indices: $0, primitiveType: .triangles) }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
                                             SCNGeometrySource(textureCoordinates: uvs)], elements: elements)
        geometry.materials = materials.isEmpty ? [StudioMaterials.chrome] : materials
        return geometry
    }

    static func mirrored(_ p: [P], _ side: Double) -> [P] {
        let m = p.map { P($0.r, $0.x * side, $0.m) }
        return side < 0 ? m.reversed() : m
    }

    static func fillet(_ cr: Double, _ cx: Double, _ radius: Double, from a0: Double, to a1: Double, steps: Int = 6, m: Int) -> [P] {
        (0...steps).map { i in
            let a = a0 + (a1 - a0) * Double(i) / Double(steps)
            return P(cr + radius * cos(a), cx + radius * sin(a), m)
        }
    }
}

// MARK: - Plates

enum StudioPlates {
    private static var built: [String: SCNNode] = [:]
    private static let lock = NSLock()

    /// A complete plate (body, hub, bolts, lettering) centred on its own
    /// origin with the axis along x, flattened to a single node. Identical
    /// plates share geometry through clones.
    static func node(for disc: BarbellInspector.Disc, style: PlateVisualStyle, theme: PlateThemeID) -> SCNNode {
        let key = "\(disc.plate.id)|\(style.rawValue)|\(theme.rawValue)|\(disc.family)|\(disc.radius)|\(disc.thickness)"
        lock.lock()
        let hit = built[key]
        lock.unlock()
        if let hit { return hit.clone() }
        let made = build(disc, style: style, theme: theme)
        lock.lock()
        built[key] = made
        lock.unlock()
        return made.clone()
    }

    private static func build(_ disc: BarbellInspector.Disc, style: PlateVisualStyle, theme: PlateThemeID) -> SCNNode {
        let plate = disc.plate
        let R = disc.radius, T = disc.thickness, ht = T / 2
        let colour = PlateTheme.colour(plate, theme: theme, style: style)
        let finish = PlateTheme.material(plate, theme: theme, style: style)
        let ratios = PlateTheme.ratios(plate, theme: theme, style: style)
        let look = PlateTheme.description(theme)
        let bore = BarbellInspector.boreRadius
        let root = SCNNode()
        let body = StudioMaterials.plateBody(finish, fill: colour.fill)
        let tyre = StudioMaterials.plateTyre(finish, fill: colour.fill)
        let hubMat = StudioMaterials.hub(look.hubFinish)
        let ink = StudioMaterials.ink(colour.ink)
        let small = R < 120
        let kind = disc.family
        let scale = R / 225

        func addHub(_ hubR: Double, proud: Double) {
            let h = ht + proud
            let p: [StudioLathe.P] = [
                .init(bore, -h + 0.8), .init(bore + 0.8, -h), .init(hubR - 1.5, -h), .init(hubR, -h + 1.5),
                .init(hubR, h - 1.5), .init(hubR - 1.5, h), .init(bore + 0.8, h), .init(bore, h - 0.8), .init(bore, -h + 0.8),
            ]
            root.addChildNode(SCNNode(geometry: StudioLathe.geometry(p, segments: 128, materials: [hubMat])))
        }

        var faceX = ht
        func addPrint(hubR: Double, outer: Double, ink: SCNMaterial) {
            let band = (hubR + outer) / 2
            for face in [-1.0, 1.0] {
                if small {
                    root.addChildNode(StudioLettering.arc("\(plate.denomination) \(plate.unit.rawValue.uppercased())",
                                                          size: R * 0.3, radius: (hubR + R) / 2 - 4, top: false, extrude: 0.2,
                                                          material: ink, condensed: true, face: face, faceX: faceX))
                } else {
                    root.addChildNode(StudioLettering.arc("\(plate.denomination) \(plate.unit.rawValue.uppercased())",
                                                          size: min(74 * scale, (outer - hubR) * 0.62), radius: band + 2,
                                                          top: false, extrude: 0.25, material: ink, condensed: true,
                                                          face: face, faceX: faceX))
                    root.addChildNode(StudioLettering.arc(look.brand, size: 30 * scale, radius: band - 4, top: true,
                                                          extrude: 0.25, material: ink, condensed: false, tracking: 1.35,
                                                          face: face, faceX: faceX))
                }
            }
        }
        switch kind {
        case "iron", "machined":
            let boss = max(bore + 22, R * 0.27), lip = max(14, R * 0.075)
            let dish = ht - min(7, T * 0.22), f = 3.5
            var p: [StudioLathe.P] = [.init(boss, -ht - 1.5), .init(boss + 4, -dish), .init(R - lip - 4, -dish), .init(R - lip, -ht + 0.5),
                                      .init(R - f, -ht, 1)]
            p += StudioLathe.fillet(R - f, -ht + f, f, from: -.pi / 2, to: 0, steps: 4, m: 1).dropFirst()
            p += StudioLathe.fillet(R - f, ht - f, f, from: 0, to: .pi / 2, steps: 4, m: 0)
            p += [.init(R - lip, ht - 0.5), .init(R - lip - 4, dish), .init(boss + 4, dish), .init(boss, ht + 1.5)]
            let castMat = kind == "machined" ? StudioMaterials.machinedSteel : body
            root.addChildNode(SCNNode(geometry: StudioLathe.geometry(p, segments: 160, materials: [castMat, castMat])))
            let hub: [StudioLathe.P] = [.init(bore, -ht - 1.5), .init(boss, -ht - 1.5), .init(boss, ht + 1.5), .init(bore, ht + 1.5), .init(bore, -ht - 1.5)]
            root.addChildNode(SCNNode(geometry: StudioLathe.geometry(hub, segments: 128, materials: [castMat])))
            faceX = dish
            for face in [-1.0, 1.0] {
                let radius = (boss + R - lip) / 2
                root.addChildNode(StudioLettering.arc(plate.denomination, size: R > 170 ? 90 : R * 0.4, radius: radius, top: false,
                                                      extrude: 2.2, material: castMat, condensed: true, face: face, faceX: faceX))
                if R > 150 {
                    root.addChildNode(StudioLettering.arc("\(look.brand)  ·  \(plate.unit.rawValue.uppercased())", size: 24 * scale,
                                                          radius: radius, top: true, extrude: 1.5, material: castMat,
                                                          condensed: false, tracking: 1.3, face: face, faceX: faceX))
                }
            }
        case "steel", "ipf":
            let lip = min(2.2, 0.12 * T), lipW = 12 * scale
            let hubR = max(bore + 8, R * ratios.hub)
            var p: [StudioLathe.P] = [.init(hubR, -ht + 0.4), .init(hubR + 4, -ht + lip), .init(R - lipW - 4, -ht + lip),
                                      .init(R - lipW, -ht, 1)]
            p += [.init(R - 1.2, -ht, 1), .init(R, -ht + 1.2, 1), .init(R, ht - 1.2, 1), .init(R - 1.2, ht, 1), .init(R - lipW, ht, 0)]
            p += [.init(R - lipW - 4, ht - lip), .init(hubR + 4, ht - lip), .init(hubR, ht - 0.4)]
            root.addChildNode(SCNNode(geometry: StudioLathe.geometry(p, segments: 160, materials: [body, tyre])))
            addHub(hubR, proud: 1.0)
            faceX = ht - lip + 0.08
            addPrint(hubR: hubR, outer: R - lipW, ink: ink)
        default:
            // Rubber: competition/training bumpers and rubber change plates.
            let hubR = small ? max(bore + 12, R * 0.42) : max(bore + 30, R * min(0.5, look.hubRatio ?? 0.48))
            let f = min(8, T * 0.22), gR = R * 0.8
            var p: [StudioLathe.P] = [.init(hubR, -ht + 0.8)]
            if !small {
                p += [.init(gR - 4, -ht), .init(gR - 2, -ht + 1.2), .init(gR + 2, -ht + 1.2), .init(gR + 4, -ht)]
            }
            p += [.init(R - f, -ht, 1)]
            p += StudioLathe.fillet(R - f, -ht + f, f, from: -.pi / 2, to: 0, m: 1).dropFirst()
            p += StudioLathe.fillet(R - f, ht - f, f, from: 0, to: .pi / 2, m: 1)
            if !small {
                p += [.init(gR + 4, ht), .init(gR + 2, ht - 1.2), .init(gR - 2, ht - 1.2), .init(gR - 4, ht)]
            }
            p += [.init(hubR, ht - 0.8)]
            // The last fillet point starts the inner face; give it the body material.
            if let i = p.indices.last(where: { p[$0].m == 1 }) { p[i] = .init(p[i].r, p[i].x, 0) }
            root.addChildNode(SCNNode(geometry: StudioLathe.geometry(p, segments: 192, materials: [body, tyre])))
            addHub(hubR, proud: 1.2)
            if !small && (look.details.contains("boltedHub") || theme == .custom || finish.finish == .rubber) {
                for i in 0..<6 {
                    let a = Double(i) / 6 * 2 * .pi + .pi / 6
                    for face in [-1.0, 1.0] {
                        let head: [StudioLathe.P] = [.init(0, 0), .init(8.5, 0), .init(9.2, 0.8), .init(9.2, 3), .init(8, 4), .init(0, 4)]
                        let bolt = StudioLathe.geometry(StudioLathe.mirrored(head, face), segments: 32,
                                                        materials: [StudioMaterials.bolt])
                        let node = SCNNode(geometry: bolt)
                        node.position = SCNVector3(Float(face * (ht + 1.2)), Float(79 * scale * cos(a)), Float(79 * scale * sin(a)))
                        root.addChildNode(node)
                        let socket = StudioLathe.geometry(StudioLathe.mirrored([.init(4, 4.05), .init(0, 4.05)], face),
                                                          segments: 6, materials: [StudioMaterials.darkSteel])
                        let s = SCNNode(geometry: socket)
                        s.position = node.position
                        root.addChildNode(s)
                    }
                }
            }
            faceX = ht + 0.05
            addPrint(hubR: hubR, outer: small ? R : gR, ink: ink)
        }

        if let band = PlateTheme.band(plate, theme: theme) {
            let w = max(6, 0.34 * T)
            root.addChildNode(SCNNode(geometry: StudioLathe.geometry(
                [.init(R + 0.4, -w / 2), .init(R + 0.4, w / 2)], segments: 192, materials: [StudioMaterials.band(band)])))
        }
        let flat = root.flattenedClone()
        flat.name = plate.id
        return flat
    }
}

// MARK: - Lettering

/// Raised lettering laid on an arc of the plate face, like real moulded or
/// printed plates. Text sits in the face plane (y up, z across); `face` −1 is
/// the −x face read from −x, +1 the +x face read from +x.
enum StudioLettering {
    private static var glyphs: [String: SCNText] = [:]
    private static let lock = NSLock()

    static func arc(_ string: String, size: Double, radius: Double, top: Bool, extrude: Double, material: SCNMaterial,
                    condensed: Bool, tracking: Double = 1.06, face: Double, faceX: Double) -> SCNNode {
        let font = condensed
            ? UIFont.systemFont(ofSize: CGFloat(size), weight: .heavy, width: .condensed)
            : UIFont.systemFont(ofSize: CGFloat(size), weight: .bold)
        let chars = string.map(String.init)
        let advances = chars.map { advance($0, font: font) * tracking }
        let total = advances.reduce(0, +)
        let group = SCNNode()
        var cursor = -total / 2
        for (ch, adv) in zip(chars, advances) {
            defer { cursor += adv }
            guard ch != " " else { continue }
            let s = cursor + adv / 2
            let a = s / radius
            let node = SCNNode(geometry: glyph(ch, font: font, extrude: extrude, material: material))
            let (minB, maxB) = node.boundingBox
            node.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2, Float(font.capHeight / 2), 0)
            if top {
                node.position = SCNVector3(Float(radius * sin(a)), Float(radius * cos(a)), 0)
                node.eulerAngles.z = Float(-a)
            } else {
                node.position = SCNVector3(Float(radius * sin(a)), Float(-radius * cos(a)), 0)
                node.eulerAngles.z = Float(a)
            }
            group.addChildNode(node)
        }
        // Text +z → face normal, text +y → up, text +x → right as seen from that face.
        group.eulerAngles.y = Float(face < 0 ? -Double.pi / 2 : Double.pi / 2)
        group.position = SCNVector3(Float(face * faceX), 0, 0)
        return group
    }

    private static func advance(_ ch: String, font: UIFont) -> Double {
        Double((ch as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func glyph(_ ch: String, font: UIFont, extrude: Double, material: SCNMaterial) -> SCNText {
        let key = "\(ch)|\(font.fontName)|\(font.pointSize)|\(extrude)|\(ObjectIdentifier(material).hashValue)"
        lock.lock(); defer { lock.unlock() }
        if let cached = glyphs[key] { return cached }
        let text = SCNText(string: ch, extrusionDepth: CGFloat(extrude))
        text.font = font
        text.flatness = 0.08
        text.chamferRadius = CGFloat(min(extrude * 0.3, 0.35))
        text.materials = [material]
        glyphs[key] = text
        return text
    }
}

// MARK: - Platform

/// An 8 × 8 ft Olympic platform: two plywood base layers (plies at the edge),
/// a 4 ft oak centre with the Vitruvian artwork laser-burned in, and ¾" stall
/// mats where the plates land; a dark rubber gym floor around it.
enum StudioPlatform {
    static let size = 2438.4, centre = 1219.2, layer = 19.05

    static func add(to root: SCNNode, floorY: Double) {
        let h = size / 2
        let baseTop = floorY - layer
        let base = SCNBox(width: CGFloat(size), height: CGFloat(2 * layer), length: CGFloat(size), chamferRadius: 2)
        base.materials = [StudioMaterials.plywoodEdge]
        let baseNode = SCNNode(geometry: base)
        baseNode.position = SCNVector3(0, Float(baseTop - layer), 0)
        root.addChildNode(baseNode)
        // Oak centre and mats: boxes for their edges, textured planes for their faces.
        let oak = SCNBox(width: CGFloat(centre), height: CGFloat(layer), length: CGFloat(size), chamferRadius: 2.5)
        oak.materials = [StudioMaterials.plywoodEdge]
        let oakNode = SCNNode(geometry: oak)
        oakNode.position = SCNVector3(0, Float(baseTop + layer / 2 - 0.3), 0)
        root.addChildNode(oakNode)
        root.addChildNode(plane(width: centre, length: size, x: 0, y: floorY + 0.05, material: StudioMaterials.oakTop))
        for s in [-1.0, 1.0] {
            let w = h - centre / 2 - 1
            let x = s * (centre / 2 + 1 + w / 2)
            let mat = SCNBox(width: CGFloat(w), height: CGFloat(layer - 0.4), length: CGFloat(size), chamferRadius: 4)
            mat.materials = [StudioMaterials.matSide]
            let matNode = SCNNode(geometry: mat)
            matNode.position = SCNVector3(Float(x), Float(baseTop + (layer - 0.4) / 2), 0)
            root.addChildNode(matNode)
            root.addChildNode(plane(width: w, length: size, x: x, y: floorY - 0.35, material: StudioMaterials.matTop))
        }
        let floor = SCNNode(geometry: SCNPlane(width: 24000, height: 24000))
        floor.geometry?.materials = [StudioMaterials.gymFloor]
        floor.eulerAngles.x = -.pi / 2
        floor.position = SCNVector3(0, Float(baseTop - 2 * layer - 0.5), 0)
        root.addChildNode(floor)
    }

    /// A horizontal plane facing up whose texture's top edge points to −z
    /// (away from the lifter), so the artwork reads upright from the bar.
    private static func plane(width: Double, length: Double, x: Double, y: Double, material: SCNMaterial) -> SCNNode {
        let p = SCNPlane(width: CGFloat(width), height: CGFloat(length))
        p.materials = [material]
        let n = SCNNode(geometry: p)
        n.eulerAngles.x = -.pi / 2
        n.position = SCNVector3(Float(x), Float(y), 0)
        return n
    }
}

// MARK: - Lighting

/// The gym environment (baked equirect from the bar's position) lights and
/// reflects; one soft overhead key casts the contact shadows.
enum StudioLighting {
    static let exposure: CGFloat = 0.0
    static let environmentIntensity: CGFloat = 1.0
    static let keyIntensity: CGFloat = 900

    static func apply(to scene: SCNScene, floorY: Double) {
        let environment = StudioTextures.environment
        scene.lightingEnvironment.contents = environment
        scene.lightingEnvironment.intensity = environmentIntensity
        scene.background.contents = environment
        scene.background.intensity = 1
        let key = SCNLight()
        key.type = .directional
        key.intensity = keyIntensity
        key.color = UIColor(red: 1, green: 0.97, blue: 0.92, alpha: 1)
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowColor = UIColor.black.withAlphaComponent(0.72)
        key.shadowRadius = 14
        key.shadowSampleCount = 24
        key.shadowMapSize = CGSize(width: 4096, height: 4096)
        key.automaticallyAdjustsShadowProjection = true
        key.maximumShadowDistance = 9000
        key.shadowBias = 2
        let node = SCNNode()
        node.light = key
        node.eulerAngles = SCNVector3(-Float.pi * 0.42, -Float.pi * 0.06, 0)
        scene.rootNode.addChildNode(node)
    }
}

// MARK: - Materials

enum StudioMaterials {
    static func pbr(_ colour: UIColor, metalness: Double, roughness: Double) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = colour
        m.metalness.contents = NSNumber(value: metalness)
        m.roughness.contents = NSNumber(value: roughness)
        m.isDoubleSided = true
        return m
    }

    private static func tiled(_ property: SCNMaterialProperty, _ image: UIImage, _ su: Float, _ sv: Float) {
        property.contents = image
        property.wrapS = .repeat
        property.wrapT = .repeat
        property.contentsTransform = SCNMatrix4MakeScale(su, sv, 1)
    }

    static let chrome: SCNMaterial = {
        let m = pbr(UIColor(white: 0.93, alpha: 1), metalness: 1, roughness: 0.06)
        tiled(m.roughness, StudioTextures.smudgeRoughness, 3, 2)
        return m
    }()
    static let sleeve: SCNMaterial = {
        let m = pbr(UIColor(white: 0.94, alpha: 1), metalness: 1, roughness: 0.04)
        tiled(m.roughness, StudioTextures.smudgeRoughness, 4, 3)
        return m
    }()
    static let shaft: SCNMaterial = pbr(UIColor(white: 0.9, alpha: 1), metalness: 1, roughness: 0.19)
    static let knurl: SCNMaterial = {
        let m = pbr(UIColor(white: 0.86, alpha: 1), metalness: 1, roughness: 0.32)
        tiled(m.normal, StudioTextures.knurlNormal, 26, 3)
        m.normal.intensity = 0.9
        tiled(m.diffuse, StudioTextures.chalk, 6, 1)
        return m
    }()
    static let oxideShaft: SCNMaterial = pbr(UIColor(white: 0.2, alpha: 1), metalness: 1, roughness: 0.36)
    static let oxideKnurl: SCNMaterial = {
        let m = knurlCopy()
        m.diffuse.contents = UIColor(white: 0.22, alpha: 1)
        return m
    }()
    private static func knurlCopy() -> SCNMaterial { knurl.copy() as! SCNMaterial }
    static let darkSteel: SCNMaterial = pbr(UIColor(white: 0.12, alpha: 1), metalness: 0.85, roughness: 0.35)
    static let bronze: SCNMaterial = pbr(UIColor(red: 0.55, green: 0.42, blue: 0.26, alpha: 1), metalness: 1, roughness: 0.35)
    static let bolt: SCNMaterial = pbr(UIColor(white: 0.78, alpha: 1), metalness: 1, roughness: 0.2)
    static let knurledRing: SCNMaterial = {
        let m = pbr(UIColor(white: 0.62, alpha: 1), metalness: 1, roughness: 0.38)
        tiled(m.normal, StudioTextures.knurlNormal, 30, 2)
        return m
    }()
    static let lever: SCNMaterial = pbr(UIColor(white: 0.03, alpha: 1), metalness: 0, roughness: 0.4)
    static let machinedSteel: SCNMaterial = {
        let m = pbr(UIColor(white: 0.62, alpha: 1), metalness: 1, roughness: 0.28)
        tiled(m.normal, StudioTextures.brushedNormal, 1, 30)
        return m
    }()

    private static var cache: [String: SCNMaterial] = [:]
    // Recursive: a tyre material is derived from its (cached) body material.
    private static let lock = NSRecursiveLock()
    private static func cached(_ key: String, _ make: () -> SCNMaterial) -> SCNMaterial {
        lock.lock(); defer { lock.unlock() }
        if let m = cache[key] { return m }
        let m = make()
        cache[key] = m
        return m
    }

    /// Plate face: the theme's finish with mottling and fine moulding grain.
    static func plateBody(_ finish: PlateMaterial, fill: UInt32) -> SCNMaterial {
        cached("body|\(finish.finish.rawValue)|\(fill)|\(finish.roughness)|\(finish.metal)") {
            let m = pbr(UIColor(rgb: fill), metalness: finish.metal, roughness: finish.roughness)
            switch finish.finish {
            case .rubber:
                m.roughness.contents = NSNumber(value: max(0.5, min(0.66, finish.roughness)))
                tiled(m.multiply, StudioTextures.mottle, 2, 2)
                tiled(m.normal, StudioTextures.grainNormal, 14, 14)
                m.normal.intensity = 0.35
            case .powder:
                tiled(m.normal, StudioTextures.grainNormal, 10, 10)
                m.normal.intensity = 0.15
                m.clearCoat.contents = NSNumber(value: 0.35)
                m.clearCoatRoughness.contents = NSNumber(value: 0.2)
            case .gloss:
                m.roughness.contents = NSNumber(value: 0.22)
                m.clearCoat.contents = NSNumber(value: 0.8)
                m.clearCoatRoughness.contents = NSNumber(value: 0.05)
            case .castIron:
                tiled(m.normal, StudioTextures.hammerNormal, 6, 6)
                m.normal.intensity = 0.8
                m.clearCoat.contents = NSNumber(value: 0.25)
                m.clearCoatRoughness.contents = NSNumber(value: 0.35)
            case .hammertone:
                tiled(m.normal, StudioTextures.hammerNormal, 3, 3)
                m.normal.intensity = 0.9
            case .machined:
                tiled(m.normal, StudioTextures.brushedNormal, 1, 30)
            }
            return m
        }
    }

    /// The outer tyre: the same finish, rougher, with scuffs from drops.
    static func plateTyre(_ finish: PlateMaterial, fill: UInt32) -> SCNMaterial {
        cached("tyre|\(finish.finish.rawValue)|\(fill)|\(finish.roughness)") {
            let m = plateBody(finish, fill: fill).copy() as! SCNMaterial
            if finish.finish == .rubber {
                m.diffuse.contents = StudioTextures.scuffedTyre(fill: fill)
                m.diffuse.wrapS = .repeat
                m.diffuse.contentsTransform = SCNMatrix4MakeScale(3, 1, 1)
                m.roughness.contents = NSNumber(value: 0.66)
            }
            return m
        }
    }

    static func hub(_ finish: PlateHubFinish) -> SCNMaterial {
        cached("hub|\(finish.rawValue)") {
            switch finish {
            case .chrome:
                let m = pbr(UIColor(white: 0.66, alpha: 1), metalness: 1, roughness: 0.26)
                tiled(m.normal, StudioTextures.brushedNormal, 1, 40)
                return m
            case .blackSteel:
                return pbr(UIColor(white: 0.1, alpha: 1), metalness: 0.6, roughness: 0.45)
            case .castIron:
                let m = pbr(UIColor(white: 0.12, alpha: 1), metalness: 0.2, roughness: 0.55)
                tiled(m.normal, StudioTextures.hammerNormal, 4, 4)
                return m
            case .hammertone:
                let m = pbr(UIColor(white: 0.36, alpha: 1), metalness: 0.3, roughness: 0.5)
                tiled(m.normal, StudioTextures.hammerNormal, 3, 3)
                return m
            }
        }
    }

    /// Paint for printed lettering: satin, slightly worn.
    static func ink(_ colour: UInt32) -> SCNMaterial {
        cached("ink|\(colour)") {
            let m = pbr(UIColor(rgb: colour), metalness: 0, roughness: 0.55)
            tiled(m.multiply, StudioTextures.mottle, 6, 6)
            return m
        }
    }

    static func band(_ colour: UInt32) -> SCNMaterial {
        cached("band|\(colour)") { pbr(UIColor(rgb: colour), metalness: 0, roughness: 0.62) }
    }

    static let oakTop: SCNMaterial = {
        let m = pbr(.white, metalness: 0, roughness: 0.48)
        m.diffuse.contents = StudioTextures.brandedOak
        m.normal.contents = UIImage(named: "PlatformOakNormal")
        m.normal.intensity = 0.6
        m.isDoubleSided = false
        return m
    }()
    static let matTop: SCNMaterial = {
        let m = pbr(.white, metalness: 0, roughness: 0.84)
        m.diffuse.contents = UIImage(named: "PlatformMat")
        tiled(m.normal, UIImage(named: "PlatformMatNormal") ?? UIImage(), 2, 8)
        m.normal.intensity = 0.5
        m.isDoubleSided = false
        return m
    }()
    static let matSide: SCNMaterial = pbr(UIColor(white: 0.05, alpha: 1), metalness: 0, roughness: 0.85)
    static let plywoodEdge: SCNMaterial = {
        let m = pbr(.white, metalness: 0, roughness: 0.75)
        m.diffuse.contents = StudioTextures.plies
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(8, 1, 1)
        return m
    }()
    static let gymFloor: SCNMaterial = {
        let m = pbr(UIColor(white: 0.06, alpha: 1), metalness: 0, roughness: 0.86)
        tiled(m.normal, UIImage(named: "PlatformMatNormal") ?? UIImage(), 30, 30)
        m.normal.intensity = 0.3
        m.isDoubleSided = false
        return m
    }()
}

// MARK: - Textures

/// Deterministic textures: baked platform maps from the asset catalog, the
/// runtime-branded oak, and tileable noise maps for wear and grain.
enum StudioTextures {
    static let environment: UIImage = UIImage(named: "StudioGym") ?? UIImage()

    /// The oak centre with the Vitruvian artwork laser-burned in: dark
    /// engraving lines char the wood; the paper ground leaves it untouched.
    /// The artwork asset is read as-is and never modified.
    static let brandedOak: UIImage = {
        guard let oak = UIImage(named: "PlatformOak")?.cgImage else { return UIImage() }
        let w = oak.width, h = oak.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: space, bitmapInfo: info) else { return UIImage(cgImage: oak) }
        ctx.draw(oak, in: CGRect(x: 0, y: 0, width: w, height: h))
        if let art = UIImage(named: "VitruvianFront")?.cgImage {
            // 950 mm across on a 1219.2 mm-wide oak sheet, centred.
            let side = Int(Double(w) * 950 / StudioPlatform.centre)
            var logo = [UInt8](repeating: 0, count: side * side * 4)
            if let lctx = CGContext(data: &logo, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                    space: space, bitmapInfo: info) {
                lctx.interpolationQuality = .high
                lctx.draw(art, in: CGRect(x: 0, y: 0, width: side, height: side))
                let ox = (w - side) / 2, oy = (h - side) / 2
                func lin(_ v: UInt8) -> Double { pow(Double(v) / 255, 2.2) }
                func srgb(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (pow(max(0, v), 1 / 2.2) * 255).rounded()))) }
                let burn = (0.028, 0.014, 0.007)
                for y in 0..<side {
                    for x in 0..<side {
                        let li = (y * side + x) * 4
                        let lum = 0.2126 * lin(logo[li]) + 0.7152 * lin(logo[li + 1]) + 0.0722 * lin(logo[li + 2])
                        let t = min(1, max(0, (1 - lum - 0.24) / (0.62 - 0.24)))
                        let ink = t * t * (3 - 2 * t) * 0.88
                        guard ink > 0.001 else { continue }
                        let oi = ((oy + y) * w + (ox + x)) * 4
                        pixels[oi] = srgb(lin(pixels[oi]) * (1 - ink) + burn.0 * ink)
                        pixels[oi + 1] = srgb(lin(pixels[oi + 1]) * (1 - ink) + burn.1 * ink)
                        pixels[oi + 2] = srgb(lin(pixels[oi + 2]) * (1 - ink) + burn.2 * ink)
                    }
                }
            }
        }
        guard let out = ctx.makeImage() else { return UIImage(cgImage: oak) }
        return UIImage(cgImage: out)
    }()

    /// Plywood edge: alternating veneer plies.
    static let plies: UIImage = {
        let size = CGSize(width: 64, height: 64)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.62, green: 0.48, blue: 0.32, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.36, green: 0.25, blue: 0.14, alpha: 1).setFill()
            for i in stride(from: 0, to: 64, by: 9) { ctx.fill(CGRect(x: 0, y: CGFloat(i), width: 64, height: 2)) }
        }
    }()

    static let mottle = gray(Noise.field(size: 256, cells: 6, octaves: 4, seed: 11), lo: 0.86, hi: 1.0)
    static let chalk: UIImage = {
        let n = Noise.field(size: 256, cells: 16, octaves: 4, seed: 23)
        return rgb(n) { v in
            let c = max(0, min(1, (v - 0.58) / 0.2)) * 0.22
            let base = 0.86
            return (base + (0.97 - base) * c, base + (0.97 - base) * c, base + (0.95 - base) * c)
        }
    }()
    static let smudgeRoughness = gray(Noise.field(size: 256, cells: 4, octaves: 3, seed: 5), lo: 0.03, hi: 0.1)
    static let grainNormal = normal(Noise.field(size: 256, cells: 64, octaves: 2, seed: 3), strength: 2.0)
    static let hammerNormal = normal(Noise.field(size: 256, cells: 20, octaves: 3, seed: 9), strength: 6.0)
    static let brushedNormal: UIImage = {
        let n = 256
        var field = [Double](repeating: 0, count: n * n)
        let lines = Noise.field(size: n, cells: 128, octaves: 1, seed: 31)
        for y in 0..<n { for x in 0..<n { field[y * n + x] = lines[y * n] * 0.7 + lines[y * n + x] * 0.3 } }
        return normal(field, strength: 1.5)
    }()
    static let knurlNormal: UIImage = {
        let n = 128
        var field = [Double](repeating: 0, count: n * n)
        let pitch = 8.0
        for y in 0..<n {
            for x in 0..<n {
                func tri(_ v: Double) -> Double { let f = v / pitch - (v / pitch).rounded(.down); return 0.5 - abs(f - 0.5) }
                field[y * n + x] = min(tri(Double(x + y)), tri(Double(x - y + n)))
            }
        }
        return normal(field, strength: 4.0)
    }()

    private static var tyres: [UInt32: UIImage] = [:]
    private static let lock = NSLock()
    /// Plate colour with lighter streaks where the tyre has met the platform.
    static func scuffedTyre(fill: UInt32) -> UIImage {
        lock.lock(); defer { lock.unlock() }
        if let t = tyres[fill] { return t }
        let n = 256
        let streak = Noise.field(size: n, cells: 24, octaves: 4, seed: 41)
        let r = Double((fill >> 16) & 255) / 255, g = Double((fill >> 8) & 255) / 255, b = Double(fill & 255) / 255
        let image = rgb(streak) { v in
            let s = max(0, min(1, (v - 0.55) / 0.15)) * 0.7
            func mix(_ c: Double) -> Double { c * (1 - s) + min(1, c * 1.25 + 0.06) * s }
            return (mix(r), mix(g), mix(b))
        }
        tyres[fill] = image
        return image
    }

    // Helpers

    private static func gray(_ field: [Double], lo: Double, hi: Double) -> UIImage {
        rgb(field) { v in let g = lo + (hi - lo) * v; return (g, g, g) }
    }

    private static func rgb(_ field: [Double], _ map: (Double) -> (Double, Double, Double)) -> UIImage {
        let n = Int(Double(field.count).squareRoot())
        var px = [UInt8](repeating: 255, count: n * n * 4)
        for i in 0..<(n * n) {
            let (r, g, b) = map(field[i])
            px[i * 4] = UInt8(max(0, min(255, r * 255)))
            px[i * 4 + 1] = UInt8(max(0, min(255, g * 255)))
            px[i * 4 + 2] = UInt8(max(0, min(255, b * 255)))
        }
        return image(px, n)
    }

    private static func normal(_ field: [Double], strength: Double) -> UIImage {
        let n = Int(Double(field.count).squareRoot())
        var px = [UInt8](repeating: 255, count: n * n * 4)
        func h(_ x: Int, _ y: Int) -> Double { field[((y + n) % n) * n + ((x + n) % n)] }
        for y in 0..<n {
            for x in 0..<n {
                let dx = (h(x + 1, y) - h(x - 1, y)) * strength, dy = (h(x, y + 1) - h(x, y - 1)) * strength
                let l = (dx * dx + dy * dy + 1).squareRoot()
                let i = (y * n + x) * 4
                px[i] = UInt8((-dx / l * 0.5 + 0.5) * 255)
                px[i + 1] = UInt8((-dy / l * 0.5 + 0.5) * 255)
                px[i + 2] = UInt8((1 / l * 0.5 + 0.5) * 255)
            }
        }
        return image(px, n)
    }

    private static func image(_ px: [UInt8], _ n: Int) -> UIImage {
        guard let provider = CGDataProvider(data: Data(px) as CFData),
              let cg = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return UIImage() }
        return UIImage(cgImage: cg)
    }
}

/// Tileable value noise: a periodic lattice, smoothstep interpolation, summed
/// octaves, normalised to 0...1. Deterministic for a seed.
enum Noise {
    static func field(size n: Int, cells: Int, octaves: Int, seed: UInt32) -> [Double] {
        var out = [Double](repeating: 0, count: n * n)
        var amplitude = 1.0, total = 0.0, c = cells
        var state = seed &* 2654435761 &+ 1
        for _ in 0..<octaves {
            var lattice = [Double](repeating: 0, count: c * c)
            for i in 0..<(c * c) {
                state = state &* 1664525 &+ 1013904223
                lattice[i] = Double(state >> 8) / Double(1 << 24)
            }
            for y in 0..<n {
                let fy = Double(y) / Double(n) * Double(c)
                let y0 = Int(fy) % c, y1 = (y0 + 1) % c, ty = fy - fy.rounded(.down)
                let sy = ty * ty * (3 - 2 * ty)
                for x in 0..<n {
                    let fx = Double(x) / Double(n) * Double(c)
                    let x0 = Int(fx) % c, x1 = (x0 + 1) % c, tx = fx - fx.rounded(.down)
                    let sx = tx * tx * (3 - 2 * tx)
                    let a = lattice[y0 * c + x0] * (1 - sx) + lattice[y0 * c + x1] * sx
                    let b = lattice[y1 * c + x0] * (1 - sx) + lattice[y1 * c + x1] * sx
                    out[y * n + x] += (a * (1 - sy) + b * sy) * amplitude
                }
            }
            total += amplitude
            amplitude *= 0.5
            c *= 2
        }
        let lo = out.min() ?? 0, hi = out.max() ?? 1
        return out.map { ($0 - lo) / max(1e-9, hi - lo) }
    }
}

// MARK: - Offscreen renders

/// Renders static studio images for rows, stages and the calculator on one
/// serial queue with one SceneKit renderer, and caches them by request.
final class StudioRenderer: @unchecked Sendable {
    static let shared = StudioRenderer()

    struct Request: Hashable {
        let loadout: Loadout
        let style: PlateVisualStyle
        let theme: PlateThemeID
        let shot: StudioShot
        let width: Int
        let height: Int
        let scale: Double
    }

    private let queue = DispatchQueue(label: "com.madhakish.cadence.studio", qos: .userInitiated)
    private let cache = NSCache<NSString, UIImage>()
    private var renderer: SCNRenderer?

    static var isSupported: Bool { MTLCreateSystemDefaultDevice() != nil }

    private static func key(_ r: Request) -> NSString {
        "\(r.loadout.hashValue)|\(r.style.rawValue)|\(r.theme.rawValue)|\(r.shot.rawValue)|\(r.width)x\(r.height)@\(r.scale)" as NSString
    }

    func cached(_ request: Request) -> UIImage? { cache.object(forKey: Self.key(request)) }

    func render(_ request: Request) async -> UIImage? {
        if let hit = cached(request) { return hit }
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: renderNow(request))
            }
        }
    }

    /// Synchronous on the studio queue; also used by the render lab.
    func renderNow(_ request: Request) -> UIImage? {
        if let hit = cached(request) { return hit }
        guard request.width > 0, request.height > 0 else { return nil }
        if renderer == nil {
            guard let device = MTLCreateSystemDefaultDevice() else { return nil }
            renderer = SCNRenderer(device: device, options: nil)
        }
        guard let renderer else { return nil }
        let studio = BarbellStudio(loadout: request.loadout, style: request.style, theme: request.theme)
        if request.shot == .blowup { studio.explode(1) }
        studio.frame(request.shot, aspect: Double(request.width) / Double(request.height))
        renderer.scene = studio.scene
        renderer.pointOfView = studio.cameraNode
        renderer.autoenablesDefaultLighting = false
        let pixels = CGSize(width: Double(request.width) * request.scale, height: Double(request.height) * request.scale)
        let raw = renderer.snapshot(atTime: 0, with: pixels, antialiasingMode: .multisampling4X)
        guard let cg = raw.cgImage else { return raw }
        let image = UIImage(cgImage: cg, scale: CGFloat(request.scale), orientation: .up)
        cache.setObject(image, forKey: Self.key(request))
        renderer.scene = nil
        return image
    }
}

/// A cached studio render sized to its container.
struct StudioImage: View {
    @Environment(\.displayScale) private var displayScale
    let loadout: Loadout
    let style: PlateVisualStyle
    let theme: PlateThemeID
    let shot: StudioShot
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            let request = StudioRenderer.Request(loadout: loadout, style: style, theme: theme, shot: shot,
                                                 width: Int(proxy.size.width.rounded()), height: Int(proxy.size.height.rounded()),
                                                 scale: Double(displayScale))
            ZStack {
                Theme.sceneStudio
                if let shown = image ?? StudioRenderer.shared.cached(request) {
                    Image(uiImage: shown)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            }
            .task(id: request) {
                image = await StudioRenderer.shared.render(request)
            }
        }
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
