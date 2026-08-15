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

    /// [INV-BANKED-SETS-CORRECTABLE] The shared correction rule for editing a
    /// banked set: only provided fields change, only sane values are written,
    /// and one field's edit can never disturb another (mirrors core.test.mjs).
    func testBankedSetCorrectionsApplyOnlySaneProvidedFields() {
        typealias Correction = SetLifecycle.SetCorrection
        let base = (weightLb: 195.0, reps: 5, durationSeconds: nil as Int?, status: SetStatus.completed)

        let reweighed = SetLifecycle.correctedSetValues(
            weightLb: base.weightLb, reps: base.reps, durationSeconds: base.durationSeconds,
            status: base.status, correction: Correction(weightLb: 205)
        )
        XCTAssertEqual(reweighed.weightLb, 205)
        XCTAssertEqual(reweighed.reps, 5, "editing weight cannot reset reps")
        XCTAssertEqual(reweighed.status, .completed)

        let ticked = SetLifecycle.correctedSetValues(
            weightLb: base.weightLb, reps: base.reps, durationSeconds: nil,
            status: .planned, correction: Correction(status: .completed)
        )
        XCTAssertEqual(ticked.status, .completed, "the missed ✓ becomes real history")
        XCTAssertEqual(ticked.weightLb, 195, "editing status cannot reset weight")

        let garbage = SetLifecycle.correctedSetValues(
            weightLb: base.weightLb, reps: base.reps, durationSeconds: 30,
            status: base.status,
            correction: Correction(weightLb: -5, reps: -1, durationSeconds: -10)
        )
        XCTAssertEqual(garbage.weightLb, 195, "a negative weight keeps the stored value")
        XCTAssertEqual(garbage.reps, 5, "a negative rep count keeps the stored value")
        XCTAssertEqual(garbage.durationSeconds, 30, "a negative hold keeps the stored value")

        let nan = SetLifecycle.correctedSetValues(
            weightLb: base.weightLb, reps: base.reps, durationSeconds: nil,
            status: base.status, correction: Correction(weightLb: .nan)
        )
        XCTAssertEqual(nan.weightLb, 195, "a non-numeric weight keeps the stored value")

        let untouched = SetLifecycle.correctedSetValues(
            weightLb: base.weightLb, reps: base.reps, durationSeconds: 45,
            status: base.status, correction: Correction()
        )
        XCTAssertEqual(untouched.weightLb, 195)
        XCTAssertEqual(untouched.reps, 5)
        XCTAssertEqual(untouched.durationSeconds, 45)
        XCTAssertEqual(untouched.status, .completed, "an empty correction changes nothing")
    }

    /// [INV-BANKED-SETS-CORRECTABLE] The status cycle is shared domain
    /// behavior — one tap must walk the same documented order on both clients
    /// (mirrors the core.test.mjs nextSetStatus block).
    func testStatusCorrectionCycleIsSharedAndOrdered() {
        XCTAssertEqual(SetLifecycle.nextCorrectionStatus(.planned), .completed)
        XCTAssertEqual(SetLifecycle.nextCorrectionStatus(.completed), .skipped)
        XCTAssertEqual(SetLifecycle.nextCorrectionStatus(.skipped), .planned)
    }
}
