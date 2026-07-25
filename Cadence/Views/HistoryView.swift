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
                ForEach(Array(report.rotations.reversed()), id: \.key) { rotation in
                    Section("Cycle \(rotation.key.cycleNumber) · R\(rotation.key.rotation)") {
                        HStack {
                            Label(rotation.readiness.name, systemImage: readinessIcon(rotation.readiness))
                                .foregroundStyle(readinessColor(rotation.readiness))
                            Spacer()
                            Text("\(rotation.completedWorkingSets)/\(rotation.plannedWorkingSets) sets")
                                .font(.callout.monospacedDigit())
                        }
                        ForEach(rotation.patternSets.keys.sorted { $0.name < $1.name }, id: \.self) { pattern in
                            if !pattern.isConditioning {
                                LabeledContent(pattern.name, value: "\(rotation.patternSets[pattern, default: 0])")
                            }
                        }
                        LabeledContent("Conditioning", value: "\(Int(rotation.conditioningMinutes.rounded())) min")
                        if let reason = rotation.reasons.first {
                            Text(reason).font(.caption).foregroundStyle(.secondary)
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
    @State private var didCheckHealth = false

    /// Everything this session logged as conditioning distance.
    private var loggedMiles: Double? {
        let total = session.orderedExercises
            .filter { $0.exercise?.type == .conditioning }
            .flatMap(\.orderedSets)
            .compactMap(\.distanceMiles)
            .reduce(0, +)
        return total > 0 ? total : nil
    }

    private var healthVerdict: HealthComparison.Verdict {
        HealthComparison.compare(loggedMiles: loggedMiles, healthMiles: healthMiles)
    }

    /// Only completed sessions have both ends of a window to look up.
    private var healthWindow: (start: Date, end: Date)? {
        guard let end = session.completedAt, end > session.date else { return nil }
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
                        if let phase = entry.phase {
                            Text(phase.label).foregroundStyle(Theme.accent)
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
            healthMiles = await HealthKitService.shared
                .conditioningDistanceMiles(start: window.start, end: window.end)
        }
    }

    /// [INV-HEALTH-IS-A-SECOND-OPINION] Both numbers, side by side, and an
    /// explicit tap to take Health's. Nothing here writes on its own, and a
    /// session with nothing in Health is silent rather than alarming.
    @ViewBuilder
    private var healthSection: some View {
        if healthReadEnabled, healthWindow != nil, showsHealthRow {
            Section {
                Text(HealthComparison.label(healthVerdict))
                    .font(.callout)
                    .foregroundStyle(healthVerdict.isDiscrepancy ? Theme.warn : .secondary)
                if let miles = healthVerdict.adoptableMiles {
                    Button("Use Health's \(Weight.trim(miles, decimals: 2)) mi") {
                        adoptHealthDistance(miles)
                    }
                    .font(.callout)
                }
            } header: {
                Text("Health")
            } footer: {
                Text("Your log stays the record. Adopting rewrites only this session's conditioning distance.")
            }
        }
    }

    /// Nothing to say, and an unworn watch, are both silence rather than a
    /// finding worth its own row.
    private var showsHealthRow: Bool {
        switch healthVerdict {
        case .neither, .onlyLogged: return false
        case .agree, .healthHigher, .loggedHigher, .onlyHealth: return true
        }
    }

    /// Write Health's number onto the single conditioning set, or spread it
    /// across several in proportion to what they already hold, so a two-leg
    /// walk keeps its shape instead of collapsing into the first set.
    private func adoptHealthDistance(_ miles: Double) {
        let sets = session.orderedExercises
            .filter { $0.exercise?.type == .conditioning }
            .flatMap(\.orderedSets)
        guard !sets.isEmpty else { return }
        let existing = sets.compactMap(\.distanceMiles).reduce(0, +)
        if existing > 0 {
            for set in sets {
                guard let current = set.distanceMiles, current > 0 else { continue }
                set.distanceMiles = ((miles * (current / existing)) * 100).rounded() / 100
            }
        } else {
            sets.first?.distanceMiles = miles
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
                                         loadLb: set.weightLb)
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
    @State private var splitByRotation = false
    /// Main only by default — that alone removes the main/complementary
    /// sawtooth that made a main lift's progression unreadable.
    @State private var showComplementary = false

    enum Metric: String, CaseIterable {
        case topSet = "Working weight"
        case estimatedMax = "Est. 1RM"
        case volume = "Volume"
        case all = "All three"
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
                let phase = entries.compactMap(\.phase).first
                let rotation = phase.map { "R\($0.rawValue) \($0.name)" } ?? "Untracked"
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
        guard metric == .all else { return [] }
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
    private var chartUnitLabel: String { (settingsList.first?.unitDisplay ?? .lbPrimary).primaryUnit.rawValue }

    private var peakTarget: Double? {
        guard metric != .volume,
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

    /// Map tonnage onto the load axis so the bars fill the plot without
    /// touching the y-domain the load lines define.
    private func scaledVolume(_ value: Double) -> Double {
        let loads = points.map(\.value)
        guard let ceiling = loads.max(), let floor = loads.min(),
              let maxVolume = volumeBars.map(\.value).max(), maxVolume > 0 else { return 0 }
        let headroom = ceiling - min(floor, ceiling)
        let base = max(0, floor - headroom * 0.35)
        return base + (ceiling - base) * 0.82 * (value / maxVolume)
    }

    private var chartCaption: String {
        let metricLabel: String
        switch metric {
        case .topSet: metricLabel = "Top working weight"
        case .estimatedMax: metricLabel = "Estimated 1RM"
        case .volume: metricLabel = "Working volume"
        case .all: metricLabel = "Working weight, est. 1RM, and volume"
        }
        let role = showComplementary ? " · solid = main, dashed = complementary" : " · main slots only"
        return "\(metricLabel) per session (\(chartUnitLabel))\(role)"
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Lift", selection: $selectedLift) {
                ForEach(mainLifts) { Text($0.name).tag($0.name) }
            }
            .onAppear { if selectedLift.isEmpty { selectedLift = mainLifts.first?.name ?? "" } }
            Picker("Metric", selection: $metric) {
                ForEach(Metric.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            // One line per rotation: compare this cycle's R1 against last
            // cycle's R1 instead of reading a sawtooth.
            Toggle("Show complementary", isOn: $showComplementary)
                .font(.callout)
            Toggle("Split by rotation", isOn: $splitByRotation)
                .font(.callout)

            if points.isEmpty {
                ContentUnavailableView(Copy.emptyHistory, systemImage: "chart.xyaxis.line")
            } else {
                Chart {
                    // Tonnage recedes to bars scaled against their own maximum,
                    // so the two same-unit load lines keep the weight axis to
                    // themselves and stay comparable.
                    ForEach(volumeBars) { bar in
                        BarMark(x: .value("Date", bar.date),
                                y: .value(chartUnitLabel, scaledVolume(bar.value)))
                            .foregroundStyle(Color(hex: 0x8B9196).opacity(0.28))
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
                }
                .chartForegroundStyleScale(range: splitByRotation ? Self.rotationPalette : Self.seriesPalette)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartLegend(Set(points.map(\.series)).count > 1 ? .visible : .hidden)
                .frame(maxHeight: 280)
                .padding(.horizontal)
                Text(chartCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if !repRecords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rep PRs").font(.headline)
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
}
