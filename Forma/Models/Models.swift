import Foundation
import SwiftData
import FormaKit

// Persistence notes
// -----------------
// * Masses are stored in kilograms, energy in kcal, macros in grams.
// * Enums are stored as raw strings with typed computed accessors, which keeps
//   predicates simple and makes adding cases a non-breaking change.
// * Diary-style records store a `dayKey` ("yyyy-MM-dd") chosen by the person,
//   separate from the instant they were created. Instants (`measuredAt`,
//   `startedAt`) are stored as absolute dates.
// * Completed sessions and diary entries snapshot names and nutrition values, so
//   editing a template or a food never rewrites history.
// * Relationship arrays are unordered in SwiftData; every ordered child has a
//   `position` used for sorting.

// MARK: - Body weight

@Model
final class WeightEntry {
    var id: UUID = UUID()
    /// When the weight was measured. May be backdated.
    var measuredAt: Date = Date()
    /// When the entry was created in Forma (or imported).
    var createdAt: Date = Date()
    var updatedAt: Date?
    var kilograms: Double = 0
    var note: String = ""
    var sourceRaw: String = WeightSource.manual.rawValue
    /// UUID of the Apple Health sample this entry was imported from.
    var healthSampleUUID: String?
    /// Name of the app or device that recorded the imported sample.
    var healthSourceName: String?
    /// UUID of the sample Forma wrote to Apple Health for this entry, if any.
    var writtenHealthSampleUUID: String?

    init(kilograms: Double, measuredAt: Date, note: String = "", source: WeightSource = .manual) {
        self.id = UUID()
        self.kilograms = kilograms
        self.measuredAt = measuredAt
        self.createdAt = Date()
        self.note = note
        self.sourceRaw = source.rawValue
    }

