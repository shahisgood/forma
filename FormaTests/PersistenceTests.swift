import Foundation
import SwiftData
import Testing
@testable import Forma

/// Persistence and app-level behaviour, exercised against an in-memory store.
/// Pure calculations are covered by the FormaKit package tests.
@MainActor
@Suite("Persistence")
struct PersistenceTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try Persistence.makeContainer(inMemory: true)
        context = container.mainContext
    }

    @Test func weightEntriesCanBeEditedAndDeleted() throws {
        let entry = WeightEntry(kilograms: 80, measuredAt: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(entry)
        try context.save()

        entry.kilograms = 79.5
        entry.measuredAt = Date(timeIntervalSince1970: 1_699_900_000)
        try context.save()

        var fetched = try context.fetch(FetchDescriptor<WeightEntry>())
        #expect(fetched.count == 1)
        #expect(fetched[0].kilograms == 79.5)
        #expect(fetched[0].createdAt > fetched[0].measuredAt, "measurement time is independent of creation time")

        context.delete(entry)
        try context.save()
        fetched = try context.fetch(FetchDescriptor<WeightEntry>())
        #expect(fetched.isEmpty)
    }

    @Test func storingPoundsDoesNotDrift() throws {
        let unit = WeightUnit.pounds
        let entry = WeightEntry(kilograms: unit.toKilograms(180), measuredAt: Date())
        context.insert(entry)
        try context.save()
        let fetched = try #require(try context.fetch(FetchDescriptor<WeightEntry>()).first)
        #expect(abs(unit.fromKilograms(fetched.kilograms) - 180) < 1e-9)
    }

    @Test func nutritionTotalsFollowEdits() throws {
        let day = DayKey(year: 2026, month: 10, day: 14)
        let entry = FoodEntry(day: day, meal: .lunch, name: "Rice", servings: 1, servingSize: 100, servingUnit: .gram, perServing: Nutrients(calories: 130, protein: 2.7), source: .myFood)
        context.insert(entry)
        try context.save()

        func total() throws -> Nutrients {
            let key = day.string
            let entries = try context.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.dayKey == key }))
            return entries.reduce(Nutrients.zero) { $0 + $1.nutrients }
        }

        #expect(try total().calories == 130)
        entry.servings = 2
        try context.save()
        #expect(try total().calories == 260)

        let copy = entry.duplicate(to: day)
        context.insert(copy)
        try context.save()
        #expect(try total().calories == 520)

        copy.servings = 0.5
        try context.save()
        #expect(entry.servings == 2, "duplicates are independent")
        #expect(try total().calories == 325)

        context.delete(entry)
        try context.save()
        #expect(try total().calories == 65)
    }

    @Test func entriesKeepValuesWhenFoodChanges() throws {
        let food = Food(name: "Oats", servingSize: 40, servingUnit: .gram, nutrients: Nutrients(calories: 150, protein: 5))
        context.insert(food)
        let entry = FoodEntry(day: .today(), meal: .breakfast, name: food.name, servings: 1, servingSize: food.servingSize, servingUnit: food.servingUnit, perServing: food.nutrientsPerServing, source: .myFood, foodID: food.id)
        context.insert(entry)
        try context.save()

        food.calories = 999
        context.delete(food)
        try context.save()
        #expect(entry.nutrients.calories == 150)
    }

    @Test func savedMealsExpandIntoEditableEntries() throws {
        let day = DayKey.today()
        let a = FoodEntry(day: day, meal: .breakfast, name: "Eggs", servings: 2, servingSize: 1, servingUnit: .piece, perServing: Nutrients(calories: 70, protein: 6), source: .myFood)
        let b = FoodEntry(day: day, meal: .breakfast, name: "Toast", servings: 1, servingSize: 1, servingUnit: .slice, perServing: Nutrients(calories: 90, protein: 3), source: .myFood)
        let meal = SavedMeal(name: "Usual breakfast")
        context.insert(meal)
        meal.items.append(SavedMealItem(from: a, position: 0))
        meal.items.append(SavedMealItem(from: b, position: 1))
        try context.save()
        #expect(meal.totals.calories == 230)

        let tomorrow = day.adding(days: 1)
        let expanded = meal.orderedItems.map { $0.makeEntry(day: tomorrow, meal: .breakfast) }
        expanded.forEach(context.insert)
        try context.save()
        #expect(expanded.allSatisfy { $0.source == .savedMeal })

        expanded[0].servings = 3
        try context.save()
        #expect(meal.orderedItems[0].servings == 2, "editing a logged entry doesn't change the saved meal")
    }

    @Test func targetChangesOnSameDayKeepOneRecord() throws {
        let day = DayKey(year: 2026, month: 10, day: 1)
        TargetStore.set(.calories, to: 2400, effectiveFrom: day, in: context)
        TargetStore.set(.calories, to: 2300, effectiveFrom: day, in: context)
        TargetStore.set(.calories, to: 2200, effectiveFrom: day.adding(days: 7), in: context)
        let records = try context.fetch(FetchDescriptor<TargetRecord>())
        #expect(records.count == 2)
        let timeline = TargetStore.timeline(records)
        #expect(timeline.value(.calories, on: day.adding(days: 3)) == 2300)
        #expect(timeline.value(.calories, on: day.adding(days: 8)) == 2200)
    }

    @Test func routineCompletionToggles() throws {
        let routine = Routine(name: "Walk", symbol: "figure.walk", schedule: .daily, link: .none, position: 0)
        context.insert(routine)
        try context.save()
        let day = DayKey.today()
        RoutineActions.toggle(routine, on: day, in: context)
        #expect(routine.manualCompletionDays == [day])
        RoutineActions.toggle(routine, on: day, in: context)
        #expect(routine.manualCompletionDays.isEmpty)
    }

    @Test func catalogSeedingIsIdempotent() throws {
        ExerciseCatalog.seedIfNeeded(in: context)
        ExerciseCatalog.seedIfNeeded(in: context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(exercises.count == ExerciseCatalog.items.count)
        #expect(Set(exercises.compactMap(\.catalogKey)).count == exercises.count)
    }
}

