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

    // [INV-CARDIO-SOLVES-THE-THIRD]
    func testDistanceFromSpeedAndTime() {
        // The treadmill case: 3.5 mph for half an hour is 1.75 miles, and the
        // lifter should never have to work that out on the belt.
        XCTAssertEqual(CardioFormat.distanceMiles(speedMph: 3.5, durationSeconds: 1800), 1.75)
        XCTAssertEqual(CardioFormat.distanceMiles(speedMph: 4, durationSeconds: 1350), 1.5)
        XCTAssertEqual(CardioFormat.distanceMiles(speedMph: 3.7, durationSeconds: 1020), 1.05,
                       "rounded to the two decimals a treadmill reports")
        XCTAssertNil(CardioFormat.distanceMiles(speedMph: nil, durationSeconds: 1800), "no speed → no distance")
        XCTAssertNil(CardioFormat.distanceMiles(speedMph: 3.5, durationSeconds: nil), "no time → no distance")
        XCTAssertNil(CardioFormat.distanceMiles(speedMph: 0, durationSeconds: 0), "zeros → no distance")
    }

    // [INV-CARDIO-SOLVES-THE-THIRD]
    func testDurationFromDistanceAndSpeed() {
        XCTAssertEqual(CardioFormat.durationSeconds(distanceMiles: 1.75, speedMph: 3.5), 1800)
        XCTAssertEqual(CardioFormat.durationSeconds(distanceMiles: 1.5, speedMph: 4), 1350)
        XCTAssertNil(CardioFormat.durationSeconds(distanceMiles: nil, speedMph: 3.5), "no distance → no time")
        XCTAssertNil(CardioFormat.durationSeconds(distanceMiles: 2, speedMph: nil), "no speed → no time")
        XCTAssertNil(CardioFormat.durationSeconds(distanceMiles: 0, speedMph: 0), "zeros → no time")
    }

    // [INV-CARDIO-SOLVES-THE-THIRD]
    func testSolvingIsSelfConsistent() {
        // Whichever two the logger was given, the third must agree with the
        // pair it came from. Only distance and duration persist, so a distance
        // computed from speed has to read back as that same speed or the
        // history would quietly disagree with what the lifter set on the belt.
        for mph in [2.5, 3.0, 3.5, 4.0, 5.5, 6.0, 7.5] {
            for minutes in [10, 15, 20, 30, 45, 60] {
                let secs = minutes * 60
                guard let miles = CardioFormat.distanceMiles(speedMph: mph, durationSeconds: secs) else {
                    return XCTFail("\(mph) mph for \(minutes)m should yield a distance")
                }
                XCTAssertEqual(CardioFormat.speedMph(distanceMiles: miles, durationSeconds: secs), mph,
                               accuracy: 0.05, "\(mph) mph for \(minutes)m read back as a different pace")
                XCTAssertEqual(CardioFormat.durationSeconds(distanceMiles: miles, speedMph: mph) ?? 0,
                               secs, accuracy: 30, "\(mph) mph over \(miles) mi read back as a different time")
            }
        }
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
                       "3 mi · 45:00 · 4 mph · 12%", "fictional full-field fixture")
        XCTAssertEqual(CardioFormat.setLabel(distanceMiles: nil, durationSeconds: 1800, inclinePercent: nil), "30:00")
        XCTAssertEqual(CardioFormat.setLabel(distanceMiles: 2, durationSeconds: nil, inclinePercent: nil), "2 mi")
        XCTAssertEqual(CardioFormat.setLabel(distanceMiles: 0.25, durationSeconds: nil, inclinePercent: nil), "0.25 mi", "quarter-mile keeps two decimals")
        XCTAssertEqual(CardioFormat.setLabel(distanceMiles: nil, durationSeconds: nil, inclinePercent: nil), "—", "nothing logged yet")
    }
}
