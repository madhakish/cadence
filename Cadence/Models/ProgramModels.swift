import Foundation
import SwiftData
import CadenceCore

/// A structured training plan: ordered days, each pairing a main + complementary
/// cycle-lift with accessories. The program OWNS the progression state for its
/// lifts and drives one unified 4-week wave (`currentWeek`). Adaptive
/// cross-cycle progression lives in CadenceCore (`ProgramProgression`).
@Model
final class Program {
    @Attribute(.unique) var name: String
    var focusRaw: String
    var cycleNumber: Int
    var currentWeek: Int            // 1...4 phase pointer for the whole program
    var nextDayIndex: Int
    var roundingLb: Double
    var isActive: Bool
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

    /// Main first, then complementary.
    var orderedLifts: [ProgramLift] {
        lifts.sorted { (a, b) in (a.role == .main ? 0 : 1) < (b.role == .main ? 0 : 1) }
    }
    var orderedAccessories: [ProgramAccessory] { accessories }
}

/// A cycle-driven main/complementary lift. Wraps `ProgramLiftState`.
@Model
final class ProgramLift {
    var exerciseName: String
    var roleRaw: String
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
    var day: ProgramDay?

    init(exerciseName: String, role: LiftRole, baseWeightLb: Double, estimatedMaxLb: Double,
         stallCount: Int = 0, lastIncrementLb: Double = 0) {
        self.exerciseName = exerciseName
        self.roleRaw = role.rawValue
        self.baseWeightLb = baseWeightLb
        self.estimatedMaxLb = estimatedMaxLb
        self.stallCount = stallCount
        self.lastIncrementLb = lastIncrementLb
    }

    var role: LiftRole {
        get { LiftRole(rawValue: roleRaw) ?? .main }
        set { roleRaw = newValue.rawValue }
    }

    var coreState: ProgramLiftState {
        ProgramLiftState(baseWeightLb: baseWeightLb, estimatedMaxLb: estimatedMaxLb,
                         stallCount: stallCount, role: role, lastIncrementLb: lastIncrementLb)
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
    var exerciseName: String
    var sets: Int
    var minReps: Int
    var maxReps: Int
    var currentReps: Int
    var weightLb: Double
    var incrementLb: Double
    var stallCount: Int
    var day: ProgramDay?

    init(exerciseName: String, sets: Int, minReps: Int, maxReps: Int,
         currentReps: Int, weightLb: Double, incrementLb: Double, stallCount: Int = 0) {
        self.exerciseName = exerciseName
        self.sets = sets
        self.minReps = minReps
        self.maxReps = maxReps
        self.currentReps = currentReps
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
