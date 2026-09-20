import CadenceCore
import Metal
import SceneKit
import SwiftUI
import UIKit

/// Backdrop presets for the 3D inspector. Colours are theme tokens; the
/// environment intensity and shadow weight follow the backdrop's brightness.
@MainActor
enum BarbellBackdrop: String, CaseIterable, Identifiable {
    case studio, dark, paper
    var id: String { rawValue }
    var label: String {
        switch self {
        case .studio: return "Studio"
        case .dark: return "Dark"
        case .paper: return "Paper"
        }
    }
    var background: UIColor {
        switch self {
        case .studio: return UIColor(Theme.sceneStudio)
        case .dark: return UIColor(Theme.sceneDark)
        case .paper: return UIColor(Theme.scenePaper)
        }
    }
    var environmentIntensity: CGFloat {
        switch self {
        case .studio: return 1.15
        case .dark: return 0.85
        case .paper: return 1.35
        }
    }
    var shadowAlpha: CGFloat { self == .paper ? 0.35 : 0.6 }
}

/// Real-time solid of the loaded bar: orbit by drag, pinch to zoom, animated
/// explode/assemble, a studio light rig with a shadow-catching floor, and
/// backdrop presets. Geometry, explode spacing, and camera state all come from
/// `CadenceCore.BarbellInspector`, so web renders the same solid from the same
/// numbers. Nothing here touches the solver, the loadout, or a store.
struct BarbellSceneView: UIViewRepresentable {
    let loadout: Loadout
    let plateStyle: PlateVisualStyle
    let exploded: Bool
    let backdrop: BarbellBackdrop
    let camera: BarbellInspector.Camera
    let reduceMotion: Bool

    /// SceneKit needs a Metal device; without one (some simulators, audits)
    /// the inspector keeps the sprite canvas.
    static var isSupported: Bool { MTLCreateSystemDefaultDevice() != nil }

    func makeUIView(context: Context) -> FittingSceneView {
        let view = FittingSceneView(frame: .zero)
        view.antialiasingMode = .multisampling4X
        view.isJitteringEnabled = true
        view.rendersContinuously = false
        view.allowsCameraControl = false
        view.isAccessibilityElement = false
        view.scene = context.coordinator.scene
        context.coordinator.attach(view)
        context.coordinator.apply(exploded: exploded, camera: camera, backdrop: backdrop, animated: false, reduceMotion: reduceMotion)
        return view
    }

    func updateUIView(_ view: FittingSceneView, context: Context) {
        context.coordinator.apply(exploded: exploded, camera: camera, backdrop: backdrop, animated: true, reduceMotion: reduceMotion)
    }

    func makeCoordinator() -> BarbellSolid {
        BarbellSolid(loadout: loadout, style: plateStyle)
    }

    /// An SCNView that tells the solid when its bounds change so the camera
    /// refits the whole bar (rotation, split view, Dynamic Type reflow).
    final class FittingSceneView: SCNView {
        var onLayout: ((CGSize) -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?(bounds.size)
        }
    }
}

/// Owns the SceneKit node graph for one loadout.
@MainActor
final class BarbellSolid {
    let scene = SCNScene()
    private let loadout: Loadout
    private let style: PlateVisualStyle
    private let cameraNode = SCNNode()
    private let keyLight = SCNLight()
    private let floor = SCNNode()
    private var discNodes: [(disc: BarbellInspector.Disc, node: SCNNode)] = []
    private var collarNodes: [SCNNode] = []
    private var explodedNow: Bool?
    private var cameraNow: BarbellInspector.Camera?
    private var backdropNow: BarbellBackdrop?
    private var viewSize = CGSize(width: 390, height: 260)
    private weak var view: SCNView?

    init(loadout: Loadout, style: PlateVisualStyle) {
        self.loadout = loadout
        self.style = style
        build()
    }

    func attach(_ view: BarbellSceneView.FittingSceneView) {
        self.view = view
        view.onLayout = { [weak self] size in
            guard let self, size != self.viewSize, size.width > 0 else { return }
            self.viewSize = size
            if let camera = self.cameraNow { self.place(camera: camera) }
        }
    }

    // MARK: - State

