import SwiftUI
import CadenceCore

/// This reading belongs only to the open bank summary. It never enters the
/// session model, backups, logs, analytics or progression.
struct RuckStepsSection: View {
    let timing: HealthWorkoutTiming.Export
    @AppStorage(HealthKitService.stepsReadEnabledKey) private var enabled = false
    @State private var reading: HealthKitService.StepReading?
    @State private var loading = false
    @State private var refresh = 0

    var body: some View {
        Section {
            HealthStepsReadToggle()
            if enabled {
                if loading {
                    ProgressView("Reading measured steps…")
                } else if let reading {
                    switch reading {
                    case .measured(let count):
                        Text("\(count.formatted(.number.precision(.fractionLength(0)))) steps recorded in Health")
                            .font(.headline)
                    case .noData:
                        Text("No step reading available. Health may still be syncing, or step access may be off. This does not mean zero steps.")
                    case .unavailable:
                        Text("Apple Health isn't available on this device.")
                    case .failed:
                        Text("Steps couldn't be read. Your ruck is saved; you can try again.")
                    case .disabled:
                        Text("Step reading is off.")
                    }
                }
                Button("Refresh steps") { refresh += 1 }
                    .disabled(loading)
            }
        } header: {
            Text("Measured steps · ruck window")
        } footer: {
            Text("Health records overlapping \(timing.start.formatted(date: .abbreviated, time: .standard))–\(timing.end.formatted(date: .abbreviated, time: .standard)), including any pauses inside that window. This is not an active-only count. Phone or watch readings may arrive later. Shown here only; no steps are estimated or written to Health.")
        }
        .task(id: "\(enabled)-\(refresh)") {
            reading = nil
            guard enabled else { loading = false; return }
            loading = true
            let result = await HealthKitService.shared.ruckSteps(timing: timing)
            guard !Task.isCancelled else { return }
            reading = result
            loading = false
        }
    }
}

/// Separate opt-in even when the older conditioning comparison is enabled.
/// A failed prompt leaves this off; a successful prompt may still mean denial.
struct HealthStepsReadToggle: View {
    @AppStorage(HealthKitService.stepsReadEnabledKey) private var enabled = false
    @State private var requesting = false
    @State private var requestFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Read measured ruck steps", isOn: Binding(
                get: { enabled },
                set: { on in
                    requestFailed = false
                    guard on else { enabled = false; return }
                    requesting = true
                    Task {
                        let completed = await HealthKitService.shared.requestStepsReadAuthorization()
                        enabled = completed
                        requestFailed = !completed
                        requesting = false
                    }
                }
            ))
            .disabled(requesting)
            Text("Separately allow reading Steps from Apple Health for timed ruck summaries. Off by default; stays on this device and never changes your log.")
                .font(.caption).foregroundStyle(.secondary)
            if requesting { ProgressView("Requesting Health step access…") }
            if requestFailed {
                Text("Health step access couldn't be requested. You can try again; logging your ruck still works.")
                    .font(.caption)
            }
        }
    }
}
