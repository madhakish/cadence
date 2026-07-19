import Foundation
import SwiftData

enum CoachingDecisionAction: String, Codable, CaseIterable {
    case accepted
    case deferred
    case dismissed
    case overridden
}

struct TemporaryAccessoryOverride {
    let percent: Int
    let cycleNumber: Int
    let rotation: Int
}

/// Audit trail for user-controlled deterministic coaching changes. The engine
/// can always recompute a recommendation; this record explains what the user
/// chose and prevents a deferred proposal from nagging again in the same data
/// state. It contains no repository-seeded personal defaults.
@Model
final class CoachingDecision {
    @Attribute(.unique) var id: String = UUID().uuidString
    var date: Date = Date.now
    var programID: String = ""
    var ruleID: String = ""
    var recommendationID: String = ""
    var actionRaw: String = "accepted"
    var title: String = ""
    var explanation: String = ""
    var evidence: [String] = []
    var beforeValue: String?
    var afterValue: String?

    init(
        programID: String,
        ruleID: String,
        recommendationID: String,
        action: CoachingDecisionAction,
        title: String,
        explanation: String,
        evidence: [String] = [],
        beforeValue: String? = nil,
        afterValue: String? = nil
    ) {
        self.id = UUID().uuidString
        self.date = .now
        self.programID = programID
        self.ruleID = ruleID
        self.recommendationID = recommendationID
        self.actionRaw = action.rawValue
        self.title = title
        self.explanation = explanation
        self.evidence = evidence
        self.beforeValue = beforeValue
        self.afterValue = afterValue
    }

    var action: CoachingDecisionAction {
        get { CoachingDecisionAction(rawValue: actionRaw) ?? .accepted }
        set { actionRaw = newValue.rawValue }
    }

    static func temporaryAccessoryValue(percent: Int, cycleNumber: Int, rotation: Int) -> String {
        "temporaryAccessoryPercent:\(percent):cycle:\(cycleNumber):rotation:\(rotation)"
    }

    var temporaryAccessoryOverride: TemporaryAccessoryOverride? {
        guard let afterValue else { return nil }
        let pieces = afterValue.split(separator: ":")
        guard pieces.count == 6, pieces[0] == "temporaryAccessoryPercent",
              pieces[2] == "cycle", pieces[4] == "rotation",
              let percent = Int(pieces[1]), let cycle = Int(pieces[3]),
              let rotation = Int(pieces[5]), (1...100).contains(percent) else { return nil }
        return TemporaryAccessoryOverride(
            percent: percent, cycleNumber: cycle, rotation: rotation
        )
    }
}
