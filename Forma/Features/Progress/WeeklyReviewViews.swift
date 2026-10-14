import SwiftUI
import SwiftData
import FormaKit

/// Collects a week's data from the store and hands it to `WeeklyReview`.
@MainActor
enum WeeklyReviewBuilder {
    static func build(week: WeekInterval, today: DayKey, context: ModelContext, settings: AppSettings, health: HealthService) -> WeeklyReview {
        let start = week.start.startDate()
        let end = week.end.adding(days: 1).startDate()

        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.endedAt != nil && $0.startedAt >= start && $0.startedAt < end }
        ))) ?? []
        var highlights: [StrengthHighlight] = []
        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            for entry in session.orderedExercises {
                guard let exercise = entry.exercise else { continue }
                let prior = exercise.completedSetRecords(excludingSession: session.id).filter { $0.date < session.startedAt }
                let new = entry.completedRecords(sessionID: session.id, fallbackDate: session.startedAt)
                for record in PersonalRecords.detect(newSets: new, history: prior, trackingType: entry.trackingType) {
                    highlights.append(StrengthHighlight(exerciseName: entry.exerciseName, trackingType: entry.trackingType, record: record, date: session.startedAt))
                }
            }
        }
        // One highlight per exercise, preferring estimated-max records.
        var seen = Set<String>()
        let priority: [PersonalRecordKind] = [.estimatedOneRepMax, .heaviestWeight, .repsAtWeight, .mostReps, .longestDuration, .longestDistance]
        let distinctHighlights = highlights
            .sorted { (priority.firstIndex(of: $0.record.kind) ?? 9) < (priority.firstIndex(of: $1.record.kind) ?? 9) }
            .filter { seen.insert($0.exerciseName).inserted }

        let targetRecords = (try? context.fetch(FetchDescriptor<TargetRecord>())) ?? []
        let targets = TargetStore.timeline(targetRecords)

        let keys = week.days().map(\.string)
        let food = (try? context.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate<FoodEntry> { keys.contains($0.dayKey) }))) ?? []
        let grouped = Dictionary(grouping: food, by: \.dayKey)
        let nutritionDays = week.days().map { day in
            let entries = grouped[day.string] ?? []
            return DayNutritionSummary(
                day: day,
                totals: entries.reduce(Nutrients.zero) { $0 + $1.nutrients },
                entryCount: entries.count,
                targets: targets.nutrition(on: day)
            )
        }

        let weights = (try? context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.measuredAt)]))) ?? []
        let points = WeightTrend.compute(weights.map { WeightSample(date: $0.measuredAt, kilograms: $0.kilograms) })
        let weighIns = weights.filter { week.contains(DayKey($0.measuredAt)) }.count

        let manual = (try? context.fetch(FetchDescriptor<ManualStepEntry>())) ?? []
        let stepDays = StepHistory.days(health: health, manualEntries: manual, manualEnabled: settings.values.manualStepsEnabled)

        let signals = ActivitySignals.build(from: week.start, through: week.end, context: context, stepDays: stepDays, targets: targets)
        let routines = ((try? context.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.position)]))) ?? [])
        let routineResults = routines.compactMap { routine -> RoutineWeekResult? in
            let result = routine.evaluator(signals: signals).consistency(for: week, today: today)
            guard result.expected > 0 else { return nil }
            return RoutineWeekResult(name: routine.name, completed: result.completed, expected: result.expected)
        }

        let input = WeeklyReviewInput(
            week: week,
            today: today,
            unit: settings.unit,
            plannedWorkouts: settings.values.trainingDays.isEmpty ? nil : settings.values.trainingDays.count,
            completedWorkouts: sessions.count,
            trainingMinutes: Int(sessions.reduce(0) { $0 + $1.duration } / 60),
            strengthHighlights: distinctHighlights,
            nutritionDays: nutritionDays,
            weightPoints: points,
            weighInCount: weighIns,
            stepDays: stepDays,
            stepTargets: targets,
            routines: routineResults
        )
        return WeeklyReview(input)
    }
}

struct WeeklyReviewView: View {
    let week: WeekInterval

    @Environment(AppSettings.self) private var settings
    @Environment(HealthService.self) private var health
    @Environment(DayClock.self) private var clock
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var notes: [WeeklyReviewNote]

    @State private var decision: ReviewDecision?
    @State private var noteText = ""
    @State private var showingTargets = false
    @State private var showingSchedule = false
    @State private var showingStepTarget = false

