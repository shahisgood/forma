import Foundation
import Observation
import HealthKit
import SwiftData
import FormaKit

/// Apple Health integration.
///
/// What Forma reads: body mass (to import weigh-ins from scales and other apps)
/// and step count (daily totals). What it can optionally write: weigh-ins
/// entered in Forma and completed strength workouts.
///
/// HealthKit deliberately does not tell apps whether *read* access was granted;
/// a denied read looks the same as "no data". Forma therefore never claims that
/// access was denied, and phrases empty results as "no data found".
@MainActor
@Observable
final class HealthService {
    enum Status: Equatable {
        /// HealthKit is not supported on this device.
        case unavailable
        /// The person has not connected Apple Health yet.
        case notConnected
        /// Authorization has been requested; individual permissions may still be off.
        case connected
    }

    struct ImportSummary: Equatable {
        var date: Date
        var added: Int
        var removed: Int
        var skipped: Int
    }

    private(set) var status: Status
    private(set) var stepsByDay: [DayKey: Int] = [:]
    /// True once a step query has completed (even if it returned nothing).
    private(set) var hasLoadedSteps = false
    private(set) var isRefreshingSteps = false
    private(set) var lastStepRefresh: Date?
    private(set) var isImporting = false
    private(set) var lastImport: ImportSummary?
    private(set) var lastError: String?

    @ObservationIgnored private let store: HKHealthStore?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let anchorKey = "forma.health.bodyMassAnchor"

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    init(settings: AppSettings) {
        self.settings = settings
        if Self.isAvailable {
            store = HKHealthStore()
            status = settings.values.health.connected ? .connected : .notConnected
        } else {
            store = nil
            status = .unavailable
        }
    }

    private var preferences: HealthPreferences { settings.values.health }

    private var bodyMassType: HKQuantityType { HKQuantityType(.bodyMass) }
    private var stepType: HKQuantityType { HKQuantityType(.stepCount) }

