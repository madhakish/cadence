import CadenceCore
import UIKit

/// Projects the physical layout onto the camera and floor in Astra study 03.
/// Coordinates in the calibration photograph are pixels of its 1672 × 941 master.
struct PhotographicBar {
    private let style: PlateVisualStyle
    private let theme: PlateThemeID
    private let size: CGSize
    private let progress: CGFloat
    private let caption: CGFloat
    private let layout: BarbellInspector.Layout
    private let expanded: BarbellInspector.Layout
    private let restingRadius: CGFloat
    private let stage: CGRect
    private let heroStage: CGRect
    private let explosionScale: CGFloat
    private let explosionAxisScale: CGFloat
    private let explosionOrigin: CGPoint
    static let referenceSize = CGSize(width: 1672, height: 941)

    private struct Pose {
        var centre: CGPoint
        var scale: CGFloat
    }

    init(loadout: Loadout, style: PlateVisualStyle, theme: PlateThemeID, size: CGSize, shot: StudioShot,
         progress: CGFloat, captionSize: CGFloat = 14) {
        self.theme = theme
        self.style = style
        self.size = size
        self.caption = captionSize
        self.layout = BarbellInspector.layout(loadout: loadout, style: style, explode: 0, theme: theme)
        self.expanded = BarbellInspector.layout(loadout: loadout, style: style, explode: 1, theme: theme)
        let near = expanded.discs.filter { $0.side < 0 }
        self.progress = near.isEmpty ? 0 : min(1, max(0, progress))
        let restingRadius = max(layout.bar.shoulderRadius, layout.collar.radius, layout.discs.map(\.radius).max() ?? 0)

        self.restingRadius = restingRadius

        let extent = max(layout.extent, layout.bar.shoulderEnd + layout.bar.sleeveLength)
        let leftDisc = layout.discs.min { $0.centerX < $1.centerX }
        let rightDisc = layout.discs.max { $0.centerX < $1.centerX }
        let left = min(Self.reference(-extent).centre.x,
                       leftDisc.map { Self.reference($0.centerX).centre.x - $0.radius * Self.reference($0.centerX).scale * 0.54 } ?? 0)
        let right = max(Self.reference(extent).centre.x,
                        rightDisc.map { Self.reference($0.centerX).centre.x + $0.radius * Self.reference($0.centerX).scale * 0.54 } ?? 1672)
        let frameLeft = min(0, left - 24), frameRight = max(1672, right + 24)
        let scale = min(size.width / (frameRight - frameLeft), size.height / (shot == .row ? 538 : 790))
        let centreY: CGFloat = shot == .row ? 442 + (225 - restingRadius) * 0.65 : 470.5
        heroStage = CGRect(x: size.width / 2 - (frameLeft + frameRight) / 2 * scale,
                           y: size.height / 2 - centreY * scale, width: Self.referenceSize.width * scale, height: Self.referenceSize.height * scale)

        let availableHeight = max(1, size.height - Self.captionHeight(captionSize))
        let slot = max(1, (size.width - 24) / CGFloat(max(1, near.count)))
        // A cell fits both the widest physical disc and its projected sidewall.
        let maxRatio = near.map {
            (PhotoEquipment.faceAspect + PhotoEquipment.axialScale * $0.thickness / (2 * $0.radius)) * $0.radius / restingRadius
        }.max() ?? 1
        let diameter = max(1, min(availableHeight * 0.77, slot * 0.82 / maxRatio))
        explosionScale = diameter / (2 * restingRadius)
        let first = near.first?.centerX ?? -740, last = near.last?.centerX ?? first
        let spacing = near.count > 1 ? slot * CGFloat(near.count - 1) / CGFloat(first - last) : explosionScale * 0.88
        explosionAxisScale = spacing
        let anchorX = size.width / 2 - (first + last) / 2 * spacing
        explosionOrigin = CGPoint(x: anchorX, y: availableHeight * 0.50)
        let focusScale = max(size.width / Self.referenceSize.width, size.height / Self.referenceSize.height, diameter / 409)
        let focusWidth = Self.referenceSize.width * focusScale, focusHeight = Self.referenceSize.height * focusScale
        let focusX = min(0, max(size.width - focusWidth, size.width * 0.60 - 357 * focusScale))
        let focusY = min(0, max(size.height - focusHeight, availableHeight * 0.50 + diameter * 0.50 - 650 * focusScale))
        stage = Self.interpolate(heroStage, CGRect(x: focusX, y: focusY, width: focusWidth, height: focusHeight), self.progress)
    }

