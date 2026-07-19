import SwiftUI
import SwiftData
import CadenceCore

/// Today: suggested next session per lift, one-tap session start,
/// gym tag, protein running total. Nothing motivational.
struct HomeView: View {
    @Binding var pendingSessionID: String?
    private enum StartError: LocalizedError {
        case missingExercise(String)
        var errorDescription: String? {
            switch self {
            case .missingExercise(let name): return "The exercise library is missing \(name). Sync or restore the library, then try again."
            }
        }
    }
    @Environment(\.modelContext) private var context
    @Query private var tracks: [LiftTrack]
    @Query private var programs: [Program]
    @Query private var exercises: [Exercise]
    @Query private var gyms: [Gym]
    @Query private var settingsList: [AppSettings]
    @Query private var proteinEntries: [ProteinEntry]
    @Query(filter: #Predicate<WorkoutSession> { !$0.isCompleted })
    private var openSessions: [WorkoutSession]
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted }, sort: \WorkoutSession.date)
    private var completedSessions: [WorkoutSession]

    @State private var activeSession: WorkoutSession?
    @State private var showGymCard = false
    @State private var previewDay: ProgramDay?
    @State private var discardSession: WorkoutSession?

    private var settings: AppSettings? { settingsList.first }
    private var unitDisplay: UnitDisplay { settings?.unitDisplay ?? .lbPrimary }
    private var entryUnit: WeightUnit { unitDisplay.primaryUnit }
    private var defaultGym: Gym? { gyms.first { $0.isDefault } ?? gyms.first }
    private var activeProgram: Program? { programs.first { $0.isActive } ?? programs.first }
    private var ownedLiftNames: Set<String> {
        guard let p = activeProgram else { return [] }
        return Set(p.days.flatMap { $0.lifts.map(\.exerciseName) })
    }

    private func nextDay(_ program: Program) -> ProgramDay? {
        program.orderedDays.first { $0.order == program.nextDayIndex } ?? program.orderedDays.first
    }

    private func programPlan(_ program: Program, _ lift: ProgramLift) -> SessionPlan {
        let phase = CyclePhase(rawValue: program.currentWeek) ?? .volume
        let exercise = exercises.first { $0.name == lift.exerciseName }
        let plan = ProgramEngine.programPlan(
            for: CycleState(cycleNumber: program.cycleNumber, baseWeightLb: lift.baseWeightLb, nextPhase: phase, incrementLb: 0),
            programRoundingLb: program.roundingLb,
            exerciseType: exercise?.typeRaw,
            movementGroup: exercise?.movementGroup,
            role: lift.role,
            focus: program.focus,
            prescriptionStyle: lift.prescription)
        // Preview the same snapped weight the session will store (secondary barbell lifts).
        let weightLb = ProgramSession.achievableWeight(
            plan.weightLb, exercise: exercise, isMain: lift.role.rawValue == "main",
            gym: defaultGym, bar: defaultGym?.defaultBar ?? .bar45lb,
            stepLb: program.roundingLb)
        return SessionPlan(weightLb: weightLb, sets: plan.sets, reps: plan.reps, phase: plan.phase, cycleNumber: plan.cycleNumber)
    }

    private func trackPlan(_ track: LiftTrack) -> SessionPlan {
        let plan = track.suggestion
        let exercise = exercises.first { $0.name == track.exerciseName }
        let weightLb = ProgramSession.achievableWeight(
            plan.weightLb, exercise: exercise, isMain: true, gym: defaultGym,
            bar: defaultGym?.defaultBar ?? .bar45lb, stepLb: track.roundingLb)
        return SessionPlan(weightLb: weightLb, sets: plan.sets, reps: plan.reps,
                           phase: plan.phase, cycleNumber: plan.cycleNumber)
    }

    /// Last 8 top working weights for a lift, oldest → newest (sparkline source).
    private func recentTops(_ name: String) -> [Double] {
        Array(completedSessions
            .compactMap { session -> Double? in
                let tops = session.exercises.filter { $0.exercise?.name == name }.compactMap(\.topSet?.weightLb)
                return tops.max()
            }
            .suffix(8))
    }

    private var todayProtein: Double {
        let cal = Calendar.current
        return proteinEntries
            .filter { cal.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.grams }
    }

    var body: some View {
        NavigationStack {
            List {
                // Arrival is a real workflow: the membership tag replaces a
                // physical keychain and must be available before the workout.
                Section {
                    Button {
                        showGymCard = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "barcode.viewfinder")
                                .font(.title2.bold())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Gym Tag").font(.headline)
                                Text(defaultGym?.barcodeImageData == nil
                                     ? "Add your membership barcode"
                                     : "Ready to scan · full brightness")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold()).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, minHeight: Theme.bigTap, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Shows the default membership barcode at full brightness")
                }

                if !openSessions.isEmpty {
                    Section("Open sessions") {
                        ForEach(openSessions.sorted { $0.date > $1.date }) { open in
                            Button {
                                activeSession = open
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Label("Resume session", systemImage: "play.fill").font(.headline)
                                    Text(openSessionLabel(open))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    discardSession = open
                                } label: {
                                    Label("Discard", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                if let program = activeProgram, let day = nextDay(program) {
                    Section("\(program.name) · Cycle \(program.cycleNumber)") {
                        // Tapping the day opens the full preview — browse the
                        // whole workout without starting it.
                        Button {
                            previewDay = day
                        } label: {
                            HStack(spacing: 8) {
                                Text(day.name).font(.headline)
                                Spacer()
                                WaveGlyph(week: program.currentWeek)
                                Text((CyclePhase(rawValue: program.currentWeek) ?? .volume).name)
                                    .font(.caption.bold())
                                    .foregroundStyle(Theme.accent)
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        ForEach(day.orderedLifts) { lift in
                            let plan = programPlan(program, lift)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(lift.exerciseName).font(.subheadline.bold())
                                        Text(lift.role.rawValue).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(unitDisplay.format(lb: plan.weightLb))
                                            .font(.body.bold().monospacedDigit())
                                        Text("\(plan.sets)×\(plan.reps)")
                                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                }
                                // The bar you'll load / the pair you'll grab —
                                // every wave lift, matching the preview screen
                                // (a complementary barbell lift is loaded just
                                // the same as the main).
                                if plan.weightLb > 0 {
                                    let type = exercises.first(where: { $0.name == lift.exerciseName })?.type
                                    if type == .barbell {
                                        BarbellView(weightLb: plan.weightLb, unit: entryUnit,
                                                    bar: defaultGym?.defaultBar ?? .bar45lb, gym: defaultGym)
                                    } else if type == .dumbbell {
                                        DumbbellView(weightLb: plan.weightLb, unit: entryUnit)
                                    }
                                }
                            }
                        }
                        if !day.accessories.isEmpty {
                            Text("+ " + day.accessories.map(\.exerciseName).joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button {
                            startProgramDay(program, day)
                        } label: {
                            Text("Start \(day.name)").frame(maxWidth: .infinity).font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Section(activeProgram == nil ? "Next up" : "Other tracked lifts") {
                    ForEach(tracks.filter { !ownedLiftNames.contains($0.exerciseName) }.sorted { $0.exerciseName < $1.exerciseName }) { track in
                        let plan = trackPlan(track)
                        Button {
                            startSession(with: track)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.exerciseName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(unitDisplay.format(lb: plan.weightLb)) · \(plan.sets)×\(plan.reps)")
                                        .font(.title3.bold())
                                        .foregroundStyle(Theme.accent)
                                    if track.mode == .cycle {
                                        Text("Cycle \(track.cycleNumber) · advances when you bank it")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                let tops = recentTops(track.exerciseName)
                                if tops.count >= 2 {
                                    Sparkline(values: tops)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Button {
                        startBlankSession()
                    } label: {
                        Label("Blank session", systemImage: "plus")
                    }
                }

                Section("Protein") {
                    HStack {
                        Text("\(Int(todayProtein)) g")
                            .font(.title2.bold().monospacedDigit())
                        Text("/ \(Int(settings?.proteinTargetGrams ?? 100)) g")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    HStack(spacing: 12) {
                        proteinButton("Shake ~45g", grams: 45)
                        proteinButton("Meat ~50g", grams: 50)
                        NavigationLink("More") { BodyView() }
                            .font(.callout)
                    }
                }
            }
            .navigationTitle("Cadence")
            .fullScreenCover(item: $activeSession) { session in
                NavigationStack {
                    ActiveSessionView(session: session)
                }
            }
            .sheet(item: $previewDay) { day in
                NavigationStack {
                    if let program = activeProgram {
                        WorkoutPreviewView(program: program, day: day) {
                            previewDay = nil
                            startProgramDay(program, day)
                        }
                    }
                }
            }
            .sheet(isPresented: $showGymCard) {
                GymCardView(gym: defaultGym)
            }
            .task { openPendingSessionIfNeeded() }
            .onChange(of: pendingSessionID) { _, _ in openPendingSessionIfNeeded() }
            .confirmationDialog("Discard this open session?", isPresented: Binding(
                get: { discardSession != nil },
                set: { if !$0 { discardSession = nil } }
            ), titleVisibility: .visible) {
                Button("Discard session", role: .destructive) {
                    guard let session = discardSession else { return }
                    context.delete(session)
                    PersistenceErrorCenter.shared.save(context, operation: "Discarding the session")
                    discardSession = nil
                }
                Button("Cancel", role: .cancel) { discardSession = nil }
            } message: {
                Text("Only this unbanked session is removed. Completed history and the program are unchanged.")
            }
        }
    }

    private func openSessionLabel(_ session: WorkoutSession) -> String {
        let names = session.orderedExercises.compactMap { $0.exercise?.name }
        let workout = names.isEmpty ? "Blank session" : names.prefix(2).joined(separator: " · ")
        return "\(workout) · \(session.date.formatted(date: .abbreviated, time: .shortened))"
    }

    private func openPendingSessionIfNeeded() {
        guard let id = pendingSessionID else { return }
        pendingSessionID = nil
        guard let session = openSessions.first(where: { $0.id == id }) else { return }
        activeSession = session
    }

    private func proteinButton(_ label: String, grams: Double) -> some View {
        Button(label) {
            context.insert(ProteinEntry(grams: grams, label: label))
            PersistenceErrorCenter.shared.save(context, operation: "Logging protein")
        }
        .buttonStyle(.bordered)
        .font(.callout)
    }

    private func startSession(with track: LiftTrack) {
        // #Predicate can't reference properties of captured objects; capture the value
        let exerciseName = track.exerciseName
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.name == exerciseName }
        )
        let exercise: Exercise
        do {
            guard let found = try context.fetch(descriptor).first else { throw StartError.missingExercise(exerciseName) }
            exercise = found
        } catch {
            PersistenceErrorCenter.shared.report(error, operation: "Starting the session", context: context)
            return
        }

        let session = WorkoutSession(gymID: defaultGym?.id, gymName: defaultGym?.name)
        context.insert(session)

        let entry = SessionExercise(order: 0, exercise: exercise)
        entry.session = session
        let plan = trackPlan(track)
        entry.plannedWeightLb = plan.weightLb
        entry.plannedSets = plan.sets
        entry.plannedReps = plan.reps
        entry.phase = plan.phase
        context.insert(entry)
        session.exercises.append(entry)

        // Pre-fill warmup ramp + working sets. All editable.
        if exercise.type == .barbell {
            for warmup in WarmupRamp.ramp(
                workingLb: plan.weightLb,
                barLb: (defaultGym?.defaultBar ?? .bar45lb).lb,
                roundingLb: track.roundingLb
            ) {
                let set = SetEntry(order: entry.sets.count, weightLb: warmup.weightLb, reps: warmup.reps,
                                   isWarmup: true, enteredUnit: entryUnit,
                                   loadBasis: exercise.loadBasis, implementCount: exercise.resolvedImplementCount)
                set.sessionExercise = entry
                context.insert(set)
                entry.sets.append(set)
            }
        }
        for _ in 0..<plan.sets {
            let set = SetEntry(order: entry.sets.count, weightLb: plan.weightLb, reps: plan.reps,
                               enteredUnit: entryUnit, loadBasis: exercise.loadBasis,
                               implementCount: exercise.resolvedImplementCount)
            set.sessionExercise = entry
            context.insert(set)
            entry.sets.append(set)
        }

        if PersistenceErrorCenter.shared.save(context, operation: "Starting the session") { activeSession = session }
    }

    private func startBlankSession() {
        let session = WorkoutSession(gymID: defaultGym?.id, gymName: defaultGym?.name)
        context.insert(session)
        if PersistenceErrorCenter.shared.save(context, operation: "Starting the session") { activeSession = session }
    }

    private func startProgramDay(_ program: Program, _ day: ProgramDay) {
        do {
            let session = try ProgramSession.make(program: program, day: day, context: context)
            if PersistenceErrorCenter.shared.save(context, operation: "Starting the program session") { activeSession = session }
        } catch {
            PersistenceErrorCenter.shared.report(error, operation: "Starting the program session", context: context)
        }
    }
}
