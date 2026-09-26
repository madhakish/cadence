import SwiftUI
import CadenceCore

/// One rack-resolution path for native callers. The resulting `PlateSolution`
/// is the only value `BarbellView` accepts, so station units, mixed inventory,
/// collars, and loading policy cannot drift inside the presentation layer.
func authoritativePlateSolution(
    targetLb: Double,
    fallbackUnit: WeightUnit,
    bar: Bar,
    gym: Gym?,
    stationDenomination: WeightUnit? = nil
) -> PlateSolution {
    let fallback = fallbackUnit == .kg ? Plate.standardKg : Plate.standardLb
    let rack = PlateMath.stationPlates(
        preference: stationDenomination,
        gymPlates: gym?.availablePlates ?? fallback
    )
    return PlateMath.solveLoad(
        weightLb: targetLb,
        bar: bar,
        plates: rack,
        collarLb: gym?.collarWeightLb ?? 0,
        policy: gym?.loadingPolicy ?? .closest
    )
}

/// Plate colours come from the one table in CadenceCore (`PlatePalette`);
/// this only turns its hex into SwiftUI colours.
private extension PlateColour {
    var fillColor: Color { Color(hex: fill) }
    var edgeColor: Color { Color(hex: edge) }
    var inkColor: Color { Color(hex: ink) }
}

/// A readable, face-on denomination key for a plate in the calculator. The
/// bar graphic stays an honest edge-on load-order diagram; this companion
/// view owns the large number that an edge-on plate cannot physically carry.
/// Decorative: every use pairs it with a readable denomination label.
struct PlateFaceBadge: View {
    var plateTheme: PlateThemeID = .custom
    let plate: Plate
    let style: PlateVisualStyle
    var exactDenomination = false

    private var colour: PlateColour { PlateTheme.colour(plate, theme: plateTheme, style: style) }

    var body: some View {
        let foreground = colour.inkColor
        ZStack {
            Circle()
                .fill(colour.fillColor)
            Circle()
                .stroke(colour.edgeColor, lineWidth: 2)
            Circle()
                .stroke(foreground.opacity(0.34), lineWidth: 1)
                .padding(7)
            VStack(spacing: -2) {
                Text(exactDenomination ? inspectionPlateValue(plate) : Weight.trim(plate.value, decimals: 2))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                Text(plate.unit.rawValue)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
            }
            .foregroundStyle(foreground)
        }
        .frame(width: 52, height: 52)
        .accessibilityHidden(true)
    }
}

/// Renders the solver's exact stack from the rendered plate and bar sprites.
/// `presentation` is chosen by the SURFACE (a set row vs the current set's
/// stage); `emphasis` is the state and changes only opacity — never geometry,
/// order, or labels.
struct BarbellView: View {
    enum Presentation: Equatable { case compactSide, fullBar, inspectionSide }
    enum Emphasis: Equatable { case current, standard, muted }
    let solution: PlateSolution
    var plateStyle: PlateVisualStyle = .steel
    var plateTheme: PlateThemeID = .custom
    var presentation: Presentation = .compactSide
    var exploded = false
    var emphasis: Emphasis = .standard
    @ScaledMetric(relativeTo: .subheadline) private var inspectionCaptionSize: CGFloat = 14

    static func minimumLegibleWidth(for loadout: Loadout, style: PlateVisualStyle, theme: PlateThemeID = .custom) -> CGFloat {
        CGFloat(max(320, BarbellScene(loadout: loadout, style: style, exploded: false, theme: theme).width * 0.55))
    }

