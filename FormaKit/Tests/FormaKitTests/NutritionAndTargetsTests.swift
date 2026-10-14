import Foundation
import Testing
@testable import FormaKit

@Suite("Nutrition")
struct NutritionTests {
    @Test func addingNutrientsKeepsMissingMacrosMissing() {
        let a = Nutrients(calories: 200, protein: 20)
        let b = Nutrients(calories: 100, protein: 5)
        let sum = a + b
        #expect(sum.calories == 300)
        #expect(sum.protein == 25)
        #expect(sum.carbs == nil)
        #expect(sum.fat == nil)
        let c = Nutrients(calories: 50, protein: 0, carbs: 10, fat: nil)
        #expect((sum + c).carbs == 10)
    }

    @Test func scaling() {
        let n = Nutrients(calories: 100, protein: 10, carbs: 20, fat: 2).scaled(by: 1.5)
        #expect(n == Nutrients(calories: 150, protein: 15, carbs: 30, fat: 3))
    }

    @Test func remainingAgainstTargets() {
        let summary = DayNutritionSummary(
            day: DayKey(year: 2026, month: 10, day: 14),
            totals: Nutrients(calories: 1800, protein: 120),
            entryCount: 4,
            targets: NutritionTargets(calories: 2200, protein: 150)
        )
        #expect(summary.caloriesRemaining == 400)
        #expect(summary.proteinRemaining == 30)
        let noTargets = DayNutritionSummary(day: summary.day, totals: summary.totals, entryCount: 4, targets: NutritionTargets())
        #expect(noTargets.caloriesRemaining == nil)
    }

    @Test func averagesIgnoreUnloggedDays() {
        let d1 = DayKey(year: 2026, month: 10, day: 12)
        let days = [
            DayNutritionSummary(day: d1, totals: Nutrients(calories: 2000, protein: 100), entryCount: 3, targets: NutritionTargets(protein: 120)),
            DayNutritionSummary(day: d1.adding(days: 1), totals: .zero, entryCount: 0, targets: NutritionTargets(protein: 120)),
            DayNutritionSummary(day: d1.adding(days: 2), totals: Nutrients(calories: 2400, protein: 140), entryCount: 2, targets: NutritionTargets(protein: 120))
        ]
        let avg = NutritionStats.averageOfLoggedDays(days)!
        #expect(avg.calories == 2200)
        let protein = NutritionStats.proteinTargetDays(days)
        #expect(protein.met == 1)
        #expect(protein.withTarget == 2)
    }

    @Test func mealSuggestionByHour() {
        let cal = makeCalendar()
        #expect(Meal.suggested(for: date(2026, 10, 14, 7, calendar: cal), calendar: cal) == .breakfast)
        #expect(Meal.suggested(for: date(2026, 10, 14, 13, calendar: cal), calendar: cal) == .lunch)
        #expect(Meal.suggested(for: date(2026, 10, 14, 19, calendar: cal), calendar: cal) == .dinner)
        #expect(Meal.suggested(for: date(2026, 10, 14, 23, calendar: cal), calendar: cal) == .snacks)
    }
}

@Suite("Target timeline")
struct TargetTimelineTests {
    let d = DayKey(year: 2026, month: 10, day: 10)

    @Test func changesApplyFromTheirDayForward() {
        let timeline = TargetTimeline([
            TargetChange(metric: .calories, value: 2500, effectiveFrom: d, createdAt: Date(timeIntervalSince1970: 1)),
            TargetChange(metric: .calories, value: 2200, effectiveFrom: d.adding(days: 5), createdAt: Date(timeIntervalSince1970: 2))
        ])
        #expect(timeline.value(.calories, on: d.adding(days: 4)) == 2500)
        #expect(timeline.value(.calories, on: d.adding(days: 5)) == 2200)
        #expect(timeline.value(.calories, on: d.adding(days: 30)) == 2200)
    }

    @Test func firstTargetAppliesToEarlierHistory() {
        let timeline = TargetTimeline([TargetChange(metric: .steps, value: 8000, effectiveFrom: d, createdAt: Date())])
        #expect(timeline.value(.steps, on: d.adding(days: -100)) == 8000)
    }

    @Test func sameDayChangesUseLatest() {
        let timeline = TargetTimeline([
            TargetChange(metric: .protein, value: 120, effectiveFrom: d, createdAt: Date(timeIntervalSince1970: 10)),
            TargetChange(metric: .protein, value: 140, effectiveFrom: d, createdAt: Date(timeIntervalSince1970: 20))
        ])
        #expect(timeline.value(.protein, on: d) == 140)
    }

    @Test func clearingATarget() {
        let timeline = TargetTimeline([
            TargetChange(metric: .fat, value: 70, effectiveFrom: d, createdAt: Date(timeIntervalSince1970: 1)),
            TargetChange(metric: .fat, value: nil, effectiveFrom: d.adding(days: 2), createdAt: Date(timeIntervalSince1970: 2))
        ])
        #expect(timeline.value(.fat, on: d.adding(days: 1)) == 70)
        #expect(timeline.value(.fat, on: d.adding(days: 3)) == nil)
        #expect(timeline.value(.carbs, on: d) == nil)
    }
}
