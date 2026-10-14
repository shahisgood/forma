import Foundation

public enum TargetMetric: String, Codable, CaseIterable, Sendable {
    case calories, protein, carbs, fat, steps
}

/// A target value that took effect on a given day. `value == nil` records that
/// the target was removed.
public struct TargetChange: Hashable, Codable, Sendable {
    public var metric: TargetMetric
    public var value: Double?
    public var effectiveFrom: DayKey
    public var createdAt: Date

    public init(metric: TargetMetric, value: Double?, effectiveFrom: DayKey, createdAt: Date) {
        self.metric = metric
        self.value = value
        self.effectiveFrom = effectiveFrom
        self.createdAt = createdAt
    }
}

/// Resolves which target applied on a given day.
///
/// Changing a target only affects the day it is changed and later days, so past
/// days keep being evaluated against the target that was in effect at the time.
/// The very first target recorded for a metric also applies to earlier days, so
/// history imported from Apple Health has something to be compared against.
public struct TargetTimeline: Sendable {
    private let changes: [TargetMetric: [TargetChange]]

    public init(_ changes: [TargetChange]) {
        var grouped: [TargetMetric: [TargetChange]] = [:]
        for change in changes {
            grouped[change.metric, default: []].append(change)
        }
        for key in grouped.keys {
            grouped[key]?.sort { ($0.effectiveFrom, $0.createdAt) < ($1.effectiveFrom, $1.createdAt) }
        }
        self.changes = grouped
    }

    public func value(_ metric: TargetMetric, on day: DayKey) -> Double? {
        guard let list = changes[metric], let first = list.first else { return nil }
        if day < first.effectiveFrom { return first.value }
        return list.last { $0.effectiveFrom <= day }?.value
    }

    /// The target currently in effect (for `today`).
    public func current(_ metric: TargetMetric, today: DayKey) -> Double? {
        value(metric, on: today)
    }

    public func nutrition(on day: DayKey) -> NutritionTargets {
        NutritionTargets(
            calories: value(.calories, on: day),
            protein: value(.protein, on: day),
            carbs: value(.carbs, on: day),
            fat: value(.fat, on: day)
        )
    }

    /// Whether the target changed at any point within the range (useful for chart footnotes).
    public func changed(_ metric: TargetMetric, between start: DayKey, and end: DayKey) -> Bool {
        guard let list = changes[metric] else { return false }
        return list.contains { $0.effectiveFrom > start && $0.effectiveFrom <= end }
    }
}
