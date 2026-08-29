import XCTest
@testable import CadenceCore

/// Matching cases live in web/tests/core.test.mjs — same samples, same numbers.
final class TrendProjectionTests: XCTestCase {
    private func samples(_ pairs: [(Double, Double)]) -> [TrendProjection.Sample] {
        pairs.map { TrendProjection.Sample(day: $0.0, value: $0.1) }
    }

    // A history that climbed 5 lb a week projects 5 lb a week. The line is the
    // rate the lifter already walked, not a target anyone set.
    // [INV-PROJECTION-IS-THE-PERFORMED-RATE]
    func testCleanClimbProjectsItsOwnRate() throws {
        let result = try XCTUnwrap(TrendProjection.project(
            samples: samples([(0, 200), (7, 205), (14, 210), (21, 215), (28, 220)]),
            horizonDays: 30, asOfDay: 28
        ))
        XCTAssertEqual(result.perWeek, 5, accuracy: 0.0001)
        XCTAssertEqual(result.fitQuality, 1, accuracy: 0.0001)
        XCTAssertEqual(result.horizonDay, 58, accuracy: 0.0001)
        XCTAssertEqual(result.horizonValue, 241.4285714, accuracy: 0.0001)
        // Weekly steps from the last performed session, ending exactly on the
        // horizon so the line reaches the date the caption names.
        XCTAssertEqual(result.points.map(\.day), [28, 35, 42, 49, 56, 58])
        XCTAssertEqual(result.points.first?.value ?? 0, 220, accuracy: 0.0001)
        XCTAssertEqual(result.points.last?.value ?? 0, result.horizonValue, accuracy: 0.0001)
    }

    // Bad news is data. A lift that has been sliding projects the slide.
    // [INV-PROJECTION-IS-THE-PERFORMED-RATE]
    func testDeclineProjectsDownward() throws {
        let result = try XCTUnwrap(TrendProjection.project(
            samples: samples([(0, 220), (7, 215), (14, 210), (21, 205), (28, 200)]),
            horizonDays: 30, asOfDay: 28
        ))
        XCTAssertEqual(result.perWeek, -5, accuracy: 0.0001)
        XCTAssertEqual(result.horizonValue, 178.5714286, accuracy: 0.0001)
    }

    // ...but never through the floor. A steep enough slide would otherwise
    // project a negative barbell.
    // [INV-PROJECTION-IS-THE-PERFORMED-RATE]
    func testProjectionNeverGoesBelowZero() throws {
        let result = try XCTUnwrap(TrendProjection.project(
            samples: samples([(0, 100), (7, 75), (14, 50), (21, 25)]),
            horizonDays: 90, asOfDay: 21
        ))
        XCTAssertEqual(result.perWeek, -25, accuracy: 0.0001)
        XCTAssertEqual(result.horizonValue, 0, accuracy: 0.0001)
        XCTAssertTrue(result.points.allSatisfy { $0.value >= 0 })
    }

    // [INV-PROJECTION-REFUSES-THIN-HISTORY]
    func testRefusesTooFewExposures() {
        XCTAssertNil(TrendProjection.project(
            samples: samples([(0, 200), (14, 210), (28, 220)]), horizonDays: 30, asOfDay: 28
        ), "three exposures is an anecdote, not a trend")
    }

    // [INV-PROJECTION-REFUSES-THIN-HISTORY]
    func testRefusesTooShortASpan() {
        XCTAssertNil(TrendProjection.project(
            samples: samples([(0, 200), (3, 205), (7, 210), (10, 215)]), horizonDays: 30, asOfDay: 10
        ), "four sessions inside ten days say nothing about a month from now")
    }

    // [INV-PROJECTION-REFUSES-THIN-HISTORY]
    func testRefusesAStaleLift() {
        XCTAssertNil(TrendProjection.project(
            samples: samples([(0, 200), (7, 205), (14, 210), (21, 215), (28, 220)]),
            horizonDays: 30, asOfDay: 70
        ), "a lift untouched for six weeks is not on a trajectory to extend")
        // The same history one day inside the limit still projects.
        XCTAssertNotNil(TrendProjection.project(
            samples: samples([(0, 200), (7, 205), (14, 210), (21, 215), (28, 220)]),
            horizonDays: 30, asOfDay: 63
        ))
    }

    // [INV-PROJECTION-REFUSES-THIN-HISTORY]
    func testRefusesWithoutAHorizon() {
        XCTAssertNil(TrendProjection.project(
            samples: samples([(0, 200), (7, 205), (14, 210), (21, 215), (28, 220)]),
            horizonDays: 0, asOfDay: 28
        ), "the off horizon projects nothing")
    }

    // A line drawn through noise still has a slope. Reporting how badly it fits
    // is what stops that slope from reading as a finding.
    // [INV-PROJECTION-DECLARES-ITS-FIT]
    func testNoisyHistoryReportsAPoorFit() throws {
        let result = try XCTUnwrap(TrendProjection.project(
            samples: samples([(0, 200), (7, 300), (14, 200), (21, 300)]),
            horizonDays: 30, asOfDay: 21
        ))
        XCTAssertEqual(result.perWeek, 20, accuracy: 0.0001)
        XCTAssertEqual(result.fitQuality, 0.2, accuracy: 0.0001)
        XCTAssertEqual(TrendProjection.fitDescription(result.fitQuality),
                       "very noisy — treat as a guess")
    }

