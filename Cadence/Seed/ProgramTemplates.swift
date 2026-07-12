import Foundation
import SwiftData
import CadenceCore

/// Pre-programmed starting points for "Add program" (the style picker).
/// Each template is DATA: a focus, days of lifts/accessories, and the library
/// exercises it needs (created only if missing — an existing exercise is never
/// overwritten). Baselines start deliberately light: the docs walk through
/// setting rotation-1 bases before the first session. Ported 1:1 from
/// web/js/templates.js — keep the two in lockstep.
enum ProgramTemplates {

    struct TemplateExercise {
        let name: String
        let category: ExerciseCategory
        let type: ExerciseType
        let group: String
        var isUnilateral = false
        var rest = 90
    }
    struct TemplateLift {
        let exercise: String
        let role: LiftRole
        let baseWeightLb: Double
        let estimatedMaxLb: Double
    }
    struct TemplateAccessory {
        let exercise: String
        let sets: Int
        let minReps: Int
        let maxReps: Int
        var weightLb: Double = 0
        var incrementLb: Double = 0
    }
    struct TemplateDay {
        let name: String
        let lifts: [TemplateLift]
        let accessories: [TemplateAccessory]
    }
    struct Template: Identifiable {
        let id: String
        let name: String
        let tagline: String
        let focus: TrainingFocus
        let roundingLb: Double
        let exercises: [TemplateExercise]
        let days: [TemplateDay]
    }

