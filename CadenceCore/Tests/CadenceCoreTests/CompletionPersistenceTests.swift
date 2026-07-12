import XCTest
@testable import CadenceCore

/// Mirrors the completionCommit block in web/tests/core.test.mjs — keep the
/// two in lockstep (same cases, same expectations). Regression for issue 19:
/// a failed completion save must roll back everything staged and propagate the
/// failure, and side effects must never run before a durable commit.
final class CompletionPersistenceTests: XCTestCase {

    private struct StoreDown: Error {}

    func testSuccessfulCommitNeverRollsBack() throws {
        var saves = 0, rollbacks = 0
        try CompletionPersistence.commit(
            save: { saves += 1 },
            rollback: { rollbacks += 1 }
        )
        XCTAssertEqual(saves, 1, "committed once")
        XCTAssertEqual(rollbacks, 0, "no rollback on success")
    }

    func testFailedSaveRollsBackAndRethrows() {
        var rollbacks = 0
        var sideEffects = 0
        func bankAttempt() throws {
            try CompletionPersistence.commit(
                save: { throw StoreDown() },
                rollback: { rollbacks += 1 }
            )
            sideEffects += 1   // everything after commit — HealthKit, notifications
        }
        XCTAssertThrowsError(try bankAttempt()) { error in
            XCTAssertTrue(error is StoreDown, "the underlying failure propagates to the caller")
        }
        XCTAssertEqual(rollbacks, 1, "a failed save rolls back exactly once")
        XCTAssertEqual(sideEffects, 0, "side effects after commit never run on failure")
    }

    func testRetryAfterFailureCommitsCleanly() throws {
        // The Bank button stays retryable: after a rolled-back failure, the
        // same completion committed again succeeds without a second rollback.
        var rollbacks = 0
        var storeHealthy = false
        let attempt = {
            try CompletionPersistence.commit(
                save: { if !storeHealthy { throw StoreDown() } },
                rollback: { rollbacks += 1 }
            )
        }
        XCTAssertThrowsError(try attempt())
        storeHealthy = true
        XCTAssertNoThrow(try attempt())
        XCTAssertEqual(rollbacks, 1, "only the failed attempt rolled back")
    }
}
