import XCTest
@testable import CadenceCore

final class WatchWireTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private var settings: WatchSettings {
        WatchSettings(accessoryRestSeconds: 90, secondaryRestSeconds: 180, mainUpperRestSeconds: 180,
                      mainCompoundRestSeconds: 300, autoStartRest: true, haptics: true, unit: "lb",
                      healthKitEnabled: false)
    }

    func testEveryMessageRoundTripsThroughAPropertyListDictionary() throws {
        let snapshot = SyncSessionSnapshot(title: "Day A", position: nil, builtAt: t0, exercises: [],
                                           phoneContext: Data([1, 2, 3]))
        let op = SyncOperation(id: "op-1", sessionID: "s", device: .watch, seq: 1, version: 1, timestamp: t0,
                               payload: .sessionStarted(snapshot))
        let messages: [WatchWire] = [
            .operations([op]),
            .ack(SyncAck(sessionID: "s", device: .watch, throughSeq: 4)),
            .plan(WatchPlan(next: snapshot, settings: settings, sentAt: t0)),
            .requestPlan,
            .join(sessionID: "s"),
        ]
        for message in messages {
            let dictionary = try message.dictionary()
            XCTAssertTrue(PropertyListSerialization.propertyList(dictionary, isValidFor: .binary),
                          "WatchConnectivity only carries property-list values")
            XCTAssertEqual(WatchWire.decode(dictionary), message)
        }
        XCTAssertNil(WatchWire.decode(["something": "else"]))
    }

    func testAPlanBuiltOnAnEarlierDayIsStale() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let plan = WatchPlan(next: SyncSessionSnapshot(title: "Day A", position: nil, builtAt: t0, exercises: []),
                             settings: settings, sentAt: t0)
        XCTAssertFalse(plan.isStale(now: t0.addingTimeInterval(3600), calendar: calendar))
        XCTAssertTrue(plan.isStale(now: t0.addingTimeInterval(86_400 * 2), calendar: calendar))
        XCTAssertFalse(WatchPlan(next: nil, settings: settings, sentAt: t0).isStale(now: t0.addingTimeInterval(86_400 * 9)))
    }

    func testRestFollowsTheEntryRole() {
        XCTAssertEqual(settings.restSeconds(forRole: "main"), 300)
        XCTAssertEqual(settings.restSeconds(forRole: "secondary"), 180)
        XCTAssertEqual(settings.restSeconds(forRole: nil), 90)
    }
}
