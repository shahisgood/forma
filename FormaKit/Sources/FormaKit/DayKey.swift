import Foundation

/// A calendar day that is independent of time zones.
///
/// Diary entries, routine completions and manual step counts belong to the day
/// the person *chose*, not to an instant in time. Storing the day as a
/// year-month-day triple means that travelling across time zones never moves
/// Tuesday's lunch into Wednesday. Instants (such as a weigh-in timestamp) are
/// converted to a `DayKey` with the calendar in effect when they are displayed.
public struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: comps.year ?? 1970, month: comps.month ?? 1, day: comps.day ?? 1)
    }

    /// Parses the canonical `yyyy-MM-dd` representation.
    public init?(string: String) {
        let parts = string.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public static func today(calendar: Calendar = .current, now: Date = Date()) -> DayKey {
        DayKey(now, calendar: calendar)
    }

    /// Canonical, sortable string form (`2026-10-14`). Used for persistence and predicates.
    public var string: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { string }

    /// Start of this day in the given calendar's time zone.
    public func startDate(calendar: Calendar = .current) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 0
        return calendar.date(from: comps) ?? Date(timeIntervalSince1970: 0)
    }

    /// A time near the middle of the day; safe to use when an instant is needed but
    /// daylight-saving transitions must not push the value into a neighbouring day.
    public func middayDate(calendar: Calendar = .current) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        return calendar.date(from: comps) ?? startDate(calendar: calendar)
    }

    public func adding(days: Int, calendar: Calendar = .current) -> DayKey {
        let base = middayDate(calendar: calendar)
        let shifted = calendar.date(byAdding: .day, value: days, to: base) ?? base
        return DayKey(shifted, calendar: calendar)
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    public func days(to other: DayKey, calendar: Calendar = .current) -> Int {
        let a = middayDate(calendar: calendar)
        let b = other.middayDate(calendar: calendar)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// Weekday number using `Calendar` conventions (1 = Sunday ... 7 = Saturday).
    public func weekday(calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: middayDate(calendar: calendar))
    }

    /// First day of the week containing this day, honouring `calendar.firstWeekday`.
    public func startOfWeek(calendar: Calendar = .current) -> DayKey {
        let offset = (weekday(calendar: calendar) - calendar.firstWeekday + 7) % 7
        return adding(days: -offset, calendar: calendar)
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Every day from `start` through `end` inclusive.
    public static func range(_ start: DayKey, through end: DayKey, calendar: Calendar = .current) -> [DayKey] {
        guard start <= end else { return [] }
        var result: [DayKey] = []
        var cursor = start
        while cursor <= end {
            result.append(cursor)
            cursor = cursor.adding(days: 1, calendar: calendar)
        }
        return result
    }
}

/// A week identified by its first day.
public struct WeekInterval: Hashable, Sendable {
    public let start: DayKey
    public let end: DayKey

    public init(containing day: DayKey, calendar: Calendar = .current) {
        start = day.startOfWeek(calendar: calendar)
        end = start.adding(days: 6, calendar: calendar)
    }

    public func days(calendar: Calendar = .current) -> [DayKey] {
        DayKey.range(start, through: end, calendar: calendar)
    }

    public func previous(calendar: Calendar = .current) -> WeekInterval {
        WeekInterval(containing: start.adding(days: -7, calendar: calendar), calendar: calendar)
    }

    public func next(calendar: Calendar = .current) -> WeekInterval {
        WeekInterval(containing: start.adding(days: 7, calendar: calendar), calendar: calendar)
    }

    public func contains(_ day: DayKey) -> Bool {
        day >= start && day <= end
    }
}
