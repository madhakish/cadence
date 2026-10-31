import CadenceCore
import Foundation
import SwiftData

/// Phone side of watch session sync (design: docs/superpowers/specs/
/// 2026-10-18-apple-watch-design.md, sections 3–5). Models only, so the
/// hostless migration suite exercises it on real SwiftData rows.
///
/// The merge itself lives in CadenceCore (`SyncReplica`); this file turns a
/// SwiftData session into the snapshot the watch runs, creates the SwiftData
/// session a watch start describes, and writes each merged view back onto the
/// rows, addressed by `syncID`, never by position.
@MainActor
enum WatchSessionSync {
    /// Planning detail the watch never needs but banking does. Encoded into
    /// `SyncSessionSnapshot.phoneContext`; the watch returns it unchanged.
    struct PhoneContext: Codable, Equatable {
        struct Entry: Codable, Equatable {
            var notes: String
            var barID: String?
            var barIDIsManual: Bool
            var plannedWeightLb: Double?
            var targetWeightLb: Double?
            var plannedSets: Int?
            var plannedReps: Int?
            var plannedDurationSeconds: Int?
            var fallbackWeightLb: Double?
            var prescriptionStyleRaw: String
            var phaseRaw: Int?
            var tfhAnchorData: Data?
        }

        struct SetDetail: Codable, Equatable {
            var targetWeightLb: Double?
            var isPerSide: Bool
            var enteredUnitRaw: String
            var loadBasisRaw: String
            var implementCount: Int
            var distanceMiles: Double?
            var flights: Double?
            var inclinePercent: Double?
            var tfhBenchmarkData: Data?
        }

        var notes: String
        var gymID: String?
        var gymName: String?
        var programID: String?
        var programName: String?
        var programTemplateID: String?
        var programCycleNumber: Int?
        var programWeek: Int?
        var programDayIndex: Int?
        var programPlanNames: [String]?
        var tfhPolicyID: String?
        var tfhContext: String?
        var tfhExcludedFromProgression: Bool?
        var entries: [String: Entry]
        var sets: [String: SetDetail]
    }

    enum SyncError: Error, Equatable {
        case missingPhoneContext
        case unreadableSyncState
    }

    // MARK: Snapshot

    /// The watch's copy of `session`: what it shows and logs, plus the phone's
    /// planning detail as opaque context.
    static func snapshot(of session: WorkoutSession, title: String, builtAt: Date) throws -> SyncSessionSnapshot {
        var context = PhoneContext(
            notes: session.notes, gymID: session.gymID, gymName: session.gymName,
            programID: session.programID, programName: session.programName,
            programTemplateID: session.programTemplateID, programCycleNumber: session.programCycleNumber,
            programWeek: session.programWeek, programDayIndex: session.programDayIndex,
            programPlanNames: session.programPlanNames, tfhPolicyID: session.tfhPolicyID,
            tfhContext: session.tfhContext, tfhExcludedFromProgression: session.tfhExcludedFromProgression,
            entries: [:], sets: [:])
        var exercises: [SyncPlannedExercise] = []
        for entry in session.orderedExercises {
            context.entries[entry.syncID] = PhoneContext.Entry(
                notes: entry.notes, barID: entry.barID, barIDIsManual: entry.barIDIsManual,
                plannedWeightLb: entry.plannedWeightLb, targetWeightLb: entry.targetWeightLb,
                plannedSets: entry.plannedSets, plannedReps: entry.plannedReps,
                plannedDurationSeconds: entry.plannedDurationSeconds, fallbackWeightLb: entry.fallbackWeightLb,
                prescriptionStyleRaw: entry.prescriptionStyleRaw, phaseRaw: entry.phaseRaw,
                tfhAnchorData: entry.tfhAnchorData)
            let exercise = entry.exercise
            let catalog = SyncCatalogExercise(
                exerciseID: entry.exerciseID ?? exercise?.id ?? "",
                name: exercise?.name ?? "",
                isPerSide: entry.orderedSets.first?.isPerSide ?? false,
                loadBasis: LoadBasis(rawValue: exercise?.loadBasisRaw ?? "") ?? .totalBar,
                implementCount: exercise?.implementCount ?? 0)
            var sets: [SyncPlannedSet] = []
            for set in entry.orderedSets {
                context.sets[set.syncID] = PhoneContext.SetDetail(
                    targetWeightLb: set.targetWeightLb, isPerSide: set.isPerSide, enteredUnitRaw: set.enteredUnitRaw,
                    loadBasisRaw: set.loadBasisRaw, implementCount: set.implementCount,
                    distanceMiles: set.distanceMiles, flights: set.flights, inclinePercent: set.inclinePercent,
                    tfhBenchmarkData: set.tfhBenchmarkData)
                sets.append(SyncPlannedSet(
                    id: set.syncID, status: set.status, reps: set.reps, weightLb: set.weightLb,
                    durationSeconds: set.durationSeconds, isWarmup: set.isWarmup, flags: set.flagsRaw,
                    autoregReason: set.autoregReasonRaw.flatMap(AutoregReason.init(rawValue:)),
                    plannedReps: set.plannedReps, plannedWeightLb: set.plannedWeightLb,
                    plannedDurationSeconds: set.plannedDurationSeconds,
                    prescriptionBlock: PrescriptionBlockKind(rawValue: set.prescriptionBlockRaw) ?? .work))
            }
            exercises.append(SyncPlannedExercise(id: entry.syncID, catalog: catalog,
                                                 programSlotID: entry.programSlotID,
                                                 programRole: entry.programRole, sets: sets))
        }
        let position = session.programID.flatMap { id -> SyncProgramPosition? in
            guard let cycle = session.programCycleNumber, let week = session.programWeek,
                  let day = session.programDayIndex else { return nil }
            return SyncProgramPosition(programID: id, cycle: cycle, week: week, dayIndex: day,
                                       tfhPolicyID: session.tfhPolicyID)
        }
        return SyncSessionSnapshot(title: title, position: position, builtAt: builtAt, exercises: exercises,
                                   phoneContext: try JSONEncoder().encode(context))
    }

