import Foundation
import ActivityKit

/// Live Activity payload for an in-progress workout. Shared by the app and the
/// widget extension.
///
/// Times are sent as timestamps (`startedAt`, `restEndsAt`) and rendered with
/// system timer text, so the Lock Screen keeps counting without the app
/// running or sending updates every second.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// `nil` when the person has chosen to hide details on the Lock Screen.
        var exerciseName: String?
        var completedSets: Int
        var totalSets: Int
        var restStartedAt: Date?
        var restEndsAt: Date?
        var isFinished: Bool

        var isResting: Bool {
            guard let restEndsAt else { return false }
            return restEndsAt > Date()
        }

        /// When resting, the activity becomes stale as rest ends so the view re-renders.
        var staleDate: Date? {
            guard let restEndsAt, restEndsAt > Date() else { return nil }
            return restEndsAt
        }
    }

    var sessionID: String
    /// Generic text ("Workout") when details are hidden.
    var title: String
    var startedAt: Date
    var showsDetails: Bool
}

/// Rest-timer state stored outside SwiftData so that Live Activity buttons
/// (which run in the app's process, possibly while it is in the background)
/// can change it without loading the whole workout.
enum RestTimerStore {
    private static let endsKey = "forma.rest.endsAt"
    private static let startKey = "forma.rest.startedAt"
    private static let sessionKey = "forma.rest.sessionID"

    static let changedNotification = Notification.Name("FormaRestTimerChanged")
    static let notificationIdentifier = "forma.rest-timer"

    struct State: Equatable {
        var sessionID: String
        var startedAt: Date
        var endsAt: Date
    }

    static func load(defaults: UserDefaults = .standard) -> State? {
        guard let session = defaults.string(forKey: sessionKey),
              let ends = defaults.object(forKey: endsKey) as? Date,
              let start = defaults.object(forKey: startKey) as? Date else { return nil }
        return State(sessionID: session, startedAt: start, endsAt: ends)
    }

    static func save(_ state: State?, defaults: UserDefaults = .standard) {
        if let state {
            defaults.set(state.sessionID, forKey: sessionKey)
            defaults.set(state.startedAt, forKey: startKey)
            defaults.set(state.endsAt, forKey: endsKey)
        } else {
            defaults.removeObject(forKey: sessionKey)
            defaults.removeObject(forKey: startKey)
            defaults.removeObject(forKey: endsKey)
        }
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }
}