    var body: some View {
        let scene = BarbellScene(loadout: solution.loadout, style: plateStyle, exploded: exploded, theme: plateTheme)
        let look = PlateTheme.description(plateTheme)
        Canvas { context, size in
            let inspection = presentation == .inspectionSide
            let near = inspection ? scene.discs.filter { $0.side < 0 } : []
            let minX = min(-scene.end * scene.axisX, near.map { $0.x - $0.faceRadius - $0.depth / 2 }.min() ?? 0) - 24
            let maxX = -scene.shoulder * scene.axisX + 100
            let minY = near.map { $0.y - $0.radius }.min() ?? -50
            let maxY = near.map { $0.y + $0.radius }.max() ?? 50
            let width = inspection ? maxX - minX : scene.width
            let height = inspection ? maxY - minY + (exploded ? 70 : 30) : scene.height
            let scale = min(size.width / width, size.height / height)
            context.translateBy(x: size.width / 2 - (inspection ? (minX + maxX) / 2 * scale : 0),
                                y: size.height / 2 - (inspection ? (minY + maxY) / 2 * scale + (exploded ? 16 : 0) : 0))
            context.scaleBy(x: scale, y: scale)
            func point(_ position: Double) -> CGPoint {
                CGPoint(x: position * scene.axisX, y: position * scene.axisY)
            }
            let angle = exploded ? "exploded" : "assembled"
            // Rendered sprites (PlateSprites) placed from the shared scene: a bar
            // part maps its two axis reference points onto two scene points.
            // Thickness comes from the sprite's nominal span (an exploded scene's
            // longer sleeve stretches along the bar, never fattens).
            let axisLength = hypot(scene.axisX, scene.axisY)
            func placeBar(_ name: String, from: CGPoint, to: CGPoint) {
                guard case let .bar(_, _, spriteSize, a, b, spanUnits)? = PlateSprites.sprites[name] else { return }
                let spritePx = hypot(b.x - a.x, b.y - a.y)
                let k = spanUnits * axisLength / spritePx
                let stretch = hypot(to.x - from.x, to.y - from.y) / (spanUnits * axisLength)
                let image = context.resolve(Image(name))
                context.drawLayer { layer in
                    layer.translateBy(x: from.x, y: from.y)
                    layer.rotate(by: .radians(atan2(to.y - from.y, to.x - from.x)))
                    layer.scaleBy(x: k * stretch, y: k)
                    layer.rotate(by: .radians(-atan2(b.y - a.y, b.x - a.x)))
                    layer.translateBy(x: -a.x, y: -a.y)
                    layer.draw(image, in: CGRect(origin: .zero, size: spriteSize))
                }
            }
            // The bar goes under everything: every plate bore is open in the sprites,
            // so the sleeves and shaft show through wherever the plate's thickness lets them. The camera sits at the
            // −x end: the far (+x) collar precedes the plates, the near one follows.
            placeBar("bar-sleeve-\(angle)", from: point(scene.shoulder), to: point(scene.end))
            placeBar("bar-shaft-\(angle)", from: point(-scene.shoulder), to: point(scene.shoulder))
            placeBar("bar-sleeve-near-\(angle)", from: point(-scene.end), to: point(-scene.shoulder))
            if solution.loadout.collarLb > 0,
               case let .bar(_, _, _, _, _, span)? = PlateSprites.sprites["bar-collar-\(angle)"] {
                placeBar("bar-collar-\(angle)", from: point(scene.collar - span / 2), to: point(scene.collar + span / 2))
            }
            for disc in scene.discs.sorted(by: { $0.x > $1.x }) {
                let token = disc.plate.colorToken(for: plateStyle)
                let colour = PlateTheme.colour(disc.plate, theme: plateTheme, style: plateStyle)
                let family = PlateTheme.family(disc.plate, theme: plateTheme, style: plateStyle)
                let known = PlateSprites.plates["\(family):\(disc.plate.id)"].map { "plate-\($0)-\(angle)" }
                // An unknown shape borrows the family's first sprite, and an
                // unknown family the steel one; geometry still scales it.
                func first(_ family: String) -> String? {
                    PlateSprites.sprites.keys.sorted().first { $0.hasPrefix("plate-\(family)-") && $0.hasSuffix("-\(angle)") }
                }
                let name = known.flatMap { PlateSprites.sprites[$0] != nil ? $0 : nil } ?? first(family) ?? first("steel")
                guard let name, case let .plate(_, _, _, spriteSize, faceCenter, faceRadius, hubRadius)? = PlateSprites.sprites[name] else { continue }
                // The sprite's front face is the −x face; the scene's disc extends ±depth/2.
                let x = disc.x - disc.depth / 2
                let k = disc.radius / faceRadius
                let frame = CGRect(x: x - faceCenter.x * k, y: disc.y - faceCenter.y * k,
                                   width: spriteSize.width * k, height: spriteSize.height * k)
                let image = context.resolve(Image(name))
                let tint = plateTheme == .custom ? PlateFaceTint(token: token, style: plateStyle)
                    : PlateFaceTint(fill: colour.fill, style: plateStyle)
                let m = tint.matrix.map(Float.init)
                var matrix = ColorMatrix()
                (matrix.r1, matrix.r2, matrix.r3, matrix.r4, matrix.r5) = (m[0], m[1], m[2], m[3], m[4])
                (matrix.g1, matrix.g2, matrix.g3, matrix.g4, matrix.g5) = (m[5], m[6], m[7], m[8], m[9])
                (matrix.b1, matrix.b2, matrix.b3, matrix.b4, matrix.b5) = (m[10], m[11], m[12], m[13], m[14])
                (matrix.a1, matrix.a2, matrix.a3, matrix.a4, matrix.a5) = (m[15], m[16], m[17], m[18], m[19])
                context.drawLayer { tinted in
                    tinted.addFilter(.colorMatrix(matrix))
                    tinted.draw(image, in: frame)
                }
                let hub = CGRect(x: x - disc.faceRadius * hubRadius, y: disc.y - disc.radius * hubRadius,
                                 width: disc.faceRadius * hubRadius * 2, height: disc.radius * hubRadius * 2)
                context.drawLayer { untinted in
                    untinted.clip(to: Path(ellipseIn: hub))
                    untinted.draw(image, in: frame)
                }
                // Theme bands are drawn over the face; other details are in the sprite.
                let mm = disc.radius / (PlateTheme.geometry(disc.plate, theme: plateTheme, style: plateStyle).diameter / 2)
                func ring(radius: Double, width: Double, colour: UInt32) {
                    let rx = disc.faceRadius * radius / disc.radius
                    context.stroke(Path(ellipseIn: CGRect(x: x - rx, y: disc.y - radius, width: rx * 2, height: radius * 2)),
                                   with: .color(Color(hex: colour)), lineWidth: width)
                }
                if look.details.contains("colourBand"), let band = PlateTheme.band(disc.plate, theme: plateTheme) {
                    let width = max(6, 0.34 * PlateTheme.geometry(disc.plate, theme: plateTheme, style: plateStyle).thickness) * mm
                    ring(radius: disc.radius - width / 2, width: width, colour: band)
                }
                if look.details.contains("hubRing") {
                    ring(radius: disc.radius * hubRadius + 2 * mm, width: 4 * mm, colour: colour.ink)
                }
                // The denomination is printed on the face beside the hub, value
                // over unit, scaled with the plate (the value is ~22% of its
                // radius) and foreshortened with the face, like the approved
                // plate-loading mockups. Mirrors barbell.js.
                let printSize: CGFloat = exploded ? 14 : 10
                let grow = disc.radius * 0.22 / printSize
                let squash = max(0.35, disc.faceRadius / disc.radius)
                var print = context
                // Centred in the band between the sprite's hub insert and the rim.
                print.translateBy(x: x + disc.faceRadius * (hubRadius + 0.92) / 2, y: disc.y)
                print.scaleBy(x: squash * grow, y: grow)
                let ink = colour.inkColor.opacity(0.94)
                let value = Text(inspection ? inspectionPlateValue(disc.plate) : Weight.trim(disc.plate.value, decimals: 2))
                    .font(.system(size: printSize, weight: .heavy).width(.condensed))
                    .foregroundColor(ink)
                let unit = Text(disc.plate.unit.rawValue.uppercased())
                    .font(.system(size: (printSize * 0.64).rounded(), weight: .heavy).width(.condensed))
                    .tracking(0.4)
                    .foregroundColor(ink)
                print.draw(value, at: CGPoint(x: 0, y: -printSize * 0.4))
                print.draw(unit, at: CGPoint(x: 0, y: printSize * 0.52))
                if inspection && exploded && disc.side < 0 {
                    // The caption follows Dynamic Type and stays readable as a
                    // long stack scrolls instead of shrinking to fit.
                    let caption = Text(inspectionPlateLabel(disc.plate))
                        .font(.system(size: inspectionCaptionSize / scale, weight: .semibold).monospacedDigit())
                        .foregroundColor(.primary)
                    context.draw(caption, at: CGPoint(x: x, y: disc.y + disc.radius + 18 / scale))
                }
            }
            if solution.loadout.collarLb > 0,
               case let .bar(_, _, _, _, _, span)? = PlateSprites.sprites["bar-collar-near-\(angle)"] {
                placeBar("bar-collar-near-\(angle)", from: point(-scene.collar - span / 2), to: point(-scene.collar + span / 2))
            }
        }
        .frame(height: presentation == .compactSide ? 84 : nil)
        .opacity(emphasis == .muted ? 0.85 : 1)
        .accessibilityLabel("\(exploded ? "Exploded" : "Assembled") bar, \(Weight.both(lb: solution.loadout.totalLb))")
        .accessibilityChildren { Self.plateChildren(scene: scene, loadout: solution.loadout) }
    }

