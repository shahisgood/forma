import SwiftUI
import SwiftData
import FormaKit

/// Shared helper that computes signals for linked routines.
@MainActor
struct RoutineContext {
    let signals: [DayKey: DaySignals]

    static func make(for week: WeekInterval, context: ModelContext, health: HealthService, settings: AppSettings, targetRecords: [TargetRecord]) -> RoutineContext {
        let manual = (try? context.fetch(FetchDescriptor<ManualStepEntry>())) ?? []
        let steps = StepHistory.days(health: health, manualEntries: manual, manualEnabled: settings.values.manualStepsEnabled)
        let signals = ActivitySignals.build(
            from: week.start,
            through: week.end,
            context: context,
            stepDays: steps,
            targets: TargetStore.timeline(targetRecords)
        )
        return RoutineContext(signals: signals)
    }
}

enum RoutineActions {
    @MainActor
    static func toggle(_ routine: Routine, on day: DayKey, in context: ModelContext) {
        let key = day.string
        if let existing = routine.completions.first(where: { $0.dayKey == key }) {
            routine.completions.removeAll { $0.id == existing.id }
            context.delete(existing)
            Haptics.selection()
        } else {
            routine.completions.append(RoutineCompletion(day: day))
            Haptics.success()
        }
        try? context.save()
    }
}

