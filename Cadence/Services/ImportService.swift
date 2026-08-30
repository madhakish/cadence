import Foundation
import SwiftData
import CadenceCore

/// Restores a JSON backup produced by ExportService (or the web app) into
/// SwiftData — the missing other half of ExportService. Mirrors the web
/// `importBundle`: replaces each store the backup contains, leaves absent
/// stores untouched, and is all-or-nothing. The file is fully decoded before
/// anything is written, and any write failure rolls the context back.
enum ImportService {

    enum ImportError: LocalizedError {
        case notABackup, unsupportedSchemaVersion(Int), invalidData(String), writeFailed
        var errorDescription: String? {
            switch self {
            case .notABackup: return "That file isn't a Cadence backup."
            case .unsupportedSchemaVersion(let version):
                return "This backup uses schema version \(version), which this version of Cadence can't restore. Update Cadence and try again."
            case .invalidData(let reason): return "Backup validation failed at \(reason). Nothing was changed."
            case .writeFailed: return "Couldn't restore the backup — nothing was changed."
            }
        }
    }

    struct Summary {
        let sessions, programs, tracks, gyms: Int
        /// Slot ids the bundle reused across programs, re-minted on the way in.
        /// Reported rather than swallowed: silently rewriting identity is what
        /// this codebase refuses to do everywhere else.
        var repairedSlotIDs: Int = 0
    }

    // Lenient decode DTOs — optional everywhere so a partial or web-origin
    // backup never throws on a missing key.
    private struct Bundle: Decodable {
        var schemaVersion: Int?
        // `protein` was dropped in backup schema 6. Decodable ignores unknown
        // keys, so a v<=5 bundle's protein array is simply skipped — there is no
        // longer anywhere in the store to put it.
        var sessions: [Session]?; var bodyweight: [Bodyweight]?
        var checkIns: [CheckInDTO]?; var milestones: [MilestoneDTO]?; var programs: [ProgramDTO]?
        var tracks: [Track]?; var gyms: [GymDTO]?; var exercises: [ExerciseDef]?; var settings: SettingsDTO?
        var coachingDecisions: [CoachingDecisionDTO]?
        var intervals: [IntervalDTO]?
    }
    private struct IntervalDTO: Decodable {
        var id: String?; var kind: String?; var startDate: String?; var endDate: String?
        var enteredAsDays: Bool?; var note: String?; var programId: String?
    }
    private struct Session: Decodable {
        var id: String?; var programTemplateId: String?; var date: Date?; var notes: String?; var gym: String?; var gymId: String?; var isCompleted: Bool?
        var completedAt: Date?
        var programTag: ProgramTag?; var exercises: [ExerciseEntry]?
        var woodSplitting: WoodSplittingDTO?
    }
    /// v12 typed wood-splitting facts. Absent on every older bundle — the
    /// session simply restores with no detail; nothing is invented.
    private struct WoodSplittingDTO: Decodable {
        var sessionRPE: Double?; var rounds: Int?; var splitPieces: Int?
        var estimatedStrikes: Int?; var cordVolume: Double?
    }
    private struct ProgramTag: Decodable {
        var programId: String?; var programName: String?; var cycleNumber: Int?; var week: Int?; var dayIndex: Int?
        var planNames: [String]?

