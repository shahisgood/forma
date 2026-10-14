import Foundation
import Observation
import UserNotifications
import FormaKit

/// Schedules local notifications from a computed plan (see `ReminderPlanner`).
///
/// Forma never requests notification permission at launch. It asks the first
/// time someone turns on a reminder or rest alert, and every reminder screen
/// reflects the current authorization honestly.
@MainActor
@Observable
final class NotificationService: NSObject {
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var pendingReminderCount = 0

    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    var isAuthorized: Bool {
        authorization == .authorized || authorization == .provisional || authorization == .ephemeral
    }

    var isDenied: Bool { authorization == .denied }

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
    }

    /// Requests permission if it has not been decided yet. Returns whether notifications can be delivered.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        await refreshAuthorization()
        if authorization == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
        }
        return isAuthorized
    }

    // MARK: Reminders

    /// Makes the pending reminder notifications match `plan` exactly: stale ones
    /// are removed, missing ones added, unchanged ones left alone.
    func apply(plan: [PlannedNotification]) async {
        await refreshAuthorization()
        let pending = await center.pendingNotificationRequests()
        let existing = pending.filter { $0.identifier.hasPrefix(ReminderPlanner.idPrefix) }

        guard isAuthorized else {
            center.removePendingNotificationRequests(withIdentifiers: existing.map(\.identifier))
            pendingReminderCount = 0
            return
        }

        let planned = Dictionary(uniqueKeysWithValues: plan.map { ($0.id, $0) })
        var toRemove: [String] = []
        var unchanged = Set<String>()
        for request in existing {
            if let item = planned[request.identifier],
               request.content.title == item.title,
               request.content.body == item.body,
               let trigger = request.trigger as? UNCalendarNotificationTrigger,
               trigger.nextTriggerDate().map({ abs($0.timeIntervalSince(item.fireDate)) < 1 }) == true {
                unchanged.insert(request.identifier)
            } else {
                toRemove.append(request.identifier)
            }
        }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)

        for item in plan where !unchanged.contains(item.id) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.threadIdentifier = "forma.\(item.kind.rawValue)"
            content.interruptionLevel = .active
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
        pendingReminderCount = plan.count
    }

    func removeAllReminders() async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(ReminderPlanner.idPrefix) })
        pendingReminderCount = 0
    }

    // MARK: Rest timer

    func scheduleRestAlert(endsAt: Date) async {
        cancelRestAlert()
        let interval = endsAt.timeIntervalSinceNow
        guard interval > 1, isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Ready for your next set."
        content.sound = .default
        content.interruptionLevel = .active
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: RestTimerStore.notificationIdentifier, content: content, trigger: trigger))
    }

    func cancelRestAlert() {
        center.removePendingNotificationRequests(withIdentifiers: [RestTimerStore.notificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [RestTimerStore.notificationIdentifier])
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // The in-app rest timer already shows completion; avoid a duplicate banner.
        if notification.request.identifier == RestTimerStore.notificationIdentifier {
            return []
        }
        return [.banner, .list, .sound]
    }
}
