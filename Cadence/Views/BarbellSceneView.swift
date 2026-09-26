import CadenceCore
import CoreImage
import Metal
import SceneKit
import SwiftUI
import UIKit

/// A fixed studio view of one sleeve. A tap switches between the assembled
/// front view and the angled inspection; layout and cameras are shared with web.
struct BarbellSceneView: UIViewRepresentable {
    let loadout: Loadout
    let plateStyle: PlateVisualStyle
    let exploded: Bool
    let reduceMotion: Bool

    /// Keep the offline sprite canvas on devices without a Metal renderer.
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
        context.coordinator.apply(exploded: exploded, animated: false, reduceMotion: reduceMotion)
        return view
    }

    func updateUIView(_ view: FittingSceneView, context: Context) {
        context.coordinator.apply(exploded: exploded, animated: true, reduceMotion: reduceMotion)
    }

    func makeCoordinator() -> BarbellSolid { BarbellSolid(loadout: loadout, style: plateStyle) }

    final class FittingSceneView: SCNView {
        var onLayout: ((CGSize) -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?(bounds.size)
        }
    }
}

/// Denominations are equipment identities, not rounded workout totals. Keep
/// custom values such as 0.625 kg intact on the disc and its readable caption.
func inspectionPlateValue(_ plate: Plate) -> String {
    let value = String(plate.value)
    return value.hasSuffix(".0") ? String(value.dropLast(2)) : value
}

func inspectionPlateLabel(_ plate: Plate) -> String {
    "\(inspectionPlateValue(plate)) \(plate.unit.rawValue)"
}

@MainActor
final class BarbellSolid {
    let scene = SCNScene()
    private let loadout: Loadout
    private let style: PlateVisualStyle
    private let cameraNode = SCNNode()
    private var discNodes: [(disc: BarbellInspector.Disc, node: SCNNode, caption: UILabel)] = []
    private var collarNode: SCNNode?
    private var faceTextures: [String: UIImage] = [:]
    private var explodedNow: Bool?
    private var transition = 0
    private var transitioning = false
    private var viewSize = CGSize(width: 390, height: 300)
    private weak var view: SCNView?

    init(loadout: Loadout, style: PlateVisualStyle) {
        self.loadout = loadout
        self.style = style
        build()
    }

    func attach(_ view: BarbellSceneView.FittingSceneView) {
        self.view = view
        view.pointOfView = cameraNode
        view.backgroundColor = UIColor(Theme.sceneStudio)
        for entry in discNodes { view.addSubview(entry.caption) }
        view.onLayout = { [weak self] size in
            guard let self, size != self.viewSize, size.width > 0, size.height > 0 else { return }
            self.viewSize = size
            self.place()
            self.updateCaptions()
        }
    }

    func apply(exploded: Bool, animated: Bool, reduceMotion: Bool) {
        scene.background.contents = UIColor(Theme.sceneStudio)
        view?.backgroundColor = UIColor(Theme.sceneStudio)
        guard exploded != explodedNow else { updateCaptions(); return }
        explodedNow = exploded
        transition += 1
        let currentTransition = transition
        let duration = animated && !reduceMotion ? 0.26 : 0
        transitioning = duration > 0
        for entry in discNodes { entry.caption.isHidden = true }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        SCNTransaction.completionBlock = { [weak self] in
            Task { @MainActor in
                guard let self, self.transition == currentTransition else { return }
                self.transitioning = false
                self.updateCaptions()
            }
        }
        let layout = BarbellInspector.layout(loadout: loadout, style: style, explode: exploded ? 1 : 0)
        for (entry, target) in zip(discNodes, layout.discs.filter { $0.side < 0 }) {
            entry.node.position = SCNVector3(Float(target.centerX), 0, 0)
        }
        collarNode?.position = SCNVector3(Float(layout.collar.left - layout.collar.length / 2), 0, 0)
        place()
        SCNTransaction.commit()
        if duration == 0 { updateCaptions() }
    }

    // A product-photo lens avoids shrinking the far discs in a long stack.
    static let fieldOfView = 8.0

