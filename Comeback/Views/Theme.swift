import SwiftUI

/// Dark, minimal, chalk-hands-friendly. No streaks, no badges, no quotes.
enum Theme {
    static let accent = Color.orange
    static let warn = Color.yellow
    static let hardStop = Color.red
    static let good = Color.green
    static let card = Color(.secondarySystemGroupedBackground)

    /// Minimum touch target for between-sets thumbs.
    static let bigTap: CGFloat = 56
}

/// All user-facing copy in one place. Tone: terse, dry, coach-like.
enum Copy {
    static let sessionDone = "Bank it."
    static let stoppedEarly = "Clean reps over rep count."
    static let noSwelling = "Clear. Carry on."
    static let swelling = "Hard stop on running. Let it settle."
    static let restOver = "Rest over."
    static let offTarget = "Closest load is off target."
    static let emptyHistory = "Nothing logged yet."
    static let shelved = "Shelved"
}

extension View {
    func cardStyle() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// The one mm:ss formatter for the app (web equivalent: ui.mmss).
func mmss(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
