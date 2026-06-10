import XCTest
@testable import ComebackCore

final class PRDetectionTests: XCTestCase {

    /// Deadlift history through Jun 4 (working sets only), per the seed log.
    private var deadliftHistory: [SetSample] {
        // May 9: 221×1×3; May 15: 221×1×3; May 22: 210×3×5 + 221×3×2; May 29: 210×5×5.
        [SetSample(weightLb: 221, reps: 3), SetSample(weightLb: 221, reps: 3)]
            + Array(repeating: SetSample(weightLb: 210, reps: 5), count: 3)
            + Array(repeating: SetSample(weightLb: 221, reps: 2), count: 3)
            + Array(repeating: SetSample(weightLb: 210, reps: 5), count: 5)
    }

    private var deadliftHistoryVolumes: [Double] {
        [221 * 3, 221 * 3, 210 * 3 * 5 + 221 * 3 * 2, 210 * 5 * 5]
    }

    func testJun7DeadliftIsHeaviestOfComeback() {
        // Jun 7: 232 × 5 sets × 3 reps. Prior max 221 → heaviest-set milestone.
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
        XCTAssertEqual(heaviest?.label, "232×5×3 — heaviest deadlift of the comeback")
        // First time running a 5×3 top scheme → also a milestone.
        XCTAssertTrue(events.contains { $0.kind == .firstScheme })
        // 232×5×3 = 3480 lb < May 29's 5250 lb — NOT a volume PR. Don't inflate.
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
}
