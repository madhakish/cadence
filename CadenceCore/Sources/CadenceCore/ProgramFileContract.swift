import Foundation

/// The program-level interchange format: a single program as a standalone JSON
/// document, independent of the portable backup.
///
/// This is a SEPARATE contract from `BackupContract`. It carries its own `kind`
/// discriminator and its own version, so a program file and a full backup can
/// version independently and neither importer can be fed the other's file by
/// accident. Mirrored 1:1 in `web/app/js/program-file.js`; parity is enforced
/// against the shared fixture `web/tests/fixtures/program-file.json` from both
/// suites, so either side drifting fails CI. Regenerate that fixture with
/// `web/tools/generate-program-file-fixture.mjs`.
///
/// String-typed throughout, like `ProgramTemplateData`, so the core stays
/// app-model-agnostic and Linux-testable.
///
/// Version 1 is the plan shape plus optional runtime state and optional
/// identity. A file is plan-only unless it explicitly carries them.
public enum ProgramFileContract {

    public static let kind = "cadence.program"
    public static let currentSchemaVersion = 1

    public static func supports(schemaVersion: Int?) -> Bool {
        guard let schemaVersion else { return false }
        return schemaVersion >= 1 && schemaVersion <= currentSchemaVersion
    }

    // MARK: - Allowed values

    public static let focuses: Set<String> = ["strength", "hypertrophy", "maintain"]
    public static let roles: Set<String> = ["main", "complementary"]
    public static let conditioningEfforts: Set<String> = ["easy", "interval", "mixed"]
    public static let warmupPolicies: Set<String> = ["automatic", "full", "short", "none"]

    // MARK: - Shape

    /// The week-3 peak grade, stashed until cycle rollover. Carried only by a
    /// file exported with state — losing it would turn the next rollover into
    /// a stall, but it is meaningless on someone else's device.
    public struct PendingState: Codable, Equatable, Sendable {
        public var baseWeightLb: Double
        public var estimatedMaxLb: Double
        public var stallCount: Int
        public var lastIncrementLb: Double

        public init(baseWeightLb: Double, estimatedMaxLb: Double, stallCount: Int, lastIncrementLb: Double) {
            self.baseWeightLb = baseWeightLb
            self.estimatedMaxLb = estimatedMaxLb
            self.stallCount = stallCount
            self.lastIncrementLb = lastIncrementLb
        }
    }

    public struct PendingResult: Codable, Equatable, Sendable {
        public var state: PendingState
        public var note: String?

        public init(state: PendingState, note: String?) {
            self.state = state
            self.note = note
        }
    }

    public struct Lift: Codable, Equatable, Sendable {
        /// Present only in a file exported with identity. Slot ids are history
        /// linkage, so preserving them is an explicit choice, not a default.
        public var id: String?
        public var exerciseName: String
        public var role: String
        public var order: Int
        public var prescription: String
        public var warmupPolicy: String
        public var loadOffsetLb: Double
        public var peakOffsetLb: Double
        public var deloadMultiplier: Double
        public var doubleProgressionSets: Int
        public var minimumReps: Int
        public var maximumReps: Int
        public var currentReps: Int
        public var peakSingleEnabled: Bool
        public var peakSingleIncrementLb: Double
        public var phasePrimerEnabled: Bool
        public var dropIncrementLb: Double
        public var capacityManaged: Bool
        public var maximumSets: Int
        public var baseWeightLb: Double
        public var estimatedMaxLb: Double
        /// Runtime state — present as a group or not at all, enforced in
        /// `validate`. `pending` and `revertToExerciseName` are independent:
        /// both are markers that are genuinely absent most of the time.
        public var stallCount: Int?
        public var lastIncrementLb: Double?
        public var lastPeakSingleLb: Double?
        public var pending: PendingResult?
        public var revertToExerciseName: String?