    /// Every plate as its own element, each side from the collar outward, then
    /// the bar-only or collar note — the same order web's focusable plate
    /// groups take. Shared with the 3D inspector.
    @ViewBuilder
    static func plateChildren(scene: BarbellScene, loadout: Loadout, exactDenominations: Bool = false) -> some View {
        ForEach([-1, 1], id: \.self) { side in
            ForEach(scene.discs.filter { $0.side == side }.sorted { $0.index < $1.index }, id: \.index) { disc in
                Text(exactDenominations
                         ? "\(inspectionPlateLabel(disc.plate)) plate, \(disc.index + 1) from inside, \(side < 0 ? "left" : "right") side"
                         : disc.accessibilityLabel)
                    .accessibilityIdentifier("barbell-plate-\(side < 0 ? "left" : "right")-\(disc.index)")
            }
        }
        if loadout.perSide.isEmpty {
            Text(loadout.collarLb > 0 ? "Bar + collars" : "Bar only")
        } else if loadout.collarLb > 0 {
            Text("Collars, \(Weight.both(lb: loadout.collarLb)) total")
        }
    }
}

/// Always offers inspection, even when a typical stack fits the phone.
struct BarbellStageView: View {
    let solution: PlateSolution
    let unit: WeightUnit
    var plateStyle: PlateVisualStyle = .steel
    var plateTheme: PlateThemeID = .custom
    var caption = "Mirrored stack · counts are per side"
    var onExpand: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let onExpand {
                BarbellView(solution: solution, plateStyle: plateStyle, plateTheme: plateTheme, presentation: .fullBar)
                    .frame(height: 170)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onExpand)
                HStack {
                    Text("Tap to inspect").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: onExpand) {
                        Label("Larger view", systemImage: "arrow.up.right")
                            .labelStyle(.titleAndIcon)
                            .font(.callout.bold())
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Inspect loaded bar and explode plates")
                    .accessibilityIdentifier("expand-loaded-bar")
                }
            } else {
                BarbellView(solution: solution, plateStyle: plateStyle, plateTheme: plateTheme, presentation: .fullBar)
                    .frame(height: 170)
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            if abs(solution.deviationLb) > 0.01 {
                Text("Difference: \(solution.deviationLb > 0 ? "+" : "")\(Weight.trim(solution.deviationLb, decimals: 2)) lb")
                    .font(.caption.bold()).foregroundStyle(Theme.warn)
            } else if !solution.satisfiesPolicy {
                Text("Closest available · policy not exact").font(.caption.bold()).foregroundStyle(Theme.warn)
            }
        }
    }
}