    /// The next program day as the watch should run it, built exactly as
    /// Start would build it but in a scratch context that is never saved, so
    /// nothing is inserted into the owner's store (design section 3).
    static func plannedSnapshot(program: Program, day: ProgramDay, container: ModelContainer,
                                builtAt: Date) throws -> SyncSessionSnapshot {
        let scratch = ModelContext(container)
        scratch.autosaveEnabled = false
        defer { scratch.rollback() }
        guard let scratchProgram = scratch.model(for: program.persistentModelID) as? Program,
              let scratchDay = scratch.model(for: day.persistentModelID) as? ProgramDay else {
            throw SyncError.missingPhoneContext
        }
        let session = try ProgramSession.make(program: scratchProgram, day: scratchDay, context: scratch)
        return try snapshot(of: session, title: day.name, builtAt: builtAt)
    }

    // MARK: Watch-started sessions

    /// Create the SwiftData session a watch `sessionStarted` describes, with the
    /// watch-minted session ID and every entry and set ID unchanged.
    static func materialize(_ replica: SyncReplica, startedAt: Date, context: ModelContext) throws -> WorkoutSession {
        guard let data = replica.snapshot.phoneContext else { throw SyncError.missingPhoneContext }
        let phone = try JSONDecoder().decode(PhoneContext.self, from: data)
        let session = WorkoutSession(date: startedAt, notes: phone.notes, gymID: phone.gymID, gymName: phone.gymName)
        session.id = replica.sessionID
        session.programID = phone.programID
        session.programName = phone.programName
        session.programTemplateID = phone.programTemplateID
        session.programCycleNumber = phone.programCycleNumber
        session.programWeek = phone.programWeek
        session.programDayIndex = phone.programDayIndex
        session.programPlanNames = phone.programPlanNames
        session.tfhPolicyID = phone.tfhPolicyID
        session.tfhContext = phone.tfhContext
        session.tfhExcludedFromProgression = phone.tfhExcludedFromProgression
        context.insert(session)
        try project(replica.view(), onto: session, phone: phone, context: context)
        return session
    }

    // MARK: Projection

    /// The SwiftData `syncID` for a view entry. Entries the merge derived (work
    /// performed as a since-swapped exercise) have a composite view ID; it maps
    /// to a deterministic UUID so every projection finds the same row.
    static func entrySyncID(forViewID id: String) -> String {
        UUID(uuidString: id) != nil ? id : StableID.uuid(from: "watch-sync-entry:" + id)
    }

