import Foundation

/// Body-weight and load units. All masses are *stored* in kilograms; the unit
/// only affects input and display, so switching units never rewrites history.
public enum WeightUnit: String, Codable, CaseIterable, Sendable, Identifiable {
    case kilograms = "kg"
    case pounds = "lb"

    public var id: String { rawValue }

    public static let poundsPerKilogram = 2.204_622_621_8

    public var symbol: String { rawValue }

    public var name: String {
        switch self {
        case .kilograms: return "Kilograms"
        case .pounds: return "Pounds"
        }
    }

    /// Converts a stored kilogram value into this unit.
    public func fromKilograms(_ kg: Double) -> Double {
        switch self {
        case .kilograms: return kg
        case .pounds: return kg * Self.poundsPerKilogram
        }
    }

    /// Converts a value expressed in this unit into kilograms for storage.
    public func toKilograms(_ value: Double) -> Double {
        switch self {
        case .kilograms: return value
        case .pounds: return value / Self.poundsPerKilogram
        }
    }

    /// Default increment for load steppers during workouts.
    public var loadIncrement: Double {
        switch self {
        case .kilograms: return 2.5
        case .pounds: return 5
        }
    }

    /// Smallest y-axis span used for body-weight charts so that ordinary daily
    /// fluctuation is not stretched to fill the whole plot.
    public var minimumBodyWeightChartSpan: Double {
        switch self {
        case .kilograms: return 3
        case .pounds: return 6
        }
    }

    /// Change per week below which a weight trend is described as "stable".
    public var stableRatePerWeek: Double {
        switch self {
        case .kilograms: return 0.1
        case .pounds: return 0.2
        }
    }

    /// Default unit for a locale: pounds for the US, Liberia and Myanmar; kilograms elsewhere.
    public static func preferred(for locale: Locale) -> WeightUnit {
        switch locale.region?.identifier {
        case "US", "LR", "MM": return .pounds
        default: return .kilograms
        }
    }
}

public enum Rounding {
    /// Rounds to a number of fraction digits without floating-point drift in the result string.
    public static func round(_ value: Double, fractionDigits: Int) -> Double {
        let factor = pow(10, Double(fractionDigits))
        return (value * factor).rounded() / factor
    }

    /// Rounds to the nearest multiple of `step` (e.g. 2.5 kg plates).
    public static func round(_ value: Double, toNearest step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }
}

/// Serving units understood by the nutrition logger. Mass and volume units can
/// be converted between each other within their family.
public enum ServingUnit: String, Codable, CaseIterable, Sendable, Identifiable {
    case serving
    case gram = "g"
    case ounce = "oz"
    case milliliter = "ml"
    case fluidOunce = "fl oz"
    case cup
    case tablespoon = "tbsp"
    case teaspoon = "tsp"
    case piece
    case slice

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .serving: return "serving"
        case .gram: return "g"
        case .ounce: return "oz"
        case .milliliter: return "ml"
        case .fluidOunce: return "fl oz"
        case .cup: return "cup"
        case .tablespoon: return "tbsp"
        case .teaspoon: return "tsp"
        case .piece: return "piece"
        case .slice: return "slice"
        }
    }

    public enum Family: Sendable { case mass, volume, count }

    public var family: Family {
        switch self {
        case .gram, .ounce: return .mass
        case .milliliter, .fluidOunce, .cup, .tablespoon, .teaspoon: return .volume
        case .serving, .piece, .slice: return .count
        }
    }

    /// Size of one unit in the family's base unit (grams or millilitres).
    var baseFactor: Double? {
        switch self {
        case .gram: return 1
        case .ounce: return 28.349_523_125
        case .milliliter: return 1
        case .fluidOunce: return 29.573_529_562_5
        case .cup: return 240
        case .tablespoon: return 14.786_764_781_25
        case .teaspoon: return 4.928_921_593_75
        case .serving, .piece, .slice: return nil
        }
    }

    /// Converts an amount in this unit to `other`, if both belong to the same family.
    public func convert(_ amount: Double, to other: ServingUnit) -> Double? {
        if self == other { return amount }
        guard family == other.family, let a = baseFactor, let b = other.baseFactor else { return nil }
        return amount * a / b
    }

    /// Units a logged amount may be entered in for a food defined in this unit.
    public var compatibleUnits: [ServingUnit] {
        switch family {
        case .mass: return [.gram, .ounce]
        case .volume: return [.milliliter, .fluidOunce, .cup, .tablespoon, .teaspoon]
        case .count: return [self]
        }
    }
}
