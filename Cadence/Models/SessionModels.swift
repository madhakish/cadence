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
    // Reps in reserve. Coarse on purpose — see SetLifecycle.rirValues. Stored
    // in the same `flagsRaw` list as quality, in its own exclusive group.
    case rir1
    case rir2
    case rir3plus

    var isQuality: Bool { SetLifecycle.qualityValues.contains(rawValue) }
    var isRIR: Bool { SetLifecycle.rirValues.contains(rawValue) }

    /// "1 rep left", not "rir1" — the raw value is a storage key, not copy.
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
    /// Literal default keeps V1→V2 lightweight. Existing sessions are assigned
    /// unique IDs by Seeder immediately after migration; new sessions set one
    /// in init. Import validation and the post-migration backfill enforce it.
    var id: String = ""
    var date: Date
    var notes: String
    var isCompleted: Bool
    /// Nil for open and historical pre-V4 sessions. New banks set the actual
    /// completion time so duration/density and recovery intervals stay honest.
    var completedAt: Date?
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
        self.id = UUID().uuidString
        self.date = date
        self.notes = notes
        self.isCompleted = false
        self.completedAt = nil
        self.gymID = gymID
        self.gymName = gymName
        self.exercises = []
    }

    var orderedExercises: [SessionExercise] {
        uniqueSessionModels(exercises).sorted { $0.order < $1.order }
    }

    /// When this session actually ended — the timestamp history, progression
    /// windows, and check-in attribution all sort and anchor by. Sessions
    /// banked before `completedAt` existed fall back to their start date.
    /// Mirrors web `completedAt || date`.
    var effectiveCompletionDate: Date { completedAt ?? date }

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
    /// The theoretical strategy target before the gym inventory resolves it.
    var targetWeightLb: Double?
    var plannedSets: Int?
    var plannedReps: Int?
    var plannedDurationSeconds: Int?
    /// Pre-computed one-tap fallback for the leading work block.
    var fallbackWeightLb: Double?
    var prescriptionStyleRaw: String = ""
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

    /// A phase label is truthful only for prescriptions that use Cadence's
    /// Volume/Load/Peak vocabulary. Sessions created before prescription style
    /// was captured retain their legacy label because there is no evidence to
    /// classify them more precisely.
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
    /// Only performed work belongs in history, PRs, volume, or progression.
    var workingSets: [SetEntry] { plannedWorkingSets.filter { $0.status == .completed } }

    var workingVolumeLb: Double {
        // A carried pack is not tonnage. Twenty pounds for three miles is not
        // twenty pounds of volume, and conditioning has never contributed to
        // this number — it only became reachable once loaded carries started
        // storing a weight instead of a forced zero. The library TYPE decides
        // first; the per-set DATA (distance, flights, duration) still excludes
        // a cardio set whose library entry is gone — restored history must
        // behave the same on both clients (mirrors web db.js workingVolume).
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
    /// Canonical pounds. Always. kg entry is converted at the keyboard.
    var weightLb: Double
    var reps: Int
    /// Strategy target → achievable planned load → final performed load.
    /// Historical V3 sets migrate with nil snapshots and retain their actual
    /// values; new sessions fill all three before training starts.
    var targetWeightLb: Double?
    var plannedWeightLb: Double?
    var plannedReps: Int?
    var plannedDurationSeconds: Int?
    var prescriptionBlockRaw: String = "work"
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
    /// Flights climbed, for conditioning a belt measures in floors rather than
    /// ground covered. Nil on every set written before V5 and on every movement
    /// that is not a climber; the pace is always re-derived from this and
    /// `durationSeconds`, never stored.
    var flights: Double?
    /// Conditioning treadmill/road grade, percent.
    var inclinePercent: Double?
    /// Snapshot of the load interpretation used when this set was created.
    /// Empty/zero are legacy records and fall back to the linked exercise.
    var loadBasisRaw: String = ""
    var implementCount: Int = 0
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

    /// Normalized on READ, so a store that somehow holds two qualities or two
    /// RIR values still presents one of each. Every group the app understands
    /// has to be listed here — anything omitted is silently dropped on every
    /// read, not just on export.
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
            // Carries the RIR through. Rebuilding from quality and stopped-early
            // alone would silently erase it every time the athlete regraded how
            // the bar moved.
            flags = SetLifecycle.normalizedFlags(
                quality: (newValue?.isQuality ?? false) ? newValue?.rawValue : nil,
                stoppedEarly: flags.contains(.stoppedEarly),
                rir: rir?.rawValue
            ).compactMap(SetFlag.init(rawValue:))
        }
    }

    /// Reps left in reserve. Its own exclusive group beside `quality`: quality
    /// says how the bar moved, this says how close to failure it was.
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