    // Perspective interpolates the two observed plate diameters. Outside the
    // reference sleeves, continue along the end tangent for over-capacity loads.
    private static func reference(_ x: CGFloat) -> Pose {
        let k: CGFloat = 409.0 / 321 - 1
        let t = (min(1120, max(-1120, x)) + 765) / 1470
        let denominator = 1 + k * t
        let scale: CGFloat = 409 / 450 / denominator
        // Calibrate the measured sleeve endpoints separately. The dimensions
        // describe Cadence's real bar, while the photograph is the camera plate.
        if x < -765 {
            let t = (x + 765) / 355
            return Pose(centre: CGPoint(x: 357 + 291 * t, y: 446 - 34 * t), scale: scale)
        }
        if x > 705 {
            let t = (x - 705) / 415
            return Pose(centre: CGPoint(x: 1351 + 199 * t, y: 332 - 17 * t), scale: scale)
        }
        let u = t * (1 + k) / denominator
        return Pose(centre: CGPoint(x: 357 + 994 * u, y: 446 - 114 * u), scale: scale)
    }

    private static func interpolate(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }

    private static func captionHeight(_ size: CGFloat) -> CGFloat {
        UIFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold).lineHeight + 12
    }

    private func pose(_ x: CGFloat, expandedX: CGFloat) -> Pose {
        let original = Self.reference(x)
        let scale = heroStage.width / room.width
        let hero = CGPoint(x: heroStage.minX + original.centre.x * scale,
                           y: heroStage.minY + (original.centre.y + (225 - restingRadius) * original.scale) * scale)
        let focusX = explosionOrigin.x + expandedX * explosionAxisScale
        // On a very long scrolling canvas, keep the floor and captions in frame.
        let slope = min(PhotoEquipment.axisRise, size.height * 0.17 / max(1, size.width))
        let focusY = explosionOrigin.y - (focusX - size.width / 2) * slope
        return Pose(centre: CGPoint(x: hero.x + (focusX - hero.x) * progress, y: hero.y + (focusY - hero.y) * progress),
                    scale: original.scale * scale + (explosionScale - original.scale * scale) * progress)
    }

    struct ProjectedPlate {
        let disc: BarbellInspector.Disc
        let centre: CGPoint
        let diameter: CGFloat
        let aspect: CGFloat
        let bounds: CGRect
    }

    /// Also consumed by the lab's framing assertions and the inspector captions.
    var projectedPlates: [ProjectedPlate] {
        zip(layout.discs, expanded.discs).map { disc, loose in
            let position = pose(disc.centerX - disc.thickness / 2, expandedX: loose.centerX - loose.thickness / 2)
            let diameter = 2 * disc.radius * position.scale
            // The far near-facing ellipse opens up as the sight line moves
            // along the bar (measured 0.55 and 0.72 in the source photograph).
            let aspect = (100 * (0.55 + 0.17 * min(1, max(0, (disc.centerX + 765) / 1470)))).rounded() / 100
            let unit = PhotoEquipment.bounds(depth: PhotoEquipment.axialScale * disc.thickness / (2 * disc.radius), aspect: aspect)
            let rect = CGRect(x: position.centre.x + unit.minX * diameter, y: position.centre.y + unit.minY * diameter,
                              width: unit.width * diameter, height: unit.height * diameter)
            return ProjectedPlate(disc: disc, centre: position.centre, diameter: diameter, aspect: aspect, bounds: rect)
        }
    }

    static func snapshot(_ request: StudioRenderer.Request) -> UIImage? {
        guard UIImage(named: PhotoEquipment.stage(request.theme)) != nil else { return nil }
        let size = CGSize(width: request.width, height: request.height)
        let scene = PhotographicBar(loadout: request.loadout, style: request.style, theme: request.theme,
                                    size: size, shot: request.shot, progress: request.shot == .blowup ? 1 : 0)
        return UIGraphicsImageRenderer(size: size, format: PhotoEquipment.format(scale: request.scale, opaque: true))
            .image { scene.draw(in: $0.cgContext) }
    }

    private func drawStage() {
        guard let background = UIImage(named: PhotoEquipment.stage(theme)) else { return }
        let frame = CGRect(origin: .zero, size: size)
        if !stage.contains(frame) {
            // Very wide rows and intermediate inspector poses can extend beyond
            // the photographed aperture. Keep those margins optically neutral.
            UIColor(white: 0.055, alpha: 1).setFill()
            UIRectFill(frame)
        }
        background.draw(in: stage)
    }

    private static let shadowGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [UIColor.black.withAlphaComponent(0.72).cgColor, UIColor.black.withAlphaComponent(0.27).cgColor,
                 UIColor.clear.cgColor] as CFArray, locations: [0, 0.48, 1])!

    private func shadow(_ context: CGContext, at centre: CGPoint, width: CGFloat, height: CGFloat, opacity: CGFloat) {
        guard width > 0, height > 0 else { return }
        context.saveGState()
        context.setAlpha(opacity)
        context.translateBy(x: centre.x, y: centre.y)
        context.rotate(by: -0.075)
        context.scaleBy(x: width / 2, y: height / 2)
        context.drawRadialGradient(Self.shadowGradient, startCenter: .zero, startRadius: 0, endCenter: .zero,
                                   endRadius: 1, options: [])
        context.restoreGState()
    }

    private func segment(_ context: CGContext, from start: CGFloat, to end: CGFloat, radius: CGFloat,
                         image: UIImage, fullStart: CGFloat, fullEnd: CGFloat, reversed: Bool = false) {
        // A full segment photograph is mapped only once along its length. When
        // occlusion splits it, clipped intervals retain the exact same knurling.
        let a = pose(fullStart, expandedX: fullStart), b = pose(fullEnd, expandedX: fullEnd)
        let low = pose(start, expandedX: start).centre, high = pose(end, expandedX: end).centre
        let dx = b.centre.x - a.centre.x, dy = b.centre.y - a.centre.y
        let length = hypot(dx, dy)
        guard length > 0.01 else { return }
        let angle = atan2(dy, dx)
        let startFraction = (low.x - a.centre.x) / dx, endFraction = (high.x - a.centre.x) / dx
        let maximum = 2 * radius * max(a.scale, b.scale)
        context.saveGState()
        context.translateBy(x: a.centre.x, y: a.centre.y)
        context.rotate(by: angle)
        context.clip(to: CGRect(x: startFraction * length - 0.3, y: -maximum,
                                width: (endFraction - startFraction) * length + 0.6, height: 2 * maximum))
        // The far sleeve has the same product with its outer end facing right.
        // Slice the continuous photograph to taper with perspective, retaining
        // the polished griplines at their measured positions along the shaft.
        let slices = max(1, min(12, Int(ceil(length / 24))))
        for index in 0..<slices {
            let t = (CGFloat(index) + 0.5) / CGFloat(slices)
            guard t + 0.5 / CGFloat(slices) >= startFraction, t - 0.5 / CGFloat(slices) <= endFraction else { continue }
            let diameter = 2 * radius * (a.scale + (b.scale - a.scale) * t)
            context.saveGState()
            context.clip(to: CGRect(x: CGFloat(index) * length / CGFloat(slices) - 0.25, y: -maximum,
                                    width: length / CGFloat(slices) + 0.5, height: 2 * maximum))
            if reversed {
                context.translateBy(x: length, y: 0)
                context.scaleBy(x: -1, y: 1)
            }
            image.draw(in: CGRect(x: 0, y: -diameter / 2, width: length, height: diameter))
            context.restoreGState()
        }
        context.restoreGState()
    }

    private func drawBar(_ context: CGContext, from front: CGFloat, to back: CGFloat) {
        let bar = layout.bar, tip = bar.shoulderEnd + bar.sleeveLength
        let segments = [(-tip, -bar.shoulderEnd, bar.sleeveRadius, "PhotoSleeve"),
                        (-bar.shoulderEnd, -bar.shaftHalfLength, bar.shoulderRadius, "PhotoShoulder"),
                        (-bar.shaftHalfLength, bar.shaftHalfLength, bar.shaftRadius, "PhotoShaft"),
                        (bar.shaftHalfLength, bar.shoulderEnd, bar.shoulderRadius, "PhotoShoulder"),
                        (bar.shoulderEnd, tip, bar.sleeveRadius, "PhotoSleeve")]
        for (a, b, radius, name) in segments {
            let start = max(front, a), end = min(back, b)
            guard end > start else { continue }
            let black = name == "PhotoShaft" && PlateTheme.description(theme).barFinish == .blackOxide
            guard let image = PhotoEquipment.hardware(name, darkened: black) else { continue }
            segment(context, from: start, to: end, radius: radius, image: image, fullStart: a, fullEnd: b, reversed: a > 0)
        }
        // Only the near end looks into the camera. This is the outer Olympic
        // endcap, never a hub/plug repeated on every plate.
        if front <= -tip && back > -tip, let endcap = UIImage(named: "PhotoEndcap") {
            let p = pose(-tip, expandedX: -tip)
            let height = 2 * bar.sleeveRadius * p.scale
            endcap.draw(in: CGRect(x: p.centre.x - height * 0.25, y: p.centre.y - height / 2,
                                   width: height * 0.5, height: height))
        }
    }

    private func drawCollar(at x: CGFloat, expandedX: CGFloat, context: CGContext) {
        let front = pose(x, expandedX: expandedX)
        let back = pose(x + layout.collar.length, expandedX: expandedX + layout.collar.length)
        let near = x < 0
        let rearX = x + (near ? layout.collar.length : 0) + (expandedX - x) * progress
        let tip = layout.bar.shoulderEnd + layout.bar.sleeveLength
        if abs(rearX) < tip, let lock = UIImage(named: "PhotoLock") {
            let anchor = near ? back : front
            let width = PhotoEquipment.lockWidthMM * anchor.scale
            let height = PhotoEquipment.lockHeightMM * anchor.scale
            context.saveGState()
            context.translateBy(x: anchor.centre.x, y: anchor.centre.y)
            if !near {
                context.concatenate(CGAffineTransform(a: -1, b: 2 * PhotoEquipment.axisRise, c: 0, d: 1, tx: 0, ty: 0))
            }
            lock.draw(in: CGRect(x: -width * PhotoEquipment.lockRearAnchor.x, y: -height * PhotoEquipment.lockRearAnchor.y, width: width, height: height))
            context.restoreGState()
            return
        }
        // Once the clamp is clear of the shaft, show the entire open aperture.
        guard let collar = UIImage(named: "PhotoCollar") else { return }
        let height = layout.collar.radius * 2 * front.scale
        let width = max(height * 0.30, back.centre.x - front.centre.x) + height * 0.40
        context.saveGState()
        context.translateBy(x: front.centre.x, y: front.centre.y)
        context.rotate(by: -atan(PhotoEquipment.axisRise))
        collar.draw(in: CGRect(x: -width * 0.34, y: -height * 0.54, width: width, height: height))
        context.restoreGState()
    }

    private func drawCaption(_ item: ProjectedPlate, context: CGContext) {
        let text = inspectionPlateLabel(item.disc.plate) as NSString
        let font = UIFont.monospacedDigitSystemFont(ofSize: caption, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let label = text.size(withAttributes: attributes)
        let width = min(size.width, label.width + 12), height = label.height + 6
        let x = min(size.width - width, max(0, item.centre.x - width / 2))
        let y = min(size.height - height - 2, item.bounds.maxY + 5)
        context.saveGState()
        context.setAlpha((progress - 0.85) / 0.15)
        UIColor(white: 0.055, alpha: 0.86).setFill()
        UIBezierPath(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: 4).fill()
        text.draw(at: CGPoint(x: x + (width - label.width) / 2, y: y + 3), withAttributes: attributes)
        context.restoreGState()
    }

    func draw(in context: CGContext) {
        guard size.width > 0, size.height > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.interpolationQuality = .high
        drawStage()
        let plates = projectedPlates
        let tip = layout.bar.shoulderEnd + layout.bar.sleeveLength
        let nearAxis = pose(-tip, expandedX: -tip), farAxis = pose(tip, expandedX: tip)
        let floorMiddle = CGPoint(x: (nearAxis.centre.x + farAxis.centre.x) / 2,
                                  y: (nearAxis.centre.y + farAxis.centre.y + (nearAxis.scale + farAxis.scale) * restingRadius) / 2)
        shadow(context, at: floorMiddle, width: farAxis.centre.x - nearAxis.centre.x,
               height: max(3, 30 * nearAxis.scale), opacity: plates.isEmpty ? 0.72 : 0.35)
        for item in plates {
            let scale = item.diameter / (item.disc.radius * 2)
            let foot = CGPoint(x: item.centre.x + PhotoEquipment.shear * item.diameter / 2,
                               y: item.centre.y + restingRadius * scale)
            let reach = item.disc.radius / restingRadius
            shadow(context, at: CGPoint(x: foot.x - item.diameter * 0.22, y: foot.y + item.diameter * 0.067),
                   width: item.diameter * 1.07, height: item.diameter * 0.27, opacity: 0.87 * reach)
            if reach > 0.98 {
                shadow(context, at: CGPoint(x: foot.x - item.diameter * 0.10, y: foot.y + item.diameter * 0.020),
                       width: item.diameter * 0.87, height: item.diameter * 0.13, opacity: 0.90)
                shadow(context, at: foot, width: item.diameter * 0.38, height: item.diameter * 0.05, opacity: 1)
            }
        }

        // The photographed metal is continuous behind every perforated hub.
        // Repaint only the visible spans during the depth pass below. This
        // underlay is what shows through a bore on a plate still on a sleeve.
        drawBar(context, from: -tip, to: tip)

        // Paint back-to-front along the axis. A plate occupies a physical
        // interval; the sleeve resumes in front of its bore, and its shaft can
        // never appear painted across a closer disc. Separated plates can
        // travel beyond the endcap, exposing the room through their holes.
        struct Layer {
            let front: CGFloat
            let back: CGFloat
            let assembled: CGFloat
            let plate: ProjectedPlate?
        }
        var layers: [Layer] = zip(plates, expanded.discs).map { item, loose in
            let centre = item.disc.centerX + (loose.centerX - item.disc.centerX) * progress
            return Layer(front: centre - item.disc.thickness / 2, back: centre + item.disc.thickness / 2,
                         assembled: item.disc.centerX - item.disc.thickness / 2, plate: item)
        }
        if layout.collar.length > 0 {
            for (compact, loose) in [(layout.collar.left - layout.collar.length, expanded.collar.left - expanded.collar.length),
                                     (layout.collar.right, expanded.collar.right)] {
                let front = compact + (loose - compact) * progress
                layers.append(Layer(front: front, back: front + layout.collar.length, assembled: compact, plate: nil))
            }
        }
        var cursor = tip
        let canvas = CGRect(origin: .zero, size: size)
        for layer in layers.sorted(by: { $0.front > $1.front }) {
            drawBar(context, from: layer.back, to: cursor)
            if let item = layer.plate {
                if canvas.intersects(item.bounds), let product = PhotoEquipment.disc(plate: item.disc.plate, theme: theme, style: style, aspect: item.aspect) {
                    product.draw(in: item.bounds)
                }
            } else if layer.assembled > 0 {
                drawCollar(at: layout.collar.right, expandedX: expanded.collar.right, context: context)
            }
            cursor = layer.front
        }
        drawBar(context, from: -tip, to: cursor)
        if layout.collar.length > 0 {
            // This is the nearest object. Its photographic aperture reveals the
            // continuous sleeve underneath while its clasp eclipses the metal.
            drawCollar(at: layout.collar.left - layout.collar.length,
                       expandedX: expanded.collar.left - expanded.collar.length, context: context)
        }
        if progress > 0.85 {
            for item in plates where item.disc.side < 0 { drawCaption(item, context: context) }
        }
    }
}
