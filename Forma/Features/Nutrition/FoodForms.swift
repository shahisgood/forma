import SwiftUI
import SwiftData
import FormaKit

// MARK: - Quick add

/// Logs an estimate without creating a food. Only calories are required.
struct QuickAddView: View {
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var day: DayKey
    @State private var meal: Meal
    @State private var name = ""
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var recordTime = false
    @State private var eatenAt = Date()

    init(day: DayKey, meal: Meal, onDone: @escaping () -> Void) {
        self.onDone = onDone
        _day = State(initialValue: day)
        _meal = State(initialValue: meal)
    }

    private var calories: Double? {
        guard let value = NumberParsing.decimal(from: caloriesText), value >= 0, value < 20_000 else { return nil }
        return value
    }

    private func optional(_ text: String) -> Double? {
        guard let value = NumberParsing.decimal(from: text), value >= 0 else { return nil }
        return value
    }

    var body: some View {
        Form {
            Section {
                NumberRow(title: "Calories", unit: "kcal", text: $caloriesText, tint: Metric.calories.color, autoFocus: true)
                NumberRow(title: "Protein", unit: "g", text: $proteinText, tint: Metric.protein.color)
                if settings.values.trackCarbs {
                    NumberRow(title: "Carbs", unit: "g", text: $carbsText, tint: Metric.carbs.color)
                }
                if settings.values.trackFat {
                    NumberRow(title: "Fat", unit: "g", text: $fatText, tint: Metric.fat.color)
                }
                TextField("Label (optional), e.g. Restaurant lunch", text: $name)
            } footer: {
                Text("For when you don't have exact details. It's saved as an estimate.")
            }

            EntryPlacementSection(day: $day, meal: $meal, recordTime: $recordTime, eatenAt: $eatenAt)
        }
        .navigationTitle("Quick Add")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", action: add)
                    .fontWeight(.semibold)
                    .disabled(calories == nil)
            }
        }
    }

    private func add() {
        guard let calories else { return }
        let nutrients = Nutrients(
            calories: calories,
            protein: optional(proteinText) ?? 0,
            carbs: optional(carbsText),
            fat: optional(fatText)
        )
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = FoodEntry(
            day: day,
            meal: meal,
            name: label.isEmpty ? "Quick add" : label,
            servings: 1,
            servingSize: 1,
            servingUnit: .serving,
            perServing: nutrients,
            source: .quickEstimate
        )
        entry.consumedAt = recordTime ? EntryPlacementSection.combine(day: day, time: eatenAt) : nil
        context.insert(entry)
        try? context.save()
        Haptics.success()
        onDone()
    }
}

/// A labelled numeric entry row.
struct NumberRow: View {
    let title: String
    let unit: String
    @Binding var text: String
    var tint: Color = .primary
    var placeholder = "0"
    var autoFocus = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(title)
            Spacer()
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .numericStyle()
                .frame(maxWidth: 110)
                .focused($focused)
                .accessibilityLabel(title)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear {
            if autoFocus { focused = true }
        }
    }
}

// MARK: - Food editor

