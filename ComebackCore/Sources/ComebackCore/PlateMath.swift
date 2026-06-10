import Foundation

/// Result of a plate-math solve.
public struct PlateSolution: Hashable, Codable, Sendable {
    public let loadout: Loadout
    public let targetLb: Double

    public init(loadout: Loadout, targetLb: Double) {
        self.loadout = loadout
        self.targetLb = targetLb
    }

    /// achieved − target, in lb. Positive = bar is heavier than asked.
    public var deviationLb: Double { loadout.totalLb - targetLb }

    /// True when the closest achievable load misses the target by more than 2 lb.
    public var isOffTarget: Bool { abs(deviationLb) > PlateMath.toleranceLb }

    /// "42.5 kg/side on 45 lb bar = 232.4 lb / 105.4 kg total"
    public var summary: String {
        let side = loadout.perSideLabel
        return "\(side) per side on \(loadout.bar.label) = \(Weight.both(lb: loadout.totalLb)) total"
    }
}

public enum PlateMath {
    /// Warn when achieved differs from target by more than this.
    public static let toleranceLb = 2.0

    /// Find the per-side plate combination (mixed units allowed) closest to the
    /// target total. Ties prefer fewer plates, then erring under the target.
    ///
    /// - Parameters:
    ///   - targetLb: desired TOTAL bar weight in lb (convert kg before calling).
    ///   - bar: the bar in use.
    ///   - plates: available denominations (unlimited pairs of each).
    ///   - maxPerPlateSide: sanity cap per denomination per side.
    public static func solve(
        targetLb: Double,
        bar: Bar,
        plates: [Plate],
        maxPerPlateSide: Int = 10
    ) -> PlateSolution {
        let perSideTarget = (targetLb - bar.lb) / 2.0
        let sorted = Array(Set(plates)).sorted { $0.lb > $1.lb }

        guard perSideTarget > 1e-9, !sorted.isEmpty else {
            return PlateSolution(loadout: Loadout(bar: bar, perSide: []), targetLb: targetLb)
        }

        let values = sorted.map(\.lb)
        var counts = [Int](repeating: 0, count: sorted.count)
        var bestCounts = counts
        var bestDev = perSideTarget * 2.0 // empty-bar baseline
        var bestSigned = -perSideTarget * 2.0
        var bestPlates = 0
        var nodes = 0

        func consider(remaining: Double, used: Int) {
            let signed = -remaining * 2.0 // achieved − target
            let dev = abs(signed)
            let better: Bool
            if dev < bestDev - 1e-9 {
                better = true
            } else if abs(dev - bestDev) <= 1e-9 {
                if used < bestPlates {
                    better = true
                } else if used == bestPlates && signed < bestSigned - 1e-9 {
                    better = true // equal miss: prefer under target
                } else {
                    better = false
                }
            } else {
                better = false
            }
            if better {
                bestDev = dev
                bestSigned = signed
                bestPlates = used
                bestCounts = counts
            }
        }

        func search(_ index: Int, _ remaining: Double, _ used: Int) {
            nodes += 1
            guard nodes < 300_000 else { return }
            consider(remaining: remaining, used: used)
            guard index < values.count, remaining > 1e-9 else { return }
            let v = values[index]
            // +1 allows one plate of overshoot so "closest over" is reachable.
            let maxCount = min(maxPerPlateSide, Int((remaining / v).rounded(.down)) + 1)
            var c = maxCount
            while c >= 0 {
                let next = remaining - Double(c) * v
                // Overshoot already worse than best: smaller counts may still win.
                if next < 0 && -next * 2.0 > bestDev + 1e-9 {
                    c -= 1
                    continue
                }
                counts[index] = c
                search(index + 1, next, used + c)
                c -= 1
            }
            counts[index] = 0
        }

        search(0, perSideTarget, 0)

        let perSide = zip(sorted, bestCounts).compactMap { plate, count in
            count > 0 ? PlateCount(plate: plate, count: count) : nil
        }
        return PlateSolution(loadout: Loadout(bar: bar, perSide: perSide), targetLb: targetLb)
    }

    /// Reverse mode: what's on the bar (per side, mixed units) → total.
    public static func total(bar: Bar, perSide: [PlateCount]) -> Double {
        Loadout(bar: bar, perSide: perSide).totalLb
    }
}