    var source: WeightSource {
        get { WeightSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var isImported: Bool { source == .appleHealth }
}

enum WeightSource: String, Codable {
    case manual
    case appleHealth
}

// MARK: - Targets

/// History of target changes (calories, macros, steps). See `TargetTimeline`.
@Model
final class TargetRecord {
    var id: UUID = UUID()
    var metricRaw: String = TargetMetric.calories.rawValue
    var value: Double?
    var effectiveDayKey: String = ""
    var createdAt: Date = Date()

    init(metric: TargetMetric, value: Double?, effectiveFrom: DayKey) {
        self.id = UUID()
        self.metricRaw = metric.rawValue
        self.value = value
        self.effectiveDayKey = effectiveFrom.string
        self.createdAt = Date()
    }

    var metric: TargetMetric { TargetMetric(rawValue: metricRaw) ?? .calories }

    var change: TargetChange? {
        guard let day = DayKey(string: effectiveDayKey) else { return nil }
        return TargetChange(metric: metric, value: value, effectiveFrom: day, createdAt: createdAt)
    }
}

// MARK: - Nutrition

@Model
final class Food {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String = ""
    /// Size of one serving in `servingUnit` (e.g. 170 g, 1 slice).
    var servingSize: Double = 1
    var servingUnitRaw: String = ServingUnit.serving.rawValue
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double?
    var fat: Double?
    var isFavorite: Bool = false
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var lastUsedAt: Date?
    var useCount: Int = 0
    var originRaw: String = NutritionSource.myFood.rawValue

    init(name: String, brand: String = "", servingSize: Double, servingUnit: ServingUnit, nutrients: Nutrients) {
        self.id = UUID()
        self.name = name
        self.brand = brand
        self.servingSize = servingSize
        self.servingUnitRaw = servingUnit.rawValue
        self.calories = nutrients.calories
        self.protein = nutrients.protein
        self.carbs = nutrients.carbs
        self.fat = nutrients.fat
        self.createdAt = Date()
    }

    var servingUnit: ServingUnit {
        get { ServingUnit(rawValue: servingUnitRaw) ?? .serving }
        set { servingUnitRaw = newValue.rawValue }
    }

    var nutrientsPerServing: Nutrients {
        get { Nutrients(calories: calories, protein: protein, carbs: carbs, fat: fat) }
        set {
            calories = newValue.calories
            protein = newValue.protein
            carbs = newValue.carbs
            fat = newValue.fat
        }
    }

    var servingDescription: String {
        if servingUnit == .serving {
            return servingSize == 1 ? "1 serving" : "\(Format.servings(servingSize)) servings"
        }
        return "\(Format.servings(servingSize)) \(servingUnit.label)"
    }
}

/// One line in the food diary.
@Model
final class FoodEntry {
    var id: UUID = UUID()
    /// The diary day this belongs to ("yyyy-MM-dd").
    var dayKey: String = ""
    var mealRaw: String = Meal.snacks.rawValue
    var name: String = ""
    var detail: String = ""
    /// Multiplier applied to the per-serving values.
    var servings: Double = 1
    /// What was entered, for display ("150 g"). `nil` means servings were entered directly.
    var amount: Double?
    var amountUnitRaw: String?
    var servingSize: Double = 1
    var servingUnitRaw: String = ServingUnit.serving.rawValue
    var caloriesPerServing: Double = 0
    var proteinPerServing: Double = 0
    var carbsPerServing: Double?
    var fatPerServing: Double?
    var sourceRaw: String = NutritionSource.myFood.rawValue
    var foodID: UUID?
    /// Optional time the food was eaten. Independent of `loggedAt`.
    var consumedAt: Date?
    /// When the entry was created.
    var loggedAt: Date = Date()
    var updatedAt: Date?
    var note: String = ""

    init(
        day: DayKey,
        meal: Meal,
        name: String,
        detail: String = "",
        servings: Double,
        servingSize: Double,
        servingUnit: ServingUnit,
        perServing: Nutrients,
        source: NutritionSource,
        foodID: UUID? = nil
    ) {
        self.id = UUID()
        self.dayKey = day.string
        self.mealRaw = meal.rawValue
        self.name = name
        self.detail = detail
        self.servings = servings
        self.servingSize = servingSize
        self.servingUnitRaw = servingUnit.rawValue
        self.caloriesPerServing = perServing.calories
        self.proteinPerServing = perServing.protein
        self.carbsPerServing = perServing.carbs
        self.fatPerServing = perServing.fat
        self.sourceRaw = source.rawValue
        self.foodID = foodID
        self.loggedAt = Date()
    }

    var meal: Meal {
        get { Meal(rawValue: mealRaw) ?? .snacks }
        set { mealRaw = newValue.rawValue }
    }

    var day: DayKey {
        get { DayKey(string: dayKey) ?? DayKey.today() }
        set { dayKey = newValue.string }
    }

    var source: NutritionSource {
        get { NutritionSource(rawValue: sourceRaw) ?? .myFood }
        set { sourceRaw = newValue.rawValue }
    }

    var servingUnit: ServingUnit { ServingUnit(rawValue: servingUnitRaw) ?? .serving }
    var amountUnit: ServingUnit? { amountUnitRaw.flatMap(ServingUnit.init(rawValue:)) }

    var perServing: Nutrients {
        get { Nutrients(calories: caloriesPerServing, protein: proteinPerServing, carbs: carbsPerServing, fat: fatPerServing) }
        set {
            caloriesPerServing = newValue.calories
            proteinPerServing = newValue.protein
            carbsPerServing = newValue.carbs
            fatPerServing = newValue.fat
        }
    }

    var nutrients: Nutrients { perServing.scaled(by: servings) }

    /// "1.5 servings" or "150 g".
    var quantityDescription: String {
        if let amount, let unit = amountUnit, unit != .serving {
            return "\(Format.servings(amount)) \(unit.label)"
        }
        if source == .quickEstimate && servings == 1 { return "Estimate" }
        return servings == 1 ? "1 serving" : "\(Format.servings(servings)) servings"
    }

    /// Creates an independent copy on another day/meal.
    func duplicate(to day: DayKey, meal: Meal? = nil, source: NutritionSource? = nil) -> FoodEntry {
        let copy = FoodEntry(
            day: day,
            meal: meal ?? self.meal,
            name: name,
            detail: detail,
            servings: servings,
            servingSize: servingSize,
            servingUnit: servingUnit,
            perServing: perServing,
            source: source ?? self.source,
            foodID: foodID
        )
        copy.amount = amount
        copy.amountUnitRaw = amountUnitRaw
        copy.note = note
        return copy
    }
}

/// A reusable group of foods. Logging it creates ordinary, editable diary entries.
@Model
final class SavedMeal {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var lastUsedAt: Date?
    var useCount: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \SavedMealItem.meal)
    var items: [SavedMealItem] = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }

    var orderedItems: [SavedMealItem] { items.sorted { $0.position < $1.position } }

    var totals: Nutrients { items.reduce(Nutrients.zero) { $0 + $1.nutrients } }
}

