import Foundation

/// Four-phase mesocycle state. In a cycle-based program, each main lift runs
/// its own track and progression keys off completed work rather than dates.
/// Week-bound programs are also valid; this phase type does not infer timing
/// semantics from a lift's prescription style. Phase 4 is a short recovery
/// bridge rather than another full authored rotation.
public enum CyclePhase: Int, Codable, CaseIterable, Sendable {
    case volume = 1 // 5×5 moderate
    case load = 2   // 5×3 heavier
    case peak = 3   // 3×3 top working weight
    case deload = 4 // recovery exposure: 2×3 ~75–85% of rotation-1 base

    public var name: String {
        switch self {
        case .volume: return "Volume"
        case .load: return "Load"
        case .peak: return "Peak"
        case .deload: return "Recovery"
        }
    }

    public var sets: Int {
        switch self {
        case .volume, .load: return 5
        case .peak: return 3
        case .deload: return 2
        }
    }

    public var reps: Int {
        switch self {
        case .volume: return 5
        case .load, .peak: return 3
        case .deload: return 3
        }
    }

    /// Multiplier on the cycle's week-1 (volume) weight.
    public var multiplier: Double {
        switch self {
        case .volume: return 1.0
        case .load: return 1.10
        case .peak: return 1.175
        case .deload: return 0.775
        }
    }

    public var next: CyclePhase {
        CyclePhase(rawValue: rawValue + 1) ?? .volume
    }

    /// "R2 Load 5×3"
    public var label: String { "R\(rawValue) \(name) \(sets)×\(reps)" }

    /// Backup phase labels are a wire-format snapshot, not live UI copy.
    /// Version-7 bundles encode only this label and import recovers the phase
    /// number from `R4`; preserving the old phase-4 string keeps every existing
    /// backup byte-stable without adding a schema field solely for wording.
    public var portableLabel: String {
        self == .deload ? "R4 Deload 3×5" : label
    }
}

/// Which rotation a charted session belongs to.
///
/// The rotation is a fact about the SESSION — the program stamps every
/// generated session with the rotation it was built for. Only some entries
/// repeat it: main and complementary slots carry a per-entry phase, accessory
/// slots never have, and entries logged before per-entry phase capture do not
/// either. Reading the entry alone therefore reported real program work as
/// "Untracked", and the same session that History's Rotations tab counted
/// under "Cycle 2 · R3" vanished into the untracked series on Charts.
///
/// The entry still wins where it exists: a slot re-logged into a later session
/// keeps the rotation it was actually performed in. The session tag is the
/// fallback, and only a session with no program tag at all is untracked.
///
/// Mirrored 1:1 in web/app/js/core.js `chartRotationLabel`.
public enum ChartRotation {
    /// The series key for a session that belongs to no program rotation.
    public static let untrackedLabel = "Untracked"

    public static func label(entryPhase: Int?, sessionRotation: Int?) -> String {
        guard let rotation = entryPhase ?? sessionRotation,
              let phase = CyclePhase(rawValue: rotation) else { return untrackedLabel }
        return "R\(phase.rawValue) \(phase.name)"
    }
}

/// Linear vs mesocycle progression.
public enum TrackMode: String, Codable, Sendable {
    case cycle
    case linear
}

/// Set/rep strategy for a program slot. `automatic` keeps setup simple while
/// still respecting the program focus, lift role, and Olympic lift technique
/// needs. Coaches can override an individual slot when the default is not the
/// right training stimulus.
public enum PrescriptionStyle: String, Codable, CaseIterable, Sendable {
    case automatic
    case wave
    case offsetWave
    case secondary
    case hypertrophy
    case technique
    case doubleProgression
    case linearFives
    case texasVolume
    case texasLight
    case texasIntensity
    case fiveThreeOne
    case maxEffort
    case dynamicEffort

    public var name: String {
        switch self {
        case .automatic: return "Automatic"
        case .wave: return "Strength wave"
        case .offsetWave: return "Strength wave — offsets"
        case .secondary: return "Secondary volume"
        case .hypertrophy: return "Hypertrophy"
        case .technique: return "Technique"
        case .doubleProgression: return "Double progression"
        case .linearFives: return "Linear progression"
        case .texasVolume: return "Texas — volume day"
        case .texasLight: return "Texas — light day"
        case .texasIntensity: return "Texas — intensity day"
        case .fiveThreeOne: return "5/3/1 wave"
        case .maxEffort: return "Max effort"
        case .dynamicEffort: return "Dynamic effort"
        }
    }

    /// Styles whose base advances after every banked exposure of the slot
    /// (session-to-session or week-to-week linear progression) instead of
    /// being graded once per mesocycle at the Peak.
    public var advancesPerExposure: Bool {
        switch self {
        case .doubleProgression, .linearFives, .texasVolume, .texasLight, .texasIntensity, .maxEffort:
            return true
        default:
            return false
        }
    }

    /// Styles that build their own session shape (sets-across, ramps, singles,
    /// speed sets). The generic phase primer and peak-single add-ons never
    /// apply to them.
    public var buildsOwnSessionShape: Bool {
        advancesPerExposure || self == .fiveThreeOne || self == .dynamicEffort
    }

    /// Whether the Volume / Load / Peak / Recovery vocabulary actually
    /// describes what this style prescribes.
    ///
    /// The rotation counter advances for every slot — the program is one
    /// calendar — but the *names* on it are a claim about the prescription, and
    /// for most styles that claim is false. `linearFives`, max effort and the
    /// Texas days move per exposure and never grade at a peak;
    /// `doubleProgression` is a
    /// rep window at a held load; `fiveThreeOne` and `dynamicEffort` grade at
    /// the cycle boundary but with shapes of their own
    /// (5+/3+/1+/recovery is not "Volume/Load/Peak"). Rendering a phase name
    /// against any of them asserts something about the engine that is not true.
    ///
    /// This is deliberately derived from `buildsOwnSessionShape` rather than
    /// listed again: those are exactly the styles whose plan comes out of their
    /// own branch instead of the shared phase-shaped table, so one predicate
    /// cannot drift from the other.
    public var usesCyclePhases: Bool { !buildsOwnSessionShape }

    /// Badge-length name for a slot — what the slot actually does, short enough
    /// to sit beside the lift name. `name` is the picker's full label.
    ///
    /// `automatic` never reaches a badge: resolve it with `resolvedStyle`
    /// first, which is what `ProgramEngine.slotBadge` does.
    public var shortName: String {
        switch self {
        case .automatic: return "Automatic"
        case .wave: return "Wave"
        case .offsetWave: return "Wave — offsets"
        case .secondary: return "Secondary volume"
        case .hypertrophy: return "Hypertrophy"
        case .technique: return "Technique"
        case .doubleProgression: return "Double progression"
        case .linearFives: return "Linear"
        case .texasVolume: return "Texas volume"
        case .texasLight: return "Texas light"
        case .texasIntensity: return "Texas intensity"
        case .fiveThreeOne: return "5/3/1"
        case .maxEffort: return "Max effort"
        case .dynamicEffort: return "Speed work"
        }
    }

