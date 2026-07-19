import Foundation
import SwiftData
import CadenceCore

enum WarmupPolicy: String, Codable, CaseIterable {
    case automatic
    case full
    case short
    case none

    var name: String {
        switch self {
        case .automatic: return "Automatic"
        case .full: return "Full ramp"
        case .short: return "Short ramp"
        case .none: return "No warm-up"
        }
    }
}

/// A structured training plan: ordered days, each pairing a main + complementary
/// cycle-lift with accessories. The program OWNS the progression state for its
/// lifts and drives one unified 4-week wave (`currentWeek`). Adaptive
/// cross-cycle progression lives in CadenceCore (`ProgramProgression`).
@Model
final class Program {
    @Attribute(.unique) var id: String = UUID().uuidString
    @Attribute(.unique) var name: String
    var focusRaw: String
    var cycleNumber: Int
    var currentWeek: Int            // 1...4 phase pointer for the whole program
    var nextDayIndex: Int
    var roundingLb: Double
    var isActive: Bool
    var coachEnabled: Bool = true
    /// Nil keeps all history eligible. Users with incomplete alpha-era logs
    /// can explicitly choose the first reliable date without deleting data.
    var reliableHistoryStart: Date?
    var preferredSessionSpacingDays: Int = 3
    var maximumAddedSetsPerRotation: Int = 6
    @Relationship(deleteRule: .cascade, inverse: \ProgramDay.program)
    var days: [ProgramDay]
    var createdAt: Date

    init(name: String, focus: TrainingFocus = .strength, cycleNumber: Int = 1,
         currentWeek: Int = 1, nextDayIndex: Int = 0, roundingLb: Double = 5, isActive: Bool = true) {
        self.name = name
        self.focusRaw = focus.rawValue
        self.cycleNumber = cycleNumber
        self.currentWeek = currentWeek
        self.nextDayIndex = nextDayIndex
        self.roundingLb = roundingLb
        self.isActive = isActive
        self.coachEnabled = true
        self.reliableHistoryStart = nil
        self.preferredSessionSpacingDays = 3
        self.maximumAddedSetsPerRotation = 6
        self.days = []
        self.createdAt = .now
    }

    var focus: TrainingFocus {
        get { TrainingFocus(rawValue: focusRaw) ?? .strength }
        set { focusRaw = newValue.rawValue }
    }

    var orderedDays: [ProgramDay] { days.sorted { $0.order < $1.order } }

    /// All exercise names owned by this program (so Home can filter them out of
    /// the standalone "Next up" tracks).
    var ownedExerciseNames: Set<String> {
        Set(days.flatMap { $0.lifts.map(\.exerciseName) + $0.accessories.map(\.exerciseName) })
    }
}

@Model
final class ProgramDay {
    var name: String
    var order: Int
    var program: Program?
    @Relationship(deleteRule: .cascade, inverse: \ProgramLift.day)
    var lifts: [ProgramLift]
    @Relationship(deleteRule: .cascade, inverse: \ProgramAccessory.day)
    var accessories: [ProgramAccessory]

    init(name: String, order: Int) {
        self.name = name
        self.order = order
        self.lifts = []
        self.accessories = []
    }

    /// The coach's explicit order. Legacy stores whose slots predate the field
    /// retain the old main-first behavior until the day is reordered once.
    var orderedLifts: [ProgramLift] {
        if Set(lifts.map(\.order)).count <= 1 {
            return lifts.sorted {
                ($0.role == .main ? 0 : 1, $0.exerciseName)
                    < ($1.role == .main ? 0 : 1, $1.exerciseName)
            }
        }
        return lifts.sorted { ($0.order, $0.exerciseName) < ($1.order, $1.exerciseName) }
    }
    var orderedAccessories: [ProgramAccessory] {
        accessories.sorted { ($0.order, $0.exerciseName) < ($1.order, $1.exerciseName) }
    }
}

/// A cycle-driven main/complementary lift. Wraps `ProgramLiftState`.
@Model
final class ProgramLift {
    /// Stable slot identity. Exercise names and roles are editable presentation;
    /// completion must advance the slot that created the session entry.
    var id: String = UUID().uuidString
    var exerciseName: String
    var roleRaw: String
    var order: Int = 0
    var prescriptionRaw: String = "automatic"
    var warmupPolicyRaw: String = "automatic"
    /// Zero offsets mean use movement-aware defaults (25/33 lower body,
    /// 10/15 upper body). Explicit values remain user-owned.
    var loadOffsetLb: Double = 0
    var peakOffsetLb: Double = 0
    var deloadMultiplier: Double = 0.775
    var doubleProgressionSets: Int = 3
    var minimumReps: Int = 5
    var maximumReps: Int = 8
    var currentReps: Int = 5
    var peakSingleEnabled: Bool = false
    var lastPeakSingleLb: Double = 0
    var peakSingleIncrementLb: Double = 5
    var phasePrimerEnabled: Bool = true
    var dropIncrementLb: Double = 0
    var capacityManaged: Bool = true
    var maximumSets: Int = 6
    var baseWeightLb: Double
    var estimatedMaxLb: Double
    var stallCount: Int
    var lastIncrementLb: Double
    // Week-3 grade is stashed here and applied at cycle rollover (deload week end).
    var pendingBaseWeightLb: Double?
    var pendingEstimatedMaxLb: Double?
    var pendingStallCount: Int?
    var pendingLastIncrementLb: Double?
    var pendingNote: String?
    /// Cycle-scoped swap (issue 20): the slot's original exercise, restored
    /// at the next cycle rollover. nil = no revert pending.
    var revertToExerciseName: String?
    var day: ProgramDay?

