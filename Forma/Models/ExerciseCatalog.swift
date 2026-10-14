import Foundation
import SwiftData
import FormaKit

/// Built-in exercise catalog. Entries carry a stable `catalogKey` so the catalog
/// can grow in later versions without duplicating exercises people already have.
enum ExerciseCatalog {
    struct Item {
        let key: String
        let name: String
        let category: ExerciseCategory
        let equipment: Equipment
        let tracking: ExerciseTrackingType
    }

    static let items: [Item] = [
        // Chest
        Item(key: "bench-press", name: "Bench Press", category: .chest, equipment: .barbell, tracking: .weightReps),
        Item(key: "incline-bench-press", name: "Incline Bench Press", category: .chest, equipment: .barbell, tracking: .weightReps),
        Item(key: "db-bench-press", name: "Dumbbell Bench Press", category: .chest, equipment: .dumbbell, tracking: .weightReps),
        Item(key: "incline-db-press", name: "Incline Dumbbell Press", category: .chest, equipment: .dumbbell, tracking: .weightReps),
        Item(key: "chest-fly-cable", name: "Cable Fly", category: .chest, equipment: .cable, tracking: .weightReps),
        Item(key: "machine-chest-press", name: "Machine Chest Press", category: .chest, equipment: .machine, tracking: .weightReps),
        Item(key: "push-up", name: "Push-up", category: .chest, equipment: .bodyweight, tracking: .bodyweightReps),
        Item(key: "dip", name: "Dip", category: .chest, equipment: .bodyweight, tracking: .bodyweightReps),
        Item(key: "db-pullover", name: "Dumbbell Pullover", category: .chest, equipment: .dumbbell, tracking: .weightReps),

        // Back
        Item(key: "deadlift", name: "Deadlift", category: .back, equipment: .barbell, tracking: .weightReps),
        Item(key: "barbell-row", name: "Barbell Row", category: .back, equipment: .barbell, tracking: .weightReps),
        Item(key: "db-row", name: "One-Arm Dumbbell Row", category: .back, equipment: .dumbbell, tracking: .weightReps),
        Item(key: "seated-cable-row", name: "Seated Cable Row", category: .back, equipment: .cable, tracking: .weightReps),
        Item(key: "lat-pulldown", name: "Lat Pulldown", category: .back, equipment: .cable, tracking: .weightReps),
        Item(key: "straight-arm-pulldown", name: "Straight-Arm Pulldown", category: .back, equipment: .cable, tracking: .weightReps),
        Item(key: "pull-up", name: "Pull-up", category: .back, equipment: .bodyweight, tracking: .bodyweightReps),
        Item(key: "chin-up", name: "Chin-up", category: .back, equipment: .bodyweight, tracking: .bodyweightReps),
        Item(key: "assisted-pull-up", name: "Assisted Pull-up", category: .back, equipment: .machine, tracking: .assistedReps),
        Item(key: "machine-pullover", name: "Machine Pullover", category: .back, equipment: .machine, tracking: .weightReps),
        Item(key: "t-bar-row", name: "T-Bar Row", category: .back, equipment: .barbell, tracking: .weightReps),

        // Legs
        Item(key: "back-squat", name: "Back Squat", category: .legs, equipment: .barbell, tracking: .weightReps),
        Item(key: "front-squat", name: "Front Squat", category: .legs, equipment: .barbell, tracking: .weightReps),
        Item(key: "romanian-deadlift", name: "Romanian Deadlift", category: .legs, equipment: .barbell, tracking: .weightReps),
        Item(key: "leg-press", name: "Leg Press", category: .legs, equipment: .machine, tracking: .weightReps),
        Item(key: "bulgarian-split-squat", name: "Bulgarian Split Squat", category: .legs, equipment: .dumbbell, tracking: .weightReps),
        Item(key: "walking-lunge", name: "Walking Lunge", category: .legs, equipment: .dumbbell, tracking: .weightReps),
        Item(key: "leg-extension", name: "Leg Extension", category: .legs, equipment: .machine, tracking: .weightReps),
        Item(key: "leg-curl", name: "Leg Curl", category: .legs, equipment: .machine, tracking: .weightReps),
        Item(key: "hip-thrust", name: "Hip Thrust", category: .legs, equipment: .barbell, tracking: .weightReps),
        Item(key: "calf-raise", name: "Standing Calf Raise", category: .legs, equipment: .machine, tracking: .weightReps),
        Item(key: "goblet-squat", name: "Goblet Squat", category: .legs, equipment: .kettlebell, tracking: .weightReps),

        // Shoulders
        Item(key: "overhead-press", name: "Overhead Press", category: .shoulders, equipment: .barbell, tracking: .weightReps),
        Item(key: "db-shoulder-press", name: "Dumbbell Shoulder Press", category: .shoulders, equipment: .dumbbell, tracking: .weightReps),
        Item(key: "lateral-raise", name: "Lateral Raise", category: .shoulders, equipment: .dumbbell, tracking: .weightReps),
        Item(key: "cable-lateral-raise", name: "Cable Lateral Raise", category: .shoulders, equipment: .cable, tracking: .weightReps),
        Item(key: "rear-delt-fly", name: "Rear Delt Fly", category: .shoulders, equipment: .dumbbell, tracking: .weightReps),
        Item(key: "face-pull", name: "Face Pull", category: .shoulders, equipment: .cable, tracking: .weightReps),

        // Arms
        Item(key: "barbell-curl", name: "Barbell Curl", category: .arms, equipment: .barbell, tracking: .weightReps),
        Item(key: "db-curl", name: "Dumbbell Curl", category: .arms, equipment: .dumbbell, tracking: .weightReps),
        Item(key: "hammer-curl", name: "Hammer Curl", category: .arms, equipment: .dumbbell, tracking: .weightReps),
        Item(key: "triceps-pushdown", name: "Triceps Pushdown", category: .arms, equipment: .cable, tracking: .weightReps),
        Item(key: "overhead-triceps-extension", name: "Overhead Triceps Extension", category: .arms, equipment: .cable, tracking: .weightReps),
        Item(key: "skull-crusher", name: "Skull Crusher", category: .arms, equipment: .barbell, tracking: .weightReps),

        // Core
        Item(key: "plank", name: "Plank", category: .core, equipment: .bodyweight, tracking: .duration),
        Item(key: "hanging-leg-raise", name: "Hanging Leg Raise", category: .core, equipment: .bodyweight, tracking: .bodyweightReps),
        Item(key: "cable-crunch", name: "Cable Crunch", category: .core, equipment: .cable, tracking: .weightReps),
        Item(key: "ab-wheel", name: "Ab Wheel Rollout", category: .core, equipment: .other, tracking: .bodyweightReps),

        // Full body
        Item(key: "kettlebell-swing", name: "Kettlebell Swing", category: .fullBody, equipment: .kettlebell, tracking: .weightReps),
        Item(key: "farmers-carry", name: "Farmer's Carry", category: .fullBody, equipment: .dumbbell, tracking: .distanceDuration),

        // Cardio
        Item(key: "treadmill-run", name: "Treadmill Run", category: .cardio, equipment: .machine, tracking: .distanceDuration),
        Item(key: "rowing-machine", name: "Rowing Machine", category: .cardio, equipment: .machine, tracking: .distanceDuration),
        Item(key: "stationary-bike", name: "Stationary Bike", category: .cardio, equipment: .machine, tracking: .duration),
        Item(key: "jump-rope", name: "Jump Rope", category: .cardio, equipment: .other, tracking: .duration)
    ]

    /// Inserts any catalog exercises that are not yet in the store. Safe to call on every launch.
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let keys = Set(existing.compactMap(\.catalogKey))
        var inserted = false
        for item in items where !keys.contains(item.key) {
            context.insert(Exercise(
                name: item.name,
                category: item.category,
                equipment: item.equipment,
                trackingType: item.tracking,
                isCustom: false,
                catalogKey: item.key
            ))
            inserted = true
        }
        if inserted { try? context.save() }
    }
}
