import XCTest
@testable import CadenceCore

/// Mirrors the cardio-format assertions in web/tests/core.test.mjs.
final class CardioFormatTests: XCTestCase {
    func testSpeed() {
        XCTAssertEqual(CardioFormat.speedMph(distanceMiles: 1.5, durationSeconds: 1350), 4.0)
        XCTAssertEqual(CardioFormat.speedMph(distanceMiles: 5, durationSeconds: 5400), 3.3, "rounded to one decimal")
        XCTAssertNil(CardioFormat.speedMph(distanceMiles: nil, durationSeconds: 1800), "no distance → no speed")
        XCTAssertNil(CardioFormat.speedMph(distanceMiles: 2, durationSeconds: nil), "no time → no speed")
        XCTAssertNil(CardioFormat.speedMph(distanceMiles: 0, durationSeconds: 0), "zeros → no speed")
    }

    func testDurationLabel() {
        XCTAssertEqual(CardioFormat.durationLabel(seconds: 1350), "22:30")
        XCTAssertEqual(CardioFormat.durationLabel(seconds: 65), "1:05")
        XCTAssertEqual(CardioFormat.durationLabel(seconds: 5400), "1:30:00", "hour-plus gets h:mm:ss")
        XCTAssertEqual(CardioFormat.durationLabel(seconds: 0), "0:00")
    }

    func testSetLabel() {
        XCTAssertEqual(CardioFormat.setLabel(distanceMiles: 1.5, durationSeconds: 1350, inclinePercent: nil),
                       "1.5 mi · 22:30 · 4 mph")
        XCTAssertEqual(CardioFormat.setLabel(distanceMiles: 3, durationSeconds: 2700, inclinePercent: 12),
                       "3 mi · 45:00 · 4 mph · 12%", "the 12-3-30 special")
        XCTAssertEqual(CardioFormat.setLabel(distanceMiles: nil, durationSeconds: 1800, inclinePercent: nil), "30:00")
        XCTAssertEqual(CardioFormat.setLabel(distanceMiles: 2, durationSeconds: nil, inclinePercent: nil), "2 mi")
        XCTAssertEqual(CardioFormat.setLabel(distanceMiles: 0.25, durationSeconds: nil, inclinePercent: nil), "0.25 mi", "quarter-mile keeps two decimals")
        XCTAssertEqual(CardioFormat.setLabel(distanceMiles: nil, durationSeconds: nil, inclinePercent: nil), "—", "nothing logged yet")
    }
}
