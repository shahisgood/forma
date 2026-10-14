import SwiftUI
import UIKit
import SwiftData
import FormaKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(LiveActivityService.self) private var liveActivities
    @Environment(HealthService.self) private var health
    @Environment(NotificationService.self) private var notifications

    @State private var showingGoal = false
    @State private var showingTargets = false
    @State private var showingStepTarget = false

    private let restOptions = [45, 60, 75, 90, 120, 150, 180, 240, 300]

    var body: some View {
        NavigationStack {
            Form {
                Section("Body") {
                    Picker("Units", selection: settings.binding(\.weightUnit)) {
                        ForEach(WeightUnit.allCases) { Text($0.name).tag($0) }
                    }
                    Button {
                        showingGoal = true
                    } label: {
                        LabeledContent("Weight goal", value: settings.values.goal.direction?.name ?? "None")
                    }
                    .foregroundStyle(.primary)
                }

                Section {
                    Button {
                        showingTargets = true
                    } label: {
                        Label("Nutrition targets", systemImage: "target")
                    }
                    Button {
                        showingStepTarget = true
                    } label: {
                        Label("Step target", systemImage: "figure.walk")
                    }
                    Toggle(isOn: settings.binding(\.manualStepsEnabled)) {
                        Label("Manual step entry", systemImage: "hand.tap")
                    }
                } header: {
                    Text("Targets")
                } footer: {
                    Text("Manual steps are for days without Apple Health data and are always labelled as manual.")
                }
                .foregroundStyle(.primary)

                Section("Training") {
                    NavigationLink {
                        TrainingScheduleForm()
                    } label: {
                        LabeledContent("Training days", value: settings.values.trainingDays.isEmpty ? "None" : RoutineSchedule(kind: .weekdays, weekdays: settings.values.trainingDays).summary())
                    }
                    Picker("Default rest", selection: settings.binding(\.defaultRestSeconds)) {
                        ForEach(restOptions, id: \.self) { Text(Format.restClock($0)).tag($0) }
                    }
                    Toggle("Start rest timer after each set", isOn: settings.binding(\.autoStartRestTimer))
                    Toggle("Track effort (RPE)", isOn: settings.binding(\.trackEffort))
                }

                Section {
                    NavigationLink {
                        RoutinesView()
                    } label: {
                        Label("Routines", systemImage: "checklist")
                    }
                    NavigationLink {
                        RemindersSettingsView()
                    } label: {
                        HStack {
                            Label("Reminders", systemImage: "bell")
                            Spacer()
                            if notifications.isDenied {
                                Text("Off in iOS Settings").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    NavigationLink {
                        HealthSettingsView()
                    } label: {
                        HStack {
                            Label("Apple Health", systemImage: "heart")
                            Spacer()
                            Text(healthStatusText).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle("Show workout on Lock Screen", isOn: settings.binding(\.liveActivities.enabled))
                    Toggle("Include workout details", isOn: settings.binding(\.liveActivities.showDetails))
                        .disabled(!settings.values.liveActivities.enabled)
                } header: {
                    Text("Live Activity")
                } footer: {
                    if !liveActivities.systemAllowsActivities {
                        Text("Live Activities are turned off for Forma in iOS Settings, or aren't supported on this device.")
                    } else {
                        Text("Shows elapsed time, sets and rest timer on the Lock Screen and Dynamic Island. Without details, only a timer and set count are shown.")
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: settings.binding(\.appearance)) {
                        ForEach(AppearancePreference.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Data & Privacy") {
                    NavigationLink {
                        DataSettingsView()
                    } label: {
                        Label("Export or delete data", systemImage: "externaldrive")
                    }
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label("Privacy", systemImage: "hand.raised")
                    }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                } footer: {
                    Text("Forma stores your data on this iPhone. No account required.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingGoal) { GoalEditorView() }
            .sheet(isPresented: $showingTargets) { NutritionTargetsView() }
            .sheet(isPresented: $showingStepTarget) { StepTargetSheet() }
            .task { await notifications.refreshAuthorization() }
        }
    }

    private var healthStatusText: String {
        switch health.status {
        case .unavailable: return "Unavailable"
        case .notConnected: return "Not connected"
        case .connected: return "Connected"
        }
    }
}

// MARK: - Training schedule

/// Training weekdays and the template planned for each.
struct TrainingScheduleForm: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \WorkoutTemplate.position) private var templates: [WorkoutTemplate]

    var body: some View {
        Form {
            Section {
                WeekdayPicker(selection: settings.binding(\.trainingDays), tint: Metric.training.color)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            } footer: {
                Text("Planned days set expectations for Today, reminders and your weekly review. Training on other days still counts.")
            }

            if !settings.values.trainingDays.isEmpty {
                Section("Planned workout") {
                    ForEach(Weekdays.ordered().filter { settings.values.trainingDays.contains($0) }, id: \.self) { weekday in
                        Picker(Calendar.current.weekdaySymbols[weekday - 1], selection: templateBinding(for: weekday)) {
                            Text("Any workout").tag(UUID?.none)
                            ForEach(templates) { template in
                                Text(template.name).tag(UUID?.some(template.id))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Training Days")
        .onChange(of: settings.values.trainingDays) { _, days in
            // Drop template assignments for days that are no longer training days.
            settings.update { values in
                values.templateForWeekday = values.templateForWeekday.filter { days.contains($0.key) }
            }
        }
    }

    private func templateBinding(for weekday: Int) -> Binding<UUID?> {
        Binding(
            get: { settings.values.templateForWeekday[weekday] },
            set: { id in settings.update { $0.templateForWeekday[weekday] = id } }
        )
    }
}

struct TrainingScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TrainingScheduleForm()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
        }
    }
}

// MARK: - Reminders

struct RemindersSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(NotificationService.self) private var notifications
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            if notifications.isDenied {
                Section {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Label("Notifications are off for Forma", systemImage: "bell.slash")
                            .font(.headline)
                        Text("Reminders can't be delivered until you allow notifications in iOS Settings.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Open iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }

            Section {
                reminderToggle("Planned workouts", keyPath: \.reminders.workout.enabled)
                if settings.values.reminders.workout.enabled {
                    timePicker(keyPath: \.reminders.workout.time)
                    if settings.values.trainingDays.isEmpty {
                        FootnoteText(text: "Set training days in Settings → Training days for workout reminders to be sent.", symbol: "calendar")
                    }
                }
            } footer: {
                Text("Sent on your training days, unless you've already logged a workout.")
            }

            Section {
                reminderToggle("Weigh-ins", keyPath: \.reminders.weight.enabled)
                if settings.values.reminders.weight.enabled {
                    timePicker(keyPath: \.reminders.weight.time)
                    WeekdayPicker(selection: settings.binding(\.reminders.weight.weekdays), tint: Metric.weight.color)
                }
            } footer: {
                Text(settings.values.reminders.weight.weekdays.isEmpty ? "Every day, skipped once you've logged that day." : "Selected days only, skipped once you've logged that day.")
            }

            Section {
                reminderToggle("Weekly review", keyPath: \.reminders.weeklyReview.enabled)
                if settings.values.reminders.weeklyReview.enabled {
                    timePicker(keyPath: \.reminders.weeklyReview.time)
                    WeekdayPicker(selection: settings.binding(\.reminders.weeklyReview.weekdays), tint: Theme.Palette.accent, allowsMultiple: false)
                }
            }

            Section {
                reminderToggle("Rest timer alerts", keyPath: \.reminders.restTimer)
            } footer: {
                Text("Alerts when rest ends while Forma is in the background.")
            }

            Section {
                NavigationLink("Routine reminders") { RoutinesView() }
            } footer: {
                Text("Each routine has its own optional reminder.")
            }

            Section {
                Toggle("Quiet hours", isOn: settings.binding(\.reminders.quietHours.enabled))
                if settings.values.reminders.quietHours.enabled {
                    timePicker("From", keyPath: \.reminders.quietHours.start)
                    timePicker("Until", keyPath: \.reminders.quietHours.end)
                }
            } footer: {
                Text("Reminders that fall in quiet hours aren't sent.")
            }

            Section {
                Toggle("Discreet notifications", isOn: settings.binding(\.reminders.discreet))
            } footer: {
                Text(settings.values.reminders.discreet ? "Notifications only say “You have a reminder” so nothing personal appears on your Lock Screen." : "Notifications describe what the reminder is for.")
            }

            if notifications.pendingReminderCount > 0 {
                Section {
                    LabeledContent("Scheduled", value: "\(notifications.pendingReminderCount) upcoming")
                } footer: {
                    Text("Reminders are planned up to two weeks ahead and refreshed whenever you open Forma.")
                }
            }
        }
        .navigationTitle("Reminders")
        .task { await notifications.refreshAuthorization() }
    }

    private func reminderToggle(_ title: String, keyPath: WritableKeyPath<SettingsValues, Bool>) -> some View {
        Toggle(title, isOn: Binding(
            get: { settings.values[keyPath: keyPath] },
            set: { enabled in
                settings.update { $0[keyPath: keyPath] = enabled }
                if enabled {
                    Task { await notifications.requestAuthorizationIfNeeded() }
                }
            }
        ))
    }

    private func timePicker(_ title: String = "Time", keyPath: WritableKeyPath<SettingsValues, ClockTime>) -> some View {
        DatePicker(title, selection: Binding(
            get: { settings.values[keyPath: keyPath].date(on: .today()) ?? Date() },
            set: { date in settings.update { $0[keyPath: keyPath] = ClockTime(date: date) } }
        ), displayedComponents: .hourAndMinute)
    }
}

// MARK: - Apple Health

struct HealthSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HealthService.self) private var health
    @Environment(\.modelContext) private var context
    @State private var confirmRemove = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Label(statusTitle, systemImage: health.status == .connected ? "heart.fill" : "heart")
                        .font(.headline)
                        .foregroundStyle(health.status == .connected ? .pink : .primary)
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if health.status == .notConnected {
                        Button("Connect Apple Health") {
                            Task { await connectAndRefresh() }
                        }
                        .buttonStyle(SecondaryButtonStyle(tint: .pink))
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }

            if health.status != .unavailable {
                Section {
                    healthToggle("Import weigh-ins", keyPath: \.health.importWeight)
                    healthToggle("Read steps", keyPath: \.health.readSteps)
                } header: {
                    Text("Read from Health")
                } footer: {
                    Text("Weigh-ins from scales and other apps are imported as entries marked Health. Steps are read as daily totals; HealthKit merges iPhone and Apple Watch so nothing is counted twice.")
                }

                Section {
                    healthToggle("Save weigh-ins", keyPath: \.health.saveWeight)
                    healthToggle("Save workouts", keyPath: \.health.saveWorkouts)
                } header: {
                    Text("Save to Health")
                } footer: {
                    Text("Forma only writes entries you create in Forma, and only ever edits or deletes those. It never changes data from other apps.")
                }
            }

            if health.status == .connected {
                Section {
                    Button {
                        Task {
                            await health.importWeights(into: context)
                            await health.refreshSteps(force: true)
                        }
                    } label: {
                        HStack {
                            Text("Refresh now")
                            Spacer()
                            if health.isImporting || health.isRefreshingSteps { ProgressView() }
                        }
                    }
                    if let summary = health.lastImport {
                        LabeledContent("Last import", value: "\(summary.added) added · \(Format.relative(summary.date))")
                    }
                    if let error = health.lastError {
                        Text(error).font(.footnote).foregroundStyle(.orange)
                    }
                }

                Section {
                    Button("Remove Imported Weigh-ins", role: .destructive) { confirmRemove = true }
                    Button("Stop Using Apple Health") { health.disconnect() }
                } footer: {
                    Text("To change or revoke permissions, open the Health app → Sharing → Apps → Forma. Forma can't see which read permissions you granted; if data is missing, check there.")
                }
            }
        }
        .navigationTitle("Apple Health")
        .confirmationDialog("Remove imported weigh-ins?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { health.removeImportedWeights(from: context) }
        } message: {
            Text("They're removed from Forma only. Apple Health is not changed. They'll be imported again next time unless you turn off importing.")
        }
    }

    private var statusTitle: String {
        switch health.status {
        case .unavailable: return "Not available"
        case .notConnected: return "Not connected"
        case .connected: return "Connected"
        }
    }

    private var statusMessage: String {
        switch health.status {
        case .unavailable:
            return "Apple Health isn't available on this device. Everything in Forma still works with manual entry."
        case .notConnected:
            return "Connect to import weigh-ins from smart scales and see your daily steps. Forma works fully without it."
        case .connected:
            return "Forma refreshes Health data when you open the app."
        }
    }

    private func healthToggle(_ title: String, keyPath: WritableKeyPath<SettingsValues, Bool>) -> some View {
        Toggle(title, isOn: Binding(
            get: { settings.values[keyPath: keyPath] },
            set: { enabled in
                settings.update { $0[keyPath: keyPath] = enabled }
                if enabled && health.status == .connected {
                    Task { await connectAndRefresh() }
                }
            }
        ))
    }

    private func connectAndRefresh() async {
        guard await health.connect() else { return }
        await health.refreshSteps(force: true)
        await health.importWeights(into: context)
    }
}

// MARK: - Data

struct DataSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(NotificationService.self) private var notifications
    @Environment(LiveActivityService.self) private var liveActivities
    @Environment(HealthService.self) private var health
    @Environment(WorkoutController.self) private var workout
    @Environment(\.dismiss) private var dismiss

    @State private var exportedFiles: [URL] = []
    @State private var exportError: String?
    @State private var isExporting = false
    @State private var confirmDelete = false
    @State private var confirmDeleteAgain = false

    var body: some View {
        Form {
            Section {
                Button {
                    export()
                } label: {
                    HStack {
                        Label("Prepare CSV Export", systemImage: "doc.text")
                        Spacer()
                        if isExporting { ProgressView() }
                    }
                }
                if !exportedFiles.isEmpty {
                    ShareLink(items: exportedFiles) {
                        Label("Share \(exportedFiles.count) Files", systemImage: "square.and.arrow.up")
                    }
                }
                if let exportError {
                    Text(exportError).font(.footnote).foregroundStyle(.orange)
                }
            } header: {
                Text("Export")
            } footer: {
                Text("Creates spreadsheet-friendly CSV files for weight, food, foods, workouts, sets, routines, manual steps and targets. Weights are in kilograms.")
            }

            Section {
                Button("Delete All Data", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Permanently deletes everything stored in Forma on this iPhone and resets settings. Apple Health isn't changed — weigh-ins or workouts Forma saved there stay until you remove them in the Health app.")
            }
        }
        .navigationTitle("Your Data")
        .confirmationDialog("Delete all Forma data?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) { confirmDeleteAgain = true }
        } message: {
            Text("This can't be undone. Consider exporting first.")
        }
        .alert("Are you sure?", isPresented: $confirmDeleteAgain) {
            Button("Delete", role: .destructive) {
                Task {
                    if workout.hasActiveWorkout { workout.discard() }
                    await DataEraser.eraseAll(context: context, settings: settings, notifications: notifications, liveActivities: liveActivities, health: health)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All workouts, food entries, weigh-ins, routines and settings will be removed from this iPhone.")
        }
    }

    private func export() {
        isExporting = true
        exportError = nil
        defer { isExporting = false }
        do {
            exportedFiles = try DataExporter.export(context: context)
            Haptics.success()
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
        }
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                privacyItem("iphone", "Stored on this iPhone", "Everything you log is stored locally in Forma's database. There's no account and no server.")
                privacyItem("icloud.slash", "Not synced to iCloud", "Forma's database doesn't sync through iCloud. Like other app data, it's included in your iPhone backups.")
                privacyItem("heart", "Apple Health", "Forma only reads the types you enable (body mass and steps) and only writes what you create in Forma. You control access in the Health app.")
                privacyItem("chart.bar.xaxis", "No analytics", "Forma doesn't include analytics or advertising SDKs, and doesn't log your health values.")
                privacyItem("bell.badge", "Discreet by default", "Reminder notifications use generic text unless you change that, and the Lock Screen workout can hide exercise details.")
                privacyItem("square.and.arrow.up", "Your data, your files", "Export everything as CSV at any time, or delete it all from Settings.")
            }
            .padding(Theme.Spacing.xl)
        }
        .navigationTitle("Privacy")
    }

    private func privacyItem(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
