import Foundation

/// Which lifts a session exercise may be swapped for, and how a swap ends
/// (issue 20). String-typed so the core stays app-model-agnostic — both apps
/// pass their exercise record's raw fields. Mirrored as `swapCompatible` /
/// `UNLOADABLE_TYPES` in web/js/core.js.
///
/// Swap semantics (the UI lives in the native app; the web PWA documents
/// native-only scope for the gesture but honors the resulting state):
/// - Default is SESSION-ONLY: the program slot is untouched. The slot simply
///   isn't performed that day — on a peak day the existing skipped-peak rule
///   applies, which is the honest grade for substituted work.
/// - "For this cycle": the slot is renamed and remembers its original in
///   `revertToExerciseName`; the cycle rollover restores it with a note.
/// - "For the whole program": the slot is renamed and any pending cycle
///   revert is cleared. Progression state stays with the slot in both cases —
///   candidates train the same movement pattern at the same tier, so the
///   base/e1RM remain the best available prior.
public enum SwapRules {

    /// Exercise types that can't carry a weight prescription. A loaded slot
    /// must never be offered an unloadable substitute (Incline DB Press →
    /// Dips) or vice versa — the prescription wouldn't survive the swap.
    public static let unloadableTypes: Set<String> = ["bodyweight", "timed", "conditioning"]

    /// A candidate is offered only when it trains the same movement pattern
    /// (non-empty matching group), sits in the same programming tier
    /// (Main/Accessory/Conditioning — no accessory→competition-lift jumps),
    /// matches the current lift's loadability, isn't the same exercise, and
    /// isn't shelved.
    public static func compatible(
        currentName: String, currentCategory: String, currentType: String, currentGroup: String,
        candidateName: String, candidateCategory: String, candidateType: String, candidateGroup: String,
        candidateShelved: Bool
    ) -> Bool {
        !currentGroup.isEmpty
            && candidateGroup == currentGroup
            && candidateName != currentName
            && !candidateShelved
            && candidateCategory == currentCategory
            && unloadableTypes.contains(candidateType) == unloadableTypes.contains(currentType)
    }
}
