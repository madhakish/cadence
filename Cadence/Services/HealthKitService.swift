import Foundation
import HealthKit
import CadenceCore

/// Optional and permission-gated, in two independent halves that are granted
/// separately and can be used separately:
///
/// - **Write** (`healthKitEnabled`, persisted in settings): mirrors completed
///   workouts and bodyweight out to Health.
/// - **Read** (`healthReadEnabled`, below): looks up conditioning distance to
///   compare against what was logged. Off by default.
///
/// [INV-HEALTH-IS-A-SECOND-OPINION] Reading never merges. It produces a verdict
/// naming both numbers; adopting one is an explicit tap. Health is a mirror and
/// a cross-check, never the source of truth.
final class HealthKitService {
    static let shared = HealthKitService()
    private let store = HKHealthStore()

    /// The read opt-in lives in `UserDefaults`, not SwiftData, on purpose.
    /// It mirrors a device-local OS permission, so it must not travel in a
    /// backup — restoring on a new phone would otherwise imply a Health grant
    /// that device never gave. HealthKit deliberately refuses to report read
    /// authorization status (that itself would leak health information), so
    /// the app has to remember that the lifter asked.
    private static let readEnabledKey = "healthReadEnabled"

    var isReadEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.readEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.readEnabledKey) }
    }

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

    /// Ask for the read half. Returns false when the prompt could not be shown;
    /// a *granted* result is not knowable, because HealthKit reports read
    /// denial as empty results rather than as an error.
    func requestReadAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
        ]
        do {
            try await store.requestAuthorization(toShare: [], read: types)
            return true
        } catch {
            return false
        }
    }

    /// Total conditioning distance Health recorded for a session window, in
    /// miles. nil when reading is off, unavailable, or Health has nothing —
    /// all three are "no second opinion", never "you did zero".
    ///
    /// Candidate workouts are whatever overlaps the window at all; which of
    /// them actually belong to the session is decided by the shared
    /// majority-overlap rule so both clients agree on the same set.
    func conditioningDistanceMiles(start: Date, end: Date) async -> Double? {
        guard isAvailable, isReadEnabled, end > start else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples: [HKSample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, _ in
                continuation.resume(returning: results ?? [])
            }
            store.execute(query)
        }
        var miles = 0.0
        for workout in samples.compactMap({ $0 as? HKWorkout }) {
            guard HealthComparison.sampleBelongsToSession(
                sampleStart: workout.startDate, sampleEnd: workout.endDate,
                sessionStart: start, sessionEnd: end
            ) else { continue }
            miles += distanceMiles(in: workout)
        }
        return miles > 0 ? miles : nil
    }

    /// Foot and wheel distance are separate quantities in Health; a session may
    /// legitimately contain both (a ruck and a bike cooldown).
    private func distanceMiles(in workout: HKWorkout) -> Double {
        let types: [HKQuantityType] = [
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
        ]
        return types.reduce(0.0) { total, type in
            total + (workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: .mile()) ?? 0)
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
