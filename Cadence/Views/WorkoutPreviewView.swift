import SwiftUI
import SwiftData
import CadenceCore

/// Read-only preview of a program day from the Today card: every lift with
/// its full prescription and every accessory, WITHOUT creating a session —
/// the prominent Start button up top is what commits. Mirrors the same
/// preview math as the Today card (ProgramEngine.plan + neat snapping), so
/// the preview and the started session never disagree.
struct WorkoutPreviewView: View {
    let program: Program
    let day: ProgramDay
    let onStart: () -> Void

    @Query private var exercises: [Exercise]
    @Query private var gyms: [Gym]
    @Query private var settingsList: [AppSettings]
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted }, sort: \WorkoutSession.date)
    private var completedSessions: [WorkoutSession]

    private var defaultGym: Gym? { gyms.first { $0.isDefault } ?? gyms.first }
    private var unitDisplay: UnitDisplay { settingsList.first?.unitDisplay ?? .lbPrimary }
    private var phase: CyclePhase { CyclePhase(rawValue: program.currentWeek) ?? .volume }

    private func targetPlan(for lift: ProgramLift) -> SessionPlan {
        let exercise = exercises.first { $0.name == lift.exerciseName }
        let baseWeightLb = ProgramSession.reconciledBaseWeight(
            for: lift, program: program, day: day,
            exercise: exercise, sessions: completedSessions
        )
        return ProgramEngine.programPlan(
            for: CycleState(cycleNumber: program.cycleNumber, baseWeightLb: baseWeightLb,
                            nextPhase: phase, incrementLb: 0),
            programRoundingLb: program.roundingLb,
            exerciseType: exercise?.typeRaw,
            movementGroup: exercise?.movementGroup,
            role: lift.role,
            focus: program.focus,
            prescriptionStyle: lift.prescription,
            configuration: lift.prescriptionConfiguration(movementGroup: exercise?.movementGroup ?? ""))
    }

    private func plan(for lift: ProgramLift) -> SessionPlan {
        let raw = targetPlan(for: lift)
        let exercise = exercises.first { $0.name == lift.exerciseName }
        let weightLb = ProgramSession.achievableWeight(
            raw.weightLb, exercise: exercise,
            isMain: lift.role.rawValue == "main" || lift.prescription.buildsOwnSessionShape,
            gym: defaultGym, bar: defaultGym?.defaultBar ?? .bar45lb,
            stepLb: program.roundingLb, phase: phase
        )
        return SessionPlan(weightLb: weightLb, sets: raw.sets, reps: raw.reps,
                           phase: raw.phase, cycleNumber: raw.cycleNumber)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    WaveGlyph(week: program.currentWeek)
                    Text("\(program.name) · Cycle \(program.cycleNumber) · \(phase.name)")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.accent)
                    Spacer()
                }
            }

            Section("Lifts") {
                ForEach(day.orderedLifts) { lift in
                    let target = targetPlan(for: lift)
                    let p = plan(for: lift)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            NavigationLink {
                                ExerciseDetailByNameView(name: lift.exerciseName)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lift.exerciseName).font(.subheadline.bold())
                                    Text(lift.role.rawValue).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(unitDisplay.format(lb: p.weightLb)).font(.body.bold().monospacedDigit())
                                Text("\(p.sets)×\(p.reps)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        if p.weightLb > 0 {
                            let type = exercises.first(where: { $0.name == lift.exerciseName })?.type
                            if type == .barbell {
                                BarbellView(weightLb: p.weightLb, unit: unitDisplay.primaryUnit,
                                            bar: defaultGym?.defaultBar ?? .bar45lb, gym: defaultGym,
                                            targetWeightLb: target.weightLb)
                            } else if type == .dumbbell {
                                DumbbellView(weightLb: p.weightLb, unit: unitDisplay.primaryUnit)
                            }
                        }
                    }
                }
            }

            if !day.accessories.isEmpty {
                Section("Accessories") {
                    ForEach(day.orderedAccessories) { acc in
                        let type = exercises.first(where: { $0.name == acc.exerciseName })?.type
                        let isTimed = type == .timed || type == .conditioning
                        HStack {
                            NavigationLink {
                                ExerciseDetailByNameView(name: acc.exerciseName)
                            } label: {
                                Text(acc.exerciseName).font(.subheadline)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Text(isTimed
                                 ? "\(acc.sets) × \(CardioFormat.durationLabel(seconds: acc.targetSeconds))"
                                 : (acc.weightLb > 0
                                    ? "\(acc.sets)×\(acc.currentReps) @ \(unitDisplay.format(lb: acc.weightLb))"
                                    : "\(acc.sets)×\(acc.currentReps)"))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(day.name)
        .navigationBarTitleDisplayMode(.inline)
        // Start lives up top, pinned — browsing the workout never scrolls it away.
        .safeAreaInset(edge: .top, spacing: 0) {
            Button(action: onStart) {
                Label("Start \(day.name)", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}
