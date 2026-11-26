import SwiftUI
import CadenceCore

/// The rendered implement has no baked-in weight. Its label always follows
/// the captured per-implement load and the unit entered for this set.
struct DumbbellView: View {
    let weightLb: Double
    let unit: WeightUnit

    var body: some View {
        let value = unit == .kg ? Weight.kg(fromLb: weightLb) : weightLb
        let amount = "\(Weight.trim(value)) \(unit.rawValue)"
        HStack(spacing: 10) {
            Image(decorative: "AstraDumbbell")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 46)
            Text("\(amount) each")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dumbbell, \(amount) each")
    }
}
