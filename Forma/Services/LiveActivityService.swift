import Foundation
import Observation
import ActivityKit

/// Starts, updates and ends the workout Live Activity.
///
/// Every operation is best-effort: Live Activities can be disabled system-wide
/// or per app, aren't available on every device, and the system may end them
/// on its own. The app never depends on one existing.
@MainActor
@Observable
final class LiveActivityService {
    private(set) var lastErrorDescription: String?

    @ObservationIgnored private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    var systemAllowsActivities: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    var isEnabled: Bool { settings.values.liveActivities.enabled && systemAllowsActivities }

    private func activity(for sessionID: String) -> Activity<WorkoutActivityAttributes>? {
        Activity<WorkoutActivityAttributes>.activities.first { $0.attributes.sessionID == sessionID }
    }

    /// Starts an activity for the session, or adopts one that survived an app restart.
    func startOrResume(sessionID: String, title: String, startedAt: Date, state: WorkoutActivityAttributes.ContentState) async {
        guard isEnabled else { return }
        if let existing = activity(for: sessionID) {
            await existing.update(ActivityContent(state: state, staleDate: state.staleDate))
            return
        }
        let showsDetails = settings.values.liveActivities.showDetails
        let attributes = WorkoutActivityAttributes(
            sessionID: sessionID,
            title: showsDetails ? title : "Workout",
            startedAt: startedAt,
            showsDetails: showsDetails
        )
        do {
            _ = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: state.staleDate), pushType: nil)
            lastErrorDescription = nil
        } catch {
            lastErrorDescription = error.localizedDescription
        }
    }

    func update(sessionID: String, state: WorkoutActivityAttributes.ContentState) async {
        guard let activity = activity(for: sessionID) else { return }
        await activity.update(ActivityContent(state: state, staleDate: state.staleDate))
    }

    /// Ends the session's activity. A finished workout lingers briefly on the
    /// Lock Screen with its final state; a discarded one disappears at once.
    func end(sessionID: String, finalState: WorkoutActivityAttributes.ContentState?, immediately: Bool) async {
        for activity in Activity<WorkoutActivityAttributes>.activities where activity.attributes.sessionID == sessionID {
            let content = finalState.map { ActivityContent(state: $0, staleDate: nil) }
            await activity.end(content, dismissalPolicy: immediately ? .immediate : .after(Date().addingTimeInterval(5 * 60)))
        }
    }

    /// Ends any activity that doesn't belong to the in-progress session (e.g.
    /// left behind after the app was terminated, or the workout was finished on
    /// another launch).
    func endOrphans(keeping sessionID: String?) async {
        for activity in Activity<WorkoutActivityAttributes>.activities where activity.attributes.sessionID != sessionID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func endAll() async {
        await endOrphans(keeping: nil)
    }
}
