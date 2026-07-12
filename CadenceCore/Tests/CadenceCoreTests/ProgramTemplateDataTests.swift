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
            .deletingLastPathComponent()   // CadenceCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // CadenceCore
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
}
