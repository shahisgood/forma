import SwiftUI
import SwiftData
import FormaKit

// MARK: - Save as meal

struct SaveMealSheet: View {
    let entries: [FoodEntry]
    let suggestedName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Meal name", text: $name)
                } footer: {
                    Text("Saves these \(entries.count) item\(entries.count == 1 ? "" : "s") with their current amounts. Logging the meal later adds each item separately so you can still adjust it.")
                }
                Section {
                    ForEach(entries) { entry in
                        HStack {
                            Text(entry.name)
                            Spacer()
                            Text(entry.quantityDescription)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Save as Meal")
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
            .onAppear { name = suggestedName }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let meal = SavedMeal(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        context.insert(meal)
        for (index, entry) in entries.enumerated() {
            meal.items.append(SavedMealItem(from: entry, position: index))
        }
        try? context.save()
        Haptics.success()
        dismiss()
    }
}

// MARK: - Saved meal editor

struct SavedMealEditor: View {
    let savedMeal: SavedMeal

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var addingFood = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Meal name", text: $name)
                }
                Section {
                    ForEach(savedMeal.orderedItems) { item in
                        SavedMealItemRow(item: item)
                    }
                    .onDelete { offsets in
                        let ordered = savedMeal.orderedItems
                        for index in offsets {
                            let item = ordered[index]
                            savedMeal.items.removeAll { $0.id == item.id }
                            context.delete(item)
                        }
                        try? context.save()
                    }
                    Button {
                        addingFood = true
                    } label: {
                        Label("Add Food", systemImage: "plus")
                    }
                } header: {
                    Text("Items")
                } footer: {
                    Text("Total \(Format.calories(savedMeal.totals.calories)) kcal · \(Format.grams(savedMeal.totals.protein)) g protein")
                }
                Section {
                    Button("Delete Meal", role: .destructive) { showDeleteConfirmation = true }
                } footer: {
                    Text("Entries already logged from this meal stay in your diary.")
                }
            }
            .navigationTitle("Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { savedMeal.name = trimmed }
                        try? context.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $addingFood) {
                FoodPickerSheet { food in
                    let item = SavedMealItem(
                        from: FoodEntry(
                            day: .today(),
                            meal: .snacks,
                            name: food.name,
                            detail: food.brand,
                            servings: 1,
                            servingSize: food.servingSize,
                            servingUnit: food.servingUnit,
                            perServing: food.nutrientsPerServing,
                            source: .myFood,
                            foodID: food.id
                        ),
                        position: (savedMeal.items.map(\.position).max() ?? -1) + 1
                    )
                    savedMeal.items.append(item)
                    try? context.save()
                }
            }
            .confirmationDialog("Delete \(savedMeal.name)?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    context.delete(savedMeal)
                    try? context.save()
                    dismiss()
                }
            }
            .onAppear { name = savedMeal.name }
        }
    }
}

private struct SavedMealItemRow: View {
    @Bindable var item: SavedMealItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text("\(Format.calories(item.nutrients.calories)) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .numericStyle()
            }
            Spacer()
            Stepper(value: $item.servings, in: 0.25...20, step: 0.25) {
                Text("\(Format.servings(item.servings))×")
                    .numericStyle()
            }
            .fixedSize()
            .accessibilityLabel("Servings of \(item.name)")
            .accessibilityValue(Format.servings(item.servings))
        }
    }
}

