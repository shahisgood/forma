import SwiftUI
import SwiftData
import FormaKit

/// Food logging hub: recent foods, favorites, saved meals, the person's own
/// foods, quick estimates and food creation. Everything is local; there is no
/// bundled food database.
struct AddFoodSheet: View {
    let day: DayKey
    let meal: Meal

    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Food> { !$0.isArchived }, sort: \Food.name) private var foods: [Food]
    @Query(sort: \SavedMeal.name) private var savedMeals: [SavedMeal]

    @State private var search = ""
    @State private var tab: Tab = .recent
    @State private var path = NavigationPath()
    @State private var creatingFood = false

    enum Tab: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case favorites = "Favorites"
        case meals = "Meals"
        case mine = "My Foods"
        var id: String { rawValue }
    }

    enum Route: Hashable {
        case food(UUID)
        case savedMeal(UUID)
        case quickAdd
    }

    private var recentFoods: [Food] {
        foods.filter { $0.lastUsedAt != nil }
            .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
            .prefix(25)
            .map { $0 }
    }

    private var filteredFoods: [Food] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return foods.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.brand.localizedCaseInsensitiveContains(query) }
    }

    private var filteredMeals: [SavedMeal] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return savedMeals.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    HStack(spacing: Theme.Spacing.s) {
                        QuickActionButton(title: "Quick Add", symbol: "bolt.fill", tint: Metric.calories.color) {
                            path.append(Route.quickAdd)
                        }
                        QuickActionButton(title: "New Food", symbol: "plus.circle.fill", tint: Theme.Palette.accent) {
                            creatingFood = true
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if search.isEmpty {
                    Section {
                        Picker("Show", selection: $tab) {
                            ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                    tabContent
                } else {
                    searchResults
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search your foods and meals")
            .navigationTitle("Add to \(meal.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .food(let id):
                    if let food = foods.first(where: { $0.id == id }) {
                        LogFoodView(food: food, day: day, meal: meal, onDone: { dismiss() })
                    }
                case .savedMeal(let id):
                    if let saved = savedMeals.first(where: { $0.id == id }) {
                        LogSavedMealView(savedMeal: saved, day: day, meal: meal, onDone: { dismiss() })
                    }
                case .quickAdd:
                    QuickAddView(day: day, meal: meal, onDone: { dismiss() })
                }
            }
            .sheet(isPresented: $creatingFood) {
                FoodEditorView(food: nil, initialName: search.trimmingCharacters(in: .whitespaces)) { created in
                    search = ""
                    path.append(Route.food(created.id))
                }
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .recent:
            if recentFoods.isEmpty {
                emptySection(
                    symbol: "clock.arrow.circlepath",
                    title: "Nothing recent yet",
                    message: "Foods you log will appear here so you can add them again in a tap."
                )
            } else {
                Section { ForEach(recentFoods) { foodRow($0) } }
            }
        case .favorites:
            let favorites = foods.filter(\.isFavorite)
            if favorites.isEmpty {
                emptySection(symbol: "star", title: "No favorites", message: "Mark a food as a favorite when you create or edit it.")
            } else {
                Section { ForEach(favorites) { foodRow($0) } }
            }
        case .meals:
            if savedMeals.isEmpty {
                emptySection(
                    symbol: "square.stack",
                    title: "No saved meals",
                    message: "In your diary, open a meal's menu and choose Save as Meal to reuse a combination of foods."
                )
            } else {
                Section { ForEach(savedMeals) { mealRow($0) } }
            }
        case .mine:
            if foods.isEmpty {
                emptySection(symbol: "carrot", title: "No foods yet", message: "Create foods you eat often with their nutrition values, or use Quick Add for one-off estimates.")
            } else {
                Section { ForEach(foods) { foodRow($0) } }
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let matchedFoods = filteredFoods
        let matchedMeals = filteredMeals
        if matchedFoods.isEmpty && matchedMeals.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("No matches for “\(search)”")
                        .font(.headline)
                    Text("Forma searches the foods and meals you've saved. Create it as a new food, or log a quick estimate.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Create “\(search)”") { creatingFood = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.vertical, Theme.Spacing.s)
            }
        } else {
            if !matchedMeals.isEmpty {
                Section("Saved meals") { ForEach(matchedMeals) { mealRow($0) } }
            }
            if !matchedFoods.isEmpty {
                Section("Foods") { ForEach(matchedFoods) { foodRow($0) } }
            }
        }
    }

    private func emptySection(symbol: String, title: String, message: String) -> some View {
        Section {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
    }

    private func foodRow(_ food: Food) -> some View {
        NavigationLink(value: Route.food(food.id)) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(food.name)
                        if food.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(Theme.Palette.record)
                                .accessibilityLabel("Favorite")
                        }
                    }
                    Text([food.brand, food.servingDescription].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Format.calories(food.calories)) kcal")
                        .font(.subheadline.weight(.medium))
                    Text("\(Format.grams(food.protein)) g P")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .numericStyle()
            }
        }
    }

    private func mealRow(_ saved: SavedMeal) -> some View {
        NavigationLink(value: Route.savedMeal(saved.id)) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(saved.name)
                    Text("\(saved.items.count) item\(saved.items.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Format.calories(saved.totals.calories)) kcal")
                    .font(.subheadline.weight(.medium))
                    .numericStyle()
            }
        }
    }
}