    /// Starting base weight as a fraction of a known estimated 1RM, used when
    /// a program is created from recorded history. 0 = keep the template's
    /// hand-set base. Values follow each methodology's published guidance:
    /// novice work starts with runway below a ~5RM, Texas days derive from the
    /// intensity 5RM (≈0.86 × 1RM), a 5/3/1 training max is 90% of 1RM, a max-
    /// effort target starts at 90%, and speed work sits at ~50%.
    public var defaultStartFraction: Double {
        switch self {
        case .linearFives: return 0.74
        case .texasVolume: return 0.77
        case .texasLight: return 0.62
        case .texasIntensity: return 0.86
        case .fiveThreeOne: return 0.90
        case .maxEffort: return 0.90
        case .dynamicEffort: return 0.50
        default: return 0
        }
    }

    /// Conservative history-derived starting point used only when building a
    /// new program. Explicit methodology ratios above still win; the classic
    /// Cadence styles get enough runway that a new template can reuse a known
    /// e1RM without starting near the lifter's limit.
    public var templateStartFraction: Double {
        if defaultStartFraction > 0 { return defaultStartFraction }
        switch self {
        case .automatic, .wave, .offsetWave: return 0.65
        case .secondary: return 0.55
        case .hypertrophy, .doubleProgression: return 0.50
        // Classic lifts need enough load to expose real timing and position
        // without turning a technique block into daily maxing. New Olympic
        // templates start at ~70%, then the technique prescription builds to
        // ~75/80% before an easy bridge.
        case .technique: return 0.70
        default: return 0
        }
    }

    /// Styles no longer offered when configuring a slot.
    ///
    /// `offsetWave` adds fixed pound offsets on the load and peak rotations
    /// instead of the wave's multipliers. No shipped template uses it, and its
    /// two defaults are calibrated to bases 61 lb apart — +25 implies a 250 lb
    /// lift (25/0.10) while +33 implies a 189 lb one (33/0.175) — so the
    /// intra-cycle range it produces depends on how heavy you are in a way
    /// nobody chose.
    ///
    /// Retired rather than deleted. The raw value is persisted in programs, in
    /// backups, and in program files, so removing the case would reject data
    /// that restores today — a breaking change for a style a lifter may be
    /// mid-cycle on. A slot already using it keeps working and keeps its
    /// offsets; it just cannot be newly selected.
    public static let retiredForNewSlots: Set<PrescriptionStyle> = [.offsetWave]

    /// The styles a picker should offer, keeping whatever the slot already has
    /// so a retired choice never silently rewrites itself to something else.
    public static func selectable(current: PrescriptionStyle) -> [PrescriptionStyle] {
        allCases.filter { !retiredForNewSlots.contains($0) || $0 == current }
    }
}

public enum PrescriptionBlockKind: String, Codable, CaseIterable, Sendable {
    case warmup
    case primer
    case topSingle
    /// Prescribed sub-maximal sets BEFORE the day's top work (the 5/3/1
    /// 65/75% sets). Real work, but not the set that gates progression.
    case ramp
    case work
    /// A prescribed set taken past its rep target — 5/3/1's "+" set, and the
    /// opt-in final set of the wave's load rotation. Capped, not to failure:
    /// the athlete stops at the rep ceiling or the first grindy/wobble rep.
    ///
    /// It grades like any other working set, and it is the set the cycle's
    /// strength sample usually comes from, because `strengthSampleIndex` ranks
    /// by Epley rather than by weight.
    case amrap
    case backoff
    case conditioning

    /// Whether a set of this kind counts as the slot's prescribed work — the
    /// sets that are graded and that supply the cycle's strength sample.
    ///
    /// `amrap` has to be in here. Grading filtered on `work` alone, so an AMRAP
    /// set would have been invisible: not counted toward completion, not
    /// eligible as the top set, and therefore unable to reach the e1RM sample
    /// at all. The whole point of the block is that its earned reps are read.
    ///
    /// Warm-ups, primers, ramps, top singles and back-offs stay out. They are
    /// real work but they are not the prescription being graded.
    public var countsAsPrescribedWork: Bool { self == .work || self == .amrap }

    /// Whether a set of this kind is an instruction the program gave the
    /// athlete — the question "did they do what was asked", which is what
    /// gates advancing the schedule.
    ///
    /// Wider than `countsAsPrescribedWork` by exactly one kind: conditioning is
    /// prescribed work the athlete owes, but it is graded in its own minutes
    /// ledger rather than against a load, so it never joins the lifting counts.
    public var countsAsProgramInstruction: Bool {
        countsAsPrescribedWork || self == .conditioning
    }
}

/// Persistable knobs for a lift slot. Defaults preserve the shipped multiplier
/// wave; an offset wave and double progression are explicit opt-ins.
public struct LiftPrescriptionConfiguration: Codable, Hashable, Sendable {
    public var loadOffsetLb: Double
    public var peakOffsetLb: Double
    public var deloadMultiplier: Double
    public var workingSets: Int
    public var minimumReps: Int
    public var maximumReps: Int
    public var currentReps: Int
    public var peakSingleEnabled: Bool
    public var lastPeakSingleLb: Double
    public var peakSingleIncrementLb: Double
    public var phasePrimerEnabled: Bool

    public init(
        loadOffsetLb: Double = 10,
        peakOffsetLb: Double = 15,
        deloadMultiplier: Double = 0.775,
        workingSets: Int = 3,
        minimumReps: Int = 5,
        maximumReps: Int = 8,
        currentReps: Int = 5,
        peakSingleEnabled: Bool = false,
        lastPeakSingleLb: Double = 0,
        peakSingleIncrementLb: Double = 5,
        phasePrimerEnabled: Bool = true
    ) {
        self.loadOffsetLb = loadOffsetLb
        self.peakOffsetLb = peakOffsetLb
        self.deloadMultiplier = deloadMultiplier
        self.workingSets = workingSets
        self.minimumReps = minimumReps
        self.maximumReps = maximumReps
        self.currentReps = currentReps
        self.peakSingleEnabled = peakSingleEnabled
        self.lastPeakSingleLb = lastPeakSingleLb
        self.peakSingleIncrementLb = peakSingleIncrementLb
        self.phasePrimerEnabled = phasePrimerEnabled
    }
}

public struct PrescriptionBlock: Hashable, Sendable {
    public let kind: PrescriptionBlockKind
    public let weightLb: Double
    public let sets: Int
    public let reps: Int

