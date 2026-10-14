import SwiftUI
import SwiftData
import Charts
import FormaKit

// MARK: - Picker

/// Multi-select exercise picker with search, category filter and inline creation.
struct ExercisePickerView: View {
    let title: String
    let onPick: ([Exercise]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Exercise> { !$0.isArchived }, sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var category: ExerciseCategory?
    @State private var selection: [UUID] = []
    @State private var creating = false

    private var filtered: [Exercise] {
        exercises.filter { exercise in
            (category == nil || exercise.category == category)
                && (search.isEmpty || exercise.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.s) {
                            CategoryChip(title: "All", selected: category == nil) { category = nil }
                            ForEach(ExerciseCategory.allCases) { item in
                                CategoryChip(title: item.name, selected: category == item) { category = item }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.l)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(filtered) { exercise in
                        let index = selection.firstIndex(of: exercise.id)
                        Button {
                            Haptics.selection()
                            if let index { selection.remove(at: index) } else { selection.append(exercise.id) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name).foregroundStyle(.primary)
                                    Text("\(exercise.category.name) · \(exercise.equipment.name)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if exercise.isCustom {
                                    TagBadge(text: "Custom")
                                }
                                ZStack {
                                    Circle()
                                        .strokeBorder(index == nil ? Color.secondary.opacity(0.4) : Color.clear, lineWidth: 1.5)
                                        .background(Circle().fill(index == nil ? Color.clear : Metric.training.color))
                                    if let index {
                                        Text("\(index + 1)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 26, height: 26)
                                .motion(Motion.quick, value: index)
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityAddTraits(index != nil ? .isSelected : [])
                    }
                } footer: {
                    if filtered.isEmpty {
                        Text("No exercises match. Create a custom one with the + button.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selection.isEmpty ? "Add" : "Add \(selection.count)") {
                        let picked = selection.compactMap { id in exercises.first { $0.id == id } }
                        onPick(picked)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selection.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        creating = true
                    } label: {
                        Label("New Exercise", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $creating) {
                ExerciseEditorView(exercise: nil, initialName: search) { created in
                    selection.append(created.id)
                }
            }
        }
    }
}

struct CategoryChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            Motion.perform(Motion.quick, action)
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(Capsule().fill(selected ? Metric.training.color : Theme.Palette.fill))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Library

struct ExerciseLibraryView: View {
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var creating = false
    @State private var showArchived = false

    private var visible: [Exercise] {
        exercises.filter { (showArchived || !$0.isArchived) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
    }

    var body: some View {
        List {
            ForEach(ExerciseCategory.allCases) { category in
                let items = visible.filter { $0.category == category }
                if !items.isEmpty {
                    Section(category.name) {
                        ForEach(items) { exercise in
                            NavigationLink(value: exercise) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(exercise.name)
                                        Text(exercise.equipment.name)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if exercise.isArchived {
                                        TagBadge(text: "Archived")
                                    } else if exercise.isCustom {
                                        TagBadge(text: "Custom")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle("Exercises")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        creating = true
                    } label: {
                        Label("New Exercise", systemImage: "plus")
                    }
                    Toggle("Show Archived", isOn: $showArchived)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Exercise options")
            }
        }
        .sheet(isPresented: $creating) {
            ExerciseEditorView(exercise: nil)
        }
        .overlay {
            if visible.isEmpty && !search.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
    }
}

// MARK: - Editor

struct ExerciseEditorView: View {
    let exercise: Exercise?
    var initialName = ""
    var onSave: ((Exercise) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var category: ExerciseCategory = .chest
    @State private var equipment: Equipment = .barbell
    @State private var tracking: ExerciseTrackingType = .weightReps
    @State private var notes = ""

    private var hasHistory: Bool { !(exercise?.sessionEntries.isEmpty ?? true) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Category", selection: $category) {
                        ForEach(ExerciseCategory.allCases) { Text($0.name).tag($0) }
                    }
                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases) { Text($0.name).tag($0) }
                    }
                }
                Section {
                    Picker("Tracks", selection: $tracking) {
                        ForEach(ExerciseTrackingType.allCases) { Text($0.name).tag($0) }
                    }
                    .disabled(hasHistory)
                } footer: {
                    if hasHistory {
                        Text("The tracking type can't change once the exercise has logged sets, so history stays comparable.")
                    } else {
                        Text(trackingExplanation)
                    }
                }
                Section("Notes") {
                    TextField("Setup, cues…", text: $notes, axis: .vertical)
                        .lineLimit(1...5)
                }
            }
            .navigationTitle(exercise == nil ? "New Exercise" : "Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let exercise {
                    name = exercise.name
                    category = exercise.category
                    equipment = exercise.equipment
                    tracking = exercise.trackingType
                    notes = exercise.notes
                } else {
                    name = initialName
                }
            }
        }
    }

    private var trackingExplanation: String {
        switch tracking {
        case .weightReps: return "Weight and reps for each set."
        case .bodyweightReps: return "Reps, with optional added weight."
        case .assistedReps: return "Reps, with optional assistance weight (lower is harder)."
        case .duration: return "Time for each set, e.g. planks."
        case .distanceDuration: return "Distance and time, e.g. carries or rowing."
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let target: Exercise
        if let exercise {
            exercise.name = trimmed
            exercise.category = category
            exercise.equipment = equipment
            if !hasHistory { exercise.trackingType = tracking }
            exercise.notes = notes
            target = exercise
        } else {
            target = Exercise(name: trimmed, category: category, equipment: equipment, trackingType: tracking, isCustom: true)
            target.notes = notes
            context.insert(target)
        }
        try? context.save()
        Haptics.success()
        dismiss()
        onSave?(target)
    }
}
