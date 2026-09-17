import Foundation
import XCTest
@testable import CadenceCore

final class BackupContentTests: XCTestCase {
    private func matches(_ incoming: String, _ current: String) throws -> Bool {
        try BackupContract.dataMatches(incoming: Data(incoming.utf8), current: Data(current.utf8))
    }

    func testWeightAndPendingCorrectionsWithTheSameShapeAreNotIdentical() throws {
        let before = #"{"sessions":[{"exercises":[{"sets":[{"weightLb":100,"reps":5}]}]}],"programs":[{"days":[{"lifts":[{"pending":{"state":{"estimatedMaxLb":150}}}]}]}]}"#
        XCTAssertTrue(try matches(before, before))
        XCTAssertFalse(try matches(before.replacingOccurrences(of: "100", with: "95"), before))
        XCTAssertFalse(try matches(before.replacingOccurrences(of: "150", with: "140"), before))
    }

    func testEveryDataSectionParticipates() throws {
        for key in ["sessions", "programs", "gyms", "exercises", "tracks", "bodyweight",
                    "checkIns", "milestones", "coachingDecisions", "intervals", "settings"] {
            XCTAssertFalse(try matches("{\"\(key)\":[{\"value\":1}]}", "{\"\(key)\":[{\"value\":2}]}"), key)
        }
    }

    func testMetadataAndObjectKeyOrderDoNotChangeData() throws {
        XCTAssertTrue(try matches(
            #"{"schemaVersion":14,"appVersion":"native","exportedAt":"first","settings":{"a":1,"b":2}}"#,
            #"{"settings":{"b":2,"a":1},"appVersion":"web","exportedAt":"later","schemaVersion":14}"#))
    }

    func testMissingSectionsAreUntouchedButEmptySectionsAndUnknownContentAreNotEqual() throws {
        XCTAssertTrue(try matches(#"{"settings":{"theme":"slate"}}"#,
                                  #"{"settings":{"theme":"slate"},"sessions":[{"id":"one"}]}"#))
        XCTAssertFalse(try matches(#"{"sessions":[]}"#, #"{"sessions":[{"id":"one"}]}"#))
        XCTAssertFalse(try matches(#"{"schemaVersion":14}"#, #"{"sessions":[]}"#))
        XCTAssertFalse(try matches(#"{"futureSection":[]}"#, #"{"sessions":[]}"#))
    }

    func testSetOrderAndScalarTypesRemainSignificant() throws {
        XCTAssertFalse(try matches(#"{"sessions":[1,2]}"#, #"{"sessions":[2,1]}"#))
        XCTAssertFalse(try matches(#"{"settings":{"value":false}}"#, #"{"settings":{"value":0}}"#))
        XCTAssertFalse(try matches(#"{"settings":{"value":null}}"#, #"{"settings":{}}"#))
    }
}
