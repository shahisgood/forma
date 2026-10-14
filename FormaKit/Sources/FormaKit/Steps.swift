import Foundation

/// Where a day's step count came from.
public enum StepSource: String, Codable, Sendable {
    case health
    case manual
}

/// The step count used for one day after reconciling sources.
public struct StepDay: Hashable, Sendable, Identifiable {
    public var id: DayKey { day }
    public var day: DayKey
    public var steps: Int
    public var source: StepSource
    /// True when a manual entry exists for this day but was not used because
    /// Apple Health already had data. Shown so nothing is silently discarded.
    public var manualEntryIgnored: Bool

    public init(day: DayKey, steps: Int, source: StepSource, manualEntryIgnored: Bool = false) {
        self.day = day
        self.steps = steps
        self.source = source
        self.manualEntryIgnored = manualEntryIgnored
    }
}

public enum StepReconciler {
    /// Combines Health totals and manual entries without double counting.
    ///
    /// Rules:
    /// - Apple Health totals (already de-duplicated across devices by HealthKit's
    ///   statistics query) take precedence for any day that has Health data.
    /// - Manual entries fill days that have no Health data. Multiple manual entries
    ///   on one day are added together (e.g. "morning walk", "evening walk").
    /// - Manual entries are never added on top of Health data.
    /// - Days with no data at all are omitted rather than reported as zero.
    public static func reconcile(health: [DayKey: Int], manual: [DayKey: [Int]]) -> [StepDay] {
        var result: [DayKey: StepDay] = [:]
        for (day, steps) in health where steps > 0 {
            result[day] = StepDay(day: day, steps: steps, source: .health, manualEntryIgnored: !(manual[day]?.isEmpty ?? true))
        }
        for (day, entries) in manual where !entries.isEmpty {
            if result[day] == nil {
                result[day] = StepDay(day: day, steps: entries.reduce(0, +), source: .manual)
            }
        }
        return result.values.sorted { $0.day < $1.day }
    }
}

public struct StepStatistics: Equatable, Sendable {
    public var daysWithData: Int
    public var average: Int?
    public var total: Int
    public var daysTargetReached: Int
    /// Days that had both data and a target, i.e. the denominator for `daysTargetReached`.
    public var daysWithTarget: Int
    public var best: StepDay?

    /// Statistics over `range`. Days without data are excluded from the average.
    public init(days: [StepDay], range: ClosedRange<DayKey>, targets: TargetTimeline) {
        let inRange = days.filter { range.contains($0.day) }
        daysWithData = inRange.count
        total = inRange.reduce(0) { $0 + $1.steps }
        average = inRange.isEmpty ? nil : Int((Double(total) / Double(inRange.count)).rounded())
        var reached = 0
        var withTarget = 0
        for day in inRange {
            if let target = targets.value(.steps, on: day.day), target > 0 {
                withTarget += 1
                if Double(day.steps) >= target { reached += 1 }
            }
        }
        daysTargetReached = reached
        daysWithTarget = withTarget
        best = inRange.max { $0.steps < $1.steps }
    }
}
