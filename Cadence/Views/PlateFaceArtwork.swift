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
        let rect: CGRect
    }

    let discs: [Disc]
    let width: CGFloat
    let sleeve: CGRect
    let exposed: CGRect
    let lock: CGRect?
    let lockOnSleeve: Bool

    init(loadout: Loadout, theme: PlateThemeID, style: PlateVisualStyle) {
        let layout = BarbellInspector.layout(loadout: loadout, style: style, explode: 0, theme: theme)
        let scale: CGFloat = 34 / 450
        let step = scale * PhotoEquipment.axialScale
        let near = layout.discs.filter { $0.side < 0 }
        let items = near.map { item in
            let front = (item.centerX - item.thickness / 2 + layout.bar.shoulderEnd) * step
            let diameter = 2 * item.radius * scale
            let shape = PhotoEquipment.bounds(depth: PhotoEquipment.axialScale * item.thickness / (2 * item.radius))
            return Disc(plate: item.plate, rect: CGRect(x: front + shape.minX * diameter, y: shape.minY * diameter,
                                                      width: shape.width * diameter, height: shape.height * diameter))
        }
        let tip: CGFloat = -CGFloat(layout.bar.sleeveLength) * step
        let shoulder = CGFloat.zero
        let stackEnd: CGFloat = CGFloat(layout.collar.left + layout.bar.shoulderEnd) * step
        let lockWidth = PhotoEquipment.lockWidthMM * scale, lockHeight = PhotoEquipment.lockHeightMM * scale
        let lock: CGRect? = layout.collar.length > 0
            ? CGRect(x: stackEnd - lockWidth * PhotoEquipment.lockRearAnchor.x, y: -lockHeight * PhotoEquipment.lockRearAnchor.y, width: lockWidth, height: lockHeight) : nil
        let plateLeft = items.map { $0.rect.minX }.min() ?? tip
        let plateRight = items.map { $0.rect.maxX }.max() ?? shoulder
        let low = min(tip - 1.5, plateLeft, lock?.minX ?? tip) - 1
        let high = max(shoulder, plateRight, lock?.maxX ?? shoulder) + 1
        width = high - low
        discs = items.map { Disc(plate: $0.plate, rect: $0.rect.offsetBy(dx: -low, dy: 18)) }
        let tubeHeight = 2 * layout.bar.sleeveRadius * scale
        sleeve = CGRect(x: tip - low, y: 18 - tubeHeight / 2, width: shoulder - tip, height: tubeHeight)
        exposed = CGRect(x: tip - low, y: 18 - tubeHeight / 2, width: max(0, stackEnd - tip), height: tubeHeight)
        self.lock = lock?.offsetBy(dx: -low, dy: 18)
        lockOnSleeve = stackEnd > tip
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
        let layout = MiniSleeveLayout(loadout: loadout, theme: theme, style: style)
        ViewThatFits(in: .horizontal) {
            artwork(layout)
            ScrollView(.horizontal) { artwork(layout) }
                .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Each side: \(loadout.perSideLabel)")
    }

    private func artwork(_ layout: MiniSleeveLayout) -> some View {
        ZStack(alignment: .topLeading) {
            photo("PhotoSleeve", in: layout.sleeve)
            ForEach(Array(layout.discs.enumerated()), id: \.offset) { _, disc in
                PlateFaceArtwork(plate: disc.plate, theme: theme, style: style, showsLettering: false)
                    .frame(width: disc.rect.width * scale, height: disc.rect.height * scale)
                    .offset(x: disc.rect.minX * scale, y: disc.rect.minY * scale)
            }
            if layout.exposed.width > 0 {
                photo("PhotoSleeve", in: layout.exposed)
                let height = layout.sleeve.height
                photo("PhotoEndcap", in: CGRect(x: layout.sleeve.minX - height * 0.25, y: layout.sleeve.minY,
                                               width: height * 0.5, height: height))
            }
            if let lock = layout.lock {
                photo(layout.lockOnSleeve ? "PhotoLock" : "PhotoCollar", in: lock)
            }
        }
        .frame(width: layout.width * scale, height: 36 * scale, alignment: .topLeading)
    }

    private func photo(_ name: String, in rect: CGRect) -> some View {
        Image(decorative: name).resizable().interpolation(.high)
            .frame(width: rect.width * scale, height: rect.height * scale)
            .offset(x: rect.minX * scale, y: rect.minY * scale)
    }
}
