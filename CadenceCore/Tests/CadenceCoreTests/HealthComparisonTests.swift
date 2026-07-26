import XCTest
@testable import CadenceCore

/// Mirrors the health-reconciliation assertions in web/tests/core.test.mjs.
final class HealthComparisonTests: XCTestCase {
    private func date(_ minutes: Double) -> Date { Date(timeIntervalSince1970: 1_780_000_000 + minutes * 60) }

    // [INV-HEALTH-IS-A-SECOND-OPINION]
    func testAgreementInsideTolerance() {
        // Two honest instruments never match exactly. A hundredth of a mile is
        // not a discrepancy worth showing a lifter.
        let verdict = HealthComparison.compare(loggedMiles: 3.0, healthMiles: 3.04)
        XCTAssertEqual(verdict, .agree(miles: 3.0))
        XCTAssertFalse(verdict.isDiscrepancy)
        XCTAssertNil(verdict.adoptableMiles, "there is nothing to adopt when they agree")
    }

    // [INV-HEALTH-IS-A-SECOND-OPINION]
    func testLongEffortsGetProportionalSlack() {
        // 2% of a ten-mile ruck is a fifth of a mile, and that is still
        // agreement — a fixed 0.05 would flag every long effort.
        XCTAssertEqual(HealthComparison.compare(loggedMiles: 10.0, healthMiles: 10.18), .agree(miles: 10.0))
        XCTAssertEqual(HealthComparison.compare(loggedMiles: 10.0, healthMiles: 10.6),
                       .healthHigher(loggedMiles: 10.0, healthMiles: 10.6),
                       "past the proportional band it is a real disagreement")
    }

    // [INV-HEALTH-IS-A-SECOND-OPINION]
    func testDisagreementNamesBothSides() {
        let higher = HealthComparison.compare(loggedMiles: 2.0, healthMiles: 2.4)
        XCTAssertEqual(higher, .healthHigher(loggedMiles: 2.0, healthMiles: 2.4))
        XCTAssertTrue(higher.isDiscrepancy)
        XCTAssertEqual(higher.adoptableMiles, 2.4)

        let lower = HealthComparison.compare(loggedMiles: 3.0, healthMiles: 2.4)
        XCTAssertEqual(lower, .loggedHigher(loggedMiles: 3.0, healthMiles: 2.4))
        XCTAssertEqual(lower.adoptableMiles, 2.4, "adopting always means taking Health's number")
    }

    // [INV-HEALTH-IS-A-SECOND-OPINION]
    func testOneSidedAndEmptyCases() {
        XCTAssertEqual(HealthComparison.compare(loggedMiles: nil, healthMiles: 2.0), .onlyHealth(miles: 2.0))
        XCTAssertEqual(HealthComparison.compare(loggedMiles: 2.0, healthMiles: nil), .onlyLogged(miles: 2.0))
        XCTAssertEqual(HealthComparison.compare(loggedMiles: nil, healthMiles: nil), .neither)
        XCTAssertEqual(HealthComparison.compare(loggedMiles: 0, healthMiles: 0), .neither, "zeros are absence")

        // An unworn watch must never read as "you logged too much".
        XCTAssertFalse(HealthComparison.compare(loggedMiles: 5.0, healthMiles: nil).isDiscrepancy)
        XCTAssertNil(HealthComparison.compare(loggedMiles: 5.0, healthMiles: nil).adoptableMiles,
                     "there is nothing in Health to adopt")
    }

    // [INV-HEALTH-IS-A-SECOND-OPINION]
    func testOverlapAndSessionMatching() {
        XCTAssertEqual(HealthComparison.overlapSeconds(
            aStart: date(0), aEnd: date(60), bStart: date(30), bEnd: date(90)), 1800)
        XCTAssertEqual(HealthComparison.overlapSeconds(
            aStart: date(0), aEnd: date(30), bStart: date(30), bEnd: date(60)), 0, "touching is not overlapping")
        XCTAssertEqual(HealthComparison.overlapSeconds(
            aStart: date(0), aEnd: date(10), bStart: date(50), bEnd: date(60)), 0, "disjoint")

        // The walk started in the car park before the app was opened.
        XCTAssertTrue(HealthComparison.sampleBelongsToSession(
            sampleStart: date(-5), sampleEnd: date(45), sessionStart: date(0), sessionEnd: date(60)))
        // The bike commute that ended as the session began.
        XCTAssertFalse(HealthComparison.sampleBelongsToSession(
            sampleStart: date(-40), sampleEnd: date(5), sessionStart: date(0), sessionEnd: date(60)))
        XCTAssertFalse(HealthComparison.sampleBelongsToSession(
            sampleStart: date(10), sampleEnd: date(10), sessionStart: date(0), sessionEnd: date(60)),
            "a zero-length sample belongs to nothing")
    }

    func testLabels() {
        XCTAssertEqual(HealthComparison.label(.agree(miles: 3)), "Health agrees: 3 mi")
        XCTAssertEqual(HealthComparison.label(.healthHigher(loggedMiles: 2, healthMiles: 2.4)),
                       "Health recorded 2.4 mi · you logged 2 mi")
        XCTAssertEqual(HealthComparison.label(.onlyLogged(miles: 2)), "Nothing in Health for this session")
        XCTAssertEqual(HealthComparison.label(.neither), "No conditioning distance")
    }
}