@Model
final class SavedMealItem {
    var id: UUID = UUID()
    var position: Int = 0
    var name: String = ""
    var detail: String = ""
    var servings: Double = 1
    var amount: Double?
    var amountUnitRaw: String?
    var servingSize: Double = 1
    var servingUnitRaw: String = ServingUnit.serving.rawValue
    var caloriesPerServing: Double = 0
    var proteinPerServing: Double = 0
    var carbsPerServing: Double?
    var fatPerServing: Double?
    var foodID: UUID?
    var meal: SavedMeal?

    init(from entry: FoodEntry, position: Int) {
        self.id = UUID()
        self.position = position
        self.name = entry.name
        self.detail = entry.detail
        self.servings = entry.servings
        self.amount = entry.amount
        self.amountUnitRaw = entry.amountUnitRaw
        self.servingSize = entry.servingSize
        self.servingUnitRaw = entry.servingUnitRaw
        self.caloriesPerServing = entry.caloriesPerServing
        self.proteinPerServing = entry.proteinPerServing
        self.carbsPerServing = entry.carbsPerServing
        self.fatPerServing = entry.fatPerServing
        self.foodID = entry.foodID
    }

    var perServing: Nutrients {
        Nutrients(calories: caloriesPerServing, protein: proteinPerServing, carbs: carbsPerServing, fat: fatPerServing)
    }

    var nutrients: Nutrients { perServing.scaled(by: servings) }

    func makeEntry(day: DayKey, meal: Meal) -> FoodEntry {
        let entry = FoodEntry(
            day: day,
            meal: meal,
            name: name,
            detail: detail,
            servings: servings,
            servingSize: servingSize,
            servingUnit: ServingUnit(rawValue: servingUnitRaw) ?? .serving,
            perServing: perServing,
            source: .savedMeal,
            foodID: foodID
        )
        entry.amount = amount
        entry.amountUnitRaw = amountUnitRaw
        return entry
    }
}

// MARK: - Training

@Model
final class Exercise {
    var id: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = ExerciseCategory.fullBody.rawValue
    var equipmentRaw: String = Equipment.other.rawValue
    var trackingTypeRaw: String = ExerciseTrackingType.weightReps.rawValue
    var isCustom: Bool = false
    /// Stable identifier for exercises from the built-in catalog.
    var catalogKey: String?
    var notes: String = ""
    var isArchived: Bool = false
    var createdAt: Date = Date()
    @Relationship(deleteRule: .nullify, inverse: \SessionExercise.exercise)
    var sessionEntries: [SessionExercise] = []
    @Relationship(deleteRule: .nullify, inverse: \TemplateExercise.exercise)
    var templateEntries: [TemplateExercise] = []

    init(name: String, category: ExerciseCategory, equipment: Equipment, trackingType: ExerciseTrackingType, isCustom: Bool, catalogKey: String? = nil) {
        self.id = UUID()
        self.name = name
        self.categoryRaw = category.rawValue
        self.equipmentRaw = equipment.rawValue
        self.trackingTypeRaw = trackingType.rawValue
        self.isCustom = isCustom
        self.catalogKey = catalogKey
        self.createdAt = Date()
    }

    var category: ExerciseCategory {
        get { ExerciseCategory(rawValue: categoryRaw) ?? .fullBody }
        set { categoryRaw = newValue.rawValue }
    }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .other }
        set { equipmentRaw = newValue.rawValue }
    }

    var trackingType: ExerciseTrackingType {
        get { ExerciseTrackingType(rawValue: trackingTypeRaw) ?? .weightReps }
        set { trackingTypeRaw = newValue.rawValue }
    }

    /// Completed sets from finished sessions, flattened for analysis.
    func completedSetRecords(excludingSession excluded: UUID? = nil) -> [SetRecord] {
        sessionEntries.flatMap { entry -> [SetRecord] in
            guard let session = entry.session, session.endedAt != nil, session.id != excluded else { return [] }
            return entry.completedRecords(sessionID: session.id, fallbackDate: session.startedAt)
        }
    }

    /// Most recent finished session entry for this exercise, excluding `excluded`.
    func lastSessionEntry(excludingSession excluded: UUID? = nil) -> SessionExercise? {
        sessionEntries
            .filter { entry in
                guard let s = entry.session, s.endedAt != nil, s.id != excluded else { return false }
                return entry.sets.contains { $0.isCompleted }
            }
            .max { ($0.session?.startedAt ?? .distantPast) < ($1.session?.startedAt ?? .distantPast) }
    }
}

@Model
final class WorkoutTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    var position: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastUsedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.template)
    var exercises: [TemplateExercise] = []

    init(name: String, position: Int = 0) {
        self.id = UUID()
        self.name = name
        self.position = position
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var orderedExercises: [TemplateExercise] { exercises.sorted { $0.position < $1.position } }

    var totalSets: Int { exercises.reduce(0) { $0 + $1.targetSets + $1.warmupSets } }
}

