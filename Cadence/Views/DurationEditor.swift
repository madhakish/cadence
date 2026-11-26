import SwiftUI
import CadenceCore

/// A compact row opens a staged duration editor. Cancel never writes a default.
struct DurationEditorButton: View {
    let title: String
    @Binding var seconds: Int
    var zeroLabel = "Off"
    @State private var showingEditor = false

    var body: some View {
        Button { showingEditor = true } label: {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(title).foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    value
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).foregroundStyle(.primary)
                    value
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(seconds == 0 ? zeroLabel : DurationEditor.spoken(seconds))
        .accessibilityHint("Opens presets, fine adjustment, and exact duration entry")
        .sheet(isPresented: $showingEditor) {
            DurationEditor(title: title, seconds: seconds, zeroLabel: zeroLabel) { seconds = $0 }
        }
    }

    private var value: some View {
        HStack(spacing: 6) {
            Text(seconds == 0 ? zeroLabel : mmss(seconds))
                .font(.body.weight(.heavy).width(.condensed))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

/// Presets and ±15 s handle common rests; exact entry keeps every second
/// editable. The caller's zero state (Off, End rest, Use default) has its
/// own button. Nothing is written until Save.
struct DurationEditor: View {
    private enum Component: String, Hashable { case hours = "Hours", minutes = "Minutes", seconds = "Seconds" }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var figureSize: CGFloat = 104
    let title: String
    let zeroLabel: String
    let onSave: (Int) -> Void
    @State private var hours: String
    @State private var minutes: String
    @State private var seconds: String
    @FocusState private var focusedComponent: Component?

    init(title: String, seconds: Int, zeroLabel: String, onSave: @escaping (Int) -> Void) {
        self.title = title
        self.zeroLabel = zeroLabel
        self.onSave = onSave
        _hours = State(initialValue: String(seconds / 3600))
        _minutes = State(initialValue: String(seconds / 60 % 60))
        _seconds = State(initialValue: String(seconds % 60))
    }

    /// The same staged fields feed both controls and Save. Invalid typed
    /// input must never fall back to a previously valid duration.
    private var draft: Int? { RestDuration.parse(hours: hours, minutes: minutes, seconds: seconds) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    readout
                    steppers
                    presets
                    choice(zeroLabel, selected: draft == 0, font: .headline) { set(0) }
                        .accessibilityIdentifier("duration-zero")
                    exactEntry
                    if draft == nil {
                        Text("Enter whole numbers totaling no more than 60:00.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.hardStop)
                            .accessibilityIdentifier("duration-entry-error")
                    }
                    Text("Up to 60:00. Nothing changes until you tap Save.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let draft else { return }
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedComponent = nil }
                        .accessibilityIdentifier("duration-keyboard-done")
                }
            }
        }
    }

    // The number is the screen. Condensed heavy so 60:00 still fits a
    // phone at accessibility sizes before the scale factor has to step in.
    private var readout: some View {
        VStack(spacing: 2) {
            Text(draft.map { mmss($0) } ?? "—")
                .font(.system(size: figureSize, weight: .heavy).width(.condensed))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(draft == 0 ? .secondary : .primary)
                .contentTransition(reduceMotion ? .identity : .numericText(value: Double(draft ?? 0)))
            // Always laid out so the figure does not hop when zero toggles.
            Text(zeroLabel)
                .font(.headline)
                .multilineTextAlignment(.center)
                .opacity(draft == 0 ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(draft.map { $0 == 0 ? zeroLabel : Self.spoken($0) } ?? "Invalid duration")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(up: true)
            case .decrement: step(up: false)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("duration-readout")
    }

    private var steppers: some View {
        HStack(spacing: 12) {
            stepButton(up: false)
            stepButton(up: true)
        }
    }

    private func stepButton(up: Bool) -> some View {
        let atLimit = draft.map { up ? $0 >= RestDuration.maximumSeconds : $0 <= 0 } ?? true
        return Button { step(up: up) } label: {
            Label {
                Text("\(RestDuration.stepSeconds) s")
            } icon: {
                Image(systemName: up ? "plus" : "minus")
            }
            .labelStyle(.titleAndIcon)
            .font(.title3.weight(.heavy).width(.condensed))
            .frame(maxWidth: .infinity, minHeight: Theme.bigTap)
        }
        .buttonStyle(DurationChipStyle(selected: false))
        .buttonRepeatBehavior(.enabled)
        .disabled(atLimit)
        .accessibilityLabel(up ? "Add \(RestDuration.stepSeconds) seconds" : "Subtract \(RestDuration.stepSeconds) seconds")
    }

    private var presets: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12),
                            count: dynamicTypeSize.isAccessibilitySize ? 2 : 3)
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(RestDuration.presets, id: \.self) { preset in
                choice(mmss(preset), selected: draft == preset,
                       font: .title2.weight(.heavy).width(.condensed)) { set(preset) }
                    .accessibilityLabel(Self.spoken(preset))
            }
        }
    }

    private var exactEntry: some View {
        DisclosureGroup("Enter exact duration") {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 12),
                                count: dynamicTypeSize.isAccessibilitySize ? 1 : 3)
            LazyVGrid(columns: columns, spacing: 12) {
                durationField(.hours, text: $hours)
                durationField(.minutes, text: $minutes)
                durationField(.seconds, text: $seconds)
            }
            .padding(.top, 12)
        }
        .font(.body.weight(.semibold))
        .tint(Color.primary)
    }

    private func durationField(_ component: Component, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(component.rawValue)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(component.rawValue, text: text)
                .font(.title3.monospacedDigit())
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedComponent, equals: component)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.hairline))
                .accessibilityLabel(component.rawValue)
                .accessibilityIdentifier("duration-\(component.rawValue.lowercased())")
        }
    }

    private func choice(_ label: String, selected: Bool, font: Font,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(font)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: Theme.bigTap)
        }
        .buttonStyle(DurationChipStyle(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func set(_ seconds: Int) {
        focusedComponent = nil
        withAnimation(reduceMotion ? nil : .snappy(duration: Theme.shortMotion)) {
            hours = String(seconds / 3600)
            minutes = String(seconds / 60 % 60)
            self.seconds = String(seconds % 60)
        }
    }

    private func step(up: Bool) {
        guard let draft else { return }
        set(RestDuration.stepped(draft, up: up))
    }

    /// "1 minute, 30 seconds" — what VoiceOver should say instead of "1:30".
    static func spoken(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(max(0, seconds))) ?? mmss(max(0, seconds))
    }
}

/// Square-shouldered plates, not pills. The current value is the one thing
/// lit in the accent; everything else is steel on the canvas.
private struct DurationChipStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius)
        configuration.label
            .foregroundStyle(selected ? Theme.onAccent : Color.primary)
            .background(selected ? Theme.accent : Theme.card, in: shape)
            .overlay { shape.stroke(selected ? Color.clear : Theme.hairline, lineWidth: 1) }
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .contentShape(shape)
    }
}