    static let all: [Template] = [
        Template(
            id: "strength-upper-lower",
            name: "Strength — Upper/Lower",
            tagline: "4 days · barbell strength · A/B split over a 4-week wave",
            focus: .strength, roundingLb: 5,
            exercises: [
                TemplateExercise(name: "Overhead Press", category: .main, type: .barbell, group: "press", rest: 300),
                TemplateExercise(name: "Push Press", category: .main, type: .barbell, group: "press", rest: 300),
                TemplateExercise(name: "Incline DB Press", category: .main, type: .dumbbell, group: "press", rest: 180),
                TemplateExercise(name: "Back Squat", category: .main, type: .barbell, group: "squat", rest: 300),
                TemplateExercise(name: "Front Squat", category: .main, type: .barbell, group: "squat", rest: 300),
                TemplateExercise(name: "Deadlift", category: .main, type: .barbell, group: "hinge", rest: 300),
                TemplateExercise(name: "Romanian Deadlift", category: .main, type: .barbell, group: "hinge", rest: 180),
                TemplateExercise(name: "Chin-ups", category: .accessory, type: .bodyweight, group: "pull", rest: 120),
                TemplateExercise(name: "One-arm DB Row", category: .accessory, type: .dumbbell, group: "pull", isUnilateral: true),
                TemplateExercise(name: "Walking Lunges", category: .accessory, type: .bodyweight, group: "squat", isUnilateral: true),
                TemplateExercise(name: "Back Extension", category: .accessory, type: .bodyweight, group: "hinge"),
                TemplateExercise(name: "Hanging Knee Raise", category: .accessory, type: .bodyweight, group: "core"),
                TemplateExercise(name: "Push-ups", category: .accessory, type: .bodyweight, group: "press"),
            ],
            days: [
                TemplateDay(name: "Upper A",
                            lifts: [TemplateLift(exercise: "Overhead Press", role: .main, baseWeightLb: 65, estimatedMaxLb: 95),
                                    TemplateLift(exercise: "Incline DB Press", role: .complementary, baseWeightLb: 50, estimatedMaxLb: 80)],
                            accessories: [TemplateAccessory(exercise: "Chin-ups", sets: 3, minReps: 5, maxReps: 10),
                                          TemplateAccessory(exercise: "One-arm DB Row", sets: 3, minReps: 8, maxReps: 12, weightLb: 40, incrementLb: 5)]),
                TemplateDay(name: "Lower A",
                            lifts: [TemplateLift(exercise: "Back Squat", role: .main, baseWeightLb: 135, estimatedMaxLb: 205),
                                    TemplateLift(exercise: "Romanian Deadlift", role: .complementary, baseWeightLb: 95, estimatedMaxLb: 165)],
                            accessories: [TemplateAccessory(exercise: "Walking Lunges", sets: 3, minReps: 10, maxReps: 20),
                                          TemplateAccessory(exercise: "Hanging Knee Raise", sets: 3, minReps: 8, maxReps: 15)]),
                TemplateDay(name: "Upper B",
                            lifts: [TemplateLift(exercise: "Push Press", role: .main, baseWeightLb: 75, estimatedMaxLb: 115),
                                    TemplateLift(exercise: "Incline DB Press", role: .complementary, baseWeightLb: 50, estimatedMaxLb: 80)],
                            accessories: [TemplateAccessory(exercise: "Push-ups", sets: 3, minReps: 10, maxReps: 25),
                                          TemplateAccessory(exercise: "One-arm DB Row", sets: 3, minReps: 8, maxReps: 12, weightLb: 40, incrementLb: 5)]),
                TemplateDay(name: "Lower B",
                            lifts: [TemplateLift(exercise: "Deadlift", role: .main, baseWeightLb: 155, estimatedMaxLb: 245),
                                    TemplateLift(exercise: "Front Squat", role: .complementary, baseWeightLb: 95, estimatedMaxLb: 155)],
                            accessories: [TemplateAccessory(exercise: "Back Extension", sets: 3, minReps: 10, maxReps: 15),
                                          TemplateAccessory(exercise: "Hanging Knee Raise", sets: 3, minReps: 8, maxReps: 15)]),
            ]
        ),
        Template(
            id: "olympic-weightlifting",
            name: "Olympic Weightlifting",
            tagline: "3 days · snatch, clean & jerk, strength base",
            focus: .strength, roundingLb: 5,
            exercises: [
                TemplateExercise(name: "Snatch", category: .main, type: .barbell, group: "olympic", rest: 300),
                TemplateExercise(name: "Clean and Jerk", category: .main, type: .barbell, group: "olympic", rest: 300),
                TemplateExercise(name: "Overhead Squat", category: .main, type: .barbell, group: "squat", rest: 300),
                TemplateExercise(name: "Front Squat", category: .main, type: .barbell, group: "squat", rest: 300),
                TemplateExercise(name: "Back Squat", category: .main, type: .barbell, group: "squat", rest: 300),
                TemplateExercise(name: "Snatch Pull", category: .accessory, type: .barbell, group: "olympic", rest: 180),
                TemplateExercise(name: "Clean Pull", category: .accessory, type: .barbell, group: "olympic", rest: 180),
                TemplateExercise(name: "Overhead Press", category: .main, type: .barbell, group: "press", rest: 300),
                TemplateExercise(name: "Pull-ups", category: .accessory, type: .bodyweight, group: "pull", rest: 120),
                TemplateExercise(name: "Back Extension", category: .accessory, type: .bodyweight, group: "hinge"),
                TemplateExercise(name: "Hanging Knee Raise", category: .accessory, type: .bodyweight, group: "core"),
            ],
            days: [
                TemplateDay(name: "Snatch Day",
                            lifts: [TemplateLift(exercise: "Snatch", role: .main, baseWeightLb: 65, estimatedMaxLb: 115),
                                    TemplateLift(exercise: "Overhead Squat", role: .complementary, baseWeightLb: 65, estimatedMaxLb: 115)],
                            accessories: [TemplateAccessory(exercise: "Snatch Pull", sets: 3, minReps: 3, maxReps: 5, weightLb: 95, incrementLb: 10),
                                          TemplateAccessory(exercise: "Hanging Knee Raise", sets: 3, minReps: 8, maxReps: 15)]),
                TemplateDay(name: "Clean & Jerk Day",
                            lifts: [TemplateLift(exercise: "Clean and Jerk", role: .main, baseWeightLb: 85, estimatedMaxLb: 145),
                                    TemplateLift(exercise: "Front Squat", role: .complementary, baseWeightLb: 115, estimatedMaxLb: 185)],
                            accessories: [TemplateAccessory(exercise: "Clean Pull", sets: 3, minReps: 3, maxReps: 5, weightLb: 115, incrementLb: 10),
                                          TemplateAccessory(exercise: "Pull-ups", sets: 3, minReps: 5, maxReps: 10)]),
                TemplateDay(name: "Strength Day",
                            lifts: [TemplateLift(exercise: "Back Squat", role: .main, baseWeightLb: 135, estimatedMaxLb: 225),
                                    TemplateLift(exercise: "Overhead Press", role: .complementary, baseWeightLb: 65, estimatedMaxLb: 105)],
                            accessories: [TemplateAccessory(exercise: "Back Extension", sets: 3, minReps: 10, maxReps: 15),
                                          TemplateAccessory(exercise: "Hanging Knee Raise", sets: 3, minReps: 8, maxReps: 15)]),
            ]
        ),
        Template(
            id: "metabolic-conditioning",
            name: "Metabolic Conditioning",
            tagline: "3 days · circuits & engine work · reps climb, loads hold",
            // maintain: mains never add load; accessories double-progress reps,
            // which is the progression that makes sense for engine work.
            focus: .maintain, roundingLb: 5,
            exercises: [
                TemplateExercise(name: "Kettlebell Swing", category: .conditioning, type: .kettlebell, group: "hinge", rest: 60),
                TemplateExercise(name: "Goblet Squat", category: .accessory, type: .kettlebell, group: "squat", rest: 60),
                TemplateExercise(name: "Burpees", category: .conditioning, type: .bodyweight, group: "conditioning", rest: 60),
                TemplateExercise(name: "Push-ups", category: .accessory, type: .bodyweight, group: "press", rest: 60),
                TemplateExercise(name: "Inverted Row", category: .accessory, type: .bodyweight, group: "pull", rest: 60),
                TemplateExercise(name: "Walking Lunges", category: .accessory, type: .bodyweight, group: "squat", isUnilateral: true, rest: 60),
                TemplateExercise(name: "Mountain Climbers", category: .conditioning, type: .bodyweight, group: "conditioning", rest: 45),
                TemplateExercise(name: "Sit-ups", category: .accessory, type: .bodyweight, group: "core", rest: 45),
                TemplateExercise(name: "Box Jumps", category: .conditioning, type: .bodyweight, group: "conditioning", rest: 60),
            ],
            days: [
                TemplateDay(name: "Engine A", lifts: [],
                            accessories: [TemplateAccessory(exercise: "Kettlebell Swing", sets: 5, minReps: 10, maxReps: 20, weightLb: 35),
                                          TemplateAccessory(exercise: "Burpees", sets: 4, minReps: 8, maxReps: 15),
                                          TemplateAccessory(exercise: "Mountain Climbers", sets: 4, minReps: 20, maxReps: 40)]),
                TemplateDay(name: "Engine B", lifts: [],
                            accessories: [TemplateAccessory(exercise: "Push-ups", sets: 4, minReps: 10, maxReps: 25),
                                          TemplateAccessory(exercise: "Inverted Row", sets: 4, minReps: 8, maxReps: 15),
                                          TemplateAccessory(exercise: "Sit-ups", sets: 4, minReps: 15, maxReps: 30)]),
                TemplateDay(name: "Engine C", lifts: [],
                            accessories: [TemplateAccessory(exercise: "Box Jumps", sets: 4, minReps: 8, maxReps: 15),
                                          TemplateAccessory(exercise: "Goblet Squat", sets: 4, minReps: 10, maxReps: 20, weightLb: 35),
                                          TemplateAccessory(exercise: "Walking Lunges", sets: 4, minReps: 12, maxReps: 24)]),
            ]
        ),
    ]

