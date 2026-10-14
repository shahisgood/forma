import Foundation
import Observation
import SwiftData
import FormaKit

/// Result shown after finishing a workout.
struct WorkoutSummary: Identifiable, Equatable {
    struct Record: Hashable {
        var exerciseName: String
        var trackingType: ExerciseTrackingType
        var record: PersonalRecord
    }

    var id: UUID { sessionID }
    var sessionID: UUID
    var name: String
    var duration: TimeInterval
    var completedSets: Int
    var exerciseCount: Int
    var records: [Record]
}

/// Owns the in-progress workout.
///
/// The session lives in SwiftData from the first tap and is saved after every
/// change, so a crash, a force-quit or the phone restarting mid-workout loses
/// nothing: on next launch `restore()` picks the session back up, including
/// any rest timer that was running.
@MainActor
@Observable
final class WorkoutController {
    private(set) var session: WorkoutSession?
    var isPresented = false
    private(set) var rest: RestTimerStore.State?
    var summary: WorkoutSummary?
    /// Held until the workout screen has finished dismissing, then shown.
    @ObservationIgnored private var pendingSummary: WorkoutSummary?
    /// Sets that beat a previous best when they were completed (for a small celebration).
    private(set) var recordSetIDs: Set<UUID> = []
    /// Increments on each completed set; drives haptics and animations.
    private(set) var completionCount = 0
    /// Increments when the rest timer finishes on its own.
    private(set) var restFinishedCount = 0

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let liveActivities: LiveActivityService
    @ObservationIgnored private let notifications: NotificationService
    @ObservationIgnored private let health: HealthService
    @ObservationIgnored private var historyCache: [UUID: [SetRecord]] = [:]
    @ObservationIgnored private var previousCache: [UUID: [SetRecord]] = [:]
    @ObservationIgnored private var restTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var restObserver: NSObjectProtocol?

