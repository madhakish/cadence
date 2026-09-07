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
        .accessibilityValue(seconds == 0 ? zeroLabel : RestDuration.label(seconds))
        .accessibilityHint("Edit hours, minutes and seconds")
        .sheet(isPresented: $showingEditor) {
            DurationEditor(title: title, seconds: seconds, zeroLabel: zeroLabel) { seconds = $0 }
        }
    }

    private var value: some View {
        Label(seconds == 0 ? zeroLabel : RestDuration.label(seconds), systemImage: "timer")
            .monospacedDigit()
            .foregroundStyle(Theme.accent)
    }
}

struct DurationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let zeroLabel: String
    let onSave: (Int) -> Void
    @State private var hours: String
    @State private var minutes: String
    @State private var seconds: String

    init(title: String, seconds: Int, zeroLabel: String, onSave: @escaping (Int) -> Void) {
        self.title = title
        self.zeroLabel = zeroLabel
        self.onSave = onSave
        _hours = State(initialValue: String(seconds / 3600))
        _minutes = State(initialValue: String(seconds / 60 % 60))
        _seconds = State(initialValue: String(seconds % 60))
    }

    private var duration: Int? { RestDuration.parse(hours: hours, minutes: minutes, seconds: seconds) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                        : AnyLayout(HStackLayout(spacing: 12))
                    layout {
                        field("Hours", text: $hours)
                        field("Minutes", text: $minutes)
                        field("Seconds", text: $seconds)
                    }
                    Text(duration.map { $0 == 0 ? zeroLabel : RestDuration.label($0) } ?? "Enter a duration from 00:00:00 to 01:00:00.")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(duration == nil ? Theme.warn : Color.primary)
                        .accessibilityLabel("Selected duration")
                        .accessibilityValue(duration.map { $0 == 0 ? zeroLabel : RestDuration.label($0) } ?? "Invalid duration")
                    Button(zeroLabel) { hours = "0"; minutes = "0"; seconds = "0" }
                } footer: {
                    Text("Up to one hour. Extra seconds and minutes carry into the next unit when saved. Changes apply only when you tap Save.")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let duration else { return }
                        onSave(duration)
                        dismiss()
                    }
                    .disabled(duration == nil)
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline)
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .font(.title2.monospacedDigit())
                .frame(minHeight: 44)
                .accessibilityLabel(label)
        }
    }
}