/// Simple picker over the person's foods.
struct FoodPickerSheet: View {
    let onPick: (Food) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Food> { !$0.isArchived }, sort: \Food.name) private var foods: [Food]
    @State private var search = ""

    private var filtered: [Food] {
        search.isEmpty ? foods : foods.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { food in
                Button {
                    onPick(food)
                    dismiss()
                } label: {
                    HStack {
                        Text(food.name).foregroundStyle(.primary)
                        Spacer()
                        Text("\(Format.calories(food.calories)) kcal")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if foods.isEmpty {
                    ContentUnavailableView("No Foods Yet", systemImage: "carrot", description: Text("Create a food first, then add it to meals."))
                }
            }
            .searchable(text: $search)
            .navigationTitle("Choose Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Copy meal from another day

struct CopyMealSheet: View {
    let targetDay: DayKey
    let targetMeal: Meal

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var sourceDate: Date
    @State private var sourceMeal: Meal
    @State private var selected: Set<UUID> = []
    @State private var candidates: [FoodEntry] = []

    init(targetDay: DayKey, targetMeal: Meal) {
        self.targetDay = targetDay
        self.targetMeal = targetMeal
        _sourceDate = State(initialValue: targetDay.adding(days: -1).middayDate())
        _sourceMeal = State(initialValue: targetMeal)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("From", selection: $sourceDate, in: ...Date(), displayedComponents: .date)
                    Picker("Meal", selection: $sourceMeal) {
                        ForEach(Meal.allCases) { Text($0.name).tag($0) }
                    }
                }

                Section {
                    if candidates.isEmpty {
                        Text("Nothing logged for \(sourceMeal.name.lowercased()) on that day.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(candidates) { entry in
                            Button {
                                if selected.contains(entry.id) { selected.remove(entry.id) } else { selected.insert(entry.id) }
                                Haptics.selection()
                            } label: {
                                HStack {
                                    Image(systemName: selected.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected.contains(entry.id) ? Theme.Palette.accent : .secondary)
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name).foregroundStyle(.primary)
                                        Text(entry.quantityDescription).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(Format.calories(entry.nutrients.calories)) kcal")
                                        .foregroundStyle(.secondary)
                                        .numericStyle()
                                }
                            }
                            .accessibilityAddTraits(selected.contains(entry.id) ? .isSelected : [])
                        }
                    }
                } header: {
                    Text("Items")
                } footer: {
                    Text("Copies go to \(targetMeal.name.lowercased()) on \(Format.dayTitle(targetDay, today: .today()).lowercased()). They're independent of the originals.")
                }
            }
            .navigationTitle("Copy Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy \(selected.count)", action: copy)
                        .fontWeight(.semibold)
                        .disabled(selected.isEmpty)
                }
            }
            .onAppear(perform: loadCandidates)
            .onChange(of: sourceDate) { _, _ in loadCandidates() }
            .onChange(of: sourceMeal) { _, _ in loadCandidates() }
        }
    }

    private func loadCandidates() {
        let key = DayKey(sourceDate).string
        let mealRaw = sourceMeal.rawValue
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate<FoodEntry> { $0.dayKey == key && $0.mealRaw == mealRaw },
            sortBy: [SortDescriptor(\.loggedAt)]
        )
        candidates = (try? context.fetch(descriptor)) ?? []
        selected = Set(candidates.map(\.id))
    }

    private func copy() {
        for entry in candidates where selected.contains(entry.id) {
            context.insert(entry.duplicate(to: targetDay, meal: targetMeal, source: .copied))
        }
        try? context.save()
        Haptics.success()
        dismiss()
    }
}

// MARK: - Targets

