import Foundation

/// A single body-weight measurement, in kilograms.
public struct WeightSample: Hashable, Sendable {
    public var date: Date
    public var kilograms: Double

    public init(date: Date, kilograms: Double) {
        self.date = date
        self.kilograms = kilograms
    }
}

/// One day of weigh-ins, reduced to their mean, plus the smoothed trend value.
public struct WeightTrendPoint: Hashable, Sendable {
    public var day: DayKey
    /// Mid-day instant for charting.
    public var date: Date
    /// Mean of that day's measurements.
    public var observed: Double
    /// Smoothed trend value on that day.
    public var trend: Double
    /// Number of measurements recorded that day.
    public var count: Int
    /// Index of the contiguous segment this point belongs to. Long gaps without
    /// measurements start a new segment so charts never draw a line through
    /// periods with no data.
    public var segment: Int
}

/// Weight-trend smoothing.
///
/// Method: an exponentially weighted moving average applied to daily means.
/// Each day the trend moves `alpha` (10%) of the way from its previous value
/// toward that day's average weigh-in. When days are skipped, the step is
/// scaled by the gap (`1 - (1 - alpha)^days`), so a weigh-in after a week away
/// moves the trend further than one taken the next morning, but no values are
/// ever invented for the skipped days.
///
/// With `alpha = 0.1`, the trend has a half-life of roughly 6.6 days: it
/// follows sustained changes within a couple of weeks while damping the
/// day-to-day swings caused by water, food volume, sodium and timing.
public enum WeightTrend {
    public static let defaultAlpha = 0.1
    /// Gaps longer than this (in days) break the trend line into a new segment.
    public static let defaultMaxGapDays = 21

    public static func compute(
        _ samples: [WeightSample],
        alpha: Double = defaultAlpha,
        maxGapDays: Int = defaultMaxGapDays,
        calendar: Calendar = .current
    ) -> [WeightTrendPoint] {
        guard !samples.isEmpty else { return [] }

        // Reduce to one observation per calendar day.
        var byDay: [DayKey: (sum: Double, count: Int)] = [:]
        for s in samples where s.kilograms.isFinite && s.kilograms > 0 {
            let key = DayKey(s.date, calendar: calendar)
            let existing = byDay[key] ?? (0, 0)
            byDay[key] = (existing.sum + s.kilograms, existing.count + 1)
        }
        let days = byDay.keys.sorted()
        guard let first = days.first, let firstValue = byDay[first] else { return [] }

        var points: [WeightTrendPoint] = []
        var trend = firstValue.sum / Double(firstValue.count)
        var segment = 0
        var previousDay = first

        for day in days {
            guard let bucket = byDay[day] else { continue }
            let observed = bucket.sum / Double(bucket.count)
            if day == first {
                trend = observed
            } else {
                let gap = max(1, previousDay.days(to: day, calendar: calendar))
                if gap > maxGapDays {
                    // Too long without data to carry the old trend forward honestly.
                    segment += 1
                    trend = observed
                } else {
                    let effectiveAlpha = 1 - pow(1 - alpha, Double(gap))
                    trend += effectiveAlpha * (observed - trend)
                }
            }
            points.append(WeightTrendPoint(
                day: day,
                date: day.middayDate(calendar: calendar),
                observed: observed,
                trend: trend,
                count: bucket.count,
                segment: segment
            ))
            previousDay = day
        }
        return points
    }

    /// Least-squares slope of daily weigh-ins over the trailing window, in kg per week.
    ///
    /// Returns `nil` when there is not enough data to say anything meaningful:
    /// fewer than `minimumPoints` days with weigh-ins, or the weigh-ins span
    /// fewer than `minimumSpanDays` days.
    public static func weeklyRate(
        _ points: [WeightTrendPoint],
        endingOn end: DayKey,
        windowDays: Int = 28,
        minimumPoints: Int = 4,
        minimumSpanDays: Int = 10,
        calendar: Calendar = .current
    ) -> Double? {
        let start = end.adding(days: -(windowDays - 1), calendar: calendar)
        let window = points.filter { $0.day >= start && $0.day <= end }
        guard window.count >= minimumPoints,
              let firstDay = window.first?.day, let lastDay = window.last?.day,
              firstDay.days(to: lastDay, calendar: calendar) >= minimumSpanDays else { return nil }

        let xs = window.map { Double(firstDay.days(to: $0.day, calendar: calendar)) }
        let ys = window.map(\.observed)
        let n = Double(xs.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var num = 0.0
        var den = 0.0
        for (x, y) in zip(xs, ys) {
            num += (x - meanX) * (y - meanY)
            den += (x - meanX) * (x - meanX)
        }
        guard den > 0 else { return nil }
        return num / den * 7
    }

    /// Change in the smoothed trend between the first and last points inside `interval`.
    public static func change(
        _ points: [WeightTrendPoint],
        from start: DayKey,
        through end: DayKey
    ) -> Double? {
        let inRange = points.filter { $0.day >= start && $0.day <= end }
        guard inRange.count >= 2, let first = inRange.first, let last = inRange.last,
              first.segment == last.segment else { return nil }
        return last.trend - first.trend
    }
}

/// Plain-language description of a weight trend, written to avoid over-claiming.
public struct WeightTrendSummary: Equatable, Sendable {
    public enum Direction: String, Sendable { case down, stable, up }

    public var direction: Direction?
    /// kg per week, if enough data exists.
    public var weeklyRateKg: Double?
    public var latestTrendKg: Double?
    /// Difference between the latest weigh-in and the trend, in kg.
    public var latestDeviationKg: Double?
    public var hasEnoughData: Bool { weeklyRateKg != nil }

    public init(points: [WeightTrendPoint], today: DayKey, calendar: Calendar = .current) {
        let rate = WeightTrend.weeklyRate(points, endingOn: today, calendar: calendar)
        weeklyRateKg = rate
        latestTrendKg = points.last?.trend
        if let last = points.last {
            latestDeviationKg = last.observed - last.trend
        }
        if let rate {
            if abs(rate) < WeightUnit.kilograms.stableRatePerWeek {
                direction = .stable
            } else {
                direction = rate < 0 ? .down : .up
            }
        }
    }

    /// One-sentence description in the given unit.
    public func sentence(unit: WeightUnit) -> String {
        guard let rate = weeklyRateKg, let direction else {
            return "Log a few more weigh-ins over two weeks or so to see a trend."
        }
        let amount = Rounding.round(abs(unit.fromKilograms(rate)), fractionDigits: 1)
        let formatted = String(format: "%.1f", amount)
        switch direction {
        case .stable:
            return "Your trend has been roughly stable over the last four weeks."
        case .down:
            return "Your trend is moving down about \(formatted) \(unit.symbol) per week over the last four weeks."
        case .up:
            return "Your trend is moving up about \(formatted) \(unit.symbol) per week over the last four weeks."
        }
    }
}
