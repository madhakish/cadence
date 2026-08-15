import Foundation

/// Session→program linkage, spelled once.
///
/// The name fallback exists ONLY for ID-less legacy sessions: a session
/// carrying a non-nil programID belongs to that program and no other — a
/// deleted program's sessions must never be attributed to a later program
/// that reuses the display name. Half the call sites had this guard
/// (the resume filter, lastVolumeEvidence — with its "a non-nil foreign ID
/// must never feed this program's evidence" doctrine — and recallEntry) and
/// half spelled the unguarded `id match || name match`, so grading could
/// mutate progression from history that planning deliberately excluded.
/// Mirrors web db.js sessionBelongsToProgram.
extension WorkoutSession {
    func belongs(to program: Program) -> Bool {
        programID == program.id || (programID == nil && programName == program.name)
    }
}

extension Array where Element == Program {
    /// The program a session's linkage names, honoring the same guard: an ID
    /// resolves by ID or not at all; only an ID-less legacy session may fall
    /// back to the display name.
    func matching(sessionProgramID id: String?, name: String?) -> Program? {
        if let id { return first { $0.id == id } }
        return first { $0.name == name }
    }
}
