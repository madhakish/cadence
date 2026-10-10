import XCTest
@testable import CadenceCore

final class HealthWorkoutTimingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private func time(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }
    private func clock() -> WorkoutClockRecord {
        WorkoutClockRecord(sessionID: "synthetic-session", start: start,
                           healthTiming: HealthWorkoutTiming(start: start))
    }

    func testResumeShiftsDisplayButNeverTheActualWorkoutStart() throws {
        // [INV-HEALTH-WORKOUT-TIMING]
        var record = clock()
        record.pause(at: time(600))
        record.resume(at: time(900))
        let export = try XCTUnwrap(record.healthTiming?.export(endingAt: time(1200)))
        XCTAssertEqual(record.start, time(300))
        XCTAssertEqual(export.start, start)
        XCTAssertEqual(export.end, time(1200))
        XCTAssertEqual(export.activeDuration, 900)
        XCTAssertEqual(export.pauses.map(\.start), [time(600)])
        XCTAssertEqual(export.pauses.map(\.end), [time(900)])
    }

    func testBankingWhilePausedEndsAtPauseAndOmitsItsUnfinishedEvent() throws {
        // [INV-HEALTH-WORKOUT-TIMING]
        var record = clock()
        record.pause(at: time(300))
        record.resume(at: time(420))
        record.pause(at: time(600))
        let export = try XCTUnwrap(record.healthTiming?.export(endingAt: time(900)))
        XCTAssertEqual(export.end, time(600))
        XCTAssertEqual(export.activeDuration, 480)
        XCTAssertEqual(export.pauses.count, 1)
    }

    func testRepeatedControlsDoNotDuplicatePauses() throws {
        var record = clock()
        record.pause(at: time(300))
        record.pause(at: time(360))
        record.resume(at: time(420))
        record.resume(at: time(480))
        XCTAssertEqual(record.start, time(120))
        XCTAssertEqual(record.healthTiming?.pauses.count, 1)
        XCTAssertEqual(record.healthTiming?.export(endingAt: time(600))?.activeDuration, 480)
    }

    func testResetResumesDisplayButKeepsActualStartAndPauseHistory() throws {
        var record = clock()
        record.pause(at: time(300))
        record.reset(at: time(420))
        record.reset(at: time(480))
        XCTAssertEqual(record.start, time(480))
        XCTAssertNil(record.pausedAt)
        let export = try XCTUnwrap(record.healthTiming?.export(endingAt: time(600)))
        XCTAssertEqual(export.start, start)
        XCTAssertEqual(export.activeDuration, 480)
    }

    func testRelaunchPreservesTimingAndPausedStopwatch() throws {
        // [INV-CLOCK-SURVIVES-RELAUNCH] [INV-HEALTH-WORKOUT-TIMING]
        var record = clock()
        record.pause(at: time(300))
        record.resume(at: time(420))
        record.pause(at: time(600))
        let restored = try JSONDecoder().decode(WorkoutClockRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(restored, record)
        XCTAssertEqual(restored.healthTiming?.export(endingAt: time(900))?.activeDuration, 480)
    }

    func testLegacyRecordRestoresStopwatchWithoutInventingExportTiming() throws {
        // [INV-CLOCK-SURVIVES-RELAUNCH] [INV-HEALTH-WORKOUT-TIMING]
        struct Legacy: Codable { let sessionID: String; let start: Date; let pausedAt: Date? }
        let bytes = try JSONEncoder().encode(Legacy(sessionID: "synthetic-session", start: time(120), pausedAt: time(600)))
        var restored = try JSONDecoder().decode(WorkoutClockRecord.self, from: bytes)
        XCTAssertEqual(restored.start, time(120))
        XCTAssertEqual(restored.pausedAt, time(600))
        XCTAssertNil(restored.healthTiming)
        restored.resume(at: time(900))
        XCTAssertEqual(restored.start, time(420))
        XCTAssertNil(restored.healthTiming)
        // An older binary can still decode every newly written record.
        let downgraded = try JSONDecoder().decode(Legacy.self, from: JSONEncoder().encode(clock()))
        XCTAssertEqual(downgraded.start, start)
    }

    func testDamagedOptionalHistoryDoesNotDestroyUsableStopwatch() throws {
        let bytes = Data(#"{"version":2,"sessionID":"synthetic-session","start":0,"healthTiming":"unknown future format"}"#.utf8)
        let record = try JSONDecoder().decode(WorkoutClockRecord.self, from: bytes)
        XCTAssertEqual(record.start, Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertNil(record.healthTiming)
    }

    func testInvalidAndZeroTimingIsNotExported() {
        XCTAssertNil(clock().healthTiming?.export(endingAt: start))
        XCTAssertNil(clock().healthTiming?.export(endingAt: time(-1)))
        var record = clock()
        record.pause(at: time(300))
        record.resume(at: time(200))
        XCTAssertNil(record.healthTiming?.export(endingAt: time(600)))
        record = clock()
        record.pause(at: time(700))
        XCTAssertNil(record.healthTiming?.export(endingAt: time(600)))
    }

    func testManyPausesStayInDurableHistoryRatherThanActivityPayload() throws {
        var record = clock()
        for offset in stride(from: 10, to: 1000, by: 10) {
            record.pause(at: time(Double(offset)))
            record.resume(at: time(Double(offset + 2)))
        }
        let restored = try JSONDecoder().decode(WorkoutClockRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(restored.healthTiming?.export(endingAt: time(1000))?.activeDuration, 802)
    }
}
