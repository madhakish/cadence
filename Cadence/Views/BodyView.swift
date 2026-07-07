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

    @State private var showWeightEntry = false
    @State private var customProteinText = ""

    private var settings: AppSettings? { settingsList.first }

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
                                    y: .value("lb", entry.weightLb)
                                )
                                .foregroundStyle(Theme.accent)
                                PointMark(
                                    x: .value("Date", entry.date),
                                    y: .value("lb", entry.weightLb)
                                )
                                .foregroundStyle(Theme.accent)
                                .annotation(position: .top) {
                                    if let label = entry.milestoneLabel {
                                        Text("\(label) \(Weight.trim(entry.weightLb))")
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
                            Text("\(Weight.trim(latest.weightLb)) lb")
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
                        Text("/ \(Int(settings?.proteinTargetGrams ?? 175)) g today")
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(1, todayProteinTotal / (settings?.proteinTargetGrams ?? 175)))
                        .tint(todayProteinTotal >= (settings?.proteinTargetGrams ?? 175) ? Theme.good : Theme.accent)

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
                            try? context.save()
                        }
                    }
                }
            }
            .navigationTitle("Body")
            .sheet(isPresented: $showWeightEntry) {
                BodyweightEntrySheet()
                    .presentationDetents([.medium])
            }
        }
    }

    private func logProtein(_ grams: Double, _ label: String) {
        context.insert(ProteinEntry(grams: grams, label: label))
        try? context.save()
        if settings?.healthKitEnabled == true { /* protein not mirrored; weights only */ }
    }
}

private struct BodyweightEntrySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    @State private var weightText = ""
    @State private var bodyFatText = ""
    @State private var milestoneLabel = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Weight (lb)", text: $weightText)
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
        guard let weight = Double(weightText) else { return }
        let entry = BodyweightEntry(
            weightLb: weight,
            bodyFatPercent: Double(bodyFatText),
            milestoneLabel: milestoneLabel.isEmpty ? nil : milestoneLabel
        )
        context.insert(entry)
        try? context.save()
        if settingsList.first?.healthKitEnabled == true {
            Task { await HealthKitService.shared.saveBodyweight(lb: weight, date: entry.date) }
        }
        dismiss()
    }
}
