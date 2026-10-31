import CadenceCore
import Foundation
import HealthKit

/// The watch's workout session (design #339, section 6). It keeps the app
/// running with the wrist down, supplies the small heart-rate reading, and at
/// the end either saves the workout or discards it, reporting which.
@MainActor
final class WorkoutRecorder: NSObject, ObservableObject {
    @Published private(set) var heartRate: Int?
    @Published private(set) var isRecording = false

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    /// Asks for Health permission the first time (owner decision 12), then
    /// starts collecting. Declining still lets the session run on the watch.
    func start(modality: WorkoutModality? = nil) async {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = Self.activityType(for: modality ?? .traditionalStrength)
            configuration.locationType = modality == .hiking ? .outdoor : .indoor
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            builder.delegate = self
            self.session = session
            self.builder = builder
            let now = Date()
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            isRecording = true
        } catch {
            session = nil
            builder = nil
        }
    }

    /// Same mapping as the phone's `HealthKitService`, so a workout recorded on
    /// the watch has the type the phone would have exported.
    static func activityType(for modality: WorkoutModality) -> HKWorkoutActivityType {
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

    /// Ends the workout. With `save`, the workout goes to Health; otherwise it
    /// is discarded. A finish that fails after Health may have committed is
    /// `unknown`, never retried (matching `HealthKitService.saveWorkout`).
    func finish(save: Bool) async -> SyncHealthOutcome {
        defer {
            session = nil
            builder = nil
            isRecording = false
            heartRate = nil
        }
        guard let session, let builder else { return .notWritten }
        session.end()
        do {
            try await builder.endCollection(at: Date())
        } catch {
            builder.discardWorkout()
            return .notWritten
        }
        guard save else {
            builder.discardWorkout()
            return .notWritten
        }
        do {
            guard let workout = try await builder.finishWorkout() else { return .unknown }
            return .saved(workoutID: workout.uuid.uuidString)
        } catch {
            return .unknown
        }
    }
}

extension WorkoutRecorder: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let type = HKQuantityType(.heartRate)
        guard collectedTypes.contains(type),
              let quantity = workoutBuilder.statistics(for: type)?.mostRecentQuantity() else { return }
        let bpm = Int(quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
        Task { @MainActor in self.heartRate = bpm }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
