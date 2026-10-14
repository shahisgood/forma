import Foundation

/// How an exercise is measured. Determines which fields a set shows.
public enum ExerciseTrackingType: String, Codable, CaseIterable, Sendable, Identifiable {
    case weightReps
    case bodyweightReps
    case assistedReps
    case duration
    case distanceDuration

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .weightReps: return "Weight × reps"
        case .bodyweightReps: return "Bodyweight reps"
        case .assistedReps: return "Assisted reps"
        case .duration: return "Time"
        case .distanceDuration: return "Distance & time"
        }
    }

    public var usesWeight: Bool { self == .weightReps || self == .assistedReps || self == .bodyweightReps }
    public var usesReps: Bool { self == .weightReps || self == .bodyweightReps || self == .assistedReps }
    public var usesDuration: Bool { self == .duration || self == .distanceDuration }
    public var usesDistance: Bool { self == .distanceDuration }
    /// Whether the weight column is required (bodyweight exercises treat it as optional added load).
    public var weightIsPrimary: Bool { self == .weightReps }
}

public enum ExerciseCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case chest, back, legs, shoulders, arms, core, fullBody, cardio

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .legs: return "Legs"
        case .shoulders: return "Shoulders"
        case .arms: return "Arms"
        case .core: return "Core"
        case .fullBody: return "Full body"
        case .cardio: return "Cardio"
        }
    }
}

public enum Equipment: String, Codable, CaseIterable, Sendable, Identifiable {
    case barbell, dumbbell, machine, cable, bodyweight, kettlebell, band, other

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .barbell: return "Barbell"
        case .dumbbell: return "Dumbbell"
        case .machine: return "Machine"
        case .cable: return "Cable"
        case .bodyweight: return "Bodyweight"
        case .kettlebell: return "Kettlebell"
        case .band: return "Band"
        case .other: return "Other"
        }
    }
}

public enum SetKind: String, Codable, CaseIterable, Sendable {
    case warmup
    case working
}

/// A completed set, flattened for analysis.
public struct SetRecord: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var sessionID: UUID
    public var date: Date
    public var kind: SetKind
    public var weightKg: Double?
    public var reps: Int?
    public var durationSeconds: Double?
    public var distanceMeters: Double?

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        date: Date,
        kind: SetKind = .working,
        weightKg: Double? = nil,
        reps: Int? = nil,
        durationSeconds: Double? = nil,
        distanceMeters: Double? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.date = date
        self.kind = kind
        self.weightKg = weightKg
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
    }

    public var isWorking: Bool { kind == .working }
}

/// Estimated one-rep max.
///
/// Uses the Epley formula, `weight × (1 + reps / 30)`. Estimates become
/// unreliable at high rep counts, so sets above 12 reps produce no estimate.
public enum OneRepMax {
    public static let maximumReps = 12

    public static func epley(weightKg: Double, reps: Int) -> Double? {
        guard weightKg > 0, reps >= 1, reps <= maximumReps else { return nil }
        if reps == 1 { return weightKg }
        return weightKg * (1 + Double(reps) / 30)
    }
}

/// Kinds of personal record the app recognises.
public enum PersonalRecordKind: String, Codable, Sendable, Hashable {
    case estimatedOneRepMax
    case heaviestWeight
    case repsAtWeight
    case mostReps
    case longestDuration
    case longestDistance

    public var title: String {
        switch self {
        case .estimatedOneRepMax: return "Estimated 1RM"
        case .heaviestWeight: return "Heaviest weight"
        case .repsAtWeight: return "Most reps at this weight"
        case .mostReps: return "Most reps"
        case .longestDuration: return "Longest time"
        case .longestDistance: return "Longest distance"
        }
    }
}

public struct PersonalRecord: Hashable, Sendable {
    public var kind: PersonalRecordKind
    public var setID: UUID
    /// The value that set the record (kg, reps, seconds or metres depending on kind).
    public var value: Double
    /// The previous best, if there was one.
    public var previous: Double?
}

