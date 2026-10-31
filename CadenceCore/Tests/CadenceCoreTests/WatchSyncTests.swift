import XCTest
@testable import CadenceCore

/// Two-device session sync (design section 4–5). Every scenario checks that the
/// phone and the watch end with the same merged session.
final class WatchSyncTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var nextID = 0

    private func opID() -> String {
        nextID += 1
        return "op-\(nextID)"
    }

    private func snapshot() -> SyncSessionSnapshot {
        let bench = SyncCatalogExercise(exerciseID: "bench", name: "Bench Press")
        let row = SyncCatalogExercise(exerciseID: "row", name: "Barbell Row")
        return SyncSessionSnapshot(
            title: "Day A",
            position: SyncProgramPosition(programID: "p", cycle: 1, week: 2, dayIndex: 0),
            builtAt: t0,
            exercises: [
                SyncPlannedExercise(id: "e-bench", catalog: bench, programSlotID: "slot-bench", sets: [
                    SyncPlannedSet(id: "b1", reps: 5, weightLb: 185, plannedReps: 5, plannedWeightLb: 185),
                    SyncPlannedSet(id: "b2", reps: 5, weightLb: 185, plannedReps: 5, plannedWeightLb: 185),
                    SyncPlannedSet(id: "b3", reps: 5, weightLb: 185, plannedReps: 5, plannedWeightLb: 185),
                ]),
                SyncPlannedExercise(id: "e-row", catalog: row, sets: [
                    SyncPlannedSet(id: "r1", reps: 8, weightLb: 135),
                    SyncPlannedSet(id: "r2", reps: 8, weightLb: 135),
                ]),
            ])
    }

    /// The watch starts the session and the phone joins it.
    private func joined() -> (phone: SyncEndpoint, watch: SyncEndpoint) {
        var watch = SyncEndpoint(device: .watch)
        var phone = SyncEndpoint(device: .phone)
        let start = watch.start(sessionID: "s1", snapshot: snapshot(), operationID: opID(), now: t0)!
        XCTAssertEqual(phone.receive(start), .applied)
        return (phone, watch)
    }

    @discardableResult
    private func issue(_ endpoint: inout SyncEndpoint, _ payload: SyncPayload) -> SyncOperation {
        endpoint.issue(payload, operationID: opID(), now: t0)!
    }

    private func complete(_ set: String, reps: Int, weight: Double, as exercise: String) -> SyncPayload {
        .setPerformed(setID: set, patch: SyncSetPatch(status: .completed, reps: reps, weightLb: weight,
                                                     performedAs: exercise))
    }

    private func deliverOutbox(from sender: SyncEndpoint, to receiver: inout SyncEndpoint) {
        for op in sender.outbox { receiver.receive(op) }
    }

    private func exchange(_ a: inout SyncEndpoint, _ b: inout SyncEndpoint) {
        deliverOutbox(from: a, to: &b)
        deliverOutbox(from: b, to: &a)
    }

    private func layout(_ view: SyncSessionView) -> [String] {
        view.exercises.map { "\($0.id):" + $0.sets.map(\.id).joined(separator: ",") }
    }

    private func set(_ id: String, in view: SyncSessionView) -> SyncSessionView.Set? {
        view.exercises.flatMap(\.sets).first { $0.id == id }
    }

    // MARK: Basics

    func testThePhoneContextTravelsThroughTheWatchUnchanged() throws {
        var snap = snapshot()
        snap.phoneContext = Data([0x00, 0xFF, 0x7B, 0x22])
        var watch = SyncEndpoint(device: .watch)
        var phone = SyncEndpoint(device: .phone)
        let start = watch.start(sessionID: "s2", snapshot: snap, operationID: opID(), now: t0)!
        let wire = try JSONDecoder().decode(SyncOperation.self, from: JSONEncoder().encode(start))
        XCTAssertEqual(phone.receive(wire), .applied)
        XCTAssertEqual(phone.replica!.snapshot.phoneContext, snap.phoneContext)
    }

    func testJoiningCopiesTheStartedSession() {
        let (phone, watch) = joined()
        XCTAssertEqual(phone.replica!.view(), watch.replica!.view())
        XCTAssertEqual(layout(phone.replica!.view()), ["e-bench:b1,b2,b3", "e-row:r1,r2"])
        XCTAssertEqual(phone.replica!.startedBy, .watch)
    }

    // [INV-WATCH-SYNC-CONVERGES]
    func testRedeliveryIsANoOp() {
        var (phone, watch) = joined()
        let op = issue(&watch, complete("b1", reps: 5, weight: 185, as: "bench"))
        XCTAssertEqual(phone.receive(op), .applied)
        let before = phone.replica!.view()
        XCTAssertEqual(phone.receive(op), .duplicate)
        XCTAssertEqual(phone.replica!.view(), before)
    }

    // [INV-WATCH-SYNC-CONVERGES]
    func testOperationsDeliveredOutOfOrderWaitForTheGap() {
        var (phone, watch) = joined()
        let first = issue(&watch, .setAdded(exerciseID: "e-bench", after: "b3",
                                            set: SyncPlannedSet(id: "b4", reps: 5, weightLb: 185)))
        let second = issue(&watch, complete("b4", reps: 6, weight: 185, as: "bench"))
        XCTAssertEqual(phone.receive(second), .buffered)
        XCTAssertNil(set("b4", in: phone.replica!.view()))
        XCTAssertEqual(phone.receive(first), .applied)
        XCTAssertEqual(set("b4", in: phone.replica!.view())?.reps, 6)
        XCTAssertEqual(phone.replica!.view(), watch.replica!.view())
    }

    func testCodableRoundTripKeepsTheEndpoint() throws {
        var (phone, watch) = joined()
        issue(&watch, complete("b1", reps: 5, weight: 185, as: "bench"))
        issue(&phone, .setFlags(setID: "b1", flags: ["grindy", "rir1"]))
        exchange(&phone, &watch)
        let data = try JSONEncoder().encode(phone)
        let decoded = try JSONDecoder().decode(SyncEndpoint.self, from: data)
        XCTAssertEqual(decoded, phone)
        XCTAssertEqual(decoded.replica!.view(), watch.replica!.view())
    }

    // MARK: Per-field last writer wins

    // [INV-WATCH-SYNC-CONVERGES]
    func testConcurrentEditsToDifferentFieldsBothSurvive() {
        var (phone, watch) = joined()
        issue(&phone, .setPerformed(setID: "b2", patch: SyncSetPatch(weightLb: 175)))
        issue(&watch, .setPerformed(setID: "b2", patch: SyncSetPatch(reps: 4)))
        exchange(&phone, &watch)
        let b2 = set("b2", in: phone.replica!.view())!
        XCTAssertEqual(b2.weightLb, 175, "an edited weight never resets reps, and the reverse")
        XCTAssertEqual(b2.reps, 4)
        XCTAssertEqual(phone.replica!.view(), watch.replica!.view())
    }

    // [INV-WATCH-SYNC-CONVERGES]
    func testConcurrentEditsToOneFieldPickTheSameWinnerOnBothDevices() {
        var (phone, watch) = joined()
        issue(&phone, .setPerformed(setID: "b2", patch: SyncSetPatch(reps: 3)))
        issue(&watch, .setPerformed(setID: "b2", patch: SyncSetPatch(reps: 4)))
        exchange(&phone, &watch)
        XCTAssertEqual(phone.replica!.view(), watch.replica!.view())
    }

    // [INV-WATCH-SYNC-CONVERGES]
    func testAnEditMadeAfterSeeingAnotherWinsWhateverTheClocks() {
        var (phone, watch) = joined()
        // The phone has issued many operations, so its counter is far ahead.
        for _ in 0..<20 { issue(&phone, .setFlags(setID: "r1", flags: [])) }
        issue(&phone, .setPerformed(setID: "b1", patch: SyncSetPatch(reps: 3)))
        deliverOutbox(from: phone, to: &watch)
        // The watch corrects it after seeing it: its version passes the phone's.
        let correction = issue(&watch, .setPerformed(setID: "b1", patch: SyncSetPatch(reps: 5)))
        XCTAssertGreaterThan(correction.version, phone.clock)
        deliverOutbox(from: watch, to: &phone)
        XCTAssertEqual(set("b1", in: phone.replica!.view())?.reps, 5)
        XCTAssertEqual(phone.replica!.view(), watch.replica!.view())
    }

    func testClearingADropLoadReason() {
        var (phone, watch) = joined()
        issue(&watch, .setPerformed(setID: "b3", patch: SyncSetPatch(weightLb: 165,
                                                                     autoregReason: SyncValue(.barSpeed))))
        issue(&watch, .setPerformed(setID: "b3", patch: SyncSetPatch(autoregReason: SyncValue(nil))))
        exchange(&phone, &watch)
        XCTAssertNil(set("b3", in: phone.replica!.view())?.autoregReason)
        XCTAssertEqual(set("b3", in: phone.replica!.view())?.weightLb, 165)
    }

    // MARK: Order

    func testConcurrentInsertsAfterTheSameSetLandInTheSameOrder() {
        var (phone, watch) = joined()
        issue(&phone, .setAdded(exerciseID: "e-bench", after: "b3", set: SyncPlannedSet(id: "p4", reps: 5, weightLb: 185)))
        issue(&watch, .setAdded(exerciseID: "e-bench", after: "b3", set: SyncPlannedSet(id: "w4", reps: 5, weightLb: 185)))
        exchange(&phone, &watch)
        XCTAssertEqual(layout(phone.replica!.view()), layout(watch.replica!.view()))
        XCTAssertEqual(Array(layout(phone.replica!.view())[0].split(separator: ",").prefix(3)), ["e-bench:b1", "b2", "b3"])
    }

    // [INV-WATCH-SYNC-PERFORMED-WORK]
    func testWatchOutboxDeliveredAfterPhoneAddedAndRemovedSets() {
        var (phone, watch) = joined()
        // Apart: the watch logs bench and adds a fourth set after b3.
        issue(&watch, complete("b1", reps: 5, weight: 185, as: "bench"))
        issue(&watch, complete("b2", reps: 5, weight: 185, as: "bench"))
        issue(&watch, .setAdded(exerciseID: "e-bench", after: "b3", set: SyncPlannedSet(id: "w4", reps: 5, weightLb: 185)))
        issue(&watch, complete("w4", reps: 4, weight: 185, as: "bench"))
        // Meanwhile the phone drops the third planned set and adds a back-off after b1.
        issue(&phone, .setRemoved(setID: "b3", sawStatus: phone.replica!.statusStamp(ofSet: "b3")!))
        issue(&phone, .setAdded(exerciseID: "e-bench", after: "b1",
                                set: SyncPlannedSet(id: "p-bo", reps: 8, weightLb: 155, prescriptionBlock: .backoff)))
        // The phone's outbox reaches the watch first, then the watch's reaches the phone.
        deliverOutbox(from: phone, to: &watch)
        deliverOutbox(from: watch, to: &phone)

        let view = phone.replica!.view()
        XCTAssertEqual(view, watch.replica!.view())
        XCTAssertEqual(layout(view)[0], "e-bench:b1,p-bo,b2,w4", "b3 removed; w4 keeps its place after b3's tombstone")
        XCTAssertEqual(set("w4", in: view)?.reps, 4)
        XCTAssertEqual(view.exercises[0].sets.filter { $0.status == .completed }.count, 3)
        XCTAssertTrue(view.notice.isEmpty)
    }

    func testExerciseMovesReachTheWatch() {
        var (phone, watch) = joined()
        issue(&phone, .exerciseMoved(exerciseID: "e-row", after: nil))
        exchange(&phone, &watch)
        XCTAssertEqual(watch.replica!.view().exercises.map(\.id), ["e-row", "e-bench"])
    }

    func testOnlyThePhoneChangesTheExerciseList() {
        var (phone, watch) = joined()
        let op = issue(&watch, .exerciseMoved(exerciseID: "e-row", after: nil))
        XCTAssertEqual(phone.receive(op), .rejected("only the phone changes the exercise list"))
        XCTAssertEqual(phone.replica!.view().exercises.map(\.id), ["e-bench", "e-row"])
        XCTAssertEqual(watch.replica!.view().exercises.map(\.id), ["e-bench", "e-row"])
    }

    // MARK: Performed work is never lost

    // [INV-WATCH-SYNC-PERFORMED-WORK]
    func testPerformedWorkBeatsAConcurrentRemoval() {
        var (phone, watch) = joined()
        issue(&phone, .setRemoved(setID: "b3", sawStatus: phone.replica!.statusStamp(ofSet: "b3")!))
        issue(&watch, complete("b3", reps: 5, weight: 185, as: "bench"))
        exchange(&phone, &watch)
        let view = phone.replica!.view()
        XCTAssertEqual(view, watch.replica!.view())
        XCTAssertEqual(set("b3", in: view)?.status, .completed)
        XCTAssertEqual(set("b3", in: view)?.isReinstated, true)
        XCTAssertEqual(view.notice.reinstatedSetIDs, ["b3"])
    }

    // [INV-WATCH-SYNC-PERFORMED-WORK]
    func testRemovingASetAfterSeeingItsWorkRemovesIt() {
        var (phone, watch) = joined()
        issue(&watch, complete("b3", reps: 5, weight: 185, as: "bench"))
        exchange(&phone, &watch)
        issue(&phone, .setRemoved(setID: "b3", sawStatus: phone.replica!.statusStamp(ofSet: "b3")!))
        exchange(&phone, &watch)
        XCTAssertNil(set("b3", in: phone.replica!.view()))
        XCTAssertNil(set("b3", in: watch.replica!.view()))
    }

    // [INV-WATCH-SYNC-PERFORMED-WORK]
    func testAnEditWithoutWorkOnARemovedSetIsRejected() {
        var (phone, watch) = joined()
        let removal = issue(&phone, .setRemoved(setID: "b3", sawStatus: phone.replica!.statusStamp(ofSet: "b3")!))
        let edit = issue(&watch, .setPerformed(setID: "b3", patch: SyncSetPatch(weightLb: 175)))
        XCTAssertEqual(watch.receive(removal), .applied)
        XCTAssertEqual(phone.receive(edit), .rejected("set was removed"))
        XCTAssertNil(set("b3", in: phone.replica!.view()))
        XCTAssertEqual(phone.replica!.view().notice.rejected.map(\.operationID), [edit.id])
        XCTAssertEqual(layout(phone.replica!.view()), layout(watch.replica!.view()))
    }

    // [INV-WATCH-SYNC-PERFORMED-WORK]
    func testWorkLoggedOnARemovedExerciseKeepsIt() {
        var (phone, watch) = joined()
        issue(&phone, .exerciseRemoved(exerciseID: "e-row", sawStatus: phone.replica!.newestStatusStamp(inExercise: "e-row")!))
        issue(&watch, complete("r1", reps: 8, weight: 135, as: "row"))
        exchange(&phone, &watch)
        let view = phone.replica!.view()
        XCTAssertEqual(view, watch.replica!.view())
        XCTAssertEqual(view.exercises.map(\.id), ["e-bench", "e-row"])
        XCTAssertEqual(view.notice.reinstatedExerciseIDs, ["e-row"])
    }

    func testAnUntouchedRemovedExerciseStaysRemoved() {
        var (phone, watch) = joined()
        issue(&phone, .exerciseRemoved(exerciseID: "e-row", sawStatus: phone.replica!.newestStatusStamp(inExercise: "e-row")!))
        exchange(&phone, &watch)
        XCTAssertEqual(watch.replica!.view().exercises.map(\.id), ["e-bench"])
    }

    // [INV-WATCH-SYNC-PERFORMED-WORK]
    func testWorkPerformedBeforeAnUnseenSwapKeepsItsMovement() {
        var (phone, watch) = joined()
        // Apart: the watch completes a row set; the phone swaps rows for pull-ups
        // (it saw no completed sets, so the swap was allowed) and rebuilds the sets.
        issue(&watch, complete("r1", reps: 8, weight: 135, as: "row"))
        let pullup = SyncCatalogExercise(exerciseID: "pullup", name: "Pull-up", loadBasis: .externalTotal)
        let saw = phone.replica!.newestStatusStamp(inExercise: "e-row")!
        issue(&phone, .exerciseReplaced(exerciseID: "e-row", catalog: pullup))
        issue(&phone, .setRemoved(setID: "r1", sawStatus: saw))
        issue(&phone, .setRemoved(setID: "r2", sawStatus: saw))
        issue(&phone, .setAdded(exerciseID: "e-row", after: nil, set: SyncPlannedSet(id: "u1", reps: 6, weightLb: 0)))
        exchange(&phone, &watch)

        let view = phone.replica!.view()
        XCTAssertEqual(view, watch.replica!.view())
        XCTAssertEqual(layout(view), ["e-bench:b1,b2,b3", "e-row~row:r1", "e-row:u1"])
        XCTAssertEqual(view.exercises[1].catalog.name, "Barbell Row", "the row set is never recorded as a pull-up")
        XCTAssertTrue(view.exercises[1].isReinstated)
        XCTAssertEqual(view.exercises[2].catalog.exerciseID, "pullup")
        XCTAssertEqual(view.notice.reinstatedExerciseIDs, ["e-row~row"])
    }

    // MARK: Ending

    func testTheEndBarrierWaitsForEveryListedOperation() {
        var (phone, watch) = joined()
        let a = issue(&watch, complete("b1", reps: 5, weight: 185, as: "bench"))
        let b = issue(&watch, complete("b2", reps: 5, weight: 185, as: "bench"))
        let end = SyncSessionEnd(endedAt: t0.addingTimeInterval(3600),
                                 operationIDs: watch.unacknowledgedOperationIDs,
                                 health: .saved(workoutID: "hk-1"))
        let ended = issue(&watch, .sessionEnded(end))
        // sendMessage overtakes the queued transfers.
        XCTAssertEqual(phone.receive(ended), .buffered)
        XCTAssertFalse(phone.replica!.isReadyToBank)
        phone.receive(b)
        XCTAssertFalse(phone.replica!.isReadyToBank)
        phone.receive(a)
        XCTAssertTrue(phone.replica!.isReadyToBank)
        XCTAssertEqual(phone.replica!.view().ended?.health, .saved(workoutID: "hk-1"))
        XCTAssertEqual(phone.replica!.view().exercises[0].sets.filter { $0.status == .completed }.count, 2)
    }

    func testAcknowledgedOperationsLeaveTheOutbox() {
        var (phone, watch) = joined()
        issue(&watch, complete("b1", reps: 5, weight: 185, as: "bench"))
        issue(&watch, complete("b2", reps: 5, weight: 185, as: "bench"))
        deliverOutbox(from: watch, to: &phone)
        watch.acknowledge(phone.replica!.acknowledgement(for: .watch))
        XCTAssertTrue(watch.outbox.isEmpty)
        let late = issue(&watch, complete("b3", reps: 5, weight: 185, as: "bench"))
        XCTAssertEqual(watch.unacknowledgedOperationIDs, [late.id])
    }

    func testRestAndPausesSync() {
        var (phone, watch) = joined()
        let rest = RestClock.start(total: 120, now: t0.timeIntervalSince1970)
        issue(&watch, .restChanged(rest))
        issue(&phone, .sessionPaused(at: t0.addingTimeInterval(60)))
        issue(&phone, .sessionResumed(at: t0.addingTimeInterval(90)))
        exchange(&phone, &watch)
        XCTAssertEqual(phone.replica!.view().rest, rest)
        XCTAssertEqual(watch.replica!.view().timing.map(\.paused), [true, false])
        XCTAssertEqual(phone.replica!.view(), watch.replica!.view())
    }

    func testOperationsArrivingBeforeTheStartWait() {
        var watch = SyncEndpoint(device: .watch)
        var phone = SyncEndpoint(device: .phone)
        let start = watch.start(sessionID: "s1", snapshot: snapshot(), operationID: opID(), now: t0)!
        let edit = issue(&watch, complete("b1", reps: 5, weight: 185, as: "bench"))
        XCTAssertEqual(phone.receive(edit), .buffered)
        XCTAssertEqual(phone.receive(start), .applied)
        XCTAssertEqual(set("b1", in: phone.replica!.view())?.status, .completed)
    }

    // MARK: Convergence under any delivery order

    // [INV-WATCH-SYNC-CONVERGES]
    func testRandomDeliveryOrdersConverge() {
        for seed in 1...40 {
            var rng = SplitMix64(seed: UInt64(seed))
            var (phone, watch) = joined()
            let setIDs = ["b1", "b2", "b3", "r1", "r2"]
            var added = 0
            for step in 0..<30 {
                let onPhone = rng.next() % 2 == 0
                let target = setIDs[Int(rng.next() % UInt64(setIDs.count))]
                let payload: SyncPayload
                switch rng.next() % 6 {
                case 0:
                    payload = complete(target, reps: Int(rng.next() % 10), weight: 100 + Double(rng.next() % 100), as: target.hasPrefix("b") ? "bench" : "row")
                case 1: payload = .setPerformed(setID: target, patch: SyncSetPatch(reps: Int(rng.next() % 12)))
                case 2: payload = .setFlags(setID: target, flags: rng.next() % 2 == 0 ? ["clean"] : ["wobble", "rir2"])
                case 3:
                    added += 1
                    payload = .setAdded(exerciseID: target.hasPrefix("b") ? "e-bench" : "e-row", after: target,
                                        set: SyncPlannedSet(id: "x\(seed)-\(step)", reps: 5, weightLb: 100))
                case 4:
                    let endpoint = onPhone ? phone : watch
                    payload = .setRemoved(setID: target, sawStatus: endpoint.replica!.statusStamp(ofSet: target)!)
                default: payload = .setPerformed(setID: target, patch: SyncSetPatch(status: .skipped))
                }
                if onPhone { issue(&phone, payload) } else { issue(&watch, payload) }
            }
            // Deliver each side's operations to the other in a shuffled order.
            var toWatch = phone.outbox
            var toPhone = watch.outbox
            toWatch.shuffle(using: &rng)
            toPhone.shuffle(using: &rng)
            for op in toWatch { watch.receive(op) }
            for op in toPhone { phone.receive(op) }
            let p = phone.replica!.view()
            let w = watch.replica!.view()
            XCTAssertEqual(layout(p), layout(w), "seed \(seed)")
            XCTAssertEqual(p.exercises, w.exercises, "seed \(seed)")
            XCTAssertTrue(phone.replica!.pending.isEmpty && watch.replica!.pending.isEmpty, "seed \(seed)")
        }
    }

    // MARK: Session rules

    func testDuplicateStartsMatchBankedAndPassedPositions() {
        let day = SyncProgramPosition(programID: "p", cycle: 1, week: 2, dayIndex: 1)
        XCTAssertTrue(SyncSessionRules.duplicatesBankedWork(day, bankedPositions: [day], programNow: day))
        XCTAssertTrue(SyncSessionRules.duplicatesBankedWork(
            day, bankedPositions: [], programNow: SyncProgramPosition(programID: "p", cycle: 1, week: 2, dayIndex: 2)))
        XCTAssertFalse(SyncSessionRules.duplicatesBankedWork(day, bankedPositions: [], programNow: day))
        XCTAssertFalse(SyncSessionRules.duplicatesBankedWork(
            day, bankedPositions: [], programNow: SyncProgramPosition(programID: "other", cycle: 9, week: 9, dayIndex: 9)))
    }

    func testTheWatchWritesHealthOnlyWithConsentConfirmedDuringTheSession() {
        let start = t0
        XCTAssertFalse(SyncSessionRules.watchMaySaveWorkout(sessionStartedAt: start, latestSetting: nil))
        XCTAssertFalse(SyncSessionRules.watchMaySaveWorkout(
            sessionStartedAt: start, latestSetting: SyncHealthSetting(enabled: true, receivedAt: start.addingTimeInterval(-60))),
            "a setting cached before the session is not consent")
        XCTAssertTrue(SyncSessionRules.watchMaySaveWorkout(
            sessionStartedAt: start, latestSetting: SyncHealthSetting(enabled: true, receivedAt: start)))
        XCTAssertFalse(SyncSessionRules.watchMaySaveWorkout(
            sessionStartedAt: start, latestSetting: SyncHealthSetting(enabled: false, receivedAt: start.addingTimeInterval(60))))
    }

    func testThePhoneExportsOnlyWhenTheWatchWroteNothing() {
        XCTAssertTrue(SyncSessionRules.phoneMayExportAtBank(watchOutcome: nil))
        XCTAssertTrue(SyncSessionRules.phoneMayExportAtBank(watchOutcome: .notWritten))
        XCTAssertFalse(SyncSessionRules.phoneMayExportAtBank(watchOutcome: .saved(workoutID: "hk")))
        XCTAssertFalse(SyncSessionRules.phoneMayExportAtBank(watchOutcome: .unknown),
                       "an ambiguous finish is never retried")
    }
}

/// Deterministic generator so failures name a reproducible seed.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
