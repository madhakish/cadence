import XCTest
@testable import CadenceCore

/// Mirrored 1:1 with the interval helper cases in web/tests/core.test.mjs —
/// the two clients must read the same declared break the same way.
final class TrainingIntervalsTests: XCTestCase {
    private let day: Double = 86_400_000

    private func snapshot(_ kind: TrainingIntervalKind, _ startDay: Double, _ endDay: Double) -> TrainingIntervalSnapshot {
        TrainingIntervalSnapshot(kind: kind, startMs: startDay * day, endMs: endDay * day + day - 1)
    }

    func testContainsIsInclusiveOfBothDayBounds() {
        let rest = snapshot(.rest, 10, 12)
        XCTAssertTrue(TrainingIntervals.contains(rest, 10 * day))
        XCTAssertTrue(TrainingIntervals.contains(rest, 12 * day + day - 1))
        XCTAssertFalse(TrainingIntervals.contains(rest, 10 * day - 1))
        XCTAssertFalse(TrainingIntervals.contains(rest, 13 * day))
    }

    func testInvertedRangeCollapsesToItsStart() {
        let inverted = TrainingIntervalSnapshot(kind: .rest, startMs: 5 * day, endMs: 2 * day)
        XCTAssertEqual(inverted.endMs, 5 * day)
        XCTAssertTrue(TrainingIntervals.contains(inverted, 5 * day))
        XCTAssertFalse(TrainingIntervals.contains(inverted, 3 * day))
    }

    func testInsideFiltersByKind() {
        let intervals = [snapshot(.deload, 1, 3), snapshot(.away, 5, 8)]
        XCTAssertTrue(TrainingIntervals.inside(2 * day, intervals: intervals))
        XCTAssertTrue(TrainingIntervals.inside(2 * day, intervals: intervals, kinds: [.deload]))
        XCTAssertFalse(TrainingIntervals.inside(2 * day, intervals: intervals, kinds: [.away]))
        XCTAssertFalse(TrainingIntervals.inside(4 * day, intervals: intervals))
    }

    func testDeloadDoesNotExcuseAbsenceButTheOtherKindsDo() {
        // [INV-INTERVAL-KINDS-STAY-DISTINCT] deload days still expect sessions.
        XCTAssertFalse(TrainingIntervals.absenceExcusingKinds.contains(.deload))
        for kind in [TrainingIntervalKind.rest, .away, .activeRecovery] {
            XCTAssertTrue(TrainingIntervals.absenceExcusingKinds.contains(kind))
        }
        let deloadOnly = [snapshot(.deload, 10, 14)]
        XCTAssertFalse(TrainingIntervals.gapExcused(fromMs: 9 * day, toMs: 15 * day, intervals: deloadOnly))
    }

    func testGapExcusedByAnyOverlapWithAnExcusingInterval() {
        // [INV-INTERVAL-IS-NOT-A-GAP]
        let away = [snapshot(.away, 10, 14)]
        // Fully covering, partially overlapping at either edge, and contained.
        XCTAssertTrue(TrainingIntervals.gapExcused(fromMs: 9 * day, toMs: 15 * day, intervals: away))
        XCTAssertTrue(TrainingIntervals.gapExcused(fromMs: 13 * day, toMs: 20 * day, intervals: away))
        XCTAssertTrue(TrainingIntervals.gapExcused(fromMs: 5 * day, toMs: 11 * day, intervals: away))
        XCTAssertTrue(TrainingIntervals.gapExcused(fromMs: 11 * day, toMs: 12 * day, intervals: away))
        // Disjoint gap, and an inverted/empty gap, are never excused.
        XCTAssertFalse(TrainingIntervals.gapExcused(fromMs: 20 * day, toMs: 25 * day, intervals: away))
        XCTAssertFalse(TrainingIntervals.gapExcused(fromMs: 15 * day, toMs: 15 * day, intervals: away))
        XCTAssertFalse(TrainingIntervals.gapExcused(fromMs: 15 * day, toMs: 9 * day, intervals: away))
    }

    func testOffProgramTimeIsActiveRecoveryOnly() {
        // [INV-RECOVERY-WORK-IS-OFF-PROGRAM] only activeRecovery makes banked
        // work off-program; rest/away days have no sessions to bank and a
        // session logged inside one is deliberate, ordinary training.
        let intervals = [snapshot(.activeRecovery, 10, 14), snapshot(.rest, 20, 22)]
        XCTAssertTrue(TrainingIntervals.isOffProgramTime(12 * day, intervals: intervals))
        XCTAssertFalse(TrainingIntervals.isOffProgramTime(21 * day, intervals: intervals))
        XCTAssertFalse(TrainingIntervals.isOffProgramTime(15 * day, intervals: intervals))
    }

