import SwiftUI
import SwiftData
import Charts
import FormaKit

/// Progress for one exercise: chart, bests and per-session history.
struct ExerciseDetailView: View {
    let exercise: Exercise

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @State private var metric: ProgressionMetric = .estimatedMax
    @State private var range: ChartRange = .threeMonths
    @State private var selectedDate: Date?
    @State private var editing = false

    private var unit: WeightUnit { settings.unit }

    enum ProgressionMetric: String, CaseIterable, Identifiable {
        case estimatedMax = "Est. 1RM"
        case topWeight = "Top set"
        case volume = "Volume"
        case bestReps = "Best reps"
        case totalReps = "Total reps"
        case duration = "Time"
        case distance = "Distance"

        var id: String { rawValue }

        static func options(for type: ExerciseTrackingType) -> [ProgressionMetric] {
            switch type {
            case .weightReps: return [.estimatedMax, .topWeight, .volume]
            case .bodyweightReps, .assistedReps: return [.bestReps, .totalReps]
            case .duration: return [.duration]
            case .distanceDuration: return [.distance, .duration]
            }
        }
    }

    private var records: [SetRecord] { exercise.completedSetRecords() }

    private var summaries: [ExerciseSessionSummary] { ExerciseProgression.summaries(records) }

    private func value(_ summary: ExerciseSessionSummary) -> Double? {
        switch metric {
        case .estimatedMax: return summary.bestEstimated1RM.map(unit.fromKilograms)
        case .topWeight: return summary.topWeight.map(unit.fromKilograms)
        case .volume: return summary.volume.map(unit.fromKilograms)
        case .bestReps: return summary.bestReps.map(Double.init)
        case .totalReps: return Double(summary.totalReps)
        case .duration: return summary.bestDuration
        case .distance: return summary.bestDistance
        }
    }

    private func formatted(_ value: Double) -> String {
        switch metric {
        case .estimatedMax, .topWeight: return "\(Format.number(value)) \(unit.symbol)"
        case .volume: return "\(Int(value.rounded()).formatted()) \(unit.symbol)"
        case .bestReps, .totalReps: return "\(Int(value)) reps"
        case .duration: return SetDescription.formatDuration(value)
        case .distance: return SetDescription.formatDistance(value)
        }
    }

