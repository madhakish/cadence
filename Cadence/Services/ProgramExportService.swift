import Foundation
import SwiftData
import CadenceCore

/// Writes a single program as a standalone JSON document.
///
/// Deliberately NOT part of `ExportService`: the program file is its own
/// contract with its own version, so a program-format change never has to move
/// the backup's `schemaVersion` and vice versa. Mirrors web
/// `program-file.js` `exportProgramFile`.
enum ProgramExportService {

    /// What a file carries beyond the plan itself.
    struct Options {
        /// Runtime progression state: stall counters, last increments, the
        /// stashed week-3 peak grade, cycle-scoped swap markers, and the
        /// program's wave position. Off by default — a program shared with
        /// someone else has no business carrying the author's stall counters,
        /// and they would be actively misleading on another lifter's device.
        var includeState: Bool = false
        /// Program and slot UUIDs. Off by default so an import is additive and
        /// cannot collide with a slot id that history already points at.
        var includeIdentity: Bool = false

        static let plan = Options()
        static let full = Options(includeState: true, includeIdentity: true)

        init(includeState: Bool = false, includeIdentity: Bool = false) {
            self.includeState = includeState
            self.includeIdentity = includeIdentity
        }
    }

    static func file(for program: Program, options: Options = .plan) -> ProgramFileContract.File {
        var payload = ProgramFileContract.Program(
            id: options.includeIdentity ? program.id : nil,
            name: program.name,
            focus: program.focusRaw,
            roundingLb: program.roundingLb,
            coachEnabled: program.coachEnabled,
            preferredSessionSpacingDays: program.preferredSessionSpacingDays,
            maximumAddedSetsPerRotation: program.maximumAddedSetsPerRotation,
            cycleNumber: options.includeState ? program.cycleNumber : nil,
            currentWeek: options.includeState ? program.currentWeek : nil,
            nextDayIndex: options.includeState ? program.nextDayIndex : nil,
            days: []
        )

        payload.days = program.orderedDays.map { day in
            ProgramFileContract.Day(
                name: day.name,
                // Verbatim. A day's order is the identity every banked
                // session's programTag.dayIndex refers to; renumbering here
                // would misattribute logged work on reimport.
                order: day.order,
                lifts: day.orderedLifts.map { lift in
                    ProgramFileContract.Lift(
                        id: options.includeIdentity ? lift.id : nil,
                        exerciseName: lift.exerciseName,
                        role: lift.roleRaw,
                        order: lift.order,
                        prescription: lift.prescriptionRaw,
                        warmupPolicy: lift.warmupPolicyRaw,
                        loadOffsetLb: lift.loadOffsetLb,
                        peakOffsetLb: lift.peakOffsetLb,
                        deloadMultiplier: lift.deloadMultiplier,
                        doubleProgressionSets: lift.doubleProgressionSets,
                        minimumReps: lift.minimumReps,
                        maximumReps: lift.maximumReps,
                        currentReps: lift.currentReps,
                        peakSingleEnabled: lift.peakSingleEnabled,
                        peakSingleIncrementLb: lift.peakSingleIncrementLb,
                        phasePrimerEnabled: lift.phasePrimerEnabled,
                        dropIncrementLb: lift.dropIncrementLb,
                        capacityManaged: lift.capacityManaged,
                        maximumSets: lift.maximumSets,
                        baseWeightLb: lift.baseWeightLb,
                        estimatedMaxLb: lift.estimatedMaxLb,
                        stallCount: options.includeState ? lift.stallCount : nil,
                        lastIncrementLb: options.includeState ? lift.lastIncrementLb : nil,
                        lastPeakSingleLb: options.includeState ? lift.lastPeakSingleLb : nil,
                        pending: options.includeState ? pending(for: lift) : nil,
                        revertToExerciseName: options.includeState ? lift.revertToExerciseName : nil
                    )
                },
                accessories: day.orderedAccessories.map { accessory in
                    ProgramFileContract.Accessory(
                        id: options.includeIdentity ? accessory.id : nil,
                        exerciseName: accessory.exerciseName,
                        order: accessory.order,
                        sets: accessory.sets,
                        minReps: accessory.minReps,
                        maxReps: accessory.maxReps,
                        currentReps: accessory.currentReps,
                        targetSeconds: accessory.targetSeconds,
                        durationStepSeconds: accessory.durationStepSeconds,
                        capacityManaged: accessory.capacityManaged,
                        maximumSets: accessory.maximumSets,
                        conditioningEffort: accessory.conditioningEffortRaw,
                        targetRPE: accessory.targetRPE,
                        weightLb: accessory.weightLb,
                        incrementLb: accessory.incrementLb,
                        stallCount: options.includeState ? accessory.stallCount : nil,
                        revertToExerciseName: options.includeState ? accessory.revertToExerciseName : nil
                    )
                }
            )
        }

        return ProgramFileContract.File(program: payload)
    }

    private static func pending(for lift: ProgramLift) -> ProgramFileContract.PendingResult? {
        guard let base = lift.pendingBaseWeightLb else { return nil }
        return ProgramFileContract.PendingResult(
            state: ProgramFileContract.PendingState(
                baseWeightLb: base,
                estimatedMaxLb: lift.pendingEstimatedMaxLb ?? lift.estimatedMaxLb,
                stallCount: lift.pendingStallCount ?? lift.stallCount,
                lastIncrementLb: lift.pendingLastIncrementLb ?? 0
            ),
            note: lift.pendingNote
        )
    }

    /// Deterministic bytes: sorted keys, no date encoding (the payload carries
    /// no timestamp at all), so the same program always produces the same file.
    static func jsonData(for program: Program, options: Options = .plan) throws -> Data {
        // Validate what we are about to hand over. A blank name or a day with no
        // slots writes a file every Cadence importer rejects, and the lifter
        // finds out on the other device. Mirrors the web export button; the
        // ShareLink already fails closed, so an unexportable program simply has
        // no button rather than a broken file.
        let payload = file(for: program, options: options)
        try ProgramFileContract.validate(payload)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    static func filename(for program: Program) -> String {
        let slug = program.name.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return "cadence-program-\(slug.isEmpty ? "program" : slug).json"
    }
}
