import XCTest
@testable import CadenceCore

/// Same cases as web/tests/hold-timer.test.mjs.
final class HoldClockTests: XCTestCase {
    func testContinuousAttemptAndWholeSeconds() throws {
        let clock = try XCTUnwrap(HoldClock.start(seconds: 30, now: 1000))
        XCTAssertEqual(HoldClock.remaining(clock, now: 1000), 30)
        XCTAssertEqual(HoldClock.remaining(clock, now: 1000.2), 30)
        XCTAssertEqual(HoldClock.loggedSeconds(clock, now: 1012.9), 12)
        let stopped = HoldClock.stop(clock, now: 1012.9)
        XCTAssertEqual(HoldClock.loggedSeconds(stopped, now: 2000), 12)
        XCTAssertEqual(HoldClock.stop(stopped, now: 2000), stopped)
        XCTAssertEqual(HoldClock.remaining(stopped, now: 2000), 18)
    }

    func testBackgroundExpirationIsCappedAndNotRoundedUp() throws {
        let clock = try XCTUnwrap(HoldClock.start(seconds: 30, now: 1000))
        XCTAssertEqual(HoldClock.remaining(clock, now: 1029.9), 1)
        XCTAssertEqual(HoldClock.loggedSeconds(clock, now: 1029.9), 29)
        XCTAssertEqual(HoldClock.remaining(clock, now: 4000), 0)
        XCTAssertEqual(HoldClock.loggedSeconds(clock, now: 4000), 30)
        XCTAssertEqual(HoldClock.loggedSeconds(clock, now: 900), 0)
    }

    func testInvalidTargetsAndIndependentRest() throws {
        for seconds in [-1, 0, 1801] { XCTAssertNil(HoldClock.start(seconds: seconds, now: 1000)) }
        XCTAssertNil(HoldClock.start(seconds: 30, now: .nan))
        let rest = RestClock.start(total: 90, now: 1000)
        let hold = try XCTUnwrap(HoldClock.start(seconds: 30, now: 1000))
        _ = HoldClock.stop(hold, now: 1012)
        XCTAssertEqual(RestClock.remaining(rest, now: 1012), 78)
    }
}