    var body: some View {
        let all = summaries
        let today = DayKey.today()
        let start = range.startDay(today: today, earliest: all.first.map { DayKey($0.date) })
        let visible = all.filter { DayKey($0.date) >= start }
        let recordSessions = sessionsWithRecords()

        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    let options = ProgressionMetric.options(for: exercise.trackingType)
                    if options.count > 1 {
                        Picker("Metric", selection: $metric) {
                            ForEach(options) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    RangePicker(range: $range, options: [.month, .threeMonths, .year, .all])
                    progressionChart(visible, start: start, today: today)
                    metricFootnote
                }
                .padding(.vertical, Theme.Spacing.s)
            }

            if exercise.trackingType == .weightReps, !records.isEmpty {
                Section {
                    bestsGrid
                } header: {
                    Text("Bests")
                }
                Section {
                    ForEach(ExerciseProgression.repMaxTable(records, maxReps: 10), id: \.reps) { row in
                        HStack {
                            Text("\(row.reps)+ rep\(row.reps == 1 ? "" : "s")")
                            Spacer()
                            Text(Format.weight(row.weightKg, unit: unit, fractionDigits: 2))
                                .fontWeight(.semibold)
                                .numericStyle()
                            Text(Format.shortDate(row.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                } header: {
                    Text("Heaviest weight by reps")
                } footer: {
                    Text("The heaviest weight you've lifted for at least that many reps in a working set.")
                }
            }

            Section("History") {
                if all.isEmpty {
                    Text("No completed sets yet. Your history will build up as you train.")
                        .foregroundStyle(.secondary)
                }
                ForEach(historyEntries(), id: \.entry.id) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(Format.dateWithYear(item.date))
                                .font(.subheadline.weight(.semibold))
                            if recordSessions.contains(item.sessionID) {
                                RecordBadge()
                            }
                            Spacer()
                            Text(item.sessionName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(item.entry.orderedSets.filter(\.isCompleted).enumerated()), id: \.element.id) { index, set in
                            HStack {
                                Text(set.kind == .warmup ? "W" : "\(index + 1)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(set.kind == .warmup ? Color.orange : Color.secondary)
                                    .frame(width: 20, alignment: .leading)
                                Text(SetDescription.short(weightKg: set.weightKg, reps: set.reps, durationSeconds: set.durationSeconds, distanceMeters: set.distanceMeters, trackingType: exercise.trackingType, unit: unit))
                                    .font(.subheadline)
                                    .numericStyle()
                                if let rpe = set.rpe {
                                    Text("RPE \(Format.number(rpe))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if !item.entry.notes.isEmpty {
                            Text(item.entry.notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if !exercise.notes.isEmpty {
                Section("Notes") {
                    Text(exercise.notes)
                }
            }

            if exercise.isCustom {
                Section {
                    Button(exercise.isArchived ? "Restore Exercise" : "Archive Exercise") {
                        exercise.isArchived.toggle()
                        try? context.save()
                    }
                } footer: {
                    Text("Archived exercises are hidden from pickers but keep their history.")
                }
            }
        }
        .navigationTitle(exercise.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            ExerciseEditorView(exercise: exercise)
        }
        .onAppear {
            let options = ProgressionMetric.options(for: exercise.trackingType)
            if !options.contains(metric) { metric = options[0] }
        }
        .onChange(of: range) { _, _ in selectedDate = nil }
    }

    private struct ChartPoint: Identifiable {
        var id: UUID { summary.sessionID }
        let summary: ExerciseSessionSummary
        let value: Double
    }

    @ViewBuilder
    private func progressionChart(_ visible: [ExerciseSessionSummary], start: DayKey, today: DayKey) -> some View {
        let points: [ChartPoint] = visible.compactMap { summary in
            value(summary).map { ChartPoint(summary: summary, value: $0) }
        }
        let selected: ChartPoint? = selectedDate.flatMap { date in
            points.min { abs($0.summary.date.timeIntervalSince(date)) < abs($1.summary.date.timeIntervalSince(date)) }
        }
        let domain = ChartScale.domain(for: points.map(\.value), minimumSpan: minimumSpan, padding: 0.15) ?? 0...1

        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let latest = points.last {
                VStack(alignment: .leading, spacing: 0) {
                    Text(metric == .estimatedMax ? "Latest estimate" : "Latest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatted(latest.value))
                        .font(.metric(.title))
                        .numericStyle()
                        .contentTransition(.numericText())
                    if let first = points.first, points.count > 1 {
                        let change = latest.value - first.value
                        Text("\(change >= 0 ? "+" : "−")\(formatted(abs(change))) since \(Format.shortDate(first.summary.date))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ZStack {
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("Date", point.summary.date, unit: .day), y: .value(metric.rawValue, point.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Metric.training.color)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .accessibilityHidden(true)
                        PointMark(x: .value("Date", point.summary.date, unit: .day), y: .value(metric.rawValue, point.value))
                            .foregroundStyle(Metric.training.color)
                            .symbolSize(30)
                            .accessibilityLabel(Format.dateWithYear(point.summary.date))
                            .accessibilityValue(formatted(point.value))
                    }
                    if let selected {
                        RuleMark(x: .value("Selected", selected.summary.date, unit: .day))
                            .foregroundStyle(Color.secondary.opacity(0.35))
                            .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(Format.dateWithYear(selected.summary.date))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(formatted(selected.value))
                                        .font(.subheadline.weight(.semibold))
                                    if let top = selected.summary.topWeight, let reps = selected.summary.topWeightReps, metric != .volume {
                                        Text("Top set \(Format.weight(top, unit: unit)) × \(reps)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                    }
                }
                .chartYScale(domain: domain)
                .chartXScale(domain: start.startDate()...today.adding(days: 1).startDate())
                .chartXSelection(value: $selectedDate)
                .frame(height: 210)
                .motion(Motion.chart, value: metric)

                if points.count < 2 {
                    Text(points.isEmpty ? "No sessions in this range" : "One session in this range — progress appears after the next.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(metric.rawValue) over time")
        }
    }

    private var minimumSpan: Double {
        switch metric {
        case .estimatedMax, .topWeight: return unit == .kilograms ? 10 : 20
        case .volume: return unit == .kilograms ? 500 : 1000
        case .bestReps, .totalReps: return 4
        case .duration: return 30
        case .distance: return 100
        }
    }

    @ViewBuilder
    private var metricFootnote: some View {
        switch metric {
        case .estimatedMax:
            FootnoteText(text: "Estimated from your working sets of 12 reps or fewer using the Epley formula. It's an estimate, not a tested max.")
        case .volume:
            FootnoteText(text: "Volume is weight × reps across working sets. It's only comparable for this exercise, and more isn't automatically better.")
        case .topWeight:
            FootnoteText(text: "Heaviest working set each session, regardless of reps.")
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var bestsGrid: some View {
        let best1RM = records.compactMap { r in r.weightKg.flatMap { w in r.reps.flatMap { OneRepMax.epley(weightKg: w, reps: $0) } } }.max()
        let heaviest = records.filter { $0.isWorking && ($0.reps ?? 0) > 0 }.max { ($0.weightKg ?? 0) < ($1.weightKg ?? 0) }
        HStack(alignment: .top) {
            StatValue(value: best1RM.map { Format.weightValue($0, unit: unit) } ?? "—", unit: unit.symbol, label: "Best est. 1RM", size: .metric(.title3))
                .frame(maxWidth: .infinity, alignment: .leading)
            StatValue(
                value: heaviest?.weightKg.map { Format.weightValue($0, unit: unit) } ?? "—",
                unit: heaviest.map { "\(unit.symbol) × \($0.reps ?? 0)" },
                label: "Heaviest set",
                size: .metric(.title3)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct HistoryItem {
        let entry: SessionExercise
        let date: Date
        let sessionID: UUID
        let sessionName: String
    }

    private func historyEntries() -> [HistoryItem] {
        exercise.sessionEntries.compactMap { entry -> HistoryItem? in
            guard let session = entry.session, session.endedAt != nil, entry.sets.contains(where: \.isCompleted) else { return nil }
            return HistoryItem(entry: entry, date: session.startedAt, sessionID: session.id, sessionName: session.name)
        }
        .sorted { $0.date > $1.date }
    }

    /// Sessions in which this exercise set a record relative to everything before it.
    private func sessionsWithRecords() -> Set<UUID> {
        let bySession = Dictionary(grouping: records, by: \.sessionID)
        let ordered = bySession.keys.sorted { (bySession[$0]?.first?.date ?? .distantPast) < (bySession[$1]?.first?.date ?? .distantPast) }
        var history: [SetRecord] = []
        var result = Set<UUID>()
        for id in ordered {
            let sets = bySession[id] ?? []
            if !PersonalRecords.detect(newSets: sets, history: history, trackingType: exercise.trackingType).isEmpty {
                result.insert(id)
            }
            history.append(contentsOf: sets)
        }
        return result
    }
}
