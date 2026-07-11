import XCTest
@testable import CadenceCore

/// Mirrored 1:1 in web/tests/core.test.mjs ("RestClock parity") — same
/// numbers, same assertions. Change both or neither.
final class RestClockTests: XCTestCase {

    func testStartCountsDownFromTotal() {
        let s = RestClock.start(total: 180, now: 1000)
        XCTAssertEqual(s.endEpoch, 1180)
        XCTAssertFalse(s.paused)
        XCTAssertEqual(RestClock.remaining(s, now: 1000), 180)
        XCTAssertEqual(RestClock.remaining(s, now: 1005), 175)
        XCTAssertEqual(RestClock.remaining(s, now: 1300), 0, "remaining floors at 0 after the end")
    }

    func testStartClampsNegativeTotal() {
        let s = RestClock.start(total: -5, now: 1000)
        XCTAssertEqual(s.total, 0)
        XCTAssertEqual(RestClock.remaining(s, now: 1000), 0)
    }

    func testPauseFreezesRemaining() {
        var s = RestClock.start(total: 180, now: 1000)
        s = RestClock.pause(s, now: 1060)
        XCTAssertTrue(s.paused)
        XCTAssertEqual(s.pausedRemaining, 120)
        XCTAssertEqual(RestClock.remaining(s, now: 1060), 120)
        XCTAssertEqual(RestClock.remaining(s, now: 2000), 120, "paused remaining ignores the clock")
    }

    func testPauseIsIdempotent() {
        var s = RestClock.start(total: 180, now: 1000)
        s = RestClock.pause(s, now: 1060)
        let again = RestClock.pause(s, now: 2000)
        XCTAssertEqual(again, s, "second pause must not re-freeze a stale remaining")
    }

    func testResumeRestartsFromFrozenRemaining() {
        var s = RestClock.start(total: 180, now: 1000)
        s = RestClock.pause(s, now: 1060)   // 120 left
        s = RestClock.resume(s, now: 2000)
        XCTAssertFalse(s.paused)
        XCTAssertEqual(s.endEpoch, 2120)
        XCTAssertEqual(RestClock.remaining(s, now: 2000), 120)
        XCTAssertEqual(RestClock.remaining(s, now: 2060), 60)
    }

    func testResumeIsIdempotent() {
        let s = RestClock.start(total: 180, now: 1000)
        XCTAssertEqual(RestClock.resume(s, now: 1050), s)
    }

    func testAddWhileRunningMovesTheEnd() {
        var s = RestClock.start(total: 60, now: 0)
        s = RestClock.add(s, seconds: 30)
        XCTAssertEqual(s.endEpoch, 90)
        XCTAssertEqual(s.total, 90)
        XCTAssertEqual(RestClock.remaining(s, now: 10), 80)
    }

    func testAddWhilePausedMovesTheFrozenRemaining() {
        var s = RestClock.start(total: 60, now: 0)
        s = RestClock.pause(s, now: 45)     // 15 left
        s = RestClock.add(s, seconds: 30)
        XCTAssertEqual(s.pausedRemaining, 45)
        XCTAssertEqual(s.total, 90)
        XCTAssertEqual(RestClock.remaining(s, now: 500), 45)
    }

    func testNegativeAddFloorsAtZero() {
        var s = RestClock.start(total: 60, now: 0)
        s = RestClock.pause(s, now: 55)     // 5 left
        s = RestClock.add(s, seconds: -30)
        XCTAssertEqual(s.pausedRemaining, 0)
        XCTAssertEqual(s.total, 30)
    }

    func testFractionRemaining() {
        let s = RestClock.start(total: 100, now: 0)
        XCTAssertEqual(RestClock.fractionRemaining(s, now: 0), 1)
        XCTAssertEqual(RestClock.fractionRemaining(s, now: 75), 0.25)
        XCTAssertEqual(RestClock.fractionRemaining(s, now: 100), 0)
        XCTAssertEqual(RestClock.fractionRemaining(s, now: 500), 0)
        let zero = RestClock.start(total: 0, now: 0)
        XCTAssertEqual(RestClock.fractionRemaining(zero, now: 0), 0, "zero-length rest has no progress")
    }

    func testPauseResumeRoundTripPreservesTotalDuration() {
        // 3:00 rest, pause twice — the countdown must still deliver 180 real
        // seconds of rest across the interruptions.
        var s = RestClock.start(total: 180, now: 0)
        s = RestClock.pause(s, now: 30)     // 150 left, frozen
        s = RestClock.resume(s, now: 100)   // runs 100→250
        s = RestClock.pause(s, now: 200)    // 50 left
        s = RestClock.resume(s, now: 300)   // runs 300→350
        XCTAssertEqual(s.endEpoch, 350)
        XCTAssertEqual(RestClock.remaining(s, now: 300), 50)
        XCTAssertEqual(s.total, 180)
    }
}
