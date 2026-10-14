import SwiftUI
import SwiftData
import FormaKit

struct WorkoutHistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }, sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    private var grouped: [(month: Date, sessions: [WorkoutSession])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: sessions) { session in
            calendar.date(from: calendar.dateComponents([.year, .month], from: session.startedAt)) ?? session.startedAt
        }
        return groups.keys.sorted(by: >).map { (month: $0, sessions: groups[$0] ?? []) }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.month) { group in
                Section {
                    ForEach(group.sessions) { session in
                        NavigationLink(value: session) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.name).font(.body.weight(.medium))
                                Text("\(Format.longDay(session.startedAt)) · \(Format.durationWords(session.duration)) · \(session.completedSetCount) sets")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let targets = offsets.map { group.sessions[$0] }
                        Task { @MainActor in
                            for session in targets {
                                await health.deleteWrittenWorkout(session)
                                context.delete(session)
                            }
                            try? context.save()
                        }
                    }
                } header: {
                    HStack {
                        Text(group.month.formatted(.dateTime.month(.wide).year()))
                        Spacer()
                        Text("\(group.sessions.count) workout\(group.sessions.count == 1 ? "" : "s")")
                    }
                }
            }
        }
        .navigationTitle("History")
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView("No Workouts Yet", systemImage: "dumbbell", description: Text("Finished workouts appear here."))
            }
        }
    }
}

