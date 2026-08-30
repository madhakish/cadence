import XCTest
@testable import CadenceCore

final class WoodSplittingTests: XCTestCase {
    /// [INV-WOOD-WORK-IS-NOT-LIFTING-VOLUME] Workload is a separate
    /// arbitrary-unit session-load value — minutes × RPE, never tonnage.
    func testWorkloadUsesMinutesTimesRPE() {
        let workload = WoodSplittingWorkload(durationSeconds: 7_200, sessionRPE: 8.5)
        XCTAssertEqual(workload?.durationMinutes, 120)
        XCTAssertEqual(workload?.arbitraryUnits, 1_020)
    }

    /// [INV-WOOD-WORK-DOES-NOT-GUESS] A missing or out-of-contract input
    /// yields no workload, never an estimate.
    func testWorkloadRequiresDurationAndRPE() {
        XCTAssertNil(WoodSplittingWorkload(durationSeconds: nil, sessionRPE: 8))
        XCTAssertNil(WoodSplittingWorkload(durationSeconds: 3_600, sessionRPE: nil))
        XCTAssertNil(WoodSplittingWorkload(durationSeconds: 0, sessionRPE: 8))
        XCTAssertNil(WoodSplittingWorkload(durationSeconds: 3_600, sessionRPE: 0))
        XCTAssertNil(WoodSplittingWorkload(durationSeconds: 3_600, sessionRPE: 0.5),
                     "the recorded contract is 1.0–10.0; sub-1 RPEs are invalid, not tiny workloads")
        XCTAssertNil(WoodSplittingWorkload(durationSeconds: 3_600, sessionRPE: 11))
    }

    func testWorkloadAcceptsContractBoundsAndHalfSteps() {
        XCTAssertEqual(WoodSplittingWorkload(durationSeconds: 60, sessionRPE: 1)?.arbitraryUnits, 1)
        XCTAssertEqual(WoodSplittingWorkload(durationSeconds: 60, sessionRPE: 10)?.arbitraryUnits, 10)
        XCTAssertEqual(WoodSplittingWorkload(durationSeconds: 1_800, sessionRPE: 6.5)?.arbitraryUnits, 195)
    }
}
