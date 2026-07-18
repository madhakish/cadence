import XCTest
@testable import CadenceCore

/// Parity enforcement for the program style templates: the Swift copy must
/// equal web/tests/fixtures/program-templates.json — the same fixture the
/// node smoke suite holds web/js/templates.js to — so either mirror drifting
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
    }
}
