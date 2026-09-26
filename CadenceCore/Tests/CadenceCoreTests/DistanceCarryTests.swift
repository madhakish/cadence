import XCTest
@testable import CadenceCore

/// Loaded carries log sets of distance with a per-hand load. Mirrored in
/// web/tests/core.test.mjs ("Distance carries").
final class DistanceCarryTests: XCTestCase {

    // [INV-CARRY-LOGS-DISTANCE]
    func testRegistryAndYards() {
        for name in ["Farmer Carry", "Suitcase Carry", "Front-rack Carry", "Overhead Carry"] {
            XCTAssertTrue(CardioFormat.logsCarryDistance(exerciseName: name), "\(name) logs distance")
        }
        XCTAssertFalse(CardioFormat.logsCarryDistance(exerciseName: "Ruck"), "a ruck stays conditioning")
        XCTAssertFalse(CardioFormat.logsCarryDistance(exerciseName: "DB Curls"))
        XCTAssertEqual(CardioFormat.carryDefaultYards, 40, "a new carry set starts at 40 yd")
        XCTAssertEqual(CardioFormat.miles(fromYards: 40), 40.0 / 1760, "yards store as exact miles")
        XCTAssertEqual(CardioFormat.yards(fromMiles: CardioFormat.miles(fromYards: 40)), 40)
        XCTAssertEqual(CardioFormat.carryYards(exerciseName: "Farmer Carry",
                                               distanceMiles: CardioFormat.miles(fromYards: 40)), 40)
        XCTAssertNil(CardioFormat.carryYards(exerciseName: "Farmer Carry", distanceMiles: nil),
                     "a carry logged as reps before this existed stays a rep set")
        XCTAssertNil(CardioFormat.carryYards(exerciseName: "Walk", distanceMiles: 1),
                     "conditioning distance is not a carry distance")
        XCTAssertEqual(CardioFormat.carryDistanceLabel(yards: 40), "40 yd")
        XCTAssertEqual(CardioFormat.carryDistanceLabel(yards: 40, isPerSide: true), "40 yd / side")
    }

    func testRopesOfferNoDistance() {
        XCTAssertEqual(CardioFormat.fields(exerciseName: "Battle Ropes", flights: nil,
                                           distanceMiles: nil, inclinePercent: nil).names, ["time", "incline"])
        XCTAssertEqual(CardioFormat.fields(exerciseName: "Jump Rope", flights: nil,
                                           distanceMiles: nil, inclinePercent: nil).names, ["time", "incline"])
        XCTAssertEqual(CardioFormat.fields(exerciseName: "Jump Rope", flights: nil,
                                           distanceMiles: 0.25, inclinePercent: nil).names,
                       ["distance", "time", "speed", "incline"],
                       "a rope set already holding a distance keeps the field that can correct it")
    }

    func testImplementCountConventions() {
        func count(_ name: String, _ type: String, _ stored: Int) -> Int {
            LoadSemantics.resolvedImplementCount(stored: stored, exerciseType: type,
                                                 exerciseName: name, basis: .perImplement)
        }
        XCTAssertEqual(count("DB Overhead Triceps Extension", "dumbbell", 2), 1,
                       "one dumbbell in both hands, even on a row that stored the type default")
        XCTAssertEqual(count("DB Overhead Triceps Extension", "dumbbell", 0), 1)
        XCTAssertEqual(count("DB Overhead Triceps Extension", "dumbbell", 3), 3, "a deliberate count still wins")
        XCTAssertEqual(count("Farmer Carry", "dumbbell", 0), 2)
        XCTAssertEqual(count("Front-rack Carry", "kettlebell", 2), 2)
        XCTAssertEqual(count("Front-rack Carry", "kettlebell", 0), 2, "unset front-rack count takes the convention")
        XCTAssertEqual(count("Suitcase Carry", "dumbbell", 1), 1)
        XCTAssertEqual(count("DB Curls", "dumbbell", 0), 2, "unnamed dumbbell work keeps the type default")
        XCTAssertEqual(LoadSemantics.resolvedImplementCount(stored: 2, exerciseType: "barbell",
                                                            exerciseName: "Farmer Carry", basis: .totalBar), 1)
        // A backup keeps what the row stores; the convention is a read-time rule.
        XCTAssertEqual(LoadSemantics.backupImplementCount(stored: 0, exerciseType: "dumbbell", basis: .perImplement), 2)
        XCTAssertEqual(LoadSemantics.backupImplementCount(stored: 1, exerciseType: "dumbbell", basis: .perImplement), 1)
    }

