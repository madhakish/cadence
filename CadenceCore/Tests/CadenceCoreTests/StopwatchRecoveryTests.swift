import XCTest
@testable import CadenceCore

/// [INV-CLOCK-SURVIVES-RELAUNCH] The persisted stopwatch record's adoption
/// rule: a running record is adoptable within a day of its origin, a paused
/// record is frozen evidence and stays adoptable, and future-dated fields
/// never fabricate a stopwatch. Mirrored in web/tests/core.test.mjs.
final class StopwatchRecoveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func minutes(_ m: Double) -> TimeInterval { m * 60 }
    private func hours(_ h: Double) -> TimeInterval { h * 60 * 60 }

    func testRunningRecordWithinADayIsUsable() {
        // [INV-CLOCK-SURVIVES-RELAUNCH]
        XCTAssertTrue(StopwatchRecovery.recordUsable(
            start: now.addingTimeInterval(-minutes(40)), pausedAt: nil, now: now))
        XCTAssertTrue(StopwatchRecovery.recordUsable(
            start: now.addingTimeInterval(-hours(23.9)), pausedAt: nil, now: now))
    }

    func testRunningRecordAtOrBeyondADayIsStale() {
        // [INV-CLOCK-SURVIVES-RELAUNCH]
        XCTAssertFalse(StopwatchRecovery.recordUsable(
            start: now.addingTimeInterval(-hours(24)), pausedAt: nil, now: now))
        XCTAssertFalse(StopwatchRecovery.recordUsable(
            start: now.addingTimeInterval(-hours(24 * 7)), pausedAt: nil, now: now))
    }

    func testFutureDatedOriginNeverFabricatesAStopwatch() {
        // [INV-CLOCK-SURVIVES-RELAUNCH]
        XCTAssertFalse(StopwatchRecovery.recordUsable(
            start: now.addingTimeInterval(hours(1)), pausedAt: nil, now: now))
        XCTAssertFalse(StopwatchRecovery.recordUsable(
            start: now.addingTimeInterval(hours(1)), pausedAt: now.addingTimeInterval(hours(2)), now: now))
    }

    func testPausedRecordIsFrozenEvidenceAndOutlivesTheWindow() {
        // [INV-CLOCK-SURVIVES-RELAUNCH] Paused at 0:30 elapsed three days
        // ago: the frozen elapsed span is still exactly right.
        let start = now.addingTimeInterval(-hours(24 * 3))
        XCTAssertTrue(StopwatchRecovery.recordUsable(
            start: start, pausedAt: start.addingTimeInterval(minutes(30)), now: now))
    }

    func testPausedRecordNeedsInternalConsistency() {
        // [INV-CLOCK-SURVIVES-RELAUNCH]
        let start = now.addingTimeInterval(-hours(2))
        // A pause before the start is corrupt.
        XCTAssertFalse(StopwatchRecovery.recordUsable(
            start: start, pausedAt: start.addingTimeInterval(-minutes(5)), now: now))
        // A future-dated pause is corrupt.
        XCTAssertFalse(StopwatchRecovery.recordUsable(
            start: start, pausedAt: now.addingTimeInterval(minutes(5)), now: now))
    }
}
