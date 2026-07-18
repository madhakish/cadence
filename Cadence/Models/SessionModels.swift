import Foundation
import SwiftData
import CadenceCore

/// Per-set quality flags. One thumb-tap each in the logger.
enum SetFlag: String, Codable, CaseIterable {
    case clean
    case grindy
    case wobble
    case stoppedEarly = "stopped early"
}

@Model
final class WorkoutSession {
    var date: Date
    var notes: String
    var isCompleted: Bool
    /// Stable equipment linkage. `gymName` remains the historical display
    /// label and the fallback for records created before schema v2.
    var gymID: String?
    var gymName: String?
    // Set when this session was generated from a program day, so completion
    // advances PROGRAM state (not standalone tracks).
    var programID: String?
    var programName: String?
    var programCycleNumber: Int?
    var programWeek: Int?
    var programDayIndex: Int?
    /// The day plan this session was BUILT from (ordered lift+accessory names).
    /// Compared against the day's CURRENT plan to decide resume-vs-rebuild:
    /// unchanged program → resume (preserving session-local removes/swaps);
    /// edited program → rebuild. nil for pre-snapshot sessions (never resumed).
    var programPlanNames: [String]?
    @Relationship(deleteRule: .cascade, inverse: \SessionExercise.session)
    var exercises: [SessionExercise]

    init(date: Date = .now, notes: String = "", gymID: String? = nil, gymName: String? = nil) {
        self.date = date
        self.notes = notes
        self.isCompleted = false
        self.gymID = gymID
        self.gymName = gymName
        self.exercises = []
    }

    var orderedExercises: [SessionExercise] {
        exercises.sorted { $0.order < $1.order }
    }

    /// True if this session contains a movement watched at the knee
    /// (running-type conditioning) — drives the next-morning knee check-in.
    /// Keyed on the exercise's watch-site data (editable in the library),
    /// not on name matching.
    var includesRunning: Bool {
        exercises.contains { $0.exercise?.watchSite == .knee && !$0.workingSets.isEmpty }
    }

    var hasCompletedWork: Bool { exercises.contains { !$0.workingSets.isEmpty } }
}

@Model
final class SessionExercise {
    var order: Int
    var notes: String
    /// Optional per-exercise override. Nil follows the session gym's default.
    var barID: String?
    var exercise: Exercise?
    var session: WorkoutSession?
    @Relationship(deleteRule: .cascade, inverse: \SetEntry.sessionExercise)
    var sets: [SetEntry]
    // The plan this started from, so edits vs. plan are visible later.
    var plannedWeightLb: Double?
    var plannedSets: Int?
    var plannedReps: Int?
    var phaseRaw: Int?
    /// "main" / "complementary" / "accessory" when part of a program day; nil otherwise.
    var programRole: String?
    /// Stable ProgramLift/ProgramAccessory slot that produced this entry.
    /// Names/roles remain only a fallback for sessions created before this key.
    var programSlotID: String?

    init(order: Int, exercise: Exercise?, notes: String = "") {
        self.order = order
        self.exercise = exercise
        self.notes = notes
        self.sets = []
    }

    var phase: CyclePhase? {
        get { phaseRaw.flatMap(CyclePhase.init(rawValue:)) }
        set { phaseRaw = newValue?.rawValue }
    }

    var orderedSets: [SetEntry] { sets.sorted { $0.order < $1.order } }
    var plannedWorkingSets: [SetEntry] { orderedSets.filter { !$0.isWarmup } }
    /// Only performed work belongs in history, PRs, volume, or progression.
    var workingSets: [SetEntry] { plannedWorkingSets.filter { $0.status == .completed } }

    var workingVolumeLb: Double {
        workingSets.reduce(0) { $0 + $1.weightLb * Double($1.reps) }
    }

    var topSet: SetEntry? {
        workingSets.max { $0.weightLb < $1.weightLb }
    }
}

