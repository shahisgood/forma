import SwiftUI
import SwiftData
import Charts
import FormaKit

/// Daily steps: today's progress, history chart and statistics.
struct StepsDetailView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HealthService.self) private var health
    @Environment(DayClock.self) private var clock
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \ManualStepEntry.dayKey, order: .reverse) private var manualEntries: [ManualStepEntry]
    @Query private var targetRecords: [TargetRecord]

    @State private var range: ChartRange = .month
    @State private var selectedDate: Date?
    @State private var editingTarget = false

    private var targets: TargetTimeline { TargetStore.timeline(targetRecords) }

    var body: some View {
        let days = StepHistory.days(health: health, manualEntries: manualEntries, manualEnabled: settings.values.manualStepsEnabled)
        let start = range.startDay(today: clock.today, earliest: days.first?.day)
        let visible = days.filter { $0.day >= start && $0.day <= clock.today }
        let stats = StepStatistics(days: days, range: start...clock.today, targets: targets)
        let todayDay = days.first { $0.day == clock.today }

        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    StepsTodayHeader(steps: todayDay?.steps, source: todayDay?.source, target: targets.value(.steps, on: clock.today))
                    HealthStepsStatusView()
                }
                .padding(.vertical, Theme.Spacing.s)
            }

            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    RangePicker(range: $range, options: [.week, .month, .threeMonths, .year])
                    StepsChart(days: visible, start: start, today: clock.today, targets: targets, selectedDate: $selectedDate)
                        .frame(height: 220)
                    HStack(alignment: .top) {
                        StatValue(value: stats.average.map(Format.steps) ?? "—", label: "Daily average", size: .metric(.title3))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        StatValue(
                            value: stats.daysWithTarget > 0 ? "\(stats.daysTargetReached)/\(stats.daysWithTarget)" : "—",
                            label: "Days target reached",
                            size: .metric(.title3)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        StatValue(value: "\(stats.daysWithData)", label: "Days with data", size: .metric(.title3))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if stats.daysWithData > 0 {
                        FootnoteText(text: "Averages only include days with step data. Days without data aren't counted as zero.")
                    }
                    if targets.changed(.steps, between: start, and: clock.today) {
                        FootnoteText(text: "Your step target changed during this period. Each day is compared with the target in effect that day.", symbol: "calendar")
                    }
                }
                .padding(.vertical, Theme.Spacing.s)
            }

            Section {
                Button {
                    editingTarget = true
                } label: {
                    HStack {
                        Text("Daily target")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(targets.value(.steps, on: clock.today).map { Format.steps(Int($0)) } ?? "Not set")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("There's no single right number. Pick a target that fits your days; changing it only affects today onward.")
            }

            if settings.values.manualStepsEnabled {
                Section {
                    Button {
                        router.show(.manualSteps(day: clock.today))
                    } label: {
                        Label("Add Manual Steps", systemImage: "plus")
                    }
                    ForEach(manualEntries.prefix(30)) { entry in
                        let ignored = health.status == .connected && (health.stepsByDay[entry.day] ?? 0) > 0
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Format.dayTitle(entry.day, today: clock.today))
                                if ignored {
                                    Text("Not used — Apple Health has data for this day")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if !entry.note.isEmpty {
                                    Text(entry.note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(Format.steps(entry.steps))
                                .numericStyle()
                                .foregroundStyle(ignored ? .secondary : .primary)
                            TagBadge(text: "Manual")
                        }
                    }
                    .onDelete { offsets in
                        let items = Array(manualEntries.prefix(30))
                        for index in offsets { context.delete(items[index]) }
                        try? context.save()
                    }
                } header: {
                    Text("Manual entries")
                } footer: {
                    Text("Manual counts fill days without Apple Health data. They're never added on top of Health data.")
                }
            }
        }
        .navigationTitle("Steps")
        .refreshable { await health.refreshSteps(force: true) }
        .sheet(isPresented: $editingTarget) {
            StepTargetSheet()
        }
        .onChange(of: range) { _, _ in selectedDate = nil }
    }
}

