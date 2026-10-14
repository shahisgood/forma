import SwiftUI
import SwiftData
import FormaKit

struct NutritionView: View {
    @Environment(DayClock.self) private var clock
    @Environment(AppRouter.self) private var router
    /// `nil` follows "today", so the diary rolls over at midnight.
    @State private var pinnedDay: DayKey?
    @State private var showingDatePicker = false
    @State private var showingTargets = false
    @State private var showingLibrary = false

    private var day: DayKey { pinnedDay ?? clock.today }

    var body: some View {
        NavigationStack {
            NutritionDayView(day: day, today: clock.today, changeDay: changeDay, pickDate: { showingDatePicker = true })
                .id(day)
                .navigationTitle("Nutrition")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button {
                                showingLibrary = true
                            } label: {
                                Label("Foods & Meals", systemImage: "books.vertical")
                            }
                            Button {
                                showingTargets = true
                            } label: {
                                Label("Targets", systemImage: "target")
                            }
                        } label: {
                            Image(systemName: "books.vertical")
                        }
                        .accessibilityLabel("Foods, meals and targets")
                    }
                }
                .settingsToolbarButton(router)
                .workoutResumeAccessory()
                .sheet(isPresented: $showingDatePicker) {
                    DayPickerSheet(day: day) { picked in
                        pinnedDay = picked == clock.today ? nil : picked
                    }
                }
                .sheet(isPresented: $showingTargets) {
                    NutritionTargetsView()
                }
                .navigationDestination(isPresented: $showingLibrary) {
                    FoodLibraryView()
                }
        }
    }

    private func changeDay(_ offset: Int) {
        Haptics.selection()
        let next = day.adding(days: offset)
        Motion.perform(Motion.quick) {
            pinnedDay = next == clock.today ? nil : next
        }
    }
}

/// The diary for a single day.
struct NutritionDayView: View {
    let day: DayKey
    let today: DayKey
    let changeDay: (Int) -> Void
    let pickDate: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query private var entries: [FoodEntry]
    @Query private var targetRecords: [TargetRecord]

    @State private var editing: FoodEntry?
    @State private var copyTarget: Meal?
    @State private var savingMeal: Meal?
    @State private var showingTargets = false

