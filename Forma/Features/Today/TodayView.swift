import SwiftUI
import SwiftData
import FormaKit

struct TodayView: View {
    @Environment(DayClock.self) private var clock
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            TodayContent(day: clock.today)
                .id(clock.today)
                .navigationTitle("Today")
                .navigationDestination(for: TodayDestination.self) { destination in
                    switch destination {
                    case .weight: WeightDetailView()
                    case .steps: StepsDetailView()
                    case .routines: RoutinesView()
                    }
                }
                .settingsToolbarButton(router)
                .workoutResumeAccessory()
        }
    }
}

enum TodayDestination: Hashable {
    case weight, steps, routines
}

private struct TodayContent: View {
    let day: DayKey

    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(WorkoutController.self) private var workout
    @Environment(HealthService.self) private var health
    @Environment(\.modelContext) private var context

    @Query private var foodToday: [FoodEntry]
    @Query(sort: \WeightEntry.measuredAt, order: .reverse) private var weights: [WeightEntry]
    @Query private var recentSessions: [WorkoutSession]
    @Query(sort: \WorkoutTemplate.position) private var templates: [WorkoutTemplate]
    @Query(sort: \Routine.position) private var routines: [Routine]
    @Query private var targetRecords: [TargetRecord]
    @Query private var manualSteps: [ManualStepEntry]

    @State private var showingTargets = false
    @State private var showingStepTarget = false

