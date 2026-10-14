import Foundation
import Testing
@testable import FormaKit

@Suite("Weight trend")
struct WeightTrendTests {
    let cal = makeCalendar()

    func sample(_ d: Int, _ kg: Double, month: Int = 10, hour: Int = 7) -> WeightSample {
        WeightSample(date: date(2026, month, d, hour, calendar: cal), kilograms: kg)
    }

    @Test func emptyInputProducesNoPoints() {
        #expect(WeightTrend.compute([], calendar: cal).isEmpty)
    }

    @Test func firstPointEqualsObservation() {
        let points = WeightTrend.compute([sample(1, 80)], calendar: cal)
        #expect(points.count == 1)
        #expect(points[0].trend == 80)
    }

    @Test func multipleWeighInsPerDayAreAveraged() {
        let points = WeightTrend.compute([sample(1, 80, hour: 7), sample(1, 81, hour: 21)], calendar: cal)
        #expect(points.count == 1)
        #expect(points[0].observed == 80.5)
        #expect(points[0].count == 2)
    }

    @Test func trendMovesTenPercentPerDay() {
        let points = WeightTrend.compute([sample(1, 80), sample(2, 81)], calendar: cal)
        #expect(abs(points[1].trend - 80.1) < 1e-9)
    }

    @Test func gapsScaleTheStepWithoutInventingDays() {
        let points = WeightTrend.compute([sample(1, 80), sample(4, 81)], calendar: cal)
        #expect(points.count == 2, "no values are created for skipped days")
        let expectedAlpha: Double = 1 - 0.9 * 0.9 * 0.9
        #expect(abs(points[1].trend - (80 + expectedAlpha)) < 1e-9)
    }

    @Test func longGapsStartNewSegment() {
        let points = WeightTrend.compute([
            sample(1, 80, month: 1), sample(2, 80, month: 1), sample(1, 85, month: 3)
        ], calendar: cal)
        #expect(points.map(\.segment) == [0, 0, 1])
        #expect(points[2].trend == 85, "trend restarts after a long gap")
    }

    @Test func dampsSingleDaySpike() {
        var samples = (1...14).map { sample($0, 80) }
        samples.append(sample(15, 82))
        let points = WeightTrend.compute(samples, calendar: cal)
        #expect(points.last!.trend < 80.3)
    }

    @Test func weeklyRateNeedsEnoughData() {
        let today = DayKey(year: 2026, month: 10, day: 20)
        let few = WeightTrend.compute([sample(18, 80), sample(19, 80), sample(20, 80)], calendar: cal)
        #expect(WeightTrend.weeklyRate(few, endingOn: today, calendar: cal) == nil)
    }

    @Test func weeklyRateMatchesLinearLoss() {
        // Losing 0.1 kg/day = 0.7 kg/week.
        let samples = (1...28).map { sample($0, 90 - Double($0 - 1) * 0.1) }
        let points = WeightTrend.compute(samples, calendar: cal)
        let rate = WeightTrend.weeklyRate(points, endingOn: DayKey(year: 2026, month: 10, day: 28), calendar: cal)
        #expect(rate != nil)
        #expect(abs(rate! + 0.7) < 1e-6)
        let summary = WeightTrendSummary(points: points, today: DayKey(year: 2026, month: 10, day: 28), calendar: cal)
        #expect(summary.direction == .down)
        #expect(summary.sentence(unit: .kilograms).contains("down about 0.7 kg"))
    }

    @Test func stableTrendIsDescribedAsStable() {
        let samples = (1...20).map { sample($0, $0 % 2 == 0 ? 80.2 : 79.8) }
        let points = WeightTrend.compute(samples, calendar: cal)
        let summary = WeightTrendSummary(points: points, today: DayKey(year: 2026, month: 10, day: 20), calendar: cal)
        #expect(summary.direction == .stable)
    }

    @Test func changeOverPeriodUsesTrend() {
        let samples = (1...10).map { sample($0, 80 - Double($0) * 0.1) }
        let points = WeightTrend.compute(samples, calendar: cal)
        let change = WeightTrend.change(points, from: DayKey(year: 2026, month: 10, day: 1), through: DayKey(year: 2026, month: 10, day: 10))
        #expect(change != nil)
        #expect(change! < 0)
        #expect(WeightTrend.change(points, from: DayKey(year: 2026, month: 11, day: 1), through: DayKey(year: 2026, month: 11, day: 5)) == nil)
    }
}

@Suite("Chart scale")
struct ChartScaleTests {
    @Test func enforcesMinimumSpan() {
        let domain = ChartScale.domain(for: [80.0, 80.4, 80.2], minimumSpan: 3)!
        #expect(domain.upperBound - domain.lowerBound >= 3)
        #expect(domain.contains(80.2))
    }

    @Test func includesNearbyGoalButIgnoresDistantOne() {
        let near = ChartScale.domain(for: [80, 82], minimumSpan: 3, include: [78])!
        #expect(near.contains(78))
        let far = ChartScale.domain(for: [80, 82], minimumSpan: 3, include: [60])!
        #expect(!far.contains(60))
    }

    @Test func emptyValuesHaveNoDomain() {
        #expect(ChartScale.domain(for: [], minimumSpan: 3) == nil)
    }
}
