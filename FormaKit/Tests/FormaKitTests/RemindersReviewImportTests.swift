import Foundation
import Testing
@testable import FormaKit

@Suite("Reminder planning")
struct ReminderPlannerTests {
    let cal = makeCalendar()

    func input(
        now: Date,
        discreet: Bool = false,
        quiet: QuietHours = QuietHours(),
        workoutDone: Set<DayKey> = [],
        weightDone: Set<DayKey> = []
    ) -> ReminderPlanInput {
        ReminderPlanInput(
            now: now,
            horizonDays: 7,
            discreet: discreet,
            quietHours: quiet,
            workout: ReminderConfig(enabled: true, time: ClockTime(hour: 17, minute: 0)),
            weight: ReminderConfig(enabled: true, time: ClockTime(hour: 7, minute: 30)),
            weeklyReview: ReminderConfig(enabled: true, time: ClockTime(hour: 18, minute: 0), weekdays: [1]),
            trainingDays: [2, 4, 6],
            plannedWorkoutNames: [2: "Push"],
            workoutCompletedDays: workoutDone,
            weightLoggedDays: weightDone,
            routines: []
        )
    }

    @Test func plansWithinHorizonAndSkipsPast() {
        // Monday 2026-10-12 at 08:00: today's 07:30 weigh-in reminder is already past.
        let now = date(2026, 10, 12, 8, 0, calendar: cal)
        let plan = ReminderPlanner.plan(input(now: now), calendar: cal)
        #expect(plan.allSatisfy { $0.fireDate > now })
        #expect(plan.filter { $0.kind == .weight }.count == 6)
        #expect(plan.filter { $0.kind == .workout }.count == 3)
        #expect(plan.filter { $0.kind == .weeklyReview }.count == 1)
        #expect(plan.first { $0.kind == .workout }?.body == "Push is planned for today.")
        #expect(plan == plan.sorted { $0.fireDate < $1.fireDate })
    }

    @Test func skipsRemindersForCompletedDays() {
        let now = date(2026, 10, 12, 6, 0, calendar: cal)
        let monday = DayKey(year: 2026, month: 10, day: 12)
        let plan = ReminderPlanner.plan(input(now: now, workoutDone: [monday], weightDone: [monday]), calendar: cal)
        #expect(!plan.contains { $0.day == monday })
    }

    @Test func respectsQuietHoursAcrossMidnight() {
        let quiet = QuietHours(enabled: true, start: ClockTime(hour: 21, minute: 0), end: ClockTime(hour: 8, minute: 0))
        #expect(quiet.contains(ClockTime(hour: 7, minute: 30)))
        #expect(quiet.contains(ClockTime(hour: 23, minute: 0)))
        #expect(!quiet.contains(ClockTime(hour: 12, minute: 0)))
        let plan = ReminderPlanner.plan(input(now: date(2026, 10, 12, 6, 0, calendar: cal), quiet: quiet), calendar: cal)
        #expect(!plan.contains { $0.kind == .weight })
    }

    @Test func discreetTextHidesDetails() {
        let plan = ReminderPlanner.plan(input(now: date(2026, 10, 12, 6, 0, calendar: cal), discreet: true), calendar: cal)
        #expect(plan.allSatisfy { $0.title == "Forma" && $0.body == "You have a reminder." })
    }

    @Test func capsTotalCount() {
        var i = input(now: date(2026, 10, 12, 6, 0, calendar: cal))
        i.horizonDays = 60
        i.maximumCount = 10
        #expect(ReminderPlanner.plan(i, calendar: cal).count == 10)
    }

    @Test func idsAreStableAndUnique() {
        let plan = ReminderPlanner.plan(input(now: date(2026, 10, 12, 6, 0, calendar: cal)), calendar: cal)
        #expect(Set(plan.map(\.id)).count == plan.count)
        #expect(plan.allSatisfy { $0.id.hasPrefix(ReminderPlanner.idPrefix) })
    }
}

@Suite("Health import de-duplication")
struct HealthImportTests {
    func sample(_ uuid: String, bundle: String = "com.scale.app", external: String? = nil, kg: Double = 80) -> IncomingWeightSample {
        IncomingWeightSample(uuid: uuid, date: Date(), kilograms: kg, sourceBundleID: bundle, sourceName: "Scale", externalID: external)
    }

    @Test func skipsOwnExistingAndInvalid() {
        let plan = HealthImportDeduplicator.plan(
            incoming: [
                sample("A"),
                sample("B", bundle: "dev.forma.app"),
                sample("C", external: "local-1"),
                sample("D"),
                sample("E", kg: 2),
                sample("A"),
                sample("F")
            ],
            appBundleID: "dev.forma.app",
            importedSampleUUIDs: ["D"],
            localEntryIDs: ["local-1"],
            writtenSampleUUIDs: ["F"]
        )
        #expect(plan.toInsert.map(\.uuid) == ["A"])
        #expect(plan.skippedOwn == 3)
        #expect(plan.skippedExisting == 2)
        #expect(plan.skippedInvalid == 1)
    }

