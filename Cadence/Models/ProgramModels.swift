import Foundation
import SwiftData
import CadenceCore

/// Relationship collections in shipped stores may contain the same model
/// reference more than once after older code mutated both sides of an inverse.
/// Collapse those aliases at every read boundary as well as repairing the
/// persisted arrays in Seeder.
private func uniqueProgramModels<Model: PersistentModel>(_ models: [Model]) -> [Model] {
    var seen: Set<PersistentIdentifier> = []
    return models.filter { seen.insert($0.persistentModelID).inserted }
}

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

/// A structured training plan: ordered days, individually prescribed lifts,
/// and accessories. The program owns each slot's progression state. Its
/// `currentWeek` is the persisted compatibility name for a style-neutral
/// rotation pointer; each prescription interprets that position itself, so a
/// classic wave, max effort, dynamic effort and rep progression may coexist.
/// Adaptive progression lives in CadenceCore (`ProgramProgression`).
@Model
final class Program {
    @Attribute(.unique) var id: String = UUID().uuidString
    @Attribute(.unique) var name: String
    var focusRaw: String
    var cycleNumber: Int
    var currentWeek: Int            // 1...4 style-neutral rotation pointer
    var nextDayIndex: Int
    var roundingLb: Double
    var isActive: Bool
    var coachEnabled: Bool = true
    /// Nil keeps all history eligible. Users with incomplete alpha-era logs
    /// can explicitly choose the first reliable date without deleting data.
    var reliableHistoryStart: Date?
    var preferredSessionSpacingDays: Int = 3
    var maximumAddedSetsPerRotation: Int = 6
    /// Automatic exercise selection may use any equipment unless a program
    /// explicitly narrows itself to free-weight/bodyweight work.
    var equipmentPolicyRaw: String = "any"
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
        self.equipmentPolicyRaw = "any"
        self.days = []
        self.createdAt = .now
    }

    var focus: TrainingFocus {
        get { TrainingFocus(rawValue: focusRaw) ?? .strength }
        set { focusRaw = newValue.rawValue }
    }

    var equipmentPolicy: EquipmentPolicy {
        get { EquipmentPolicy(rawValue: equipmentPolicyRaw) ?? .any }
        set { equipmentPolicyRaw = newValue.rawValue }
    }

    var orderedDays: [ProgramDay] {
        uniqueProgramModels(days).sorted { $0.order < $1.order }
    }

    /// The day whose ORDER (not array position) matches — the only correct
    /// way to resolve a stored day pointer, since orders are unique but not
    /// contiguous and the collection is unordered.
    func day(order: Int) -> ProgramDay? {
        orderedDays.first { $0.order == order }
    }

    /// The scheduled next day, falling back to the lowest-order day when the
    /// pointer names an order that no longer exists (a deleted or renumbered
    /// day must not strand the schedule).
    var nextDay: ProgramDay? {
        day(order: nextDayIndex) ?? orderedDays.first
    }

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
    /// Explicit authoring intent. `general` preserves every existing program.
    var trainingIntentRaw: String = "general"
    var program: Program?
    @Relationship(deleteRule: .cascade, inverse: \ProgramLift.day)
    var lifts: [ProgramLift]
    @Relationship(deleteRule: .cascade, inverse: \ProgramAccessory.day)
    var accessories: [ProgramAccessory]

    init(name: String, order: Int) {
        self.name = name
        self.order = order
        self.trainingIntentRaw = "general"
        self.lifts = []
        self.accessories = []
    }

    var trainingIntent: DayTrainingIntent {
        get { DayTrainingIntent(rawValue: trainingIntentRaw) ?? .general }
        set { trainingIntentRaw = newValue.rawValue }
    }

    /// Main work first, then complementary work. Explicit order is retained
    /// inside each role so assistance cannot move ahead of the main lift.
    var orderedLifts: [ProgramLift] {
        uniqueProgramModels(lifts).sorted {
            ProgramEngine.programSlotPrecedes(
                lhsRole: $0.roleRaw, lhsOrder: $0.order, lhsName: $0.exerciseName,
                rhsRole: $1.roleRaw, rhsOrder: $1.order, rhsName: $1.exerciseName
            )
        }
    }
    var orderedAccessories: [ProgramAccessory] {
        uniqueProgramModels(accessories).sorted { ($0.order, $0.exerciseName) < ($1.order, $1.exerciseName) }
    }

    /// Authored order (order field, ordinal name tiebreak), role-blind — the
    /// portable contracts (backup, program file) serialize the athlete's
    /// authored sequence exactly as the web exporter does; role-first
    /// `orderedLifts` is a display/session rule, not part of the bytes.
    var authoredLifts: [ProgramLift] {
        uniqueProgramModels(lifts).sorted { ($0.order, $0.exerciseName) < ($1.order, $1.exerciseName) }
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
    // Rotation-3 grade is stashed here and applied after the recovery bridge.
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

    /// The slot's effective rep window. See `ProgramProgression.repWindow`.
    /// `loadable` is false for a slot whose double progression has no weight
    /// to add (a bodyweight-basis identity), which climbs past its window top
    /// instead of resetting.
    func repWindow(loadable: Bool = true) -> (low: Int, high: Int, current: Int) {
        ProgramProgression.repWindow(
            minReps: minimumReps, maxReps: maximumReps, currentReps: currentReps,
            capped: loadable
        )
    }

    func prescriptionConfiguration(movementGroup: String) -> LiftPrescriptionConfiguration {
        // Resolved in CadenceCore so both clients agree — see resolvedOffsets.
        let window = repWindow()
        let offsets = ProgramEngine.resolvedOffsets(
            loadOffsetLb: loadOffsetLb, peakOffsetLb: peakOffsetLb, movementGroup: movementGroup
        )
        return LiftPrescriptionConfiguration(
            loadOffsetLb: offsets.load,
            peakOffsetLb: offsets.peak,
            deloadMultiplier: deloadMultiplier > 0 ? deloadMultiplier : 0.775,
            workingSets: max(1, doubleProgressionSets),
            // One owner for the window — crossed steppers read as the same
            // range with its ends swapped rather than a collapsed one. The
            // target itself passes through RAW: `linearFives` stores its
            // triples stage in the same field and reads it against 3, not
            // against a double-progression window it does not run on.
            // `ProgramEngine.plan` clamps it for the styles that do.
            minimumReps: window.low,
            maximumReps: window.high,
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

    /// The slot's effective rep window. See `ProgramProgression.repWindow`.
    /// A slot with no loadable increment climbs past its window top, so its
    /// target is floored but never capped.
    var repWindow: (low: Int, high: Int, current: Int) {
        ProgramProgression.repWindow(
            minReps: minReps, maxReps: maxReps, currentReps: currentReps,
            capped: incrementLb > 0
        )
    }

    /// What this slot prescribes right now — the target clamped into its own
    /// window, so the card, the built session, and the advance all read the
    /// same number even when the stored endpoints are crossed.
    var prescribedReps: Int { repWindow.current }

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
