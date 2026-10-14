import Foundation
import SwiftData
import FormaKit

/// Reading and writing dated targets.
@MainActor
enum TargetStore {
    static func timeline(_ records: [TargetRecord]) -> TargetTimeline {
        TargetTimeline(records.compactMap(\.change))
    }

    /// Records a new target effective from `day`. Changing a target twice on the
    /// same day keeps a single record for that day.
    static func set(_ metric: TargetMetric, to value: Double?, effectiveFrom day: DayKey = .today(), in context: ModelContext) {
        let raw = metric.rawValue
        let key = day.string
        let all = (try? context.fetch(FetchDescriptor<TargetRecord>(predicate: #Predicate<TargetRecord> { $0.metricRaw == raw }))) ?? []
        let current = timeline(all).value(metric, on: day)
        if current == value { return }
        if let sameDay = all.first(where: { $0.effectiveDayKey == key }) {
            sameDay.value = value
            sameDay.createdAt = Date()
        } else {
            context.insert(TargetRecord(metric: metric, value: value, effectiveFrom: day))
        }
        try? context.save()
    }
}

/// Day-key helpers for querying diary-style records.
enum DayKeys {
    static func strings(from start: DayKey, through end: DayKey) -> [String] {
        DayKey.range(start, through: end).map(\.string)
    }

    static func last(_ days: Int, endingOn end: DayKey = .today()) -> [String] {
        strings(from: end.adding(days: -(days - 1)), through: end)
    }
}

/// Gathers per-day activity used to auto-complete linked routines.
@MainActor
enum ActivitySignals {
    static func build(
        from start: DayKey,
        through end: DayKey,
        context: ModelContext,
        stepDays: [StepDay],
        targets: TargetTimeline
    ) -> [DayKey: DaySignals] {
        var signals: [DayKey: DaySignals] = [:]
        let startDate = start.startDate()
        let endDate = end.adding(days: 1).startDate()

        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.endedAt != nil && $0.startedAt >= startDate && $0.startedAt < endDate }
        ))) ?? []
        for session in sessions {
            signals[DayKey(session.startedAt), default: DaySignals()].workoutCompleted = true
        }

        let weights = (try? context.fetch(FetchDescriptor<WeightEntry>(
            predicate: #Predicate<WeightEntry> { $0.measuredAt >= startDate && $0.measuredAt < endDate }
        ))) ?? []
        for weight in weights {
            signals[DayKey(weight.measuredAt), default: DaySignals()].weightLogged = true
        }

        let keys = DayKeys.strings(from: start, through: end)
        let food = (try? context.fetch(FetchDescriptor<FoodEntry>(
            predicate: #Predicate<FoodEntry> { keys.contains($0.dayKey) }
        ))) ?? []
        for entry in food {
            if let day = DayKey(string: entry.dayKey) {
                signals[day, default: DaySignals()].foodLogged = true
            }
        }

        for day in stepDays where day.day >= start && day.day <= end {
            if let target = targets.value(.steps, on: day.day), target > 0, Double(day.steps) >= target {
                signals[day.day, default: DaySignals()].stepTargetReached = true
            }
        }
        return signals
    }
}

/// Step history combining Apple Health and manual entries.
@MainActor
enum StepHistory {
    static func days(health: HealthService, manualEntries: [ManualStepEntry], manualEnabled: Bool) -> [StepDay] {
        var manual: [DayKey: [Int]] = [:]
        if manualEnabled {
            for entry in manualEntries {
                manual[entry.day, default: []].append(entry.steps)
            }
        }
        let healthDays = health.status == .connected ? health.stepsByDay : [:]
        return StepReconciler.reconcile(health: healthDays, manual: manual)
    }
}

/// Rebuilds the reminder schedule from current data and preferences.
@MainActor
enum ReminderCoordinator {
    static func refresh(context: ModelContext, settings: AppSettings, notifications: NotificationService, health: HealthService) async {
        let values = settings.values
        let routines = ((try? context.fetch(FetchDescriptor<Routine>())) ?? []).filter { $0.reminderEnabled && !$0.isArchived }
        let anyEnabled = values.reminders.workout.enabled || values.reminders.weight.enabled || values.reminders.weeklyReview.enabled || !routines.isEmpty
        guard anyEnabled else {
            await notifications.removeAllReminders()
            return
        }

        let today = DayKey.today()
        let horizon = 14
        let windowStart = today.adding(days: -7)
        let windowEnd = today.adding(days: horizon)
        let targets = TargetStore.timeline((try? context.fetch(FetchDescriptor<TargetRecord>())) ?? [])
        let manual = (try? context.fetch(FetchDescriptor<ManualStepEntry>())) ?? []
        let stepDays = StepHistory.days(health: health, manualEntries: manual, manualEnabled: values.manualStepsEnabled)
        let signals = ActivitySignals.build(from: windowStart, through: windowEnd, context: context, stepDays: stepDays, targets: targets)

        let templates = (try? context.fetch(FetchDescriptor<WorkoutTemplate>())) ?? []
        var plannedNames: [Int: String] = [:]
        for (weekday, id) in values.templateForWeekday {
            if let template = templates.first(where: { $0.id == id }) { plannedNames[weekday] = template.name }
        }

        let input = ReminderPlanInput(
            now: Date(),
            horizonDays: horizon,
            maximumCount: 60,
            discreet: values.reminders.discreet,
            quietHours: values.reminders.quietHours,
            workout: values.reminders.workout,
            weight: values.reminders.weight,
            weeklyReview: values.reminders.weeklyReview,
            trainingDays: values.trainingDays,
            plannedWorkoutNames: plannedNames,
            workoutCompletedDays: Set(signals.filter { $0.value.workoutCompleted }.keys),
            weightLoggedDays: Set(signals.filter { $0.value.weightLogged }.keys),
            routines: routines.map { routine in
                RoutineReminderInput(id: routine.id, name: routine.name, time: routine.reminderTime, evaluator: routine.evaluator(signals: signals))
            }
        )
        await notifications.apply(plan: ReminderPlanner.plan(input))
    }
}
