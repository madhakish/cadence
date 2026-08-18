import XCTest
@testable import CadenceCore

/// The program-file contract: version gate, validation, and byte-stable
/// encoding. Parity with the JavaScript mirror is enforced against the shared
/// fixture web/tests/fixtures/program-file.json — the same file the node
/// program-file suite asserts web/app/js/program-file.js produces — so either
/// side drifting fails its own CI job. Regenerate it with
/// web/tools/generate-program-file-fixture.mjs.
final class ProgramFileContractTests: XCTestCase {

    // MARK: - Builders

    private func lift(
        name: String = "Back Squat", role: String = "main", order: Int = 0,
        id: String? = nil, minimumReps: Int = 5, maximumReps: Int = 8
    ) -> ProgramFileContract.Lift {
        ProgramFileContract.Lift(
            id: id, exerciseName: name, role: role, order: order,
            prescription: "automatic", warmupPolicy: "automatic",
            loadOffsetLb: 0, peakOffsetLb: 0, deloadMultiplier: 0.775,
            doubleProgressionSets: 3, minimumReps: minimumReps, maximumReps: maximumReps,
            currentReps: 5, peakSingleEnabled: false, peakSingleIncrementLb: 5,
            phasePrimerEnabled: true, dropIncrementLb: 0, capacityManaged: true,
            maximumSets: 6, baseWeightLb: 135, estimatedMaxLb: 185
        )
    }

    private func accessory(
        name: String = "Plank", order: Int = 0, id: String? = nil,
        minReps: Int = 8, maxReps: Int = 12
    ) -> ProgramFileContract.Accessory {
        ProgramFileContract.Accessory(
            id: id, exerciseName: name, order: order, sets: 3, minReps: minReps, maxReps: maxReps,
            currentReps: 8, targetSeconds: 30, durationStepSeconds: 5, capacityManaged: true,
            maximumSets: 6, conditioningEffort: "easy", targetRPE: 0, weightLb: 0, incrementLb: 0
        )
    }

    private func program(
        name: String = "Fixture Program", days: [ProgramFileContract.Day]? = nil
    ) -> ProgramFileContract.Program {
        ProgramFileContract.Program(
            name: name, focus: "strength", roundingLb: 5, coachEnabled: true,
            preferredSessionSpacingDays: 3, maximumAddedSetsPerRotation: 6,
            days: days ?? [ProgramFileContract.Day(
                name: "Day A", order: 0, lifts: [lift()], accessories: [accessory()]
            )]
        )
    }

    private func file(_ payload: ProgramFileContract.Program? = nil) -> ProgramFileContract.File {
        ProgramFileContract.File(program: payload ?? program())
    }

    private func assertRejects(
        _ payload: ProgramFileContract.Program, _ reason: String,
        file filePath: StaticString = #filePath, line: UInt = #line
    ) {
        let candidate = ProgramFileContract.File(program: payload)
        XCTAssertThrowsError(try ProgramFileContract.validate(candidate), reason, file: filePath, line: line)
    }

    // MARK: - Version gate

    func testVersionGate() {
        XCTAssertEqual(ProgramFileContract.currentSchemaVersion, 2)
        XCTAssertEqual(ProgramFileContract.kind, "cadence.program")
        XCTAssertTrue(ProgramFileContract.supports(schemaVersion: 1))
        XCTAssertTrue(ProgramFileContract.supports(schemaVersion: 2))
        XCTAssertFalse(ProgramFileContract.supports(schemaVersion: 0))
        XCTAssertFalse(ProgramFileContract.supports(schemaVersion: 3), "a newer file is refused, not guessed at")
        XCTAssertFalse(ProgramFileContract.supports(schemaVersion: nil))
    }

    /// The program file versions independently of the backup. If these ever
    /// become coupled, a program-format change starts forcing a backup bump.
    func testProgramVersionIsIndependentOfTheBackupVersion() {
        XCTAssertNotEqual(
            ProgramFileContract.kind, "cadence.backup",
            "the discriminator keeps the two importers from accepting each other's files"
        )
        XCTAssertEqual(ProgramFileContract.currentSchemaVersion, 2,
                       "program version 2 stands on its own regardless of BackupContract v\(BackupContract.currentSchemaVersion)")
    }

