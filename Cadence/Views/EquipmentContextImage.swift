import SwiftUI

/// Category context only. Exact workout loads continue to use BarbellStageView.
/// Fixed geometry keeps asynchronous image decode out of the layout contract.
struct EquipmentContextImage: View {
    let category: ExerciseCategory
    var width: CGFloat = 96

    var body: some View {
        Image("TrainingContext\(category.rawValue)")
            .resizable()
            .scaledToFit()
            .frame(width: width, height: width * 2 / 3)
            .accessibilityHidden(true)
    }
}
