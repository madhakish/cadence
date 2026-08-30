import Foundation
import SwiftData
import CadenceCore

private func uniqueSessionModels<Model: PersistentModel>(_ models: [Model]) -> [Model] {
    var seen: Set<PersistentIdentifier> = []
    return models.filter { seen.insert($0.persistentModelID).inserted }
}

/// Per-set quality flags. One thumb-tap each in the logger.
enum SetFlag: String, Codable, CaseIterable {
    case clean
    case grindy
    case wobble
    case stoppedEarly = "stopped early"
    case rir1
    case rir2
    case rir3plus

    var isQuality: Bool { SetLifecycle.qualityValues.contains(rawValue) }
    var isRIR: Bool { SetLifecycle.rirValues.contains(rawValue) }

    var name: String {
        switch self {
        case .clean: return "Clean"
        case .grindy: return "Grindy"
        case .wobble: return "Wobble"
        case .stoppedEarly: return "Stopped early"
        case .rir1: return "1 left"
        case .rir2: return "2 left"
        case .rir3plus: return "3+ left"
        }
    }
}

@Model
final class WorkoutSession {
    var id: String = ""
    var date: Date
    var notes: String
    var isCompleted: Bool
    var completedAt: Date?
    var gymID: String?
    var gymName: String?
    var programID: String?
    var programName: String?
    var programCycleNumber: Int?
    var programWeek: Int?
    var programDayIndex: Int?
    var programPlanNames: [String]?
    @Relationship(deleteRule: .cascade, inverse: \SessionExercise.session)
    var exercises: [SessionExercise]
    @Relationship(deleteRule: .cascade, inverse: \WoodSplittingDetail.session)
    var woodSplittingDetail: WoodSplittingDetail?

    init(date: Date = .now, notes: String = "", gymID: String? = nil, gymName: String? = nil) {
        self.id = UUID().uuidString
        self.date = date
        self.notes = notes
        self.isCompleted = false
        self.completedAt = nil
        self.gymID = gymID
        self.gymName = gymName
        self.exercises = []
        self.woodSplittingDetail = nil
    }

    var orderedExercises: [SessionExercise] {
        uniqueSessionModels(exercises).sorted { $0.order < $1.order }
    }

    var effectiveCompletionDate: Date { completedAt ?? date }

    var includesRunning: Bool {
        exercises.contains { $0.exercise?.watchSite == .knee && !$0.workingSets.isEmpty }
    }

    var hasCompletedWork: Bool { exercises.contains { !$0.workingSets.isEmpty } }
}

@Model
final class SessionExercise {
    var order: Int
    var notes: String
    var barID: String?
    var barIDIsManual: Bool = false
    var exercise: Exercise?
    var session: WorkoutSession?
    @Relationship(deleteRule: .cascade, inverse: \SetEntry.sessionExercise)
    var sets: [SetEntry]
    var plannedWeightLb: Double?
    var targetWeightLb: Double?
    var plannedSets: Int?
    var plannedReps: Int?
    var plannedDurationSeconds: Int?
    var fallbackWeightLb: Double?
    var prescriptionStyleRaw: String = ""
    var phaseRaw: Int?
    var programRole: String?
    var programSlotID: String?

    init(order: Int, exercise: Exercise?, notes: String = "") {
        self.order = order
        self.exercise = exercise
        self.notes = notes
        self.sets = []
    }

    func stampBarID(for exercise: Exercise, bar: Bar) {
        barID = exercise.type == .barbell ? bar.id : nil
        barIDIsManual = false
    }

    var phase: CyclePhase? {
        get { phaseRaw.flatMap(CyclePhase.init(rawValue:)) }
        set { phaseRaw = newValue?.rawValue }
    }

    var truthfulPhaseLabel: String? {
        guard let phase else { return nil }
        guard !prescriptionStyleRaw.isEmpty else { return phase.label }
        let style = PrescriptionStyle(rawValue: prescriptionStyleRaw) ?? .automatic
        let role = LiftRole(rawValue: programRole ?? "") ?? .main
        return ProgramEngine.slotPhaseLabel(
            rotation: phase.rawValue,
            role: role,
            prescriptionStyle: style,
            movementGroup: exercise?.movementGroup,
            focus: .strength
        )
    }

    var orderedSets: [SetEntry] { uniqueSessionModels(sets).sorted { $0.order < $1.order } }
    var plannedWorkingSets: [SetEntry] { orderedSets.filter { !$0.isWarmup } }
    var workingSets: [SetEntry] { plannedWorkingSets.filter { $0.status == .completed } }

