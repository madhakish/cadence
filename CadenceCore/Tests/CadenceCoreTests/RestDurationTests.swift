import XCTest
@testable import CadenceCore

final class RestDurationTests: XCTestCase {
    func testExactEntryAndVisibleNormalization() {
        for (h, m, s, expected) in [("0", "0", "0", 0), ("0", "0", "1", 1),
                                     ("0", "1", "37", 97), ("0", "0", "90", 90),
                                     ("0", "59", "59", 3599), ("1", "0", "0", 3600),
                                     ("", "60", "", 3600)] {
            XCTAssertEqual(RestDuration.parse(hours: h, minutes: m, seconds: s), expected)
        }
        XCTAssertEqual(RestDuration.label(90), "00:01:30")
        XCTAssertEqual(RestDuration.label(3600), "01:00:00")
        for invalid in ["-1", "1.5", "1e2", "NaN", "abc", "9999999999999999999999"] {
            XCTAssertNil(RestDuration.parse(hours: "0", minutes: "0", seconds: invalid))
        }
        XCTAssertNil(RestDuration.parse(hours: "1", minutes: "0", seconds: "1"))
        XCTAssertEqual(RestDuration.maximumSeconds, 3600)
    }

    func testSteppingSnapsToTheQuarterMinuteAndStaysInRange() {
        for (start, up, expected) in [(90, true, 105), (90, false, 75), (97, true, 105), (97, false, 90),
                                      (0, false, 0), (10, false, 0), (3600, true, 3600), (3590, true, 3600),
                                      (-5, true, 15), (4000, false, 3585)] {
            XCTAssertEqual(RestDuration.stepped(start, up: up), expected, "\(start) \(up ? "+" : "-")")
        }
        XCTAssertEqual(RestDuration.presets, [60, 90, 120, 180, 240, 300])
        XCTAssertTrue(RestDuration.presets.allSatisfy { (1...RestDuration.maximumSeconds).contains($0) })
    }

    func testEditingRemainingPreservesElapsedAndPauseWithoutRevivingExpiredRest() throws {
        let clock = RestClock.start(total: 300, now: 100)
        let updated = try XCTUnwrap(RestClock.settingRemaining(clock, seconds: 97, now: 200))
        XCTAssertEqual(RestClock.remaining(updated, now: 200), 97)
        XCTAssertEqual(updated.total, 197) // 100 elapsed, 97 remaining
        let paused = RestClock.pause(clock, now: 200)
        let edited = try XCTUnwrap(RestClock.settingRemaining(paused, seconds: 30, now: 900))
        XCTAssertTrue(edited.paused)
        XCTAssertEqual(RestClock.remaining(edited, now: 1000), 30)
        XCTAssertNil(RestClock.settingRemaining(clock, seconds: 30, now: 400))
        XCTAssertNil(RestClock.settingRemaining(paused, seconds: 0, now: 900))
    }
}