    func apply(exploded: Bool, camera: BarbellInspector.Camera, backdrop: BarbellBackdrop, animated: Bool, reduceMotion: Bool) {
        if backdrop != backdropNow {
            backdropNow = backdrop
            scene.background.contents = backdrop.background
            scene.lightingEnvironment.intensity = backdrop.environmentIntensity
            keyLight.shadowColor = UIColor.black.withAlphaComponent(backdrop.shadowAlpha)
            view?.backgroundColor = backdrop.background
        }
        let explodeChanged = exploded != explodedNow
        explodedNow = exploded
        cameraNow = camera
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated && explodeChanged && !reduceMotion ? 0.42 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        if explodeChanged {
            let layout = BarbellInspector.layout(loadout: loadout, style: style, explode: exploded ? 1 : 0)
            for (disc, node) in discNodes {
                if let target = layout.discs.first(where: { $0.side == disc.side && $0.index == disc.index }) {
                    node.position = SCNVector3(Float(target.centerX), 0, 0)
                }
            }
            let half = Float(layout.collar.length / 2)
            collarNodes.first?.position = SCNVector3(Float(layout.collar.left) - half, 0, 0)
            collarNodes.last?.position = SCNVector3(Float(layout.collar.right) + half, 0, 0)
        }
        place(camera: camera)
        SCNTransaction.commit()
    }

    /// Fit the whole bar at zoom 1 for the view's aspect, then orbit.
    private func place(camera: BarbellInspector.Camera) {
        let layout = BarbellInspector.layout(loadout: loadout, style: style, explode: explodedNow == true ? 1 : 0)
        let aspect = max(0.5, viewSize.width / max(1, viewSize.height))
        let vertical = 30.0 * Double.pi / 180
        let horizontal = 2 * atan(tan(vertical / 2) * Double(aspect))
        let fitWidth = layout.extent * 1.12 / tan(horizontal / 2)
        let fitHeight = layout.maxRadius * 1.6 / tan(vertical / 2)
        let eye = camera.position(distance: max(fitWidth, fitHeight))
        cameraNode.position = SCNVector3(Float(eye.x), Float(eye.y), Float(eye.z))
        cameraNode.look(at: SCNVector3(0, 0, 0))
    }

    // MARK: - Build

    private func build() {
        let layout = BarbellInspector.layout(loadout: loadout, style: style, explode: 0)
        let bar = layout.bar

        // Bar: shaft, knurl bands, shoulders, sleeves.
        addCylinder(radius: bar.shaftRadius, length: bar.shaftHalfLength * 2, at: 0, material: Materials.shaft)
        for side in [-1.0, 1.0] {
            addCylinder(radius: bar.shaftRadius + 0.15, length: 310, at: side * (bar.shaftHalfLength - 190), material: Materials.knurl)
            addCylinder(radius: bar.sleeveRadius, length: bar.sleeveLength, at: side * (bar.shaftHalfLength + bar.sleeveLength / 2), material: Materials.chrome)
            addCylinder(radius: bar.shoulderRadius, length: bar.shoulderLength, at: side * (bar.shaftHalfLength + bar.shoulderLength / 2), material: Materials.chrome)
        }

        // Plates: one lathe per disc from the shared profile, colour from the
        // shared palette, denomination printed on the outward face.
        for disc in layout.discs {
            let profile = BarbellInspector.plateProfile(family: disc.family, diameter: disc.radius * 2, thickness: disc.thickness)
            // The first two profile edges on each face are the chrome hub
            // insert; the lathe keeps them as their own element and material.
            let geometry = Lathe.geometry(profile: profile, segments: 96, hubEdges: 2)
            let colour = PlatePalette.colour(for: disc.plate.colorToken(for: style))
            geometry.materials = [Materials.chrome, Materials.plate(family: disc.family, fill: colour.fill)]
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(Float(disc.centerX), 0, 0)
            node.addChildNode(denomination(for: disc, ink: colour.ink))
            scene.rootNode.addChildNode(node)
            discNodes.append((disc, node))
        }

        // Lock collars, only when the loadout has them.
        if loadout.collarLb > 0 {
            let half = layout.collar.length / 2
            for x in [layout.collar.left - half, layout.collar.right + half] {
                let node = cylinder(radius: layout.collar.radius, length: layout.collar.length, material: Materials.collar)
                node.position = SCNVector3(Float(x), 0, 0)
                scene.rootNode.addChildNode(node)
                collarNodes.append(node)
            }
        }

        // Studio rig: image-based light for reflections, a key light for the
        // shadow, a soft fill, and a floor that only catches the shadow.
        scene.lightingEnvironment.contents = StudioEnvironment.image()
        keyLight.type = .directional
        keyLight.intensity = 900
        keyLight.castsShadow = true
        keyLight.shadowMode = .deferred
        keyLight.shadowRadius = 14
        keyLight.shadowSampleCount = 24
        keyLight.shadowMapSize = CGSize(width: 2048, height: 2048)
        keyLight.automaticallyAdjustsShadowProjection = true
        keyLight.maximumShadowDistance = 12000
        let keyNode = SCNNode()
        keyNode.light = keyLight
        keyNode.eulerAngles = SCNVector3(-Float.pi / 2.6, Float.pi / 6, 0)
        scene.rootNode.addChildNode(keyNode)
        let fill = SCNLight()
        fill.type = .ambient
        fill.intensity = 220
        let fillNode = SCNNode()
        fillNode.light = fill
        scene.rootNode.addChildNode(fillNode)
        floor.geometry = SCNPlane(width: 12000, height: 12000)
        floor.geometry?.firstMaterial?.lightingModel = .shadowOnly
        floor.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        floor.position = SCNVector3(0, Float(-layout.maxRadius - 2), 0)
        scene.rootNode.addChildNode(floor)

        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 20
        camera.zFar = 40000
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
    }