/// Shared by calculator, workout, and contextual exercise sheets.
struct BarbellInspectionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var captionSize: CGFloat = 14
    let solution: PlateSolution
    var plateStyle: PlateVisualStyle = .steel
    var plateTheme: PlateThemeID = .custom
    @State private var exploded = false
    private let solid = BarbellSceneView.isSupported

    var body: some View {
        let scene = BarbellScene(loadout: solution.loadout, style: plateStyle, exploded: exploded, theme: plateTheme)
        let layout = BarbellInspector.layout(loadout: solution.loadout, style: plateStyle, explode: exploded ? 1 : 0, theme: plateTheme)
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                let minimum = BarbellInspector.minimumWidth(layout: layout, viewportWidth: Double(proxy.size.width), exploded: exploded)
                let width = exploded ? max(proxy.size.width, CGFloat(minimum) * max(1, captionSize / 14)) : proxy.size.width
                ScrollView(.horizontal, showsIndicators: exploded && width > proxy.size.width) {
                    Group {
                        if solid {
                            BarbellSceneView(loadout: solution.loadout, plateStyle: plateStyle, plateTheme: plateTheme,
                                             exploded: exploded, reduceMotion: reduceMotion)
                        } else {
                            BarbellView(solution: solution, plateStyle: plateStyle, plateTheme: plateTheme, presentation: .inspectionSide, exploded: exploded)
                        }
                    }
                    .frame(width: width, height: 300)
                    .contentShape(Rectangle())
                    .onTapGesture { toggle() }
                }
                .scrollDisabled(!exploded || width <= proxy.size.width)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
            .frame(height: 300)
            .accessibilityIdentifier("barbell-inspection-artwork")
            .accessibilityLabel("\(exploded ? "Exploded" : "Assembled") bar, \(Weight.both(lb: solution.loadout.totalLb))")
            .accessibilityHint(exploded ? "One sleeve shown; both sides are mirrored. Tap to assemble." : "One sleeve shown; both sides are mirrored. Tap to inspect each plate.")
            .accessibilityChildren { BarbellView.plateChildren(scene: scene, loadout: solution.loadout, exactDenominations: true) }
            Button(exploded ? "Angled inspection · tap to assemble" : "Front view · tap to inspect") { toggle() }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .accessibilityLabel(exploded ? "Assemble bar" : "Explode plates")
                .accessibilityValue(exploded ? "Exploded" : "Assembled")
                .accessibilityIdentifier("barbell-explode-toggle")
            Text("Plates per side").font(.headline)
            ForEach(Array(solution.loadout.perSide.enumerated()), id: \.offset) { _, count in
                HStack(spacing: 12) {
                    PlateFaceBadge(plateTheme: plateTheme, plate: count.plate, style: plateStyle, exactDenomination: true)
                    Text(inspectionPlateLabel(count.plate)).font(.body.monospacedDigit())
                    Spacer()
                    Text("× \(count.count)").font(.body.bold().monospacedDigit())
                }
                .accessibilityElement(children: .combine)
            }
            if solution.loadout.perSide.isEmpty {
                Text(solution.loadout.collarLb > 0 ? "Bar + collars" : "Bar only")
            }
            if !solution.satisfiesPolicy {
                Label("Closest available · policy not exact", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.warn)
            }
        }
        .padding(.horizontal)
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: Theme.shortMotion)) { exploded.toggle() }
    }
}

