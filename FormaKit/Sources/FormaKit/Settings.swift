import Foundation

public enum GoalDirection: String, Codable, CaseIterable, Sendable, Identifiable {
    case lose
    case maintain
    case gain

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .lose: return "Lose weight"
        case .maintain: return "Maintain"
        case .gain: return "Gain weight"
        }
    }

    public var shortName: String {
        switch self {
        case .lose: return "Cut"
        case .maintain: return "Maintain"
        case .gain: return "Bulk"
        }
    }

    public var symbol: String {
        switch self {
        case .lose: return "arrow.down.right"
        case .maintain: return "equal"
        case .gain: return "arrow.up.right"
        }
    }
}

/// Body-weight goal. Every field is optional: a direction alone is a valid goal.
public struct BodyGoal: Hashable, Codable, Sendable {
    public var direction: GoalDirection?
    /// Target weight for lose/gain goals.
    public var targetKg: Double?
    /// Maintenance range.
    public var rangeLowerKg: Double?
    public var rangeUpperKg: Double?

    public init(direction: GoalDirection? = nil, targetKg: Double? = nil, rangeLowerKg: Double? = nil, rangeUpperKg: Double? = nil) {
        self.direction = direction
        self.targetKg = targetKg
        self.rangeLowerKg = rangeLowerKg
        self.rangeUpperKg = rangeUpperKg
    }

    /// Values a chart should show as a goal line or band.
    public var chartValues: [Double] {
        switch direction {
        case .maintain:
            return [rangeLowerKg, rangeUpperKg].compactMap { $0 }
        case .lose, .gain:
            return [targetKg].compactMap { $0 }
        case nil:
            return []
        }
    }

    /// A neutral description of where the current trend sits relative to the goal.
    public func status(trendKg: Double?, unit: WeightUnit) -> String? {
        guard let trendKg, let direction else { return nil }
        switch direction {
        case .maintain:
            guard let lo = rangeLowerKg, let hi = rangeUpperKg, lo < hi else { return nil }
            if trendKg < lo { return "Trend is \(NumberText.weight(lo - trendKg, unit: unit)) below your range" }
            if trendKg > hi { return "Trend is \(NumberText.weight(trendKg - hi, unit: unit)) above your range" }
            return "Trend is within your range"
        case .lose:
            guard let target = targetKg else { return nil }
            let remaining = trendKg - target
            return remaining <= 0 ? "Trend has reached your target" : "\(NumberText.weight(remaining, unit: unit)) to your target"
        case .gain:
            guard let target = targetKg else { return nil }
            let remaining = target - trendKg
            return remaining <= 0 ? "Trend has reached your target" : "\(NumberText.weight(remaining, unit: unit)) to your target"
        }
    }
}

public enum AppearancePreference: String, Codable, CaseIterable, Sendable, Identifiable {
    case system, light, dark
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

public struct ReminderSettings: Hashable, Codable, Sendable {
    public var workout = ReminderConfig(enabled: false, time: ClockTime(hour: 17, minute: 30))
    public var weight = ReminderConfig(enabled: false, time: ClockTime(hour: 7, minute: 30))
    public var weeklyReview = ReminderConfig(enabled: false, time: ClockTime(hour: 18, minute: 0), weekdays: [1])
    public var restTimer = true
    public var quietHours = QuietHours()
    /// Generic notification text by default, so nothing personal shows on the Lock Screen.
    public var discreet = true

    public init() {}

    enum CodingKeys: String, CodingKey { case workout, weight, weeklyReview, restTimer, quietHours, discreet }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReminderSettings()
        workout = try c.decodeIfPresent(ReminderConfig.self, forKey: .workout) ?? d.workout
        weight = try c.decodeIfPresent(ReminderConfig.self, forKey: .weight) ?? d.weight
        weeklyReview = try c.decodeIfPresent(ReminderConfig.self, forKey: .weeklyReview) ?? d.weeklyReview
        restTimer = try c.decodeIfPresent(Bool.self, forKey: .restTimer) ?? d.restTimer
        quietHours = try c.decodeIfPresent(QuietHours.self, forKey: .quietHours) ?? d.quietHours
        discreet = try c.decodeIfPresent(Bool.self, forKey: .discreet) ?? d.discreet
    }
}

public struct HealthPreferences: Hashable, Codable, Sendable {
    /// Whether the person has chosen to connect Apple Health (authorization was requested).
    public var connected = false
    public var importWeight = true
    public var readSteps = true
    public var saveWeight = false
    public var saveWorkouts = false

    public init() {}