    var workingVolumeLb: Double {
        guard exercise?.type != .conditioning else { return 0 }
        return workingSets
            .filter { !(($0.distanceMiles ?? 0) > 0 || ($0.flights ?? 0) > 0 || ($0.durationSeconds ?? 0) > 0) }
            .compactMap(\.volumeLb).reduce(0, +)
    }

    var topSet: SetEntry? {
        workingSets.max { $0.weightLb < $1.weightLb }
    }
}

@Model
final class SetEntry {
    var order: Int
    var weightLb: Double
    var reps: Int
    var targetWeightLb: Double?
    var plannedWeightLb: Double?
    var plannedReps: Int?
    var plannedDurationSeconds: Int?
    var prescriptionBlockRaw: String = "work"
    var isWarmup: Bool
    var statusRaw: String = ""
    var isPerSide: Bool
    var enteredUnitRaw: String
    var flagsRaw: [String]
    var bodyFlagSiteRaw: String?
    var bodyFlagNote: String?
    var durationSeconds: Int?
    var distanceMiles: Double?
    var flights: Double?
    var inclinePercent: Double?
    var loadBasisRaw: String = ""
    var implementCount: Int = 0
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
        flights: Double? = nil,
        inclinePercent: Double? = nil,
        loadBasis: LoadBasis? = nil,
        implementCount: Int = 0,
        autoregReason: AutoregReason? = nil,
        targetWeightLb: Double? = nil,
        plannedWeightLb: Double? = nil,
        plannedReps: Int? = nil,
        plannedDurationSeconds: Int? = nil,
        prescriptionBlock: PrescriptionBlockKind = .work
    ) {
        self.order = order
        self.weightLb = weightLb
        self.reps = reps
        self.targetWeightLb = targetWeightLb
        self.plannedWeightLb = plannedWeightLb
        self.plannedReps = plannedReps
        self.plannedDurationSeconds = plannedDurationSeconds
        self.prescriptionBlockRaw = prescriptionBlock.rawValue
        self.isWarmup = isWarmup
        self.statusRaw = status.rawValue
        self.isPerSide = isPerSide
        self.enteredUnitRaw = enteredUnit.rawValue
        self.flagsRaw = flags.map(\.rawValue)
        self.bodyFlagSiteRaw = bodyFlagSite?.rawValue
        self.bodyFlagNote = bodyFlagNote
        self.durationSeconds = durationSeconds
        self.distanceMiles = distanceMiles
        self.flights = flights
        self.inclinePercent = inclinePercent
        self.loadBasisRaw = loadBasis?.rawValue ?? ""
        self.implementCount = implementCount
        self.autoregReasonRaw = autoregReason?.rawValue
    }

    var flags: [SetFlag] {
        get {
            SetLifecycle.normalizedFlags(
                quality: SetLifecycle.quality(in: flagsRaw),
                stoppedEarly: flagsRaw.contains(SetFlag.stoppedEarly.rawValue),
                rir: SetLifecycle.rir(in: flagsRaw)
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
        get { flags.first(where: \.isQuality) }
        set {
            flags = SetLifecycle.normalizedFlags(
                quality: (newValue?.isQuality ?? false) ? newValue?.rawValue : nil,
                stoppedEarly: flags.contains(.stoppedEarly),
                rir: rir?.rawValue
            ).compactMap(SetFlag.init(rawValue:))
        }
    }

    var rir: SetFlag? {
        get { flags.first(where: \.isRIR) }
        set {
            flags = SetLifecycle.normalizedFlags(
                quality: quality?.rawValue,
                stoppedEarly: flags.contains(.stoppedEarly),
                rir: (newValue?.isRIR ?? false) ? newValue?.rawValue : nil
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

    var prescriptionBlock: PrescriptionBlockKind {
        get { PrescriptionBlockKind(rawValue: prescriptionBlockRaw) ?? (isWarmup ? .warmup : .work) }
        set { prescriptionBlockRaw = newValue.rawValue }
    }

    var enteredUnit: WeightUnit {
        get { WeightUnit(rawValue: enteredUnitRaw) ?? .lb }
        set { enteredUnitRaw = newValue.rawValue }
    }

    var loadBasis: LoadBasis {
        get {
            LoadBasis(rawValue: loadBasisRaw)
                ?? sessionExercise?.exercise?.loadBasis
                ?? .externalTotal
        }
        set { loadBasisRaw = newValue.rawValue }
    }

    var resolvedImplementCount: Int {
        let linked = sessionExercise?.exercise?.resolvedImplementCount ?? 1
        return LoadSemantics.normalizedImplementCount(implementCount > 0 ? implementCount : linked, basis: loadBasis)
    }

    var volumeLb: Double? {
        LoadSemantics.volume(weightLb: weightLb, reps: reps, isPerSide: isPerSide,
                             basis: loadBasis, implementCount: resolvedImplementCount)
    }
}