    /// Write a merged view onto `session`'s rows: create what is new, update
    /// changed fields only, reorder, and delete rows the merge hides. Idempotent:
    /// projecting the same view twice changes nothing. The caller saves.
    static func project(_ view: SyncSessionView, onto session: WorkoutSession,
                        phone: PhoneContext?, context: ModelContext) throws {
        var library: [String: Exercise] = [:]
        for exercise in try context.fetch(FetchDescriptor<Exercise>()) {
            if let id = exercise.id { library[id] = exercise }
        }
        var entries: [String: SessionExercise] = [:]
        var sets: [String: SetEntry] = [:]
        for entry in session.exercises {
            entries[entry.syncID] = entries[entry.syncID] ?? entry
            for set in entry.sets { sets[set.syncID] = sets[set.syncID] ?? set }
        }
        var keptEntries: Set<PersistentIdentifier> = []
        var keptSets: Set<PersistentIdentifier> = []

        for (index, item) in view.exercises.enumerated() {
            let key = entrySyncID(forViewID: item.id)
            let entry: SessionExercise
            if let existing = entries[key] {
                entry = existing
            } else {
                entry = SessionExercise(order: index, exercise: library[item.catalog.exerciseID])
                entry.syncID = key
                entry.exerciseID = item.catalog.exerciseID
                if let detail = phone?.entries[item.id] {
                    entry.notes = detail.notes
                    entry.barID = detail.barID
                    entry.barIDIsManual = detail.barIDIsManual
                    entry.plannedWeightLb = detail.plannedWeightLb
                    entry.targetWeightLb = detail.targetWeightLb
                    entry.plannedSets = detail.plannedSets
                    entry.plannedReps = detail.plannedReps
                    entry.plannedDurationSeconds = detail.plannedDurationSeconds
                    entry.fallbackWeightLb = detail.fallbackWeightLb
                    entry.prescriptionStyleRaw = detail.prescriptionStyleRaw
                    entry.phaseRaw = detail.phaseRaw
                    entry.tfhAnchorData = detail.tfhAnchorData
                }
                context.insert(entry)
                entry.session = session
                entries[key] = entry
            }
            keptEntries.insert(entry.persistentModelID)
            if entry.order != index { entry.order = index }
            if entry.programSlotID != item.programSlotID { entry.programSlotID = item.programSlotID }
            if entry.programRole != item.programRole { entry.programRole = item.programRole }
            if entry.exerciseID != item.catalog.exerciseID {
                // A phone-side swap reached this row: follow the catalog exercise.
                entry.exerciseID = item.catalog.exerciseID
                entry.exercise = library[item.catalog.exerciseID]
            }

            for (setIndex, value) in item.sets.enumerated() {
                let set: SetEntry
                if let existing = sets[value.id] {
                    set = existing
                } else {
                    let created = value.created
                    let detail = phone?.sets[value.id]
                    set = SetEntry(order: setIndex, weightLb: created.weightLb, reps: created.reps,
                                   isWarmup: created.isWarmup, status: created.status,
                                   isPerSide: detail?.isPerSide ?? item.catalog.isPerSide,
                                   durationSeconds: created.durationSeconds,
                                   distanceMiles: detail?.distanceMiles, flights: detail?.flights,
                                   inclinePercent: detail?.inclinePercent,
                                   loadBasis: LoadBasis(rawValue: detail?.loadBasisRaw ?? "") ?? item.catalog.loadBasis,
                                   implementCount: detail?.implementCount ?? item.catalog.implementCount,
                                   autoregReason: created.autoregReason,
                                   targetWeightLb: detail?.targetWeightLb,
                                   plannedWeightLb: created.plannedWeightLb, plannedReps: created.plannedReps,
                                   plannedDurationSeconds: created.plannedDurationSeconds,
                                   prescriptionBlock: created.prescriptionBlock)
                    set.syncID = value.id
                    set.flagsRaw = created.flags
                    if let unit = detail?.enteredUnitRaw { set.enteredUnitRaw = unit }
                    set.tfhBenchmarkData = detail?.tfhBenchmarkData
                    context.insert(set)
                    sets[value.id] = set
                }
                keptSets.insert(set.persistentModelID)
                if set.sessionExercise !== entry { set.sessionExercise = entry }
                if set.order != setIndex { set.order = setIndex }
                if set.statusRaw != value.status.rawValue { set.statusRaw = value.status.rawValue }
                if set.reps != value.reps { set.reps = value.reps }
                if set.weightLb != value.weightLb { set.weightLb = value.weightLb }
                if set.durationSeconds != value.durationSeconds { set.durationSeconds = value.durationSeconds }
                if set.isWarmup != value.isWarmup { set.isWarmup = value.isWarmup }
                if set.flagsRaw != value.flags { set.flagsRaw = value.flags }
                if set.autoregReasonRaw != value.autoregReason?.rawValue { set.autoregReasonRaw = value.autoregReason?.rawValue }
            }
        }
        for set in sets.values where !keptSets.contains(set.persistentModelID) {
            context.delete(set)
        }
        for entry in entries.values where !keptEntries.contains(entry.persistentModelID) {
            context.delete(entry)
        }
    }