    // MARK: - Acceptance

    func testValidPlanOnlyFilePasses() throws {
        XCTAssertNoThrow(try ProgramFileContract.validate(file()))
    }

    func testVersion1FileDecodesWithLiteralLegacyPolicies() throws {
        let encoded = try JSONEncoder().encode(file())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json["programSchemaVersion"] = 1
        var payload = try XCTUnwrap(json["program"] as? [String: Any])
        payload.removeValue(forKey: "equipmentPolicy")
        var days = try XCTUnwrap(payload["days"] as? [[String: Any]])
        days[0].removeValue(forKey: "trainingIntent")
        payload["days"] = days
        json["program"] = payload

        let legacy = try JSONDecoder().decode(
            ProgramFileContract.File.self,
            from: JSONSerialization.data(withJSONObject: json)
        )
        XCTAssertEqual(legacy.program.equipmentPolicy, EquipmentPolicy.any.rawValue)
        XCTAssertEqual(legacy.program.days[0].trainingIntent, DayTrainingIntent.general.rawValue)
        XCTAssertNoThrow(try ProgramFileContract.validate(legacy))
    }

    func testValidStatefulFilePasses() throws {
        var payload = program()
        payload.cycleNumber = 3
        payload.currentWeek = 2
        payload.nextDayIndex = 0   // the default fixture has one day, order 0
        payload.days[0].lifts[0].stallCount = 2
        payload.days[0].lifts[0].lastIncrementLb = 5
        payload.days[0].lifts[0].lastPeakSingleLb = 0
        payload.days[0].lifts[0].pending = ProgramFileContract.PendingResult(
            state: ProgramFileContract.PendingState(
                baseWeightLb: 140, estimatedMaxLb: 190, stallCount: 0, lastIncrementLb: 5
            ),
            note: "Clean peak — add 5 lb next cycle."
        )
        XCTAssertNoThrow(try ProgramFileContract.validate(ProgramFileContract.File(program: payload)))
        XCTAssertTrue(payload.carriesState)
    }

    func testDayWithOnlyAccessoriesIsValid() {
        let day = ProgramFileContract.Day(name: "Conditioning", order: 0, lifts: [], accessories: [accessory()])
        XCTAssertNoThrow(try ProgramFileContract.validate(file(program(days: [day]))))
    }

    func testSparseDayOrdersAreAccepted() {
        // Day order is the identity banked sessions refer to. Gaps are real
        // and must survive a round trip rather than be renumbered.
        let days = [
            ProgramFileContract.Day(name: "A", order: 0, lifts: [lift()], accessories: []),
            ProgramFileContract.Day(name: "C", order: 7, lifts: [lift()], accessories: []),
        ]
        XCTAssertNoThrow(try ProgramFileContract.validate(file(program(days: days))))
    }

    // MARK: - Rejection

    func testRejectsWrongKind() {
        var candidate = file()
        candidate.kind = "cadence.backup"
        XCTAssertThrowsError(try ProgramFileContract.validate(candidate), "a backup is not a program file")
    }

    func testRejectsUnsupportedVersion() {
        var candidate = file()
        candidate.programSchemaVersion = 99
        XCTAssertThrowsError(try ProgramFileContract.validate(candidate))
    }

    func testRejectsBlankProgramName() {
        assertRejects(program(name: "   "), "a blank name cannot key a unique program")
    }

    func testRejectsUnknownFocus() {
        var payload = program()
        payload.focus = "powerbuilding"
        assertRejects(payload, "unknown focus")
    }

    func testRejectsUnknownProgrammingPolicies() {
        var payload = program()
        payload.equipmentPolicy = "machinesOnly"
        assertRejects(payload, "unknown equipment policy")

        payload = program()
        payload.days[0].trainingIntent = "maximum"
        assertRejects(payload, "unknown day training intent")
    }

    func testRejectsEmptyDays() {
        assertRejects(program(days: []), "a program with no days is not runnable")
    }

    func testRejectsEmptyDay() {
        let day = ProgramFileContract.Day(name: "Rest", order: 0, lifts: [], accessories: [])
        assertRejects(program(days: [day]), "a day with no slots is not runnable")
    }

