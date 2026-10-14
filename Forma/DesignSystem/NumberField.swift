import SwiftUI
import FormaKit

/// A text field bound to an optional number.
///
/// It keeps its own text while editing, so partial input like "81." isn't
/// reformatted under the cursor, and it only writes back when the typed value
/// actually changes. That matters for unit conversion: merely displaying a
/// kilogram value in pounds never rewrites the stored kilograms.
struct NumberField: View {
    let placeholder: String
    @Binding var value: Double?
    var allowsDecimal = true
    var fractionDigits = 2
    var alignment: TextAlignment = .center

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
            .multilineTextAlignment(alignment)
            .focused($focused)
            .onAppear { text = format(value) }
            .onChange(of: text) { _, newText in
                guard newText != format(value) else { return }
                let parsed = allowsDecimal ? NumberParsing.decimal(from: newText) : NumberParsing.integer(from: newText).map(Double.init)
                if newText.trimmingCharacters(in: .whitespaces).isEmpty {
                    if value != nil { value = nil }
                } else if let parsed, parsed >= 0, parsed != value {
                    value = parsed
                }
            }
            .onChange(of: value) { _, newValue in
                if !focused { text = format(newValue) }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { text = format(value) }
            }
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "" }
        if !allowsDecimal { return String(Int(value.rounded())) }
        return value.formatted(.number.precision(.fractionLength(0...fractionDigits)).grouping(.never))
    }
}

extension Binding where Value == Double? {
    /// Presents a stored kilogram value in the chosen unit.
    static func weight(_ kilograms: Binding<Double?>, unit: WeightUnit) -> Binding<Double?> {
        Binding(
            get: { kilograms.wrappedValue.map { (unit.fromKilograms($0) * 100).rounded() / 100 } },
            set: { kilograms.wrappedValue = $0.map(unit.toKilograms) }
        )
    }

    /// Presents an optional integer as an optional double.
    static func integer(_ source: Binding<Int?>) -> Binding<Double?> {
        Binding(
            get: { source.wrappedValue.map(Double.init) },
            set: { source.wrappedValue = $0.map { Int($0.rounded()) } }
        )
    }
}