struct SessionDetailView: View {
    let session: WorkoutSession

    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutController.self) private var workout
    @Environment(HealthService.self) private var health
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var savedTemplate = false

    private var unit: WeightUnit { settings.unit }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text(Format.longDay(session.startedAt))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .top) {
                        StatValue(value: Format.durationWords(session.duration), label: "Duration", size: .metric(.title3))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        StatValue(value: "\(session.completedSetCount)", label: "Sets", size: .metric(.title3))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        StatValue(value: "\(session.exercises.count)", label: "Exercises", size: .metric(.title3))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let end = session.endedAt {
                        Text("\(Format.time(session.startedAt)) – \(Format.time(end))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if session.healthWorkoutUUID != nil {
                        TagBadge(text: "Saved to Apple Health", symbol: "heart.fill", tint: .pink)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }

            ForEach(session.orderedExercises) { entry in
                Section {
                    ForEach(entry.orderedSets) { set in
                        HStack {
                            Text(set.kind == .warmup ? "W" : "\(workingIndex(of: set, in: entry))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(set.kind == .warmup ? Color.orange : Color.secondary)
                                .frame(width: 24, alignment: .leading)
                                .accessibilityLabel(set.kind == .warmup ? "Warm-up" : "Set \(workingIndex(of: set, in: entry))")
                            Text(SetDescription.short(weightKg: set.weightKg, reps: set.reps, durationSeconds: set.durationSeconds, distanceMeters: set.distanceMeters, trackingType: entry.trackingType, unit: unit))
                                .numericStyle()
                            if let rpe = set.rpe {
                                Text("RPE \(Format.number(rpe))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if entry.trackingType == .weightReps, let w = set.weightKg, let r = set.reps, let e = OneRepMax.epley(weightKg: w, reps: r), set.kind == .working {
                                Text("e1RM \(Format.weightValue(e, unit: unit))")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    if !entry.notes.isEmpty {
                        Text(entry.notes)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    if let exercise = entry.exercise {
                        NavigationLink(value: exercise) {
                            HStack {
                                Text(entry.exerciseName)
                                Image(systemName: "chevron.right").font(.caption2)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .textCase(nil)
                    } else {
                        Text(entry.exerciseName).textCase(nil)
                    }
                }
            }

            if !session.notes.isEmpty {
                Section("Notes") {
                    Text(session.notes)
                }
            }

            Section {
                Button {
                    workout.start(repeating: session)
                } label: {
                    Label("Repeat This Workout", systemImage: "arrow.clockwise")
                }
                .disabled(workout.hasActiveWorkout)
                Button {
                    TemplateActions.makeTemplate(from: session, in: context)
                    savedTemplate = true
                    Haptics.success()
                } label: {
                    Label(savedTemplate ? "Saved as Template" : "Save as Template", systemImage: savedTemplate ? "checkmark" : "square.and.arrow.down")
                }
                .disabled(savedTemplate)
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete Workout", systemImage: "trash")
                }
            }
        }
        .navigationTitle(session.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            SessionEditorView(session: session)
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { @MainActor in
                    await health.deleteWrittenWorkout(session)
                    context.delete(session)
                    try? context.save()
                    dismiss()
                }
            }
        } message: {
            Text("This removes the workout and its sets from your history and progress.")
        }
    }

    private func workingIndex(of set: WorkoutSet, in entry: SessionExercise) -> Int {
        (entry.orderedSets.filter { $0.kind == .working }.firstIndex { $0.id == set.id } ?? 0) + 1
    }
}

// MARK: - Editing a completed session

/// Edits a finished workout in place. Charts, records and the weekly review
/// read from these records, so they update automatically.
struct SessionEditorView: View {
    let session: WorkoutSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(HealthService.self) private var health

    @State private var name = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var notes = ""
    @State private var addingExercise = false
    @State private var originalTimes: (Date, Date?)?

    private var unit: WeightUnit { settings.unit }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    DatePicker("Started", selection: $start, in: ...Date())
                    DatePicker("Finished", selection: $end, in: start...max(start, Date()))
                }

                ForEach(session.orderedExercises) { entry in
                    Section {
                        ForEach(entry.orderedSets) { set in
                            EditableSetRow(set: set, trackingType: entry.trackingType, unit: unit)
                        }
                        .onDelete { offsets in
                            let ordered = entry.orderedSets
                            for index in offsets {
                                let set = ordered[index]
                                entry.sets.removeAll { $0.id == set.id }
                                context.delete(set)
                            }
                            for (i, s) in entry.orderedSets.enumerated() { s.position = i }
                        }
                        Button {
                            let set = WorkoutSet(position: entry.nextPosition, kind: .working)
                            set.isCompleted = true
                            set.completedAt = session.startedAt
                            if let last = entry.orderedSets.last {
                                set.weightKg = last.weightKg
                                set.reps = last.reps
                                set.durationSeconds = last.durationSeconds
                                set.distanceMeters = last.distanceMeters
                            }
                            entry.sets.append(set)
                        } label: {
                            Label("Add Set", systemImage: "plus")
                        }
                    } header: {
                        HStack {
                            Text(entry.exerciseName).textCase(nil)
                            Spacer()
                            Button(role: .destructive) {
                                session.exercises.removeAll { $0.id == entry.id }
                                context.delete(entry)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Remove \(entry.exerciseName)")
                        }
                    }
                }

                Section {
                    Button {
                        addingExercise = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                    }
                }

                Section("Notes") {
                    TextField("How did it go?", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle("Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: finish)
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $addingExercise) {
                ExercisePickerView(title: "Add Exercises") { picked in
                    var position = (session.exercises.map(\.position).max() ?? -1) + 1
                    for exercise in picked {
                        let entry = SessionExercise(exercise: exercise, position: position)
                        session.exercises.append(entry)
                        let set = WorkoutSet(position: 0, kind: .working)
                        set.isCompleted = true
                        set.completedAt = session.startedAt
                        entry.sets.append(set)
                        position += 1
                    }
                }
            }
            .onAppear {
                name = session.name
                start = session.startedAt
                end = session.endedAt ?? Date()
                notes = session.notes
                originalTimes = (session.startedAt, session.endedAt)
            }
            .interactiveDismissDisabled()
        }
    }

    private func finish() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        session.name = trimmed.isEmpty ? session.name : trimmed
        session.startedAt = start
        session.endedAt = max(end, start)
        session.notes = notes
        // In history every remaining set counts as done; empty ones are dropped.
        for entry in session.exercises {
            for set in entry.sets {
                if set.hasValues {
                    set.isCompleted = true
                    if set.completedAt == nil { set.completedAt = start }
                } else {
                    entry.sets.removeAll { $0.id == set.id }
                    context.delete(set)
                }
            }
        }
        for entry in session.exercises where entry.sets.isEmpty {
            session.exercises.removeAll { $0.id == entry.id }
            context.delete(entry)
        }
        for (index, entry) in session.orderedExercises.enumerated() { entry.position = index }
        try? context.save()

        let timesChanged = originalTimes.map { $0.0 != session.startedAt || $0.1 != session.endedAt } ?? false
        if timesChanged && session.healthWorkoutUUID != nil {
            let target = session
            Task { @MainActor in
                await health.syncWorkout(target)
                try? context.save()
            }
        }
        dismiss()
    }
}

struct EditableSetRow: View {
    @Bindable var set: WorkoutSet
    let trackingType: ExerciseTrackingType
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button {
                set.kind = set.kind == .warmup ? .working : .warmup
            } label: {
                Text(set.kind == .warmup ? "W" : "•")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(set.kind == .warmup ? Color.orange : Color.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(set.kind == .warmup ? "Warm-up set" : "Working set")
            .accessibilityHint("Toggles warm-up")

            if trackingType.usesWeight {
                labeled(unit.symbol) {
                    NumberField(placeholder: "0", value: .weight($set.weightKg, unit: unit))
                }
            }
            if trackingType.usesReps {
                labeled("reps") {
                    NumberField(placeholder: "0", value: .integer($set.reps), allowsDecimal: false)
                }
            }
            if trackingType.usesDistance {
                labeled("m") {
                    NumberField(placeholder: "0", value: $set.distanceMeters, fractionDigits: 0)
                }
            }
            if trackingType.usesDuration {
                labeled("sec") {
                    NumberField(placeholder: "0", value: $set.durationSeconds, fractionDigits: 0)
                }
            }
        }
    }

    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 4) {
            content()
                .frame(minWidth: 50)
                .padding(.vertical, 6)
                .background(Theme.Palette.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