    func testRejectsDuplicateDayOrder() {
        let days = [
            ProgramFileContract.Day(name: "A", order: 0, lifts: [lift()], accessories: []),
            ProgramFileContract.Day(name: "B", order: 0, lifts: [lift()], accessories: []),
        ]
        assertRejects(program(days: days), "two days sharing an order make programTag.dayIndex ambiguous")
    }

    /// Slot ids are history linkage — two slots sharing one would make
    /// progression advance the wrong lift, which is the web index-derived-id
    /// failure mode. Reject rather than silently repair.
    func testRejectsDuplicateSlotIdentifiers() {
        let shared = "11111111-2222-3333-4444-555555555555"
        let day = ProgramFileContract.Day(
            name: "A", order: 0,
            lifts: [lift(id: shared)],
            accessories: [accessory(id: shared)]
        )
        assertRejects(program(days: [day]), "duplicate slot id")
    }

    func testRejectsDuplicateSlotIdentifiersAcrossDays() {
        let shared = "11111111-2222-3333-4444-555555555555"
        let days = [
            ProgramFileContract.Day(name: "A", order: 0, lifts: [lift(id: shared)], accessories: []),
            ProgramFileContract.Day(name: "B", order: 1, lifts: [lift(id: shared)], accessories: []),
        ]
        assertRejects(program(days: days), "duplicate slot id across days")
    }

    func testRejectsMalformedIdentifier() {
        let day = ProgramFileContract.Day(name: "A", order: 0, lifts: [lift(id: "not-a-uuid")], accessories: [])
        assertRejects(program(days: [day]), "a non-UUID slot id")
    }

    func testRejectsUnknownRoleAndPrescription() {
        var payload = program()
        payload.days[0].lifts[0].role = "tertiary"
        assertRejects(payload, "unknown role")

        payload = program()
        payload.days[0].lifts[0].prescription = "madeUpStyle"
        assertRejects(payload, "unknown prescription style")

        payload = program()
        payload.days[0].lifts[0].warmupPolicy = "sometimes"
        assertRejects(payload, "unknown warm-up policy")

        payload = program()
        payload.days[0].accessories[0].conditioningEffort = "brutal"
        assertRejects(payload, "unknown conditioning effort")
    }

    func testRejectsInvertedRepWindows() {
        var payload = program()
        payload.days[0].lifts[0] = lift(minimumReps: 8, maximumReps: 5)
        assertRejects(payload, "a lift whose maximum is below its minimum")

        payload = program()
        payload.days[0].accessories[0] = accessory(minReps: 12, maxReps: 8)
        assertRejects(payload, "an accessory whose maximum is below its minimum")
    }

    func testRejectsOutOfRangeNumbers() {
        var payload = program()
        payload.days[0].lifts[0].deloadMultiplier = 1.5
        assertRejects(payload, "a deload multiplier above 1 would ADD weight")

        payload = program()
        payload.days[0].lifts[0].baseWeightLb = .infinity
        assertRejects(payload, "a non-finite weight")

        payload = program()
        payload.days[0].lifts[0].baseWeightLb = .nan
        assertRejects(payload, "NaN is not a weight")

        payload = program()
        payload.days[0].lifts[0].baseWeightLb = -5
        assertRejects(payload, "a negative weight")

        payload = program()
        payload.days[0].accessories[0].maxReps = 9999
        assertRejects(payload, "an absurd rep target")

        payload = program()
        payload.roundingLb = 0
        assertRejects(payload, "a zero rounding step would divide by zero downstream")
    }

    func testRejectsOutOfRangeWaveWeek() {
        var payload = program()
        payload.cycleNumber = 1
        payload.currentWeek = 7   // the wave is 4 weeks
        payload.nextDayIndex = 0
        assertRejects(payload, "week 7 does not exist in a 4-week wave")
    }

