import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct FormaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
    }
}

/// Lock Screen and Dynamic Island presentation of an active workout.
///
/// All clocks use `Text(_:style: .timer)` / `Text(timerInterval:)` driven by
/// timestamps in the activity state, so they keep counting without updates.
/// While resting, the content's stale date is the rest end time, so the system
/// re-renders it when rest is over even if the app is suspended.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockScreenView(context: context)
                .activityBackgroundTint(Color(uiColor: .systemBackground).opacity(0.85))
                .activitySystemActionForegroundColor(SharedPalette.training)
                .widgetURL(URL(string: "forma://workout"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "dumbbell.fill")
                            .foregroundStyle(SharedPalette.training)
                        Text(context.attributes.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 72, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    if let exercise = context.state.exerciseName, !context.state.isFinished {
                        Text(exercise)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WorkoutActivityDetail(context: context, compact: true)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.restEndsAt != nil ? "timer" : "dumbbell.fill")
                    .foregroundStyle(SharedPalette.training)
            } compactTrailing: {
                if let ends = context.state.restEndsAt, let start = context.state.restStartedAt, ends > Date(), !context.isStale {
                    Text(timerInterval: start...max(start, ends), countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                        .foregroundStyle(SharedPalette.training)
                } else {
                    Text("\(context.state.completedSets)/\(context.state.totalSets)")
                        .monospacedDigit()
                        .font(.caption.weight(.semibold))
                }
            } minimal: {
                Image(systemName: context.state.restEndsAt != nil ? "timer" : "dumbbell.fill")
                    .foregroundStyle(SharedPalette.training)
            }
            .widgetURL(URL(string: "forma://workout"))
            .keylineTint(SharedPalette.training)
        }
    }
}

private struct WorkoutLockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.isFinished ? "Workout complete" : context.attributes.title)
                        .font(.headline)
                        .lineLimit(1)
                    if let exercise = context.state.exerciseName, !context.state.isFinished {
                        Text(exercise)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if !context.state.isFinished {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 96, alignment: .trailing)
                }
            }
            WorkoutActivityDetail(context: context, compact: false)
        }
        .padding(16)
    }
}

/// Rest countdown with controls, or set progress when not resting.
private struct WorkoutActivityDetail: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>
    let compact: Bool

    var body: some View {
        if context.state.isFinished {
            Label("\(context.state.completedSets) sets logged", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SharedPalette.done)
        } else if let ends = context.state.restEndsAt, let start = context.state.restStartedAt, ends > Date(), !context.isStale {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Rest")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(timerInterval: start...max(start, ends), countsDown: true)
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                    }
                    ProgressView(timerInterval: start...max(start, ends), countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(SharedPalette.training)
                }
                Button(intent: ExtendRestIntent(sessionID: context.attributes.sessionID)) {
                    Text("+30s")
                        .font(.caption.weight(.semibold))
                }
                .tint(SharedPalette.training)
                Button(intent: SkipRestIntent(sessionID: context.attributes.sessionID)) {
                    Text("Skip")
                        .font(.caption.weight(.semibold))
                }
                .tint(SharedPalette.training)
            }
        } else {
            HStack(spacing: 8) {
                ProgressView(value: Double(context.state.completedSets), total: Double(max(context.state.totalSets, 1)))
                    .tint(SharedPalette.done)
                Text("\(context.state.completedSets)/\(context.state.totalSets) sets")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
