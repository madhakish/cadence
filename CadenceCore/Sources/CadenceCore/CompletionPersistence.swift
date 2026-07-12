import Foundation

/// The transactional boundary for banking a session (issue 19). Completion
/// stages a batch of mutations (milestones, lift tracks, program state, the
/// session's completed flag) and then makes them durable in one step: either
/// everything saves, or everything staged is rolled back and the failure
/// propagates to the caller. External side effects (HealthKit mirroring,
/// notification scheduling) belong strictly AFTER a successful commit — never
/// before it, and never when it throws — so a failed save can't leave phantom
/// workouts or check-ins behind. Mirrored as `completionCommit` in
/// web/js/core.js (where IndexedDB gives the web app this atomicity natively).
public enum CompletionPersistence {

    /// Make staged completion changes durable, or undo them and rethrow.
    /// `save` persists the staged batch; `rollback` must discard every staged
    /// mutation, returning state to the last durable checkpoint.
    public static func commit(save: () throws -> Void, rollback: () -> Void) throws {
        do {
            try save()
        } catch {
            rollback()
            throw error
        }
    }
}
