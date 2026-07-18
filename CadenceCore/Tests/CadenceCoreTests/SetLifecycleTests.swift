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
}
