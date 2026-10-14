import SwiftUI
import FormaKit

/// Edits the body-weight goal. Goals are descriptive: they set chart lines and
/// wording, and never change nutrition targets on their own.
struct GoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @State private var direction: GoalDirection?
    @State private var targetText = ""
    @State private var lowerText = ""
    @State private var upperText = ""

    private var unit: WeightUnit { settings.unit }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Goal", selection: $direction) {
                        Text("No goal").tag(GoalDirection?.none)
                        ForEach(GoalDirection.allCases) { option in
                            Label(option.name, systemImage: option.symbol).tag(GoalDirection?.some(option))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                switch direction {
                case .lose, .gain:
                    Section {
                        weightField("Target weight (optional)", text: $targetText)
                    } footer: {
                        Text("Shown as a line on your weight chart.")
                    }
                case .maintain:
                    Section {
                        weightField("Lower bound", text: $lowerText)
                        weightField("Upper bound", text: $upperText)
                    } footer: {
                        if let message = rangeMessage {
                            Text(message).foregroundStyle(.orange)
                        } else {
                            Text("A range acknowledges normal day-to-day fluctuation. Shown as two lines on your weight chart.")
                        }
                    }
                case nil:
                    EmptyView()
                }

                Section {
                    Text("Your goal changes how progress is described. It doesn't change your calorie or protein targets — you set those yourself in Nutrition targets.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Weight Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(rangeMessage != nil)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func weightField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text(unit.symbol).foregroundStyle(.secondary)
        }
    }

    private var rangeMessage: String? {
        guard direction == .maintain else { return nil }
        let lo = NumberParsing.decimal(from: lowerText)
        let hi = NumberParsing.decimal(from: upperText)
        if let lo, let hi, lo >= hi { return "The lower bound needs to be below the upper bound." }
        return nil
    }

    private func load() {
        let goal = settings.values.goal
        direction = goal.direction
        targetText = goal.targetKg.map { Format.weightValue($0, unit: unit) } ?? ""
        lowerText = goal.rangeLowerKg.map { Format.weightValue($0, unit: unit) } ?? ""
        upperText = goal.rangeUpperKg.map { Format.weightValue($0, unit: unit) } ?? ""
    }

    private func save() {
        func kg(_ text: String) -> Double? {
            NumberParsing.decimal(from: text).map(unit.toKilograms)
        }
        var goal = BodyGoal(direction: direction)
        switch direction {
        case .lose, .gain:
            goal.targetKg = kg(targetText)
        case .maintain:
            goal.rangeLowerKg = kg(lowerText)
            goal.rangeUpperKg = kg(upperText)
        case nil:
            break
        }
        settings.update { $0.goal = goal }
        dismiss()
    }
}
