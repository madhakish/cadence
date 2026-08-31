import CadenceCore
import Foundation
import SwiftData

/// The one owner of program activation (epic #155 Stage 4). Activation used
/// to be a toggle that mutated `isActive` inline in Settings; every rule
/// below now lives here, on both clients, so switching methodologies is a
/// first-class action instead of a checkbox with implications.
///
/// Mirrors web `programActivation` in views/settings.js.
enum ProgramActivationService {
    enum ActivationError: LocalizedError, Equatable {
        /// An open session belongs to a different program. Switching would
        /// either orphan it or silently retag its work, so it fails loudly
        /// and the lifter decides: finish it, or discard it.
        case openSessionBelongsToAnotherProgram(String)

        var errorDescription: String? {
            switch self {
            case .openSessionBelongsToAnotherProgram(let name):
                return "You have an unfinished \(name) workout. Finish or discard it before switching programs."
            }
        }
    }

    /// Resume an existing block. Flips activation and NOTHING else: the
    /// cycle, rotation, next day, per-slot stalls, and pending peak results
    /// are exactly where the lifter left them, and no weight is re-derived.
    static func activate(_ program: Program, context: ModelContext) throws {
        try assertNoForeignOpenSession(target: program, context: context)
        for other in try context.fetch(FetchDescriptor<Program>())
        where other.isActive && other.id != program.id {
            other.isActive = false
        }
        program.isActive = true
    }

    /// Suspend the active block. History, cursors, and pending state stay
    /// untouched — this is a pause, never a reset.
    static func suspend(_ program: Program) {
        program.isActive = false
    }

    /// Start a new block from a template, seeded from CURRENT global history
    /// through the anchor resolver — no weight prompt, no re-entry. Every
    /// existing instance is preserved (and its history with it); the new
    /// program becomes active only after the store accepts it, so a failed
    /// write can never leave two active programs or none.
    @discardableResult
    static func startBlock(
        _ template: ProgramTemplateData.Template, context: ModelContext
    ) throws -> Program {
        let target = try ProgramTemplates.instantiate(template, context: context)
        try assertNoForeignOpenSession(target: target, context: context)
        try context.save()
        try activate(target, context: context)
        return target
    }

    /// Programs grouped by the methodology they came from — the switcher's
    /// "resume" list. Legacy programs carry no template origin and group
    /// under nil rather than being guessed into a style.
    static func instances(
        byTemplate programs: [Program]
    ) -> [String?: [Program]] {
        Dictionary(grouping: programs, by: \.templateID)
    }

    private static func assertNoForeignOpenSession(
        target: Program, context: ModelContext
    ) throws {
        let open = try context.fetch(
            FetchDescriptor<WorkoutSession>(predicate: #Predicate { !$0.isCompleted })
        )
        for session in open {
            // An untagged ad-hoc session belongs to no program and blocks
            // nothing; only work built from a DIFFERENT program does.
            guard let programID = session.programID, programID != target.id else { continue }
            throw ActivationError.openSessionBelongsToAnotherProgram(
                session.programName ?? "unfinished")
        }
    }
}
