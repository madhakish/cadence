import XCTest
@testable import CadenceCore

final class BuildPolishTests: XCTestCase {
    func testMovementFilterIncludesSecondaryClassification() {
        XCTAssertTrue(ExerciseSearch.matchesMovement(nil, primary: .hipHinge, secondary: .squat))
        XCTAssertTrue(ExerciseSearch.matchesMovement(.hipHinge, primary: .hipHinge, secondary: .squat))
        XCTAssertTrue(ExerciseSearch.matchesMovement(.squat, primary: .hipHinge, secondary: .squat))
        XCTAssertFalse(ExerciseSearch.matchesMovement(.squat, primary: .hipHinge))
        XCTAssertFalse(ExerciseSearch.matchesMovement(.horizontalPress, primary: .hipHinge, secondary: .squat))
    }

    func testIWFChangePlateColoursDoNotAlterInventoryOrIPFSteel() {
        for (value, colour) in [(2.0, "blue"), (1.5, "yellow"), (1.0, "green"), (0.5, "white")] {
            let plate = Plate(value: value, unit: .kg)
            XCTAssertEqual(plate.colorToken(for: .bumper), colour)
            XCTAssertEqual(plate.colorToken(for: .steel), "black")
            XCTAssertFalse(Plate.allStandard.contains(plate))
        }
    }

    func testWarmupsKeepFocusUntilExplicitlyResolved() {
        var entries: [[SetStatus]] = [[.planned, .completed], [.planned], [.planned]]
        XCTAssertEqual(SetLifecycle.focusAfterResolving(entries, resolvedIndex: 0), 0)
        XCTAssertEqual(entries[0], [.planned, .completed], "focus never skips the warmup")
        entries[0][0] = .skipped
        XCTAssertEqual(SetLifecycle.focusAfterResolving(entries, resolvedIndex: 0), 1)
        entries[0][0] = .planned // undo returns focus to earlier work
        XCTAssertEqual(SetLifecycle.focusAfterResolving(entries, resolvedIndex: 0), 0)
        XCTAssertNil(SetLifecycle.focusAfterResolving(entries, resolvedIndex: -1))
        XCTAssertEqual(SetLifecycle.focusAfterResolving([[.completed], [.skipped]], resolvedIndex: 1), 1)
    }

    func testHistoryLabelsUseLocalCalendarDatesAcrossDSTAndMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let iso = ISO8601DateFormatter()
        for (before, after) in [
            ("2026-03-07T12:00:00-06:00", "2026-03-08T11:30:00-05:00"),
            ("2026-10-31T12:00:00-05:00", "2026-11-01T11:30:00-06:00"),
            ("2026-03-08T23:55:00-05:00", "2026-03-09T00:05:00-05:00")
        ] {
            XCTAssertEqual(ProgramProgression.historyProvenanceLabel(
                exposureDate: try XCTUnwrap(iso.date(from: before)),
                asOf: try XCTUnwrap(iso.date(from: after)), calendar: calendar),
                "from your last exposure, yesterday")
        }
    }
}
