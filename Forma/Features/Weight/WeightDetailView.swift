import SwiftUI
import SwiftData
import FormaKit

struct WeightDetailView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DayClock.self) private var clock
    @Environment(AppRouter.self) private var router
    @Environment(HealthService.self) private var health
    @Environment(\.modelContext) private var context
    @Query(sort: \WeightEntry.measuredAt, order: .reverse) private var entries: [WeightEntry]

    @State private var range: ChartRange = .threeMonths
    @State private var selectedDate: Date?
    @State private var editing: WeightEntry?
    @State private var showingGoalEditor = false
    @State private var showingMethod = false

    private var unit: WeightUnit { settings.unit }

    private var allPoints: [WeightTrendPoint] {
        WeightTrend.compute(entries.map { WeightSample(date: $0.measuredAt, kilograms: $0.kilograms) })
    }

    var body: some View {
        let points = allPoints
        let startDay = range.startDay(today: clock.today, earliest: points.first?.day)
        let visible = points.filter { $0.day >= startDay && $0.day <= clock.today }
        let summary = WeightTrendSummary(points: points, today: clock.today)
        let periodChange = WeightTrend.change(points, from: startDay, through: clock.today)

        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header(summary: summary, periodChange: periodChange, visibleCount: visible.count)
                    RangePicker(range: $range)
                    chart(visible: visible, startDay: startDay)
                    Text(summary.sentence(unit: unit))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let deviation = summary.latestDeviationKg, abs(unit.fromKilograms(deviation)) >= (unit == .kilograms ? 0.5 : 1) {
                        FootnoteText(text: "Your latest weigh-in is \(Format.weight(abs(deviation), unit: unit)) \(deviation > 0 ? "above" : "below") your trend. Single-day changes often come from water, food volume, sodium and timing rather than body fat or muscle.")
                    }
                    Button {
                        showingMethod = true
                    } label: {
                        Label("How the trend is calculated", systemImage: "questionmark.circle")
                            .font(.footnote.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, Theme.Spacing.s)
            }

            Section("Goal") {
                Button {
                    showingGoalEditor = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goalTitle)
                                .foregroundStyle(.primary)
                            if let status = settings.values.goal.status(trendKg: summary.latestTrendKg, unit: unit) {
                                Text(status)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Section {
                if entries.isEmpty {
                    Text("No weigh-ins yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        Button {
                            editing = entry
                        } label: {
                            WeightEntryRow(entry: entry, unit: unit)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                }
            } header: {
                Text("Weigh-ins")
            } footer: {
                if entries.contains(where: \.isImported) {
                    Text("Entries marked Health were imported from Apple Health. Deleting them here doesn't delete them from Apple Health.")
                }
            }
        }
        .navigationTitle("Weight")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.show(.logWeight)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Log weight")
            }
        }
        .sheet(item: $editing) { entry in
            WeightEntrySheet(entry: entry)
        }
        .sheet(isPresented: $showingGoalEditor) {
            GoalEditorView()
        }
        .sheet(isPresented: $showingMethod) {
            TrendMethodSheet()
        }
        .onChange(of: range) { _, _ in selectedDate = nil }
    }

    private var goalTitle: String {
        let goal = settings.values.goal
        guard let direction = goal.direction else { return "Set a goal" }
        switch direction {
        case .maintain:
            if let lo = goal.rangeLowerKg, let hi = goal.rangeUpperKg {
                return "Maintain \(Format.weightValue(lo, unit: unit))–\(Format.weight(hi, unit: unit))"
            }
            return "Maintain"
        case .lose, .gain:
            if let target = goal.targetKg {
                return "\(direction.name) to \(Format.weight(target, unit: unit))"
            }
            return direction.name
        }
    }

    @ViewBuilder
    private func header(summary: WeightTrendSummary, periodChange: Double?, visibleCount: Int) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Trend")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let trend = summary.latestTrendKg {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Format.weightValue(trend, unit: unit))
                            .font(.metric(.largeTitle))
                            .numericStyle()
                            .contentTransition(.numericText())
                        Text(unit.symbol)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("—").font(.metric(.largeTitle))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(range.accessibilityName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let periodChange {
                    Text(Format.weightChange(periodChange, unit: unit))
                        .font(.headline)
                        .numericStyle()
                        .contentTransition(.numericText())
                } else {
                    Text("Not enough data")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func chart(visible: [WeightTrendPoint], startDay: DayKey) -> some View {
        let domain = startDay.startDate()...clock.today.adding(days: 1).startDate()
        ZStack {
            WeightChart(points: visible, unit: unit, goal: settings.values.goal, xDomain: domain, selectedDate: $selectedDate)
                .frame(height: 240)
            if visible.count < 2 {
                VStack(spacing: 4) {
                    Image(systemName: "chart.dots.scatter")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(visible.isEmpty ? "No weigh-ins in this range" : "One weigh-in in this range")
                        .font(.subheadline.weight(.medium))
                    Text("A trend appears once there are a few entries.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weight chart, \(range.accessibilityName.lowercased())")
    }

    private func delete(_ offsets: IndexSet) {
        let targets = offsets.map { entries[$0] }
        Task { @MainActor in
            for entry in targets {
                await health.deleteWrittenWeight(entry)
                context.delete(entry)
            }
            try? context.save()
        }
    }
}

struct WeightEntryRow: View {
    let entry: WeightEntry
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.dateWithYear(entry.measuredAt))
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    Text(Format.time(entry.measuredAt))
                    if !entry.note.isEmpty {
                        Image(systemName: "text.bubble")
                            .accessibilityLabel("Has note")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if entry.isImported {
                TagBadge(text: "Health", symbol: "heart.fill", tint: .pink)
            }
            Text(Format.weight(entry.kilograms, unit: unit))
                .font(.body.weight(.semibold))
                .numericStyle()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit weigh-in")
    }
}

struct TrendMethodSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Text("Body weight naturally moves up and down from day to day — mostly water, the weight of food, salt and timing. The trend line smooths those swings so longer-term change is easier to see.")
                    Text("How it works").font(.headline)
                    Text("Forma averages each day's weigh-ins, then moves the trend 10% of the way toward that day's average. If you skip days, the next weigh-in moves the trend a bit further to account for the gap. No values are made up for days you didn't weigh in.")
                    Text("If there's a gap of more than three weeks, the trend starts fresh rather than drawing a line through time with no data.")
                    Text("What it can't tell you").font(.headline)
                    Text("Weight alone doesn't show whether a change is fat, muscle or water. The weekly rate is a straight-line fit over your last four weeks and needs at least four weigh-ins across ten or more days.")
                }
                .padding(Theme.Spacing.xl)
            }
            .navigationTitle("About the Trend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