        public init(
            id: String? = nil, exerciseName: String, role: String, order: Int,
            prescription: String, warmupPolicy: String, loadOffsetLb: Double, peakOffsetLb: Double,
            deloadMultiplier: Double, doubleProgressionSets: Int, minimumReps: Int, maximumReps: Int,
            currentReps: Int, peakSingleEnabled: Bool, peakSingleIncrementLb: Double,
            phasePrimerEnabled: Bool, dropIncrementLb: Double, capacityManaged: Bool, maximumSets: Int,
            baseWeightLb: Double, estimatedMaxLb: Double,
            stallCount: Int? = nil, lastIncrementLb: Double? = nil, lastPeakSingleLb: Double? = nil,
            pending: PendingResult? = nil, revertToExerciseName: String? = nil
        ) {
            self.id = id
            self.exerciseName = exerciseName
            self.role = role
            self.order = order
            self.prescription = prescription
            self.warmupPolicy = warmupPolicy
            self.loadOffsetLb = loadOffsetLb
            self.peakOffsetLb = peakOffsetLb
            self.deloadMultiplier = deloadMultiplier
            self.doubleProgressionSets = doubleProgressionSets
            self.minimumReps = minimumReps
            self.maximumReps = maximumReps
            self.currentReps = currentReps
            self.peakSingleEnabled = peakSingleEnabled
            self.peakSingleIncrementLb = peakSingleIncrementLb
            self.phasePrimerEnabled = phasePrimerEnabled
            self.dropIncrementLb = dropIncrementLb
            self.capacityManaged = capacityManaged
            self.maximumSets = maximumSets
            self.baseWeightLb = baseWeightLb
            self.estimatedMaxLb = estimatedMaxLb
            self.stallCount = stallCount
            self.lastIncrementLb = lastIncrementLb
            self.lastPeakSingleLb = lastPeakSingleLb
            self.pending = pending
            self.revertToExerciseName = revertToExerciseName
        }
    }

    public struct Accessory: Codable, Equatable, Sendable {
        public var id: String?
        public var exerciseName: String
        public var order: Int
        public var sets: Int
        public var minReps: Int
        public var maxReps: Int
        public var currentReps: Int
        public var targetSeconds: Int
        public var durationStepSeconds: Int
        public var capacityManaged: Bool
        public var maximumSets: Int
        public var conditioningEffort: String
        public var targetRPE: Int
        public var weightLb: Double
        public var incrementLb: Double
        public var stallCount: Int?
        public var revertToExerciseName: String?

        public init(
            id: String? = nil, exerciseName: String, order: Int, sets: Int, minReps: Int, maxReps: Int,
            currentReps: Int, targetSeconds: Int, durationStepSeconds: Int, capacityManaged: Bool,
            maximumSets: Int, conditioningEffort: String, targetRPE: Int, weightLb: Double,
            incrementLb: Double, stallCount: Int? = nil, revertToExerciseName: String? = nil
        ) {
            self.id = id
            self.exerciseName = exerciseName
            self.order = order
            self.sets = sets
            self.minReps = minReps
            self.maxReps = maxReps
            self.currentReps = currentReps
            self.targetSeconds = targetSeconds
            self.durationStepSeconds = durationStepSeconds
            self.capacityManaged = capacityManaged
            self.maximumSets = maximumSets
            self.conditioningEffort = conditioningEffort
            self.targetRPE = targetRPE
            self.weightLb = weightLb
            self.incrementLb = incrementLb
            self.stallCount = stallCount
            self.revertToExerciseName = revertToExerciseName
        }
    }

    public struct Day: Codable, Equatable, Sendable {
        public var name: String
        /// Verbatim, never renumbered — a day's order is the identity every
        /// banked session's `programTag.dayIndex` refers to.
        public var order: Int
        public var lifts: [Lift]
        public var accessories: [Accessory]

        public init(name: String, order: Int, lifts: [Lift], accessories: [Accessory]) {
            self.name = name
            self.order = order
            self.lifts = lifts
            self.accessories = accessories
        }
    }

    public struct Program: Codable, Equatable, Sendable {
        public var id: String?
        public var name: String
        public var focus: String
        public var roundingLb: Double
        public var coachEnabled: Bool
        public var preferredSessionSpacingDays: Int
        public var maximumAddedSetsPerRotation: Int
        // Wave position — present as a group or not at all.
        public var cycleNumber: Int?
        public var currentWeek: Int?
        public var nextDayIndex: Int?
        public var days: [Day]

        /// A file carries wave position as a group; a partial set is a file we
        /// refuse rather than guess at.
        public var carriesState: Bool {
            cycleNumber != nil && currentWeek != nil && nextDayIndex != nil
        }

        public init(
            id: String? = nil, name: String, focus: String, roundingLb: Double, coachEnabled: Bool,
            preferredSessionSpacingDays: Int, maximumAddedSetsPerRotation: Int,
            cycleNumber: Int? = nil, currentWeek: Int? = nil, nextDayIndex: Int? = nil,
            days: [Day]
        ) {
            self.id = id
            self.name = name
            self.focus = focus
            self.roundingLb = roundingLb
            self.coachEnabled = coachEnabled
            self.preferredSessionSpacingDays = preferredSessionSpacingDays
            self.maximumAddedSetsPerRotation = maximumAddedSetsPerRotation
            self.cycleNumber = cycleNumber
            self.currentWeek = currentWeek
            self.nextDayIndex = nextDayIndex
            self.days = days
        }
    }