        private enum CodingKeys: String, CodingKey { case programId, programName, cycleNumber, week, dayIndex, planNames }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            programId = (try? c.decode(String.self, forKey: .programId))
                ?? (try? c.decode(Int.self, forKey: .programId)).map { String($0) }
            programName = try? c.decode(String.self, forKey: .programName)
            cycleNumber = try? c.decode(Int.self, forKey: .cycleNumber)
            week = try? c.decode(Int.self, forKey: .week)
            dayIndex = try? c.decode(Int.self, forKey: .dayIndex)
            planNames = try? c.decode([String].self, forKey: .planNames)
        }
    }
    private struct ExerciseEntry: Decodable {
        var name: String?; var exerciseId: String?; var notes: String?; var phase: String?; var role: String?
        var programSlotId: String?; var barId: String?; var barIdManual: Bool?
        var plannedWeightLb: Double?; var targetWeightLb: Double?; var plannedSets: Int?; var plannedReps: Int?
        var plannedDurationSeconds: Int?; var fallbackWeightLb: Double?; var prescriptionStyle: String?
        var sets: [SetDTO]?
    }
    private struct SetDTO: Decodable {
        var weightLb: Double?; var reps: Int?; var isWarmup: Bool?; var isPerSide: Bool?
        var targetWeightLb: Double?; var plannedWeightLb: Double?; var plannedReps: Int?
        var plannedDurationSeconds: Int?; var prescriptionBlock: String?
        var loadBasis: String?; var implementCount: Int?
        var status: String?
        var enteredUnit: String?; var flags: [String]?; var bodyFlagSite: String?; var bodyFlagNote: String?
        var durationSeconds: Int?; var distanceMiles: Double?; var flights: Double?
        var inclinePercent: Double?; var autoregReason: String?
    }
    private struct Bodyweight: Decodable { var date: Date?; var weightLb: Double?; var bodyFatPercent: Double?; var milestoneLabel: String? }
    private struct CheckInDTO: Decodable { var date: Date?; var site: String?; var response: String?; var note: String? }
    private struct MilestoneDTO: Decodable { var date: Date?; var exercise: String?; var exerciseId: String?; var kind: String?; var label: String? }
    private struct ProgramDTO: Decodable {
        var id: String?; var templateId: String?; var name: String?; var focus: String?; var cycleNumber: Int?; var currentWeek: Int?
        var nextDayIndex: Int?; var roundingLb: Double?; var isActive: Bool?; var days: [DayDTO]?
        var equipmentPolicy: String?
        var coachEnabled: Bool?; var reliableHistoryStart: Date?; var preferredSessionSpacingDays: Int?
        var maximumAddedSetsPerRotation: Int?

        private enum CodingKeys: String, CodingKey {
            case id, templateId, name, focus, cycleNumber, currentWeek, nextDayIndex, roundingLb, isActive, days
            case equipmentPolicy
            case coachEnabled, reliableHistoryStart, preferredSessionSpacingDays, maximumAddedSetsPerRotation
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decode(String.self, forKey: .id))
                ?? (try? c.decode(Int.self, forKey: .id)).map { String($0) }
            templateId = try? c.decode(String.self, forKey: .templateId)
            name = try? c.decode(String.self, forKey: .name)
            focus = try? c.decode(String.self, forKey: .focus)
            cycleNumber = try? c.decode(Int.self, forKey: .cycleNumber)
            currentWeek = try? c.decode(Int.self, forKey: .currentWeek)
            nextDayIndex = try? c.decode(Int.self, forKey: .nextDayIndex)
            roundingLb = try? c.decode(Double.self, forKey: .roundingLb)
            isActive = try? c.decode(Bool.self, forKey: .isActive)
            days = try? c.decode([DayDTO].self, forKey: .days)
            equipmentPolicy = try? c.decode(String.self, forKey: .equipmentPolicy)
            coachEnabled = try? c.decode(Bool.self, forKey: .coachEnabled)
            reliableHistoryStart = try? c.decode(Date.self, forKey: .reliableHistoryStart)
            preferredSessionSpacingDays = try? c.decode(Int.self, forKey: .preferredSessionSpacingDays)
            maximumAddedSetsPerRotation = try? c.decode(Int.self, forKey: .maximumAddedSetsPerRotation)
        }
    }
    private struct DayDTO: Decodable {
        var name: String?; var order: Int?; var trainingIntent: String?
        var lifts: [LiftDTO]?; var accessories: [AccessoryDTO]?
    }
    private struct LiftDTO: Decodable {
        var id: String?; var exerciseName: String?; var exerciseId: String?; var role: String?; var order: Int?
        var prescription: String?; var warmupPolicy: String?; var baseWeightLb: Double?; var estimatedMaxLb: Double?
        var loadOffsetLb: Double?; var peakOffsetLb: Double?; var deloadMultiplier: Double?
        var doubleProgressionSets: Int?; var minimumReps: Int?; var maximumReps: Int?; var currentReps: Int?
        var peakSingleEnabled: Bool?; var lastPeakSingleLb: Double?; var peakSingleIncrementLb: Double?
        var phasePrimerEnabled: Bool?; var dropIncrementLb: Double?; var capacityManaged: Bool?; var maximumSets: Int?
        var stallCount: Int?; var lastIncrementLb: Double?; var pending: PendingDTO?
        var revertToExerciseName: String?   // cycle-scoped swap, reverts at rollover
    }
    private struct PendingDTO: Decodable { var state: PendingState?; var note: String? }
    private struct PendingState: Decodable { var baseWeightLb: Double?; var estimatedMaxLb: Double?; var stallCount: Int?; var lastIncrementLb: Double? }
    private struct AccessoryDTO: Decodable {
        var id: String?; var exerciseName: String?; var exerciseId: String?; var order: Int?; var sets: Int?; var minReps: Int?; var maxReps: Int?
        var currentReps: Int?; var targetSeconds: Int?; var durationStepSeconds: Int?
        var capacityManaged: Bool?; var maximumSets: Int?; var conditioningEffort: String?; var targetRPE: Int?
        var weightLb: Double?; var incrementLb: Double?; var stallCount: Int?
        var revertToExerciseName: String?   // cycle-scoped swap, reverts at rollover
    }
    private struct Track: Decodable {
        var exerciseName: String?; var exerciseId: String?; var mode: String?; var cycleNumber: Int?; var baseWeightLb: Double?
        var nextPhase: Int?; var incrementLb: Double?; var roundingLb: Double?; var lastCompletedAt: Date?
    }
    private struct GymDTO: Decodable {
        var id: String?; var name: String?; var isDefault: Bool?; var defaultBarId: String?
        var collarWeightLb: Double?; var loadingPolicy: String?
        var plateToggles: [PlateToggleDTO]?; var barcodeImage: String?; var barcodeLabel: String?
    }
    private struct PlateToggleDTO: Decodable { var value: Double?; var unit: String?; var enabled: Bool? }
    private struct ExerciseDef: Decodable {
        var id: String?; var name: String?; var category: String?; var type: String?; var movementGroup: String?
        var movementPattern: String?; var secondaryMovementPattern: String?; var aliases: [String]?; var strategyTags: [String]?
        var isUnilateral: Bool?; var loadBasis: String?; var implementCount: Int?
        var defaultRestSeconds: Int?; var notes: String?
        var isShelved: Bool?; var shelvedNote: String?; var watchSite: String?; var createdAt: Date?
        var gateStatus: String?; var gateSite: String?; var reEntryCriteria: [String]?; var completedReEntryCriteria: [String]?
        var reEntryTestWeightLb: Double?; var reEntryTestSets: Int?; var reEntryTestReps: Int?
        var stationDenomination: String?
    }
    private struct CoachingDecisionDTO: Decodable {
        var id: String?; var date: Date?; var programId: String?; var ruleId: String?; var recommendationId: String?
        var action: String?; var title: String?; var explanation: String?; var evidence: [String]?
        var beforeValue: String?; var afterValue: String?
    }
    /// Web `settings.rest` — the PWA's canonical nested shape for the buckets.
    private struct RestDTO: Decodable {
        var mainCompoundSeconds: Int?; var olympicSeconds: Int?; var mainUpperSeconds: Int?
        var secondarySeconds: Int?; var accessorySeconds: Int?
    }
    private struct SettingsDTO: Decodable {
        // `proteinTargetGrams` went with the tracker in schema 6 and is
        // ignored where old bundles still carry it.
        var unitDisplay: String?; var birthYear: Int?; var accessoryRestSeconds: Int?
        var mainCompoundRestSeconds: Int?; var olympicRestSeconds: Int?; var mainUpperRestSeconds: Int?; var secondaryRestSeconds: Int?
        var rest: RestDTO?
        var autoStartRest: Bool?; var haptics: Bool?; var gymTagFirstLaunchOfDay: Bool?; var restSeedStampsCleared: Bool?
        var loadSemanticsMigrated: Bool?; var verticalPullMainsPromoted: Bool?
        var seededAt: Date?; var theme: String?
    }

    // MARK: - Preflight validation

    private static func requiredText(_ value: String?, _ path: String) throws -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.invalidData("\(path): expected non-empty text") }
        return trimmed
    }

    private static func portableID(_ value: String?, _ path: String, allowLegacy: Bool = false) throws -> String {
        let id = try requiredText(value, path)
        guard UUID(uuidString: id) != nil || (allowLegacy && id.hasPrefix("legacy:")) else {
            throw ImportError.invalidData("\(path): expected a UUID")
        }
        return id
    }

    private static func finite(_ value: Double?, _ path: String, required: Bool = false,
                               min: Double = -Double.greatestFiniteMagnitude,
                               max: Double = .greatestFiniteMagnitude) throws {
        guard let value else {
            if required { throw ImportError.invalidData("\(path): expected a number") }
            return
        }
        guard value.isFinite, value >= min, value <= max else {
            throw ImportError.invalidData("\(path): expected a finite number from \(min) to \(max)")
        }
    }

    private static func integer(_ value: Int?, _ path: String, required: Bool = false,
                                min: Int = .min, max: Int = .max) throws {
        guard let value else {
            if required { throw ImportError.invalidData("\(path): expected an integer") }
            return
        }
        guard value >= min, value <= max else {
            throw ImportError.invalidData("\(path): expected an integer from \(min) to \(max)")
        }
    }

    private static func known(_ value: String?, _ allowed: Set<String>, _ path: String, required: Bool = false) throws {
        guard let value else {
            if required { throw ImportError.invalidData("\(path): expected a known value") }
            return
        }
        guard allowed.contains(value) else { throw ImportError.invalidData("\(path): unknown value \(value)") }
    }

    private static func bodySite(_ value: String?, _ path: String, required: Bool = false) throws {
        guard let value else {
            if required { throw ImportError.invalidData("\(path): expected a known body site") }
            return
        }
        guard BodySite.fromStorage(value) != nil else {
            throw ImportError.invalidData("\(path): unknown body site \(value)")
        }
    }

    private static func currentYear() -> Int {
        Calendar.current.component(.year, from: .now)
    }

    private static func requireDate(_ value: Date?, _ path: String) throws {
        guard value != nil else { throw ImportError.invalidData("\(path): expected an ISO-8601 date") }
    }

    private static func unique(_ values: [String], _ path: String) throws {
        var seen = Set<String>()
        for (index, value) in values.enumerated() where !seen.insert(value).inserted {
            throw ImportError.invalidData("\(path)[\(index)]: duplicate identifier \(value)")
        }
    }

    /// Mirrors web `validateBackup`: reject data that either platform would
    /// silently coerce to a default. This runs before the first fetch/delete,
    /// so a bad file cannot partially restore or mutate the context.
    private static func validate(_ bundle: Bundle, schemaVersion: Int) throws {
        let units: Set<String> = ["lb", "kg"]
        let roles: Set<String> = ["main", "complementary", "accessory"]
        let liftRoles: Set<String> = ["main", "complementary"]
        let flags: Set<String> = Set(SetLifecycle.qualityValues)
            .union(SetLifecycle.rirValues)
            .union(["stopped early"])
        let statuses = Set(SetStatus.allCases.map(\.rawValue))
        let reasons = Set(AutoregReason.allCases.map(\.rawValue))
        let loadBases = Set(LoadBasis.allCases.map(\.rawValue))
        let blockKinds = Set(PrescriptionBlockKind.allCases.map(\.rawValue))

        for (si, session) in (bundle.sessions ?? []).enumerated() {
            let path = "sessions[\(si)]"
            if session.id != nil { _ = try portableID(session.id, "\(path).id") }
            try requireDate(session.date, "\(path).date")
            if schemaVersion >= 3, session.isCompleted == true, session.completedAt != nil {
                try requireDate(session.completedAt, "\(path).completedAt")
            }
            if let tag = session.programTag {
                if schemaVersion >= 1 { _ = try requiredText(tag.programName, "\(path).programTag.programName") }
                if schemaVersion >= 2 { _ = try portableID(tag.programId, "\(path).programTag.programId", allowLegacy: true) }
                try integer(tag.cycleNumber, "\(path).programTag.cycleNumber", min: 1)
                try integer(tag.week, "\(path).programTag.week", min: 1)
                try integer(tag.dayIndex, "\(path).programTag.dayIndex", min: 0)
                for (i, name) in (tag.planNames ?? []).enumerated() {
                    _ = try requiredText(name, "\(path).programTag.planNames[\(i)]")
                }
            }
            for (ei, exercise) in (session.exercises ?? []).enumerated() {
                let exercisePath = "\(path).exercises[\(ei)]"
                _ = try requiredText(exercise.name, "\(exercisePath).name")
                try known(exercise.role, roles, "\(exercisePath).role")
                if exercise.programSlotId != nil { _ = try portableID(exercise.programSlotId, "\(exercisePath).programSlotId") }
                try finite(exercise.plannedWeightLb, "\(exercisePath).plannedWeightLb", min: 0)
                try finite(exercise.targetWeightLb, "\(exercisePath).targetWeightLb", min: 0)
                try integer(exercise.plannedSets, "\(exercisePath).plannedSets", min: 0)
                try integer(exercise.plannedReps, "\(exercisePath).plannedReps", min: 0)
                try integer(exercise.plannedDurationSeconds, "\(exercisePath).plannedDurationSeconds", min: 0)
                try finite(exercise.fallbackWeightLb, "\(exercisePath).fallbackWeightLb", min: 0)
                try known(exercise.prescriptionStyle, Set(PrescriptionStyle.allCases.map(\.rawValue)),
                          "\(exercisePath).prescriptionStyle")
                for (xi, set) in (exercise.sets ?? []).enumerated() {
                    let setPath = "\(exercisePath).sets[\(xi)]"
                    try finite(set.weightLb, "\(setPath).weightLb", required: true, min: 0)
                    try integer(set.reps, "\(setPath).reps", required: true, min: 0)
                    try finite(set.targetWeightLb, "\(setPath).targetWeightLb", min: 0)
                    try finite(set.plannedWeightLb, "\(setPath).plannedWeightLb", min: 0)
                    try integer(set.plannedReps, "\(setPath).plannedReps", min: 0)
                    try integer(set.plannedDurationSeconds, "\(setPath).plannedDurationSeconds", min: 0)
                    try known(set.prescriptionBlock, blockKinds, "\(setPath).prescriptionBlock",
                              required: schemaVersion >= 3)
                    try known(set.status, statuses, "\(setPath).status", required: schemaVersion >= 2)
                    try known(set.loadBasis, loadBases, "\(setPath).loadBasis")
                    try integer(set.implementCount, "\(setPath).implementCount", min: 1, max: 4)
                    try known(set.enteredUnit, units, "\(setPath).enteredUnit", required: schemaVersion >= 1)
                    let setFlags = set.flags ?? []
                    for (fi, flag) in setFlags.enumerated() { try known(flag, flags, "\(setPath).flags[\(fi)]") }
                    // RIR is its own exclusive group, NOT part of the quality
                    // group: a set can be clean at 3+ reps in reserve or clean
                    // at 1, and those say different things. Folding them
                    // together would make the two exclude each other.
                    if schemaVersion >= 5 && setFlags.filter({ SetLifecycle.rirValues.contains($0) }).count > 1 {
                        throw ImportError.invalidData("\(setPath).flags: reps in reserve must be mutually exclusive")
                    }
                    if schemaVersion >= 2 && setFlags.filter({ SetLifecycle.qualityValues.contains($0) }).count > 1 {
                        throw ImportError.invalidData("\(setPath).flags: quality must be mutually exclusive")
                    }
                    try bodySite(set.bodyFlagSite, "\(setPath).bodyFlagSite")
                    try known(set.autoregReason, reasons, "\(setPath).autoregReason")
                    try integer(set.durationSeconds, "\(setPath).durationSeconds", min: 0)
                    try finite(set.distanceMiles, "\(setPath).distanceMiles", min: 0)
                    try finite(set.flights, "\(setPath).flights", min: 0)
                    try finite(set.inclinePercent, "\(setPath).inclinePercent", min: -100, max: 100)
                }
            }
        }
        try unique((bundle.sessions ?? []).compactMap(\.id), "sessions.id")

        for (i, entry) in (bundle.bodyweight ?? []).enumerated() {
            try requireDate(entry.date, "bodyweight[\(i)].date")
            try finite(entry.weightLb, "bodyweight[\(i)].weightLb", required: true, min: 0)
            try finite(entry.bodyFatPercent, "bodyweight[\(i)].bodyFatPercent", min: 0, max: 100)
        }
        for (i, entry) in (bundle.checkIns ?? []).enumerated() {
            try requireDate(entry.date, "checkIns[\(i)].date")
            _ = try requiredText(entry.site, "checkIns[\(i)].site")
            try bodySite(entry.site, "checkIns[\(i)].site", required: true)
            _ = try requiredText(entry.response, "checkIns[\(i)].response")
        }
        let milestoneKinds: Set<String> = Set(PREvent.Kind.allCases.map(\.rawValue))
        for (i, entry) in (bundle.milestones ?? []).enumerated() {
            try requireDate(entry.date, "milestones[\(i)].date")
            _ = try requiredText(entry.kind, "milestones[\(i)].kind")
            try known(entry.kind, milestoneKinds, "milestones[\(i)].kind")
            _ = try requiredText(entry.label, "milestones[\(i)].label")
        }

        for (pi, program) in (bundle.programs ?? []).enumerated() {
            let path = "programs[\(pi)]"
            if schemaVersion >= 2 { _ = try portableID(program.id, "\(path).id") }
            _ = try requiredText(program.name, "\(path).name")
            try known(program.focus, ["strength", "hypertrophy", "maintain"], "\(path).focus", required: schemaVersion >= 1)
            try known(program.equipmentPolicy, ProgramFileContract.equipmentPolicies,
                      "\(path).equipmentPolicy", required: schemaVersion >= 9)
            try integer(program.cycleNumber, "\(path).cycleNumber", min: 1)
            try integer(program.currentWeek, "\(path).currentWeek", min: 1, max: 4)
            try integer(program.nextDayIndex, "\(path).nextDayIndex", min: 0)
            try finite(program.roundingLb, "\(path).roundingLb", min: Double.leastNonzeroMagnitude)
            try integer(program.preferredSessionSpacingDays, "\(path).preferredSessionSpacingDays", min: 2, max: 14)
            try integer(program.maximumAddedSetsPerRotation, "\(path).maximumAddedSetsPerRotation", min: 0, max: 20)
            for (di, day) in (program.days ?? []).enumerated() {
                let dayPath = "\(path).days[\(di)]"
                _ = try requiredText(day.name, "\(dayPath).name")
                try integer(day.order, "\(dayPath).order", required: true, min: 0)
                // The static contract set, not a per-day rebuild — this runs
                // inside the day loop for every restored program.
                try known(day.trainingIntent, ProgramFileContract.dayTrainingIntents,
                          "\(dayPath).trainingIntent", required: schemaVersion >= 9)
                for (li, lift) in (day.lifts ?? []).enumerated() {
                    let liftPath = "\(dayPath).lifts[\(li)]"
                    if lift.id != nil { _ = try portableID(lift.id, "\(liftPath).id") }
                    _ = try requiredText(lift.exerciseName, "\(liftPath).exerciseName")
                    try known(lift.role, liftRoles, "\(liftPath).role", required: schemaVersion >= 1)
                    try integer(lift.order, "\(liftPath).order", min: 0)
                    try known(lift.prescription, Set(PrescriptionStyle.allCases.map(\.rawValue)), "\(liftPath).prescription")
                    try known(lift.warmupPolicy, Set(WarmupPolicy.allCases.map(\.rawValue)), "\(liftPath).warmupPolicy")
                    try finite(lift.loadOffsetLb, "\(liftPath).loadOffsetLb", min: 0)
                    try finite(lift.peakOffsetLb, "\(liftPath).peakOffsetLb", min: 0)
                    try finite(lift.deloadMultiplier, "\(liftPath).deloadMultiplier", min: 0.25, max: 1)
                    // Set-count ceiling is 100, not 20: the released web
                    // validator accepted up to 100 into real stores, and a
                    // cross-platform backup those stores exported must stay
                    // restorable here. Widening revokes nothing.
                    try integer(lift.doubleProgressionSets, "\(liftPath).doubleProgressionSets", min: 1, max: 100)
                    try integer(lift.minimumReps, "\(liftPath).minimumReps", min: 1, max: 100)
                    try integer(lift.maximumReps, "\(liftPath).maximumReps", min: 1, max: 100)
                    try integer(lift.currentReps, "\(liftPath).currentReps", min: 1, max: 100)
                    try finite(lift.lastPeakSingleLb, "\(liftPath).lastPeakSingleLb", min: 0)
                    try finite(lift.peakSingleIncrementLb, "\(liftPath).peakSingleIncrementLb", min: 0)
                    try finite(lift.dropIncrementLb, "\(liftPath).dropIncrementLb", min: 0)
                    try integer(lift.maximumSets, "\(liftPath).maximumSets", min: 1, max: 100)
                    try finite(lift.baseWeightLb, "\(liftPath).baseWeightLb", min: 0)
                    try finite(lift.estimatedMaxLb, "\(liftPath).estimatedMaxLb", min: 0)
                    try integer(lift.stallCount, "\(liftPath).stallCount", min: 0)
                    try finite(lift.lastIncrementLb, "\(liftPath).lastIncrementLb", min: 0)
                    if let state = lift.pending?.state {
                        try finite(state.baseWeightLb, "\(liftPath).pending.state.baseWeightLb", min: 0)
                        try finite(state.estimatedMaxLb, "\(liftPath).pending.state.estimatedMaxLb", min: 0)
                        try integer(state.stallCount, "\(liftPath).pending.state.stallCount", min: 0)
                        try finite(state.lastIncrementLb, "\(liftPath).pending.state.lastIncrementLb", min: 0)
                    }
                }
                for (ai, accessory) in (day.accessories ?? []).enumerated() {
                    let accessoryPath = "\(dayPath).accessories[\(ai)]"
                    if accessory.id != nil { _ = try portableID(accessory.id, "\(accessoryPath).id") }
                    _ = try requiredText(accessory.exerciseName, "\(accessoryPath).exerciseName")
                    try integer(accessory.order, "\(accessoryPath).order", min: 0)
                    try integer(accessory.sets, "\(accessoryPath).sets", min: 0)
                    try integer(accessory.minReps, "\(accessoryPath).minReps", min: 0)
                    try integer(accessory.maxReps, "\(accessoryPath).maxReps", min: 0)
                    try integer(accessory.currentReps, "\(accessoryPath).currentReps", min: 0)
                    try integer(accessory.targetSeconds, "\(accessoryPath).targetSeconds", min: 0)
                    try integer(accessory.durationStepSeconds, "\(accessoryPath).durationStepSeconds", min: 0)
                    try integer(accessory.maximumSets, "\(accessoryPath).maximumSets", min: 1, max: 20)
                    try known(accessory.conditioningEffort, ["easy", "interval", "mixed"],
                              "\(accessoryPath).conditioningEffort")
                    try integer(accessory.targetRPE, "\(accessoryPath).targetRPE", min: 0, max: 10)
                    try finite(accessory.weightLb, "\(accessoryPath).weightLb", min: 0)
                    try finite(accessory.incrementLb, "\(accessoryPath).incrementLb", min: 0)
                    try integer(accessory.stallCount, "\(accessoryPath).stallCount", min: 0)
                }
            }
            try unique((program.days ?? []).compactMap(\.order).map { String($0) }, "\(path).days")
            let slotIDs = (program.days ?? []).flatMap { day in
                (day.lifts ?? []).compactMap(\.id) + (day.accessories ?? []).compactMap(\.id)
            }
            try unique(slotIDs, "\(path).slotIds")
            // nextDayIndex names a day's ORDER, not its position, and orders
            // are validated as unique but never as contiguous. Range-checking
            // it against the day COUNT rejected legitimate bundles — orders
            // [0, 1, 5] pointing at day 5 is the exact sparse case the
            // schedule now handles. Check membership instead.
            let dayOrders = Set((program.days ?? []).compactMap(\.order))
            if let next = program.nextDayIndex, !dayOrders.isEmpty, !dayOrders.contains(next) {
                throw ImportError.invalidData("\(path).nextDayIndex: outside the program's day list")
            }
        }
        try unique((bundle.programs ?? []).map { try requiredText($0.name, "programs.name") }, "programs")
        if schemaVersion >= 2 {
            try unique((bundle.programs ?? []).map { try portableID($0.id, "programs.id") }, "programs.id")
        }

        for (i, track) in (bundle.tracks ?? []).enumerated() {
            let path = "tracks[\(i)]"
            _ = try requiredText(track.exerciseName, "\(path).exerciseName")
            try known(track.mode, ["cycle", "linear"], "\(path).mode", required: schemaVersion >= 1)
            try integer(track.cycleNumber, "\(path).cycleNumber", min: 1)
            try integer(track.nextPhase, "\(path).nextPhase", min: 1, max: 4)
            try finite(track.baseWeightLb, "\(path).baseWeightLb", min: 0)
            try finite(track.incrementLb, "\(path).incrementLb", min: Double.leastNonzeroMagnitude)
            try finite(track.roundingLb, "\(path).roundingLb", min: Double.leastNonzeroMagnitude)
        }
        try unique((bundle.tracks ?? []).map { try requiredText($0.exerciseName, "tracks.exerciseName") }, "tracks")

        for (i, gym) in (bundle.gyms ?? []).enumerated() {
            if schemaVersion >= 2 { _ = try portableID(gym.id, "gyms[\(i)].id") }
            _ = try requiredText(gym.name, "gyms[\(i)].name")
            try finite(gym.collarWeightLb, "gyms[\(i)].collarWeightLb", min: 0, max: 20)
            try known(gym.loadingPolicy, Set(LoadingPolicy.allCases.map(\.rawValue)), "gyms[\(i)].loadingPolicy")
            for (pi, plate) in (gym.plateToggles ?? []).enumerated() {
                try finite(plate.value, "gyms[\(i)].plateToggles[\(pi)].value", required: true, min: Double.leastNonzeroMagnitude)
                _ = try requiredText(plate.unit, "gyms[\(i)].plateToggles[\(pi)].unit")
                try known(plate.unit, units, "gyms[\(i)].plateToggles[\(pi)].unit", required: schemaVersion >= 1)
            }
        }
        try unique((bundle.gyms ?? []).map { try requiredText($0.name, "gyms.name") }, "gyms")
        if schemaVersion >= 2 {
            try unique((bundle.gyms ?? []).map { try portableID($0.id, "gyms.id") }, "gyms.id")
        }

        let categories: Set<String> = ["Main", "Accessory", "Conditioning"]
        let types: Set<String> = ["barbell", "dumbbell", "kettlebell", "bodyweight", "band", "machine", "timed", "conditioning"]
        for (i, exercise) in (bundle.exercises ?? []).enumerated() {
            let path = "exercises[\(i)]"
            _ = try requiredText(exercise.name, "\(path).name")
            try known(exercise.category, categories, "\(path).category", required: schemaVersion >= 1)
            try known(exercise.type, types, "\(path).type", required: schemaVersion >= 1)
            try known(exercise.movementPattern, Set(MovementPattern.allCases.map(\.rawValue)),
                      "\(path).movementPattern", required: schemaVersion >= 3)
            try known(exercise.secondaryMovementPattern, Set(MovementPattern.allCases.map(\.rawValue)),
                      "\(path).secondaryMovementPattern")
            try known(exercise.loadBasis, loadBases, "\(path).loadBasis")
            try integer(exercise.implementCount, "\(path).implementCount", min: 1, max: 4)
            try bodySite(exercise.watchSite, "\(path).watchSite")
            try known(exercise.gateStatus, Set(ExerciseGateStatus.allCases.map(\.rawValue)),
                      "\(path).gateStatus", required: schemaVersion >= 3)
            try bodySite(exercise.gateSite, "\(path).gateSite")
            try finite(exercise.reEntryTestWeightLb, "\(path).reEntryTestWeightLb", min: 0)
            try integer(exercise.reEntryTestSets, "\(path).reEntryTestSets", min: 1, max: 20)
            try integer(exercise.reEntryTestReps, "\(path).reEntryTestReps", min: 1, max: 100)
            try integer(exercise.defaultRestSeconds, "\(path).defaultRestSeconds", min: 0, max: 3600)
            try known(exercise.stationDenomination, Set(["lb", "kg"]), "\(path).stationDenomination")
        }
        try unique((bundle.exercises ?? []).map { try requiredText($0.name, "exercises.name") }, "exercises")

        for (i, decision) in (bundle.coachingDecisions ?? []).enumerated() {
            let path = "coachingDecisions[\(i)]"
            _ = try portableID(decision.id, "\(path).id")
            try requireDate(decision.date, "\(path).date")
            _ = try portableID(decision.programId, "\(path).programId")
            _ = try requiredText(decision.ruleId, "\(path).ruleId")
            _ = try requiredText(decision.recommendationId, "\(path).recommendationId")
            try known(decision.action, Set(CoachingDecisionAction.allCases.map(\.rawValue)),
                      "\(path).action", required: true)
        }
        try unique((bundle.coachingDecisions ?? []).compactMap(\.id), "coachingDecisions.id")

        // V10 typed calendar spans. Present values validate at any version
        // (the vocabulary is closed); the kind is required on v10 bundles.
        for (i, interval) in (bundle.intervals ?? []).enumerated() {
            let path = "intervals[\(i)]"
            _ = try portableID(interval.id, "\(path).id")
            try known(interval.kind, Set(TrainingIntervalKind.allCases.map(\.rawValue)),
                      "\(path).kind", required: schemaVersion >= 10)
            guard let start = interval.startDate.flatMap(IntervalDay.date(from:)) else {
                throw ImportError.invalidData("\(path).startDate: expected an ISO date")
            }
            guard let end = interval.endDate.flatMap(IntervalDay.date(from:)) else {
                throw ImportError.invalidData("\(path).endDate: expected an ISO date")
            }
            if end < start {
                throw ImportError.invalidData("\(path).endDate: expected endDate on or after startDate")
            }
            if interval.programId != nil {
                _ = try portableID(interval.programId, "\(path).programId", allowLegacy: true)
            }
        }
        try unique((bundle.intervals ?? []).compactMap(\.id), "intervals.id")

        if let settings = bundle.settings {
            try known(settings.unitDisplay, ["lbPrimary", "kgPrimary", "both"], "settings.unitDisplay", required: schemaVersion >= 1)
            try known(settings.theme, ["memento", "carbon", "slate", "system"], "settings.theme", required: schemaVersion >= 1)
            // 0 is the "not set" sentinel and always valid. Any other year has
            // to produce a plausible age, so a corrupted field cannot silently
            // move the lifter across the older-adult protein threshold.
            if let year = settings.birthYear, year != 0,
               ProteinGuidance.age(birthYear: year, inYear: currentYear()) == nil {
                throw ImportError.invalidData("settings.birthYear: \(year) is not a plausible year of birth")
            }
            for (path, value) in [
                ("settings.accessoryRestSeconds", settings.accessoryRestSeconds),
                ("settings.mainCompoundRestSeconds", settings.mainCompoundRestSeconds),
                ("settings.olympicRestSeconds", settings.olympicRestSeconds),
                ("settings.mainUpperRestSeconds", settings.mainUpperRestSeconds),
                ("settings.secondaryRestSeconds", settings.secondaryRestSeconds),
                ("settings.rest.mainCompoundSeconds", settings.rest?.mainCompoundSeconds),
                ("settings.rest.olympicSeconds", settings.rest?.olympicSeconds),
                ("settings.rest.mainUpperSeconds", settings.rest?.mainUpperSeconds),
                ("settings.rest.secondarySeconds", settings.rest?.secondarySeconds),
                ("settings.rest.accessorySeconds", settings.rest?.accessorySeconds),
            ] { try integer(value, path, min: 0, max: 3600) }
        }
    }

    @discardableResult
    /// Accept BOTH ISO-8601 forms: native ExportService writes no fractional
    /// seconds, the web PWA's Date.toISOString() writes ".000Z". A single
    /// strategy that rejects fractions would fail every web-origin backup.
    /// Shared by `load` and `namedRestorePreview` so the preview reads dates
    /// exactly as the restore it previews will.
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "Unrecognised date: \(s)"))
        }
        return decoder
    }

    static func load(_ data: Data, into context: ModelContext) throws -> Summary {
        guard let bundle = try? makeDecoder().decode(Bundle.self, from: data) else { throw ImportError.notABackup }
        let schemaVersion = bundle.schemaVersion ?? 0
        guard BackupContract.supports(schemaVersion: schemaVersion) else {
            throw ImportError.unsupportedSchemaVersion(schemaVersion)
        }

        let hasAnything = [bundle.sessions != nil, bundle.programs != nil, bundle.tracks != nil,
                           bundle.gyms != nil, bundle.exercises != nil, bundle.bodyweight != nil,
                           bundle.checkIns != nil, bundle.milestones != nil,
                           bundle.settings != nil, bundle.coachingDecisions != nil].contains(true)
        guard hasAnything else { throw ImportError.notABackup }
        try validate(bundle, schemaVersion: schemaVersion)

        var repairedSlotIDs = 0
        do {
            // Exercises: UPSERT by name (never delete — SessionExercise links to
            // them by relationship, so replacing them would orphan history).
            if let defs = bundle.exercises {
                var byName: [String: Exercise] = [:]
                for e in (try context.fetch(FetchDescriptor<Exercise>())) { byName[e.name] = e }
                for d in defs {
                    // Exercise.name is @Attribute(.unique); an unnamed def can't
                    // own a key, and two of them would collide on save.
                    let name = (d.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { continue }
                    if let existing = byName[name] {
                        update(existing, from: d, schemaVersion: schemaVersion)
                        existing.id = importedExerciseID(d.id, name: name, schemaVersion: schemaVersion)
                    }
                    else {
                        let e = makeExercise(d)
                        e.id = importedExerciseID(d.id, name: name, schemaVersion: schemaVersion)
                        context.insert(e); byName[name] = e
                    }
                }
            }
            var exByName: [String: Exercise] = [:]
            for e in try context.fetch(FetchDescriptor<Exercise>()) { exByName[e.name] = e }

            if let gyms = bundle.gyms {
                try context.delete(model: Gym.self)
                for g in gyms { context.insert(makeGym(g)) }
            }
            if let tracks = bundle.tracks {
                try context.delete(model: LiftTrack.self)
                for t in tracks { context.insert(makeTrack(t, schemaVersion: schemaVersion)) }
            }
            let programIDsByName: [String: String]
            if let programs = bundle.programs {
                try context.delete(model: Program.self)
                var imported: [String: String] = [:]
                // Bundle-wide, so a slot id repeated across two programs is
                // caught. Validation only checks uniqueness within a program.
                var seenSlotIDs: Set<String> = []
                for p in programs {
                    let program = makeProgram(p, preserveID: schemaVersion >= 2, schemaVersion: schemaVersion,
                                              seenSlotIDs: &seenSlotIDs, repairedSlotIDs: &repairedSlotIDs)
                    context.insert(program)
                    imported[program.name] = program.id
                }
                programIDsByName = imported
            } else {
                programIDsByName = Dictionary(
                    uniqueKeysWithValues: try context.fetch(FetchDescriptor<Program>()).map { ($0.name, $0.id) }
                )
            }
            if let bw = bundle.bodyweight {
                try context.delete(model: BodyweightEntry.self)
                for b in bw { context.insert(BodyweightEntry(date: b.date ?? .now, weightLb: b.weightLb ?? 0, bodyFatPercent: b.bodyFatPercent, milestoneLabel: b.milestoneLabel)) }
            }
            if let cis = bundle.checkIns {
                try context.delete(model: CheckIn.self)
                for c in cis {
                    let ci = CheckIn(date: c.date ?? .now, site: BodySite.fromStorage(c.site) ?? .knee,
                                     response: c.response ?? "", note: c.note ?? "")
                    context.insert(ci)
                }
            }
            if let ms = bundle.milestones {
                try context.delete(model: Milestone.self)
                for m in ms {
                    let mi = Milestone(date: m.date ?? .now, exerciseName: m.exercise, kind: .heaviestSet, label: m.label ?? "")
                    mi.kindRaw = m.kind ?? mi.kindRaw   // preserve exact raw (incl. "programNote")
                    mi.exerciseID = importedExerciseID(m.exerciseId, name: m.exercise, schemaVersion: schemaVersion)
                    context.insert(mi)
                }
            }
            if let sessions = bundle.sessions {
                try context.delete(model: WorkoutSession.self)
                for s in sessions {
                    context.insert(makeSession(s, schemaVersion: schemaVersion, exByName: exByName,
                                               programIDsByName: programIDsByName))
                }
            }
            if let decisions = bundle.coachingDecisions {
                try context.delete(model: CoachingDecision.self)
                for value in decisions { context.insert(makeCoachingDecision(value)) }
            }
            if let intervals = bundle.intervals {
                try context.delete(model: TrainingInterval.self)
                for value in intervals {
                    let record = TrainingInterval(
                        kindRaw: value.kind ?? "rest",
                        startDate: value.startDate.flatMap(IntervalDay.date(from:)) ?? .now,
                        endDate: value.endDate.flatMap(IntervalDay.date(from:)) ?? .now,
                        enteredAsDays: value.enteredAsDays ?? true,
                        note: value.note ?? "",
                        programID: value.programId
                    )
                    if let id = value.id { record.id = id }
                    context.insert(record)
                }
            }
            if let st = bundle.settings {
                try applySettings(st, restoredExercises: bundle.exercises != nil, in: context)
            } else if bundle.exercises != nil,
                      let s = try context.fetch(FetchDescriptor<AppSettings>()).first {
                // A library restored with no settings riding along is of
                // unknown vintage — re-arm the retired-rest-stamp check so the
                // next launch's syncLibrary re-inspects the restored records.
                s.restSeedStampsCleared = false
                s.loadSemanticsMigrated = false
                s.verticalPullMainsPromoted = false
            }

            try context.save()
        } catch {
            context.rollback()
            throw ImportError.writeFailed
        }

        return Summary(sessions: bundle.sessions?.count ?? 0, programs: bundle.programs?.count ?? 0,
                       tracks: bundle.tracks?.count ?? 0, gyms: bundle.gyms?.count ?? 0,
                       repairedSlotIDs: repairedSlotIDs)
    }

    // MARK: - Restore preview

    /// Named-entity restore preview: per-item new/changed/unchanged/removed
    /// for the backup's exercises, lift tracks, gyms, sessions, and programs
    /// against the current store. Reads the bundle's own field values
    /// directly rather than running them through
    /// `makeExercise`/`makeTrack`/`makeGym`/`makeSession`/`makeProgram`'s
    /// import-time defaulting, so an older bundle that omits a field previews
    /// as it will actually read, not as the restore would backfill it.
    /// Returns nil only when `data` isn't decodable as a backup at all.
    ///
    /// A collection the bundle omits entirely is left out of both sides
    /// (`[]`, `[]`): `load` above only touches a store when the bundle key is
    /// present at all, so fetching the CURRENT records for an omitted
    /// collection would wrongly preview every one of them as `removed` for a
    /// restore that will not touch it.
    static func namedRestorePreview(_ data: Data, context: ModelContext) throws -> BackupContract.NamedRestorePreview? {
        guard let bundle = try? makeDecoder().decode(Bundle.self, from: data) else { return nil }
        let schemaVersion = bundle.schemaVersion ?? 0

        func trimmed(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

        let incomingExercises = (bundle.exercises ?? []).compactMap { d -> BackupContract.NamedEntity? in
            let name = trimmed(d.name)
            // Exercise.name is @Attribute(.unique); an unnamed def can't own a
            // restore-preview identity either — `load` skips it the same way.
            guard !name.isEmpty else { return nil }
            return BackupContract.NamedEntity(id: name, name: name, signature: exerciseSignature(
                category: d.category, type: d.type, movementGroup: d.movementGroup,
                movementPattern: d.movementPattern, secondaryMovementPattern: d.secondaryMovementPattern,
                loadBasis: d.loadBasis, implementCount: d.implementCount, isUnilateral: d.isUnilateral,
                defaultRestSeconds: d.defaultRestSeconds, notes: d.notes, isShelved: d.isShelved,
                stationDenomination: d.stationDenomination))
        }
        // Native exercises are upserted by name and never deleted (see `load`
        // above), so their current records are only fetched when the bundle
        // actually carries the key — otherwise there is nothing to diff.
        let currentExercises: [BackupContract.NamedEntity] = bundle.exercises == nil ? [] :
            try context.fetch(FetchDescriptor<Exercise>()).map { e in
                BackupContract.NamedEntity(id: e.name, name: e.name, signature: exerciseSignature(
                    category: e.categoryRaw, type: e.typeRaw, movementGroup: e.movementGroup,
                    movementPattern: e.movementPatternRaw, secondaryMovementPattern: e.secondaryMovementPatternRaw,
                    loadBasis: e.loadBasisRaw, implementCount: e.implementCount, isUnilateral: e.isUnilateral,
                    defaultRestSeconds: e.defaultRestSeconds, notes: e.notes, isShelved: e.isShelved,
                    stationDenomination: e.stationDenominationRaw))
            }

        let incomingTracks = (bundle.tracks ?? []).compactMap { t -> BackupContract.NamedEntity? in
            let name = trimmed(t.exerciseName)
            guard !name.isEmpty else { return nil }
            return BackupContract.NamedEntity(id: name, name: name, signature: trackSignature(
                mode: t.mode, cycleNumber: t.cycleNumber, baseWeightLb: t.baseWeightLb,
                nextPhase: t.nextPhase, incrementLb: t.incrementLb, roundingLb: t.roundingLb))
        }
        let currentTracks: [BackupContract.NamedEntity] = bundle.tracks == nil ? [] :
            try context.fetch(FetchDescriptor<LiftTrack>()).map { t in
                BackupContract.NamedEntity(id: t.exerciseName, name: t.exerciseName, signature: trackSignature(
                    mode: t.modeRaw, cycleNumber: t.cycleNumber, baseWeightLb: t.baseWeightLb,
                    nextPhase: t.nextPhaseRaw, incrementLb: t.incrementLb, roundingLb: t.roundingLb))
            }

        // A gym missing an id can never match a current one by id (`load`
        // mints it a fresh random id the same way), so it always previews as
        // new — matching what the restore will actually do.
        let incomingGyms = (bundle.gyms ?? []).map { g in
            BackupContract.NamedEntity(id: g.id ?? "", name: trimmed(g.name), signature: gymSignature(
                isDefault: g.isDefault, defaultBarId: g.defaultBarId, collarWeightLb: g.collarWeightLb,
                loadingPolicy: g.loadingPolicy, barcodeLabel: g.barcodeLabel))
        }
        let currentGyms: [BackupContract.NamedEntity] = bundle.gyms == nil ? [] :
            try context.fetch(FetchDescriptor<Gym>()).map { g in
                BackupContract.NamedEntity(id: g.id, name: g.name, signature: gymSignature(
                    isDefault: g.isDefault, defaultBarId: g.defaultBarID, collarWeightLb: g.collarWeightLb,
                    loadingPolicy: g.loadingPolicyRaw, barcodeLabel: g.barcodeLabel))
            }

        // A session id that isn't a valid UUID can never match a current
        // one (`makeSession` mints a fresh random id the same way), so it
        // always previews as new.
        let incomingSessions = (bundle.sessions ?? []).map { s -> BackupContract.NamedEntity in
            let id = s.id.flatMap { UUID(uuidString: $0) != nil ? $0 : nil } ?? ""
            let name = s.date.map { isoSessionName($0) } ?? "Untitled session"
            return BackupContract.NamedEntity(id: id, name: name, signature: sessionSignature(
                date: s.date, programId: s.programTag?.programId, exerciseCount: (s.exercises ?? []).count))
        }
        let currentSessions: [BackupContract.NamedEntity] = bundle.sessions == nil ? [] :
            try context.fetch(FetchDescriptor<WorkoutSession>()).map { session in
                BackupContract.NamedEntity(id: session.id, name: isoSessionName(session.date), signature: sessionSignature(
                    date: session.date, programId: session.programID, exerciseCount: session.exercises.count))
            }

        // Mirrors `load`'s own program id derivation exactly (a v2+ bundle's
        // own id rides along verbatim; anything else — including a pre-v2
        // bundle — mints a fresh random id `makeProgram` the same way), so
        // the preview classifies a program the same way the restore will
        // actually key it.
        let incomingPrograms = (bundle.programs ?? []).map { p -> BackupContract.NamedEntity in
            let id = (schemaVersion >= 2 ? p.id : nil) ?? ""
            let dayCount = p.days?.count ?? 0
            let slotCount = (p.days ?? []).reduce(0) { $0 + ($1.lifts?.count ?? 0) + ($1.accessories?.count ?? 0) }
            return BackupContract.NamedEntity(id: id, name: trimmed(p.name), signature: programSignature(dayCount: dayCount, slotCount: slotCount))
        }
        let currentPrograms: [BackupContract.NamedEntity] = bundle.programs == nil ? [] :
            try context.fetch(FetchDescriptor<Program>()).map { program in
                let slotCount = program.days.reduce(0) { $0 + $1.lifts.count + $1.accessories.count }
                return BackupContract.NamedEntity(id: program.id, name: program.name, signature: programSignature(dayCount: program.days.count, slotCount: slotCount))
            }

        return BackupContract.namedRestorePreview(
            currentExercises: currentExercises, incomingExercises: incomingExercises,
            currentTracks: currentTracks, incomingTracks: incomingTracks,
            currentGyms: currentGyms, incomingGyms: incomingGyms,
            currentSessions: currentSessions, incomingSessions: incomingSessions,
            currentPrograms: currentPrograms, incomingPrograms: incomingPrograms,
            // The native exercise importer upserts by name and never
            // deletes — see the `currentExercises` comment above.
            includeRemovedExercises: false
        )
    }

    private static func isoSessionName(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func sessionSignature(date: Date?, programId: String?, exerciseCount: Int) -> String {
        [date.map { ISO8601DateFormatter().string(from: $0) } ?? "", programId ?? "", String(exerciseCount)]
            .joined(separator: "\u{1F}")
    }

    private static func programSignature(dayCount: Int, slotCount: Int) -> String {
        [String(dayCount), String(slotCount)].joined(separator: "\u{1F}")
    }

    private static func exerciseSignature(
        category: String?, type: String?, movementGroup: String?, movementPattern: String?,
        secondaryMovementPattern: String?, loadBasis: String?, implementCount: Int?,
        isUnilateral: Bool?, defaultRestSeconds: Int?, notes: String?, isShelved: Bool?,
        stationDenomination: String?
    ) -> String {
        [category ?? "", type ?? "", movementGroup ?? "", movementPattern ?? "",
         secondaryMovementPattern ?? "", loadBasis ?? "", String(implementCount ?? 0),
         (isUnilateral ?? false) ? "1" : "0", String(defaultRestSeconds ?? 0), notes ?? "",
         (isShelved ?? false) ? "1" : "0", stationDenomination ?? ""].joined(separator: "\u{1F}")
    }

    private static func trackSignature(
        mode: String?, cycleNumber: Int?, baseWeightLb: Double?,
        nextPhase: Int?, incrementLb: Double?, roundingLb: Double?
    ) -> String {
        [mode ?? "", String(cycleNumber ?? 0), String(baseWeightLb ?? 0),
         String(nextPhase ?? 0), String(incrementLb ?? 0), String(roundingLb ?? 0)].joined(separator: "\u{1F}")
    }

    private static func gymSignature(
        isDefault: Bool?, defaultBarId: String?, collarWeightLb: Double?,
        loadingPolicy: String?, barcodeLabel: String?
    ) -> String {
        [(isDefault ?? false) ? "1" : "0", defaultBarId ?? "", String(collarWeightLb ?? 0),
         loadingPolicy ?? "", barcodeLabel ?? ""].joined(separator: "\u{1F}")
    }

    // MARK: - Makers

    private static func makeExercise(_ d: ExerciseDef) -> Exercise {
        let e = Exercise(
            name: d.name ?? "Unknown",
            category: ExerciseCategory(rawValue: d.category ?? "") ?? .accessory,
            type: ExerciseType(rawValue: d.type ?? "") ?? .barbell,
            movementGroup: d.movementGroup ?? "",
            movementPattern: d.movementPattern.flatMap(MovementPattern.init(rawValue:)),
            secondaryMovementPattern: d.secondaryMovementPattern.flatMap(MovementPattern.init(rawValue:)),
            aliases: d.aliases ?? [], strategyTags: d.strategyTags ?? [],
            loadBasis: d.loadBasis.flatMap(LoadBasis.init(rawValue:)),
            implementCount: d.implementCount ?? 0,
            isUnilateral: d.isUnilateral ?? false,
            // 0 = bucket-driven; a missing key must NOT mint a per-exercise
            // override (90 was the retired blanket stamp — web imports the
            // same record raw, so anything else diverges the platforms).
            defaultRestSeconds: d.defaultRestSeconds ?? 0,
            notes: d.notes ?? "",
            isShelved: d.isShelved ?? false,
            shelvedNote: d.shelvedNote ?? "",
            watchSite: BodySite.fromStorage(d.watchSite)
        )
        if let c = d.createdAt { e.createdAt = c }
        e.gateStatus = ExerciseGateStatus(rawValue: d.gateStatus ?? "") ?? (d.isShelved == true ? .shelved : .open)
        e.gateSite = BodySite.fromStorage(d.gateSite)
        e.reEntryCriteria = d.reEntryCriteria ?? []
        e.completedReEntryCriteria = d.completedReEntryCriteria ?? []
        e.reEntryTestWeightLb = d.reEntryTestWeightLb ?? 0
        e.reEntryTestSets = d.reEntryTestSets ?? 3
        e.reEntryTestReps = d.reEntryTestReps ?? 5
        e.stationDenomination = d.stationDenomination.flatMap(WeightUnit.init(rawValue:))
        return e
    }

    private static func update(_ e: Exercise, from d: ExerciseDef, schemaVersion: Int) {
        if let v = d.category, let c = ExerciseCategory(rawValue: v) { e.category = c }
        if let v = d.type, let t = ExerciseType(rawValue: v) { e.type = t }
        if let v = d.movementGroup { e.movementGroup = v }
        if let v = d.movementPattern, let pattern = MovementPattern(rawValue: v) { e.movementPattern = pattern }
        if schemaVersion >= 3 {
            // Schema-3 exporters emit these keys even when their value is nil
            // or empty. Restore that absence explicitly; otherwise an import
            // over the relationship-owned library would retain stale local
            // gate/taxonomy state that is not present in the backup.
            e.secondaryMovementPattern = d.secondaryMovementPattern.flatMap(MovementPattern.init(rawValue:))
            e.aliases = d.aliases ?? []
            e.strategyTags = d.strategyTags ?? []
        } else {
            if let v = d.secondaryMovementPattern { e.secondaryMovementPattern = MovementPattern(rawValue: v) }
            if let v = d.aliases { e.aliases = v }
            if let v = d.strategyTags { e.strategyTags = v }
        }
        if let v = d.loadBasis, let basis = LoadBasis(rawValue: v) { e.loadBasis = basis }
        if let v = d.implementCount { e.implementCount = v }
        if let v = d.isUnilateral { e.isUnilateral = v }
        if let v = d.defaultRestSeconds { e.defaultRestSeconds = v }
        if let v = d.notes { e.notes = v }
        if let v = d.isShelved { e.isShelved = v }
        if let v = d.shelvedNote { e.shelvedNote = v }
        if let v = d.gateStatus, let status = ExerciseGateStatus(rawValue: v) { e.gateStatus = status }
        // Restore the field's absence explicitly, at EVERY bundle version: a
        // v8 bundle with the key cleared and a pre-v8 bundle that never knew
        // stations both describe a world where this lift solves on the gym
        // inventory, and web restores exactly that by replacing the record
        // wholesale. Keeping a newer local preference would resurrect a
        // station configuration the backup does not contain.
        e.stationDenomination = d.stationDenomination.flatMap(WeightUnit.init(rawValue:))
        if schemaVersion >= 3 {
            e.watchSite = BodySite.fromStorage(d.watchSite)
            e.gateSite = BodySite.fromStorage(d.gateSite)
            e.reEntryCriteria = d.reEntryCriteria ?? []
            e.completedReEntryCriteria = d.completedReEntryCriteria ?? []
            e.reEntryTestWeightLb = d.reEntryTestWeightLb ?? 0
            e.reEntryTestSets = d.reEntryTestSets ?? 3
            e.reEntryTestReps = d.reEntryTestReps ?? 5
            if let createdAt = d.createdAt { e.createdAt = createdAt }
        } else {
            if let v = d.watchSite { e.watchSite = BodySite.fromStorage(v) }
            if d.gateSite != nil { e.gateSite = BodySite.fromStorage(d.gateSite) }
            if let v = d.reEntryCriteria { e.reEntryCriteria = v }
            if let v = d.completedReEntryCriteria { e.completedReEntryCriteria = v }
            if let v = d.reEntryTestWeightLb { e.reEntryTestWeightLb = v }
            if let v = d.reEntryTestSets { e.reEntryTestSets = v }
            if let v = d.reEntryTestReps { e.reEntryTestReps = v }
        }
    }

    private static func makeGym(_ g: GymDTO) -> Gym {
        let gym = Gym(name: g.name ?? "Gym", isDefault: g.isDefault ?? false, defaultBar: Bar.by(id: g.defaultBarId ?? "45-lb"))
        if let id = g.id { gym.id = id }
        gym.collarWeightLb = g.collarWeightLb ?? 0
        gym.loadingPolicy = g.loadingPolicy.flatMap(LoadingPolicy.init(rawValue:)) ?? .closest
        gym.plateToggles = (g.plateToggles ?? []).map {
            PlateToggle(plate: Plate(value: $0.value ?? 0, unit: WeightUnit(rawValue: $0.unit ?? "lb") ?? .lb), enabled: $0.enabled ?? true)
        }
        gym.barcodeLabel = g.barcodeLabel ?? "Membership tag"
        gym.barcodeImageData = dataFromURL(g.barcodeImage)
        return gym
    }

    /// v11 exercise ids ride verbatim when they are portable UUIDs; anything
    /// else — an older bundle, a missing or malformed id — derives the
    /// deterministic legacy id from the recorded name, so both clients agree
    /// on identity for the same content (repair-not-reject, like slot ids).
    private static func importedExerciseID(_ dtoID: String?, name: String?, schemaVersion: Int) -> String? {
        if schemaVersion >= 11, let id = dtoID, UUID(uuidString: id) != nil { return id }
        guard let name, !name.isEmpty else { return nil }
        return StableID.exerciseLegacyID(name: name)
    }

    private static func makeTrack(_ t: Track, schemaVersion: Int) -> LiftTrack {
        let track = LiftTrack(
            exerciseName: t.exerciseName ?? "",
            mode: TrackMode(rawValue: t.mode ?? "cycle") ?? .cycle,
            cycleNumber: t.cycleNumber ?? 1,
            baseWeightLb: t.baseWeightLb ?? 45,
            nextPhase: CyclePhase(rawValue: t.nextPhase ?? 1) ?? .volume,
            incrementLb: t.incrementLb ?? 10,
            roundingLb: t.roundingLb ?? 5
        )
        track.lastCompletedAt = t.lastCompletedAt
        track.exerciseID = importedExerciseID(t.exerciseId, name: t.exerciseName, schemaVersion: schemaVersion)
        return track
    }

    /// Adopt a slot id from the bundle, or mint a fresh one.
    ///
    /// Two rules, in order: the id must be a UUID, and it must not already be
    /// taken by another slot ANYWHERE in the bundle. Validation checks slot-id
    /// uniqueness within one program only, so a hand-edited backup can carry
    /// the same id on two programs — and `programSlotID` is what banked
    /// sessions point at, so a duplicate makes that history permanently
    /// ambiguous. The launch-time repair cannot clean it up either: its
    /// duplicate detection is scoped to a single program.
    ///
    /// Repairs rather than refusing, unlike the program-file importer. A backup
    /// is the recovery path of last resort, and the app itself may have written
    /// the duplicate; refusing to restore would strand the lifter's data over a
    /// problem we can fix. The first occurrence keeps its id so the most
    /// history stays bound, and the count is reported rather than silently
    /// swallowed.
    private static func adoptSlotID(_ raw: String?, seen: inout Set<String>, repaired: inout Int) -> String {
        let portable = raw.flatMap { UUID(uuidString: $0) != nil ? $0 : nil }
        if let portable, seen.insert(portable).inserted { return portable }
        if portable != nil { repaired += 1 }
        var fresh = UUID().uuidString
        while !seen.insert(fresh).inserted { fresh = UUID().uuidString }
        return fresh
    }

    private static func makeProgram(
        _ p: ProgramDTO, preserveID: Bool, schemaVersion: Int,
        seenSlotIDs: inout Set<String>, repairedSlotIDs: inout Int
    ) -> Program {
        let prog = Program(name: p.name ?? "Program", focus: TrainingFocus(rawValue: p.focus ?? "strength") ?? .strength,
                           cycleNumber: p.cycleNumber ?? 1, currentWeek: p.currentWeek ?? 1,
                           nextDayIndex: p.nextDayIndex ?? 0, roundingLb: p.roundingLb ?? 5, isActive: p.isActive ?? false)
        if preserveID, let id = p.id { prog.id = id }
        // Template origin is data, not an enum: carried verbatim from v11
        // bundles, never guessed for older ones.
        prog.templateID = schemaVersion >= 11 ? p.templateId : nil
        prog.equipmentPolicyRaw = p.equipmentPolicy ?? EquipmentPolicy.any.rawValue
        prog.coachEnabled = p.coachEnabled ?? true
        prog.reliableHistoryStart = p.reliableHistoryStart
        prog.preferredSessionSpacingDays = p.preferredSessionSpacingDays ?? 3
        prog.maximumAddedSetsPerRotation = p.maximumAddedSetsPerRotation ?? 6
        for d in (p.days ?? []) {
            let day = ProgramDay(name: d.name ?? "Day", order: d.order ?? 0)
            day.trainingIntentRaw = d.trainingIntent ?? DayTrainingIntent.general.rawValue
            prog.days.append(day)
            // Missing orders take the array position; a day whose slots ALL
            // tie carries no ordering information either, so the authored
            // sequence wins there too rather than the alphabetical fallback.
            let liftOrders = ProgramEngine.authoredSlotOrders(
                (d.lifts ?? []).enumerated().map { $1.order ?? $0 })
            let accessoryOrders = ProgramEngine.authoredSlotOrders(
                (d.accessories ?? []).enumerated().map { $1.order ?? $0 })
            for (slotOrder, l) in (d.lifts ?? []).enumerated() {
                let lift = ProgramLift(id: adoptSlotID(l.id, seen: &seenSlotIDs, repaired: &repairedSlotIDs),
                                       exerciseName: l.exerciseName ?? "", role: LiftRole(rawValue: l.role ?? "main") ?? .main,
                                       order: liftOrders[slotOrder],
                                       prescription: PrescriptionStyle(rawValue: l.prescription ?? "automatic") ?? .automatic,
                                       warmupPolicy: WarmupPolicy(rawValue: l.warmupPolicy ?? "automatic") ?? .automatic,
                                       baseWeightLb: l.baseWeightLb ?? 45, estimatedMaxLb: l.estimatedMaxLb ?? 0,
                                       stallCount: l.stallCount ?? 0, lastIncrementLb: l.lastIncrementLb ?? 0)
                lift.loadOffsetLb = l.loadOffsetLb ?? 0
                lift.peakOffsetLb = l.peakOffsetLb ?? 0
                lift.deloadMultiplier = l.deloadMultiplier ?? 0.775
                lift.doubleProgressionSets = l.doubleProgressionSets ?? 3
                lift.minimumReps = l.minimumReps ?? 5
                lift.maximumReps = l.maximumReps ?? 8
                lift.currentReps = l.currentReps ?? lift.minimumReps
                lift.peakSingleEnabled = l.peakSingleEnabled ?? false
                lift.lastPeakSingleLb = l.lastPeakSingleLb ?? 0
                lift.peakSingleIncrementLb = l.peakSingleIncrementLb ?? 5
                lift.phasePrimerEnabled = l.phasePrimerEnabled ?? true
                lift.dropIncrementLb = l.dropIncrementLb ?? 0
                lift.capacityManaged = l.capacityManaged ?? true
                lift.maximumSets = l.maximumSets ?? 6
                lift.exerciseID = importedExerciseID(l.exerciseId, name: l.exerciseName, schemaVersion: schemaVersion)
                if let st = l.pending?.state {
                    lift.pendingBaseWeightLb = st.baseWeightLb
                    lift.pendingEstimatedMaxLb = st.estimatedMaxLb
                    lift.pendingStallCount = st.stallCount
                    lift.pendingLastIncrementLb = st.lastIncrementLb
                    lift.pendingNote = l.pending?.note
                }
                lift.revertToExerciseName = l.revertToExerciseName
                day.lifts.append(lift)
            }
            for (slotOrder, a) in (d.accessories ?? []).enumerated() {
                let acc = ProgramAccessory(id: adoptSlotID(a.id, seen: &seenSlotIDs, repaired: &repairedSlotIDs),
                                           exerciseName: a.exerciseName ?? "", order: accessoryOrders[slotOrder],
                                           sets: a.sets ?? 3, minReps: a.minReps ?? 8,
                                           maxReps: a.maxReps ?? 12, currentReps: a.currentReps ?? 8,
                                           targetSeconds: a.targetSeconds ?? 30,
                                           durationStepSeconds: a.durationStepSeconds ?? 5, weightLb: a.weightLb ?? 0,
                                           incrementLb: a.incrementLb ?? 0, stallCount: a.stallCount ?? 0)
                acc.revertToExerciseName = a.revertToExerciseName
                acc.capacityManaged = a.capacityManaged ?? true
                acc.maximumSets = a.maximumSets ?? 6
                acc.conditioningEffortRaw = a.conditioningEffort ?? "easy"
                acc.targetRPE = a.targetRPE ?? 0
                acc.exerciseID = importedExerciseID(a.exerciseId, name: a.exerciseName, schemaVersion: schemaVersion)
                day.accessories.append(acc)
            }
        }
        // Day orders are imported VERBATIM. Renumbering them to 0..n-1 would
        // be tidier, but a day's order is the identity that every session's
        // `programTag.dayIndex` refers to — renumbering the days without
        // rewriting the tags of sessions in the same bundle would leave those
        // sessions unable to resume or bank, and would misattribute their
        // banked work to the wrong day in history and coaching. Gaps are
        // handled where they matter instead, by ProgramProgression
        // .scheduleAdvance walking real order values.
        return prog
    }

    private static func makeSession(_ s: Session, schemaVersion: Int, exByName: [String: Exercise],
                                    programIDsByName: [String: String]) -> WorkoutSession {
        let session = WorkoutSession(date: s.date ?? .now, notes: s.notes ?? "", gymID: s.gymId, gymName: s.gym)
        if let id = s.id, UUID(uuidString: id) != nil { session.id = id }
        session.programTemplateID = schemaVersion >= 11 ? s.programTemplateId : nil
        // Legacy, unversioned backups only contained completed sessions, so a
        // missing flag means completed. Version 1 carries the actual state.
        session.isCompleted = s.isCompleted ?? true
        session.completedAt = s.completedAt
        if let tag = s.programTag {
            session.programID = schemaVersion >= 2
                ? tag.programId
                : tag.programName.flatMap { programIDsByName[$0] }
            session.programName = tag.programName
            session.programCycleNumber = tag.cycleNumber
            session.programWeek = tag.week
            session.programDayIndex = tag.dayIndex
            session.programPlanNames = tag.planNames
        }
        for (oi, e) in (s.exercises ?? []).enumerated() {
            let entry = SessionExercise(order: oi, exercise: e.name.flatMap { exByName[$0] }, notes: e.notes ?? "")
            entry.exerciseID = importedExerciseID(e.exerciseId, name: e.name, schemaVersion: schemaVersion)
            // Empty means roleless, matching web's `e.role || null`: importing
            // "" as a role would flip an unprogrammed entry's chart role.
            entry.programRole = e.role.flatMap { $0.isEmpty ? nil : $0 }
            entry.programSlotID = e.programSlotId
            entry.barID = e.barId
            entry.barIDIsManual = e.barIdManual ?? false
            entry.plannedWeightLb = e.plannedWeightLb
            entry.targetWeightLb = e.targetWeightLb
            entry.plannedSets = e.plannedSets
            entry.plannedReps = e.plannedReps
            entry.plannedDurationSeconds = e.plannedDurationSeconds
            entry.fallbackWeightLb = e.fallbackWeightLb
            entry.prescriptionStyleRaw = e.prescriptionStyle ?? ""
            entry.phaseRaw = recoverPhase(e.phase)
            for (si, x) in (e.sets ?? []).enumerated() {
                let set = SetEntry(order: si, weightLb: x.weightLb ?? 0, reps: x.reps ?? 0,
                                   isWarmup: x.isWarmup ?? false,
                                   status: x.status.flatMap { SetStatus(rawValue: $0) }
                                       ?? (schemaVersion < 2 && session.isCompleted ? .completed : .planned),
                                   isPerSide: x.isPerSide ?? false,
                                   enteredUnit: WeightUnit(rawValue: x.enteredUnit ?? "lb") ?? .lb,
                                   flags: (x.flags ?? []).compactMap(SetFlag.init(rawValue:)),
                                   bodyFlagSite: BodySite.fromStorage(x.bodyFlagSite),
                                   bodyFlagNote: x.bodyFlagNote,
                                   durationSeconds: x.durationSeconds, distanceMiles: x.distanceMiles,
                                   flights: x.flights,
                                   inclinePercent: x.inclinePercent,
                                   loadBasis: x.loadBasis.flatMap(LoadBasis.init(rawValue:))
                                       ?? e.name.flatMap { exByName[$0]?.loadBasis },
                                   implementCount: x.implementCount
                                       ?? e.name.flatMap { exByName[$0]?.resolvedImplementCount } ?? 1,
                                   autoregReason: AutoregReason(rawValue: x.autoregReason ?? ""),
                                   targetWeightLb: x.targetWeightLb,
                                   plannedWeightLb: x.plannedWeightLb,
                                   plannedReps: x.plannedReps,
                                   plannedDurationSeconds: x.plannedDurationSeconds,
                                   prescriptionBlock: PrescriptionBlockKind(rawValue: x.prescriptionBlock ?? "")
                                       ?? (x.isWarmup == true ? .warmup : .work))
                entry.sets.append(set)
            }
            session.exercises.append(entry)
        }
        // v12 typed wood-splitting facts. Values restore verbatim — absence
        // stays absent (INV-WOOD-WORK-DOES-NOT-GUESS), and an all-nil object
        // still restores as a detail row so the session keeps reading as a
        // wood-splitting log.
        if schemaVersion >= 12, let wood = s.woodSplitting {
            session.woodSplittingDetail = WoodSplittingDetail(
                sessionRPE: wood.sessionRPE,
                rounds: wood.rounds,
                splitPieces: wood.splitPieces,
                estimatedStrikes: wood.estimatedStrikes,
                cordVolume: wood.cordVolume
            )
        }
        return session
    }

    private static func makeCoachingDecision(_ d: CoachingDecisionDTO) -> CoachingDecision {
        let decision = CoachingDecision(
            programID: d.programId ?? "",
            ruleID: d.ruleId ?? "",
            recommendationID: d.recommendationId ?? "",
            action: CoachingDecisionAction(rawValue: d.action ?? "") ?? .deferred,
            title: d.title ?? "",
            explanation: d.explanation ?? "",
            evidence: d.evidence ?? [],
            beforeValue: d.beforeValue,
            afterValue: d.afterValue
        )
        if let id = d.id { decision.id = id }
        if let date = d.date { decision.date = date }
        return decision
    }

    private static func applySettings(_ st: SettingsDTO, restoredExercises: Bool, in context: ModelContext) throws {
        let settings = (try context.fetch(FetchDescriptor<AppSettings>()).first) ?? {
            let s = AppSettings(); context.insert(s); return s
        }()
        if let v = st.unitDisplay { settings.unitDisplayRaw = v }
        if let v = st.birthYear { settings.birthYear = v }
        // Rest buckets arrive flat (native backups) or nested under `rest`
        // (web's canonical shape) — accept both; nested wins when both ride,
        // since the web keeps the legacy flat accessory key merely in sync.
        if let v = st.accessoryRestSeconds { settings.accessoryRestSeconds = v }
        if let v = st.mainCompoundRestSeconds { settings.mainCompoundRestSeconds = v }
        if let v = st.olympicRestSeconds { settings.olympicRestSeconds = v }
        if let v = st.mainUpperRestSeconds { settings.mainUpperRestSeconds = v }
        if let v = st.secondaryRestSeconds { settings.secondaryRestSeconds = v }
        if let v = st.rest?.mainCompoundSeconds { settings.mainCompoundRestSeconds = v }
        if let v = st.rest?.olympicSeconds { settings.olympicRestSeconds = v }
        if let v = st.rest?.mainUpperSeconds { settings.mainUpperRestSeconds = v }
        if let v = st.rest?.secondarySeconds { settings.secondaryRestSeconds = v }
        if let v = st.rest?.accessorySeconds { settings.accessoryRestSeconds = v }
        if let v = st.autoStartRest { settings.autoStartRest = v }
        if let v = st.haptics { settings.haptics = v }
        if let v = st.gymTagFirstLaunchOfDay { settings.gymTagFirstLaunchOfDay = v }
        // restSeedStampsCleared describes the EXERCISE LIBRARY's migration
        // state, so it follows the bundle only when the library itself was
        // restored from it: a pre-migration backup (no flag) restores
        // old-stamped exercises and the next syncLibrary must re-clear them,
        // while a settings-only restore keeps the current marker — resetting
        // it over an untouched library could eat a user-set rest that happens
        // to equal a retired stamp (Codex). Mirrors web importBundle.
        if restoredExercises { settings.restSeedStampsCleared = st.restSeedStampsCleared ?? false }
        if restoredExercises { settings.loadSemanticsMigrated = st.loadSemanticsMigrated ?? false }
        // Same reasoning: a restore can write the pre-promotion accessory rows
        // back, so the one-shot stamp has to be re-armed or the repair is
        // blocked permanently on a store that now needs it again.
        if restoredExercises { settings.verticalPullMainsPromoted = st.verticalPullMainsPromoted ?? false }
        // Only accept a known theme; an unknown value would round-trip as
        // garbage on the next export (the UI would silently show Carbon anyway).
        // Keep the backup codec platform-neutral. `ThemeName` lives beside the
        // SwiftUI palette and imports UIKit, while the wire contract is just
        // these four stable strings (mirrored by web `[data-theme]`).
        if let v = st.theme, ["memento", "carbon", "slate", "system"].contains(v) {
            settings.themeNameRaw = v
        }
        // Keep the install marked seeded so a restore isn't re-seeded over
        // (Seeder.seedIfNeeded gates on seededAt != nil).
        settings.seededAt = st.seededAt ?? settings.seededAt ?? .now
    }

    /// Recover a cycle-phase number from an exported phase label ("… R3 …").
    /// Accepts the current "R{n}" prefix and legacy "Wk{n}" from older backups.
    private static func recoverPhase(_ label: String?) -> Int? {
        guard let label,
              let r = label.range(of: #"(?:R|Wk)(\d+)"#, options: .regularExpression) else { return nil }
        return Int(label[r].drop(while: { !$0.isNumber }))
    }

    /// Decode a `data:...;base64,XXXX` URL back to bytes (the gym barcode photo).
    private static func dataFromURL(_ s: String?) -> Data? {
        guard let s, let comma = s.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(s[s.index(after: comma)...]))
    }
}
