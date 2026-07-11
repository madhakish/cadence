import SwiftUI
import SwiftData
import CadenceCore

/// The killer feature. Target → per-side loading in mixed units, or
/// reverse: what's on the bar → total. Big digits, zero ceremony.
struct PlateCalculatorView: View {
    @Query private var gyms: [Gym]

    @State private var mode: Mode = .target
    @State private var targetText = ""
    @State private var targetUnit: WeightUnit = .lb
    @State private var bar: Bar = .bar45lb
    @State private var selectedGymName: String?
    // Reverse mode: counts per plate denomination on ONE side.
    @State private var reverseCounts: [String: Int] = [:]

    enum Mode: String, CaseIterable {
        case target = "Target"
        case reverse = "On the bar"
    }

    private var gym: Gym? {
        gyms.first { $0.name == selectedGymName } ?? gyms.first { $0.isDefault } ?? gyms.first
    }

    private var availablePlates: [Plate] {
        gym?.availablePlates ?? Plate.allStandard
    }

    private var targetLb: Double? {
        guard let value = Double(targetText.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return Weight.toLb(value, from: targetUnit)
    }

    private var solution: PlateSolution? {
        guard let targetLb else { return nil }
        return PlateMath.solve(targetLb: targetLb, bar: bar, plates: availablePlates)
    }

    var body: some View {
        Form {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            Section {
                Picker("Bar", selection: $bar) {
                    ForEach(Bar.all) { Text($0.label).tag($0) }
                }
                if gyms.count > 1 {
                    Picker("Gym", selection: Binding(
                        get: { gym?.name ?? "" },
                        set: { selectedGymName = $0 }
                    )) {
                        ForEach(gyms) { Text($0.name).tag($0.name) }
                    }
                }
            }

            switch mode {
            case .target: targetSections
            case .reverse: reverseSections
            }
        }
        .navigationTitle("Plates")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Target mode

    @ViewBuilder
    private var targetSections: some View {
        Section("Target total") {
            HStack {
                TextField("0", text: $targetText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Picker("", selection: $targetUnit) {
                    Text("lb").tag(WeightUnit.lb)
                    Text("kg").tag(WeightUnit.kg)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
        }

        if let solution {
            // The answer, drawn: the loaded bar itself — the list below is
            // the detail, not the deliverable.
            Section {
                BarbellView(weightLb: solution.targetLb, unit: targetUnit, bar: bar, gym: gym)
                    .scaleEffect(1.6, anchor: .leading)
                    .frame(height: 52, alignment: .leading)
            }
            Section("Per side") {
                if solution.loadout.perSide.isEmpty {
                    Text("Bar only").font(.title2.bold())
                } else {
                    ForEach(solution.loadout.perSide) { pc in
                        HStack {
                            Text(pc.plate.label)
                                .font(.title3.bold())
                                .foregroundStyle(pc.plate.unit == .kg ? Theme.accent : .primary)
                            Spacer()
                            Text("× \(pc.count)")
                                .font(.title3.monospacedDigit())
                        }
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Weight.both(lb: solution.loadout.totalLb))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                    Text("achieved total on \(bar.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if solution.isOffTarget {
                        Label(
                            "\(Copy.offTarget) \(solution.deviationLb > 0 ? "+" : "")\(Weight.trim(solution.deviationLb)) lb vs target.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.callout.bold())
                        .foregroundStyle(Theme.warn)
                    }
                }
            }
        }
    }

    // MARK: - Reverse mode

    @ViewBuilder
    private var reverseSections: some View {
        Section("Plates on one side") {
            ForEach(availablePlates.sorted(by: >).reversed(), id: \.id) { plate in
                Stepper(value: Binding(
                    get: { reverseCounts[plate.id] ?? 0 },
                    set: { reverseCounts[plate.id] = $0 }
                ), in: 0...12) {
                    HStack {
                        Text(plate.label)
                            .foregroundStyle(plate.unit == .kg ? Theme.accent : .primary)
                        Spacer()
                        let count = reverseCounts[plate.id] ?? 0
                        if count > 0 {
                            Text("× \(count)").bold().monospacedDigit()
                        }
                    }
                }
            }
            Button("Clear", role: .destructive) { reverseCounts = [:] }
        }

        Section {
            let perSide = availablePlates.compactMap { plate -> PlateCount? in
                let count = reverseCounts[plate.id] ?? 0
                return count > 0 ? PlateCount(plate: plate, count: count) : nil
            }
            let total = PlateMath.total(bar: bar, perSide: perSide)
            VStack(alignment: .leading, spacing: 6) {
                BarbellView(weightLb: total, unit: .lb, bar: bar, gym: gym)
                    .scaleEffect(1.6, anchor: .leading)
                    .frame(height: 52, alignment: .leading)
                Text(Weight.both(lb: total))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                Text("total on \(bar.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