    /// Only the types the current preferences actually use.
    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        if preferences.importWeight { types.insert(bodyMassType) }
        if preferences.readSteps { types.insert(stepType) }
        return types
    }

    private var shareTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>()
        if preferences.saveWeight { types.insert(bodyMassType) }
        if preferences.saveWorkouts { types.insert(HKObjectType.workoutType()) }
        return types
    }

    // MARK: Authorization

    /// Shows the Health permission sheet for the types currently enabled.
    /// HealthKit only prompts for types that have not been asked about before.
    @discardableResult
    func connect() async -> Bool {
        guard let store else { return false }
        let read = readTypes
        let share = shareTypes
        guard !read.isEmpty || !share.isEmpty else {
            settings.update { $0.health.connected = true }
            status = .connected
            return true
        }
        do {
            try await store.requestAuthorization(toShare: share, read: read)
            settings.update { $0.health.connected = true }
            status = .connected
            lastError = nil
            return true
        } catch {
            lastError = "Apple Health couldn't be connected. \(error.localizedDescription)"
            return false
        }
    }

    /// Whether enabling the current preferences would show a new permission sheet.
    func needsAuthorizationRequest() async -> Bool {
        guard let store, status == .connected else { return false }
        let read = readTypes
        let share = shareTypes
        guard !read.isEmpty || !share.isEmpty else { return false }
        let requestStatus = try? await store.statusForAuthorizationRequest(toShare: share, read: read)
        return requestStatus == .shouldRequest
    }

    /// Stops using Health data in Forma. Permissions themselves can only be
    /// revoked by the person in the Health app.
    func disconnect() {
        settings.update { $0.health.connected = false }
        status = Self.isAvailable ? .notConnected : .unavailable
        stepsByDay = [:]
        hasLoadedSteps = false
    }

    /// Whether Forma may write the given type (reflects the share permission the person chose).
    func canWrite(_ type: HKObjectType) -> Bool {
        guard let store else { return false }
        return store.authorizationStatus(for: type) == .sharingAuthorized
    }

    // MARK: Steps

    /// Loads daily step totals. HealthKit's cumulative statistics merge
    /// overlapping samples from iPhone and Apple Watch, so steps are not
    /// double counted.
    func refreshSteps(daysBack: Int = 400, force: Bool = false) async {
        guard let store, status == .connected, preferences.readSteps else { return }
        if !force, let last = lastStepRefresh, Date().timeIntervalSince(last) < 30 { return }
        guard !isRefreshingSteps else { return }
        isRefreshingSteps = true
        defer { isRefreshingSteps = false }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(daysBack - 1), to: todayStart) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: stepType, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: todayStart,
            intervalComponents: DateComponents(day: 1)
        )
        do {
            let collection = try await descriptor.result(for: store)
            var result: [DayKey: Int] = [:]
            for statistics in collection.statistics() {
                guard let sum = statistics.sumQuantity()?.doubleValue(for: .count()) else { continue }
                let steps = Int(sum.rounded())
                if steps > 0 { result[DayKey(statistics.startDate, calendar: calendar)] = steps }
            }
            stepsByDay = result
            hasLoadedSteps = true
            lastStepRefresh = Date()
        } catch {
            hasLoadedSteps = true
            lastError = "Steps couldn't be read from Apple Health."
        }
    }

    // MARK: Body mass import

    /// Imports new body-mass samples recorded by other apps and devices.
    ///
    /// Uses an anchored query, so each run only receives changes since the last
    /// one, including deletions. Samples Forma wrote itself and samples already
    /// imported are skipped (see `HealthImportDeduplicator`). Imported entries
    /// that were deleted in Health are removed locally as well; Forma never
    /// deletes or edits other apps' data in Health.
    func importWeights(into context: ModelContext) async {
        guard let store, status == .connected, preferences.importWeight, !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: bodyMassType)],
            anchor: loadAnchor()
        )
        do {
            let result = try await descriptor.result(for: store)
            let incoming = result.addedSamples.map { sample in
                IncomingWeightSample(
                    uuid: sample.uuid.uuidString,
                    date: sample.startDate,
                    kilograms: sample.quantity.doubleValue(for: .gramUnit(with: .kilo)),
                    sourceBundleID: sample.sourceRevision.source.bundleIdentifier,
                    sourceName: sample.sourceRevision.source.name,
                    externalID: sample.metadata?[HKMetadataKeyExternalUUID] as? String
                )
            }

            let entries = try context.fetch(FetchDescriptor<WeightEntry>())
            let plan = HealthImportDeduplicator.plan(
                incoming: incoming,
                appBundleID: Bundle.main.bundleIdentifier ?? "",
                importedSampleUUIDs: Set(entries.compactMap(\.healthSampleUUID)),
                localEntryIDs: Set(entries.map { $0.id.uuidString }),
                writtenSampleUUIDs: Set(entries.compactMap(\.writtenHealthSampleUUID))
            )

            for sample in plan.toInsert {
                let entry = WeightEntry(kilograms: sample.kilograms, measuredAt: sample.date, source: .appleHealth)
                entry.healthSampleUUID = sample.uuid
                entry.healthSourceName = sample.sourceName
                context.insert(entry)
            }

            let deleted = Set(result.deletedObjects.map { $0.uuid.uuidString })
            var removed = 0
            if !deleted.isEmpty {
                for entry in entries where entry.healthSampleUUID.map(deleted.contains) == true {
                    context.delete(entry)
                    removed += 1
                }
            }

            try context.save()
            saveAnchor(result.newAnchor)
            lastImport = ImportSummary(
                date: Date(),
                added: plan.toInsert.count,
                removed: removed,
                skipped: plan.skippedOwn + plan.skippedExisting + plan.skippedInvalid
            )
            lastError = nil
        } catch {
            lastError = "Weights couldn't be imported from Apple Health."
        }
    }

    /// Deletes local copies of imported weights and resets the import position.
    func removeImportedWeights(from context: ModelContext) {
        let imported = (try? context.fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate<WeightEntry> { $0.healthSampleUUID != nil }))) ?? []
        for entry in imported { context.delete(entry) }
        try? context.save()
        resetImportState()
    }

    /// Forgets the import position so the next import starts from scratch.
    func resetImportState() {
        UserDefaults.standard.removeObject(forKey: anchorKey)
        lastImport = nil
    }

    private func loadAnchor() -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: anchorKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: anchorKey)
        }
    }

    // MARK: Writing

    /// Writes (or rewrites, after an edit) a manually entered weight to Health.
    func syncWeight(_ entry: WeightEntry) async {
        guard let store, status == .connected, preferences.saveWeight, !entry.isImported else { return }
        guard canWrite(bodyMassType) else { return }
        await deleteWrittenWeight(entry)
        let sample = HKQuantitySample(
            type: bodyMassType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: entry.kilograms),
            start: entry.measuredAt,
            end: entry.measuredAt,
            metadata: [
                HKMetadataKeyExternalUUID: entry.id.uuidString,
                HKMetadataKeyWasUserEntered: true
            ]
        )
        do {
            try await store.save(sample)
            entry.writtenHealthSampleUUID = sample.uuid.uuidString
        } catch {
            lastError = "The weight couldn't be saved to Apple Health."
        }
    }

    /// Removes the sample Forma wrote for this entry. Only Forma's own samples can match.
    func deleteWrittenWeight(_ entry: WeightEntry) async {
        guard let store, entry.writtenHealthSampleUUID != nil else { return }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [entry.id.uuidString]),
            HKQuery.predicateForObjects(from: HKSource.default())
        ])
        _ = try? await store.deleteObjects(of: bodyMassType, predicate: predicate)
        entry.writtenHealthSampleUUID = nil
    }

    /// Saves a finished strength session to Health as a workout.
    func syncWorkout(_ session: WorkoutSession) async {
        guard let store, status == .connected, preferences.saveWorkouts, let end = session.endedAt else { return }
        guard canWrite(HKObjectType.workoutType()) else { return }
        await deleteWrittenWorkout(session)
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: session.startedAt)
            try await builder.endCollection(at: end)
            try await builder.addMetadata([HKMetadataKeyExternalUUID: session.id.uuidString])
            if let workout = try await builder.finishWorkout() {
                session.healthWorkoutUUID = workout.uuid.uuidString
            }
        } catch {
            lastError = "The workout couldn't be saved to Apple Health."
        }
    }

    func deleteWrittenWorkout(_ session: WorkoutSession) async {
        guard let store, session.healthWorkoutUUID != nil else { return }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [session.id.uuidString]),
            HKQuery.predicateForObjects(from: HKSource.default())
        ])
        _ = try? await store.deleteObjects(of: HKObjectType.workoutType(), predicate: predicate)
        session.healthWorkoutUUID = nil
    }
}
