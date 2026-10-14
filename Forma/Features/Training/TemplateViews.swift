import SwiftUI
import SwiftData
import FormaKit

struct TemplateDetailView: View {
    let template: WorkoutTemplate

    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutController.self) private var workout
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if !template.notes.isEmpty {
                        Text(template.notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        workout.start(template: template)
                    } label: {
                        Label(workout.hasActiveWorkout ? "Resume Current Workout" : "Start Workout", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: Metric.training.color))
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section("Exercises") {
                if template.exercises.isEmpty {
                    Text("No exercises yet. Edit the template to add some.")
                        .foregroundStyle(.secondary)
                }
                ForEach(template.orderedExercises) { item in
                    if let exercise = item.exercise {
                        NavigationLink(value: exercise) {
                            itemRow(item)
                        }
                        .accessibilityHint("Shows \(exercise.name) history")
                    } else {
                        itemRow(item)
                    }
                }
            }

            Section("Schedule") {
                let days = settings.values.templateForWeekday.filter { $0.value == template.id }.map(\.key)
                if days.isEmpty {
                    Text("Not assigned to any days")
                        .foregroundStyle(.secondary)
                } else {
                    Text(RoutineSchedule(kind: .weekdays, weekdays: Set(days)).summary())
                }
            }

            Section {
                Button {
                    TemplateActions.duplicate(template, in: context)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete Template", systemImage: "trash")
                }
            } footer: {
                Text("Editing or deleting a template never changes workouts you've already logged.")
            }
        }
        .navigationTitle(template.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            TemplateEditorView(template: template)
        }
        .confirmationDialog("Delete \(template.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let id = template.id
                settings.update { $0.templateForWeekday = $0.templateForWeekday.filter { $0.value != id } }
                context.delete(template)
                try? context.save()
                dismiss()
            }
        }
    }

    private func itemRow(_ item: TemplateExercise) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.exercise?.name ?? "Removed exercise")
            Text(itemSummary(item))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func itemSummary(_ item: TemplateExercise) -> String {
        var parts: [String] = []
        if item.warmupSets > 0 { parts.append("\(item.warmupSets) warm-up") }
        let sets = "\(item.targetSets) set\(item.targetSets == 1 ? "" : "s")"
        if let reps = item.repRangeDescription { parts.append("\(sets) × \(reps)") } else { parts.append(sets) }
        if let rest = item.restSeconds { parts.append("\(Format.restClock(rest)) rest") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Editor

/// Edits a template through a draft, so cancelling leaves the template untouched.
struct TemplateEditorView: View {
    let template: WorkoutTemplate?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query private var allTemplates: [WorkoutTemplate]

    @State private var name = ""
    @State private var notes = ""
    @State private var items: [DraftItem] = []
    @State private var weekdays: Set<Int> = []
    @State private var pickingExercises = false
    @State private var editingItem: DraftItem?
    @State private var loaded = false

    struct DraftItem: Identifiable, Equatable {
        let id: UUID
        var exercise: Exercise
        var targetSets: Int
        var warmupSets: Int
        var repLow: Int?
        var repHigh: Int?
        var restSeconds: Int?
        var notes: String

        static func == (lhs: DraftItem, rhs: DraftItem) -> Bool {
            lhs.id == rhs.id && lhs.targetSets == rhs.targetSets && lhs.warmupSets == rhs.warmupSets
                && lhs.repLow == rhs.repLow && lhs.repHigh == rhs.repHigh && lhs.restSeconds == rhs.restSeconds
                && lhs.notes == rhs.notes && lhs.exercise.id == rhs.exercise.id
        }
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Name, e.g. Push Day", text: $name)
                        .font(.headline)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    ForEach(items) { item in
                        Button {
                            editingItem = item
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.exercise.name).foregroundStyle(.primary)
                                    Text(summary(item))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "slider.horizontal.3")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { items.remove(atOffsets: $0) }
                    Button {
                        pickingExercises = true
                    } label: {
                        Label("Add Exercises", systemImage: "plus")
                    }
                } header: {
                    HStack {
                        Text("Exercises")
                        Spacer()
                        if items.count > 1 {
                            EditButton().font(.footnote).textCase(nil)
                        }
                    }
                }

                Section {
                    WeekdayPicker(selection: $weekdays, tint: Metric.training.color)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                } header: {
                    Text("Planned days")
                } footer: {
                    Text(scheduleFooter)
                }
            }
            .navigationTitle(template == nil ? "New Template" : "Edit Template")
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
            .sheet(isPresented: $pickingExercises) {
                ExercisePickerView(title: "Add Exercises") { picked in
                    for exercise in picked {
                        items.append(DraftItem(
                            id: UUID(),
                            exercise: exercise,
                            targetSets: 3,
                            warmupSets: 0,
                            repLow: exercise.trackingType.usesReps ? 8 : nil,
                            repHigh: exercise.trackingType.usesReps ? 12 : nil,
                            restSeconds: nil,
                            notes: ""
                        ))
                    }
                }
            }
            .sheet(item: $editingItem) { item in
                TemplateItemSheet(item: item, defaultRest: settings.values.defaultRestSeconds) { updated in
                    if let index = items.firstIndex(where: { $0.id == updated.id }) {
                        items[index] = updated
                    }
                }
            }
            .onAppear(perform: load)
        }
    }

    private var scheduleFooter: String {
        let others = weekdays.compactMap { weekday -> String? in
            guard let id = settings.values.templateForWeekday[weekday], id != template?.id,
                  let other = allTemplates.first(where: { $0.id == id }) else { return nil }
            return "\(Calendar.current.weekdaySymbols[weekday - 1]) (currently \(other.name))"
        }
        if others.isEmpty {
            return "Optional. Planned days appear on Today and in your weekly review."
        }
        return "Saving will reassign \(others.joined(separator: ", ")) to this template."
    }

    private func summary(_ item: DraftItem) -> String {
        var parts: [String] = []
        if item.warmupSets > 0 { parts.append("\(item.warmupSets) warm-up") }
        var working = "\(item.targetSets) × "
        switch (item.repLow, item.repHigh) {
        case let (lo?, hi?) where lo != hi: working += "\(lo)–\(hi)"
        case let (lo?, _): working += "\(lo)"
        default: working = "\(item.targetSets) set\(item.targetSets == 1 ? "" : "s")"
        }
        parts.append(working)
        parts.append("\(Format.restClock(item.restSeconds ?? settings.values.defaultRestSeconds)) rest\(item.restSeconds == nil ? " (default)" : "")")
        return parts.joined(separator: " · ")
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let template else { return }
        name = template.name
        notes = template.notes
        items = template.orderedExercises.compactMap { item in
            guard let exercise = item.exercise else { return nil }
            return DraftItem(
                id: item.id,
                exercise: exercise,
                targetSets: item.targetSets,
                warmupSets: item.warmupSets,
                repLow: item.repLow,
                repHigh: item.repHigh,
                restSeconds: item.restSeconds,
                notes: item.notes
            )
        }
        weekdays = Set(settings.values.templateForWeekday.filter { $0.value == template.id }.map(\.key))
    }

    private func save() {
        let target: WorkoutTemplate
        if let template {
            target = template
            for existing in template.exercises {
                context.delete(existing)
            }
            template.exercises.removeAll()
        } else {
            target = WorkoutTemplate(name: "", position: (allTemplates.map(\.position).max() ?? -1) + 1)
            context.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.updatedAt = Date()
        for (index, item) in items.enumerated() {
            let newItem = TemplateExercise(exercise: item.exercise, position: index, targetSets: item.targetSets, repLow: item.repLow, repHigh: item.repHigh)
            newItem.warmupSets = item.warmupSets
            newItem.restSeconds = item.restSeconds
            newItem.notes = item.notes
            target.exercises.append(newItem)
        }
        try? context.save()

        let id = target.id
        let selected = weekdays
        settings.update { values in
            for (weekday, mapped) in values.templateForWeekday where mapped == id && !selected.contains(weekday) {
                values.templateForWeekday[weekday] = nil
            }
            for weekday in selected {
                values.templateForWeekday[weekday] = id
                values.trainingDays.insert(weekday)
            }
        }
        Haptics.success()
        dismiss()
    }
}