// MARK: - Logging a food

/// Chooses an amount of a food and adds it to the diary.
struct LogFoodView: View {
    let food: Food
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @State private var day: DayKey
    @State private var meal: Meal
    @State private var amountText: String
    @State private var unit: ServingUnit
    @State private var recordTime = false
    @State private var eatenAt = Date()
    @State private var editingFood = false
    @FocusState private var amountFocused: Bool

    init(food: Food, day: DayKey, meal: Meal, onDone: @escaping () -> Void) {
        self.food = food
        self.onDone = onDone
        _day = State(initialValue: day)
        _meal = State(initialValue: meal)
        _amountText = State(initialValue: "1")
        _unit = State(initialValue: .serving)
    }

    private var servings: Double? {
        guard let amount = NumberParsing.decimal(from: amountText), amount > 0 else { return nil }
        return ServingMath.servings(amount: amount, unit: unit, servingSize: food.servingSize, servingUnit: food.servingUnit)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name).font(.title3.weight(.semibold))
                    Text([food.brand, "\(food.servingDescription) per serving"].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Amount") {
                HStack {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.title3.weight(.semibold))
                        .focused($amountFocused)
                        .numericStyle()
                    Picker("Unit", selection: $unit) {
                        ForEach(ServingMath.loggableUnits(for: food.servingUnit)) { option in
                            Text(option == .serving ? "serving" : option.label).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                HStack(spacing: Theme.Spacing.s) {
                    ForEach([0.5, 1, 1.5, 2], id: \.self) { preset in
                        Button(Format.servings(preset)) {
                            unit = .serving
                            amountText = Format.servings(preset)
                            Haptics.selection()
                        }
                        .buttonStyle(SecondaryButtonStyle(tint: .secondary, fullWidth: true))
                        .accessibilityLabel("\(Format.servings(preset)) servings")
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            Section {
                NutrientPreview(nutrients: food.nutrientsPerServing.scaled(by: servings ?? 0), valid: servings != nil)
            } header: {
                Text("Adds")
            } footer: {
                Text("Estimated from the values saved for this food.")
            }

            EntryPlacementSection(day: $day, meal: $meal, recordTime: $recordTime, eatenAt: $eatenAt)
        }
        .navigationTitle("Log Food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", action: add)
                    .fontWeight(.semibold)
                    .disabled(servings == nil)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Edit Food") { editingFood = true }
            }
        }
        .sheet(isPresented: $editingFood) {
            FoodEditorView(food: food, onSave: nil)
        }
    }

    private func add() {
        guard let servings, let amount = NumberParsing.decimal(from: amountText) else { return }
        let entry = FoodEntry(
            day: day,
            meal: meal,
            name: food.name,
            detail: food.brand,
            servings: servings,
            servingSize: food.servingSize,
            servingUnit: food.servingUnit,
            perServing: food.nutrientsPerServing,
            source: .myFood,
            foodID: food.id
        )
        if unit != .serving {
            entry.amount = amount
            entry.amountUnitRaw = unit.rawValue
        }
        entry.consumedAt = recordTime ? EntryPlacementSection.combine(day: day, time: eatenAt) : nil
        context.insert(entry)
        food.lastUsedAt = Date()
        food.useCount += 1
        try? context.save()
        Haptics.success()
        onDone()
    }
}

/// Day, meal and optional eaten-at time. The time eaten is separate from when
/// the entry was logged, so logging lunch in the evening stays "lunch".
struct EntryPlacementSection: View {
    @Binding var day: DayKey
    @Binding var meal: Meal
    @Binding var recordTime: Bool
    @Binding var eatenAt: Date

