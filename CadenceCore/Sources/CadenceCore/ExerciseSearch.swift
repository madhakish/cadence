import Foundation

/// One search rule for every exercise picker and library surface.
///
/// Availability/gate filtering stays outside this function: whether an
/// exercise may be programmed is a different question from whether its name,
/// aliases, or programming tags match what the lifter typed.
public enum ExerciseSearch {
    public static func matches(
        _ query: String,
        name: String,
        movementGroup: String,
        movementPatternName: String,
        exerciseType: String,
        aliases: [String] = [],
        strategyTags: [String] = []
    ) -> Bool {
        let term = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !term.isEmpty else { return true }
        return ([name, movementGroup, movementPatternName, exerciseType] + aliases + strategyTags)
            .contains { normalized($0).contains(term) }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