public enum PersonalRecords {
    /// Weights are compared in 0.25 kg buckets so that unit-conversion rounding
    /// (e.g. 100 kg vs 220.5 lb) does not create spurious "new weight" records.
    static func bucket(_ kg: Double) -> Double { Rounding.round(kg, toNearest: 0.25) }

    /// Records set by `newSets` relative to all `history` (which must exclude `newSets`).
    ///
    /// Only working sets count. When the history is empty, nothing is reported —
    /// a first session is a baseline, not a record.
    public static func detect(
        newSets: [SetRecord],
        history: [SetRecord],
        trackingType: ExerciseTrackingType
    ) -> [PersonalRecord] {
        let prior = history.filter(\.isWorking)
        let candidates = newSets.filter(\.isWorking)
        guard !prior.isEmpty, !candidates.isEmpty else { return [] }
        var records: [PersonalRecord] = []

        switch trackingType {
        case .weightReps:
            let prior1RM = prior.compactMap { s in s.weightKg.flatMap { w in s.reps.flatMap { OneRepMax.epley(weightKg: w, reps: $0) } } }.max()
            let best1RM = candidates.compactMap { s -> (SetRecord, Double)? in
                guard let w = s.weightKg, let r = s.reps, let e = OneRepMax.epley(weightKg: w, reps: r) else { return nil }
                return (s, e)
            }.max { $0.1 < $1.1 }
            if let best = best1RM, best.1 > (prior1RM ?? 0) + 0.01 {
                records.append(PersonalRecord(kind: .estimatedOneRepMax, setID: best.0.id, value: best.1, previous: prior1RM))
            }

            let priorHeaviest = prior.compactMap { ($0.reps ?? 0) > 0 ? $0.weightKg : nil }.max()
            if let heaviest = candidates.filter({ ($0.reps ?? 0) > 0 }).max(by: { ($0.weightKg ?? 0) < ($1.weightKg ?? 0) }),
               let w = heaviest.weightKg, bucket(w) > bucket(priorHeaviest ?? 0) {
                records.append(PersonalRecord(kind: .heaviestWeight, setID: heaviest.id, value: w, previous: priorHeaviest))
            }

            // More reps than ever at a given weight (compared against sets at the same or heavier weight).
            var seenWeights = Set<Double>()
            for set in candidates.sorted(by: { ($0.reps ?? 0) > ($1.reps ?? 0) }) {
                guard let w = set.weightKg, let reps = set.reps, w > 0 else { continue }
                let b = bucket(w)
                guard !seenWeights.contains(b) else { continue }
                let priorAtOrAbove = prior.filter { bucket($0.weightKg ?? 0) >= b }.compactMap(\.reps).max()
                // Only meaningful if the weight has been lifted before.
                guard let previousBest = priorAtOrAbove else { continue }
                if reps > previousBest {
                    seenWeights.insert(b)
                    records.append(PersonalRecord(kind: .repsAtWeight, setID: set.id, value: Double(reps), previous: Double(previousBest)))
                }
            }

        case .bodyweightReps, .assistedReps:
            let priorReps = prior.compactMap(\.reps).max() ?? 0
            if let best = candidates.max(by: { ($0.reps ?? 0) < ($1.reps ?? 0) }), let reps = best.reps, reps > priorReps {
                records.append(PersonalRecord(kind: .mostReps, setID: best.id, value: Double(reps), previous: Double(priorReps)))
            }

        case .duration:
            let priorBest = prior.compactMap(\.durationSeconds).max() ?? 0
            if let best = candidates.max(by: { ($0.durationSeconds ?? 0) < ($1.durationSeconds ?? 0) }),
               let d = best.durationSeconds, d > priorBest {
                records.append(PersonalRecord(kind: .longestDuration, setID: best.id, value: d, previous: priorBest))
            }

        case .distanceDuration:
            let priorBest = prior.compactMap(\.distanceMeters).max() ?? 0
            if let best = candidates.max(by: { ($0.distanceMeters ?? 0) < ($1.distanceMeters ?? 0) }),
               let d = best.distanceMeters, d > priorBest {
                records.append(PersonalRecord(kind: .longestDistance, setID: best.id, value: d, previous: priorBest))
            }
        }
        return records
    }
}

