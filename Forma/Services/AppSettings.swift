import SwiftUI
import UIKit
import FormaKit

/// Observable store for user preferences, persisted as one JSON document in
/// `UserDefaults`. Targets with history (calories, protein, steps) live in
/// SwiftData as `TargetRecord`s instead, so changes are dated.
@MainActor
@Observable
final class AppSettings {
    private(set) var values: SettingsValues

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "forma.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey) {
            values = SettingsValues.decode(data)
        } else {
            var initial = SettingsValues()
            initial.weightUnit = WeightUnit.preferred(for: .current)
            values = initial
        }
    }

    func update(_ change: (inout SettingsValues) -> Void) {
        var next = values
        change(&next)
        guard next != values else { return }
        values = next
        defaults.set(next.encoded(), forKey: storageKey)
    }

    /// A binding into one setting, for use with standard controls.
    func binding<T>(_ keyPath: WritableKeyPath<SettingsValues, T>) -> Binding<T> {
        Binding(
            get: { self.values[keyPath: keyPath] },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    /// Clears every preference (used by "Delete all data").
    func reset() {
        defaults.removeObject(forKey: storageKey)
        var initial = SettingsValues()
        initial.weightUnit = WeightUnit.preferred(for: .current)
        values = initial
    }

    // Convenience accessors used throughout the UI.
    var unit: WeightUnit { values.weightUnit }

    var colorScheme: ColorScheme? {
        switch values.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Publishes the current calendar day and updates it at midnight, when the time
/// zone changes, and when the app returns to the foreground.
@MainActor
@Observable
final class DayClock {
    private(set) var today: DayKey = DayKey.today()

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [.NSCalendarDayChanged, .NSSystemTimeZoneDidChange, UIApplication.significantTimeChangeNotification]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    func refresh() {
        let now = DayKey.today()
        if now != today { today = now }
    }
}
