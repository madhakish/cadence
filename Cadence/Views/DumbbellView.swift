import SwiftUI
import CadenceCore

/// Compact dumbbell graphic for dumbbell lifts — the counterpart of
/// BarbellView's plate loadout: heads on both ends, the dumbbell's size (in
/// the entered unit) stamped on the handle, so a glance says which pair to
/// grab off the rack. Mirrors web/js/barbell.js `dumbbellSVG` (same geometry
/// and greys).
struct DumbbellView: View {
    let weightLb: Double
    let unit: WeightUnit

    private static let height: CGFloat = 30
    private static let width: CGFloat = 88

    var body: some View {
        let value = unit == .kg ? Weight.kg(fromLb: weightLb) : weightLb
        HStack(spacing: 6) {
            Canvas { ctx, size in
                let h = Self.height
                let w = size.width
                func plate(_ x: CGFloat, _ pw: CGFloat, _ ph: CGFloat) {
                    let rect = Path(roundedRect: CGRect(x: x, y: (h - ph) / 2, width: pw, height: ph), cornerRadius: 1.5)
                    ctx.fill(rect, with: .color(Color(hex: 0x7C828C)))
                    ctx.stroke(rect, with: .color(Color(hex: 0x3A3B42)), lineWidth: 0.75)
                }
                // handle
                ctx.fill(Path(roundedRect: CGRect(x: 15, y: h / 2 - 3, width: w - 30, height: 6), cornerRadius: 3),
                         with: .color(Color(hex: 0x9AA0AA)))
                // heads: outer + inner plate each side
                plate(0, 7, 24); plate(8, 6, 18)
                plate(w - 7, 7, 24); plate(w - 14, 6, 18)
                // the number you look for on the rack
                ctx.draw(
                    Text(Weight.trim(value))
                        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit()),
                    at: CGPoint(x: w / 2, y: h / 2), anchor: .center
                )
            }
            .frame(width: Self.width, height: Self.height)
            Text(unit.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Dumbbell, \(Weight.trim(value)) \(unit.rawValue)")
    }
}
