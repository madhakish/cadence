import Foundation
import HealthKit

/// Optional, permission-gated. WRITE workouts and bodyweight only — this app
/// reads nothing from HealthKit. Off by default; toggled in Settings.
final class HealthKitService {
    static let shared = HealthKitService()
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestWriteAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let types: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.bodyMass),
        ]
        do {
            try await store.requestAuthorization(toShare: types, read: [])
            return true
        } catch {
            return false
        }
    }

    func saveStrengthWorkout(start: Date, end: Date) async {
        guard isAvailable else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            try await builder.finishWorkout()
        } catch {
            // Non-fatal: HealthKit is a mirror, never the source of truth.
        }
    }

    func saveBodyweight(lb: Double, date: Date) async {
        guard isAvailable else { return }
        let quantity = HKQuantity(unit: .pound(), doubleValue: lb)
        let sample = HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: quantity, start: date, end: date)
        try? await store.save(sample)
    }
}
