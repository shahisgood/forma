import SwiftUI
import UIKit
import SwiftData
import FormaKit

/// The in-progress workout. Designed for one-handed use between sets: large
/// targets, prefilled values from last time, minimal typing.
struct ActiveWorkoutView: View {
    @Environment(WorkoutController.self) private var workout
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var addingExercises = false
    @State private var reordering = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var nothingCompletedAlert = false
    @FocusState private var notesFocused: Bool

    var body: some View {
        NavigationStack {
            if let session = workout.session {
                content(session)
            } else {
                ContentUnavailableView("No Workout in Progress", systemImage: "dumbbell")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { workout.isPresented = false }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func content(_ session: WorkoutSession) -> some View {
        @Bindable var session = session
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                header(session)

                if session.exercises.isEmpty {
                    EmptyStateCard(
                        symbol: "plus.circle",
                        title: "Add your first exercise",
                        message: "Pick exercises from the library. Each one shows what you did last time.",
                        tint: Metric.training.color,
                        actionTitle: "Add Exercises"
                    ) {
                        addingExercises = true
                    }
                }

                ForEach(session.orderedExercises) { entry in
                    ExerciseCard(entry: entry)
                        .transition(.lift)
                }

                if !session.exercises.isEmpty {
                    Button {
                        addingExercises = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: Metric.training.color))
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Workout notes")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("How's it going?", text: $session.notes, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($notesFocused)
                        .padding(Theme.Spacing.m)
                        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
                        .onChange(of: session.notes) { _, _ in workout.scheduleSave() }
                }

                Button {
                    attemptFinish(session)
                } label: {
                    Label("Finish Workout", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle(tint: Metric.steps.color))
                .padding(.top, Theme.Spacing.s)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, 120)
            .motion(Motion.standard, value: session.exercises.count)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.Palette.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let rest = workout.rest {
                RestTimerBar(rest: rest)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.bottom, Theme.Spacing.s)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .motion(Motion.emphasized, value: workout.rest?.endsAt)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    workout.saveNow()
                    workout.isPresented = false
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("Minimize workout")
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(session.startedAt, style: .timer)
                        .font(.headline)
                        .monospacedDigit()
                    Text("Elapsed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        newName = session.name
                        renaming = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button {
                        reordering = true
                    } label: {
                        Label("Reorder Exercises", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(session.exercises.count < 2)
                    Divider()
                    Button(role: .destructive) {
                        confirmDiscard = true
                    } label: {
                        Label("Discard Workout", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("Workout options")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $addingExercises) {
            ExercisePickerView(title: "Add Exercises") { picked in
                workout.addExercises(picked)
            }
        }
        .sheet(isPresented: $reordering) {
            ReorderExercisesSheet()
        }
        .alert("Rename Workout", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") { workout.rename(newName) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Finish workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish Workout") { workout.finish() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            let unchecked = session.totalSetCount - session.completedSetCount
            Text("\(unchecked) set\(unchecked == 1 ? " isn't" : "s aren't") checked off and won't be saved.")
        }
        .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Workout", role: .destructive) { workout.discard() }
            Button("Keep Workout", role: .cancel) {}
        } message: {
            Text("All sets from this session will be deleted.")
        }
        .alert("No sets completed", isPresented: $nothingCompletedAlert) {
            Button("Keep Going", role: .cancel) {}
            Button("Discard Workout", role: .destructive) { workout.discard() }
        } message: {
            Text("Check off at least one set to save this workout, or discard it.")
        }
    }

    @ViewBuilder
    private func header(_ session: WorkoutSession) -> some View {
        let total = session.totalSetCount
        let done = session.completedSetCount
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(session.name)
                .font(.largeTitle.weight(.bold))
                .lineLimit(2)
                .onTapGesture {
                    newName = session.name
                    renaming = true
                }
                .accessibilityAddTraits(.isHeader)
                .accessibilityHint("Double tap to rename")
            HStack(spacing: Theme.Spacing.m) {
                CapsuleProgress(progress: total > 0 ? Double(done) / Double(total) : 0, color: Metric.training.color, height: 6)
                Text("\(done)/\(total) sets")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .numericStyle()
                    .contentTransition(.numericText(value: Double(done)))
                    .fixedSize()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(done) of \(total) sets completed")
        }
        .padding(.top, Theme.Spacing.s)
    }

    private func attemptFinish(_ session: WorkoutSession) {
        if session.completedSetCount == 0 {
            nothingCompletedAlert = true
        } else if session.completedSetCount < session.totalSetCount {
            confirmFinish = true
        } else {
            workout.finish()
        }
    }
}

// MARK: - Exercise card

struct ExerciseCard: View {
    let entry: SessionExercise

    @Environment(WorkoutController.self) private var workout
    @Environment(AppSettings.self) private var settings
    @State private var showingNotes = false
    @State private var showingHistory = false

    private var unit: WeightUnit { settings.unit }

    var body: some View {
        let previous = workout.previousSets(for: entry)
        let type = entry.trackingType
        let completed = entry.sets.filter(\.isCompleted).count
        let allDone = completed == entry.sets.count && !entry.sets.isEmpty

        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.exerciseName)
                            .font(.title3.weight(.semibold))
                        if allDone {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Metric.steps.color)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                                .accessibilityLabel("All sets done")
                        }
                    }
                    if !previous.isEmpty {
                        Button {
                            showingHistory = true
                        } label: {
                            Text("Last: " + previousSummary(previous, type: type))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows recent history")
                    } else {
                        Text("First time — no previous sets")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let target = targetDescription {
                        Text(target)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Metric.training.color)
                    }
                }
                Spacer()
                exerciseMenu
            }
            .motion(Motion.emphasized, value: allDone)

            if !entry.notes.isEmpty || showingNotes {
                NotesField(entry: entry)
            }

            SetColumnsHeader(type: type, unit: unit, showsEffort: settings.values.trackEffort)

            VStack(spacing: Theme.Spacing.s) {
                ForEach(entry.orderedSets) { set in
                    SetRow(set: set, entry: entry, previous: previousSet(for: set, in: previous))
                        .transition(.lift)
                }
            }
            .motion(Motion.standard, value: entry.sets.count)

            HStack(spacing: Theme.Spacing.s) {
                Button {
                    Haptics.tap()
                    workout.addSet(to: entry)
                } label: {
                    Label("Add Set", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle(tint: Metric.training.color))
                Button {
                    workout.startRest(seconds: entry.restSeconds ?? settings.values.defaultRestSeconds)
                } label: {
                    Label(Format.restClock(entry.restSeconds ?? settings.values.defaultRestSeconds), systemImage: "timer")
                }
                .buttonStyle(SecondaryButtonStyle(tint: .secondary, fullWidth: false))
                .accessibilityLabel("Start rest timer, \(Format.restClock(entry.restSeconds ?? settings.values.defaultRestSeconds))")
            }
        }
        .padding(Theme.Spacing.l)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .sheet(isPresented: $showingHistory) {
            if let exercise = entry.exercise {
                NavigationStack {
                    ExerciseDetailView(exercise: exercise)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingHistory = false }
                            }
                        }
                }
            }
        }
    }

    private var exerciseMenu: some View {
        Menu {
            Button {
                workout.addSet(to: entry, kind: .warmup)
            } label: {
                Label("Add Warm-up Set", systemImage: "flame")
            }
            Button {
                showingNotes = true
            } label: {
                Label(entry.notes.isEmpty ? "Add Note" : "Edit Note", systemImage: "note.text")
            }
            Menu {
                ForEach([45, 60, 90, 120, 150, 180, 240], id: \.self) { seconds in
                    Button {
                        entry.restSeconds = seconds
                        workout.scheduleSave()
                    } label: {
                        if (entry.restSeconds ?? settings.values.defaultRestSeconds) == seconds {
                            Label(Format.restClock(seconds), systemImage: "checkmark")
                        } else {
                            Text(Format.restClock(seconds))
                        }
                    }
                }
            } label: {
                Label("Rest Time", systemImage: "timer")
            }
            Divider()
            Button {
                workout.moveExercise(entry, by: -1)
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            Button {
                workout.moveExercise(entry, by: 1)
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
            Divider()
            Button(role: .destructive) {
                workout.remove(entry)
            } label: {
                Label("Remove Exercise", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: Theme.target, height: Theme.target)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("\(entry.exerciseName) options")
    }

    private var targetDescription: String? {
        switch (entry.targetRepLow, entry.targetRepHigh) {
        case let (lo?, hi?) where lo != hi: return "Target \(lo)–\(hi) reps"
        case let (lo?, _): return "Target \(lo) reps"
        default: return nil
        }
    }

    private func previousSummary(_ sets: [SetRecord], type: ExerciseTrackingType) -> String {
        let working = sets.filter(\.isWorking)
        let shown = working.isEmpty ? sets : working
        let date = shown.first.map { Format.relative($0.date) } ?? ""
        if type == .weightReps {
            let weights = Set(shown.compactMap { $0.weightKg.map { Rounding.round($0, fractionDigits: 2) } })
            if weights.count == 1, let w = weights.first {
                let reps = shown.compactMap { $0.reps.map(String.init) }.joined(separator: ", ")
                return "\(Format.weight(w, unit: unit, fractionDigits: 2)) × \(reps) · \(date)"
            }
        }
        let parts = shown.prefix(4).map {
            SetDescription.short(weightKg: $0.weightKg, reps: $0.reps, durationSeconds: $0.durationSeconds, distanceMeters: $0.distanceMeters, trackingType: type, unit: unit)
        }
        return parts.joined(separator: ", ") + (shown.count > 4 ? "…" : "") + " · \(date)"
    }

    /// The set from last time in the same position (within warm-ups or working sets).
    private func previousSet(for set: WorkoutSet, in previous: [SetRecord]) -> SetRecord? {
        let sameKindNow = entry.orderedSets.filter { $0.kind == set.kind }
        guard let index = sameKindNow.firstIndex(where: { $0.id == set.id }) else { return nil }
        let sameKindBefore = previous.filter { $0.kind == set.kind }
        return index < sameKindBefore.count ? sameKindBefore[index] : nil
    }
}

private struct NotesField: View {
    @Bindable var entry: SessionExercise
    @Environment(WorkoutController.self) private var workout

    var body: some View {
        TextField("Note for this exercise", text: $entry.notes, axis: .vertical)
            .font(.subheadline)
            .lineLimit(1...4)
            .padding(Theme.Spacing.s)
            .background(Theme.Palette.fill, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            .onChange(of: entry.notes) { _, _ in workout.scheduleSave() }
    }
}

struct SetColumnsHeader: View {
    let type: ExerciseTrackingType
    let unit: WeightUnit
    let showsEffort: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("SET").frame(width: SetRow.badgeWidth)
            Text("PREVIOUS").frame(maxWidth: .infinity, alignment: .leading)
            if type.usesWeight {
                Text(type == .assistedReps ? "−\(unit.symbol.uppercased())" : (type == .bodyweightReps ? "+\(unit.symbol.uppercased())" : unit.symbol.uppercased()))
                    .frame(width: SetRow.fieldWidth)
            }
            if type.usesReps { Text("REPS").frame(width: SetRow.fieldWidth) }
            if type.usesDistance { Text("M").frame(width: SetRow.fieldWidth) }
            if type.usesDuration { Text("SEC").frame(width: SetRow.fieldWidth) }
            if showsEffort { Text("RPE").frame(width: SetRow.effortWidth) }
            Color.clear.frame(width: SetRow.checkWidth, height: 1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}