/// Sets, reps, warm-ups and rest for one exercise in a template.
struct TemplateItemSheet: View {
    @State var item: TemplateEditorView.DraftItem
    let defaultRest: Int
    let onSave: (TemplateEditorView.DraftItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var useCustomRest = false
    @State private var rest = 120

    private let restOptions = [30, 45, 60, 75, 90, 120, 150, 180, 240, 300]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Working sets: \(item.targetSets)", value: $item.targetSets, in: 1...12)
                    Stepper("Warm-up sets: \(item.warmupSets)", value: $item.warmupSets, in: 0...6)
                }
                if item.exercise.trackingType.usesReps {
                    Section("Rep range") {
                        Stepper("From \(item.repLow ?? 1) reps", value: Binding(
                            get: { item.repLow ?? 8 },
                            set: { newValue in
                                item.repLow = newValue
                                if let hi = item.repHigh, hi < newValue { item.repHigh = newValue }
                            }
                        ), in: 1...50)
                        Stepper("To \(item.repHigh ?? item.repLow ?? 1) reps", value: Binding(
                            get: { item.repHigh ?? item.repLow ?? 12 },
                            set: { newValue in item.repHigh = max(newValue, item.repLow ?? 1) }
                        ), in: 1...50)
                    }
                }
                Section {
                    Toggle("Custom rest time", isOn: $useCustomRest.animation(Motion.standard))
                    if useCustomRest {
                        Picker("Rest", selection: $rest) {
                            ForEach(restOptions, id: \.self) { Text(Format.restClock($0)).tag($0) }
                        }
                    }
                } footer: {
                    Text("Otherwise the default rest of \(Format.restClock(defaultRest)) is used.")
                }
                Section("Notes") {
                    TextField("Cues, seat height, grip…", text: $item.notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle(item.exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        item.restSeconds = useCustomRest ? rest : nil
                        onSave(item)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                useCustomRest = item.restSeconds != nil
                let preferred = item.restSeconds ?? defaultRest
                rest = restOptions.min { abs($0 - preferred) < abs($1 - preferred) } ?? 120
            }
        }
        .presentationDetents([.medium, .large])
    }
}