    public struct File: Codable, Equatable, Sendable {
        public var kind: String
        public var programSchemaVersion: Int
        public var program: Program

        public init(program: Program) {
            self.kind = ProgramFileContract.kind
            self.programSchemaVersion = ProgramFileContract.currentSchemaVersion
            self.program = program
        }
    }

    // MARK: - Validation

    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case invalid(path: String, message: String)

        public var description: String {
            switch self {
            case .invalid(let path, let message):
                // Same sentence as the backup importer, so the two read alike.
                return "Program file validation failed at \(path): \(message). Nothing was changed."
            }
        }
    }

    private static func check(_ condition: Bool, _ path: String, _ message: @autoclosure () -> String) throws {
        if !condition { throw ValidationError.invalid(path: path, message: message()) }
    }

    private static func text(_ value: String, _ path: String) throws {
        try check(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, path, "expected non-empty text")
    }

    private static func number(_ value: Double, _ path: String, _ min: Double, _ max: Double) throws {
        try check(value.isFinite && value >= min && value <= max, path,
                  "expected a finite number from \(Weight.trim(min, decimals: 2)) to \(Weight.trim(max, decimals: 2))")
    }

    private static func integer(_ value: Int, _ path: String, _ min: Int, _ max: Int) throws {
        try check(value >= min && value <= max, path, "expected an integer from \(min) to \(max)")
    }

    private static func known(_ value: String, _ allowed: Set<String>, _ path: String, _ label: String) throws {
        try check(allowed.contains(value), path, "unknown \(label) \"\(value)\"")
    }

    private static func uuid(_ value: String, _ path: String) throws {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        let shape = parts.map(\.count) == [8, 4, 4, 4, 12]
        let hex = value.allSatisfy { $0.isHexDigit || $0 == "-" }
        try check(shape && hex, path, "expected a UUID")
    }

    /// Full structural validation. Throws on the first problem — callers run
    /// this before opening a write, so a rejected file changes nothing.
    public static func validate(_ file: File) throws {
        try check(file.kind == kind, "kind", "expected \"\(kind)\", got \"\(file.kind)\"")
        try check(supports(schemaVersion: file.programSchemaVersion), "programSchemaVersion",
                  "version \(file.programSchemaVersion) is not supported (this app writes \(currentSchemaVersion))")

        let program = file.program
        try text(program.name, "program.name")
        try known(program.focus, focuses, "program.focus", "focus")
        try number(program.roundingLb, "program.roundingLb", 0.5, 50)
        try integer(program.preferredSessionSpacingDays, "program.preferredSessionSpacingDays", 0, 14)
        try integer(program.maximumAddedSetsPerRotation, "program.maximumAddedSetsPerRotation", 0, 60)
        if let id = program.id { try uuid(id, "program.id") }

        // Wave position is all-or-nothing: a half-carried state would silently
        // reposition the program in its cycle.
        let statePresent = [program.cycleNumber != nil, program.currentWeek != nil, program.nextDayIndex != nil]
        try check(statePresent.allSatisfy { $0 } || statePresent.allSatisfy { !$0 }, "program.cycleNumber",
                  "wave position must be complete or absent")
        if let cycle = program.cycleNumber { try integer(cycle, "program.cycleNumber", 1, 9999) }
        if let week = program.currentWeek { try integer(week, "program.currentWeek", 1, 4) }
        if let next = program.nextDayIndex { try integer(next, "program.nextDayIndex", 0, 99) }

        try check(!program.days.isEmpty, "program.days", "expected at least one day")

        var dayOrders = Set<Int>()
        var slotIDs = Set<String>()
        for (dayIndex, day) in program.days.enumerated() {
            let path = "program.days[\(dayIndex)]"
            try text(day.name, "\(path).name")
            try integer(day.order, "\(path).order", 0, 99)
            try check(dayOrders.insert(day.order).inserted, "\(path).order", "duplicate day order \(day.order)")
            try check(!day.lifts.isEmpty || !day.accessories.isEmpty, path,
                      "expected at least one lift or accessory")

            for (i, lift) in day.lifts.enumerated() {
                let p = "\(path).lifts[\(i)]"
                try text(lift.exerciseName, "\(p).exerciseName")
                try known(lift.role, roles, "\(p).role", "role")
                try known(lift.warmupPolicy, warmupPolicies, "\(p).warmupPolicy", "warm-up policy")
                try check(PrescriptionStyle(rawValue: lift.prescription) != nil, "\(p).prescription",
                          "unknown prescription style \"\(lift.prescription)\"")
                try integer(lift.order, "\(p).order", 0, 99)
                try number(lift.loadOffsetLb, "\(p).loadOffsetLb", 0, 500)
                try number(lift.peakOffsetLb, "\(p).peakOffsetLb", 0, 500)
                try number(lift.deloadMultiplier, "\(p).deloadMultiplier", 0.25, 1)
                try integer(lift.doubleProgressionSets, "\(p).doubleProgressionSets", 1, 20)
                try integer(lift.minimumReps, "\(p).minimumReps", 1, 100)
                try integer(lift.maximumReps, "\(p).maximumReps", 1, 100)
                try check(lift.minimumReps <= lift.maximumReps, "\(p).maximumReps",
                          "maximum reps is below minimum reps")
                try integer(lift.currentReps, "\(p).currentReps", 1, 100)
                try number(lift.peakSingleIncrementLb, "\(p).peakSingleIncrementLb", 0, 500)
                try number(lift.dropIncrementLb, "\(p).dropIncrementLb", 0, 500)
                try integer(lift.maximumSets, "\(p).maximumSets", 1, 20)
                try number(lift.baseWeightLb, "\(p).baseWeightLb", 0, 2000)
                try number(lift.estimatedMaxLb, "\(p).estimatedMaxLb", 0, 2000)
                // Runtime state is a group, matching the JS validator. A file
                // carrying one counter but not the others describes a slot
                // half-way through a cycle, which is not a state the engine
                // ever produces — accepting it would let the two clients
                // disagree about the same file.
                let liftState = [lift.stallCount != nil, lift.lastIncrementLb != nil, lift.lastPeakSingleLb != nil]
                try check(liftState.allSatisfy { $0 } || liftState.allSatisfy { !$0 }, "\(p).stallCount",
                          "progression state must be complete or absent")
                if let stall = lift.stallCount { try integer(stall, "\(p).stallCount", 0, 100) }
                if let inc = lift.lastIncrementLb { try number(inc, "\(p).lastIncrementLb", 0, 500) }
                if let peak = lift.lastPeakSingleLb { try number(peak, "\(p).lastPeakSingleLb", 0, 2000) }
                if let id = lift.id {
                    try uuid(id, "\(p).id")
                    // Two slots sharing an id make progression advance the
                    // wrong lift. Reject rather than silently repair.
                    try check(slotIDs.insert(id).inserted, "\(p).id", "duplicate identifier \"\(id)\"")
                }
            }

            for (i, accessory) in day.accessories.enumerated() {
                let p = "\(path).accessories[\(i)]"
                try text(accessory.exerciseName, "\(p).exerciseName")
                try integer(accessory.order, "\(p).order", 0, 99)
                try integer(accessory.sets, "\(p).sets", 1, 20)
                try integer(accessory.minReps, "\(p).minReps", 1, 100)
                try integer(accessory.maxReps, "\(p).maxReps", 1, 100)
                try check(accessory.minReps <= accessory.maxReps, "\(p).maxReps",
                          "maximum reps is below minimum reps")
                try integer(accessory.currentReps, "\(p).currentReps", 1, 100)
                try integer(accessory.targetSeconds, "\(p).targetSeconds", 0, 3600)
                try integer(accessory.durationStepSeconds, "\(p).durationStepSeconds", 0, 600)
                try integer(accessory.maximumSets, "\(p).maximumSets", 1, 20)
                try known(accessory.conditioningEffort, conditioningEfforts,
                          "\(p).conditioningEffort", "conditioning effort")
                try integer(accessory.targetRPE, "\(p).targetRPE", 0, 10)
                try number(accessory.weightLb, "\(p).weightLb", 0, 2000)
                try number(accessory.incrementLb, "\(p).incrementLb", 0, 500)
                if let stall = accessory.stallCount { try integer(stall, "\(p).stallCount", 0, 100) }
                if let id = accessory.id {
                    try uuid(id, "\(p).id")
                    try check(slotIDs.insert(id).inserted, "\(p).id", "duplicate identifier \"\(id)\"")
                }
            }
        }

        // nextDayIndex is a day ORDER, not a position in the array. A pointer
        // that names no day silently falls back to the first day, quietly
        // losing the wave position the file was carrying. The backup validator
        // enforces the same membership rule (INV-NEXTDAY-IS-AN-ORDER).
        if let next = program.nextDayIndex {
            try check(dayOrders.contains(next), "program.nextDayIndex",
                      "\(next) is not one of this program's day orders (\(dayOrders.sorted().map(String.init).joined(separator: ", ")))")
        }
    }
}
