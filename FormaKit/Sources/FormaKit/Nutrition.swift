import Foundation

/// Energy and macronutrients. Carbohydrate and fat are optional because many
/// people only track calories and protein; `nil` means "not recorded", which is
/// different from zero.
public struct Nutrients: Hashable, Codable, Sendable {
    public var calories: Double
    public var protein: Double
    public var carbs: Double?
    public var fat: Double?

    public init(calories: Double = 0, protein: Double = 0, carbs: Double? = nil, fat: Double? = nil) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    public static let zero = Nutrients()

    public func scaled(by factor: Double) -> Nutrients {
        Nutrients(
            calories: calories * factor,
            protein: protein * factor,
            carbs: carbs.map { $0 * factor },
            fat: fat.map { $0 * factor }
        )
    }

    public static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients {
        Nutrients(
            calories: lhs.calories + rhs.calories,
            protein: lhs.protein + rhs.protein,
            carbs: addOptional(lhs.carbs, rhs.carbs),
            fat: addOptional(lhs.fat, rhs.fat)
        )
    }

    private static func addOptional(_ a: Double?, _ b: Double?) -> Double? {
        switch (a, b) {
        case (nil, nil): return nil
        default: return (a ?? 0) + (b ?? 0)
        }
    }

    /// Energy implied by the macros (4/4/9 kcal per gram), when all are present.
    public var macroCalories: Double? {
        guard let carbs, let fat else { return nil }
        return protein * 4 + carbs * 4 + fat * 9
    }

    public var isValid: Bool {
        calories.isFinite && calories >= 0 && protein.isFinite && protein >= 0
            && (carbs.map { $0.isFinite && $0 >= 0 } ?? true)
            && (fat.map { $0.isFinite && $0 >= 0 } ?? true)
    }
}

public enum Meal: String, Codable, CaseIterable, Sendable, Identifiable {
    case breakfast, lunch, dinner, snacks

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snacks: return "Snacks"
        }
    }

    public var symbol: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        case .snacks: return "takeoutbag.and.cup.and.straw"
        }
    }

    /// A sensible default meal for the time of day, used only to preselect the picker.
    public static func suggested(for date: Date, calendar: Calendar = .current) -> Meal {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snacks
        }
    }
}

/// Where a diary entry's nutrition values came from. Shown alongside entries so
/// estimates are never mistaken for measured values.
public enum NutritionSource: String, Codable, CaseIterable, Sendable {
    /// Logged from a food the person created.
    case myFood
    /// Expanded from a saved meal.
    case savedMeal
    /// Typed in directly as an estimate.
    case quickEstimate
    /// Copied from another day's entry.
    case copied
    /// From an external food database (not bundled; reserved for future integrations).
    case externalDatabase

    public var label: String {
        switch self {
        case .myFood: return "My food"
        case .savedMeal: return "Saved meal"
        case .quickEstimate: return "Quick estimate"
        case .copied: return "Copied"
        case .externalDatabase: return "Food database"
        }
    }
}

public enum ServingMath {
    /// Number of servings represented by `amount` of `unit`, for a food whose
    /// serving is `servingSize` × `servingUnit`. Returns `nil` if the units are
    /// incompatible.
    public static func servings(amount: Double, unit: ServingUnit, servingSize: Double, servingUnit: ServingUnit) -> Double? {
        guard amount.isFinite, amount >= 0 else { return nil }
        if unit == .serving { return amount }
        guard servingSize > 0, let converted = unit.convert(amount, to: servingUnit) else { return nil }
        return converted / servingSize
    }

    /// Inverse of `servings(...)`: the amount of `unit` equal to `servings`.
    public static func amount(servings: Double, unit: ServingUnit, servingSize: Double, servingUnit: ServingUnit) -> Double? {
        if unit == .serving { return servings }
        guard let perServing = servingUnit.convert(servingSize, to: unit) else { return nil }
        return servings * perServing
    }

    /// Units a food can be logged in: always "serving", plus the food's own unit family.
    public static func loggableUnits(for servingUnit: ServingUnit) -> [ServingUnit] {
        var units: [ServingUnit] = [.serving]
        for u in servingUnit.compatibleUnits where u != .serving && !units.contains(u) {
            units.append(u)
        }
        return units
    }
}

/// Daily nutrition targets. `nil` means the person has chosen not to set that target.
public struct NutritionTargets: Hashable, Codable, Sendable {
    public var calories: Double?
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?

    public init(calories: Double? = nil, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    public var isEmpty: Bool { calories == nil && protein == nil && carbs == nil && fat == nil }
}

public struct DayNutritionSummary: Equatable, Sendable {
    public var day: DayKey
    public var totals: Nutrients
    public var entryCount: Int
    public var targets: NutritionTargets

    public init(day: DayKey, totals: Nutrients, entryCount: Int, targets: NutritionTargets) {
        self.day = day
        self.totals = totals
        self.entryCount = entryCount
        self.targets = targets
    }

    public var hasEntries: Bool { entryCount > 0 }

    /// Remaining calories (negative when over). `nil` without a target.
    public var caloriesRemaining: Double? { targets.calories.map { $0 - totals.calories } }
    public var proteinRemaining: Double? { targets.protein.map { $0 - totals.protein } }

    public func progress(_ value: Double, target: Double?) -> Double? {
        guard let target, target > 0 else { return nil }
        return value / target
    }
}

public enum NutritionStats {
    /// Averages over days that have at least one entry. Days without entries
    /// are *not* treated as zero-calorie days.
    public static func averageOfLoggedDays(_ days: [DayNutritionSummary]) -> Nutrients? {
        let logged = days.filter(\.hasEntries)
        guard !logged.isEmpty else { return nil }
        let total = logged.reduce(Nutrients.zero) { $0 + $1.totals }
        return total.scaled(by: 1 / Double(logged.count))
    }

    /// Count of logged days on which protein reached its target in effect that day.
    public static func proteinTargetDays(_ days: [DayNutritionSummary]) -> (met: Int, withTarget: Int) {
        let eligible = days.filter { $0.hasEntries && $0.targets.protein != nil }
        let met = eligible.filter { $0.totals.protein >= ($0.targets.protein ?? .infinity) }.count
        return (met, eligible.count)
    }
}
