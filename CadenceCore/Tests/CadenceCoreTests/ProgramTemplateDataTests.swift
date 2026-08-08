import XCTest
@testable import CadenceCore

/// Parity enforcement for the program style templates: the Swift copy must
/// equal web/tests/fixtures/program-templates.json — the same fixture the
/// node smoke suite holds web/app/js/templates.js to — so either mirror drifting
/// fails its own CI job. Regenerate the fixture with
/// web/tools/generate-template-fixture.mjs when templates change.
final class ProgramTemplateDataTests: XCTestCase {

    private func fixtureURL() -> URL {
        // …/CadenceCore/Tests/CadenceCoreTests/ThisFile.swift → repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // → CadenceCoreTests/
            .deletingLastPathComponent()   // → Tests/
            .deletingLastPathComponent()   // → CadenceCore/
            .deletingLastPathComponent()   // → repo root
            .appendingPathComponent("web/tests/fixtures/program-templates.json")
    }

    func testTemplatesMatchSharedFixture() throws {
        let data = try Data(contentsOf: fixtureURL())
        let fixture = try JSONDecoder().decode([ProgramTemplateData.Template].self, from: data)
        XCTAssertEqual(ProgramTemplateData.all.count, fixture.count, "template count matches fixture")
        for (mine, theirs) in zip(ProgramTemplateData.all, fixture) {
            XCTAssertEqual(mine, theirs, "template \(mine.id) matches the shared fixture — if you edited templates on either platform, mirror it and regenerate the fixture")
        }
    }

    func testTemplateInternalConsistency() {
        for t in ProgramTemplateData.all {
            XCTAssertFalse(t.days.isEmpty, "\(t.id): has days")
            XCTAssertNotNil(TrainingFocus(rawValue: t.focus), "\(t.id): focus decodes")
            for d in t.days {
                XCTAssertLessThanOrEqual(d.lifts.filter { $0.role == "main" }.count, 1, "\(t.id)/\(d.name): at most one main lift")
                for a in d.accessories {
                    XCTAssertLessThanOrEqual(a.minReps, a.maxReps, "\(t.id)/\(d.name)/\(a.exercise): rep range sane")
                }
            }
        }
    }

    func testUpperLowerSplitKeepsTheReviewedFourDayRotation() throws {
        let template = try XCTUnwrap(ProgramTemplateData.all.first { $0.id == "strength-upper-lower" })
        XCTAssertEqual(template.days.map(\.name), ["Upper A", "Lower A", "Upper B", "Lower B"])
        XCTAssertEqual(template.roundingLb, 5, "upper-body and per-hand dumbbell work must allow 5 lb steps")
        XCTAssertEqual(template.days[0].lifts.first?.exercise, "Overhead Press")
        XCTAssertEqual(template.days[2].lifts.first?.exercise, "Incline DB Press")
        XCTAssertEqual(template.days[1].lifts.first?.exercise, "Back Squat")
        XCTAssertEqual(template.days[3].lifts.first?.exercise, "Deadlift")
        XCTAssertTrue(template.days.allSatisfy { day in
            day.lifts.first?.role == "main" && day.lifts.dropFirst().allSatisfy { $0.role == "complementary" }
        }, "role order is deterministic so goal slots cannot cross-align")
        XCTAssertTrue(template.days.allSatisfy { day in
            day.accessories.contains { ["core", "GHD Sit-up", "Hanging Knee Raise"].contains($0.exercise) }
        }, "each day retains trunk work")
        // Vertical pulling is main work (issue #126): both upper days program
        // pull-ups as a LIFT slot on a rep window that earns load, not as an
        // accessory buried under the press. Mirrored in web smoke tests.
        let upperDays = template.days.filter { $0.name.hasPrefix("Upper") }
        XCTAssertEqual(upperDays.count, 2)
        XCTAssertTrue(upperDays.allSatisfy { day in
            day.lifts.contains {
                $0.exercise == "Pull-ups" && $0.prescription == "doubleProgression" && $0.sets == 3
            }
        }, "upper/lower trains the vertical pull as programmed lift work on both upper days")
        // Every template compat record agrees with the seed's category.
        XCTAssertTrue(ProgramTemplateData.all.allSatisfy { candidate in
            candidate.exercises.filter { $0.name == "Pull-ups" }.allSatisfy { $0.category == "Main" }
        }, "template compat records agree with the seed: pull-ups are Main")
    }

    func testConjugateTemplateKeepsWeeklyMaxEffortSeparateFromSpeedWaves() throws {
        let template = try XCTUnwrap(ProgramTemplateData.all.first { $0.id == "conjugate" })
        XCTAssertEqual(template.days.map(\.name), [
            "Mon — Max Effort Lower", "Wed — Max Effort Upper",
            "Fri — Dynamic Effort Lower", "Sun — Dynamic Effort Upper",
        ])

        let lifts = template.days.flatMap(\.lifts)
        XCTAssertEqual(lifts.filter { $0.prescription == "maxEffort" }.map(\.exercise),
                       ["Low Box Squat", "Floor Press"])
        XCTAssertEqual(lifts.filter { $0.prescription == "dynamicEffort" }.map(\.startFraction),
                       [0.50, 0.50, 0.40])
        XCTAssertEqual(lifts.compactMap(\.historyExercise),
                       ["Back Squat", "Barbell Bench", "Back Squat", "Deadlift", "Barbell Bench"])

        let speedNames = Set(["Speed Box Squat", "Speed Deadlift", "Speed Bench Press"])
        XCTAssertTrue(template.exercises.filter { speedNames.contains($0.name) }.allSatisfy { $0.rest == 60 })
        XCTAssertGreaterThanOrEqual(template.exercises.filter { $0.group == "squat" && $0.name != "Speed Box Squat" }.count, 3,
                                    "the lower max-effort slot ships a weekly special-exercise pool")
        XCTAssertGreaterThanOrEqual(template.exercises.filter { $0.group == "press" && !$0.name.hasPrefix("Speed") }.count, 2,
                                    "the upper max-effort slot ships a weekly special-exercise pool")

        let sled = try XCTUnwrap(template.days[2].accessories.first { $0.exercise == "Sled Pull" })
        XCTAssertEqual(sled.sets, 4)
        XCTAssertEqual(sled.targetSeconds, 60)
        XCTAssertEqual(sled.conditioningEffort, "easy")
        XCTAssertEqual(sled.targetRPE, 5)
    }
}
