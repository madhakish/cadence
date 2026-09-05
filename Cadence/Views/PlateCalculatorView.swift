import SwiftUI
import SwiftData
import CadenceCore

/// The killer feature. Target → per-side loading in mixed units, or
/// reverse: what's on the bar → total. Big digits, zero ceremony.
struct PlateCalculatorView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var gyms: [Gym]
    @Query private var settingsList: [AppSettings]

    @State private var mode: Mode = .target
#if DEBUG
    @State private var targetText = ProcessInfo.processInfo.arguments.contains("--visual-proof") ? "139" : ""
#else
    @State private var targetText = ""
#endif
    @State private var targetUnit: WeightUnit = .lb
    @State private var bar: Bar = .bar45lb
    @State private var plateStyle: PlateVisualStyle = .steel
    @State private var selectedGymName: String?
    @State private var showExpandedBar = false
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

    private var reverseLoadout: Loadout {
        Loadout(bar: bar, perSide: reversePerSide, collarLb: reverseCollarLb)
    }

    var body: some View {
        Form {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            switch mode {
            case .target: targetSections
            case .reverse: reverseSections
            }

            equipmentSection
        }
        .listStyle(.plain)
        .accessibilityIdentifier("plate-calculator-screen")
        .navigationTitle("Plates")
        .navigationBarTitleDisplayMode(.inline)
        .listSectionSpacing(.compact)
        .onAppear {
            if targetText.isEmpty { targetUnit = preferredUnit }
            if selectedGymName == nil { bar = gym?.defaultBar ?? .bar45lb }
        }
        .sheet(isPresented: $showExpandedBar) {
            expandedBarView
        }
    }

    // MARK: - Target mode

    @ViewBuilder
    private var targetSections: some View {
        Section("Requested target") {
            HStack {
                TextField("0", text: $targetText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .accessibilityIdentifier("plate-target")
                Picker("", selection: $targetUnit) {
                    Text("lb").tag(WeightUnit.lb)
                    Text("kg").tag(WeightUnit.kg)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
        }

        if let solution {
            Section {
                ScrollView(.horizontal, showsIndicators: true) {
                    BarbellView(weightLb: solution.targetLb, unit: targetUnit, bar: bar, gym: gym,
                                loadout: solution.loadout, plateStyle: plateStyle, presentation: .fullBar)
                        .frame(width: 420, height: 132)
                        .id(solution.loadout)
                        .animation(reduceMotion ? nil : .easeOut(duration: Theme.shortMotion),
                                   value: solution.loadout)
                }
                .accessibilityLabel("Loaded bar diagram; scroll horizontally if needed")
                HStack {
                    Text("Mirrored stack · counts are per side")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Expand", systemImage: "arrow.up.left.and.arrow.down.right") {
                        showExpandedBar = true
                    }
                    .font(.caption.bold())
                    .labelStyle(.titleAndIcon)
                }
                .frame(minHeight: 44)
            } header: {
                Text("Load on the bar")
            }

            Section {
                LoadoutSummaryView(requestedLb: targetLb, loadout: solution.loadout)
                if let mixed = mixedUnitExplanation(solution.loadout) {
                    Label(mixed, systemImage: "scalemass")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
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
            } header: {
                Text("Load summary")
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
        Section {
            // Draw exactly what the user says is on the bar — never re-solve it.
            ScrollView(.horizontal, showsIndicators: true) {
                BarbellView(weightLb: reverseTotalLb, unit: .lb, bar: bar, gym: gym,
                            loadout: reverseLoadout,
                            plateStyle: plateStyle, presentation: .fullBar)
                    .frame(width: 420, height: 132)
                    .id(reverseLoadout)
                    .animation(reduceMotion ? nil : .easeOut(duration: Theme.shortMotion), value: reverseLoadout)
            }
            .accessibilityLabel("Loaded bar diagram; scroll horizontally if needed")
            HStack {
                Text("Mirrored stack · counts are per side")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Expand", systemImage: "arrow.up.left.and.arrow.down.right") {
                    showExpandedBar = true
                }
                .font(.caption.bold())
            }
            .frame(minHeight: 44)
        } header: {
            Text("On the bar")
        }

        Section {
            LoadoutSummaryView(requestedLb: nil, loadout: reverseLoadout)
            if let mixed = mixedUnitExplanation(reverseLoadout) {
                Label(mixed, systemImage: "scalemass")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Load summary")
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
                .frame(minHeight: 44)
        }
    }

    private var equipmentSection: some View {
        Section {
            DisclosureGroup("Equipment & loading") {
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
                Text("Bar units and plate denominations stay independent. Mixed racks are converted only in the total; the pictured stack always uses the plates actually selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func mixedUnitExplanation(_ loadout: Loadout) -> String? {
        let plateUnits = Set(loadout.perSide.map { $0.plate.unit })
        guard plateUnits.count > 1 || plateUnits.contains(where: { $0 != loadout.bar.unit }) else { return nil }
        return "Mixed equipment: \(loadout.bar.label) with \(loadout.perSideLabel) per side. The achieved total above already includes every conversion."
    }

    private var expandedBarView: some View {
        let loadout = mode == .target ? solution?.loadout : reverseLoadout
        let requested = mode == .target ? targetLb : nil
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let loadout {
                        BarbellView(
                            weightLb: loadout.totalLb,
                            unit: mode == .target ? targetUnit : .lb,
                            bar: bar,
                            gym: gym,
                            loadout: loadout,
                            plateStyle: plateStyle,
                            presentation: .fullBar
                        )
                        .frame(maxWidth: 620)
                        .frame(height: 180)
                        .padding(.horizontal)
                        LoadoutSummaryView(requestedLb: requested, loadout: loadout)
                            .padding(.horizontal)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Plates per side")
                                .font(.headline)
                            if loadout.perSide.isEmpty {
                                Text(loadout.collarLb > 0 ? "Bar + collars" : "Bar only")
                            } else {
                                ForEach(loadout.perSide) { plateCount in
                                    HStack {
                                        PlateFaceBadge(plate: plateCount.plate, style: plateStyle)
                                        Text(plateCount.plate.label).font(.title3.bold())
                                        Spacer()
                                        Text("× \(plateCount.count)").font(.title3.bold().monospacedDigit())
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Loaded bar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showExpandedBar = false }
                }
            }
        }
    }
}
