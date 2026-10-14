import Foundation

public struct StrengthHighlight: Hashable, Sendable {
    public var exerciseName: String
    public var trackingType: ExerciseTrackingType
    public var record: PersonalRecord
    public var date: Date

    public init(exerciseName: String, trackingType: ExerciseTrackingType, record: PersonalRecord, date: Date) {
        self.exerciseName = exerciseName
        self.trackingType = trackingType
        self.record = record
        self.date = date
    }

    public func sentence(unit: WeightUnit) -> String {
        switch record.kind {
        case .estimatedOneRepMax:
            return "\(exerciseName): estimated 1RM of \(NumberText.weight(record.value, unit: unit))"
        case .heaviestWeight:
            return "\(exerciseName): heaviest set yet at \(NumberText.weight(record.value, unit: unit))"
        case .repsAtWeight:
            return "\(exerciseName): \(Int(record.value)) reps, more than before at that weight"
        case .mostReps:
            return "\(exerciseName): \(Int(record.value)) reps in a set"
        case .longestDuration:
            return "\(exerciseName): longest time of \(SetDescription.formatDuration(record.value))"
        case .longestDistance:
            return "\(exerciseName): longest distance of \(SetDescription.formatDistance(record.value))"
        }
    }
}

public struct RoutineWeekResult: Hashable, Sendable {
    public var name: String
    public var completed: Int
    public var expected: Int

    public init(name: String, completed: Int, expected: Int) {
        self.name = name
        self.completed = completed
        self.expected = expected
    }
}

public struct WeeklyReviewInput: Sendable {
    public var week: WeekInterval
    public var today: DayKey
    public var unit: WeightUnit
    /// Number of planned training days in the week, or `nil` without a plan.
    public var plannedWorkouts: Int?
    public var completedWorkouts: Int
    public var trainingMinutes: Int
    public var strengthHighlights: [StrengthHighlight]
    /// One summary per day of the week (days without entries included).
    public var nutritionDays: [DayNutritionSummary]
    public var weightPoints: [WeightTrendPoint]
    public var weighInCount: Int
    public var stepDays: [StepDay]
    public var stepTargets: TargetTimeline
    public var routines: [RoutineWeekResult]

    public init(
        week: WeekInterval,
        today: DayKey,
        unit: WeightUnit,
        plannedWorkouts: Int?,
        completedWorkouts: Int,
        trainingMinutes: Int,
        strengthHighlights: [StrengthHighlight],
        nutritionDays: [DayNutritionSummary],
        weightPoints: [WeightTrendPoint],
        weighInCount: Int,
        stepDays: [StepDay],
        stepTargets: TargetTimeline,
        routines: [RoutineWeekResult]
    ) {
        self.week = week
        self.today = today
        self.unit = unit
        self.plannedWorkouts = plannedWorkouts
        self.completedWorkouts = completedWorkouts
        self.trainingMinutes = trainingMinutes
        self.strengthHighlights = strengthHighlights
        self.nutritionDays = nutritionDays
        self.weightPoints = weightPoints
        self.weighInCount = weighInCount
        self.stepDays = stepDays
        self.stepTargets = stepTargets
        self.routines = routines
    }
}

public struct WeeklyReviewSection: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case training, strength, nutrition, weight, steps, routines
    }

    /// Whether there was enough data to say something.
    public enum Coverage: String, Sendable {
        case none, partial, good
    }

    public var id: Kind { kind }
    public var kind: Kind
    public var headline: String
    public var details: [String]
    public var coverage: Coverage
    /// 0...1 when a natural ratio exists (used for the small progress indicator).
    public var ratio: Double?
}

/// Builds a descriptive, non-judgemental summary of a week.
///
/// It reports what was *logged*. Missing entries are described as missing,
/// never as failures, and nothing is inferred beyond what the data supports.
public struct WeeklyReview: Sendable {
    public var week: WeekInterval
    public var isWeekComplete: Bool
    public var sections: [WeeklyReviewSection]

    public var hasAnyData: Bool { sections.contains { $0.coverage != .none } }

