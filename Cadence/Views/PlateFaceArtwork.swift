import CadenceCore
import SwiftUI

/// Inventory and progress badges use the same photographic component as the
/// assembled bar. Denominations come from the actual equipment record.
struct PlateFaceArtwork: View {
    let plate: Plate
    let theme: PlateThemeID
    let style: PlateVisualStyle
    var showsLettering = true

    var body: some View {
        if let product = PhotoEquipment.disc(plate: plate, theme: theme, style: style, lettered: showsLettering) {
            if showsLettering {
                Image(uiImage: product).resizable().interpolation(.high).scaledToFit().accessibilityHidden(true)
            } else {
                Image(uiImage: product).resizable().interpolation(.high).accessibilityHidden(true)
            }
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
                    .offset(x: (layout.width - disc.x - disc.width) * scale)
            }
            // The end of the sleeve emerges through the outermost bore.
            sleeve.frame(width: layout.exposedSleeve * scale, height: 3.8 * scale)
            Image(decorative: "PhotoEndcap").resizable()
                .frame(width: 1.9 * scale, height: 3.8 * scale)
        }
        .frame(width: layout.width * scale, height: 36 * scale, alignment: .leading)
    }

    private var sleeve: some View {
        Image(decorative: "PhotoSleeve").resizable()
    }
}
