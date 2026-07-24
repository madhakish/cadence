import XCTest
@testable import CadenceCore

final class PRDetectionTests: XCTestCase {

    /// Fictional prior working sets for regression coverage.
    private var deadliftHistory: [SetSample] {
        // Four fictional sessions with varied schemes and volume.
        [SetSample(weightLb: 221, reps: 3), SetSample(weightLb: 221, reps: 3)]
            + Array(repeating: SetSample(weightLb: 210, reps: 5), count: 3)
            + Array(repeating: SetSample(weightLb: 221, reps: 2), count: 3)
            + Array(repeating: SetSample(weightLb: 210, reps: 5), count: 5)
    }

    private var deadliftHistoryVolumes: [Double] {
        [221 * 3, 221 * 3, 210 * 3 * 5 + 221 * 3 * 2, 210 * 5 * 5]
    }

    func testNewTopLoadCreatesHeaviestSetEvent() {
        // 232 × 5 sets × 3 reps. Prior max 221 → heaviest-set milestone.
        let session = Array(repeating: SetSample(weightLb: 232, reps: 3), count: 5)
        let events = PRDetection.evaluate(
            exercise: "Deadlift",
            sessionSets: session,
            historySets: deadliftHistory,
            historyVolumes: deadliftHistoryVolumes,
            historySchemes: ["1×3", "3×2", "5×5"]
        )
        let heaviest = events.first { $0.kind == .heaviestSet }
        XCTAssertNotNil(heaviest)
        XCTAssertEqual(heaviest?.label, "232×5×3 — heaviest deadlift logged")
        // First time running a 5×3 top scheme → also a milestone.
        XCTAssertTrue(events.contains { $0.kind == .firstScheme })
        // 232×5×3 = 3480 lb < the prior 5250 lb — NOT a volume PR.
        XCTAssertFalse(events.contains { $0.kind == .volumePR })
    }

    func testNoMilestoneWhenNothingNew() {
        let session = [SetSample(weightLb: 200, reps: 5)]
        let events = PRDetection.evaluate(
            exercise: "Deadlift",
            sessionSets: session,
            historySets: deadliftHistory,
            historyVolumes: deadliftHistoryVolumes,
            historySchemes: ["1×3", "3×2", "5×5", "1×5"]
        )
        XCTAssertTrue(events.isEmpty)
    }

    func testVolumePRDetected() {
        let session = Array(repeating: SetSample(weightLb: 210, reps: 5), count: 5) // 5250
        let events = PRDetection.evaluate(
            exercise: "Deadlift",
            sessionSets: session,
            historySets: [SetSample(weightLb: 221, reps: 3)],
            historyVolumes: [663],
            historySchemes: ["1×3"]
        )
        XCTAssertTrue(events.contains { $0.kind == .volumePR })
        // 210 < 221: heavier history stands, no heaviest-set event.
        XCTAssertFalse(events.contains { $0.kind == .heaviestSet })
    }

    func testFirstSessionEverIsNotAVolumePR() {
        // No history → heaviest + first-scheme fire, but "volume PR" against
        // an empty history would be noise.
        let session = Array(repeating: SetSample(weightLb: 175, reps: 5), count: 5)
        let events = PRDetection.evaluate(
            exercise: "Back Squat",
            sessionSets: session,
            historySets: [],
            historyVolumes: [],
            historySchemes: []
        )
        XCTAssertTrue(events.contains { $0.kind == .heaviestSet })
        XCTAssertTrue(events.contains { $0.kind == .firstScheme })
        XCTAssertFalse(events.contains { $0.kind == .volumePR })
    }

    func testTopSchemeUsesTopWeightGroup() {
        // 175×5×5 with a back-off 155×8: scheme keys off the 175s.
        let session = Array(repeating: SetSample(weightLb: 175, reps: 5), count: 5)
            + [SetSample(weightLb: 155, reps: 8)]
        let top = PRDetection.topScheme(session)
        XCTAssertEqual(top?.weightLb, 175)
        XCTAssertEqual(top?.sets, 5)
        XCTAssertEqual(top?.reps, 5)
    }

    func testTopSchemeReportsWorkThatWasActuallyPerformed() {
        // A top set plus a fatigue set is ONE five, not two doubles. Reporting
        // the group minimum across every top-weight set invented "2×2".
        let fatigued = [SetSample(weightLb: 225, reps: 5), SetSample(weightLb: 225, reps: 2)]
        XCTAssertEqual(PRDetection.topScheme(fatigued)?.sets, 1)
        XCTAssertEqual(PRDetection.topScheme(fatigued)?.reps, 5)

        // Four clean fives and a dropped triple is 4×5, never "5×3".
        let dropped = Array(repeating: SetSample(weightLb: 225, reps: 5), count: 4)
            + [SetSample(weightLb: 225, reps: 3)]
        XCTAssertEqual(PRDetection.topScheme(dropped)?.sets, 4)
        XCTAssertEqual(PRDetection.topScheme(dropped)?.reps, 5)

        // An even split takes the harder group so the scheme is never flattered.
        let split = [SetSample(weightLb: 185, reps: 8), SetSample(weightLb: 185, reps: 6)]
        XCTAssertEqual(PRDetection.topScheme(split)?.sets, 1)
        XCTAssertEqual(PRDetection.topScheme(split)?.reps, 8)
    }

    func testBodyweightSchemeMilestoneOmitsAMeaninglessLoad() {
        let pushups = Array(repeating: SetSample(weightLb: 0, reps: 12, loadBasis: .bodyweight), count: 3)
        let events = PRDetection.evaluate(
            exercise: "Push-ups", sessionSets: pushups,
            historySets: [], historyVolumes: [], historySchemes: []
        )
        let scheme = events.first { $0.kind == .firstScheme }
        XCTAssertEqual(scheme?.label, "First 3×12 push-ups")
        XCTAssertFalse(scheme?.label.contains("0 lb") ?? true)
    }

    func testMilestoneLabelsAcceptThePresentationUnitFormatter() {
        let events = PRDetection.evaluate(
            exercise: "Deadlift",
            sessionSets: [SetSample(weightLb: 220.462, reps: 1)],
            historySets: [], historyVolumes: [], historySchemes: [],
            formatWeight: { "\(Weight.trim(Weight.kg(fromLb: $0))) kg" }
        )
        XCTAssertTrue(events.allSatisfy { $0.label.contains("100 kg") })
    }

    func testAssistanceNeverCreatesLoadOrVolumePR() {
        let assisted = [SetSample(weightLb: 40, reps: 8, loadBasis: .assisted)]
        let events = PRDetection.evaluate(
            exercise: "Assisted Pull-up", sessionSets: assisted,
            historySets: [SetSample(weightLb: 60, reps: 8, loadBasis: .assisted)],
            historyVolumes: [480], historySchemes: []
        )
        XCTAssertFalse(events.contains { $0.kind == .heaviestSet || $0.kind == .volumePR })
        XCTAssertTrue(events.contains { $0.kind == .firstScheme })
    }

    func testDifferentLoadBasesAreNotCompared() {
        let events = PRDetection.evaluate(
            exercise: "Cable Row",
            sessionSets: [SetSample(weightLb: 50, reps: 10, loadBasis: .perImplement)],
            historySets: [SetSample(weightLb: 100, reps: 10, loadBasis: .externalTotal)],
            historyVolumes: [], historySchemes: []
        )
        XCTAssertTrue(events.contains { $0.kind == .heaviestSet })
    }
}
