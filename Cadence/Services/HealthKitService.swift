import Foundation
import HealthKit
import CadenceCore

/// Optional and permission-gated, in two independent halves that are granted
/// separately and can be used separately:
///
/// - **Write** (`healthKitEnabled`, persisted in settings): mirrors completed
///   workouts, conditioning distance, bodyweight and body fat out to Health.
/// - **Read** (`healthReadEnabled`, below): looks up what Health recorded so it
///   can be shown beside what was logged. Off by default.
///
/// [INV-HEALTH-IS-A-SECOND-OPINION] Reading never merges. It produces a verdict
/// naming both numbers; adopting one is an explicit tap. Health is a mirror and
/// a cross-check, never the source of truth. **A read never counts Cadence's
/// own writes** — see `foreignSourcePredicate`.
///
/// What Health cannot hold: there is no schema for sets, reps or load.
/// `traditionalStrengthTraining` plus a duration is the entire vocabulary for
/// lifting, so the log stays the only complete record of a session.
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

    // MARK: - Anti-echo

    /// [INV-HEALTH-IS-A-SECOND-OPINION] Everything in Health *except* what
    /// Cadence put there.
    ///
    /// Cadence writes workouts, distance, bodyweight and body fat. Without this
    /// predicate every read would find those writes and agree with the log
    /// perfectly — a cross-check that always agrees is worse than none at all,
    /// because it reads as corroboration. Applied to **every** query in this
    /// file; `HealthComparison.sourceIsForeign` is the belt to its braces for
    /// samples carrying a source revision the predicate does not catch.
    private var foreignSourcePredicate: NSPredicate {
        NSCompoundPredicate(notPredicateWithSubpredicate:
            HKQuery.predicateForObjects(from: [HKSource.default()]))
    }

    private func windowPredicate(start: Date, end: Date) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end, options: []),
            foreignSourcePredicate,
        ])
    }

    /// The second layer. `HKSource.default()` identifies the app as Health
    /// currently knows it; a sample written by an earlier build can carry a
    /// source revision that survives the predicate, and one of those coming
    /// back as a "second opinion" is exactly the failure this guards.
    private func isForeign(_ sample: HKSample) -> Bool {
        HealthComparison.sourceIsForeign(
            bundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
            appBundleIdentifier: Bundle.main.bundleIdentifier
        )
    }

    // MARK: - Authorization

    func requestWriteAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let types: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
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
    /// denial as empty results rather than as an error. Every read below
    /// therefore treats "nothing came back" as "no second opinion", never as a
    /// measured zero.
    func requestReadAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.activeEnergyBurned),
            HKCategoryType(.sleepAnalysis),
        ]
        do {
            try await store.requestAuthorization(toShare: [], read: types)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Query plumbing

    private func samples(
        _ type: HKSampleType, predicate: NSPredicate, limit: Int = HKObjectQueryNoLimit,
        sortedNewestFirst: Bool = false
    ) async -> [HKSample] {
        let sort = sortedNewestFirst
            ? [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            : nil
        let results: [HKSample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: limit, sortDescriptors: sort
            ) { _, results, _ in
                continuation.resume(returning: results ?? [])
            }
            store.execute(query)
        }
        return results.filter(isForeign)
    }

    private func sum(
        _ type: HKQuantityType, unit: HKUnit, start: Date, end: Date
    ) async -> Double? {
        let found = await samples(type, predicate: windowPredicate(start: start, end: end))
        guard !found.isEmpty else { return nil }
        let total = found.compactMap { $0 as? HKQuantitySample }
            .reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
        return total > 0 ? total : nil
    }

    private func mostRecent(
        _ type: HKQuantityType, unit: HKUnit, since: Date
    ) async -> (value: Double, date: Date)? {
        let predicate = windowPredicate(start: since, end: .distantFuture)
        let found = await samples(type, predicate: predicate, limit: 1, sortedNewestFirst: true)
        guard let sample = found.first as? HKQuantitySample else { return nil }
        return (sample.quantity.doubleValue(for: unit), sample.startDate)
    }

    // MARK: - Conditioning

    /// Total conditioning distance Health recorded for a session window, in
    /// miles. nil when reading is off, unavailable, or Health has nothing —
    /// all three are "no second opinion", never "you did zero".
    ///
    /// Candidate workouts are whatever overlaps the window at all; which of
    /// them actually belong to the session is decided by the shared
    /// majority-overlap rule so both clients agree on the same set. Cadence's
    /// own mirrored workouts are excluded before any of that: they now carry
    /// real distance samples, so counting them would compare the log against
    /// itself.
    func conditioningDistanceMiles(start: Date, end: Date) async -> Double? {
        guard isAvailable, isReadEnabled, end > start else { return nil }
        let found = await samples(
            .workoutType(), predicate: windowPredicate(start: start, end: end)
        )
        var miles = 0.0
        for workout in found.compactMap({ $0 as? HKWorkout }) {
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

    /// Energy Health attributes to a session window, in kilocalories. Read
    /// only — Cadence has no heart rate and will not invent a calorie figure
    /// for a store other apps trust.
    func activeEnergyKilocalories(start: Date, end: Date) async -> Double? {
        guard isAvailable, isReadEnabled, end > start else { return nil }
        return await sum(HKQuantityType(.activeEnergyBurned),
                         unit: .kilocalorie(), start: start, end: end)
    }

    // MARK: - Body

    /// The most recent weigh-in Health has that Cadence did not write, with the
    /// body fat recorded alongside it. Both halves are optional: a smart scale
    /// reports body fat, a bathroom scale does not.
    func latestBodyweight(
        since: Date
    ) async -> (weightLb: Double, bodyFatPercent: Double?, date: Date)? {
        guard isAvailable, isReadEnabled else { return nil }
        guard let weight = await mostRecent(HKQuantityType(.bodyMass), unit: .pound(), since: since)
        else { return nil }
        // Only body fat from the same day as the weigh-in — pairing today's
        // weight with last month's caliper reading would invent a trend.
        let sameDay = Calendar.current.startOfDay(for: weight.date)
        let fat = await mostRecent(HKQuantityType(.bodyFatPercentage),
                                   unit: .percent(), since: sameDay)
        let fatPercent = fat.flatMap {
            Calendar.current.isDate($0.date, inSameDayAs: weight.date) ? $0.value * 100 : nil
        }
        return (weight.value, fatPercent, weight.date)
    }

    // MARK: - Recovery

    /// What Health's instruments say about recovery. Displayed, never stored,
    /// and deliberately **not** wired into readiness or progression: Cadence
    /// grades from work actually performed, which is the more defensible signal
    /// for a self-coached lifter than an overnight HRV reading.
    struct RecoverySnapshot {
        var hrvMilliseconds: Double?
        var restingHeartRate: Double?
        var asleepSeconds: Int?

        var isEmpty: Bool {
            hrvMilliseconds == nil && restingHeartRate == nil && asleepSeconds == nil
        }
    }

    func recovery(on day: Date = .now) async -> RecoverySnapshot {
        guard isAvailable, isReadEnabled else { return RecoverySnapshot() }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let lookback = calendar.date(byAdding: .day, value: -2, to: dayStart) ?? dayStart

        async let hrv = mostRecent(HKQuantityType(.heartRateVariabilitySDNN),
                                   unit: .secondUnit(with: .milli), since: lookback)
        async let resting = mostRecent(HKQuantityType(.restingHeartRate),
                                       unit: HKUnit.count().unitDivided(by: .minute()),
                                       since: lookback)
        async let sleep = asleepSeconds(nightEnding: dayStart)
        return await RecoverySnapshot(
            hrvMilliseconds: hrv?.value,
            restingHeartRate: resting?.value,
            asleepSeconds: sleep
        )
    }

    /// Last night's sleep, from the noon before to the noon after — the window
    /// Health itself treats as "a night", so a 2am bedtime is not split in two.
    /// Which stages count as sleep is the shared rule in `HealthComparison`.
    private func asleepSeconds(nightEnding dayStart: Date) async -> Int? {
        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .hour, value: 12, to: dayStart),
              let start = calendar.date(byAdding: .hour, value: -12, to: dayStart)
        else { return nil }
        let found = await samples(
            HKCategoryType(.sleepAnalysis), predicate: windowPredicate(start: start, end: end)
        )
        let stages = found.compactMap { sample -> (stage: String, seconds: Int)? in
            guard let category = sample as? HKCategorySample,
                  let stage = Self.sleepStageName(category.value) else { return nil }
            return (stage, Int(category.endDate.timeIntervalSince(category.startDate)))
        }
        guard !stages.isEmpty else { return nil }
        let seconds = HealthComparison.asleepSeconds(stages: stages)
        return seconds > 0 ? seconds : nil
    }

    /// HealthKit's raw category values, named so the shared rule can live in
    /// Foundation-only code rather than be duplicated against an
    /// Apple-framework enum.
    private static func sleepStageName(_ value: Int) -> String? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed: return "inBed"
        case .awake: return "awake"
        case .asleepUnspecified: return "asleepUnspecified"
        case .asleepCore: return "asleepCore"
        case .asleepDeep: return "asleepDeep"
        case .asleepREM: return "asleepREM"
        default: return nil
        }
    }

    // MARK: - Writing

    /// Mirror a completed session out to Health.
    ///
    /// `distanceMiles` is the conditioning distance the session logged. Before
    /// this carried a sample the workout held only start, end and type, which
    /// is why Health showed nothing but a duration. Sets, reps and load have no
    /// HealthKit representation at all and stay in the log.
    func saveWorkout(
        start: Date, end: Date, modality: WorkoutModality, distanceMiles: Double? = nil
    ) async {
        guard isAvailable else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = activityType(for: modality)
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            if let miles = distanceMiles, miles > 0, let type = distanceType(for: modality) {
                let sample = HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: .mile(), doubleValue: miles),
                    start: start, end: end
                )
                try await builder.addSamples([sample])
            }
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

    /// Which distance quantity a modality's miles belong to. Foot and wheel are
    /// separate in Health, and the remaining modalities either cover no ground
    /// or cover it in water — filing a swim under walking distance would be a
    /// lie, so those sessions carry duration only.
    private func distanceType(for modality: WorkoutModality) -> HKQuantityType? {
        switch modality {
        case .running, .walking, .hiking: return HKQuantityType(.distanceWalkingRunning)
        case .cycling: return HKQuantityType(.distanceCycling)
        case .traditionalStrength, .crossTraining, .rowing, .swimming: return nil
        }
    }

    func saveBodyweight(lb: Double, bodyFatPercent: Double? = nil, date: Date) async {
        guard isAvailable else { return }
        var samples: [HKSample] = [
            HKQuantitySample(
                type: HKQuantityType(.bodyMass),
                quantity: HKQuantity(unit: .pound(), doubleValue: lb),
                start: date, end: date
            )
        ]
        // Health stores body fat as a fraction; the app stores and shows a
        // percentage. Writing 18 where 0.18 belongs would read as 1800% fat.
        if let percent = bodyFatPercent, percent > 0, percent < 100 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.bodyFatPercentage),
                quantity: HKQuantity(unit: .percent(), doubleValue: percent / 100),
                start: date, end: date
            ))
        }
        try? await store.save(samples)
    }
}