/// A routine row with a large check-off control.
struct RoutineCheckRow: View {
    let routine: Routine
    let day: DayKey
    let completion: RoutineCompletionKind?
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: routine.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Metric.routines.color)
                .frame(width: 32, height: 32)
                .background(Metric.routines.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(routine.name)
                    .font(.body)
                    .strikethrough(completion != nil, color: .secondary)
                    .foregroundStyle(completion != nil ? .secondary : .primary)
                if case .automatic(let link) = completion {
                    Text("Done · \(link.shortLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if routine.schedule.kind == .timesPerWeek {
                    Text(routine.schedule.summary())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onToggle) {
                Image(systemName: completion != nil ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(completion != nil ? Metric.routines.color : Color.secondary.opacity(0.6))
                    .frame(width: Theme.target, height: Theme.target)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            .disabled(isAutomatic)
            .accessibilityLabel(completion != nil ? "\(routine.name), done" : "Mark \(routine.name) done")
            .accessibilityHint(isAutomatic ? "Completed automatically from your logged activity" : "")
        }
        .motion(Motion.quick, value: completion != nil)
    }

    private var isAutomatic: Bool {
        if case .automatic = completion { return true }
        return false
    }
}

// MARK: - Manage routines

struct RoutinesView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Environment(AppSettings.self) private var settings
    @Environment(DayClock.self) private var clock
    @Query(sort: \Routine.position) private var routines: [Routine]
    @Query private var targetRecords: [TargetRecord]
    @State private var editing: RoutineEditorTarget?

    private var active: [Routine] { routines.filter { !$0.isArchived } }
    private var archived: [Routine] { routines.filter(\.isArchived) }

    var body: some View {
        let week = WeekInterval(containing: clock.today)
        let routineContext = RoutineContext.make(for: week, context: context, health: health, settings: settings, targetRecords: targetRecords)

        List {
            if active.isEmpty {
                Section {
                    Text("Routines are small habits that support your training — like prepping meals or a short walk. Keep them few.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Suggestions")
                }
                Section {
                    ForEach(RoutineSuggestion.all) { suggestion in
                        Button {
                            add(suggestion)
                        } label: {
                            HStack {
                                Label(suggestion.name, systemImage: suggestion.symbol)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Metric.routines.color)
                            }
                        }
                        .accessibilityLabel("Add \(suggestion.name)")
                    }
                }
            } else {
                Section {
                    ForEach(active) { routine in
                        Button {
                            editing = RoutineEditorTarget(routine: routine)
                        } label: {
                            RoutineSummaryRow(
                                routine: routine,
                                week: week,
                                today: clock.today,
                                evaluator: routine.evaluator(signals: routineContext.signals)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove(perform: move)
                } header: {
                    Text("This week")
                } footer: {
                    Text("Linked routines complete themselves when the matching activity is logged.")
                }
            }

            if !archived.isEmpty {
                Section("Archived") {
                    ForEach(archived) { routine in
                        HStack {
                            Label(routine.name, systemImage: routine.symbol)
                            Spacer()
                            Button("Restore") {
                                routine.archivedDayKey = nil
                                try? context.save()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(archived[index]) }
                        try? context.save()
                    }
                }
            }
        }
        .navigationTitle("Routines")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = RoutineEditorTarget(routine: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New routine")
            }
            if active.count > 1 {
                ToolbarItem(placement: .secondaryAction) {
                    EditButton()
                }
            }
        }
        .sheet(item: $editing) { target in
            RoutineEditorView(routine: target.routine)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = active
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, routine) in ordered.enumerated() { routine.position = index }
        try? context.save()
    }

    private func add(_ suggestion: RoutineSuggestion) {
        let routine = Routine(
            name: suggestion.name,
            symbol: suggestion.symbol,
            schedule: suggestion.schedule,
            link: suggestion.link,
            position: routines.count
        )
        context.insert(routine)
        try? context.save()
        Haptics.success()
    }
}

struct RoutineEditorTarget: Identifiable {
    let id = UUID()
    let routine: Routine?
}

struct RoutineSuggestion: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let schedule: RoutineSchedule
    let link: RoutineLink

    static let all: [RoutineSuggestion] = [
        RoutineSuggestion(id: "prep", name: "Prepare tomorrow's meals", symbol: "takeoutbag.and.cup.and.straw", schedule: RoutineSchedule(kind: .weekdays, weekdays: [1, 3]), link: .none),
        RoutineSuggestion(id: "workout", name: "Complete a workout", symbol: "dumbbell", schedule: RoutineSchedule(kind: .timesPerWeek, timesPerWeek: 3), link: .workoutCompleted),
        RoutineSuggestion(id: "walk", name: "Take a walk", symbol: "figure.walk", schedule: .daily, link: .none),
        RoutineSuggestion(id: "mobility", name: "Mobility work", symbol: "figure.flexibility", schedule: RoutineSchedule(kind: .timesPerWeek, timesPerWeek: 3), link: .none),
        RoutineSuggestion(id: "winddown", name: "Start a wind-down routine", symbol: "moon.zzz", schedule: .daily, link: .none),
        RoutineSuggestion(id: "log", name: "Log what I eat", symbol: "fork.knife", schedule: .daily, link: .foodLogged)
    ]
}

/// Name, schedule and a 7-day strip showing this week's check-ins.
struct RoutineSummaryRow: View {
    let routine: Routine
    let week: WeekInterval
    let today: DayKey
    let evaluator: RoutineEvaluator

    var body: some View {
        let consistency = evaluator.consistency(for: week, today: today)
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Label(routine.name, systemImage: routine.symbol)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(consistency.completed)/\(consistency.expected)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .numericStyle()
            }
            HStack(spacing: 6) {
                ForEach(week.days(), id: \.self) { day in
                    WeekDayDot(state: state(for: day), label: day.middayDate().formatted(.dateTime.weekday(.narrow)))
                }
                Spacer()
                Text(routine.schedule.summary())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if routine.link != .none {
                Text(routine.link.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(consistency.completed) of \(consistency.expected) this week")
        .accessibilityHint("Edit routine")
    }

    private func state(for day: DayKey) -> WeekDayDot.State {
        if evaluator.completion(on: day) != nil { return .done }
        if day > today { return .upcoming }
        if day < routine.createdDay { return .notScheduled }
        if routine.schedule.kind == .timesPerWeek { return .flexible }
        return routine.schedule.isPinned(to: day) ? .missed : .notScheduled
    }
}

/// Day indicator that uses symbols, not just colour.
struct WeekDayDot: View {
    enum State { case done, missed, upcoming, flexible, notScheduled }

    let state: State
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch state {
        case .done: return "checkmark.circle.fill"
        case .missed: return "circle"
        case .upcoming: return "circle.dotted"
        case .flexible: return "circle.dashed"
        case .notScheduled: return "minus"
        }
    }

    private var color: Color {
        switch state {
        case .done: return Metric.routines.color
        case .missed: return .secondary
        case .upcoming, .flexible, .notScheduled: return Color.secondary.opacity(0.5)
        }
    }
}

// MARK: - Editor

struct RoutineEditorView: View {
    let routine: Routine?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(NotificationService.self) private var notifications
    @Environment(AppSettings.self) private var settings
    @Query private var allRoutines: [Routine]

    @State private var name = ""
    @State private var symbol = "checkmark.circle"
    @State private var kind: RoutineSchedule.Kind = .daily
    @State private var weekdays: Set<Int> = []
    @State private var timesPerWeek = 3
    @State private var link: RoutineLink = .none
    @State private var reminderEnabled = false
    @State private var reminderTime = Date()
    @State private var confirmDelete = false

    private let symbols = ["checkmark.circle", "figure.walk", "figure.flexibility", "takeoutbag.and.cup.and.straw", "moon.zzz", "drop", "fork.knife", "dumbbell", "book", "bed.double", "sun.max", "leaf"]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (kind != .weekdays || !weekdays.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.s) {
                            ForEach(symbols, id: \.self) { item in
                                Button {
                                    symbol = item
                                    Haptics.selection()
                                } label: {
                                    Image(systemName: item)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(symbol == item ? .white : Metric.routines.color)
                                        .frame(width: 40, height: 40)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(symbol == item ? Metric.routines.color : Metric.routines.color.opacity(0.12))
                                        )
                                }
                                .buttonStyle(PressableStyle(scale: 0.92))
                                .accessibilityLabel(item.replacingOccurrences(of: ".", with: " "))
                                .accessibilityAddTraits(symbol == item ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Schedule") {
                    Picker("Repeats", selection: $kind) {
                        Text("Every day").tag(RoutineSchedule.Kind.daily)
                        Text("Specific days").tag(RoutineSchedule.Kind.weekdays)
                        Text("Times per week").tag(RoutineSchedule.Kind.timesPerWeek)
                    }
                    switch kind {
                    case .daily:
                        EmptyView()
                    case .weekdays:
                        WeekdayPicker(selection: $weekdays, tint: Metric.routines.color)
                    case .timesPerWeek:
                        Stepper("\(timesPerWeek)× a week, any days", value: $timesPerWeek, in: 1...7)
                    }
                }

                Section {
                    Picker("Complete automatically", selection: $link) {
                        ForEach(RoutineLink.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } footer: {
                    Text("Linked routines tick themselves off when you log the matching activity, so you don't record the same thing twice.")
                }

                Section {
                    Toggle("Reminder", isOn: $reminderEnabled.animation(Motion.standard))
                    if reminderEnabled {
                        DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        if notifications.isDenied {
                            FootnoteText(text: "Notifications are off for Forma in iOS Settings, so this reminder can't be delivered.", symbol: "bell.slash")
                        } else if settings.values.reminders.quietHours.contains(ClockTime(date: reminderTime)) {
                            FootnoteText(text: "This time is inside your quiet hours, so the reminder won't be sent.", symbol: "moon")
                        }
                    }
                } footer: {
                    Text("Reminders are skipped on days the routine is already done.")
                }

                if routine != nil {
                    Section {
                        Button("Archive Routine") {
                            routine?.archivedDayKey = DayKey.today().string
                            try? context.save()
                            dismiss()
                        }
                        Button("Delete Routine", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Archiving hides the routine but keeps its history.")
                    }
                }
            }
            .navigationTitle(routine == nil ? "New Routine" : "Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this routine and its history?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let routine { context.delete(routine) }
                    try? context.save()
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let routine else { return }
        name = routine.name
        symbol = routine.symbol
        kind = routine.schedule.kind
        weekdays = routine.schedule.weekdays
        timesPerWeek = routine.schedule.timesPerWeek
        link = routine.link
        reminderEnabled = routine.reminderEnabled
        reminderTime = routine.reminderTime.date(on: .today()) ?? Date()
    }

    private func save() {
        let schedule = RoutineSchedule(kind: kind, weekdays: weekdays, timesPerWeek: timesPerWeek)
        let target: Routine
        if let routine {
            target = routine
            routine.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            routine.symbol = symbol
            routine.schedule = schedule
            routine.link = link
        } else {
            target = Routine(name: name.trimmingCharacters(in: .whitespacesAndNewlines), symbol: symbol, schedule: schedule, link: link, position: allRoutines.count)
            context.insert(target)
        }
        target.reminderEnabled = reminderEnabled
        target.reminderTime = ClockTime(date: reminderTime)
        try? context.save()
        Haptics.success()
        if reminderEnabled {
            Task { await notifications.requestAuthorizationIfNeeded() }
        }
        dismiss()
    }
}
