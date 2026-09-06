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
    @State private var referenceUnit: WeightUnit = .lb
    @State private var selectedGymName: String?
    @State private var showExpandedBar = false
    @FocusState private var targetFieldFocused: Bool
    // Reverse mode: counts per plate denomination on ONE side.
    @State private var reverseCounts: [String: Int] = [:]
    @State private var reverseOrder: [String] = []

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
        let plateByID = Dictionary(uniqueKeysWithValues: availablePlates.map { ($0.id, $0) })
        return reverseOrder.compactMap { id in
            guard let plate = plateByID[id] else { return nil }
            let count = reverseCounts[plate.id] ?? 0
            return count > 0 ? PlateCount(plate: plate, count: count) : nil
        }
    }

    private var reverseCollarLb: Double { gym?.collarWeightLb ?? 0 }

    private var reverseLoadout: Loadout {
        Loadout(
            bar: bar,
            perSide: reversePerSide,
            collarLb: reverseCollarLb,
            preservesOrder: true
        )
    }

    private var reverseSolution: PlateSolution {
        PlateSolution(loadout: reverseLoadout, targetLb: reverseLoadout.totalLb)
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
            referenceSection
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
        .accessibilityIdentifier("plate-calculator-screen")
        .navigationTitle("Plates")
        .navigationBarTitleDisplayMode(.inline)
        .listSectionSpacing(.compact)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { targetFieldFocused = false }
                    .accessibilityIdentifier("plate-target-done")
            }
        }
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
                    .focused($targetFieldFocused)
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
                BarbellStageView(
                    solution: solution,
                    unit: targetUnit,
                    plateStyle: plateStyle,
                    onExpand: { showExpandedBar = true }
                )
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
            BarbellStageView(
                solution: reverseSolution,
                unit: .lb,
                plateStyle: plateStyle,
                onExpand: { showExpandedBar = true }
            )
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
                    set: { setReverseCount($0, for: plate) }
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
            Button("Clear", role: .destructive) {
                reverseCounts = [:]
                reverseOrder = []
            }
                .frame(minHeight: 44)
        }

        if !reversePerSide.isEmpty {
            Section("Sleeve order · inside to outside") {
                ForEach(Array(reversePerSide.enumerated()), id: \.element.id) { index, plateCount in
                    HStack {
                        Text(plateCount.label)
                            .font(.callout.bold().monospacedDigit())
                        Spacer()
                        Button("Move inward", systemImage: "arrow.up") {
                            moveReversePlate(id: plateCount.id, by: -1)
                        }
                        .labelStyle(.iconOnly)
                        .disabled(index == 0)
                        .frame(minWidth: 44, minHeight: 44)
                        Button("Move outward", systemImage: "arrow.down") {
                            moveReversePlate(id: plateCount.id, by: 1)
                        }
                        .labelStyle(.iconOnly)
                        .disabled(index == reversePerSide.count - 1)
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
    }

    /// Reference-only plate families — colour, denomination, other-unit
    /// conversion — for recognising what's on the rack. Not inventory: nothing
    /// here reaches the solver; the 55 lb disc is listed for recognition only.
    /// Web twin: `.plate-reference` in views/plates.js.
    private static let referenceKg: [Plate] = [25, 20, 15, 10, 5, 2.5, 1.25].map { Plate(value: $0, unit: .kg) }
    private static let referenceLb: [Plate] = [55, 45, 35, 25, 10, 5, 2.5].map { Plate(value: $0, unit: .lb) }

    private static func otherUnitLabel(_ plate: Plate) -> String {
        plate.unit == .kg
            ? "\(Weight.trim(Weight.lb(fromKg: plate.value), decimals: 2)) lb"
            : "\(Weight.trim(Weight.kg(fromLb: plate.value), decimals: 2)) kg"
    }

    private var referenceSection: some View {
        Section {
            DisclosureGroup("Plate reference") {
                Picker("Reference unit", selection: $referenceUnit) {
                    Text("Kilograms").tag(WeightUnit.kg)
                    Text("Pounds").tag(WeightUnit.lb)
                }
                .pickerStyle(.segmented)
                Text(referenceUnit == .kg ? "KG · IWF / IPF COLOUR CODE" : "LB · MANUFACTURER CONVENTION")
                    .font(.caption.bold())
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                ForEach(referenceUnit == .kg ? Self.referenceKg : Self.referenceLb) { plate in
                    HStack(spacing: 12) {
                        PlateFaceBadge(plate: plate, style: .bumper)
                            .scaleEffect(0.6)
                            .frame(width: 32, height: 32)
                        Text(plate.colorToken(for: .bumper).capitalized)
                            .frame(width: 64, alignment: .leading)
                        Text(plate.label)
                            .monospacedDigit()
                        Spacer()
                        Text(Self.otherUnitLabel(plate))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Kilogram colours follow the IWF and IPF code; pound bumpers follow the common manufacturer code, and 5 lb and under are black iron. Colours never change with the theme. This guide is reference only: the 55 lb disc is listed for recognition and is never added to a gym's inventory or offered to the solver.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

    private func setReverseCount(_ count: Int, for plate: Plate) {
        let previous = reverseCounts[plate.id] ?? 0
        reverseCounts[plate.id] = count
        if previous == 0, count > 0, !reverseOrder.contains(plate.id) {
            reverseOrder.append(plate.id)
        } else if count == 0 {
            reverseOrder.removeAll { $0 == plate.id }
        }
    }

    private func moveReversePlate(id: String, by offset: Int) {
        reverseOrder = PlateMath.movedVisiblePlateIDs(
            id: id,
            by: offset,
            storedOrder: reverseOrder,
            visibleOrder: reversePerSide.map(\.id)
        )
    }

    private var expandedBarView: some View {
        let displayedSolution = mode == .target ? solution : reverseSolution
        let requested = mode == .target ? targetLb : nil
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let displayedSolution {
                        ScrollView(.horizontal, showsIndicators: true) {
                            BarbellView(
                                solution: displayedSolution,
                                plateStyle: plateStyle,
                                presentation: .fullBar
                            )
                            .frame(
                                width: max(
                                    360,
                                    BarbellView.minimumLegibleWidth(
                                        for: displayedSolution.loadout,
                                        style: plateStyle
                                    )
                                ),
                                height: 180
                            )
                            .padding(.horizontal)
                        }
                        .accessibilityLabel("Expanded loaded bar diagram")
                        LoadoutSummaryView(requestedLb: requested, loadout: displayedSolution.loadout)
                            .padding(.horizontal)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Plates per side")
                                .font(.headline)
                            if displayedSolution.loadout.perSide.isEmpty {
                                Text(displayedSolution.loadout.collarLb > 0 ? "Bar + collars" : "Bar only")
                            } else {
                                ForEach(displayedSolution.loadout.perSide) { plateCount in
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