/// Calorie and macro targets. Changes apply from today onward; earlier days keep
/// the targets that were in effect then.
struct NutritionTargetsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query private var records: [TargetRecord]

    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var trackCarbs = false
    @State private var trackFat = false
    @State private var showingProteinHelper = false

    private var latestWeightKg: Double? {
        let descriptor = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.measuredAt, order: .reverse)])
        var limited = descriptor
        limited.fetchLimit = 1
        return (try? context.fetch(limited))?.first?.kilograms
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NumberRow(title: "Calories", unit: "kcal", text: $caloriesText, tint: Metric.calories.color, placeholder: "None")
                    NumberRow(title: "Protein", unit: "g", text: $proteinText, tint: Metric.protein.color, placeholder: "None")
                } footer: {
                    Text("Leave a field empty for no target. Targets are your own choice — Forma doesn't prescribe them.")
                }

                Section {
                    Toggle("Track carbs", isOn: $trackCarbs.animation(Motion.standard))
                    if trackCarbs {
                        NumberRow(title: "Carbs", unit: "g", text: $carbsText, tint: Metric.carbs.color, placeholder: "None")
                    }
                    Toggle("Track fat", isOn: $trackFat.animation(Motion.standard))
                    if trackFat {
                        NumberRow(title: "Fat", unit: "g", text: $fatText, tint: Metric.fat.color, placeholder: "None")
                    }
                }

                if let weight = latestWeightKg {
                    Section {
                        DisclosureGroup("Protein starting point", isExpanded: $showingProteinHelper) {
                            let suggestion = (weight * 1.6).rounded()
                            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                                Text("A commonly cited range for people who strength train is about 1.6–2.2 g of protein per kg of body weight. At your latest weigh-in (\(Format.weight(weight, unit: settings.unit))), 1.6 g/kg is about \(Format.grams(suggestion)) g a day.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Text("This is general information, not medical advice. If you have a health condition, check with a professional.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Button("Use \(Format.grams(suggestion)) g") {
                                    proteinText = Format.grams(suggestion)
                                    Haptics.selection()
                                }
                                .buttonStyle(SecondaryButtonStyle(tint: Metric.protein.color, fullWidth: false))
                            }
                            .padding(.vertical, Theme.Spacing.xs)
                        }
                    }
                }

                Section {
                    FootnoteText(text: "Changes apply from today. Past days are still compared with the targets you had at the time.", symbol: "calendar")
                }
            }
            .navigationTitle("Nutrition Targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        let current = TargetStore.timeline(records).nutrition(on: .today())
        caloriesText = current.calories.map { Format.calories($0) } ?? ""
        proteinText = current.protein.map { Format.grams($0) } ?? ""
        carbsText = current.carbs.map { Format.grams($0) } ?? ""
        fatText = current.fat.map { Format.grams($0) } ?? ""
        trackCarbs = settings.values.trackCarbs
        trackFat = settings.values.trackFat
    }

    private func save() {
        func value(_ text: String) -> Double? {
            guard let v = NumberParsing.decimal(from: text), v > 0 else { return nil }
            return v
        }
        TargetStore.set(.calories, to: value(caloriesText), in: context)
        TargetStore.set(.protein, to: value(proteinText), in: context)
        TargetStore.set(.carbs, to: trackCarbs ? value(carbsText) : nil, in: context)
        TargetStore.set(.fat, to: trackFat ? value(fatText) : nil, in: context)
        settings.update {
            $0.trackCarbs = trackCarbs
            $0.trackFat = trackFat
        }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Library

/// Manage saved foods and meals.
struct FoodLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Food.name) private var foods: [Food]
    @Query(sort: \SavedMeal.name) private var meals: [SavedMeal]
    @State private var editingFood: Food?
    @State private var editingMeal: SavedMeal?
    @State private var creating = false

    var body: some View {
        List {
            Section("Saved meals") {
                if meals.isEmpty {
                    Text("Save a meal from your diary to reuse it.")
                        .foregroundStyle(.secondary)
                }
                ForEach(meals) { meal in
                    Button {
                        editingMeal = meal
                    } label: {
                        HStack {
                            Text(meal.name).foregroundStyle(.primary)
                            Spacer()
                            Text("\(meal.items.count) items · \(Format.calories(meal.totals.calories)) kcal")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(meals[index]) }
                    try? context.save()
                }
            }
            Section("My foods") {
                if foods.isEmpty {
                    Text("Foods you create appear here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(foods) { food in
                    Button {
                        editingFood = food
                    } label: {
                        HStack {
                            Text(food.name).foregroundStyle(.primary)
                            if food.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Palette.record)
                                    .accessibilityLabel("Favorite")
                            }
                            Spacer()
                            Text("\(Format.calories(food.calories)) kcal / \(food.servingDescription)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            food.isFavorite.toggle()
                            try? context.save()
                        } label: {
                            Label(food.isFavorite ? "Unfavorite" : "Favorite", systemImage: food.isFavorite ? "star.slash" : "star")
                        }
                        .tint(Theme.Palette.record)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(foods[index]) }
                    try? context.save()
                }
            }
        }
        .navigationTitle("Foods & Meals")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New food")
            }
        }
        .sheet(item: $editingFood) { FoodEditorView(food: $0) }
        .sheet(item: $editingMeal) { SavedMealEditor(savedMeal: $0) }
        .sheet(isPresented: $creating) { FoodEditorView(food: nil) }
    }
}
