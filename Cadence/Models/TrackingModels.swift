import Foundation
import SwiftData
import CadenceCore

/// Per-lift progression state. Each main lift advances on its own track,
/// keyed to its last completed session — never to the calendar.
@Model
final class LiftTrack {
    @Attribute(.unique) var exerciseName: String
    var modeRaw: String
    var cycleNumber: Int
    /// Cycle mode: week-1 volume weight. Linear mode: current working weight.
    var baseWeightLb: Double
    var nextPhaseRaw: Int
    var incrementLb: Double
    var roundingLb: Double
    var lastCompletedAt: Date?

    init(
        exerciseName: String,
        mode: TrackMode = .cycle,
        cycleNumber: Int = 1,
        baseWeightLb: Double,
        nextPhase: CyclePhase = .volume,
        incrementLb: Double = 10,
        roundingLb: Double = 5
    ) {
        self.exerciseName = exerciseName
        self.modeRaw = mode.rawValue
        self.cycleNumber = cycleNumber
        self.baseWeightLb = baseWeightLb
        self.nextPhaseRaw = nextPhase.rawValue
        self.incrementLb = incrementLb
        self.roundingLb = roundingLb
    }

    var mode: TrackMode {
        get { TrackMode(rawValue: modeRaw) ?? .cycle }
        set { modeRaw = newValue.rawValue }
    }

    var nextPhase: CyclePhase {
        get { CyclePhase(rawValue: nextPhaseRaw) ?? .volume }
        set { nextPhaseRaw = newValue.rawValue }
    }

    var cycleState: CycleState {
        CycleState(
            cycleNumber: cycleNumber,
            baseWeightLb: baseWeightLb,
            nextPhase: nextPhase,
            incrementLb: incrementLb
        )
    }

    /// Next suggested session. Editable in two taps at session start.
    var suggestion: SessionPlan {
        switch mode {
        case .cycle:
            return ProgramEngine.plan(for: cycleState, roundingLb: roundingLb)
        case .linear:
            return SessionPlan(weightLb: baseWeightLb, sets: 3, reps: 5)
        }
    }

    /// Mark the suggested session completed and advance the track.
    func completeSession() {
        lastCompletedAt = .now
        switch mode {
        case .cycle:
            let advanced = ProgramEngine.advancing(cycleState, afterCompleting: nextPhase)
            cycleNumber = advanced.cycleNumber
            baseWeightLb = advanced.baseWeightLb
            nextPhase = advanced.nextPhase
        case .linear:
            baseWeightLb += incrementLb
        }
    }
}

@Model
final class BodyweightEntry {
    var date: Date
    var weightLb: Double
    var bodyFatPercent: Double?
    /// Optional user-authored chart annotation.
    var milestoneLabel: String?

    init(date: Date = .now, weightLb: Double, bodyFatPercent: Double? = nil, milestoneLabel: String? = nil) {
        self.date = date
        self.weightLb = weightLb
        self.bodyFatPercent = bodyFatPercent
        self.milestoneLabel = milestoneLabel
    }
}

@Model
final class ProteinEntry {
    var date: Date
    var grams: Double
    var label: String

    init(date: Date = .now, grams: Double, label: String) {
        self.date = date
        self.grams = grams
        self.label = label
    }
}

/// Optional body-signal check-in.
@Model
final class CheckIn {
    var date: Date
    var siteRaw: String
    /// "none" / "swelling" / free text.
    var response: String
    var note: String

    init(date: Date = .now, site: BodySite, response: String, note: String = "") {
        self.date = date
        self.siteRaw = site.rawValue
        self.response = response
        self.note = note
    }

    var site: BodySite? { BodySite.fromStorage(siteRaw) }
    var isHardStop: Bool {
        let value = response.lowercased()
        return ["flag", "pain", "swell", "off"].contains { value.contains($0) }
    }
}

/// Auto-detected milestone, persisted so the history reads like a logbook.
@Model
final class Milestone {
    var date: Date
    var exerciseName: String?
    var kindRaw: String
    var label: String

    init(date: Date = .now, exerciseName: String? = nil, kind: PREvent.Kind, label: String) {
        self.date = date
        self.exerciseName = exerciseName
        self.kindRaw = kind.rawValue
        self.label = label
    }
}
