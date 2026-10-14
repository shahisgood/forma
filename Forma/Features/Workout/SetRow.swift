import SwiftUI
import FormaKit

/// One set in the active workout.
///
/// Empty fields show last session's values as placeholders. Those values are
/// only written into the set when the person taps the check button.
struct SetRow: View {
    @Bindable var set: WorkoutSet
    let entry: SessionExercise
    let previous: SetRecord?

    static let badgeWidth: CGFloat = 30
    static let fieldWidth: CGFloat = 60
    static let effortWidth: CGFloat = 42
    static let checkWidth: CGFloat = 46

    @Environment(WorkoutController.self) private var workout
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shake = 0
    @State private var celebrate = false

    private var unit: WeightUnit { settings.unit }
    private var type: ExerciseTrackingType { entry.trackingType }

    var body: some View {
        let suggestion = workout.suggestion(for: set, in: entry)
        let isRecord = workout.recordSetIDs.contains(set.id)

        HStack(spacing: Theme.Spacing.s) {
            badge

            Button {
                fillFromPrevious()
            } label: {
                Text(previousText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: Theme.target, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(previous == nil || set.isCompleted)
            .accessibilityLabel(previous == nil ? "No previous set" : "Previous: \(previousText)")
            .accessibilityHint(previous == nil ? "" : "Fills this set with last time's values")

            if type.usesWeight {
                field(
                    NumberField(placeholder: suggestion.weightKg.map { Format.load($0, unit: unit) } ?? (type == .weightReps ? unit.symbol : "0"), value: .weight($set.weightKg, unit: unit)),
                    label: type == .assistedReps ? "Assistance, \(unit.name)" : "Weight, \(unit.name)"
                )
            }
            if type.usesReps {
                field(
                    NumberField(placeholder: suggestion.reps.map(String.init) ?? "0", value: .integer($set.reps), allowsDecimal: false),
                    label: "Reps"
                )
            }
            if type.usesDistance {
                field(
                    NumberField(placeholder: suggestion.distanceMeters.map { Format.number($0, maxFraction: 0) } ?? "0", value: $set.distanceMeters, fractionDigits: 0),
                    label: "Distance, metres"
                )
            }
            if type.usesDuration {
                field(
                    NumberField(placeholder: suggestion.durationSeconds.map { Format.number($0, maxFraction: 0) } ?? "0", value: $set.durationSeconds, fractionDigits: 0),
                    label: "Time, seconds"
                )
            }
            if settings.values.trackEffort {
                NumberField(placeholder: "–", value: $set.rpe, fractionDigits: 1)
                    .font(.subheadline)
                    .frame(width: Self.effortWidth, height: Theme.target)
                    .background(Theme.Palette.fill, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                    .accessibilityLabel("Effort, RPE 1 to 10")
                    .onChange(of: set.rpe) { _, value in
                        if let value, value > 10 { set.rpe = 10 }
                        workout.scheduleSave()
                    }
            }

            completeButton
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(set.isCompleted ? Metric.steps.color.opacity(0.12) : Color.clear)
        )
        .overlay(alignment: .topTrailing) {
            if isRecord {
                RecordBadge()
                    .scaleEffect(celebrate ? 1 : 0.85)
                    .offset(x: 4, y: -10)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .onAppear {
                        guard !reduceMotion else {
                            celebrate = true
                            return
                        }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { celebrate = true }
                    }
            }
        }
        .modifier(ShakeEffect(animatableData: CGFloat(shake)))
        .motion(Motion.quick, value: set.isCompleted)
        .motion(Motion.emphasized, value: isRecord)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .onChange(of: set.weightKg) { _, _ in workout.scheduleSave() }
        .onChange(of: set.reps) { _, _ in workout.scheduleSave() }
        .onChange(of: set.durationSeconds) { _, _ in workout.scheduleSave() }
        .onChange(of: set.distanceMeters) { _, _ in workout.scheduleSave() }
        .contextMenu {
            Button {
                workout.toggleKind(set, in: entry)
            } label: {
                Label(set.kind == .warmup ? "Mark as Working Set" : "Mark as Warm-up", systemImage: "flame")
            }
            Button(role: .destructive) {
                workout.removeSet(set, from: entry)
            } label: {
                Label("Delete Set", systemImage: "trash")
            }
        }
    }

    // MARK: Pieces

    private var badge: some View {
        Menu {
            Button {
                workout.toggleKind(set, in: entry)
            } label: {
                Label(set.kind == .warmup ? "Mark as Working Set" : "Mark as Warm-up", systemImage: "flame")
            }
            Button(role: .destructive) {
                workout.removeSet(set, from: entry)
            } label: {
                Label("Delete Set", systemImage: "trash")
            }
        } label: {
            Text(badgeText)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(set.kind == .warmup ? Color.orange : Color.primary)
                .frame(width: Self.badgeWidth, height: Theme.target)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(set.kind == .warmup ? Color.orange.opacity(0.14) : Theme.Palette.fill)
                )
        }
        .accessibilityLabel(set.kind == .warmup ? "Warm-up set" : "Set \(badgeText)")
        .accessibilityHint("Set options")
    }

    private var badgeText: String {
        if set.kind == .warmup { return "W" }
        let working = entry.orderedSets.filter { $0.kind == .working }
        return "\((working.firstIndex { $0.id == set.id } ?? 0) + 1)"
    }

    private var previousText: String {
        guard let previous else { return "—" }
        switch type {
        case .weightReps:
            return "\(previous.weightKg.map { Format.load($0, unit: unit) } ?? "—") × \(previous.reps.map(String.init) ?? "—")"
        default:
            return SetDescription.short(weightKg: previous.weightKg, reps: previous.reps, durationSeconds: previous.durationSeconds, distanceMeters: previous.distanceMeters, trackingType: type, unit: unit)
        }
    }

    private func field(_ field: NumberField, label: String) -> some View {
        field
            .font(.body.weight(.semibold))
            .numericStyle()
            .frame(width: Self.fieldWidth, height: Theme.target)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(set.isCompleted ? Color.clear : Theme.Palette.fill)
            )
            .accessibilityLabel(label)
    }

    private var completeButton: some View {
        Button {
            switch workout.toggleCompletion(set, in: entry) {
            case .completed:
                Haptics.tap()
            case .uncompleted:
                Haptics.selection()
            case .missingValues:
                Haptics.warning()
                if !reduceMotion {
                    withAnimation(.linear(duration: 0.35)) { shake += 1 }
                }
            }
        } label: {
            Image(systemName: "checkmark")
                .font(.body.weight(.bold))
                .foregroundStyle(set.isCompleted ? Color.white : Color.secondary)
                .frame(width: Self.checkWidth, height: Theme.target)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(set.isCompleted ? Metric.steps.color : Theme.Palette.fill)
                )
                .scaleEffect(set.isCompleted ? 1 : 0.96)
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(set.isCompleted ? "Completed" : "Complete set")
        .accessibilityHint(set.isCompleted ? "Marks the set as not done" : "Uses the shown values if fields are empty")
        .accessibilityAddTraits(set.isCompleted ? .isSelected : [])
    }

    private func fillFromPrevious() {
        guard let previous, !set.isCompleted else { return }
        Haptics.selection()
        if type.usesWeight { set.weightKg = previous.weightKg }
        if type.usesReps { set.reps = previous.reps }
        if type.usesDuration { set.durationSeconds = previous.durationSeconds }
        if type.usesDistance { set.distanceMeters = previous.distanceMeters }
        workout.scheduleSave()
    }
}

/// Horizontal shake for invalid input.
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(animatableData * .pi * 4), y: 0))
    }
}

