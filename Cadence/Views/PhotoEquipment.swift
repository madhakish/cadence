import CadenceCore
import UIKit

/// Product photographs are neutral so the gym's pigment, band, weight and unit
/// can change independently. The reflective insert and steel hardware stay in colour.
enum PhotoEquipment {
    static let stageNames = ["AstraPhotoStage", "AstraPhotoStageWalnut", "AstraPhotoStageWhiteOak", "AstraPhotoStageMaple"]
    static let componentNames = ["PhotoFaceRubber", "PhotoFaceBlackRubber", "PhotoFaceCoated", "PhotoFaceGloss",
                                 "PhotoFaceIron", "PhotoFaceHammertone", "PhotoFaceMachined", "PhotoHub",
                                 "PhotoEdgeRubber", "PhotoEdgeCoated", "PhotoEdgeIron",
                                 "PhotoShaft", "PhotoSleeve", "PhotoShoulder", "PhotoCollar", "PhotoEndcap"]
    // In the reference, a 450 mm circular face is seen as an ellipse.
    static let faceAspect: CGFloat = 0.51
    static let axisRise: CGFloat = 0.115
    static let axialScale: CGFloat = 0.85
    static let shear: CGFloat = -0.047

    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 40 * 1024 * 1024
        return cache
    }()

    static func stage(_ theme: PlateThemeID) -> String {
        switch theme {
        case .ipfCalibrated, .ipfCalibratedGloss: "AstraPhotoStageWalnut"
        case .blackBumpersBand: "AstraPhotoStageWhiteOak"
        case .iwfTraining: "AstraPhotoStageMaple"
        default: "AstraPhotoStage"
        }
    }

    static func surfaces(_ finish: PlateFinish, theme: PlateThemeID) -> (face: String, edge: String) {
        switch finish {
        case .rubber: (theme == .blackBumpersBand || theme == .cadenceHouse ? "PhotoFaceBlackRubber" : "PhotoFaceRubber", "PhotoEdgeRubber")
        case .powder: ("PhotoFaceCoated", "PhotoEdgeCoated")
        case .gloss: ("PhotoFaceGloss", "PhotoEdgeCoated")
        case .castIron: ("PhotoFaceIron", "PhotoEdgeIron")
        case .hammertone: ("PhotoFaceHammertone", "PhotoEdgeIron")
        case .machined: ("PhotoFaceMachined", "PhotoEdgeIron")
        }
    }

    static func format(scale: CGFloat = 1, opaque: Bool = false) -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = opaque
        format.preferredRange = .standard
        return format
    }

    private static func remember(_ image: UIImage, key: String) -> UIImage {
        if let cg = image.cgImage {
            cache.setObject(image, forKey: key as NSString, cost: cg.bytesPerRow * cg.height)
        }
        return image
    }

    private static func painted(_ name: String, rgb: UInt32) -> UIImage? {
        let key = "surface-\(name)-\(rgb)"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        guard let photo = UIImage(named: name) else { return nil }
        let rect = CGRect(origin: .zero, size: photo.size)
        let image = UIGraphicsImageRenderer(size: rect.size, format: format()).image { output in
            photo.draw(in: rect)
            UIColor(rgb: rgb).setFill()
            UIRectFillUsingBlendMode(rect, .sourceIn)
            photo.draw(in: rect, blendMode: .hardLight, alpha: 1)
            // Discs sit under the same warm overhead light as the oak stage.
            UIColor(red: 0.20, green: 0.15, blue: 0.11, alpha: 0.22).setFill()
            output.cgContext.setBlendMode(.sourceAtop)
            output.cgContext.fill(rect)
        }
        return remember(image, key: key)
    }

    private static func lettering(_ text: String, top: Bool, radius: CGFloat, centre: CGFloat,
                                  size: CGFloat, colour: UIColor, context: CGContext) {
        let font = UIFont(name: "AvenirNextCondensed-DemiBold", size: size) ?? UIFont.boldSystemFont(ofSize: size)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
        let chars = text.map { String($0) as NSString }
        let advances = chars.map { $0.size(withAttributes: attributes).width + size * 0.08 }
        var cursor = -advances.reduce(0, +) / 2
        for (char, advance) in zip(chars, advances) {
            let angle = (cursor + advance / 2) / radius
            context.saveGState()
            context.translateBy(x: centre + radius * sin(angle), y: centre + (top ? -1 : 1) * radius * cos(angle))
            context.rotate(by: top ? angle : -angle)
            let box = char.size(withAttributes: attributes)
            char.draw(at: CGPoint(x: -box.width / 2, y: -box.height / 2), withAttributes: attributes)
            context.restoreGState()
            cursor += advance
        }
    }

    /// The front plane is also used for small plate badges. Its hole is actual
    /// transparency, so an exploded disc off the end of a sleeve shows the gym.
    static func face(plate: Plate, theme: PlateThemeID, style: PlateVisualStyle, lettered: Bool) -> UIImage? {
        let key = "face-\(plate.exactKey)-\(theme.rawValue)-\(style.rawValue)-\(lettered)"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        let material = PlateTheme.material(plate, theme: theme, style: style)
        let colour = PlateTheme.colour(plate, theme: theme, style: style)
        let physical = PlateTheme.geometry(plate, theme: theme, style: style)
        let surfaces = surfaces(material.finish, theme: theme)
        guard let photo = painted(surfaces.face, rgb: colour.fill), let hub = UIImage(named: "PhotoHub") else { return nil }
        let diameter: CGFloat = 512
        let centre = diameter / 2
        let rect = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        let image = UIGraphicsImageRenderer(size: rect.size, format: format()).image { output in
            let context = output.cgContext
            photo.draw(in: rect)
            if let band = PlateTheme.band(plate, theme: theme) {
                context.setStrokeColor(UIColor(rgb: band).withAlphaComponent(0.83).cgColor)
                context.setLineWidth(diameter * 0.022)
                context.strokeEllipse(in: rect.insetBy(dx: diameter * 0.063, dy: diameter * 0.063))
            }
            let hubMM = min(150, max(53, physical.diameter * 0.55))
            let hubSize = diameter * hubMM / physical.diameter
            let insert = CGRect(x: centre - hubSize / 2, y: centre - hubSize / 2, width: hubSize, height: hubSize)
            hub.draw(in: insert)
            if PlateTheme.description(theme).hubFinish != .chrome {
                // Keep the photographed reflections through the darker metal finish.
                context.saveGState()
                context.addEllipse(in: insert)
                context.clip()
                context.setFillColor(UIColor.black.withAlphaComponent(0.36).cgColor)
                context.fill(insert)
                context.restoreGState()
            }
            let hole = diameter * 2 * BarbellInspector.boreRadius / physical.diameter
            context.saveGState()
            context.setBlendMode(.clear)
            context.fillEllipse(in: CGRect(x: centre - hole / 2, y: centre - hole / 2, width: hole, height: hole))
            context.restoreGState()
            if lettered {
                let pale = colour.ink == 0xFFFFFF
                let ink = pale ? UIColor(red: 0.89, green: 0.83, blue: 0.70, alpha: 0.95) : UIColor(rgb: colour.ink)
                let radius = centre * 0.70
                context.setShadow(offset: CGSize(width: 0, height: 1.4), blur: 1.1, color: UIColor.black.withAlphaComponent(0.64).cgColor)
                lettering("CADENCE", top: true, radius: radius, centre: centre, size: 39, colour: ink, context: context)
                let text = inspectionPlateLabel(plate).uppercased()
                lettering(text, top: false, radius: radius, centre: centre,
                          size: min(47, 266 / CGFloat(text.count)), colour: ink, context: context)
            }
        }
        return remember(image, key: key)
    }

    /// Local projected bounds relative to the centre of the forward face (in
    /// units of one face diameter). The sidewall physically extends away, to the right.
    static func bounds(depth: CGFloat) -> CGRect {
        let halfWidth = hypot(faceAspect, shear) / 2
        return CGRect(x: -halfWidth, y: -0.5 - axisRise * depth,
                      width: 2 * halfWidth + depth, height: 1 + axisRise * depth)
    }

    static func disc(plate: Plate, theme: PlateThemeID, style: PlateVisualStyle, lettered: Bool = true) -> UIImage? {
        let key = "disc-\(plate.exactKey)-\(theme.rawValue)-\(style.rawValue)-\(lettered)"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        let geo = PlateTheme.geometry(plate, theme: theme, style: style)
        let depth = CGFloat(geo.thickness / geo.diameter) * axialScale
        let surface = surfaces(PlateTheme.material(plate, theme: theme, style: style).finish, theme: theme)
        let colour = PlateTheme.colour(plate, theme: theme, style: style)
        guard let face = face(plate: plate, theme: theme, style: style, lettered: lettered),
              let edge = painted(surface.edge, rgb: colour.fill), let rawEdge = edge.cgImage else { return nil }
        let unit = bounds(depth: depth)
        let diameter: CGFloat = 512
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: ceil(unit.width * diameter), height: ceil(unit.height * diameter)), format: format())
        let image = renderer.image { output in
            let context = output.cgContext
            context.translateBy(x: -unit.minX * diameter, y: -unit.minY * diameter)
            context.scaleBy(x: diameter, y: diameter)
            // Wrap the photographed sidewall around the outline, keeping its
            // axial wear and its light-to-shadow sweep. Only the exposed crescent
            // is visible from this camera. Use overlapping strips to avoid seams.
            let rows = min(256, rawEdge.height)
            for row in 0..<rows {
                let t = (CGFloat(row) + 0.5) / CGFloat(rows)
                let y = t - 0.5
                let x = faceAspect * sqrt(max(0, 0.25 - y * y)) + shear * y
                let crop = CGRect(x: 0, y: CGFloat(row * rawEdge.height / rows), width: CGFloat(rawEdge.width),
                                  height: CGFloat(max(1, rawEdge.height / rows)))
                guard let strip = rawEdge.cropping(to: crop) else { continue }
                context.saveGState()
                context.translateBy(x: x, y: y)
                context.concatenate(CGAffineTransform(a: 1, b: -axisRise, c: 0, d: 1, tx: 0, ty: 0))
                UIImage(cgImage: strip).draw(in: CGRect(x: -0.002, y: -0.6 / CGFloat(rows),
                                                       width: depth + 0.002, height: 1.35 / CGFloat(rows)))
                context.restoreGState()
            }
            context.concatenate(CGAffineTransform(a: faceAspect, b: 0, c: shear, d: 1, tx: 0, ty: 0))
            face.draw(in: CGRect(x: -0.5, y: -0.5, width: 1, height: 1))
        }
        return remember(image, key: key)
    }
}
