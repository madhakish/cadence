import XCTest
@testable import CadenceCore

final class BackupContractTests: XCTestCase {
    /// Deliberately a literal, so bumping the contract is never accidental —
    /// this test is meant to fail and be updated by hand. The name is
    /// version-free on purpose: it said "V4" while asserting 5.
    ///
    /// Must stay in lockstep with `BACKUP_SCHEMA_VERSION` in web/app/js/db.js.
    func testCurrentVersionIsPinned() {
        XCTAssertEqual(BackupContract.currentSchemaVersion, 10)
    }

    func testCurrentAndLegacyVersionsAreSupported() {
        XCTAssertTrue(BackupContract.supports(schemaVersion: nil))
        XCTAssertTrue(BackupContract.supports(schemaVersion: 0))
        XCTAssertTrue(BackupContract.supports(schemaVersion: 1))
        XCTAssertTrue(BackupContract.supports(schemaVersion: 2))
        // 5 is the last version that carried protein. A v5 bundle still
        // imports — its protein is dropped on the way in, which is a lossy
        // read, not a rejection.
        XCTAssertTrue(BackupContract.supports(schemaVersion: 5))
        XCTAssertTrue(BackupContract.supports(schemaVersion: 6),
                      "a pre-flights bundle still restores, with no count anywhere")
        XCTAssertTrue(BackupContract.supports(schemaVersion: 7),
                      "a pre-station bundle still restores; every lift solves on the gym inventory")
        XCTAssertTrue(BackupContract.supports(schemaVersion: 8),
                      "a pre-policy bundle restores with any/general legacy behavior")
        XCTAssertTrue(BackupContract.supports(schemaVersion: 9),
                      "a pre-intervals bundle restores; declared breaks stay untouched and bars stay stamped")
        XCTAssertTrue(BackupContract.supports(schemaVersion: BackupContract.currentSchemaVersion))
    }

    func testInvalidAndFutureVersionsAreRejected() {
        XCTAssertFalse(BackupContract.supports(schemaVersion: -1))
        XCTAssertFalse(BackupContract.supports(schemaVersion: BackupContract.currentSchemaVersion + 1))
    }
}