    /// Instantiate a template: ensure its exercises exist in the library
    /// (never overwriting an existing record), then create the program —
    /// active only when it's the first. Mirrors web createProgramFromTemplate.
    @discardableResult
    static func instantiate(_ template: Template, makeActive: Bool, context: ModelContext) -> Program {
        for e in template.exercises where findExercise(named: e.name, context: context) == nil {
            context.insert(Exercise(name: e.name, category: e.category, type: e.type,
                                    movementGroup: e.group, isUnilateral: e.isUnilateral,
                                    defaultRestSeconds: e.rest))
        }
        let program = Program(name: template.name, focus: template.focus, roundingLb: template.roundingLb, isActive: makeActive)
        context.insert(program)
        for (i, d) in template.days.enumerated() {
            let day = ProgramDay(name: d.name, order: i)
            day.program = program
            for l in d.lifts {
                let lift = ProgramLift(exerciseName: l.exercise, role: l.role,
                                       baseWeightLb: l.baseWeightLb, estimatedMaxLb: l.estimatedMaxLb)
                lift.day = day
                day.lifts.append(lift)
                context.insert(lift)
            }
            for a in d.accessories {
                let acc = ProgramAccessory(exerciseName: a.exercise, sets: a.sets, minReps: a.minReps,
                                           maxReps: a.maxReps, currentReps: a.minReps,
                                           weightLb: a.weightLb, incrementLb: a.incrementLb)
                acc.day = day
                day.accessories.append(acc)
                context.insert(acc)
            }
            program.days.append(day)
        }
        return program
    }

    private static func findExercise(named name: String, context: ModelContext) -> Exercise? {
        let n = name // hoist: a Predicate can't read a captured property
        return try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == n })).first
    }
}
