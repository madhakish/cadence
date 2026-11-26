import CadenceCore
import SwiftUI

/// The five complete reference photographs are equipment-specific. All other
/// rows use source-derived unlettered material and the actual stored plate.
struct PlateFaceArtwork: View {
    let plate: Plate
    let theme: PlateThemeID
    let style: PlateVisualStyle
    var showsLettering = true

    static func referencePhoto(plate: Plate, theme: PlateThemeID, style: PlateVisualStyle) -> String? {
        guard plate.unit == .lb,
              theme == .lbColourBumpers || (theme == .custom && style == .bumper),
              [55.0, 45, 35, 25, 10].contains(plate.value) else { return nil }
        return "AstraBumper\(plate.denomination)lb"
    }

    static func surface(plate: Plate, theme: PlateThemeID, style: PlateVisualStyle) -> String {
        switch PlateTheme.material(plate, theme: theme, style: style).finish {
        case .rubber: theme == .blackBumpersBand || theme == .cadenceHouse ? "AstraPlateBlackRubber" : "AstraPlateRubber"
        case .powder: "AstraPlatePowder"
        case .gloss: "AstraPlateGloss"
        case .castIron: "AstraPlateCastIron"
        case .hammertone: "AstraPlateHammertone"
        case .machined: "AstraPlateMachined"
        }
    }

    var body: some View {
        if showsLettering, let photo = Self.referencePhoto(plate: plate, theme: theme, style: style) {
            Image(decorative: photo).resizable().scaledToFit()
        } else {
            let colour = PlateTheme.colour(plate, theme: theme, style: style)
            let surface = Image(decorative: Self.surface(plate: plate, theme: theme, style: style)).resizable()
            GeometryReader { proxy in
                let width = proxy.size.width, height = proxy.size.height
                let geometry = PlateTheme.geometry(plate, theme: theme, style: style)
                let lip = showsLettering ? min(width * 0.14, width * CGFloat(geometry.thickness / geometry.diameter) * 0.75) : 0
                let faceWidth = showsLettering ? width * 0.77 : width
                ZStack {
                    if showsLettering {
                        // A shallow three-quarter angle gives a thick rubber tyre
                        // and a thin calibrated disc visibly different profiles.
                        paintedSurface(surface, fill: colour.fill)
                            .brightness(-0.12)
                            .frame(width: faceWidth, height: height)
                            .offset(x: -lip / 2)
                    }
                    ZStack {
                        paintedSurface(surface, fill: colour.fill)
                        if let band = PlateTheme.band(plate, theme: theme) {
                            Ellipse().strokeBorder(Color(hex: band), lineWidth: height * 0.035)
                                .frame(width: faceWidth * 0.87, height: height * 0.87)
                        }
                        Image(decorative: "AstraPlateHub").resizable()
                            .colorMultiply(hubTint)
                        if showsLettering {
                            Text(plate.label)
                                .font(.system(size: height * 0.16, weight: .heavy))
                                .monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.5)
                                .foregroundStyle(Self.lettering(on: colour.fill))
                                .frame(width: faceWidth * 0.76)
                                .position(x: faceWidth / 2, y: height * 0.75)
                        }
                    }
                    .frame(width: faceWidth, height: height)
                    .offset(x: lip / 2)
                }
                .frame(width: width, height: height)
            }
        }
    }

    private func paintedSurface(_ image: Image, fill: UInt32) -> some View {
        Color(hex: fill)
            .overlay { image.blendMode(.hardLight) }
            .compositingGroup()
            .mask(image)
    }

    // Denomination text remains legible on black plates with dark colour bands.
    static func lettering(on fill: UInt32) -> Color {
        func linear(_ component: UInt32) -> Double {
            let value = Double(component & 255) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(fill >> 16) + 0.7152 * linear(fill >> 8) + 0.0722 * linear(fill)
        return luminance > 0.18 ? Color(hex: 0x101113) : Color(hex: 0xF7F4EF)
    }

    private var hubTint: Color {
        switch PlateTheme.description(theme).hubFinish {
        case .chrome: .white
        case .blackSteel: Color(white: 0.56)
        case .castIron: Color(white: 0.50)
        case .hammertone: Color(white: 0.76)
        }
    }
}

/// Each physical plate advances the stack by its thickness. Its projected
/// face overlaps the preceding disc just as it does on an occupied sleeve.
struct MiniSleeveLayout {
    struct Disc {
        let plate: Plate
        let x: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    let discs: [Disc]
    let width: CGFloat
    let exposedSleeve: CGFloat

    init(plates: [PlateCount], theme: PlateThemeID, style: PlateVisualStyle) {
        var items: [Disc] = []
        var centre: CGFloat = 6
        var right: CGFloat = 6
        for group in plates where group.count > 0 {
            let geometry = PlateTheme.geometry(group.plate, theme: theme, style: style)
            let height = max(9, CGFloat(geometry.diameter / 450) * 34)
            let thickness = max(2, CGFloat(geometry.thickness / 450) * 34)
            let width = height * 0.32 + thickness
            if items.isEmpty { centre += width / 2 }
            for _ in 0..<group.count {
                items.append(Disc(plate: group.plate, x: centre - width / 2, width: width, height: height))
                right = max(right, centre + width / 2)
                centre += thickness
            }
        }
        discs = items
        let lastCentre = items.last.map { $0.x + $0.width / 2 } ?? centre
        width = max(right + 4, lastCentre + 10)
        exposedSleeve = width - lastCentre
    }
}

/// A shallow-angle view of one loaded sleeve. The same material photograph
/// used in the calculator follows each plate's actual thickness and diameter.
struct PlateStackMini: View {
    let loadout: Loadout
    let theme: PlateThemeID
    let style: PlateVisualStyle
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let layout = MiniSleeveLayout(plates: loadout.perSide,
                                      theme: theme, style: style)
        ViewThatFits(in: .horizontal) {
            artwork(layout)
            ScrollView(.horizontal) { artwork(layout) }
                .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Each side: \(loadout.perSideLabel)")
    }

    private func artwork(_ layout: MiniSleeveLayout) -> some View {
        ZStack(alignment: .leading) {
            sleeve.frame(width: layout.width * scale, height: 3.8 * scale)
            ForEach(Array(layout.discs.enumerated()), id: \.offset) { _, disc in
                PlateFaceArtwork(plate: disc.plate, theme: theme, style: style,
                                 showsLettering: false)
                    .frame(width: disc.width * scale, height: disc.height * scale)
                    .offset(x: disc.x * scale)
            }
            // The end of the sleeve emerges through the outermost bore.
            sleeve.frame(width: layout.exposedSleeve * scale, height: 3.8 * scale)
                .offset(x: (layout.width - layout.exposedSleeve) * scale)
        }
        .frame(width: layout.width * scale, height: 36 * scale, alignment: .leading)
    }

    private var sleeve: some View {
        Image(decorative: "AstraSleeve").resizable()
    }
}
