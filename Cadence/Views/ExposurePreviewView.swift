import SwiftUI
import SwiftData
import CadenceCore

/// The next four exposures a program slot will actually produce.
///
/// The editor is a wall of pickers and steppers: it tells you what values were
/// entered, never what they produce. A lifter setting a 190 lb base cannot see
/// that it yields a 225 lb peak triple while 188 yields 220 — a whole plate
/// step decided by which side of a rounding boundary the multiplication lands
/// on. This turns the engine's output into something a human can audit.
///
/// Every number comes from `ProgramEngine.exposurePreview`, which runs the
/// shipped engine forward; there is no second implementation that could
/// disagree with the session the lifter eventually starts. It costs no
/// persisted state — the preview is computed from the slot's current values on
/// each render, so it updates live as base, style, rounding and focus change.
struct ExposurePreviewView: View {
    @Query private var exercises: [Exercise]
    @Query private var settingsList: [AppSettings]

    let lift: ProgramLift
    let rotation: Int
    let cycleNumber: Int
    let roundingLb: Double
    var focus: TrainingFocus = .strength
    /// The selected slot's authored day, the program's next-day pointer, the
    /// shortened recovery selection, and any still-synchronized twins.
    var schedule: ProgramEngine.ExposurePreviewSchedule?
    var count: Int = 4

    private var exercise: Exercise? { exercises.first { $0.name == lift.exerciseName } }
    private var unitDisplay: UnitDisplay { settingsList.unitDisplay }

    private var resolvedStyle: PrescriptionStyle {
        ProgramEngine.resolvedStyle(lift.prescription, movementGroup: exercise?.movementGroup,
                                    role: lift.role, focus: focus)
    }

    /// The slot's own banked-but-unapplied grade, if a peak has already been
    /// graded this cycle. Without it the next-cycle entries preview the old
    /// base — the one the session will NOT use.
    private var pendingState: ProgramLiftState? {
        guard let pendingBase = lift.pendingBaseWeightLb else { return nil }
        return ProgramLiftState(
            baseWeightLb: pendingBase,
            estimatedMaxLb: lift.pendingEstimatedMaxLb ?? lift.estimatedMaxLb,
            stallCount: lift.pendingStallCount ?? lift.stallCount,
            role: lift.role,
            lastIncrementLb: lift.pendingLastIncrementLb ?? 0
        )
    }

    private var entries: [ProgramEngine.ExposurePreviewEntry] {
        ProgramEngine.exposurePreview(
            count: count,
            baseWeightLb: lift.baseWeightLb,
            estimatedMaxLb: lift.estimatedMaxLb,
            stallCount: lift.stallCount,
            cycleNumber: cycleNumber,
            rotation: rotation,
            programRoundingLb: roundingLb,
            exerciseType: exercise?.typeRaw,
            movementGroup: exercise?.movementGroup,
            role: lift.role,
            focus: focus,
            prescriptionStyle: lift.prescription,
            configuration: lift.prescriptionConfiguration(movementGroup: exercise?.movementGroup ?? ""),
            pendingState: pendingState,
            schedule: schedule
        )
    }

    /// What the numbers derive from. A 5/3/1 slot's base is a training max, not
    /// a working weight, and saying so is the difference between a preview that
    /// explains the prescription and one that looks wrong.
    private var basisLabel: String {
        resolvedStyle == .fiveThreeOne ? "Training max" : "Base"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Next \(count) exposures")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ForEach(entries, id: \.exposureNumber) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        // Phase-independent styles are numbered exposures, not
                        // phases — labelling a linearFives session "Peak" would
                        // assert something the engine does not do.
                        Text(entry.phaseName ?? "Session \(entry.exposureNumber)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(entry.isRecovery ? Theme.warn : .secondary)
                            .frame(minWidth: 92, alignment: .leading)
                        Text(unitDisplay.format(lb: entry.prescription.mainWork.weightLb))
                            .font(.caption.bold().monospacedDigit())
                        Text("\(entry.prescription.mainWork.sets)×\(entry.prescription.mainWork.reps)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if mainWorkIsAMRAP(entry) {
                            Text("+ set")
                                .font(.caption2.bold())
                                .foregroundStyle(Theme.warn)
                        }
                        Spacer(minLength: 0)
                    }
                    // Ramps, primers, top singles and the "+" set are real
                    // prescribed work. A preview that showed only the top line
                    // would hide most of a 5/3/1 session.
                    if let extras = supportingLine(entry) {
                        Text(extras)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    if let note = entry.advanceNote {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Text("\(basisLabel) \(unitDisplay.format(lb: lift.baseWeightLb)) · assumes each session is completed as prescribed.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// The blocks either side of the graded work, in the order they are
    /// performed. Returns nil when the session is a single uniform block.
    private func mainWorkIsAMRAP(_ entry: ProgramEngine.ExposurePreviewEntry) -> Bool {
        let main = entry.prescription.mainWork
        return entry.prescription.blocks.contains { block in
            block.kind == .amrap
                && abs(block.weightLb - main.weightLb) < 0.001
                && block.sets == main.sets
                && block.reps == main.reps
        }
    }

    private func supportingLine(_ entry: ProgramEngine.ExposurePreviewEntry) -> String? {
        let main = entry.prescription.mainWork
        var removedMainBlock = false
        let extras = entry.prescription.blocks.filter { block in
            guard block.kind != .work else { return false }
            if !removedMainBlock,
               abs(block.weightLb - main.weightLb) < 0.001,
               block.sets == main.sets,
               block.reps == main.reps {
                removedMainBlock = true
                return false
            }
            return true
        }
        guard !extras.isEmpty else { return nil }
        return extras.map { block in
            let load = unitDisplay.format(lb: block.weightLb)
            return "\(label(block.kind)) \(load) \(block.sets)×\(block.reps)"
        }.joined(separator: " · ")
    }

    private func label(_ kind: PrescriptionBlockKind) -> String {
        switch kind {
        case .warmup: return "warm-up"
        case .primer: return "primer"
        case .topSingle: return "top single"
        case .ramp: return "ramp"
        case .work: return "work"
        case .amrap: return "+ set"
        case .backoff: return "back-off"
        case .conditioning: return "conditioning"
        }
    }
}
