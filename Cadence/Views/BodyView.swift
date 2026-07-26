import SwiftUI
import SwiftData
import Charts
import CadenceCore

/// Bodyweight trend with milestone annotations + daily protein running total.
struct BodyView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyweightEntry.date) private var bodyweight: [BodyweightEntry]
    @Query(sort: \ProteinEntry.date, order: .reverse) private var protein: [ProteinEntry]
    @Query private var settingsList: [AppSettings]

    @AppStorage("healthReadEnabled") private var healthReadEnabled = false

    @State private var showWeightEntry = false
    @State private var customProteinText = ""
    @State private var healthWeighIn: HealthBodyweight?
    @State private var recovery = HealthKitService.RecoverySnapshot()

    typealias HealthBodyweight = (weightLb: Double, bodyFatPercent: Double?, date: Date)

    private var settings: AppSettings? { settingsList.first }
    private var unitDisplay: UnitDisplay { settings?.unitDisplay ?? .lbPrimary }
    private func displayWeight(_ lb: Double) -> Double {
        unitDisplay.primaryUnit == .kg ? Weight.kg(fromLb: lb) : lb
    }

    private var todayProtein: [ProteinEntry] {
        protein.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var todayProteinTotal: Double {
        todayProtein.reduce(0) { $0 + $1.grams }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Bodyweight") {
                    if bodyweight.count > 1 {
                        Chart {
                            ForEach(bodyweight) { entry in
                                LineMark(
                                    x: .value("Date", entry.date),
                                    y: .value(unitDisplay.primaryUnit.rawValue, displayWeight(entry.weightLb))
                                )
                                .foregroundStyle(Theme.accent)
                                PointMark(
                                    x: .value("Date", entry.date),
                                    y: .value(unitDisplay.primaryUnit.rawValue, displayWeight(entry.weightLb))
                                )
                                .foregroundStyle(Theme.accent)
                                .annotation(position: .top) {
                                    if let label = entry.milestoneLabel {
                                        Text("\(label) \(unitDisplay.format(lb: entry.weightLb))")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 200)
                    }
                    if let latest = bodyweight.last {
                        HStack {
                            Text(unitDisplay.format(lb: latest.weightLb))
                                .font(.title2.bold())
                            if let bf = latest.bodyFatPercent {
                                Text("\(Weight.trim(bf))% bf").foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(latest.date.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        showWeightEntry = true
                    } label: {
                        Label("Log weight", systemImage: "plus")
                    }
                }

                Section {
                    HStack {
                        Text("\(Int(todayProteinTotal)) g")
                            .font(.title.bold().monospacedDigit())
                        Text("/ \(Int(settings?.proteinTargetGrams ?? 100)) g today")
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(1, todayProteinTotal / (settings?.proteinTargetGrams ?? 100)))
                        .tint(todayProteinTotal >= (settings?.proteinTargetGrams ?? 100) ? Theme.good : Theme.accent)

                    // Guidance, not enforcement: the stored target stays
                    // whatever the lifter set. Offered only when there is a
                    // real bodyweight to derive it from — the app never invents
                    // one — and only when it differs from what's set.
                    if let guidance = ProteinGuidance.summary(bodyweightLb: bodyweight.last?.weightLb) {
                        Text(guidance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let suggested = ProteinGuidance.dailyTargetGrams(bodyweightLb: bodyweight.last?.weightLb),
                           let settings, Int(suggested) != Int(settings.proteinTargetGrams) {
                            Button("Use \(Int(suggested)) g as my daily target") {
                                settings.proteinTargetGrams = suggested
                                PersistenceErrorCenter.shared.save(context, operation: "Updating the protein target")
                            }
                            .font(.caption)
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Shake ~45g") { logProtein(45, "Shake ~45g") }
                            .buttonStyle(.bordered)
                        Button("Meat ~50g") { logProtein(50, "Meat meal ~50g") }
                            .buttonStyle(.bordered)
                    }
                    HStack {
                        TextField("Custom g", text: $customProteinText)
                            .keyboardType(.numberPad)
                        Button("Add") {
                            if let grams = Double(customProteinText), grams > 0 {
                                logProtein(grams, "Custom")
                                customProteinText = ""
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                } header: {
                    Text("Protein")
                }

                healthSection

                if !todayProtein.isEmpty {
                    Section("Today's entries") {
                        ForEach(todayProtein) { entry in
                            HStack {
                                Text(entry.label)
                                Spacer()
                                Text("\(Int(entry.grams)) g").monospacedDigit()
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(todayProtein[index]) }
                            PersistenceErrorCenter.shared.save(context, operation: "Deleting the protein entry")
                        }
                    }
                }
            }
            .navigationTitle("Body")
            .sheet(isPresented: $showWeightEntry) {
                BodyweightEntrySheet()
                    .presentationDetents([.medium])
            }
            .task(id: healthReadEnabled) { await refreshHealth() }
        }
    }

    /// Sleep reads as hours and minutes. `CardioFormat.durationLabel` would
    /// render seven hours as "7:24:00", which is a stopwatch, not a night.
    private static func sleepLabel(_ seconds: Int) -> String {
        let minutes = seconds / 60
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private func logProtein(_ grams: Double, _ label: String) {
        context.insert(ProteinEntry(grams: grams, label: label))
        PersistenceErrorCenter.shared.save(context, operation: "Logging protein")
    }

    // MARK: - Health

    /// [INV-HEALTH-IS-A-SECOND-OPINION] Health suggests; the lifter decides.
    /// Nothing here writes on its own, and Cadence's own mirrored samples are
    /// already excluded by the service, so a suggestion is always something the
    /// log genuinely does not have.
    @ViewBuilder
    private var healthSection: some View {
        if healthReadEnabled, healthWeighIn != nil || !recovery.isEmpty {
            Section {
                if let found = healthWeighIn {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Health has \(unitDisplay.format(lb: found.weightLb)) from \(found.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.callout)
                        Button("Log it") { adoptWeighIn(found) }
                            .font(.callout)
                    }
                }
                if let hrv = recovery.hrvMilliseconds {
                    LabeledContent("Heart rate variability", value: "\(Int(hrv.rounded())) ms")
                }
                if let rhr = recovery.restingHeartRate {
                    LabeledContent("Resting heart rate", value: "\(Int(rhr.rounded())) bpm")
                }
                if let seconds = recovery.asleepSeconds {
                    LabeledContent("Slept", value: Self.sleepLabel(seconds))
                }
            } header: {
                Text("Health")
            } footer: {
                // Said plainly because it is the whole design: these numbers
                // are shown, not applied. Training decisions come from the work
                // logged, not from an overnight reading.
                Text("Your log stays the record. Recovery figures are shown for context and never change your program.")
            }
        }
    }

    private func refreshHealth() async {
        guard healthReadEnabled else { return }
        let service = HealthKitService.shared
        // A weigh-in older than a fortnight is history, not a prompt.
        let since = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        async let weighIn = service.latestBodyweight(since: since)
        async let snapshot = service.recovery()

        let found = await weighIn
        healthWeighIn = found.flatMap { candidate in
            // Already logged is not a suggestion. Compared against every
            // recent entry rather than only the newest, because a weigh-in
            // entered out of order would otherwise be offered straight back.
            let alreadyLogged = bodyweight.contains {
                HealthComparison.isSameWeighIn(
                    loggedLb: $0.weightLb, loggedDate: $0.date,
                    healthLb: candidate.weightLb, healthDate: candidate.date
                )
            }
            return alreadyLogged ? nil : candidate
        }
        recovery = await snapshot
    }

    private func adoptWeighIn(_ found: HealthBodyweight) {
        let entry = BodyweightEntry(
            date: found.date, weightLb: found.weightLb, bodyFatPercent: found.bodyFatPercent
        )
        context.insert(entry)
        guard PersistenceErrorCenter.shared.save(context, operation: "Logging bodyweight from Health")
        else { return }
        // Not mirrored back out: it came from Health, and writing it again
        // would leave two records of one weigh-in.
        healthWeighIn = nil
    }
}

private struct BodyweightEntrySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    @State private var weightText = ""
    @State private var bodyFatText = ""
    @State private var milestoneLabel = ""
    private var entryUnit: WeightUnit { settingsList.first?.unitDisplay.primaryUnit ?? .lb }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Weight (\(entryUnit.rawValue))", text: $weightText)
                    .keyboardType(.decimalPad)
                    .font(.title2.bold())
                TextField("Body fat % (optional)", text: $bodyFatText)
                    .keyboardType(.decimalPad)
                TextField("Milestone label (optional)", text: $milestoneLabel)
            }
            .navigationTitle("Bodyweight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(Double(weightText) == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard let enteredWeight = Double(weightText) else { return }
        let weight = Weight.toLb(enteredWeight, from: entryUnit)
        let bodyFat = Double(bodyFatText)
        let entry = BodyweightEntry(
            weightLb: weight,
            bodyFatPercent: bodyFat,
            milestoneLabel: milestoneLabel.isEmpty ? nil : milestoneLabel
        )
        context.insert(entry)
        guard PersistenceErrorCenter.shared.save(context, operation: "Logging bodyweight") else { return }
        if settingsList.first?.healthKitEnabled == true {
            Task {
                await HealthKitService.shared.saveBodyweight(
                    lb: weight, bodyFatPercent: bodyFat, date: entry.date
                )
            }
        }
        dismiss()
    }
}