// MARK: - Rest timer

struct RestTimerBar: View {
    let rest: RestTimerStore.State

    @Environment(WorkoutController.self) private var workout

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let total = max(1, rest.endsAt.timeIntervalSince(rest.startedAt))
            let remaining = max(0, rest.endsAt.timeIntervalSince(context.date))
            HStack(spacing: Theme.Spacing.m) {
                ZStack {
                    ProgressRing(progress: remaining / total, color: Metric.training.color, lineWidth: 5)
                    Image(systemName: "timer")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Metric.training.color)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Rest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(timerInterval: rest.startedAt...max(rest.startedAt, rest.endsAt), countsDown: true)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Rest timer, \(Int(remaining.rounded())) seconds left")

                Spacer()

                Button {
                    Haptics.tap()
                    workout.adjustRest(by: -15)
                } label: {
                    Text("−15")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(CircleIconButtonStyle(tint: .secondary, size: 44))
                .accessibilityLabel("Subtract 15 seconds")

                Button {
                    Haptics.tap()
                    workout.adjustRest(by: 15)
                } label: {
                    Text("+15")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(CircleIconButtonStyle(tint: .secondary, size: 44))
                .accessibilityLabel("Add 15 seconds")

                Button("Skip") {
                    Haptics.tap()
                    Motion.perform { workout.skipRest() }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(SecondaryButtonStyle(tint: Metric.training.color, fullWidth: false))
            }
        }
        .padding(Theme.Spacing.m)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.separator.opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 16, y: 6)
    }
}

