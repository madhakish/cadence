import SwiftUI
import SwiftData
import Charts
import CadenceCore

/// Sessions, milestones, and per-lift progression charts.
struct HistoryView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted },
           sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \Milestone.date, order: .reverse) private var milestones: [Milestone]
    @Query private var settingsList: [AppSettings]
    @Query private var programs: [Program]
    @Query private var exercises: [Exercise]
    @Query private var checkIns: [CheckIn]

    @State private var view: ViewMode = .rotations
    @State private var rotationDetail: String?

    enum ViewMode: String, CaseIterable {
        case list = "Log"
        case rotations = "Rotations"
        case charts = "Charts"
        case milestones = "Milestones"
    }

    var body: some View {
        NavigationStack {
            VStack {
                Picker("View", selection: $view) {
                    ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch view {
                case .list: sessionList
                case .rotations: rotationList
                case .charts: ProgressionChartsView()
                case .milestones: milestoneList
                }
            }
            .navigationTitle("History")
            .alert("Rotation details", isPresented: Binding(
                get: { rotationDetail != nil }, set: { if !$0 { rotationDetail = nil } }
            )) {
                Button("OK") { rotationDetail = nil }
            } message: {
                Text(rotationDetail ?? "")
            }
        }
    }

    private var rotationList: some View {
        List {
            if let program = programs.first(where: { $0.isActive }) ?? programs.first {
                let report = CoachingService.report(
                    program: program, sessions: sessions,
                    exercises: exercises, checkIns: checkIns
                )
                Section("Rolling load") {
                    LabeledContent("14 days", value: rollingSummary(days: 14))
                    LabeledContent("28 days", value: rollingSummary(days: 28))
                    Text("Working sets and conditioning are separate; warm-ups are excluded.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !report.rotations.isEmpty {
                    let rotations = Array(Set(report.rotations.map { $0.key.rotation })).sorted()
                    let cycles = Dictionary(grouping: report.rotations, by: { $0.key.cycleNumber })
                    Section("Cycle matrix") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                                GridRow {
                                    Text("Cycle").font(.caption.bold()).foregroundStyle(.secondary)
                                    ForEach(rotations, id: \.self) { Text("R\($0)").font(.caption.bold()) }
                                }
                                ForEach(cycles.keys.sorted(by: >), id: \.self) { cycle in
                                    GridRow {
                                        Text("\(cycle)").font(.headline.monospacedDigit())
                                        ForEach(rotations, id: \.self) { number in
                                            if let rotation = cycles[cycle]?.first(where: { $0.key.rotation == number }) {
                                                Button {
                                                    rotationDetail = rotationDetailText(rotation)
                                                } label: {
                                                    VStack(spacing: 3) {
                                                        Image(systemName: readinessIcon(rotation.readiness))
                                                            .foregroundStyle(readinessColor(rotation.readiness))
                                                        Text("\(rotation.completedWorkingSets)/\(rotation.plannedWorkingSets)")
                                                            .font(.caption2.monospacedDigit())
                                                        Text("\(Int(rotation.conditioningMinutes.rounded()))m")
                                                            .font(.caption2).foregroundStyle(.secondary)
                                                    }
                                                    .frame(minWidth: 54, minHeight: 54)
                                                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityLabel("Cycle \(cycle), rotation \(number), \(rotation.readiness.name), \(rotation.completedWorkingSets) of \(rotation.plannedWorkingSets) sets")
                                            } else {
                                                Color.clear.frame(width: 54, height: 54)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if report.rotations.isEmpty {
                    Text("Complete a full program rotation to establish the first baseline.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("No program", systemImage: "list.bullet.clipboard",
                                       description: Text("Create a program to group training by rotation."))
            }
        }
    }

    private func rollingSummary(days: Int) -> String {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        let recent = sessions.filter { $0.date >= cutoff }
        let work = recent.flatMap(\.exercises).flatMap(\.workingSets).filter {
            guard let exercise = $0.sessionExercise?.exercise else { return true }
            return !exercise.movementPattern.isConditioning
        }.count
        let seconds = recent.flatMap(\.exercises).filter { $0.exercise?.movementPattern.isConditioning == true }
            .flatMap(\.workingSets).compactMap(\.durationSeconds).reduce(0, +)
        return "\(work) work sets · \(seconds / 60) min conditioning"
    }

    private func readinessIcon(_ state: ReadinessState) -> String {
        switch state {
        case .green: return "circle.fill"
        case .yellow: return "circle.lefthalf.filled"
        case .red: return "exclamationmark.octagon.fill"
        case .unknown: return "circle.dotted"
        }
    }

    private func readinessColor(_ state: ReadinessState) -> Color {
        switch state {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        case .unknown: return .gray
        }
    }

    private func rotationDetailText(_ rotation: RotationAssessment) -> String {
        let reasons = rotation.reasons.isEmpty ? "No recommendation reasons recorded." : rotation.reasons.joined(separator: "\n")
        return "Cycle \(rotation.key.cycleNumber) · Rotation \(rotation.key.rotation)\n\n"
            + "Readiness: \(rotation.readiness.name)\n"
            + "Completed/planned: \(rotation.completedWorkingSets)/\(rotation.plannedWorkingSets) work sets\n"
            + "Conditioning: \(Int(rotation.conditioningMinutes.rounded())) min\n\n\(reasons)"
    }

    private var sessionList: some View {
        // Session volume relative to the biggest on record — the thin bar under
        // each row makes trends scannable while scrolling.
        let maxVolume = max(1, sessions.map(volumeOf).max() ?? 1)
        return List {
            ForEach(monthGroups, id: \.0) { month, items in
                Section(month) {
                    ForEach(items) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let lead = leadLift(session) {
                                    HStack(spacing: 6) {
                                        Text(lead.name).font(.callout.bold())
                                        Text(lead.set)
                                            .font(.callout.bold().monospacedDigit())
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                                let rest = restLine(session)
                                if !rest.isEmpty {
                                    Text(rest)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                let vol = volumeOf(session)
                                if vol > 0 {
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color(.tertiarySystemFill))
                                            Capsule().fill(Theme.accent.opacity(0.75))
                                                .frame(width: max(4, geo.size.width * vol / maxVolume))
                                        }
                                    }
                                    .frame(height: 3)
                                    .padding(.top, 3)
                                }
                            }
                        }
                    }
                }
            }
            if sessions.isEmpty {
                Text(Copy.emptyHistory).foregroundStyle(.secondary)
            }
        }
    }

    private func volumeOf(_ session: WorkoutSession) -> Double {
        session.exercises.reduce(0) { $0 + $1.workingVolumeLb }
    }

    /// The heaviest lift of the day, emphasized; everything else rides in the sub line.
    private func leadLift(_ session: WorkoutSession) -> (name: String, set: String)? {
        let tops = session.orderedExercises.compactMap { entry -> (String, SetEntry)? in
            guard let name = entry.exercise?.name, let top = entry.topSet else { return nil }
            return (name, top)
        }
        guard let lead = tops.max(by: { $0.1.weightLb < $1.1.weightLb }) else { return nil }
        let w = lead.1.weightLb == 0 ? "BW" : (settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: lead.1.weightLb)
        return (lead.0, "\(w)×\(lead.1.reps)")
    }

    private func restLine(_ session: WorkoutSession) -> String {
        let tops = session.orderedExercises.compactMap { entry -> (String, SetEntry)? in
            guard let name = entry.exercise?.name, let top = entry.topSet else { return nil }
            return (name, top)
        }
        guard let leadName = tops.max(by: { $0.1.weightLb < $1.1.weightLb })?.0 else { return "" }
        return tops.filter { $0.0 != leadName }
            .map { "\($0.0) \((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: $0.1.weightLb))×\($0.1.reps)" }
            .joined(separator: " · ")
    }

    private var milestoneList: some View {
        List(milestones) { milestone in
            VStack(alignment: .leading, spacing: 2) {
                Label(milestone.label, systemImage: "flag.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                Text(milestone.date.formatted(date: .long, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var monthGroups: [(String, [WorkoutSession])] {
        let groups = Dictionary(grouping: sessions) {
            $0.date.formatted(.dateTime.year().month(.wide))
        }
        return groups.sorted { ($0.value.first?.date ?? .distantPast) > ($1.value.first?.date ?? .distantPast) }
    }

    private func sessionLine(_ session: WorkoutSession) -> String {
        session.orderedExercises.compactMap { entry -> String? in
            guard let name = entry.exercise?.name, let top = entry.topSet else { return nil }
            return "\(name) \((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: top.weightLb))×\(top.reps)"
        }.joined(separator: " · ")
    }
}

// MARK: - Session detail

struct SessionDetailView: View {
    let session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]
    @AppStorage("healthReadEnabled") private var healthReadEnabled = false
    @State private var healthMiles: Double?
    @State private var healthEnergyKcal: Double?
    @State private var didCheckHealth = false

    /// The conditioning sets this session actually performed. `workingSets` is
    /// already completed-and-non-warmup: a set left planned, or skipped after
    /// being edited, was not trained and must neither inflate the comparison
    /// nor be rewritten by adopting Health's number.
    private var conditioningSets: [SetEntry] {
        session.orderedExercises
            .filter { $0.exercise?.type == .conditioning }
            .flatMap(\.workingSets)
    }

    /// [INV-STAIRS-COUNT-FLIGHTS] Conditioning that measures ground covered —
    /// the sets a Health distance can honestly be compared against and written
    /// onto. A flight count is not a distance, and spreading miles across one
    /// would invent a measurement the machine never reported.
    ///
    /// Keyed on what each set HOLDS, not on the movement alone: a climb logged
    /// in miles before flights existed is still a logged distance, and dropping
    /// it here while `loggedMiles` still counted it would make the comparison
    /// and the rewrite disagree — every tap of "Use Health's…" would then move
    /// the total further from Health instead of onto it.
    private var distanceLoggingSets: [SetEntry] {
        conditioningSets.filter { set in
            if (set.flights ?? 0) > 0 { return false }
            if (set.distanceMiles ?? 0) > 0 { return true }
            // Nothing logged either way: only a movement that covers ground can
            // receive the whole-total fallback below.
            let name = set.sessionExercise?.exercise?.name ?? ""
            return !CardioFormat.climbsFlights(exerciseName: name)
        }
    }

    /// Everything this session logged as conditioning distance. Same basis as
    /// the rewrite, so adopting Health's number lands exactly on it.
    private var loggedMiles: Double? {
        let total = distanceLoggingSets.compactMap(\.distanceMiles).reduce(0, +)
        return total > 0 ? total : nil
    }

    private var healthVerdict: HealthComparison.Verdict {
        HealthComparison.compare(loggedMiles: loggedMiles, healthMiles: healthMiles)
    }

    /// The window to ask Health about: session creation to completion.
    ///
    /// Bounded to a single day, mirroring the guard the Health *write* path
    /// already applies in `SessionCompletion`. A session opened Monday and
    /// banked Thursday spans three days, and every unrelated walk or ride in
    /// that stretch would be fully contained in it — so it would pass the
    /// majority-overlap test, inflate the verdict, and be written into the log
    /// by the adopt button. When the window is not trustworthy there is no
    /// second opinion to offer.
    private var healthWindow: (start: Date, end: Date)? {
        guard let end = session.completedAt, end > session.date,
              Calendar.current.isDate(end, inSameDayAs: session.date) else { return nil }
        return (session.date, end)
    }

    var body: some View {
        List {
            if !session.notes.isEmpty {
                Section("Notes") { Text(session.notes) }
            }
            healthSection
            ForEach(session.orderedExercises) { entry in
                Section {
                    ForEach(entry.orderedSets) { set in
                        HStack {
                            // Cardio sets carry distance/time/incline, not
                            // weight×reps — same shared label as the logger.
                            // Lookup via plain helper funcs, not inline lets
                            // (type-checker budget — see CompileRegressionTests).
                            Text(Self.setLine(set, type: entry.exercise?.type,
                                              unitDisplay: settingsList.first?.unitDisplay ?? .lbPrimary))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(set.isWarmup ? .secondary : .primary)
                            if entry.exercise?.type != .conditioning && entry.exercise?.type != .timed {
                                Text("× \(set.reps)\(set.isPerSide ? "/side" : "")")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !set.isWarmup && set.status != .completed {
                                Text(set.status.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !set.flags.isEmpty {
                                Text(set.flags.map(\.rawValue).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(Theme.warn)
                            }
                            if let site = set.bodyFlagSite {
                                Label(site.rawValue, systemImage: "bolt.heart.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.hardStop)
                            }
                        }
                    }
                    if !entry.notes.isEmpty {
                        Text(entry.notes).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text(entry.exercise?.name ?? "Exercise")
                        if let phaseLabel = entry.truthfulPhaseLabel {
                            Text(phaseLabel).foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
        }
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
        .task {
            // One lookup per open, and only when there is something to compare
            // and a window to compare it over.
            guard !didCheckHealth, healthReadEnabled, let window = healthWindow else { return }
            didCheckHealth = true
            async let miles = HealthKitService.shared
                .conditioningDistanceMiles(start: window.start, end: window.end)
            async let energy = HealthKitService.shared
                .activeEnergyKilocalories(start: window.start, end: window.end)
            healthMiles = await miles
            healthEnergyKcal = await energy
        }
    }

    /// [INV-HEALTH-IS-A-SECOND-OPINION] Both numbers, side by side, and an
    /// explicit tap to take Health's. Nothing here writes on its own, and a
    /// session with nothing in Health is silent rather than alarming.
    @ViewBuilder
    private var healthSection: some View {
        if healthReadEnabled, healthWindow != nil, showsHealthRow || healthEnergyKcal != nil {
            Section {
                if showsHealthRow {
                    Text(HealthComparison.label(healthVerdict))
                        .font(.callout)
                        .foregroundStyle(healthVerdict.isDiscrepancy ? Theme.warn : .secondary)
                    if let miles = adoptableMiles {
                        Button("Use Health's \(Weight.trim(miles, decimals: 2)) mi") {
                            adoptHealthDistance(miles)
                        }
                        .font(.callout)
                    }
                }
                // Read-only. Cadence has no heart rate and never writes an
                // energy figure of its own, so this is purely what Health
                // measured for the window.
                if let kcal = healthEnergyKcal {
                    LabeledContent("Energy", value: "\(Int(kcal.rounded())) kcal")
                        .font(.callout)
                }
            } header: {
                Text("Health")
            } footer: {
                Text("Your log stays the record. Adopting rewrites only this session's conditioning distance.")
            }
        }
    }

    /// Health's number is only offerable when there is a performed conditioning
    /// set to write it onto. Health finding a run for a session that logged no
    /// conditioning at all is worth reporting, but the button would be a no-op.
    private var adoptableMiles: Double? {
        guard !distanceLoggingSets.isEmpty else { return nil }
        return healthVerdict.adoptableMiles
    }

    /// Nothing to say, and an unworn watch, are both silence rather than a
    /// finding worth its own row.
    private var showsHealthRow: Bool {
        switch healthVerdict {
        case .neither, .onlyLogged: return false
        case .agree, .healthHigher, .loggedHigher, .onlyHealth: return true
        }
    }

    /// Both adoption paths round the same way, so a single-set session and a
    /// split one store comparably clean values.
    private static func roundedMiles(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    /// Write Health's number onto the single conditioning set, or spread it
    /// across several in proportion to what they already hold, so a two-leg
    /// walk keeps its shape instead of collapsing into the first set.
    private func adoptHealthDistance(_ miles: Double) {
        let sets = distanceLoggingSets
        guard !sets.isEmpty else { return }
        let existing = sets.compactMap(\.distanceMiles).reduce(0, +)
        if existing > 0 {
            for set in sets {
                guard let current = set.distanceMiles, current > 0 else { continue }
                set.distanceMiles = Self.roundedMiles(miles * (current / existing))
            }
        } else {
            sets.first?.distanceMiles = Self.roundedMiles(miles)
        }
        _ = PersistenceErrorCenter.shared.save(context, operation: "Adopting Health's distance")

        healthMiles = miles
    }

    /// Lead label for a set line: cardio → the shared distance/time/incline
    /// label; lifts → weight (both units) or BW.
    private static func setLine(_ set: SetEntry, type: ExerciseType?, unitDisplay: UnitDisplay) -> String {
        if type == .conditioning {
            return CardioFormat.setLabel(distanceMiles: set.distanceMiles,
                                         durationSeconds: set.durationSeconds,
                                         inclinePercent: set.inclinePercent,
                                         loadLb: set.weightLb,
                                         flights: set.flights)
        }
        if type == .timed { return CardioFormat.durationLabel(seconds: set.durationSeconds ?? 0) }
        return set.weightLb == 0 ? "BW" : unitDisplay.format(lb: set.weightLb)
    }
}

// MARK: - Progression charts

struct ProgressionChartsView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted }, sort: \WorkoutSession.date)
    private var sessions: [WorkoutSession]
    @Query(filter: #Predicate<Exercise> { $0.categoryRaw == "Main" }, sort: \Exercise.name)
    private var mainLifts: [Exercise]
    @Query private var settingsList: [AppSettings]
    @Query private var programs: [Program]

    // Defaults to the first main lift in the library on appear — no
    // hardcoded exercise name (the library is user data).
    @State private var selectedLift = ""
    @State private var metric: Metric = .topSet
    @State private var intent: ChartIntent = .mainProgression
    @State private var selectedDate: Date?
    /// Off by default: the chart's job is what happened, and a forecast is
    /// something the lifter asks for rather than something they are handed.
    @State private var horizon: TrendProjection.Horizon = .off

    enum Metric: String, CaseIterable {
        case topSet = "Working weight"
        case estimatedMax = "Est. 1RM"
        case volume = "Volume"
        case all = "Weight + e1RM"
        /// Best completed working set's reps — the direct analogue of
        /// "heaviest set" for a lift whose load never changes.
        case reps = "Reps"
    }

    enum ChartIntent: String, CaseIterable {
        case mainProgression = "Main progression"
        case compareRoles = "Compare program roles"
        case compareRotations = "Compare like rotations"
    }

    /// A lift can hold a MAIN slot on one day and a COMPLEMENTARY slot on
    /// another at a much lighter base. Charting both as one line produced a
    /// sawtooth between two unrelated progressions.
    ///
    /// The third case is unprogrammed work. Inside a PROGRAM session, an entry
    /// with no role is extra work the lifter added — a few light squats on an
    /// upper day — and charting it as main dragged the progression line down to
    /// weights that were never a main effort. In a session with no program at
    /// all, an entry with no role IS the record for that lift, so it stays
    /// main. Mirrors web `chartRoleOf`.
    private enum ChartRole: String, CaseIterable {
        case main, complementary, extra
        static func of(_ entry: SessionExercise, in session: WorkoutSession) -> ChartRole {
            switch entry.programRole {
            case LiftRole.complementary.rawValue: return .complementary
            case LiftRole.main.rawValue: return .main
            case .some: return .extra          // accessory, and anything added later
            case nil:
                let programmed = session.programID != nil || session.programName != nil
                return programmed ? .extra : .main
            }
        }
    }

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        /// "R1 Volume" … "R4 Deload", or "Untracked" for sessions without a
        /// cycle phase — the rotation-split series key.
        let rotation: String
        let role: ChartRole
        /// The line this point belongs to: metric and role together, so the
        /// combined view can draw weight and e1RM without them joining up.
        let series: String
    }

    private struct RepRecord: Identifiable {
        let reps: Int
        let weightLb: Double
        var id: Int { reps }
    }

    private var showComplementary: Bool { intent == .compareRoles }
    private var splitByRotation: Bool { intent == .compareRotations }
    private var visibleRoles: [ChartRole] { showComplementary ? [.main, .complementary] : [.main] }

    /// Load points (working weight and/or est. 1RM) for the visible roles.
    /// Volume is deliberately NOT here — in the combined view it becomes
    /// background bars on its own scale rather than a third line competing
    /// with two metrics that genuinely share a unit.
    private var points: [Point] {
        let display = settingsList.first?.unitDisplay ?? .lbPrimary
        let shown = { (lb: Double) in display.primaryUnit == .kg ? Weight.kg(fromLb: lb) : lb }
        var result: [Point] = []
        for session in sessions {
            let matching = session.exercises.filter { $0.exercise?.name == selectedLift }
            guard !matching.isEmpty else { continue }
            for role in visibleRoles {
                let entries = matching.filter { ChartRole.of($0, in: session) == role }
                guard !entries.isEmpty else { continue }
                // The session's program tag is the fallback, so accessory
                // slots and pre-phase-capture entries chart under the rotation
                // they were actually performed in instead of "Untracked".
                let rotation = ChartRotation.label(
                    entryPhase: entries.compactMap(\.phase).first?.rawValue,
                    sessionRotation: session.programWeek
                )
                let suffix = showComplementary ? " (\(role == .main ? "main" : "comp."))" : ""
                if metric == .topSet || metric == .all, let top = entries.compactMap(\.topSet?.weightLb).max() {
                    result.append(Point(date: session.date, value: shown(top), rotation: rotation,
                                        role: role, series: "Working weight\(suffix)"))
                }
                if metric == .estimatedMax || metric == .all {
                    let samples = entries.flatMap(\.workingSets).map {
                        ProgramProgression.epleyE1RM(weightLb: $0.weightLb, reps: $0.reps)
                    }
                    if let estimate = samples.max(), estimate > 0 {
                        result.append(Point(date: session.date, value: shown(estimate), rotation: rotation,
                                            role: role, series: "Est. 1RM\(suffix)"))
                    }
                }
                // A lift whose load never changes progresses by reps, so the
                // best completed working set is its "top set".
                if metric == .reps,
                   let best = entries.flatMap(\.workingSets).map(\.reps).max(), best > 0 {
                    result.append(Point(date: session.date, value: Double(best), rotation: rotation,
                                        role: role, series: "Reps\(suffix)"))
                }
                if metric == .volume {
                    let volume = entries.reduce(0) { $0 + $1.workingVolumeLb }
                    if volume > 0 {
                        result.append(Point(date: session.date, value: shown(volume), rotation: rotation,
                                            role: role, series: "Volume\(suffix)"))
                    }
                }
            }
        }
        return result
    }

    /// Tonnage for the combined view. It keeps its own zero-based scale — a
    /// magnitude, not a load — so it can never stretch the weight axis.
    private var volumeBars: [Point] {
        let display = settingsList.first?.unitDisplay ?? .lbPrimary
        return sessions.compactMap { session -> Point? in
            let entries = session.exercises.filter {
                $0.exercise?.name == selectedLift && ChartRole.of($0, in: session) == .main
            }
            let volume = entries.reduce(0) { $0 + $1.workingVolumeLb }
            guard volume > 0 else { return nil }
            return Point(date: session.date,
                         value: display.primaryUnit == .kg ? Weight.kg(fromLb: volume) : volume,
                         rotation: "", role: .main, series: "Volume")
        }
    }
    /// An unloaded pull-up has no external resistance, so working weight,
    /// est. 1RM and tonnage can only ever draw a flat zero. Offering the load
    /// metrics anyway is how promoting pull-ups to Main turned a real
    /// progression into three straight lines at 0. Mirrors web `metricOptions`.
    private var selectedIsLoaded: Bool {
        guard let exercise = mainLifts.first(where: { $0.name == selectedLift }) else { return true }
        return exercise.loadBasis.supportsLoadPR
    }

    private var availableMetrics: [Metric] {
        selectedIsLoaded ? [.topSet, .estimatedMax, .all] : [.reps]
    }

    /// Reps are a count, not a load: they carry no weight unit and never convert.
    private var chartUnitLabel: String {
        metric == .reps ? "reps" : (settingsList.first?.unitDisplay ?? .lbPrimary).primaryUnit.rawValue
    }

    private var peakTarget: Double? {
        guard metric != .volume, metric != .reps,
              let lift = (programs.first(where: \.isActive) ?? programs.first)?.days
                .flatMap(\.lifts).first(where: { $0.exerciseName == selectedLift }),
              lift.peakSingleEnabled, lift.lastPeakSingleLb > 0 else { return nil }
        let targetLb = lift.lastPeakSingleLb + lift.peakSingleIncrementLb
        return (settingsList.first?.unitDisplay ?? .lbPrimary).primaryUnit == .kg
            ? Weight.kg(fromLb: targetLb) : targetLb
    }

    private var repRecords: [RepRecord] {
        var best: [Int: Double] = [:]
        for session in sessions {
            for entry in session.exercises where entry.exercise?.name == selectedLift {
                for set in entry.workingSets where (1...12).contains(set.reps) {
                    best[set.reps] = max(best[set.reps, default: 0], set.weightLb)
                }
            }
        }
        return best.keys.sorted().map { RepRecord(reps: $0, weightLb: best[$0, default: 0]) }
    }

    /// Rotation → line colour: escalating heat to Peak, muted Deload.
    /// Mirrors web `ROTATION_COLORS`.
    private static let rotationPalette: [Color] = [
        Color(hex: 0x5BA06A), Color(hex: 0xE8B008), Color(hex: 0xEF4444),
        Color(hex: 0x8B9196), Color(hex: 0x666B71),
    ]
    /// Metric → line colour when not split by rotation. Working weight takes
    /// the accent; est. 1RM the green it also carries on web.
    private static let seriesPalette: [Color] = [
        Theme.accent, Color(hex: 0x5BA06A), Theme.accent.opacity(0.75), Color(hex: 0x5BA06A).opacity(0.75),
    ]

    /// Distinct line identity. Rotation split still needs the role in the key
    /// or a main and a complementary point in the same rotation would join.
    private func seriesKey(_ point: Point) -> String {
        splitByRotation ? "\(point.rotation)|\(point.role.rawValue)" : point.series
    }

    // MARK: - Projected trend

    private static let secondsPerDay: TimeInterval = 86_400
    /// Near enough to the history to read as its continuation, distinct enough
    /// to never be mistaken for a session that happened.
    private static let projectionColor = Color(hex: 0x7AA7D9)

    private struct Projection {
        let result: TrendProjection.Result
        let points: [Point]
        let horizonDate: Date
    }

    /// The projection follows the LIFT, not a rotation: it is fitted from every
    /// main-role point of the shown metric, so splitting the history into four
    /// rotation lines does not fit four separate futures through a quarter of
    /// the evidence each.
    private var projectionSeriesPrefix: String {
        switch metric {
        case .estimatedMax: return "Est. 1RM"
        case .volume: return "Volume"
        case .reps: return "Reps"
        case .topSet, .all: return "Working weight"
        }
    }

    /// Main-role points, or whatever role the lift actually has. A lift that
    /// only ever occupies complementary slots would otherwise draw a full chart
    /// beside "0 of 4 sessions so far" — refusing on a role distinction the
    /// lifter never asked about. Web falls back the same way.
    private var projectionSamplePoints: [Point] {
        let ofMetric = points.filter { $0.series.hasPrefix(projectionSeriesPrefix) }
        let main = ofMetric.filter { $0.role == .main }
        return main.isEmpty ? ofMetric : main
    }

    private var projection: Projection? {
        guard horizon != .off else { return nil }
        let samples = projectionSamplePoints
        guard let origin = samples.map(\.date).min() else { return nil }
        let day = { (date: Date) in date.timeIntervalSince(origin) / Self.secondsPerDay }
        guard let result = TrendProjection.project(
            samples: samples.map { TrendProjection.Sample(day: day($0.date), value: $0.value) },
            horizonDays: horizon.days,
            asOfDay: day(Date.now)
        ) else { return nil }
        let date = { (offset: Double) in origin.addingTimeInterval(offset * Self.secondsPerDay) }
        return Projection(
            result: result,
            points: result.points.map {
                Point(date: date($0.day), value: $0.value, rotation: "", role: .main, series: "Projected")
            },
            horizonDate: date(result.horizonDay)
        )
    }

    /// Say what the projection is, or say why there isn't one. Asking for a
    /// forecast and getting an unchanged chart back reads as a broken control,
    /// and the reason is the useful part: the refusal names what the history is
    /// missing.
    private func projectionRefusal(given projection: Projection?) -> String? {
        guard horizon != .off, projection == nil else { return nil }
        let samples = projectionSamplePoints
        guard samples.count >= TrendProjection.minimumSamples else {
            return "Not enough history to project — \(samples.count) of \(TrendProjection.minimumSamples) sessions so far."
        }
        guard let first = samples.map(\.date).min(), let last = samples.map(\.date).max() else {
            return "Not enough history to project from yet."
        }
        // Compare RAW and truncate only for display. Rounding before the
        // comparison made the message disagree with the engine at the
        // boundary: a 20.6-day span refused, then explained itself as
        // "spans 21 days, and a trend needs 21".
        let span = last.timeIntervalSince(first) / Self.secondsPerDay
        guard span >= TrendProjection.minimumSpanDays else {
            return "Not enough time to project — this lift spans \(Int(span)) days, and a trend needs \(Int(TrendProjection.minimumSpanDays))."
        }
        let idle = Date.now.timeIntervalSince(last) / Self.secondsPerDay
        if idle > TrendProjection.stalenessLimitDays {
            return "Last trained \(Int(idle)) days ago — too long to extend a trend from. Log a session to project again."
        }
        return "Not enough history to project from yet."
    }

    /// The value range every load mark occupies, so the future shading spans
    /// the plot without depending on the chart's derived domain. Volume bars
    /// are excluded — they ride their own scale and would drag the band down
    /// past the load lines it is meant to sit behind.
    private func loadRange(including projection: Projection) -> (low: Double, high: Double)? {
        let values = points.map(\.value) + projection.points.map(\.value)
        guard let low = values.min(), let high = values.max(), high > low else { return nil }
        return (low, high)
    }

    /// Values are already in the display unit — the chart converts before it
    /// builds points, and a linear fit commutes with that scaling — so the
    /// headline needs the unit appended, not converted again.
    /// Reps are whole — a projected "12.4 reps" is precision the count does
    /// not have. Mirrors the web summary's rounding.
    private func chartValueLabel(_ value: Double) -> String {
        metric == .reps ? String(Int(value.rounded())) : Weight.trim(value)
    }

    private func projectionSummary(_ projection: Projection) -> String {
        TrendProjection.summary(
            perWeek: projection.result.perWeek,
            horizonLabel: horizon.label,
            horizonValue: "\(chartValueLabel(projection.result.horizonValue)) \(chartUnitLabel)",
            unit: chartUnitLabel
        )
    }

    /// A single series, drawn on its own, is the only case where an area fill
    /// is depth rather than clutter. Rotation split and the combined metric
    /// both put several lines on the plot, and translucent areas over each
    /// other read as regions that mean something.
    private var showsAreaFill: Bool {
        !splitByRotation && Set(points.map(\.series)).count == 1
    }

    private var chartCaption: String {
        let metricLabel: String
        switch metric {
        case .topSet: metricLabel = "Top working weight"
        case .estimatedMax: metricLabel = "Estimated 1RM"
        case .volume: metricLabel = "Working volume"
        case .all: metricLabel = "Working weight and est. 1RM"
        case .reps: metricLabel = "Best working set"
        }
        let role = showComplementary ? " · solid = main, dashed = complementary" : " · main slots only"
        return "\(metricLabel) per session (\(chartUnitLabel))\(role)"
    }

    var body: some View {
        // Bound ONCE per pass. `projection` re-runs the least-squares fit over
        // a freshly recomputed `points` on every read, and the body reads it
        // from five places.
        let trend = projection
        return VStack(spacing: 12) {
            Picker("Lift", selection: $selectedLift) {
                ForEach(mainLifts) { Text($0.name).tag($0.name) }
            }
            .onAppear { if selectedLift.isEmpty { selectedLift = defaultLiftName } }
            // Switching to a bodyweight lift while a load metric is selected
            // would otherwise strand the chart on a metric it can only draw
            // as zero. Mirrors the web picker's clamp.
            .onChange(of: selectedLift, initial: true) {
                if !availableMetrics.contains(metric) { metric = availableMetrics[0] }
            }
            Picker("Metric", selection: $metric) {
                ForEach(availableMetrics, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Picker("Chart intent", selection: $intent) {
                ForEach(ChartIntent.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            // How far past today to extend the fitted trend.
            Picker("Project forward", selection: $horizon) {
                ForEach(TrendProjection.Horizon.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Project forward")
            .accessibilityHint("Extends the trend fitted from performed sessions past today")

            if points.isEmpty {
                ContentUnavailableView(Copy.emptyHistory, systemImage: "chart.xyaxis.line")
            } else {
                Chart {
                    // The future, shaded behind everything: the region right of
                    // today is a different kind of space and should read that
                    // way before the eye reaches the dashes.
                    // The y bounds are spelled out rather than left to span the
                    // plot: RectangleMark's x-only initializer is ambiguous
                    // between two overloads, and the load range is exactly what
                    // the shading should cover anyway.
                    if let trend, let range = loadRange(including: trend) {
                        RectangleMark(
                            xStart: .value("Today", Date.now),
                            xEnd: .value("Horizon", trend.horizonDate),
                            yStart: .value(chartUnitLabel, range.low),
                            yEnd: .value(chartUnitLabel, range.high)
                        )
                        .foregroundStyle(Color.secondary.opacity(0.07))
                    }
                    // A wash under a lone line gives the plot depth without
                    // adding a second thing to read. Only when there IS one
                    // line — stacking translucent areas makes their overlaps
                    // look like data.
                    if showsAreaFill {
                        ForEach(points) { point in
                            AreaMark(x: .value("Date", point.date),
                                     y: .value(chartUnitLabel, point.value))
                                .foregroundStyle(LinearGradient(
                                    colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.01)],
                                    startPoint: .top, endPoint: .bottom
                                ))
                        }
                    }
                    ForEach(points) { point in
                        LineMark(x: .value("Date", point.date), y: .value(chartUnitLabel, point.value),
                                 series: .value("Series", seriesKey(point)))
                            .foregroundStyle(by: .value("Series", splitByRotation ? point.rotation : point.series))
                            .lineStyle(StrokeStyle(lineWidth: 2,
                                                   dash: point.role == .complementary ? [5, 4] : []))
                        PointMark(x: .value("Date", point.date), y: .value(chartUnitLabel, point.value))
                            .foregroundStyle(by: .value("Series", splitByRotation ? point.rotation : point.series))
                            .symbolSize(point.role == .complementary ? 28 : 44)
                    }
                    if let peakTarget {
                        RuleMark(y: .value("Peak target", peakTarget))
                            .foregroundStyle(Theme.accent.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .annotation(position: .top, alignment: .trailing) {
                                Text("Peak target \(Weight.trim(peakTarget))")
                                    .font(.caption2).foregroundStyle(Theme.accent)
                            }
                    }
                    // The projection last, so it reads as an overlay on the
                    // history rather than another member of it. Its colour is
                    // set outright rather than through the foreground-style
                    // scale: joining that scale's domain would renumber every
                    // performed series' colour the moment a horizon was picked.
                    // No point marks either — there is no session to mark.
                    if let trend {
                        ForEach(trend.points) { point in
                            LineMark(x: .value("Date", point.date),
                                     y: .value(chartUnitLabel, point.value),
                                     series: .value("Series", "Projected"))
                                .foregroundStyle(Self.projectionColor)
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [3, 5]))
                        }
                        PointMark(x: .value("Date", trend.horizonDate),
                                  y: .value(chartUnitLabel, trend.result.horizonValue))
                            .foregroundStyle(Self.projectionColor)
                            .symbolSize(36)
                            .annotation(position: .top, alignment: .trailing) {
                                Text(chartValueLabel(trend.result.horizonValue))
                                    .font(.caption2.bold().monospacedDigit())
                                    .foregroundStyle(Self.projectionColor)
                            }
                        RuleMark(x: .value("Today", Date.now))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("today")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .chartForegroundStyleScale(range: splitByRotation ? Self.rotationPalette : Self.seriesPalette)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartLegend(Set(points.map(\.series)).count > 1 ? .visible : .hidden)
                .chartXSelection(value: $selectedDate)
                .frame(maxHeight: 280)
                .padding(.horizontal)
                Text(chartCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let detail = selectedPointDetail {
                    Text(detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .accessibilityLabel(detail)
                }
                if selectedIsLoaded, !volumeBars.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Working volume").font(.caption.bold())
                        Chart(volumeBars) { bar in
                            BarMark(x: .value("Date", bar.date), y: .value("Volume", bar.value))
                                .foregroundStyle(Color(hex: 0x8B9196).opacity(0.55))
                        }
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(height: 105)
                    }
                    .padding(.horizontal)
                }
                if let trend {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(projectionSummary(trend))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Self.projectionColor)
                        Text("\(TrendProjection.fitDescription(trend.result.fitQuality)) · fitted from performed sessions — a continuation of the past, not a plan.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .accessibilityElement(children: .combine)
                } else if let refusal = projectionRefusal(given: trend) {
                    Text(refusal)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            if !repRecords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rep PRs").font(.headline)
                    Chart(repRecords) { record in
                        LineMark(x: .value("Reps", record.reps),
                                 y: .value("Weight", displayRepWeight(record.weightLb)))
                            .foregroundStyle(Theme.accent)
                        PointMark(x: .value("Reps", record.reps),
                                  y: .value("Weight", displayRepWeight(record.weightLb)))
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(height: 150)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(repRecords) { record in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(record.reps) rep\(record.reps == 1 ? "" : "s")")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text((settingsList.first?.unitDisplay ?? .lbPrimary).format(lb: record.weightLb))
                                        .font(.callout.bold().monospacedDigit())
                                }
                                .padding(10)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private var defaultLiftName: String {
        if let program = programs.first(where: \.isActive) ?? programs.first,
           let day = program.orderedDays.first(where: { $0.order == program.nextDayIndex }) ?? program.orderedDays.first,
           let lift = day.orderedLifts.first(where: { $0.role == .main }),
           mainLifts.contains(where: { $0.name == lift.exerciseName }) {
            return lift.exerciseName
        }
        for session in sessions.reversed() {
            if let name = session.orderedExercises.first(where: { $0.exercise?.category == .main })?.exercise?.name {
                return name
            }
        }
        return mainLifts.first?.name ?? ""
    }

    private func displayRepWeight(_ lb: Double) -> Double {
        (settingsList.first?.unitDisplay ?? .lbPrimary).primaryUnit == .kg ? Weight.kg(fromLb: lb) : lb
    }

    private var selectedPointDetail: String? {
        guard let selectedDate,
              let session = sessions.min(by: {
                  abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
              }) else { return nil }
        let matching = session.exercises.filter { $0.exercise?.name == selectedLift }
        let entries = matching.filter { visibleRoles.contains(ChartRole.of($0, in: session)) }
        guard let entry = entries.first,
              let top = entry.workingSets.max(by: { $0.weightLb < $1.weightLb }) else { return nil }
        let estimate = entry.workingSets.map {
            ProgramProgression.epleyE1RM(weightLb: $0.weightLb, reps: $0.reps)
        }.max() ?? 0
        let role = ChartRole.of(entry, in: session).rawValue
        let rotation = ChartRotation.label(entryPhase: entry.phase?.rawValue, sessionRotation: session.programWeek)
        let display = settingsList.first?.unitDisplay ?? .lbPrimary
        return "\(session.date.formatted(date: .abbreviated, time: .omitted)) · \(display.format(lb: top.weightLb)) × \(top.reps) · e1RM \(display.format(lb: estimate)) · \(role) · \(rotation)"
    }
}