struct StepsTodayHeader: View {
    let steps: Int?
    let source: StepSource?
    let target: Double?

    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            ZStack {
                ProgressRing(progress: progress ?? 0, color: Metric.steps.color, lineWidth: 10)
                Image(systemName: (progress ?? 0) >= 1 ? "checkmark" : "figure.walk")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Metric.steps.color)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 84, height: 84)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(steps.map(Format.steps) ?? "—")
                    .font(.metric(.largeTitle))
                    .numericStyle()
                    .contentTransition(.numericText(value: Double(steps ?? 0)))
                if let target {
                    Text(caption(target: target))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if source == .manual {
                    TagBadge(text: "Manual entry")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var progress: Double? {
        guard let steps, let target, target > 0 else { return nil }
        return Double(steps) / target
    }

    private func caption(target: Double) -> String {
        let goal = Int(target)
        guard let steps else { return "Target \(Format.steps(goal))" }
        if steps >= goal { return "Target of \(Format.steps(goal)) reached" }
        return "\(Format.steps(goal - steps)) to your \(Format.steps(goal)) target"
    }
}

/// Explains where step data comes from, and what to do if it's missing.
struct HealthStepsStatusView: View {
    @Environment(HealthService.self) private var health
    @Environment(AppSettings.self) private var settings

    var body: some View {
        switch health.status {
        case .unavailable:
            FootnoteText(text: "Apple Health isn't available on this device. You can turn on manual step entry in Settings.", symbol: "heart.slash")
        case .notConnected:
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                FootnoteText(text: "Connect Apple Health to see steps counted by your iPhone and Apple Watch.", symbol: "heart")
                Button("Connect Apple Health") {
                    Task {
                        await health.connect()
                        await health.refreshSteps(force: true)
                    }
                }
                .buttonStyle(SecondaryButtonStyle(tint: .pink))
            }
        case .connected:
            if !settings.values.health.readSteps {
                FootnoteText(text: "Reading steps from Apple Health is turned off in Settings.", symbol: "heart.slash")
            } else if health.hasLoadedSteps && health.stepsByDay.isEmpty {
                FootnoteText(text: "No step data found in Apple Health. If you expected some, check that Forma can read Steps in the Health app under Sharing → Apps → Forma.", symbol: "questionmark.circle")
            } else if !health.hasLoadedSteps {
                HStack(spacing: Theme.Spacing.s) {
                    ProgressView()
                    Text("Loading steps…").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct StepsChart: View {
    let days: [StepDay]
    let start: DayKey
    let today: DayKey
    let targets: TargetTimeline
    @Binding var selectedDate: Date?

    private struct TargetPoint {
        let date: Date
        let value: Double
    }

    private var targetPoints: [TargetPoint] {
        DayKey.range(start, through: today).compactMap { day in
            targets.value(.steps, on: day).map { TargetPoint(date: day.middayDate(), value: $0) }
        }
    }

    var body: some View {
        let upper = ChartScale.zeroBasedUpperBound(values: days.map { Double($0.steps) }, targets: targetPoints.map(\.value), minimum: 2000)
        let selected = selectedDate.flatMap { date in days.first { $0.day == DayKey(date) } }

        Chart {
            ForEach(days) { day in
                let reached = targets.value(.steps, on: day.day).map { Double(day.steps) >= $0 } ?? false
                BarMark(
                    x: .value("Day", day.day.middayDate(), unit: .day),
                    y: .value("Steps", day.steps)
                )
                .foregroundStyle(Metric.steps.color.opacity(reached ? 1 : 0.45))
                .cornerRadius(3)
                .accessibilityLabel(Format.dateWithYear(day.day.middayDate()))
                .accessibilityValue("\(Format.steps(day.steps)) steps\(reached ? ", target reached" : "")\(day.source == .manual ? ", manual" : "")")
            }
            ForEach(targetPoints, id: \.date) { point in
                LineMark(x: .value("Day", point.date, unit: .day), y: .value("Target", point.value), series: .value("Series", "target"))
                    .interpolationMethod(.stepCenter)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.secondary)
                    .accessibilityHidden(true)
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.day.middayDate(), unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.3))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Format.dateWithYear(selected.day.middayDate()))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("\(Format.steps(selected.steps)) steps")
                                .font(.subheadline.weight(.semibold))
                            if selected.source == .manual {
                                Text("Manual entry").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
            }
        }
        .chartYScale(domain: 0...upper)
        .chartXScale(domain: start.startDate()...today.adding(days: 1).startDate())
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel()
            }
        }
        .motion(Motion.chart, value: start)
        .overlay {
            if days.isEmpty {
                Text("No step data in this range")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily steps chart. Solid bars reached the target; lighter bars didn't.")
    }
}

struct StepTargetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var records: [TargetRecord]
    @State private var target = 8000.0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: Theme.Spacing.m) {
                        Text(Format.steps(Int(target)))
                            .font(.metric(.largeTitle))
                            .numericStyle()
                            .contentTransition(.numericText(value: target))
                        Slider(value: $target, in: 2000...25000, step: 500)
                            .tint(Metric.steps.color)
                            .accessibilityValue("\(Format.steps(Int(target))) steps")
                        HStack {
                            ForEach([5000, 7500, 10000, 12500], id: \.self) { preset in
                                Button(Format.steps(preset)) {
                                    Motion.perform(Motion.quick) { target = Double(preset) }
                                }
                                .buttonStyle(SecondaryButtonStyle(tint: Metric.steps.color))
                                .font(.footnote)
                            }
                        }
                    }
                    .padding(.vertical, Theme.Spacing.s)
                } footer: {
                    Text("Applies from today. Earlier days keep the target they had.")
                }
            }
            .navigationTitle("Step Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        TargetStore.set(.steps, to: target, in: context)
                        Haptics.success()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let current = TargetStore.timeline(records).value(.steps, on: .today()) {
                    target = current
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct ManualStepsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @State private var date: Date
    @State private var stepsText = ""
    @State private var note = ""

    init(day: DayKey) {
        _date = State(initialValue: day.middayDate())
    }

    private var steps: Int? {
        guard let value = NumberParsing.integer(from: stepsText), value > 0, value < 200_000 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Day", selection: $date, in: ...Date(), displayedComponents: .date)
                    HStack {
                        Text("Steps")
                        Spacer()
                        TextField("0", text: $stepsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .numericStyle()
                    }
                    TextField("Note (optional)", text: $note)
                } footer: {
                    if health.status == .connected && (health.stepsByDay[DayKey(date)] ?? 0) > 0 {
                        Text("Apple Health already has \(Format.steps(health.stepsByDay[DayKey(date)] ?? 0)) steps for this day, so this entry will be kept but not used.")
                    } else {
                        Text("Shown as a manual entry. If Apple Health has data for this day later, Health is used instead.")
                    }
                }
            }
            .navigationTitle("Manual Steps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let steps else { return }
                        context.insert(ManualStepEntry(day: DayKey(date), steps: steps, note: note))
                        try? context.save()
                        Haptics.success()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(steps == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
