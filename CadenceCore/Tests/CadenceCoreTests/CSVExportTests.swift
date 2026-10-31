import XCTest
@testable import CadenceCore

final class CSVExportTests: XCTestCase {
    // [INV-CSV-NO-FORMULA]
    func testFreeTextIsNeverEvaluatedAsAFormula() {
        XCTAssertEqual(CSVExport.field("=HYPERLINK(\"http://x\",\"y\")"), "\"'=HYPERLINK(\"\"http://x\"\",\"\"y\"\")\"")
        XCTAssertEqual(CSVExport.field("+1"), "'+1")
        XCTAssertEqual(CSVExport.field("-5 lb, felt heavy"), "\"'-5 lb, felt heavy\"")
        XCTAssertEqual(CSVExport.field("@cmd"), "'@cmd")
        XCTAssertEqual(CSVExport.field("\tx"), "'\tx")
        XCTAssertEqual(CSVExport.field("a\rb"), "\"a\rb\"", "a lone CR is quoted too")
    }

    // [INV-CSV-NO-FORMULA]
    func testOrdinaryFieldsAreUnchanged() {
        XCTAssertEqual(CSVExport.field("Back Squat"), "Back Squat")
        XCTAssertEqual(CSVExport.field("135"), "135")
        XCTAssertEqual(CSVExport.field("2026-10-31T12:00:00Z"), "2026-10-31T12:00:00Z")
        XCTAssertEqual(CSVExport.field("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVExport.field("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(CSVExport.field(""), "")
    }
}
