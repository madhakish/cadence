import XCTest
@testable import CadenceCore

final class BackupContractTests: XCTestCase {
    func testCurrentVersionIsV3() {
        XCTAssertEqual(BackupContract.currentSchemaVersion, 3)
    }

    func testCurrentAndLegacyVersionsAreSupported() {
        XCTAssertTrue(BackupContract.supports(schemaVersion: nil))
        XCTAssertTrue(BackupContract.supports(schemaVersion: 0))
        XCTAssertTrue(BackupContract.supports(schemaVersion: 1))
        XCTAssertTrue(BackupContract.supports(schemaVersion: 2))
        XCTAssertTrue(BackupContract.supports(schemaVersion: BackupContract.currentSchemaVersion))
    }

    func testInvalidAndFutureVersionsAreRejected() {
        XCTAssertFalse(BackupContract.supports(schemaVersion: -1))
        XCTAssertFalse(BackupContract.supports(schemaVersion: BackupContract.currentSchemaVersion + 1))
    }
}
