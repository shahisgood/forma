import SwiftUI
import FormaKit

enum AppTab: Hashable {
    case today, training, nutrition, progress
}

/// App-wide sheets that can be opened from several screens (quick actions,
/// cards, deep links), so they are presented from the root.
enum AppSheet: Identifiable, Equatable {
    case logWeight
    case logFood(day: DayKey, meal: Meal?)
    case settings
    case weeklyReview(weekStart: DayKey)
    case manualSteps(day: DayKey)

    var id: String {
        switch self {
        case .logWeight: return "logWeight"
        case .logFood(let day, let meal): return "logFood-\(day.string)-\(meal?.rawValue ?? "")"
        case .settings: return "settings"
        case .weeklyReview(let week): return "review-\(week.string)"
        case .manualSteps(let day): return "steps-\(day.string)"
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .today
    var sheet: AppSheet?

    func show(_ sheet: AppSheet) {
        self.sheet = sheet
    }
}