    /// `nextDayIndex` is a day ORDER, not an array position. A pointer naming
    /// no day silently falls back to the first day, losing the wave position
    /// the file was carrying. Same rule the backup validator enforces.
    func testRejectsNextDayIndexThatNamesNoDay() {
        let days = [
            ProgramFileContract.Day(name: "A", order: 0, lifts: [lift()], accessories: []),
            ProgramFileContract.Day(name: "C", order: 2, lifts: [lift()], accessories: []),
        ]
        var payload = program(days: days)
        payload.cycleNumber = 1
        payload.currentWeek = 1
        payload.nextDayIndex = 1   // between the two real orders, but not one of them
        assertRejects(payload, "a next-day pointer that names no day")

        payload.nextDayIndex = 2
        XCTAssertNoThrow(try ProgramFileContract.validate(ProgramFileContract.File(program: payload)),
                         "a pointer naming a real day order is fine, gaps included")
    }

    /// Lift progression state is a group on BOTH clients. Checking these
    /// independently would let the same file import natively and be rejected
    /// by the PWA, which is exactly what a mirrored contract must not do.
    func testRejectsPartialLiftProgressionState() {
        var payload = program()
        payload.days[0].lifts[0].stallCount = 1
        assertRejects(payload, "stall count without the other counters")

        payload = program()
        payload.days[0].lifts[0].lastIncrementLb = 5
        payload.days[0].lifts[0].lastPeakSingleLb = 0
        assertRejects(payload, "increments without a stall count")

        payload = program()
        payload.cycleNumber = 1      // state is one decision for the whole file
        payload.currentWeek = 1
        payload.nextDayIndex = 0
        payload.days[0].lifts[0].stallCount = 1
        payload.days[0].lifts[0].lastIncrementLb = 5
        payload.days[0].lifts[0].lastPeakSingleLb = 225
        XCTAssertNoThrow(try ProgramFileContract.validate(ProgramFileContract.File(program: payload)),
                         "the complete group is accepted")
    }

    /// The stashed peak grade is applied verbatim at cycle rollover, so an
    /// unchecked value here does not fail at import — it poisons the training
    /// max weeks later. The backup importer already guards the same payload.
    func testRejectsOutOfRangePendingGrade() {
        func withPending(_ state: ProgramFileContract.PendingState) -> ProgramFileContract.Program {
            var payload = program()
            payload.cycleNumber = 1
            payload.currentWeek = 1
            payload.nextDayIndex = 0
            payload.days[0].lifts[0].stallCount = 0
            payload.days[0].lifts[0].lastIncrementLb = 0
            payload.days[0].lifts[0].lastPeakSingleLb = 0
            payload.days[0].lifts[0].pending = ProgramFileContract.PendingResult(state: state, note: nil)
            return payload
        }

        assertRejects(withPending(.init(baseWeightLb: -500, estimatedMaxLb: 200, stallCount: 0, lastIncrementLb: 5)),
                      "a negative pending base")
        assertRejects(withPending(.init(baseWeightLb: 140, estimatedMaxLb: 99999, stallCount: 0, lastIncrementLb: 5)),
                      "an absurd pending estimated max")
        assertRejects(withPending(.init(baseWeightLb: 140, estimatedMaxLb: 200, stallCount: -3, lastIncrementLb: 5)),
                      "a negative pending stall count")
        assertRejects(withPending(.init(baseWeightLb: .nan, estimatedMaxLb: 200, stallCount: 0, lastIncrementLb: 5)),
                      "a non-finite pending base")

        XCTAssertNoThrow(try ProgramFileContract.validate(ProgramFileContract.File(
            program: withPending(.init(baseWeightLb: 140, estimatedMaxLb: 190, stallCount: 0, lastIncrementLb: 5))
        )), "a sane pending grade is accepted")
    }

    /// Runtime state is one decision for the whole file. Import keys off the
    /// program's wave position, so slot counters in a file that omits it were
    /// read, accepted, and then silently zeroed.
    func testRejectsSlotStateWithoutProgramWavePosition() {
        var payload = program()
        payload.days[0].lifts[0].stallCount = 3
        payload.days[0].lifts[0].lastIncrementLb = 5
        payload.days[0].lifts[0].lastPeakSingleLb = 225
        assertRejects(payload, "slot counters with no wave position would be discarded")

        payload = program()
        payload.days[0].accessories[0].stallCount = 2
        assertRejects(payload, "an accessory counter with no wave position")

        payload = program()
        payload.days[0].lifts[0].revertToExerciseName = "Front Squat"
        assertRejects(payload, "a swap marker with no wave position")
    }