    public init(kind: PrescriptionBlockKind, weightLb: Double, sets: Int, reps: Int) {
        self.kind = kind
        self.weightLb = weightLb
        self.sets = sets
        self.reps = reps
    }
}

public struct SessionPrescription: Hashable, Sendable {
    public let mainWork: SessionPlan
    public let blocks: [PrescriptionBlock]

    public init(mainWork: SessionPlan, blocks: [PrescriptionBlock]) {
        self.mainWork = mainWork
        self.blocks = blocks
    }
}

/// Per-lift progression state. Serializable; the app wraps this in SwiftData.
public struct CycleState: Codable, Hashable, Sendable {
    public var cycleNumber: Int
    /// Week-1 (volume) working weight for the current cycle, lb.
    public var baseWeightLb: Double
    public var nextPhase: CyclePhase
    /// Per-cycle bump: +10 lb lower body, +5 lb upper body.
    public var incrementLb: Double

    public init(cycleNumber: Int = 1, baseWeightLb: Double, nextPhase: CyclePhase = .volume, incrementLb: Double = 10) {
        self.cycleNumber = cycleNumber
        self.baseWeightLb = baseWeightLb
        self.nextPhase = nextPhase
        self.incrementLb = incrementLb
    }
}

/// What the app suggests for the next session of a lift. Always editable.
public struct SessionPlan: Hashable, Sendable {
    public let weightLb: Double
    public let sets: Int
    public let reps: Int
    public let phase: CyclePhase?
    public let cycleNumber: Int?

    public init(weightLb: Double, sets: Int, reps: Int, phase: CyclePhase? = nil, cycleNumber: Int? = nil) {
        self.weightLb = weightLb
        self.sets = sets
        self.reps = reps
        self.phase = phase
        self.cycleNumber = cycleNumber
    }

    /// "245 × 3×3 — R3 Peak"
    public var label: String {
        let base = "\(Weight.trim(weightLb)) × \(sets)×\(reps)"
        if let phase { return "\(base) — R\(phase.rawValue) \(phase.name)" }
        return base
    }
}

public enum ProgramEngine {
    /// Default rounding for barbell suggestions.
    public static let defaultRoundingLb = 5.0

    /// Dumbbells are recorded per hand. A program-level 10 lb rounding step
    /// would therefore turn into a 20 lb total jump, which is too coarse for
    /// upper-body work. Keep per-hand prescriptions and adaptive progression
    /// to at most 5 lb while leaving the program's chosen granularity intact
    /// for barbells and machines.
    public static func loadStep(programRoundingLb: Double, exerciseType: String?) -> Double {
        exerciseType == "dumbbell" ? Swift.min(programRoundingLb, 5) : programRoundingLb
    }

    /// Program-specific wave plan. Dumbbells are logged per hand, so the
    /// standard Peak multiplier can otherwise turn a 55 lb volume base into a
    /// 65 lb prescription. Keep every above-base DB rotation within one 5 lb
    /// rack jump; barbell/machine waves retain their normal percentages.
    public static func programPlan(
        for state: CycleState,
        programRoundingLb: Double,
        exerciseType: String?,
        movementGroup: String? = nil,
        role: LiftRole = .main,
        focus: TrainingFocus = .strength,
        prescriptionStyle: PrescriptionStyle = .automatic,
        configuration: LiftPrescriptionConfiguration = .init(),
        addedVolumeSets: Int = 0
    ) -> SessionPlan {
        let step = loadStep(programRoundingLb: programRoundingLb, exerciseType: exerciseType)
        let style = resolvedStyle(prescriptionStyle, movementGroup: movementGroup, role: role, focus: focus)
        let raw = plan(for: state, roundingLb: step, style: style, configuration: configuration,
                       movementGroup: movementGroup, addedVolumeSets: addedVolumeSets)
        guard exerciseType == "dumbbell", raw.weightLb > state.baseWeightLb else { return raw }
        return SessionPlan(
            weightLb: Swift.min(raw.weightLb, state.baseWeightLb + 5),
            sets: raw.sets,
            reps: raw.reps,
            phase: raw.phase,
            cycleNumber: raw.cycleNumber
        )
    }

    /// The order a day's slots were AUTHORED in, recovered from an imported
    /// payload. Distinct orders are the author's numbers and pass through
    /// verbatim. When every order in the list ties — a hand-written program
    /// file whose slots all say `order: 0`, or a backup written before slots
    /// carried orders — the tie holds no information, and the array position
    /// the author physically wrote the slots in IS their order. Without this,
    /// a tie falls through to the alphabetical display fallback and the
    /// alphabet quietly does the lifter's programming: pull-ups after biceps
    /// curls because P > D.
    ///
    /// Mirrored 1:1 in web/app/js/core.js `authoredSlotOrders`.
    public static func authoredSlotOrders(_ orders: [Int]) -> [Int] {
        guard orders.count > 1, Set(orders).count == 1 else { return orders }
        return Array(0..<orders.count)
    }

    /// Main work always precedes complementary work; the athlete's authored
    /// order is preserved inside each role. Mirrors web `orderedProgramSlots`.
    public static func programSlotPrecedes(
        lhsRole: String, lhsOrder: Int, lhsName: String,
        rhsRole: String, rhsOrder: Int, rhsName: String
    ) -> Bool {
        let lhs = (lhsRole == LiftRole.main.rawValue ? 0 : 1, lhsOrder, lhsName)
        let rhs = (rhsRole == LiftRole.main.rawValue ? 0 : 1, rhsOrder, rhsName)
        return lhs < rhs
    }

    /// Movement-aware offset defaults for `offsetWave`. A stored zero means
    /// "use the default"; an explicit value stays user-owned.
    ///
    /// These are absolute pounds ON PURPOSE — that is the whole reason
    /// `offsetWave` exists next to the multiplicative `wave`. A lifter who
    /// wants "always +25 on load week" gets exactly that, and the step does not
    /// grow with the bar. They are deliberately NOT proportional, so they do
    /// not track the wave's 1.10/1.175 shape at any particular base; that is
    /// the trade the style is for, not a defect to normalise away.
    ///
    /// Lives here rather than in the app layer so both clients resolve them
    /// identically. The JS mirror previously applied the movement-aware upgrade
    /// in `sessionPrescription` but not in `planForStyle`, so a squat reaching
    /// the latter silently got the upper-body 10/15 — the values below are
    /// unchanged, and only the divergence is fixed.
    /// Mirrored 1:1 in web/app/js/core.js `resolvedOffsets`.
    public static func resolvedOffsets(
        loadOffsetLb: Double, peakOffsetLb: Double, movementGroup: String?
    ) -> (load: Double, peak: Double) {
        let lower = movementGroup == "squat" || movementGroup == "hinge"
        return (
            loadOffsetLb > 0 ? loadOffsetLb : (lower ? 25 : 10),
            peakOffsetLb > 0 ? peakOffsetLb : (lower ? 33 : 15)
        )
    }

