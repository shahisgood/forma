import Foundation
import SwiftData
import FormaKit

/// Exports all locally stored records as CSV files.
@MainActor
enum DataExporter {
    /// Writes one CSV per record type into a fresh temporary folder and returns the file URLs.
    static func export(context: ModelContext) throws -> [URL] {
        let stamp = Date().formatted(.iso8601.year().month().day())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Forma Export \(stamp)", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var files: [URL] = []
        func write(_ name: String, _ table: CSVTable) throws {
            let url = folder.appendingPathComponent(name)
            try table.render().write(to: url, atomically: true, encoding: .utf8)
            files.append(url)
        }

        let weights = try context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.measuredAt)]))
        try write("weight.csv", CSVTable(
            header: ["measured_at", "weight_kg", "note", "source", "source_name", "created_at"],
            rows: weights.map {
                [CSVTable.timestamp($0.measuredAt), CSVTable.number($0.kilograms, fractionDigits: 3), $0.note, $0.sourceRaw, $0.healthSourceName ?? "", CSVTable.timestamp($0.createdAt)]
            }
        ))

        let food = try context.fetch(FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.dayKey), SortDescriptor(\.loggedAt)]))
        try write("food-diary.csv", CSVTable(
            header: ["day", "meal", "name", "servings", "amount", "amount_unit", "calories", "protein_g", "carbs_g", "fat_g", "source", "eaten_at", "logged_at"],
            rows: food.map { entry in
                let n = entry.nutrients
                return [
                    entry.dayKey, entry.mealRaw, entry.name, CSVTable.number(entry.servings, fractionDigits: 3),
                    CSVTable.number(entry.amount), entry.amountUnitRaw ?? "",
                    CSVTable.number(n.calories, fractionDigits: 1), CSVTable.number(n.protein, fractionDigits: 1),
                    CSVTable.number(n.carbs, fractionDigits: 1), CSVTable.number(n.fat, fractionDigits: 1),
                    entry.sourceRaw, CSVTable.timestamp(entry.consumedAt), CSVTable.timestamp(entry.loggedAt)
                ]
            }
        ))

        let foods = try context.fetch(FetchDescriptor<Food>(sortBy: [SortDescriptor(\.name)]))
        try write("foods.csv", CSVTable(
            header: ["name", "brand", "serving_size", "serving_unit", "calories", "protein_g", "carbs_g", "fat_g", "favorite"],
            rows: foods.map {
                [$0.name, $0.brand, CSVTable.number($0.servingSize), $0.servingUnitRaw, CSVTable.number($0.calories, fractionDigits: 1),
                 CSVTable.number($0.protein, fractionDigits: 1), CSVTable.number($0.carbs, fractionDigits: 1), CSVTable.number($0.fat, fractionDigits: 1),
                 $0.isFavorite ? "yes" : "no"]
            }
        ))

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt)]))
        var setRows: [[String]] = []
        for session in sessions where session.endedAt != nil {
            for entry in session.orderedExercises {
                for (index, set) in entry.orderedSets.enumerated() {
                    setRows.append([
                        CSVTable.timestamp(session.startedAt), session.name, entry.exerciseName, String(index + 1), set.kindRaw,
                        CSVTable.number(set.weightKg, fractionDigits: 2), set.reps.map(String.init) ?? "",
                        CSVTable.number(set.durationSeconds, fractionDigits: 0), CSVTable.number(set.distanceMeters, fractionDigits: 1),
                        CSVTable.number(set.rpe, fractionDigits: 1), set.isCompleted ? "yes" : "no"
                    ])
                }
            }
        }
        try write("workout-sets.csv", CSVTable(
            header: ["session_started_at", "workout", "exercise", "set", "kind", "weight_kg", "reps", "duration_s", "distance_m", "rpe", "completed"],
            rows: setRows
        ))

        try write("workouts.csv", CSVTable(
            header: ["started_at", "ended_at", "name", "notes", "completed_sets"],
            rows: sessions.filter { $0.endedAt != nil }.map {
                [CSVTable.timestamp($0.startedAt), CSVTable.timestamp($0.endedAt), $0.name, $0.notes, String($0.completedSetCount)]
            }
        ))

        let routines = try context.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.position)]))
        var routineRows: [[String]] = []
        for routine in routines {
            for completion in routine.completions.sorted(by: { $0.dayKey < $1.dayKey }) {
                routineRows.append([routine.name, completion.dayKey, CSVTable.timestamp(completion.completedAt)])
            }
        }
        try write("routine-check-ins.csv", CSVTable(header: ["routine", "day", "checked_at"], rows: routineRows))

        let steps = try context.fetch(FetchDescriptor<ManualStepEntry>(sortBy: [SortDescriptor(\.dayKey)]))
        try write("manual-steps.csv", CSVTable(
            header: ["day", "steps", "note"],
            rows: steps.map { [$0.dayKey, String($0.steps), $0.note] }
        ))

        let targets = try context.fetch(FetchDescriptor<TargetRecord>(sortBy: [SortDescriptor(\.effectiveDayKey)]))
        try write("targets.csv", CSVTable(
            header: ["metric", "value", "effective_from", "changed_at"],
            rows: targets.map { [$0.metricRaw, CSVTable.number($0.value, fractionDigits: 1), $0.effectiveDayKey, CSVTable.timestamp($0.createdAt)] }
        ))

        return files
    }
}

/// Permanently removes everything Forma stores on this device.
@MainActor
enum DataEraser {
    static func eraseAll(context: ModelContext, settings: AppSettings, notifications: NotificationService, liveActivities: LiveActivityService, health: HealthService) async {
        try? context.delete(model: WorkoutSet.self)
        try? context.delete(model: SessionExercise.self)
        try? context.delete(model: WorkoutSession.self)
        try? context.delete(model: TemplateExercise.self)
        try? context.delete(model: WorkoutTemplate.self)
        try? context.delete(model: Exercise.self)
        try? context.delete(model: FoodEntry.self)
        try? context.delete(model: SavedMealItem.self)
        try? context.delete(model: SavedMeal.self)
        try? context.delete(model: Food.self)
        try? context.delete(model: WeightEntry.self)
        try? context.delete(model: TargetRecord.self)
        try? context.delete(model: ManualStepEntry.self)
        try? context.delete(model: RoutineCompletion.self)
        try? context.delete(model: Routine.self)
        try? context.delete(model: WeeklyReviewNote.self)
        try? context.save()

        RestTimerStore.save(nil)
        notifications.cancelRestAlert()
        await notifications.removeAllReminders()
        await liveActivities.endAll()
        health.disconnect()
        health.resetImportState()
        settings.reset()
        ExerciseCatalog.seedIfNeeded(in: context)
    }
}
