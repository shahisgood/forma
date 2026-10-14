import Foundation
import Testing
@testable import FormaKit

@Suite("Steps")
struct StepsTests {
    let d = DayKey(year: 2026, month: 10, day: 12)

    @Test func healthDataWinsAndManualNeverDoubleCounts() {
        let days = StepReconciler.reconcile(
            health: [d: 9000],
            manual: [d: [3000], d.adding(days: 1): [2000, 1500]]
        )
        #expect(days.count == 2)
        #expect(days[0].steps == 9000)
        #expect(days[0].source == .health)
        #expect(days[0].manualEntryIgnored)
        #expect(days[1].steps == 3500)
        #expect(days[1].source == .manual)
    }

    @Test func daysWithoutDataAreOmitted() {
        let days = StepReconciler.reconcile(health: [d: 0], manual: [:])
        #expect(days.isEmpty)
    }

    @Test func statisticsUseTargetInEffectEachDay() {
        let targets = TargetTimeline([
            TargetChange(metric: .steps, value: 8000, effectiveFrom: d, createdAt: Date(timeIntervalSince1970: 1)),
            TargetChange(metric: .steps, value: 10000, effectiveFrom: d.adding(days: 2), createdAt: Date(timeIntervalSince1970: 2))
        ])
        let days = [
            StepDay(day: d, steps: 8500, source: .health),
            StepDay(day: d.adding(days: 1), steps: 7000, source: .health),
            StepDay(day: d.adding(days: 2), steps: 9000, source: .health)
        ]
        let stats = StepStatistics(days: days, range: d...d.adding(days: 6), targets: targets)
        #expect(stats.daysWithData == 3)
        #expect(stats.average == 8167)
        #expect(stats.daysTargetReached == 1, "9000 doesn't reach the new 10k target")
        #expect(stats.daysWithTarget == 3)
        #expect(stats.best?.steps == 9000)
    }
}

@Suite("Routines")
struct RoutineTests {
    let cal = makeCalendar()
    // Monday 2026-10-12
    let monday = DayKey(year: 2026, month: 10, day: 12)

    @Test func weekdayScheduleIsPinned() {
        let schedule = RoutineSchedule(kind: .weekdays, weekdays: [2, 4, 6]) // Mon, Wed, Fri
        #expect(schedule.isPinned(to: monday, calendar: cal))
        #expect(!schedule.isPinned(to: monday.adding(days: 1, calendar: cal), calendar: cal))
        #expect(schedule.expectedCount(from: monday, through: monday.adding(days: 6, calendar: cal), calendar: cal) == 3)
        #expect(schedule.summary(calendar: cal) == "Mon, Wed, Fri")
    }

    @Test func linkedActivityCompletesRoutine() {
        let evaluator = RoutineEvaluator(
            schedule: .daily,
            link: .workoutCompleted,
            createdOn: monday,
            manualCompletions: [],
            signals: [monday: DaySignals(workoutCompleted: true)]
        )
        #expect(evaluator.completion(on: monday) == .automatic(.workoutCompleted))
        #expect(evaluator.completion(on: monday.adding(days: 1, calendar: cal)) == nil)
    }

    @Test func flexibleRoutineHidesAfterQuota() {
        let evaluator = RoutineEvaluator(
            schedule: RoutineSchedule(kind: .timesPerWeek, timesPerWeek: 2),
            link: .none,
            createdOn: monday.adding(days: -30, calendar: cal),
            manualCompletions: [monday, monday.adding(days: 1, calendar: cal)],
            signals: [:]
        )
        let wednesday = monday.adding(days: 2, calendar: cal)
        #expect(evaluator.isDue(on: monday, calendar: cal), "still shown on a day it was completed")
        #expect(!evaluator.isDue(on: wednesday, calendar: cal))
        let week = WeekInterval(containing: monday, calendar: cal)
        let result = evaluator.consistency(for: week, today: wednesday, calendar: cal)
        #expect(result.completed == 2)
        #expect(result.expected == 2)
    }

    @Test func consistencyDoesNotCountFutureOrPreCreationDays() {
        let wednesday = monday.adding(days: 2, calendar: cal)
        let evaluator = RoutineEvaluator(
            schedule: .daily,
            link: .none,
            createdOn: monday.adding(days: 1, calendar: cal),
            manualCompletions: [wednesday],
            signals: [:]
        )
        let result = evaluator.consistency(for: WeekInterval(containing: monday, calendar: cal), today: wednesday, calendar: cal)
        #expect(result.expected == 2, "Tuesday and Wednesday only")
        #expect(result.completed == 1)
    }

    @Test func archivedRoutineIsNotDue() {
        let evaluator = RoutineEvaluator(
            schedule: .daily,
            link: .none,
            createdOn: monday.adding(days: -10, calendar: cal),
            archivedOn: monday,
            manualCompletions: [],
            signals: [:]
        )
        #expect(!evaluator.isDue(on: monday, calendar: cal))
        #expect(evaluator.isDue(on: monday.adding(days: -1, calendar: cal), calendar: cal))
    }
}