    private func cylinder(radius: Double, length: Double, material: SCNMaterial) -> SCNNode {
        let geometry = SCNCylinder(radius: CGFloat(radius), height: CGFloat(length))
        geometry.radialSegmentCount = 72
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.eulerAngles = SCNVector3(0, 0, Float.pi / 2)   // SCNCylinder is y-up; the bar runs along x
        return node
    }

    private func addCylinder(radius: Double, length: Double, at x: Double, material: SCNMaterial) {
        let node = cylinder(radius: radius, length: length, material: material)
        node.position = SCNVector3(Float(x), 0, 0)
        scene.rootNode.addChildNode(node)
    }

    /// The plate value as flat printed text on the outward face, sized to the
    /// annulus between hub and rim; unit and count stay in the list below.
    private func denomination(for disc: BarbellInspector.Disc, ink: UInt32) -> SCNNode {
        let radius = disc.radius
        let hub = disc.family == "bumper" ? 0.235 * radius : disc.family == "steel" ? 0.2 * radius : max(BarbellInspector.boreRadius + 8, 0.25 * radius)
        let rim = disc.family == "bumper" ? 0.9 * radius : disc.family == "steel" ? 0.86 * radius : radius
        let size = (rim - hub) * 0.32 / 0.7
        let text = SCNText(string: Weight.trim(disc.plate.value, decimals: 2), extrusionDepth: 0)
        text.font = UIFont.systemFont(ofSize: CGFloat(size), weight: .heavy)
        text.flatness = 0.15
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(rgb: ink)
        material.readsFromDepthBuffer = true
        text.materials = [material]
        let node = SCNNode(geometry: text)
        let (minB, maxB) = text.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, 0)
        let faceOffset = disc.family == "bumper" ? disc.thickness / 2 - 0.14 * disc.thickness : disc.thickness / 2
        node.position = SCNVector3(Float(Double(disc.side) * (faceOffset + 0.4)), Float((hub + rim) / 2), 0)
        node.eulerAngles = SCNVector3(0, Float(disc.side) * Float.pi / 2, 0)
        return node
    }
}

// MARK: - Geometry

/// Revolves a shared profile around the bar (x) axis. Every profile edge gets
/// its own ring pair with the edge normal, so rims and recesses stay crisp.
/// The first and last `hubEdges` edges form a second element (the hub insert)
/// so it can carry its own material.
enum Lathe {
    static func geometry(profile: [BarbellInspector.ProfilePoint], segments: Int, hubEdges: Int = 0) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var hubIndices: [Int32] = []
        var bodyIndices: [Int32] = []
        let edges = Array(zip(profile, profile.dropFirst()))
        let total = edges.reduce(0.0) { $0 + hypot($1.1.radius - $1.0.radius, $1.1.axial - $1.0.axial) }
        var travelled = 0.0
        for (k, (a, b)) in edges.enumerated() {
            let dr = b.radius - a.radius, dx = b.axial - a.axial
            let length = hypot(dr, dx)
            guard length > 0 else { continue }
            let isHub = k < hubEdges || k >= edges.count - hubEdges
            let nr = dx / length, nx = -dr / length     // outward edge normal in the (radius, axial) plane
            let base = Int32(vertices.count)
            for (point, v) in [(a, travelled / total), (b, (travelled + length) / total)] {
                for j in 0...segments {
                    let theta = Double(j) / Double(segments) * 2 * Double.pi
                    let c = cos(theta), s = sin(theta)
                    vertices.append(SCNVector3(Float(point.axial), Float(point.radius * c), Float(point.radius * s)))
                    normals.append(SCNVector3(Float(nx), Float(nr * c), Float(nr * s)))
                    uvs.append(CGPoint(x: Double(j) / Double(segments), y: v))
                }
            }
            let ring = Int32(segments + 1)
            for j in 0..<Int32(segments) {
                let i0 = base + j, i1 = i0 + 1, i2 = base + ring + j, i3 = i2 + 1
                if isHub { hubIndices += [i0, i2, i1, i1, i2, i3] } else { bodyIndices += [i0, i2, i1, i1, i2, i3] }
            }
            travelled += length
        }
        var elements = [SCNGeometryElement(indices: bodyIndices, primitiveType: .triangles)]
        if !hubIndices.isEmpty { elements.insert(SCNGeometryElement(indices: hubIndices, primitiveType: .triangles), at: 0) }
        return SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: uvs)],
            elements: elements
        )
    }
}