@MainActor
@Suite("Workouts")
struct WorkoutTests {
    let container: ModelContainer
    let context: ModelContext
    let settings: AppSettings

    init() throws {
        container = try Persistence.makeContainer(inMemory: true)
        context = container.mainContext
        settings = AppSettings(defaults: UserDefaults(suiteName: "forma-tests-\(UUID().uuidString)")!)
        settings.update { $0.autoStartRestTimer = false }
        ExerciseCatalog.seedIfNeeded(in: context)
    }

    func makeController() -> WorkoutController {
        WorkoutController(
            context: context,
            settings: settings,
            liveActivities: LiveActivityService(settings: settings),
            notifications: NotificationService(),
            health: HealthService(settings: settings)
        )
    }

    func exercise(_ key: String) throws -> Exercise {
        try #require(try context.fetch(FetchDescriptor<Exercise>()).first { $0.catalogKey == key })
    }

    func makeTemplate() throws -> WorkoutTemplate {
        let template = WorkoutTemplate(name: "Push")
        context.insert(template)
        template.exercises.append(TemplateExercise(exercise: try exercise("bench-press"), position: 0, targetSets: 3, repLow: 5, repHigh: 8))
        template.exercises.append(TemplateExercise(exercise: try exercise("overhead-press"), position: 1, targetSets: 2, repLow: 8, repHigh: 10))
        try context.save()
        return template
    }

    @Test func templateEditsDoNotRewriteSessions() throws {
        let template = try makeTemplate()
        let controller = makeController()
        controller.start(template: template)
        let session = try #require(controller.session)
        #expect(session.orderedExercises.map(\.exerciseName) == ["Bench Press", "Overhead Press"])
        #expect(session.totalSetCount == 5)

        template.name = "Push v2"
        template.exercises.first?.targetSets = 6
        if let last = template.exercises.first(where: { $0.position == 1 }) {
            template.exercises.removeAll { $0.id == last.id }
            context.delete(last)
        }
        try context.save()

        #expect(session.name == "Push")
        #expect(session.exercises.count == 2)
        #expect(session.totalSetCount == 5)

        context.delete(template)
        try context.save()
        #expect(session.exercises.count == 2, "deleting the template keeps the session")
    }

