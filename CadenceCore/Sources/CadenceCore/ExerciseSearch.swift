import Foundation

/// One search rule for every exercise picker and library surface.
///
/// Availability/gate filtering stays outside this function: whether an
/// exercise may be programmed is a different question from whether its name,
/// aliases, or programming tags match what the lifter typed.
public enum ExerciseSearch {
    /// One locale for every fold — this runs per keystroke over the whole
    /// library, and the folding rule is deliberately locale-fixed anyway.
    private static let foldingLocale = Locale(identifier: "en_US_POSIX")

    /// Normalize the query once per filter pass, not once per exercise.
    public static func preparedTerm(_ query: String) -> String {
        normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func matches(
        _ query: String,
        name: String,
        movementGroup: String,
        movementPatternName: String,
        exerciseType: String,
        aliases: [String] = [],
        strategyTags: [String] = []
    ) -> Bool {
        matches(
            preparedTerm: preparedTerm(query),
            name: name, movementGroup: movementGroup,
            movementPatternName: movementPatternName, exerciseType: exerciseType,
            aliases: aliases, strategyTags: strategyTags
        )
    }

    public static func matches(
        preparedTerm term: String,
        name: String,
        movementGroup: String,
        movementPatternName: String,
        exerciseType: String,
        aliases: [String] = [],
        strategyTags: [String] = []
    ) -> Bool {
        guard !term.isEmpty else { return true }
        return ([name, movementGroup, movementPatternName, exerciseType] + aliases + strategyTags)
            .contains { normalized($0).contains(term) }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: foldingLocale
        )
    }
}
