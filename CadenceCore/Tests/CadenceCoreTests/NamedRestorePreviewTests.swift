import XCTest
@testable import CadenceCore

final class NamedRestorePreviewTests: XCTestCase {
    private typealias Entity = BackupContract.NamedEntity

    func testAbsentIDIsNew() {
        let diff = BackupContract.namedRestoreDiff(
            current: [],
            incoming: [Entity(id: "bench-press", name: "Bench Press", signature: "barbell")]
        )
        XCTAssertEqual(diff, [.init(name: "Bench Press", id: "bench-press", status: .new)])
    }

    func testMatchingIDNameAndSignatureIsUnchanged() {
        let diff = BackupContract.namedRestoreDiff(
            current: [Entity(id: "bench-press", name: "Bench Press", signature: "barbell")],
            incoming: [Entity(id: "bench-press", name: "Bench Press", signature: "barbell")]
        )
        XCTAssertEqual(diff, [.init(name: "Bench Press", id: "bench-press", status: .unchanged)])
    }

    func testSameIDDifferentNameIsChanged() {
        let diff = BackupContract.namedRestoreDiff(
            current: [Entity(id: "gym-1", name: "Old Gym", signature: "closest")],
            incoming: [Entity(id: "gym-1", name: "New Gym", signature: "closest")]
        )
        XCTAssertEqual(diff, [.init(name: "New Gym", id: "gym-1", status: .changed)])
    }

    func testSameIDAndNameDifferentSignatureIsChanged() {
        let diff = BackupContract.namedRestoreDiff(
            current: [Entity(id: "bench-press", name: "Bench Press", signature: "barbell")],
            incoming: [Entity(id: "bench-press", name: "Bench Press", signature: "dumbbell")]
        )
        XCTAssertEqual(diff, [.init(name: "Bench Press", id: "bench-press", status: .changed)])
    }

    // A restore clears each collection's store and re-inserts only the
    // bundle's records, so a current-only id is genuinely dropped — the
    // default behavior reports that as `removed` rather than staying silent.
    func testCurrentOnlyEntityIsRemovedByDefault() {
        let diff = BackupContract.namedRestoreDiff(
            current: [Entity(id: "squat", name: "Squat", signature: "barbell")],
            incoming: []
        )
        XCTAssertEqual(diff, [.init(name: "Squat", id: "squat", status: .removed)])
    }

    // The native exercise importer upserts by name and never deletes, so its
    // caller opts out of removal reporting rather than preview a drop that
    // will not happen.
    func testCurrentOnlyEntityIsOmittedWhenRemovalDisabled() {
        let diff = BackupContract.namedRestoreDiff(
            current: [Entity(id: "squat", name: "Squat", signature: "barbell")],
            incoming: [],
            includeRemoved: false
        )
        XCTAssertEqual(diff, [])
    }

    func testSessionRemovedWhenBundleOmitsAPreviouslyBankedSession() {
        let diff = BackupContract.namedRestoreDiff(
            current: [Entity(id: "session-1", name: "2026-01-01", signature: "2026-01-01|program-a|3")],
            incoming: []
        )
        XCTAssertEqual(diff, [.init(name: "2026-01-01", id: "session-1", status: .removed)])
    }

    func testSessionNewWhenIDIsUnseen() {
        let diff = BackupContract.namedRestoreDiff(
            current: [],
            incoming: [Entity(id: "session-2", name: "2026-02-02", signature: "2026-02-02|program-a|4")]
        )
        XCTAssertEqual(diff, [.init(name: "2026-02-02", id: "session-2", status: .new)])
    }

    func testSessionChangedWhenExerciseCountDiffers() {
        let diff = BackupContract.namedRestoreDiff(
            current: [Entity(id: "session-1", name: "2026-01-01", signature: "2026-01-01|program-a|3")],
            incoming: [Entity(id: "session-1", name: "2026-01-01", signature: "2026-01-01|program-a|4")]
        )
        XCTAssertEqual(diff, [.init(name: "2026-01-01", id: "session-1", status: .changed)])
    }

    func testSessionUnchangedWhenDateProgramAndCountMatch() {
        let diff = BackupContract.namedRestoreDiff(
            current: [Entity(id: "session-1", name: "2026-01-01", signature: "2026-01-01|program-a|3")],
            incoming: [Entity(id: "session-1", name: "2026-01-01", signature: "2026-01-01|program-a|3")]
        )
        XCTAssertEqual(diff, [.init(name: "2026-01-01", id: "session-1", status: .unchanged)])
    }

    func testProgramRemovedWhenBundleOmitsAnExistingProgram() {
        let diff = BackupContract.namedRestoreDiff(
            current: [Entity(id: "program-1", name: "5/3/1", signature: "4|8")],
            incoming: []
        )
        XCTAssertEqual(diff, [.init(name: "5/3/1", id: "program-1", status: .removed)])
    }

