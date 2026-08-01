import Foundation
import SwiftData
import CadenceCore

/// Applies a standalone program file.
///
/// Deliberately NOT `ImportService`. That path REPLACES whole domains — it
/// opens with `context.delete(model: Program.self)` and recreates from the
/// bundle. A program file is additive by nature: it creates one program and
/// touches nothing else. The precedent to follow is
/// `ProgramTemplates.instantiate` + `uniqueProgramName`, not the backup
/// restore. Mirrors web `program-file.js` `importProgramFile`.
///
/// Two invariants hold throughout:
///
///   1. Only the program tree is written. No session, bodyweight, milestone,
///      gym, track, coaching, or settings record is modified — and the
///      exercise library is READ ONLY, never inserted into.
///   2. Nothing is written until the file has fully validated AND every
///      exercise name has resolved. A file that cannot be fully applied
///      changes nothing.
enum ProgramImportService {

    enum ImportError: LocalizedError {
        case notAProgramFile
        case unsupportedSchemaVersion(Int)
        case invalidData(String)
        case unresolvedExercises([String])
        /// Slot ids the file wants to keep that are already live on another
        /// program: `(slotID, owningProgramName)`.
        case slotIdentityCollision([(String, String)])
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .notAProgramFile:
                return "That file isn't a Cadence program."
            case .unsupportedSchemaVersion(let version):
                return "This program file uses version \(version), which this version of Cadence can't read. Update Cadence and try again."
            case .invalidData(let reason):
                return reason
            case .unresolvedExercises(let names):
                let list = names.map { "\"\($0)\"" }.joined(separator: ", ")
                let subject = names.count == 1 ? "Exercise \(list) is" : "Exercises \(list) are"
                return "Program import failed: \(subject) not in your library. "
                    + "Add it there first, or rename the slot to a name or alias you already have. Nothing was changed."
            case .slotIdentityCollision(let collisions):
                let named = collisions
                    .map { "\"\($0.0)\" (already used by \"\($0.1)\")" }
                    .joined(separator: ", ")
                return "Program import failed: slot \(collisions.count == 1 ? "id" : "ids") \(named). "
                    + "Importing with identity preserved would give two slots the same history linkage. "
                    + "Nothing was changed."
            case .writeFailed:
                return "Couldn't import the program — nothing was changed."
            }
        }
    }

    /// What the import did, so the caller can say so rather than succeed
    /// silently.
    struct Report {
        enum Action: String { case created, updated }
        let action: Action
        let programID: String
        let name: String
        let days: Int
        let lifts: Int
        let accessories: Int
        let carriedState: Bool
        /// Non-fatal notes — currently gated exercises the program references.
        let warnings: [String]

        var summary: String {
            let verb = action == .created ? "Created" : "Updated"
            return "\(verb) “\(name)” — \(days) day\(days == 1 ? "" : "s"), "
                + "\(lifts) lift\(lifts == 1 ? "" : "s"), \(accessories) accessor\(accessories == 1 ? "y" : "ies")."
        }
    }

    struct Options {
        /// Reuse the file's program and slot UUIDs, updating a program already
        /// carrying that id instead of creating a copy. Off by default: slot
        /// ids are what banked sessions point at, so adopting them is an
        /// explicit choice.
        var preserveIdentity: Bool = false

        static let additive = Options()

        init(preserveIdentity: Bool = false) {
            self.preserveIdentity = preserveIdentity
        }
    }

    /// Just the envelope, so the discriminator and version can be read even
    /// when the payload itself is a shape this build cannot decode.
    private struct Envelope: Decodable {
        let kind: String?
        let programSchemaVersion: Int?
    }

    /// Dotted field path from a decoding error, matching the web importer's
    /// convention (`program.days[0].lifts[2].deloadMultiplier`).
    private static func path(of error: DecodingError) -> String {
        let context: DecodingError.Context
        switch error {
        case .typeMismatch(_, let c), .valueNotFound(_, let c),
             .keyNotFound(_, let c), .dataCorrupted(let c):
            context = c
        @unknown default:
            return "file"
        }
        var parts: [String] = []
        for key in context.codingPath {
            if let index = key.intValue {
                parts[parts.isEmpty ? 0 : parts.count - 1] += "[\(index)]"
            } else {
                parts.append(key.stringValue)
            }
        }
        if case .keyNotFound(let key, _) = error { parts.append(key.stringValue) }
        return parts.isEmpty ? "file" : parts.joined(separator: ".")
    }

    private static func reason(of error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, _): return "expected \(type)"
        case .valueNotFound(let type, _): return "expected a value of type \(type)"
        case .keyNotFound: return "is required"
        case .dataCorrupted: return "is not readable"
        @unknown default: return "is not readable"
        }
    }

    // MARK: - Entry point

    @discardableResult
    static func load(_ data: Data, into context: ModelContext, options: Options = .additive) throws -> Report {
        // Read the envelope BEFORE the full decode. A version-2 file that adds
        // a required field would otherwise fail `decode` first and be reported
        // as "not a Cadence program", when the honest answer — and the one the
        // forward-compatibility contract promises — is "update Cadence".
        let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        guard let envelope, envelope.kind == ProgramFileContract.kind else {
            throw ImportError.notAProgramFile
        }
        guard ProgramFileContract.supports(schemaVersion: envelope.programSchemaVersion) else {
            throw ImportError.unsupportedSchemaVersion(envelope.programSchemaVersion ?? 0)
        }
        let file: ProgramFileContract.File
        do {
            file = try JSONDecoder().decode(ProgramFileContract.File.self, from: data)
        } catch let error as DecodingError {
            // Hand-editing is a documented workflow, so name the field rather
            // than reject the whole file anonymously. Mirrors the dotted paths
            // the web importer reports.
            throw ImportError.invalidData(
                "Program file validation failed at \(Self.path(of: error)): \(Self.reason(of: error)). Nothing was changed."
            )
        } catch {
            throw ImportError.notAProgramFile
        }
        do {
            try ProgramFileContract.validate(file)
        } catch let error as ProgramFileContract.ValidationError {
            throw ImportError.invalidData(error.description)
        }

        let payload = file.program

        // Read-only view of the library. If the fetch itself fails we must not
        // write: resolving against an unverifiable library could bind slots to
        // the wrong movement.
        let library = try context.fetch(FetchDescriptor<Exercise>())
        let (resolved, gated) = try resolve(payload, library: library)

        let existingPrograms = try context.fetch(FetchDescriptor<Program>())
        let existing = options.preserveIdentity
            ? payload.id.flatMap { id in existingPrograms.first { $0.id == id } }
            : nil

        // [INV-SLOT-ID-IS-UNIQUE] Adopting the file's slot ids must not give
        // two live slots the same id. Only reachable through preserveIdentity —
        // the additive path re-mints every id — and the program being updated
        // is excluded, since its own slots are the ones being replaced.
        if options.preserveIdentity {
            var owners: [String: String] = [:]
            for other in existingPrograms where other.id != existing?.id {
                for day in other.orderedDays {
                    let ids = day.orderedLifts.map(\.id) + day.orderedAccessories.map(\.id)
                    for id in ids where owners[id] == nil {
                        owners[id] = other.name
                    }
                }
            }
            let collisions = ProgramFileContract.collidingSlotIDs(payload, liveElsewhere: Set(owners.keys))
            if !collisions.isEmpty {
                throw ImportError.slotIdentityCollision(collisions.map { ($0, owners[$0] ?? "another program") })
            }
        }

        do {
            let report = try apply(payload, resolved: resolved, gated: gated, existing: existing,
                                   existingPrograms: existingPrograms, options: options, context: context)
            try context.save()
            return report
        } catch {
            context.rollback()
            throw ImportError.writeFailed
        }
    }

    // MARK: - Exercise resolution

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// Canonical name first, then aliases. Never creates a stub: `loadBasis`
    /// and `movementPattern` decide how a slot progresses and how its volume
    /// counts, so a guessed definition produces confidently wrong
    /// prescriptions — worse than an import the lifter can see failed.
    private static func resolve(
        _ payload: ProgramFileContract.Program, library: [Exercise]
    ) throws -> (resolved: [String: Exercise], gated: [String]) {
        var byName: [String: Exercise] = [:]
        var byAlias: [String: Exercise] = [:]
        for exercise in library {
            byName[normalized(exercise.name)] = exercise
            for alias in exercise.aliases {
                let key = normalized(alias)
                // A canonical name always beats someone else's alias.
                if byAlias[key] == nil { byAlias[key] = exercise }
            }
        }

        var resolved: [String: Exercise] = [:]
        var missing: [String] = []
        var gated: [String] = []
        for day in payload.days {
            // Revert markers are resolved too. The marker is the name a slot
            // springs back to at cycle rollover, and SessionCompletion writes
            // it straight onto the slot — so an unresolvable marker leaves the
            // slot bound to no exercise definition weeks after the import
            // looked like it worked.
            var names: [String] = []
            for lift in day.lifts {
                names.append(lift.exerciseName)
                if let revert = lift.revertToExerciseName { names.append(revert) }
            }
            for accessory in day.accessories {
                names.append(accessory.exerciseName)
                if let revert = accessory.revertToExerciseName { names.append(revert) }
            }
            for raw in names where resolved[raw] == nil {
                let key = normalized(raw)
                guard let match = byName[key] ?? byAlias[key] else {
                    if !missing.contains(raw) { missing.append(raw) }
                    continue
                }
                resolved[raw] = match
                if match.gateStatus == .shelved || match.gateStatus == .reEntry,
                   !gated.contains(match.name) {
                    gated.append(match.name)
                }
            }
        }
        guard missing.isEmpty else { throw ImportError.unresolvedExercises(missing) }
        return (resolved, gated)
    }

    // MARK: - Apply

    private static func apply(
        _ payload: ProgramFileContract.Program,
        resolved: [String: Exercise],
        gated: [String],
        existing: Program?,
        existingPrograms: [Program],
        options: Options,
        context: ModelContext
    ) throws -> Report {
        let carriesState = payload.carriesState

        let program: Program
        if let existing {
            program = existing
            // A rename in the file is honoured, but still has to stay unique:
            // Program.name is @Attribute(.unique), so adopting a colliding name
            // would upsert into a different program. The web mirror applies the
            // same rule, so the clients cannot disagree about the same file.
            if existing.name != payload.name {
                existing.name = ProgramTemplates.uniqueProgramName(
                    payload.name, existing: existingPrograms.filter { $0 !== existing }.map(\.name)
                )
            }
            // Replacing the day tree wholesale is the point of an update: the
            // file is the new definition. Cascade deletes take the old slots.
            for day in existing.days { context.delete(day) }
            existing.days = []
        } else {
            // Program.name is unique — a fixed name would silently UPSERT into
            // an in-progress program, resetting its wave state.
            let name = ProgramTemplates.uniqueProgramName(
                payload.name, existing: existingPrograms.map(\.name)
            )
            program = Program(
                name: name,
                focus: TrainingFocus(rawValue: payload.focus) ?? .strength,
                roundingLb: payload.roundingLb,
                // An import never takes the active flag from a program the
                // lifter is mid-cycle on. An empty store has nothing to steal.
                isActive: existingPrograms.isEmpty
            )
            if options.preserveIdentity, let id = payload.id { program.id = id }
            context.insert(program)
        }

        program.focus = TrainingFocus(rawValue: payload.focus) ?? .strength
        program.roundingLb = payload.roundingLb
        program.coachEnabled = payload.coachEnabled
        program.preferredSessionSpacingDays = payload.preferredSessionSpacingDays
        program.maximumAddedSetsPerRotation = payload.maximumAddedSetsPerRotation
        program.cycleNumber = carriesState ? (payload.cycleNumber ?? 1) : 1
        program.currentWeek = carriesState ? (payload.currentWeek ?? 1) : 1
        program.nextDayIndex = carriesState ? (payload.nextDayIndex ?? 0) : 0

        for dayPayload in payload.days {
            let day = ProgramDay(name: dayPayload.name, order: dayPayload.order)
            context.insert(day)   // insert before appending children (Seeder pattern)
            // Mutate ONE side of each SwiftData relationship. Setting the
            // inverse and appending as well stores the same reference twice,
            // which renders as mirrored editor rows and deletes destructively.
            program.days.append(day)

            // A file whose slots all say the same order carries no ordering
            // information beyond the sequence they were written in — keep it,
            // or the tie falls to the alphabetical display fallback.
            let liftOrders = ProgramEngine.authoredSlotOrders(dayPayload.lifts.map(\.order))
            let accessoryOrders = ProgramEngine.authoredSlotOrders(dayPayload.accessories.map(\.order))

            for (index, liftPayload) in dayPayload.lifts.enumerated() {
                guard let exercise = resolved[liftPayload.exerciseName] else { continue }
                let lift = ProgramLift(
                    id: options.preserveIdentity ? (liftPayload.id ?? UUID().uuidString) : UUID().uuidString,
                    exerciseName: exercise.name,
                    role: LiftRole(rawValue: liftPayload.role) ?? .main,
                    order: liftOrders[index],
                    prescription: PrescriptionStyle(rawValue: liftPayload.prescription) ?? .automatic,
                    warmupPolicy: WarmupPolicy(rawValue: liftPayload.warmupPolicy) ?? .automatic,
                    baseWeightLb: liftPayload.baseWeightLb,
                    estimatedMaxLb: liftPayload.estimatedMaxLb,
                    stallCount: carriesState ? (liftPayload.stallCount ?? 0) : 0,
                    lastIncrementLb: carriesState ? (liftPayload.lastIncrementLb ?? 0) : 0
                )
                lift.loadOffsetLb = liftPayload.loadOffsetLb
                lift.peakOffsetLb = liftPayload.peakOffsetLb
                lift.deloadMultiplier = liftPayload.deloadMultiplier
                lift.doubleProgressionSets = liftPayload.doubleProgressionSets
                lift.minimumReps = liftPayload.minimumReps
                lift.maximumReps = liftPayload.maximumReps
                lift.currentReps = liftPayload.currentReps
                lift.peakSingleEnabled = liftPayload.peakSingleEnabled
                lift.peakSingleIncrementLb = liftPayload.peakSingleIncrementLb
                lift.phasePrimerEnabled = liftPayload.phasePrimerEnabled
                lift.dropIncrementLb = liftPayload.dropIncrementLb
                lift.capacityManaged = liftPayload.capacityManaged
                lift.maximumSets = liftPayload.maximumSets
                if carriesState {
                    lift.lastPeakSingleLb = liftPayload.lastPeakSingleLb ?? 0
                    // Canonical, like exerciseName — an alias stored here would
                    // resolve to nothing when rollover applies it.
                    lift.revertToExerciseName = liftPayload.revertToExerciseName
                        .flatMap { resolved[$0]?.name }
                    if let pending = liftPayload.pending {
                        lift.pendingBaseWeightLb = pending.state.baseWeightLb
                        lift.pendingEstimatedMaxLb = pending.state.estimatedMaxLb
                        lift.pendingStallCount = pending.state.stallCount
                        lift.pendingLastIncrementLb = pending.state.lastIncrementLb
                        lift.pendingNote = pending.note
                    }
                }
                context.insert(lift)
                day.lifts.append(lift)
            }

            for (index, accessoryPayload) in dayPayload.accessories.enumerated() {
                guard let exercise = resolved[accessoryPayload.exerciseName] else { continue }
                let accessory = ProgramAccessory(
                    id: options.preserveIdentity ? (accessoryPayload.id ?? UUID().uuidString) : UUID().uuidString,
                    exerciseName: exercise.name,
                    order: accessoryOrders[index],
                    sets: accessoryPayload.sets,
                    minReps: accessoryPayload.minReps,
                    maxReps: accessoryPayload.maxReps,
                    currentReps: accessoryPayload.currentReps,
                    targetSeconds: accessoryPayload.targetSeconds,
                    durationStepSeconds: accessoryPayload.durationStepSeconds,
                    weightLb: accessoryPayload.weightLb,
                    incrementLb: accessoryPayload.incrementLb,
                    stallCount: carriesState ? (accessoryPayload.stallCount ?? 0) : 0
                )
                accessory.capacityManaged = accessoryPayload.capacityManaged
                accessory.maximumSets = accessoryPayload.maximumSets
                accessory.conditioningEffortRaw = accessoryPayload.conditioningEffort
                accessory.targetRPE = accessoryPayload.targetRPE
                if carriesState {
                    accessory.revertToExerciseName = accessoryPayload.revertToExerciseName
                        .flatMap { resolved[$0]?.name }
                }
                context.insert(accessory)
                day.accessories.append(accessory)
            }
        }

        return Report(
            action: existing == nil ? .created : .updated,
            programID: program.id,
            name: program.name,
            days: payload.days.count,
            lifts: payload.days.reduce(0) { $0 + $1.lifts.count },
            accessories: payload.days.reduce(0) { $0 + $1.accessories.count },
            carriedState: carriesState,
            warnings: gated.map {
                "\($0) is gated in your library — the slot imported, but it won't be programmed until you reopen it."
            }
        )
    }
}
