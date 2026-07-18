import XCTest
@testable import CadenceCore

final class BackupContractTests: XCTestCase {
    func testCurrentAndLegacyVersionsAreSupported() {
        XCTAssertTrue(BackupContract.supports(schemaVersion: nil))
        XCTAssertTrue(BackupContract.supports(schemaVersion: 0))
        XCTAssertTrue(BackupContract.supports(schemaVersion: BackupContract.currentSchemaVersion))
    }

    func testInvalidAndFutureVersionsAreRejected() {
        XCTAssertFalse(BackupContract.supports(schemaVersion: -1))
        XCTAssertFalse(BackupContract.supports(schemaVersion: BackupContract.currentSchemaVersion + 1))
    }
}
