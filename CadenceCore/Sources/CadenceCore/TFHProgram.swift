import Foundation

/// Portable TFH configuration. A new identity starts a new evidence cohort;
/// existing sessions retain their own anchor and prescription snapshots.
public struct TFHProgramPolicy: Codable, Equatable, Sendable {
    public var version: Int
    public var id: String
    public var startCycle: Int
    public var dayOrders: [Int]
    public var recoveryDayOrders: [Int]
    public var anchors: [String: TFHAnchor]
    public var layout: [String: String]

    public init(id: String, startCycle: Int, dayOrders: [Int], recoveryDayOrders: [Int],
                anchors: [String: TFHAnchor], layout: [String: String]) {
        self.version = 1; self.id = id; self.startCycle = startCycle
        self.dayOrders = dayOrders; self.recoveryDayOrders = recoveryDayOrders
        self.anchors = anchors
        self.layout = layout
    }

    public var isValid: Bool {
        version == 1 && !id.isEmpty && startCycle > 0 && dayOrders.count >= 2
            && dayOrders.count <= 20 && dayOrders.allSatisfy { $0 >= 0 }
            && Set(dayOrders).count == dayOrders.count
            && (2...3).contains(recoveryDayOrders.count)
            && Set(recoveryDayOrders).count == recoveryDayOrders.count
            && recoveryDayOrders.allSatisfy { dayOrders.contains($0) }
            && !anchors.isEmpty && anchors.count <= 100
            && anchors.allSatisfy { !$0.key.isEmpty && $0.value.isValid }
            && Set(anchors.values.map(\.id)).count == anchors.count
            && !layout.isEmpty && layout.count <= 200
            && anchors.keys.allSatisfy { layout[$0] != nil }
    }
}

public enum TFHBenchmarkStop: String, Codable, CaseIterable, Sendable {
    case technicalLimit, repCap, pain, interrupted, voluntary
}

public struct TFHBenchmarkResult: Codable, Equatable, Sendable {
    public var stopReason: TFHBenchmarkStop?
    public var restSeconds: Double?

    public init(stopReason: TFHBenchmarkStop? = nil, restSeconds: Double? = nil) {
        self.stopReason = stopReason; self.restSeconds = restSeconds
    }

    public var isValid: Bool {
        restSeconds.map { $0.isFinite && $0 > 0 && $0 <= 3600 } ?? true
    }
}

/// Only completed, correctly tagged sessions belong in this input.
public struct TFHCompletion: Equatable, Sendable {
    public var cycle: Int
    public var rotation: Int
    public var dayOrder: Int
    public init(cycle: Int, rotation: Int, dayOrder: Int) {
        self.cycle = cycle; self.rotation = rotation; self.dayOrder = dayOrder
    }
}

public struct TFHPosition: Equatable, Sendable {
    public var cycle: Int
    public var rotation: Int
    public var dayOrder: Int
    public var completedCycles: [Int]
}

public enum TFHSchedule {
    /// Finds the first uncompleted position from canonical session tags. No
    /// calendar expiry and no mutable stall/weight grade participates.
    public static func position(policy: TFHProgramPolicy, completions: [TFHCompletion]) -> TFHPosition? {
        guard policy.isValid else { return nil }
        func key(_ cycle: Int, _ rotation: Int, _ day: Int) -> String { "\(cycle):\(rotation):\(day)" }
        var occupied: Set<String> = []
        for e in completions where e.cycle >= policy.startCycle {
            let days = e.rotation == 4 ? policy.recoveryDayOrders : policy.dayOrders
            guard (1...4).contains(e.rotation), days.contains(e.dayOrder),
                  occupied.insert(key(e.cycle, e.rotation, e.dayOrder)).inserted else { return nil }
        }
        var cycle = policy.startCycle
        var completedCycles: [Int] = []
        // Each complete cycle consumes at least one input record. The bound
        // prevents an invalid distant cycle number from driving a huge loop.
        for _ in 0...completions.count {
            for rotation in 1...4 {
                let days = rotation == 4 ? policy.recoveryDayOrders : policy.dayOrders
                for day in days where !occupied.contains(key(cycle, rotation, day)) {
                    return TFHPosition(cycle: cycle, rotation: rotation, dayOrder: day,
                                       completedCycles: completedCycles)
                }
            }
            completedCycles.append(cycle)
            guard cycle < Int.max else { return nil }
            cycle += 1
        }
        return nil
    }
}
