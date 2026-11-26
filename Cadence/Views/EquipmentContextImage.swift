import SwiftUI

/// Category context only. Exact workout loads continue to use BarbellStageView.
/// Fixed geometry keeps asynchronous image decode out of the layout contract.
struct EquipmentContextImage: View {
    let category: ExerciseCategory
    var width: CGFloat = 96

    var body: some View {
        Image(decorative: category == .main ? "AstraMainEquipmentContext" : "TrainingContext\(category.rawValue)")
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: category == .main ? 5 : 0))
            .frame(width: width, height: width * 2 / 3)
            .accessibilityHidden(true)
    }
}
