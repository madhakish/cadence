import Foundation

/// Transient iOS Health-read presentation policy, not stored training data.
/// No web counterpart: the web app cannot read Apple Health.
public enum HealthRuckSteps {
    /// Conservative: only conditioning exercises named Ruck, with completed work.
    /// Mixed sessions cannot attribute session-wide steps to the ruck portion.
    public static func isRuckOnly(_ completed: [CompletedExerciseKind]) -> Bool {
        !completed.isEmpty && completed.allSatisfy {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ruck"
                && $0.type.lowercased() == "conditioning"
        }
    }

    /// Missing, sub-step, nonfinite and invalid values never become measured zeros.
    /// Keep Health's quantity rather than manufacturing steps from distance.
    public static func measuredCount(_ quantity: Double?) -> Double? {
        guard let quantity, quantity.isFinite, quantity >= 1 else { return nil }
        return quantity
    }
}
