import SwiftUI
import SwiftData
import FormaKit

struct TrainingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(WorkoutController.self) private var workout
    @Environment(DayClock.self) private var clock
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\WorkoutTemplate.position), SortDescriptor(\WorkoutTemplate.createdAt)]) private var templates: [WorkoutTemplate]
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }, sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    @State private var editingTemplate: TemplateEditorTarget?
    @State private var confirmDelete: WorkoutTemplate?

    private var plannedTemplate: WorkoutTemplate? {
        let weekday = clock.today.weekday()
        guard let id = settings.values.templateForWeekday[weekday] else { return nil }
        return templates.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    startCard
                    templatesSection
                    historySection
                    librarySection
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .background(Theme.Palette.background)
            .navigationTitle("Training")
            .navigationDestination(for: WorkoutTemplate.self) { TemplateDetailView(template: $0) }
            .navigationDestination(for: WorkoutSession.self) { SessionDetailView(session: $0) }
            .navigationDestination(for: Exercise.self) { ExerciseDetailView(exercise: $0) }
            .settingsToolbarButton(router)
            .workoutResumeAccessory()
            .sheet(item: $editingTemplate) { target in
                TemplateEditorView(template: target.template)
            }
            .confirmationDialog(
                "Delete \(confirmDelete?.name ?? "template")?",
                isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete Template", role: .destructive) {
                    if let template = confirmDelete { delete(template) }
                }
            } message: {
                Text("Workouts you've already done with it are kept.")
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var startCard: some View {
        if let session = workout.session {
            Card {
                CardHeader(title: "In progress", symbol: "timer", tint: Metric.training.color)
                Text(session.name).font(.title2.weight(.semibold))
                HStack(spacing: 4) {
                    Text("\(session.completedSetCount) of \(session.totalSetCount) sets ·")
                    Text(session.startedAt, style: .timer).monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Button("Resume Workout") { workout.isPresented = true }
                    .buttonStyle(PrimaryButtonStyle(tint: Metric.training.color))
            }
        } else if let planned = plannedTemplate {
            Card {
                CardHeader(title: "Planned for today", symbol: "calendar", tint: Metric.training.color)
                Text(planned.name).font(.title2.weight(.semibold))
                Text(exerciseSummary(planned))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button("Start \(planned.name)") { workout.start(template: planned) }
                    .buttonStyle(PrimaryButtonStyle(tint: Metric.training.color))
                Button("Start Empty Workout") { workout.start(template: nil) }
                    .buttonStyle(SecondaryButtonStyle(tint: Metric.training.color))
            }
        } else {
            HStack(spacing: Theme.Spacing.s) {
                QuickActionButton(title: "Empty Workout", symbol: "play.fill", tint: Metric.training.color) {
                    workout.start(template: nil)
                }
                QuickActionButton(title: "New Template", symbol: "plus.rectangle.on.rectangle", tint: Theme.Palette.accent) {
                    editingTemplate = TemplateEditorTarget(template: nil)
                }
            }
        }
    }

    @ViewBuilder
    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                SectionTitle(title: "Templates")
                Button {
                    editingTemplate = TemplateEditorTarget(template: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(CircleIconButtonStyle(size: 34))
                .accessibilityLabel("New template")
            }
            if templates.isEmpty {
                EmptyStateCard(
                    symbol: "list.bullet.rectangle",
                    title: "Build your first template",
                    message: "Save the exercises, sets and rep ranges you usually do. Starting a workout from a template prefills everything, including what you lifted last time.",
                    tint: Metric.training.color,
                    actionTitle: "Create Template"
                ) {
                    editingTemplate = TemplateEditorTarget(template: nil)
                }
            } else {
                ForEach(templates) { template in
                    NavigationLink(value: template) {
                        TemplateCard(
                            template: template,
                            weekdays: weekdays(for: template),
                            lastDone: sessions.first { $0.templateID == template.id }?.startedAt
                        )
                    }
                    .buttonStyle(PressableStyle())
                    .contextMenu {
                        Button {
                            workout.start(template: template)
                        } label: {
                            Label("Start Workout", systemImage: "play.fill")
                        }
                        Button {
                            editingTemplate = TemplateEditorTarget(template: template)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button {
                            TemplateActions.duplicate(template, in: context)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        Button(role: .destructive) {
                            confirmDelete = template
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                SectionTitle(title: "History")
                if !sessions.isEmpty {
                    NavigationLink("See All") { WorkoutHistoryView() }
                        .font(.subheadline.weight(.medium))
                }
            }
            if sessions.isEmpty {
                Text("Finished workouts will show up here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sessions.prefix(4))) { session in
                        NavigationLink(value: session) {
                            SessionRow(session: session)
                                .padding(.horizontal, Theme.Spacing.l)
                                .padding(.vertical, Theme.Spacing.m)
                        }
                        .buttonStyle(PressableStyle(scale: 0.99))
                        if session.id != sessions.prefix(4).last?.id {
                            Divider().padding(.leading, Theme.Spacing.l)
                        }
                    }
                }
                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
        }
    }

    private var librarySection: some View {
        NavigationLink {
            ExerciseLibraryView()
        } label: {
            HStack {
                Label("Exercise Library", systemImage: "books.vertical")
                    .font(.body.weight(.medium))
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

    // MARK: Helpers

    private func weekdays(for template: WorkoutTemplate) -> [Int] {
        settings.values.templateForWeekday.filter { $0.value == template.id }.map(\.key)
    }

    private func exerciseSummary(_ template: WorkoutTemplate) -> String {
        let names = template.orderedExercises.compactMap { $0.exercise?.name }
        if names.isEmpty { return "No exercises yet" }
        return names.joined(separator: " · ")
    }

    private func delete(_ template: WorkoutTemplate) {
        let id = template.id
        settings.update { values in
            values.templateForWeekday = values.templateForWeekday.filter { $0.value != id }
        }
        context.delete(template)
        try? context.save()
    }
}

struct TemplateEditorTarget: Identifiable {
    let id = UUID()
    let template: WorkoutTemplate?
}

enum TemplateActions {
    @MainActor
    static func duplicate(_ template: WorkoutTemplate, in context: ModelContext) {
        let copy = WorkoutTemplate(name: "\(template.name) Copy", position: template.position + 1)
        copy.notes = template.notes
        context.insert(copy)
        for item in template.orderedExercises {
            guard let exercise = item.exercise else { continue }
            let newItem = TemplateExercise(exercise: exercise, position: item.position, targetSets: item.targetSets, repLow: item.repLow, repHigh: item.repHigh)
            newItem.warmupSets = item.warmupSets
            newItem.restSeconds = item.restSeconds
            newItem.notes = item.notes
            copy.exercises.append(newItem)
        }
        try? context.save()
        Haptics.success()
    }

    /// Creates a template from a completed session's exercises and set counts.
    @MainActor
    @discardableResult
    static func makeTemplate(from session: WorkoutSession, in context: ModelContext) -> WorkoutTemplate {
        let template = WorkoutTemplate(name: session.name, position: 0)
        context.insert(template)
        for (index, entry) in session.orderedExercises.enumerated() {
            guard let exercise = entry.exercise else { continue }
            let working = entry.sets.filter { $0.kind == .working }
            let reps = working.compactMap(\.reps)
            let item = TemplateExercise(
                exercise: exercise,
                position: index,
                targetSets: max(1, working.count),
                repLow: reps.min() ?? entry.targetRepLow,
                repHigh: reps.max() ?? entry.targetRepHigh
            )
            item.warmupSets = entry.sets.filter { $0.kind == .warmup }.count
            item.restSeconds = entry.restSeconds
            template.exercises.append(item)
        }
        try? context.save()
        return template
    }
}

struct TemplateCard: View {
    let template: WorkoutTemplate
    let weekdays: [Int]
    let lastDone: Date?

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(template.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if !weekdays.isEmpty {
                    let symbols = Calendar.current.shortWeekdaySymbols
                    let ordered = Weekdays.ordered().filter { weekdays.contains($0) }
                    Text(ordered.map { symbols[$0 - 1] }.joined(separator: " · "))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Metric.training.color)
                }
            }
            let names = template.orderedExercises.compactMap { $0.exercise?.name }
            Text(names.isEmpty ? "No exercises yet" : names.prefix(4).joined(separator: ", ") + (names.count > 4 ? " +\(names.count - 4)" : ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: Theme.Spacing.m) {
                Label("\(template.exercises.count) exercises", systemImage: "list.bullet")
                Label("\(template.totalSets) sets", systemImage: "square.stack.3d.up")
                Spacer()
                if let lastDone {
                    Text(Format.relative(lastDone))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text("\(Format.longDay(session.startedAt)) · \(Format.durationWords(session.duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(session.completedSetCount) sets")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
