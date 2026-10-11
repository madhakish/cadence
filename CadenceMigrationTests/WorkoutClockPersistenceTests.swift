import CadenceCore
import Foundation
import XCTest

/// Production storage, isolated from all app defaults and HealthKit.
/// [INV-HEALTH-WORKOUT-TIMING] [INV-CLOCK-TEARDOWN-IS-SCOPED]
final class WorkoutClockPersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var start: Date!

    override func setUp() {
        suite = "synthetic.workout-clock.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        // Usable running origins relative to the production 24-hour guard.
        start = Date().addingTimeInterval(-3600)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func time(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }
    private func record(_ id: String = "synthetic-session") -> WorkoutClockRecord {
        WorkoutClockRecord(sessionID: id, start: start,
                           healthTiming: HealthWorkoutTiming(start: start))
    }
    private func seed(_ record: WorkoutClockRecord) {
        XCTAssertNotNil(WorkoutClockPersistence.adopt(record, replacing: nil, defaults: defaults))
    }

    func testRecoveryDoesNotOverwriteAnIntentPauseBetweenReadAndAdopt() throws {
        let original = record()
        seed(original)
        let observed = WorkoutClockPersistence.load(defaults: defaults)
        _ = WorkoutClockPersistence.update(for: original.sessionID, defaults: defaults) { $0.pause(at: time(300)) }
        let adopted = try XCTUnwrap(WorkoutClockPersistence.adopt(original, replacing: observed, defaults: defaults))
        XCTAssertEqual(adopted.pausedAt, time(300))
        XCTAssertEqual(adopted.healthTiming?.export(endingAt: time(600))?.activeDuration, 300)
    }

    func testRecoveryDoesNotResurrectAClearedClockOrReplaceANewerOwner() {
        let original = record()
        seed(original)
        let observed = WorkoutClockPersistence.load(defaults: defaults)
        WorkoutClockPersistence.clear(for: original.sessionID, defaults: defaults)
        XCTAssertNil(WorkoutClockPersistence.adopt(original, replacing: observed, defaults: defaults))
        seed(record("another-synthetic-session"))
        XCTAssertNil(WorkoutClockPersistence.adopt(original, replacing: observed, defaults: defaults))
        XCTAssertEqual(WorkoutClockPersistence.load(defaults: defaults)?.sessionID, "another-synthetic-session")
    }

    func testLateIntentDoesNotResurrectAClearedDurableRecord() {
        let original = record()
        seed(original)
        WorkoutClockPersistence.clear(for: original.sessionID, defaults: defaults)
        let face = WorkoutClockPersistence.update(for: original.sessionID, recovering: original, defaults: defaults) {
            $0.pause(at: time(300))
        }
        XCTAssertEqual(face?.pausedAt, time(300))
        XCTAssertNil(WorkoutClockPersistence.load(defaults: defaults))
    }

    func testLegacyIntentFirstAdoptsItsOldActivityThenPromotesDurableAuthority() throws {
        struct V1: Codable { let sessionID: String; let start: Date; let pausedAt: Date? }
        let original = V1(sessionID: "synthetic-session", start: start, pausedAt: nil)
        defaults.set(try JSONEncoder().encode(original), forKey: "workoutClockState")
        XCTAssertTrue(try XCTUnwrap(WorkoutClockPersistence.load(defaults: defaults)).isLegacy)
        // Shipped V1 paused only the activity; its stored record is stale.
        let pausedFace = WorkoutClockRecord(sessionID: original.sessionID, start: start, pausedAt: time(300))
        let resumed = try XCTUnwrap(WorkoutClockPersistence.update(
            for: original.sessionID, recovering: pausedFace, defaults: defaults) { $0.resume(at: time(420)) })
        XCTAssertEqual(resumed.start, time(120))
        XCTAssertNil(resumed.pausedAt)
        XCTAssertNil(resumed.healthTiming)
        XCTAssertFalse(try XCTUnwrap(WorkoutClockPersistence.load(defaults: defaults)).isLegacy)
        // A stale ActivityKit face cannot replace the now-authoritative V2.
        let again = WorkoutClockPersistence.update(for: original.sessionID, recovering: pausedFace, defaults: defaults) {
            $0.resume(at: time(480))
        }
        XCTAssertEqual(again?.start, time(120))
        XCTAssertNil(again?.pausedAt)
    }

    func testWrongSessionIntentAndClearLeaveCurrentOwnerIntact() {
        let original = record()
        seed(original)
        let other = record("another-synthetic-session")
        XCTAssertNil(WorkoutClockPersistence.update(for: other.sessionID, recovering: other, defaults: defaults) {
            $0.pause(at: time(300))
        })
        WorkoutClockPersistence.clear(for: other.sessionID, defaults: defaults)
        XCTAssertEqual(WorkoutClockPersistence.load(defaults: defaults), original)
    }
}
