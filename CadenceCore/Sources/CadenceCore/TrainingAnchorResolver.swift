import Foundation

/// Where a training anchor's capability estimate came from. Ordered by how
/// much evidence stands behind it — the UI shows this so an estimate never
/// masquerades as measured history.
public enum TrainingAnchorSource: String, Sendable, Equatable {
    case explicitOverride
    case exactExerciseE1RM
    case exactExerciseRecentWork
    case relatedExerciseEstimate
    case movementFamilyEstimate
    case conservativeDefault
}

public enum AnchorConfidence: String, Sendable, Equatable {
    case measured, estimated, guessed
}

/// One explicit, versioned relationship between two lifts. Deliberately a
/// small data table, not an exercise ontology: only the relationships shipped
/// templates and common substitutions actually need, each with coefficients
/// under test. Relations are never inferred from substring matching.
public struct ExerciseEstimateRule: Sendable, Equatable {
    public let id: String
    public let version: Int
    public let sourceExerciseName: String
    public let targetExerciseName: String
    public let coefficient: Double
    public let confidence: AnchorConfidence

    public init(id: String, version: Int = 1, source: String, target: String,
                coefficient: Double, confidence: AnchorConfidence = .estimated) {
        self.id = id
        self.version = version
        self.sourceExerciseName = source
        self.targetExerciseName = target
        self.coefficient = coefficient
        self.confidence = confidence
    }
}

public struct ResolvedTrainingAnchor: Sendable, Equatable {
    public let e1RMLb: Double?
    public let latestWorkLb: Double?
    public let source: TrainingAnchorSource
    public let sourceExerciseName: String?
    public let confidence: AnchorConfidence
    public let ruleID: String?
    /// Short, user-facing: "Estimated from Back Squat".
    public let explanation: String
}

public enum TrainingAnchorResolver {
    /// The shipped relation table. Conservative by construction: a variation
    /// resolves from the competition lift that trains it, Olympic work
    /// prefers its own history and only falls back at low confidence, and no
    /// rule chains through another rule.
    public static let defaultRules: [ExerciseEstimateRule] = [
        // Squat family
        .init(id: "front-squat-from-back-squat", source: "Back Squat", target: "Front Squat", coefficient: 0.85),
        .init(id: "overhead-squat-from-back-squat", source: "Back Squat", target: "Overhead Squat", coefficient: 0.65, confidence: .guessed),
        .init(id: "low-box-squat-from-back-squat", source: "Back Squat", target: "Low Box Squat", coefficient: 0.90),
        .init(id: "paused-box-squat-from-back-squat", source: "Back Squat", target: "Paused Box Squat", coefficient: 0.90),
        .init(id: "front-box-squat-from-back-squat", source: "Back Squat", target: "Front Box Squat", coefficient: 0.80),
        .init(id: "speed-box-squat-from-back-squat", source: "Back Squat", target: "Speed Box Squat", coefficient: 0.60),
        // Hinge family
        .init(id: "rdl-from-deadlift", source: "Deadlift", target: "Romanian Deadlift", coefficient: 0.85),
        .init(id: "snatch-grip-deadlift-from-deadlift", source: "Deadlift", target: "Snatch-grip Deadlift", coefficient: 0.85),
        .init(id: "speed-deadlift-from-deadlift", source: "Deadlift", target: "Speed Deadlift", coefficient: 0.60),
        .init(id: "sumo-deadlift-from-deadlift", source: "Deadlift", target: "Sumo Deadlift", coefficient: 0.95),
        .init(id: "good-morning-from-deadlift", source: "Deadlift", target: "Good Morning", coefficient: 0.50, confidence: .guessed),
        // Horizontal press family
        .init(id: "incline-bench-from-bench", source: "Barbell Bench", target: "Incline Barbell Bench Press", coefficient: 0.80),
        .init(id: "close-grip-bench-from-bench", source: "Barbell Bench", target: "Close-Grip Bench Press", coefficient: 0.90),
        .init(id: "floor-press-from-bench", source: "Barbell Bench", target: "Close-Grip Floor Press", coefficient: 0.85),
        .init(id: "speed-bench-from-bench", source: "Barbell Bench", target: "Speed Bench Press", coefficient: 0.60),
        // Vertical press family
        .init(id: "press-from-bench", source: "Barbell Bench", target: "Overhead Press", coefficient: 0.63, confidence: .guessed),
        .init(id: "push-press-from-press", source: "Overhead Press", target: "Push Press", coefficient: 1.15),
        // Olympic: exact history first; these are the low-confidence floor.
        .init(id: "clean-from-front-squat", source: "Front Squat", target: "Clean", coefficient: 0.80, confidence: .guessed),
        .init(id: "power-clean-from-clean", source: "Clean", target: "Power Clean", coefficient: 0.85),
        .init(id: "clean-and-jerk-from-clean", source: "Clean", target: "Clean & Jerk", coefficient: 0.95),
        .init(id: "power-snatch-from-snatch", source: "Snatch", target: "Power Snatch", coefficient: 0.85),
    ]