    // [INV-PROJECTION-DECLARES-ITS-FIT]
    func testFlatHistoryIsAPerfectFitNotADivideByZero() throws {
        let result = try XCTUnwrap(TrendProjection.project(
            samples: samples([(0, 200), (7, 200), (14, 200), (21, 200)]),
            horizonDays: 30, asOfDay: 21
        ))
        XCTAssertEqual(result.perWeek, 0, accuracy: 0.0001)
        XCTAssertEqual(result.fitQuality, 1, accuracy: 0.0001)
        XCTAssertEqual(result.horizonValue, 200, accuracy: 0.0001)
    }

    // [INV-PROJECTION-DECLARES-ITS-FIT]
    func testFitDescriptionBands() {
        XCTAssertEqual(TrendProjection.fitDescription(1), "steady trend")
        XCTAssertEqual(TrendProjection.fitDescription(0.75), "steady trend")
        XCTAssertEqual(TrendProjection.fitDescription(0.74), "rough trend")
        XCTAssertEqual(TrendProjection.fitDescription(0.4), "rough trend")
        XCTAssertEqual(TrendProjection.fitDescription(0.39), "very noisy — treat as a guess")
        XCTAssertEqual(TrendProjection.fitDescription(0), "very noisy — treat as a guess")
    }

    // The chart converts to the display unit before projecting. A linear fit
    // commutes with that scaling, so kg and lb describe the same line — the
    // projection can never disagree with itself between units.
    // [INV-PROJECTION-IS-THE-PERFORMED-RATE]
    func testProjectionCommutesWithUnitScaling() throws {
        let lb = try XCTUnwrap(TrendProjection.project(
            samples: samples([(0, 200), (7, 205), (14, 210), (21, 215), (28, 220)]),
            horizonDays: 30, asOfDay: 28
        ))
        let kg = try XCTUnwrap(TrendProjection.project(
            samples: samples([(0, 200), (7, 205), (14, 210), (21, 215), (28, 220)]
                .map { ($0.0, Weight.kg(fromLb: $0.1)) }),
            horizonDays: 30, asOfDay: 28
        ))
        XCTAssertEqual(kg.perWeek, Weight.kg(fromLb: lb.perWeek), accuracy: 0.0001)
        XCTAssertEqual(kg.horizonValue, Weight.kg(fromLb: lb.horizonValue), accuracy: 0.0001)
        XCTAssertEqual(kg.fitQuality, lb.fitQuality, accuracy: 0.0001)
    }

    // Copy always says "at this rate". The number is a continuation of the
    // past, and must never read as a promise about the future.
    // [INV-PROJECTION-IS-THE-PERFORMED-RATE]
    func testSummaryNamesTheRateAndHedgesIt() {
        XCTAssertEqual(
            TrendProjection.summary(perWeek: 5, horizonLabel: "1 month", horizonValue: "241 lb", unit: "lb"),
            "+5 lb/week · 241 lb in 1 month at this rate"
        )
        XCTAssertEqual(
            TrendProjection.summary(perWeek: -2.25, horizonLabel: "3 months", horizonValue: "180 lb", unit: "lb"),
            "−2.3 lb/week · 180 lb in 3 months at this rate"
        )
        XCTAssertEqual(
            TrendProjection.summary(perWeek: 0, horizonLabel: "1 month", horizonValue: "200 lb", unit: "lb"),
            "Holding flat · 200 lb in 1 month at this rate"
        )
        // A rate that rounds away is flat, not a vanishing "+0".
        XCTAssertEqual(
            TrendProjection.summary(perWeek: 0.04, horizonLabel: "1 month", horizonValue: "200 lb", unit: "lb"),
            "Holding flat · 200 lb in 1 month at this rate"
        )
    }

    func testHorizonsCoverOffOneMonthAndThree() {
        XCTAssertEqual(TrendProjection.Horizon.allCases.map(\.rawValue), [0, 30, 90])
        XCTAssertEqual(TrendProjection.Horizon.allCases.map(\.label), ["Off", "1 month", "3 months"])
    }

    // "Holding flat" should not also read as trustworthy when the fit behind
    // it is noise — isPlateaued adds the same fitQuality floor fitDescription
    // uses for "rough trend" on top of summary()'s rounding rule.
    // [INV-PROJECTION-DECLARES-ITS-FIT]
    func testIsPlateauedRequiresBothAZeroRoundedSlopeAndAnAdequateFit() {
        // Zero-rounded slope with an adequate fit: plateaued.
        XCTAssertTrue(TrendProjection.isPlateaued(perWeek: 0, fitQuality: 0.5))
        XCTAssertTrue(TrendProjection.isPlateaued(perWeek: 0.04, fitQuality: 1))
        // Zero-rounded slope but a fit too noisy to trust as flat: not plateaued.
        XCTAssertFalse(TrendProjection.isPlateaued(perWeek: 0, fitQuality: 0.39))
        XCTAssertFalse(TrendProjection.isPlateaued(perWeek: -0.04, fitQuality: 0))
        // Nonzero-rounded slope, either sign: never plateaued, regardless of fit.
        XCTAssertFalse(TrendProjection.isPlateaued(perWeek: 5, fitQuality: 1))
        XCTAssertFalse(TrendProjection.isPlateaued(perWeek: -5, fitQuality: 1))
        XCTAssertFalse(TrendProjection.isPlateaued(perWeek: 0.06, fitQuality: 1))
        // Boundary: fitQuality == 0.4 is inclusive, same as fitDescription's floor.
        XCTAssertTrue(TrendProjection.isPlateaued(perWeek: 0, fitQuality: 0.4))
    }
}
