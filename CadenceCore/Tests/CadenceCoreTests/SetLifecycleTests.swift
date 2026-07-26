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
}