    init(day: DayKey) {
        self.day = day
        let key = day.string
        _foodToday = Query(filter: #Predicate<FoodEntry> { $0.dayKey == key }, sort: \FoodEntry.loggedAt)
        var sessions = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.endedAt != nil },
            sortBy: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)]
        )
        sessions.fetchLimit = 30
        _recentSessions = Query(sessions)
    }

    private var targets: TargetTimeline { TargetStore.timeline(targetRecords) }
    private var activeRoutines: [Routine] { routines.filter { !$0.isArchived } }
    private var sessionsToday: [WorkoutSession] { recentSessions.filter { DayKey($0.startedAt) == day } }

    private var plannedTemplate: WorkoutTemplate? {
        guard let id = settings.values.templateForWeekday[day.weekday()] else { return nil }
        return templates.first { $0.id == id }
    }

    private var isTrainingDay: Bool { settings.values.trainingDays.contains(day.weekday()) }

    private var isNewUser: Bool {
        weights.isEmpty && recentSessions.isEmpty && foodToday.isEmpty && templates.isEmpty && workout.session == nil
    }

    var body: some View {
        let stepDays = StepHistory.days(health: health, manualEntries: manualSteps, manualEnabled: settings.values.manualStepsEnabled)
        let week = WeekInterval(containing: day)
        let signals = ActivitySignals.build(from: week.start, through: week.end, context: context, stepDays: stepDays, targets: targets)

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header(signals: signals)

                quickActions

                if isNewUser {
                    GettingStartedCard(
                        healthAvailable: health.status != .unavailable,
                        healthConnected: health.status == .connected,
                        hasTargets: targets.current(.calories, today: day) != nil || targets.current(.protein, today: day) != nil,
                        hasTemplates: !templates.isEmpty,
                        hasRoutines: !activeRoutines.isEmpty,
                        setTargets: { showingTargets = true }
                    )
                }

                if workout.session != nil || isTrainingDay || !sessionsToday.isEmpty {
                    workoutCard
                    nutritionCard
                } else {
                    nutritionCard
                    workoutCard
                }

                routinesCard(signals: signals)

                stepsCard(stepDays: stepDays)

                weightCard

                WeeklyReviewLinkCard(today: day)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(Theme.Palette.background)
        .refreshable {
            await health.refreshSteps(force: true)
            await health.importWeights(into: context)
        }
        .sheet(isPresented: $showingTargets) { NutritionTargetsView() }
        .sheet(isPresented: $showingStepTarget) { StepTargetSheet() }
    }

    // MARK: Header

    private func header(signals: [DayKey: DaySignals]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Format.longDay(day.middayDate()))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(summaryLine(signals: signals))
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func summaryLine(signals: [DayKey: DaySignals]) -> String {
        var parts: [String] = []
        if let session = workout.session {
            parts.append("\(session.name) in progress")
        } else if let done = sessionsToday.first {
            parts.append("\(done.name) done")
        } else if let planned = plannedTemplate {
            parts.append("\(planned.name) planned")
        } else if isTrainingDay {
            parts.append("Training day")
        } else if !settings.values.trainingDays.isEmpty {
            parts.append("Rest day")
        }
        let due = activeRoutines.filter { routine in
            let evaluator = routine.evaluator(signals: signals)
            return evaluator.isDue(on: day) && evaluator.completion(on: day) == nil
        }
        if !due.isEmpty {
            parts.append("\(due.count) routine\(due.count == 1 ? "" : "s") to go")
        }
        if parts.isEmpty { return "Here's your day." }
        return parts.joined(separator: " · ")
    }

    private var quickActions: some View {
        HStack(spacing: Theme.Spacing.s) {
            QuickActionButton(title: "Log Food", symbol: "fork.knife", tint: Metric.calories.color) {
                router.show(.logFood(day: day, meal: nil))
            }
            QuickActionButton(title: "Log Weight", symbol: "scalemass", tint: Metric.weight.color) {
                router.show(.logWeight)
            }
            QuickActionButton(
                title: workout.session == nil ? "Workout" : "Resume",
                symbol: workout.session == nil ? "play.fill" : "timer",
                tint: Metric.training.color
            ) {
                if workout.session != nil {
                    workout.isPresented = true
                } else {
                    workout.start(template: plannedTemplate)
                }
            }
        }
    }

    // MARK: Workout

    @ViewBuilder
    private var workoutCard: some View {
        Card {
            CardHeader(title: "Training", symbol: Metric.training.symbol, tint: Metric.training.color) {
                if !templates.isEmpty && workout.session == nil {
                    Menu {
                        ForEach(templates) { template in
                            Button(template.name) { workout.start(template: template) }
                        }
                        Divider()
                        Button("Empty Workout") { workout.start(template: nil) }
                    } label: {
                        Text("Choose")
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
            if let session = workout.session {
                Text(session.name).font(.title3.weight(.semibold))
                HStack(spacing: 4) {
                    Text("\(session.completedSetCount) of \(session.totalSetCount) sets ·")
                    Text(session.startedAt, style: .timer).monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if Date().timeIntervalSince(session.startedAt) > 4 * 3600 {
                    FootnoteText(text: "Started \(Format.dateTime(session.startedAt)). Finish or discard it when you're ready.", symbol: "clock")
                }
                Button("Resume") { workout.isPresented = true }
                    .buttonStyle(PrimaryButtonStyle(tint: Metric.training.color))
            } else if !sessionsToday.isEmpty {
                ForEach(sessionsToday) { session in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Metric.steps.color)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.name).font(.headline)
                            Text("\(Format.durationWords(session.duration)) · \(session.completedSetCount) sets")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Completed \(session.name)")
                }
            } else if let planned = plannedTemplate {
                VStack(alignment: .leading, spacing: 2) {
                    Text(planned.name).font(.title3.weight(.semibold))
                    Text("\(planned.exercises.count) exercises · \(planned.totalSets) sets")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button("Start \(planned.name)") { workout.start(template: planned) }
                    .buttonStyle(PrimaryButtonStyle(tint: Metric.training.color))
            } else if isTrainingDay {
                Text("Training day — no template assigned.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Start Workout") { workout.start(template: nil) }
                    .buttonStyle(PrimaryButtonStyle(tint: Metric.training.color))
            } else {
                Text(settings.values.trainingDays.isEmpty ? "No workout planned." : "Rest day. Recovery counts too.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Start a Workout Anyway") { workout.start(template: nil) }
                    .buttonStyle(SecondaryButtonStyle(tint: Metric.training.color))
            }
        }
    }

    // MARK: Nutrition

    @ViewBuilder
    private var nutritionCard: some View {
        let totals = foodToday.reduce(Nutrients.zero) { $0 + $1.nutrients }
        let nutritionTargets = targets.nutrition(on: day)
        Button {
            router.selectedTab = .nutrition
        } label: {
            Card {
                CardHeader(title: "Nutrition", symbol: Metric.calories.symbol, tint: Metric.calories.color) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                if foodToday.isEmpty && nutritionTargets.calories == nil && nutritionTargets.protein == nil {
                    Text("Nothing logged yet today.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: Theme.Spacing.l) {
                        ZStack {
                            ProgressRing(progress: nutritionTargets.calories.map { totals.calories / max($0, 1) } ?? 0, color: Metric.calories.color, lineWidth: 8)
                            Image(systemName: Metric.calories.symbol)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Metric.calories.color)
                        }
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(Format.calories(totals.calories))
                                    .font(.metric(.title2))
                                    .numericStyle()
                                    .contentTransition(.numericText(value: totals.calories))
                                Text(nutritionTargets.calories.map { "/ \(Format.calories($0)) kcal" } ?? "kcal")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let remaining = nutritionTargets.calories.map({ $0 - totals.calories }) {
                                Text(remaining >= 0 ? "\(Format.calories(remaining)) left" : "\(Format.calories(-remaining)) over")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    MacroRow(metric: .protein, value: totals.protein, target: nutritionTargets.protein)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Opens Nutrition")
    }

    // MARK: Routines

    @ViewBuilder
    private func routinesCard(signals: [DayKey: DaySignals]) -> some View {
        let due = activeRoutines.filter { $0.evaluator(signals: signals).isDue(on: day) }
        if !due.isEmpty {
            Card {
                CardHeader(title: "Routines", symbol: Metric.routines.symbol, tint: Metric.routines.color) {
                    NavigationLink(value: TodayDestination.routines) {
                        Text("Manage").font(.subheadline.weight(.medium))
                    }
                }
                VStack(spacing: 0) {
                    ForEach(due) { routine in
                        RoutineCheckRow(
                            routine: routine,
                            day: day,
                            completion: routine.evaluator(signals: signals).completion(on: day)
                        ) {
                            RoutineActions.toggle(routine, on: day, in: context)
                        }
                        if routine.id != due.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }
        } else if activeRoutines.isEmpty && !isNewUser {
            NavigationLink(value: TodayDestination.routines) {
                HStack {
                    Label("Add a routine", systemImage: "checklist")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(Theme.Spacing.l)
                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: Steps

    @ViewBuilder
    private func stepsCard(stepDays: [StepDay]) -> some View {
        let today = stepDays.first { $0.day == day }
        let target = targets.value(.steps, on: day)
        NavigationLink(value: TodayDestination.steps) {
            Card {
                CardHeader(title: "Steps", symbol: Metric.steps.symbol, tint: Metric.steps.color) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                if let today {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(Format.steps(today.steps))
                                .font(.metric(.title2))
                                .numericStyle()
                                .contentTransition(.numericText(value: Double(today.steps)))
                            if let target {
                                Text("/ \(Format.steps(Int(target)))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if today.source == .manual { TagBadge(text: "Manual") }
                            if let target, Double(today.steps) >= target {
                                TagBadge(text: "Target reached", symbol: "checkmark", tint: Metric.steps.color)
                            }
                        }
                        if let target {
                            CapsuleProgress(progress: Double(today.steps) / max(target, 1), color: Metric.steps.color)
                        }
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    stepsEmptyState
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder
    private var stepsEmptyState: some View {
        switch health.status {
        case .notConnected:
            Text(settings.values.manualStepsEnabled ? "No steps logged today. Connect Apple Health or add them manually." : "Connect Apple Health to see today's steps.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .unavailable:
            Text(settings.values.manualStepsEnabled ? "No steps logged today." : "Turn on manual steps in Settings to track them here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .connected:
            Text(health.hasLoadedSteps ? "No step data for today yet." : "Loading…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Weight

    @ViewBuilder
    private var weightCard: some View {
        let unit = settings.unit
        if let latest = weights.first {
            let points = WeightTrend.compute(weights.prefix(120).map { WeightSample(date: $0.measuredAt, kilograms: $0.kilograms) })
            let summary = WeightTrendSummary(points: points, today: day)
            let recent = points.filter { $0.day >= day.adding(days: -29) }
            Card {
                CardHeader(title: "Weight", symbol: Metric.weight.symbol, tint: Metric.weight.color) {
                    Button {
                        router.show(.logWeight)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Metric.weight.color)
                            .frame(width: Theme.target, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Log weight")
                }
                NavigationLink(value: TodayDestination.weight) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(Format.weightValue(latest.kilograms, unit: unit))
                                        .font(.metric(.title2))
                                        .numericStyle()
                                        .contentTransition(.numericText(value: latest.kilograms))
                                    Text(unit.symbol)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(Format.relative(latest.measuredAt))\(summary.latestTrendKg.map { " · trend \(Format.weight($0, unit: unit))" } ?? "")")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if recent.count >= 2 {
                                WeightSparkline(points: recent, unit: unit)
                                    .frame(width: 110, height: 44)
                            }
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        Text(summary.sentence(unit: unit))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityHint("Opens weight history")
            }
        } else if !isNewUser {
            EmptyStateCard(
                symbol: Metric.weight.symbol,
                title: "No weigh-ins yet",
                message: "Log your weight a few times a week to see a smoothed trend that filters out daily noise.",
                tint: Metric.weight.color,
                actionTitle: "Log Weight"
            ) {
                router.show(.logWeight)
            }
        }
    }
}

// MARK: - Getting started

private struct GettingStartedCard: View {
    let healthAvailable: Bool
    let healthConnected: Bool
    let hasTargets: Bool
    let hasTemplates: Bool
    let hasRoutines: Bool
    let setTargets: () -> Void

    @Environment(AppRouter.self) private var router
    @Environment(HealthService.self) private var health
    @Environment(\.modelContext) private var context

    var body: some View {
        Card {
            CardHeader(title: "Get started", symbol: "sparkles", tint: Theme.Palette.accent)
            Text("A few quick steps to make Today useful. Do them in any order — or skip them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                step("Log your weight", symbol: "scalemass", done: false) { router.show(.logWeight) }
                step("Set calorie and protein targets", symbol: "target", done: hasTargets, action: setTargets)
                step("Create a workout template", symbol: "dumbbell", done: hasTemplates) { router.selectedTab = .training }
                if healthAvailable {
                    step("Connect Apple Health", symbol: "heart", done: healthConnected) {
                        Task {
                            await health.connect()
                            await health.refreshSteps(force: true)
                            await health.importWeights(into: context)
                        }
                    }
                }
            }
        }
    }

    private func step(_ title: String, symbol: String, done: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: done ? "checkmark.circle.fill" : symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(done ? Metric.steps.color : Theme.Palette.accent)
                    .frame(width: 28)
                Text(title)
                    .foregroundStyle(done ? .secondary : .primary)
                    .strikethrough(done)
                Spacer()
                if !done {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minHeight: Theme.target)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(done)
        .accessibilityValue(done ? "Done" : "")
    }
}
