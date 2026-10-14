import SwiftUI
import SwiftData
import FormaKit

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(DayClock.self) private var clock
    @Environment(HealthService.self) private var health
    @Environment(NotificationService.self) private var notifications
    @Environment(LiveActivityService.self) private var liveActivities
    @Environment(WorkoutController.self) private var workout
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @State private var didBootstrap = false
    @State private var reminderTask: Task<Void, Never>?

    var body: some View {
        @Bindable var router = router
        @Bindable var workout = workout

        Group {
            if settings.values.onboardingCompleted {
                TabView(selection: $router.selectedTab) {
                    TodayView()
                        .tabItem { Label("Today", systemImage: "sun.horizon") }
                        .tag(AppTab.today)
                    TrainingView()
                        .tabItem { Label("Training", systemImage: "dumbbell") }
                        .tag(AppTab.training)
                    NutritionView()
                        .tabItem { Label("Nutrition", systemImage: "fork.knife") }
                        .tag(AppTab.nutrition)
                    ProgressScreen()
                        .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                        .tag(AppTab.progress)
                }
                .fullScreenCover(isPresented: $workout.isPresented, onDismiss: workout.workoutScreenDidDismiss) {
                    ActiveWorkoutView()
                }
                .sheet(item: $workout.summary) { summary in
                    WorkoutSummaryView(summary: summary)
                }
                .sheet(item: $router.sheet) { sheet in
                    sheetContent(sheet)
                }
                .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .tint(Theme.Palette.accent)
        .preferredColorScheme(settings.colorScheme)
        .motion(Motion.standard, value: settings.values.onboardingCompleted)
        .task { @MainActor in
            guard !didBootstrap else { return }
            didBootstrap = true
            ExerciseCatalog.seedIfNeeded(in: context)
            workout.restore()
            await refreshExternalData()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                clock.refresh()
                Task { await refreshExternalData() }
            case .background:
                workout.saveNow()
                try? context.save()
            default:
                break
            }
        }
        .onChange(of: settings.values.reminders) { _, _ in scheduleReminderRefresh() }
        .onChange(of: settings.values.trainingDays) { _, _ in scheduleReminderRefresh() }
        .onChange(of: settings.values.templateForWeekday) { _, _ in scheduleReminderRefresh() }
        .onChange(of: settings.values.liveActivities) { _, _ in workout.restartActivity() }
        .onChange(of: clock.today) { _, _ in scheduleReminderRefresh() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            scheduleReminderRefresh()
        }
        .onOpenURL { url in
            guard url.scheme == "forma" else { return }
            if url.host == "workout", workout.hasActiveWorkout {
                workout.isPresented = true
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .logWeight:
            WeightEntrySheet(entry: nil)
        case .logFood(let day, let meal):
            AddFoodSheet(day: day, meal: meal ?? Meal.suggested(for: Date()))
        case .settings:
            SettingsView()
        case .weeklyReview(let weekStart):
            NavigationStack {
                WeeklyReviewView(week: WeekInterval(containing: weekStart))
            }
        case .manualSteps(let day):
            ManualStepsSheet(day: day)
        }
    }

    /// Pulls fresh data from Apple Health and re-plans reminders.
    private func refreshExternalData() async {
        await notifications.refreshAuthorization()
        if health.status == .connected {
            await health.refreshSteps()
            await health.importWeights(into: context)
        }
        await ReminderCoordinator.refresh(context: context, settings: settings, notifications: notifications, health: health)
    }

    /// Coalesces bursts of saves into one reminder refresh.
    private func scheduleReminderRefresh() {
        reminderTask?.cancel()
        reminderTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await ReminderCoordinator.refresh(context: context, settings: settings, notifications: notifications, health: health)
        }
    }
}

/// "Workout in progress" bar shown above the tab bar on every tab.
struct WorkoutResumeBar: View {
    @Environment(WorkoutController.self) private var workout

    var body: some View {
        if let session = workout.session {
            Button {
                Motion.perform { workout.isPresented = true }
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    ZStack {
                        Circle().fill(Theme.Palette.training.opacity(0.15))
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.training)
                    }
                    .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if let rest = workout.rest, rest.endsAt > Date() {
                                Text("Rest")
                                Text(timerInterval: rest.startedAt...max(rest.startedAt, rest.endsAt), countsDown: true)
                                    .monospacedDigit()
                            } else {
                                Text("In progress ·")
                                Text(session.startedAt, style: .timer)
                                    .monospacedDigit()
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Resume")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.training)
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous)
                        .strokeBorder(Theme.Palette.separator.opacity(0.4), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            }
            .buttonStyle(PressableStyle())
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.s)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityLabel("Workout in progress: \(session.name)")
            .accessibilityHint("Opens the active workout")
        }
    }
}

extension View {
    /// Adds the persistent "Workout in progress" bar above the tab bar.
    func workoutResumeAccessory() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            WorkoutResumeBar()
        }
    }

    /// Standard profile/settings button for tab toolbars.
    func settingsToolbarButton(_ router: AppRouter) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.show(.settings)
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.title3)
                }
                .accessibilityLabel("Profile and settings")
            }
        }
    }
}
