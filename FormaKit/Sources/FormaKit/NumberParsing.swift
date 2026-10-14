import Foundation

/// Forgiving number parsing for quick-entry fields.
///
/// Accepts either `.` or `,` as the decimal separator regardless of locale, so
/// "81,4" and "81.4" both work, and ignores surrounding whitespace. Grouping
/// separators are only accepted when they are unambiguous ("2,500" in a
/// dot-decimal locale).
public enum NumberParsing {
    public static func decimal(from text: String, locale: Locale = .current) -> Double? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "\u{00A0}", with: "")
        s = s.replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty else { return nil }

        let decimalSeparator = locale.decimalSeparator ?? "."
        let hasComma = s.contains(",")
        let hasDot = s.contains(".")

        if hasComma && hasDot {
            // Both present: the last one is the decimal separator.
            let lastComma = s.lastIndex(of: ",")!
            let lastDot = s.lastIndex(of: ".")!
            if lastComma > lastDot {
                s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        } else if hasComma {
            let commaCount = s.filter { $0 == "," }.count
            let afterComma = s.split(separator: ",", omittingEmptySubsequences: false).last ?? ""
            if decimalSeparator == "." && commaCount >= 1 && afterComma.count == 3 && !s.hasPrefix(",") && !s.hasPrefix("0") {
                // "2,500" in a dot-decimal locale is a thousands grouping.
                s = s.replacingOccurrences(of: ",", with: "")
            } else if commaCount == 1 {
                s = s.replacingOccurrences(of: ",", with: ".")
            } else {
                return nil
            }
        } else if hasDot && decimalSeparator == "," {
            let dotCount = s.filter { $0 == "." }.count
            let afterDot = s.split(separator: ".", omittingEmptySubsequences: false).last ?? ""
            if afterDot.count == 3 && !s.hasPrefix(".") && !s.hasPrefix("0") && (dotCount > 1 || s.count > 4) {
                // "2.500" / "12.000" in a comma-decimal locale is a thousands grouping.
                s = s.replacingOccurrences(of: ".", with: "")
            }
        }

        guard s.filter({ $0 == "." }).count <= 1 else { return nil }
        guard let value = Double(s), value.isFinite else { return nil }
        return value
    }

    /// Parses a whole number. Returns `nil` for fractional input such as "7.5".
    public static func integer(from text: String, locale: Locale = .current) -> Int? {
        guard let value = decimal(from: text, locale: locale),
              value.rounded() == value,
              abs(value) < Double(Int.max / 2) else { return nil }
        return Int(value)
    }
}