    /// The long lens keeps both authored views natural. The same distance
    /// calculation on web reserves room below the solid for readable captions.
    private func place() {
        let exploded = explodedNow == true
        let camera = BarbellInspector.Camera.initial(exploded: exploded)
        let layout = BarbellInspector.layout(loadout: loadout, style: style, explode: exploded ? 1 : 0)
        let frame = BarbellInspector.frame(layout: layout, explode: exploded ? 1 : 0)
        let aspect = max(0.5, viewSize.width / max(1, viewSize.height))
        let vertical = Self.fieldOfView * Double.pi / 180
        let horizontal = 2 * atan(tan(vertical / 2) * Double(aspect))
        let yaw = camera.yaw * Double.pi / 180
        let reach = frame.halfWidth * abs(sin(yaw)), across = frame.halfWidth * abs(cos(yaw))
        let fitWidth = across * 1.12 / tan(horizontal / 2)
        let fitHeight = layout.maxRadius * (exploded ? 1.35 : 1.7) / tan(vertical / 2)
        let distance = reach + max(fitWidth, fitHeight)
        // Preserve enough depth precision for the face detail above the hub.
        cameraNode.camera?.zNear = max(20, distance * 0.1)
        let eye = camera.position(distance: distance)
        let target = SCNVector3(Float(frame.target.x), Float(frame.target.y), Float(frame.target.z))
        cameraNode.position = SCNVector3(Float(eye.x) + target.x, Float(eye.y) + target.y, Float(eye.z) + target.z)
        cameraNode.look(at: target)
    }

    /// Screen-space text never shrinks with the model. Each physical disc,
    /// including duplicates, owns a caption directly below its projected face.
    private func updateCaptions() {
        guard let view else { return }
        for (disc, node, caption) in discNodes {
            caption.isHidden = explodedNow != true || transitioning
            guard !caption.isHidden else { continue }
            caption.font = UIFontMetrics(forTextStyle: .subheadline)
                .scaledFont(for: .monospacedDigitSystemFont(ofSize: 14, weight: .semibold))
            caption.sizeToFit()
            let point = view.projectPoint(SCNVector3(node.position.x, Float(-disc.radius - 34), 0))
            let width = caption.bounds.width + 14, height = caption.bounds.height + 8
            let x = max(4, min(viewSize.width - width - 4, CGFloat(point.x) - width / 2))
            caption.frame = CGRect(x: x, y: min(viewSize.height - height - 4, CGFloat(point.y)), width: width, height: height)
        }
    }

