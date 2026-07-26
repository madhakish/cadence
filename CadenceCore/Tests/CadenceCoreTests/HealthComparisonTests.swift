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

    // [INV-HEALTH-IS-A-SECOND-OPINION] A read never counts Cadence's own
    // writes. Comparing the log against a mirror of itself is not a second
    // opinion — and once Cadence writes distance, bodyweight and protein into
    // Health, every read would find them without this rule.
    func testCadencesOwnSamplesAreNotASecondOpinion() {
        let app = "com.example.cadence"
        XCTAssertFalse(HealthComparison.sourceIsForeign(
            bundleIdentifier: app, appBundleIdentifier: app),
            "our own write is not a second opinion")
        XCTAssertFalse(HealthComparison.sourceIsForeign(
            bundleIdentifier: "COM.EXAMPLE.CADENCE", appBundleIdentifier: app),
            "bundle identifiers are not case sensitive")
        XCTAssertTrue(HealthComparison.sourceIsForeign(
            bundleIdentifier: "com.apple.health", appBundleIdentifier: app))
        XCTAssertTrue(HealthComparison.sourceIsForeign(
            bundleIdentifier: "com.example.cadence.watch", appBundleIdentifier: app),
            "a different bundle is a different source, prefix or not")

        // Unattributable is foreign: dropping a sample we cannot prove is ours
        // would silently discard a real second opinion, where the opposite
        // choice fails visibly the first time it offers back our own number.
        XCTAssertTrue(HealthComparison.sourceIsForeign(
            bundleIdentifier: nil, appBundleIdentifier: app))
        XCTAssertTrue(HealthComparison.sourceIsForeign(
            bundleIdentifier: "  ", appBundleIdentifier: app))
        XCTAssertTrue(HealthComparison.sourceIsForeign(
            bundleIdentifier: app, appBundleIdentifier: nil),
            "not knowing who we are cannot be read as owning everything")
    }

    // [INV-HEALTH-IS-A-SECOND-OPINION]
    func testWeighInImportIsNotOfferedForAWeightAlreadyLogged() {
        let morning = date(0)
        XCTAssertTrue(HealthComparison.isSameWeighIn(
            loggedLb: 197.2, loggedDate: morning, healthLb: 197.2, healthDate: morning))
        XCTAssertTrue(HealthComparison.isSameWeighIn(
            loggedLb: 197.2, loggedDate: morning, healthLb: 197.3, healthDate: morning),
            "a kilogram round-trip is the same weigh-in")
        XCTAssertFalse(HealthComparison.isSameWeighIn(
            loggedLb: 197.2, loggedDate: morning, healthLb: 198.6, healthDate: morning),
            "a genuinely different weight the same day stays offerable")

        // Yesterday's weight is not a duplicate of today's, however close.
        let yesterday = morning.addingTimeInterval(-60 * 60 * 30)
        XCTAssertFalse(HealthComparison.isSameWeighIn(
            loggedLb: 197.2, loggedDate: yesterday, healthLb: 197.2, healthDate: morning))
    }

    func testSleepCountsSleepAndNotTimeInBed() {
        let night: [(stage: String, seconds: Int)] = [
            ("inBed", 30 * 60), ("asleepCore", 3 * 3600), ("asleepDeep", 3600),
            ("awake", 20 * 60), ("asleepREM", 90 * 60), ("inBed", 15 * 60),
        ]
        XCTAssertEqual(HealthComparison.asleepSeconds(stages: night), 3 * 3600 + 3600 + 90 * 60)
        XCTAssertEqual(HealthComparison.asleepSeconds(stages: []), 0)
        XCTAssertEqual(HealthComparison.asleepSeconds(stages: [("inBed", 8 * 3600)]), 0,
                       "a night on the mattress with no staging is not eight hours of sleep")
        XCTAssertEqual(HealthComparison.asleepSeconds(stages: [("asleepCore", -60)]), 0)
    }

    func testLabels() {
        XCTAssertEqual(HealthComparison.label(.agree(miles: 3)), "Health agrees: 3 mi")
        XCTAssertEqual(HealthComparison.label(.healthHigher(loggedMiles: 2, healthMiles: 2.4)),
                       "Health recorded 2.4 mi · you logged 2 mi")
        XCTAssertEqual(HealthComparison.label(.onlyLogged(miles: 2)), "Nothing in Health for this session")
        XCTAssertEqual(HealthComparison.label(.neither), "No conditioning distance")
    }
}