    /// Half-carried wave position would silently reposition the program in its
    /// cycle — the difference between a deload and a peak week.
    func testRejectsPartialWaveState() {
        var payload = program()
        payload.cycleNumber = 2
        assertRejects(payload, "cycle without week or day index")

        payload = program()
        payload.currentWeek = 3
        payload.nextDayIndex = 0
        assertRejects(payload, "week and day index without cycle")
    }

    // MARK: - Slot identity

    /// [INV-SLOT-ID-IS-UNIQUE] `validate` enforces slot-id uniqueness within
    /// the file, but nothing there can see the store. An identity-preserving
    /// import adopts these ids verbatim, and once two live slots share one the
    /// banked sessions pointing at it are permanently ambiguous — the
    /// launch-time repair scopes its duplicate detection to a single program,
    /// so nothing cleans it up afterwards.
    func testCollidingSlotIDsFindsIdsAlreadyLiveElsewhere() {
        let a = "aaaaaaaa-0000-4000-8000-000000000001"
        let b = "bbbbbbbb-0000-4000-8000-000000000002"
        func file(_ liftID: String, _ accessoryID: String) -> ProgramFileContract.Program {
            var payload = program()
            payload.days[0].lifts[0].id = liftID
            payload.days[0].accessories[0].id = accessoryID
            return payload
        }

        XCTAssertEqual(ProgramFileContract.slotIDs(of: file(a, b)), [a, b],
                       "[INV-SLOT-ID-IS-UNIQUE] lift and accessory ids, in document order")
        XCTAssertTrue(ProgramFileContract.slotIDs(of: program()).isEmpty,
                      "[INV-SLOT-ID-IS-UNIQUE] a plan-only file carries no slot ids")

        XCTAssertEqual(ProgramFileContract.collidingSlotIDs(file(a, b), liveElsewhere: []), [],
                       "[INV-SLOT-ID-IS-UNIQUE] disjoint ids do not collide")
        XCTAssertEqual(ProgramFileContract.collidingSlotIDs(file(a, b), liveElsewhere: [a]), [a],
                       "[INV-SLOT-ID-IS-UNIQUE] a colliding lift id is reported")
        XCTAssertEqual(ProgramFileContract.collidingSlotIDs(file(a, b), liveElsewhere: [b]), [b],
                       "[INV-SLOT-ID-IS-UNIQUE] a colliding accessory id is reported")
        XCTAssertEqual(ProgramFileContract.collidingSlotIDs(file(a, a), liveElsewhere: [a]), [a],
                       "[INV-SLOT-ID-IS-UNIQUE] one id repeated in the file is reported once")
        XCTAssertEqual(ProgramFileContract.collidingSlotIDs(file(b, a), liveElsewhere: [a, b]), [a, b],
                       "[INV-SLOT-ID-IS-UNIQUE] collisions are sorted, so the error text is stable")
        XCTAssertEqual(ProgramFileContract.collidingSlotIDs(file(a, b), liveElsewhere: ["unrelated"]), [],
                       "[INV-SLOT-ID-IS-UNIQUE] unrelated live ids are not collisions")
    }

    // MARK: - Encoding

    /// Deterministic output: sorted keys, no timestamp anywhere in the payload.
    func testEncodingIsDeterministicAndCarriesNoTimestamp() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let first = try encoder.encode(file())
        let second = try encoder.encode(file())
        XCTAssertEqual(first, second, "the same program encodes to the same bytes")

