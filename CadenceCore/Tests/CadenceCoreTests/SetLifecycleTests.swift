import XCTest
@testable import CadenceCore

final class SetLifecycleTests: XCTestCase {
    func testLegacyResolutionIsConservativeForOpenSessions() {
        XCTAssertEqual(SetLifecycle.resolve(nil, sessionCompleted: false), .planned)
        XCTAssertEqual(SetLifecycle.resolve(nil, sessionCompleted: true), .completed)
        XCTAssertEqual(SetLifecycle.resolve("skipped", sessionCompleted: true), .skipped)
    }

    func testQualityIsExclusiveAndStoppedEarlyIndependent() {
        XCTAssertEqual(SetLifecycle.normalizedFlags(quality: "grindy", stoppedEarly: true),
                       ["grindy", "stopped early"])
        XCTAssertEqual(SetLifecycle.normalizedFlags(quality: nil, stoppedEarly: true),
                       ["stopped early"])
        XCTAssertEqual(SetLifecycle.quality(in: ["wobble", "stopped early"]), "wobble")
    }

    /// Reps in reserve is its own exclusive group beside quality. The normalizer
    /// is the single writer of every flag list, so a group it does not know
    /// about is dropped on every read as well as on export — which is exactly
    /// how a new flag can appear to work and then vanish on restore.
    func testRepsInReserveSurvivesNormalizationAlongsideQuality() {
        XCTAssertEqual(
            SetLifecycle.normalizedFlags(quality: "clean", stoppedEarly: false, rir: "rir1"),
            ["clean", "rir1"],
            "a set can be both clean and one rep from failure"
        )
        XCTAssertEqual(
            SetLifecycle.normalizedFlags(quality: "grindy", stoppedEarly: true, rir: "rir3plus"),
            ["grindy", "rir3plus", "stopped early"]
        )
        XCTAssertEqual(SetLifecycle.normalizedFlags(quality: nil, stoppedEarly: false, rir: "rir2"), ["rir2"])
        XCTAssertEqual(SetLifecycle.normalizedFlags(quality: "clean", stoppedEarly: false, rir: "nonsense"), ["clean"],
                       "an unknown value is dropped rather than stored")
        XCTAssertNil(SetLifecycle.rir(in: ["clean", "stopped early"]))
        XCTAssertEqual(SetLifecycle.rir(in: ["clean", "rir2"]), "rir2")
        // The two groups must not overlap, or one would exclude the other.
        XCTAssertTrue(Set(SetLifecycle.qualityValues).isDisjoint(with: SetLifecycle.rirValues))
    }

    /// Mirrors the current-set block in web/tests/core.test.mjs.
    ///
    /// This rule decides which set the Lock Screen's Done button completes, so
    /// it has to agree with the row the logger highlights. It was hand-written
    /// in both clients before it lived here.
    func testCurrentSetIsTheFirstPlannedWorkingSet() {
        // warmup, warmup, done, planned, planned
        let isWarmup = [true, true, false, false, false]
        let statuses = ["completed", "planned", "completed", "planned", "planned"]
        XCTAssertEqual(SetLifecycle.currentSetIndex(isWarmup: isWarmup, statuses: statuses), 3,
                       "an unflagged warmup must not hold the working sets hostage")

        XCTAssertEqual(
            SetLifecycle.currentSetIndex(isWarmup: [false, false], statuses: ["planned", "planned"]), 0)
        XCTAssertNil(
            SetLifecycle.currentSetIndex(isWarmup: [false, false], statuses: ["completed", "completed"]),
            "nothing left to work is nil, not zero")
        XCTAssertNil(SetLifecycle.currentSetIndex(isWarmup: [], statuses: []))
        XCTAssertNil(
            SetLifecycle.currentSetIndex(isWarmup: [true, true], statuses: ["planned", "planned"]),
            "warmups alone are not a current set")

        // A skipped set is passed over, not treated as the end of the exercise:
        // skipping set two still leaves set three to do.
        XCTAssertEqual(
            SetLifecycle.currentSetIndex(isWarmup: [false, false, false],
                                         statuses: ["completed", "skipped", "planned"]), 2)
    }

    func testWorkingSetProgressCountsWarmupsOutOfBothHalves() {
        // Two warmups then five working sets, two of them banked.
        let isWarmup = [true, true, false, false, false, false, false]
        let statuses = ["completed", "completed", "completed", "completed", "planned", "planned", "planned"]
        let progress = SetLifecycle.workingSetProgress(isWarmup: isWarmup, statuses: statuses)
        XCTAssertEqual(progress?.position, 3, "the set being worked, not the number already banked")
        XCTAssertEqual(progress?.total, 5, "warmups are not part of the count")

        // With everything done the readout parks at the end rather than
        // reporting a set that does not exist.
        XCTAssertEqual(
            SetLifecycle.workingSetProgress(isWarmup: [false, false],
                                            statuses: ["completed", "completed"])?.position, 2)
        XCTAssertNil(SetLifecycle.workingSetProgress(isWarmup: [true], statuses: ["planned"]),
                     "an exercise of only warmups has no working progress to report")
        XCTAssertNil(SetLifecycle.workingSetProgress(isWarmup: [], statuses: []))

        // A skipped set still occupies its position — the lifter did plan it.
        let skipped = SetLifecycle.workingSetProgress(
            isWarmup: [false, false, false], statuses: ["skipped", "planned", "planned"])
        XCTAssertEqual(skipped?.position, 2)
        XCTAssertEqual(skipped?.total, 3)
    }
}
