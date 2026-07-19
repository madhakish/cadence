import Foundation
import HealthKit
import CadenceCore

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

    func saveWorkout(start: Date, end: Date, modality: WorkoutModality) async {
        guard isAvailable else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = activityType(for: modality)
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            try await builder.finishWorkout()
        } catch {
            // Non-fatal: HealthKit is a mirror, never the source of truth.
        }
    }

    private func activityType(for modality: WorkoutModality) -> HKWorkoutActivityType {
        switch modality {
        case .traditionalStrength: return .traditionalStrengthTraining
        case .crossTraining: return .crossTraining
        case .running: return .running
        case .walking: return .walking
        case .hiking: return .hiking
        case .cycling: return .cycling
        case .rowing: return .rowing
        case .swimming: return .swimming
        }
    }

    func saveBodyweight(lb: Double, date: Date) async {
        guard isAvailable else { return }
        let quantity = HKQuantity(unit: .pound(), doubleValue: lb)
        let sample = HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: quantity, start: date, end: date)
        try? await store.save(sample)
    }
}
