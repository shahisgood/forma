import SwiftUI
import SwiftData

@main
struct FormaApp: App {
    @State private var environment: Result<AppEnvironment, Error>

    init() {
        _environment = State(initialValue: AppEnvironment.make())
    }

    var body: some Scene {
        WindowGroup {
            switch environment {
            case .success(let env):
                RootView()
                    .modelContainer(env.container)
                    .environment(env.settings)
                    .environment(env.clock)
                    .environment(env.health)
                    .environment(env.notifications)
                    .environment(env.liveActivities)
                    .environment(env.workout)
                    .environment(env.router)
            case .failure(let error):
                StoreFailureView(error: error) {
                    environment = AppEnvironment.make()
                }
            }
        }
    }
}

/// Long-lived app objects, created once at launch.
@MainActor
final class AppEnvironment {
    let container: ModelContainer
    let settings: AppSettings
    let clock: DayClock
    let health: HealthService
    let notifications: NotificationService
    let liveActivities: LiveActivityService
    let workout: WorkoutController
    let router: AppRouter

    private init(container: ModelContainer) {
        self.container = container
        settings = AppSettings()
        clock = DayClock()
        health = HealthService(settings: settings)
        notifications = NotificationService()
        liveActivities = LiveActivityService(settings: settings)
        workout = WorkoutController(
            context: container.mainContext,
            settings: settings,
            liveActivities: liveActivities,
            notifications: notifications,
            health: health
        )
        router = AppRouter()
    }

    static func make() -> Result<AppEnvironment, Error> {
        do {
            let container = try Persistence.makeContainer()
            return .success(AppEnvironment(container: container))
        } catch {
            return .failure(error)
        }
    }
}

/// Shown if the local store cannot be opened. Data is not deleted automatically.
struct StoreFailureView: View {
    let error: Error
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Forma couldn't open its data")
                .font(.title3.weight(.semibold))
            Text("Your data has not been deleted. Try again, or restart your iPhone. If this keeps happening, make sure there is free storage space.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(error.localizedDescription)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Try Again", action: retry)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Theme.Spacing.xxl)
    }
}