    /// Resolves the low-friction automatic choice. Olympic lifts prioritize
    /// crisp practice; hypertrophy programs use a rep-range wave; secondary
    /// lifts carry less fatigue than main lifts.
    public static func resolvedStyle(
        _ requested: PrescriptionStyle,
        movementGroup: String?,
        role: LiftRole,
        focus: TrainingFocus
    ) -> PrescriptionStyle {
        guard requested == .automatic else { return requested }
        if movementGroup == "olympic" { return .technique }
        if focus == .hypertrophy { return .hypertrophy }
        if role == .complementary || focus == .maintain { return .secondary }
        return .wave
    }

    /// Where the program is in its rotation, said without claiming the
    /// rotation is a weight wave. The program-level indicator is shared by
    /// slots that have nothing to do with each other's prescriptions, so it can
    /// only honestly report position.
    ///
    /// Mirrored 1:1 in web/app/js/core.js `rotationLabel`.
    public static func rotationLabel(rotation: Int) -> String {
        let clamped = Swift.min(Swift.max(rotation, 1), ProgramProgression.deloadWeek)
        return "Rotation \(clamped) of \(ProgramProgression.deloadWeek)"
    }

    /// Relative position used by the exercise-detail four-rotation preview.
    /// Recovery is called out separately so R3 can name both the recovery
    /// bridge and the first work rotation of the next cycle honestly.
    /// Mirrors web `rotationContextLabel`.
    public static func rotationContextLabel(rotation: Int, currentRotation: Int) -> String {
        let current = Swift.min(Swift.max(currentRotation, 1), ProgramProgression.deloadWeek)
        if rotation == current {
            return rotation == ProgramProgression.deloadWeek ? "Current recovery" : "Current"
        }
        if rotation == ProgramProgression.deloadWeek { return "Recovery" }
        // deloadWeek - 1 is the last work rotation; the cycle length has
        // exactly one owner, so no literal wrap point here.
        let lastWork = ProgramProgression.deloadWeek - 1
        let previous = current == 1 || current == ProgramProgression.deloadWeek ? lastWork : current - 1
        if rotation == previous { return "Previous" }
        let next = current >= lastWork ? 1 : current + 1
        if rotation == next { return current >= lastWork ? "Next cycle" : "Next" }
        return "Later"
    }

    /// What a slot does, for the badge beside its name: `Main · 5/3/1`,
    /// `Complementary · Secondary volume`, `Main · Linear`.
    ///
    /// Resolves `automatic` first, so the badge names the style the engine will
    /// actually run rather than the placeholder the lifter left in the picker.
    ///
    /// Mirrored 1:1 in web/app/js/core.js `slotBadge`.
    public static func slotBadge(
        role: LiftRole,
        prescriptionStyle: PrescriptionStyle,
        movementGroup: String? = nil,
        focus: TrainingFocus = .strength
    ) -> String {
        let style = resolvedStyle(prescriptionStyle, movementGroup: movementGroup, role: role, focus: focus)
        let roleLabel = role == .main ? "Main" : "Complementary"
        return "\(roleLabel) · \(style.shortName)"
    }

    /// The phase name for a slot, or `nil` where the phase vocabulary does not
    /// describe what the slot prescribes.
    ///
    /// This is the whole of the fix: the phase label is a per-slot fact, not a
    /// program-wide one, and a program mixing a wave main lift with a novice
    /// linear complementary lift has to be able to say so on one screen.
    ///
    /// Mirrored 1:1 in web/app/js/core.js `slotPhaseLabel`.
    public static func slotPhaseLabel(
        rotation: Int,
        role: LiftRole = .main,
        prescriptionStyle: PrescriptionStyle,
        movementGroup: String? = nil,
        focus: TrainingFocus = .strength
    ) -> String? {
        let style = resolvedStyle(prescriptionStyle, movementGroup: movementGroup, role: role, focus: focus)
        guard style.usesCyclePhases, let phase = CyclePhase(rawValue: rotation) else { return nil }
        return "R\(phase.rawValue) \(phase.name)"
    }