    // [INV-CARRY-LOGS-DISTANCE]
    func testHeroStatesTheBasis() {
        XCTAssertEqual(LoadSemantics.heroLoadLabel(weightLb: 50, basis: .perImplement), "50 lb · 22.7 kg each")
        XCTAssertEqual(LoadSemantics.heroLoadLabel(weightLb: 135, basis: .totalBar), "135 lb · 61.2 kg")
        XCTAssertEqual(LoadSemantics.heroLoadLabel(weightLb: 0, basis: .perImplement), "BW")
    }

    private let farmer = SetSample(weightLb: 50, reps: 1, loadBasis: .perImplement,
                                   implementCount: 2, distanceYards: 40)

    // [INV-CARRY-LOGS-DISTANCE]
    func testTonnageIsLoadTimesYards() {
        XCTAssertEqual(LoadSemantics.carryVolume(weightLb: 50, yards: 40, isPerSide: false,
                                                 basis: .perImplement, implementCount: 2), 4_000)
        XCTAssertEqual(LoadSemantics.carryVolume(weightLb: 50, yards: 40, isPerSide: true,
                                                 basis: .perImplement, implementCount: 1), 4_000,
                       "a suitcase carry counts both sides")
        XCTAssertNil(LoadSemantics.carryVolume(weightLb: 0, yards: 40, isPerSide: false, basis: .bodyweight))
        XCTAssertEqual(PRDetection.volume([farmer, farmer]), 8_000, "carry comparison counts yards, not the placeholder rep")
    }

    // [INV-CARRY-LOGS-DISTANCE]
    func testCarryAddsNoTonnageButStillEarnsARecord() {
        XCTAssertFalse(CardioFormat.countsTowardTonnage(distanceMiles: CardioFormat.miles(fromYards: 40),
                                                        flights: nil, durationSeconds: nil),
                       "a distance carry set contributes nothing to lifting tonnage")
        XCTAssertTrue(CardioFormat.countsTowardTonnage(distanceMiles: nil, flights: nil, durationSeconds: nil),
                      "a carry logged as reps is still tonnage")
        // Same load, longer walk: the lb×yd product beats the previous best.
        let farther = SetSample(weightLb: 50, reps: 1, loadBasis: .perImplement, implementCount: 2, distanceYards: 60)
        let events = PRDetection.evaluate(exercise: "Farmer Carry", sessionSets: [farther],
                                          historySets: [farmer], historyVolumes: [4_000], historySchemes: [])
        XCTAssertEqual(events.map(\.kind), [.volumePR])
    }

    // [INV-CARRY-LOGS-DISTANCE]
    func testCarryRecordsAreHeaviestAndVolumeOnly() {
        let heavier = SetSample(weightLb: 60, reps: 1, loadBasis: .perImplement, implementCount: 2, distanceYards: 40)
        let events = PRDetection.evaluate(exercise: "Farmer Carry", sessionSets: [heavier, heavier],
                                          historySets: [farmer, farmer], historyVolumes: [8_000],
                                          historySchemes: ["2×1"])
        XCTAssertEqual(events.map(\.kind), [.heaviestSet, .volumePR])
        XCTAssertEqual(events[0].label, "60 × 40 yd — heaviest farmer carry logged")
        XCTAssertEqual(events[1].label, "Volume PR — 9600 lb·yd total farmer carry")

        let legacyRep = SetSample(weightLb: 50, reps: 5, loadBasis: .perImplement, implementCount: 2)
        let first = PRDetection.evaluate(exercise: "Farmer Carry", sessionSets: [farmer],
                                         historySets: [legacyRep], historyVolumes: [500],
                                         historySchemes: ["1×5"])
        XCTAssertEqual(first.map(\.kind), [.heaviestSet],
                       "the first distance session is not a volume record over rep tonnage, nor a new scheme")

        let legacy = PRDetection.evaluate(exercise: "Farmer Carry", sessionSets: [legacyRep],
                                          historySets: [farmer], historyVolumes: [4_000], historySchemes: [])
        XCTAssertTrue(legacy.contains { $0.kind == .firstScheme } && !legacy.contains { $0.kind == .volumePR },
                      "a rep-based carry set stays in the rep lane")
    }
}