/// Per-session summary of one exercise, used for progression charts.
public struct ExerciseSessionSummary: Hashable, Sendable, Identifiable {
    public var id: UUID { sessionID }
    public var sessionID: UUID
    public var date: Date
    public var workingSets: Int
    /// Best Epley estimate among working sets (weighted exercises only).
    public var bestEstimated1RM: Double?
    /// Heaviest working-set weight.
    public var topWeight: Double?
    /// Reps performed with the top weight.
    public var topWeightReps: Int?
    /// Sum of weight × reps over working sets. Only comparable within one exercise.
    public var volume: Double?
    public var totalReps: Int
    public var bestReps: Int?
    public var bestDuration: Double?
    public var bestDistance: Double?
}

public enum ExerciseProgression {
    public static func summaries(_ sets: [SetRecord]) -> [ExerciseSessionSummary] {
        let grouped = Dictionary(grouping: sets.filter(\.isWorking), by: \.sessionID)
        return grouped.compactMap { sessionID, sets -> ExerciseSessionSummary? in
            guard let date = sets.map(\.date).min() else { return nil }
            let e1rm = sets.compactMap { s in s.weightKg.flatMap { w in s.reps.flatMap { OneRepMax.epley(weightKg: w, reps: $0) } } }.max()
            let weighted = sets.filter { ($0.weightKg ?? 0) > 0 && ($0.reps ?? 0) > 0 }
            let top = weighted.max { a, b in
                (a.weightKg ?? 0, a.reps ?? 0) < (b.weightKg ?? 0, b.reps ?? 0)
            }
            let volume = weighted.reduce(0.0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) }
            return ExerciseSessionSummary(
                sessionID: sessionID,
                date: date,
                workingSets: sets.count,
                bestEstimated1RM: e1rm,
                topWeight: top?.weightKg,
                topWeightReps: top?.reps,
                volume: weighted.isEmpty ? nil : volume,
                totalReps: sets.compactMap(\.reps).reduce(0, +),
                bestReps: sets.compactMap(\.reps).max(),
                bestDuration: sets.compactMap(\.durationSeconds).max(),
                bestDistance: sets.compactMap(\.distanceMeters).max()
            )
        }
        .sorted { $0.date < $1.date }
    }

    public struct RepMax: Hashable, Sendable {
        public var reps: Int
        public var weightKg: Double
        public var date: Date
    }

    /// Heaviest weight lifted for *at least* N reps, for N in 1...maxReps.
    /// Only rep counts that have a qualifying set are returned.
    public static func repMaxTable(_ sets: [SetRecord], maxReps: Int = 12) -> [RepMax] {
        let working = sets.filter { $0.isWorking && ($0.weightKg ?? 0) > 0 && ($0.reps ?? 0) > 0 }
        var rows: [RepMax] = []
        for n in 1...max(1, maxReps) {
            let qualifying = working.filter { ($0.reps ?? 0) >= n }
            if let best = qualifying.max(by: { ($0.weightKg ?? 0, $1.date) < ($1.weightKg ?? 0, $0.date) }),
               let w = best.weightKg {
                rows.append(RepMax(reps: n, weightKg: w, date: best.date))
            }
        }
        return rows
    }

    public struct RepsAtWeight: Hashable, Sendable {
        public var weightKg: Double
        public var reps: Int
        public var date: Date
    }

    /// Best reps achieved at each distinct weight (bucketed to 0.25 kg), heaviest first.
    public static func bestRepsByWeight(_ sets: [SetRecord]) -> [RepsAtWeight] {
        var best: [Double: RepsAtWeight] = [:]
        for s in sets where s.isWorking {
            guard let w = s.weightKg, w > 0, let r = s.reps, r > 0 else { continue }
            let b = PersonalRecords.bucket(w)
            if let existing = best[b], existing.reps >= r { continue }
            best[b] = RepsAtWeight(weightKg: b, reps: r, date: s.date)
        }
        return best.values.sorted { $0.weightKg > $1.weightKg }
    }
}

