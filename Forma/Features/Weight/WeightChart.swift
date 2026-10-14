import SwiftUI
import Charts
import FormaKit

/// Body-weight chart: individual daily weigh-ins as faint points and the
/// smoothed trend as a line. The line breaks across long gaps instead of
/// implying measurements that don't exist.
struct WeightChart: View {
    let points: [WeightTrendPoint]
    let unit: WeightUnit
    let goal: BodyGoal
    let xDomain: ClosedRange<Date>
    @Binding var selectedDate: Date?
    var showsGoal = true

    private let color = Metric.weight.color

    private var yDomain: ClosedRange<Double> {
        let values = points.flatMap { [$0.observed, $0.trend] }.map(unit.fromKilograms)
        let goals = showsGoal ? goal.chartValues.map(unit.fromKilograms) : []
        return ChartScale.domain(for: values, minimumSpan: unit.minimumBodyWeightChartSpan, include: goals) ?? 0...1
    }

    private var selectedPoint: WeightTrendPoint? {
        guard let selectedDate, !points.isEmpty else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    private var visibleGoalValues: [Double] {
        guard showsGoal else { return [] }
        let domain = yDomain
        return goal.chartValues.map(unit.fromKilograms).filter { domain.contains($0) }
    }

    var body: some View {
        Chart {
            ForEach(visibleGoalValues, id: \.self) { value in
                RuleMark(y: .value("Goal", value))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .accessibilityLabel("Goal")
                    .accessibilityValue(Format.weight(unit.toKilograms(value), unit: unit))
            }

            ForEach(points, id: \.day) { point in
                PointMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Weigh-in", unit.fromKilograms(point.observed))
                )
                .symbolSize(26)
                .foregroundStyle(color.opacity(0.35))
                .accessibilityLabel(Format.dateWithYear(point.date))
                .accessibilityValue("Weighed \(Format.weight(point.observed, unit: unit)), trend \(Format.weight(point.trend, unit: unit))")
            }

            ForEach(points, id: \.day) { point in
                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Trend", unit.fromKilograms(point.trend)),
                    series: .value("Segment", "trend-\(point.segment)")
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            }

            if let point = selectedPoint {
                RuleMark(x: .value("Selected", point.date, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        WeightSelectionCallout(point: point, unit: unit)
                    }
                PointMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Trend", unit.fromKilograms(point.trend))
                )
                .symbolSize(70)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: xDomain)
        .chartXSelection(value: $selectedDate)
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .motion(Motion.chart, value: xDomain.lowerBound)
    }
}

private struct WeightSelectionCallout: View {
    let point: WeightTrendPoint
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Format.dateWithYear(point.date))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(Format.weight(point.observed, unit: unit))
                .font(.subheadline.weight(.semibold))
                .numericStyle()
            Text("Trend \(Format.weight(point.trend, unit: unit))")
                .font(.caption2)
                .foregroundStyle(Metric.weight.color)
            if point.count > 1 {
                Text("Average of \(point.count) weigh-ins")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Minimal trend line for cards.
struct WeightSparkline: View {
    let points: [WeightTrendPoint]
    let unit: WeightUnit

    var body: some View {
        let values = points.map { unit.fromKilograms($0.trend) }
        let domain = ChartScale.domain(for: values, minimumSpan: unit.minimumBodyWeightChartSpan / 2, padding: 0.2) ?? 0...1
        Chart {
            ForEach(points, id: \.day) { point in
                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Trend", unit.fromKilograms(point.trend)),
                    series: .value("Segment", "trend-\(point.segment)")
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .foregroundStyle(Metric.weight.color)
            }
        }
        .chartYScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}