    func testProgramChangedWhenSlotCountDiffers() {
        let diff = BackupContract.namedRestoreDiff(
            current: [Entity(id: "program-1", name: "5/3/1", signature: "4|8")],
            incoming: [Entity(id: "program-1", name: "5/3/1", signature: "4|9")]
        )
        XCTAssertEqual(diff, [.init(name: "5/3/1", id: "program-1", status: .changed)])
    }

    func testProgramNewWhenIDIsUnseen() {
        let diff = BackupContract.namedRestoreDiff(
            current: [],
            incoming: [Entity(id: "program-2", name: "Texas Method", signature: "3|6")]
        )
        XCTAssertEqual(diff, [.init(name: "Texas Method", id: "program-2", status: .new)])
    }

    func testAllUnchangedPreviewIsNoOp() {
        let preview = BackupContract.namedRestorePreview(
            currentExercises: [Entity(id: "squat", name: "Squat", signature: "barbell")],
            incomingExercises: [Entity(id: "squat", name: "Squat", signature: "barbell")],
            currentTracks: [Entity(id: "squat", name: "Squat", signature: "cycle|1|315")],
            incomingTracks: [Entity(id: "squat", name: "Squat", signature: "cycle|1|315")],
            currentGyms: [Entity(id: "gym-1", name: "Home", signature: "closest")],
            incomingGyms: [Entity(id: "gym-1", name: "Home", signature: "closest")],
            currentSessions: [Entity(id: "session-1", name: "2026-01-01", signature: "2026-01-01|program-a|3")],
            incomingSessions: [Entity(id: "session-1", name: "2026-01-01", signature: "2026-01-01|program-a|3")],
            currentPrograms: [Entity(id: "program-1", name: "5/3/1", signature: "4|8")],
            incomingPrograms: [Entity(id: "program-1", name: "5/3/1", signature: "4|8")]
        )
        XCTAssertTrue(preview.isNoOp)
    }

    func testAnySingleChangeBreaksNoOp() {
        let preview = BackupContract.namedRestorePreview(
            currentExercises: [Entity(id: "squat", name: "Squat", signature: "barbell")],
            incomingExercises: [Entity(id: "squat", name: "Squat", signature: "barbell")],
            currentTracks: [],
            incomingTracks: [Entity(id: "deadlift", name: "Deadlift", signature: "linear|1|405")],
            currentGyms: [Entity(id: "gym-1", name: "Home", signature: "closest")],
            incomingGyms: [Entity(id: "gym-1", name: "Home", signature: "closest")],
            currentSessions: [], incomingSessions: [],
            currentPrograms: [], incomingPrograms: []
        )
        XCTAssertFalse(preview.isNoOp)
        XCTAssertEqual(preview.tracks, [.init(name: "Deadlift", id: "deadlift", status: .new)])
    }

    // A bundle that drops a previously-banked session breaks the no-op check
    // exactly like a rename would — the restore is about to delete it.
    func testRemovedSessionBreaksNoOp() {
        let preview = BackupContract.namedRestorePreview(
            currentExercises: [], incomingExercises: [],
            currentTracks: [], incomingTracks: [],
            currentGyms: [], incomingGyms: [],
            currentSessions: [Entity(id: "session-1", name: "2026-01-01", signature: "2026-01-01|program-a|3")],
            incomingSessions: [],
            currentPrograms: [], incomingPrograms: []
        )
        XCTAssertFalse(preview.isNoOp)
        XCTAssertEqual(preview.sessions, [.init(name: "2026-01-01", id: "session-1", status: .removed)])
    }

    // Deviation from the parent turn-2 design (see NamedEntityStatus doc):
    // the exercises collection now defaults to reporting removals too, since
    // its restore write also wholesale-replaces the store on web. Native's
    // own caller is the one that opts out via `includeRemovedExercises`.
    func testExercisesReportRemovalWhenIncludeRemovedExercisesDefaultsTrue() {
        let preview = BackupContract.namedRestorePreview(
            currentExercises: [Entity(id: "Squat", name: "Squat", signature: "barbell")],
            incomingExercises: [],
            currentTracks: [], incomingTracks: [],
            currentGyms: [], incomingGyms: [],
            currentSessions: [], incomingSessions: [],
            currentPrograms: [], incomingPrograms: []
        )
        XCTAssertEqual(preview.exercises, [.init(name: "Squat", id: "Squat", status: .removed)])
    }

    func testExercisesOmitRemovalWhenIncludeRemovedExercisesIsFalse() {
        let preview = BackupContract.namedRestorePreview(
            currentExercises: [Entity(id: "Squat", name: "Squat", signature: "barbell")],
            incomingExercises: [],
            currentTracks: [], incomingTracks: [],
            currentGyms: [], incomingGyms: [],
            currentSessions: [], incomingSessions: [],
            currentPrograms: [], incomingPrograms: [],
            includeRemovedExercises: false
        )
        XCTAssertEqual(preview.exercises, [])
    }
}
