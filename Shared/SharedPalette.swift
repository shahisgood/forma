import SwiftUI
import UIKit

/// Colours used by both the app and the Live Activity, so the Lock Screen
/// matches the in-app workout screen.
enum SharedPalette {
    static let accent = Color(light: 0x2D62E0, dark: 0x6E95FF)
    static let training = Color(light: 0x2D62E0, dark: 0x6E95FF)
    /// Completion green (also the steps colour in the app).
    static let done = Color(light: 0x1E8C55, dark: 0x4CD38A)
}

extension Color {
    /// An appearance-adaptive colour from two hex values.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
