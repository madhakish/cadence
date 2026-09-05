import XCTest
@testable import CadenceCore

final class ActivityTests: XCTestCase {
    /// The kind → canonical exercise mapping is pinned on both clients
    /// (web: core.test.mjs) so the quick-log flow resolves the same seeded
    /// library row everywhere.
    func testKindsResolveCanonicalExerciseNames() {
        XCTAssertEqual(ActivityKind.allCases, [.woodSplitting],
                       "kinds are added deliberately — update both clients and the backup contract together")
        XCTAssertEqual(ActivityKind.woodSplitting.rawValue, "woodSplitting")
        XCTAssertEqual(ActivityKind.woodSplitting.exerciseName, "Wood Splitting")
    }

    /// [INV-WOOD-WORK-IS-NOT-LIFTING-VOLUME] Workload is a separate
    /// arbitrary-unit session-load value — minutes × RPE, never tonnage.
    func testWorkloadUsesMinutesTimesRPE() {
        let workload = ActivityWorkload(durationSeconds: 7_200, sessionRPE: 8.5)
        XCTAssertEqual(workload?.durationMinutes, 120)
        XCTAssertEqual(workload?.arbitraryUnits, 1_020)
    }

    /// [INV-WOOD-WORK-DOES-NOT-GUESS] A missing or out-of-contract input
    /// yields no workload, never an estimate.
    func testWorkloadRequiresDurationAndRPE() {
        XCTAssertNil(ActivityWorkload(durationSeconds: nil, sessionRPE: 8))
        XCTAssertNil(ActivityWorkload(durationSeconds: 3_600, sessionRPE: nil))
        XCTAssertNil(ActivityWorkload(durationSeconds: 0, sessionRPE: 8))
        XCTAssertNil(ActivityWorkload(durationSeconds: 3_600, sessionRPE: 0))
        XCTAssertNil(ActivityWorkload(durationSeconds: 3_600, sessionRPE: 0.5),
                     "the recorded contract is 1.0–10.0; sub-1 RPEs are invalid, not tiny workloads")
        XCTAssertNil(ActivityWorkload(durationSeconds: 3_600, sessionRPE: 11))
    }

    func testWorkloadAcceptsContractBoundsAndHalfSteps() {
        XCTAssertEqual(ActivityWorkload(durationSeconds: 60, sessionRPE: 1)?.arbitraryUnits, 1)
        XCTAssertEqual(ActivityWorkload(durationSeconds: 60, sessionRPE: 10)?.arbitraryUnits, 10)
        XCTAssertEqual(ActivityWorkload(durationSeconds: 1_800, sessionRPE: 6.5)?.arbitraryUnits, 195)
    }
}
