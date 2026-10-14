import Foundation

public struct ClockTime: Hashable, Codable, Sendable, Comparable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    public static func < (lhs: ClockTime, rhs: ClockTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    public func date(on day: DayKey, calendar: Calendar = .current) -> Date? {
        var comps = DateComponents()
        comps.year = day.year
        comps.month = day.month
        comps.day = day.day
        comps.hour = hour
        comps.minute = minute
        return calendar.date(from: comps)
    }

    public init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }
}

public struct QuietHours: Hashable, Codable, Sendable {
    public var enabled: Bool
    public var start: ClockTime
    public var end: ClockTime

    public init(enabled: Bool = false, start: ClockTime = ClockTime(hour: 22, minute: 0), end: ClockTime = ClockTime(hour: 7, minute: 0)) {
        self.enabled = enabled
        self.start = start
        self.end = end
    }

    /// Whether `time` falls inside quiet hours. Handles ranges that cross midnight.
    public func contains(_ time: ClockTime) -> Bool {
        guard enabled, start != end else { return false }
        if start < end {
            return time >= start && time < end
        }
        return time >= start || time < end
    }
}

public enum ReminderKind: String, Codable, CaseIterable, Sendable {
    case workout
    case weight
    case routine
    case weeklyReview
}

public struct ReminderConfig: Hashable, Codable, Sendable {
    public var enabled: Bool
    public var time: ClockTime
    /// Weekdays (1 = Sunday ... 7 = Saturday). Empty means every day.
    public var weekdays: Set<Int>

    public init(enabled: Bool = false, time: ClockTime, weekdays: Set<Int> = []) {
        self.enabled = enabled
        self.time = time
        self.weekdays = weekdays
    }

    func applies(to weekday: Int) -> Bool {
        weekdays.isEmpty || weekdays.contains(weekday)
    }
}

public struct RoutineReminderInput: Sendable {
    public var id: UUID
    public var name: String
    public var time: ClockTime
    public var evaluator: RoutineEvaluator

    public init(id: UUID, name: String, time: ClockTime, evaluator: RoutineEvaluator) {
        self.id = id
        self.name = name
        self.time = time
        self.evaluator = evaluator
    }
}

public struct PlannedNotification: Hashable, Sendable {
    public var id: String
    public var kind: ReminderKind
    public var fireDate: Date
    public var day: DayKey
    public var title: String
    public var body: String
}

public struct ReminderPlanInput: Sendable {
    public var now: Date
    public var horizonDays: Int
    public var maximumCount: Int
    public var discreet: Bool
    public var quietHours: QuietHours
    public var workout: ReminderConfig
    public var weight: ReminderConfig
    public var weeklyReview: ReminderConfig
    /// Planned training weekdays and, where assigned, the template name for that weekday.
    public var trainingDays: Set<Int>
    public var plannedWorkoutNames: [Int: String]
    public var workoutCompletedDays: Set<DayKey>
    public var weightLoggedDays: Set<DayKey>
    public var routines: [RoutineReminderInput]

    public init(
        now: Date,
        horizonDays: Int = 14,
        maximumCount: Int = 60,
        discreet: Bool,
        quietHours: QuietHours,
        workout: ReminderConfig,
        weight: ReminderConfig,
        weeklyReview: ReminderConfig,
        trainingDays: Set<Int>,
        plannedWorkoutNames: [Int: String],
        workoutCompletedDays: Set<DayKey>,
        weightLoggedDays: Set<DayKey>,
        routines: [RoutineReminderInput]
    ) {
        self.now = now
        self.horizonDays = horizonDays
        self.maximumCount = maximumCount
        self.discreet = discreet
        self.quietHours = quietHours
        self.workout = workout
        self.weight = weight
        self.weeklyReview = weeklyReview
        self.trainingDays = trainingDays
        self.plannedWorkoutNames = plannedWorkoutNames
        self.workoutCompletedDays = workoutCompletedDays
        self.weightLoggedDays = weightLoggedDays
        self.routines = routines
    }
}

/// Computes the exact set of reminder notifications that should be pending.
///
/// Reminders are planned as individual, dated notifications over a rolling
/// window rather than as open-ended repeating ones. That lets the app skip a
/// reminder for something already done today (no stale nudges), respect quiet
/// hours, and stay within iOS's limit of 64 pending notifications. The plan is
/// rebuilt whenever data or settings change and when the app becomes active.
public enum ReminderPlanner {
    public static let idPrefix = "forma.reminder."

    public static func plan(_ input: ReminderPlanInput, calendar: Calendar = .current) -> [PlannedNotification] {
        let today = DayKey(input.now, calendar: calendar)
        var result: [PlannedNotification] = []

        func add(_ kind: ReminderKind, day: DayKey, time: ClockTime, suffix: String? = nil, title: String, body: String) {
            guard !input.quietHours.contains(time),
                  let fire = time.date(on: day, calendar: calendar),
                  fire > input.now else { return }
            var id = "\(idPrefix)\(kind.rawValue).\(day.string)"
            if let suffix { id += ".\(suffix)" }
            let text = input.discreet
                ? (title: "Forma", body: "You have a reminder.")
                : (title: title, body: body)
            result.append(PlannedNotification(id: id, kind: kind, fireDate: fire, day: day, title: text.title, body: text.body))
        }

        for offset in 0..<max(0, input.horizonDays) {
            let day = today.adding(days: offset, calendar: calendar)
            let weekday = day.weekday(calendar: calendar)

            if input.workout.enabled, input.trainingDays.contains(weekday), !input.workoutCompletedDays.contains(day) {
                let body: String
                if let name = input.plannedWorkoutNames[weekday], !name.isEmpty {
                    body = "\(name) is planned for today."
                } else {
                    body = "Today is one of your training days."
                }
                add(.workout, day: day, time: input.workout.time, title: "Training day", body: body)
            }

            if input.weight.enabled, input.weight.applies(to: weekday), !input.weightLoggedDays.contains(day) {
                add(.weight, day: day, time: input.weight.time, title: "Weigh-in", body: "Log your weight whenever you're ready.")
            }

            if input.weeklyReview.enabled, input.weeklyReview.applies(to: weekday) {
                add(.weeklyReview, day: day, time: input.weeklyReview.time, title: "Your week in review", body: "See how the week went and plan the next one.")
            }

            for routine in input.routines {
                let evaluator = routine.evaluator
                guard evaluator.isDue(on: day, calendar: calendar), evaluator.completion(on: day) == nil else { continue }
                add(.routine, day: day, time: routine.time, suffix: routine.id.uuidString, title: routine.name, body: "Scheduled for today.")
            }
        }

        result.sort { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        return Array(result.prefix(max(0, input.maximumCount)))
    }
}
