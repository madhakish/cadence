import Foundation

/// One search rule for every exercise picker and library surface.
///
/// Availability/gate filtering stays outside this function: whether an
/// exercise may be programmed is a different question from whether its name,
/// aliases, or programming tags match what the lifter typed.
public enum ExerciseSearch {
    /// Both classifications participate in library filtering; nil means all.
    public static func matchesMovement(_ selected: MovementPattern?, primary: MovementPattern,
                                       secondary: MovementPattern? = nil) -> Bool {
        selected == nil || selected == primary || selected == secondary
    }

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

    /// The lifter's recent lifts — the browser's entry point above the
    /// category groups, never a category of its own. Distinct names from the
    /// most recent completed sessions, newest session first and in performed
    /// order within a session, capped at `limit`. A name appears once, at
    /// its most recent position. Sessions arrive newest-first; the sequence
    /// is walked only as far as the cap needs. Mirrors `recentExerciseNames`
    /// in core.js.
    public static func recentNames<S: Sequence>(sessionsNewestFirst: S, limit: Int = 6) -> [String]
    where S.Element == [String] {
        guard limit > 0 else { return [] }
        var seen = Set<String>()
        var recent: [String] = []
        for names in sessionsNewestFirst {
            for name in names where !name.isEmpty && seen.insert(name).inserted {
                recent.append(name)
                if recent.count == limit { return recent }
            }
        }
        return recent
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: foldingLocale
        )
    }
}