@Model
final class SetEntry {
    var order: Int
    /// Canonical pounds. Always. kg entry is converted at the keyboard.
    var weightLb: Double
    var reps: Int
    var isWarmup: Bool
    /// Empty marks a pre-v2 record. Completed historical sessions migrate as
    /// performed; ambiguous open-session sets migrate as planned.
    var statusRaw: String = ""
    /// Unilateral movements: reps are per side.
    var isPerSide: Bool
    /// What the user actually typed (lb/kg) so the field re-displays in kind.
    var enteredUnitRaw: String
    var flagsRaw: [String]
    var bodyFlagSiteRaw: String?
    var bodyFlagNote: String?
    /// Timed work (planks) and conditioning duration, seconds.
    var durationSeconds: Int?
    /// Conditioning distance, miles.
    var distanceMiles: Double?
    /// Conditioning treadmill/road grade, percent.
    var inclinePercent: Double?
    /// Set when this set's load came from a mid-session "dropping load" tap.
    var autoregReasonRaw: String?
    var sessionExercise: SessionExercise?

    init(
        order: Int,
        weightLb: Double,
        reps: Int,
        isWarmup: Bool = false,
        status: SetStatus = .planned,
        isPerSide: Bool = false,
        enteredUnit: WeightUnit = .lb,
        flags: [SetFlag] = [],
        bodyFlagSite: BodySite? = nil,
        bodyFlagNote: String? = nil,
        durationSeconds: Int? = nil,
        distanceMiles: Double? = nil,
        inclinePercent: Double? = nil,
        autoregReason: AutoregReason? = nil
    ) {
        self.order = order
        self.weightLb = weightLb
        self.reps = reps
        self.isWarmup = isWarmup
        self.statusRaw = status.rawValue
        self.isPerSide = isPerSide
        self.enteredUnitRaw = enteredUnit.rawValue
        self.flagsRaw = flags.map(\.rawValue)
        self.bodyFlagSiteRaw = bodyFlagSite?.rawValue
        self.bodyFlagNote = bodyFlagNote
        self.durationSeconds = durationSeconds
        self.distanceMiles = distanceMiles
        self.inclinePercent = inclinePercent
        self.autoregReasonRaw = autoregReason?.rawValue
    }

    var flags: [SetFlag] {
        get {
            SetLifecycle.normalizedFlags(
                quality: SetLifecycle.quality(in: flagsRaw),
                stoppedEarly: flagsRaw.contains(SetFlag.stoppedEarly.rawValue)
            ).compactMap(SetFlag.init(rawValue:))
        }
        set { flagsRaw = newValue.map(\.rawValue) }
    }

    var status: SetStatus {
        get {
            SetLifecycle.resolve(statusRaw.isEmpty ? nil : statusRaw,
                                 sessionCompleted: sessionExercise?.session?.isCompleted == true)
        }
        set { statusRaw = newValue.rawValue }
    }

    var quality: SetFlag? {
        get { flags.first { $0 == .clean || $0 == .grindy || $0 == .wobble } }
        set {
            flags = SetLifecycle.normalizedFlags(
                quality: newValue == .stoppedEarly ? nil : newValue?.rawValue,
                stoppedEarly: flags.contains(.stoppedEarly)
            ).compactMap(SetFlag.init(rawValue:))
        }
    }

    var bodyFlagSite: BodySite? {
        get { BodySite.fromStorage(bodyFlagSiteRaw) }
        set { bodyFlagSiteRaw = newValue?.rawValue }
    }

    var autoregReason: AutoregReason? {
        get { autoregReasonRaw.flatMap(AutoregReason.init(rawValue:)) }
        set { autoregReasonRaw = newValue?.rawValue }
    }

    var enteredUnit: WeightUnit {
        get { WeightUnit(rawValue: enteredUnitRaw) ?? .lb }
        set { enteredUnitRaw = newValue.rawValue }
    }
}