// MARK: - Reorder

struct ReorderExercisesSheet: View {
    @Environment(WorkoutController.self) private var workout
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let session = workout.session {
                    ForEach(session.orderedExercises) { entry in
                        HStack {
                            Text(entry.exerciseName)
                            Spacer()
                            Text("\(entry.sets.count) sets")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onMove { workout.move(from: $0, to: $1) }
                    .onDelete { offsets in
                        let ordered = session.orderedExercises
                        for index in offsets { workout.remove(ordered[index]) }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Summary

struct WorkoutSummaryView: View {
    let summary: WorkoutSummary

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    VStack(spacing: Theme.Spacing.m) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 56, weight: .semibold))
                            .foregroundStyle(Metric.steps.color)
                            .scaleEffect(appeared || reduceMotion ? 1 : 0.85)
                            .opacity(appeared || reduceMotion ? 1 : 0)
                            .accessibilityHidden(true)
                        Text("Workout saved")
                            .font(.title2.weight(.bold))
                        Text(summary.name)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, Theme.Spacing.xl)

                    HStack {
                        StatValue(value: Format.durationWords(summary.duration), label: "Duration", size: .metric(.title3))
                            .frame(maxWidth: .infinity)
                        StatValue(value: "\(summary.completedSets)", label: "Sets", size: .metric(.title3))
                            .frame(maxWidth: .infinity)
                        StatValue(value: "\(summary.exerciseCount)", label: "Exercises", size: .metric(.title3))
                            .frame(maxWidth: .infinity)
                    }
                    .padding(Theme.Spacing.l)
                    .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                    if !summary.records.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                            Label("Personal records", systemImage: "trophy.fill")
                                .font(.headline)
                                .foregroundStyle(Theme.Palette.record)
                            ForEach(Array(summary.records.enumerated()), id: \.offset) { index, item in
                                Text(StrengthHighlight(exerciseName: item.exerciseName, trackingType: item.trackingType, record: item.record, date: Date()).sentence(unit: settings.unit))
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .opacity(appeared || reduceMotion ? 1 : 0)
                                    .offset(y: appeared || reduceMotion ? 0 : 6)
                                    .animation(reduceMotion ? nil : Motion.standard.delay(0.15 + Double(index) * 0.05), value: appeared)
                            }
                            Text("Estimated 1RM values are estimates based on reps and weight.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(Theme.Spacing.l)
                        .background(Theme.Palette.record.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                withAnimation(reduceMotion ? nil : Motion.emphasized) { appeared = true }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
