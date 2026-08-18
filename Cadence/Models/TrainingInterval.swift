import Foundation
import SwiftData
import CadenceCore

/// A typed, dated span annotating a stretch of the calendar — not a session,
/// not a program day, but a layer over the timeline the rest of the app
/// reads. A gap the lifter chose must never read as a lapse, and the engine
/// must never grade a planned break as a red readiness flag.
///
/// The four kinds are deliberately distinct (INV-INTERVAL-KINDS-STAY-DISTINCT):
/// they differ in whether load was applied, whether the body was recovering,
/// and what the engine should do afterwards. Nothing collapses them into a
/// single "break" for storage, display, or grading.
@Model
final class TrainingInterval {
    @Attribute(.unique) var id: String = UUID().uuidString
    /// `deload` | `rest` | `away` | `activeRecovery` — see
    /// `TrainingIntervalKind` in CadenceCore.
    var kindRaw: String = "rest"
    /// Inclusive calendar-day bounds. Stored as the same start/end pair
    /// whichever entry affordance (days count or date range) created it;
    /// `enteredAsDays` remembers which, so editing reopens in that shape.
    var startDate: Date
    var endDate: Date
    var enteredAsDays: Bool = true
    var note: String = ""
    /// The program this span interrupts, when the lifter says so. Optional —
    /// an interval is a calendar fact, not program state.
    var programID: String?
    var createdAt: Date

    init(kindRaw: String = "rest", startDate: Date, endDate: Date,
         enteredAsDays: Bool = true, note: String = "", programID: String? = nil) {
        self.kindRaw = kindRaw
        self.startDate = startDate
        self.endDate = endDate
        self.enteredAsDays = enteredAsDays
        self.note = note
        self.programID = programID
        self.createdAt = .now
    }

    var kind: TrainingIntervalKind {
        get { TrainingIntervalKind(rawValue: kindRaw) ?? .rest }
        set { kindRaw = newValue.rawValue }
    }
}

/// Day-granular ISO date strings ("yyyy-MM-dd") are the portable interval
/// bound format — the web store and the backup contract carry exactly this
/// shape. Local calendar: a break is declared in the lifter's own days.
/// Noon-anchored parsing dodges DST-edge midnight ambiguity.
enum IntervalDay {
    static func string(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    static func date(from string: String) -> Date? {
        let parts = string.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]; c.hour = 12
        return Calendar.current.date(from: c)
    }
}
