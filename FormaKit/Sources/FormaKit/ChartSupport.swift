import Foundation

/// Date ranges offered by progress charts.
public enum ChartRange: String, CaseIterable, Codable, Sendable, Identifiable {
    case week = "W"
    case month = "M"
    case threeMonths = "3M"
    case year = "Y"
    case all = "All"

    public var id: String { rawValue }

    public var accessibilityName: String {
        switch self {
        case .week: return "Past week"
        case .month: return "Past month"
        case .threeMonths: return "Past three months"
        case .year: return "Past year"
        case .all: return "All time"
        }
    }

    /// Number of days covered, or `nil` for all time.
    public var dayCount: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .threeMonths: return 91
        case .year: return 365
        case .all: return nil
        }
    }

    /// First day of the range ending on `today`. For `.all`, the earliest data day (or today).
    public func startDay(today: DayKey, earliest: DayKey?, calendar: Calendar = .current) -> DayKey {
        if let count = dayCount {
            return today.adding(days: -(count - 1), calendar: calendar)
        }
        return min(earliest ?? today, today)
    }
}

/// Helpers that keep chart axes honest.
public enum ChartScale {
    /// A y-axis domain covering `values`, padded and widened to at least
    /// `minimumSpan`, so small fluctuations are not exaggerated.
    ///
    /// - Parameters:
    ///   - include: extra values (such as a goal) to include when they are
    ///     reasonably close to the data. Values farther than `includeReach`
    ///     spans away are ignored so they do not flatten the data.
    public static func domain(
        for values: [Double],
        minimumSpan: Double,
        padding: Double = 0.12,
        include: [Double] = [],
        includeReach: Double = 1.0
    ) -> ClosedRange<Double>? {
        let finite = values.filter(\.isFinite)
        guard let lo = finite.min(), let hi = finite.max() else { return nil }
        var low = lo
        var high = hi
        let baseSpan = max(hi - lo, minimumSpan)
        for extra in include where extra.isFinite {
            let distance = extra < low ? low - extra : (extra > high ? extra - high : 0)
            if distance <= baseSpan * includeReach {
                low = min(low, extra)
                high = max(high, extra)
            }
        }
        var span = high - low
        if span < minimumSpan {
            let mid = (low + high) / 2
            low = mid - minimumSpan / 2
            high = mid + minimumSpan / 2
            span = minimumSpan
        }
        let pad = span * padding
        return (low - pad)...(high + pad)
    }

    /// Whether a value lies inside a domain.
    public static func contains(_ domain: ClosedRange<Double>?, _ value: Double?) -> Bool {
        guard let domain, let value else { return false }
        return domain.contains(value)
    }

    /// Upper bound for a zero-based bar chart (steps, calories) with headroom
    /// for a target rule mark.
    public static func zeroBasedUpperBound(values: [Double], targets: [Double], minimum: Double) -> Double {
        let top = (values + targets).filter(\.isFinite).max() ?? 0
        return max(minimum, top * 1.12)
    }
}