    init(week: WeekInterval) {
        self.week = week
        let key = week.start.string
        _notes = Query(filter: #Predicate<WeeklyReviewNote> { $0.weekStartKey == key })
    }

    var body: some View {
        let review = WeeklyReviewBuilder.build(week: week, today: clock.today, context: context, settings: settings, health: health)

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Format.weekRange(week))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(review.isWeekComplete ? "Your week in review" : "This week so far")
                        .font(.largeTitle.weight(.bold))
                    Text("A summary of what you logged. Days without entries are described as missing, not as misses.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !review.hasAnyData {
                    EmptyStateCard(
                        symbol: "calendar.badge.exclamationmark",
                        title: "Nothing logged this week",
                        message: "Once you log workouts, food, weight or routines, they'll be summarised here."
                    )
                }

                ForEach(review.sections) { section in
                    ReviewSectionCard(section: section)
                }

                nextStep
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(Theme.Palette.background)
        .navigationTitle("Weekly Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showingTargets) { NutritionTargetsView() }
        .sheet(isPresented: $showingSchedule) { TrainingScheduleSheet() }
        .sheet(isPresented: $showingStepTarget) { StepTargetSheet() }
        .onAppear {
            if let note = notes.first {
                decision = note.decision
                noteText = note.note
            }
        }
    }

    @ViewBuilder
    private var nextStep: some View {
        Card {
            CardHeader(title: "Next week", symbol: "arrow.right.circle", tint: Theme.Palette.accent)
            Text("Keep things as they are, or make a small adjustment.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: Theme.Spacing.s) {
                ForEach(ReviewDecision.allCases) { option in
                    Button {
                        Haptics.selection()
                        Motion.perform { decision = option }
                        saveDecision()
                    } label: {
                        Text(option.title)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(decision == option ? .white : Theme.Palette.accent)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                    .fill(decision == option ? Theme.Palette.accent : Theme.Palette.accent.opacity(0.12))
                            )
                    }
                    .buttonStyle(PressableStyle(scale: 0.97))
                    .accessibilityAddTraits(decision == option ? .isSelected : [])
                }
            }
            if decision == .adjust {
                VStack(spacing: 0) {
                    adjustRow("Training days", symbol: "calendar") { showingSchedule = true }
                    Divider()
                    adjustRow("Nutrition targets", symbol: "target") { showingTargets = true }
                    Divider()
                    adjustRow("Step target", symbol: "figure.walk") { showingStepTarget = true }
                    Divider()
                    NavigationLink {
                        RoutinesView()
                    } label: {
                        adjustLabel("Routines", symbol: "checklist")
                    }
                    .buttonStyle(.plain)
                }
                .transition(.lift)
            }
            if decision != nil {
                TextField("Note to self (optional)", text: $noteText, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(Theme.Spacing.m)
                    .background(Theme.Palette.fill, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .onSubmit(saveDecision)
                    .onChange(of: noteText) { _, _ in saveDecision() }
            }
        }
        .motion(Motion.standard, value: decision)
    }

    private func adjustRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            adjustLabel(title, symbol: symbol)
        }
        .buttonStyle(.plain)
    }

    private func adjustLabel(_ title: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: Theme.target)
        .contentShape(Rectangle())
    }

    private func saveDecision() {
        guard let decision else { return }
        if let existing = notes.first {
            existing.decision = decision
            existing.note = noteText
        } else {
            context.insert(WeeklyReviewNote(weekStart: week.start, decision: decision, note: noteText))
        }
        try? context.save()
    }
}

struct ReviewSectionCard: View {
    let section: WeeklyReviewSection

    private var metric: Metric {
        switch section.kind {
        case .training: return .training
        case .strength: return .training
        case .nutrition: return .calories
        case .weight: return .weight
        case .steps: return .steps
        case .routines: return .routines
        }
    }

    private var title: String {
        switch section.kind {
        case .training: return "Training"
        case .strength: return "Strength"
        case .nutrition: return "Nutrition"
        case .weight: return "Weight"
        case .steps: return "Steps"
        case .routines: return "Routines"
        }
    }

    var body: some View {
        Card {
            CardHeader(title: title, symbol: section.kind == .strength ? "trophy" : metric.symbol, tint: section.kind == .strength ? Theme.Palette.record : metric.color) {
                coverageTag
            }
            Text(section.headline)
                .font(.headline)
            if let ratio = section.ratio {
                CapsuleProgress(progress: ratio, color: metric.color, height: 6)
            }
            ForEach(section.details, id: \.self) { detail in
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var coverageTag: some View {
        switch section.coverage {
        case .none: TagBadge(text: "No data", tint: .secondary)
        case .partial: TagBadge(text: "Partial", tint: .secondary)
        case .good: EmptyView()
        }
    }
}

/// Card on Today linking to last week's review.
struct WeeklyReviewLinkCard: View {
    let today: DayKey

    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(HealthService.self) private var health
    @Environment(\.modelContext) private var context

    var body: some View {
        let lastWeek = WeekInterval(containing: today).previous()
        if settings.values.dismissedReviewWeek != lastWeek.start.string {
            let review = WeeklyReviewBuilder.build(week: lastWeek, today: today, context: context, settings: settings, health: health)
            if review.hasAnyData {
                HStack(spacing: Theme.Spacing.m) {
                    Button {
                        router.show(.weeklyReview(weekStart: lastWeek.start))
                    } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Theme.Palette.accent)
                                .frame(width: 40, height: 40)
                                .background(Theme.Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Last week in review")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(Format.weekRange(lastWeek))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    Button {
                        Motion.perform {
                            settings.update { $0.dismissedReviewWeek = lastWeek.start.string }
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: Theme.target, height: Theme.target)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hide weekly review card")
                }
                .padding(.leading, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .transition(.lift)
            }
        }
    }
}