@Model
final class TemplateExercise {
    var id: UUID = UUID()
    var position: Int = 0
    var exercise: Exercise?
    var targetSets: Int = 3
    var warmupSets: Int = 0
    var repLow: Int?
    var repHigh: Int?
    var restSeconds: Int?
    var notes: String = ""
    var template: WorkoutTemplate?

    init(exercise: Exercise, position: Int, targetSets: Int = 3, repLow: Int? = 8, repHigh: Int? = 12) {
        self.id = UUID()
        self.exercise = exercise
        self.position = position
        self.targetSets = targetSets
        self.repLow = repLow
        self.repHigh = repHigh
    }

    var repRangeDescription: String? {
        switch (repLow, repHigh) {
        case let (lo?, hi?) where lo != hi: return "\(lo)–\(hi) reps"
        case let (lo?, _): return "\(lo) reps"
        case let (nil, hi?): return "\(hi) reps"
        default: return nil
        }
    }
}

@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var name: String = ""
    /// The template this session was started from. A reference only; history never follows template edits.
    var templateID: UUID?
    var startedAt: Date = Date()
    /// `nil` while the workout is in progress.
    var endedAt: Date?
    var notes: String = ""
    var healthWorkoutUUID: String?
    @Relationship(deleteRule: .cascade, inverse: \SessionExercise.session)
    var exercises: [SessionExercise] = []

    init(name: String, templateID: UUID?, startedAt: Date = Date()) {
        self.id = UUID()
        self.name = name
        self.templateID = templateID
        self.startedAt = startedAt
    }

    var isInProgress: Bool { endedAt == nil }

    var orderedExercises: [SessionExercise] { exercises.sorted { $0.position < $1.position } }

    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }

    var completedSetCount: Int { exercises.reduce(0) { $0 + $1.sets.filter(\.isCompleted).count } }
    var totalSetCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    var day: DayKey { DayKey(startedAt) }
}

@Model
final class SessionExercise {
    var id: UUID = UUID()
    var position: Int = 0
    var exercise: Exercise?
    /// Snapshot so history survives renaming or deleting the exercise.
    var exerciseName: String = ""
    var trackingTypeRaw: String = ExerciseTrackingType.weightReps.rawValue
    var notes: String = ""
    var restSeconds: Int?
    var targetRepLow: Int?
    var targetRepHigh: Int?
    var session: WorkoutSession?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.sessionExercise)
    var sets: [WorkoutSet] = []

    init(exercise: Exercise, position: Int) {
        self.id = UUID()
        self.exercise = exercise
        self.exerciseName = exercise.name
        self.trackingTypeRaw = exercise.trackingTypeRaw
        self.position = position
    }

    var trackingType: ExerciseTrackingType { ExerciseTrackingType(rawValue: trackingTypeRaw) ?? .weightReps }

    var orderedSets: [WorkoutSet] { sets.sorted { $0.position < $1.position } }

    func completedRecords(sessionID: UUID, fallbackDate: Date) -> [SetRecord] {
        orderedSets.filter(\.isCompleted).map { $0.record(sessionID: sessionID, fallbackDate: fallbackDate) }
    }

    var nextPosition: Int { (sets.map(\.position).max() ?? -1) + 1 }
}

@Model
final class WorkoutSet {
    var id: UUID = UUID()
    var position: Int = 0
    var kindRaw: String = SetKind.working.rawValue
    var weightKg: Double?
    var reps: Int?
    var durationSeconds: Double?
    var distanceMeters: Double?
    /// Rate of perceived exertion (1–10), optional.
    var rpe: Double?
    var isCompleted: Bool = false
    var completedAt: Date?
    var sessionExercise: SessionExercise?

    init(position: Int, kind: SetKind) {
        self.id = UUID()
        self.position = position
        self.kindRaw = kind.rawValue
    }

    var kind: SetKind {
        get { SetKind(rawValue: kindRaw) ?? .working }
        set { kindRaw = newValue.rawValue }
    }

    var hasValues: Bool { weightKg != nil || reps != nil || durationSeconds != nil || distanceMeters != nil }

    func record(sessionID: UUID, fallbackDate: Date) -> SetRecord {
        SetRecord(
            id: id,
            sessionID: sessionID,
            date: completedAt ?? fallbackDate,
            kind: kind,
            weightKg: weightKg,
            reps: reps,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters
        )
    }
}

