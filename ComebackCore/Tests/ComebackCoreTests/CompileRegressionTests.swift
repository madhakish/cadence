import XCTest
import Foundation
@testable import ComebackCore

/// Each test here captures the root cause of a compile failure hit in CI,
/// reduced to a minimal fixture. If a "simplification" reintroduces the
/// pattern, the test target itself stops compiling — that's the tripwire.
final class CompileRegressionTests: XCTestCase {

    // MARK: CI run 1 — ActiveSessionView.swift:263
    // "error: expected '{' to start setter definition"
    // A computed property whose body STARTS with the token `set` is parsed
    // as a setter declaration when the type has a property named `set`.
    // Qualifying with `self.` disambiguates.

    private struct FlagToggleFixture {
        var set: [String]
        let flag: String
        // Removing `self.` here reproduces the run-1 compile failure.
        var isOn: Bool { self.set.contains(flag) }
    }

    func testPropertyNamedSetReadableFromComputedProperty() {
        XCTAssertTrue(FlagToggleFixture(set: ["clean"], flag: "clean").isOn)
        XCTAssertFalse(FlagToggleFixture(set: [], flag: "clean").isOn)
    }

    // MARK: CI run 2 — HomeView.swift:127
    // "cannot convert value ... to closure result type 'any StandardPredicateExpression<Bool>'"
    // #Predicate cannot build an expression from a property access on a
    // captured object (track.exerciseName); the value must be hoisted into
    // a local constant first. Foundation's #Predicate is the same macro
    // SwiftData uses, so the fixture guards the pattern on Darwin.

    #if canImport(Darwin)
    private struct TrackFixture { let exerciseName: String }
    private struct ExerciseFixture { let name: String }

    func testPredicateCapturesHoistedValueNotObjectProperty() throws {
        let track = TrackFixture(exerciseName: "Deadlift")
        // Inlining `track.exerciseName` into the macro reproduces the
        // run-2 compile failure.
        let exerciseName = track.exerciseName
        let predicate = #Predicate<ExerciseFixture> { $0.name == exerciseName }
        XCTAssertTrue(try predicate.evaluate(ExerciseFixture(name: "Deadlift")))
        XCTAssertFalse(try predicate.evaluate(ExerciseFixture(name: "Squat")))
    }
    #endif

    // MARK: CI run 1 — UnitsTests.testTrimDropsTrailingZero (runtime, not compile)
    // trim(2.5, decimals: 2) returned "2.50": trailing zeros were never
    // stripped for decimals > 1. Extra cases beyond the original test.

    func testTrimStripsTrailingZerosAtAnyPrecision() {
        XCTAssertEqual(Weight.trim(2.50, decimals: 2), "2.5")
        XCTAssertEqual(Weight.trim(0.10, decimals: 2), "0.1")
        XCTAssertEqual(Weight.trim(102.40, decimals: 2), "102.4")
        XCTAssertEqual(Weight.trim(45.0, decimals: 2), "45")
    }
}