    @Test func reimportIsIdempotent() {
        let incoming = [sample("A"), sample("B")]
        let first = HealthImportDeduplicator.plan(incoming: incoming, appBundleID: "x", importedSampleUUIDs: [], localEntryIDs: [], writtenSampleUUIDs: [])
        let second = HealthImportDeduplicator.plan(incoming: incoming, appBundleID: "x", importedSampleUUIDs: Set(first.toInsert.map(\.uuid)), localEntryIDs: [], writtenSampleUUIDs: [])
        #expect(first.toInsert.count == 2)
        #expect(second.toInsert.isEmpty)
    }
}

@Suite("CSV")
struct CSVTests {
    @Test func escapesFields() {
        let table = CSVTable(header: ["name", "note"], rows: [["Oats, rolled", "said \"hi\""], ["Plain", "line\nbreak"]])
        let csv = table.render()
        #expect(csv == "name,note\r\n\"Oats, rolled\",\"said \"\"hi\"\"\"\r\nPlain,\"line\nbreak\"\r\n")
    }
}

@Suite("Weekly review")
struct WeeklyReviewTests {
    let cal = makeCalendar()

    @Test func describesLoggingWithoutJudgement() {
        let monday = DayKey(year: 2026, month: 10, day: 5)
        let week = WeekInterval(containing: monday, calendar: cal)
        let nutrition = week.days(calendar: cal).enumerated().map { i, day in
            DayNutritionSummary(
                day: day,
                totals: i < 4 ? Nutrients(calories: 2000, protein: 130) : .zero,
                entryCount: i < 4 ? 3 : 0,
                targets: NutritionTargets(calories: 2200, protein: 120)
            )
        }
        let input = WeeklyReviewInput(
            week: week,
            today: DayKey(year: 2026, month: 10, day: 13),
            unit: .kilograms,
            plannedWorkouts: 4,
            completedWorkouts: 3,
            trainingMinutes: 160,
            strengthHighlights: [],
            nutritionDays: nutrition,
            weightPoints: [],
            weighInCount: 1,
            stepDays: [],
            stepTargets: TargetTimeline([]),
            routines: [RoutineWeekResult(name: "Walk", completed: 5, expected: 7)]
        )
        let review = WeeklyReview(input, calendar: cal)
        #expect(review.isWeekComplete)
        let training = review.sections.first { $0.kind == .training }!
        #expect(training.headline == "3 of 4 planned workouts completed")
        let food = review.sections.first { $0.kind == .nutrition }!
        #expect(food.headline == "Food logged on 4 of 7 days")
        #expect(food.details.contains { $0.contains("Days without entries aren't counted") })
        let weight = review.sections.first { $0.kind == .weight }!
        #expect(weight.details.contains("Not enough weigh-ins this week to describe a change."))
        let steps = review.sections.first { $0.kind == .steps }!
        #expect(steps.headline == "No step data")
        #expect(steps.coverage == .none)
        let routines = review.sections.first { $0.kind == .routines }!
        #expect(routines.headline == "5 of 7 routine check-ins")
    }
}

@Suite("Settings")
struct SettingsTests {
    @Test func toleratesMissingAndUnknownKeys() throws {
        let json = #"{"weightUnit":"lb","trackCarbs":true,"futureSetting":42,"reminders":{"discreet":false}}"#
        let values = SettingsValues.decode(json.data(using: .utf8))
        #expect(values.weightUnit == .pounds)
        #expect(values.trackCarbs)
        #expect(values.defaultRestSeconds == 120)
        #expect(values.reminders.discreet == false)
        #expect(values.reminders.restTimer == true)
        #expect(values.health.importWeight == true)
    }

    @Test func roundTrips() {
        var values = SettingsValues()
        values.trainingDays = [2, 4]
        values.templateForWeekday = [2: UUID()]
        values.goal = BodyGoal(direction: .maintain, rangeLowerKg: 78, rangeUpperKg: 80)
        let decoded = SettingsValues.decode(values.encoded())
        #expect(decoded == values)
    }

    @Test func goalStatusIsNeutral() {
        let goal = BodyGoal(direction: .maintain, rangeLowerKg: 78, rangeUpperKg: 80)
        #expect(goal.status(trendKg: 79, unit: .kilograms) == "Trend is within your range")
        let cut = BodyGoal(direction: .lose, targetKg: 75)
        #expect(cut.status(trendKg: 77.5, unit: .kilograms) == "2.5 kg to your target")
    }

    @Test func corruptDataFallsBackToDefaults() {
        #expect(SettingsValues.decode("not json".data(using: .utf8)) == SettingsValues())
        #expect(SettingsValues.decode(nil) == SettingsValues())
    }
}
