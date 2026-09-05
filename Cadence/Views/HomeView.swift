import SwiftUI
import SwiftData
import CadenceCore

/// Today: suggested next session per lift, one-tap session start,
/// gym tag. Nothing motivational.
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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(RestTimer.self) private var restTimer
    @Environment(WorkoutClock.self) private var workoutClock
    @Query private var tracks: [LiftTrack]
    @Query private var programs: [Program]
    @State private var showProgramSwitcher = false
    @State private var switcherError: String?
    @Query private var exercises: [Exercise]
    @Query(sort: \CoachingDecision.date, order: .reverse) private var coachingDecisions: [CoachingDecision]
    @Query private var gyms: [Gym]
    @Query private var settingsList: [AppSettings]
    @Query private var checkIns: [CheckIn]
    @Query(sort: \TrainingInterval.startDate) private var trainingIntervals: [TrainingInterval]
    @Query(filter: #Predicate<WorkoutSession> { !$0.isCompleted })
    private var openSessions: [WorkoutSession]
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted }, sort: \WorkoutSession.date)
    private var completedSessions: [WorkoutSession]

    @State private var activeSession: WorkoutSession?
    @State private var showGymCard = false
    @State private var previewDay: ProgramDay?
    @State private var discardSession: WorkoutSession?
    @State private var coachingMessage: String?
    @State private var recoveryMessage: String?
    @State private var showCoachDetail = false
    @State private var showActivityLog = false
    @AppStorage(RootView.gymTagLastAutoDayKey) private var gymTagLastShownDay = 0.0

    private var settings: AppSettings? { settingsList.first }
    private var unitDisplay: UnitDisplay { settingsList.unitDisplay }
    private var entryUnit: WeightUnit { unitDisplay.primaryUnit }
    private var defaultGym: Gym? { gyms.first { $0.isDefault } ?? gyms.first }
    private var activeProgram: Program? { programs.first { $0.isActive } ?? programs.first }
    private var todayStamp: Double { Calendar.current.startOfDay(for: .now).timeIntervalSince1970 }
    private var prominentGymTag: Bool {
        defaultGym?.barcodeImageData == nil || gymTagLastShownDay != todayStamp
    }
    private var intervalSnapshots: [TrainingIntervalSnapshot] {
        trainingIntervals.map(\.snapshot)
    }
    private var coachingReport: CoachingReport? {
        guard let program = activeProgram, program.coachEnabled else { return nil }
        return CoachingService.report(
            program: program, sessions: completedSessions,
            exercises: exercises, checkIns: checkIns,
            intervals: intervalSnapshots
        )
    }
    private var ownedLiftNames: Set<String> {
        guard let p = activeProgram else { return [] }
        return Set(p.days.flatMap { $0.lifts.map(\.exerciseName) })
    }

    /// Advisory only — the preference used to be write-only, set by a stepper
    /// and never read back. It never blocks a session: the lifter's calendar
    /// beats the app's opinion.
    private func spacingNote(_ program: Program) -> String? {
        // `completedSessions` is oldest → newest (`recentTops` relies on that
        // order), so the most recent banked session is the last element.
        guard let last = completedSessions.last?.date else { return nil }
        // A declared break (rest/away/active recovery) overlapping the open
        // time excuses the gap entirely — a chosen break is not a lapse, and
        // nagging about spacing through it reads the calendar as a failure
        // (INV-INTERVAL-IS-NOT-A-GAP). Mirrors web home.js.
        if TrainingIntervals.gapExcused(
            fromMs: last.timeIntervalSince1970 * 1000,
            toMs: Date.now.timeIntervalSince1970 * 1000,
            intervals: intervalSnapshots
        ) { return nil }
        let elapsed = Calendar.current.dateComponents([.day], from: last, to: .now).day
        guard let shortfall = ProgramProgression.sessionSpacingShortfall(
            daysSinceLastSession: elapsed, preferredDays: program.preferredSessionSpacingDays
        ), shortfall > 0, let elapsed else { return nil }
        let since = elapsed == 0 ? "Trained today" : "\(elapsed) day\(elapsed == 1 ? "" : "s") since your last session"
        return "\(since) · you prefer \(program.preferredSessionSpacingDays). "
            + "Train anyway if today is the day that works."
    }

    /// A just-ended away interval with no session banked since deserves a
    /// re-entry suggestion, not silent resumption at full loading. Advisory
    /// only — it never blocks starting anything. Mirrors web home.js.
    private var returnFromAwayNote: String? {
        guard TrainingIntervals.recentReturnFromAway(
            nowMs: Date.now.timeIntervalSince1970 * 1000,
            lastSessionMs: completedSessions.last.map { $0.date.timeIntervalSince1970 * 1000 },
            intervals: intervalSnapshots
        ) != nil else { return nil }
        return "Back from time away — the first session back is re-entry, not a test. Ease in and let the log rebuild."
    }

    private func nextDay(_ program: Program) -> ProgramDay? {
        program.nextDay
    }

    /// The shared preview pipeline — the card must show the same honest,
    /// snapped plan the started session will store.
    private func previewPlans(_ program: Program, _ lift: ProgramLift) -> (raw: SessionPlan, snapped: SessionPlan) {
        let exercise = exercises.first { $0.name == lift.exerciseName }
        return ProgramSession.previewPlan(
            for: lift, exercise: exercise, program: program,
            phase: CyclePhase(rawValue: program.currentWeek) ?? .volume,
            planningBase: ProgramSession.planningBase(
                for: lift, exercise: exercise, program: program, sessions: completedSessions
            ),
            addedVolumeSets: ProgramSession.volumeFallbackSets(for: lift, program: program),
            gym: defaultGym
        )
    }

    private func rawProgramPlan(_ program: Program, _ day: ProgramDay, _ lift: ProgramLift) -> SessionPlan {
        previewPlans(program, lift).raw
    }

    private func programPlan(_ program: Program, _ day: ProgramDay, _ lift: ProgramLift) -> SessionPlan {
        previewPlans(program, lift).snapped
    }

    private func trackPlan(_ track: LiftTrack) -> SessionPlan {
        let plan = track.suggestion
        let exercise = exercises.first { $0.name == track.exerciseName }
        let weightLb = ProgramSession.achievableWeight(
            plan.weightLb, exercise: exercise, isMain: true, gym: defaultGym,
            bar: defaultGym?.defaultBar ?? .bar45lb, stepLb: track.roundingLb,
            phase: plan.phase)
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

    var body: some View {
        NavigationStack {
            List {
                // The first card is always the next action: resume beats plan.
                if let open = openSessions.max(by: { $0.date < $1.date }) {
                    Section {
                        Button { activeSession = open } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Label("Resume workout", systemImage: "play.fill").font(.title3.bold())
                                Text(openSessionLabel(open)).font(.caption).foregroundStyle(.secondary)
                                if workoutClock.isTracking(sessionID: open.id), let start = workoutClock.startDate {
                                    TimelineView(.periodic(from: start, by: 1)) { timeline in
                                        Text(workoutElapsedLabel(from: start, to: workoutClock.pausedAt ?? timeline.date))
                                            .font(.title2.bold().monospacedDigit()).foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("resume-session")
                        Button(role: .destructive) { discardSession = open } label: {
                            Label("Discard session", systemImage: "trash").font(.caption)
                        }
                    }
                    // The hero shows the newest open session, but this screen
                    // can create more — and an older one (including the one
                    // the workout clock is timing) must never lose its resume
                    // and discard controls behind a newer session.
                    let others = openSessions.filter { $0.id != open.id }.sorted { $0.date > $1.date }
                    if !others.isEmpty {
                        Section("Other open sessions") {
                            ForEach(others) { other in
                                Button { activeSession = other } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Label(
                                            workoutClock.isTracking(sessionID: other.id)
                                                ? (workoutClock.isPaused ? "Workout paused" : "Workout in progress")
                                                : "Open session",
                                            systemImage: workoutClock.isTracking(sessionID: other.id) ? "stopwatch" : "arrow.forward"
                                        )
                                        .font(.subheadline.bold())
                                        Text(openSessionLabel(other)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .swipeActions {
                                    Button(role: .destructive) { discardSession = other } label: {
                                        Label("Discard", systemImage: "trash")
                                    }
                                }
                                // The swipe alone is invisible to VoiceOver and
                                // to anyone who doesn't reach for it — the
                                // visible control is the real affordance.
                                Button(role: .destructive) { discardSession = other } label: {
                                    Label("Discard session", systemImage: "trash").font(.caption)
                                }
                                .accessibilityHint("Deletes this unfinished session without banking it")
                            }
                        }
                    }
                } else if let program = activeProgram, let day = nextDay(program) {
                    Section {
                        Button { previewProgramDay(program, fallback: day) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Next workout").font(.caption.bold()).foregroundStyle(.secondary)
                                    Text(day.name).font(.title2.bold())
                                    Text("\(program.name) · Cycle \(program.cycleNumber)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                RotationGlyph(week: program.currentWeek)
                            }
                            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        }
                        Button("Start \(day.name)") { startProgramDay(program, day) }
                            .buttonStyle(.borderedProminent)
                    }
                }

                if let program = activeProgram, !program.orderedDays.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(program.orderedDays) { day in
                                    Text("\(day.order == program.nextDayIndex ? "NOW " : day.order < program.nextDayIndex ? "✓ " : "")\(day.name)")
                                        .font(.caption.bold())
                                        .foregroundStyle(day.order == program.nextDayIndex ? Theme.accent : .secondary)
                                    if day.id != program.orderedDays.last?.id { Text("→").foregroundStyle(.tertiary) }
                                }
                            }
                        }
                        .accessibilityLabel("Program sequence, \(nextDay(program)?.name ?? "next day") is now")
                    }
                }

                // Keychain replacement stays prominent until today's scan, then
                // collapses to one compact 44-point action.
                Section {
                    Button {
                        gymTagLastShownDay = todayStamp
                        showGymCard = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "barcode.viewfinder")
                            Text(prominentGymTag ? "Gym Tag" : "Scan gym tag").font(.headline)
                            Spacer()
                            if prominentGymTag {
                                Text(defaultGym?.barcodeImageData == nil ? "Add barcode" : "Ready to scan")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: Theme.bigTap, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(prominentGymTag ? Theme.accent : Color(.tertiarySystemFill))
                    .accessibilityHint("Shows the default membership barcode at full brightness")
                }

                if let recoveryMessage {
                    Section {
                        Label(recoveryMessage, systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline.bold())
                            .foregroundStyle(Theme.accent)
                            .accessibilityLabel(Text(recoveryMessage))
                    }
                }

                if let note = returnFromAwayNote {
                    Section {
                        Label(note, systemImage: "figure.walk.arrival")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(Text(note))
                    }
                }

                if let program = activeProgram, let report = coachingReport {
                    Section {
                        Button { showCoachDetail = true } label: {
                            HStack(spacing: 10) {
                                Circle().fill(readinessColor(report.currentReadiness)).frame(width: 12, height: 12)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Coach · \(report.currentReadiness.name)").font(.headline)
                                    Text(readinessSummary(report)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                HStack(spacing: 4) {
                                    ForEach(Array(report.rotations.suffix(4)), id: \.key) { rotation in
                                        Circle().fill(readinessColor(rotation.readiness)).frame(width: 7, height: 7)
                                    }
                                }
                                .accessibilityLabel("Recent rotation readiness")
                                Spacer()
                                let count = visibleRecommendations(report, program: program).count
                                Text("\(count) recommendation\(count == 1 ? "" : "s")")
                                    .font(.caption.bold()).foregroundStyle(Theme.accent)
                            }
                            .frame(minHeight: Theme.bigTap)
                        }
                    }

                }

                if let program = activeProgram, let day = nextDay(program) {
                    Section {
                        // The switcher lives where training starts (epic #155
                        // Stage 4): resuming another block or trying a
                        // different methodology is one tap from Today instead
                        // of buried in Settings.
                        Button("Switch program") { showProgramSwitcher = true }
                            .accessibilityLabel("Switch training program")
                    } header: {
                        Text("\(program.name) · Cycle \(program.cycleNumber)")
                    }
                    Section {
                        // Tapping the day opens the full preview — browse the
                        // whole workout without starting it.
                        Button {
                            previewProgramDay(program, fallback: day)
                        } label: {
                            HStack(spacing: 8) {
                                Text(day.name).font(.headline)
                                Spacer()
                                // Position only. The phase NAME moved onto the
                                // slots it actually describes — this counter is
                                // shared by slots whose prescriptions have
                                // nothing to do with each other.
                                RotationGlyph(week: program.currentWeek)
                                Text("R\(min(max(program.currentWeek, 1), ProgramProgression.deloadWeek))")
                                    .font(.caption.bold().monospacedDigit())
                                    .foregroundStyle(Theme.accent)
                                    .accessibilityHidden(true)
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        if let note = spacingNote(program) {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(day.orderedLifts) { lift in
                            let target = rawProgramPlan(program, day, lift)
                            let plan = programPlan(program, day, lift)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        NavigationLink {
                                            ExerciseDetailByNameView(name: lift.exerciseName)
                                        } label: {
                                            Text(lift.exerciseName).font(.subheadline.bold())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityHint("Shows exercise history, program cycle, and settings")
                                        SlotPrescriptionBadge(
                                            lift: lift, rotation: program.currentWeek,
                                            movementGroup: exercises.first { $0.name == lift.exerciseName }?.movementGroup,
                                            focus: program.focus
                                        )
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
                                    let previewExercise = exercises.first(where: { $0.name == lift.exerciseName })
                                    let type = previewExercise?.type
                                    if type == .barbell {
                                        BarbellView(weightLb: plan.weightLb, unit: entryUnit,
                                                    bar: defaultGym?.defaultBar ?? .bar45lb, gym: defaultGym,
                                                    targetWeightLb: target.weightLb,
                                                    stationDenomination: previewExercise?.stationDenomination,
                                                    plateStyle: previewExercise?.movementGroup == "olympic" ? .bumper : .steel)
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

                Section {
                    Button { showActivityLog = true } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("Wood Splitting")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "plus")
                                    .font(.headline)
                                    .foregroundStyle(Theme.accent)
                            }
                            Text("Log duration, effort, maul and wood counts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("activity-quick-log")
                    .accessibilityHint("Banks off-program physical work without starting a training session")
                } header: {
                    Text("Ad-hoc work")
                } footer: {
                    Text("Hard work outside the program. It appears in History but never advances your training cycle or lifting volume.")
                }

            }
            .accessibilityIdentifier("home-screen")
            .navigationTitle("Cadence")
            .sheet(isPresented: $showProgramSwitcher) {
                NavigationStack {
                    ProgramSwitcherView(onError: { switcherError = $0 })
                }
            }
            .alert("Can't switch programs", isPresented: Binding(
                get: { switcherError != nil }, set: { if !$0 { switcherError = nil } }
            )) {
                Button("OK") { switcherError = nil }
            } message: {
                Text(switcherError ?? "")
            }
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
            .sheet(isPresented: $showActivityLog) {
                ActivityQuickLogView()
            }
            .sheet(isPresented: $showCoachDetail) {
                if let program = activeProgram, let report = coachingReport {
                    NavigationStack {
                        List {
                            Section("\(report.currentReadiness.name) · per rotation") {
                                Text(readinessSummary(report))
                                if let latest = report.rotations.last {
                                    Text("\(latest.completedWorkingSets)/\(latest.plannedWorkingSets) work sets · \(Int(latest.conditioningMinutes.rounded())) conditioning min")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                            Section("Recommendations") {
                                ForEach(visibleRecommendations(report, program: program)) { recommendation in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(recommendation.title).font(.headline)
                                        Text(recommendation.explanation).font(.caption).foregroundStyle(.secondary)
                                        HStack {
                                            Button("Apply") { apply(recommendation, report: report, program: program) }
                                                .buttonStyle(.borderedProminent)
                                            Button("Not now") { deferRecommendation(recommendation, report: report, program: program) }
                                                .buttonStyle(.bordered)
                                        }
                                    }
                                }
                                if let coachingMessage { Text(coachingMessage).foregroundStyle(Theme.accent) }
                            }
                        }
                        .navigationTitle("Coach")
                        .toolbar { Button("Done") { showCoachDetail = false } }
                    }
                }
            }
            .task {
                reconcileActiveRecovery()
                openPendingSessionIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { reconcileActiveRecovery() }
            }
            .onChange(of: pendingSessionID) { _, _ in openPendingSessionIfNeeded() }
            .confirmationDialog("Discard this open session?", isPresented: Binding(
                get: { discardSession != nil },
                set: { if !$0 { discardSession = nil } }
            ), titleVisibility: .visible) {
                Button("Discard session", role: .destructive) {
                    guard let session = discardSession else { return }
                    if workoutClock.isTracking(sessionID: session.id) {
                        restTimer.stop()
                    }
                    // Scoped teardown: ends the clock only if this session
                    // owns it; otherwise drops just this session's leftovers —
                    // its durable record and any orphaned Live Activity a
                    // force-quit left on the lock screen (which begin() would
                    // otherwise adopt ahead of the cleared record and
                    // resurrect the discarded stopwatch).
                    workoutClock.release(sessionID: session.id)
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

    private func visibleRecommendations(_ report: CoachingReport, program: Program) -> [CoachingRecommendation] {
        let handled = Set(coachingDecisions.filter { $0.programID == program.id }.map(\.recommendationID))
        return report.recommendations.filter { !handled.contains($0.id) }
    }

    private func readinessColor(_ state: ReadinessState) -> Color {
        switch state {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        case .unknown: return .secondary
        }
    }

    private func workoutElapsedLabel(from start: Date, to end: Date) -> String {
        let total = max(0, Int(end.timeIntervalSince(start)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    private func readinessSummary(_ report: CoachingReport) -> String {
        guard let latest = report.rotations.last else {
            return "Bank program days to establish an output baseline."
        }
        return latest.reasons.first ?? "Readiness is computed from completed work and next-exposure output."
    }

    private func apply(_ recommendation: CoachingRecommendation, report: CoachingReport, program: Program) {
        do {
            coachingMessage = try CoachingService.accept(
                recommendation,
                for: program,
                exercises: exercises,
                sessions: completedSessions,
                evidence: report.rotations.last?.reasons ?? [],
                context: context
            )
        } catch {
            // Every other user-initiated write goes through the error center,
            // whose contract is rollback-on-failure. Without it, a failed
            // accept leaves the half-applied program mutation and the audit
            // row as dirty state the NEXT unrelated save would silently
            // commit under a different operation label.
            PersistenceErrorCenter.shared.report(error, operation: "Applying the coaching recommendation", context: context)
            coachingMessage = error.localizedDescription
        }
    }

    private func deferRecommendation(_ recommendation: CoachingRecommendation, report: CoachingReport, program: Program) {
        do {
            try CoachingService.record(
                .deferred,
                recommendation: recommendation,
                program: program,
                evidence: report.rotations.last?.reasons ?? [],
                context: context
            )
            coachingMessage = "Deferred. The program was not changed."
        } catch {
            // Same rollback contract as accept: a failed decision insert must
            // not linger as dirty state in the shared context.
            PersistenceErrorCenter.shared.report(error, operation: "Recording the coaching decision", context: context)
            coachingMessage = error.localizedDescription
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

    private func reconcileRecoveryBridge(for program: Program) throws -> Bool {
        guard let result = try SessionCompletion.reconcileRecoveryBridge(
            program: program, context: context
        ) else { return false }
        recoveryMessage = result.message
        return true
    }

    private func reconcileActiveRecovery() {
        guard let program = activeProgram else { return }
        do {
            _ = try reconcileRecoveryBridge(for: program)
        } catch {
            PersistenceErrorCenter.shared.report(
                error, operation: "Finishing the recovery bridge", context: context
            )
        }
    }

    private func previewProgramDay(_ program: Program, fallback day: ProgramDay) {
        do {
            let changed = try reconcileRecoveryBridge(for: program)
            previewDay = changed ? (nextDay(program) ?? day) : day
        } catch {
            PersistenceErrorCenter.shared.report(
                error, operation: "Opening the program preview", context: context
            )
        }
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
        entry.stampBarID(for: exercise, bar: defaultGym?.defaultBar ?? .bar45lb)
        let plan = trackPlan(track)
        entry.targetWeightLb = track.suggestion.weightLb
        entry.plannedWeightLb = plan.weightLb
        entry.plannedSets = plan.sets
        entry.plannedReps = plan.reps
        entry.phase = plan.phase
        context.insert(entry)
        session.exercises.append(entry)

        // Pre-fill warmup ramp + working sets. All editable.
        if exercise.type == .barbell {
            let theoretical = WarmupRamp.ramp(
                workingLb: plan.weightLb,
                barLb: (defaultGym?.defaultBar ?? .bar45lb).lb,
                roundingLb: track.roundingLb,
                includeEmptyBar: ProgramSession.includesEmptyBarWarmup(for: exercise)
            )
            for warmup in ProgramSession.achievableWarmups(
                theoretical, workingLb: plan.weightLb,
                gym: defaultGym, bar: defaultGym?.defaultBar ?? .bar45lb, exercise: exercise
            ) {
                let set = SetEntry(order: entry.sets.count, weightLb: warmup.weightLb, reps: warmup.reps,
                                   isWarmup: true, enteredUnit: entryUnit,
                                   loadBasis: exercise.loadBasis, implementCount: exercise.resolvedImplementCount,
                                   targetWeightLb: warmup.weightLb, plannedWeightLb: warmup.weightLb,
                                   plannedReps: warmup.reps, prescriptionBlock: .warmup)
                context.insert(set)
                entry.sets.append(set)
            }
        } else if exercise.type == .dumbbell {
            for warmup in WarmupRamp.dumbbellRamp(
                workingLb: plan.weightLb,
                roundingLb: ProgramEngine.loadStep(
                    programRoundingLb: track.roundingLb,
                    exerciseType: exercise.typeRaw
                )
            ) {
                let set = SetEntry(
                    order: entry.sets.count, weightLb: warmup.weightLb, reps: warmup.reps,
                    isWarmup: true, isPerSide: exercise.isUnilateral, enteredUnit: entryUnit,
                    loadBasis: exercise.loadBasis, implementCount: exercise.resolvedImplementCount,
                    targetWeightLb: warmup.weightLb, plannedWeightLb: warmup.weightLb,
                    plannedReps: warmup.reps, prescriptionBlock: .warmup
                )
                context.insert(set)
                entry.sets.append(set)
            }
        }
        for _ in 0..<plan.sets {
            let set = SetEntry(order: entry.sets.count, weightLb: plan.weightLb, reps: plan.reps,
                               enteredUnit: entryUnit, loadBasis: exercise.loadBasis,
                               implementCount: exercise.resolvedImplementCount,
                               targetWeightLb: track.suggestion.weightLb,
                               plannedWeightLb: plan.weightLb, plannedReps: plan.reps,
                               prescriptionBlock: .work)
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
            let changed = try reconcileRecoveryBridge(for: program)
            let resolvedDay = changed ? (nextDay(program) ?? day) : day
            let session = try ProgramSession.make(program: program, day: resolvedDay, context: context)
            if PersistenceErrorCenter.shared.save(context, operation: "Starting the program session") { activeSession = session }
        } catch {
            PersistenceErrorCenter.shared.report(error, operation: "Starting the program session", context: context)
        }
    }
}

/// Resume another block, or start a fresh one in any methodology — every slot
/// seeded from current global history through the anchor resolver, never a
/// weight prompt (epic #155 Stage 4). Activation itself belongs to
/// ProgramActivationService so exclusivity, cursor preservation, and the
/// open-session refusal have exactly one implementation.
private struct ProgramSwitcherView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var programs: [Program]
    let onError: (String) -> Void

    var body: some View {
        List {
            let resumable = programs.filter { !$0.isActive }
            if !resumable.isEmpty {
                Section("Resume") {
                    ForEach(resumable) { program in
                        Button {
                            act { try ProgramActivationService.activate(program, context: context) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(program.name)
                                // Resuming picks up exactly where this block
                                // left off — nothing is re-derived.
                                Text("Cycle \(program.cycleNumber) · rotation \(program.currentWeek)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section {
                ForEach(ProgramTemplateData.all, id: \.id) { template in
                    Button {
                        act { _ = try ProgramActivationService.startBlock(template, context: context) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                            Text(template.tagline).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Start a new block")
            } footer: {
                Text("Your history, PRs and charts stay whole either way — a new "
                     + "block starts from the weights you have already earned.")
            }
        }
        .navigationTitle("Switch program")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
    }

    private func act(_ work: () throws -> Void) {
        do {
            try work()
            guard PersistenceErrorCenter.shared.save(context, operation: "Switching programs") else { return }
            dismiss()
        } catch {
            dismiss()
            onError(error.localizedDescription)
        }
    }
}
