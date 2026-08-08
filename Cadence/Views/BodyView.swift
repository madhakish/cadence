import SwiftUI
import SwiftData
import Charts
import CadenceCore

/// Bodyweight trend with milestone annotations, advisory protein guidance,
/// and what Apple Health has to say about either.
struct BodyView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyweightEntry.date) private var bodyweight: [BodyweightEntry]
    @Query private var settingsList: [AppSettings]
    @Query private var checkIns: [CheckIn]

    @AppStorage("healthReadEnabled") private var healthReadEnabled = false

    @State private var showWeightEntry = false
    @State private var healthWeighIn: HealthBodyweight?
    @State private var recovery = HealthKitService.RecoverySnapshot()

    typealias HealthBodyweight = (weightLb: Double, bodyFatPercent: Double?, date: Date)

    private var settings: AppSettings? { settingsList.first }
    private var unitDisplay: UnitDisplay { settings?.unitDisplay ?? .lbPrimary }
    private func displayWeight(_ lb: Double) -> Double {
        unitDisplay.primaryUnit == .kg ? Weight.kg(fromLb: lb) : lb
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        InjuryTimelineView()
                    } label: {
                        HStack {
                            Label("Signals", systemImage: "bolt.heart")
                            Spacer()
                            if hardStopCount > 0 {
                                Text("\(hardStopCount)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Theme.hardStop, in: Capsule())
                                    .accessibilityLabel("\(hardStopCount) active hard stops")
                            }
                        }
                    }
                } footer: {
                    Text("Body-site check-ins and set flags, including anything that should stop training.")
                }

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

                proteinSection

                healthSection
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

    // MARK: - Protein

    /// Advice, not a tracker.
    ///
    /// Logging individual servings was retired in schema V5: counting grams
    /// only works with a real meal-entry surface, and a half-measure the lifter
    /// abandons after a week is worse than an honest target. What is left is a
    /// figure to aim at, derived from bodyweight and — for the per-meal
    /// threshold, where age genuinely changes the answer — year of birth.
    @ViewBuilder
    private var proteinSection: some View {
        if let guidance = ProteinGuidance.summary(bodyweightLb: latestWeightLb, age: age) {
            Section {
                Text(guidance)
                if let rationale = ProteinGuidance.perMealRationale(age: age) {
                    Text(rationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // Naming the assumption rather than hiding it: the figure
                    // shown is the older-adult one until the lifter says
                    // otherwise, and they should know why it might drop.
                    Text("Add your year of birth in Settings for an age-adjusted per-meal figure.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Protein")
            } footer: {
                Text("Guidance only — Cadence does not track what you eat.")
            }
        }
    }

    private var latestWeightLb: Double? { bodyweight.last?.weightLb }

    private var hardStopCount: Int {
        Dictionary(grouping: checkIns.compactMap { checkIn in
            checkIn.site.map { ($0, checkIn) }
        }, by: { $0.0 })
        .values
        .compactMap { entries in entries.map { $0.1 }.max(by: { $0.date < $1.date }) }
        .filter(\.isHardStop)
        .count
    }

    private var age: Int? {
        guard let birthYear = settings?.birthYear else { return nil }
        return ProteinGuidance.age(
            birthYear: birthYear, inYear: Calendar.current.component(.year, from: .now)
        )
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
