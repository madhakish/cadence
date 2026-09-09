import Foundation
import CadenceCore

extension CoachingService {
    static func tfhReport(program: Program, sessions: [WorkoutSession]) -> CoachingReport {
        var recommendations: [CoachingRecommendation] = []
        do {
            guard let p = try TFHProgramService.policy(program) else {
                throw TFHProgramService.Failure.invalid("Missing policy.")
            }
            let next = try TFHProgramService.position(program, policy: p, sessions: sessions)
            let history = try TFHProgramService.exposures(program, policy: p, sessions: sessions)
            let names = Dictionary(uniqueKeysWithValues: program.days.flatMap {
                $0.lifts.map { ($0.id, $0.exerciseName) } + $0.accessories.map { ($0.id, $0.exerciseName) }
            })
            for id in p.anchors.keys.sorted() {
                guard let anchor = p.anchors[id] else { continue }
                let assessment = TFHProgression.plateau(anchor: anchor, exposures: history,
                    completedCycles: next.completedCycles, currentCycle: next.cycle)
                recommendations.append(CoachingRecommendation(ruleID: "tfh.\(assessment.state)", priority: 30,
                    title: "\(names[id] ?? "Exercise") · \(assessment.state == "possiblePlateau" ? "review capacity" : assessment.state)",
                    explanation: assessment.reason, change: .hold,
                    evidenceKey: "\(p.id):\(id):\(next.cycle)"))
            }
        } catch {
            recommendations = [CoachingRecommendation(ruleID: "tfh.review", priority: 1,
                title: "Review TFH history", explanation: error.localizedDescription, change: .hold)]
        }
        // Capacity evidence does not establish today's physiological readiness.
        return CoachingReport(rotations: [], currentReadiness: .unknown, greenRotationStreak: 0,
                              recommendations: recommendations)
    }
}
