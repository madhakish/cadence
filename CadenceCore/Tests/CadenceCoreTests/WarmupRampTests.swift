import XCTest
@testable import CadenceCore

final class WarmupRampTests: XCTestCase {

    func testRampFor245() {
        // bar×10 then ~40/55/70/85%: 100×5, 135×3, 170×2, 210×1.
        let ramp = WarmupRamp.ramp(workingLb: 245)
        XCTAssertEqual(ramp.map(\.weightLb), [45, 100, 135, 170, 210])
        XCTAssertEqual(ramp.map(\.reps), [10, 5, 3, 2, 1])
    }

    func testLightWorkingWeightSkipsSubBarSteps() {
        // Working 65: only the 85% step (55) clears the bar.
        let ramp = WarmupRamp.ramp(workingLb: 65)
        XCTAssertEqual(ramp.map(\.weightLb), [45, 55])
    }

    func testBarWeightWorkIsJustTheBar() {
        let ramp = WarmupRamp.ramp(workingLb: 45)
        XCTAssertEqual(ramp.map(\.weightLb), [45])
        XCTAssertEqual(ramp[0].reps, 10)
    }

    func testRampCanOmitTheEmptyBarOpener() {
        let ramp = WarmupRamp.ramp(workingLb: 245, includeEmptyBar: false)
        XCTAssertEqual(ramp.map(\.weightLb), [100, 135, 170, 210])
        XCTAssertEqual(ramp.map(\.reps), [5, 3, 2, 1])
    }

    func testRampNeverReachesWorkingWeight() {
        for working in stride(from: 50.0, through: 500.0, by: 7.5) {
            for set in WarmupRamp.ramp(workingLb: working).dropFirst() {
                XCTAssertLessThan(set.weightLb, working)
            }
        }
    }
}
