import SwiftUI
import SwiftData
import CadenceCore

/// Today: suggested next session per lift, one-tap session start,
/// gym tag, protein running total. Nothing motivational.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query private var tracks: [LiftTrack]
    @Query private var programs: [Program]
    @Query private var gyms: [Gym]
    @Query private var settingsList: [AppSettings]
    @Query private var proteinEntries: [ProteinEntry]
    @Query(filter: #Predicate<WorkoutSession> { !$0.isCompleted })
    private var openSessions: [WorkoutSession]

    @State private var activeSession: WorkoutSession?
    @State private var showGymCard = false

    private var settings: AppSettings? { settingsList.first }
    private var defaultGym: Gym? { gyms.first { $0.isDefault } ?? gyms.first }
    private var activeProgram: Program? { programs.first { $0.isActive } ?? programs.first }
    private var ownedLiftNames: Set<String> {
        guard let p = activeProgram else { return [] }
        return Set(p.days.flatMap { $0.lifts.map(\.exerciseName) })
    }

    private func nextDay(_ program: Program) -> ProgramDay? {
        program.orderedDays.first { $0.order == program.nextDayIndex } ?? program.orderedDays.first
    }

    private func programPlanLabel(_ program: Program, _ lift: ProgramLift) -> String {
        let phase = CyclePhase(rawValue: program.currentWeek) ?? .volume
        let plan = ProgramEngine.plan(
            for: CycleState(cycleNumber: program.cycleNumber, baseWeightLb: lift.baseWeightLb, nextPhase: phase, incrementLb: 0),
            roundingLb: program.roundingLb)
        return plan.label
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
                if let open = openSessions.first {
                    Section {
                        Button {
                            activeSession = open
                        } label: {
                            Label("Resume session — \(open.date.formatted(date: .abbreviated, time: .shortened))",
                                  systemImage: "play.fill")
                                .font(.headline)
                        }
                    }
                }

                if let program = activeProgram, let day = nextDay(program) {
                    Section("\(program.name) · Cycle \(program.cycleNumber)") {
                        HStack {
                            Text(day.name).font(.headline)
                            Spacer()
                            Text("Rotation \(program.currentWeek) · \(CyclePhase(rawValue: program.currentWeek)?.name ?? "")")
                                .font(.caption.bold())
                                .foregroundStyle(Theme.accent)
                        }
                        ForEach(day.orderedLifts) { lift in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lift.exerciseName).font(.subheadline.bold())
                                Text("\(lift.role.rawValue) · \(programPlanLabel(program, lift))")
                                    .font(.caption).foregroundStyle(.secondary)
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
                        Button {
                            startSession(with: track)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.exerciseName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(track.suggestion.label)
                                    .font(.title3.bold())
                                    .foregroundStyle(Theme.accent)
                                if track.mode == .cycle {
                                    Text("Cycle \(track.cycleNumber) · advances when you bank it")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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

                Section {
                    Button {
                        showGymCard = true
                    } label: {
                        Label("Gym tag", systemImage: "barcode.viewfinder")
                            .font(.headline)
                    }
                } footer: {
                    Text(defaultGym?.barcodeImageData == nil
                         ? "Add a photo of your membership barcode in Settings → Gyms."
                         : "Full brightness, ready to scan.")
                }

                Section("Protein") {
                    HStack {
                        Text("\(Int(todayProtein)) g")
                            .font(.title2.bold().monospacedDigit())
                        Text("/ \(Int(settings?.proteinTargetGrams ?? 175)) g")
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
            .sheet(isPresented: $showGymCard) {
                GymCardView(gym: defaultGym)
            }
        }
    }

    private func proteinButton(_ label: String, grams: Double) -> some View {
        Button(label) {
            context.insert(ProteinEntry(grams: grams, label: label))
            try? context.save()
        }
        .buttonStyle(.bordered)
        .font(.callout)
    }

    private func startSession(with track: LiftTrack) {
        let session = WorkoutSession(gymName: defaultGym?.name)
        context.insert(session)

        // #Predicate can't reference properties of captured objects; capture the value
        let exerciseName = track.exerciseName
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.name == exerciseName }
        )
        let exercise = try? context.fetch(descriptor).first

        let entry = SessionExercise(order: 0, exercise: exercise)
        entry.session = session
        let plan = track.suggestion
        entry.plannedWeightLb = plan.weightLb
        entry.plannedSets = plan.sets
        entry.plannedReps = plan.reps
        entry.phase = plan.phase
        context.insert(entry)
        session.exercises.append(entry)

        // Pre-fill warmup ramp + working sets. All editable.
        if exercise?.type == .barbell {
            for warmup in WarmupRamp.ramp(workingLb: plan.weightLb) {
                let set = SetEntry(order: entry.sets.count, weightLb: warmup.weightLb, reps: warmup.reps, isWarmup: true)
                set.sessionExercise = entry
                context.insert(set)
                entry.sets.append(set)
            }
        }
        for _ in 0..<plan.sets {
            let set = SetEntry(order: entry.sets.count, weightLb: plan.weightLb, reps: plan.reps)
            set.sessionExercise = entry
            context.insert(set)
            entry.sets.append(set)
        }

        try? context.save()
        activeSession = session
    }

    private func startBlankSession() {
        let session = WorkoutSession(gymName: defaultGym?.name)
        context.insert(session)
        try? context.save()
        activeSession = session
    }

    private func startProgramDay(_ program: Program, _ day: ProgramDay) {
        let session = ProgramSession.make(program: program, day: day, context: context)
        try? context.save()
        activeSession = session
    }
}
