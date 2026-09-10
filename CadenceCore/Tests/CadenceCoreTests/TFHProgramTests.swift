import XCTest
@testable import CadenceCore

final class TFHProgramTests: XCTestCase {
    private var policy: TFHProgramPolicy {
        TFHProgramPolicy(id: "cohort", startCycle: 3, dayOrders: [0,1,2,3], recoveryDayOrders: [0,1],
            anchors: ["slot": TFHAnchor(id: "anchor", exerciseId: "exercise", weightLb: 60,
                reps: [3,3,3], minReps: 3, maxReps: 5, incrementLb: 5, loadBasis: .perImplement, implementCount: 2)],
            layout: ["slot":"0:main:0"])
    }
    func testThreeBuildRotationsAndTwoCompletedRecoverySessions() {
        var completions: [TFHCompletion] = []
        for rotation in 1...3 {
            for day in 0...3 {
                let next = TFHSchedule.position(policy: policy, completions: completions)
                XCTAssertEqual(next?.rotation, rotation); XCTAssertEqual(next?.dayOrder, day)
                completions.append(TFHCompletion(cycle: 3, rotation: rotation, dayOrder: day))
            }
        }
        XCTAssertEqual(TFHSchedule.position(policy: policy, completions: completions)?.rotation, 4)
        completions.append(TFHCompletion(cycle: 3, rotation: 4, dayOrder: 0))
        XCTAssertEqual(TFHSchedule.position(policy: policy, completions: completions)?.rotation, 4)
        completions.append(TFHCompletion(cycle: 3, rotation: 4, dayOrder: 1))
        XCTAssertEqual(TFHSchedule.position(policy: policy, completions: completions)?.cycle, 4)
        XCTAssertEqual(TFHSchedule.position(policy: policy, completions: completions)?.completedCycles, [3])
        completions.remove(at: 0)
        XCTAssertEqual(TFHSchedule.position(policy: policy, completions: completions)?.cycle, 3)
        XCTAssertEqual(TFHSchedule.position(policy: policy, completions: completions)?.rotation, 1)
        completions.append(completions[0])
        XCTAssertNil(TFHSchedule.position(policy: policy, completions: completions))
    }
    func testPortablePolicyRejectsInvalidRangeAndBenchmarkEvidence() throws {
        let bytes = try JSONEncoder().encode(policy)
        XCTAssertEqual(try JSONDecoder().decode(TFHProgramPolicy.self, from: bytes), policy)
        var invalid = policy; invalid.recoveryDayOrders = [0]
        XCTAssertFalse(invalid.isValid)
        XCTAssertFalse(TFHBenchmarkResult(restSeconds: .infinity).isValid)
        XCTAssertFalse(TFHBenchmarkResult(restSeconds: 0).isValid)
        XCTAssertTrue(TFHBenchmarkResult().isValid, "missing evidence stays unknown")
    }
    func testDeliberateLoadAdjustmentIsNotReplacedByTheOldTarget() throws {
        let anchor = try XCTUnwrap(policy.anchors["slot"])
        let adjusted = TFHExposure(id: "adjusted", anchorId: anchor.id, exerciseId: anchor.exerciseId,
            cycle: 3, rotation: 1, sets: (0..<3).map { _ in
                TFHSet(weightLb: 50, reps: 3, plannedWeightLb: 60, plannedReps: 3,
                       loadBasis: .perImplement, implementCount: 2, quality: "clean")
            })
        let plan = TFHProgression.project(anchor: anchor, exposures: [adjusted], cycle: 3, rotation: 2)
        XCTAssertEqual(plan?.weightLb, 50); XCTAssertEqual(plan?.reps, [3,3,3])
        XCTAssertEqual(plan?.state, "hold")
    }

    func testOldMatchingPhasesCannotUndoARepeatedManualAdjustment() throws {
        let anchor = try XCTUnwrap(policy.anchors["slot"])
        func exposure(_ cycle: Int, _ rotation: Int, actual: Double, planned: Double) -> TFHExposure {
            TFHExposure(id: "\(cycle)-\(rotation)", anchorId: anchor.id, exerciseId: anchor.exerciseId,
                cycle: cycle, rotation: rotation, sets: (0..<3).map { _ in
                    TFHSet(weightLb: actual, reps: 3, plannedWeightLb: planned, plannedReps: 3,
                           loadBasis: .perImplement, implementCount: 2, quality: "clean")
                })
        }
        var history = [exposure(3, 1, actual: 60, planned: 60),
                       exposure(3, 2, actual: 50, planned: 60),
                       exposure(3, 3, actual: 50, planned: 50)]
        XCTAssertEqual(TFHProgression.project(anchor: anchor, exposures: history, cycle: 4, rotation: 1)?.weightLb, 50)
        history.append(exposure(4, 1, actual: 50, planned: 50))
        XCTAssertEqual(TFHProgression.project(anchor: anchor, exposures: history, cycle: 4, rotation: 2)?.weightLb, 50)
    }
}