    public init(_ input: WeeklyReviewInput, calendar: Calendar = .current) {
        week = input.week
        isWeekComplete = input.today > input.week.end
        let elapsedDays = min(7, max(0, input.week.start.days(to: min(input.today, input.week.end), calendar: calendar) + 1))
        var sections: [WeeklyReviewSection] = []

        // Training
        do {
            let done = input.completedWorkouts
            var details: [String] = []
            if input.trainingMinutes > 0 {
                details.append("\(NumberText.integer(input.trainingMinutes)) minutes of training logged.")
            }
            let headline: String
            var ratio: Double?
            if let planned = input.plannedWorkouts, planned > 0 {
                headline = "\(done) of \(planned) planned workout\(planned == 1 ? "" : "s") completed"
                ratio = min(1, Double(done) / Double(planned))
            } else if done > 0 {
                headline = "\(done) workout\(done == 1 ? "" : "s") completed"
            } else {
                headline = "No workouts logged"
            }
            sections.append(WeeklyReviewSection(kind: .training, headline: headline, details: details, coverage: done > 0 ? .good : .none, ratio: ratio))
        }

        // Strength
        if !input.strengthHighlights.isEmpty {
            let lines = input.strengthHighlights.prefix(4).map { $0.sentence(unit: input.unit) }
            let count = input.strengthHighlights.count
            sections.append(WeeklyReviewSection(
                kind: .strength,
                headline: "\(count) personal record\(count == 1 ? "" : "s")",
                details: Array(lines),
                coverage: .good,
                ratio: nil
            ))
        }

        // Nutrition
        do {
            let logged = input.nutritionDays.filter(\.hasEntries)
            var details: [String] = []
            if let avg = NutritionStats.averageOfLoggedDays(input.nutritionDays) {
                details.append("Average on logged days: \(NumberText.integer(Int(avg.calories.rounded()))) kcal and \(NumberText.integer(Int(avg.protein.rounded()))) g protein.")
            }
            let protein = NutritionStats.proteinTargetDays(input.nutritionDays)
            if protein.withTarget > 0 {
                details.append("Protein target reached on \(protein.met) of \(protein.withTarget) logged day\(protein.withTarget == 1 ? "" : "s").")
            }
            if !logged.isEmpty && logged.count < elapsedDays {
                details.append("Days without entries aren't counted in averages.")
            }
            let headline = logged.isEmpty
                ? "No food logged"
                : "Food logged on \(logged.count) of \(elapsedDays) day\(elapsedDays == 1 ? "" : "s")"
            sections.append(WeeklyReviewSection(
                kind: .nutrition,
                headline: headline,
                details: details,
                coverage: logged.isEmpty ? .none : (logged.count >= max(1, elapsedDays - 1) ? .good : .partial),
                ratio: elapsedDays > 0 ? Double(logged.count) / Double(elapsedDays) : nil
            ))
        }

        // Weight
        do {
            var details: [String] = []
            let headline: String
            let coverage: WeeklyReviewSection.Coverage
            if let change = WeightTrend.change(input.weightPoints, from: input.week.start, through: input.week.end),
               input.weighInCount >= 2 {
                let converted = input.unit.fromKilograms(change)
                let rounded = Rounding.round(converted, fractionDigits: 1)
                if abs(rounded) < 0.1 {
                    headline = "Trend roughly unchanged"
                } else {
                    let sign = rounded > 0 ? "+" : "−"
                    headline = "Trend \(sign)\(String(format: "%.1f", abs(rounded))) \(input.unit.symbol) this week"
                }
                details.append("Based on \(input.weighInCount) weigh-ins. The trend smooths out day-to-day swings from water, food and timing.")
                coverage = input.weighInCount >= 3 ? .good : .partial
            } else if input.weighInCount > 0 {
                headline = "\(input.weighInCount) weigh-in\(input.weighInCount == 1 ? "" : "s")"
                details.append("Not enough weigh-ins this week to describe a change.")
                coverage = .partial
            } else {
                headline = "No weigh-ins"
                coverage = .none
            }
            sections.append(WeeklyReviewSection(kind: .weight, headline: headline, details: details, coverage: coverage, ratio: nil))
        }

        // Steps
        do {
            let range = input.week.start...min(input.week.end, max(input.week.start, input.today))
            let stats = StepStatistics(days: input.stepDays, range: range, targets: input.stepTargets)
            var details: [String] = []
            let headline: String
            if let avg = stats.average {
                headline = "\(NumberText.integer(avg)) steps a day on average"
                if stats.daysWithTarget > 0 {
                    details.append("Step target reached on \(stats.daysTargetReached) of \(stats.daysWithTarget) day\(stats.daysWithTarget == 1 ? "" : "s") with data.")
                }
                if stats.daysWithData < elapsedDays {
                    details.append("\(elapsedDays - stats.daysWithData) day\(elapsedDays - stats.daysWithData == 1 ? "" : "s") had no step data.")
                }
            } else {
                headline = "No step data"
            }
            sections.append(WeeklyReviewSection(
                kind: .steps,
                headline: headline,
                details: details,
                coverage: stats.daysWithData == 0 ? .none : (stats.daysWithData >= elapsedDays ? .good : .partial),
                ratio: stats.daysWithTarget > 0 ? Double(stats.daysTargetReached) / Double(stats.daysWithTarget) : nil
            ))
        }

        // Routines
        let routinesWithExpectations = input.routines.filter { $0.expected > 0 }
        if !routinesWithExpectations.isEmpty {
            let completed = routinesWithExpectations.reduce(0) { $0 + $1.completed }
            let expected = routinesWithExpectations.reduce(0) { $0 + $1.expected }
            let details = routinesWithExpectations.map { "\($0.name): \($0.completed) of \($0.expected)" }
            sections.append(WeeklyReviewSection(
                kind: .routines,
                headline: "\(completed) of \(expected) routine check-ins",
                details: details,
                coverage: completed > 0 ? .good : .none,
                ratio: expected > 0 ? min(1, Double(completed) / Double(expected)) : nil
            ))
        }

        self.sections = sections
    }
}

/// Minimal locale-aware number text used by FormaKit's generated sentences.
public enum NumberText {
    public static func integer(_ value: Int, locale: Locale = .current) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    public static func decimal(_ value: Double, fractionDigits: Int = 1, locale: Locale = .current) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = fractionDigits
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.\(fractionDigits)f", value)
    }

    public static func weight(_ kilograms: Double, unit: WeightUnit, locale: Locale = .current) -> String {
        "\(decimal(unit.fromKilograms(kilograms), fractionDigits: 1, locale: locale)) \(unit.symbol)"
    }
}