    init(day: DayKey, today: DayKey, changeDay: @escaping (Int) -> Void, pickDate: @escaping () -> Void) {
        self.day = day
        self.today = today
        self.changeDay = changeDay
        self.pickDate = pickDate
        let key = day.string
        _entries = Query(filter: #Predicate<FoodEntry> { $0.dayKey == key }, sort: \FoodEntry.loggedAt)
    }

    private var targets: NutritionTargets {
        TargetStore.timeline(targetRecords).nutrition(on: day)
    }

    private var totals: Nutrients {
        entries.reduce(Nutrients.zero) { $0 + $1.nutrients }
    }

    var body: some View {
        List {
            Section {
                DayNavigator(day: day, today: today, changeDay: changeDay, pickDate: pickDate)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                NutritionSummaryCard(
                    totals: totals,
                    targets: targets,
                    trackCarbs: settings.values.trackCarbs,
                    trackFat: settings.values.trackFat,
                    hasEntries: !entries.isEmpty,
                    editTargets: { showingTargets = true }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            .listSectionSpacing(Theme.Spacing.m)

            ForEach(Meal.allCases) { meal in
                mealSection(meal)
            }

            Section {
                FootnoteText(text: "Nutrition values are estimates. Entries keep the values they were logged with, even if you edit the food later.")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }
        }
        .listStyle(.insetGrouped)
        .sheet(item: $editing) { entry in
            FoodEntryEditor(entry: entry)
        }
        .sheet(item: $copyTarget) { meal in
            CopyMealSheet(targetDay: day, targetMeal: meal)
        }
        .sheet(item: $savingMeal) { meal in
            SaveMealSheet(entries: entries.filter { $0.meal == meal }, suggestedName: "\(meal.name) \(Format.shortDate(day.middayDate()))")
        }
        .sheet(isPresented: $showingTargets) {
            NutritionTargetsView()
        }
        .motion(Motion.standard, value: entries.count)
    }

    @ViewBuilder
    private func mealSection(_ meal: Meal) -> some View {
        let items = entries.filter { $0.meal == meal }
        let subtotal = items.reduce(Nutrients.zero) { $0 + $1.nutrients }
        Section {
            ForEach(items) { entry in
                Button {
                    editing = entry
                } label: {
                    FoodEntryRow(entry: entry)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        delete(entry)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        duplicate(entry, to: day)
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    .tint(Theme.Palette.accent)
                }
                .contextMenu {
                    Button {
                        editing = entry
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button {
                        duplicate(entry, to: day)
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    if day != today {
                        Button {
                            duplicate(entry, to: today)
                        } label: {
                            Label("Log Again Today", systemImage: "arrow.uturn.forward")
                        }
                    }
                    Menu {
                        ForEach(Meal.allCases.filter { $0 != meal }) { other in
                            Button(other.name) { move(entry, to: other) }
                        }
                    } label: {
                        Label("Move to", systemImage: "arrow.right.circle")
                    }
                    Divider()
                    Button(role: .destructive) {
                        delete(entry)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            Button {
                router.show(.logFood(day: day, meal: meal))
            } label: {
                Label("Add to \(meal.name)", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
            }
        } header: {
            HStack {
                Label(meal.name, systemImage: meal.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
                Spacer()
                if !items.isEmpty {
                    Text("\(Format.calories(subtotal.calories)) kcal")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .numericStyle()
                        .textCase(nil)
                }
                Menu {
                    Button {
                        router.show(.logFood(day: day, meal: meal))
                    } label: {
                        Label("Add Food", systemImage: "plus")
                    }
                    Button {
                        copyTarget = meal
                    } label: {
                        Label("Copy From Another Day", systemImage: "doc.on.doc")
                    }
                    if !items.isEmpty {
                        Button {
                            savingMeal = meal
                        } label: {
                            Label("Save as Meal", systemImage: "square.and.arrow.down")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("\(meal.name) options")
            }
        }
    }

    private func delete(_ entry: FoodEntry) {
        Haptics.tap()
        context.delete(entry)
        try? context.save()
    }

    private func duplicate(_ entry: FoodEntry, to target: DayKey) {
        Haptics.tap()
        let copy = entry.duplicate(to: target, source: target == day ? nil : .copied)
        context.insert(copy)
        try? context.save()
    }

    private func move(_ entry: FoodEntry, to meal: Meal) {
        entry.meal = meal
        entry.updatedAt = Date()
        try? context.save()
    }
}

struct DayNavigator: View {
    let day: DayKey
    let today: DayKey
    let changeDay: (Int) -> Void
    let pickDate: () -> Void

    var body: some View {
        HStack {
            Button {
                changeDay(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(CircleIconButtonStyle(tint: .primary, size: 40))
            .accessibilityLabel("Previous day")

            Spacer()
            Button(action: pickDate) {
                VStack(spacing: 0) {
                    Text(Format.dayTitle(day, today: today))
                        .font(.headline)
                    if day == today || day == today.adding(days: -1) {
                        Text(day.middayDate().formatted(.dateTime.weekday(.wide).month().day()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 44)
                .contentTransition(.opacity)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose a date")
            Spacer()

            Button {
                changeDay(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(CircleIconButtonStyle(tint: .primary, size: 40))
            .disabled(day >= today)
            .opacity(day >= today ? 0.3 : 1)
            .accessibilityLabel("Next day")
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

struct DayPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    let onPick: (DayKey) -> Void

    init(day: DayKey, onPick: @escaping (DayKey) -> Void) {
        _date = State(initialValue: day.middayDate())
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Go to Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Go") {
                            onPick(DayKey(date))
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Calories and macros for one day against the targets in effect that day.
struct NutritionSummaryCard: View {
    let totals: Nutrients
    let targets: NutritionTargets
    let trackCarbs: Bool
    let trackFat: Bool
    let hasEntries: Bool
    var editTargets: (() -> Void)?

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: Theme.Spacing.l) {
                ZStack {
                    ProgressRing(progress: targets.calories.map { totals.calories / max($0, 1) } ?? 0, color: Metric.calories.color, lineWidth: 10)
                    VStack(spacing: 0) {
                        Text(Format.calories(totals.calories))
                            .font(.metric(.title2))
                            .numericStyle()
                            .contentTransition(.numericText(value: totals.calories))
                        Text("kcal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 104, height: 104)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Calories")
                .accessibilityValue(caloriesAccessibilityValue)

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    if let target = targets.calories {
                        let remaining = target - totals.calories
                        Text(remaining >= 0 ? "\(Format.calories(remaining)) kcal left" : "\(Format.calories(-remaining)) kcal over target")
                            .font(.headline)
                            .numericStyle()
                            .contentTransition(.numericText(value: remaining))
                        Text("of \(Format.calories(target)) kcal target")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(hasEntries ? "Eaten so far" : "Nothing logged yet")
                            .font(.headline)
                        if let editTargets {
                            Button("Set a calorie target", action: editTargets)
                                .font(.footnote.weight(.medium))
                                .buttonStyle(.borderless)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: Theme.Spacing.m) {
                MacroRow(metric: .protein, value: totals.protein, target: targets.protein)
                if trackCarbs {
                    MacroRow(metric: .carbs, value: totals.carbs ?? 0, target: targets.carbs)
                }
                if trackFat {
                    MacroRow(metric: .fat, value: totals.fat ?? 0, target: targets.fat)
                }
            }
        }
    }

    private var caloriesAccessibilityValue: String {
        if let target = targets.calories {
            return "\(Format.calories(totals.calories)) of \(Format.calories(target)) kilocalories"
        }
        return "\(Format.calories(totals.calories)) kilocalories"
    }
}

struct MacroRow: View {
    let metric: Metric
    let value: Double
    let target: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Group {
                    if let target {
                        Text("\(Format.grams(value)) / \(Format.grams(target)) g")
                    } else {
                        Text("\(Format.grams(value)) g")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .numericStyle()
                .contentTransition(.numericText(value: value))
            }
            CapsuleProgress(progress: target.map { value / max($0, 1) } ?? (value > 0 ? 1 : 0), color: target == nil ? metric.color.opacity(0.5) : metric.color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(target.map { "\(Format.grams(value)) of \(Format.grams($0)) grams" } ?? "\(Format.grams(value)) grams")
    }
}

struct FoodEntryRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.body)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(entry.quantityDescription)
                    if let eaten = entry.consumedAt {
                        Text("· \(Format.time(eaten))")
                    }
                    if entry.source == .quickEstimate || entry.source == .copied || entry.source == .savedMeal {
                        TagBadge(text: entry.source.label, tint: .secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Spacing.s)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Format.calories(entry.nutrients.calories))")
                    .font(.body.weight(.semibold))
                    .numericStyle()
                Text("\(Format.grams(entry.nutrients.protein)) g protein")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Format.calories(entry.nutrients.calories)) kilocalories")
        .accessibilityHint("Edit entry")
    }
}