    @Test func suggestionsAreOnlyAppliedWhenCompleting() throws {
        let template = try makeTemplate()
        let controller = makeController()
        controller.start(template: template)
        let bench = try #require(controller.session?.orderedExercises.first)
        let first = try #require(bench.orderedSets.first)

        // No history: nothing to complete yet.
        #expect(controller.toggleCompletion(first, in: bench) == .missingValues)
        #expect(first.isCompleted == false)

        first.weightKg = 100
        first.reps = 5
        #expect(controller.toggleCompletion(first, in: bench) == .completed)
        #expect(first.isCompleted)

        // The next set suggests 100 × 5 but stays incomplete until tapped.
        let second = bench.orderedSets[1]
        #expect(second.isCompleted == false)
        #expect(second.weightKg == nil)
        #expect(controller.suggestion(for: second, in: bench) == SetSuggestion(weightKg: 100, reps: 5))
        #expect(controller.toggleCompletion(second, in: bench) == .completed)
        #expect(second.weightKg == 100)
        #expect(second.reps == 5)
    }

    @Test func finishDropsUncheckedSetsAndSurvivesRestart() throws {
        let template = try makeTemplate()
        let controller = makeController()
        controller.start(template: template)
        let session = try #require(controller.session)
        let bench = try #require(session.orderedExercises.first)
        let set = bench.orderedSets[0]
        set.weightKg = 80
        set.reps = 8
        controller.toggleCompletion(set, in: bench)

        // Simulate the app being terminated and relaunched.
        let relaunched = makeController()
        relaunched.restore()
        #expect(relaunched.session?.id == session.id)
        #expect(relaunched.session?.completedSetCount == 1)

        #expect(relaunched.finish())
        let finished = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.endedAt != nil }))
        #expect(finished.count == 1)
        #expect(finished[0].totalSetCount == 1, "unchecked sets are removed")
        #expect(finished[0].exercises.count == 1, "exercises without completed sets are removed")
        #expect(relaunched.session == nil)
    }

    @Test func finishWithNothingCompletedKeepsWorkout() throws {
        let controller = makeController()
        controller.start(template: try makeTemplate())
        #expect(controller.finish() == false)
        #expect(controller.session?.totalSetCount == 5, "nothing is deleted when finishing is refused")
    }

    @Test func discardDeletesEverything() throws {
        let controller = makeController()
        controller.start(template: try makeTemplate())
        controller.discard()
        #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<WorkoutSet>()).isEmpty)
        #expect(controller.session == nil)
    }

    @Test func historyEditsFeedProgression() throws {
        let controller = makeController()
        controller.start(template: try makeTemplate())
        let bench = try #require(controller.session?.orderedExercises.first)
        let set = bench.orderedSets[0]
        set.weightKg = 100
        set.reps = 5
        controller.toggleCompletion(set, in: bench)
        controller.finish()

        let exercise = try exercise("bench-press")
        #expect(ExerciseProgression.summaries(exercise.completedSetRecords()).last?.topWeight == 100)

        set.weightKg = 105
        try context.save()
        #expect(ExerciseProgression.summaries(exercise.completedSetRecords()).last?.topWeight == 105)
    }

    @Test func repeatingAWorkoutCopiesStructureOnly() throws {
        let controller = makeController()
        controller.start(template: try makeTemplate())
        let bench = try #require(controller.session?.orderedExercises.first)
        let set = bench.orderedSets[0]
        set.weightKg = 90
        set.reps = 6
        controller.toggleCompletion(set, in: bench)
        controller.finish()
        let past = try #require(try context.fetch(FetchDescriptor<WorkoutSession>()).first)

        controller.start(repeating: past)
        let repeated = try #require(controller.session)
        #expect(repeated.id != past.id)
        #expect(repeated.completedSetCount == 0)
        #expect(repeated.orderedExercises.first?.orderedSets.first?.weightKg == nil)
    }
}