/// Prefilled values offered for a new set. These are suggestions only: a set is
/// never marked complete until the person confirms it.
public struct SetSuggestion: Equatable, Sendable {
    public var weightKg: Double?
    public var reps: Int?
    public var durationSeconds: Double?
    public var distanceMeters: Double?

    public init(weightKg: Double? = nil, reps: Int? = nil, durationSeconds: Double? = nil, distanceMeters: Double? = nil) {
        self.weightKg = weightKg
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
    }

    public var isEmpty: Bool { weightKg == nil && reps == nil && durationSeconds == nil && distanceMeters == nil }

    /// Suggests values for the set at `index` (0-based, counted within `kind`),
    /// based on the most recent session's sets of the same kind, then falling
    /// back to that session's last working set, then to the template's rep target.
    public static func make(
        index: Int,
        kind: SetKind,
        previousSets: [SetRecord],
        templateRepLow: Int?
    ) -> SetSuggestion {
        let sameKind = previousSets.filter { $0.kind == kind }
        let source: SetRecord?
        if index < sameKind.count {
            source = sameKind[index]
        } else {
            source = sameKind.last ?? (kind == .working ? previousSets.last : nil)
        }
        if let source {
            return SetSuggestion(
                weightKg: source.weightKg,
                reps: source.reps,
                durationSeconds: source.durationSeconds,
                distanceMeters: source.distanceMeters
            )
        }
        if kind == .working, let low = templateRepLow {
            return SetSuggestion(reps: low)
        }
        return SetSuggestion()
    }
}

/// Formats a short "80 kg × 8" style description of a set.
public enum SetDescription {
    public static func short(
        weightKg: Double?,
        reps: Int?,
        durationSeconds: Double?,
        distanceMeters: Double?,
        trackingType: ExerciseTrackingType,
        unit: WeightUnit
    ) -> String {
        switch trackingType {
        case .weightReps:
            let w = weightKg.map { formatWeight(unit.fromKilograms($0)) + " " + unit.symbol } ?? "—"
            let r = reps.map(String.init) ?? "—"
            return "\(w) × \(r)"
        case .bodyweightReps:
            let r = reps.map { "\($0) reps" } ?? "—"
            if let w = weightKg, w > 0 { return "+\(formatWeight(unit.fromKilograms(w))) \(unit.symbol) × \(reps.map(String.init) ?? "—")" }
            return r
        case .assistedReps:
            let r = reps.map(String.init) ?? "—"
            if let w = weightKg, w > 0 { return "−\(formatWeight(unit.fromKilograms(w))) \(unit.symbol) × \(r)" }
            return "\(r) reps"
        case .duration:
            return durationSeconds.map(formatDuration) ?? "—"
        case .distanceDuration:
            let d = distanceMeters.map { formatDistance($0) } ?? "—"
            if let t = durationSeconds { return "\(d) in \(formatDuration(t))" }
            return d
        }
    }

    public static func formatWeight(_ value: Double) -> String {
        let rounded = Rounding.round(value, fractionDigits: 2)
        if rounded == rounded.rounded() { return String(format: "%.0f", rounded) }
        if (rounded * 10) == (rounded * 10).rounded() { return String(format: "%.1f", rounded) }
        return String(format: "%.2f", rounded)
    }

    public static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    public static func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 { return String(format: "%.2f km", meters / 1000) }
        return String(format: "%.0f m", meters)
    }
}
