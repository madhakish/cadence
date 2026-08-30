import XCTest
@testable import CadenceCore

final class WoodSplittingTests: XCTestCase {
    func testWorkloadUsesMinutesTimesRPE() {
        let workload = WoodSplittingWorkload(durationSeconds: 7_200, sessionRPE: 8.5)
        XCTAssertEqual(workload?.durationMinutes, 120)
        XCTAssertEqual(workload?.arbitraryUnits, 1_020)
    }

    func testWorkloadRequiresDurationAndRPE() {
        XCTAssertNil(WoodSplittingWorkload(durationSeconds: nil, sessionRPE: 8))
        XCTAssertNil(WoodSplittingWorkload(durationSeconds: 3_600, sessionRPE: nil))
        XCTAssertNil(WoodSplittingWorkload(durationSeconds: 0, sessionRPE: 8))
        XCTAssertNil(WoodSplittingWorkload(durationSeconds: 3_600, sessionRPE: 0))
        XCTAssertNil(WoodSplittingWorkload(durationSeconds: 3_600, sessionRPE: 11))
    }
}
