import XCTest
@testable import CadenceCore

/// Epic #155 Stage 3. Mirrored 1:1 by web/tests/core.test.mjs
/// "resolveTrainingAnchor" — same fixtures, same expectations.
final class TrainingAnchorResolverTests: XCTestCase {
    private func profile(best: Double? = nil, latest: Double? = nil) -> AthleteHistory.LiftHistoryProfile {
        AthleteHistory.LiftHistoryProfile(
            latestCompletedLoadLb: latest, latestExposureMs: latest == nil ? nil : 1_000,
            allTimeBestE1RMLb: best)
    }

    func testExactHistoryWinsAndReadsAsMeasured() {
        let anchor = TrainingAnchorResolver.resolve(
            exerciseName: "Back Squat", movementGroup: "squat",
            history: ["Back Squat": profile(best: 315, latest: 285)])
        XCTAssertEqual(anchor.source, .exactExerciseE1RM)
        XCTAssertEqual(anchor.e1RMLb, 315)
        XCTAssertEqual(anchor.latestWorkLb, 285)
        XCTAssertEqual(anchor.confidence, .measured)
    }

    func testExplicitOverrideOutranksEverything() {
        let anchor = TrainingAnchorResolver.resolve(
            exerciseName: "Back Squat", history: ["Back Squat": profile(best: 315)],
            overrideE1RMLb: 405)
        XCTAssertEqual(anchor.source, .explicitOverride)
        XCTAssertEqual(anchor.e1RMLb, 405)
    }

    func testRecentWorkCarriesAStyleThatNeedsALoadNotAnEstimate() {
        // A lift logged only at bodyweight-ish loads has no usable e1RM but a
        // real last exposure: double progression wants that load.
        let anchor = TrainingAnchorResolver.resolve(
            exerciseName: "Good Morning", history: ["Good Morning": profile(latest: 135)])
        XCTAssertEqual(anchor.source, .exactExerciseRecentWork)
        XCTAssertEqual(anchor.latestWorkLb, 135)
        XCTAssertNil(anchor.e1RMLb)
    }

    func testRelatedLiftEstimateFillsAnUnseenVariation() {
        let anchor = TrainingAnchorResolver.resolve(
            exerciseName: "Front Squat", movementGroup: "squat",
            history: ["Back Squat": profile(best: 300)])
        XCTAssertEqual(anchor.source, .relatedExerciseEstimate)
        XCTAssertEqual(anchor.e1RMLb, 255)             // 300 × 0.85
        XCTAssertEqual(anchor.sourceExerciseName, "Back Squat")
        XCTAssertEqual(anchor.ruleID, "front-squat-from-back-squat")
        XCTAssertEqual(anchor.explanation, "Estimated from Back Squat")
        XCTAssertEqual(anchor.confidence, .estimated)
    }

    func testMovementFamilyAnchorIsTheLastEstimateBeforeTheDefault() {
        // Hack Squat has no rule of its own, but it is squat work.
        let anchor = TrainingAnchorResolver.resolve(
            exerciseName: "Hack Squat", movementGroup: "squat",
            history: ["Back Squat": profile(best: 300)])
        XCTAssertEqual(anchor.source, .movementFamilyEstimate)
        XCTAssertEqual(anchor.e1RMLb, 150)             // deliberately pessimistic
        XCTAssertEqual(anchor.confidence, .guessed)
    }

    func testNoHistoryFallsBackToTheConservativeDefault() {
        let anchor = TrainingAnchorResolver.resolve(
            exerciseName: "Front Squat", movementGroup: "squat",
            history: [:], defaultE1RMLb: 95)
        XCTAssertEqual(anchor.source, .conservativeDefault)
        XCTAssertEqual(anchor.e1RMLb, 95)
        XCTAssertEqual(anchor.confidence, .guessed)
        XCTAssertNil(anchor.sourceExerciseName)
    }

    func testAShelvedLiftNeverSeedsNewWork() {
        let anchor = TrainingAnchorResolver.resolve(
            exerciseName: "Front Squat", movementGroup: "squat",
            history: ["Back Squat": profile(best: 300)], defaultE1RMLb: 95,
            shelvedExerciseNames: ["Back Squat"])
        XCTAssertEqual(anchor.source, .conservativeDefault,
                       "a shelved squat must not quietly seed a new squat variation")
    }

    func testOlympicWorkPrefersItsOwnHistoryOverAStrengthEstimate() {
        let both = TrainingAnchorResolver.resolve(
            exerciseName: "Clean", movementGroup: "hinge",
            history: ["Clean": profile(best: 205), "Front Squat": profile(best: 275)])
        XCTAssertEqual(both.source, .exactExerciseE1RM)
        XCTAssertEqual(both.e1RMLb, 205)

        let estimated = TrainingAnchorResolver.resolve(
            exerciseName: "Clean", movementGroup: "hinge",
            history: ["Front Squat": profile(best: 275)])
        XCTAssertEqual(estimated.source, .relatedExerciseEstimate)
        XCTAssertEqual(estimated.confidence, .guessed, "a lifted-from-squat clean is a guess, and says so")
    }


    func testSeedingCallersOptOutOfFamilyGuesses() {
        // The seeding path takes the catalog default rather than opening an
        // unfamiliar main lift at half of a different lift's estimate.
        let anchor = TrainingAnchorResolver.resolve(
            exerciseName: "Landmine Press", movementGroup: "press",
            history: ["Barbell Bench": profile(best: 225)], defaultE1RMLb: 60,
            allowFamilyEstimate: false)
        XCTAssertEqual(anchor.source, .conservativeDefault)
        XCTAssertEqual(anchor.e1RMLb, 60)
        // An EXPLICIT rule still seeds — that is real, named evidence.
        let ruled = TrainingAnchorResolver.resolve(
            exerciseName: "Front Squat", movementGroup: "squat",
            history: ["Back Squat": profile(best: 300)], defaultE1RMLb: 60,
            allowFamilyEstimate: false)
        XCTAssertEqual(ruled.source, .relatedExerciseEstimate)
        XCTAssertEqual(ruled.e1RMLb, 255)
    }

    func testEveryShippedRuleIsSaneAndUnique() {
        let rules = TrainingAnchorResolver.defaultRules
        XCTAssertEqual(Set(rules.map(\.id)).count, rules.count, "rule ids are unique")
        for rule in rules {
            XCTAssertGreaterThan(rule.coefficient, 0.3, "\(rule.id) is implausibly light")
            XCTAssertLessThan(rule.coefficient, 1.3, "\(rule.id) is implausibly heavy")
            XCTAssertNotEqual(rule.sourceExerciseName, rule.targetExerciseName, "\(rule.id) is circular")
        }
        // No rule chains through another rule's target: one hop from measured
        // history, never an estimate built on an estimate.
        let targets = Set(rules.map(\.targetExerciseName))
        for rule in rules where targets.contains(rule.sourceExerciseName) {
            XCTAssertTrue(["Clean", "Snatch", "Overhead Press", "Front Squat"].contains(rule.sourceExerciseName),
                          "\(rule.id) chains off an estimated lift without being a declared Olympic/press hop")
        }
    }
}
