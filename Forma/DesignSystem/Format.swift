import Foundation
import FormaKit

/// Display formatting. Stored values are always in base units (kg, kcal, g,
/// seconds); these helpers convert for presentation only.
enum Format {
    static func weightValue(_ kg: Double, unit: WeightUnit, fractionDigits: Int = 1) -> String {
        unit.fromKilograms(kg).formatted(.number.precision(.fractionLength(0...fractionDigits)))
    }

    static func weight(_ kg: Double, unit: WeightUnit, fractionDigits: Int = 1) -> String {
        "\(weightValue(kg, unit: unit, fractionDigits: fractionDigits)) \(unit.symbol)"
    }

    /// Signed change, e.g. "+0.4 kg" / "−1.2 lb".
    static func weightChange(_ kg: Double, unit: WeightUnit) -> String {
        let value = unit.fromKilograms(kg)
        let rounded = (value * 10).rounded() / 10
        if rounded == 0 { return "0 \(unit.symbol)" }
        let sign = rounded > 0 ? "+" : "−"
        return "\(sign)\(abs(rounded).formatted(.number.precision(.fractionLength(1)))) \(unit.symbol)"
    }

    /// Load for set entry fields: up to two decimals, no trailing zeros.
    static func load(_ kg: Double, unit: WeightUnit) -> String {
        let value = (unit.fromKilograms(kg) * 100).rounded() / 100
        return value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    static func calories(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number)
    }

    static func grams(_ value: Double) -> String {
        value < 10 && value != value.rounded()
            ? value.formatted(.number.precision(.fractionLength(0...1)))
            : Int(value.rounded()).formatted(.number)
    }

    static func steps(_ value: Int) -> String {
        value.formatted(.number)
    }

    static func number(_ value: Double, maxFraction: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxFraction)))
    }

    static func servings(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// "1:05:12" or "42:07".
    static func elapsed(_ seconds: TimeInterval) -> String {
        SetDescription.formatDuration(max(0, seconds))
    }

    /// "52 min" / "1 h 12 min".
    static func durationWords(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    static func restClock(_ seconds: Int) -> String {
        String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }

    // MARK: Dates

    static func dayTitle(_ day: DayKey, today: DayKey) -> String {
        if day == today { return "Today" }
        if day == today.adding(days: -1) { return "Yesterday" }
        if day == today.adding(days: 1) { return "Tomorrow" }
        return day.middayDate().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    static func longDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func dateWithYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    static func weekRange(_ week: WeekInterval) -> String {
        let start = week.start.middayDate()
        let end = week.end.middayDate()
        if week.start.month == week.end.month {
            return "\(start.formatted(.dateTime.month(.abbreviated).day()))–\(end.formatted(.dateTime.day()))"
        }
        return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// "2 days ago", "Today".
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let today = DayKey(now)
        let day = DayKey(date)
        let diff = day.days(to: today)
        switch diff {
        case 0: return "Today"
        case 1: return "Yesterday"
        case 2...6: return "\(diff) days ago"
        default: return shortDate(date)
        }
    }

    static func clock(_ time: ClockTime) -> String {
        time.date(on: DayKey.today())?.formatted(date: .omitted, time: .shortened) ?? "\(time.hour):\(time.minute)"
    }
}
