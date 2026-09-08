import XCTest
@testable import CadenceCore

final class TFHProgressionTests: XCTestCase {
    private var anchor: TFHAnchor {
        TFHAnchor(id: "anchor", exerciseId: "exercise", weightLb: 42, reps: [3,3,3,3],
                  minReps: 3, maxReps: 5, incrementLb: 5,
                  loadBasis: .perImplement, implementCount: 2, benchmarkEnabled: true)
    }
    private func exposure(_ cycle: Int, _ rotation: Int, reps: [Int] = [3,3,3,3]) -> TFHExposure {
        TFHExposure(id: "\(cycle)-\(rotation)", anchorId: "anchor", exerciseId: "exercise",
                    cycle: cycle, rotation: rotation, sets: reps.enumerated().map { i, reps in
            TFHSet(weightLb: 42, reps: reps, plannedWeightLb: 42, plannedReps: 3,
                   loadBasis: .perImplement, implementCount: 2, quality: "clean",
                   benchmark: rotation == 3 && i == 3, stopReason: "technicalLimit", restSeconds: 180)
        }, context: "same preceding work")
    }
    private var history: [TFHExposure] {
        (1...3).flatMap { cycle in (1...3).map { exposure(cycle, $0) } }
    }

    func testStartingShapeAndOneTotalRep() throws {
        let empty = try XCTUnwrap(TFHProgression.project(anchor: anchor, exposures: [], cycle: 1, rotation: 1))
        XCTAssertEqual(empty.reps, anchor.reps)
        let next = try XCTUnwrap(TFHProgression.project(anchor: anchor, exposures: [exposure(1,1)], cycle: 1, rotation: 2))
        XCTAssertEqual(next.weightLb, 42)
        XCTAssertEqual(next.reps.reduce(0,+), 13)
        XCTAssertEqual(TFHProgression.project(anchor: anchor, exposures: [exposure(1,1,reps:[2,2,2,2])],
                                             cycle: 1, rotation: 2)?.reps, anchor.reps)
    }

    func testRecoveryAndAmbiguousHistory() throws {
        let recovery = try XCTUnwrap(TFHProgression.project(anchor: anchor, exposures: [], cycle: 1, rotation: 4))
        XCTAssertFalse(recovery.benchmark)
        XCTAssertLessThan(recovery.reps.count, anchor.reps.count)
        XCTAssertEqual(TFHProgression.project(anchor: anchor, exposures: [exposure(1,4)], cycle: 2, rotation: 1)?.reps, anchor.reps)
        let duplicates = [exposure(1,1), exposure(1,1)]
        XCTAssertNil(TFHProgression.project(anchor: anchor, exposures: duplicates, cycle: 1, rotation: 2))
        XCTAssertNil(TFHProgression.project(anchor: anchor, exposures: duplicates, cycle: 1, rotation: 4))
        var adjusted = exposure(2,1)
        adjusted.sets[0].plannedReps = 2
        XCTAssertNil(TFHProgression.project(anchor: anchor, exposures: [adjusted], cycle: 2, rotation: 2))
    }

    func testBodyweightAndMaintenanceDoNotBecomeLoadIncreases() {
        var bw = anchor
        bw.weightLb = 0; bw.incrementLb = 0; bw.loadBasis = .bodyweight
        bw.implementCount = 1; bw.reps = [6,6]; bw.minReps = 4; bw.maxReps = 6
        XCTAssertEqual(TFHProgression.project(anchor: bw, exposures: [], cycle: 1, rotation: 1)?.weightLb, 0)
        XCTAssertEqual(TFHProgression.project(anchor: bw, exposures: [], cycle: 1, rotation: 1)?.reps, [6,6])
        var maintaining = anchor
        maintaining.intent = .maintain
        XCTAssertEqual(TFHProgression.project(anchor: maintaining, exposures: history, cycle: 4, rotation: 1)?.reps, anchor.reps)
        XCTAssertEqual(TFHProgression.plateau(anchor: maintaining, exposures: history, completedCycles: [1,2,3], currentCycle: 4).state, "notAssessing")
    }

    func testPlateauRequiresBaselineThenTwoCompleteCycles() {
        XCTAssertEqual(TFHProgression.plateau(anchor: anchor, exposures: history, completedCycles: [1,2], currentCycle: 3).state, "learning")
        XCTAssertEqual(TFHProgression.plateau(anchor: anchor, exposures: history, completedCycles: [1,2,3], currentCycle: 4).state, "possiblePlateau")
        var improved = history
        improved[8].sets[3].reps += 1
        XCTAssertEqual(TFHProgression.plateau(anchor: anchor, exposures: improved, completedCycles: [1,2,3], currentCycle: 4).state, "progressing")
    }