// MARK: - Materials and studio

enum Materials {
    static func pbr(_ colour: UIColor, metalness: Double, roughness: Double) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = colour
        material.metalness.contents = NSNumber(value: metalness)
        material.roughness.contents = NSNumber(value: roughness)
        material.isDoubleSided = true
        return material
    }

    static var chrome: SCNMaterial { pbr(UIColor(white: 0.92, alpha: 1), metalness: 1, roughness: 0.22) }
    static var shaft: SCNMaterial { pbr(UIColor(white: 0.78, alpha: 1), metalness: 1, roughness: 0.4) }
    static var collar: SCNMaterial { pbr(UIColor(white: 0.16, alpha: 1), metalness: 0.4, roughness: 0.55) }
    static var knurl: SCNMaterial {
        let material = pbr(UIColor(white: 0.7, alpha: 1), metalness: 1, roughness: 0.58)
        material.normal.contents = StudioEnvironment.knurlNormalMap()
        material.normal.wrapS = .repeat
        material.normal.wrapT = .repeat
        material.normal.contentsTransform = SCNMatrix4MakeScale(28, 3, 1)
        return material
    }

    static func plate(family: String, fill: UInt32) -> SCNMaterial {
        switch family {
        case "bumper": return pbr(UIColor(rgb: fill), metalness: 0, roughness: 0.62)
        case "change": return pbr(UIColor(rgb: fill), metalness: 0.75, roughness: 0.38)
        default: return pbr(UIColor(rgb: fill), metalness: 0.35, roughness: 0.5)
        }
    }

}

enum StudioEnvironment {
    /// Equirectangular studio: dark floor, mid horizon, a bright overhead
    /// softbox band, and two side softboxes — the same rig the sprites used.
    static func image() -> UIImage {
        let size = CGSize(width: 512, height: 256)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let colours = [UIColor(white: 0.82, alpha: 1).cgColor, UIColor(white: 0.34, alpha: 1).cgColor, UIColor(white: 0.1, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours as CFArray, locations: [0, 0.55, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            cg.setFillColor(UIColor(white: 1, alpha: 0.95).cgColor)
            cg.fill(CGRect(x: 0, y: size.height * 0.1, width: size.width, height: size.height * 0.09))
            cg.setFillColor(UIColor(white: 0.97, alpha: 0.9).cgColor)
            cg.fill(CGRect(x: size.width * 0.12, y: size.height * 0.3, width: size.width * 0.12, height: size.height * 0.22))
            cg.fill(CGRect(x: size.width * 0.76, y: size.height * 0.3, width: size.width * 0.12, height: size.height * 0.22))
        }
    }

    /// A tileable diamond-knurl normal map from a drawn height field.
    static func knurlNormalMap() -> UIImage {
        let n = 64
        let height = UIGraphicsImageRenderer(size: CGSize(width: n, height: n)).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: n, height: n))
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(2.2)
            for k in stride(from: -n, through: 2 * n, by: 8) {
                cg.move(to: CGPoint(x: k, y: 0)); cg.addLine(to: CGPoint(x: k + n, y: n))
                cg.move(to: CGPoint(x: k + n, y: 0)); cg.addLine(to: CGPoint(x: k, y: n))
            }
            cg.strokePath()
        }
        guard let source = height.cgImage else { return height }
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let read = CGContext(data: &pixels, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: space,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return height }
        read.draw(source, in: CGRect(x: 0, y: 0, width: n, height: n))
        func h(_ x: Int, _ y: Int) -> Double { Double(pixels[(((y + n) % n) * n + ((x + n) % n)) * 4]) / 255 }
        var out = [UInt8](repeating: 255, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let dx = (h(x + 1, y) - h(x - 1, y)) * 1.6, dy = (h(x, y + 1) - h(x, y - 1)) * 1.6
                let length = (dx * dx + dy * dy + 1).squareRoot()
                let i = (y * n + x) * 4
                out[i] = UInt8((-dx / length * 0.5 + 0.5) * 255)
                out[i + 1] = UInt8((-dy / length * 0.5 + 0.5) * 255)
                out[i + 2] = UInt8((1 / length * 0.5 + 0.5) * 255)
            }
        }
        // The provider owns a copy of the bytes, so the image outlives `out`.
        guard let provider = CGDataProvider(data: Data(out) as CFData),
              let normal = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4, space: space,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return height }
        return UIImage(cgImage: normal)
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
