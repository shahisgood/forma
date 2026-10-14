import SwiftUI
import UIKit

/// Forma's visual language.
///
/// - Neutral system surfaces carry the layout; colour is reserved for meaning.
/// - Each metric owns one hue that is used everywhere it appears (cards, charts,
///   progress, icons) so people learn the mapping once.
/// - One accent for interactive elements.
enum Theme {
    enum Palette {
        static let accent = SharedPalette.accent

        static let weight = Color(light: 0x6B4FD8, dark: 0xA390FF)
        static let calories = Color(light: 0xDB6A1F, dark: 0xFF9B54)
        static let protein = Color(light: 0xC8386A, dark: 0xFF7099)
        static let carbs = Color(light: 0xB58300, dark: 0xF2C14E)
        static let fat = Color(light: 0x14839A, dark: 0x52C6DA)
        static let steps = SharedPalette.done
        static let training = SharedPalette.training
        static let routines = Color(light: 0x4A7A8C, dark: 0x8DC2D4)
        static let record = Color(light: 0xC28A00, dark: 0xFFC94A)

        static let background = Color(uiColor: .systemGroupedBackground)
        static let surface = Color(uiColor: .secondarySystemGroupedBackground)
        static let raised = Color(uiColor: .tertiarySystemGroupedBackground)
        static let separator = Color(uiColor: .separator)
        static let fill = Color(uiColor: .tertiarySystemFill)
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
        static let section: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 22
        static let inner: CGFloat = 14
        static let control: CGFloat = 12
        static let chip: CGFloat = 9
    }

    /// Minimum hit target for controls, larger than the HIG minimum for use mid-workout.
    static let largeTarget: CGFloat = 52
    static let target: CGFloat = 44
}

/// A tracked quantity with a consistent colour and symbol.
enum Metric: String, CaseIterable, Identifiable {
    case weight, calories, protein, carbs, fat, steps, training, routines

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .weight: return Theme.Palette.weight
        case .calories: return Theme.Palette.calories
        case .protein: return Theme.Palette.protein
        case .carbs: return Theme.Palette.carbs
        case .fat: return Theme.Palette.fat
        case .steps: return Theme.Palette.steps
        case .training: return Theme.Palette.training
        case .routines: return Theme.Palette.routines
        }
    }

    var symbol: String {
        switch self {
        case .weight: return "scalemass"
        case .calories: return "flame"
        case .protein: return "fork.knife"
        case .carbs: return "leaf"
        case .fat: return "drop"
        case .steps: return "figure.walk"
        case .training: return "dumbbell"
        case .routines: return "checklist"
        }
    }

    var title: String {
        switch self {
        case .weight: return "Weight"
        case .calories: return "Calories"
        case .protein: return "Protein"
        case .carbs: return "Carbs"
        case .fat: return "Fat"
        case .steps: return "Steps"
        case .training: return "Training"
        case .routines: return "Routines"
        }
    }
}

extension Font {
    /// Large numeric display used for headline values.
    static func metric(_ style: Font.TextStyle = .largeTitle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

extension View {
    /// Tabular, rounded digits for values that change in place.
    func numericStyle() -> some View {
        self.monospacedDigit().fontDesign(.rounded)
    }
}