    // MARK: Phone-side edits

    /// Turn every difference between `session`'s rows and the merged view into
    /// phone operations on `endpoint`, applied there first. The phone's logger
    /// edits rows directly; capturing before each projection means a phone
    /// edit is never overwritten by the merge, and reaches the watch as an
    /// ordinary operation. Returns the operations issued (empty when the rows
    /// already match).
    static func captureLocalEdits(of session: WorkoutSession, into endpoint: inout SyncEndpoint,
                                  now: Date, makeID: () -> String = { UUID().uuidString }) -> [SyncOperation] {
        guard let replica = endpoint.replica else { return [] }
        var issued: [SyncOperation] = []
        func issue(_ payload: SyncPayload) {
            if let op = endpoint.issue(payload, operationID: makeID(), now: now) { issued.append(op) }
        }
        let view = replica.view()
        // Rows for entries the merge derived are its output, not phone edits.
        var viewIDBySyncID: [String: String] = [:]
        for item in view.exercises { viewIDBySyncID[entrySyncID(forViewID: item.id)] = item.id }
        let derived = Set(view.exercises.filter { UUID(uuidString: $0.id) == nil }.map { entrySyncID(forViewID: $0.id) })
        let viewSets = Dictionary(view.exercises.flatMap(\.sets).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let entries = session.orderedExercises.filter { !derived.contains($0.syncID) }
        let rowSetIDs = Set(entries.flatMap(\.sets).map(\.syncID))

        // Entries: added, swapped, reordered.
        var previousEntryID: String?
        for entry in entries {
            if let viewID = viewIDBySyncID[entry.syncID] {
                let item = view.exercises.first { $0.id == viewID }!
                if let catalogID = entry.exerciseID, catalogID != item.catalog.exerciseID {
                    issue(.exerciseReplaced(exerciseID: viewID, catalog: SyncCatalogExercise(
                        exerciseID: catalogID, name: entry.exercise?.name ?? item.catalog.name,
                        isPerSide: entry.orderedSets.first?.isPerSide ?? item.catalog.isPerSide,
                        loadBasis: LoadBasis(rawValue: entry.exercise?.loadBasisRaw ?? "") ?? item.catalog.loadBasis,
                        implementCount: entry.exercise?.implementCount ?? item.catalog.implementCount)))
                }
                // The live order (earlier moves in this pass already applied),
                // without the merge's derived entries.
                let order = (endpoint.replica?.view().exercises.map(\.id) ?? []).filter { UUID(uuidString: $0) != nil }
                let currentPrevious = order.firstIndex(of: viewID).flatMap { $0 > 0 ? order[$0 - 1] : nil }
                if currentPrevious != previousEntryID {
                    issue(.exerciseMoved(exerciseID: viewID, after: previousEntryID))
                }
            } else if let added = try? snapshotEntry(entry) {
                issue(.exerciseAdded(after: previousEntryID, exercise: added))
                viewIDBySyncID[entry.syncID] = entry.syncID
            }
            previousEntryID = viewIDBySyncID[entry.syncID]
        }
        let rowEntryIDs = Set(entries.map(\.syncID))
        for item in view.exercises where UUID(uuidString: item.id) != nil && !rowEntryIDs.contains(item.id) {
            issue(.exerciseRemoved(exerciseID: item.id,
                                   sawStatus: endpoint.replica?.newestStatusStamp(inExercise: item.id)
                                       ?? SyncStamp(version: 0, device: .phone)))
        }

        // Sets: added, removed, edited.
        let current = endpoint.replica?.view() ?? view
        let currentSets = Dictionary(current.exercises.flatMap(\.sets).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for entry in entries {
            guard let viewID = viewIDBySyncID[entry.syncID] else { continue }
            var previousSetID: String?
            for set in entry.orderedSets {
                if let value = currentSets[set.syncID] ?? viewSets[set.syncID] {
                    var patch = SyncSetPatch()
                    var changed = false
                    if set.status != value.status {
                        patch.status = set.status; changed = true
                        if set.status == .completed { patch.performedAs = entry.exerciseID }
                    }
                    if set.reps != value.reps { patch.reps = set.reps; changed = true }
                    if set.weightLb != value.weightLb { patch.weightLb = set.weightLb; changed = true }
                    if set.durationSeconds != value.durationSeconds, let seconds = set.durationSeconds {
                        patch.durationSeconds = seconds; changed = true
                    }
                    if set.isWarmup != value.isWarmup { patch.isWarmup = set.isWarmup; changed = true }
                    let reason = set.autoregReasonRaw.flatMap(AutoregReason.init(rawValue:))
                    if reason != value.autoregReason { patch.autoregReason = SyncValue(reason); changed = true }
                    if changed { issue(.setPerformed(setID: set.syncID, patch: patch)) }
                    if set.flagsRaw != value.flags { issue(.setFlags(setID: set.syncID, flags: set.flagsRaw)) }
                } else {
                    issue(.setAdded(exerciseID: viewID, after: previousSetID, set: plannedSet(set)))
                }
                previousSetID = set.syncID
            }
        }
        for item in current.exercises where rowEntryIDs.contains(entrySyncID(forViewID: item.id)) {
            for value in item.sets where !rowSetIDs.contains(value.id) {
                issue(.setRemoved(setID: value.id, sawStatus: endpoint.replica?.statusStamp(ofSet: value.id)
                    ?? SyncStamp(version: 0, device: .phone)))
            }
        }
        return issued
    }

    private static func plannedSet(_ set: SetEntry) -> SyncPlannedSet {
        SyncPlannedSet(id: set.syncID, status: set.status, reps: set.reps, weightLb: set.weightLb,
                       durationSeconds: set.durationSeconds, isWarmup: set.isWarmup, flags: set.flagsRaw,
                       autoregReason: set.autoregReasonRaw.flatMap(AutoregReason.init(rawValue:)),
                       plannedReps: set.plannedReps, plannedWeightLb: set.plannedWeightLb,
                       plannedDurationSeconds: set.plannedDurationSeconds,
                       prescriptionBlock: PrescriptionBlockKind(rawValue: set.prescriptionBlockRaw) ?? .work)
    }

    private static func snapshotEntry(_ entry: SessionExercise) throws -> SyncPlannedExercise {
        let exercise = entry.exercise
        return SyncPlannedExercise(
            id: entry.syncID,
            catalog: SyncCatalogExercise(exerciseID: entry.exerciseID ?? exercise?.id ?? "", name: exercise?.name ?? "",
                                         isPerSide: entry.orderedSets.first?.isPerSide ?? false,
                                         loadBasis: LoadBasis(rawValue: exercise?.loadBasisRaw ?? "") ?? .totalBar,
                                         implementCount: exercise?.implementCount ?? 0),
            programSlotID: entry.programSlotID, programRole: entry.programRole,
            sets: entry.orderedSets.map(plannedSet))
    }

    // MARK: Persisted sync state

    static func phoneContext(of replica: SyncReplica) throws -> PhoneContext? {
        guard let data = replica.snapshot.phoneContext else { return nil }
        return try JSONDecoder().decode(PhoneContext.self, from: data)
    }

    static func endpoint(of session: WorkoutSession) throws -> SyncEndpoint? {
        guard let data = session.syncStateData else { return nil }
        do { return try JSONDecoder().decode(SyncEndpoint.self, from: data) } catch { throw SyncError.unreadableSyncState }
    }

    static func store(_ endpoint: SyncEndpoint, in session: WorkoutSession) throws {
        session.syncStateData = try JSONEncoder().encode(endpoint)
    }

    /// Wall-clock timing for the Health workout, from the session start and the
    /// merged pause/resume events.
    static func healthTiming(startedAt: Date, view: SyncSessionView) -> HealthWorkoutTiming {
        var timing = HealthWorkoutTiming(start: startedAt)
        for event in view.timing {
            if event.paused { timing.pause(at: event.at) } else { timing.resume(at: event.at) }
        }
        return timing
    }
}

extension WorkoutSession {
    /// The watch's Health outcome for this session (schema V16). Nil means the
    /// watch wrote no workout.
    var watchHealthOutcome: SyncHealthOutcome? {
        get {
            switch watchHealthOutcomeRaw {
            case "saved": return .saved(workoutID: watchHealthWorkoutID ?? "")
            case "notWritten": return .notWritten
            case "unknown": return .unknown
            default: return nil
            }
        }
        set {
            switch newValue {
            case .saved(let id)?: watchHealthOutcomeRaw = "saved"; watchHealthWorkoutID = id
            case .notWritten?: watchHealthOutcomeRaw = "notWritten"; watchHealthWorkoutID = nil
            case .unknown?: watchHealthOutcomeRaw = "unknown"; watchHealthWorkoutID = nil
            case nil: watchHealthOutcomeRaw = nil; watchHealthWorkoutID = nil
            }
        }
    }
}