    /// Resolve gym-independent athlete capability for one exercise, in the
    /// documented order: explicit override, exact-exercise e1RM, exact-exercise
    /// recent work, an explicit related-lift rule, a movement-family anchor,
    /// then the conservative catalog default. The result carries its source
    /// and confidence so the UI can say "Estimated from Back Squat" and never
    /// present an estimate as measured history.
    ///
    /// Capability only: no gym, bar, or plate inventory reaches this function,
    /// so the same history resolves identically everywhere. The methodology
    /// converts the anchor into a prescription, and `PlateMath.quantize` snaps
    /// that to the rack — strictly downstream of here.
    public static func resolve(
        exerciseName: String,
        movementGroup: String? = nil,
        history: [String: AthleteHistory.LiftHistoryProfile],
        overrideE1RMLb: Double? = nil,
        defaultE1RMLb: Double? = nil,
        rules: [ExerciseEstimateRule] = defaultRules,
        familyAnchors: [String: String] = defaultFamilyAnchors,
        shelvedExerciseNames: Set<String> = [],
        allowFamilyEstimate: Bool = true
    ) -> ResolvedTrainingAnchor {
        if let override = overrideE1RMLb, override > 0 {
            return ResolvedTrainingAnchor(
                e1RMLb: override, latestWorkLb: history[exerciseName]?.latestCompletedLoadLb,
                source: .explicitOverride, sourceExerciseName: exerciseName,
                confidence: .measured, ruleID: nil, explanation: "Your own setting")
        }
        if let exact = history[exerciseName] {
            if let best = exact.allTimeBestE1RMLb, best > 0 {
                return ResolvedTrainingAnchor(
                    e1RMLb: best, latestWorkLb: exact.latestCompletedLoadLb,
                    source: .exactExerciseE1RM, sourceExerciseName: exerciseName,
                    confidence: .measured, ruleID: nil, explanation: "From your \(exerciseName) history")
            }
            if let latest = exact.latestCompletedLoadLb, latest > 0 {
                return ResolvedTrainingAnchor(
                    e1RMLb: nil, latestWorkLb: latest,
                    source: .exactExerciseRecentWork, sourceExerciseName: exerciseName,
                    confidence: .measured, ruleID: nil, explanation: "From your last \(exerciseName)")
            }
        }
        // A shelved lift's history still informs estimates, but a shelved
        // SOURCE never seeds new work: a program must not quietly reactivate
        // something the lifter benched for a reason.
        func sourceEstimate(_ name: String, coefficient: Double, confidence: AnchorConfidence,
                            ruleID: String?, source: TrainingAnchorSource) -> ResolvedTrainingAnchor? {
            guard !shelvedExerciseNames.contains(name),
                  let profile = history[name], let best = profile.allTimeBestE1RMLb, best > 0
            else { return nil }
            return ResolvedTrainingAnchor(
                e1RMLb: best * coefficient, latestWorkLb: nil, source: source,
                sourceExerciseName: name, confidence: confidence, ruleID: ruleID,
                explanation: "Estimated from \(name)")
        }
        for rule in rules where rule.targetExerciseName == exerciseName {
            if let estimate = sourceEstimate(rule.sourceExerciseName, coefficient: rule.coefficient,
                                             confidence: rule.confidence, ruleID: rule.id,
                                             source: .relatedExerciseEstimate) {
                return estimate
            }
        }
        // A family estimate says only "these train the same pattern", which is
        // thin evidence for a lift the athlete has never performed. Callers
        // that SEED a slot pass false and take the conservative catalog
        // default instead: a too-light opening set costs one easy session, a
        // too-heavy one costs a failed rep under a loaded bar. Surfaces that
        // show an estimate for the athlete to accept or correct keep it.
        if allowFamilyEstimate, let group = movementGroup, let anchorName = familyAnchors[group],
           anchorName != exerciseName,
           let estimate = sourceEstimate(anchorName, coefficient: familyCoefficient,
                                         confidence: .guessed, ruleID: nil,
                                         source: .movementFamilyEstimate) {
            return estimate
        }
        return ResolvedTrainingAnchor(
            e1RMLb: (defaultE1RMLb ?? 0) > 0 ? defaultE1RMLb : nil, latestWorkLb: nil,
            source: .conservativeDefault, sourceExerciseName: nil,
            confidence: .guessed, ruleID: nil, explanation: "Conservative starting load")
    }

    /// The core lift each movement family answers to when no exact or related
    /// history exists. Last stop before the catalog default.
    public static let defaultFamilyAnchors: [String: String] = [
        "squat": "Back Squat",
        "hinge": "Deadlift",
        "press": "Barbell Bench",
        "pull": "Deadlift",
    ]

    /// Deliberately pessimistic: a family estimate knows only that two lifts
    /// train the same pattern, so it starts light and lets the program earn
    /// the load back.
    public static let familyCoefficient = 0.5
}
