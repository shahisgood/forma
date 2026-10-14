import SwiftUI
import SwiftData
import Charts
import FormaKit

/// Progress overview. Each card states what it shows in plain language and
/// links to a detailed view.
struct ProgressScreen: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            ProgressOverview()
                .navigationTitle("Progress")
                .navigationDestination(for: ProgressDestination.self) { destination in
                    switch destination {
                    case .weight: WeightDetailView()
                    case .steps: StepsDetailView()
                    case .nutrition: NutritionTrendsView()
                    case .routines: RoutinesView()
                    case .exercises: ExerciseLibraryView()
                    case .review(let start): WeeklyReviewView(week: WeekInterval(containing: start))
                    }
                }
                .navigationDestination(for: Exercise.self) { ExerciseDetailView(exercise: $0) }
                .settingsToolbarButton(router)
                .workoutResumeAccessory()
        }
    }
}

enum ProgressDestination: Hashable {
    case weight, steps, nutrition, routines, exercises
    case review(DayKey)
}

private struct ProgressOverview: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DayClock.self) private var clock
    @Environment(HealthService.self) private var health
    @Environment(\.modelContext) private var context
    @Query(sort: \WeightEntry.measuredAt) private var weights: [WeightEntry]
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }, sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]
    @Query private var targetRecords: [TargetRecord]
    @Query private var manualSteps: [ManualStepEntry]
    @Query(sort: \Routine.position) private var routines: [Routine]

    private var unit: WeightUnit { settings.unit }
    private var today: DayKey { clock.today }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                weightCard
                strengthCard
                consistencyCard
                stepsCard
                NutritionOverviewCard(today: today)
                routinesCard
                reviewsSection
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(Theme.Palette.background)
    }

    // MARK: Weight

    @ViewBuilder
    private var weightCard: some View {
        let points = WeightTrend.compute(weights.map { WeightSample(date: $0.measuredAt, kilograms: $0.kilograms) })
        let start = today.adding(days: -89)
        let visible = points.filter { $0.day >= start }
        let summary = WeightTrendSummary(points: points, today: today)
        NavigationLink(value: ProgressDestination.weight) {
            Card {
                CardHeader(title: "Weight trend · 3 months", symbol: Metric.weight.symbol, tint: Metric.weight.color) { chevron }
                if visible.isEmpty {
                    Text("Log a few weigh-ins to see your trend.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    if let trend = summary.latestTrendKg {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(Format.weightValue(trend, unit: unit))
                                .font(.metric(.title2))
                                .numericStyle()
                            Text(unit.symbol).font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            if let change = WeightTrend.change(points, from: start, through: today) {
                                Text(Format.weightChange(change, unit: unit))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    WeightChart(points: visible, unit: unit, goal: settings.values.goal, xDomain: start.startDate()...today.adding(days: 1).startDate(), selectedDate: .constant(nil))
                        .frame(height: 140)
                        .allowsHitTesting(false)
                    Text(summary.sentence(unit: unit))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Strength

    private struct StrengthRow: Identifiable {
        var id: UUID { exercise.id }
        let exercise: Exercise
        let latest: String
        let change: String?
        let sessionCount: Int
    }

    private var strengthRows: [StrengthRow] {
        let windowStart = today.adding(days: -89).startDate()
        var counts: [UUID: (exercise: Exercise, count: Int)] = [:]
        for session in sessions where session.startedAt >= windowStart {
            for entry in session.exercises {
                guard let exercise = entry.exercise, entry.sets.contains(where: \.isCompleted) else { continue }
                counts[exercise.id, default: (exercise, 0)].count += 1
            }
        }
        return counts.values
            .sorted { $0.count > $1.count }
            .prefix(4)
            .map { item in
                let summaries = ExerciseProgression.summaries(item.exercise.completedSetRecords()).filter { $0.date >= windowStart }
                switch item.exercise.trackingType {
                case .weightReps:
                    let values = summaries.compactMap(\.bestEstimated1RM)
                    let latest = values.last.map { "e1RM \(Format.weight($0, unit: unit))" } ?? "—"
                    let change: String? = values.count >= 2 ? Format.weightChange(values.last! - values.first!, unit: unit) : nil
                    return StrengthRow(exercise: item.exercise, latest: latest, change: change, sessionCount: item.count)
                case .bodyweightReps, .assistedReps:
                    let values = summaries.compactMap(\.bestReps)
                    let latest = values.last.map { "Best \($0) reps" } ?? "—"
                    let change: String? = values.count >= 2 ? "\(values.last! - values.first! >= 0 ? "+" : "−")\(abs(values.last! - values.first!)) reps" : nil
                    return StrengthRow(exercise: item.exercise, latest: latest, change: change, sessionCount: item.count)
                case .duration, .distanceDuration:
                    let latest = summaries.last.map { $0.bestDistance.map(SetDescription.formatDistance) ?? $0.bestDuration.map(SetDescription.formatDuration) ?? "—" } ?? "—"
                    return StrengthRow(exercise: item.exercise, latest: latest, change: nil, sessionCount: item.count)
                }
            }
    }

    @ViewBuilder
    private var strengthCard: some View {
        let rows = strengthRows
        Card {
            CardHeader(title: "Strength · 3 months", symbol: "chart.line.uptrend.xyaxis", tint: Metric.training.color) {
                NavigationLink(value: ProgressDestination.exercises) {
                    Text("All").font(.subheadline.weight(.medium))
                }
            }
            if rows.isEmpty {
                Text("Your most-trained exercises and their progress will appear here after a few workouts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        NavigationLink(value: row.exercise) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.exercise.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text("\(row.latest) · \(row.sessionCount) session\(row.sessionCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let change = row.change {
                                    Text(change)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .numericStyle()
                                }
                                chevron
                            }
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle(scale: 0.99))
                        if row.id != rows.last?.id { Divider() }
                    }
                }
                FootnoteText(text: "Change compares your first and latest session in the last three months. e1RM is an estimate.")
            }
        }
    }

    // MARK: Consistency

    private struct WeekCount: Identifiable {
        var id: DayKey { start }
        let start: DayKey
        let count: Int
    }

    @ViewBuilder
    private var consistencyCard: some View {
        let currentWeek = WeekInterval(containing: today)
        let weeks: [WeekCount] = (0..<12).reversed().map { offset in
            let week = WeekInterval(containing: currentWeek.start.adding(days: -7 * offset))
            let count = sessions.filter { week.contains(DayKey($0.startedAt)) }.count
            return WeekCount(start: week.start, count: count)
        }
        let planned = settings.values.trainingDays.count
        let completeWeeks = weeks.dropLast()
        let average = completeWeeks.isEmpty ? 0 : Double(completeWeeks.reduce(0) { $0 + $1.count }) / Double(completeWeeks.count)

        Card {
            CardHeader(title: "Training consistency · 12 weeks", symbol: "calendar", tint: Metric.training.color)
            if sessions.isEmpty {
                Text("Workouts per week will appear here once you've logged some.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("About \(Format.number(average)) workouts a week over the last 11 full weeks.")
                    .font(.subheadline)
                Chart {
                    ForEach(weeks) { week in
                        BarMark(x: .value("Week", week.start.middayDate(), unit: .weekOfYear), y: .value("Workouts", week.count))
                            .foregroundStyle(Metric.training.color.opacity(week.start == currentWeek.start ? 0.45 : 1))
                            .cornerRadius(3)
                            .accessibilityLabel("Week of \(Format.shortDate(week.start.middayDate()))")
                            .accessibilityValue("\(week.count) workouts\(week.start == currentWeek.start ? ", week in progress" : "")")
                    }
                    if planned > 0 {
                        RuleMark(y: .value("Plan", planned))
                            .foregroundStyle(Color.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("Current plan: \(planned)/week")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .chartYScale(domain: 0...Double(max(planned, weeks.map(\.count).max() ?? 0, 3) + 1))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 140)
                Text("The lighter bar is the current week, still in progress.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var stepsCard: some View {
        let days = StepHistory.days(health: health, manualEntries: manualSteps, manualEnabled: settings.values.manualStepsEnabled)
        let targets = TargetStore.timeline(targetRecords)
        let start = today.adding(days: -6)
        let stats = StepStatistics(days: days, range: start...today, targets: targets)
        NavigationLink(value: ProgressDestination.steps) {
            Card {
                CardHeader(title: "Steps · 7 days", symbol: Metric.steps.symbol, tint: Metric.steps.color) { chevron }
                if stats.daysWithData == 0 {
                    Text(health.status == .connected ? "No step data in the last week." : "Connect Apple Health or add steps manually to see your history.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .top) {
                        StatValue(value: stats.average.map(Format.steps) ?? "—", label: "Daily average", size: .metric(.title3))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        StatValue(value: stats.daysWithTarget > 0 ? "\(stats.daysTargetReached) of \(stats.daysWithTarget)" : "—", label: "Days target reached", size: .metric(.title3))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    StepsChart(days: days.filter { $0.day >= start }, start: start, today: today, targets: targets, selectedDate: .constant(nil))
                        .frame(height: 110)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Routines

    @ViewBuilder
    private var routinesCard: some View {
        let active = routines.filter { !$0.isArchived }
        if !active.isEmpty {
            let week = WeekInterval(containing: today)
            let routineContext = RoutineContext.make(for: week, context: context, health: health, settings: settings, targetRecords: targetRecords)
            let results = active.map { RoutineResult(routine: $0, result: $0.evaluator(signals: routineContext.signals).consistency(for: week, today: today)) }
            let completed = results.reduce(0) { $0 + $1.result.completed }
            let expected = results.reduce(0) { $0 + $1.result.expected }
            NavigationLink(value: ProgressDestination.routines) {
                Card {
                    CardHeader(title: "Routines · this week", symbol: Metric.routines.symbol, tint: Metric.routines.color) { chevron }
                    Text("\(completed) of \(expected) check-ins so far")
                        .font(.headline)
                    CapsuleProgress(progress: expected > 0 ? Double(completed) / Double(expected) : 0, color: Metric.routines.color)
                    ForEach(results, id: \.routine.id) { item in
                        HStack {
                            Text(item.routine.name).font(.subheadline)
                            Spacer()
                            Text("\(item.result.completed)/\(item.result.expected)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .numericStyle()
                        }
                    }
                }
            }
            .buttonStyle(PressableStyle())
        }
    }

    private struct RoutineResult {
        let routine: Routine
        let result: (completed: Int, expected: Int)
    }

    // MARK: Reviews

    @ViewBuilder
    private var reviewsSection: some View {
        let current = WeekInterval(containing: today)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionTitle(title: "Weekly reviews")
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { offset in
                    let week = WeekInterval(containing: current.start.adding(days: -7 * offset))
                    NavigationLink(value: ProgressDestination.review(week.start)) {
                        HStack {
                            Text(Format.weekRange(week))
                                .foregroundStyle(.primary)
                            if offset == 0 {
                                TagBadge(text: "In progress")
                            }
                            Spacer()
                            chevron
                        }
                        .padding(.horizontal, Theme.Spacing.l)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.99))
                    if offset < 7 { Divider().padding(.leading, Theme.Spacing.l) }
                }
            }
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Nutrition trends

struct NutritionOverviewCard: View {
    let today: DayKey

    @Query private var entries: [FoodEntry]
    @Query private var targetRecords: [TargetRecord]

    init(today: DayKey) {
        self.today = today
        let keys = DayKeys.last(7, endingOn: today)
        _entries = Query(filter: #Predicate<FoodEntry> { keys.contains($0.dayKey) })
    }

    var body: some View {
        let summaries = NutritionHistory.summaries(entries: entries, days: DayKey.range(today.adding(days: -6), through: today), targets: TargetStore.timeline(targetRecords))
        let logged = summaries.filter(\.hasEntries)
        let average = NutritionStats.averageOfLoggedDays(summaries)
        NavigationLink(value: ProgressDestination.nutrition) {
            Card {
                CardHeader(title: "Nutrition · 7 days", symbol: Metric.calories.symbol, tint: Metric.calories.color) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                if logged.isEmpty {
                    Text("Nothing logged in the last week.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .top) {
                        StatValue(value: "\(logged.count) of 7", label: "Days logged", size: .metric(.title3))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        StatValue(value: average.map { Format.calories($0.calories) } ?? "—", unit: "kcal", label: "Avg. on logged days", size: .metric(.title3))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        StatValue(value: average.map { Format.grams($0.protein) } ?? "—", unit: "g", label: "Avg. protein", size: .metric(.title3))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .buttonStyle(PressableStyle())
    }
}

enum NutritionHistory {
    static func summaries(entries: [FoodEntry], days: [DayKey], targets: TargetTimeline) -> [DayNutritionSummary] {
        let grouped = Dictionary(grouping: entries, by: \.dayKey)
        return days.map { day in
            let items = grouped[day.string] ?? []
            return DayNutritionSummary(
                day: day,
                totals: items.reduce(Nutrients.zero) { $0 + $1.nutrients },
                entryCount: items.count,
                targets: targets.nutrition(on: day)
            )
        }
    }
}

struct NutritionTrendsView: View {
    @Environment(DayClock.self) private var clock
    @State private var range: ChartRange = .month

    var body: some View {
        NutritionTrendsContent(range: range, today: clock.today, rangeBinding: $range)
            .id(range)
            .navigationTitle("Nutrition Trends")
    }
}

private struct TargetPoint {
    let day: DayKey
    let value: Double
}

private struct NutritionTrendsContent: View {
    let range: ChartRange
    let today: DayKey
    @Binding var rangeBinding: ChartRange

    @Query private var entries: [FoodEntry]
    @Query private var targetRecords: [TargetRecord]
    @State private var selectedDate: Date?

    init(range: ChartRange, today: DayKey, rangeBinding: Binding<ChartRange>) {
        self.range = range
        self.today = today
        _rangeBinding = rangeBinding
        let keys = DayKeys.last(range.dayCount ?? 30, endingOn: today)
        _entries = Query(filter: #Predicate<FoodEntry> { keys.contains($0.dayKey) })
    }

    var body: some View {
        let days = DayKey.range(today.adding(days: -((range.dayCount ?? 30) - 1)), through: today)
        let timeline = TargetStore.timeline(targetRecords)
        let summaries = NutritionHistory.summaries(entries: entries, days: days, targets: timeline)
        let logged = summaries.filter(\.hasEntries)
        let average = NutritionStats.averageOfLoggedDays(summaries)
        let protein = NutritionStats.proteinTargetDays(summaries)
        let targetPoints = days.compactMap { day in timeline.value(.calories, on: day).map { TargetPoint(day: day, value: $0) } }
        let upper = ChartScale.zeroBasedUpperBound(values: logged.map(\.totals.calories), targets: targetPoints.map(\.value), minimum: 1500)
        let selected = selectedDate.flatMap { date in logged.first { $0.day == DayKey(date) } }

        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    RangePicker(range: $rangeBinding, options: [.week, .month, .threeMonths])
                    Chart {
                        ForEach(logged, id: \.day) { day in
                            BarMark(x: .value("Day", day.day.middayDate(), unit: .day), y: .value("Calories", day.totals.calories))
                                .foregroundStyle(Metric.calories.color)
                                .cornerRadius(3)
                                .accessibilityLabel(Format.dateWithYear(day.day.middayDate()))
                                .accessibilityValue("\(Format.calories(day.totals.calories)) kilocalories")
                        }
                        ForEach(targetPoints, id: \.day) { point in
                            LineMark(x: .value("Day", point.day.middayDate(), unit: .day), y: .value("Target", point.value), series: .value("Series", "target"))
                                .interpolationMethod(.stepCenter)
                                .foregroundStyle(Color.secondary)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .accessibilityHidden(true)
                        }
                        if let selected {
                            RuleMark(x: .value("Selected", selected.day.middayDate(), unit: .day))
                                .foregroundStyle(Color.secondary.opacity(0.3))
                                .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(Format.dateWithYear(selected.day.middayDate()))
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        Text("\(Format.calories(selected.totals.calories)) kcal")
                                            .font(.subheadline.weight(.semibold))
                                        Text("\(Format.grams(selected.totals.protein)) g protein")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                        }
                    }
                    .chartYScale(domain: 0...upper)
                    .chartXScale(domain: days.first!.startDate()...today.adding(days: 1).startDate())
                    .chartXSelection(value: $selectedDate)
                    .frame(height: 220)
                    .overlay {
                        if logged.isEmpty {
                            Text("Nothing logged in this range")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding()
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
                        }
                    }
                    .accessibilityLabel("Daily calories on logged days")
                    FootnoteText(text: "Only days with entries are shown. Unlogged days aren't treated as zero. Values are estimates.")
                }
                .padding(.vertical, Theme.Spacing.s)
            }

            Section("Summary") {
                LabeledContent("Days logged", value: "\(logged.count) of \(days.count)")
                LabeledContent("Average calories", value: average.map { "\(Format.calories($0.calories)) kcal" } ?? "—")
                LabeledContent("Average protein", value: average.map { "\(Format.grams($0.protein)) g" } ?? "—")
                if let carbs = average?.carbs {
                    LabeledContent("Average carbs", value: "\(Format.grams(carbs)) g")
                }
                if let fat = average?.fat {
                    LabeledContent("Average fat", value: "\(Format.grams(fat)) g")
                }
                if protein.withTarget > 0 {
                    LabeledContent("Protein target reached", value: "\(protein.met) of \(protein.withTarget) logged days")
                }
            }
        }
    }
}
