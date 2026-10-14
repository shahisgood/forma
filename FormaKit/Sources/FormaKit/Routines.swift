import Foundation

/// How often a routine is meant to happen.
public struct RoutineSchedule: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// Every day.
        case daily
        /// On specific weekdays.
        case weekdays
        /// A number of times per week, on any days.
        case timesPerWeek
    }

    public var kind: Kind
    /// Calendar weekdays (1 = Sunday ... 7 = Saturday). Used by `.weekdays`.
    public var weekdays: Set<Int>
    /// Used by `.timesPerWeek`.
    public var timesPerWeek: Int

    public init(kind: Kind, weekdays: Set<Int> = [], timesPerWeek: Int = 3) {
        self.kind = kind
        self.weekdays = weekdays
        self.timesPerWeek = max(1, min(7, timesPerWeek))
    }

    public static let daily = RoutineSchedule(kind: .daily)

    /// Whether the routine is pinned to this specific day.
    /// Flexible (`timesPerWeek`) routines are never pinned to a day.
    public func isPinned(to day: DayKey, calendar: Calendar = .current) -> Bool {
        switch kind {
        case .daily: return true
        case .weekdays: return weekdays.contains(day.weekday(calendar: calendar))
        case .timesPerWeek: return false
        }
    }

    /// Number of completions expected between `start` and `end` inclusive.
    public func expectedCount(from start: DayKey, through end: DayKey, calendar: Calendar = .current) -> Int {
        guard start <= end else { return 0 }
        let days = DayKey.range(start, through: end, calendar: calendar)
        switch kind {
        case .daily:
            return days.count
        case .weekdays:
            return days.filter { weekdays.contains($0.weekday(calendar: calendar)) }.count
        case .timesPerWeek:
            return min(timesPerWeek, days.count)
        }
    }

    public func summary(calendar: Calendar = .current) -> String {
        switch kind {
        case .daily:
            return "Every day"
        case .weekdays:
            if weekdays.count == 7 { return "Every day" }
            if weekdays.isEmpty { return "No days selected" }
            let symbols = calendar.shortWeekdaySymbols
            let ordered = Weekdays.ordered(calendar: calendar).filter { weekdays.contains($0) }
            return ordered.map { symbols[$0 - 1] }.joined(separator: ", ")
        case .timesPerWeek:
            return timesPerWeek == 1 ? "Once a week" : "\(timesPerWeek)× a week"
        }
    }
}

public enum Weekdays {
    /// Weekday numbers ordered starting at the calendar's first weekday.
    public static func ordered(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }
}

/// Recorded activity that can complete a routine automatically, so the person
/// does not have to tick the same thing twice.
public enum RoutineLink: String, Codable, CaseIterable, Sendable {
    case none
    case workoutCompleted
    case stepTargetReached
    case foodLogged
    case weightLogged

    public var label: String {
        switch self {
        case .none: return "Only when I check it off"
        case .workoutCompleted: return "When I finish a workout"
        case .stepTargetReached: return "When I reach my step target"
        case .foodLogged: return "When I log food"
        case .weightLogged: return "When I log my weight"
        }
    }

    public var shortLabel: String {
        switch self {
        case .none: return ""
        case .workoutCompleted: return "Workout logged"
        case .stepTargetReached: return "Step target reached"
        case .foodLogged: return "Food logged"
        case .weightLogged: return "Weight logged"
        }
    }
}

/// What happened on a day, used to auto-complete linked routines.
public struct DaySignals: Hashable, Sendable {
    public var workoutCompleted: Bool
    public var stepTargetReached: Bool
    public var foodLogged: Bool
    public var weightLogged: Bool

    public init(workoutCompleted: Bool = false, stepTargetReached: Bool = false, foodLogged: Bool = false, weightLogged: Bool = false) {
        self.workoutCompleted = workoutCompleted
        self.stepTargetReached = stepTargetReached
        self.foodLogged = foodLogged
        self.weightLogged = weightLogged
    }

    public func satisfies(_ link: RoutineLink) -> Bool {
        switch link {
        case .none: return false
        case .workoutCompleted: return workoutCompleted
        case .stepTargetReached: return stepTargetReached
        case .foodLogged: return foodLogged
        case .weightLogged: return weightLogged
        }
    }
}

public enum RoutineCompletionKind: Sendable, Equatable {
    case manual
    case automatic(RoutineLink)
}

public struct RoutineEvaluator: Sendable {
    public var schedule: RoutineSchedule
    public var link: RoutineLink
    public var createdOn: DayKey
    public var archivedOn: DayKey?
    public var manualCompletions: Set<DayKey>
    public var signals: [DayKey: DaySignals]

    public init(
        schedule: RoutineSchedule,
        link: RoutineLink,
        createdOn: DayKey,
        archivedOn: DayKey? = nil,
        manualCompletions: Set<DayKey>,
        signals: [DayKey: DaySignals]
    ) {
        self.schedule = schedule
        self.link = link
        self.createdOn = createdOn
        self.archivedOn = archivedOn
        self.manualCompletions = manualCompletions
        self.signals = signals
    }

    public func completion(on day: DayKey) -> RoutineCompletionKind? {
        if manualCompletions.contains(day) { return .manual }
        if link != .none, signals[day]?.satisfies(link) == true { return .automatic(link) }
        return nil
    }

    public func completedDays(in range: ClosedRange<DayKey>, calendar: Calendar = .current) -> [DayKey] {
        DayKey.range(range.lowerBound, through: range.upperBound, calendar: calendar).filter { completion(on: $0) != nil }
    }

    /// Whether the routine should be shown as something to do on `day`.
    public func isDue(on day: DayKey, calendar: Calendar = .current) -> Bool {
        guard day >= createdOn else { return false }
        if let archivedOn, day >= archivedOn { return false }
        switch schedule.kind {
        case .daily, .weekdays:
            return schedule.isPinned(to: day, calendar: calendar)
        case .timesPerWeek:
            // Flexible routines stay visible until the weekly count is reached,
            // and remain visible on the days they were completed.
            if completion(on: day) != nil { return true }
            let week = WeekInterval(containing: day, calendar: calendar)
            let done = completedDays(in: week.start...week.end, calendar: calendar).count
            return done < schedule.timesPerWeek
        }
    }

    /// Completed and expected counts for a week, counting only days the routine existed.
    /// For the current week, days after `today` are not counted as missed.
    public func consistency(for week: WeekInterval, today: DayKey, calendar: Calendar = .current) -> (completed: Int, expected: Int) {
        let activeStart = max(week.start, createdOn)
        var activeEnd = week.end
        if let archivedOn { activeEnd = min(activeEnd, archivedOn.adding(days: -1, calendar: calendar)) }
        guard activeStart <= activeEnd, activeStart <= today else { return (0, 0) }
        let countedEnd = min(activeEnd, today)
        let done = completedDays(in: activeStart...countedEnd, calendar: calendar).filter {
            schedule.kind == .timesPerWeek || schedule.isPinned(to: $0, calendar: calendar)
        }
        switch schedule.kind {
        case .timesPerWeek:
            // A flexible routine's weekly goal applies to the whole week, even mid-week.
            let available = activeStart.days(to: activeEnd, calendar: calendar) + 1
            let expected = min(schedule.timesPerWeek, available)
            return (min(done.count, expected), expected)
        case .daily, .weekdays:
            return (done.count, schedule.expectedCount(from: activeStart, through: countedEnd, calendar: calendar))
        }
    }
}