    init(context: ModelContext, settings: AppSettings, liveActivities: LiveActivityService, notifications: NotificationService, health: HealthService) {
        self.context = context
        self.settings = settings
        self.liveActivities = liveActivities
        self.notifications = notifications
        self.health = health
        restObserver = NotificationCenter.default.addObserver(forName: RestTimerStore.changedNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadRestFromStore() }
        }
    }

    var hasActiveWorkout: Bool { session != nil }

    // MARK: Lifecycle

    /// Reattaches to an unfinished workout after launch.
    func restore() {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        session = (try? context.fetch(descriptor))?.first
        historyCache = [:]
        previousCache = [:]
        if let session {
            reloadRestFromStore()
            // Bring a recent workout straight back; an old forgotten one waits on the Today screen.
            if Date().timeIntervalSince(session.startedAt) < 4 * 3600 {
                isPresented = true
            }
            let id = session.id.uuidString
            Task {
                await liveActivities.endOrphans(keeping: id)
                await liveActivities.startOrResume(sessionID: id, title: session.name, startedAt: session.startedAt, state: activityState())
            }
        } else {
            RestTimerStore.save(nil)
            rest = nil
            Task { await liveActivities.endAll() }
        }
    }

    /// Starts a workout from a template (or an empty one). If a workout is
    /// already running, it is shown instead of starting a second one.
    func start(template: WorkoutTemplate?) {
        if session != nil {
            isPresented = true
            return
        }
        let newSession = WorkoutSession(name: template?.name ?? "Workout", templateID: template?.id)
        context.insert(newSession)
        if let template {
            template.lastUsedAt = Date()
            var position = 0
            for item in template.orderedExercises {
                guard let exercise = item.exercise else { continue }
                let entry = SessionExercise(exercise: exercise, position: position)
                entry.restSeconds = item.restSeconds
                entry.targetRepLow = item.repLow
                entry.targetRepHigh = item.repHigh
                entry.notes = item.notes
                newSession.exercises.append(entry)
                var setPosition = 0
                for _ in 0..<max(0, item.warmupSets) {
                    entry.sets.append(WorkoutSet(position: setPosition, kind: .warmup))
                    setPosition += 1
                }
                for _ in 0..<max(1, item.targetSets) {
                    entry.sets.append(WorkoutSet(position: setPosition, kind: .working))
                    setPosition += 1
                }
                position += 1
            }
        }
        begin(newSession)
    }

    /// Starts a new workout with the same exercises and set structure as a past one.
    func start(repeating past: WorkoutSession) {
        if session != nil {
            isPresented = true
            return
        }
        let newSession = WorkoutSession(name: past.name, templateID: past.templateID)
        context.insert(newSession)
        var position = 0
        for item in past.orderedExercises {
            guard let exercise = item.exercise else { continue }
            let entry = SessionExercise(exercise: exercise, position: position)
            entry.restSeconds = item.restSeconds
            entry.targetRepLow = item.targetRepLow
            entry.targetRepHigh = item.targetRepHigh
            newSession.exercises.append(entry)
            for (index, set) in item.orderedSets.enumerated() {
                entry.sets.append(WorkoutSet(position: index, kind: set.kind))
            }
            position += 1
        }
        begin(newSession)
    }

    private func begin(_ newSession: WorkoutSession) {
        saveNow()
        session = newSession
        recordSetIDs = []
        historyCache = [:]
        previousCache = [:]
        Motion.perform { isPresented = true }
        Haptics.firm()
        let id = newSession.id.uuidString
        let state = activityState()
        Task { await liveActivities.startOrResume(sessionID: id, title: newSession.name, startedAt: newSession.startedAt, state: state) }
    }

    /// Finishes the workout. Unchecked sets are discarded; exercises without any
    /// completed sets are removed. Returns `false` if nothing was completed.
    @discardableResult
    func finish(at end: Date = Date()) -> Bool {
        guard let session, session.completedSetCount > 0 else { return false }
        for entry in session.exercises {
            for set in entry.sets where !set.isCompleted {
                delete(set, from: entry)
            }
        }
        for entry in session.exercises where entry.sets.isEmpty {
            session.exercises.removeAll { $0.id == entry.id }
            context.delete(entry)
        }
        for (index, entry) in session.orderedExercises.enumerated() { entry.position = index }

        session.endedAt = max(end, session.startedAt.addingTimeInterval(1))
        let records = detectRecords(in: session)
        saveNow()

        pendingSummary = WorkoutSummary(
            sessionID: session.id,
            name: session.name,
            duration: session.duration,
            completedSets: session.completedSetCount,
            exerciseCount: session.exercises.count,
            records: records
        )
        let finalState = WorkoutActivityAttributes.ContentState(
            exerciseName: nil,
            completedSets: session.completedSetCount,
            totalSets: session.completedSetCount,
            restStartedAt: nil,
            restEndsAt: nil,
            isFinished: true
        )
        let finished = session
        clearRest()
        self.session = nil
        recordSetIDs = []
        isPresented = false
        Haptics.success()
        Task {
            await liveActivities.end(sessionID: finished.id.uuidString, finalState: finalState, immediately: false)
            await health.syncWorkout(finished)
            try? context.save()
        }
        return true
    }

    /// Called when the workout screen has been dismissed.
    func workoutScreenDidDismiss() {
        if let pending = pendingSummary {
            pendingSummary = nil
            summary = pending
        }
    }

    /// Deletes the in-progress workout entirely.
    func discard() {
        guard let session else { return }
        let id = session.id.uuidString
        clearRest()
        context.delete(session)
        saveNow()
        self.session = nil
        recordSetIDs = []
        isPresented = false
        Task { await liveActivities.end(sessionID: id, finalState: nil, immediately: true) }
    }

    // MARK: Editing

    func rename(_ name: String) {
        guard let session else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        session.name = trimmed.isEmpty ? "Workout" : trimmed
        scheduleSave()
    }

    func addExercises(_ exercises: [Exercise]) {
        guard let session else { return }
        var position = (session.exercises.map(\.position).max() ?? -1) + 1
        for exercise in exercises {
            let entry = SessionExercise(exercise: exercise, position: position)
            session.exercises.append(entry)
            let previousWorking = previousSets(for: entry).filter(\.isWorking).count
            let setCount = previousWorking == 0 ? 3 : min(previousWorking, 8)
            for i in 0..<setCount {
                entry.sets.append(WorkoutSet(position: i, kind: .working))
            }
            position += 1
        }
        saveNow()
        pushActivityUpdate()
    }

    func remove(_ entry: SessionExercise) {
        guard let session else { return }
        session.exercises.removeAll { $0.id == entry.id }
        context.delete(entry)
        for (index, item) in session.orderedExercises.enumerated() { item.position = index }
        saveNow()
        pushActivityUpdate()
    }

    func move(from source: IndexSet, to destination: Int) {
        guard let session else { return }
        let ordered = Self.reordered(session.orderedExercises, from: source, to: destination)
        for (index, item) in ordered.enumerated() { item.position = index }
        saveNow()
        pushActivityUpdate()
    }

    /// List reordering with the same semantics as SwiftUI's `onMove`.
    static func reordered<T>(_ items: [T], from source: IndexSet, to destination: Int) -> [T] {
        let moving = source.sorted().map { items[$0] }
        var remaining = items.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: min(max(0, insertAt), remaining.count))
        return remaining
    }

    func moveExercise(_ entry: SessionExercise, by offset: Int) {
        guard let session else { return }
        var ordered = session.orderedExercises
        guard let index = ordered.firstIndex(where: { $0.id == entry.id }) else { return }
        let target = index + offset
        guard ordered.indices.contains(target) else { return }
        ordered.swapAt(index, target)
        for (i, item) in ordered.enumerated() { item.position = i }
        saveNow()
    }

    func addSet(to entry: SessionExercise, kind: SetKind = .working) {
        let ordered = entry.orderedSets
        let newSet: WorkoutSet
        if kind == .warmup {
            // Warm-ups go after existing warm-ups, before working sets.
            let insertAt = (ordered.lastIndex { $0.kind == .warmup }).map { $0 + 1 } ?? 0
            newSet = WorkoutSet(position: insertAt, kind: .warmup)
            for set in ordered where set.position >= insertAt { set.position += 1 }
        } else {
            newSet = WorkoutSet(position: entry.nextPosition, kind: .working)
        }
        entry.sets.append(newSet)
        normalizePositions(entry)
        saveNow()
        pushActivityUpdate()
    }

    func removeSet(_ set: WorkoutSet, from entry: SessionExercise) {
        delete(set, from: entry)
        normalizePositions(entry)
        recordSetIDs.remove(set.id)
        saveNow()
        pushActivityUpdate()
    }

    func toggleKind(_ set: WorkoutSet, in entry: SessionExercise) {
        set.kind = set.kind == .warmup ? .working : .warmup
        // Keep warm-ups grouped at the top.
        let ordered = entry.orderedSets.sorted { a, b in
            if a.kind != b.kind { return a.kind == .warmup }
            return a.position < b.position
        }
        for (index, item) in ordered.enumerated() { item.position = index }
        saveNow()
    }

    private func normalizePositions(_ entry: SessionExercise) {
        for (index, item) in entry.orderedSets.enumerated() { item.position = index }
    }

    private func delete(_ set: WorkoutSet, from entry: SessionExercise) {
        entry.sets.removeAll { $0.id == set.id }
        context.delete(set)
    }

    /// Value edits are saved shortly after typing stops.
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        try? context.save()
    }

    // MARK: Suggestions & history

    /// Sets from the most recent finished session of this exercise.
    func previousSets(for entry: SessionExercise) -> [SetRecord] {
        guard let exercise = entry.exercise else { return [] }
        if let cached = previousCache[exercise.id] { return cached }
        let excluded = session?.id
        let records: [SetRecord]
        if let last = exercise.lastSessionEntry(excludingSession: excluded), let lastSession = last.session {
            records = last.completedRecords(sessionID: lastSession.id, fallbackDate: lastSession.startedAt)
        } else {
            records = []
        }
        previousCache[exercise.id] = records
        return records
    }

    func previousDate(for entry: SessionExercise) -> Date? {
        previousSets(for: entry).first?.date
    }

    func suggestion(for set: WorkoutSet, in entry: SessionExercise) -> SetSuggestion {
        let sameKind = entry.orderedSets.filter { $0.kind == set.kind }
        let index = sameKind.firstIndex { $0.id == set.id } ?? 0
        // Within a session, carry forward what was just done for the next set.
        if index > 0 {
            let earlier = sameKind[index - 1]
            if earlier.isCompleted || earlier.hasValues {
                return SetSuggestion(weightKg: earlier.weightKg, reps: earlier.reps, durationSeconds: earlier.durationSeconds, distanceMeters: earlier.distanceMeters)
            }
        }
        return SetSuggestion.make(index: index, kind: set.kind, previousSets: previousSets(for: entry), templateRepLow: entry.targetRepLow)
    }

    private func history(for exercise: Exercise) -> [SetRecord] {
        if let cached = historyCache[exercise.id] { return cached }
        let records = exercise.completedSetRecords(excludingSession: session?.id)
        historyCache[exercise.id] = records
        return records
    }

    // MARK: Completing sets

    enum CompletionResult {
        case completed
        case uncompleted
        case missingValues
    }

    /// Toggles completion. Suggested values are only written into the set at
    /// the moment the person checks it off; nothing is completed automatically.
    @discardableResult
    func toggleCompletion(_ set: WorkoutSet, in entry: SessionExercise) -> CompletionResult {
        if set.isCompleted {
            set.isCompleted = false
            set.completedAt = nil
            recordSetIDs.remove(set.id)
            saveNow()
            pushActivityUpdate()
            return .uncompleted
        }

        let suggestion = suggestion(for: set, in: entry)
        let type = entry.trackingType
        if type.usesReps && set.reps == nil { set.reps = suggestion.reps }
        if type.usesWeight && set.weightKg == nil { set.weightKg = suggestion.weightKg }
        if type.usesDuration && set.durationSeconds == nil { set.durationSeconds = suggestion.durationSeconds }
        if type.usesDistance && set.distanceMeters == nil { set.distanceMeters = suggestion.distanceMeters }

        guard Self.hasRequiredValues(set, type: type) else { return .missingValues }

        set.isCompleted = true
        set.completedAt = Date()
        completionCount += 1

        // Records are only celebrated against earlier sessions; a first session is a baseline.
        if set.kind == .working, let exercise = entry.exercise, let sessionID = session?.id, !history(for: exercise).isEmpty {
            let earlierThisSession = entry.orderedSets
                .filter { $0.isCompleted && $0.id != set.id }
                .map { $0.record(sessionID: sessionID, fallbackDate: Date()) }
            let found = PersonalRecords.detect(
                newSets: [set.record(sessionID: sessionID, fallbackDate: Date())],
                history: history(for: exercise) + earlierThisSession,
                trackingType: type
            )
            if !found.isEmpty {
                recordSetIDs.insert(set.id)
            }
        }

        if set.kind == .working && settings.values.autoStartRestTimer {
            startRest(seconds: entry.restSeconds ?? settings.values.defaultRestSeconds)
        } else {
            pushActivityUpdate()
        }
        saveNow()
        return .completed
    }

    static func hasRequiredValues(_ set: WorkoutSet, type: ExerciseTrackingType) -> Bool {
        switch type {
        case .weightReps:
            return (set.reps ?? 0) > 0 && set.weightKg != nil
        case .bodyweightReps, .assistedReps:
            return (set.reps ?? 0) > 0
        case .duration:
            return (set.durationSeconds ?? 0) > 0
        case .distanceDuration:
            return (set.distanceMeters ?? 0) > 0 || (set.durationSeconds ?? 0) > 0
        }
    }

    // MARK: Rest timer

    func startRest(seconds: Int) {
        guard let session, seconds > 0 else { return }
        let now = Date()
        let state = RestTimerStore.State(sessionID: session.id.uuidString, startedAt: now, endsAt: now.addingTimeInterval(TimeInterval(seconds)))
        applyRest(state)
    }

    func adjustRest(by seconds: Int) {
        guard var state = rest else { return }
        state.endsAt = max(Date().addingTimeInterval(1), state.endsAt.addingTimeInterval(TimeInterval(seconds)))
        applyRest(state)
    }

    func skipRest() {
        clearRest()
        pushActivityUpdate()
    }

    private func applyRest(_ state: RestTimerStore.State) {
        rest = state
        RestTimerStore.save(state)
        scheduleRestCompletion(at: state.endsAt)
        if settings.values.reminders.restTimer {
            Task {
                if notifications.authorization == .notDetermined {
                    await notifications.requestAuthorizationIfNeeded()
                }
                await notifications.scheduleRestAlert(endsAt: state.endsAt)
            }
        }
        pushActivityUpdate()
    }

    private func clearRest() {
        restTask?.cancel()
        restTask = nil
        rest = nil
        RestTimerStore.save(nil)
        notifications.cancelRestAlert()
    }

    private func scheduleRestCompletion(at date: Date) {
        restTask?.cancel()
        let delay = max(0, date.timeIntervalSinceNow)
        restTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.restDidFinish()
        }
    }

    private func restDidFinish() {
        guard rest != nil else { return }
        rest = nil
        RestTimerStore.save(nil)
        restFinishedCount += 1
        Haptics.success()
        pushActivityUpdate()
    }

    /// Picks up changes made by Live Activity buttons, or restores after launch.
    private func reloadRestFromStore() {
        guard let session else {
            rest = nil
            return
        }
        let stored = RestTimerStore.load()
        if let stored, stored.sessionID == session.id.uuidString, stored.endsAt > Date() {
            if stored != rest {
                rest = stored
                scheduleRestCompletion(at: stored.endsAt)
            }
        } else if rest != nil {
            restTask?.cancel()
            rest = nil
        }
    }

    // MARK: Live Activity

    /// The exercise the person is most likely working on: the first with unchecked sets.
    var currentExercise: SessionExercise? {
        guard let session else { return nil }
        let ordered = session.orderedExercises
        return ordered.first { entry in entry.sets.contains { !$0.isCompleted } } ?? ordered.last
    }

    func activityState() -> WorkoutActivityAttributes.ContentState {
        let showDetails = settings.values.liveActivities.showDetails
        return WorkoutActivityAttributes.ContentState(
            exerciseName: showDetails ? currentExercise?.exerciseName : nil,
            completedSets: session?.completedSetCount ?? 0,
            totalSets: session?.totalSetCount ?? 0,
            restStartedAt: rest?.startedAt,
            restEndsAt: rest?.endsAt,
            isFinished: false
        )
    }

    func pushActivityUpdate() {
        guard let session else { return }
        let id = session.id.uuidString
        let state = activityState()
        Task { await liveActivities.update(sessionID: id, state: state) }
    }

    /// Called when Live Activity preferences change mid-workout.
    func restartActivity() {
        guard let session else { return }
        let id = session.id.uuidString
        let name = session.name
        let start = session.startedAt
        let state = activityState()
        Task {
            await liveActivities.end(sessionID: id, finalState: nil, immediately: true)
            await liveActivities.startOrResume(sessionID: id, title: name, startedAt: start, state: state)
        }
    }

    // MARK: Records

    private func detectRecords(in session: WorkoutSession) -> [WorkoutSummary.Record] {
        var result: [WorkoutSummary.Record] = []
        for entry in session.orderedExercises {
            guard let exercise = entry.exercise else { continue }
            let newSets = entry.completedRecords(sessionID: session.id, fallbackDate: session.startedAt)
            let prior = exercise.completedSetRecords(excludingSession: session.id)
            for record in PersonalRecords.detect(newSets: newSets, history: prior, trackingType: entry.trackingType) {
                result.append(WorkoutSummary.Record(exerciseName: entry.exerciseName, trackingType: entry.trackingType, record: record))
            }
        }
        return result
    }
}
