import Foundation
import Testing
@testable import FormaKit

@Suite("Strength calculations")
struct TrainingTests {
    let cal = makeCalendar()
    let s1 = UUID()
    let s2 = UUID()

    func set(_ session: UUID, day: Int, _ kg: Double?, _ reps: Int?, kind: SetKind = .working) -> SetRecord {
        SetRecord(sessionID: session, date: date(2026, 10, day, calendar: cal), kind: kind, weightKg: kg, reps: reps)
    }

    @Test func epleyEstimate() {
        #expect(OneRepMax.epley(weightKg: 100, reps: 1) == 100)
        #expect(abs(OneRepMax.epley(weightKg: 100, reps: 10)! - 133.333) < 0.001)
        #expect(OneRepMax.epley(weightKg: 100, reps: 15) == nil, "no estimate above 12 reps")
        #expect(OneRepMax.epley(weightKg: 0, reps: 5) == nil)
    }

    @Test func firstSessionIsBaselineNotRecord() {
        let records = PersonalRecords.detect(newSets: [set(s1, day: 1, 100, 5)], history: [], trackingType: .weightReps)
        #expect(records.isEmpty)
    }

    @Test func detectsEstimatedMaxAndHeaviestWeight() {
        let history = [set(s1, day: 1, 100, 5), set(s1, day: 1, 100, 5)]
        let new = [set(s2, day: 3, 105, 5)]
        let kinds = Set(PersonalRecords.detect(newSets: new, history: history, trackingType: .weightReps).map(\.kind))
        #expect(kinds.contains(.estimatedOneRepMax))
        #expect(kinds.contains(.heaviestWeight))
    }

    @Test func detectsRepsAtWeight() {
        let history = [set(s1, day: 1, 100, 5)]
        let new = [set(s2, day: 3, 100, 6)]
        let records = PersonalRecords.detect(newSets: new, history: history, trackingType: .weightReps)
        #expect(records.contains { $0.kind == .repsAtWeight && $0.value == 6 && $0.previous == 5 })
    }

    @Test func warmupsNeverCountAsRecords() {
        let history = [set(s1, day: 1, 100, 5)]
        let new = [set(s2, day: 3, 140, 5, kind: .warmup)]
        #expect(PersonalRecords.detect(newSets: new, history: history, trackingType: .weightReps).isEmpty)
    }

    @Test func unitRoundingDoesNotCreateFakeRecord() {
        // 225 lb converted back and forth is ~102.06 kg; 102.058 vs 102.06 must not be a "heavier" set.
        let history = [set(s1, day: 1, WeightUnit.pounds.toKilograms(225), 5)]
        let new = [set(s2, day: 3, Rounding.round(WeightUnit.pounds.toKilograms(225), fractionDigits: 2), 5)]
        let records = PersonalRecords.detect(newSets: new, history: history, trackingType: .weightReps)
        #expect(!records.contains { $0.kind == .heaviestWeight })
    }

    @Test func bodyweightRepRecords() {
        let history = [SetRecord(sessionID: s1, date: date(2026, 10, 1, calendar: cal), reps: 10)]
        let new = [SetRecord(sessionID: s2, date: date(2026, 10, 3, calendar: cal), reps: 12)]
        let records = PersonalRecords.detect(newSets: new, history: history, trackingType: .bodyweightReps)
        #expect(records.map(\.kind) == [.mostReps])
    }

    @Test func sessionSummariesComputeVolumeAndTopSet() {
        let sets = [
            set(s1, day: 1, 60, 10, kind: .warmup),
            set(s1, day: 1, 100, 5),
            set(s1, day: 1, 100, 4),
            set(s2, day: 3, 102.5, 5)
        ]
        let summaries = ExerciseProgression.summaries(sets)
        #expect(summaries.count == 2)
        #expect(summaries[0].volume == 900, "warm-ups are excluded from volume")
        #expect(summaries[0].topWeight == 100)
        #expect(summaries[0].topWeightReps == 5)
        #expect(summaries[0].workingSets == 2)
        #expect(summaries[1].sessionID == s2)
    }

    @Test func repMaxTableIsMonotonic() {
        let sets = [set(s1, day: 1, 100, 5), set(s1, day: 1, 110, 2), set(s2, day: 3, 90, 8)]
        let table = ExerciseProgression.repMaxTable(sets, maxReps: 8)
        #expect(table.first { $0.reps == 1 }?.weightKg == 110)
        #expect(table.first { $0.reps == 3 }?.weightKg == 100)
        #expect(table.first { $0.reps == 8 }?.weightKg == 90)
        let weights = table.map(\.weightKg)
        #expect(weights == weights.sorted(by: >))
    }

    @Test func suggestionsComeFromMatchingPreviousSet() {
        let previous = [
            set(s1, day: 1, 60, 8, kind: .warmup),
            set(s1, day: 1, 100, 5),
            set(s1, day: 1, 100, 4)
        ]
        #expect(SetSuggestion.make(index: 1, kind: .working, previousSets: previous, templateRepLow: 5) == SetSuggestion(weightKg: 100, reps: 4))
        #expect(SetSuggestion.make(index: 0, kind: .warmup, previousSets: previous, templateRepLow: 5) == SetSuggestion(weightKg: 60, reps: 8))
        // Beyond the previous session's sets: repeat the last one.
        #expect(SetSuggestion.make(index: 5, kind: .working, previousSets: previous, templateRepLow: 5) == SetSuggestion(weightKg: 100, reps: 4))
        // No history: fall back to the template's rep target only.
        #expect(SetSuggestion.make(index: 0, kind: .working, previousSets: [], templateRepLow: 8) == SetSuggestion(reps: 8))
    }

    @Test func setDescriptions() {
        #expect(SetDescription.short(weightKg: 100, reps: 5, durationSeconds: nil, distanceMeters: nil, trackingType: .weightReps, unit: .kilograms) == "100 kg × 5")
        #expect(SetDescription.short(weightKg: 100, reps: 5, durationSeconds: nil, distanceMeters: nil, trackingType: .weightReps, unit: .pounds) == "220.46 lb × 5")
        #expect(SetDescription.formatDuration(75) == "1:15")
        #expect(SetDescription.formatDuration(3725) == "1:02:05")
        #expect(SetDescription.formatWeight(82.5) == "82.5")
    }
}