struct FoodEditorView: View {
    let food: Food?
    var onSave: ((Food) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @State private var name: String
    @State private var brand = ""
    @State private var servingSizeText = "1"
    @State private var servingUnit: ServingUnit = .serving
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var isFavorite = false
    @State private var showDeleteConfirmation = false

    init(food: Food?, initialName: String = "", onSave: ((Food) -> Void)? = nil) {
        self.food = food
        self.onSave = onSave
        _name = State(initialValue: food?.name ?? initialName)
    }

    private var servingSize: Double? {
        guard let value = NumberParsing.decimal(from: servingSizeText), value > 0 else { return nil }
        return value
    }

    private var calories: Double? {
        guard let value = NumberParsing.decimal(from: caloriesText), value >= 0 else { return nil }
        return value
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && servingSize != nil && calories != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Brand or note (optional)", text: $brand)
                }

                Section {
                    HStack {
                        Text("Serving size")
                        Spacer()
                        TextField("1", text: $servingSizeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                        Picker("Unit", selection: $servingUnit) {
                            ForEach(ServingUnit.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                } footer: {
                    Text("Nutrition below is for one serving of this size. Foods measured in grams or millilitres can also be logged by weight or volume.")
                }

                Section("Per serving") {
                    NumberRow(title: "Calories", unit: "kcal", text: $caloriesText, tint: Metric.calories.color)
                    NumberRow(title: "Protein", unit: "g", text: $proteinText, tint: Metric.protein.color)
                    NumberRow(title: "Carbs", unit: "g", text: $carbsText, tint: Metric.carbs.color, placeholder: "—")
                    NumberRow(title: "Fat", unit: "g", text: $fatText, tint: Metric.fat.color, placeholder: "—")
                }

                if let mismatch = macroMismatchNote {
                    Section {
                        FootnoteText(text: mismatch, symbol: "exclamationmark.triangle")
                    }
                }

                Section {
                    Toggle("Favorite", isOn: $isFavorite)
                }

                if food != nil {
                    Section {
                        Button("Delete Food", role: .destructive) { showDeleteConfirmation = true }
                    } footer: {
                        Text("Diary entries already logged keep their values.")
                    }
                }
            }
            .navigationTitle(food == nil ? "New Food" : "Edit Food")
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
            .confirmationDialog("Delete \(food?.name ?? "food")?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let food {
                        context.delete(food)
                        try? context.save()
                    }
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    /// Gentle hint when entered macros don't add up to the calories (common with label typos).
    private var macroMismatchNote: String? {
        guard let calories, calories > 50,
              let protein = NumberParsing.decimal(from: proteinText),
              let carbs = NumberParsing.decimal(from: carbsText),
              let fat = NumberParsing.decimal(from: fatText) else { return nil }
        let implied = protein * 4 + carbs * 4 + fat * 9
        guard abs(implied - calories) / calories > 0.25 else { return nil }
        return "These macros add up to about \(Format.calories(implied)) kcal. That's fine if the label says so (fibre and alcohol can explain differences) — just worth a second look."
    }

    private func load() {
        guard let food else { return }
        brand = food.brand
        servingSizeText = Format.servings(food.servingSize)
        servingUnit = food.servingUnit
        caloriesText = Format.number(food.calories)
        proteinText = Format.number(food.protein)
        carbsText = food.carbs.map { Format.number($0) } ?? ""
        fatText = food.fat.map { Format.number($0) } ?? ""
        isFavorite = food.isFavorite
    }

    private func save() {
        guard let servingSize, let calories else { return }
        let nutrients = Nutrients(
            calories: calories,
            protein: NumberParsing.decimal(from: proteinText) ?? 0,
            carbs: NumberParsing.decimal(from: carbsText),
            fat: NumberParsing.decimal(from: fatText)
        )
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let target: Food
        if let food {
            food.name = trimmedName
            food.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
            food.servingSize = servingSize
            food.servingUnit = servingUnit
            food.nutrientsPerServing = nutrients
            food.isFavorite = isFavorite
            target = food
        } else {
            target = Food(name: trimmedName, brand: brand.trimmingCharacters(in: .whitespacesAndNewlines), servingSize: servingSize, servingUnit: servingUnit, nutrients: nutrients)
            target.isFavorite = isFavorite
            context.insert(target)
        }
        try? context.save()
        Haptics.success()
        dismiss()
        onSave?(target)
    }
}

// MARK: - Diary entry editor

struct FoodEntryEditor: View {
    let entry: FoodEntry

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(DayClock.self) private var clock

    @State private var name = ""
    @State private var servingsText = ""
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var day = DayKey.today()
    @State private var meal: Meal = .snacks
    @State private var recordTime = false
    @State private var eatenAt = Date()
    @State private var showDeleteConfirmation = false

    private var amountUnit: ServingUnit { entry.amountUnit ?? .serving }

    private var quantity: Double? {
        guard let value = NumberParsing.decimal(from: servingsText), value > 0 else { return nil }
        return value
    }

    private var servings: Double? {
        guard let quantity else { return nil }
        return ServingMath.servings(amount: quantity, unit: amountUnit, servingSize: entry.servingSize, servingUnit: entry.servingUnit)
    }

    private var perServing: Nutrients? {
        guard let calories = NumberParsing.decimal(from: caloriesText), calories >= 0 else { return nil }
        return Nutrients(
            calories: calories,
            protein: NumberParsing.decimal(from: proteinText) ?? 0,
            carbs: NumberParsing.decimal(from: carbsText),
            fat: NumberParsing.decimal(from: fatText)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    HStack {
                        Text(amountUnit == .serving ? "Servings" : "Amount")
                        Spacer()
                        TextField("1", text: $servingsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                        Text(amountUnit == .serving ? "×" : amountUnit.label)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    HStack(spacing: 6) {
                        TagBadge(text: entry.source.label)
                        Text("Logged \(Format.dateTime(entry.loggedAt))")
                    }
                }

                Section {
                    NutrientPreview(nutrients: (perServing ?? .zero).scaled(by: servings ?? 0), valid: perServing != nil && servings != nil)
                } header: {
                    Text("Total")
                }

                Section {
                    NumberRow(title: "Calories", unit: "kcal", text: $caloriesText, tint: Metric.calories.color)
                    NumberRow(title: "Protein", unit: "g", text: $proteinText, tint: Metric.protein.color)
                    NumberRow(title: "Carbs", unit: "g", text: $carbsText, tint: Metric.carbs.color, placeholder: "—")
                    NumberRow(title: "Fat", unit: "g", text: $fatText, tint: Metric.fat.color, placeholder: "—")
                } header: {
                    Text(entry.source == .quickEstimate ? "Estimate" : "Per serving")
                } footer: {
                    Text("Changing these corrects this entry only.")
                }

                EntryPlacementSection(day: $day, meal: $meal, recordTime: $recordTime, eatenAt: $eatenAt)

                Section {
                    Button {
                        let copy = entry.duplicate(to: clock.today, source: clock.today == entry.day ? nil : .copied)
                        context.insert(copy)
                        try? context.save()
                        Haptics.success()
                        dismiss()
                    } label: {
                        Label(clock.today == entry.day ? "Duplicate" : "Log Again Today", systemImage: "plus.square.on.square")
                    }
                    Button("Delete Entry", role: .destructive) { showDeleteConfirmation = true }
                }
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(servings == nil || perServing == nil)
                }
            }
            .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    context.delete(entry)
                    try? context.save()
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        name = entry.name
        if let amount = entry.amount, entry.amountUnit != nil, entry.amountUnit != .serving {
            servingsText = Format.servings(amount)
        } else {
            servingsText = Format.servings(entry.servings)
        }
        let per = entry.perServing
        caloriesText = Format.number(per.calories)
        proteinText = Format.number(per.protein)
        carbsText = per.carbs.map { Format.number($0) } ?? ""
        fatText = per.fat.map { Format.number($0) } ?? ""
        day = entry.day
        meal = entry.meal
        recordTime = entry.consumedAt != nil
        eatenAt = entry.consumedAt ?? Date()
    }

    private func save() {
        guard let servings, let perServing, let quantity else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.name = trimmed.isEmpty ? entry.name : trimmed
        entry.servings = servings
        if entry.amountUnit != nil && entry.amountUnit != .serving {
            entry.amount = quantity
        }
        entry.perServing = perServing
        entry.day = day
        entry.meal = meal
        entry.consumedAt = recordTime ? EntryPlacementSection.combine(day: day, time: eatenAt) : nil
        entry.updatedAt = Date()
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