    /// Phase-shaped plan for a specific training stimulus. The phase still
    /// advances with the unified four-rotation program, but every slot no
    /// longer has to inherit the main-lift 5×5 → 5×3 prescription.
    public static func plan(
        for state: CycleState,
        roundingLb: Double = defaultRoundingLb,
        style: PrescriptionStyle,
        configuration: LiftPrescriptionConfiguration = .init(),
        movementGroup: String? = nil,
        addedVolumeSets: Int = 0
    ) -> SessionPlan {
        let phase = state.nextPhase
        // A held cycle's volume fallback: extra sets land on the VOLUME
        // rotation of the wave-family styles only — load and peak keep their
        // shapes, and complementary styles govern their own volume.
        let extraSets = phase == .volume ? Swift.max(0, addedVolumeSets) : 0
        let prescription: (sets: Int, reps: Int, multiplier: Double)
        switch style {
        case .automatic, .wave:
            // Recovery intensity is the slot's own knob (default 0.775,
            // the historical constant). The literature's asymmetry motivates
            // making this the adjustable side: volume stays cut either way,
            // and a lifter who finds 77.5% unproductively light raises the
            // intensity rather than adding sets back.
            // Zero is "unset", never "lift nothing" — mirror core.js's guard
            // inside the shared engine, not only in the app-layer builder, so
            // both cores agree for every caller.
            prescription = (phase.sets + extraSets, phase.reps,
                            phase == .deload
                                ? (configuration.deloadMultiplier > 0 ? configuration.deloadMultiplier : phase.multiplier)
                                : phase.multiplier)
        case .linearFives:
            // Sets-across at the slot's own base; the base moves per exposure
            // (advanceLinearLift). Recovery is the only phase that overrides
            // that contract. `currentReps` is deliberately a two-stage switch:
            // five is the ordinary linear prescription, while three supports
            // the explicit 3x5 -> 5x3 coaching transition without inventing a
            // second persisted strategy or a per-slot phase pointer.
            prescription = phase == .deload
                ? (2, 3, 0.80)
                : (max(1, configuration.workingSets), configuration.currentReps <= 3 ? 3 : 5, 1.0)
        case .texasVolume, .texasLight, .texasIntensity:
            // Texas day roles stay sets of five. They share the storage knobs
            // with linear progression, but not its adaptive triples stage.
            prescription = phase == .deload
                ? (2, 3, 0.80)
                : (max(1, configuration.workingSets), 5, 1.0)
        case .fiveThreeOne:
            // baseWeightLb is the TRAINING MAX. The plan is the graded top set
            // ("+" set); the two ramp sets are emitted by sessionPrescription.
            let top: (pct: Double, reps: Int)
            switch phase {
            case .volume: top = (0.85, 5)
            case .load: top = (0.90, 3)
            case .peak: top = (0.95, 1)
            case .deload: top = (0.60, 5)
            }
            return SessionPlan(
                weightLb: Weight.round(state.baseWeightLb * top.pct, to: roundingLb),
                sets: 1, reps: top.reps, phase: phase, cycleNumber: state.cycleNumber
            )
        case .maxEffort:
            // Work up to a top single at the slot's current target; recovery
            // trades the single for two moderate triples.
            if phase == .deload {
                return SessionPlan(
                    weightLb: Weight.round(state.baseWeightLb * 0.70, to: roundingLb),
                    sets: 2, reps: 3, phase: phase, cycleNumber: state.cycleNumber
                )
            }
            return SessionPlan(
                weightLb: Weight.round(state.baseWeightLb, to: roundingLb),
                sets: 1, reps: 1, phase: phase, cycleNumber: state.cycleNumber
            )
        case .dynamicEffort:
            // Three-week pendulum wave. Straight-bar squat and pull work runs
            // 50→55→60%; speed bench runs 40→45→50%. The slot base is the
            // first percentage, so press multipliers are slightly wider.
            let scheme: (sets: Int, reps: Int)
            if movementGroup == "squat" {
                scheme = (phase == .peak ? 10 : 12, 2)
            } else if movementGroup == "hinge" {
                scheme = (6, 1)
            } else {
                scheme = (9, 3)
            }
            let multiplier: Double
            switch phase {
            case .volume, .deload: multiplier = 1.0
            case .load: multiplier = movementGroup == "press" ? 1.125 : 1.10
            case .peak: multiplier = movementGroup == "press" ? 1.25 : 1.20
            }
            return SessionPlan(
                weightLb: Weight.round(state.baseWeightLb * multiplier, to: roundingLb),
                sets: phase == .deload ? Swift.max(2, (scheme.sets + 1) / 2) : scheme.sets,
                reps: scheme.reps, phase: phase, cycleNumber: state.cycleNumber
            )
        case .offsetWave:
            let weight: Double
            switch phase {
            case .volume: weight = state.baseWeightLb
            case .load: weight = state.baseWeightLb + configuration.loadOffsetLb
            case .peak: weight = state.baseWeightLb + configuration.peakOffsetLb
            case .deload:
                // Same zero-is-unset rescue as the wave branch above.
                weight = state.baseWeightLb
                    * (configuration.deloadMultiplier > 0 ? configuration.deloadMultiplier : phase.multiplier)
            }
            return SessionPlan(
                weightLb: Weight.round(weight, to: roundingLb),
                sets: phase.sets + extraSets, reps: phase.reps, phase: phase, cycleNumber: state.cycleNumber
            )
        case .secondary:
            // Complementary work is volume after the day's heavy main — never
            // a second miniature of the main wave. Sets stay at 5+ reps and at
            // or below the slot's base so the heavy stimulus stays with the
            // main lift (the base is a 5-rep-calibrated weight; 8s sit ~90%).
            switch phase {
            case .volume: prescription = (3, 8, 0.90)
            case .load: prescription = (3, 8, 0.95)
            case .peak: prescription = (3, 6, 1.0)
            case .deload: prescription = (1, 5, 0.75)
            }
        case .hypertrophy:
            switch phase {
            case .volume: prescription = (4, 10, 1.0)
            case .load: prescription = (4, 8, 1.025)
            case .peak: prescription = (3, 8, 1.05)
            case .deload: prescription = (1, 5, 0.80)
            }
        case .technique:
            // A conservative classic-lift build: triples, then doubles, then
            // crisp singles. Five sets keeps practice volume stable while the
            // reps fall; each step adds 7.5% of the opening load (~70/75/80%
            // when a new template is seeded from history). Recovery repeats
            // easy doubles instead of dropping to the old ~48% of e1RM.
            switch phase {
            case .volume: prescription = (5, 3, 1.0)
            case .load: prescription = (5, 2, 1.075)
            case .peak: prescription = (5, 1, 1.15)
            case .deload: prescription = (3, 2, 0.90)
            }
        case .doubleProgression:
            if phase == .deload {
                return SessionPlan(
                    weightLb: Weight.round(state.baseWeightLb * 0.80, to: roundingLb),
                    sets: 1,
                    reps: Swift.min(5, ProgramProgression.repWindow(
                        minReps: configuration.minimumReps,
                        maxReps: configuration.maximumReps,
                        currentReps: configuration.minimumReps
                    ).low),
                    phase: phase,
                    cycleNumber: state.cycleNumber
                )
            }
            return SessionPlan(
                weightLb: Weight.round(state.baseWeightLb, to: roundingLb),
                sets: max(1, configuration.workingSets),
                // One owner for the window, shared with the advance, so the
                // prescription and the grade can never disagree about it.
                reps: ProgramProgression.repWindow(
                    minReps: configuration.minimumReps,
                    maxReps: configuration.maximumReps,
                    currentReps: configuration.currentReps
                ).current,
                phase: phase,
                cycleNumber: state.cycleNumber
            )
        }
        return SessionPlan(
            weightLb: Weight.round(state.baseWeightLb * prescription.multiplier, to: roundingLb),
            sets: prescription.sets,
            reps: prescription.reps,
            phase: phase,
            cycleNumber: state.cycleNumber
        )
    }

