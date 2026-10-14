import SwiftUI
import UIKit

/// Shared animation vocabulary.
///
/// Interface motion is short and decelerating so the app feels immediate:
/// things arrive quickly and settle softly. Springs are used for anything the
/// user can interrupt (sheets, toggles, progress), because a spring picks up
/// from its current velocity instead of restarting. When Reduce Motion is on,
/// movement is replaced by a plain cross-fade or dropped entirely.
enum Motion {
    /// Presses and small state flips.
    static let quick = Animation.easeOut(duration: 0.16)
    /// Default for layout changes and content swaps.
    static let standard = Animation.spring(response: 0.32, dampingFraction: 0.9)
    /// Elements entering with a little more presence (rest timer, completion).
    static let emphasized = Animation.spring(response: 0.4, dampingFraction: 0.8)
    /// Progress bars and rings filling after a log.
    static let progress = Animation.spring(response: 0.7, dampingFraction: 0.92)
    /// Chart range changes.
    static let chart = Animation.easeInOut(duration: 0.28)

    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// Runs `body` inside an animation, or a short fade when Reduce Motion is on.
    static func perform(_ animation: Animation = standard, _ body: () -> Void) {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.15), body)
        } else {
            withAnimation(animation, body)
        }
    }
}

private struct MotionAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? .easeInOut(duration: 0.15) : animation, value: value)
    }
}

extension View {
    /// `.animation(_:value:)` that falls back to a gentle fade under Reduce Motion.
    func motion<V: Equatable>(_ animation: Animation = Motion.standard, value: V) -> some View {
        modifier(MotionAnimationModifier(animation: animation, value: value))
    }
}

extension AnyTransition {
    /// Content arriving: slight lift and scale from 96%, never from zero.
    static var lift: AnyTransition {
        if Motion.reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96)).combined(with: .offset(y: 6)),
            removal: .opacity.combined(with: .scale(scale: 0.98))
        )
    }
}

/// Imperative haptics for places where a view-bound `sensoryFeedback` is awkward
/// (controllers, async completions).
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func firm() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
