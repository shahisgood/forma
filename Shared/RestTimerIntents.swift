import Foundation
import AppIntents
import ActivityKit
import UserNotifications

/// Buttons on the workout Live Activity.
///
/// `LiveActivityIntent`s compiled into both targets are performed in the app's
/// process, so they can update the shared rest-timer state, the Live Activity
/// and the pending rest notification directly. The running app observes
/// `RestTimerStore.changedNotification` to refresh its UI.
struct SkipRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip Rest"
    static var description = IntentDescription("Ends the current rest timer.")
    static var isDiscoverable = false

    @Parameter(title: "Workout")
    var sessionID: String

    init() {}

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    func perform() async throws -> some IntentResult {
        RestTimerStore.save(nil)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [RestTimerStore.notificationIdentifier])
        await RestTimerActivityUpdater.apply(sessionID: sessionID, startedAt: nil, endsAt: nil)
        return .result()
    }
}

struct ExtendRestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Add 30 Seconds"
    static var description = IntentDescription("Adds 30 seconds to the current rest timer.")
    static var isDiscoverable = false

    @Parameter(title: "Workout")
    var sessionID: String

    init() {}

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    func perform() async throws -> some IntentResult {
        guard var state = RestTimerStore.load(), state.sessionID == sessionID else { return .result() }
        let base = max(state.endsAt, Date())
        state.endsAt = base.addingTimeInterval(30)
        RestTimerStore.save(state)
        await RestTimerActivityUpdater.apply(sessionID: sessionID, startedAt: state.startedAt, endsAt: state.endsAt)
        await RestTimerActivityUpdater.rescheduleNotification(endsAt: state.endsAt)
        return .result()
    }
}

enum RestTimerActivityUpdater {
    static func apply(sessionID: String, startedAt: Date?, endsAt: Date?) async {
        for activity in Activity<WorkoutActivityAttributes>.activities where activity.attributes.sessionID == sessionID {
            var state = activity.content.state
            state.restStartedAt = startedAt
            state.restEndsAt = endsAt
            await activity.update(ActivityContent(state: state, staleDate: state.staleDate))
        }
    }

    static func rescheduleNotification(endsAt: Date) async {
        let center = UNUserNotificationCenter.current()
        // Only replace a notification the app scheduled; if rest alerts are off, none exists.
        let pending = await center.pendingNotificationRequests()
        guard pending.contains(where: { $0.identifier == RestTimerStore.notificationIdentifier }) else { return }
        center.removePendingNotificationRequests(withIdentifiers: [RestTimerStore.notificationIdentifier])
        let interval = endsAt.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Ready for your next set."
        content.sound = .default
        content.interruptionLevel = .active
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: RestTimerStore.notificationIdentifier, content: content, trigger: trigger))
    }
}