    var body: some View {
        Section {
            Picker("Meal", selection: $meal) {
                ForEach(Meal.allCases) { Text($0.name).tag($0) }
            }
            DatePicker(
                "Day",
                selection: Binding(get: { day.middayDate() }, set: { day = DayKey($0) }),
                in: ...Date(),
                displayedComponents: .date
            )
            Toggle("Record time eaten", isOn: $recordTime.animation(Motion.standard))
            if recordTime {
                DatePicker("Time eaten", selection: $eatenAt, displayedComponents: .hourAndMinute)
            }
        } footer: {
            Text("Optional. The time you log something is kept separately from when you ate it.")
        }
    }

    static func combine(day: DayKey, time: Date, calendar: Calendar = .current) -> Date {
        let clock = ClockTime(date: time, calendar: calendar)
        return clock.date(on: day, calendar: calendar) ?? time
    }
}

struct NutrientPreview: View {
    let nutrients: Nutrients
    var valid = true

    var body: some View {
        HStack {
            value(Format.calories(nutrients.calories), "kcal", Metric.calories.color)
            value(Format.grams(nutrients.protein), "g protein", Metric.protein.color)
            if let carbs = nutrients.carbs {
                value(Format.grams(carbs), "g carbs", Metric.carbs.color)
            }
            if let fat = nutrients.fat {
                value(Format.grams(fat), "g fat", Metric.fat.color)
            }
        }
        .opacity(valid ? 1 : 0.4)
        .accessibilityElement(children: .combine)
    }

    private func value(_ text: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(text)
                .font(.headline)
                .foregroundStyle(color)
                .numericStyle()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Saved meals

struct LogSavedMealView: View {
    let savedMeal: SavedMeal
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @State private var day: DayKey
    @State private var meal: Meal
    @State private var recordTime = false
    @State private var eatenAt = Date()
    @State private var included: Set<UUID>
    @State private var editing = false

    init(savedMeal: SavedMeal, day: DayKey, meal: Meal, onDone: @escaping () -> Void) {
        self.savedMeal = savedMeal
        self.onDone = onDone
        _day = State(initialValue: day)
        _meal = State(initialValue: meal)
        _included = State(initialValue: Set(savedMeal.items.map(\.id)))
    }

    private var selectedItems: [SavedMealItem] {
        savedMeal.orderedItems.filter { included.contains($0.id) }
    }

    var body: some View {
        Form {
            Section {
                ForEach(savedMeal.orderedItems) { item in
                    Button {
                        if included.contains(item.id) { included.remove(item.id) } else { included.insert(item.id) }
                        Haptics.selection()
                    } label: {
                        HStack {
                            Image(systemName: included.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(included.contains(item.id) ? Theme.Palette.accent : .secondary)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).foregroundStyle(.primary)
                                Text(item.servings == 1 ? "1 serving" : "\(Format.servings(item.servings)) servings")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Format.calories(item.nutrients.calories)) kcal")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .numericStyle()
                        }
                    }
                    .accessibilityAddTraits(included.contains(item.id) ? .isSelected : [])
                }
            } header: {
                Text(savedMeal.name)
            } footer: {
                Text("Each item is added as its own diary entry, so you can adjust amounts afterwards.")
            }

            Section("Adds") {
                NutrientPreview(nutrients: selectedItems.reduce(Nutrients.zero) { $0 + $1.nutrients }, valid: !selectedItems.isEmpty)
            }

            EntryPlacementSection(day: $day, meal: $meal, recordTime: $recordTime, eatenAt: $eatenAt)
        }
        .navigationTitle("Log Meal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add \(selectedItems.count)", action: add)
                    .fontWeight(.semibold)
                    .disabled(selectedItems.isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Edit Meal") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            SavedMealEditor(savedMeal: savedMeal)
        }
    }

    private func add() {
        let time = recordTime ? EntryPlacementSection.combine(day: day, time: eatenAt) : nil
        for item in selectedItems {
            let entry = item.makeEntry(day: day, meal: meal)
            entry.consumedAt = time
            context.insert(entry)
        }
        savedMeal.lastUsedAt = Date()
        savedMeal.useCount += 1
        try? context.save()
        Haptics.success()
        onDone()
    }
}