    private func build() {
        let layout = BarbellInspector.layout(loadout: loadout, style: style, explode: 0)
        let bar = layout.bar
        // One near sleeve with enough shaft to identify the bar. Real sleeve
        // lengths remain unchanged even when the inspection separates plates.
        addCylinder(radius: bar.shaftRadius, length: bar.shaftHalfLength, at: -bar.shaftHalfLength / 2, material: Materials.shaft)
        addCylinder(radius: bar.shaftRadius + 0.12, length: 310, at: -(bar.shaftHalfLength - 205), material: Materials.knurl)
        addCylinder(radius: bar.sleeveRadius, length: bar.sleeveLength, at: -(bar.shaftHalfLength + bar.sleeveLength / 2), material: Materials.chrome)
        addCylinder(radius: bar.shoulderRadius, length: bar.shoulderLength, at: -(bar.shaftHalfLength + bar.shoulderLength / 2), material: Materials.chrome)
        addCylinder(radius: bar.shoulderRadius + 0.15, length: 1.5, at: -bar.shoulderEnd + 3, material: Materials.darkSteel)
        // Fine turned rings catch broad reflections; they are shallow machining,
        // not a knurled sleeve or a row of heavy decorative bands.
        for offset in stride(from: bar.shoulderLength + 5, to: bar.sleeveLength - 3, by: 12) {
            addCylinder(radius: bar.sleeveRadius + 0.04, length: 0.3, at: -(bar.shaftHalfLength + offset), material: Materials.machining)
        }
        let end = -(bar.shaftHalfLength + bar.sleeveLength)
        addCylinder(radius: bar.sleeveRadius - 2, length: 1.5, at: end - 0.5, material: Materials.darkSteel)
        addCylinder(radius: bar.sleeveRadius - 5, length: 1.8, at: end - 0.7, material: Materials.chrome)

        for disc in layout.discs where disc.side < 0 {
            let profile = BarbellInspector.plateProfile(family: disc.family, diameter: disc.radius * 2, thickness: disc.thickness)
            let geometry = Lathe.geometry(profile: profile, segments: 128, hubEdges: 2)
            let colour = PlatePalette.colour(for: disc.plate.colorToken(for: style))
            geometry.materials = [Materials.chrome, Materials.plate(family: disc.family, fill: colour.fill)]
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(Float(disc.centerX), 0, 0)
            let textureKey = "\(disc.family):\(colour.fill):\(disc.radius)"
            if faceTextures[textureKey] == nil {
                faceTextures[textureKey] = PhotographicPlateFace.image(family: disc.family, fill: colour.fill, radius: disc.radius)
            }
            for face in [-1, 1] {
                if let image = faceTextures[textureKey] {
                    node.addChildNode(photographicFace(image: image, disc: disc, face: face))
                }
                node.addChildNode(denomination(for: disc, face: face, ink: colour.ink))
            }
            scene.rootNode.addChildNode(node)
            let caption = UILabel()
            caption.text = inspectionPlateLabel(disc.plate)
            caption.textColor = UIColor(white: 0.96, alpha: 1)
            caption.backgroundColor = UIColor(Theme.sceneStudio).withAlphaComponent(0.94)
            caption.textAlignment = .center
            caption.layer.cornerRadius = 5
            caption.layer.masksToBounds = true
            caption.isUserInteractionEnabled = false
            caption.isAccessibilityElement = false
            caption.isHidden = true
            discNodes.append((disc, node, caption))
        }

        if loadout.collarLb > 0 {
            let half = layout.collar.length / 2, r = layout.collar.radius, bore = BarbellInspector.boreRadius
            let outline: [(Double, Double)] = [(bore, -half), (r - 1.5, -half), (r, -half + 1.5),
                                               (r, half - 1.5), (r - 1.5, half), (bore, half), (bore, -half)]
            let geometry = Lathe.geometry(profile: outline.map { .init(radius: $0.0, axial: $0.1) }, segments: 96)
            geometry.materials = [Materials.collar]
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(Float(layout.collar.left - layout.collar.length / 2), 0, 0)
            // A metal release lever distinguishes the lock from
            // another weight plate without inventing a maker's hardware.
            let lever = SCNBox(width: 32, height: 9, length: 16, chamferRadius: 3)
            lever.firstMaterial = Materials.chrome
            let handle = SCNNode(geometry: lever)
            handle.position = SCNVector3(0, Float(layout.collar.radius + 3), 0)
            node.addChildNode(handle)
            scene.rootNode.addChildNode(node)
            collarNode = node
        }

        scene.background.contents = UIColor(Theme.sceneStudio)
        scene.lightingEnvironment.contents = StudioEnvironment.image()
        scene.lightingEnvironment.intensity = 1.05
        let key = SCNLight()
        key.type = .directional
        key.intensity = 850
        key.castsShadow = true
        key.shadowColor = UIColor.black.withAlphaComponent(0.5)
        key.shadowMode = .deferred
        key.shadowRadius = 18
        key.shadowSampleCount = 32
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.automaticallyAdjustsShadowProjection = true
        key.maximumShadowDistance = 18000
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-Float.pi / 2.6, Float.pi / 6, 0)
        scene.rootNode.addChildNode(keyNode)
        let fill = SCNLight()
        fill.type = .ambient
        fill.intensity = 180
        let fillNode = SCNNode()
        fillNode.light = fill
        scene.rootNode.addChildNode(fillNode)
        let floor = SCNNode(geometry: SCNPlane(width: 30000, height: 12000))
        floor.geometry?.firstMaterial?.lightingModel = .shadowOnly
        floor.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        floor.position = SCNVector3(0, Float(-layout.maxRadius - 2), 0)
        scene.rootNode.addChildNode(floor)

        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(Self.fieldOfView)
        camera.zNear = 20
        camera.zFar = 60000
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
    }

    /// Beveled lathe parts avoid the razor edges of an unmodified cylinder.
    private func cylinder(radius: Double, length: Double, material: SCNMaterial) -> SCNNode {
        let half = length / 2, bevel = min(1.2, min(length / 4, radius / 8))
        let points: [(Double, Double)] = [(0, -half), (radius - bevel, -half), (radius, -half + bevel),
                                         (radius, half - bevel), (radius - bevel, half), (0, half)]
        let geometry = Lathe.geometry(profile: points.map { .init(radius: $0.0, axial: $0.1) }, segments: 96)
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    private func addCylinder(radius: Double, length: Double, at x: Double, material: SCNMaterial) {
        let node = cylinder(radius: radius, length: length, material: material)
        node.position = SCNVector3(Float(x), 0, 0)
        scene.rootNode.addChildNode(node)
    }

    /// The photograph contributes machining and surface grain; the shared
    /// solid still supplies actual diameter, thickness, bore and beveled edges.
    private func photographicFace(image: UIImage, disc: BarbellInspector.Disc, face: Int) -> SCNNode {
        let plane = SCNPlane(width: CGFloat(disc.radius * 2 / 0.97), height: CGFloat(disc.radius * 2 / 0.97))
        let material = SCNMaterial()
        // The texture already contains the studio's illumination. Lighting it
        // again would flatten its photographed highlights and deepen shadows.
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.blendMode = .alpha
        material.transparencyMode = .aOne
        material.writesToDepthBuffer = false
        material.isDoubleSided = false
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.position.x = Float(Double(face) * (disc.thickness / 2 + 1.2))
        node.eulerAngles.y = Float(face) * Float.pi / 2
        node.castsShadow = false
        return node
    }

    /// Original Cadence stamps, without manufacturer or certification marks.
    /// The screen-space caption below each disc is the authoritative readable
    /// denomination; the face print is part of the realistic construction.
    private func denomination(for disc: BarbellInspector.Disc, face: Int, ink: UInt32) -> SCNNode {
        let hub = max(BarbellInspector.boreRadius + 8, disc.radius * (disc.family == "bumper" ? 0.57 : 0.245))
        let rim = disc.radius * 0.86
        let root = SCNNode()
        for (string, y, size) in [(inspectionPlateLabel(disc.plate), -(hub + rim) / 2, (rim - hub) * 0.48),
                                  ("CADENCE", (hub + rim) / 2, (rim - hub) * 0.22)] {
            let text = SCNText(string: string, extrusionDepth: 0)
            text.font = UIFont.systemFont(ofSize: CGFloat(size), weight: .heavy)
            text.flatness = 0.15
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = UIColor(rgb: ink)
            text.materials = [material]
            let node = SCNNode(geometry: text)
            let (minB, maxB) = text.boundingBox
            node.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, 0)
            let scale = min(1, Float(disc.radius * 1.3) / max(1, maxB.x - minB.x))
            node.scale = SCNVector3(scale, scale, scale)
            node.position = SCNVector3(Float(Double(face) * (disc.thickness / 2 + 1.6)), Float(y), 0)
            node.eulerAngles = SCNVector3(0, Float(face) * Float.pi / 2, 0)
            root.addChildNode(node)
        }
        return root
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

/// Decode immutable original face artwork once per denomination. Tint only
/// the coated body, restore the source's chrome, and clip the physical bore.
/// This is runtime rendering; the bundled photographic assets stay unchanged.
@MainActor
private enum PhotographicPlateFace {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func image(family: String, fill: UInt32, radius: Double) -> UIImage? {
        let bumper = family == "bumper"
        guard let source = UIImage(named: bumper ? "PlateBumperFaceDetail" : "PlateSteelFaceDetail")?.cgImage,
              let filter = CIFilter(name: "CIColorMatrix") else { return nil }
        let input = CIImage(cgImage: source)
        filter.setValue(input, forKey: kCIInputImageKey)
        let channels = [Double((fill >> 16) & 255) / 255, Double((fill >> 8) & 255) / 255, Double(fill & 255) / 255]
        for (channel, key) in zip(channels, ["inputRVector", "inputGVector", "inputBVector"]) {
            let gain = channel / 0.5 * 0.93 + 0.07
            filter.setValue(CIVector(x: CGFloat(0.2126 * gain), y: CGFloat(0.7152 * gain), z: CGFloat(0.0722 * gain), w: 0), forKey: key)
        }
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        guard let output = filter.outputImage, let tinted = context.createCGImage(output, from: input.extent) else { return nil }
        let size = CGSize(width: CGFloat(source.width), height: CGFloat(source.height))
        let rect = CGRect(origin: .zero, size: size)
        let sourceRadius = size.width * 0.485
        let hubRadius = sourceRadius * (bumper ? 0.57 : 0.245)
        let boreRadius = sourceRadius * CGFloat(max(0.13, BarbellInspector.boreRadius / radius))
        func circle(_ r: CGFloat) -> CGRect {
            CGRect(x: size.width / 2 - r, y: size.height / 2 - r, width: 2 * r, height: 2 * r)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { output in
            let cg = output.cgContext
            cg.addEllipse(in: circle(sourceRadius))
            cg.addEllipse(in: circle(boreRadius))
            cg.clip(using: .evenOdd)
            UIImage(cgImage: tinted).draw(in: rect)
            cg.addEllipse(in: circle(hubRadius))
            cg.clip()
            UIImage(cgImage: source).draw(in: rect)
        }
    }
}

// MARK: - Materials and studio

@MainActor
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

    static var chrome: SCNMaterial {
        let material = pbr(UIColor(red: 0.72, green: 0.76, blue: 0.8, alpha: 1), metalness: 1, roughness: 0.23)
        material.normal.contents = StudioEnvironment.brushedNormal
        material.normal.wrapS = .repeat
        material.normal.wrapT = .repeat
        material.normal.contentsTransform = SCNMatrix4MakeScale(3, 8, 1)
        return material
    }
    static var shaft: SCNMaterial { pbr(UIColor(white: 0.7, alpha: 1), metalness: 1, roughness: 0.36) }
    static var darkSteel: SCNMaterial { pbr(UIColor(white: 0.19, alpha: 1), metalness: 0.9, roughness: 0.32) }
    static var machining: SCNMaterial { pbr(UIColor(white: 0.64, alpha: 1), metalness: 1, roughness: 0.35) }
    static var collar: SCNMaterial { pbr(UIColor(white: 0.08, alpha: 1), metalness: 0.1, roughness: 0.62) }
    static var knurl: SCNMaterial {
        let material = pbr(UIColor(white: 0.64, alpha: 1), metalness: 1, roughness: 0.5)
        material.normal.contents = StudioEnvironment.knurlNormalMap()
        material.normal.wrapS = .repeat
        material.normal.wrapT = .repeat
        material.normal.contentsTransform = SCNMatrix4MakeScale(24, 4, 1)
        return material
    }

    static func plate(family: String, fill: UInt32) -> SCNMaterial {
        // Colored steel is a painted surface; its exposed insert is the metal.
        let material = pbr(UIColor(rgb: fill), metalness: family == "bumper" ? 0 : 0.08,
                           roughness: family == "bumper" ? 0.68 : 0.36)
        material.normal.contents = StudioEnvironment.grainNormal
        material.normal.intensity = family == "bumper" ? 0.7 : 0.3
        material.normal.wrapS = .repeat
        material.normal.wrapT = .repeat
        material.normal.contentsTransform = SCNMatrix4MakeScale(5, 5, 1)
        return material
    }

}

@MainActor
enum StudioEnvironment {
    static let brushedNormal = surfaceNormalMap(brushed: true)
    static let grainNormal = surfaceNormalMap(brushed: false)

    /// Broad softboxes and a dark horizon produce soft chrome reflections,
    /// with a narrow rim source separating the plate silhouette from the stage.
    static func image() -> UIImage {
        let size = CGSize(width: 1024, height: 512)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let colours = [UIColor(white: 0.65, alpha: 1).cgColor, UIColor(white: 0.26, alpha: 1).cgColor, UIColor(white: 0.07, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours as CFArray, locations: [0, 0.55, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            cg.setShadow(offset: .zero, blur: 18, color: UIColor.white.cgColor)
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(x: 80, y: 42, width: 420, height: 82))
            cg.setFillColor(UIColor(white: 0.87, alpha: 1).cgColor)
            cg.fill(CGRect(x: 670, y: 130, width: 240, height: 128))
            cg.setFillColor(UIColor(white: 0.7, alpha: 1).cgColor)
            cg.fill(CGRect(x: 20, y: 200, width: 22, height: 150))
        }
    }

    /// Deterministic, low-amplitude grain: a directional machining finish for
    /// steel and fine isotropic texture for rubber or powder-coated faces.
    static func surfaceNormalMap(brushed: Bool) -> UIImage {
        let n = 128
        var pixels = [UInt8](repeating: 255, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let phase = Double((x * 73 + y * 151 + x * y * 7) % 251) / 251
                let dx = brushed ? sin(Double(y) * .pi / 4) * 0.025 : sin(phase * .pi * 2) * 0.07
                let dy = brushed ? cos(Double(y) * .pi / 4) * 0.05 : cos(phase * .pi * 6) * 0.07
                let length = (dx * dx + dy * dy + 1).squareRoot()
                let i = (y * n + x) * 4
                pixels[i] = UInt8((dx / length * 0.5 + 0.5) * 255)
                pixels[i + 1] = UInt8((dy / length * 0.5 + 0.5) * 255)
                pixels[i + 2] = UInt8((1 / length * 0.5 + 0.5) * 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return UIImage() }
        return UIImage(cgImage: image)
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
                let dx = (h(x + 1, y) - h(x - 1, y)) * 0.55, dy = (h(x, y + 1) - h(x, y - 1)) * 0.55
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