    func testUnknownOrChangedBenchmarkContextCannotProvePlateau() {
        for stop in [nil, "repCap"] as [String?] {
            var capped = history
            for e in capped.indices { for s in capped[e].sets.indices { capped[e].sets[s].stopReason = stop } }
            XCTAssertEqual(TFHProgression.plateau(anchor: anchor, exposures: capped, completedCycles: [1,2,3], currentCycle: 4).state, "learning")
        }
        var changed = history
        for e in changed.indices { changed[e].context = "different-\(changed[e].cycle)" }
        XCTAssertEqual(TFHProgression.plateau(anchor: anchor, exposures: changed, completedCycles: [1,2,3], currentCycle: 4).state, "learning")
    }

    func testDifficultExposureRetainsCurrentTargetsAndFutureWorkIsExcluded() {
        var difficult = exposure(2,1,reps:[4,4,4,4])
        for i in difficult.sets.indices {
            difficult.sets[i].weightLb = 47; difficult.sets[i].plannedWeightLb = 47
            difficult.sets[i].plannedReps = 4; difficult.sets[i].quality = "grindy"
        }
        let plan = TFHProgression.project(anchor: anchor, exposures: [difficult], cycle: 2, rotation: 2)
        XCTAssertEqual(plan?.weightLb, 47); XCTAssertEqual(plan?.reps, [4,4,4,4])
        XCTAssertEqual(TFHProgression.project(anchor: anchor, exposures: [exposure(3,1)], cycle: 2, rotation: 1)?.weightLb, 42)
    }

    func testLoadStepRequiresLatestConsecutiveMatchingPhases() {
        var loaded = anchor
        loaded.weightLb = 101; loaded.reps = [5,5,5,5]
        func top(_ cycle: Int, clean: Bool = true) -> TFHExposure {
            var e = exposure(cycle,1,reps:[5,5,5,5])
            for i in e.sets.indices {
                e.sets[i].weightLb = 101; e.sets[i].plannedWeightLb = 101
                e.sets[i].plannedReps = 5; e.sets[i].quality = clean ? "clean" : "grindy"
            }
            return e
        }
        XCTAssertEqual(TFHProgression.project(anchor: loaded, exposures: [top(1),top(2)], cycle: 3, rotation: 1)?.weightLb,106)
        XCTAssertEqual(TFHProgression.project(anchor: loaded, exposures: [top(1),top(2),top(3,clean:false),top(4)], cycle: 5, rotation: 1)?.weightLb,101)
        XCTAssertEqual(TFHProgression.project(anchor: loaded, exposures: [top(1),top(3)], cycle: 4, rotation: 1)?.weightLb,101)
    }

    func testLatestDifficultWorkAndPracticeDoNotEarnBenchmarks() {
        var difficult = exposure(2,2)
        difficult.sets[0].quality = "grindy"
        let plan = TFHProgression.project(anchor: anchor, exposures: [exposure(1,3),difficult], cycle: 2, rotation: 3)
        XCTAssertEqual(plan?.reps,anchor.reps); XCTAssertEqual(plan?.benchmark,false)
        let unselected = TFHAnchor(id:"anchor",exerciseId:"exercise",weightLb:42,reps:[3,3,3,3],
                                   minReps:3,maxReps:5,incrementLb:5,loadBasis:.perImplement,implementCount:2)
        XCTAssertEqual(TFHProgression.project(anchor: unselected,exposures:[],cycle:1,rotation:3)?.benchmark,false)
        var practice = anchor
        practice.intent = .practice
        let practicePlan = TFHProgression.project(anchor:practice,exposures:history,cycle:4,rotation:3)
        XCTAssertEqual(practicePlan?.benchmark,false); XCTAssertEqual(practicePlan?.reps,anchor.reps)
    }

    func testEarlierProgressCannotHideLaterDeclineOrUseStaleCycles() {
        var changed = history
        for e in changed.indices where changed[e].cycle == 2 {
            for s in changed[e].sets.indices { changed[e].sets[s].reps += 1 }
        }
        XCTAssertEqual(TFHProgression.plateau(anchor:anchor,exposures:changed,completedCycles:[1,2,3],currentCycle:4).state,"review")
        XCTAssertEqual(TFHProgression.plateau(anchor:anchor,exposures:history,completedCycles:[1,2,3],currentCycle:7).state,"learning")
    }

    func testBodyweightWithExternalMassIsNotComparableEvidence() {
        var bw = anchor
        bw.weightLb = 0; bw.incrementLb = 0; bw.loadBasis = .bodyweight
        bw.implementCount = 1; bw.reps = [6,6]; bw.minReps = 4; bw.maxReps = 6
        var invalid = history
        for e in invalid.indices {
            invalid[e].sets = Array(invalid[e].sets.prefix(2))
            for s in invalid[e].sets.indices {
                invalid[e].sets[s].weightLb = 12; invalid[e].sets[s].plannedWeightLb = 12
                invalid[e].sets[s].loadBasis = .bodyweight; invalid[e].sets[s].implementCount = 1
                invalid[e].sets[s].reps = 6; invalid[e].sets[s].plannedReps = 6
            }
        }
        XCTAssertEqual(TFHProgression.plateau(anchor:bw,exposures:invalid,completedCycles:[1,2,3],currentCycle:4).state,"learning")
    }
}