    func testRecentReturnFromAwayFindsTheNewestQualifyingInterval() {
        let intervals = [snapshot(.away, 10, 14), snapshot(.away, 20, 24), snapshot(.rest, 26, 27)]
        let now = 27 * day
        // No session since either away span: the NEWEST one wins.
        let hit = TrainingIntervals.recentReturnFromAway(nowMs: now, lastSessionMs: 5 * day, intervals: intervals)
        XCTAssertEqual(hit?.startMs, 20 * day)
        // A session banked after the away span ended clears the suggestion.
        XCTAssertNil(TrainingIntervals.recentReturnFromAway(nowMs: now, lastSessionMs: 26 * day, intervals: intervals))
        // No sessions at all still counts as "not banked since".
        XCTAssertNotNil(TrainingIntervals.recentReturnFromAway(nowMs: now, lastSessionMs: nil, intervals: intervals))
        // Outside the window the return is old news.
        XCTAssertNil(TrainingIntervals.recentReturnFromAway(
            nowMs: 24 * day + day - 1 + 8 * day, lastSessionMs: nil, intervals: [snapshot(.away, 20, 24)]
        ))
        // Rest intervals never trigger a re-entry suggestion.
        XCTAssertNil(TrainingIntervals.recentReturnFromAway(nowMs: 28 * day, lastSessionMs: nil, intervals: [snapshot(.rest, 26, 27)]))
        // A still-open away span is not a return yet.
        XCTAssertNil(TrainingIntervals.recentReturnFromAway(nowMs: 22 * day, lastSessionMs: nil, intervals: [snapshot(.away, 20, 24)]))
    }

    func testDaysByKindReturnsAllFourKindsZeroedWhenAbsent() {
        let result = TrainingIntervals.daysByKind(intervals: [snapshot(.rest, 10, 12)], sinceMs: 0, untilMs: 30 * day + day - 1)
        XCTAssertEqual(result[.rest], 3)
        XCTAssertEqual(result[.deload], 0)
        XCTAssertEqual(result[.away], 0)
        XCTAssertEqual(result[.activeRecovery], 0)
    }

    func testDaysByKindMergesOverlappingSameKindIntervalsWithoutDoubleCounting() {
        // Two overlapping rest spans covering days 10-12 and 11-15 share days
        // 11-12 — the merged span is 10-15, six days, not nine.
        let intervals = [snapshot(.rest, 10, 12), snapshot(.rest, 11, 15)]
        let result = TrainingIntervals.daysByKind(intervals: intervals, sinceMs: 0, untilMs: 30 * day + day - 1)
        XCTAssertEqual(result[.rest], 6)
    }

    func testDaysByKindClampsAnIntervalPartiallyOutsideTheWindow() {
        // The interval runs days 5-20, but the window only opens on day 10.
        let intervals = [snapshot(.away, 5, 20)]
        let result = TrainingIntervals.daysByKind(intervals: intervals, sinceMs: 10 * day, untilMs: 20 * day + day - 1)
        XCTAssertEqual(result[.away], 11)
    }

    func testDaysByKindIsAllZeroForEmptyIntervalsOrAZeroWidthWindow() {
        XCTAssertEqual(TrainingIntervals.daysByKind(intervals: [], sinceMs: 0, untilMs: 30 * day), [
            .deload: 0, .rest: 0, .away: 0, .activeRecovery: 0,
        ])
        let intervals = [snapshot(.deload, 1, 3)]
        XCTAssertEqual(TrainingIntervals.daysByKind(intervals: intervals, sinceMs: 5 * day, untilMs: 5 * day), [
            .deload: 0, .rest: 0, .away: 0, .activeRecovery: 0,
        ])
    }

    func testDaysByKindKeepsDifferentKindsSeparateOnAnOverlappingDay() {
        // A deload span and an away span overlap on day 12: each kind counts
        // its own days, they never merge into a single "break" total
        // (INV-INTERVAL-KINDS-STAY-DISTINCT).
        let intervals = [snapshot(.deload, 10, 12), snapshot(.away, 12, 14)]
        let result = TrainingIntervals.daysByKind(intervals: intervals, sinceMs: 0, untilMs: 30 * day + day - 1)
        XCTAssertEqual(result[.deload], 3)
        XCTAssertEqual(result[.away], 3)
    }
}