    /// Full session prescription for slots that need more than one uniform
    /// work block. Top singles are controlled, optional peak work; primers are
    /// warm-up observations and never count toward the main work grade.
    public static func sessionPrescription(
        for state: CycleState,
        programRoundingLb: Double,
        exerciseType: String?,
        movementGroup: String? = nil,
        role: LiftRole = .main,
        focus: TrainingFocus = .strength,
        prescriptionStyle: PrescriptionStyle = .automatic,
        configuration: LiftPrescriptionConfiguration = .init(),
        estimatedMaxLb: Double = 0,
        addedVolumeSets: Int = 0
    ) -> SessionPrescription {
        let step = loadStep(programRoundingLb: programRoundingLb, exerciseType: exerciseType)
        let style = resolvedStyle(prescriptionStyle, movementGroup: movementGroup, role: role, focus: focus)
        let work = programPlan(
            for: state, programRoundingLb: programRoundingLb, exerciseType: exerciseType,
            movementGroup: movementGroup, role: role, focus: focus,
            prescriptionStyle: style, configuration: configuration,
            addedVolumeSets: addedVolumeSets
        )
        var blocks: [PrescriptionBlock] = []
        if configuration.phasePrimerEnabled, !style.buildsOwnSessionShape,
           let primer = primerWeight(
            baseWeightLb: state.baseWeightLb, phase: state.nextPhase, style: style,
            roundingLb: step, configuration: configuration
           ), primer > 0, primer < work.weightLb {
            blocks.append(PrescriptionBlock(kind: .primer, weightLb: primer, sets: 1, reps: 1))
        }
        if configuration.peakSingleEnabled, state.nextPhase == .peak,
           style != .technique, !style.buildsOwnSessionShape {
            // The seed is a training max, so it follows the program's focus
            // rather than a hardcoded 0.90 — a hypertrophy program's ceiling is
            // 0.78, and opening its first peak single at 90% ignored that.
            let seed = configuration.lastPeakSingleLb > 0
                ? configuration.lastPeakSingleLb + configuration.peakSingleIncrementLb
                : estimatedMaxLb * (focus.tmFraction > 0 ? focus.tmFraction : 0.90)
            let target = Weight.round(seed, to: step)
            if target > work.weightLb {
                blocks.append(PrescriptionBlock(kind: .topSingle, weightLb: target, sets: 1, reps: 1))
            }
        }
        if style == .fiveThreeOne {
            // The two ramp sets below the "+" set. They are real prescribed
            // work but only the top set gates progression, so they carry the
            // non-graded ramp kind; block order puts them before the top set.
            let ramp: [(pct: Double, reps: Int)]
            switch state.nextPhase {
            case .volume: ramp = [(0.65, 5), (0.75, 5)]
            case .load: ramp = [(0.70, 3), (0.80, 3)]
            case .peak: ramp = [(0.75, 5), (0.85, 3)]
            case .deload: ramp = [(0.50, 5)]
            }
            for step531 in ramp {
                blocks.append(PrescriptionBlock(
                    kind: .ramp,
                    weightLb: Weight.round(state.baseWeightLb * step531.pct, to: step),
                    sets: 1, reps: step531.reps
                ))
            }
        }
        if style == .maxEffort, state.nextPhase != .deload {
            // After ordinary warm-ups, prescribe no more than three singles at
            // 90% and above: an opener, a near-max single, then the day's
            // target. Distinct guards keep light targets from duplicating a
            // rounded weight. These are ramps; only the final single gates the
            // next target.
            var last = -Double.infinity
            for pct in [0.90, 0.975] {
                let target = Weight.round(state.baseWeightLb * pct, to: step)
                if target > last, target < work.weightLb {
                    blocks.append(PrescriptionBlock(kind: .ramp, weightLb: target, sets: 1, reps: 1))
                    last = target
                }
            }
        }
        // 5/3/1's top set is the "+" set — the AMRAP is the progression engine,
        // not a garnish, and shipping the percentages without it was the
        // template's one material infidelity to the published method. Wendler's
        // recovery has no "+" set, so it stays ordinary work.
        let isFiveThreeOnePlusSet = style == .fiveThreeOne && state.nextPhase != .deload
        blocks.append(PrescriptionBlock(
            kind: isFiveThreeOnePlusSet ? .amrap : .work,
            weightLb: work.weightLb, sets: work.sets, reps: work.reps
        ))
        return SessionPrescription(mainWork: work, blocks: blocks)
    }

    /// The authored schedule surrounding a slot preview. The current pointer is
    /// required because a slot already banked in this rotation belongs to the
    /// NEXT rotation, while a synchronized twin before it may move the shared
    /// base before the slot appears. Recovery orders are separate because the
    /// shortened bridge deliberately omits authored days.
    public struct ExposurePreviewSchedule: Hashable, Sendable {
        public let targetDayOrder: Int
        public let nextDayOrder: Int
        public let allDayOrders: [Int]
        public let recoveryDayOrders: [Int]
        public let synchronizedDayOrders: [Int]

        public init(targetDayOrder: Int, nextDayOrder: Int, allDayOrders: [Int],
                    recoveryDayOrders: [Int], synchronizedDayOrders: [Int]) {
            self.targetDayOrder = targetDayOrder
            self.nextDayOrder = nextDayOrder
            self.allDayOrders = allDayOrders
            self.recoveryDayOrders = recoveryDayOrders
            self.synchronizedDayOrders = synchronizedDayOrders
        }
    }

    /// One exposure in a slot's forward preview — what the engine will
    /// prescribe, and what the numbers derive from.
    public struct ExposurePreviewEntry: Hashable, Sendable {
        /// 1 = the next exposure of this slot.
        public let exposureNumber: Int
        public let cycleNumber: Int
        /// Position in the program's rotation, 1…4. Always real: the rotation
        /// counter advances for every slot, including the ones whose
        /// prescription ignores its names.
        public let rotation: Int
        /// "R3 Peak", or nil where the phase vocabulary does not describe this
        /// slot. Same predicate the badges use, so a preview can never label a
        /// per-exposure slot with a wave phase.
        public let phaseName: String?
        public let isRecovery: Bool
        /// The base — or, for `fiveThreeOne`, the TRAINING MAX — these numbers
        /// are computed from.
        public let baseWeightLb: Double
        public let prescription: SessionPrescription
        /// What the engine does to the slot after this exposure is banked as
        /// prescribed: the increment, the reset, or the hold.
        public let advanceNote: String?

        public init(exposureNumber: Int, cycleNumber: Int, rotation: Int, phaseName: String?,
                    isRecovery: Bool, baseWeightLb: Double, prescription: SessionPrescription,
                    advanceNote: String?) {
            self.exposureNumber = exposureNumber
            self.cycleNumber = cycleNumber
            self.rotation = rotation
            self.phaseName = phaseName
            self.isRecovery = isRecovery
            self.baseWeightLb = baseWeightLb
            self.prescription = prescription
            self.advanceNote = advanceNote
        }
    }

