import Foundation
import SwiftData
import ComebackCore

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
    var gymName: String?
    // Set when this session was generated from a program day, so completion
    // advances PROGRAM state (not standalone tracks).
    var programName: String?
    var programCycleNumber: Int?
    var programWeek: Int?
    var programDayIndex: Int?
    @Relationship(deleteRule: .cascade, inverse: \SessionExercise.session)
    var exercises: [SessionExercise]

    init(date: Date = .now, notes: String = "", gymName: String? = nil) {
        self.date = date
        self.notes = notes
        self.isCompleted = false
        self.gymName = gymName
        self.exercises = []
    }

    var orderedExercises: [SessionExercise] {
        exercises.sorted { $0.order < $1.order }
    }

    /// True if this session contains running-type conditioning (drives the
    /// next-morning right-knee check-in).
    var includesRunning: Bool {
        exercises.contains {
            let name = $0.exercise?.name.lowercased() ?? ""
            return name.contains("run")
        }
    }
}

@Model
final class SessionExercise {
    var order: Int
    var notes: String
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
    var workingSets: [SetEntry] { orderedSets.filter { !$0.isWarmup } }

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
    /// Unilateral movements: reps are per side.
    var isPerSide: Bool
    /// What the user actually typed (lb/kg) so the field re-displays in kind.
    var enteredUnitRaw: String
    var flagsRaw: [String]
    var bodyFlagSiteRaw: String?
    var bodyFlagNote: String?
    /// Timed work (planks) in seconds.
    var durationSeconds: Int?
    /// Conditioning distance, miles.
    var distanceMiles: Double?
    /// Set when this set's load came from a mid-session "dropping load" tap.
    var autoregReasonRaw: String?
    var sessionExercise: SessionExercise?

    init(
        order: Int,
        weightLb: Double,
        reps: Int,
        isWarmup: Bool = false,
        isPerSide: Bool = false,
        enteredUnit: WeightUnit = .lb,
        flags: [SetFlag] = [],
        bodyFlagSite: BodySite? = nil,
        bodyFlagNote: String? = nil,
        durationSeconds: Int? = nil,
        distanceMiles: Double? = nil,
        autoregReason: AutoregReason? = nil
    ) {
        self.order = order
        self.weightLb = weightLb
        self.reps = reps
        self.isWarmup = isWarmup
        self.isPerSide = isPerSide
        self.enteredUnitRaw = enteredUnit.rawValue
        self.flagsRaw = flags.map(\.rawValue)
        self.bodyFlagSiteRaw = bodyFlagSite?.rawValue
        self.bodyFlagNote = bodyFlagNote
        self.durationSeconds = durationSeconds
        self.distanceMiles = distanceMiles
        self.autoregReasonRaw = autoregReason?.rawValue
    }

    var flags: [SetFlag] {
        get { flagsRaw.compactMap(SetFlag.init(rawValue:)) }
        set { flagsRaw = newValue.map(\.rawValue) }
    }

    var bodyFlagSite: BodySite? {
        get { bodyFlagSiteRaw.flatMap(BodySite.init(rawValue:)) }
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