    enum CodingKeys: String, CodingKey { case connected, importWeight, readSteps, saveWeight, saveWorkouts }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        connected = try c.decodeIfPresent(Bool.self, forKey: .connected) ?? false
        importWeight = try c.decodeIfPresent(Bool.self, forKey: .importWeight) ?? true
        readSteps = try c.decodeIfPresent(Bool.self, forKey: .readSteps) ?? true
        saveWeight = try c.decodeIfPresent(Bool.self, forKey: .saveWeight) ?? false
        saveWorkouts = try c.decodeIfPresent(Bool.self, forKey: .saveWorkouts) ?? false
    }
}

public struct LiveActivityPreferences: Hashable, Codable, Sendable {
    public var enabled = true
    /// Show workout and exercise names on the Lock Screen. When off, only a timer is shown.
    public var showDetails = true

    public init() {}

    enum CodingKeys: String, CodingKey { case enabled, showDetails }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        showDetails = try c.decodeIfPresent(Bool.self, forKey: .showDetails) ?? true
    }
}

/// All user preferences. Stored as a single JSON document; decoding tolerates
/// missing keys so new settings can be added without a migration.
public struct SettingsValues: Hashable, Codable, Sendable {
    public var onboardingCompleted = false
    public var weightUnit: WeightUnit = .kilograms
    public var goal = BodyGoal()
    public var trackCarbs = false
    public var trackFat = false
    /// Planned training weekdays (1 = Sunday ... 7 = Saturday).
    public var trainingDays: Set<Int> = []
    /// Template assigned to a training weekday, keyed by weekday number.
    public var templateForWeekday: [Int: UUID] = [:]
    public var defaultRestSeconds = 120
    public var autoStartRestTimer = true
    public var trackEffort = false
    public var manualStepsEnabled = false
    public var reminders = ReminderSettings()
    public var health = HealthPreferences()
    public var liveActivities = LiveActivityPreferences()
    public var appearance: AppearancePreference = .system
    /// First day (`yyyy-MM-dd`) of the week whose review card was dismissed on Today.
    public var dismissedReviewWeek: String?

    public init() {}

    enum CodingKeys: String, CodingKey {
        case onboardingCompleted, weightUnit, goal, trackCarbs, trackFat, trainingDays, templateForWeekday
        case defaultRestSeconds, autoStartRestTimer, trackEffort, manualStepsEnabled
        case reminders, health, liveActivities, appearance, dismissedReviewWeek
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SettingsValues()
        onboardingCompleted = (try? c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted)) ?? d.onboardingCompleted
        weightUnit = (try? c.decodeIfPresent(WeightUnit.self, forKey: .weightUnit)) ?? d.weightUnit
        goal = (try? c.decodeIfPresent(BodyGoal.self, forKey: .goal)) ?? d.goal
        trackCarbs = (try? c.decodeIfPresent(Bool.self, forKey: .trackCarbs)) ?? d.trackCarbs
        trackFat = (try? c.decodeIfPresent(Bool.self, forKey: .trackFat)) ?? d.trackFat
        trainingDays = (try? c.decodeIfPresent(Set<Int>.self, forKey: .trainingDays)) ?? d.trainingDays
        templateForWeekday = (try? c.decodeIfPresent([Int: UUID].self, forKey: .templateForWeekday)) ?? d.templateForWeekday
        defaultRestSeconds = (try? c.decodeIfPresent(Int.self, forKey: .defaultRestSeconds)) ?? d.defaultRestSeconds
        autoStartRestTimer = (try? c.decodeIfPresent(Bool.self, forKey: .autoStartRestTimer)) ?? d.autoStartRestTimer
        trackEffort = (try? c.decodeIfPresent(Bool.self, forKey: .trackEffort)) ?? d.trackEffort
        manualStepsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .manualStepsEnabled)) ?? d.manualStepsEnabled
        reminders = (try? c.decodeIfPresent(ReminderSettings.self, forKey: .reminders)) ?? d.reminders
        health = (try? c.decodeIfPresent(HealthPreferences.self, forKey: .health)) ?? d.health
        liveActivities = (try? c.decodeIfPresent(LiveActivityPreferences.self, forKey: .liveActivities)) ?? d.liveActivities
        appearance = (try? c.decodeIfPresent(AppearancePreference.self, forKey: .appearance)) ?? d.appearance
        dismissedReviewWeek = (try? c.decodeIfPresent(String.self, forKey: .dismissedReviewWeek)) ?? nil
    }

    public static func decode(_ data: Data?) -> SettingsValues {
        guard let data, let values = try? JSONDecoder().decode(SettingsValues.self, from: data) else {
            return SettingsValues()
        }
        return values
    }

    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }
}