    init(id: String = UUID().uuidString, exerciseName: String, role: LiftRole, order: Int = 0,
         prescription: PrescriptionStyle = .automatic, warmupPolicy: WarmupPolicy = .automatic,
         baseWeightLb: Double, estimatedMaxLb: Double, stallCount: Int = 0, lastIncrementLb: Double = 0) {
        self.id = id
        self.exerciseName = exerciseName
        self.roleRaw = role.rawValue
        self.order = order
        self.prescriptionRaw = prescription.rawValue
        self.warmupPolicyRaw = warmupPolicy.rawValue
        self.baseWeightLb = baseWeightLb
        self.estimatedMaxLb = estimatedMaxLb
        self.stallCount = stallCount
        self.lastIncrementLb = lastIncrementLb
    }

    var role: LiftRole {
        get { LiftRole(rawValue: roleRaw) ?? .main }
        set { roleRaw = newValue.rawValue }
    }

    var prescription: PrescriptionStyle {
        get { PrescriptionStyle(rawValue: prescriptionRaw) ?? .automatic }
        set { prescriptionRaw = newValue.rawValue }
    }

    var warmupPolicy: WarmupPolicy {
        get { WarmupPolicy(rawValue: warmupPolicyRaw) ?? .automatic }
        set { warmupPolicyRaw = newValue.rawValue }
    }

    var coreState: ProgramLiftState {
        ProgramLiftState(baseWeightLb: baseWeightLb, estimatedMaxLb: estimatedMaxLb,
                         stallCount: stallCount, role: role, lastIncrementLb: lastIncrementLb)
    }

    func prescriptionConfiguration(movementGroup: String) -> LiftPrescriptionConfiguration {
        let lower = movementGroup == "squat" || movementGroup == "hinge"
        return LiftPrescriptionConfiguration(
            loadOffsetLb: loadOffsetLb > 0 ? loadOffsetLb : (lower ? 25 : 10),
            peakOffsetLb: peakOffsetLb > 0 ? peakOffsetLb : (lower ? 33 : 15),
            deloadMultiplier: deloadMultiplier > 0 ? deloadMultiplier : 0.775,
            workingSets: max(1, doubleProgressionSets),
            minimumReps: max(1, minimumReps),
            maximumReps: max(minimumReps, maximumReps),
            currentReps: currentReps,
            peakSingleEnabled: peakSingleEnabled,
            lastPeakSingleLb: lastPeakSingleLb,
            peakSingleIncrementLb: peakSingleIncrementLb,
            phasePrimerEnabled: phasePrimerEnabled
        )
    }

    func apply(_ s: ProgramLiftState) {
        baseWeightLb = s.baseWeightLb
        estimatedMaxLb = s.estimatedMaxLb
        stallCount = s.stallCount
        lastIncrementLb = s.lastIncrementLb
    }
}

/// An accessory tracked with double progression. Wraps `AccessoryState`.
@Model
final class ProgramAccessory {
    /// Stable slot identity; see ProgramLift.id.
    var id: String = UUID().uuidString
    var exerciseName: String
    var order: Int = 0
    var sets: Int
    var minReps: Int
    var maxReps: Int
    var currentReps: Int
    /// Timed accessories use seconds instead of reps. Kept alongside the rep
    /// fields so changing an exercise between typed and rep-based is lossless.
    var targetSeconds: Int = 30
    var durationStepSeconds: Int = 5
    var capacityManaged: Bool = true
    var maximumSets: Int = 6
    /// Easy conditioning defaults to conversational effort. RPE zero means no
    /// explicit target; it remains separate from lifting-set analytics.
    var conditioningEffortRaw: String = "easy"
    var targetRPE: Int = 0
    var weightLb: Double
    var incrementLb: Double
    var stallCount: Int
    /// Cycle-scoped swap (issue 20): the slot's original exercise, restored
    /// at the next cycle rollover. nil = no revert pending.
    var revertToExerciseName: String?
    var day: ProgramDay?

    var conditioningEffort: ConditioningEffort {
        get { ConditioningEffort(rawValue: conditioningEffortRaw) ?? .easy }
        set { conditioningEffortRaw = newValue.rawValue }
    }

    init(id: String = UUID().uuidString, exerciseName: String, order: Int = 0, sets: Int, minReps: Int, maxReps: Int,
         currentReps: Int, targetSeconds: Int = 30, durationStepSeconds: Int = 5,
         weightLb: Double, incrementLb: Double, stallCount: Int = 0) {
        self.id = id
        self.exerciseName = exerciseName
        self.order = order
        self.sets = sets
        self.minReps = minReps
        self.maxReps = maxReps
        self.currentReps = currentReps
        self.targetSeconds = targetSeconds
        self.durationStepSeconds = durationStepSeconds
        self.weightLb = weightLb
        self.incrementLb = incrementLb
        self.stallCount = stallCount
    }

    var coreState: AccessoryState {
        AccessoryState(sets: sets, minReps: minReps, maxReps: maxReps, currentReps: currentReps,
                       weightLb: weightLb, incrementLb: incrementLb, stallCount: stallCount)
    }

    func apply(_ s: AccessoryState) {
        sets = s.sets
        minReps = s.minReps
        maxReps = s.maxReps
        currentReps = s.currentReps
        weightLb = s.weightLb
        incrementLb = s.incrementLb
        stallCount = s.stallCount
    }
}

enum ConditioningEffort: String, CaseIterable {
    case easy
    case interval
    case mixed

    var name: String {
        switch self {
        case .easy: return "Easy / conversational"
        case .interval: return "Intervals"
        case .mixed: return "Mixed"
        }
    }
}