// MARK: - Steps

/// A manually entered step count. Only used for days without Apple Health data.
@Model
final class ManualStepEntry {
    var id: UUID = UUID()
    var dayKey: String = ""
    var steps: Int = 0
    var note: String = ""
    var createdAt: Date = Date()

    init(day: DayKey, steps: Int, note: String = "") {
        self.id = UUID()
        self.dayKey = day.string
        self.steps = steps
        self.note = note
        self.createdAt = Date()
    }

    var day: DayKey { DayKey(string: dayKey) ?? DayKey.today() }
}

// MARK: - Routines

@Model
final class Routine {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "checkmark.circle"
    var scheduleKindRaw: String = RoutineSchedule.Kind.daily.rawValue
    var weekdays: [Int] = []
    var timesPerWeek: Int = 3
    var linkRaw: String = RoutineLink.none.rawValue
    var reminderEnabled: Bool = false
    var reminderHour: Int = 9
    var reminderMinute: Int = 0
    var position: Int = 0
    var createdAt: Date = Date()
    var createdDayKey: String = ""
    var archivedDayKey: String?
    @Relationship(deleteRule: .cascade, inverse: \RoutineCompletion.routine)
    var completions: [RoutineCompletion] = []

    init(name: String, symbol: String, schedule: RoutineSchedule, link: RoutineLink, position: Int) {
        self.id = UUID()
        self.name = name
        self.symbol = symbol
        self.scheduleKindRaw = schedule.kind.rawValue
        self.weekdays = Array(schedule.weekdays).sorted()
        self.timesPerWeek = schedule.timesPerWeek
        self.linkRaw = link.rawValue
        self.position = position
        self.createdAt = Date()
        self.createdDayKey = DayKey.today().string
    }

    var schedule: RoutineSchedule {
        get {
            RoutineSchedule(
                kind: RoutineSchedule.Kind(rawValue: scheduleKindRaw) ?? .daily,
                weekdays: Set(weekdays),
                timesPerWeek: timesPerWeek
            )
        }
        set {
            scheduleKindRaw = newValue.kind.rawValue
            weekdays = Array(newValue.weekdays).sorted()
            timesPerWeek = newValue.timesPerWeek
        }
    }

    var link: RoutineLink {
        get { RoutineLink(rawValue: linkRaw) ?? .none }
        set { linkRaw = newValue.rawValue }
    }

    var reminderTime: ClockTime {
        get { ClockTime(hour: reminderHour, minute: reminderMinute) }
        set {
            reminderHour = newValue.hour
            reminderMinute = newValue.minute
        }
    }

    var isArchived: Bool { archivedDayKey != nil }

    var createdDay: DayKey { DayKey(string: createdDayKey) ?? DayKey(createdAt) }
    var archivedDay: DayKey? { archivedDayKey.flatMap(DayKey.init(string:)) }

    var manualCompletionDays: Set<DayKey> { Set(completions.compactMap { DayKey(string: $0.dayKey) }) }

    func evaluator(signals: [DayKey: DaySignals]) -> RoutineEvaluator {
        RoutineEvaluator(
            schedule: schedule,
            link: link,
            createdOn: createdDay,
            archivedOn: archivedDay,
            manualCompletions: manualCompletionDays,
            signals: signals
        )
    }
}

@Model
final class RoutineCompletion {
    var id: UUID = UUID()
    var dayKey: String = ""
    var completedAt: Date = Date()
    var routine: Routine?

    init(day: DayKey) {
        self.id = UUID()
        self.dayKey = day.string
        self.completedAt = Date()
    }
}

// MARK: - Weekly review

/// The person's decision after reading a weekly review.
@Model
final class WeeklyReviewNote {
    var id: UUID = UUID()
    var weekStartKey: String = ""
    var decisionRaw: String = ReviewDecision.keepPlan.rawValue
    var note: String = ""
    var createdAt: Date = Date()

    init(weekStart: DayKey, decision: ReviewDecision, note: String) {
        self.id = UUID()
        self.weekStartKey = weekStart.string
        self.decisionRaw = decision.rawValue
        self.note = note
        self.createdAt = Date()
    }

    var decision: ReviewDecision {
        get { ReviewDecision(rawValue: decisionRaw) ?? .keepPlan }
        set { decisionRaw = newValue.rawValue }
    }
}

enum ReviewDecision: String, CaseIterable, Identifiable {
    case keepPlan
    case adjust

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepPlan: return "Keep the current plan"
        case .adjust: return "Adjust next week"
        }
    }
}
