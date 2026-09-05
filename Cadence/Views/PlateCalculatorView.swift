import SwiftUI
import SwiftData
import CadenceCore

/// The killer feature. Target → per-side loading in mixed units, or
/// reverse: what's on the bar → total. Big digits, zero ceremony.
struct PlateCalculatorView: View {
    @Query private var gyms: [Gym]
    @Query private var settingsList: [AppSettings]

    @State private var mode: Mode = .target
    @State private var targetText = ""
    @State private var targetUnit: WeightUnit = .lb
    @State private var bar: Bar = .bar45lb
    @State private var plateStyle: PlateVisualStyle = .steel
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
        return PlateMath.solve(targetLb: targetLb, bar: bar, plates: availablePlates,
                               collarLb: gym?.collarWeightLb ?? 0,
                               policy: gym?.loadingPolicy ?? .closest)
    }

    private var preferredUnit: WeightUnit {
        settingsList.first?.unitDisplay.primaryUnit ?? .lb
    }

    private var reversePerSide: [PlateCount] {
        availablePlates.compactMap { plate in
            let count = reverseCounts[plate.id] ?? 0
            return count > 0 ? PlateCount(plate: plate, count: count) : nil
        }
    }

    private var reverseCollarLb: Double { gym?.collarWeightLb ?? 0 }

    private var reverseTotalLb: Double {
        PlateMath.total(bar: bar, perSide: reversePerSide, collarLb: reverseCollarLb)
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
                Picker("Plate type", selection: $plateStyle) {
                    ForEach(PlateVisualStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if gyms.count > 1 {
                    Picker("Gym", selection: Binding(
                        get: { gym?.name ?? "" },
                        set: { name in
                            selectedGymName = name
                            if let selected = gyms.first(where: { $0.name == name }) {
                                bar = selected.defaultBar
                            }
                        }
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
        .onAppear {
            if targetText.isEmpty { targetUnit = preferredUnit }
            if selectedGymName == nil { bar = gym?.defaultBar ?? .bar45lb }
        }
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
            Section("Total on bar") {
                DualWeightReadout(lb: solution.loadout.totalLb)
                Text("Achieved on \(bar.label) · \((gym?.loadingPolicy ?? .closest).label.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !solution.satisfiesPolicy {
                    Label("No available stack satisfies this loading policy; showing the closest load.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.bold())
                        .foregroundStyle(Theme.warn)
                }
                if solution.isOffTarget {
                    let deviation = targetUnit == .kg
                        ? Weight.kg(fromLb: solution.deviationLb)
                        : solution.deviationLb
                    Label(
                        "\(Copy.offTarget) \(deviation > 0 ? "+" : "")\(Weight.trim(deviation)) \(targetUnit.rawValue) vs target.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout.bold())
                    .foregroundStyle(Theme.warn)
                }
            }

            // The answer, drawn: the loaded bar itself — the SAME solution as
            // the list below (which may pick the other unit system).
            Section {
                BarbellView(weightLb: solution.targetLb, unit: targetUnit, bar: bar, gym: gym,
                            loadout: solution.loadout, plateStyle: plateStyle, presentation: .fullBar)
                    .frame(minHeight: 102)
                Text("Same stack on both sides")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            Section("Per side") {
                if solution.loadout.perSide.isEmpty {
                    Text(solution.loadout.collarLb > 0 ? "Bar + collars" : "Bar only")
                        .font(.title2.bold())
                } else {
                    ForEach(solution.loadout.perSide) { pc in
                        HStack {
                            PlateFaceBadge(plate: pc.plate, style: plateStyle)
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
        }
    }

    // MARK: - Reverse mode

    @ViewBuilder
    private var reverseSections: some View {
        Section("Total on bar") {
            DualWeightReadout(lb: reverseTotalLb)
            Text("On \(bar.label)\(reverseCollarLb > 0 ? " + collars" : "")")
                .font(.caption)
                .foregroundStyle(.secondary)
            // Draw exactly what the user says is on the bar — never re-solve it.
            BarbellView(weightLb: reverseTotalLb, unit: .lb, bar: bar, gym: gym,
                        loadout: Loadout(bar: bar, perSide: reversePerSide, collarLb: reverseCollarLb),
                        plateStyle: plateStyle, presentation: .fullBar)
                .frame(minHeight: 102)
            Text("Counts are per side and mirrored")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }

        Section("Plates on one side") {
            ForEach(availablePlates.sorted(by: >).reversed(), id: \.id) { plate in
                Stepper(value: Binding(
                    get: { reverseCounts[plate.id] ?? 0 },
                    set: { reverseCounts[plate.id] = $0 }
                ), in: 0...12) {
                    HStack {
                        PlateFaceBadge(plate: plate, style: plateStyle)
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
    }
}

/// Both totals are always visible and always ordered lb → kg. The selectors
/// describe what the user typed and what equipment they grabbed; neither is a
/// reason to hide the other interpretation of the final mixed-unit bar.
private struct DualWeightReadout: View {
    let lb: Double

    var body: some View {
        HStack(spacing: 0) {
            metric(Weight.trim(lb), unit: "lb")
            Divider().frame(height: 48)
            metric(Weight.trim(Weight.kg(fromLb: lb)), unit: "kg")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Total \(Weight.both(lb: lb))")
    }

    private func metric(_ value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(unit)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