/// The one totals composition used anywhere Cadence explains a solved or
/// entered bar — the calculator, the current set, the exercise pane, the
/// workout preview. What was achieved, pounds first, kilograms after; how far
/// from what was asked; which bar and what is on each side; and one cell per
/// plate family so the rack is readable at a glance. Web twin:
/// `loadoutSummary` in barbell.js.
struct LoadoutSummaryView: View {
    let requestedLb: Double?
    let loadout: Loadout
    var plateStyle: PlateVisualStyle = .steel
    var plateTheme: PlateThemeID = .custom
    /// The achieved total keeps its display proportion and follows Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var totalSize: CGFloat = 40

    private var differenceLb: Double? {
        requestedLb.map { loadout.totalLb - $0 }
    }

    private var perSideText: String {
        loadout.perSide.isEmpty
            ? (loadout.collarLb > 0 ? "Bar + collars" : "Bar only")
            : "\(loadout.perSideLabel) / side"
    }

    private struct Cell: Identifiable {
        let id: String
        let plate: Plate?
        let count: String
        let kind: String
    }

    /// One cell per denomination, counting both sleeves, then the collars.
    private var cells: [Cell] {
        var result = loadout.perSide.map { count in
            Cell(id: count.plate.id,
                 plate: count.plate,
                 count: "\(count.count * 2) × \(count.plate.label)",
                 kind: PlateGeometry.familyLabel(PlateTheme.family(count.plate, theme: plateTheme, style: plateStyle)))
        }
        if loadout.collarLb > 0 {
            result.append(Cell(id: "collars", plate: nil, count: "2 collars", kind: "Outermost"))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ACHIEVED WITH BAR")
                        .font(.caption.bold())
                        .tracking(0.8)
                        .foregroundStyle(Theme.accent)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Weight.trim(loadout.totalLb))
                            .font(.system(size: totalSize, weight: .black, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Text("lb")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text(Weight.trim(Weight.kg(fromLb: loadout.totalLb)))
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        Text("kg")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if let requestedLb, let differenceLb {
                    let sign = differenceLb > 0.005 ? "+" : ""
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(sign)\(Weight.trim(differenceLb, decimals: 2)) lb")
                            .font(.callout.bold().monospacedDigit())
                            .foregroundStyle(abs(differenceLb) > 0.01 ? Theme.warn : .secondary)
                        Text("from \(Weight.trim(requestedLb)) lb")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)

            Divider()

            HStack(alignment: .firstTextBaseline) {
                Text(loadout.bar.label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(perSideText)
                    .font(.body.bold().monospacedDigit())
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)

            if !cells.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                    ForEach(cells) { cell in
                        LoadoutCell(cell: cell, style: plateStyle, theme: plateTheme)
                    }
                }
            }
        }
    }

    private var accessibilitySummary: String {
        var parts = ["Achieved total, bar included, \(Weight.both(lb: loadout.totalLb))"]
        if let requestedLb, let differenceLb {
            let sign = differenceLb > 0.005 ? "plus " : (differenceLb < -0.005 ? "minus " : "")
            parts.append("from \(Weight.trim(requestedLb)) lb, \(sign)\(Weight.trim(abs(differenceLb), decimals: 2)) lb")
        }
        return parts.joined(separator: ", ")
    }

    private struct LoadoutCell: View {
        let cell: Cell
        let style: PlateVisualStyle
        let theme: PlateThemeID

        var body: some View {
            HStack(spacing: 8) {
                if let plate = cell.plate {
                    PlateFaceBadge(plateTheme: theme, plate: plate, style: style)
                        .scaleEffect(0.5)
                        .frame(width: 26, height: 26)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(cell.count)
                        .font(.callout.bold().monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(cell.kind)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.hairline, lineWidth: 0.5))
            .accessibilityElement(children: .combine)
        }
    }
}
// Colour(hex:) comes from Theme.swift; the plate hex values come from CadenceCore.
