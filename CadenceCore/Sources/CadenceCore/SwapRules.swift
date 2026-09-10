import Foundation

/// Which lifts a session exercise may be swapped for, and how a swap ends
/// (issue 20). Primitive fields plus `LoadBasis` keep the core app-model-
/// agnostic while preserving real load semantics. Mirrored as `swapCompatible` /
/// `swapCompatible` in web/app/js/core.js.
///
/// Swap semantics (the UI lives in the native app; the web PWA documents
/// native-only scope for the gesture but honors the resulting state):
/// - Default is SESSION-ONLY: the program slot is untouched. The substitute
///   retains the durable slot identity, and its prescribed work grades that slot.
/// - "For this cycle": the slot is renamed and remembers its original in
///   `revertToExerciseName`; the cycle rollover restores it with a note.
/// - "For the whole program": the slot is renamed and any pending cycle
///   revert is cleared. Progression state stays with the slot in both cases,
///   so candidates must use the same load basis. Matching units do not prove
///   equal strength: the lifter should check the substitute's starting load.
public enum SwapRules {

    /// A candidate is offered only when it trains the same movement pattern
    /// (non-empty matching group), sits in the same programming tier
    /// (Main/Accessory/Conditioning — no accessory→competition-lift jumps),
    /// matches the current lift's exact load basis, isn't the same exercise, and
    /// isn't shelved.
    public static func compatible(
        currentName: String, currentCategory: String, currentLoadBasis: LoadBasis, currentGroup: String,
        candidateName: String, candidateCategory: String, candidateLoadBasis: LoadBasis, candidateGroup: String,
        candidateShelved: Bool
    ) -> Bool {
        !currentGroup.isEmpty
            && candidateGroup == currentGroup
            && candidateName != currentName
            && !candidateShelved
            && candidateCategory == currentCategory
            && candidateLoadBasis == currentLoadBasis
    }

    /// Replacing an entry changes the identity of every set, including warmups.
    /// Performed work must keep its original exercise; add a separate entry
    /// when changing movements after logging any set.
    public static func canReplaceEntry(setStatuses: [SetStatus]) -> Bool {
        !setStatuses.contains(.completed)
    }
}
