import XCTest
@testable import CadenceCore

final class HealthRuckStepsTests: XCTestCase {
    private let ruck = CompletedExerciseKind(name: "Ruck", type: "conditioning", category: "conditioning")

    func testOnlyCompletedRucksQualify() {
        // [INV-HEALTH-RUCK-STEPS-ARE-MEASURED]
        XCTAssertTrue(HealthRuckSteps.isRuckOnly([ruck]))
        XCTAssertTrue(HealthRuckSteps.isRuckOnly([ruck, ruck]))
        XCTAssertFalse(HealthRuckSteps.isRuckOnly([]))
        XCTAssertFalse(HealthRuckSteps.isRuckOnly([ruck, CompletedExerciseKind(name: "", type: "", category: "")]))
        XCTAssertFalse(HealthRuckSteps.isRuckOnly([
            ruck, CompletedExerciseKind(name: "Squat", type: "barbell", category: "legs")
        ]))
        XCTAssertFalse(HealthRuckSteps.isRuckOnly([
            ruck, CompletedExerciseKind(name: "Walk", type: "conditioning", category: "conditioning")
        ]))
        XCTAssertFalse(HealthRuckSteps.isRuckOnly([
            CompletedExerciseKind(name: "Ruck", type: "barbell", category: "conditioning")
        ]))
        // A substring is not evidence of rucking, nor does hiking prove a ruck.
        XCTAssertFalse(HealthRuckSteps.isRuckOnly([
            CompletedExerciseKind(name: "Truck pull", type: "conditioning", category: "conditioning")
        ]))
        XCTAssertFalse(HealthRuckSteps.isRuckOnly([
            CompletedExerciseKind(name: "Hike", type: "conditioning", category: "conditioning")
        ]))
    }

    func testNoDataNeverBecomesAMeasuredZero() {
        for value: Double? in [nil, 0, 0.25, -1, .nan, .infinity, -.infinity] {
            XCTAssertNil(HealthRuckSteps.measuredCount(value))
        }
        XCTAssertEqual(HealthRuckSteps.measuredCount(1234), 1234)
        XCTAssertEqual(HealthRuckSteps.measuredCount(1234.5), 1234.5)
    }

    func testWindowUsesRealStartAndIncludesInteriorPauseButNotTrailingPause() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var record = WorkoutClockRecord(sessionID: "synthetic-ruck", start: start,
                                       healthTiming: HealthWorkoutTiming(start: start))
        record.pause(at: start.addingTimeInterval(100))
        record.resume(at: start.addingTimeInterval(200))
        record.reset(at: start.addingTimeInterval(250))
        record.pause(at: start.addingTimeInterval(300))
        let timing = try XCTUnwrap(record.healthTiming?.export(endingAt: start.addingTimeInterval(400)))
        XCTAssertEqual(timing.start, start)
        XCTAssertEqual(timing.end, start.addingTimeInterval(300))
        XCTAssertEqual(timing.end.timeIntervalSince(timing.start), 300)
        XCTAssertEqual(timing.activeDuration, 200)
        XCTAssertEqual(timing.pauses.count, 1)
    }
}
