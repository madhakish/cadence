import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CadenceCore

/// The whole program at a glance. Editing remains in ProgramEditorView so the
/// overview cannot grow a second, subtly different programming engine.
struct ProgramOverviewView: View {
    @Environment(\.modelContext) private var context
    @Query private var programs: [Program]
    @Query private var exercises: [Exercise]
    @Query private var settingsList: [AppSettings]
    @Query private var gyms: [Gym]
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted })
    private var completedSessions: [WorkoutSession]

    @State private var showCreator = false
    @State private var showImporter = false
    @State private var importAfterCreator = false
    @State private var alert: String?

    private var orderedPrograms: [Program] {
        programs.sorted {
            if $0.isActive != $1.isActive { return $0.isActive }
            return $0.createdAt < $1.createdAt
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(orderedPrograms) { program in
                    Section {
                        ForEach(program.orderedDays) { day in
                            NavigationLink {
                                // The card names a DAY, so it opens that day —
                                // landing on the whole-program editor made the
                                // label a lie and cost a navigation hop.
                                ProgramDayEditorView(day: day, step: program.roundingLb)
                            } label: {
                                dayCard(program, day)
                            }
                            .accessibilityHint("Edits \(day.name)")
                        }
                    } header: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(program.name)
                                Text("\(program.focus.rawValue.capitalized) · Cycle \(program.cycleNumber)")
                                    .font(.caption)
                            }
                            Spacer()
                            RotationGlyph(week: program.currentWeek)
                            if program.isActive {
                                Text("Active").font(.caption.bold()).foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }

                if programs.isEmpty {
                    ContentUnavailableView(
                        "No program",
                        systemImage: "list.bullet.clipboard",
                        description: Text("Start blank, use a template, or import a Cadence program file.")
                    )
                }
            }
            .navigationTitle("Program")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreator = true } label: {
                        Label("Add program", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreator, onDismiss: {
                guard importAfterCreator else { return }
                importAfterCreator = false
                showImporter = true
            }) {
                ProgramCreationSheet(existingPrograms: programs) {
                    importAfterCreator = true
                    showCreator = false
                }
                .presentationDetents([.medium, .large])
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                alert = importProgram(from: result)
            }
            .alert("Cadence program", isPresented: Binding(
                get: { alert != nil }, set: { if !$0 { alert = nil } }
            )) {
                Button("OK") { alert = nil }
            } message: {
                Text(alert ?? "")
            }
        }
    }

    private func dayCard(_ program: Program, _ day: ProgramDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(day.name).font(.headline)
                Spacer()
                if day.order == program.nextDayIndex {
                    Text("Next").font(.caption.bold()).foregroundStyle(Theme.accent)
                }
            }
            ForEach(day.orderedLifts) { lift in
                let exercise = exercises.first { $0.name == lift.exerciseName }
                let plan = plan(program, lift, exercise)
                VStack(alignment: .leading, spacing: 3) {
                    Text(lift.exerciseName).font(.callout.bold())
                    SlotPrescriptionBadge(
                        lift: lift, rotation: program.currentWeek,
                        movementGroup: exercise?.movementGroup, focus: program.focus
                    )
                    Text("Base \(format(lift.baseWeightLb)) · next \(format(plan.weightLb)) · \(plan.sets)×\(plan.reps)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("\(day.orderedAccessories.count) accessories")
                    .font(.caption).foregroundStyle(.secondary)
                if day.orderedAccessories.contains(where: cannotProgress) {
                    Label("Needs progression", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold()).foregroundStyle(Theme.warn)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func plan(_ program: Program, _ lift: ProgramLift, _ exercise: Exercise?) -> SessionPlan {
        // "next" shows the honest plan (planningBase) beside the stored base,
        // so the overview and the Today card can never quote different
        // numbers. The overview deliberately lists the theoretical target
        // (raw stage), never a gym-snapped stack.
        ProgramSession.rawPreviewPlan(
            for: lift, exercise: exercise, program: program,
            phase: CyclePhase(rawValue: program.currentWeek) ?? .volume,
            planningBase: ProgramSession.planningBase(
                for: lift, exercise: exercise, program: program, sessions: completedSessions
            ),
            addedVolumeSets: ProgramSession.volumeFallbackSets(for: lift, program: program)
        )
    }

    /// Whether a slot has no way left to move the needle.
    ///
    /// This used to read "at the top of its rep window with no increment",
    /// which flagged every healthy bodyweight accessory: reps ARE its
    /// progression, so it climbs past its window top forever and the flag
    /// was permanently on. The real stuck cases are a slot carrying load it
    /// can never add to, and timed work with no duration step — and the first
    /// of those already has an owner the program editor uses.
    private func cannotProgress(_ accessory: ProgramAccessory) -> Bool {
        // A missing exercise must not fail OPEN — the quietly stuck slot is
        // exactly what this pill exists to flag. Fall back to the inferred
        // (external) basis, the same reading web's resolvedLoadBasis gives an
        // unknown exercise, so a loaded no-increment slot stays visible even
        // when an import references a name the library no longer holds.
        let exercise = exercises.first(where: { $0.name == accessory.exerciseName })
        if let exercise, exercise.type == .timed || exercise.type == .conditioning {
            return accessory.durationStepSeconds <= 0
        }
        return ProgramProgression.accessoryCannotProgressLoad(
            exerciseType: exercise?.typeRaw,
            loadBasis: exercise?.loadBasis ?? LoadSemantics.inferredBasis(exerciseType: nil),
            weightLb: accessory.weightLb, incrementLb: accessory.incrementLb
        )
    }

    private func format(_ lb: Double) -> String {
        settingsList.unitDisplay.format(lb: lb)
    }

    private func importProgram(from result: Result<URL, Error>) -> String {
        switch result {
        case .failure(let error): return error.localizedDescription
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let report = try ProgramImportService.load(Data(contentsOf: url), into: context)
                return ([report.summary] + report.warnings).joined(separator: "\n\n")
            } catch {
                return error.localizedDescription
            }
        }
    }
}