    /// The next `count` exposures a slot will actually produce.
    ///
    /// The point of the deterministic engine is that its output can be audited,
    /// and a wall of steppers is not an audit. A lifter setting a 190 lb base
    /// cannot see that it yields a 225 lb peak triple while 188 yields 220 —
    /// the difference between a +10 and a +5 jump, decided entirely by which
    /// side of a rounding boundary the multiplication lands on. This turns that
    /// into something a human reads at a glance.
    ///
    /// It runs the SHIPPED engine forward rather than describing it: every
    /// prescription comes from `sessionPrescription`, and every step between
    /// exposures comes from the same `advanceAccessory` / `advanceLinearLift` /
    /// `advanceProgramLift` calls the banking layer makes. A parallel
    /// implementation would be able to disagree with the app, which would make
    /// the preview worse than nothing.
    ///
    /// The forward walk assumes each exposure is banked exactly as prescribed —
    /// a clean success. That is the honest reading of "what will this produce":
    /// misses are the lifter's to discover, and a preview that guessed at them
    /// would be fiction. Reset and stall state still show, because the slot's
    /// CURRENT `stallCount` is carried in and the engine's own notes come back
    /// on each entry.
    ///
    /// Costs no persisted state — it takes a copy of the slot's values and
    /// returns a value type.
    ///
    /// Mirrored 1:1 in web/app/js/core.js `exposurePreview`.
    public static func exposurePreview(
        count: Int = 4,
        baseWeightLb: Double,
        estimatedMaxLb: Double = 0,
        stallCount: Int = 0,
        cycleNumber: Int = 1,
        rotation: Int = 1,
        programRoundingLb: Double = defaultRoundingLb,
        exerciseType: String? = nil,
        movementGroup: String? = nil,
        role: LiftRole = .main,
        focus: TrainingFocus = .strength,
        prescriptionStyle: PrescriptionStyle = .automatic,
        configuration: LiftPrescriptionConfiguration = .init(),
        pendingState: ProgramLiftState? = nil,
        schedule: ExposurePreviewSchedule? = nil
    ) -> [ExposurePreviewEntry] {
        guard count > 0, baseWeightLb >= 0 else { return [] }
        let style = resolvedStyle(prescriptionStyle, movementGroup: movementGroup, role: role, focus: focus)
        let step = loadStep(programRoundingLb: programRoundingLb, exerciseType: exerciseType)
        var state = ProgramLiftState(
            baseWeightLb: baseWeightLb, estimatedMaxLb: estimatedMaxLb,
            stallCount: stallCount, role: role, lastIncrementLb: 0
        )
        // Normalize the rep window BEFORE the first prescription, not inside
        // the double-progression branch that advances it. A slot whose window
        // was never configured carries zeroes, which is a prescription of
        // nothing, and crossed endpoints would otherwise let the preview show
        // a rep jump and a load step landing together. `repWindow` owns both
        // readings; the app layer clamps on the way in
        // (`ProgramLift.prescriptionConfiguration`), so only a direct core
        // caller can reach here unclamped, and doing it here as well is what
        // keeps this function honest on its own and identical to core.js.
        var config = configuration
        config.workingSets = Swift.max(1, config.workingSets)
        let window = ProgramProgression.repWindow(
            minReps: config.minimumReps, maxReps: config.maximumReps, currentReps: config.currentReps
        )
        config.minimumReps = window.low
        config.maximumReps = window.high
        config.currentReps = style == .linearFives
            ? (config.currentReps <= 3 ? 3 : 5)
            : window.current
        var cycle = Swift.max(1, cycleNumber)
        var phase = CyclePhase(rawValue: rotation) ?? .volume
        // Graded styles stash the new base at the Peak and apply it at the
        // rollover, so the recovery rotation still runs off the old base.
        // Mirrors `pendingBaseWeightLb` in the banking layer exactly.
        //
        // Seeded from the slot's ALREADY-BANKED grade when there is one. Open
        // the editor during recovery after a peak has been banked and the slot
        // is carrying an earned new base that the next cycle will use; starting
        // from nil previewed that cycle off the old base and quietly understated
        // every number the lifter was about to see.
        var pending: ProgramLiftState? = pendingState
        var entries: [ExposurePreviewEntry] = []

        // A direct core caller may omit schedule context. Treat that as a
        // one-day program so the pure prescription walk remains useful, while
        // the app surfaces always supply the real authored schedule.
        let previewSchedule = schedule ?? ExposurePreviewSchedule(
            targetDayOrder: 0, nextDayOrder: 0,
            allDayOrders: [0], recoveryDayOrders: [0], synchronizedDayOrders: [0]
        )
        let allOrders = Array(Set(previewSchedule.allDayOrders)).sorted()
        let recoveryOrders = Array(Set(previewSchedule.recoveryDayOrders)).sorted()
        guard allOrders.contains(previewSchedule.targetDayOrder) else { return [] }
        let synchronizedOrders = Set(previewSchedule.synchronizedDayOrders + [previewSchedule.targetDayOrder])

        func activeOrders(for phase: CyclePhase) -> [Int] {
            if phase == .deload, !recoveryOrders.isEmpty { return recoveryOrders }
            return allOrders
        }

        var orders = activeOrders(for: phase)
        var orderIndex = orders.firstIndex(of: previewSchedule.nextDayOrder) ?? 0
        // Four requested exposures need at most four complete authored passes,
        // plus the partial pass before the first target and one omitted recovery
        // pass. The guard fails closed for malformed/empty schedules.
        let maxSteps = count * Swift.max(1, allOrders.count + recoveryOrders.count) + allOrders.count + 8
        var steps = 0

        while entries.count < count, !orders.isEmpty, steps < maxSteps {
            steps += 1
            let dayOrder = orders[orderIndex]
            let isTarget = dayOrder == previewSchedule.targetDayOrder
            let isSynchronizedDay = synchronizedOrders.contains(dayOrder)
            let cycleState = CycleState(
                cycleNumber: cycle, baseWeightLb: state.baseWeightLb,
                nextPhase: phase, incrementLb: state.lastIncrementLb
            )
            let prescription = sessionPrescription(
                for: cycleState, programRoundingLb: programRoundingLb, exerciseType: exerciseType,
                movementGroup: movementGroup, role: role, focus: focus,
                prescriptionStyle: style, configuration: config, estimatedMaxLb: state.estimatedMaxLb
            )
            let work = prescription.mainWork
            var note: String?

            if isTarget, style == .doubleProgression {
                // Rep window first, load second — and never on the recovery
                // rotation, which is non-progressive by contract.
                if phase != .deload {
                    // `config` was normalized on the way in, so the window is
                    // already coherent here.
                    let prior = AccessoryState(
                        sets: config.workingSets, minReps: config.minimumReps,
                        maxReps: config.maximumReps, currentReps: config.currentReps,
                        weightLb: state.baseWeightLb, incrementLb: step, stallCount: state.stallCount
                    )
                    let next = ProgramProgression.advanceAccessory(
                        prior,
                        perf: AccessoryPerformance(
                            completedSets: work.sets, minRepsAchieved: work.reps,
                            anyStoppedEarly: false, performedAtPlannedLoad: true,
                            grindyOrWobbleSets: 0, bodyFlagSets: 0
                        )
                    )
                    note = next.weightLb > prior.weightLb
                        ? "Top of the window earned — add \(Weight.trim(step)) lb and drop back to \(next.currentReps) reps."
                        : "Earned the reps — \(next.currentReps) next time at the same load."
                    state.lastIncrementLb = next.weightLb - prior.weightLb
                    state.baseWeightLb = next.weightLb
                    state.stallCount = next.stallCount
                    config.currentReps = next.currentReps
                }
            } else if style.advancesPerExposure, style != .doubleProgression, isSynchronizedDay {
                if phase != .deload {
                    let result = style == .maxEffort
                        ? ProgramProgression.advanceProgramLift(
                            state, perf: cleanPerformance(for: work), focus: focus,
                            style: style, movementGroup: movementGroup, roundingLb: step
                        )
                        : ProgramProgression.advanceLinearLift(
                            state, perf: cleanPerformance(for: work),
                            rule: ProgramProgression.linearRule(for: style, movementGroup: movementGroup),
                            roundingLb: step
                        )
                    state = result.state
                    if isTarget { note = result.note }
                } else if isTarget {
                    note = "Recovery rotation — the base holds, then the exposure cadence resumes."
                }
            } else if isTarget, phase.rawValue == ProgramProgression.gradedWeek {
                let result = ProgramProgression.advanceProgramLift(
                    state, perf: cleanPerformance(for: work), focus: focus, style: style,
                    movementGroup: movementGroup, roundingLb: step
                )
                // The grade is banked now; the base lands at the rollover.
                pending = result.state
                note = result.note
            }

            if isTarget {
                entries.append(ExposurePreviewEntry(
                    exposureNumber: entries.count + 1,
                    cycleNumber: cycle,
                    rotation: phase.rawValue,
                    phaseName: slotPhaseLabel(
                        rotation: phase.rawValue, role: role, prescriptionStyle: style,
                        movementGroup: movementGroup, focus: focus
                    ),
                    isRecovery: phase == .deload,
                    baseWeightLb: cycleState.baseWeightLb,
                    prescription: prescription,
                    advanceNote: note
                ))
            }

            orderIndex += 1
            if orderIndex >= orders.count {
                if phase == .deload {
                    cycle += 1
                    // Mirror `rollOverRecovery` exactly, all three branches.
                    // Per-exposure slots discard stale pending grades; graded
                    // slots apply a banked grade; a peak-less wave accrues the
                    // same stall/rebuild the real rollover will apply.
                    if style.advancesPerExposure {
                        pending = nil
                    } else if let banked = pending {
                        state = banked
                        pending = nil
                    } else if style.usesCyclePhases {
                        state.stallCount += 1
                        state.lastIncrementLb = 0
                        if state.stallCount >= ProgramProgression.stallLimit {
                            state.baseWeightLb = Weight.round(
                                state.baseWeightLb * ProgramProgression.deloadRebuildFraction, to: step
                            )
                            state.stallCount = 0
                        }
                    }
                    phase = .volume
                } else {
                    phase = phase.next
                }
                orders = activeOrders(for: phase)
                orderIndex = 0
            }
        }
        return entries
    }