        let text = String(decoding: first, as: UTF8.self)
        XCTAssertFalse(text.contains("exportedAt"))
        XCTAssertFalse(text.contains("generatedAt"))
        XCTAssertFalse(text.contains("createdAt"))
    }

    /// A plan-only file must not leak runtime state or identity through
    /// encoded-but-null keys.
    func testPlanOnlyFileOmitsStateAndIdentity() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let text = String(decoding: try encoder.encode(file()), as: UTF8.self)
        for absent in ["stallCount", "lastIncrementLb", "lastPeakSingleLb", "pending",
                       "revertToExerciseName", "cycleNumber", "currentWeek", "nextDayIndex", "\"id\""] {
            XCTAssertFalse(text.contains(absent), "\(absent) is absent from a plan-only file")
        }
        XCTAssertFalse(text.contains("isActive"), "the active flag is never a property of the file")
    }

    func testCodableRoundTripIsLossless() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        var payload = program()
        payload.equipmentPolicy = EquipmentPolicy.freeWeightsOnly.rawValue
        payload.days[0].trainingIntent = DayTrainingIntent.heavy.rawValue
        payload.id = "11111111-2222-3333-4444-555555555555"
        payload.cycleNumber = 4
        payload.currentWeek = 3
        payload.nextDayIndex = 0
        payload.days[0].lifts[0].id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        payload.days[0].lifts[0].stallCount = 1
        payload.days[0].lifts[0].lastIncrementLb = 5
        payload.days[0].lifts[0].lastPeakSingleLb = 225
        payload.days[0].lifts[0].revertToExerciseName = "Front Squat"
        payload.days[0].lifts[0].pending = ProgramFileContract.PendingResult(
            state: .init(baseWeightLb: 140, estimatedMaxLb: 190, stallCount: 0, lastIncrementLb: 5),
            note: "Clean peak"
        )
        payload.days[0].accessories[0].id = "99999999-8888-7777-6666-555555555555"
        payload.days[0].accessories[0].stallCount = 3

        let original = ProgramFileContract.File(program: payload)
        let encoded = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(ProgramFileContract.File.self, from: encoded)
        XCTAssertEqual(decoded, original, "every field survives a round trip")
        XCTAssertEqual(try encoder.encode(decoded), encoded, "re-encoding is byte-identical")
        XCTAssertNoThrow(try ProgramFileContract.validate(decoded))
    }

    // MARK: - Shared fixture (JS parity)

    private func fixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // → CadenceCoreTests/
            .deletingLastPathComponent()   // → Tests/
            .deletingLastPathComponent()   // → CadenceCore/
            .deletingLastPathComponent()   // → repo root
            .appendingPathComponent("web/tests/fixtures/program-file.json")
    }

    /// The JavaScript exporter's output must decode into this contract without
    /// loss and re-encode to the same JSON. That is what keeps a program file
    /// written on the web readable by the app, and vice versa.
    ///
    /// Compared as parsed JSON, not as text. Foundation's `.prettyPrinted`
    /// writes `"key" : value` where `JSON.stringify` writes `"key": value`, so
    /// the two agree on every key and value but not on interior whitespace.
    /// Whitespace is not part of the contract; keys, values, and ordering are.
    /// Byte-stability *within* a platform is covered by
    /// `testEncodingIsDeterministicAndCarriesNoTimestamp`.
    func testSharedFixtureRoundTripsThroughTheSwiftContract() throws {
        let data = try Data(contentsOf: fixtureURL())
        let decoded = try JSONDecoder().decode(ProgramFileContract.File.self, from: data)
        XCTAssertNoThrow(try ProgramFileContract.validate(decoded), "the JS fixture passes Swift validation")
        XCTAssertEqual(decoded.kind, ProgramFileContract.kind)
        XCTAssertEqual(decoded.programSchemaVersion, ProgramFileContract.currentSchemaVersion)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let reencoded = try encoder.encode(decoded)

        // Deep equality over the parsed graphs: same keys, same values, no
        // field silently dropped on the way through Swift.
        let mine = try JSONSerialization.jsonObject(with: reencoded) as? NSDictionary
        let theirs = try JSONSerialization.jsonObject(with: data) as? NSDictionary
        XCTAssertNotNil(mine)
        XCTAssertNotNil(theirs)
        XCTAssertEqual(mine, theirs, "Swift re-encodes the JS fixture with identical keys and values")

        // And the decode is lossless: a second pass produces the same model.
        let again = try JSONDecoder().decode(ProgramFileContract.File.self, from: reencoded)
        XCTAssertEqual(again, decoded, "nothing is lost re-decoding Swift's own encoding of the JS file")
    }
}
