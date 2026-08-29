import XCTest
@testable import CadenceCore

/// Epic #155 Stage 1: the shared history fold behind template seeding.
/// Mirrored 1:1 by web/tests/core.test.mjs "athleteHistoryIndex" cases —
/// fixtures and expectations must stay identical.
final class AthleteHistoryTests: XCTestCase {
    private func sample(_ name: String, ts: Double, lb: Double, reps: Int) -> AthleteHistory.CompletedSetSample {
        AthleteHistory.CompletedSetSample(exerciseName: name, timestampMs: ts, weightLb: lb, reps: reps)
    }

    func testLatestLoadFollowsRecencyNotMagnitude() {
        let index = AthleteHistory.index([
            sample("Deadlift", ts: 1_000, lb: 315, reps: 5),
            sample("Deadlift", ts: 2_000, lb: 275, reps: 5),
        ])
        XCTAssertEqual(index["Deadlift"]?.latestCompletedLoadLb, 275)
        XCTAssertEqual(index["Deadlift"]?.latestExposureMs, 2_000)
    }

    func testSameTimestampTieTakesTheHeavierLoad() {
        let index = AthleteHistory.index([
            sample("Deadlift", ts: 2_000, lb: 275, reps: 5),
            sample("Deadlift", ts: 2_000, lb: 305, reps: 3),
            sample("Deadlift", ts: 1_000, lb: 315, reps: 5),
        ])
        XCTAssertEqual(index["Deadlift"]?.latestCompletedLoadLb, 305)
    }

    func testBestE1RMIsTheLifetimeEpleyMaxAcrossAllSamples() {
        let index = AthleteHistory.index([
            sample("Deadlift", ts: 1_000, lb: 315, reps: 5),   // 367.5
            sample("Deadlift", ts: 2_000, lb: 275, reps: 12),  // 385
            sample("Deadlift", ts: 3_000, lb: 345, reps: 1),   // 356.5
        ])
        XCTAssertEqual(index["Deadlift"]?.allTimeBestE1RMLb, 275 * (1 + 12.0 / 30.0))
    }

    func testFoldIsOrderIndependent() {
        let samples = [
            sample("Deadlift", ts: 3_000, lb: 225, reps: 8),
            sample("Deadlift", ts: 1_000, lb: 315, reps: 5),
            sample("Squat", ts: 2_000, lb: 285, reps: 5),
            sample("Deadlift", ts: 3_000, lb: 245, reps: 5),
        ]
        XCTAssertEqual(AthleteHistory.index(samples), AthleteHistory.index(samples.reversed()))
    }

    func testUnseenExerciseIsAbsent() {
        XCTAssertNil(AthleteHistory.index([sample("Deadlift", ts: 1, lb: 100, reps: 1)])["Squat"])
        XCTAssertTrue(AthleteHistory.index([]).isEmpty)
    }
}