    /// A clean exposure of a plan: every prescribed set made at the prescribed
    /// load, no quality flags, no autoreg drop. This is what the forward walk
    /// assumes at each step — misses are the lifter's to discover, and a
    /// preview that guessed at them would be fiction.
    private static func cleanPerformance(for plan: SessionPlan) -> CycleLiftPerformance {
        CycleLiftPerformance(
            prescribedSets: plan.sets, prescribedReps: plan.reps,
            completedSets: plan.sets, anyStoppedEarly: false, anyDroppedLoad: false,
            anyBelowPlanLoad: false, grindyOrWobbleSets: 0,
            topSetWeightLb: plan.weightLb, topSetReps: plan.reps,
            plannedTopWeightLb: plan.weightLb
        )
    }

    public static func primerWeight(
        baseWeightLb: Double,
        phase: CyclePhase,
        style: PrescriptionStyle,
        roundingLb: Double,
        configuration: LiftPrescriptionConfiguration = .init()
    ) -> Double? {
        switch phase {
        case .volume, .deload: return nil
        case .load: return Weight.round(baseWeightLb, to: roundingLb)
        case .peak:
            if style == .offsetWave {
                return Weight.round(baseWeightLb + configuration.loadOffsetLb, to: roundingLb)
            }
            return Weight.round(baseWeightLb * CyclePhase.load.multiplier, to: roundingLb)
        }
    }

    /// Next suggested session for a cycle-tracked lift.
    public static func plan(for state: CycleState, roundingLb: Double = defaultRoundingLb) -> SessionPlan {
        let phase = state.nextPhase
        let raw = state.baseWeightLb * phase.multiplier
        return SessionPlan(
            weightLb: Weight.round(raw, to: roundingLb),
            sets: phase.sets,
            reps: phase.reps,
            phase: phase,
            cycleNumber: state.cycleNumber
        )
    }

    /// Advance state after completing a phase. Completing recovery rolls the
    /// cycle: base weight += increment, back to volume.
    public static func advancing(_ state: CycleState, afterCompleting phase: CyclePhase) -> CycleState {
        var next = state
        if phase == .deload {
            next.cycleNumber += 1
            next.baseWeightLb += state.incrementLb
            next.nextPhase = .volume
        } else {
            next.nextPhase = phase.next
        }
        return next
    }

    /// Autoregulation: one tap on "dropping load" mid-session. Cuts the
    /// remaining sets ~7% and rounds to a loadable weight, never below the bar.
    public static func droppedLoad(
        from currentLb: Double,
        roundingLb: Double = defaultRoundingLb,
        barLb: Double = 45,
        dropIncrementLb: Double? = nil
    ) -> Double {
        let dropped = dropIncrementLb.flatMap { $0 > 0 ? currentLb - $0 : nil }
            ?? Weight.round(currentLb * 0.93, to: roundingLb)
        // Guarantee an actual drop even when rounding lands on the same number.
        let result = dropped >= currentLb ? currentLb - roundingLb : dropped
        return Swift.max(result, barLb)
    }

    /// Which sets a mid-session "dropping load" tap rewrites, and to what.
    /// Only sets not yet performed (unflagged working sets) are touched — a
    /// flagged set is history — and each is dropped from ITS OWN weight, so a
    /// lighter back-off set is never raised toward the top set's drop.
    /// Mirrored 1:1 in web/app/js/core.js `dropLoadPlan`.
    public static func dropLoadPlan(
        sets: [(weightLb: Double, isWarmup: Bool, isFlagged: Bool)],
        roundingLb: Double = defaultRoundingLb,
        barLb: Double = 45,
        dropIncrementLb: Double? = nil
    ) -> [(index: Int, weightLb: Double)] {
        sets.enumerated().compactMap { i, s in
            guard !s.isWarmup, !s.isFlagged else { return nil }
            return (index: i, weightLb: droppedLoad(from: s.weightLb, roundingLb: roundingLb,
                                                    barLb: barLb, dropIncrementLb: dropIncrementLb))
        }
    }
}

/// Why load was dropped mid-session. Logged with the change.
public enum AutoregReason: String, Codable, CaseIterable, Sendable {
    case barSpeed = "bar speed"
    case wobble
    case jointSignal = "joint signal"
    case heat
    case fatigue
    case notThere = "not there"
}
